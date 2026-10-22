package alicorn

import "core:testing"
import "core:fmt"

SELECT_TEST_OPTIONS :: [4]Select_Option{
	{key=10, label="Alpha"},
	{key=20, label="Beta"},
	{key=30, label="Charlie"},
	{key=40, label="Unavailable", disabled=true},
}

select_test_build :: proc(rt: ^Runtime) -> (result: Select_Result, trigger: Node_ID) {
	if !rt.invalidated { invalidate_root(rt, "select test rebuild") }
	ui, build := begin_frame(rt)
	if !build { return }
	options := SELECT_TEST_OPTIONS
	container_begin_simple(&ui, .Root, label="select-test-root", key=key_string("root"), style=layout_style(.Column, width=300, height=240, gap=8, padding=10))
	result = select_control(
		&ui,
		key_string("appearance-theme"),
		"Theme",
		options[:],
		20,
	)
	trigger = rt.pending[len(rt.pending)-1].description.id
	container_end(&ui)
	end_frame(&ui)
	return
}

select_test_open :: proc(rt: ^Runtime) -> (trigger: Node_ID) {
	_, trigger = select_test_build(rt)
	if trigger == 0 { return }
	if node, ok := rt.nodes[trigger]; ok {
		x := node.bounds.x+node.bounds.w/2
		y := node.bounds.y+node.bounds.h/2
		_ = process_pointer(rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
		_ = process_pointer(rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	}
	_, trigger = select_test_build(rt)
	return
}

select_test_row :: proc(rt: ^Runtime, label: string) -> Node_ID {
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.active && node.kind == .Button && node.label == label && node.parent != 0 {
			if parent, parent_ok := rt.nodes[node.parent]; parent_ok && parent.kind == .Virtual_List { return id }
		}
	}
	return 0
}

@(test)
test_select_opens_anchored_listbox_with_theme_semantics_and_selected_focus :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 240})
	defer destroy_runtime(&rt)
	_, trigger := select_test_build(&rt)
	if trigger == 0 { testing.expect(t, false, "Select trigger should be retained"); return }
	before := rt.nodes[trigger].bounds
	testing.expect(t, rt.nodes[trigger].label == "Beta" && rt.nodes[trigger].icon_id == .Chevron_Down,
		"the Select trigger should keep its value text separate from a font-independent chevron icon")
	trigger_icon_seen := false
	for command in rt.nodes[trigger].paint {
		if icon, ok := command.payload.(Icon_Paint); ok && icon.id == .Chevron_Down { trigger_icon_seen = true }
	}
	testing.expect(t, trigger_icon_seen, "the Select trigger should retain a separate vector chevron paint command")
	trigger_semantic, found := semantic_node_lookup(&rt, semantic_visual_id(trigger))
	testing.expect(t, found && trigger_semantic.role == .Combo_Box && trigger_semantic.label == "Theme" && trigger_semantic.value == "Beta",
		"closed trigger semantics should expose the field name and selected value")

	opened_trigger := select_test_open(&rt)
	testing.expect(t, opened_trigger == trigger && context_menu_is_open(&rt), "pointer activation should open the Select-owned popup")
	testing.expect(t, rt.nodes[trigger].bounds == before, "opening a Select overlay must not move the ordinary workbench geometry")
	testing.expect(t, select_wants_text_input(&rt), "the open listbox should request native text input for type-ahead")

	first := select_test_row(&rt, "Alpha")
	selected := select_test_row(&rt, "Beta")
	last := select_test_row(&rt, "Charlie")
	disabled := select_test_row(&rt, "Unavailable")
	testing.expect(t, first != 0 && selected != 0 && last != 0 && disabled != 0, "all bounded option rows should be present in the retained popup")
	testing.expect(t, rt.focused == selected, "opening should focus the selected enabled option")
	panel := rt.nodes[rt.context_menu.panel]
	testing.expect(t, panel.bounds.x >= rt.viewport.x && panel.bounds.y >= rt.viewport.y &&
		panel.bounds.x+panel.bounds.w <= rt.viewport.x+rt.viewport.w && panel.bounds.y+panel.bounds.h <= rt.viewport.y+rt.viewport.h,
		"the anchored panel should flip or clamp inside the viewport")

	listbox, listbox_found := semantic_node_lookup(&rt, rt.select.list_semantic_id)
	option, option_found := semantic_node_lookup(&rt, rt.select.option_semantic_ids[1])
	testing.expect(t, listbox_found && listbox.role == .List_Box && listbox.parent == semantic_visual_id(trigger) &&
		listbox.selected_id == rt.select.option_semantic_ids[1] && listbox.logical_count == 4,
		"the popup should publish a named List_Box related to the Combo_Box")
	testing.expect(t, option_found && option.role == .List_Box_Option && semantic_states_has(option.states, .Selected) &&
		semantic_actions_has(option.actions, .Select),
		"the controlled selected value should be a selectable, selected option")
}

