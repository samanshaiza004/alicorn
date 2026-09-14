package alicorn

import "core:fmt"

hit_test :: proc(rt: ^Runtime, x, y: f32) -> Node_ID {
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		if node, ok := rt.nodes[id]; ok && node.active && rect_contains(node.bounds, x, y) && rect_contains(node.clip, x, y) {
			if node.kind == .Button || node.kind == .Text_Field || node.kind == .Custom_Surface {
				return id
			}
		}
	}
	return 0
}

focus :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || !node.focusable {
		return false
	}
	rt.focused = id
	record_trace(rt, .Focus, id, "pointer focus owner assigned")
	return true
}

// Selection is an explicit runtime projection of an application choice. It
// is not inferred from arbitrary application memory and disappears
// deterministically when its retained node leaves the description.
select :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	next, ok := rt.nodes[id]
	if !ok || !next.active { return false }
	if rt.selected == id { return true }
	if rt.selected != 0 {
		if old, old_ok := rt.nodes[rt.selected]; old_ok { old.selected = false }
	}
	next.selected = true
	rt.selected = id
	record_trace(rt, .Focus, id, "selection owner assigned")
	invalidate_root(rt, "selection changed")
	return true
}

process_pointer :: proc(rt: ^Runtime, event: Pointer_Event) -> Node_ID {
	rt.stats.pointer_events += 1
	target := hit_test(rt, event.x, event.y)
	if event.kind == .Move {
		if target != rt.last_hovered {
			if rt.last_hovered != 0 {
				if old, ok := rt.nodes[rt.last_hovered]; ok { old.hovered = false }
			}
			if target != 0 {
				if next, ok := rt.nodes[target]; ok { next.hovered = true }
			}
			rt.last_hovered = target
			invalidate_root(rt, "hover target changed")
		}
	} else if event.kind == .Down {
		if rt.captured_node != 0 {
			if old, ok := rt.nodes[rt.captured_node]; ok { old.pressed = false }
		}
		if target != 0 {
			focus(rt, target)
			if node, ok := rt.nodes[target]; ok { node.pressed = true }
			rt.captured_node = target
		}
		rt.activation_node = 0
		record_trace(rt, .Pointer, target, "pointer down hit retained node")
		invalidate_root(rt, "pointer down")
	} else if event.kind == .Up {
		captured := rt.captured_node
		if captured != 0 {
			if node, ok := rt.nodes[captured]; ok { node.pressed = false }
			rt.captured_node = 0
		}
		if captured != 0 && captured == target {
			rt.activation_sequence += 1
			rt.activation_node = captured
		} else {
			rt.activation_node = 0
		}
		record_trace(rt, .Pointer, target, "pointer up hit retained node")
		invalidate_root(rt, "pointer up")
	}
	return target
}

process_text_edit :: proc(rt: ^Runtime, id: Node_ID, edit: Text_Edit) -> Text_Change {
	change := Text_Change{id, "", false}
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field {
		return change
	}
	if !focus(rt, id) {
		return change
	}
	start := node.selection_start
	end := node.selection_end
	if start > end { start, end = end, start }
	start = grapheme_floor_boundary(node.text, start)
	end = grapheme_ceil_boundary(node.text, end)
	if start == end {
		caret := grapheme_floor_boundary(node.text, node.caret_byte)
		switch edit.kind {
		case .Insert:
			start, end = caret, caret
		case .Backspace:
			if caret > 0 {
				start, end = grapheme_floor_boundary(node.text, caret-1), caret
			}
		case .Delete:
			if caret < len(node.text) {
				start, end = caret, grapheme_ceil_boundary(node.text, caret+1)
			}
		}
	}
	if edit.kind == .Insert && len(edit.text) == 0 && start == end {
		// Empty insertion still leaves a normalized caret, but does not create
		// an application-state change.
		node.caret_byte = start
		node.selection_start = start
		node.selection_end = start
	} else if start != end || edit.kind == .Insert {
		old_text := node.text
		node.text = fmt.aprintf("%s%s%s", old_text[:start], edit.text, old_text[end:])
		if len(old_text) > 0 { delete(old_text) }
		node.caret_byte = start + len(edit.text)
		node.selection_start = node.caret_byte
		node.selection_end = node.caret_byte
		change.changed = start != end || len(edit.text) > 0
	}
	change.text = owned(node.text)
	if change.changed {
		node.paint_hash = 0
		invalidate_root(rt, "text edit")
	}
	return change
}

// set_text_caret and set_text_selection are runtime editing primitives. The
// byte offsets are normalized to Runa's UAX #29 grapheme boundaries before
// they are retained, so callers cannot create a caret in the middle of UTF-8
// or an extended grapheme cluster.
set_text_caret :: proc(rt: ^Runtime, id: Node_ID, byte_index: int) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field { return false }
	caret := grapheme_floor_boundary(node.text, byte_index)
	node.caret_byte = caret
	node.selection_start = caret
	node.selection_end = caret
	invalidate_root(rt, "text caret changed")
	return true
}

set_text_selection :: proc(rt: ^Runtime, id: Node_ID, start, end: int) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field { return false }
	low, high := start, end
	if low > high { low, high = high, low }
	lo := grapheme_floor_boundary(node.text, low)
	hi := grapheme_ceil_boundary(node.text, high)
	node.selection_start = lo
	node.selection_end = hi
	node.caret_byte = hi
	invalidate_root(rt, "text selection changed")
	return true
}
