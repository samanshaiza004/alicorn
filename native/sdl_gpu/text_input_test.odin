package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

native_text_paint_span_contract_test :: proc() -> Native_Validation_Result {
	red := alicorn.Color{1, 0, 0, 1}
	green := alicorn.Color{0, 1, 0, 1}
	blue := alicorn.Color{0, 0, 1, 1}
	spans := []alicorn.Text_Paint_Span{
		{start=0, end=4, color=red, color_set=true},
		{start=2, end=5, color=blue, color_set=true},
		{start=1, end=3, color=green, color_set=true},
		{start=0, end=6, underline=true},
	}
	winners := native_text_span_winners("abcdef", spans)
	defer delete(winners, context.temp_allocator)
	if len(winners) != 6 || winners[0] != 0 || winners[1] != 2 || winners[2] != 2 || winners[3] != 1 || winners[4] != 1 || winners[5] != -1 { return native_validation_failed() }
	if native_text_color_for_cluster(spans, winners, 1, 2, alicorn.Color{}) != green ||
		native_text_color_for_cluster(spans, winners, 3, 4, alicorn.Color{}) != blue ||
		native_text_color_for_cluster(spans, winners, 5, 6, red) != red ||
		native_text_color_for_cluster(spans, winners, 1, 4, red) != green ||
		native_text_color_for_cluster(spans, winners, 1, 4, red) != alicorn.text_paint_color_for_cluster(spans, 1, 4, red) ||
		native_text_color_for_cluster(spans, winners, 3, 4, red) != alicorn.text_paint_color_for_cluster(spans, 3, 4, red) ||
		len(native_text_span_winners("abcdef", []alicorn.Text_Paint_Span{{start=0, end=6, underline=true}})) != 0 {
		return native_validation_failed()
	}
	unicode_spans := []alicorn.Text_Paint_Span{{start=2, end=4, color=blue, color_set=true}}
	unicode_winners := native_text_span_winners("Aéfi", unicode_spans)
	defer delete(unicode_winners, context.temp_allocator)
	if native_text_color_for_cluster(unicode_spans, unicode_winners, 1, 4, red) == blue &&
		native_text_color_for_cluster(unicode_spans, unicode_winners, 5, 6, red) == red { return Native_Validation_Result{ok=true} }
	return native_validation_failed()
}

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

Native_Text_Input_Suspension_Probe :: struct {
	commits: u64,
}

native_text_input_suspend_after_commit_callback :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Input_Event,
) {
	probe := cast(^Native_Text_Input_Suspension_Probe)state
	if event.kind == .Commit {
		probe.commits += 1
		_ = alicorn.text_input_target_set_suspended(rt, owner, true)
	}
}

Native_Text_Key_Probe :: struct {
	events: [dynamic]Application_Text_Key_Event,
	owners: [dynamic]alicorn.Node_ID,
	application_keys: [dynamic]Application_Key,
	handled: bool,
	application_key_handled: bool,
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

native_application_key_probe_callback :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	key: Application_Key,
) -> bool {
	probe := cast(^Native_Text_Key_Probe)state
	append(&probe.application_keys, key)
	return probe.application_key_handled
}

