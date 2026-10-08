package alicorn

import text_selection "../text_interaction"

import "core:mem"
import "core:strings"

Focus_Direction :: enum {
	Next,
	Previous,
}

Activation_Key :: enum {
	Enter,
	Space,
}

Slider_Bound :: enum {
	Minimum,
	Maximum,
}

Scrollbar_Hit :: struct {
	node: Node_ID,
	axis: Scroll_Axis,
	thumb: bool,
}

modal_overlay_root :: proc(rt: ^Runtime) -> Node_ID {
	for index := len(rt.top_level)-1; index >= 0; index -= 1 {
		id := rt.top_level[index]
		if node, ok := rt.nodes[id]; ok && node.active {
			if node.kind == .Modal_Overlay { return id }
			if node.kind == .Context_Menu_Overlay && id == rt.context_menu.overlay &&
				(rt.context_menu.open || rt.context_menu.dismissed) { return id }
		}
	}
	return 0
}

node_is_in_modal_overlay :: proc(rt: ^Runtime, id, overlay_id: Node_ID) -> bool {
	if overlay_id == 0 { return true }
	current := id
	for current != 0 {
		if current == overlay_id { return true }
		node, ok := rt.nodes[current]
		if !ok { return false }
		current = node.parent
	}
	return false
}

scrollbar_hit_test :: proc(rt: ^Runtime, x, y: f32) -> Scrollbar_Hit {
	modal_root := modal_overlay_root(rt)
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		node, ok := rt.nodes[id]
		if !ok || !node.active || node.kind != .Scroll_Region ||
			!node_is_in_modal_overlay(rt, id, modal_root) || !rect_contains(layout_node_finalized_geometry(rt, id).clip, x, y) { continue }
		if node.scrollbar_vertical_visible && rect_contains(layout_finalize_rect(node.scrollbar_vertical_track, rt.presentation_scale_x, rt.presentation_scale_y), x, y) {
			return Scrollbar_Hit{id, .Vertical, rect_contains(layout_finalize_rect(node.scrollbar_vertical_thumb, rt.presentation_scale_x, rt.presentation_scale_y), x, y)}
		}
		if node.scrollbar_horizontal_visible && rect_contains(layout_finalize_rect(node.scrollbar_horizontal_track, rt.presentation_scale_x, rt.presentation_scale_y), x, y) {
			return Scrollbar_Hit{id, .Horizontal, rect_contains(layout_finalize_rect(node.scrollbar_horizontal_thumb, rt.presentation_scale_x, rt.presentation_scale_y), x, y)}
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

text_field_pointer_selection_cancel :: proc(rt: ^Runtime) {
	if rt == nil { return }
	rt.text_field_selection_owner = 0
	rt.text_field_selection_drag = text_selection.Text_Selection_Drag_State{}
}

text_field_pointer_selection_affinities :: proc(
	state: text_selection.Text_Selection_Drag_State,
	endpoints: text_selection.Text_Selection_Endpoints,
	position_affinity: Text_Affinity,
	anchor_affinity: Text_Affinity,
) -> (anchor, focus: Text_Affinity) {
	if state.granularity == .Character { return anchor_affinity, position_affinity }
	if endpoints.anchor <= endpoints.focus { return .Leading, .Trailing }
	return .Trailing, .Leading
}

text_field_pointer_selection_update :: proc(rt: ^Runtime, owner: Node_ID, x, y: f32) -> bool {
	if rt == nil || owner == 0 || rt.text_field_selection_owner != owner ||
		rt.captured_node != owner || !rt.text_field_selection_drag.active { return false }
	node, ok := rt.nodes[owner]
	if !ok || !node.active || node.kind != .Text_Field || !node.text_run_valid { return false }
	bounds := layout_node_finalized_geometry(rt, owner).bounds
	position := text_run_hit_test(&node.text_run, x-bounds.x, y-bounds.y, rt.scratch_allocator)
	endpoints, changed := text_selection.text_selection_drag_extend(
		node.text,
		rt.text_field_selection_drag,
		position.byte,
	)
	if !changed { return false }
	anchor_affinity, focus_affinity := text_field_pointer_selection_affinities(
		rt.text_field_selection_drag,
		endpoints,
		position.affinity,
		node.selection_anchor.affinity,
	)
	anchor := Text_Position{endpoints.anchor, anchor_affinity}
	focus_position := Text_Position{endpoints.focus, focus_affinity}
	if node.selection_anchor == anchor && node.selection_focus == focus_position && node.caret == focus_position { return false }
	node.selection_anchor = anchor
	node.selection_focus = focus_position
	node.caret = focus_position
	invalidate_interaction_paint(rt, owner, "text field pointer selection extended")
	return true
}

// cancel_pointer_capture is the host boundary for focus loss or native input
// cancellation. SDL auto-captures mouse motion while a button is held, but a
// focus transition can interrupt the matching pointer-up; clearing runtime
// capture here prevents a scrollbar drag or pressed button from sticking.
cancel_pointer_capture :: proc(rt: ^Runtime) -> bool {
	captured := rt.captured_node
	dragging := rt.scrollbar_drag_node != 0
	drag_candidate := rt.drag.phase != .Idle
	selection_drag := rt.text_field_selection_owner != 0
	if captured == 0 && !dragging && !drag_candidate && !selection_drag { return false }
	if drag_candidate { drag_cancel_session(rt) }
	if node, ok := rt.nodes[captured]; ok {
		if node.pressed {
			node.pressed = false
			invalidate_interaction_paint(rt, captured, "pointer capture canceled by host")
		}
		if node.kind == .Split_Handle {
			if owner, owner_ok := rt.nodes[node.split_owner]; owner_ok { owner.split_dragging = false }
		}
	}
	text_field_pointer_selection_cancel(rt)
	rt.captured_node = 0
	rt.scrollbar_drag_node = 0
	rt.activation_node = 0
	if rt.last_hovered == captured {
		if node, ok := rt.nodes[captured]; ok {
			node.hovered = false
			invalidate_interaction_paint(rt, captured, "hover cleared with pointer capture")
		}
		rt.last_hovered = 0
		rt.stats.hover_target_transitions += 1
	}
	record_trace_literal(rt, .Pointer, captured, "pointer capture canceled by host")
	return true
}

hit_test :: proc(rt: ^Runtime, x, y: f32, include_reveal_targets := false) -> Node_ID {
	modal_root := modal_overlay_root(rt)
	// A solid scrollbar owns its reserved strip, including the portion that
	// overlaps a split divider's deliberately enlarged grab target.
	if scrollbar_hit_test(rt, x, y).node != 0 { return 0 }
	// Split dividers get priority over pane descendants because their expanded
	// grab area intentionally overlaps both adjacent panes.
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		if node, ok := rt.nodes[id]; ok && node.active && node.kind == .Split_Handle &&
			node_is_in_modal_overlay(rt, id, modal_root) &&
			rect_contains(layout_node_finalized_geometry(rt, id).hit_bounds, x, y) &&
			rect_contains(layout_node_finalized_geometry(rt, id).clip, x, y) {
			return id
		}
	}
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		if node, ok := rt.nodes[id]; ok && node.active && !node.disabled &&
			visual_part_hit_test_visible(rt, id, include_reveal_target=include_reveal_targets) &&
			node_is_in_modal_overlay(rt, id, modal_root) &&
			rect_contains(layout_node_finalized_geometry(rt, id).bounds, x, y) &&
			rect_contains(layout_node_finalized_geometry(rt, id).clip, x, y) {
			if node.kind == .Button || node.kind == .Checkbox || node.kind == .Slider || node.kind == .Text_Field ||
			   (node.kind == .Custom_Surface && node.surface_interaction == .Pointer) ||
			   (node.text_input_target && node.focusable) {
				return id
			}
		}
	}
	// Background drop surfaces are hit-testable only during an active drag.
	// Ordinary pointer hit testing remains restricted to interactive nodes,
	// while blank tree/panel space can still represent a meaningful target.
	if rt.drag.phase == .Dragging {
		for i := len(rt.order)-1; i >= 0; i -= 1 {
			id := rt.order[i]
			if node, ok := rt.nodes[id]; ok && node.active && !node.disabled && visual_part_is_visible(rt, id) &&
				node.drop_target_type == rt.drag.drag_type && semantic_id_is_valid(node.drop_target_id) &&
				node_is_in_modal_overlay(rt, id, modal_root) &&
				rect_contains(layout_node_finalized_geometry(rt, id).bounds, x, y) &&
				rect_contains(layout_node_finalized_geometry(rt, id).clip, x, y) {
				return id
			}
		}
	}
	if overlay, ok := rt.nodes[modal_root]; ok && overlay.active &&
		rect_contains(layout_node_finalized_geometry(rt, modal_root).bounds, x, y) &&
		rect_contains(layout_node_finalized_geometry(rt, modal_root).clip, x, y) {
		if overlay.kind == .Modal_Overlay || overlay.kind == .Context_Menu_Overlay { return modal_root }
	}
	return 0
}

