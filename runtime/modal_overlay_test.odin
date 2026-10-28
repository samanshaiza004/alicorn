package alicorn

import "core:testing"

modal_overlay_test_button :: proc(rt: ^Runtime, label: string) -> Node_ID {
	for id in rt.order {
		node, ok := rt.nodes[id]
		if ok && node.kind == .Button && node.label == label { return id }
	}
	return 0
}

modal_overlay_test_node :: proc(rt: ^Runtime, label: string) -> Node_ID {
	for id in rt.order {
		node, ok := rt.nodes[id]
		if ok && node.label == label { return id }
	}
	return 0
}

modal_focus_test_describe :: proc(ui: ^UI, omit_first_modal_action, show_modal: bool) {
	container_begin_simple(ui, .Root, label="modal-focus-root", key=key_string("modal-focus-root"), style=layout_style())
	button(ui, "Background", key=key_string("modal-focus-background"), style=layout_style())
	container_end(ui)
	if show_modal {
		modal_overlay_begin(ui, key_string("modal-focus-overlay"), style=layout_style(.Column), backdrop_color=Color{0, 0, 0, 0.5})
		if !omit_first_modal_action {
			button(ui, "First modal action", key=key_string("modal-focus-first"), style=layout_style())
		}
		button(ui, "Second modal action", key=key_string("modal-focus-second"), style=layout_style())
		modal_overlay_end(ui)
	}
}

modal_semantic_activation_describe :: proc(ui: ^UI, show_modal: bool) {
	container_begin_simple(ui, .Root, label="modal-semantic-root", key=key_string("modal-semantic-root"), style=layout_style())
	button(ui, "Background press", key=key_string("modal-semantic-background-press"), style=layout_style())
	_ = semantic_description(ui, .Button, "Background press", actions=semantic_actions_add({}, .Press))
	button(ui, "Background select", key=key_string("modal-semantic-background-select"), style=layout_style())
	_ = semantic_description(ui, .Tab, "Background select", actions=semantic_actions_add({}, .Select))
	container_end(ui)
	if show_modal {
		modal_overlay_begin(ui, key_string("modal-semantic-overlay"), style=layout_style(.Column))
		button(ui, "Modal press", key=key_string("modal-semantic-modal-press"), style=layout_style())
		_ = semantic_description(ui, .Button, "Modal press", actions=semantic_actions_add({}, .Press))
		button(ui, "Modal select", key=key_string("modal-semantic-modal-select"), style=layout_style())
		_ = semantic_description(ui, .Tab, "Modal select", actions=semantic_actions_add({}, .Select))
		modal_overlay_end(ui)
	}
}

modal_text_selection_test_area :: proc(
	ui: ^UI,
	area_id, run_id: Semantic_ID,
	label, key: string,
) -> bool {
	text(ui, label, key=key_string(key), style=layout_style(height=24))
	actions := semantic_actions_add({}, .Set_Text_Selection)
	if !semantic_describe_as(ui, area_id, .Text_Area, label, actions=actions) { return false }
	lengths := [1]u8{1}
	if semantic_text_run_set(ui.runtime, run_id, area_id, "x", lengths[:]) { return true }
	run, found := semantic_node_lookup(ui.runtime, run_id)
	return found && run.role == .Text_Run && run.parent == area_id && run.value == "x" &&
		semantic_byte_lengths_equal(run.text_run_character_lengths, lengths[:])
}

modal_text_selection_test_describe :: proc(
	ui: ^UI,
	show_modal: bool,
	background_area, background_run, modal_area, modal_run: Semantic_ID,
) -> (background_area_ok, modal_area_ok: bool) {
	container_begin_simple(ui, .Root, label="modal-text-selection-root", key=key_string("modal-text-selection-root"), style=layout_style(.Column, grow=1))
	_ = text_field(ui, "background field", key=key_string("modal-text-selection-background-field"), style=layout_style(height=32))
	background_area_ok = modal_text_selection_test_area(ui, background_area, background_run, "background area", "modal-text-selection-background-area")
	container_end(ui)
	if show_modal {
		modal_overlay_begin(ui, key_string("modal-text-selection-overlay"), style=layout_style(.Column))
		_ = text_field(ui, "modal field", key=key_string("modal-text-selection-modal-field"), style=layout_style(height=32))
		modal_area_ok = modal_text_selection_test_area(ui, modal_area, modal_run, "modal area", "modal-text-selection-modal-area")
		modal_overlay_end(ui)
	}
	return
}

