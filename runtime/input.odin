package alicorn

import "core:mem"
import "core:strings"

Focus_Direction :: enum {
	Next,
	Previous,
}

Scrollbar_Hit :: struct {
	node: Node_ID,
	axis: Scroll_Axis,
	thumb: bool,
}

scrollbar_hit_test :: proc(rt: ^Runtime, x, y: f32) -> Scrollbar_Hit {
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		node, ok := rt.nodes[id]
		if !ok || !node.active || node.kind != .Scroll_Region || !rect_contains(node.clip, x, y) { continue }
		if node.scrollbar_vertical_visible && rect_contains(node.scrollbar_vertical_track, x, y) {
			return Scrollbar_Hit{id, .Vertical, rect_contains(node.scrollbar_vertical_thumb, x, y)}
		}
		if node.scrollbar_horizontal_visible && rect_contains(node.scrollbar_horizontal_track, x, y) {
			return Scrollbar_Hit{id, .Horizontal, rect_contains(node.scrollbar_horizontal_thumb, x, y)}
		}
	}
	return {}
}

scrollbar_handle_pointer :: proc(rt: ^Runtime, event: Pointer_Event) -> bool {
	if rt.scrollbar_drag_node == 0 || event.kind != .Move && event.kind != .Up { return false }
	id := rt.scrollbar_drag_node
	node, ok := rt.nodes[id]
	if event.kind == .Up || !ok || !node.active {
		rt.scrollbar_drag_node = 0
		rt.captured_node = 0
		return true
	}
	if rt.scrollbar_drag_axis == .Vertical {
		track := node.scrollbar_vertical_track
		thumb := node.scrollbar_vertical_thumb
		travel := track.h-thumb.h
		max_scroll := maxf(node.scroll_content_height-node.scroll_viewport_height, 0)
		if travel > 0 && max_scroll > 0 {
			_ = scroll_region_set_offset(rt, id, rt.scrollbar_drag_offset_origin+(event.y-rt.scrollbar_drag_pointer_origin)/travel*max_scroll, "vertical scrollbar drag")
		}
	} else {
		track := node.scrollbar_horizontal_track
		thumb := node.scrollbar_horizontal_thumb
		travel := track.w-thumb.w
		max_scroll := maxf(node.scroll_content_width-node.scroll_viewport_width, 0)
		if travel > 0 && max_scroll > 0 {
			_ = scroll_region_set_offset_x(rt, id, rt.scrollbar_drag_offset_origin+(event.x-rt.scrollbar_drag_pointer_origin)/travel*max_scroll, "horizontal scrollbar drag")
		}
	}
	return true
}

// cancel_pointer_capture is the host boundary for focus loss or native input
// cancellation. SDL auto-captures mouse motion while a button is held, but a
// focus transition can interrupt the matching pointer-up; clearing runtime
// capture here prevents a scrollbar drag or pressed button from sticking.
cancel_pointer_capture :: proc(rt: ^Runtime) -> bool {
	captured := rt.captured_node
	dragging := rt.scrollbar_drag_node != 0
	if captured == 0 && !dragging { return false }
	if node, ok := rt.nodes[captured]; ok && node.pressed {
		node.pressed = false
		invalidate_interaction_paint(rt, captured, "pointer capture canceled by host")
	}
	rt.captured_node = 0
	rt.scrollbar_drag_node = 0
	record_trace_literal(rt, .Pointer, captured, "pointer capture canceled by host")
	return true
}

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

scroll_region_hit_test :: proc(rt: ^Runtime, x, y: f32) -> Node_ID {
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		if node, ok := rt.nodes[id]; ok && node.active && node.kind == .Scroll_Region &&
			rect_contains(node.bounds, x, y) && rect_contains(node.clip, x, y) {
			return id
		}
	}
	return 0
}

// process_scroll routes wheel input to the retained scroll region under the
// pointer. Applications only receive scroll events that do not belong to an
// Alicorn-owned region.
process_scroll :: proc(rt: ^Runtime, event: Scroll_Event) -> bool {
	id := scroll_region_hit_test(rt, event.x, event.y)
	if id == 0 { return false }
	node, ok := rt.nodes[id]
	if !ok { return false }
	// SDL's floating-point values carry precise trackpad motion. The integer
	// fields are accumulated whole ticks, not a higher-quality replacement;
	// using them here creates large discontinuities on precise devices.
	delta_y := event.delta_y
	delta_x := event.delta_x
	if node.scroll_axes == .Vertical {
		delta_x = 0
	} else if node.scroll_axes == .Horizontal {
		delta_y = 0
	} else if node.scroll_axis_behavior == .Auto_Lock && delta_x != 0 && delta_y != 0 {
		if abs(delta_x) > abs(delta_y) {
			delta_y = 0
		} else {
			delta_x = 0
		}
	}
	line_height := node.scroll_line_height
	if line_height <= 0 { line_height = 24 }
	line_width := node.scroll_line_width
	if line_width <= 0 { line_width = 24 }
	if delta_y != 0 {
		_ = scroll_region_set_offset(rt, id, node.scroll_offset_y-delta_y*line_height, "scroll region wheel")
	}
	if delta_x != 0 {
		_ = scroll_region_set_offset_x(rt, id, node.scroll_offset_x-delta_x*line_width, "horizontal scroll region wheel")
	}
	return true
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
	record_trace(rt, .Focus, id, "focus owner assigned")
	invalidate_interaction_paint(rt, previous, "focus lost")
	invalidate_interaction_paint(rt, id, "focus gained")
	invalidate_root(rt, "focus owner changed")
	return true
}

