package alicorn

rebuild_display :: proc(rt: ^Runtime) {
	clear(&rt.display)
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok || !node.active { continue }
		node.display_index = -1
		for command in node.paint {
			if node.display_index < 0 { node.display_index = len(rt.display) }
			append(&rt.display, command)
			rt.stats.composition_nodes_visited += 1
		}
	}
	rt.stats.composite_updates += 1
	rt.composition_rebuild = false
	record_trace(rt, .Composite, 0, "retained display list rebuilt after structure change")
}

update_paint :: proc(rt: ^Runtime) {
	// Only nodes queued by description or layout changes are visited. An
	// unchanged retained display command is left in place.
	for id in rt.paint_queue {
		node, ok := rt.nodes[id]
		if !ok { continue }
		node.paint_queued = false
		if !node.active { continue }
		rt.stats.paint_nodes_visited += 1
		if node.dirty.paint || len(node.paint) == 0 {
			for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
			clear(&node.paint)
			display_text := node.label if node.label != "" else node.text
			append(&node.paint, Display_Command{node.id, node.kind, node.bounds, node.clip, owned(display_text), node.color})
			rt.stats.paint_updates += 1
			node.dirty.composite = true
			record_trace(rt, .Paint, id, node.last_reason)
		}
		if !rt.composition_rebuild && node.display_index >= 0 && len(node.paint) > 0 {
			rt.display[node.display_index] = node.paint[0]
			rt.stats.composition_nodes_visited += 1
			rt.stats.composite_updates += 1
			record_trace(rt, .Composite, id, "retained display command updated")
		} else {
			rt.composition_rebuild = true
		}
		node.dirty.description = false
		node.dirty.paint = false
		node.dirty.composite = false
	}
	clear(&rt.paint_queue)
	if rt.composition_rebuild {
		rebuild_display(rt)
	}
}
