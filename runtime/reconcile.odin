#+vet explicit-allocators
package alicorn

import "core:fmt"
import "core:mem"

hash_style :: proc(style: Layout_Style) -> u64 {
	h: u64 = 1469598103934665603
	h = hash_mix(h, u64(style.direction))
	h = hash_mix(h, u64(transmute(u32)style.width))
	h = hash_mix(h, u64(transmute(u32)style.height))
	h = hash_mix(h, u64(transmute(u32)style.min_width))
	h = hash_mix(h, u64(transmute(u32)style.max_width))
	h = hash_mix(h, u64(transmute(u32)style.min_height))
	h = hash_mix(h, u64(transmute(u32)style.max_height))
	h = hash_mix(h, u64(transmute(u32)style.grow))
	h = hash_mix(h, u64(transmute(u32)style.padding))
	h = hash_mix(h, u64(transmute(u32)style.gap))
	h = hash_mix(h, u64(style.align))
	h = hash_mix(h, u64(style.clip ? 1 : 0))
	return h
}

hash_color :: proc(color: Color) -> u64 {
	h: u64 = 1469598103934665603
	h = hash_mix(h, u64(transmute(u32)color.r))
	h = hash_mix(h, u64(transmute(u32)color.g))
	h = hash_mix(h, u64(transmute(u32)color.b))
	h = hash_mix(h, u64(transmute(u32)color.a))
	return h
}

hash_button_content_style :: proc(style: Button_Content_Style) -> u64 {
	h: u64 = 1469598103934665603
	h = hash_mix(h, u64(style.horizontal))
	h = hash_mix(h, u64(style.vertical))
	h = hash_mix(h, u64(transmute(u32)style.padding_x))
	h = hash_mix(h, u64(transmute(u32)style.padding_y))
	return h
}

description_hash :: proc(d: Description) -> u64 {
	h := hash_mix(hash_string(d.label), hash_string(d.text))
	h = hash_mix(h, u64(d.kind))
	h = hash_mix(h, u64(d.font))
	if d.kind == .Button {
		h = hash_mix(h, hash_button_content_style(d.button_content_style))
	}
	if node_has_text_product(d.kind) {
		h = hash_mix(h, u64(transmute(u32)effective_font_weight(d.text_style.font_weight)))
		h = hash_mix(h, u64(d.text_style.overflow))
	}
	h = hash_mix(h, d.paint_value)
	h = hash_mix(h, hash_color(d.color))
	h = hash_mix(h, u64(d.paint_background ? 1 : 0))
	h = hash_mix(h, d.region_revision)
	h = hash_mix(h, u64(d.surface_kind))
	h = hash_mix(h, u64(d.surface_pixel_width))
	h = hash_mix(h, u64(d.surface_pixel_height))
	h = hash_mix(h, u64(transmute(u32)d.surface_dpi_scale))
	h = hash_mix(h, u64(transmute(u32)d.scroll_offset_y))
	h = hash_mix(h, u64(transmute(u32)d.scroll_offset_x))
	h = hash_mix(h, u64(transmute(u32)d.scroll_content_height))
	h = hash_mix(h, u64(transmute(u32)d.scroll_viewport_height))
	h = hash_mix(h, u64(transmute(u32)d.scroll_line_height))
	h = hash_mix(h, u64(transmute(u32)d.scroll_content_width))
	h = hash_mix(h, u64(transmute(u32)d.scroll_viewport_width))
	h = hash_mix(h, u64(transmute(u32)d.scroll_line_width))
	h = hash_mix(h, u64(d.scroll_axes))
	h = hash_mix(h, u64(d.scroll_axis_behavior))
	h = hash_mix(h, u64(d.scrollbar_policy))
	return h
}

