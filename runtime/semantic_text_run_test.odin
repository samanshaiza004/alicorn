package alicorn

import "core:testing"

semantic_text_run_test_id :: proc(value: u64) -> Semantic_ID {
	return Semantic_ID{namespace=0x54585452554E0001, value=value}
}

@(test)
test_semantic_text_runs_attach_to_pending_visual_text_area :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)
	area_id := semantic_text_run_test_id(90)
	run_id := semantic_text_run_test_id(91)
	lengths := [2]u8{1, 4}
	actions := semantic_actions_add({}, .Focus)
	actions = semantic_actions_add(actions, .Set_Text_Selection)
	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "the semantic fixture should build once"); return }
	container_begin_simple(&ui, .Root, label="text-run-area", key=key_string("text-run-area"), style=layout_style(.Column, width=240, height=120))
	_ = semantic_describe_as(&ui, area_id, .Text_Area, "Document", actions=actions)
	testing.expect(t, semantic_text_run_set(ui.runtime, run_id, area_id, "a🙂", lengths[:], 1),
		"a logical Text_Run can attach to a Text_Area still pending in the same UI build")
	selection := Semantic_Text_Selection{
		anchor={run_id=run_id, character_index=0},
		focus={run_id=run_id, character_index=2},
		valid=true,
	}
	testing.expect(t, semantic_text_area_selection_set(ui.runtime, area_id, selection),
		"the editor selection can be recorded on the pending area after its runs are described")
	container_end(&ui)
	end_frame(&ui)
	area, area_found := semantic_node_lookup(&rt, area_id)
	run, run_found := semantic_node_lookup(&rt, run_id)
	testing.expect(t, area_found && run_found && area.text_selection == selection && run.parent == area_id &&
		semantic_revision(&rt) == 1,
		"the visual area and logical text runs should appear together in one semantic revision")
}

@(test)
test_semantic_text_runs_own_boundaries_selection_and_requests :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)

	area_id := semantic_text_run_test_id(1)
	first_run_id := semantic_text_run_test_id(2)
	second_run_id := semantic_text_run_test_id(3)
	actions := semantic_actions_add({}, .Focus)
	actions = semantic_actions_add(actions, .Set_Text_Selection)
	actions = semantic_actions_add(actions, .Replace_Selected_Text)
	testing.expect(t, semantic_node_set(&rt, Semantic_Node_Description{
		id=area_id,
		role=.Text_Area,
		label="README.md",
		actions=actions,
	}), "a text area can be published before its logical text runs")

	first_lengths := [2]u8{1, 4} // ASCII + one four-byte selectable grapheme.
	second_lengths := [2]u8{1, 2} // ASCII + CRLF represented as one unit.
	testing.expect(t, semantic_text_run_set(&rt, first_run_id, area_id, "a🙂", first_lengths[:], 10),
		"Text_Run should accept selectable UTF-8 byte lengths that sum to its value")
	testing.expect(t, semantic_text_run_set(&rt, second_run_id, area_id, "b\r\n", second_lengths[:], 20),
		"CRLF can occupy one selectable unit with two source bytes")
	first_lengths[0] = 99
	second_lengths[1] = 99

	selection := Semantic_Text_Selection{
		anchor={run_id=second_run_id, character_index=2},
		focus={run_id=first_run_id, character_index=1},
		valid=true,
	}
	testing.expect(t, semantic_text_area_selection_set(&rt, area_id, selection),
		"the Text_Area can publish a directional selection spanning run boundaries")
	testing.expect(t, semantic_commit(&rt), "the area, runs, and selection publish in one semantic revision")

	first, first_found := semantic_node_lookup(&rt, first_run_id)
	second, second_found := semantic_node_lookup(&rt, second_run_id)
	area, area_found := semantic_node_lookup(&rt, area_id)
	testing.expect(t, first_found && second_found && area_found &&
		first.text_run_character_lengths[0] == 1 && first.text_run_character_lengths[1] == 4 &&
		second.text_run_character_lengths[0] == 1 && second.text_run_character_lengths[1] == 2 &&
		area.text_selection == selection,
		"published run boundaries must be owned and selection anchor/focus order must be preserved")
	byte_offset, byte_ok := semantic_text_run_byte_offset(first, 2)
	character_index, character_ok := semantic_text_run_character_index(first, 5)
	_, split_grapheme_ok := semantic_text_run_character_index(first, 2)
	testing.expect(t, byte_ok && byte_offset == 5 && character_ok && character_index == 2 && !split_grapheme_ok,
		"text positions should convert losslessly at selectable boundaries and reject offsets inside graphemes")
	crlf_byte_offset, crlf_ok := semantic_text_run_byte_offset(second, 2)
	crlf_character_index, crlf_index_ok := semantic_text_run_character_index(second, 3)
	testing.expect(t, crlf_ok && crlf_byte_offset == 3 && crlf_index_ok && crlf_character_index == 2,
		"CRLF's two source bytes should remain one accessible selectable unit")

	snapshot := semantic_snapshot(&rt)
	defer semantic_snapshot_destroy(&snapshot)
	snapshot_copied := false
	for node in snapshot.nodes {
		if node.id == first_run_id {
			snapshot_copied = len(node.text_run_character_lengths) == 2 &&
				node.text_run_character_lengths[0] == 1 && node.value == "a🙂"
		}
	}
	testing.expect(t, snapshot_copied, "semantic snapshots must own text and selectable-unit metadata")

	requested := Semantic_Text_Selection{
		anchor={run_id=first_run_id, character_index=0},
		focus={run_id=second_run_id, character_index=1},
		valid=true,
	}
	testing.expect(t, semantic_text_selection_request(&rt, area_id, requested),
		"assistive text-selection actions should enter the application request queue")
	event, found := semantic_request_pop(&rt)
	testing.expect(t, found && event.id == area_id && event.action == .Set_Text_Selection &&
		event.text_selection == requested,
		"the queued selection request should preserve both semantic run positions")
	semantic_request_event_destroy(&rt, &event)

	testing.expect(t, semantic_action_request(&rt, area_id, .Replace_Selected_Text, text_value="hello"),
		"ReplaceSelectedText should reuse the existing owned text action payload")
	event, found = semantic_request_pop(&rt)
	testing.expect(t, found && event.id == area_id && event.action == .Replace_Selected_Text && event.text_value == "hello",
		"replacement text should arrive as an application-thread domain event")
	semantic_request_event_destroy(&rt, &event)

	testing.expect(t, !semantic_text_selection_request(&rt, area_id, Semantic_Text_Selection{
		anchor={run_id=first_run_id, character_index=3},
		focus={run_id=first_run_id, character_index=0},
		valid=true,
	}), "selection endpoints outside a run's selectable-unit count must be rejected")
	testing.expect(t, semantic_text_area_remove(&rt, area_id) && len(rt.semantic_entities) == 0,
		"retiring an editor semantic subtree should remove its logical runs with the area")
}