// focus_traverse moves focus through the retained preorder used by the
// runtime. This keeps keyboard navigation independent of application-owned
// widget objects while preserving the same keyed focus state as pointer input.
focus_traverse :: proc(rt: ^Runtime, direction: Focus_Direction) -> Node_ID {
	if len(rt.order) == 0 { return 0 }

	step := 1
	start := 0
	if direction == .Previous {
		step = -1
		start = len(rt.order) - 1
	}
	if rt.focused != 0 {
		for id, index in rt.order {
			if id == rt.focused {
				start = index + step
				break
			}
		}
	}

	for offset := 0; offset < len(rt.order); offset += 1 {
		index := start + offset*step
		for index < 0 { index += len(rt.order) }
		for index >= len(rt.order) { index -= len(rt.order) }
		id := rt.order[index]
		node, ok := rt.nodes[id]
		if ok && node.active && node.focusable && !node.disabled {
			if focus(rt, id) { return id }
		}
	}
	return 0
}

// activate_focused feeds a keyboard activation through the same retained
// button contract used by pointer-up. The button consumes this sequence during
// the next description pass, so activation remains one-shot and application
// code only observes its public clicked result.
activate_focused :: proc(rt: ^Runtime) -> bool {
	id := rt.focused
	node, ok := rt.nodes[id]
	if !ok || !node.active || !node.focusable || node.disabled || node.kind != .Button {
		return false
	}
	rt.activation_sequence += 1
	rt.activation_node = id
	record_trace(rt, .Focus, id, "focused button activated")
	invalidate_interaction_paint(rt, id, "focused button activated")
	invalidate_root(rt, "focused button activated")
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
	if scrollbar_handle_pointer(rt, event) {
		return rt.scrollbar_drag_node if rt.scrollbar_drag_node != 0 else rt.captured_node
	}
	target := hit_test(rt, event.x, event.y)
	if event.kind == .Down {
		if rt.captured_node != 0 || rt.scrollbar_drag_node != 0 {
			_ = cancel_pointer_capture(rt)
		}
		bar_hit := scrollbar_hit_test(rt, event.x, event.y)
		if bar_hit.node != 0 {
			node := rt.nodes[bar_hit.node]
			if bar_hit.thumb {
				rt.scrollbar_drag_node = bar_hit.node
				rt.scrollbar_drag_axis = bar_hit.axis
				if bar_hit.axis == .Vertical {
					rt.scrollbar_drag_pointer_origin = event.y
					rt.scrollbar_drag_offset_origin = node.scroll_offset_y
				} else {
					rt.scrollbar_drag_pointer_origin = event.x
					rt.scrollbar_drag_offset_origin = node.scroll_offset_x
				}
				rt.captured_node = bar_hit.node
				record_trace_literal(rt, .Pointer, bar_hit.node, "scrollbar thumb drag began")
			} else if bar_hit.axis == .Vertical {
				position := event.y
				if position < node.scrollbar_vertical_thumb.y {
					_ = scroll_region_set_offset(rt, bar_hit.node, node.scroll_offset_y-node.scroll_viewport_height, "vertical scrollbar page backward")
				} else {
					_ = scroll_region_set_offset(rt, bar_hit.node, node.scroll_offset_y+node.scroll_viewport_height, "vertical scrollbar page forward")
				}
			} else {
				position := event.x
				if position < node.scrollbar_horizontal_thumb.x {
					_ = scroll_region_set_offset_x(rt, bar_hit.node, node.scroll_offset_x-node.scroll_viewport_width, "horizontal scrollbar page backward")
				} else {
					_ = scroll_region_set_offset_x(rt, bar_hit.node, node.scroll_offset_x+node.scroll_viewport_width, "horizontal scrollbar page forward")
				}
			}
			return bar_hit.node
		}
	}
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
			// Hover only changes retained presentation state. The application
			// description remains valid and must not be rebuilt just to repaint
			// the old and new hover targets.
		}
	} else if event.kind == .Down {
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
					position := text_run_hit_test(&node.text_run, event.x-node.bounds.x, event.y-node.bounds.y, rt.scratch_allocator)
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

text_replace_owned :: proc(value, insert: string, start, end: int, allocator: mem.Allocator) -> string {
	result_length := len(value) - (end-start) + len(insert)
	builder := strings.builder_make(0, result_length, allocator)
	strings.write_string(&builder, value[:start])
	strings.write_string(&builder, insert)
	strings.write_string(&builder, value[end:])
	return strings.to_string(builder)
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
		}
	} else if start != end || edit.kind == .Insert {
		old_text := node.text
		node.text = text_replace_owned(old_text, edit.text, start, end, rt.persistent_allocator)
		if len(old_text) > 0 { delete(old_text, rt.persistent_allocator) }
		caret := grapheme_ceil_boundary(node.text, start+len(edit.text))
		node.caret = Text_Position{caret, .Leading}
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
set_text_position :: proc(rt: ^Runtime, id: Node_ID, position: Text_Position) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field { return false }
	caret := grapheme_floor_boundary(node.text, position.byte)
	next := Text_Position{caret, position.affinity}
	changed := node.caret != next || node.selection_anchor != next || node.selection_focus != next
	node.caret = next
	node.selection_anchor = next
	node.selection_focus = next
	if changed {
		invalidate_interaction_paint(rt, id, "text caret changed")
	}
	return true
}

