package text_interaction

import runa "../third_party/Runa"

Text_Selection_Granularity :: enum { Character, Word, Line }

Text_Selection_Range :: struct {
	start, end: int,
}

Text_Selection_Endpoints :: struct {
	anchor, focus: int,
}

// A pointer selection keeps its original granularity and range until capture
// ends. It is independent of GUI state and can be used by editors that map
// display positions to their own source coordinates.
Text_Selection_Drag_State :: struct {
	active: bool,
	granularity: Text_Selection_Granularity,
	anchor: int,
	initial_range: Text_Selection_Range,
}

text_selection_position_normalize :: proc(value: string, position: int) -> int {
	byte := clamp(position, 0, len(value))
	if byte == 0 || byte == len(value) { return byte }
	last := 0
	iterator := runa.grapheme_iter_make(value)
	for {
		start, end, ok := runa.grapheme_iter_next(&iterator)
		if !ok { break }
		if byte < end { return start }
		last = end
	}
	return last
}

text_selection_granularity_for_click_count :: proc(click_count: u8) -> Text_Selection_Granularity {
	if click_count >= 3 { return .Line }
	if click_count == 2 { return .Word }
	return .Character
}

// Word selection uses the same Runa UAX #29 segments as keyboard word
// movement. Separator segments are intentionally selectable too, matching
// double-click behavior over punctuation and whitespace.
text_selection_word_range_at :: proc(value: string, position: int) -> (range: Text_Selection_Range, found: bool) {
	byte := text_selection_position_normalize(value, position)
	iterator := runa.word_iter_make(value)
	last := Text_Selection_Range{}
	has_last := false
	for {
		start, end, ok := runa.word_iter_next(&iterator)
		if !ok { break }
		current := Text_Selection_Range{start, end}
		if byte >= start && byte < end {
			return current, true
		}
		last, has_last = current, true
	}
	if byte == len(value) && has_last {
		return last, true
	}
	return
}

// Line selection returns the content of the logical line, excluding LF, CR,
// or CRLF. A position in the middle of CRLF belongs to the preceding line.
text_selection_line_range_at :: proc(value: string, position: int) -> Text_Selection_Range {
	byte := text_selection_position_normalize(value, position)
	if byte > 0 && byte < len(value) && value[byte-1] == '\r' && value[byte] == '\n' {
		byte -= 1
	}
	start := byte
	for start > 0 {
		previous := value[start-1]
		if previous == '\r' || previous == '\n' { break }
		start -= 1
	}
	end := byte
	for end < len(value) {
		current := value[end]
		if current == '\r' || current == '\n' { break }
		end += 1
	}
	return Text_Selection_Range{start, end}
}

text_selection_range_at :: proc(
	value: string,
	position: int,
	granularity: Text_Selection_Granularity,
) -> (range: Text_Selection_Range, found: bool) {
	switch granularity {
	case .Character:
		byte := text_selection_position_normalize(value, position)
		return Text_Selection_Range{byte, byte}, true
	case .Word:
		return text_selection_word_range_at(value, position)
	case .Line:
		range = text_selection_line_range_at(value, position)
		return range, true
	}
	return
}

text_selection_drag_begin :: proc(
	value: string,
	position: int,
	click_count: u8,
	shift: bool,
	existing_anchor: int,
) -> (state: Text_Selection_Drag_State, endpoints: Text_Selection_Endpoints) {
	byte := text_selection_position_normalize(value, position)
	granularity := text_selection_granularity_for_click_count(click_count)
	if granularity != .Character {
		if range, found := text_selection_range_at(value, byte, granularity); found {
			state = Text_Selection_Drag_State{
				active=true,
				granularity=granularity,
				anchor=range.start,
				initial_range=range,
			}
			return state, Text_Selection_Endpoints{range.start, range.end}
		}
		// Empty fields have no word under the pointer. Treat that click as a
		// character gesture so pointer capture still behaves consistently.
		granularity = .Character
	}
	anchor := byte
	if shift { anchor = text_selection_position_normalize(value, existing_anchor) }
	start, end := anchor, byte
	if start > end { start, end = end, start }
	state = Text_Selection_Drag_State{
		active=true,
		granularity=.Character,
		anchor=anchor,
		initial_range=Text_Selection_Range{start, end},
	}
	return state, Text_Selection_Endpoints{anchor, byte}
}

// text_selection_range_extend keeps the original selected range stable while
// the pointer crosses it, then extends from the opposite edge in either
// direction. `current` is produced by the consumer's source/display mapping.
text_selection_range_extend :: proc(
	initial, current: Text_Selection_Range,
) -> Text_Selection_Endpoints {
	if current.end <= initial.start {
		return Text_Selection_Endpoints{initial.end, current.start}
	}
	if current.start >= initial.end {
		return Text_Selection_Endpoints{initial.start, current.end}
	}
	return Text_Selection_Endpoints{initial.start, initial.end}
}

text_selection_drag_extend :: proc(
	value: string,
	state: Text_Selection_Drag_State,
	position: int,
) -> (endpoints: Text_Selection_Endpoints, changed: bool) {
	if !state.active { return }
	byte := text_selection_position_normalize(value, position)
	if state.granularity == .Character {
		return Text_Selection_Endpoints{state.anchor, byte}, true
	}
	current, found := text_selection_range_at(value, byte, state.granularity)
	if !found { return }
	return text_selection_range_extend(state.initial_range, current), true
}