layout_hash :: proc(d: Description) -> u64 {
	h := hash_mix(hash_style(d.style), u64(d.parent))
	// Scrolling changes realized child geometry even when the description and
	// child set remain otherwise identical. Keep both the logical offset and
	// the residual layout offset in this dependency: the former is the public
	// scroll position and the latter is the value used by virtualized layout.
	h = hash_mix(h, u64(transmute(u32)d.scroll_offset_y))
	h = hash_mix(h, u64(transmute(u32)d.scroll_offset_x))
	h = hash_mix(h, u64(transmute(u32)d.layout_scroll_offset_y))
	h = hash_mix(h, u64(transmute(u32)d.layout_scroll_offset_x))
	// Scroll-region content extents and scrollbar policy affect both the
	// reserved viewport and its descendant clipping, so they are layout inputs.
	h = hash_mix(h, u64(transmute(u32)d.scroll_content_width))
	h = hash_mix(h, u64(transmute(u32)d.scroll_content_height))
	h = hash_mix(h, u64(transmute(u32)d.scroll_viewport_width))
	h = hash_mix(h, u64(transmute(u32)d.scroll_viewport_height))
	h = hash_mix(h, u64(d.scroll_axes))
	h = hash_mix(h, u64(d.scrollbar_policy))
	h = hash_mix(h, u64(d.split_axis))
	h = hash_mix(h, u64(transmute(u32)d.split_min_first))
	h = hash_mix(h, u64(transmute(u32)d.split_min_second))
	h = hash_mix(h, u64(transmute(u32)d.split_handle_size))
	h = hash_mix(h, u64(transmute(u32)d.split_hit_size))
	// Text participates in intrinsic measurement. A description can otherwise
	// look layout-identical while a changing label/value moves its siblings.
	#partial switch d.kind {
	case .Button:
		h = hash_mix(h, hash_string(d.label))
		h = hash_mix(h, u64(transmute(u32)d.button_content_style.padding_x))
		h = hash_mix(h, u64(transmute(u32)d.button_content_style.padding_y))
		h = hash_mix(h, u64(d.font))
		h = hash_mix(h, u64(transmute(u32)effective_font_weight(d.text_style.font_weight)))
		h = hash_mix(h, u64(d.text_style.overflow))
	case .Text, .Text_Field:
		h = hash_mix(h, hash_string(d.text))
		h = hash_mix(h, u64(d.font))
		h = hash_mix(h, u64(transmute(u32)effective_font_weight(d.text_style.font_weight)))
		h = hash_mix(h, u64(d.text_style.overflow))
	}
	return h
}

paint_hash :: proc(d: Description) -> u64 {
	h := description_hash(d)
	h = hash_mix(h, u64(d.focusable ? 1 : 0))
	h = hash_mix(h, u64(d.selected ? 1 : 0))
	h = hash_mix(h, u64(d.disabled ? 1 : 0))
	return h
}

same_rect :: proc(a, b: Rect) -> bool {
	return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h
}

mark_dirty :: proc(node: ^Node, reason: string, description, layout, paint, composite: bool, allocator := context.allocator) {
	previous_paint := dirty_has(node.dirty, .Paint)
	previous_composite := dirty_has(node.dirty, .Composite)
	node.dirty = {}
	dirty_set(&node.dirty, .Description, description)
	dirty_set(&node.dirty, .Layout, layout)
	dirty_set(&node.dirty, .Paint, paint || previous_paint)
	dirty_set(&node.dirty, .Composite, composite || previous_composite)
	if !previous_paint {
		if len(node.last_reason) > 0 { delete(node.last_reason, allocator) }
		node.last_reason = owned(reason, allocator)
	}
}

replace_owned :: proc(destination: ^string, value: string, allocator := context.allocator) {
	if destination^ == value { return }
	if len(destination^) > 0 { delete(destination^, allocator) }
	destination^ = owned(value, allocator)
}

replace_site :: proc(destination: ^Source_Site, value: Source_Site, allocator := context.allocator) {
	replace_owned(&destination.file, value.file, allocator)
	replace_owned(&destination.component, value.component, allocator)
	destination.line = value.line
	destination.column = value.column
}

release_node_strings :: proc(node: ^Node, allocator := context.allocator) {
	if len(node.site.file) > 0 { delete(node.site.file, allocator) }
	if len(node.site.component) > 0 { delete(node.site.component, allocator) }
	if len(node.key) > 0 { delete(node.key, allocator) }
	if len(node.label) > 0 { delete(node.label, allocator) }
	if len(node.text) > 0 { delete(node.text, allocator) }
	if len(node.identity_key) > 0 { delete(node.identity_key, allocator) }
	if len(node.last_reason) > 0 { delete(node.last_reason, allocator) }
	node.site = Source_Site{}
	node.key, node.label, node.text, node.identity_key, node.last_reason = "", "", "", "", ""
}