@(test)
test_select_coexists_above_notices_and_outside_click_dismisses_only_select :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 240})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "overlay precedence fixture should load its UI font")
		return
	}
	retry := [1]Notice_Action{{id=Action_ID(991), label="Retry"}}
	notice := Notice{
		id="select-overlap-test",
		title="Folder needs refresh",
		message="The folder contents may be out of date.",
		severity=.Warning,
		lifetime=.Persistent,
		placement=.Toast,
		actions=retry[:],
	}
	testing.expect(t, notice_post(&rt, notice, 1), "the persistent actionable toast should post")
	trigger := select_test_open(&rt)
	if trigger == 0 { testing.expect(t, false, "the Select trigger should open"); return }
	notice_card := notice_test_find_node(&rt, "notice-card")
	panel := context_menu_test_find(&rt, "context-menu-panel", .Context_Menu_Panel)
	option := select_test_row(&rt, "Alpha")
	if notice_card == 0 || panel == 0 || option == 0 {
		testing.expect(t, false, "the toast and Select popup should both remain retained while Select is open")
		return
	}
	card_bounds, panel_bounds := rt.nodes[notice_card].bounds, rt.nodes[panel].bounds
	overlap := rect_intersection(card_bounds, panel_bounds)
	testing.expect(t, overlap.w > 0 && overlap.h > 0,
		"the fixture should exercise actual overlap between the toast and anchored popup")
	option_bounds := rt.nodes[option].bounds
	target := hit_test(&rt, option_bounds.x+option_bounds.w/2, option_bounds.y+option_bounds.h/2)
	testing.expect(t, target == option,
		"the Select listbox should own pointer input above overlapping notice content")

	close := notice_test_find_node(&rt, "", .Button)
	if close == 0 { testing.expect(t, false, "the notice should retain an accessible close button"); return }
	close_bounds := rt.nodes[close].bounds
	x, y := close_bounds.x+close_bounds.w/2, close_bounds.y+close_bounds.h/2
	if !rect_contains(panel_bounds, x, y) {
		outside_target := process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
		testing.expect(t, outside_target == rt.context_menu.overlay && !context_menu_is_open(&rt),
			"pressing the notice behind the popup should first be consumed to dismiss Select")
		_, _ = select_test_build(&rt)
		_, notice_root := select_test_build(&rt)
		testing.expect(t, notice_root != 0 && rt.notice_count == 1,
			"dismissing Select should leave the actionable notice available to the user")
	}
}

@(test)
test_select_semantic_expand_before_first_open_and_collapse :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 240})
	defer destroy_runtime(&rt)
	_, trigger := select_test_build(&rt)
	if trigger == 0 { testing.expect(t, false, "Select trigger should be retained"); return }
	trigger_id := semantic_visual_id(trigger)
	testing.expect(t, semantic_action_request(&rt, trigger_id, .Expand),
		"AccessKit Expand should queue for a Select that has never been opened")
	_, _ = select_test_build(&rt)
	semantic, found := semantic_node_lookup(&rt, trigger_id)
	testing.expect(t, context_menu_is_open(&rt) && found && semantic_states_has(semantic.states, .Expanded),
		"the next application description should realize the pending semantic expansion")
	testing.expect(t, semantic_action_request(&rt, trigger_id, .Collapse),
		"AccessKit Collapse should close the active Select popup")
	_, _ = select_test_build(&rt)
	testing.expect(t, !context_menu_is_open(&rt), "semantic Collapse should dismiss the popup")
}

