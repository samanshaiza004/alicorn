package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

Menu_Wake_Test_State :: struct { application_wakes: int }

@(test)
test_direct_caption_command_uses_its_window_state :: proc(t: ^testing.T) {
	state := Menu_Dispatch_Test_State{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	command := Application_Command_ID(0x9876)
	menus := [?]Application_Menu{{label="Save", command=command, state=alicorn.Action_State{enabled=true}}}
	app := Application{state=rawptr(&state), menus=menus[:], on_menu_command=menu_dispatch_test_callback}
	menu := Native_Menu_Runtime{application=&app, runtime=&rt}
	_ = alicorn.action_update(&rt, alicorn.Action_Descriptor{id=command, name="test.save", label="Save"}, alicorn.Action_State{enabled=false})
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1, "a direct caption action must use its window's explicit state rather than another view's action state")
	menus[0].state.enabled = false
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1, "disabling the borrowed caption action must prevent subsequent invocation")
}

@(test)
test_menu_shortcut_matching_supports_nested_items_and_exact_modifiers :: proc(t: ^testing.T) {
	recent_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(4), label="Open", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'O', {.Primary}}},
	}
	file_items := [?]Application_Menu_Item{
		{kind=.Submenu, label="Recent", state=alicorn.Action_State{enabled=true}, items=recent_items[:]},
		{kind=.Command, command=Application_Command_ID(2), label="Save", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'S', {.Primary}}},
		{kind=.Command, command=Application_Command_ID(3), label="Save As", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'S', {.Primary, .Shift}}},
		{kind=.Command, command=Application_Command_ID(5), label="Palette", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'P', {.Primary, .Shift}}},
	}
	menus := [?]Application_Menu{{label="File", items=file_items[:]}}
	application := Application{menus=menus[:]}
	primary := sdl3.KMOD_CTRL
	when ODIN_OS == .Darwin { primary = sdl3.KMOD_GUI }

	command, found := native_menu_match_shortcut(&application, int(sdl3.K_S), primary)
	testing.expect(t, found && command == Application_Command_ID(2), "Primary+S should match Save")
	command, found = native_menu_match_shortcut(&application, int(sdl3.K_S), primary|sdl3.KMOD_SHIFT)
	testing.expect(t, found && command == Application_Command_ID(3), "Primary+Shift+S should match Save As")
	command, found = native_menu_match_shortcut(&application, int(sdl3.K_O), primary)
	testing.expect(t, found && command == Application_Command_ID(4), "nested Primary+O should match Open")
	command, found = native_menu_match_shortcut(&application, int(sdl3.K_P), primary|sdl3.KMOD_SHIFT)
	testing.expect(t, found && command == Application_Command_ID(5), "Primary+Shift+P should match the command palette")
	_, found = native_menu_match_shortcut(&application, int(sdl3.K_S), primary|sdl3.KMOD_ALT)
	testing.expect(t, !found, "an unexpected modifier must not match a shortcut")
	file_items[1].state.enabled = false
	_, found = native_menu_match_shortcut(&application, int(sdl3.K_S), primary)
	testing.expect(t, !found, "a disabled command must not match a shortcut")
}

@(test)
test_linux_menu_shortcut_dispatch_ignores_repeats :: proc(t: ^testing.T) {
	when ODIN_OS == .Linux {
		state := Menu_Dispatch_Test_State{}
		items := [?]Application_Menu_Item{
			{kind=.Command, command=Application_Command_ID(1), label="Save", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'S', {.Primary}}},
		}
		menus := [?]Application_Menu{{label="File", items=items[:]}}
		application := Application{state=rawptr(&state), menus=menus[:], on_menu_command=menu_dispatch_test_callback}
		menu := Native_Menu_Runtime{application=&application}
		primary := sdl3.KMOD_CTRL
		testing.expect(t, native_menu_prepare(&menu), "Linux should accept semantic menu metadata with system decorations")
		testing.expect(t, native_menu_try_shortcut(&menu, int(sdl3.K_S), primary, false), "Linux should handle a matching menu accelerator")
		testing.expect(t, state.calls == 1, "a non-repeating shortcut should dispatch exactly once")
		testing.expect(t, native_menu_try_shortcut(&menu, int(sdl3.K_S), primary, true), "a repeated matching accelerator should remain consumed")
		testing.expect(t, state.calls == 1, "a repeated shortcut must not dispatch a second command")
		rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
		defer alicorn.destroy_runtime(&rt)
		rt.focused = 1
		composition := Native_Text_Input_State{composition_owner=1}
		testing.expect(t, native_text_composition_active(&rt, &composition), "an active IME composition should be visible to shortcut routing")
	}
}