node_has_text_product :: proc(kind: Node_Kind) -> bool {
	return kind == .Text || kind == .Text_Field || kind == .Button
}

copy_node_description :: proc(rt: ^Runtime, node: ^Node, d: Description) {
	// Runtime-owned copies are important: a generic description may borrow a
	// caller's string for only the duration of this procedure.
	label_changed := d.kind == .Button && node.label != d.label
	text_changed := node.text != d.text || label_changed
	font_changed := node.font != d.font
	weight_changed := effective_font_weight(node.text_style.font_weight) != effective_font_weight(d.text_style.font_weight)
	overflow_changed := node.text_style.overflow != d.text_style.overflow
	kind_changed := node.kind != d.kind
	if node.text_run_valid && (text_changed || font_changed || weight_changed || overflow_changed || kind_changed || !node_has_text_product(d.kind)) {
		text_run_destroy(&node.text_run)
		node.text_run_valid = false
	}
	if text_changed || font_changed || kind_changed || !node_has_text_product(d.kind) {
		clear_text_composition(node, rt.persistent_allocator)
	}
	replace_site(&node.site, d.site, rt.persistent_allocator)
	replace_owned(&node.key, d.key, rt.persistent_allocator)
	replace_owned(&node.label, d.label, rt.persistent_allocator)
	replace_owned(&node.text, d.text, rt.persistent_allocator)
	node.parent = d.parent
	node.kind = d.kind
	node.style = d.style
	node.font = d.font
	node.text_style = d.text_style
	node.button_content_style = d.button_content_style
	node.color = d.color
	node.paint_background = d.paint_background
	surface_description_changed := node.paint_value != d.paint_value
	node.paint_value = d.paint_value
	node.region_revision = d.region_revision
	node.region = d.region
	node.focusable = d.focusable && !d.disabled
	node.disabled = d.disabled
	// `selected` is both an application-declared visual state and the runtime's
	// explicit selection projection. Preserve the runtime selection owner when
	// the procedural description does not mention selection, while allowing a
	// description to opt a node into the selected visual state.
	node.selected = d.selected || rt.selected == node.id
	node.explicit_key = d.explicit_key
	node.identity_key_kind = d.identity_key_kind
	node.identity_key_pair = d.identity_key_pair
	node.surface_kind = d.surface_kind
	node.surface_pixel_width = d.surface_pixel_width
	node.surface_pixel_height = d.surface_pixel_height
	node.surface_dpi_scale = d.surface_dpi_scale
	node.scroll_offset_y = d.scroll_offset_y
	node.scroll_offset_x = d.scroll_offset_x
	node.layout_scroll_offset_y = d.layout_scroll_offset_y
	node.layout_scroll_offset_x = d.layout_scroll_offset_x
	node.scroll_content_height = d.scroll_content_height
	node.scroll_viewport_height = d.scroll_viewport_height
	node.scroll_line_height = d.scroll_line_height
	node.scroll_content_width = d.scroll_content_width
	node.scroll_viewport_width = d.scroll_viewport_width
	node.scroll_line_width = d.scroll_line_width
	node.scroll_axes = d.scroll_axes
	node.scroll_axis_behavior = d.scroll_axis_behavior
	node.scrollbar_policy = d.scrollbar_policy
	if kind_changed && d.kind == .Split {
		node.split_position = d.split_position
	}
	node.split_axis = d.split_axis
	node.split_min_first = d.split_min_first
	node.split_min_second = d.split_min_second
	node.split_owner = d.split_owner
	node.split_handle_size = d.split_handle_size
	node.split_hit_size = d.split_hit_size
	// A direct surface update owns the high-frequency revision. A later root
	// wake with the same description must not roll it back; a changed
	// description revision is an explicit replacement and is authoritative.
	if node.surface_revision == node.paint_value || surface_description_changed {
		node.surface_revision = d.paint_value
	}
	if node.kind == .Custom_Surface {
		if kind_changed || surface_description_changed {
			clear(&node.surface_samples)
			clear(&node.surface_segments)
			clear(&node.surface_circles)
			node.surface_geometry_active = d.surface_kind == .Geometry
		}
	} else {
		clear(&node.surface_samples)
		clear(&node.surface_segments)
		clear(&node.surface_circles)
		node.surface_geometry_active = false
	}
	replace_owned(&node.identity_key, d.identity_key, rt.persistent_allocator)
	node.identity_key_u64 = d.identity_key_u64
	node.identity_key_numeric = d.identity_key_numeric
	if text_changed {
		node.caret = Text_Position{len(d.text), .Leading}
		node.selection_anchor = node.caret
		node.selection_focus = node.caret
	}
	if d.disabled {
		node.hovered = false
		node.pressed = false
		if rt.focused == node.id { rt.focused = 0 }
		if rt.captured_node == node.id { rt.captured_node = 0 }
		if rt.activation_node == node.id { rt.activation_node = 0 }
	}
}

