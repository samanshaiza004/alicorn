package alicorn

import "core:fmt"

// utf8_character_index_to_byte_offset converts SDL's TEXT_EDITING character
// indexes to Alicorn's byte-addressed text positions. The conversion is kept
// explicit at this boundary: SDL defines start/length in UTF-8 characters,
// while the runtime stores source positions as byte offsets.
utf8_character_index_to_byte_offset :: proc(value: string, character_index: int) -> int {
	if character_index <= 0 { return 0 }
	byte_index := 0
	characters := 0
	for byte_index < len(value) && characters < character_index {
		first := value[byte_index]
		advance := 1
		switch {
		case first < 0x80:
			advance = 1
		case first & 0xE0 == 0xC0:
			advance = 2
		case first & 0xF0 == 0xE0:
			advance = 3
		case first & 0xF8 == 0xF0:
			advance = 4
		}
		if byte_index+advance > len(value) { advance = len(value)-byte_index }
		if advance < 1 { advance = 1 }
		byte_index += advance
		characters += 1
	}
	return byte_index
}

text_composition_range :: proc(composition: Text_Composition, value_length: int) -> (start, end: int) {
	start = composition.replace_anchor.byte
	end = composition.replace_focus.byte
	if start > end { start, end = end, start }
	start = text_min_int(text_max_int(start, 0), value_length)
	end = text_min_int(text_max_int(end, 0), value_length)
	return
}

text_composition_destroy :: proc(composition: ^Text_Composition, allocator := context.allocator) {
	if len(composition.text) > 0 { delete(composition.text, allocator) }
	composition^ = Text_Composition{}
}

text_composition_run_destroy :: proc(node: ^Node) {
	if node.composition_run_valid {
		text_run_destroy(&node.composition_run)
		node.composition_run_valid = false
	}
}

clear_text_composition :: proc(node: ^Node, allocator := context.allocator) -> bool {
	was_active := node.composition.active || node.composition_run_valid
	text_composition_destroy(&node.composition, allocator)
	text_composition_run_destroy(node)
	return was_active
}

// cancel_text_composition is the explicit application/runtime cancellation
// boundary used by Escape and platform focus changes. It clears only the
// transient preedit; committed field text and its current selection remain
// untouched.
cancel_text_composition :: proc(rt: ^Runtime, id: Node_ID, reason := "text composition canceled") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field { return false }
	if !clear_text_composition(node, rt.persistent_allocator) { return false }
	invalidate_interaction_paint(rt, id, reason)
	invalidate_root(rt, reason)
	return true
}

// text_composition_visual_value creates the temporary display projection. The
// committed selection is replaced only for this projection; node.text remains
// the retained copy of application state until TEXT_INPUT commits it.
text_composition_visual_value :: proc(node: ^Node) -> string {
	start, end := text_composition_range(node.composition, len(node.text))
	return fmt.aprintf("%s%s%s", node.text[:start], node.composition.text, node.text[end:])
}

text_composition_visual_start :: proc(node: ^Node) -> int {
	start, _ := text_composition_range(node.composition, len(node.text))
	return start
}

text_composition_visual_position :: proc(node: ^Node) -> Text_Position {
	visual_start := text_composition_visual_start(node)
	composition_byte := grapheme_floor_boundary(node.composition.text, node.composition.selection_end)
	return Text_Position{visual_start + composition_byte, .Leading}
}

