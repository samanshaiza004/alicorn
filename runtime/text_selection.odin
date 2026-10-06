package alicorn

Text_Selection_Granularity :: enum { Character, Word, Line }

Text_Selection_Range :: struct {
	start, end: int,
}

Text_Selection_Endpoints :: struct {
	anchor, focus: int,
}

// A pointer selection keeps its original granularity and range until capture
// ends. This value is independent of Runtime and can also be used by editors
// that map display positions to their own source coordinates.
Text_Selection_Drag_State :: struct {
	active: bool,
	granularity: Text_Selection_Granularity,
	anchor: int,
	initial_range: Text_Selection_Range,
}

text_selection_position_normalize :: proc(value: string, position: int) -> int {
	byte := clamp(position, 0, len(value))
	return grapheme_floor_boundary(value, byte)
}

text_selection_granularity_for_click_count :: proc(click_count: u8) -> Text_Selection_Granularity {
	if click_count >= 3 { return .Line }
	if click_count == 2 { return .Word }
	return .Character
}

// Word selection uses the same Runa UAX #29 segments as keyboard word
// movement. Separator segments are intentionally selectable too, matching
// double-click behavior over punctuation and whitespace.
text_selection_word_range_at :: proc(value: string, position: int, scratch_allocator := context.temp_allocator) -> (range: Text_Selection_Range, found: bool) {
	byte := text_selection_position_normalize(value, position)
	ranges := text_word_ranges(value, scratch_allocator)
	defer delete(ranges)
	for word in ranges {
		if byte >= word.start && byte < word.end {
			return Text_Selection_Range{word.start, word.end}, true
		}
	}
	if byte == len(value) && len(ranges) > 0 {
		last := ranges[len(ranges)-1]
		return Text_Selection_Range{last.start, last.end}, true
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
	scratch_allocator := context.temp_allocator,
) -> (range: Text_Selection_Range, found: bool) {
	switch granularity {
	case .Character:
		byte := text_selection_position_normalize(value, position)
		return Text_Selection_Range{byte, byte}, true
	case .Word:
		return text_selection_word_range_at(value, position, scratch_allocator)
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
	scratch_allocator := context.temp_allocator,
) -> (state: Text_Selection_Drag_State, endpoints: Text_Selection_Endpoints) {
	byte := text_selection_position_normalize(value, position)
	granularity := text_selection_granularity_for_click_count(click_count)
	if granularity != .Character {
		if range, found := text_selection_range_at(value, byte, granularity, scratch_allocator); found {
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
	scratch_allocator := context.temp_allocator,
) -> (endpoints: Text_Selection_Endpoints, changed: bool) {
	if !state.active { return }
	byte := text_selection_position_normalize(value, position)
	if state.granularity == .Character {
		return Text_Selection_Endpoints{state.anchor, byte}, true
	}
	current, found := text_selection_range_at(value, byte, state.granularity, scratch_allocator)
	if !found { return }
	return text_selection_range_extend(state.initial_range, current), true
}