queue_paint :: proc(rt: ^Runtime, id: Node_ID) {
	node, ok := rt.nodes[id]
	if !ok || node.paint_queued { return }
	node.paint_queued = true
	append(&rt.paint_queue, id)
}

invalidate_interaction_paint :: proc(rt: ^Runtime, id: Node_ID, reason := "interaction visual state changed") {
	node, ok := rt.nodes[id]
	if !ok || !node.active { return }
	dirty_set(&node.dirty, .Paint, true)
	dirty_set(&node.dirty, .Composite, true)
	if len(node.last_reason) > 0 { delete(node.last_reason, rt.persistent_allocator) }
	node.last_reason = owned(reason, rt.persistent_allocator)
	queue_paint(rt, id)
	request_presentation(rt, reason)
	record_trace(rt, .Invalidation, id, reason)
}

mark_layout_ancestors :: proc(rt: ^Runtime, id: Node_ID) {
	rt.layout_pending = true
	current := id
	for current != 0 {
		node, ok := rt.nodes[current]
		if !ok { break }
		dirty_set(&node.dirty, .Layout, true)
		dirty_set(&node.dirty, .Composite, true)
		current = node.parent
	}
}

Desired_Children :: struct {
	parent:   Node_ID,
	children: [dynamic]Node_ID,
}

desired_children_index :: proc(buckets: []Desired_Children, parent: Node_ID) -> int {
	for bucket, i in buckets {
		if bucket.parent == parent { return i }
	}
	return -1
}

same_children :: proc(a, b: []Node_ID) -> bool {
	if len(a) != len(b) { return false }
	for i := 0; i < len(a); i += 1 {
		if a[i] != b[i] { return false }
	}
	return true
}

retire_subtree :: proc(rt: ^Runtime, id: Node_ID, desired: map[Node_ID]bool) {
	if desired[id] { return }
	node, ok := rt.nodes[id]
	if !ok { return }
	children := node.children[:]
	for child in children {
		retire_subtree(rt, child, desired)
	}
	if id == rt.focused { rt.focused = 0 }
	if id == rt.last_hovered { rt.last_hovered = 0 }
	if id == rt.captured_node {
		if node.kind == .Split_Handle {
			if owner, owner_ok := rt.nodes[node.split_owner]; owner_ok { owner.split_dragging = false }
		}
		rt.captured_node = 0
	}
	if id == rt.selected { rt.selected = 0 }
	delete_key(&rt.nodes, id)
	for command in node.paint { if len(command.text) > 0 { delete(command.text, rt.persistent_allocator) } }
	delete(node.paint)
	delete(node.children)
	delete(node.surface_samples)
	delete(node.surface_segments)
	delete(node.surface_circles)
	text_run_destroy(&node.text_run)
	clear_text_composition(node, rt.persistent_allocator)
	release_node_strings(node, rt.persistent_allocator)
	free(node, allocator=rt.persistent_allocator)
	rt.stats.nodes_retired += 1
	record_trace(rt, .Retire, id, "retained subtree disappeared")
}

append_order_subtree :: proc(rt: ^Runtime, id: Node_ID) {
	node, ok := rt.nodes[id]
	if !ok || !node.active { return }
	append(&rt.order, id)
	for child in node.children {
		append_order_subtree(rt, child)
	}
}

rebuild_order :: proc(rt: ^Runtime) {
	clear(&rt.order)
	for id in rt.top_level {
		append_order_subtree(rt, id)
	}
	rt.stats.adjacency_rebuilds += 1
	rt.composition_rebuild = true
}

