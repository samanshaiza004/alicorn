package alicorn

import "core:testing"
import text_selection "../text_interaction"

@(test)
test_text_selection_click_granularity_and_word_drag_are_stable :: proc(t: ^testing.T) {
	value := "John Michael Smith"
	state, selected := text_selection.text_selection_drag_begin(value, 7, 2, false, 0)
	testing.expect(t, state.active && state.granularity == .Word &&
		selected.anchor == 5 && selected.focus == 12,
		"double-click should select the complete UAX word segment")

	forward, forward_ok := text_selection.text_selection_drag_extend(value, state, 15)
	testing.expect(t, forward_ok && forward.anchor == 5 && forward.focus == 18,
		"word dragging forward should extend through the complete destination word")
	backward, backward_ok := text_selection.text_selection_drag_extend(value, state, 1)
	testing.expect(t, backward_ok && backward.anchor == 12 && backward.focus == 0,
		"word dragging backward should preserve the initial selection's far edge")

	shift_state, shifted := text_selection.text_selection_drag_begin(value, 15, 1, true, 5)
	testing.expect(t, shift_state.granularity == .Character && shifted.anchor == 5 && shifted.focus == 15,
		"Shift-click should preserve the supplied selection anchor")
}

@(test)
test_text_selection_character_drag_never_splits_extended_graphemes :: proc(t: ^testing.T) {
	family :: "👨‍👩‍👧‍👦"
	value :: "x" + family + "y"
	family_start := 1
	family_end := family_start + len(family)
	state, initial := text_selection.text_selection_drag_begin(value, family_start+2, 1, false, 0)
	inside, inside_ok := text_selection.text_selection_drag_extend(value, state, family_start+5)
	end, end_ok := text_selection.text_selection_drag_extend(value, state, family_end)
	testing.expect(t, initial.anchor == family_start && initial.focus == family_start &&
		inside_ok && inside.anchor == family_start && inside.focus == family_start,
		"pointer positions inside an emoji grapheme should normalize to its leading boundary")
	testing.expect(t, end_ok && end.anchor == family_start && end.focus == family_end,
		"dragging past the emoji should select its full grapheme without splitting its bytes")
}

@(test)
test_text_selection_line_ranges_handle_lf_crlf_and_graphemes :: proc(t: ^testing.T) {
	value := "cafe\u0301\r\n日本語\nlast"
	first := text_selection.text_selection_line_range_at(value, 6)
	testing.expect(t, first.start == 0 && first.end == 6,
		"a position in CRLF should select the preceding logical line without its terminator")
	second := text_selection.text_selection_line_range_at(value, 10)
	testing.expect(t, second.start == 8 && second.end == 17,
		"LF-separated Unicode text should select the complete logical line")

	word, found := text_selection.text_selection_word_range_at(value, 2)
	testing.expect(t, found && word.start == 0 && word.end == 6,
		"word selection should keep a combining grapheme intact")
	if found {
		testing.expect(t, text_selection.text_selection_position_normalize(value, word.start) == word.start &&
			text_selection.text_selection_position_normalize(value, word.end) == word.end,
			"word selection endpoints should remain legal grapheme boundaries")
	}
}

@(test)
test_text_selection_range_extension_preserves_original_edges :: proc(t: ^testing.T) {
	initial := text_selection.Text_Selection_Range{10, 20}
	forward := text_selection.text_selection_range_extend(initial, text_selection.Text_Selection_Range{25, 31})
	backward := text_selection.text_selection_range_extend(initial, text_selection.Text_Selection_Range{2, 8})
	overlap := text_selection.text_selection_range_extend(initial, text_selection.Text_Selection_Range{15, 24})
	testing.expect(t, forward.anchor == 10 && forward.focus == 31,
		"a selection dragged beyond its initial end should retain the initial start")
	testing.expect(t, backward.anchor == 20 && backward.focus == 2,
		"a selection dragged before its initial start should retain the initial end")
	testing.expect(t, overlap.anchor == 10 && overlap.focus == 20,
		"a selection dragged back across its original range should restore that range")
}
