package alicorn

import "core:fmt"

// visual_part_attach labels an already-described retained node as a visual
// part of an existing retained owner. Static owners support always-visible
// parts; interaction-dependent visibility requires an owner that exposes the
// relevant state. This does not create interaction behavior or position the
// node; ordinary parent layout remains authoritative.
visual_part_attach :: proc(
	ui: ^UI,
	node, owner: Node_ID,
	identity: Visual_Part_ID,
	visibility := Visual_Part_Visibility.Always,
	reveal_on_direct_hover := false,
) -> bool {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open || node == 0 || owner == 0 ||
		!visual_part_identity_is_valid(identity) {
		if ui != nil && ui.runtime != nil { append_diagnostic(ui.runtime, "visual_part_attach requires an open frame, valid node/owner identities, and a valid part ID") }
		return false
	}
	rt := ui.runtime
	part_pending := -1
	owner_kind := Node_Kind.Root
	owner_surface_interaction := GPU_Surface_Interaction.Inert
	owner_found := false
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := rt.pending[index]
		if item.kind != .Description { continue }
		if item.description.id == node { part_pending = index }
		if item.description.id == owner {
			owner_kind = item.description.kind
			owner_surface_interaction = item.description.surface_interaction
			owner_found = true
		}
	}
	if !owner_found {
		if retained, exists := rt.nodes[owner]; exists && retained.active {
			owner_kind = retained.kind
			owner_surface_interaction = retained.surface_interaction
			owner_found = true
		}
	}
	if int(visibility) < 0 || visibility > .Owner_Not_Hovered {
		append_diagnostic(rt, "visual-part visibility must be a declared owner-state policy")
		return false
	}
	if part_pending < 0 || !owner_found {
		append_diagnostic(rt, "visual_part_attach must tag a node described in this frame and name an existing retained owner")
		return false
	}
	if !visual_part_owner_supports_visibility(owner_kind, owner_surface_interaction, visibility) {
		append_diagnostic(rt, "visual-part visibility policy requires state exposed by the owning control; non-control owners support Always")
		return false
	}
	if !visual_part_node_descends_from(rt, node, owner, part_pending) {
		append_diagnostic(rt, "visual_part_attach requires the tagged node to be the owner or one of its retained layout descendants")
		return false
	}
	if rt.pending[part_pending].visual_part.defined {
		append_diagnostic(rt, "each retained node may carry one visual-part identity")
		return false
	}
	rt.pending[part_pending].visual_part = Visual_Part_Style{
		defined=true,
		owner=owner,
		identity=identity,
		visibility=visibility,
		reveal_on_direct_hover=reveal_on_direct_hover,
	}
	return true
}

visual_part_owner_supports_visibility :: proc(
	kind: Node_Kind,
	surface_interaction: GPU_Surface_Interaction,
	visibility: Visual_Part_Visibility,
) -> bool {
	switch visibility {
	case .Always:
		return true
	case .Owner_Hovered, .Owner_Not_Hovered:
		switch kind {
		case .Button, .Checkbox, .Slider, .Text_Field:
			return true
		case .Custom_Surface:
			return surface_interaction == .Pointer
		case .Root, .Modal_Overlay, .Context_Menu_Overlay, .Context_Menu_Panel, .Container, .Grid,
		     .Tab, .Tab_Close, .Text, .Text_Composition, .Virtual_List, .Virtual_Row,
		     .Scroll_Region, .Split, .Split_Handle:
			return false
		}
	case .Owner_Selected_Or_Hovered:
		// Button is currently the only built-in control that exposes a distinct
		// selected state to visual recipes.
		return kind == .Button
	}
	return false
}