@(test)
test_direct_caption_click_defers_application_callback :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		calls := Menu_Dispatch_Test_State{}
		description := Application_Menu{label="Return", command=Application_Command_ID(0x9877), state=alicorn.Action_State{enabled=true}}
		app := Application{state=rawptr(&calls), on_menu_command=menu_dispatch_test_callback}
		menu := Native_Menu_Runtime{application=&app}
		labels := [?]Win32_Menu_Label{{direct_menu=&description}}
		state := Win32_Menu_State{menu=&menu, labels=labels[:]}
		win32_menu_label_activate(&state, 0)
		testing.expect(t, calls.calls == 0 && menu.has_pending, "Win32 subclass input must queue the command until the host reaches its dispatch safe point")
		command, found := native_menu_take_pending(&menu)
		testing.expect(t, found && command == description.command, "the pending command must retain the caption action identity")
		native_menu_dispatch_command(&menu, command)
		testing.expect(t, calls.calls == 1, "the host should invoke the queued action exactly once")
	}
}

Menu_Chrome_Appearance_Test_State :: struct {
	appearance: Window_Chrome_Appearance,
	reads:      int,
}

menu_chrome_appearance_test_callback :: proc(data: rawptr, rt: ^alicorn.Runtime) -> Window_Chrome_Appearance {
	_ = rt
	state := cast(^Menu_Chrome_Appearance_Test_State)data
	state.reads += 1
	return state.appearance
}

menu_application_wake_test_callback :: proc(data: rawptr, rt: ^alicorn.Runtime) {
	state := cast(^Menu_Wake_Test_State)data
	state.application_wakes += 1
	alicorn.invalidate_root(rt, "application wake test")
}

@(test)
	test_native_chrome_wake_isolated_from_application_wake :: proc(t: ^testing.T) {
	if !sdl3.Init(sdl3.INIT_EVENTS) {
		testing.expect(t, false, "SDL event subsystem should initialize for host-wake routing regression")
		return
	}
	defer sdl3.Quit()

	application_event_id := sdl3.RegisterEvents(1)
	host_event_id := sdl3.RegisterEvents(1)
	if application_event_id == 0 || host_event_id == 0 {
		testing.expect(t, false, "SDL should register distinct application and host wake events")
		return
	}
	application_event := sdl3.EventType(application_event_id)
	host_event := sdl3.EventType(host_event_id)
	if application_event == host_event {
		testing.expect(t, false, "host and application wake events must be distinct")
		return
	}

	state := Menu_Wake_Test_State{}
	app := Application{state=rawptr(&state), on_wake=menu_application_wake_test_callback}
	host_waker := Native_Host_Event_Waker{event_type=host_event, active=true}
	menu := Native_Menu_Runtime{host_waker=&host_waker}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200}, alicorn.Runtime_Config{trace_capacity=8})
	defer alicorn.destroy_runtime(&rt)
	rt.invalidated = false
	host_wake_events: u64 = 0
	host_wait_timed_out := false
	quit := false
	logical_resize_events, pixel_resize_events, scale_events: int
	text_input_events, composition_events: int
	app_text := ""
	metrics := Window_Metrics{}

	native_menu_request_chrome_redraw(&menu)
	native_menu_request_chrome_redraw(&menu)
	testing.expect(t, menu.chrome_redraw_pending, "chrome invalidation should remain pending until presentation")
	testing.expect(t, native_frame_submission_requested(false, menu.chrome_redraw_pending, false, false),
		"chrome-only invalidation should request a host frame")
	pump_events(
		nil, &rt, &metrics, &quit,
		&logical_resize_events, &pixel_resize_events, &scale_events,
		&text_input_events, &composition_events, &app_text,
		application=&app,
		wake_event=application_event,
		wake_event_enabled=true,
		host_wake_event=host_event,
		host_wake_event_enabled=true,
		wait_for_event=true,
		wait_timeout_ms=1000,
		wait_timed_out=&host_wait_timed_out,
		native_host_wake_events=&host_wake_events,
		native_menu=&menu,
	)
	testing.expect(t, host_wake_events == 1, "coalesced chrome redraw event should return the host event pump once")
	testing.expect(t, !host_wait_timed_out, "queued host redraw should wake SDL's blocking event wait")
	testing.expect(t, state.application_wakes == 0, "chrome redraw must not invoke Application.on_wake")
	testing.expect(t, !rt.invalidated, "chrome redraw must not invalidate or rebuild application content")

	app_wake := sdl3.Event{type=application_event}
	if !sdl3.PushEvent(&app_wake) {
		testing.expect(t, false, "independent application wake should enqueue successfully")
		return
	}
	pump_events(
		nil, &rt, &metrics, &quit,
		&logical_resize_events, &pixel_resize_events, &scale_events,
		&text_input_events, &composition_events, &app_text,
		application=&app,
		wake_event=application_event,
		wake_event_enabled=true,
		host_wake_event=host_event,
		host_wake_event_enabled=true,
		native_host_wake_events=&host_wake_events,
		native_menu=&menu,
	)
	testing.expect(t, state.application_wakes == 1, "application wake event must remain independently deliverable")
	testing.expect(t, rt.invalidated, "actual application wake should retain its normal application invalidation")
}