split_drag_coordinate :: proc(node: ^Node, x, y: f32) -> f32 {
	return x if node.split_axis == .Horizontal else y
}

update_split_drag :: proc(rt: ^Runtime, handle: ^Node, x, y: f32) {
	owner, ok := rt.nodes[handle.split_owner]
	if !ok || !owner.active { return }
	// Drag math remains in target logical geometry, matching split placement.
	// Finalized bounds are only for pointer hit testing and presentation.
	total := owner.bounds.w if owner.split_axis == .Horizontal else owner.bounds.h
	total -= 2 * owner.style.padding
	if total < 0 { total = 0 }
	coordinate := split_drag_coordinate(handle, x, y)
	delta := coordinate-owner.split_drag_start_coordinate
	if owner.split_axis == .Horizontal && layout_effective_writing_direction(rt, owner) == .Right_To_Left {
		delta = -delta
	}
	requested := owner.split_drag_start_position + delta
	direction := Layout_Direction.Row if owner.split_axis == .Horizontal else .Column
	min_first, min_second := owner.split_min_first, owner.split_min_second
	max_first, max_second: f32 = -1, -1
	if len(owner.children) == 3 {
		first_pane, first_ok := rt.nodes[owner.children[0]]
		second_pane, second_ok := rt.nodes[owner.children[2]]
		if first_ok { min_first, max_first, _ = layout_split_pane_bounds(rt, owner, first_pane, min_first, direction) }
		if second_ok { min_second, max_second, _ = layout_split_pane_bounds(rt, owner, second_pane, min_second, direction) }
	}
	next := split_clamp_position(total, handle.split_handle_size, requested, min_first, min_second, max_first, max_second)
	if next == owner.split_position { return }
	owner.split_position = next
	owner.split_preferred_position = next
	mark_layout_ancestors(rt, owner.id)
	request_presentation(rt, "split divider dragged")
	record_trace(rt, .Pointer, handle.id, "retained split position changed")
}