reconcile :: proc(rt: ^Runtime) {
	previous_focus := rt.focused
	focus_lineage := make([dynamic]Node_ID, 0, allocator=rt.scratch_allocator)
	focus_was_in_virtual_list := false
	if previous_focus != 0 {
		current := previous_focus
		for current != 0 {
			append(&focus_lineage, current)
			old, ok := rt.nodes[current]
			if !ok { break }
			if old.kind == .Virtual_List { focus_was_in_virtual_list = true }
			current = old.parent
		}
	}

	desired := make(map[Node_ID]bool, allocator=rt.scratch_allocator)
	reused_roots := make(map[Node_ID]bool, allocator=rt.scratch_allocator)
	buckets := make([dynamic]Desired_Children, 0, allocator=rt.scratch_allocator)
	for item in rt.pending {
		switch item.kind {
		case .Description:
			d := item.description
			desired[d.id] = true
			index := desired_children_index(buckets[:], d.parent)
			if index < 0 {
				append(&buckets, Desired_Children{d.parent, make([dynamic]Node_ID, 0, allocator=rt.scratch_allocator)})
				index = len(buckets)-1
			}
			append(&buckets[index].children, d.id)
		case .Reuse_Subtree:
			reused_roots[item.subtree] = true
		}
	}

	// Explicit descriptions are the only nodes whose application-facing
	// description is revisited. Descendants under a reuse marker are not
	// touched; their retained hierarchy remains authoritative.
	for item in rt.pending {
		if item.kind != .Description { continue }
		d := item.description
		rt.stats.reconcile_nodes_visited += 1
		rt.stats.stage_visits[.Reconcile] += 1
		node, exists := rt.nodes[d.id]
		if !exists {
			node = new(Node, allocator=rt.persistent_allocator)
			node.id = d.id
			node.display_index = -1
			node.hit_bounds = {}
			node.children = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
			node.paint = make([dynamic]Display_Command, 0, allocator=rt.persistent_allocator)
			node.surface_samples = make([dynamic]f32, 0, allocator=rt.persistent_allocator)
			node.surface_segments = make([dynamic]GPU_Surface_Line_Segment, 0, allocator=rt.persistent_allocator)
			node.surface_circles = make([dynamic]GPU_Surface_Filled_Circle, 0, allocator=rt.persistent_allocator)
			rt.nodes[d.id] = node
			rt.stats.nodes_created += 1
			copy_node_description(rt, node, d)
			node.description_hash = description_hash(d)
			node.layout_hash = layout_hash(d)
			node.paint_hash = paint_hash(d)
			mark_dirty(node, "new retained node", true, true, true, true, rt.persistent_allocator)
			queue_paint(rt, d.id)
			mark_layout_ancestors(rt, d.id)
			record_trace(rt, .Reconcile, d.id, "new retained node")
		} else {
			new_desc_hash := description_hash(d)
			new_layout_hash := layout_hash(d)
			new_paint_hash := paint_hash(d)
			description_changed := node.description_hash != new_desc_hash
			text_changed := node.text != d.text || (d.kind == .Button && node.label != d.label)
			// Text/labels are included in layout_hash because they contribute
			// intrinsic size. Keep this explicit at the reconciliation boundary so
			// the invariant remains true even if layout hashing is later split by
			// product type.
			layout_changed := node.layout_hash != new_layout_hash || text_changed
			paint_changed := node.paint_hash != new_paint_hash
			copy_node_description(rt, node, d)
			node.description_hash = new_desc_hash
			node.layout_hash = new_layout_hash
			node.paint_hash = new_paint_hash
			reason := "description reused"
			if description_changed { reason = "description changed" }
			mark_dirty(node, reason, description_changed, layout_changed, paint_changed || layout_changed, false, rt.persistent_allocator)
			if layout_changed { mark_layout_ancestors(rt, d.id) }
			if description_changed || layout_changed || paint_changed {
				queue_paint(rt, d.id)
				record_trace(rt, .Reconcile, d.id, reason)
			} else {
				rt.stats.descriptions_reused += 1
			}
		}
		node.active = true
		node.present = true
		if d.region { node.region_cached = true } else { node.region_cached = false }
	}

	structure_changed := false
	root_index := desired_children_index(buckets[:], 0)
	desired_roots: []Node_ID
	if root_index >= 0 { desired_roots = buckets[root_index].children[:] }
	if !same_children(rt.top_level[:], desired_roots) {
		for id in rt.top_level {
			if !desired[id] { retire_subtree(rt, id, desired) }
		}
		clear(&rt.top_level)
		for id in desired_roots { append(&rt.top_level, id) }
		structure_changed = true
	}

	// Reconcile only the direct child list of explicitly described parents.
	// A reused region is an atomic unit here, so its descendants do not enter
	// this loop.
	processed_parents := make(map[Node_ID]bool, allocator=rt.scratch_allocator)
	for item in rt.pending {
		if item.kind != .Description { continue }
		parent_id := item.description.id
		if processed_parents[parent_id] || reused_roots[parent_id] { continue }
		processed_parents[parent_id] = true
		parent, ok := rt.nodes[parent_id]
		if !ok { continue }
		index := desired_children_index(buckets[:], parent_id)
		wanted: []Node_ID
		if index >= 0 { wanted = buckets[index].children[:] }
		if !same_children(parent.children[:], wanted) {
			for old_child in parent.children {
				if !desired[old_child] { retire_subtree(rt, old_child, desired) }
			}
			clear(&parent.children)
			for child in wanted { append(&parent.children, child) }
			// Child membership and order are layout inputs. Mark this parent and
			// its ancestors so retained layout cannot preserve stale positions
			// after keyed reorder, insertion, or removal.
			dirty_set(&parent.dirty, .Layout, true)
			dirty_set(&parent.dirty, .Composite, true)
			mark_layout_ancestors(rt, parent_id)
			structure_changed = true
		}
	}
	delete(processed_parents)
	delete(desired)
	delete(reused_roots)
	for bucket in buckets { delete(bucket.children) }
	delete(buckets)

	if structure_changed || len(rt.order) == 0 {
		rebuild_order(rt)
	}

	if previous_focus != 0 {
		if node, ok := rt.nodes[previous_focus]; ok && node.active && node.focusable {
			rt.focused = previous_focus
		} else {
			rt.focused = focus_fallback(rt, focus_lineage[:], !focus_was_in_virtual_list)
			if rt.focused != previous_focus {
				record_trace(rt, .Focus, rt.focused, "focused node disappeared; deterministic fallback")
			}
		}
	}
	if rt.focused != 0 {
		if node, ok := rt.nodes[rt.focused]; !ok || !node.active || !node.focusable {
			rt.focused = focus_fallback(rt, focus_lineage[:], !focus_was_in_virtual_list)
		}
	}
	if rt.focused != previous_focus {
		// The old focus owner may have been retired during reconciliation. The
		// new owner still needs an interaction repaint so a fallback caret or
		// focus decoration appears on the very next frame.
		invalidate_interaction_paint(rt, previous_focus, "focus visual state changed")
		invalidate_interaction_paint(rt, rt.focused, "focus visual state changed")
	}

	prepare_text_runs(rt)
	layout_tree(rt)
	update_paint(rt)
	rt.frame_open = false
	rt.invalidated = rt.scroll_geometry_changed
	rt.scroll_geometry_changed = false
	rt.virtual_viewport_changed = false
	// This description already observed the final geometry-surface bounds.
	rt.geometry_surface_bounds_changed = false
	rt.presentation_pending = false
	advance_presentation_revision(rt)
	rt.stats.frame += 1
	delete(focus_lineage)
	record_trace(rt, .Reconcile, 0, fmt.tprintf("frame %d reconciled", rt.stats.frame))
	note_submission_cause(rt, rt.frame_cause)
	if rt.invalidated { note_pending_work_cause(rt, rt.frame_cause) }
	rt.frame_cause = Cause_Context{}
}