@(test)
test_select_escape_and_outside_pointer_dismiss_restore_trigger_focus :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 240})
	defer destroy_runtime(&rt)
	trigger := select_test_open(&rt)
	if trigger == 0 { testing.expect(t, false, "Select trigger should be retained"); return }
	testing.expect(t, select_handle_key(&rt, .Cancel), "Escape should be consumed by the open Select")
	_, _ = select_test_build(&rt)
	testing.expect(t, !context_menu_is_open(&rt) && rt.focused == trigger,
		"Escape should close the popup and restore trigger focus")

	_ = select_test_open(&rt)
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=350, y=20, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=350, y=20, button=POINTER_BUTTON_PRIMARY})
	_, _ = select_test_build(&rt)
	testing.expect(t, !context_menu_is_open(&rt), "an outside pointer press should dismiss the popup")
}

@(test)
test_select_tab_closes_popup_and_moves_around_retiring_options :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 420, 260})
	defer destroy_runtime(&rt)
	build := proc(rt: ^Runtime) -> (before, trigger, after: Node_ID) {
		options := SELECT_TEST_OPTIONS
		if !rt.invalidated { invalidate_root(rt, "Select Tab test rebuild") }
		ui, ready := begin_frame(rt)
		if !ready { return }
		container_begin_simple(&ui, .Root, label="select-tab-root", key=key_string("root"), style=layout_style(.Column, width=360, height=220, gap=8, padding=10))
		_ = button(&ui, "Before", key=key_string("before"), style=layout_style(width=120, height=32))
		before = rt.pending[len(rt.pending)-1].description.id
		_ = select_control(&ui, key_string("choice"), "Choice", options[:], 20)
		trigger = rt.pending[len(rt.pending)-1].description.id
		_ = button(&ui, "After", key=key_string("after"), style=layout_style(width=120, height=32))
		after = rt.pending[len(rt.pending)-1].description.id
		container_end(&ui)
		end_frame(&ui)
		return
	}
	before, trigger, after := build(&rt)
	if trigger == 0 || after == 0 { testing.expect(t, false, "tab focus fixture controls should be retained"); return }
	trigger_node := rt.nodes[trigger]
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=trigger_node.bounds.x+trigger_node.bounds.w/2, y=trigger_node.bounds.y+trigger_node.bounds.h/2, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=trigger_node.bounds.x+trigger_node.bounds.w/2, y=trigger_node.bounds.y+trigger_node.bounds.h/2, button=POINTER_BUTTON_PRIMARY})
	before, trigger, after = build(&rt)
	testing.expect(t, select_handle_tab(&rt) && !context_menu_is_open(&rt) && rt.focused == after,
		"Tab should close the popup and skip its still-retained option nodes")
	_, trigger, _ = build(&rt)
	trigger_node = rt.nodes[trigger]
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=trigger_node.bounds.x+trigger_node.bounds.w/2, y=trigger_node.bounds.y+trigger_node.bounds.h/2, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=trigger_node.bounds.x+trigger_node.bounds.w/2, y=trigger_node.bounds.y+trigger_node.bounds.h/2, button=POINTER_BUTTON_PRIMARY})
	_, trigger, _ = build(&rt)
	testing.expect(t, select_handle_tab(&rt, reverse=true) && !context_menu_is_open(&rt) && rt.focused == before,
		"Shift+Tab should close the popup and move backward from its trigger")
}

