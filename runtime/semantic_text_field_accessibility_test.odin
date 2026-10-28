package alicorn

import "core:testing"

@(test)
test_builtin_text_field_publishes_stable_text_run_and_live_caret :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 200})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build {
		testing.expect(t, false, "the initial text-field description should build")
		return
	}
	container_begin(&ui, .Root, key=key_string("text-field-a11y-root"), style=layout_style(.Column, grow=1))
	field_id := text_field(&ui, "A日本🙂", key=key_string("text-field-a11y-input"))
	container_end(&ui)
	end_frame(&ui)

	field_semantic_id := semantic_visual_id(field_id)
	field, field_found := semantic_node_lookup(&rt, field_semantic_id)
	run := Semantic_Node{}
	run_found := false
	for _, entity in rt.semantic_entities {
		if entity.node.role == .Text_Run && entity.node.parent == field_semantic_id {
			run = entity.node
			run_found = true
			break
		}
	}
	expected_lengths := [4]u8{1, 3, 3, 4}
	stable_run_id := run.id
	testing.expect(t, field_found && run_found,
		"a built-in Text_Field must expose a stable Text_Run child")
	if !field_found || !run_found { return }
	testing.expect(t, run.value == "A日本🙂" && semantic_byte_lengths_equal(run.text_run_character_lengths, expected_lengths[:]),
		"the Text_Run must preserve committed Unicode and one UTF-8 length per grapheme")
	testing.expect(t, field.text_selection.valid && field.text_selection.anchor.run_id == run.id &&
		field.text_selection.focus.run_id == run.id && field.text_selection.focus.character_index == 4,
		"the initial Text_Field selection must expose its end caret in Text_Run character indexes")

	testing.expect(t, set_text_caret(&rt, field_id, 4), "the field caret should move to a grapheme boundary")
	_ = semantic_commit(&rt)
	field, field_found = semantic_node_lookup(&rt, field_semantic_id)
	testing.expect(t, field_found && field.text_selection.valid &&
		field.text_selection.anchor.character_index == 2 && field.text_selection.focus.character_index == 2,
		"caret-only movement must publish an updated collapsed AccessKit text selection")
	updated_run, updated_run_found := semantic_node_lookup(&rt, stable_run_id)
	testing.expect(t, updated_run_found && updated_run.value == "A日本🙂",
		"caret changes must preserve the same Text_Run identity and committed value")

	selection := Semantic_Text_Selection{
		anchor={run_id=stable_run_id, character_index=1},
		focus={run_id=stable_run_id, character_index=3},
		valid=true,
	}
	testing.expect(t, semantic_text_selection_apply(&rt, field_semantic_id, selection),
		"native text-selection requests should update a built-in field directly")
	field, field_found = semantic_node_lookup(&rt, field_semantic_id)
	selected, interaction_ok := text_field_interaction(&rt, field_id)
	testing.expect(t, field_found && field.text_selection.anchor.character_index == 1 &&
		field.text_selection.focus.character_index == 3 && interaction_ok && selected.selection_start == 1 &&
		selected.selection_end == 7,
		"the semantic selection and retained UTF-8 selection must remain synchronized")
	change := process_text_edit(&rt, field_id, Text_Edit{.Insert, "Go"})
	_ = semantic_commit(&rt)
	field, field_found = semantic_node_lookup(&rt, field_semantic_id)
	updated_run, updated_run_found = semantic_node_lookup(&rt, stable_run_id)
	testing.expect(t, change.changed && field_found && field.value == "AGo🙂" && updated_run_found &&
		updated_run.value == "AGo🙂" && field.text_selection.focus.character_index == 3,
		"committed edits must publish updated Text_Run text and caret together")
	text_change_destroy(&rt, &change)
}

@(test)
test_empty_builtin_text_field_has_position_zero_text_run :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 160})
	defer destroy_runtime(&rt)
	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "the empty text field should build"); return }
	container_begin(&ui, .Root, key=key_string("empty-text-field-root"), style=layout_style(.Column, grow=1))
	field_id := text_field(&ui, "", key=key_string("empty-text-field"))
	container_end(&ui)
	end_frame(&ui)
	field_id_semantic := semantic_visual_id(field_id)
	field, field_found := semantic_node_lookup(&rt, field_id_semantic)
	run, run_found := semantic_node_lookup(&rt, semantic_text_field_run_id(field_id))
	testing.expect(t, field_found && run_found && run.role == .Text_Run && run.value == "" &&
		field.text_selection.valid && field.text_selection.anchor.character_index == 0 &&
		field.text_selection.focus.character_index == 0,
		"an empty text field must still expose a stable zero-length text run and caret")
}
