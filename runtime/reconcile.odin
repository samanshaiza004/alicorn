package alicorn

import "core:fmt"

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

description_hash :: proc(d: Description) -> u64 {
	h := hash_mix(hash_string(d.label), hash_string(d.text))
	h = hash_mix(h, u64(d.kind))
	h = hash_mix(h, d.paint_value)
	h = hash_mix(h, hash_color(d.color))
	h = hash_mix(h, d.region_revision)
	return h
}

layout_hash :: proc(d: Description) -> u64 {
	return hash_mix(hash_style(d.style), u64(d.parent))
}

paint_hash :: proc(d: Description) -> u64 {
	h := description_hash(d)
	h = hash_mix(h, u64(d.focusable ? 1 : 0))
	return h
}

same_rect :: proc(a, b: Rect) -> bool {
	return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h
}

mark_dirty :: proc(node: ^Node, reason: string, description, layout, paint, composite: bool) {
	previous_paint := node.dirty.paint
	previous_composite := node.dirty.composite
	node.dirty = Dirty_Stages{description, layout, paint || previous_paint, composite || previous_composite}
	if !previous_paint {
		if len(node.last_reason) > 0 { delete(node.last_reason) }
		node.last_reason = owned(reason)
	}
}

replace_owned :: proc(destination: ^string, value: string) {
	if destination^ == value { return }
	if len(destination^) > 0 { delete(destination^) }
	destination^ = owned(value)
}

replace_site :: proc(destination: ^Source_Site, value: Source_Site) {
	replace_owned(&destination.file, value.file)
	replace_owned(&destination.component, value.component)
	destination.line = value.line
	destination.column = value.column
}

release_node_strings :: proc(node: ^Node) {
	if len(node.site.file) > 0 { delete(node.site.file) }
	if len(node.site.component) > 0 { delete(node.site.component) }
	if len(node.key) > 0 { delete(node.key) }
	if len(node.label) > 0 { delete(node.label) }
	if len(node.text) > 0 { delete(node.text) }
	if len(node.identity_key) > 0 { delete(node.identity_key) }
	if len(node.last_reason) > 0 { delete(node.last_reason) }
	node.site = Source_Site{}
	node.key, node.label, node.text, node.identity_key, node.last_reason = "", "", "", "", ""
}

node_has_text_product :: proc(kind: Node_Kind) -> bool {
	return kind == .Text || kind == .Text_Field
}