modal_overlay_test_text_field :: proc(rt: ^Runtime, label: string) -> Node_ID {
	for id in rt.order {
		node, ok := rt.nodes[id]
		if ok && node.kind == .Text_Field && node.text == label { return id }
	}
	return 0
}

modal_text_selection_test_selection :: proc(run_id: Semantic_ID, anchor, focus: u64) -> Semantic_Text_Selection {
	return Semantic_Text_Selection{
		anchor={run_id=run_id, character_index=anchor},
		focus={run_id=run_id, character_index=focus},
		valid=true,
	}
}

@(test)
test_semantic_activation_obeys_modal_scope_and_recovers_after_dismissal :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "new runtime should request its first description"); return }
	modal_semantic_activation_describe(&ui, true)
	end_frame(&ui)

	background_press_node := modal_overlay_test_button(&rt, "Background press")
	background_select_node := modal_overlay_test_button(&rt, "Background select")
	modal_press_node := modal_overlay_test_button(&rt, "Modal press")
	modal_select_node := modal_overlay_test_button(&rt, "Modal select")
	testing.expect(t, background_press_node != 0 && background_select_node != 0 &&
		modal_press_node != 0 && modal_select_node != 0,
		"the workspace and modal activation controls should all be realized")
	if background_press_node == 0 || background_select_node == 0 || modal_press_node == 0 || modal_select_node == 0 {
		return
	}
	background_press := semantic_visual_id(background_press_node)
	background_select := semantic_visual_id(background_select_node)
	modal_press := semantic_visual_id(modal_press_node)
	modal_select := semantic_visual_id(modal_select_node)
	background_press_entity, background_press_found := semantic_node_lookup(&rt, background_press)
	background_select_entity, background_select_found := semantic_node_lookup(&rt, background_select)
	modal_press_entity, modal_press_found := semantic_node_lookup(&rt, modal_press)
	modal_select_entity, modal_select_found := semantic_node_lookup(&rt, modal_select)
	testing.expect(t, background_press_found && background_press_entity.visual_node == background_press_node &&
		semantic_actions_has(background_press_entity.actions, .Press) &&
		background_select_found && background_select_entity.visual_node == background_select_node &&
		semantic_actions_has(background_select_entity.actions, .Select) &&
		modal_press_found && modal_press_entity.visual_node == modal_press_node &&
		semantic_actions_has(modal_press_entity.actions, .Press) &&
		modal_select_found && modal_select_entity.visual_node == modal_select_node &&
		semantic_actions_has(modal_select_entity.actions, .Select),
		"each test control should publish the expected realized semantic action")
	sequence_before_blocked_actions := rt.activation_sequence
	testing.expect(t, !semantic_action_request(&rt, background_press, .Press),
		"semantic Press must not activate a covered workspace button")
	testing.expect(t, !semantic_action_request(&rt, background_select, .Select),
		"semantic Select must not activate a covered workspace tab")
	testing.expect(t, rt.activation_sequence == sequence_before_blocked_actions,
		"blocked semantic actions must not advance the activation sequence")

	sequence_before_modal_actions := rt.activation_sequence
	testing.expect(t, semantic_action_request(&rt, modal_press, .Press) && rt.activation_node == modal_press_node,
		"semantic Press must activate a button inside the modal")
	testing.expect(t, semantic_action_request(&rt, modal_select, .Select) && rt.activation_node == modal_select_node,
		"semantic Select must activate a tab inside the modal")
	testing.expect(t, rt.activation_sequence == sequence_before_modal_actions+2,
		"both modal semantic actions should advance the activation sequence")

	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "dismissing the modal should rebuild"); return }
	modal_semantic_activation_describe(&ui, false)
	end_frame(&ui)
	sequence_after_dismissal := rt.activation_sequence
	testing.expect(t, semantic_action_request(&rt, background_press, .Press),
		"the workspace button should accept semantic Press after modal dismissal")
	testing.expect(t, semantic_action_request(&rt, background_select, .Select),
		"the workspace tab should accept semantic Select after modal dismissal")
	testing.expect(t, rt.activation_sequence == sequence_after_dismissal+2,
		"workspace activation should resume after the modal is removed")
}

