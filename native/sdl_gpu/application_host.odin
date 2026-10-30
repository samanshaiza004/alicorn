package alicorn_sdl_gpu

import "base:runtime"
import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

NATIVE_DESCRIPTION_STABILIZATION_LIMIT :: 4

// Host presentation can be requested by app content, native chrome, DevTools,
// or the inspector. Keep this decision explicit so host-only wake paths can
// be verified without attributing them to application work.
native_frame_submission_requested :: proc(
	application, native_chrome, devtools_hud, inspector: bool,
) -> bool {
	return application || native_chrome || devtools_hud || inspector
}

Native_Description_Stabilization :: struct {
	passes: int,
	stable: bool,
}

// In-build application invalidations describe a newer state than the
// description that raised them. Rebuild a small bounded number of times before
// the host submits a GPU frame, so transient intermediate descriptions are not
// visibly presented. Event/button consumption remains owned by the runtime.
native_application_build_until_stable :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	metrics: ^Window_Metrics,
	timing: ^Native_Host_Timing,
	stop_on_hard_error := false,
) -> Native_Description_Stabilization {
	result := Native_Description_Stabilization{}
	for rt.invalidated && (!stop_on_hard_error || !rt.hard_error) && result.passes < NATIVE_DESCRIPTION_STABILIZATION_LIMIT {
		interaction_sequence := rt.interaction_consumption_sequence
		// Intent-based motion resolves targets from the same monotonic domain as
		// native presentation sampling. Inject it before every application
		// description so app code never needs its own motion clock.
		_ = alicorn.motion_clock_set_time(
			rt, alicorn.Motion_Time(i64(sdl3.GetTicksNS())), .Native_Monotonic,
		)
		build_start := time.now()
		_ = application.build(application.state, rt, metrics.logical_width, metrics.logical_height, metrics.display_scale)
		native_timing_accumulate(&timing.application_build_ns, &timing.application_build_max_ns, u64(time.duration_nanoseconds(time.since(build_start))))
		result.passes += 1
		if application.interaction_update_policy == .Correct_After_Interaction &&
		   rt.interaction_consumption_sequence != interaction_sequence && !rt.invalidated {
			alicorn.invalidate_root(rt, "corrective description after consumed interaction")
		}
	}
	result.stable = !rt.invalidated || (stop_on_hard_error && rt.hard_error)
	if result.passes > 1 { timing.application_stabilization_rebuilds += u64(result.passes-1) }
	if !result.stable { timing.application_stabilization_limit_hits += 1 }
	return result
}

// Native_Menu_Runtime is a host-owned bridge. Platform adapters keep HWND,
// NSWindow, HMENU, NSMenu and selectors outside the application API.
Native_Menu_Runtime :: struct {
	window:          ^sdl3.Window,
	application:     ^Application,
	runtime:         ^alicorn.Runtime,
	inspector:       ^Native_Inspector_Overlay,
	platform_data:   rawptr,
	// The window/client coordinate space includes this host-owned top chrome;
	// application logical coordinates begin immediately below it.
	content_inset_top: f32,
	chrome_appearance: Window_Chrome_Appearance,
	chrome_appearance_resolved: bool,
	chrome_redraw_pending: bool,
	host_waker: ^Native_Host_Event_Waker,
	pending_command: Application_Command_ID,
	has_pending:     bool,
}

native_menu_shortcut_key_equal :: proc(shortcut_key, key: rune) -> bool {
	if shortcut_key == 0 { return false }
	upper_key := key
	if upper_key >= 'a' && upper_key <= 'z' { upper_key -= ('a' - 'A') }
	upper_shortcut_key := shortcut_key
	if upper_shortcut_key >= 'a' && upper_shortcut_key <= 'z' { upper_shortcut_key -= ('a' - 'A') }
	return upper_key == upper_shortcut_key
}