copy_node_description :: proc(node: ^Node, d: Description) {
	// Runtime-owned copies are important: a generic description may borrow a
	// caller's string for only the duration of this procedure.
	text_changed := node.text != d.text
	kind_changed := node.kind != d.kind
	if node.text_run_valid && (text_changed || kind_changed || !node_has_text_product(d.kind)) {
		text_run_destroy(&node.text_run)
		node.text_run_valid = false
	}
	if text_changed || kind_changed || !node_has_text_product(d.kind) {
		clear_text_composition(node)
	}
	replace_site(&node.site, d.site)
	replace_owned(&node.key, d.key)
	replace_owned(&node.label, d.label)
	replace_owned(&node.text, d.text)
	node.parent = d.parent
	node.kind = d.kind
	node.style = d.style
	node.color = d.color
	node.paint_value = d.paint_value
	node.region_revision = d.region_revision
	node.region = d.region
	node.focusable = d.focusable
	replace_owned(&node.identity_key, d.identity_key)
	node.identity_key_u64 = d.identity_key_u64
	node.identity_key_numeric = d.identity_key_numeric
	if text_changed {
		node.caret = Text_Position{len(d.text), .Leading}
		node.selection_anchor = node.caret
		node.selection_focus = node.caret
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
	node.dirty.paint = true
	node.dirty.composite = true
	if len(node.last_reason) > 0 { delete(node.last_reason) }
	node.last_reason = owned(reason)
	queue_paint(rt, id)
	record_trace(rt, .Invalidation, id, reason)
}

mark_layout_ancestors :: proc(rt: ^Runtime, id: Node_ID) {
	current := id
	for current != 0 {
		node, ok := rt.nodes[current]
		if !ok { break }
		node.dirty.layout = true
		node.dirty.composite = true
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
	if id == rt.captured_node { rt.captured_node = 0 }
	if id == rt.selected { rt.selected = 0 }
	delete_key(&rt.nodes, id)
	for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
	delete(node.paint)
	delete(node.children)
	text_run_destroy(&node.text_run)
	clear_text_composition(node)
	release_node_strings(node)
	free(node)
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
	focus_lineage := make([dynamic]Node_ID, 0)
	if previous_focus != 0 {
		current := previous_focus
		for current != 0 {
			append(&focus_lineage, current)
			old, ok := rt.nodes[current]
			if !ok { break }
			current = old.parent
		}
	}

	desired := make(map[Node_ID]bool)
	reused_roots := make(map[Node_ID]bool)
	buckets := make([dynamic]Desired_Children, 0)
	for item in rt.pending {
		switch item.kind {
		case .Description:
			d := item.description
			desired[d.id] = true
			index := desired_children_index(buckets[:], d.parent)
			if index < 0 {
				append(&buckets, Desired_Children{d.parent, make([dynamic]Node_ID, 0)})
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
		node, exists := rt.nodes[d.id]
		if !exists {
			node = new(Node)
			node.id = d.id
			node.display_index = -1
			rt.nodes[d.id] = node
			rt.stats.nodes_created += 1
			copy_node_description(node, d)
			node.description_hash = description_hash(d)
			node.layout_hash = layout_hash(d)
			node.paint_hash = paint_hash(d)
			mark_dirty(node, "new retained node", true, true, true, true)
			queue_paint(rt, d.id)
			mark_layout_ancestors(rt, d.id)
			record_trace(rt, .Reconcile, d.id, "new retained node")
		} else {
			new_desc_hash := description_hash(d)
			new_layout_hash := layout_hash(d)
			new_paint_hash := paint_hash(d)
			description_changed := node.description_hash != new_desc_hash
			layout_changed := node.layout_hash != new_layout_hash
			paint_changed := node.paint_hash != new_paint_hash
			copy_node_description(node, d)
			node.description_hash = new_desc_hash
			node.layout_hash = new_layout_hash
			node.paint_hash = new_paint_hash
			reason := "description reused"
			if description_changed { reason = "description changed" }
			mark_dirty(node, reason, description_changed, layout_changed, paint_changed || layout_changed, false)
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
	processed_parents := make(map[Node_ID]bool)
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
			rt.focused = focus_fallback(rt, focus_lineage[:])
			if rt.focused != previous_focus {
				record_trace(rt, .Focus, rt.focused, "focused node disappeared; deterministic fallback")
			}
		}
	}
	if rt.focused != 0 {
		if node, ok := rt.nodes[rt.focused]; !ok || !node.active || !node.focusable {
			rt.focused = focus_fallback(rt, focus_lineage[:])
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
	rt.invalidated = false
	rt.stats.frame += 1
	delete(focus_lineage)
	record_trace(rt, .Reconcile, 0, fmt.tprintf("frame %d reconciled", rt.stats.frame))
}

destroy_runtime :: proc(rt: ^Runtime) {
	for _, node in rt.nodes {
		for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
		delete(node.paint)
		delete(node.children)
		text_run_destroy(&node.text_run)
		clear_text_composition(node)
		release_node_strings(node)
		free(node)
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
	delete(rt.paint_queue)
	for entry in rt.trace.events { if len(entry.reason) > 0 { delete(entry.reason) } }
	delete(rt.trace.events)
	delete(rt.display)
	text_engine_destroy(&rt.text_engine)
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason) }
	if len(rt.diagnostic) > 0 { delete(rt.diagnostic) }
}

focus_fallback :: proc(rt: ^Runtime, lineage: []Node_ID) -> Node_ID {
	for i := 1; i < len(lineage); i += 1 {
		if parent, ok := rt.nodes[lineage[i]]; ok && parent.active && parent.focusable {
			return lineage[i]
		}
	}
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