end_presentation_frame :: proc(ui: ^UI) {
	rt := ui.runtime
	if !rt.frame_open || rt.invalidated {
		return
	}
	// Interaction-only frames do not have descriptions to reconcile. Existing
	// child adjacency remains authoritative; pending retained layout and paint
	// work are flushed without rerunning application code.
	if rt.layout_pending { layout_tree(rt) }
	update_paint(rt)
	rt.frame_open = false
	rt.invalidated = rt.virtual_viewport_changed || rt.geometry_surface_bounds_changed
	rt.virtual_viewport_changed = false
	rt.scroll_geometry_changed = false
	rt.geometry_surface_bounds_changed = false
	rt.presentation_pending = false
	advance_presentation_revision(rt)
	rt.stats.frame += 1
	record_trace(rt, .Composite, 0, "retained presentation frame flushed")
	note_submission_cause(rt, rt.frame_cause)
	if rt.invalidated { note_pending_work_cause(rt, rt.frame_cause) }
	rt.frame_cause = Cause_Context{}
}

destroy_runtime :: proc(rt: ^Runtime) {
	for _, node in rt.nodes {
		for command in node.paint { if len(command.text) > 0 { delete(command.text, rt.persistent_allocator) } }
		delete(node.paint)
		delete(node.children)
		delete(node.surface_samples)
		delete(node.surface_segments)
		delete(node.surface_circles)
		text_run_destroy(&node.text_run)
		clear_text_composition(node, rt.persistent_allocator)
		release_node_strings(node, rt.persistent_allocator)
		free(node, allocator=rt.persistent_allocator)
	}
	delete(rt.nodes)
	delete(rt.order)
	delete(rt.top_level)
	delete(rt.pending)
	delete(rt.seen)
	delete(rt.identity_scopes)
	delete(rt.stack)
	delete(rt.identity_stack)
	delete(rt.identity_labels)
	delete(rt.identity_key_u64)
	delete(rt.identity_key_numeric)
	delete(rt.identity_key_kind)
	delete(rt.identity_key_pair)
	delete(rt.paint_queue)
	for entry in rt.trace.events { if entry.reason_owned && len(entry.reason) > 0 { delete(entry.reason, rt.persistent_allocator) } }
	delete(rt.trace.events)
	delete(rt.display)
	text_engine_destroy(&rt.text_engine)
	if rt.scratch_arena != nil {
		mem.dynamic_arena_destroy(rt.scratch_arena)
		free(rt.scratch_arena, allocator=rt.persistent_allocator)
		rt.scratch_arena = nil
	}
	if rt.scratch_allocator_state != nil {
		free(rt.scratch_allocator_state, allocator=rt.persistent_allocator)
		rt.scratch_allocator_state = nil
	}
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	if len(rt.diagnostic) > 0 { delete(rt.diagnostic, rt.persistent_allocator) }
	if rt.persistent_allocator_state != nil {
		free(rt.persistent_allocator_state, allocator=rt.persistent_backing_allocator)
		rt.persistent_allocator_state = nil
	}
	// The runtime has released every retained allocation by this point. The
	// allocator wrapper cannot always reconstruct exact resize deltas from an
	// arbitrary backing allocator, so close the per-runtime requested-byte
	// lifetime explicitly at the ownership boundary.
	if rt.allocation_stats != nil {
		rt.allocation_stats.persistent_requested_bytes_live = 0
	}
	if rt.allocation_stats_owned && rt.allocation_stats != nil {
		free(rt.allocation_stats, allocator=rt.persistent_backing_allocator)
	}
	rt.allocation_stats = nil
}

focus_fallback :: proc(rt: ^Runtime, lineage: []Node_ID, allow_global := true) -> Node_ID {
	for i := 1; i < len(lineage); i += 1 {
		if parent, ok := rt.nodes[lineage[i]]; ok && parent.active && parent.focusable {
			return lineage[i]
		}
	}
	// Virtualized descendants are transient. If one disappears, moving focus
	// to the first unrelated control in the application is surprising; retain
	// focus only through a surviving ancestor in that list's lineage.
	if !allow_global { return 0 }
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.active && node.focusable {
			return id
		}
	}
	return 0
}

end_frame :: proc(ui: ^UI) {
	if !ui.runtime.frame_open {
		return
	}
	if len(ui.runtime.stack) != 0 || len(ui.runtime.identity_stack) != 0 {
		append_diagnostic(ui.runtime, "unbalanced container or identity scope at end_frame")
		clear(&ui.runtime.stack)
		clear(&ui.runtime.identity_stack)
		clear(&ui.runtime.identity_labels)
		clear(&ui.runtime.identity_key_u64)
		clear(&ui.runtime.identity_key_numeric)
	}
	reconcile(ui.runtime)
}
