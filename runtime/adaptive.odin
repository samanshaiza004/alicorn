#+vet explicit-allocators
package alicorn

import "core:fmt"
import "core:math"

Adaptive_Selection_Reason :: enum {
	Unresolved,
	Minimum_Fit,
	Fallback,
	Invalid_Configuration_Fallback,
}

Adaptive_Rejection_Reason :: enum {
	Minimum_Width_Not_Met,
	Earlier_Alternative_Selected,
}

Adaptive_Rejected_Alternative :: struct {
	node: Node_ID,
	name: string,
	minimum_width: f32,
	reason: Adaptive_Rejection_Reason,
}

// The names borrow from retained alternative nodes and remain valid until the
// next application description or runtime destruction.
Adaptive_Selection_State :: struct {
	valid: bool,
	available_width: f32,
	selected_alternative: Node_ID,
	selected_name: string,
	reason: Adaptive_Selection_Reason,
	rejected_count: u8,
	rejected: [2]Adaptive_Rejected_Alternative,
}

// adaptive_begin creates one parent-assigned layout boundary whose width is
// the sole input to ordered alternative selection. It deliberately rejects
// content-sized outer bounds: a selected child must not be able to influence
// the constraint used to select itself.
adaptive_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	style := DEFAULT_STYLE,
	label := "adaptive",
	loc := #caller_location,
) -> Node_ID {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return 0 }
	normalized := style
	if layout_size_is_fit_content(normalized.width) || layout_size_is_fit_content(normalized.height) {
		append_diagnostic(ui.runtime, "adaptive regions require parent-assigned or explicit outer dimensions; FIT_CONTENT is not supported on the adaptive owner")
		if layout_size_is_fit_content(normalized.width) { normalized.width = -1 }
		if layout_size_is_fit_content(normalized.height) { normalized.height = -1 }
	}
	id := container_begin_simple(ui, .Container, label=label, key=key, style=normalized, loc=loc, layout_boundary=true)
	if id != 0 {
		pending := &ui.runtime.pending[len(ui.runtime.pending)-1]
		pending.description.adaptive_owner = true
	}
	return id
}

// adaptive_alternative_begin starts one ordered candidate. Candidates are
// fully bounded at two for v1; use a positive minimum_width for the preferred
// presentation and zero for the final fallback.
adaptive_alternative_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	name: string,
	minimum_width: f32 = 0,
	style := DEFAULT_STYLE,
	loc := #caller_location,
) -> Node_ID {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return 0 }
	rt := ui.runtime
	owner_id := current_node_parent(ui)
	owner_pending: ^Pending_Item = nil
	for i := len(rt.pending)-1; i >= 0; i -= 1 {
		if rt.pending[i].kind == .Description && rt.pending[i].description.id == owner_id {
			owner_pending = &rt.pending[i]
			break
		}
	}
	if owner_pending == nil || !owner_pending.description.adaptive_owner {
		append_diagnostic(rt, "adaptive_alternative_begin must be called directly inside adaptive_begin")
		return 0
	}
	count := 0
	for item in rt.pending {
		if item.kind == .Description && item.description.parent == owner_id && item.description.adaptive_alternative { count += 1 }
	}
	if count >= 2 {
		append_diagnostic(rt, "adaptive regions support exactly two ordered alternatives in v1")
		return 0
	}
	threshold := minimum_width
	if math.is_nan(threshold) || math.is_inf(threshold) || threshold < 0 {
		append_diagnostic(rt, fmt.tprintf("adaptive alternative %q has invalid minimum width %.3f; using zero", name, threshold))
		threshold = 0
	}
	id := container_begin_simple(ui, .Container, label=name, key=key, style=style, loc=loc)
	if id != 0 {
		pending := &rt.pending[len(rt.pending)-1]
		pending.description.adaptive_alternative = true
		pending.description.adaptive_min_width = threshold
	}
	return id
}

adaptive_alternative_end :: proc(ui: ^UI) {
	container_end(ui)
}