scroll_region_hit_test :: proc(rt: ^Runtime, x, y: f32) -> Node_ID {
	modal_root := modal_overlay_root(rt)
	for i := len(rt.order)-1; i >= 0; i -= 1 {
		id := rt.order[i]
		if node, ok := rt.nodes[id]; ok && node.active && node.kind == .Scroll_Region &&
			node_is_in_modal_overlay(rt, id, modal_root) &&
			rect_contains(layout_node_finalized_geometry(rt, id).bounds, x, y) &&
			rect_contains(layout_node_finalized_geometry(rt, id).clip, x, y) {
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
	if id == 0 { return modal_overlay_root(rt) != 0 }
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
	if !ok || !node.active || !node.focusable || !node_is_in_modal_overlay(rt, id, modal_overlay_root(rt)) {
		return false
	}
	previous := rt.focused
	if previous == id {
		return true
	}
	tooltip_dismiss(rt)
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

focus_indicator_set :: proc(rt: ^Runtime, visible: bool) {
	if rt == nil || rt.focus_visible == visible { return }
	rt.focus_visible = visible
	if focused, found := rt.nodes[rt.focused]; found && focused.kind == .Button {
		invalidate_interaction_paint(rt, focused.id, "keyboard focus indicator visibility changed")
	}
}

// focus_traverse moves focus through the retained preorder used by the
// runtime. This keeps keyboard navigation independent of application-owned
// widget objects while preserving the same keyed focus state as pointer input.
focus_traverse :: proc(rt: ^Runtime, direction: Focus_Direction) -> Node_ID {
	if len(rt.order) == 0 { return 0 }
	modal_root := modal_overlay_root(rt)

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
		if ok && node.active && node.focusable && !node.disabled && node_is_in_modal_overlay(rt, id, modal_root) {
			if focus(rt, id) {
				focus_indicator_set(rt, true)
				return id
			}
		}
	}
	return 0
}

// activate_focused feeds a keyboard activation through the same retained
// contract used by pointer-up. Enter activates buttons; Space activates both
// buttons and checkboxes, matching the usual checkbox keyboard convention.
activate_focused :: proc(rt: ^Runtime, key: Activation_Key) -> bool {
	id := rt.focused
	node, ok := rt.nodes[id]
	if !ok { return false }
	can_activate := node.kind == .Button || (node.kind == .Checkbox && key == .Space)
	if !node.active || !node.focusable || node.disabled || !can_activate {
		return false
	}
	focus_indicator_set(rt, true)
	rt.activation_sequence += 1
	rt.activation_node = id
	reason := "focused control activated by Enter" if key == .Enter else "focused control activated by Space"
	record_trace(rt, .Focus, id, reason)
	invalidate_interaction_paint(rt, id, reason)
	invalidate_root(rt, reason)
	return true
}

slider_stage_value :: proc(rt: ^Runtime, node: ^Node, requested: f32, reason: string) -> bool {
	current := node.control_value
	if node.control_pending { current = node.control_pending_value }
	next := slider_normalize(requested, node.control_minimum, node.control_maximum, node.control_step)
	if current == next { return false }
	node.control_pending = true
	node.control_pending_value = next
	record_trace(rt, .Mutation, node.id, reason)
	invalidate_root(rt, reason)
	return true
}

slider_set_from_pointer :: proc(rt: ^Runtime, node: ^Node, x: f32) -> bool {
	if node.kind != .Slider || node.disabled || node.control_maximum <= node.control_minimum { return false }
	bounds := layout_node_finalized_geometry(rt, node.id).bounds
	track_start := bounds.x + minf(8, bounds.w*0.25)
	track_width := maxf(bounds.w - minf(16, bounds.w*0.5), 1)
	position := clampf((x-track_start)/track_width, 0, 1)
	requested := node.control_minimum+position*(node.control_maximum-node.control_minimum)
	return slider_stage_value(rt, node, requested, "slider value changed by pointer")
}

// adjust_focused_slider applies one keyboard step to the focused slider. A
// continuous slider uses one percent of its range; arrows at a bound are
// still consumed without reporting a value change.
adjust_focused_slider :: proc(rt: ^Runtime, direction: int) -> bool {
	if direction == 0 { return false }
	node, ok := rt.nodes[rt.focused]
	if !ok || !node.active || node.kind != .Slider || !node.focusable || node.disabled || node.control_maximum <= node.control_minimum {
		return false
	}
	current := node.control_value
	if node.control_pending { current = node.control_pending_value }
	step := node.control_step
	if step <= 0 { step = (node.control_maximum-node.control_minimum)/100 }
	_ = slider_stage_value(rt, node, current+f32(direction)*step, "slider value changed by keyboard")
	return true
}

// set_focused_slider_bound moves the focused slider to an exact endpoint. It
// consumes the key even if already at that endpoint, so Home/End don't leak
// into unrelated application shortcuts.
set_focused_slider_bound :: proc(rt: ^Runtime, bound: Slider_Bound) -> bool {
	node, ok := rt.nodes[rt.focused]
	if !ok || !node.active || node.kind != .Slider || !node.focusable || node.disabled || node.control_maximum <= node.control_minimum {
		return false
	}
	value := node.control_minimum if bound == .Minimum else node.control_maximum
	_ = slider_stage_value(rt, node, value, "slider moved to range bound by keyboard")
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
			visual_part_invalidate_dependents(rt, old.id, "visual part owner selection changed")
		}
	}
	next.selected = true
	rt.selected = id
	invalidate_interaction_paint(rt, id, "selection gained")
	visual_part_invalidate_dependents(rt, id, "visual part owner selection changed")
	record_trace(rt, .Focus, id, "selection owner assigned")
	invalidate_root(rt, "selection changed")
	return true
}