set_text_caret :: proc(rt: ^Runtime, id: Node_ID, byte_index: int) -> bool {
	return set_text_position(rt, id, Text_Position{byte_index, .Leading})
}

set_text_selection :: proc(rt: ^Runtime, id: Node_ID, start, end: int) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field { return false }
	anchor: Text_Position
	focus_position: Text_Position
	if start <= end {
		anchor = Text_Position{grapheme_floor_boundary(node.text, start), .Leading}
		focus_position = Text_Position{grapheme_ceil_boundary(node.text, end), .Trailing}
	} else {
		anchor = Text_Position{grapheme_ceil_boundary(node.text, start), .Trailing}
		focus_position = Text_Position{grapheme_floor_boundary(node.text, end), .Leading}
	}
	changed := node.selection_anchor != anchor || node.selection_focus != focus_position || node.caret != focus_position
	node.selection_anchor = anchor
	node.selection_focus = focus_position
	node.caret = focus_position
	if changed {
		invalidate_interaction_paint(rt, id, "text selection changed")
	}
	return true
}

// process_text_command is the platform-neutral command boundary. It keeps
// host key maps out of the runtime while making word behavior identical on
// every platform. Movement changes only retained interaction presentation;
// deletion delegates to the existing edit path so application text changes
// keep the established Text_Change contract.
process_text_command :: proc(rt: ^Runtime, id: Node_ID, command: Text_Command) -> Text_Change {
	change := Text_Change{id, "", false}
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !focus(rt, id) {
		return change
	}

	switch command {
	case .Move_Left:
		position := text_move_logical(node.text, node.caret, -1)
		_ = set_text_position(rt, id, position)
	case .Move_Right:
		position := text_move_logical(node.text, node.caret, 1)
		_ = set_text_position(rt, id, position)
	case .Move_Word_Left:
		position := text_move_word(node.text, node.caret, -1, rt.scratch_allocator)
		_ = set_text_position(rt, id, position)
	case .Move_Word_Right:
		position := text_move_word(node.text, node.caret, 1, rt.scratch_allocator)
		_ = set_text_position(rt, id, position)
	case .Delete_Backward:
		return process_text_edit(rt, id, Text_Edit{.Backspace, ""})
	case .Delete_Forward:
		return process_text_edit(rt, id, Text_Edit{.Delete, ""})
	case .Delete_Word_Backward, .Delete_Word_Forward:
		if node.selection_anchor.byte != node.selection_focus.byte {
			return process_text_edit(rt, id, Text_Edit{.Backspace, ""})
		}
		caret := grapheme_floor_boundary(node.text, node.caret.byte)
		start, end := caret, caret
		if command == .Delete_Word_Backward {
			start = text_move_word(node.text, Text_Position{caret, node.caret.affinity}, -1, rt.scratch_allocator).byte
		} else {
			end = text_move_word(node.text, Text_Position{caret, node.caret.affinity}, 1, rt.scratch_allocator).byte
		}
		if start != end {
			node.selection_anchor = Text_Position{start, .Leading}
			node.selection_focus = Text_Position{end, .Trailing}
			return process_text_edit(rt, id, Text_Edit{.Delete, ""})
		}
	}
	return change
}

text_field_caret_geometry :: proc(rt: ^Runtime, id: Node_ID) -> Text_Caret_Geometry {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !node.text_run_valid {
		return Text_Caret_Geometry{}
	}
	geometry := text_run_caret_geometry(&node.text_run, node.caret, rt.scratch_allocator)
	if node.composition.active && node.composition_run_valid {
		geometry = text_run_caret_geometry(&node.composition_run, text_composition_visual_position(node), rt.scratch_allocator)
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
	return text_run_hit_test(&node.text_run, x-node.bounds.x, y-node.bounds.y, rt.scratch_allocator)
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
		rt.scratch_allocator,
	)
	for &selection in result {
		selection.rect.x += node.bounds.x
		selection.rect.y += node.bounds.y
	}
	return result
}