// native_generic_text_input_contract_test exercises the app-facing adapter
// without creating an SDL window. The platform smoke still owns validation of
// actual OS candidate-window behavior and IME focus transitions.
native_generic_text_input_contract_test :: proc() -> Native_Validation_Result {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "generic text-input host contract test")
	ui, build := alicorn.begin_frame(&rt)
	if !build { return native_validation_failed() }
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
	if !alicorn.text_input_target(&ui, owner) { return native_validation_failed() }
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if !alicorn.text_input_target_is_active(&rt, owner) { return native_validation_failed() }
	if !alicorn.focus(&rt, owner) { return native_validation_failed() }

	probe: Native_Text_Input_Probe
	application := Application{state=rawptr(&probe), on_text_input=native_text_input_probe_callback}
	text_input_state := Native_Text_Input_State{active=true, owner=owner, window_focused=true}
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Preedit, text="日本", selection_start_byte=3, selection_end_byte=6,
	}) { return native_validation_failed() }
	if text_input_state.composition_owner != owner { return native_validation_failed() }
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Commit, text="日本",
	}) { return native_validation_failed() }
	if text_input_state.composition_owner != 0 { return native_validation_failed() }
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Preedit,
	}) { return native_validation_failed() }
	if text_input_state.composition_owner != 0 { return native_validation_failed() }
	if !native_dispatch_generic_text_input_event(&application, &rt, &text_input_state, Application_Text_Input_Event{
		kind=.Preedit, text="候", selection_start_byte=3, selection_end_byte=3,
	}) { return native_validation_failed() }
	if native_current_text_input_owner(&rt, &text_input_state) != owner { return native_validation_failed() }
	text_input_state.window_focused = false
	if native_current_text_input_owner(&rt, &text_input_state) != 0 { return native_validation_failed() }
	native_cancel_current_text_composition(&application, &rt, &text_input_state, "headless focus-loss test")
	if text_input_state.composition_owner != 0 || len(probe.events) != 5 || len(probe.owners) != 5 { return native_validation_failed() }
	if probe.events[0].kind != .Preedit || probe.events[0].text != "日本" ||
		probe.events[0].selection_start_byte != 3 || probe.events[0].selection_end_byte != 6 { return native_validation_failed() }
	if probe.events[1].kind != .Commit || probe.events[1].text != "日本" { return native_validation_failed() }
	if probe.events[2].kind != .Cancel || probe.events[2].text != "" { return native_validation_failed() }
	if probe.events[3].kind != .Preedit || probe.events[3].text != "候" { return native_validation_failed() }
	if probe.events[4].kind != .Cancel || probe.events[4].text != "" { return native_validation_failed() }
	for event_owner in probe.owners {
		if event_owner != owner { return native_validation_failed() }
	}
	// A callback can suspend its retained target before the host's post-event
	// focus sync. The target becomes ineligible immediately, so already-queued
	// TEXT_INPUT/TEXT_EDITING events are rejected; clearing suspension makes it
	// eligible for the host to start again on that same post-event sync.
	eligibility_state := Native_Text_Input_State{active=true, owner=owner, window_focused=true}
	suspension_probe: Native_Text_Input_Suspension_Probe
	suspension_application := Application{
		state=rawptr(&suspension_probe),
		on_text_input=native_text_input_suspend_after_commit_callback,
	}
	if !native_dispatch_generic_text_input_event(&suspension_application, &rt, &eligibility_state, Application_Text_Input_Event{
		kind=.Commit, text="fill recovery buffer",
	}) { return native_validation_failed() }
	if suspension_probe.commits != 1 || !alicorn.text_input_target_is_suspended(&rt, owner) { return native_validation_failed() }
	if native_text_input_owner_is_valid(&rt, owner) || native_current_text_input_owner(&rt) != 0 { return native_validation_failed() }
	if native_dispatch_generic_text_input_event(&suspension_application, &rt, &eligibility_state, Application_Text_Input_Event{
		kind=.Commit, text="must be rejected while suspended",
	}) { return native_validation_failed() }
	if suspension_probe.commits != 1 || len(probe.events) != 5 { return native_validation_failed() }
	if !alicorn.text_input_target_set_suspended(&rt, owner, false) { return native_validation_failed() }
	if alicorn.text_input_target_is_suspended(&rt, owner) || !native_text_input_owner_is_valid(&rt, owner) ||
		native_current_text_input_owner(&rt) != owner { return native_validation_failed() }
	if !native_dispatch_generic_text_input_event(&suspension_application, &rt, &eligibility_state, Application_Text_Input_Event{
		kind=.Commit, text="resumed",
	}) { return native_validation_failed() }
	if suspension_probe.commits != 2 || !alicorn.text_input_target_is_suspended(&rt, owner) { return native_validation_failed() }
	input_area := alicorn.Text_Input_Area{rect=alicorn.Rect{12, 18, 2, 20}, cursor_x=1}
	geometry_state := Native_Text_Input_State{last_area=input_area, last_area_valid=true}
	if !native_text_input_area_update_required(&geometry_state, {}, false) { return native_validation_failed() }
	geometry_state.last_area_valid = false
	if native_text_input_area_update_required(&geometry_state, {}, false) { return native_validation_failed() }
	geometry_state.last_area_valid = true
	if native_text_input_area_update_required(&geometry_state, input_area, true) { return native_validation_failed() }
	if !native_text_input_area_update_required(&geometry_state, alicorn.Text_Input_Area{rect=alicorn.Rect{12, 18, 2, 20}, cursor_x=2}, true) { return native_validation_failed() }
	return Native_Validation_Result{ok=true}
}