// prepare_text_composition_node materializes the temporary projected run only
// after normal layout has established the field's current wrapping constraint.
// It is a retained runtime product, not a renderer-owned cache.
prepare_text_composition_node :: proc(rt: ^Runtime, node: ^Node) -> bool {
	if !node.active || node.kind != .Text_Field || !node.composition.active {
		text_composition_run_destroy(node)
		return false
	}
	max_width := node.text_run.max_width if node.text_run_valid else node.style.width
	value := text_composition_visual_value(node)
	defer { if len(value) > 0 { delete(value, rt.persistent_allocator) } }
	if node.composition_run_valid &&
		node.composition_run.font_generation == rt.text_engine.font_generation &&
		node.composition_run.max_width == max_width &&
		node.composition_run.font_weight == effective_font_weight(node.text_style.font_weight) &&
		node.composition_run.value == value {
		return false
	}
	text_composition_run_destroy(node)
	_, role_loaded := text_engine_font(&rt.text_engine, node.font)
	if !role_loaded { return false }
	run, ok := text_run_build(&rt.text_engine, value, 16, max_width, editable=true, allocator=rt.persistent_allocator, scratch_allocator=rt.scratch_allocator, font_role=node.font, font_weight=node.text_style.font_weight)
	if !ok { return false }
	node.composition_run = run
	node.composition_run_valid = true
	node.composition_run_generation += 1
	return true
}

// process_text_editing consumes one copied SDL preedit update. SDL's start and
// length are UTF-8 character indexes; the retained composition stores byte
// offsets only after this conversion. An empty preedit is treated as an
// explicit cancellation, which keeps focus transfer and platform cancellation
// deterministic.
process_text_editing :: proc(rt: ^Runtime, id: Node_ID, text: string, start_char, length_char: int) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !focus(rt, id) {
		return false
	}
	if len(text) == 0 {
		cancel_text_composition(rt, id, "text composition canceled")
		return true
	}
	if !node.composition.active {
		node.composition.replace_anchor = node.selection_anchor
		node.composition.replace_focus = node.selection_focus
		node.composition.active = true
	}
	if len(node.composition.text) > 0 { delete(node.composition.text, rt.persistent_allocator) }
	node.composition.text = owned(text, rt.persistent_allocator)
	if start_char < 0 {
		node.composition.selection_start = len(text)
		node.composition.selection_end = len(text)
	} else {
		start := utf8_character_index_to_byte_offset(text, start_char)
		finish_index := start_char + length_char
		if length_char < 0 { finish_index = start_char }
		finish := utf8_character_index_to_byte_offset(text, finish_index)
		node.composition.selection_start = start
		node.composition.selection_end = finish
	}
	text_composition_run_destroy(node)
	invalidate_interaction_paint(rt, id, "text composition updated")
	invalidate_root(rt, "text composition updated")
	record_trace(rt, .Focus, id, "SDL text composition updated")
	return true
}

// process_text_input handles committed platform text through the same editing
// path as other insertions. While a composition is active, its original
// replacement range wins over any transient preedit cursor/selection.
process_text_input :: proc(rt: ^Runtime, id: Node_ID, text: string) -> Text_Change {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field {
		return Text_Change{id, "", false}
	}
	if len(text) == 0 && node.composition.active {
		cancel_text_composition(rt, id, "empty committed text canceled composition")
		return Text_Change{id, owned(node.text, rt.persistent_allocator), false}
	}
	if node.composition.active {
		replace_anchor := node.composition.replace_anchor
		replace_focus := node.composition.replace_focus
		node.selection_anchor = replace_anchor
		node.selection_focus = replace_focus
		change := process_text_edit(rt, id, Text_Edit{.Insert, text})
		if clear_text_composition(node, rt.persistent_allocator) {
			invalidate_interaction_paint(rt, id, "text composition committed")
			invalidate_root(rt, "text composition committed")
		}
		return change
	}
	return process_text_edit(rt, id, Text_Edit{.Insert, text})
}

text_field_input_area :: proc(rt: ^Runtime, id: Node_ID) -> (area: Rect, cursor: f32, ok: bool) {
	node, found := rt.nodes[id]
	if !found || !node.active || node.kind != .Text_Field || !node.text_run_valid { return }
	caret := text_field_caret_geometry(rt, id)
	if !caret.valid { return }
	area = node.bounds
	cursor = caret.rect.x - area.x
	if cursor < 0 { cursor = 0 }
	ok = true
	return
}