@(test)
test_semantic_text_run_removal_clears_committed_and_pending_selection :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)
	area_id := semantic_text_run_test_id(20)
	run_id := semantic_text_run_test_id(21)
	area_actions := semantic_actions_add({}, .Set_Text_Selection)
	_ = semantic_node_set(&rt, Semantic_Node_Description{id=area_id, role=.Text_Area, actions=area_actions})
	lengths := [1]u8{1}
	_ = semantic_text_run_set(&rt, run_id, area_id, "x", lengths[:])
	selection := Semantic_Text_Selection{
		anchor={run_id=run_id, character_index=1},
		focus={run_id=run_id, character_index=1},
		valid=true,
	}
	_ = semantic_text_area_selection_set(&rt, area_id, selection)
	_ = semantic_commit(&rt)
	previous_revision := semantic_revision(&rt)

	testing.expect(t, semantic_node_remove(&rt, run_id), "an individual logical text run can be retired")
	area, area_found := semantic_node_lookup(&rt, area_id)
	updated := semantic_commit(&rt)
	update := semantic_update_since(&rt, previous_revision)
	area_changed, run_removed := false, false
	for id in update.changed_ids { if id == area_id { area_changed = true } }
	for id in update.removed_ids { if id == run_id { run_removed = true } }
	testing.expect(t, area_found && !area.text_selection.valid && updated && area_changed && run_removed,
		"removing a referenced run must clear the owning area's selection in the same semantic revision")

	pending_area_id := semantic_text_run_test_id(22)
	pending_run_id := semantic_text_run_test_id(23)
	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "the pending text-area fixture should build"); return }
	container_begin_simple(&ui, .Root, label="pending-text-run-area", key=key_string("pending-text-run-area"),
		style=layout_style(.Column, width=240, height=120))
	_ = semantic_describe_as(&ui, pending_area_id, .Text_Area, "Pending document", actions=area_actions)
	_ = semantic_text_run_set(ui.runtime, pending_run_id, pending_area_id, "y", lengths[:])
	pending_selection := Semantic_Text_Selection{
		anchor={run_id=pending_run_id, character_index=0},
		focus={run_id=pending_run_id, character_index=1},
		valid=true,
	}
	_ = semantic_text_area_selection_set(ui.runtime, pending_area_id, pending_selection)
	testing.expect(t, semantic_node_remove(ui.runtime, pending_run_id),
		"a run can be removed while its Text_Area is still pending in this frame")
	container_end(&ui)
	end_frame(&ui)
	pending_area, pending_area_found := semantic_node_lookup(&rt, pending_area_id)
	_, pending_run_found := semantic_node_lookup(&rt, pending_run_id)
	testing.expect(t, pending_area_found && !pending_area.text_selection.valid && !pending_run_found,
		"a pending Text_Area must publish without a selection into a run removed in the same frame")
}

@(test)
test_semantic_text_run_rejects_invalid_byte_boundaries :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	area_id := semantic_text_run_test_id(10)
	run_id := semantic_text_run_test_id(11)
	_ = semantic_node_set(&rt, Semantic_Node_Description{id=area_id, role=.Text_Area})
	wrong_sum := [2]u8{1, 1}
	zero_length := [2]u8{1, 0}
	oversized_unit := [1]u8{255}
	testing.expect(t, !semantic_text_run_set(&rt, run_id, area_id, "a🙂", wrong_sum[:]),
		"run metadata that does not cover the complete UTF-8 value must be rejected")
	testing.expect(t, !semantic_text_run_set(&rt, run_id, area_id, "ab", zero_length[:]),
		"zero-byte selectable units must be rejected")
	testing.expect(t, !semantic_text_run_set(&rt, run_id, area_id, "x", oversized_unit[:]),
		"unit byte lengths must exactly match the run value")
	empty_run_id := semantic_text_run_test_id(12)
	testing.expect(t, semantic_text_run_set(&rt, empty_run_id, area_id, "", nil),
		"an empty run should represent the position-zero caret in an empty document")
	empty_selection := Semantic_Text_Selection{
		anchor={run_id=empty_run_id, character_index=0},
		focus={run_id=empty_run_id, character_index=0},
		valid=true,
	}
	area_actions := semantic_actions_add({}, .Set_Text_Selection)
	_ = semantic_node_set(&rt, Semantic_Node_Description{
		id=area_id,
		role=.Text_Area,
		actions=area_actions,
	})
	testing.expect(t, semantic_text_area_selection_set(&rt, area_id, empty_selection),
		"an empty editor still needs a representable caret position")
}
