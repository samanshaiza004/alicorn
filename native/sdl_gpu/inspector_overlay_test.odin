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

native_inspector_test_button_bounds :: proc(rt: ^alicorn.Runtime, label: string) -> (bounds: alicorn.Rect, found: bool) {
	for id in rt.order {
		node := rt.nodes[id]
		if node.kind == .Button && node.label == label { return node.bounds, true }
	}
	return
}

@(test)
test_native_inspector_horizontal_wheel_matches_application_direction :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&app)
	overlay: Native_Inspector_Overlay
	native_inspector_runtime_init(&overlay, {enabled=true, start_visible=true}, app.viewport)
	defer native_inspector_destroy(&overlay)
	overlay.state.panel_bounds = app.viewport
	ui, ready := alicorn.begin_frame(&overlay.runtime)
	testing.expect(t, ready, "the inspector runtime should be ready for its first description")
	if !ready { return }
	alicorn.container_begin(&ui, .Root, style=alicorn.layout_style(.Column))
	region := alicorn.scroll_region_begin(&ui, viewport_width=240, viewport_height=180, content_width=600, content_height=600,
		line_width=10, line_height=20, axes=.Both, axis_behavior=.Free,
		style=alicorn.layout_style(.Column, width=240, height=180, clip=true))
	alicorn.scroll_region_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	_ = alicorn.scroll_region_set_offset_x(&overlay.runtime, region.id, 100)
	_ = alicorn.scroll_region_set_offset(&overlay.runtime, region.id, 100)
	event := sdl3.Event{type=.MOUSE_WHEEL}
	event.wheel.mouse_x, event.wheel.mouse_y = 20, 20
	event.wheel.x, event.wheel.y, event.wheel.direction = 0.375, -0.625, .FLIPPED
	testing.expect(t, native_inspector_route_event(&overlay, &app, event, {}), "the inspector must own input inside its panel")
	testing.expect(t, alicorn.scroll_region_offset_x(&overlay.runtime, region.id) == 103.75 &&
		alicorn.scroll_region_offset(&overlay.runtime, region.id) == 112.5,
		"inspector scroll regions must apply the same precise axis conversion as application windows")
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
test_native_inspector_routes_input_nonmodally_and_pick_isolates_app :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	button, field := native_inspector_test_source(&app)
	overlay: Native_Inspector_Overlay
	native_inspector_runtime_init(&overlay, Native_Inspector_Options{enabled=true, start_visible=true}, app.viewport)
	defer native_inspector_destroy(&overlay)
	before_frame := app.stats.frames_built
	text_input := Native_Text_Input_State{active=true, owner=field, window_focused=true}
	alicorn.process_text_editing(&app, field, "preedit", 0, 7)
	testing.expect(t, app.nodes[field].composition.active, "the app starts with an active native composition")
	native_inspector_update(&overlay, &app, app.viewport)
	testing.expect(t, native_inspector_visible(&overlay) && !text_input.suspended && native_current_text_input_owner(&app, &text_input) == field,
		"showing the inspector leaves the application text-input owner active")
	testing.expect(t, app.nodes[field].composition.active, "showing the inspector preserves the application's active composition")
	testing.expect(t, !native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_INPUT}, {}) &&
		!native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_EDITING}, {}),
		"text and IME events pass to the app while its editor owns keyboard input")
	testing.expect(t, overlay.runtime.focused != 0, "the inspector owns its own keyboard focus")
	testing.expect(t, !native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P), {}),
		"keys continue to the app until the inspector panel takes keyboard ownership")
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P, false), {})

	app_down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, app.nodes[button].bounds)
	app_up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, app.nodes[button].bounds)
	testing.expect(t, !native_inspector_route_event(&overlay, &app, app_down, {}), "an app-area press passes through the visible inspector")
	_ = alicorn.process_pointer(&app, alicorn.Pointer_Event{kind=.Down, x=app_down.button.x, y=app_down.button.y, button=1})
	testing.expect(t, !native_inspector_route_event(&overlay, &app, app_up, {}), "the app keeps ownership through release after pressing outside the panel")
	_ = alicorn.process_pointer(&app, alicorn.Pointer_Event{kind=.Up, x=app_up.button.x, y=app_up.button.y, button=1})
	testing.expect(t, app.activation_node == button, "the app button activates while the inspector remains visible")

	wheel := sdl3.Event{type=.MOUSE_WHEEL}
	wheel.wheel.mouse_x, wheel.wheel.mouse_y, wheel.wheel.y = 24, 24, -1
	testing.expect(t, !native_inspector_route_event(&overlay, &app, wheel, {}), "wheel input outside the inspector passes through to the app")
	inside_wheel := wheel
	inside_wheel.wheel.mouse_x, inside_wheel.wheel.mouse_y = overlay.state.panel_bounds.x+20, 20
	testing.expect(t, native_inspector_route_event(&overlay, &app, inside_wheel, {}), "wheel input over the inspector scrolls the inspector")

	pick_bounds, pick_found := native_inspector_test_button_bounds(&overlay.runtime, "Pick")
	testing.expect(t, pick_found, "the inspector Pick control is retained in its own runtime")
	pick_down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, pick_bounds)
	pick_up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, pick_bounds)
	app_trace_before_focus_transfer := app.trace.sequence
	testing.expect(t, native_inspector_route_event(&overlay, &app, pick_down, {}, text_input=&text_input),
		"the Pick control receives its press")
	testing.expect(t, overlay.keyboard_owned && text_input.suspended && !app.nodes[field].composition.active,
		"interacting with the panel transfers keyboard ownership and cancels only the app's transient preedit")
	_ = native_inspector_route_event(&overlay, &app, pick_up, {}, text_input=&text_input)
	native_inspector_update(&overlay, &app, app.viewport)
	testing.expect(t, overlay.state.picking, "the inspector Pick button enters Pick mode")
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P), {})
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P, false), {})
	testing.expect(t, !overlay.state.picking, "the inspector-owned P shortcut can disable Pick")
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P), {})
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_P, .P, false), {})
	testing.expect(t, overlay.state.picking, "the inspector-owned P shortcut can re-enable Pick")
	app_captured, app_activation, app_trace := app.captured_node, app.activation_node, app.trace.sequence
	down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, app.nodes[button].bounds)
	up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, app.nodes[button].bounds)
	testing.expect(t, native_inspector_route_event(&overlay, &app, down, {}) && native_inspector_route_event(&overlay, &app, up, {}),
		"picking consumes the complete app click")
	testing.expect(t, overlay.state.selected == button && app.captured_node == app_captured && app.activation_node == app_activation && app.trace.sequence == app_trace,
		"Pick reads app bounds without press, activation, or trace side effects")
	testing.expect(t, !overlay.state.picking, "a successful Pick completes the one-shot selection mode")
	testing.expect(t, native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_INPUT}, {}) &&
		native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_EDITING}, {}),
		"queued app text is drained instead of crossing into the inspector after ownership changes")
	testing.expect(t, !native_inspector_route_event(&overlay, &app, sdl3.Event{type=.WINDOW_RESIZED}, {}) &&
		!native_inspector_route_event(&overlay, &app, sdl3.Event{type=.WINDOW_CLOSE_REQUESTED}, {}) &&
		!native_inspector_route_event(&overlay, &app, sdl3.Event{type=.QUIT}, {}), "native resize and close requests continue through the host while inspecting")
	field_down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, app.nodes[field].bounds)
	field_up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, app.nodes[field].bounds)
	testing.expect(t, !native_inspector_route_event(&overlay, &app, field_down, {}, text_input=&text_input),
		"an ordinary app click returns keyboard ownership to the application")
	_ = alicorn.process_pointer(&app, alicorn.Pointer_Event{kind=.Down, x=field_down.button.x, y=field_down.button.y, button=1})
	testing.expect(t, !native_inspector_route_event(&overlay, &app, field_up, {}, text_input=&text_input),
		"the app gesture remains routed through release")
	_ = alicorn.process_pointer(&app, alicorn.Pointer_Event{kind=.Up, x=field_up.button.x, y=field_up.button.y, button=1})
	app_focus_after_click, app_semantic_after_click := app.focused, app.semantic_focus
	native_inspector_finish_input_pump(&overlay, &text_input)
	testing.expect(t, !text_input.suspended && native_current_text_input_owner(&app, &text_input) == field &&
		!native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_INPUT}, {}),
		"the app text-input owner resumes and receives new text after the ownership handoff drains")
	testing.expect(t, app.trace.sequence >= app_trace_before_focus_transfer, "inspector routing does not damage app causal state")

	panel_rect := alicorn.Rect{overlay.state.panel_bounds.x+8, overlay.state.panel_bounds.y+8, 16, 16}
	panel_down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, panel_rect)
	_ = native_inspector_route_event(&overlay, &app, panel_down, {}, text_input=&text_input)
	testing.expect(t, native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_ESCAPE, .ESCAPE), {}, text_input=&text_input),
		"Escape closes when the inspector owns keyboard input")
	testing.expect(t, native_inspector_route_event(&overlay, &app, sdl3.Event{type=.TEXT_INPUT}, {}), "queued text remains blocked through the closing event pump")
	native_inspector_finish_input_pump(&overlay, &text_input)
	testing.expect(t, !overlay.state.visible && !text_input.suspended && native_current_text_input_owner(&app, &text_input) == field,
		"closing the inspector restores the still-live app text owner")
	testing.expect(t, app.focused == app_focus_after_click && app.semantic_focus == app_semantic_after_click && app.stats.frames_built == before_frame,
		"inspector browsing and closing preserve app focus after ordinary app interactions and never describe the app")
}

