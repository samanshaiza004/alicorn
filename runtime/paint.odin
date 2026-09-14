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
			if node.kind == .Text_Field && node.composition.active {
				prepare_text_composition_node(rt, node)
			}
			for command in node.paint { if len(command.text) > 0 { delete(command.text) } }
			clear(&node.paint)
			display_text := node.label if node.label != "" else node.text
			display_kind := node.kind
			if node.kind == .Text_Field && node.composition.active && node.composition_run_valid {
				// A composition command renders the temporary projection once;
				// the committed selection is not rendered underneath it.
				display_text = node.composition_run.value
				display_kind = .Text_Composition
			}
			if node.kind == .Text_Field && node.text_run_valid {
				if !node.composition.active {
					selection := text_run_selection_rects(
						&node.text_run,
						node.selection_anchor,
						node.selection_focus,
					)
					for selected in selection {
						bounds := selected.rect
						bounds.x += node.bounds.x
						bounds.y += node.bounds.y
						append(&node.paint, Display_Command{
							node.id, .Text_Selection, bounds, node.clip, "",
							Color{0.20, 0.42, 0.78, 0.45},
						})
					}
					delete(selection)
				} else if node.composition_run_valid {
					visual_start := text_composition_visual_start(node)
					preedit_start := visual_start + grapheme_floor_boundary(node.composition.text, node.composition.selection_start)
					preedit_end := visual_start + grapheme_ceil_boundary(node.composition.text, node.composition.selection_end)
					if preedit_start == preedit_end {
						preedit_end = visual_start + len(node.composition.text)
					}
					selection := text_run_selection_rects(
						&node.composition_run,
						Text_Position{preedit_start, .Leading},
						Text_Position{preedit_end, .Trailing},
					)
					for selected in selection {
						bounds := selected.rect
						bounds.x += node.bounds.x
						bounds.y += node.bounds.y + bounds.h - 2
						bounds.h = 1
						append(&node.paint, Display_Command{
							node.id, .Text_Selection, bounds, node.clip, "",
							Color{0.70, 0.86, 1.0, 0.95},
						})
					}
					delete(selection)
				}
			}
			append(&node.paint, Display_Command{node.id, display_kind, node.bounds, node.clip, owned(display_text), node.color})
			if node.kind == .Text_Field && rt.focused == node.id {
				caret := text_field_caret_geometry(rt, node.id)
				caret.rect.x -= node.bounds.x
				caret.rect.y -= node.bounds.y
				if caret.valid {
					bounds := caret.rect
					bounds.x += node.bounds.x
					bounds.y += node.bounds.y
					append(&node.paint, Display_Command{
						node.id, .Text_Caret, bounds, node.clip, "",
						Color{0.92, 0.95, 1.0, 1.0},
					})
				}
			}
			rt.stats.paint_updates += 1
			node.dirty.composite = true
			record_trace(rt, .Paint, id, node.last_reason)
		}
		if !rt.composition_rebuild && node.display_index >= 0 && len(node.paint) == 1 {
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