@(test)
test_select_keeps_the_open_owner_when_multiple_controls_are_described :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 420, 260})
	defer destroy_runtime(&rt)
	options := SELECT_TEST_OPTIONS
	build := proc(rt: ^Runtime, options: []Select_Option) -> (first, second: Node_ID) {
		if !rt.invalidated { invalidate_root(rt, "multiple Select test rebuild") }
		ui, ready := begin_frame(rt)
		if !ready { return }
		container_begin_simple(&ui, .Root, label="multiple-select-root", key=key_string("root"), style=layout_style(.Column, width=360, height=220, gap=8, padding=10))
		_ = select_control(&ui, key_string("first-choice"), "First", options[:], 20)
		first = rt.pending[len(rt.pending)-1].description.id
		_ = select_control(&ui, key_string("second-choice"), "Second", options[:], 10)
		second = rt.pending[len(rt.pending)-1].description.id
		container_end(&ui)
		end_frame(&ui)
		return
	}
	first, _ := build(&rt, options[:])
	if first == 0 { testing.expect(t, false, "both Select controls should be retained"); return }
	first_node := rt.nodes[first]
	x, y := first_node.bounds.x+first_node.bounds.w/2, first_node.bounds.y+first_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	first, _ = build(&rt, options[:])
	testing.expect(t, context_menu_is_open(&rt) && rt.select.trigger_node == first,
		"describing a later closed Select must not steal ownership of the active popup")
	testing.expect(t, select_test_row(&rt, "Beta") != 0, "the first control's selected option should remain in its popup")
}

@(test)
test_select_navigation_skips_disabled_supports_typeahead_and_returns_one_controlled_change :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 240})
	defer destroy_runtime(&rt)
	trigger := select_test_open(&rt)
	if trigger == 0 { testing.expect(t, false, "Select trigger should be retained"); return }
	testing.expect(t, select_handle_key(&rt, .Down) && rt.select.active_key == 30,
		"Down should move from the selected item to the next enabled option")
	_, _ = select_test_build(&rt)
	testing.expect(t, rt.focused == select_test_row(&rt, "Charlie"), "active option focus should follow keyboard navigation")

	testing.expect(t, select_handle_key(&rt, .Home) && rt.select.active_key == 10, "Home should focus the first enabled option")
	_, _ = select_test_build(&rt)
	testing.expect(t, select_handle_key(&rt, .End) && rt.select.active_key == 30, "End should skip disabled trailing options")
	_, _ = select_test_build(&rt)

	testing.expect(t, select_typeahead(&rt, "b"), "text input should be consumed while the popup owns focus")
	result, _ := select_test_build(&rt)
	testing.expect(t, rt.select.active_key == 20 && rt.focused == select_test_row(&rt, "Beta"),
		"case-insensitive type-ahead should move active focus to the matching option")
	_ = select_typeahead(&rt, "c")
	result, _ = select_test_build(&rt)
	testing.expect(t, rt.select.active_key == 30 && rt.focused == select_test_row(&rt, "Charlie"),
		"type-ahead should update the active option before selection")
	testing.expect(t, select_handle_key(&rt, .Activate), "Enter should be consumed by the Select")
	result, _ = select_test_build(&rt)
	testing.expect(t, result.changed && result.selected_key == 30 && !result.open,
		"Enter should return the changed key to the application and close the popup")
	result, _ = select_test_build(&rt)
	testing.expect(t, !result.changed, "a controlled change event should be delivered exactly once")
}

@(test)
test_select_pointer_and_accessibility_activation_share_controlled_result_path :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 240})
	defer destroy_runtime(&rt)
	trigger := select_test_open(&rt)
	if trigger == 0 { testing.expect(t, false, "Select trigger should be retained"); return }
	charlie := select_test_row(&rt, "Charlie")
	if charlie == 0 { testing.expect(t, false, "Charlie option should be retained"); return }
	row := rt.nodes[charlie]
	x, y := row.bounds.x+row.bounds.w/2, row.bounds.y+row.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_, _ = select_test_build(&rt)
	result, _ := select_test_build(&rt)
	testing.expect(t, result.changed && result.selected_key == 30 && !context_menu_is_open(&rt),
		"pointer activation should close the list and return the chosen stable key")

	// Reopen and exercise the one-shot visual-node activation path used by an
	// AccessKit Select request on a realized List_Box_Option.
	_ = select_test_open(&rt)
	alpha := select_test_row(&rt, "Alpha")
	if alpha == 0 { testing.expect(t, false, "Alpha option should be retained after reopening"); return }
	rt.activation_sequence += 1
	rt.activation_node = alpha
	invalidate_root(&rt, "simulated accessibility option Select")
	_, _ = select_test_build(&rt)
	result, _ = select_test_build(&rt)
	testing.expect(t, result.changed && result.selected_key == 10 && !context_menu_is_open(&rt),
		"screen-reader option selection should use the same controlled result contract")
}

