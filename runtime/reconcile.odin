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
	if len(node.last_reason) > 0 { delete(node.last_reason) }
	node.dirty = Dirty_Stages{description, layout, paint, composite}
	node.last_reason = owned(reason)
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

copy_node_description :: proc(node: ^Node, d: Description) {
	// Runtime-owned copies are important: a generic description may borrow a
	// caller's string for only the duration of this procedure.
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
	for _, node in rt.nodes {
		node.active = false
		node.present = false
	}
	clear(&rt.order)
	for d in rt.pending {
		node, exists := rt.nodes[d.id]
		if !exists {
			node = new(Node)
			node.id = d.id
			rt.nodes[d.id] = node
			rt.stats.nodes_created += 1
			copy_node_description(node, d)
			node.description_hash = description_hash(d)
			node.layout_hash = layout_hash(d)
			node.paint_hash = paint_hash(d)
			mark_dirty(node, "new retained node", true, true, true, true)
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
			if description_changed {
				reason = "description changed"
			}
			mark_dirty(node, reason, description_changed, layout_changed, paint_changed || layout_changed, false)
			if layout_changed { mark_layout_ancestors(rt, d.id) }
			if description_changed || layout_changed || paint_changed {
				record_trace(rt, .Reconcile, d.id, reason)
			} else {
				rt.stats.descriptions_reused += 1
			}
		}
		node.active = true
		node.present = true
		append(&rt.order, d.id)
		if cache, ok := rt.region_captures[d.id]; ok {
			free_region_cache(node)
			node.region_cache = cache
			node.region_cached = true
		}
	}

	// Retire nodes omitted by this description. The map is authoritative; no
	// application pointer or widget object is retained outside it.
	for id, node in rt.nodes {
		if !node.active {
			delete_key(&rt.nodes, id)
			if id == rt.last_hovered { rt.last_hovered = 0 }
			if id == rt.pressed_node { rt.pressed_node = 0 }
			if id == rt.selected { rt.selected = 0 }
			free_region_cache(node)
			for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
			delete(node.paint)
			delete(node.children)
			release_node_strings(node)
			free(node)
			rt.stats.nodes_retired += 1
			record_trace(rt, .Retire, id, "node disappeared from description")
		}
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

	rebuild_adjacency(rt)
	layout_tree(rt)
	update_paint(rt)
	rt.frame_open = false
	rt.invalidated = false
	rt.stats.frame += 1
	delete(focus_lineage)
	record_trace(rt, .Reconcile, 0, fmt.tprintf("frame %d reconciled", rt.stats.frame))
}

free_region_cache :: proc(node: ^Node) {
	// The cache owns its cloned descriptions. Freeing is best-effort and keeps
	// long-running region revisions from growing without bound.
	for d in node.region_cache {
		if len(d.site.file) > 0 { delete(d.site.file) }
		if len(d.site.component) > 0 { delete(d.site.component) }
		if len(d.key) > 0 { delete(d.key) }
		if len(d.label) > 0 { delete(d.label) }
		if len(d.text) > 0 { delete(d.text) }
		if len(d.identity_key) > 0 { delete(d.identity_key) }
	}
	delete(node.region_cache)
	node.region_cache = nil
}

destroy_runtime :: proc(rt: ^Runtime) {
	for _, node in rt.nodes {
		free_region_cache(node)
		for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
		delete(node.paint)
		delete(node.children)
		release_node_strings(node)
		free(node)
	}
	delete(rt.nodes)
	delete(rt.order)
	delete(rt.pending)
	delete(rt.seen)
	delete(rt.region_captures)
	delete(rt.identity_scopes)
	delete(rt.stack)
	delete(rt.identity_stack)
	delete(rt.identity_labels)
	for entry in rt.trace.events { if len(entry.reason) > 0 { delete(entry.reason) } }
	delete(rt.trace.events)
	delete(rt.display)
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
	}
	reconcile(ui.runtime)
}
