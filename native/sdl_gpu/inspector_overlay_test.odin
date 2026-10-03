package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

native_inspector_test_source :: proc(rt: ^alicorn.Runtime) -> (button, field: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "inspector host test fixture")
	ui, ready := alicorn.begin_frame(rt)
	if !ready { return }
	alicorn.container_begin(&ui, .Root, label="app-root", style=alicorn.layout_style(.Column, padding=8, gap=8))
	_ = alicorn.button(&ui, "App action", style=alicorn.layout_style(width=160, height=32))
	field = alicorn.text_field(&ui, "App text", style=alicorn.layout_style(width=240, height=32))
	_ = alicorn.semantic_bind(&ui, alicorn.Semantic_ID{namespace=18, value=7})
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for id in rt.order { if rt.nodes[id].kind == .Button { button = id } }
	_ = alicorn.semantic_focus_set(rt, alicorn.Semantic_ID{namespace=18, value=7}, field)
	_ = alicorn.focus(rt, field)
	return
}

native_inspector_test_key :: proc(key: sdl3.Keycode, scancode: sdl3.Scancode, down := true) -> sdl3.Event {
	event := sdl3.Event{type=.KEY_DOWN if down else .KEY_UP}
	event.key.key, event.key.scancode, event.key.down = key, scancode, down
	return event
}

native_inspector_test_pointer :: proc(kind: sdl3.EventType, bounds: alicorn.Rect) -> sdl3.Event {
	event := sdl3.Event{type=kind}
	event.button.x, event.button.y = bounds.x+bounds.w/2, bounds.y+bounds.h/2
	event.button.button, event.button.clicks = 1, 1
	event.button.down = kind == .MOUSE_BUTTON_DOWN
	return event
}

@(test)
test_native_inspector_requires_explicit_host_opt_in :: proc(t: ^testing.T) {
	none := [?]string{"application", "--diagnostics"}
	hidden := [?]string{"application", "--inspector"}
	visible := [?]string{"application", "--inspector-open"}
	fixture := [?]string{"application", "--inspector-fixture"}
	testing.expect(t, !native_inspector_options(none[:]).enabled, "diagnostics alone must not opt in to the visual inspector")
	testing.expect(t, native_inspector_options(hidden[:]).enabled && !native_inspector_options(hidden[:]).start_visible,
		"--inspector enables a hidden overlay with F9 ownership")
	testing.expect(t, native_inspector_options(visible[:]).enabled && native_inspector_options(visible[:]).start_visible,
		"--inspector-open opts in and starts visible")
	testing.expect(t, native_inspector_options(fixture[:]).enabled, "the native inspector fixture must enable the same reusable host")
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	overlay: Native_Inspector_Overlay
	native_inspector_runtime_init(&overlay, {}, app.viewport)
	testing.expect(t, !overlay.runtime_ready && !native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_F9, .F9), {}),
		"an ordinary Application neither allocates inspector retained state nor reserves F9")
}

@(test)
test_native_inspector_owns_input_and_pick_without_mutating_app_focus :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	button, field := native_inspector_test_source(&app)
	overlay: Native_Inspector_Overlay
	native_inspector_runtime_init(&overlay, Native_Inspector_Options{enabled=true}, app.viewport)
	defer native_inspector_destroy(&overlay)
	before_focus, before_semantic, before_frame := app.focused, app.semantic_focus, app.stats.frames_built
	text_input := Native_Text_Input_State{active=true, owner=field, window_focused=true}
	alicorn.process_text_editing(&app, field, "preedit", 0, 7)
	testing.expect(t, app.nodes[field].composition.active, "the app starts with an active native composition")
	testing.expect(t, native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_F9, .F9), {}, text_input=&text_input),
		"F9 must be consumed before app shortcuts")
	native_inspector_finish_input_pump(&overlay, &text_input)
	native_inspector_update(&overlay, &app, app.viewport)
	testing.expect(t, native_inspector_visible(&overlay) && text_input.suspended && native_current_text_input_owner(&app, &text_input) == 0,
		"inspector input ownership suspends the platform owner while preserving app focus")
	testing.expect(t, !app.nodes[field].composition.active && app.nodes[field].text == "App text", "opening cancels transient preedit without committing it to app text")
	testing.expect(t, overlay.runtime.focused != 0, "the inspector owns its own keyboard focus")
	testing.expect(t, native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P), {}), "P enters inspector Pick mode")
	app_captured, app_activation, app_trace := app.captured_node, app.activation_node, app.trace.sequence
	down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, app.nodes[button].bounds)
	up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, app.nodes[button].bounds)
	testing.expect(t, native_inspector_route_event(&overlay, &app, down, {}) && native_inspector_route_event(&overlay, &app, up, {}),
		"picking consumes the complete app click")
	testing.expect(t, overlay.state.selected == button && app.captured_node == app_captured && app.activation_node == app_activation && app.trace.sequence == app_trace,
		"Pick reads app bounds without press, activation, or trace side effects")
	wheel := sdl3.Event{type=.MOUSE_WHEEL}
	wheel.wheel.mouse_x, wheel.wheel.mouse_y, wheel.wheel.y = 24, 24, -1
	testing.expect(t, native_inspector_route_event(&overlay, &app, wheel, {}), "wheel input belongs to the separate inspector runtime")
	testing.expect(t, native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_INPUT}, {}) &&
		native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_EDITING}, {}), "queued text and preedit never enter the app while visible")
	testing.expect(t, !native_inspector_route_event(&overlay, &app, sdl3.Event{type=.WINDOW_RESIZED}, {}) &&
		!native_inspector_route_event(&overlay, &app, sdl3.Event{type=.WINDOW_CLOSE_REQUESTED}, {}) &&
		!native_inspector_route_event(&overlay, &app, sdl3.Event{type=.QUIT}, {}), "native resize and close requests continue through the host while inspecting")
	testing.expect(t, native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_ESCAPE, .ESCAPE), {}, text_input=&text_input),
		"Escape closes before app key routing")
	testing.expect(t, native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_INPUT}, {}), "queued text remains blocked through the closing event pump")
	native_inspector_finish_input_pump(&overlay, &text_input)
	testing.expect(t, !overlay.state.visible && !text_input.suspended && native_current_text_input_owner(&app, &text_input) == field,
		"draining the close pump restores the still-live app text owner")
	testing.expect(t, app.focused == before_focus && app.semantic_focus == before_semantic && app.stats.frames_built == before_frame,
		"inspector browsing and closing preserve app keyboard/semantic focus and never describe the app")
}