@(test)
test_semantic_text_selection_obeys_modal_scope_and_owner_eligibility :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)
	background_area := Semantic_ID{namespace=0x4D4F44414C53454C, value=1}
	background_run := Semantic_ID{namespace=0x4D4F44414C53454C, value=2}
	modal_area := Semantic_ID{namespace=0x4D4F44414C53454C, value=3}
	modal_run := Semantic_ID{namespace=0x4D4F44414C53454C, value=4}

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "the initial semantic text-selection fixture should build"); return }
	background_area_ok, modal_area_ok := modal_text_selection_test_describe(
		&ui, true, background_area, background_run, modal_area, modal_run,
	)
	end_frame(&ui)
	background_field := modal_overlay_test_text_field(&rt, "background field")
	modal_field := modal_overlay_test_text_field(&rt, "modal field")
	background_field_semantic := semantic_visual_id(background_field)
	modal_field_semantic := semantic_visual_id(modal_field)
	background_selection := modal_text_selection_test_selection(semantic_text_field_run_id(background_field), 0, 1)
	modal_selection := modal_text_selection_test_selection(semantic_text_field_run_id(modal_field), 0, 1)
	area_selection := modal_text_selection_test_selection(background_run, 0, 1)
	modal_area_selection := modal_text_selection_test_selection(modal_run, 0, 1)
	background_area_node, background_area_found := semantic_node_lookup(&rt, background_area)
	modal_area_node, modal_area_found := semantic_node_lookup(&rt, modal_area)
	testing.expect(t, background_area_ok && modal_area_ok && background_field != 0 && modal_field != 0 &&
		background_area_found && background_area_node.visual_node != 0 && modal_area_found && modal_area_node.visual_node != 0,
		"both text owners should be realized in the workspace and active modal")
	if !background_area_ok || !modal_area_ok || background_field == 0 || modal_field == 0 ||
	   !background_area_found || !modal_area_found { return }

	background_before, background_before_ok := text_field_interaction(&rt, background_field)
	testing.expect(t, !semantic_text_selection_apply(&rt, background_field_semantic, background_selection),
		"native selection must reject a Text_Field covered by a modal")
	background_after, background_after_ok := text_field_interaction(&rt, background_field)
	testing.expect(t, background_before_ok && background_after_ok &&
		background_before.selection_start == background_after.selection_start &&
		background_before.selection_end == background_after.selection_end,
		"a rejected background Text_Field selection must not change its retained caret")
	queued_before := len(rt.semantic_requests)-rt.semantic_request_read_index
	testing.expect(t, !semantic_text_selection_apply(&rt, background_area, area_selection) &&
		len(rt.semantic_requests)-rt.semantic_request_read_index == queued_before,
		"native selection must not queue a Text_Area selection behind a modal")

	testing.expect(t, semantic_text_selection_apply(&rt, modal_field_semantic, modal_selection),
		"a Text_Field inside the active modal must accept native selection")
	modal_field_interaction, modal_field_interaction_ok := text_field_interaction(&rt, modal_field)
	testing.expect(t, modal_field_interaction_ok && modal_field_interaction.selection_start == 0 && modal_field_interaction.selection_end == 1,
		"the active modal Text_Field must receive the requested selection")
	testing.expect(t, semantic_text_selection_apply(&rt, modal_area, modal_area_selection),
		"a Text_Area inside the active modal must queue native selection")
	event, event_found := semantic_request_pop(&rt)
	testing.expect(t, event_found && event.id == modal_area && event.action == .Set_Text_Selection &&
		event.text_selection == modal_area_selection,
		"the active modal Text_Area selection should reach the application request queue")
	if event_found { semantic_request_event_destroy(&rt, &event) }

	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "dismissing the modal should rebuild the selection fixture"); return }
	background_area_ok, _ = modal_text_selection_test_describe(
		&ui, false, background_area, background_run, modal_area, modal_run,
	)
	end_frame(&ui)
	testing.expect(t, background_area_ok && semantic_text_selection_apply(&rt, background_field_semantic, background_selection),
		"the background Text_Field should accept selection again after modal dismissal")
	testing.expect(t, semantic_text_selection_apply(&rt, background_area, area_selection),
		"the background Text_Area should queue selection again after modal dismissal")
	event, event_found = semantic_request_pop(&rt)
	testing.expect(t, event_found && event.id == background_area && event.text_selection == area_selection,
		"dismissed-modal Text_Area selection should be queued for the correct owner")
	if event_found { semantic_request_event_destroy(&rt, &event) }

	background_area_node, background_area_found = semantic_node_lookup(&rt, background_area)
	if !background_area_found { testing.expect(t, false, "the background Text_Area should remain realized"); return }
	selection_changed := modal_text_selection_test_selection(semantic_text_field_run_id(background_field), 1, 2)
	rt.nodes[background_field].disabled = true
	testing.expect(t, !semantic_text_selection_apply(&rt, background_field_semantic, selection_changed),
		"native selection must reject a disabled Text_Field")
	rt.nodes[background_field].disabled = false
	rt.nodes[background_area_node.visual_node].disabled = true
	testing.expect(t, !semantic_text_selection_apply(&rt, background_area, area_selection) &&
		len(rt.semantic_requests)-rt.semantic_request_read_index == 0,
		"native selection must reject a disabled Text_Area without queueing it")
	rt.nodes[background_area_node.visual_node].disabled = false
	rt.nodes[background_field].active = false
	testing.expect(t, !semantic_text_selection_apply(&rt, background_field_semantic, selection_changed),
		"native selection must reject an inactive Text_Field owner")
	rt.nodes[background_field].active = true
	rt.nodes[background_area_node.visual_node].active = false
	testing.expect(t, !semantic_text_selection_apply(&rt, background_area, area_selection) &&
		len(rt.semantic_requests)-rt.semantic_request_read_index == 0,
		"native selection must reject an inactive Text_Area owner without queueing it")
}