adaptive_end :: proc(ui: ^UI) {
	if ui == nil || ui.runtime == nil { return }
	rt := ui.runtime
	owner_id := current_node_parent(ui)
	count := 0
	first_minimum: f32 = -1
	second_minimum: f32 = -1
	for item in rt.pending {
		if item.kind != .Description || item.description.parent != owner_id || !item.description.adaptive_alternative { continue }
		if count == 0 { first_minimum = item.description.adaptive_min_width }
		else if count == 1 { second_minimum = item.description.adaptive_min_width }
		count += 1
	}
	if count != 2 {
		append_diagnostic(rt, fmt.tprintf("adaptive region %d requires exactly two alternatives; found %d", owner_id, count))
	} else if first_minimum <= 0 || second_minimum != 0 || first_minimum <= second_minimum {
		append_diagnostic(rt, fmt.tprintf("adaptive region %d requires ordered alternatives: preferred minimum width > 0, followed by a zero-width fallback", owner_id))
	}
	container_end(ui)
}

adaptive_node_has_alternative_ancestor :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if rt == nil { return false }
	current := id
	for current != 0 {
		node, ok := rt.nodes[current]
		if !ok { return false }
		if node.adaptive_alternative { return true }
		current = node.parent
	}
	return false
}

adaptive_default_presentation :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if rt == nil { return true }
	current := id
	for current != 0 {
		node, ok := rt.nodes[current]
		if !ok { return false }
		if node.adaptive_alternative {
			if owner, owner_ok := rt.nodes[node.parent]; owner_ok && owner.adaptive_owner &&
				owner.adaptive_selected_alternative != 0 && owner.adaptive_selected_alternative != node.id {
				return false
			}
		}
		current = node.parent
	}
	return true
}

node_is_presentation_active :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if rt == nil { return false }
	current := id
	for current != 0 {
		node, ok := rt.nodes[current]
		if !ok || !node.active { return false }
		if node.adaptive_alternative && !node.present { return false }
		current = node.parent
	}
	return true
}

adaptive_selection_state :: proc(rt: ^Runtime, owner_id: Node_ID) -> Adaptive_Selection_State {
	if rt == nil { return {} }
	owner, ok := rt.nodes[owner_id]
	if !ok || !owner.adaptive_owner || owner.adaptive_selected_alternative == 0 { return {} }
	state := Adaptive_Selection_State{
		valid=true,
		available_width=owner.adaptive_available_width,
		selected_alternative=owner.adaptive_selected_alternative,
		reason=owner.adaptive_selection_reason,
	}
	if selected, found := rt.nodes[state.selected_alternative]; found { state.selected_name = selected.label }
	for child_id in owner.children {
		if child_id == state.selected_alternative { continue }
		child, found := rt.nodes[child_id]
		if !found || !child.adaptive_alternative || state.rejected_count >= u8(len(state.rejected)) { continue }
		rejection := Adaptive_Rejection_Reason.Minimum_Width_Not_Met
		if child.adaptive_min_width <= state.available_width { rejection = .Earlier_Alternative_Selected }
		state.rejected[state.rejected_count] = Adaptive_Rejected_Alternative{
			node=child.id,
			name=child.label,
			minimum_width=child.adaptive_min_width,
			reason=rejection,
		}
		state.rejected_count += 1
	}
	return state
}