process_pointer :: proc(rt: ^Runtime, event: Pointer_Event) -> Node_ID {
	rt.stats.pointer_events += 1
	if event.kind == .Down { focus_indicator_set(rt, false) }
	drag_event_clear(rt)
	menu_active := context_menu_input_active(rt)
	rt.context_menu.pointer_consumed = menu_active
	if event.kind != .Move || menu_active { tooltip_dismiss(rt) }
	if event.kind == .Cancel {
		_ = cancel_pointer_capture(rt)
		return 0
	}
	if menu_active && rt.context_menu.open {
		if overlay, ok := rt.nodes[rt.context_menu.overlay]; !ok || !overlay.active {
			// The application has requested a menu but has not described its
			// overlay yet. Do not let the invoking pointer sequence reach content.
			return 0
		}
	}
	if menu_active && rt.context_menu.dismissed { return 0 }
	if scrollbar_handle_pointer(rt, event) {
		tooltip_dismiss(rt)
		return rt.scrollbar_drag_node if rt.scrollbar_drag_node != 0 else rt.captured_node
	}
	target := hit_test(rt, event.x, event.y, include_reveal_targets=event.kind == .Move)
	if event.kind == .Move { tooltip_pointer_update(rt, target, event.timestamp_ns) }
	if menu_active && rt.context_menu.open && event.kind == .Down && target == rt.context_menu.overlay {
		inside_panel := false
		if panel, ok := rt.nodes[rt.context_menu.panel]; ok && panel.active {
			inside_panel = rect_contains(panel.bounds, event.x, event.y) && rect_contains(panel.clip, event.x, event.y)
		}
		if !inside_panel {
			context_menu_close_internal(rt, true)
			record_trace(rt, .Pointer, target, "context menu dismissed by outside click")
			return target
		}
	}
	// Secondary and auxiliary mouse buttons are exposed to the application as
	// context gestures, but they must not press, focus, or activate ordinary
	// retained buttons. A zero button remains accepted for adapters that do not
	// provide button identity.
	if (event.kind == .Down || event.kind == .Up) && event.button != 0 && event.button != POINTER_BUTTON_PRIMARY {
		return target
	}
	if event.kind == .Down {
		if rt.captured_node != 0 || rt.scrollbar_drag_node != 0 || rt.text_field_selection_owner != 0 {
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
		_ = drag_process_pointer(rt, event, target)
		if rt.text_field_selection_owner != 0 {
			_ = text_field_pointer_selection_update(rt, rt.text_field_selection_owner, event.x, event.y)
		}
		hover_target := target
		if captured, ok := rt.nodes[rt.captured_node]; ok && captured.active && captured.kind == .Split_Handle {
			hover_target = captured.id
			update_split_drag(rt, captured, event.x, event.y)
		} else if captured, ok := rt.nodes[rt.captured_node]; ok && captured.active && captured.kind == .Slider {
			hover_target = captured.id
			_ = slider_set_from_pointer(rt, captured, event.x)
		}
		if hover_target != rt.last_hovered {
			if rt.last_hovered != 0 {
				if old, ok := rt.nodes[rt.last_hovered]; ok {
					old.hovered = false
					invalidate_interaction_paint(rt, old.id, "hover lost")
				visual_part_invalidate_dependents(rt, old.id, "visual part owner hover changed")
				}
			}
			if hover_target != 0 {
				if next, ok := rt.nodes[hover_target]; ok {
					next.hovered = true
					invalidate_interaction_paint(rt, next.id, "hover gained")
				visual_part_invalidate_dependents(rt, next.id, "visual part owner hover changed")
				}
			}
			rt.last_hovered = hover_target
			rt.stats.hover_target_transitions += 1
			// Hover only changes retained presentation state. The application
			// description remains valid and must not be rebuilt just to repaint
			// the old and new hover targets.
		}
	} else if event.kind == .Down {
		if target != 0 {
			if event.button == 0 || event.button == POINTER_BUTTON_PRIMARY {
				if _, target_found := rt.nodes[target]; target_found {
					if source_node, drag_type, source_id, found := drag_source_at(rt, target); found {
						rt.drag = Drag_Session{
							phase=.Candidate,
							drag_type=drag_type,
							source=source_id,
							source_node=source_node,
							start_x=event.x,
							start_y=event.y,
							x=event.x,
							y=event.y,
						}
					}
				}
			}
			if node, ok := rt.nodes[target]; ok {
				focus_target := target
				if !node.focusable { focus_target = visual_part_interaction_owner(rt, target) }
				if node.kind != .Split_Handle { _ = focus(rt, focus_target) }
				// Pointer placement is an explicit cancellation boundary for a
				// platform preedit. The next hit test must use committed text
				// geometry, not the temporary composition projection.
				if node.kind == .Text_Field && clear_text_composition(node, rt.persistent_allocator) {
					invalidate_interaction_paint(rt, node.id, "text composition canceled by pointer")
				}
				node.pressed = true
				invalidate_interaction_paint(rt, node.id, "press began")
				if node.kind == .Slider { _ = slider_set_from_pointer(rt, node, event.x) }
				if node.kind == .Split_Handle {
					if owner, owner_ok := rt.nodes[node.split_owner]; owner_ok {
						owner.split_dragging = true
						owner.split_drag_start_position = owner.split_position
						owner.split_drag_start_coordinate = split_drag_coordinate(node, event.x, event.y)
					}
				}
				if node.kind == .Text_Field && node.text_run_valid &&
					(event.button == 0 || event.button == POINTER_BUTTON_PRIMARY) {
					bounds := layout_node_finalized_geometry(rt, node.id).bounds
					position := text_run_hit_test(&node.text_run, event.x-bounds.x, event.y-bounds.y, rt.scratch_allocator)
					drag_state, endpoints := text_selection.text_selection_drag_begin(
						node.text,
						position.byte,
						event.click_count,
						event.modifiers.shift,
						node.selection_anchor.byte,
					)
					rt.text_field_selection_owner = node.id
					rt.text_field_selection_drag = drag_state
					selection_anchor_affinity := position.affinity
					if event.modifiers.shift { selection_anchor_affinity = node.selection_anchor.affinity }
					anchor_affinity, focus_affinity := text_field_pointer_selection_affinities(
						drag_state,
						endpoints,
						position.affinity,
						selection_anchor_affinity,
					)
					node.caret = Text_Position{endpoints.focus, focus_affinity}
					node.selection_anchor = Text_Position{endpoints.anchor, anchor_affinity}
					node.selection_focus = node.caret
					invalidate_interaction_paint(rt, node.id, "pointer assigned text selection")
					record_trace(rt, .Focus, target, "pointer assigned text selection at visual boundary")
				}
			}
			rt.captured_node = target
		}
		rt.activation_node = 0
		record_trace(rt, .Pointer, target, "pointer down hit retained node")
		if target != 0 {
			if node, ok := rt.nodes[target]; ok && node.kind != .Split_Handle {
				invalidate_root(rt, "pointer down")
			}
		}
	} else if event.kind == .Up {
		if rt.text_field_selection_owner != 0 {
			_ = text_field_pointer_selection_update(rt, rt.text_field_selection_owner, event.x, event.y)
		}
		if drag_process_pointer(rt, event, target) {
			text_field_pointer_selection_cancel(rt)
			record_trace(rt, .Pointer, target, "drag dropped")
			return target
		}
		captured := rt.captured_node
		if captured != 0 {
			if node, ok := rt.nodes[captured]; ok {
				if node.kind == .Split_Handle { update_split_drag(rt, node, event.x, event.y) }
				if node.kind == .Slider { _ = slider_set_from_pointer(rt, node, event.x) }
				node.pressed = false
				invalidate_interaction_paint(rt, node.id, "press ended")
				if node.kind == .Split_Handle {
					if owner, owner_ok := rt.nodes[node.split_owner]; owner_ok { owner.split_dragging = false }
				}
			}
			rt.captured_node = 0
		}
		text_field_pointer_selection_cancel(rt)
		captured_is_split := false
		if node, ok := rt.nodes[captured]; ok { captured_is_split = node.kind == .Split_Handle }
		if captured_is_split && captured != target {
			if rt.last_hovered != 0 {
				if previous, ok := rt.nodes[rt.last_hovered]; ok {
					previous.hovered = false
					invalidate_interaction_paint(rt, previous.id, "split pointer released outside hover target")
				}
			}
			if target != 0 {
				if next, ok := rt.nodes[target]; ok {
					next.hovered = true
					invalidate_interaction_paint(rt, target, "pointer target after split release")
				}
			}
			rt.last_hovered = target
			rt.stats.hover_target_transitions += 1
		}
		if !captured_is_split && captured != 0 && captured == target {
			rt.activation_sequence += 1
			if node, ok := rt.nodes[captured]; ok && (node.kind == .Button || node.kind == .Checkbox) {
				rt.activation_node = captured
			} else {
				rt.activation_node = 0
			}
		} else {
			rt.activation_node = 0
		}
		record_trace(rt, .Pointer, target, "pointer up hit retained node")
		if !captured_is_split && (captured != 0 || target != 0) {
			invalidate_root(rt, "pointer up")
		}
	}
	if event.kind == .Up { tooltip_pointer_update(rt, target, event.timestamp_ns) }
	return target
}

invalidate_text_product :: proc(rt: ^Runtime, node: ^Node, reason := "retained text product invalidated") {
	if node.text_run_valid {
		text_run_destroy(&node.text_run)
		node.text_run_valid = false
		node.text_run_generation += 1
		node.text_run_handle_generation = 0
	}
	text_composition_run_destroy(node)
	dirty_set(&node.dirty, .Measure, true)
	dirty_set(&node.dirty, .Paint, true)
	dirty_set(&node.dirty, .Composite, true)
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

// text_node_hit_test maps logical window coordinates to a byte offset local to
// the retained Text or Text_Field node's UTF-8 value. The returned position is
// grapheme-normalized and retains visual affinity. ok is false unless the
// active retained node has a valid shaped run.
text_node_hit_test :: proc(rt: ^Runtime, id: Node_ID, x, y: f32) -> (position: Text_Position, ok: bool) {
	node, found := rt.nodes[id]
	if !found || !node.active || (node.kind != .Text && node.kind != .Text_Field) || !node.text_run_valid || len(node.text_run.lines) == 0 {
		return Text_Position{}, false
	}
	bounds := layout_node_finalized_geometry(rt, id).bounds
	position = text_run_hit_test(&node.text_run, x-bounds.x, y-bounds.y, rt.scratch_allocator)
	return position, true
}

// text_node_caret_geometry returns the retained Text or Text_Field run's caret
// rectangle in absolute logical window coordinates. position.byte is a UTF-8
// byte offset local to the node's text; the run normalizes it to a grapheme
// boundary while honoring its visual affinity. Invalid/unshaped nodes return
// geometry with valid=false.
text_node_caret_geometry :: proc(rt: ^Runtime, id: Node_ID, position: Text_Position) -> Text_Caret_Geometry {
	node, found := rt.nodes[id]
	if !found || !node.active || (node.kind != .Text && node.kind != .Text_Field) || !node.text_run_valid {
		return Text_Caret_Geometry{}
	}
	geometry := text_run_caret_geometry(&node.text_run, position, rt.scratch_allocator)
	if geometry.valid {
		bounds := layout_node_finalized_geometry(rt, id).bounds
		geometry.rect.x += bounds.x
		geometry.rect.y += bounds.y
		geometry.rect = layout_finalize_rect(geometry.rect, rt.presentation_scale_x, rt.presentation_scale_y)
	}
	return geometry
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
	bounds := layout_node_finalized_geometry(rt, id).bounds
	geometry.rect.x += bounds.x
	geometry.rect.y += bounds.y
	geometry.rect = layout_finalize_rect(geometry.rect, rt.presentation_scale_x, rt.presentation_scale_y)
	return geometry
}

text_field_hit_test :: proc(rt: ^Runtime, id: Node_ID, x, y: f32) -> Text_Position {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Text_Field || !node.text_run_valid {
		return Text_Position{}
	}
	bounds := layout_node_finalized_geometry(rt, id).bounds
	return text_run_hit_test(&node.text_run, x-bounds.x, y-bounds.y, rt.scratch_allocator)
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
	bounds := layout_node_finalized_geometry(rt, id).bounds
	for &selection in result {
		selection.rect.x += bounds.x
		selection.rect.y += bounds.y
		selection.rect = layout_finalize_rect(selection.rect, rt.presentation_scale_x, rt.presentation_scale_y)
	}
	return result
}