@(test)
test_native_inspector_preserves_app_gesture_and_swallows_overlay_release :: proc(t: ^testing.T) {
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
	testing.expect(t, app.captured_node == button, "opening the inspector does not cancel an app-owned gesture")
	testing.expect(t, !native_inspector_route_event(&overlay, &app, up, {}), "the app keeps its gesture through release")
	_ = alicorn.process_pointer(&app, alicorn.Pointer_Event{kind=.Up, x=up.button.x, y=up.button.y, button=1})
	testing.expect(t, app.activation_node == button, "opening the inspector does not suppress the matching app activation")
	native_inspector_update(&overlay, &app, app.viewport)
	panel := alicorn.Rect{overlay.state.panel_bounds.x+8, 8, 16, 16}
	panel_down := native_inspector_test_pointer(.MOUSE_BUTTON_DOWN, panel)
	panel_up := native_inspector_test_pointer(.MOUSE_BUTTON_UP, panel)
	testing.expect(t, native_inspector_route_event(&overlay, &app, panel_down, {}), "the panel captures its own gesture")
	_ = native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_F9, .F9), {})
	testing.expect(t, native_inspector_route_event(&overlay, &app, sdl3.Event{type=.MOUSE_MOTION}, {}),
		"closing during an inspector gesture also swallows its later motion")
	testing.expect(t, native_inspector_route_event(&overlay, &app, panel_up, {}),
		"closing while an inspector gesture is down swallows its later release")
	testing.expect(t, native_inspector_route_event(&overlay, &app, native_inspector_test_key(sdl3.K_F9, .F9), {}), "F9 can reopen the hidden inspector")
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
test_native_inspector_allows_native_menu_dispatch_while_visible :: proc(t: ^testing.T) {
	app := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 650})
	defer alicorn.destroy_runtime(&app)
	state := Menu_Dispatch_Test_State{}
	application := Application{state=rawptr(&state), on_menu_command=menu_dispatch_test_callback}
	overlay := Native_Inspector_Overlay{enabled=true, state=alicorn.Inspector_Overlay{visible=true}}
	menu := Native_Menu_Runtime{application=&application, runtime=&app, inspector=&overlay}
	command := Application_Command_ID(1801)
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1 && state.last_command == command,
		"native application menus remain available while the inspector is visible")
	overlay.state.visible = false
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 2 && state.last_command == command, "native menu dispatch remains available after the inspector closes")
}