@(test)
test_select_large_list_scrolls_selected_option_into_view_and_typeahead_skips_disabled :: proc(t: ^testing.T) {
	options: [12]Select_Option
	for index in 0..<len(options) { options[index] = Select_Option{u64(index+1), fmt.tprintf("Option %02d", index+1), false} }
	options[10].disabled = true
	options[11].label = "Target"
	rt := new_runtime(Rect{0, 0, 280, 190})
	defer destroy_runtime(&rt)

	build := proc(rt: ^Runtime, options: []Select_Option) -> (result: Select_Result, trigger: Node_ID) {
		if !rt.invalidated { invalidate_root(rt, "large Select test rebuild") }
		ui, ready := begin_frame(rt)
		if !ready { return }
		container_begin_simple(&ui, .Root, label="large-select-root", key=key_string("root"), style=layout_style(.Column, width=260, height=170, padding=4))
		result = select_control(&ui, key_string("large-select"), "Large choice", options, 12)
		trigger = rt.pending[len(rt.pending)-1].description.id
		container_end(&ui)
		end_frame(&ui)
		return result, trigger
	}
	_, trigger := build(&rt, options[:])
	if trigger == 0 { testing.expect(t, false, "large Select trigger should be retained"); return }
	node := rt.nodes[trigger]
	x, y := node.bounds.x+node.bounds.w/2, node.bounds.y+node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_, _ = build(&rt, options[:])
	region := scroll_region_state(&rt, rt.select.scroll_node)
	selected := select_test_row(&rt, "Target")
	testing.expect(t, context_menu_is_open(&rt) && region.max_scroll_y > 0,
		"a long option collection should use a clipped, scrollable popup")
	if selected != 0 {
		row := rt.nodes[selected]
		testing.expect(t, row.bounds.y >= region.viewport_bounds.y && row.bounds.y+row.bounds.h <= region.viewport_bounds.y+region.viewport_bounds.h,
			"the selected option should be revealed in the popup viewport even when it is near the end")
	}
	testing.expect(t, select_handle_key(&rt, .Home), "Home should navigate a scrollable Select")
	_, _ = build(&rt, options[:])
	testing.expect(t, select_typeahead(&rt, "target"), "type-ahead should accept a full committed string")
	_, _ = build(&rt, options[:])
	testing.expect(t, rt.select.active_key == 12, "type-ahead should find the enabled matching item after a disabled item")
	target := select_test_row(&rt, "Target")
	region = scroll_region_state(&rt, rt.select.scroll_node)
	if target != 0 {
		row := rt.nodes[target]
		testing.expect(t, row.bounds.y >= region.viewport_bounds.y && row.bounds.y+row.bounds.h <= region.viewport_bounds.y+region.viewport_bounds.h,
			"type-ahead should reveal the newly active option in the popup viewport")
	}
}

select_test_build_options :: proc(rt: ^Runtime, options: []Select_Option) -> (result: Select_Result, trigger: Node_ID) {
	if !rt.invalidated { invalidate_root(rt, "Select scroll retention test rebuild") }
	ui, ready := begin_frame(rt)
	if !ready { return }
	container_begin(&ui, .Root, key=key_string("select-scroll-root"), style=layout_style(.Column))
	result = select_control(&ui, key_string("select-scroll-choice"), "Choice", options, 1)
	trigger = rt.pending[len(rt.pending)-1].description.id
	container_end(&ui)
	end_frame(&ui)
	return
}

select_test_settle_options :: proc(rt: ^Runtime, options: []Select_Option) {
	for _ in 0..<16 {
		if rt.invalidated {
			_, _ = select_test_build_options(rt, options)
			continue
		}
		ui, ready := begin_presentation_frame(rt)
		if ready {
			end_presentation_frame(&ui)
			continue
		}
		return
	}
}

