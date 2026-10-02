package alicorn

// drag_source marks the most recently described node as a local drag source.
// The application identity must remain meaningful if virtualization removes
// the node while the drag is in progress.
drag_source :: proc(ui: ^UI, drag_type: Drag_Type, identity: Semantic_ID) -> bool {
	if ui == nil || ui.runtime == nil || drag_type == Drag_Type(0) || !semantic_id_is_valid(identity) { return false }
	if len(ui.runtime.pending) == 0 { return false }
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description { return false }
	description := &ui.runtime.pending[last].description
	description.drag_source_type = drag_type
	description.drag_source_id = identity
	return true
}

// drop_target marks the most recently described node as a target for one
// local drag category. Between modes derive Before/After from the target's
// midpoint; On treats the whole target as a single destination.
drop_target :: proc(ui: ^UI, drag_type: Drag_Type, identity: Semantic_ID, mode: Drop_Target_Mode) -> bool {
	if ui == nil || ui.runtime == nil || drag_type == Drag_Type(0) || !semantic_id_is_valid(identity) { return false }
	if len(ui.runtime.pending) == 0 { return false }
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description { return false }
	description := &ui.runtime.pending[last].description
	description.drop_target_type = drag_type
	description.drop_target_id = identity
	description.drop_target_mode = mode
	return true
}

drag_is_active :: proc(rt: ^Runtime) -> bool {
	return rt != nil && rt.drag.phase == .Dragging
}

drag_session :: proc(rt: ^Runtime) -> Drag_Session {
	if rt == nil { return {} }
	return rt.drag
}

drag_event_take :: proc(rt: ^Runtime) -> (event: Drag_Event, ok: bool) {
	if rt == nil || !rt.drag_event_pending { return {}, false }
	event = rt.drag_event
	rt.drag_event_pending = false
	return event, true
}

drag_event_clear :: proc(rt: ^Runtime) {
	if rt != nil { rt.drag_event_pending = false }
}

drag_cancel :: proc(rt: ^Runtime) -> bool {
	if rt == nil || rt.drag.phase == .Idle { return false }
	drag_cancel_session(rt)
	if node, ok := rt.nodes[rt.captured_node]; ok && node.pressed {
		node.pressed = false
		invalidate_interaction_paint(rt, node.id, "drag canceled")
	}
	rt.captured_node = 0
	rt.activation_node = 0
	return true
}

drag_cancel_session :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase == .Idle { return }
	if rt.drag.phase == .Dragging {
		rt.drag_event = Drag_Event{
			kind=.Cancelled,
			drag_type=rt.drag.drag_type,
			source=rt.drag.source,
			previous_target=rt.drag.target,
		}
		rt.drag_event_pending = true
	}
	drag_clear_target_visual(rt)
	rt.drag = {}
}

drag_clear_target_visual :: proc(rt: ^Runtime) {
	if rt == nil { return }
	if target, ok := rt.nodes[rt.drag.target_node]; ok && target.drop_position != .None {
		target.drop_position = .None
		invalidate_interaction_paint(rt, target.id, "drag target cleared")
	}
}

drag_source_at :: proc(rt: ^Runtime, hit: Node_ID) -> (node: Node_ID, drag_type: Drag_Type, identity: Semantic_ID, found: bool) {
	if rt == nil { return }
	current := hit
	for current != 0 {
		candidate, ok := rt.nodes[current]
		if !ok { break }
		if candidate.active && candidate.drag_source_type != Drag_Type(0) && semantic_id_is_valid(candidate.drag_source_id) {
			return current, candidate.drag_source_type, candidate.drag_source_id, true
		}
		current = candidate.parent
	}
	return
}