@(test)
test_modal_overlay_blocks_workspace_and_limits_focus :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "new runtime should request its first description"); return }

	container_begin_simple(&ui, .Root, label="overlay-test-root", key=key_string("root"), style=layout_style())
	button(&ui, "Underlying action", key=key_string("underlying"), style=layout_style(width=800, height=600))
	container_end(&ui)

	overlay_id := modal_overlay_begin(
		&ui,
		key_string("test-overlay"),
		style=layout_style(.Column, align=.Center, clip=true),
		backdrop_color=Color{0.02, 0.025, 0.04, 0.68},
	)
	container_begin_simple(
		&ui,
		.Container,
		label="overlay-test-panel",
		key=key_string("panel"),
		style=layout_style(width=320, height=180, padding=8, gap=4),
		color=Color{0.06, 0.08, 0.12, 1},
	)
	field_id := text_field(&ui, "", key=key_string("query"), style=layout_style(.Row, height=32))
	button(&ui, "Run command", key=key_string("overlay-command"), style=layout_style(.Row, height=32), variant=.Quiet)
	container_end(&ui)
	modal_overlay_end(&ui)
	end_frame(&ui)

	underlying_id := modal_overlay_test_button(&rt, "Underlying action")
	overlay_button_id := modal_overlay_test_button(&rt, "Run command")
	testing.expect(t, overlay_id != 0 && field_id != 0 && underlying_id != 0 && overlay_button_id != 0,
		"workspace and modal controls should both remain retained")
	if overlay_id == 0 || field_id == 0 || underlying_id == 0 || overlay_button_id == 0 { return }
	quiet_button, quiet_button_ok := rt.nodes[overlay_button_id]
	testing.expect(t, quiet_button_ok && quiet_button.button_variant == .Quiet,
		"quiet buttons should resolve an explicit quiet recipe while remaining interactive")

	testing.expect(t, hit_test(&rt, 10, 590) == overlay_id,
		"an empty backdrop hit must stop at the modal layer instead of reaching the workspace")
	testing.expect(t, hit_test(&rt, -1, -1) == 0, "modal input blocking must not extend beyond its viewport")
	button_bounds := rt.nodes[overlay_button_id].bounds
	testing.expect(t, hit_test(&rt, button_bounds.x+button_bounds.w/2, button_bounds.y+button_bounds.h/2) == overlay_button_id,
		"interactive modal descendants must remain hit-testable")
	testing.expect(t, focus(&rt, field_id), "modal query field should accept focus")
	testing.expect(t, !focus(&rt, underlying_id), "modal state should reject programmatic focus of the covered workspace")
	testing.expect(t, focus_candidate_is_valid(&rt, field_id), "visible enabled modal controls should be valid focus candidates")
	testing.expect(t, !focus_candidate_is_valid(&rt, underlying_id), "covered workspace controls should not be focus candidates")
	rt.nodes[overlay_button_id].disabled = true
	testing.expect(t, !focus_candidate_is_valid(&rt, overlay_button_id), "disabled modal controls should not be focus candidates")
	rt.nodes[overlay_button_id].disabled = false
	rt.nodes[overlay_button_id].active = false
	testing.expect(t, !focus_candidate_is_valid(&rt, overlay_button_id), "hidden modal controls should not be focus candidates")
	rt.nodes[overlay_button_id].active = true
	rt.focused = underlying_id // Model a stale focus owner during a modal transition.
	sequence_before_blocked_activation := rt.activation_sequence
	testing.expect(t, !activate_focused(&rt, .Enter), "keyboard activation must not reach a covered workspace control")
	testing.expect(t, !activate_focused(&rt, .Space), "Space activation must not reach a covered workspace control")
	testing.expect(t, rt.activation_sequence == sequence_before_blocked_activation, "blocked activation must not advance the activation sequence")
	rt.focused = field_id
	testing.expect(t, focus_traverse(&rt, .Next) == overlay_button_id,
		"forward focus traversal should stay inside the modal subtree")
	testing.expect(t, focus_traverse(&rt, .Next) == field_id,
		"focus traversal should wrap within the modal subtree")
	testing.expect(t, process_scroll(&rt, Scroll_Event{x=10, y=590, delta_y=1}),
		"wheel input outside modal controls must be consumed instead of scrolling the workspace")

	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "closing the modal description should rebuild"); return }
	container_begin_simple(&ui, .Root, label="overlay-test-root", key=key_string("root"), style=layout_style())
	button(&ui, "Underlying action", key=key_string("underlying"), style=layout_style(width=800, height=600))
	container_end(&ui)
	end_frame(&ui)
	underlying_after := modal_overlay_test_button(&rt, "Underlying action")
	testing.expect(t, underlying_after != 0 && hit_test(&rt, 10, 590) == underlying_after,
		"removing the modal should reveal the still-retained workspace")
	testing.expect(t, focus_candidate_is_valid(&rt, underlying_after), "no-modal focus candidates should retain legacy eligibility")
}