@(test)
test_native_chrome_appearance_updates_are_retained_and_host_owned :: proc(t: ^testing.T) {
	state := Menu_Chrome_Appearance_Test_State{
		appearance=Window_Chrome_Appearance{
			defined=true,
			background=alicorn.Color{0.12, 0.16, 0.22, 1},
			foreground=alicorn.Color{0.88, 0.90, 0.94, 1},
		},
	}
	application := Application{
		state=rawptr(&state),
		window_chrome_appearance=menu_chrome_appearance_test_callback,
	}
	menu := Native_Menu_Runtime{application=&application}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200}, alicorn.Runtime_Config{trace_capacity=8})
	defer alicorn.destroy_runtime(&rt)
	menu.runtime = &rt
	rt.invalidated = false

	changed := native_menu_sync_chrome_appearance(&menu, request_redraw=false)
	testing.expect(t, changed && menu.chrome_appearance_resolved && menu.chrome_appearance == state.appearance,
		"initial theme appearance should be retained by the host")
	testing.expect(t, !menu.chrome_redraw_pending,
		"initial chrome appearance should join the already-pending first application frame")
	changed = native_menu_sync_chrome_appearance(&menu)
	testing.expect(t, !changed && !menu.chrome_redraw_pending,
		"an unchanged theme appearance should not request another frame")

	state.appearance.background = alicorn.Color{0.42, 0.48, 0.58, 1}
	changed = native_menu_sync_chrome_appearance(&menu)
	testing.expect(t, changed && menu.chrome_redraw_pending && menu.chrome_appearance == state.appearance,
		"a changed theme appearance should update retained host colors and request chrome redraw")
	testing.expect(t, !rt.invalidated && state.reads == 3,
		"resolving host chrome must not invalidate application content")
}

Menu_Dispatch_Test_State :: struct {
	calls:        int,
	last_command: Application_Command_ID,
}

menu_dispatch_test_callback :: proc(state: rawptr, rt: ^alicorn.Runtime, command: Application_Command_ID) {
	test_state := cast(^Menu_Dispatch_Test_State)state
	test_state.calls += 1
	test_state.last_command = command
}

@(test)
test_menu_dispatch_preserves_semantic_command_id :: proc(t: ^testing.T) {
	state := Menu_Dispatch_Test_State{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200}, alicorn.Runtime_Config{trace_capacity=8})
	defer alicorn.destroy_runtime(&rt)
	application := Application{
		state=rawptr(&state),
		on_menu_command=menu_dispatch_test_callback,
	}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt}
	command := Application_Command_ID(0x1234)
	testing.expect(t, alicorn.action_update(&rt,
		alicorn.Action_Descriptor{id=command, name="test.open", label="Open"},
		alicorn.Action_State{enabled=true}), "native menu action should share runtime action identity")
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1, "one native selection must invoke one application command")
	testing.expect(t, state.last_command == command, "native menu IDs must map back to the semantic command ID")
	events := alicorn.trace_snapshot(&rt)
	defer delete(events)
	found_action_cause := false
	for event in events {
		if event.kind == .Cause {
			found_action_cause = event.action_id == command && event.cause_kind == .Native_Command
		}
	}
	testing.expect(t, found_action_cause, "native transport should preserve the typed action identity in causal runtime events")
}