drag_target_at :: proc(rt: ^Runtime, hit: Node_ID, drag_type: Drag_Type, x, y: f32) -> (node: Node_ID, identity: Semantic_ID, position: Drop_Position, mode: Drop_Target_Mode) {
	if rt == nil || drag_type == Drag_Type(0) { return }
	current := hit
	for current != 0 {
		candidate, ok := rt.nodes[current]
		if !ok { break }
		if candidate.active && candidate.drop_target_type == drag_type && semantic_id_is_valid(candidate.drop_target_id) {
			position := Drop_Position.On
			#partial switch candidate.drop_target_mode {
			case .On:
			case .Between_Horizontal:
				position = .Before if x < candidate.bounds.x+candidate.bounds.w*0.5 else .After
			case .Between_Vertical:
				position = .Before if y < candidate.bounds.y+candidate.bounds.h*0.5 else .After
			}
			return current, candidate.drop_target_id, position, candidate.drop_target_mode
		}
		current = candidate.parent
	}
	return
}

drag_assign_target :: proc(rt: ^Runtime, node: Node_ID, identity: Semantic_ID, position: Drop_Position, mode: Drop_Target_Mode, emit_event: bool) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	previous := rt.drag.target
	previous_position := rt.drag.position
	previous_node := rt.drag.target_node
	changed := previous != identity || previous_position != position
	next_node := node
	next_identity := identity
	next_position := position
	next_mode := mode
	if previous_node != node {
		if old, ok := rt.nodes[previous_node]; ok && old.drop_position != .None {
			old.drop_position = .None
			invalidate_interaction_paint(rt, old.id, "drag left drop target")
		}
	}
	if next, ok := rt.nodes[next_node]; ok {
		if next.drop_position != next_position {
			next.drop_position = next_position
			invalidate_interaction_paint(rt, next.id, "drag entered drop target")
		}
	} else {
		next_node = 0
		next_identity = {}
		next_position = .None
	}
	rt.drag.target = next_identity
	rt.drag.target_node = next_node
	rt.drag.position = next_position
	rt.drag.target_mode = next_mode
	if changed && emit_event {
		rt.drag_event = Drag_Event{
			kind=.Target_Changed,
			drag_type=rt.drag.drag_type,
			source=rt.drag.source,
			previous_target=previous,
			target=next_identity,
			position=next_position,
		}
		rt.drag_event_pending = true
	}
}

drag_update_target :: proc(rt: ^Runtime, hit: Node_ID, x, y: f32, emit_event := true) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	node, identity, position, mode := drag_target_at(rt, hit, rt.drag.drag_type, x, y)
	drag_assign_target(rt, node, identity, position, mode, emit_event)
}

// drag_refresh_target re-evaluates the retained target after an application
// rebuild changes geometry under a stationary pointer, such as edge autoscroll.
drag_refresh_target :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	hit := hit_test(rt, rt.drag.x, rt.drag.y)
	drag_update_target(rt, hit, rt.drag.x, rt.drag.y)
}

DRAG_AUTOSCROLL_EDGE :: 24.0
DRAG_AUTOSCROLL_MAX_SPEED :: 720.0

// drag_autoscroll_can_step reports whether an active local drag is within the
// edge zone of a scroll region that can still move in that direction. The
// native host uses this to schedule bounded ticks while the pointer is held
// still; ordinary pointer motion remains retained-only.
drag_autoscroll_can_step :: proc(rt: ^Runtime) -> bool {
	_, _, _, found := drag_autoscroll_edge(rt)
	return found
}

// drag_autoscroll_step advances the nearest scroll region under the pointer.
// elapsed_ns is capped so delayed wakeups cannot produce a large jump.
drag_autoscroll_step :: proc(rt: ^Runtime, elapsed_ns: u64) -> bool {
	region_id, direction, strength, found := drag_autoscroll_edge(rt)
	if !found || elapsed_ns == 0 { return false }
	seconds := min(f32(elapsed_ns)*0.000000001, 0.05)
	region := scroll_region_state(rt, region_id)
	return scroll_region_set_offset(
		rt,
		region_id,
		region.offset_y + direction*DRAG_AUTOSCROLL_MAX_SPEED*strength*seconds,
		"drag edge autoscroll",
	)
}