visual_part_node_descends_from :: proc(rt: ^Runtime, node_id, owner_id: Node_ID, pending_index: int) -> bool {
	if node_id == owner_id { return true }
	if rt == nil || pending_index < 0 || pending_index >= len(rt.pending) { return false }
	current := rt.pending[pending_index].description.parent
	for current != 0 {
		if current == owner_id { return true }
		parent_id := Node_ID(0)
		found_parent := false
		for index := len(rt.pending)-1; index >= 0; index -= 1 {
			item := rt.pending[index]
			if item.kind == .Description && item.description.id == current {
				parent_id = item.description.parent
				found_parent = true
				break
			}
		}
		if !found_parent {
			if retained, found := rt.nodes[current]; found {
				parent_id = retained.parent
				found_parent = true
			}
		}
		if !found_parent { return false }
		current = parent_id
	}
	return false
}

visual_part_owner_hovered :: proc(rt: ^Runtime, owner_id: Node_ID) -> bool {
	if rt == nil || owner_id == 0 { return false }
	if owner, found := rt.nodes[owner_id]; found && owner.hovered { return true }
	current := rt.last_hovered
	for current != 0 {
		if current == owner_id { return true }
		node, found := rt.nodes[current]
		if !found { break }
		current = node.parent
	}
	return false
}

visual_part_interaction_owner :: proc(rt: ^Runtime, node_id: Node_ID) -> Node_ID {
	if rt == nil || node_id == 0 { return node_id }
	if part, tagged := rt.visual_parts[node_id]; tagged && part.defined { return part.owner }
	current := node_id
	for current != 0 {
		node, found := rt.nodes[current]
		if !found { break }
		if node.kind == .Button { return current }
		current = node.parent
	}
	return node_id
}

visual_part_is_visible :: proc(rt: ^Runtime, node_id: Node_ID) -> bool {
	if rt == nil { return true }
	part, has_part := rt.visual_parts[node_id]
	if !has_part || !part.defined || part.visibility == .Always { return true }
	owner, found := rt.nodes[part.owner]
	if !found || !owner.active { return false }
	hovered := visual_part_owner_hovered(rt, part.owner)
	switch part.visibility {
	case .Always:
		return true
	case .Owner_Hovered:
		return hovered
	case .Owner_Selected_Or_Hovered:
		return owner.selected || hovered
	case .Owner_Not_Hovered:
		return !hovered
	}
	return false
}

visual_part_self_hovered :: proc(rt: ^Runtime, node_id: Node_ID) -> bool {
	if rt == nil || node_id == 0 { return false }
	if node, found := rt.nodes[node_id]; found && (node.hovered || node.pressed) { return true }
	return rt.last_hovered == node_id
}

// visual_part_hit_test_visible lets an action reserve a visual slot while
// requiring pointer motion to reveal its hit target. Paint remains governed
// by visual_part_is_visible; only hit testing uses this additional policy.
visual_part_hit_test_visible :: proc(rt: ^Runtime, node_id: Node_ID, include_reveal_target := false) -> bool {
	if !visual_part_is_visible(rt, node_id) { return false }
	if rt == nil { return true }
	part, tagged := rt.visual_parts[node_id]
	if !tagged || !part.defined || !part.reveal_on_direct_hover || visual_part_self_hovered(rt, node_id) {
		return true
	}
	return include_reveal_target
}

visual_part_owner_has_role :: proc(rt: ^Runtime, owner_id: Node_ID, role: Visual_Part_Core_ID) -> bool {
	if rt == nil { return false }
	owner, found := rt.nodes[owner_id]
	if !found { return false }
	if visual_part_has_core_role(rt, owner_id, owner_id, role) { return true }
	if len(owner.children) == 0 { return false }
	stack := make([dynamic]Node_ID, 0, allocator=context.temp_allocator)
	for child_id in owner.children { append(&stack, child_id) }
	for len(stack) > 0 {
		candidate := pop(&stack)
		if visual_part_has_core_role(rt, candidate, owner_id, role) { return true }
		if node, found := rt.nodes[candidate]; found {
			for child_id in node.children { append(&stack, child_id) }
		}
	}
	return false
}