@(test)
test_disabled_runtime_action_rejects_native_menu_invocation :: proc(t: ^testing.T) {
	state := Menu_Dispatch_Test_State{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200}, alicorn.Runtime_Config{trace_capacity=8})
	defer alicorn.destroy_runtime(&rt)
	application := Application{state=rawptr(&state), on_menu_command=menu_dispatch_test_callback}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt}
	command := Application_Command_ID(0x1235)
	testing.expect(t, alicorn.action_update(&rt,
		alicorn.Action_Descriptor{id=command, name="test.disabled", label="Disabled"},
		alicorn.Action_State{enabled=false}), "test action should register as disabled")
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 0, "native dispatch must not invoke a disabled action")
	testing.expect(t, rt.trace.sequence == 0, "rejected disabled invocation must not manufacture a causal transaction")
}

@(test)
test_application_can_preempt_text_field_navigation_and_dismissal :: proc(t: ^testing.T) {
	interceptable_keys := [?]Application_Key{
		Application_Key.Up, Application_Key.Down, Application_Key.Page_Up, Application_Key.Page_Down,
		Application_Key.Open_Repository, Application_Key.Open_Command_Palette,
		Application_Key.Find, Application_Key.Workspace_Search, Application_Key.Workspace_Rename,
		Application_Key.Find_Next, Application_Key.Find_Previous,
		Application_Key.Tab_Next, Application_Key.Tab_Previous,
		Application_Key.Zoom_In, Application_Key.Zoom_Out, Application_Key.Zoom_Reset,
		Application_Key.Escape, Application_Key.Return,
	}
	for key in interceptable_keys {
		testing.expect(t, application_key_can_preempt_text_field(key), "transient UI key should be offered before text-field handling")
	}
	normal_keys := [?]Application_Key{Application_Key.Left, Application_Key.Right, Application_Key.Home, Application_Key.End, Application_Key.Fit_Selection}
	for key in normal_keys {
		testing.expect(t, !application_key_can_preempt_text_field(key), "unrelated application key should retain normal routing")
	}
	testing.expect(t, !application_key_can_preempt_text_field(.Escape, true), "Escape must cancel active text composition before transient UI dismissal")
	testing.expect(t, !application_key_can_preempt_text_field(.Workspace_Rename, true), "F2 must not interrupt active text composition")
	testing.expect(t, !application_key_can_preempt_text_field(.Zoom_In, true), "zoom shortcuts must not interrupt active text composition")
	testing.expect(t, native_text_field_return_key(false) == .Return, "plain Enter should retain ordinary text-field return semantics")
	testing.expect(t, native_text_field_return_key(true) == .Find_Previous, "Shift+Enter should route to previous Find match")
}

@(test)
test_menu_description_supports_nested_items_and_states :: proc(t: ^testing.T) {
	children := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(7), label="Checked", state=alicorn.Action_State{enabled=true, checked=true}},
		{kind=.Command, command=Application_Command_ID(8), label="Disabled", state=alicorn.Action_State{enabled=false}},
	}
	items := [?]Application_Menu_Item{
		{kind=.Submenu, label="Recent", state=alicorn.Action_State{enabled=true}, items=children[:]},
		{kind=.Separator},
	}
	menu := Application_Menu{label="File", items=items[:]}
	testing.expect(t, menu.items[0].kind == .Submenu && len(menu.items[0].items) == 2, "menu descriptions must retain nested items")
	testing.expect(t, menu.items[0].items[0].state.checked, "menu descriptions must retain checked state")
	testing.expect(t, !menu.items[0].items[1].state.enabled, "menu descriptions must retain disabled state")
	testing.expect(t, menu.items[1].kind == .Separator, "menu descriptions must retain separators")
	children[0].state.checked = false
	testing.expect(t, !menu.items[0].items[0].state.checked, "applications must be able to update borrowed menu state in place")
}
