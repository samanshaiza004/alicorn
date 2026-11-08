package alicorn_sdl_gpu

import "core:c"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

Native_Text_Input_State :: struct {
	active: bool,
	owner: alicorn.Node_ID,
	composition_owner: alicorn.Node_ID,
	window_focused: bool,
	// A host overlay can own keyboard input while retaining the application's
	// focused node. Native text ownership resumes after its event queue drains.
	suspended: bool,
	last_area: alicorn.Text_Input_Area,
	last_area_valid: bool,
	content_inset_top: f32,
}

// SDL's Cocoa backend owns one process-wide NSTextInputContext/editor even
// though Alicorn retains focus independently for each window. This coordinator
// serializes the native side effects while each window keeps its own runtime
// focus, composition, and application state.
Native_Text_Input_Coordinator :: struct {
	owner_window: ^sdl3.Window,
	owner_window_id: sdl3.WindowID,
	owner_state: ^Native_Text_Input_State,
	owner_runtime: ^alicorn.Runtime,
	owner_application: ^Application,
	generation: u64,
}

native_text_input_coordinator_owns_state :: proc(
	coordinator: ^Native_Text_Input_Coordinator,
	state: ^Native_Text_Input_State,
) -> bool {
	return coordinator != nil && state != nil && coordinator.owner_state == state
}

native_text_input_focus_matches_window :: proc(window_id, focused_window_id: sdl3.WindowID) -> bool {
	return window_id != 0 && window_id == focused_window_id
}

native_text_input_should_replay_child_before_primary_focus :: proc(
	event_type: sdl3.EventType,
	replaying_child_events: bool,
	pending_child_events: int,
) -> bool {
	return !replaying_child_events && event_type == .WINDOW_FOCUS_GAINED && pending_child_events > 0
}

native_text_input_owner_is_valid :: proc(rt: ^alicorn.Runtime, id: alicorn.Node_ID) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || !node.focusable || node.disabled { return false }
	if alicorn.text_input_target_is_suspended(rt, id) { return false }
	return node.kind == .Text_Field || alicorn.text_input_target_is_active(rt, id) ||
		(alicorn.select_wants_text_input(rt) && id == rt.focused)
}

// A controlled field submits on an unmodified, non-repeating Return after
// application key handling declines it. AppKit/SDL composition keeps Enter
// when IME preedit is active.
native_text_field_submit_on_key :: proc(
	rt: ^alicorn.Runtime,
	key: sdl3.Keycode,
	repeat, modified, composition_active: bool,
) -> bool {
	if rt == nil || repeat || modified || composition_active ||
	   (key != sdl3.K_RETURN && key != sdl3.K_KP_ENTER) {
		return false
	}
	if node, found := rt.nodes[rt.focused]; found && node.composition.active { return false }
	return alicorn.text_field_request_submit(rt, rt.focused)
}

native_current_text_input_owner :: proc(rt: ^alicorn.Runtime, state: ^Native_Text_Input_State = nil) -> alicorn.Node_ID {
	if state != nil {
		if state.suspended || !state.active || !state.window_focused || state.owner == 0 || state.owner != rt.focused { return 0 }
		return state.owner if native_text_input_owner_is_valid(rt, state.owner) else 0
	}
	return rt.focused if native_text_input_owner_is_valid(rt, rt.focused) else 0
}

native_text_composition_active :: proc(rt: ^alicorn.Runtime, state: ^Native_Text_Input_State = nil) -> bool {
	if rt == nil { return false }
	if node, found := rt.nodes[rt.focused]; found && node.composition.active { return true }
	return state != nil && state.composition_owner != 0 && state.composition_owner == rt.focused
}

native_text_input_area_update_required :: proc(
	state: ^Native_Text_Input_State,
	area: alicorn.Text_Input_Area,
	area_valid: bool,
) -> bool {
	if !area_valid { return state.last_area_valid }
	return !state.last_area_valid || state.last_area != area
}

