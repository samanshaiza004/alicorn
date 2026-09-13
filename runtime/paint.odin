package alicorn

update_paint :: proc(rt: ^Runtime) {
	composite_dirty := false
	clear(&rt.display)
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok || !node.active { continue }
		if node.dirty.paint || len(node.paint) == 0 {
			for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
			clear(&node.paint)
			display_text := node.label if node.label != "" else node.text
			append(&node.paint, Display_Command{node.kind, node.bounds, owned(display_text), node.color})
			rt.stats.paint_updates += 1
			node.dirty.composite = true
			record_trace(rt, .Paint, id, node.last_reason)
		}
		if node.dirty.composite {
			composite_dirty = true
		}
	}
	if composite_dirty {
		for id in rt.order {
			if node, ok := rt.nodes[id]; ok && node.active {
				for command in node.paint { append(&rt.display, command) }
			}
		}
		rt.stats.composite_updates += 1
		record_trace(rt, .Composite, 0, "retained display list rebuilt")
	}
	for _, node in rt.nodes {
		node.dirty.description = false
		node.dirty.layout = false
		node.dirty.paint = false
		node.dirty.composite = false
	}
}