native_menu_shortcut_modifiers_match :: proc(
	expected: Application_Menu_Modifiers,
	actual: sdl3.Keymod,
) -> bool {
	primary_down := native_text_primary_modifier(actual)
	shift_down := native_text_modifier(actual, sdl3.KMOD_SHIFT)
	alt_down := native_text_modifier(actual, sdl3.KMOD_ALT)
	super_down := native_text_modifier(actual, sdl3.KMOD_GUI)
	when ODIN_OS == .Darwin {
		super_down = native_text_modifier(actual, sdl3.KMOD_CTRL)
	}
	return (Application_Menu_Modifier.Primary in expected) == primary_down &&
		(Application_Menu_Modifier.Shift in expected) == shift_down &&
		(Application_Menu_Modifier.Alt in expected) == alt_down &&
		(Application_Menu_Modifier.Super in expected) == super_down
}

native_menu_match_shortcut_items :: proc(
	items: []Application_Menu_Item,
	key: rune,
	modifiers: sdl3.Keymod,
) -> (Application_Command_ID, bool) {
	for item in items {
		if item.kind == .Submenu {
			if command, found := native_menu_match_shortcut_items(item.items, key, modifiers); found {
				return command, true
			}
		} else if item.kind == .Command && item.state.enabled && item.command != Application_Command_ID(0) &&
			item.shortcut.key != 0 && native_menu_shortcut_modifiers_match(item.shortcut.modifiers, modifiers) &&
			native_menu_shortcut_key_equal(item.shortcut.key, key) {
			return item.command, true
		}
	}
	return {}, false
}

native_menu_match_shortcut :: proc(
	application: ^Application,
	keycode: int,
	modifiers: sdl3.Keymod,
) -> (Application_Command_ID, bool) {
	if application == nil { return {}, false }
	key := rune(keycode)
	for description in application.menus {
		if description.command != Application_Command_ID(0) && description.state.enabled &&
			description.shortcut.key != 0 && native_menu_shortcut_modifiers_match(description.shortcut.modifiers, modifiers) &&
			native_menu_shortcut_key_equal(description.shortcut.key, key) {
			return description.command, true
		}
		if command, found := native_menu_match_shortcut_items(description.items, key, modifiers); found {
			return command, true
		}
	}
	return {}, false
}

// A native chrome transition must wake the SDL loop when it is waiting for
// events. Coalesce repeated pointer messages until the requested frame lands.
native_menu_request_chrome_redraw :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil { return }
	was_pending := menu.chrome_redraw_pending
	menu.chrome_redraw_pending = true
	if !was_pending { native_host_event_wake(menu.host_waker) }
}

native_window_chrome_appearance_equal :: proc(a, b: Window_Chrome_Appearance) -> bool {
	if a.defined != b.defined { return false }
	if !a.defined { return true }
	return a.background == b.background && a.foreground == b.foreground
}

// Resolve the app's optional chrome colors at description boundaries. If app
// paint already needs a frame, that submission will include the new host
// appearance. Otherwise request a host-only frame to repaint chrome.
native_menu_sync_chrome_appearance :: proc(menu: ^Native_Menu_Runtime, request_redraw := true) -> bool {
	if menu == nil || menu.application == nil || menu.runtime == nil ||
	   menu.application.window_chrome_appearance == nil {
		return false
	}
	next := menu.application.window_chrome_appearance(menu.application.state, menu.runtime)
	if menu.chrome_appearance_resolved && native_window_chrome_appearance_equal(menu.chrome_appearance, next) {
		return false
	}
	menu.chrome_appearance = next
	menu.chrome_appearance_resolved = true
	if request_redraw { native_menu_request_chrome_redraw(menu) }
	return true
}

native_menu_dispatch_command :: proc(menu: ^Native_Menu_Runtime, command: Application_Command_ID) {
	if menu == nil || menu.application == nil || menu.application.on_menu_command == nil { return }
	direct_command := false
	for description in menu.application.menus {
		if description.command == command && command != Application_Command_ID(0) {
			direct_command = true
			if !description.state.enabled { return }
		}
	}
	if !direct_command && menu.runtime != nil {
		_, state, found := alicorn.action_lookup(menu.runtime, command)
		if found && !state.enabled { return }
	}
	cause: alicorn.Cause_Scope
	if menu.runtime != nil {
		cause = alicorn.cause_begin(menu.runtime, .Native_Command, "native menu command", command)
	}
	menu.application.on_menu_command(menu.application.state, menu.runtime, command)
	if menu.runtime != nil { alicorn.invalidate_root(menu.runtime, "application menu command") }
	if menu.runtime != nil { alicorn.cause_end(menu.runtime, cause) }
}