native_application_text_input_event :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Input_Event,
	require_live_target := true,
) -> bool {
	if application == nil { return false }
	return alicorn.application_dispatch_text_input(
		rt, application.state, application.on_text_input, owner, event, require_live_target,
	)
}

native_dispatch_generic_text_input_event :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	event: Application_Text_Input_Event,
) -> bool {
	owner := native_current_text_input_owner(rt, state)
	if !alicorn.text_input_target_is_active(rt, owner) { return false }
	normalized_event := event
	if normalized_event.kind == .Preedit && len(normalized_event.text) == 0 { normalized_event.kind = .Cancel }
	delivered := native_application_text_input_event(application, rt, owner, normalized_event)
	if !delivered { return false }
	if state != nil {
		switch normalized_event.kind {
		case .Preedit: state.composition_owner = owner
		case .Commit, .Cancel: state.composition_owner = 0
		}
	}
	return true
}

native_application_text_key_event :: proc(
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> (event: Application_Text_Key_Event, mapped: bool) {
	word := native_text_word_modifier(mod)
	line := native_text_line_modifier(mod)
	document := native_text_document_modifier(mod)
	switch key {
	case sdl3.K_LEFT:
		if line { event.key = .Line_Start }
		else if word { event.key = .Word_Left }
		else { event.key = .Left }
	case sdl3.K_RIGHT:
		if line { event.key = .Line_End }
		else if word { event.key = .Word_Right }
		else { event.key = .Right }
	case sdl3.K_HOME: event.key = .Document_Start if document else .Home
	case sdl3.K_END: event.key = .Document_End if document else .End
	case sdl3.K_UP:
		when ODIN_OS == .Darwin {
			event.key = .Document_Start if document else .Up
		} else { event.key = .Up }
	case sdl3.K_DOWN:
		when ODIN_OS == .Darwin {
			event.key = .Document_End if document else .Down
		} else { event.key = .Down }
	case sdl3.K_PAGEUP: event.key = .Page_Up
	case sdl3.K_PAGEDOWN: event.key = .Page_Down
	case sdl3.K_BACKSPACE:
		if line { event.key = .Delete_Line_Backward }
		else if word { event.key = .Delete_Word_Backward }
		else { event.key = .Backspace }
	case sdl3.K_DELETE:
		if line { event.key = .Delete_Line_Forward }
		else if word { event.key = .Delete_Word_Forward }
		else { event.key = .Delete }
	case sdl3.K_TAB: event.key = .Tab
	case: return {}, false
	}
	event.shift = native_text_modifier(mod, sdl3.KMOD_SHIFT)
	event.control = native_text_modifier(mod, sdl3.KMOD_CTRL)
	event.alt = native_text_modifier(mod, sdl3.KMOD_ALT)
	event.super = native_text_modifier(mod, sdl3.KMOD_GUI)
	return event, true
}

native_dispatch_application_text_key :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> bool {
	if application == nil || application.on_text_key == nil || rt == nil { return false }
	event, mapped := native_application_text_key_event(key, mod)
	if !mapped { return false }
	return alicorn.application_dispatch_text_key(rt, application.state, application.on_text_key, event)
}

// Control+Tab is an application-level document navigation chord. It must be
// recognized before text owners and ordinary Tab focus traversal, even when
// the application has no document tabs (in which case it remains a no-op).
native_dispatch_application_tab_navigation :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> bool {
	if key != sdl3.K_TAB || !native_text_modifier(mod, sdl3.KMOD_CTRL) { return false }
	if rt != nil && alicorn.context_menu_input_active(rt) { return true }
	state: rawptr
	callback: alicorn.Application_Key_Proc
	if application != nil {
		state = application.state
		callback = application.on_key
	}
	return alicorn.application_dispatch_tab_navigation(
		rt, state, callback, true, native_text_modifier(mod, sdl3.KMOD_SHIFT),
	)
}

// A generic focused text owner gets first refusal on Tab. If it declines the
// key, retain the host's normal forward/backward focus traversal behavior.
native_dispatch_application_text_key_or_focus_traverse :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> bool {
	if native_dispatch_application_tab_navigation(application, rt, key, mod) { return true }
	if native_dispatch_application_text_key(application, rt, key, mod) { return true }
	if key != sdl3.K_TAB || rt == nil { return false }
	return alicorn.application_dispatch_tab_focus(rt, native_text_modifier(mod, sdl3.KMOD_SHIFT))
}

native_cancel_application_text_composition :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
) {
	if state.composition_owner == 0 { return }
	owner := state.composition_owner
	state.composition_owner = 0
	_ = native_application_text_input_event(
		application,
		rt,
		owner,
		Application_Text_Input_Event{kind=.Cancel},
		require_live_target=false,
	)
}

