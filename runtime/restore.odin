#+vet explicit-allocators
package alicorn

import "core:fmt"
import "core:math"

restore_outcome_pending :: proc(outcome: Restore_Outcome) -> bool {
	return outcome == .Requested || outcome == .Deferred
}

restore_value_is_finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

restore_value_close :: proc(a, b: f32) -> bool {
	return math.abs(a-b) <= 0.016
}

restore_layout_generation :: proc(rt: ^Runtime) -> u64 {
	if rt.frame_open { return rt.stats.frame+1 }
	return rt.stats.frame
}

restore_control_state :: proc(rt: ^Runtime, control: Restore_Control, target: Node_ID) -> ^Restore_Control_State {
	if rt == nil { return nil }
	if control == .Semantic_Focus {
		if target != 0 && rt.semantic_focus.owner != target { return nil }
		return &rt.semantic_focus_restore
	}
	return rt.restore_controls[Restore_Target{control=control, node=target}]
}

restore_request_begin :: proc(
	rt: ^Runtime,
	target: Node_ID,
	control: Restore_Control,
	token: Restore_Token,
	requested: Restore_Value,
) -> (state: ^Restore_Control_State, started: bool) {
	if rt == nil || token == RESTORE_TOKEN_NONE { return }
	state = restore_control_state(rt, control, target)
	if state == nil {
		state = new(Restore_Control_State, allocator=rt.persistent_allocator)
		rt.restore_controls[Restore_Target{control=control, node=target}] = state
	}
	started = restore_start(rt, target, control, state, token, requested)
	return
}

restore_report_record :: proc(rt: ^Runtime, target: Node_ID, state: Restore_Control_State) {
	if rt == nil { return }
	if RESTORE_REPORT_CAPACITY <= 0 { return }
	rt.restore_reports[rt.restore_report_next] = Restore_Report{target=target, state=state}
	rt.restore_report_next = (rt.restore_report_next+1) % RESTORE_REPORT_CAPACITY
	if rt.restore_report_count < RESTORE_REPORT_CAPACITY { rt.restore_report_count += 1 }
	record_trace(rt, .Restore, target,
		fmt.tprintf("restore %v token=%d outcome=%v reason=%v requested=(%.3f,%.3f) preferred=(%.3f,%.3f) resolved=(%.3f,%.3f) semantic=(%d,%d) realized=%d layout=%d",
			state.control, u64(state.token), state.outcome, state.reason,
			state.requested.x, state.requested.y, state.preferred.x, state.preferred.y,
			state.resolved.x, state.resolved.y, state.semantic_id.namespace,
			state.semantic_id.value, state.realized_node, state.layout_generation))
}

restore_set_outcome :: proc(
	rt: ^Runtime,
	target: Node_ID,
	state: ^Restore_Control_State,
	outcome: Restore_Outcome,
	reason: Restore_Reason,
) {
	if rt == nil || state == nil { return }
	generation := restore_layout_generation(rt)
	if state.outcome == outcome && state.reason == reason && state.layout_generation == generation { return }
	state.outcome = outcome
	state.reason = reason
	state.layout_generation = generation
	restore_report_record(rt, target, state^)
}

restore_token_next :: proc(rt: ^Runtime) -> Restore_Token {
	if rt == nil { return RESTORE_TOKEN_NONE }
	rt.restore_token_sequence += 1
	if rt.restore_token_sequence == 0 { rt.restore_token_sequence = 1 }
	return Restore_Token(rt.restore_token_sequence)
}

restore_start :: proc(
	rt: ^Runtime,
	target: Node_ID,
	control: Restore_Control,
	state: ^Restore_Control_State,
	token: Restore_Token,
	requested: Restore_Value,
) -> bool {
	if rt == nil || state == nil || token == RESTORE_TOKEN_NONE { return false }
	if state.token == token { return false }
	if restore_outcome_pending(state.outcome) {
		superseded_target := target
		if control == .Semantic_Focus { superseded_target = rt.semantic_focus.owner }
		restore_set_outcome(rt, superseded_target, state, .Superseded, .Newer_Request)
	}
	state^ = Restore_Control_State{
		token=token,
		control=control,
		outcome=.Requested,
		reason=.Awaiting_Layout,
		requested=requested,
		preferred=requested,
		resolved={},
		described={},
		described_viewport={},
		layout_generation=restore_layout_generation(rt),
	}
	restore_report_record(rt, target, state^)
	valid := restore_value_is_finite(requested.x) && restore_value_is_finite(requested.y)
	if !valid {
		restore_set_outcome(rt, target, state, .Cancelled, .Invalid_Value)
		return true
	}
	return true
}