@(test)
test_modal_focus_recovery_stays_inside_overlay :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "new runtime should request its first description"); return }
	modal_focus_test_describe(&ui, false, true)
	end_frame(&ui)
	background_id := modal_overlay_test_button(&rt, "Background")
	first_id := modal_overlay_test_button(&rt, "First modal action")
	modal_id := modal_overlay_root(&rt)
	second_id := modal_overlay_test_button(&rt, "Second modal action")
	testing.expect(t, background_id != 0 && first_id != 0, "test controls should be retained")
	if background_id == 0 || first_id == 0 { return }
	testing.expect(t, focus(&rt, first_id), "first modal action should accept focus")

	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "removing focused modal child should rebuild"); return }
	modal_focus_test_describe(&ui, true, true)
	end_frame(&ui)
	testing.expect(t, modal_overlay_test_button(&rt, "Background") == background_id, "background node identity should remain stable")
	testing.expect(t, modal_overlay_root(&rt) == modal_id, "modal root identity should remain stable")
	testing.expect(t, modal_overlay_test_button(&rt, "Second modal action") == second_id, "surviving modal control identity should remain stable")
	testing.expect(t, rt.focused != background_id, "removing a focused modal child must not move focus behind the modal")
	testing.expect(t, focus_candidate_is_valid(&rt, rt.focused), "focus recovery should select a valid candidate within the active modal")
	testing.expect(t, rt.focused == modal_overlay_test_button(&rt, "Second modal action"), "the surviving modal action should receive recovered focus")
}