native_cancel_current_text_composition :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	reason := "text composition canceled by text-input lifecycle",
) {
	if state.composition_owner != 0 {
		native_cancel_application_text_composition(application, rt, state)
		return
	}
	if node, ok := rt.nodes[state.owner]; ok && node.active && node.kind == .Text_Field && node.composition.active {
		_ = alicorn.cancel_text_composition(rt, state.owner, reason)
	}
}

sync_text_input_focus :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	application: ^Application = nil,
	coordinator: ^Native_Text_Input_Coordinator = nil,
	allow_native_transition := true,
) {
	desired := rt.focused
	if state.suspended || !state.window_focused || !native_text_input_owner_is_valid(rt, desired) { desired = 0 }
	if desired != 0 {
		if node, ok := rt.nodes[desired]; ok && node.kind != .Text_Field &&
			(application == nil || application.on_text_input == nil) && !alicorn.select_wants_text_input(rt) {
			desired = 0
		}
	}
	if allow_native_transition {
		when ODIN_OS == .Darwin {
			if coordinator != nil {
				native_text_input_coordinator_sync(
					coordinator, window, rt, state, application, desired, allow_native_transition,
				)
			} else {
				native_text_input_sync_window(window, rt, state, application, desired)
			}
		} else {
			native_text_input_sync_window(window, rt, state, application, desired)
		}
	}
	owns_native_session := coordinator == nil || native_text_input_coordinator_owns_state(coordinator, state)
	if state.active && state.owner != 0 && owns_native_session {
		area, ok := alicorn.text_input_area(rt, state.owner)
		if !ok {
			if native_text_input_area_update_required(state, {}, false) {
				if !sdl3.SetTextInputArea(window, nil, 0) {
					fail("SDL_SetTextInputArea failed while clearing stale candidate-window geometry")
				}
				state.last_area = alicorn.Text_Input_Area{}
				state.last_area_valid = false
			}
			return
		}
		width := int(area.rect.w)
		height := int(area.rect.h)
		if width < 1 { width = 1 }
		if height < 1 { height = 1 }
		window_rect := native_application_rect_to_window(
			native_content_transform_make(f32(rt.viewport.h)+state.content_inset_top, state.content_inset_top),
			area.rect,
		)
		input_area := sdl3.Rect{
			x=c.int(window_rect.x), y=c.int(window_rect.y), w=c.int(width), h=c.int(height),
		}
		cache_area := area
		cache_area.rect = window_rect
		if native_text_input_area_update_required(state, cache_area, true) {
			if !sdl3.SetTextInputArea(window, &input_area, c.int(area.cursor_x)) {
				fail("SDL_SetTextInputArea failed for focused text-input target")
			}
			state.last_area = cache_area
			state.last_area_valid = true
		}
	}
}

native_text_input_sync_window :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	application: ^Application,
	desired: alicorn.Node_ID,
) {
	if desired == state.owner { return }
	native_cancel_current_text_composition(application, rt, state)
	if state.active {
		// Clear platform preedit before changing the Alicorn owner; otherwise a
		// late platform event could be applied to the wrong target.
		if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed during text-input focus transfer") }
		if !sdl3.StopTextInput(window) { fail("SDL_StopTextInput failed during text-input focus transfer") }
		state.active = false
	}
	state.owner = 0
	state.last_area_valid = false
	if desired != 0 {
		if !sdl3.StartTextInput(window) { fail("SDL_StartTextInput failed for focused text-input target") }
		state.active = true
		state.owner = desired
	}
}