visual_part_owner_label :: proc(rt: ^Runtime, owner_id: Node_ID) -> string {
	if rt == nil { return "" }
	owner, found := rt.nodes[owner_id]
	if !found { return "" }
	if visual_part_has_core_role(rt, owner_id, owner_id, .Label) {
		return owner.text if owner.kind == .Text else owner.label
	}
	stack := make([dynamic]Node_ID, 0, allocator=context.temp_allocator)
	for child_id in owner.children { append(&stack, child_id) }
	for len(stack) > 0 {
		candidate := pop(&stack)
		if visual_part_has_core_role(rt, candidate, owner_id, .Label) {
			if node, exists := rt.nodes[candidate]; exists {
				return node.text if node.kind == .Text else node.label
			}
		}
		if node, exists := rt.nodes[candidate]; exists {
			for child_id in node.children { append(&stack, child_id) }
		}
	}
	return ""
}

visual_part_has_core_role :: proc(rt: ^Runtime, node_id, owner_id: Node_ID, role: Visual_Part_Core_ID) -> bool {
	part, tagged := rt.visual_parts[node_id]
	if !tagged || !part.defined || part.owner != owner_id { return false }
	switch identity in part.identity {
	case Visual_Part_Core_ID:
		return identity == role
	case Visual_Part_Extension_ID:
		return false
	}
	return false
}

// visual_part_label_color resolves a composed label from the recipe and state
// of its semantic Button owner. This keeps reusable label parts consistent
// with the control they describe without teaching paint about specific
// components such as Tabs.
visual_part_label_color :: proc(rt: ^Runtime, node_id: Node_ID) -> (color: Color, found: bool) {
	if rt == nil { return }
	part, tagged := rt.visual_parts[node_id]
	if !tagged || !part.defined || !visual_part_has_core_role(rt, node_id, part.owner, .Label) { return }
	owner, exists := rt.nodes[part.owner]
	if !exists || !owner.active || owner.kind != .Button { return }
	hovered := visual_part_owner_hovered(rt, owner.id)
	resolved := style_button_resolve_retained(rt, owner, Button_Visual_State{
		selected=owner.selected,
		hovered=hovered,
		pressed=owner.pressed,
		disabled=owner.disabled,
	}, owner.drop_position == .On)
	return resolved.text, true
}

visual_part_invalidate_dependents :: proc(rt: ^Runtime, node_id: Node_ID, reason: string) {
	if rt == nil || node_id == 0 { return }
	owner_id := visual_part_interaction_owner(rt, node_id)
	if owner, found := rt.nodes[owner_id]; found && owner.active {
		invalidate_interaction_paint(rt, owner_id, reason)
	}
	owner, found := rt.nodes[owner_id]
	if !found { return }
	stack := make([dynamic]Node_ID, 0, allocator=context.temp_allocator)
	for child_id in owner.children { append(&stack, child_id) }
	for len(stack) > 0 {
		part_id := pop(&stack)
		if part, tagged := rt.visual_parts[part_id]; tagged && part.defined && part.owner == owner_id {
			invalidate_interaction_paint(rt, part_id, reason)
		}
		if child, exists := rt.nodes[part_id]; exists {
			for child_id in child.children { append(&stack, child_id) }
		}
	}
}

visual_part_role_name :: proc(identity: Visual_Part_ID, allocator := context.temp_allocator) -> string {
	switch value in identity {
	case Visual_Part_Core_ID:
		switch value {
		case .Surface: return "surface"
		case .Content: return "content"
		case .Label: return "label"
		case .Icon: return "icon"
		case .Indicator: return "indicator"
		case .Selected_Indicator: return "selected-indicator"
		case .Overlay: return "overlay"
		case .Focus_Indicator: return "focus-indicator"
		case .Count: return "invalid"
		}
	case Visual_Part_Extension_ID:
		return fmt.aprintf("extension:%d", u64(value), allocator=allocator)
	}
	return "invalid"
}

visual_part_visibility_name :: proc(visibility: Visual_Part_Visibility) -> string {
	switch visibility {
	case .Always: return "always"
	case .Owner_Hovered: return "owner-hovered"
	case .Owner_Selected_Or_Hovered: return "owner-selected-or-hovered"
	case .Owner_Not_Hovered: return "owner-not-hovered"
	}
	return "invalid"
}
