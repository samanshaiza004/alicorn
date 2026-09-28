package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

Native_Text_Input_Probe :: struct {
	events: [dynamic]Application_Text_Input_Event,
	owners: [dynamic]alicorn.Node_ID,
}

native_text_input_probe_callback :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Input_Event,
) {
	probe := cast(^Native_Text_Input_Probe)state
	append(&probe.events, event)
	append(&probe.owners, owner)
}

Native_Text_Key_Probe :: struct {
	events: [dynamic]Application_Text_Key_Event,
	owners: [dynamic]alicorn.Node_ID,
	handled: bool,
}

native_text_key_probe_callback :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Key_Event,
) -> bool {
	probe := cast(^Native_Text_Key_Probe)state
	append(&probe.events, event)
	append(&probe.owners, owner)
	return probe.handled
}

// native_generic_text_input_contract_test exercises the app-facing adapter
// without creating an SDL window. The platform smoke still owns validation of
// actual OS candidate-window behavior and IME focus transitions.
native_generic_text_input_contract_test :: proc() -> bool {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "generic text-input host contract test")
	ui, build := alicorn.begin_frame(&rt)
	if !build { return false }
	alicorn.container_begin(&ui, .Root, label="text-input-test-root")
	owner := alicorn.container_begin_ex(
		&ui,
		.Scroll_Region,
		alicorn.site("native/sdl_gpu/text_input_test.odin", 1, 1, "editor-viewport"),
		label="editor viewport",
		key="editor-viewport",
		explicit_key=true,
		style=alicorn.layout_style(width=280, height=80),
	)
	if !alicorn.text_input_target(&ui, owner) { return false }
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if !alicorn.text_input_target_is_active(&rt, owner) { return false }
	if !alicorn.focus(&rt, owner) { return false }

	probe: Native_Text_Input_Probe
	application := Application{state=rawptr(&probe), on_text_input=native_text_input_probe_callback}
	text_input_state := Native_Text_Input_State{active=true, owner=owner, window_focused=true}
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Preedit, text="日本", selection_start_byte=3, selection_end_byte=6,
	}) { return false }
	if text_input_state.composition_owner != owner { return false }
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Commit, text="日本",
	}) { return false }
	if text_input_state.composition_owner != 0 { return false }
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Preedit,
	}) { return false }
	if text_input_state.composition_owner != 0 { return false }
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Preedit, text="候", selection_start_byte=3, selection_end_byte=3,
	}) { return false }
	if native_current_text_input_owner(&rt, &text_input_state) != owner { return false }
	text_input_state.window_focused = false
	if native_current_text_input_owner(&rt, &text_input_state) != 0 { return false }
	native_cancel_current_text_composition(&application, &rt, &text_input_state, "headless focus-loss test")
	if text_input_state.composition_owner != 0 || len(probe.events) != 5 || len(probe.owners) != 5 { return false }
	if probe.events[0].kind != .Preedit || probe.events[0].text != "日本" ||
		probe.events[0].selection_start_byte != 3 || probe.events[0].selection_end_byte != 6 { return false }
	if probe.events[1].kind != .Commit || probe.events[1].text != "日本" { return false }
	if probe.events[2].kind != .Cancel || probe.events[2].text != "" { return false }
	if probe.events[3].kind != .Preedit || probe.events[3].text != "候" { return false }
	if probe.events[4].kind != .Cancel || probe.events[4].text != "" { return false }
	for event_owner in probe.owners {
		if event_owner != owner { return false }
	}
	input_area := alicorn.Text_Input_Area{rect=alicorn.Rect{12, 18, 2, 20}, cursor_x=1}
	geometry_state := Native_Text_Input_State{last_area=input_area, last_area_valid=true}
	if !native_text_input_area_update_required(&geometry_state, {}, false) { return false }
	geometry_state.last_area_valid = false
	if native_text_input_area_update_required(&geometry_state, {}, false) { return false }
	geometry_state.last_area_valid = true
	if native_text_input_area_update_required(&geometry_state, input_area, true) { return false }
	if !native_text_input_area_update_required(&geometry_state, alicorn.Text_Input_Area{rect=alicorn.Rect{12, 18, 2, 20}, cursor_x=2}, true) { return false }
	return true
}

