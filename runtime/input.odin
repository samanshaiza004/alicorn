package alicorn

import "core:fmt"

hit_test :: proc(rt: ^Runtime, x, y: f32) -> Node_ID {
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		if node, ok := rt.nodes[id]; ok && node.active && !node.disabled && rect_contains(node.bounds, x, y) && rect_contains(node.clip, x, y) {
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
	previous := rt.focused
	if previous == id {
		return true
	}
	if previous != 0 {
		if old, old_ok := rt.nodes[previous]; old_ok && clear_text_composition(old, rt.persistent_allocator) {
			invalidate_interaction_paint(rt, previous, "text composition canceled on focus loss")
		}
	}
	rt.focused = id
	record_trace(rt, .Focus, id, "pointer focus owner assigned")
	invalidate_interaction_paint(rt, previous, "focus lost")
	invalidate_interaction_paint(rt, id, "focus gained")
	invalidate_root(rt, "focus owner changed")
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
		if old, old_ok := rt.nodes[rt.selected]; old_ok {
			old.selected = false
			invalidate_interaction_paint(rt, old.id, "selection lost")
		}
	}
	next.selected = true
	rt.selected = id
	invalidate_interaction_paint(rt, id, "selection gained")
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
				if old, ok := rt.nodes[rt.last_hovered]; ok {
					old.hovered = false
					invalidate_interaction_paint(rt, old.id, "hover lost")
				}
			}
			if target != 0 {
				if next, ok := rt.nodes[target]; ok {
					next.hovered = true
					invalidate_interaction_paint(rt, next.id, "hover gained")
				}
			}
			rt.last_hovered = target
			invalidate_root(rt, "hover target changed")
		}
	} else if event.kind == .Down {
		if rt.captured_node != 0 {
			if old, ok := rt.nodes[rt.captured_node]; ok {
				old.pressed = false
				invalidate_interaction_paint(rt, old.id, "press canceled")
			}
		}
		if target != 0 {
			focus(rt, target)
			if node, ok := rt.nodes[target]; ok {
				// Pointer placement is an explicit cancellation boundary for a
				// platform preedit. The next hit test must use committed text
				// geometry, not the temporary composition projection.
				if node.kind == .Text_Field && clear_text_composition(node, rt.persistent_allocator) {
					invalidate_interaction_paint(rt, node.id, "text composition canceled by pointer")
				}
				node.pressed = true
				invalidate_interaction_paint(rt, node.id, "press began")
				if node.kind == .Text_Field && node.text_run_valid {
					position := text_run_hit_test(&node.text_run, event.x-node.bounds.x, event.y-node.bounds.y)
					node.caret = position
					node.selection_anchor = position
					node.selection_focus = position
					invalidate_interaction_paint(rt, node.id, "pointer assigned text caret")
					record_trace(rt, .Focus, target, "pointer assigned text caret at visual boundary")
				}
			}
			rt.captured_node = target
		}
		rt.activation_node = 0
		record_trace(rt, .Pointer, target, "pointer down hit retained node")
		invalidate_root(rt, "pointer down")
	} else if event.kind == .Up {
		captured := rt.captured_node
		if captured != 0 {
			if node, ok := rt.nodes[captured]; ok {
				node.pressed = false
				invalidate_interaction_paint(rt, node.id, "press ended")
			}
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

invalidate_text_product :: proc(rt: ^Runtime, node: ^Node, reason := "retained text product invalidated") {
	if node.text_run_valid {
		text_run_destroy(&node.text_run)
		node.text_run_valid = false
		node.text_run_generation += 1
	}
	text_composition_run_destroy(node)
	dirty_set(&node.dirty, .Layout, true)
	dirty_set(&node.dirty, .Paint, true)
	dirty_set(&node.dirty, .Composite, true)
	mark_layout_ancestors(rt, node.id)
	if len(node.last_reason) > 0 { delete(node.last_reason, rt.persistent_allocator) }
	node.last_reason = owned(reason, rt.persistent_allocator)
	queue_paint(rt, node.id)
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
	start := node.selection_anchor.byte
	end := node.selection_focus.byte
	if start > end { start, end = end, start }
	start = grapheme_floor_boundary(node.text, start)
	end = grapheme_ceil_boundary(node.text, end)
	if start == end {
			caret := grapheme_floor_boundary(node.text, node.caret.byte)
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
		caret_changed := node.caret.byte != start || node.caret.affinity != .Leading ||
			node.selection_anchor.byte != start || node.selection_focus.byte != start
		node.caret = Text_Position{start, .Leading}
		node.selection_anchor = node.caret
		node.selection_focus = node.caret
		if caret_changed {
			invalidate_interaction_paint(rt, node.id, "empty text edit normalized caret")
			invalidate_root(rt, "empty text edit normalized caret")
		}
	} else if start != end || edit.kind == .Insert {
		old_text := node.text
		node.text = fmt.aprintf("%s%s%s", old_text[:start], edit.text, old_text[end:])
		if len(old_text) > 0 { delete(old_text, rt.persistent_allocator) }
		node.caret = Text_Position{start + len(edit.text), .Leading}
		node.selection_anchor = node.caret
		node.selection_focus = node.caret
		change.changed = start != end || len(edit.text) > 0
		invalidate_text_product(rt, node, "runtime text value changed")
	}
	change.text = owned(node.text, rt.persistent_allocator)
	if change.changed {
		invalidate_interaction_paint(rt, node.id, "text edit caret changed")
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
	node.caret = Text_Position{caret, .Leading}
	node.selection_anchor = node.caret
	node.selection_focus = node.caret
	invalidate_interaction_paint(rt, id, "text caret changed")
	invalidate_root(rt, "text caret changed")
	return true
}

set_text_selection :: proc(rt: ^Runtime, id: Node_ID, start, end: int) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field { return false }
	if start <= end {
		node.selection_anchor = Text_Position{grapheme_floor_boundary(node.text, start), .Leading}
		node.selection_focus = Text_Position{grapheme_ceil_boundary(node.text, end), .Trailing}
	} else {
		node.selection_anchor = Text_Position{grapheme_ceil_boundary(node.text, start), .Trailing}
		node.selection_focus = Text_Position{grapheme_floor_boundary(node.text, end), .Leading}
	}
	node.caret = node.selection_focus
	invalidate_interaction_paint(rt, id, "text selection changed")
	invalidate_root(rt, "text selection changed")
	return true
}

text_field_caret_geometry :: proc(rt: ^Runtime, id: Node_ID) -> Text_Caret_Geometry {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !node.text_run_valid {
		return Text_Caret_Geometry{}
	}
	geometry := text_run_caret_geometry(&node.text_run, node.caret)
	if node.composition.active && node.composition_run_valid {
		geometry = text_run_caret_geometry(&node.composition_run, text_composition_visual_position(node))
	}
	geometry.rect.x += node.bounds.x
	geometry.rect.y += node.bounds.y
	return geometry
}

text_field_hit_test :: proc(rt: ^Runtime, id: Node_ID, x, y: f32) -> Text_Position {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !node.text_run_valid {
		return Text_Position{}
	}
	return text_run_hit_test(&node.text_run, x-node.bounds.x, y-node.bounds.y)
}

text_field_selection_rects :: proc(rt: ^Runtime, id: Node_ID, allocator := context.allocator) -> [dynamic]Text_Selection_Rect {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !node.text_run_valid {
		return make([dynamic]Text_Selection_Rect, 0, 4, allocator)
	}
	result := text_run_selection_rects(
		&node.text_run,
		node.selection_anchor,
		node.selection_focus,
		allocator,
	)
	for &selection in result {
		selection.rect.x += node.bounds.x
		selection.rect.y += node.bounds.y
	}
	return result
}