restore_state_query :: proc(
	rt: ^Runtime,
	control: Restore_Control,
	target: Node_ID,
	token: Restore_Token = RESTORE_TOKEN_NONE,
) -> (state: Restore_Control_State, found: bool) {
	if rt == nil { return }
	for step := 0; step < rt.restore_report_count; step += 1 {
		index := rt.restore_report_next-1-step
		if index < 0 { index += RESTORE_REPORT_CAPACITY }
		report := rt.restore_reports[index]
		if report.target == target && report.state.control == control &&
			(token == RESTORE_TOKEN_NONE || report.state.token == token) {
			return report.state, true
		}
	}
	if current := restore_control_state(rt, control, target); current != nil && current.control == control &&
		(token == RESTORE_TOKEN_NONE || current.token == token) {
		return current^, true
	}
	return
}

// restore_cancel ends a pending request. The token prevents an old async
// completion from cancelling a newer request for the same control.
restore_cancel :: proc(
	rt: ^Runtime,
	control: Restore_Control,
	target: Node_ID,
	token: Restore_Token,
) -> bool {
	state := restore_control_state(rt, control, target)
	if state == nil || state.token != token || !restore_outcome_pending(state.outcome) { return false }
	restore_set_outcome(rt, target, state, .Cancelled, .Application_Cancelled)
	return true
}

restore_cancel_pending :: proc(rt: ^Runtime, control: Restore_Control, target: Node_ID, reason: Restore_Reason) -> bool {
	state := restore_control_state(rt, control, target)
	if state == nil || state.control != control || !restore_outcome_pending(state.outcome) { return false }
	restore_set_outcome(rt, target, state, .Cancelled, reason)
	return true
}

restore_release_control :: proc(rt: ^Runtime, target: Node_ID, control: Restore_Control) {
	key := Restore_Target{control=control, node=target}
	if state, ok := rt.restore_controls[key]; ok {
		if restore_outcome_pending(state.outcome) {
			restore_set_outcome(rt, target, state, .Cancelled, .Target_Retired)
		}
		free(state, allocator=rt.persistent_allocator)
		delete_key(&rt.restore_controls, key)
	}
}

restore_release_node :: proc(rt: ^Runtime, target: Node_ID) {
	if rt == nil { return }
	restore_release_control(rt, target, .Split)
	restore_release_control(rt, target, .Scroll)
}

// semantic_focus_restore_request restores the application's logical entity
// under its current owner. It does not move native keyboard focus. The row may
// remain unrealized until that owner describes the entity again.
semantic_focus_restore_request :: proc(
	rt: ^Runtime,
	id: Semantic_ID,
	owner: Node_ID,
	token: Restore_Token,
) -> bool {
	if rt == nil || token == RESTORE_TOKEN_NONE { return false }
	state := &rt.semantic_focus_restore
	if state.token == token {
		if !restore_outcome_pending(state.outcome) || state.semantic_id != id { return false }
		previous_owner := rt.semantic_focus.owner
		rt.semantic_focus.id = id
		rt.semantic_focus.owner = owner
		if previous_owner != owner {
			restore_report_record(rt, owner, state^)
			invalidate_interaction_paint(rt, previous_owner, "semantic focus restore owner changed")
			invalidate_interaction_paint(rt, owner, "semantic focus restore owner changed")
		}
		if !rt.frame_open { refresh_semantic_focus_realization(rt) }
		return true
	}
	if !restore_start(rt, owner, .Semantic_Focus, state, token, {}) { return false }
	if !semantic_id_is_valid(id) {
		state.semantic_id = id
		restore_set_outcome(rt, owner, state, .Cancelled, .Invalid_Value)
		return false
	}
	state.semantic_id = id
	previous_owner := rt.semantic_focus.owner
	rt.semantic_focus.id = id
	rt.semantic_focus.owner = owner
	if !rt.frame_open { refresh_semantic_focus_realization(rt) }
	if previous_owner != owner {
		invalidate_interaction_paint(rt, previous_owner, "semantic focus restore owner changed")
		invalidate_interaction_paint(rt, owner, "semantic focus restore owner changed")
	}
	return true
}