// native_generic_text_navigation_contract_test checks SDL-to-platform-neutral
// key mapping and the host's focused generic-target routing without SDL init.
native_generic_text_navigation_contract_test :: proc() -> bool {
	left, left_mapped := native_application_text_key_event(sdl3.K_LEFT, {})
	if !left_mapped || left.key != .Left || left.shift || left.control || left.alt || left.super { return false }
	right, right_mapped := native_application_text_key_event(sdl3.K_RIGHT, sdl3.KMOD_SHIFT)
	if !right_mapped || right.key != .Right || !right.shift || right.control || right.alt || right.super { return false }
	home, home_mapped := native_application_text_key_event(sdl3.K_HOME, sdl3.KMOD_CTRL)
	when ODIN_OS == .Darwin {
		if !home_mapped || home.key != .Home || home.shift || !home.control || home.alt || home.super { return false }
	} else {
		if !home_mapped || home.key != .Document_Start || home.shift || !home.control || home.alt || home.super { return false }
	}
	end_event, end_mapped := native_application_text_key_event(sdl3.K_END, sdl3.KMOD_ALT | sdl3.KMOD_GUI)
	when ODIN_OS == .Darwin {
		if !end_mapped || end_event.key != .Document_End || end_event.shift || end_event.control || !end_event.alt || !end_event.super { return false }
	} else {
		if !end_mapped || end_event.key != .End || end_event.shift || end_event.control || !end_event.alt || !end_event.super { return false }
	}
	up, up_mapped := native_application_text_key_event(sdl3.K_UP, sdl3.KMOD_SHIFT)
	if !up_mapped || up.key != .Up || !up.shift { return false }
	down, down_mapped := native_application_text_key_event(sdl3.K_DOWN, {})
	if !down_mapped || down.key != .Down { return false }
	page_up, page_up_mapped := native_application_text_key_event(sdl3.K_PAGEUP, {})
	if !page_up_mapped || page_up.key != .Page_Up { return false }
	page_down, page_down_mapped := native_application_text_key_event(sdl3.K_PAGEDOWN, sdl3.KMOD_SHIFT)
	if !page_down_mapped || page_down.key != .Page_Down || !page_down.shift { return false }
	backspace, backspace_mapped := native_application_text_key_event(sdl3.K_BACKSPACE, sdl3.KMOD_SHIFT)
	if !backspace_mapped || backspace.key != .Backspace || !backspace.shift { return false }
	delete, delete_mapped := native_application_text_key_event(sdl3.K_DELETE, {})
	if !delete_mapped || delete.key != .Delete { return false }
	tab, tab_mapped := native_application_text_key_event(sdl3.K_TAB, sdl3.KMOD_SHIFT)
	if !tab_mapped || tab.key != .Tab || !tab.shift { return false }
	word_modifier := sdl3.KMOD_CTRL if ODIN_OS != .Darwin else sdl3.KMOD_ALT
	word_right, word_right_mapped := native_application_text_key_event(sdl3.K_RIGHT, word_modifier|sdl3.KMOD_SHIFT)
	if !word_right_mapped || word_right.key != .Word_Right || !word_right.shift { return false }
	word_backspace, word_backspace_mapped := native_application_text_key_event(sdl3.K_BACKSPACE, word_modifier)
	if !word_backspace_mapped || word_backspace.key != .Delete_Word_Backward { return false }
	line_modifier := sdl3.KMOD_GUI if ODIN_OS == .Darwin else sdl3.Keymod{}
	line_left, line_left_mapped := native_application_text_key_event(sdl3.K_LEFT, line_modifier)
	if !line_left_mapped || line_left.key != .Line_Start { return false }
	_, unsupported_mapped := native_application_text_key_event(sdl3.K_A, sdl3.KMOD_SHIFT|sdl3.KMOD_CTRL|sdl3.KMOD_ALT|sdl3.KMOD_GUI)
	if unsupported_mapped { return false }

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "generic text-navigation host contract test")
	ui, build := alicorn.begin_frame(&rt)
	if !build { return false }
	alicorn.container_begin(&ui, .Root, label="text-navigation-test-root")
	owner := alicorn.container_begin_ex(
		&ui,
		.Scroll_Region,
		alicorn.site("native/sdl_gpu/text_input_test.odin", 1, 1, "editor-viewport"),
		label="editor viewport",
		key="editor-viewport",
		explicit_key=true,
		style=alicorn.layout_style(width=280, height=80),
	)
	if !alicorn.text_input_target(&ui, owner) { return false }
	alicorn.container_end(&ui)
	field := alicorn.text_field(&ui, "", key=alicorn.key_string("text-field"))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if !alicorn.text_input_target_is_active(&rt, owner) { return false }

	probe := Native_Text_Key_Probe{handled=true}
	application := Application{state=rawptr(&probe), on_text_key=native_text_key_probe_callback}
	if !alicorn.focus(&rt, owner) { return false }
	rt.invalidated = false
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_LEFT, {}) { return false }
	if !rt.invalidated || len(probe.events) != 1 || len(probe.owners) != 1 { return false }
	if probe.owners[0] != owner || probe.events[0] != left { return false }
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_DOWN, {}) { return false }
	if len(probe.events) != 2 || probe.owners[1] != owner || probe.events[1] != down { return false }
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_BACKSPACE, sdl3.KMOD_SHIFT) { return false }
	if len(probe.events) != 3 || probe.owners[2] != owner || probe.events[2] != backspace { return false }
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_DELETE, {}) { return false }
	if len(probe.events) != 4 || probe.owners[3] != owner || probe.events[3] != delete { return false }

	probe.handled = false
	rt.invalidated = false
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_RIGHT, sdl3.KMOD_SHIFT) { return false }
	if rt.invalidated || len(probe.events) != 5 || probe.owners[4] != owner || probe.events[4] != right { return false }

	if !alicorn.focus(&rt, field) { return false }
	rt.invalidated = false
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_HOME, sdl3.KMOD_CTRL) { return false }
	if rt.invalidated || len(probe.events) != 5 { return false }

	rt.focused = 0
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_END, sdl3.KMOD_ALT) { return false }
	if len(probe.events) != 5 { return false }

	rt.focused = owner
	owner_node, owner_found := rt.nodes[owner]
	if !owner_found { return false }
	owner_node.active = false
	rt.nodes[owner] = owner_node
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_END, sdl3.KMOD_ALT) { return false }
	if len(probe.events) != 5 { return false }

	// A generic owner that handles Tab keeps focus. If it declines, the same
	// key falls through to the host's ordinary forward/backward focus traversal.
	owner_node.active = true
	rt.nodes[owner] = owner_node
	probe.handled = true
	if !alicorn.focus(&rt, owner) { return false }
	if !native_dispatch_application_text_key_or_focus_traverse(&application, &rt, sdl3.K_TAB, {}) { return false }
	if rt.focused != owner || len(probe.events) != 6 || probe.events[5].key != .Tab { return false }
	probe.handled = false
	if !native_dispatch_application_text_key_or_focus_traverse(&application, &rt, sdl3.K_TAB, {}) { return false }
	if rt.focused != field || len(probe.events) != 7 { return false }
	if !native_dispatch_application_text_key_or_focus_traverse(&application, &rt, sdl3.K_TAB, sdl3.KMOD_SHIFT) { return false }
	return rt.focused == owner && len(probe.events) == 8
}