Native_Application_Waker :: struct {
	event_type: sdl3.EventType,
	active:     bool,
}

// Host redraw events are separate from Application_Waker so a chrome repaint
// cannot be mistaken for an asynchronous application producer wake.
Native_Host_Event_Waker :: struct {
	event_type: sdl3.EventType,
	active:     bool,
}

NATIVE_OPPORTUNISTIC_QUIET_NS :: u64(150_000_000)

native_application_schedule_after :: proc(data: rawptr, class: Scheduled_Wake_Class, delay_ns: u64) -> bool {
	return scheduled_wake_schedule(cast(^Native_Scheduled_Wake_State)data, class, u64(sdl3.GetTicksNS()), delay_ns)
}

native_application_cancel_scheduled :: proc(data: rawptr, class: Scheduled_Wake_Class) -> bool {
	return scheduled_wake_cancel(cast(^Native_Scheduled_Wake_State)data, class)
}

native_application_scheduler_stats :: proc(data: rawptr) -> Application_Scheduler_Stats {
	return scheduled_wake_read_stats(cast(^Native_Scheduled_Wake_State)data)
}

native_event_is_user_interaction :: proc(kind: sdl3.EventType) -> bool {
	#partial switch kind {
	case .KEY_DOWN, .KEY_UP, .TEXT_INPUT, .TEXT_EDITING,
		.MOUSE_MOTION, .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_WHEEL:
		return true
	}
	return false
}

native_dispatch_scheduled_wakes :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Scheduled_Wake_State,
	last_interaction_ns: u64,
	timing: ^Native_Host_Timing,
) {
	if application == nil || state == nil || !state.active { return }
	classes := [2]Scheduled_Wake_Class{.Frequent, .Opportunistic}
	for class in classes {
		now_ns := u64(sdl3.GetTicksNS())
		if !scheduled_wake_is_due(state, class, now_ns) { continue }
		index := scheduled_wake_class_index(class)
		if class == .Opportunistic {
			deferred_until, defer_work := scheduled_wake_defer_until_quiet(now_ns, last_interaction_ns, NATIVE_OPPORTUNISTIC_QUIET_NS)
			if defer_work {
				state.deadlines_ns[index] = deferred_until
				state.stats.opportunistic_deferrals += 1
				timing.opportunistic_deferrals += 1
				continue
			}
		}
		deadline_ns := state.deadlines_ns[index]
		lateness_ns := u64(0)
		if now_ns > deadline_ns { lateness_ns = now_ns-deadline_ns }
		scheduled_wake_record_run(state, class, lateness_ns)
		timing.scheduled_wakes += 1
		timing.maximum_scheduled_lateness_ns = max(timing.maximum_scheduled_lateness_ns, lateness_ns)
		if application.on_scheduled_wake != nil {
			reason := class == .Frequent ? "frequent scheduled work" : "opportunistic scheduled work"
			cause := alicorn.cause_begin(rt, .Scheduled_Wake, reason)
			application.on_scheduled_wake(application.state, rt, class)
			alicorn.cause_end(rt, cause)
		}
	}
}

native_application_wake :: proc(data: rawptr) {
	state := cast(^Native_Application_Waker)data
	if state == nil || !state.active { return }
	event := sdl3.Event{type=state.event_type}
	_ = sdl3.PushEvent(&event)
}

native_host_event_wake :: proc(state: ^Native_Host_Event_Waker) -> bool {
	if state == nil || !state.active { return false }
	event := sdl3.Event{type=state.event_type}
	return sdl3.PushEvent(&event)
}

native_application_request_quit :: proc(data: rawptr) {
	state := cast(^bool)data
	if state != nil { state^ = true }
}