@(test)
test_select_preserves_manual_wheel_offset_across_description_rebuilds :: proc(t: ^testing.T) {
	options: [16]Select_Option
	for &option, index in options {
		option = Select_Option{u64(index+1), fmt.tprintf("Option %02d", index+1), false}
	}
	rt := new_runtime(Rect{0, 0, 300, 220})
	defer destroy_runtime(&rt)
	_, trigger := select_test_build_options(&rt, options[:])
	if trigger == 0 { testing.expect(t, false, "scroll retention Select trigger should be retained"); return }
	trigger_node := rt.nodes[trigger]
	x, y := trigger_node.bounds.x+trigger_node.bounds.w/2, trigger_node.bounds.y+trigger_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	select_test_settle_options(&rt, options[:])
	if !context_menu_is_open(&rt) { testing.expect(t, false, "long-list Select popup should open"); return }
	scroll_id := rt.select.scroll_node
	before := scroll_region_state(&rt, scroll_id)
	if before.max_scroll_y <= 0 { testing.expect(t, false, "long option list should have a scrollable viewport"); return }
	consumed := process_scroll(&rt, Scroll_Event{
		x=before.viewport_bounds.x+before.viewport_bounds.w/2,
		y=before.viewport_bounds.y+before.viewport_bounds.h/2,
		delta_y=-4,
	})
	queued_offset := scroll_region_state(&rt, scroll_id).offset_y
	select_test_settle_options(&rt, options[:])
	settled_offset := scroll_region_state(&rt, scroll_id).offset_y
	invalidate_root(&rt, "unrelated application description while Select is scrolled")
	select_test_settle_options(&rt, options[:])
	final_offset := scroll_region_state(&rt, scroll_id).offset_y
	testing.expect(t, consumed && queued_offset > 0, "wheel input over the popup should advance its retained scroll offset")
	testing.expect(t, settled_offset == queued_offset && final_offset == queued_offset,
		"passive description rebuilds should preserve manual scrolling while the active option is unchanged")
}

@(test)
test_select_rejects_duplicate_keys_and_missing_selected_key :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 300, 200})
	defer destroy_runtime(&rt)
	options := [2]Select_Option{{key=1, label="One"}, {key=1, label="Duplicate"}}
	ui, ready := begin_frame(&rt)
	if !ready { testing.expect(t, false, "first Select frame should build"); return }
	container_begin_simple(&ui, .Root, label="invalid-select-root", key=key_string("root"), style=layout_style())
	result := select_control(&ui, key_string("invalid"), "Invalid", options[:], 9)
	container_end(&ui)
	end_frame(&ui)
	testing.expect(t, !result.valid && !result.open && rt.select.option_count == 0,
		"invalid option identities and unrepresented selected values should not open a malformed listbox")
}

@(test)
test_select_typeahead_matches_unicode_case_without_allocating_a_second_text_model :: proc(t: ^testing.T) {
	testing.expect(t, select_text_has_prefix("Éclair", "é"),
		"type-ahead should compare Unicode letters without ASCII-only case handling")
	testing.expect(t, select_text_has_prefix("日本語", "日"),
		"type-ahead should preserve exact matching for scripts without case")
}

@(test)
test_end_frame_unbalanced_cleanup_clears_all_identity_scope_stacks :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)
	ui, ready := begin_frame(&rt)
	if !ready {
		testing.expect(t, false, "identity cleanup fixture should begin a frame")
		return
	}
	container_begin_simple(&ui, .Root, label="identity-cleanup-root", key=key_string("root"), style=layout_style(width=300, height=180))
	_ = key_scope_begin_key(&ui, key_string("extra-scope"), Source_Site{})
	// This intentionally closes only the nested identity scope while leaving
	// the root scope active, exercising end_frame's invalid-description reset.
	container_end(&ui)
	end_frame(&ui)

	testing.expect(t, rt.hard_error, "end_frame should diagnose the unbalanced identity scope")
	testing.expect(t, len(rt.identity_stack) == 0 && len(rt.identity_labels) == 0 &&
		len(rt.identity_key_u64) == 0 && len(rt.identity_key_numeric) == 0 &&
		len(rt.identity_key_kind) == 0 && len(rt.identity_key_pair) == 0,
		"error recovery should clear every parallel identity stack so a retained overlay cannot index stale metadata")
}