drag_autoscroll_edge :: proc(rt: ^Runtime) -> (region_id: Node_ID, direction, strength: f32, found: bool) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	for index := len(rt.order)-1; index >= 0; index -= 1 {
		id := rt.order[index]
		node, ok := rt.nodes[id]
		if !ok || !node.active || node.kind != .Scroll_Region { continue }
		viewport := node.scroll_viewport_bounds
		if viewport.w <= 0 || viewport.h <= 0 { viewport = node.bounds }
		if rt.drag.x < viewport.x || rt.drag.x > viewport.x+viewport.w { continue }
		top_distance := rt.drag.y-viewport.y
		bottom_distance := viewport.y+viewport.h-rt.drag.y
		if top_distance >= -DRAG_AUTOSCROLL_EDGE && top_distance < DRAG_AUTOSCROLL_EDGE {
			if node.scroll_offset_y <= 0 { continue }
			return id, -1, clampf((DRAG_AUTOSCROLL_EDGE-top_distance)/DRAG_AUTOSCROLL_EDGE, 0.15, 1), true
		}
		if bottom_distance >= -DRAG_AUTOSCROLL_EDGE && bottom_distance < DRAG_AUTOSCROLL_EDGE {
			max_scroll := maxf(node.scroll_content_height-node.scroll_viewport_height, 0)
			if node.scroll_offset_y >= max_scroll { continue }
			return id, 1, clampf((DRAG_AUTOSCROLL_EDGE-bottom_distance)/DRAG_AUTOSCROLL_EDGE, 0.15, 1), true
		}
	}
	return
}

drag_process_pointer :: proc(rt: ^Runtime, event: Pointer_Event, hit: Node_ID) -> bool {
	if rt == nil { return false }
	if event.kind == .Move {
		if rt.drag.phase == .Candidate {
			dx := event.x-rt.drag.start_x
			dy := event.y-rt.drag.start_y
			if dx*dx+dy*dy >= DRAG_START_THRESHOLD*DRAG_START_THRESHOLD {
				if source_node, ok := rt.nodes[rt.drag.source_node]; !ok || !source_node.active {
					rt.drag = {}
					return false
				}
				rt.drag.phase = .Dragging
				rt.drag.x = event.x
				rt.drag.y = event.y
				drag_update_target(rt, hit, event.x, event.y, false)
				rt.drag_event = Drag_Event{
					kind=.Started,
					drag_type=rt.drag.drag_type,
					source=rt.drag.source,
					target=rt.drag.target,
					position=rt.drag.position,
				}
				rt.drag_event_pending = true
			}
		}
		if rt.drag.phase == .Dragging {
			rt.drag.x = event.x
			rt.drag.y = event.y
			drag_update_target(rt, hit, event.x, event.y)
			return true
		}
	} else if event.kind == .Up {
		if rt.drag.phase == .Candidate {
			rt.drag = {}
		} else if rt.drag.phase == .Dragging {
			rt.drag.x = event.x
			rt.drag.y = event.y
			drag_update_target(rt, hit, event.x, event.y, false)
			if rt.drag.target != (Semantic_ID{}) && rt.drag.position != .None {
				rt.drag_event = Drag_Event{
					kind=.Dropped,
					drag_type=rt.drag.drag_type,
					source=rt.drag.source,
					target=rt.drag.target,
					position=rt.drag.position,
				}
				rt.drag_event_pending = true
			} else {
				rt.drag_event = Drag_Event{kind=.Cancelled, drag_type=rt.drag.drag_type, source=rt.drag.source}
				rt.drag_event_pending = true
			}
			drag_clear_target_visual(rt)
			rt.drag = {}
			if node, ok := rt.nodes[rt.captured_node]; ok && node.pressed {
				node.pressed = false
				invalidate_interaction_paint(rt, node.id, "drag released")
			}
			rt.captured_node = 0
			rt.activation_node = 0
			return true
		}
	} else if event.kind == .Cancel {
		drag_cancel_session(rt)
	}
	return false
}