@(test)
test_native_inspector_swallow_gesture_release_after_close :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	button, _ := native_inspector_test_source(&app)
	overlay: Native_Inspector_Overlay
	native_inspector_runtime_init(&overlay, Native_Inspector_Options{enabled=true}, app.viewport)
	defer native_inspector_destroy(&overlay)
	down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, app.nodes[button].bounds)
	up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, app.nodes[button].bounds)
	testing.expect(t, !native_inspector_route_event(&overlay, &app, down, {}), "hidden inspector permits a fresh app gesture")
	_ = alicorn.process_pointer(&app, alicorn.Pointer_Event{kind=.Down, x=down.button.x, y=down.button.y, button=1})
	testing.expect(t, app.captured_node == button, "the app initially owns the captured press")
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_F9, .F9), {})
	testing.expect(t, app.captured_node == 0 && app.activation_node == 0, "opening cancels an app press before taking input ownership")
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_RETURN, .RETURN), {})
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_ESCAPE, .ESCAPE), {})
	testing.expect(t, native_inspector_route_event(&overlay, &app, up, {}), "the captured gesture release remains consumed after Escape closes")
	testing.expect(t, native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_RETURN, .RETURN, false), {}),
		"the inspector's held key release remains consumed after close")
	testing.expect(t, !native_inspector_route_event(&overlay, &app, down, {}), "a new gesture after the swallowed release returns to the app")
}

@(test)
test_native_inspector_submit_refresh_converges_and_hard_error_sleeps :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	_, _ = native_inspector_test_source(&app)
	overlay: Native_Inspector_Overlay
	native_inspector_runtime_init(&overlay, Native_Inspector_Options{enabled=true, start_visible=true}, app.viewport)
	defer native_inspector_destroy(&overlay)
	native_inspector_update(&overlay, &app, app.viewport)
	alicorn.frame_submission_succeeded(&app)
	app.stats.gpu_submits += 1
	native_inspector_submission_succeeded(&overlay)
	native_inspector_update(&overlay, &app, app.viewport)
	testing.expect(t, native_inspector_submission_pending(&overlay), "an app submit can refresh inspector work/cause truth once")
	native_inspector_submission_succeeded(&overlay)
	settled_builds, settled_app_trace, settled_app_frames := overlay.builds, app.trace.sequence, app.stats.frames_built
	for attempt in 0..<5 { native_inspector_update(&overlay, &app, app.viewport) }
	testing.expect(t, overlay.builds == settled_builds && !native_inspector_submission_pending(&overlay),
		"an open inspector over unchanged source does not rebuild or schedule another GPU frame")
	testing.expect(t, app.trace.sequence == settled_app_trace && app.stats.frames_built == settled_app_frames,
		"inspector submission does not feed app traces or description counters")
	app.hard_error, app.invalidated = true, true
	testing.expect(t, native_application_has_pending_work(&app), "applications without inspector opt-in retain their existing hard-error scheduling behavior")
	timing: Native_Host_Timing
	metrics := Window_Metrics{logical_width=1000, logical_height=650, display_scale=1}
	application := Application{}
	result := native_application_build_until_stable(&application, &app, &metrics, &timing, stop_on_hard_error=true)
	testing.expect(t, result.passes == 0 && result.stable && !native_application_has_pending_work(&app, suspend_hard_error=true),
		"a hard error with pending description stops retrying the app and permits native idle")
	native_inspector_update(&overlay, &app, app.viewport)
	testing.expect(t, !overlay.runtime.hard_error && native_inspector_submission_pending(&overlay), "the separate inspector remains usable for an app hard error")
	native_inspector_submission_succeeded(&overlay)
	native_inspector_update(&overlay, &app, app.viewport)
	testing.expect(t, !native_inspector_submission_pending(&overlay), "inspecting a hard error converges to idle")
}

@(test)
test_native_inspector_blocks_native_menu_semantic_dispatch :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	state := Menu_Dispatch_Test_State{}
	application := Application{state=rawptr(&state), on_menu_command=menu_dispatch_test_callback}
	overlay := Native_Inspector_Overlay{enabled=true, state=alicorn.Inspector_Overlay{visible=true}}
	menu := Native_Menu_Runtime{application=&application, runtime=&app, inspector=&overlay}
	command := Application_Command_ID(1801)
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 0 && app.trace.sequence == 0, "native menu transport must not bypass inspector input ownership")
	overlay.state.visible = false
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1 && state.last_command == command, "fresh native menu commands resume when the inspector closes")
}