restore_apply_description_request :: proc(rt: ^Runtime, node: ^Node, d: Description) {
	if node == nil { return }
	if node.kind != .Split { _ = restore_cancel_pending(rt, .Split, node.id, .Owner_Mismatch) }
	if node.kind != .Scroll_Region { _ = restore_cancel_pending(rt, .Scroll, node.id, .Owner_Mismatch) }
	if node.kind == .Split {
		if state := restore_control_state(rt, .Split, node.id); state != nil && restore_outcome_pending(state.outcome) {
			preferred := maxf(state.requested.x, 0)
			if node.split_preferred_position != preferred {
				node.split_preferred_position = preferred
				mark_layout_ancestors(rt, node.id)
			}
			state.preferred = Restore_Value{x=preferred}
		}
	}
	if node.kind == .Scroll_Region {
		state := restore_control_state(rt, .Scroll, node.id)
		if state == nil || !restore_outcome_pending(state.outcome) { return }
		state.described = Restore_Value{x=d.scroll_offset_x, y=d.scroll_offset_y}
		state.described_viewport = Restore_Value{x=d.scroll_viewport_width, y=d.scroll_viewport_height}
	}
}

restore_resolve_after_layout :: proc(rt: ^Runtime) {
	if rt == nil { return }
	for target, state in rt.restore_controls {
		id := target.node
		node, found := rt.nodes[id]
		if !restore_outcome_pending(state.outcome) { continue }
		if !found {
			restore_set_outcome(rt, id, state, .Cancelled, .Target_Retired)
			continue
		}
		if !node.active || !node.present {
			reason := Restore_Reason.Awaiting_Layout
			if !node.present { reason = .Owner_Unavailable }
			if state.outcome != .Deferred || state.reason != reason {
				restore_set_outcome(rt, id, state, .Deferred, reason)
			}
			continue
		}
		state.layout_generation = restore_layout_generation(rt)
		if target.control == .Split && node.kind == .Split {
			state.preferred = Restore_Value{x=node.split_preferred_position}
			state.resolved = Restore_Value{x=node.split_position}
			if restore_value_close(state.requested.x, node.split_position) &&
				restore_value_close(state.requested.x, node.split_preferred_position) {
				restore_set_outcome(rt, id, state, .Applied, .Resolved)
			} else {
				restore_set_outcome(rt, id, state, .Clamped, .Constrained)
			}
			continue
		}
		if target.control != .Scroll || node.kind != .Scroll_Region { continue }
		max_x := maxf(node.scroll_content_width-node.scroll_viewport_width, 0)
		max_y := maxf(node.scroll_content_height-node.scroll_viewport_height, 0)
		resolved := Restore_Value{
			x=clampf(state.requested.x, 0, max_x),
			y=clampf(state.requested.y, 0, max_y),
		}
		layout_offset_changed := !restore_value_close(node.layout_scroll_offset_x, resolved.x) ||
			!restore_value_close(node.layout_scroll_offset_y, resolved.y)
		node.scroll_offset_x = resolved.x
		node.scroll_offset_y = resolved.y
		node.layout_scroll_offset_x = resolved.x
		node.layout_scroll_offset_y = resolved.y
		state.resolved = resolved
		virtualized := false
		for child_id in node.children {
			if child, ok := rt.nodes[child_id]; ok && child.kind == .Virtual_List {
				virtualized = true
				break
			}
		}
		needs_correction := virtualized &&
			(!restore_value_close(state.described.x, resolved.x) ||
			 !restore_value_close(state.described.y, resolved.y) ||
			 !restore_value_close(state.described_viewport.x, node.scroll_viewport_width) ||
			 !restore_value_close(state.described_viewport.y, node.scroll_viewport_height))
		if needs_correction && !state.awaiting_description {
			state.awaiting_description = true
			restore_set_outcome(rt, id, state, .Deferred, .Awaiting_Corrective_Description)
			invalidate_root(rt, "scroll restoration requires one virtual range correction")
			continue
		}
		if !virtualized && layout_offset_changed {
			mark_layout_ancestors(rt, id)
		}
		state.awaiting_description = false
		clamped := !restore_value_close(state.requested.x, resolved.x) ||
			!restore_value_close(state.requested.y, resolved.y)
		if clamped {
			restore_set_outcome(rt, id, state, .Clamped, .Constrained)
		} else {
			restore_set_outcome(rt, id, state, .Applied, .Resolved)
		}
	}
	if rt.layout_pending { layout_tree(rt) }
}