// native_generic_text_navigation_contract_test checks SDL-to-platform-neutral
// key mapping and the host's focused generic-target routing without SDL init.
native_generic_text_navigation_contract_test :: proc() -> Native_Validation_Result {
	left, left_mapped := native_application_text_key_event(sdl3.K_LEFT, {})
	if !left_mapped || left.key != .Left || left.shift || left.control || left.alt || left.super { return native_validation_failed() }
	right, right_mapped := native_application_text_key_event(sdl3.K_RIGHT, sdl3.KMOD_SHIFT)
	if !right_mapped || right.key != .Right || !right.shift || right.control || right.alt || right.super { return native_validation_failed() }
	home, home_mapped := native_application_text_key_event(sdl3.K_HOME, sdl3.KMOD_CTRL)
	when ODIN_OS == .Darwin {
		if !home_mapped || home.key != .Home || home.shift || !home.control || home.alt || home.super { return native_validation_failed() }
	} else {
		if !home_mapped || home.key != .Document_Start || home.shift || !home.control || home.alt || home.super { return native_validation_failed() }
	}
	end_event, end_mapped := native_application_text_key_event(sdl3.K_END, sdl3.KMOD_ALT | sdl3.KMOD_GUI)
	when ODIN_OS == .Darwin {
		if !end_mapped || end_event.key != .Document_End || end_event.shift || end_event.control || !end_event.alt || !end_event.super { return native_validation_failed() }
	} else {
		if !end_mapped || end_event.key != .End || end_event.shift || end_event.control || !end_event.alt || !end_event.super { return native_validation_failed() }
	}
	up, up_mapped := native_application_text_key_event(sdl3.K_UP, sdl3.KMOD_SHIFT)
	if !up_mapped || up.key != .Up || !up.shift { return native_validation_failed() }
	down, down_mapped := native_application_text_key_event(sdl3.K_DOWN, {})
	if !down_mapped || down.key != .Down { return native_validation_failed() }
	page_up, page_up_mapped := native_application_text_key_event(sdl3.K_PAGEUP, {})
	if !page_up_mapped || page_up.key != .Page_Up { return native_validation_failed() }
	page_down, page_down_mapped := native_application_text_key_event(sdl3.K_PAGEDOWN, sdl3.KMOD_SHIFT)
	if !page_down_mapped || page_down.key != .Page_Down || !page_down.shift { return native_validation_failed() }
	backspace, backspace_mapped := native_application_text_key_event(sdl3.K_BACKSPACE, sdl3.KMOD_SHIFT)
	if !backspace_mapped || backspace.key != .Backspace || !backspace.shift { return native_validation_failed() }
	delete, delete_mapped := native_application_text_key_event(sdl3.K_DELETE, {})
	if !delete_mapped || delete.key != .Delete { return native_validation_failed() }
	tab, tab_mapped := native_application_text_key_event(sdl3.K_TAB, sdl3.KMOD_SHIFT)
	if !tab_mapped || tab.key != .Tab || !tab.shift { return native_validation_failed() }
	word_modifier := sdl3.KMOD_CTRL if ODIN_OS != .Darwin else sdl3.KMOD_ALT
	word_right, word_right_mapped := native_application_text_key_event(sdl3.K_RIGHT, word_modifier|sdl3.KMOD_SHIFT)
	if !word_right_mapped || word_right.key != .Word_Right || !word_right.shift { return native_validation_failed() }
	word_backspace, word_backspace_mapped := native_application_text_key_event(sdl3.K_BACKSPACE, word_modifier)
	if !word_backspace_mapped || word_backspace.key != .Delete_Word_Backward { return native_validation_failed() }
	when ODIN_OS == .Darwin {
		line_left, line_left_mapped := native_application_text_key_event(sdl3.K_LEFT, sdl3.KMOD_GUI)
		if !line_left_mapped || line_left.key != .Line_Start { return native_validation_failed() }
		line_right, line_right_mapped := native_application_text_key_event(sdl3.K_RIGHT, sdl3.KMOD_GUI)
		if !line_right_mapped || line_right.key != .Line_End { return native_validation_failed() }
	} else {
		line_left, line_left_mapped := native_application_text_key_event(sdl3.K_HOME, {})
		if !line_left_mapped || line_left.key != .Home { return native_validation_failed() }
		line_right, line_right_mapped := native_application_text_key_event(sdl3.K_END, {})
		if !line_right_mapped || line_right.key != .End { return native_validation_failed() }
	}
	_, unsupported_mapped := native_application_text_key_event(sdl3.K_A, sdl3.KMOD_SHIFT|sdl3.KMOD_CTRL|sdl3.KMOD_ALT|sdl3.KMOD_GUI)
	if unsupported_mapped { return native_validation_failed() }

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "generic text-navigation host contract test")
	ui, build := alicorn.begin_frame(&rt)
	if !build { return native_validation_failed() }
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
	if !alicorn.text_input_target(&ui, owner) { return native_validation_failed() }
	alicorn.container_end(&ui)
	field := alicorn.text_field(&ui, "", key=alicorn.key_string("text-field"))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if !alicorn.text_input_target_is_active(&rt, owner) { return native_validation_failed() }

	probe := Native_Text_Key_Probe{handled=true}
	application := Application{
		state=rawptr(&probe),
		on_text_key=native_text_key_probe_callback,
		on_key=native_application_key_probe_callback,
	}
	if !alicorn.focus(&rt, owner) { return native_validation_failed() }
	rt.invalidated = false
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_LEFT, {}) { return native_validation_failed() }
	if !rt.invalidated || len(probe.events) != 1 || len(probe.owners) != 1 { return native_validation_failed() }
	if probe.owners[0] != owner || probe.events[0] != left { return native_validation_failed() }
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_DOWN, {}) { return native_validation_failed() }
	if len(probe.events) != 2 || probe.owners[1] != owner || probe.events[1] != down { return native_validation_failed() }
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_BACKSPACE, sdl3.KMOD_SHIFT) { return native_validation_failed() }
	if len(probe.events) != 3 || probe.owners[2] != owner || probe.events[2] != backspace { return native_validation_failed() }
	if !native_dispatch_application_text_key(&application, &rt, sdl3.K_DELETE, {}) { return native_validation_failed() }
	if len(probe.events) != 4 || probe.owners[3] != owner || probe.events[3] != delete { return native_validation_failed() }

	probe.handled = false
	rt.invalidated = false
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_RIGHT, sdl3.KMOD_SHIFT) { return native_validation_failed() }
	if rt.invalidated || len(probe.events) != 5 || probe.owners[4] != owner || probe.events[4] != right { return native_validation_failed() }

	if !alicorn.focus(&rt, field) { return native_validation_failed() }
	rt.invalidated = false
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_HOME, sdl3.KMOD_CTRL) { return native_validation_failed() }
	if rt.invalidated || len(probe.events) != 5 { return native_validation_failed() }

	rt.focused = 0
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_END, sdl3.KMOD_ALT) { return native_validation_failed() }
	if len(probe.events) != 5 { return native_validation_failed() }

	rt.focused = owner
	owner_node, owner_found := rt.nodes[owner]
	if !owner_found { return native_validation_failed() }
	owner_node.active = false
	rt.nodes[owner] = owner_node
	if native_dispatch_application_text_key(&application, &rt, sdl3.K_END, sdl3.KMOD_ALT) { return native_validation_failed() }
	if len(probe.events) != 5 { return native_validation_failed() }

	// A generic owner that handles Tab keeps focus. If it declines, the same
	// key falls through to the host's ordinary forward/backward focus traversal.
	owner_node.active = true
	rt.nodes[owner] = owner_node
	probe.handled = true
	if !alicorn.focus(&rt, owner) { return native_validation_failed() }
	probe.application_key_handled = true
	if !native_dispatch_application_text_key_or_focus_traverse(
		&application, &rt, sdl3.K_TAB, sdl3.KMOD_CTRL,
	) { return native_validation_failed() }
	if rt.focused != owner || len(probe.events) != 5 || len(probe.application_keys) != 1 ||
		probe.application_keys[0] != .Tab_Next {
		return native_validation_failed()
	}
	probe.application_key_handled = false
	if !native_dispatch_application_text_key_or_focus_traverse(
		&application, &rt, sdl3.K_TAB, sdl3.KMOD_CTRL|sdl3.KMOD_SHIFT,
	) { return native_validation_failed() }
	if rt.focused != owner || len(probe.events) != 5 || len(probe.application_keys) != 2 ||
		probe.application_keys[1] != .Tab_Previous {
		return native_validation_failed()
	}

	probe.application_key_handled = true
	if !alicorn.focus(&rt, field) { return native_validation_failed() }
	field_before, field_before_found := alicorn.text_field_value(&rt, field)
	if !field_before_found { return native_validation_failed() }
	if !native_dispatch_application_text_key_or_focus_traverse(
		&application, &rt, sdl3.K_TAB, sdl3.KMOD_CTRL,
	) { return native_validation_failed() }
	field_after, field_after_found := alicorn.text_field_value(&rt, field)
	if rt.focused != field || !field_after_found || field_after != field_before ||
		len(probe.events) != 5 || len(probe.application_keys) != 3 ||
		probe.application_keys[2] != .Tab_Next {
		return native_validation_failed()
	}

	// The host consumes the chord even when no application callback exists, so
	// it can never degrade into a plain Tab focus traversal.
	application.on_key = nil
	if !native_dispatch_application_text_key_or_focus_traverse(
		&application, &rt, sdl3.K_TAB, sdl3.KMOD_CTRL,
	) || rt.focused != field || len(probe.events) != 5 {
		return native_validation_failed()
	}
	application.on_key = native_application_key_probe_callback
	if !alicorn.focus(&rt, owner) { return native_validation_failed() }
	probe.handled = true
	if !native_dispatch_application_text_key_or_focus_traverse(&application, &rt, sdl3.K_TAB, {}) { return native_validation_failed() }
	if rt.focused != owner || len(probe.events) != 6 || probe.events[5].key != .Tab { return native_validation_failed() }
	probe.handled = false
	if !native_dispatch_application_text_key_or_focus_traverse(&application, &rt, sdl3.K_TAB, {}) { return native_validation_failed() }
	if rt.focused != field || len(probe.events) != 7 { return native_validation_failed() }
	if !native_dispatch_application_text_key_or_focus_traverse(&application, &rt, sdl3.K_TAB, sdl3.KMOD_SHIFT) { return native_validation_failed() }
	// The built-in Text_Field handles its own text keys, so Shift+Tab should
	// traverse back without delivering another generic application key event.
	if rt.focused == owner && len(probe.events) == 7 { return Native_Validation_Result{ok=true} }
	return native_validation_failed()
}