native_text_input_coordinator_retire_owner :: proc(
	coordinator: ^Native_Text_Input_Coordinator,
	reason := "native text-input ownership transferred",
) {
	if coordinator == nil || coordinator.owner_state == nil { return }
	state := coordinator.owner_state
	rt := coordinator.owner_runtime
	window := coordinator.owner_window
	if rt != nil {
		native_cancel_current_text_composition(coordinator.owner_application, rt, state, reason)
	}
	// A registered owner represents the one live SDL/Cocoa input session. Stop
	// it exactly once, before installing a new window as native owner.
	if window != nil {
		if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed while retiring native text-input owner") }
		if !sdl3.StopTextInput(window) { fail("SDL_StopTextInput failed while retiring native text-input owner") }
	}
	state.active = false
	state.owner = 0
	state.last_area_valid = false
	coordinator.owner_window = nil
	coordinator.owner_window_id = 0
	coordinator.owner_state = nil
	coordinator.owner_runtime = nil
	coordinator.owner_application = nil
	coordinator.generation += 1
}

native_text_input_coordinator_sync :: proc(
	coordinator: ^Native_Text_Input_Coordinator,
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	application: ^Application,
	requested_owner: alicorn.Node_ID,
	allow_native_transition: bool,
) {
	if coordinator == nil || window == nil || rt == nil || state == nil || !allow_native_transition { return }
	desired := requested_owner
	focused_window := sdl3.GetKeyboardFocus()
	focused_window_id := sdl3.WindowID(0)
	if focused_window != nil { focused_window_id = sdl3.GetWindowID(focused_window) }
	window_id := sdl3.GetWindowID(window)
	if desired != 0 && !native_text_input_focus_matches_window(window_id, focused_window_id) {
		// SDL focus events can be deferred per-window. The platform's current
		// keyboard target is authoritative for acquiring the shared Cocoa editor.
		desired = 0
	}
	owns_session := native_text_input_coordinator_owns_state(coordinator, state)
	if desired == 0 {
		if owns_session {
			native_text_input_coordinator_retire_owner(coordinator, "native text-input window lost focus or target")
		} else if state.owner != 0 || state.composition_owner != 0 {
			// A stale non-owner must clear only its logical state. Calling SDL's
			// stop API here could remove another window's process-wide Cocoa editor.
			native_cancel_current_text_composition(application, rt, state)
			state.active = false
			state.owner = 0
			state.last_area_valid = false
		}
		return
	}
	if owns_session && state.owner == desired { return }
	if coordinator.owner_state != nil {
		native_text_input_coordinator_retire_owner(coordinator)
	}
	if state.owner != 0 || state.composition_owner != 0 {
		native_cancel_current_text_composition(application, rt, state)
		state.active = false
		state.owner = 0
		state.last_area_valid = false
	}
	if !sdl3.StartTextInput(window) { fail("SDL_StartTextInput failed for coordinated text-input target") }
	state.active = true
	state.owner = desired
	state.last_area_valid = false
	coordinator.owner_window = window
	coordinator.owner_window_id = window_id
	coordinator.owner_state = state
	coordinator.owner_runtime = rt
	coordinator.owner_application = application
	coordinator.generation += 1
}

native_text_input_coordinator_relinquish :: proc(
	coordinator: ^Native_Text_Input_Coordinator,
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	application: ^Application,
	reason := "native text-input window destroyed",
) {
	if coordinator == nil || state == nil { return }
	when ODIN_OS == .Darwin {
		if native_text_input_coordinator_owns_state(coordinator, state) &&
			(window == nil || coordinator.owner_window == window) {
			native_text_input_coordinator_retire_owner(coordinator, reason)
		} else {
			if rt != nil { native_cancel_current_text_composition(application, rt, state, reason) }
			state.active = false
			state.owner = 0
			state.last_area_valid = false
		}
	} else {
		if rt != nil { native_cancel_current_text_composition(application, rt, state, reason) }
		if state.active && window != nil {
			_ = sdl3.ClearComposition(window)
			_ = sdl3.StopTextInput(window)
		}
		state.active = false
		state.owner = 0
		state.last_area_valid = false
	}
}

