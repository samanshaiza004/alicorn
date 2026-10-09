package alicorn

import "core:testing"

TEXT_SELECTION_POINTER_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

text_selection_pointer_test_build :: proc(rt: ^Runtime) -> Node_ID {
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("text-selection-pointer-root"), style=layout_style(.Column, grow=1))
	id := text_field(&ui, "one two\nhello 世界", key=key_string("text-selection-pointer-field"), style=layout_style(width=300, height=120))
	container_end(&ui)
	end_frame(&ui)
	return id
}

text_selection_pointer_test_point :: proc(rt: ^Runtime, id: Node_ID, byte: int) -> (x, y: f32, ok: bool) {
	node, found := rt.nodes[id]
	if !found || !node.text_run_valid { return }
	position := Text_Position{byte, .Leading}
	line_index := text_run_line_for_byte(&node.text_run, position)
	local_x, x_ok := text_run_position_x(&node.text_run, line_index, position, rt.scratch_allocator)
	if !x_ok || line_index < 0 { return }
	line := node.text_run.lines[line_index]
	origin := text_field_run_origin(rt, node, &node.text_run)
	return origin.x+local_x, origin.y+line.y+line.height*0.5, true
}

text_selection_pointer_test_click :: proc(rt: ^Runtime, id: Node_ID, byte: int, click_count: u8, shift := false) -> bool {
	x, y, ok := text_selection_pointer_test_point(rt, id, byte)
	if !ok { return false }
	_ = process_pointer(rt, Pointer_Event{
		kind=.Down,
		x=x,
		y=y,
		button=POINTER_BUTTON_PRIMARY,
		click_count=click_count,
		modifiers=Input_Modifiers{shift=shift},
	})
	return rt.captured_node == id
}

text_selection_pointer_test_move :: proc(rt: ^Runtime, id: Node_ID, byte: int) -> bool {
	x, y, ok := text_selection_pointer_test_point(rt, id, byte)
	if !ok { return false }
	_ = process_pointer(rt, Pointer_Event{kind=.Move, x=x, y=y})
	return true
}

@(test)
test_text_field_pointer_selection_click_drag_and_granularity :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 180})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, TEXT_SELECTION_POINTER_TEST_FONT),
		"the pointer-selection fixture should load a shaped UI font")
	id := text_selection_pointer_test_build(&rt)
	if id == 0 || !rt.nodes[id].text_run_valid {
		testing.expect(t, false, "the fixture should retain a shaped text field")
		return
	}

	if !text_selection_pointer_test_click(&rt, id, 1, 1) {
		testing.expect(t, false, "a primary click should capture the text field")
		return
	}
	_ = text_selection_pointer_test_move(&rt, id, 3)
	field := rt.nodes[id]
	testing.expect(t, field.selection_anchor.byte == 1 && field.selection_focus.byte == 3,
		"click-drag should extend a grapheme-safe character selection from the original anchor")
	if x, y, ok := text_selection_pointer_test_point(&rt, id, 3); ok {
		_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	}
	testing.expect(t, rt.text_field_selection_owner == 0 && rt.captured_node == 0,
		"pointer release should end text selection and release capture")

	if !text_selection_pointer_test_click(&rt, id, 10, 1, true) {
		testing.expect(t, false, "Shift-click should capture the text field")
		return
	}
	field = rt.nodes[id]
	testing.expect(t, field.selection_anchor.byte == 1 && field.selection_focus.byte == 10,
		"Shift-click should extend the existing selection anchor")
	if x, y, ok := text_selection_pointer_test_point(&rt, id, 10); ok {
		_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	}

	if !text_selection_pointer_test_click(&rt, id, 5, 2) {
		testing.expect(t, false, "double-click should capture the text field")
		return
	}
	field = rt.nodes[id]
	testing.expect(t, field.selection_anchor.byte == 4 && field.selection_focus.byte == 7,
		"double-click should select the complete word under the pointer")
	_ = text_selection_pointer_test_move(&rt, id, 10)
	field = rt.nodes[id]
	testing.expect(t, field.selection_anchor.byte == 4 && field.selection_focus.byte == 13,
		"double-click-drag should extend by complete words across a hard line break")
	_ = text_selection_pointer_test_move(&rt, id, 1)
	field = rt.nodes[id]
	testing.expect(t, field.selection_anchor.byte == 7 && field.selection_focus.byte == 0,
		"word drag should reverse direction while retaining the initial word's far edge")
	if x, y, ok := text_selection_pointer_test_point(&rt, id, 1); ok {
		_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	}

	if !text_selection_pointer_test_click(&rt, id, 15, 3) {
		testing.expect(t, false, "triple-click should capture the text field")
		return
	}
	field = rt.nodes[id]
	testing.expect(t, field.selection_anchor.byte == 8 && field.selection_focus.byte == 20,
		"triple-click should select the complete logical line, including Unicode text")
	_ = process_pointer(&rt, Pointer_Event{kind=.Cancel})
	testing.expect(t, rt.text_field_selection_owner == 0 && rt.captured_node == 0,
		"native pointer cancellation should discard the active text selection gesture")
}