adaptive_set_subtree_presentation :: proc(rt: ^Runtime, root_id: Node_ID, visible: bool) -> bool {
	if rt == nil { return false }
	root, found := rt.nodes[root_id]
	if !found { return false }
	changed := false
	stack := make([dynamic]Node_ID, 0, allocator=rt.scratch_allocator)
	append(&stack, root_id)
	focused_will_hide := false
	if !visible && rt.focused != 0 {
		current := rt.focused
		for current != 0 {
			if current == root_id { focused_will_hide = true; break }
			node, ok := rt.nodes[current]
			if !ok { break }
			current = node.parent
		}
	}
	for len(stack) > 0 {
		id := pop(&stack)
		node, ok := rt.nodes[id]
		if !ok { continue }
		if node.present != visible {
			node.present = visible
			changed = true
			dirty_set(&node.dirty, .Composite, true)
			if visible {
				dirty_set(&node.dirty, .Paint, true)
				dirty_set(&node.dirty, .Layout, true)
			}
			queue_paint(rt, id)
		}
		if !visible {
			if rt.drag.phase != .Idle && (rt.drag.source_node == id || rt.drag.target_node == id) {
				drag_cancel_session(rt)
			}
			if rt.last_hovered == id { rt.last_hovered = 0; rt.stats.hover_target_transitions += 1 }
			node.hovered = false
			node.pressed = false
			if rt.captured_node == id { rt.captured_node = 0 }
			if rt.activation_node == id { rt.activation_node = 0 }
			if rt.selected == id { rt.selected = 0 }
			if rt.text_field_selection_owner == id { text_field_pointer_selection_cancel(rt) }
			delete_key(&rt.finalized_geometry, id)
			semantic_sync_bounds(rt, node)
		}
		for child in node.children { append(&stack, child) }
	}
	delete(stack)
	if changed { rt.composition_rebuild = true }
	if focused_will_hide {
		previous := rt.focused
		focused_semantic_id := Semantic_ID{}
		if focused_node, focused_found := rt.nodes[previous]; focused_found { focused_semantic_id = focused_node.semantic_id }
		rt.focused = 0
		repaired := false
		if semantic_id_is_valid(focused_semantic_id) {
			if owner, owner_found := rt.nodes[root.parent]; owner_found && owner.adaptive_owner {
				selected_id := owner.adaptive_selected_alternative
				focus_stack := make([dynamic]Node_ID, 0, allocator=rt.scratch_allocator)
				if selected_id != 0 { append(&focus_stack, selected_id) }
				for len(focus_stack) > 0 {
					candidate_id := pop(&focus_stack)
					candidate, candidate_found := rt.nodes[candidate_id]
					if !candidate_found { continue }
					if candidate.semantic_id == focused_semantic_id && candidate.focusable && !candidate.disabled &&
						node_is_presentation_active(rt, candidate_id) {
						repaired = focus(rt, candidate_id)
						if repaired { break }
					}
					for child in candidate.children { append(&focus_stack, child) }
				}
				delete(focus_stack)
			}
		}
		current := root.parent
		for current != 0 && !repaired {
			candidate, ok := rt.nodes[current]
			if !ok { break }
			if candidate.active && candidate.present && candidate.focusable && !candidate.disabled {
				rt.focused = current
				repaired = true
				break
			}
			current = candidate.parent
		}
		if !repaired {
			for id in rt.order {
				candidate, ok := rt.nodes[id]
				if ok && candidate.active && candidate.present && candidate.focusable && !candidate.disabled {
					rt.focused = id
					repaired = true
					break
				}
			}
		}
		invalidate_interaction_paint(rt, previous, "adaptive presentation hid focused content")
		invalidate_interaction_paint(rt, rt.focused, "adaptive presentation focus fallback")
		record_trace(rt, .Focus, rt.focused, "focus moved out of hidden adaptive alternative")
	}
	return changed
}

adaptive_semantics_sync_descriptions :: proc(rt: ^Runtime) {
	if rt == nil { return }
	for item in rt.pending {
		if item.kind != .Description { continue }
		node, found := rt.nodes[item.description.id]
		if !found || !adaptive_node_has_alternative_ancestor(rt, node.id) { continue }
		previous_id := Semantic_ID{}
		previous_visual_semantic := false
		for semantic_id, entity in rt.semantic_entities {
			if entity.node.visual_node == node.id {
				previous_id = semantic_id
				previous_visual_semantic = true
				break
			}
		}
		if node_is_presentation_active(rt, node.id) {
			semantic_sync_node(rt, node, item.semantic, previous_id)
		} else if previous_visual_semantic {
			// A hidden alternative may declare the same logical Semantic_ID as
			// the currently selected peer. Retire only an entity still bound to
			// this physical node; never let a hidden peer overwrite its sibling.
			semantic_retire_node_id(rt, node, previous_id)
		}
	}
	// Newly synchronized alternative nodes were not present when retained tree
	// order was rebuilt earlier in reconciliation. Refresh only their stable
	// preorder numbers before committing this frame's semantic delta.
	for id, index in rt.order { semantic_sync_tree_order(rt, id, u64(index)) }
}