@(test)
test_modal_opening_does_not_leave_focus_on_covered_workspace :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)
	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "new runtime should request its first description"); return }
	modal_focus_test_describe(&ui, false, false)
	end_frame(&ui)
	background_id := modal_overlay_test_button(&rt, "Background")
	testing.expect(t, background_id != 0 && focus(&rt, background_id), "background action should accept focus before opening a modal")

	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "opening modal should rebuild"); return }
	modal_focus_test_describe(&ui, false, true)
	end_frame(&ui)
	testing.expect(t, modal_overlay_root(&rt) != 0, "modal should be active after opening")
	testing.expect(t, rt.focused != background_id, "opening a modal must not leave keyboard focus on the covered workspace")
	if rt.focused != 0 {
		testing.expect(t, focus_candidate_is_valid(&rt, rt.focused), "modal-open focus should be eligible within the modal scope")
	}
	rt.focused = background_id // Model a host retaining the previous owner during the transition.
	sequence_before_blocked_activation := rt.activation_sequence
	testing.expect(t, !activate_focused(&rt, .Enter), "covered workspace must not receive activation after modal opens")
	testing.expect(t, rt.activation_sequence == sequence_before_blocked_activation, "covered workspace activation must not advance the sequence")
}

@(test)
test_modal_overlay_explicit_panel_height_fits_eight_results :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 1440, 900})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "new runtime should request its first description"); return }
	container_begin_simple(&ui, .Root, label="palette-layout-root", key=key_string("palette-layout-root"), style=layout_style())
	container_end(&ui)

	modal_overlay_begin(
		&ui,
		key_string("palette-layout-overlay"),
		style=layout_style(.Column, padding=48, align=.Center, clip=true),
	)
	panel_id := container_begin(
		&ui,
		.Container,
		label="palette-layout-panel",
		style=layout_style(.Column, width=680, height=384, padding=12, gap=6, clip=true),
	)
	container_begin(&ui, .Container, label="palette-layout-input-row", style=layout_style(.Row, height=40, gap=8, align=.Center))
	text_field(&ui, "", key=key_string("palette-layout-query"), style=layout_style(.Row, height=40, grow=1))
	container_end(&ui)
	result_labels := [8]string{
		"Palette result 0", "Palette result 1", "Palette result 2", "Palette result 3",
		"Palette result 4", "Palette result 5", "Palette result 6", "Palette result 7",
	}
	for index in 0..<len(result_labels) {
		button(&ui, result_labels[index], key=key_pair(u64(index+1), 3), style=layout_style(.Row, height=34))
	}
	container_end(&ui)
	modal_overlay_end(&ui)
	end_frame(&ui)

	panel, panel_ok := rt.nodes[panel_id]
	testing.expect(t, panel_ok, "palette panel should be retained")
	if !panel_ok { return }
	testing.expect(t, panel.bounds.w == 680 && panel.bounds.h == 384,
		"an explicitly sized palette panel should keep its requested dimensions")
	for label in result_labels {
		id := modal_overlay_test_node(&rt, label)
		row, row_ok := rt.nodes[id]
		testing.expect(t, row_ok, "every result up to the visible-row limit should be retained")
		if !row_ok { continue }
		fully_inside_panel := row.bounds.y >= panel.bounds.y+12 && row.bounds.y+row.bounds.h <= panel.bounds.y+panel.bounds.h-12
		testing.expect(t, row.bounds.h == 34 && fully_inside_panel,
			"visible palette rows should fit completely inside the explicitly sized panel")
	}
}