adopt_text_change :: proc(app_text: ^string, rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	// Text_Change.text is a runtime-owned product. Copy it into the host's
	// ordinary application state before releasing it through the allocator that
	// created it; never transfer the runtime allocation across this boundary.
	if change.changed {
		copy, err := strings.clone(change.text)
		if err == nil {
			if len(app_text^) > 0 { delete(app_text^) }
			app_text^ = copy
		}
	}
	if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
}

native_dispatch_text_change :: proc(
	app_text: ^string,
	application: ^Application,
	rt: ^alicorn.Runtime,
	change: alicorn.Text_Change,
	telemetry: ^Native_Text_Event_Telemetry = nil,
) {
	if telemetry != nil {
		telemetry.text_change_dispatches += 1
		if change.changed { telemetry.text_changes += 1 }
	}
	if application != nil {
		alicorn.application_dispatch_text_change(rt, application.state, application.on_text_change, change)
	} else {
		adopt_text_change(app_text, rt, change)
	}
}

native_text_modifier :: proc(mod: sdl3.Keymod, mask: sdl3.Keymod) -> bool {
	return (mod & mask) != sdl3.Keymod{}
}

native_text_primary_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_modifier(mod, sdl3.KMOD_GUI)
	} else {
		return native_text_modifier(mod, sdl3.KMOD_CTRL)
	}
}

native_text_word_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_modifier(mod, sdl3.KMOD_ALT)
	} else {
		return native_text_modifier(mod, sdl3.KMOD_CTRL)
	}
}

native_text_line_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_modifier(mod, sdl3.KMOD_GUI)
	} else {
		return false
	}
}

native_text_document_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_primary_modifier(mod)
	} else {
		return native_text_modifier(mod, sdl3.KMOD_CTRL)
	}
}

native_text_apply_key_edit :: proc(
	rt: ^alicorn.Runtime,
	node: alicorn.Node_ID,
	kind: alicorn.Text_Edit_Kind,
	word: bool,
	app_text: ^string,
	application: ^Application,
	telemetry: ^Native_Text_Event_Telemetry = nil,
) -> bool {
	event := Application_Text_Key_Event{key=.Backspace if kind == .Backspace else .Delete}
	if word {
		event.key = .Delete_Word_Backward if kind == .Backspace else .Delete_Word_Forward
	}
	result, change := alicorn.application_route_text_field_key(rt, node, event)
	if result != .Edit { return false }
	if telemetry != nil { telemetry.text_edit_key_events += 1 }
	native_dispatch_text_change(app_text, application, rt, change, telemetry)
	return true
}

native_text_apply_key_navigation :: proc(
	rt: ^alicorn.Runtime,
	node: alicorn.Node_ID,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
	telemetry: ^Native_Text_Event_Telemetry = nil,
) -> bool {
	field, ok := rt.nodes[node]
	if !ok || !field.active || field.kind != .Text_Field || field.composition.active { return false }
	if key == sdl3.K_A && native_text_primary_modifier(mod) {
		_ = alicorn.set_text_selection(rt, node, 0, len(field.text))
		if telemetry != nil { telemetry.text_selection_key_events += 1 }
		return true
	}
	event, mapped := native_application_text_key_event(key, mod)
	if !mapped { return false }
	result, _ := alicorn.application_route_text_field_key(rt, node, event)
	if result != .Navigation { return false }
	if telemetry != nil {
		telemetry.text_navigation_key_events += 1
		if event.shift { telemetry.text_selection_key_events += 1 }
		if event.key == .Word_Left || event.key == .Word_Right { telemetry.text_word_key_events += 1 }
	}
	return true
}
