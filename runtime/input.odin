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
		if target != 0 {
			focus(rt, target)
			if rt.pressed_node != 0 {
				if old, ok := rt.nodes[rt.pressed_node]; ok { old.pressed = false }
			}
			if node, ok := rt.nodes[target]; ok { node.pressed = true }
			rt.pressed_node = target
			rt.activation_sequence += 1
			rt.activation_node = target
		}
		record_trace(rt, .Pointer, target, "pointer down hit retained node")
		invalidate_root(rt, "pointer down")
	} else if event.kind == .Up {
		if rt.pressed_node != 0 {
			if node, ok := rt.nodes[rt.pressed_node]; ok { node.pressed = false }
			rt.pressed_node = 0
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
	if edit.kind == .Insert {
		old_text := node.text
		node.text = fmt.aprintf("%s%s", node.text, edit.text)
		if len(old_text) > 0 { delete(old_text) }
		change.changed = len(edit.text) > 0
	} else if edit.kind == .Backspace {
		if len(node.text) > 0 {
			old_text := node.text
			node.text = owned(node.text[:len(node.text)-1])
			if len(old_text) > 0 { delete(old_text) }
			change.changed = true
		}
	} else if edit.kind == .Delete {
		if len(node.text) > 0 {
			old_text := node.text
			node.text = owned(node.text[1:])
			if len(old_text) > 0 { delete(old_text) }
			change.changed = true
		}
	}
	change.text = owned(node.text)
	if change.changed {
		node.paint_hash = 0
		invalidate_root(rt, "text edit")
	}
	return change
}
