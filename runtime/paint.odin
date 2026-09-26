package alicorn

append_focus_outline :: proc(node: ^Node, color: Color, thickness: f32) {
	width := min(max(thickness, 0), node.bounds.w/2)
	height := min(max(thickness, 0), node.bounds.h/2)
	if width <= 0 || height <= 0 { return }
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x, node.bounds.y, node.bounds.w, height}, node.clip, "", color})
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x, node.bounds.y+node.bounds.h-height, node.bounds.w, height}, node.clip, "", color})
	interior_height := max(0, node.bounds.h-height*2)
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x, node.bounds.y+height, width, interior_height}, node.clip, "", color})
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x+node.bounds.w-width, node.bounds.y+height, width, interior_height}, node.clip, "", color})
}

append_scrollbar_display :: proc(rt: ^Runtime, node: ^Node) {
	if node.kind != .Scroll_Region { return }
	if node.scrollbar_vertical_visible {
		append(&rt.display, Display_Command{node.id, .Scrollbar_Track, node.scrollbar_vertical_track, node.clip, "", Color{0.08, 0.10, 0.14, 1}})
		append(&rt.display, Display_Command{node.id, .Scrollbar_Thumb, node.scrollbar_vertical_thumb, node.clip, "", Color{0.38, 0.48, 0.62, 1}})
	}
	if node.scrollbar_horizontal_visible {
		append(&rt.display, Display_Command{node.id, .Scrollbar_Track, node.scrollbar_horizontal_track, node.clip, "", Color{0.08, 0.10, 0.14, 1}})
		append(&rt.display, Display_Command{node.id, .Scrollbar_Thumb, node.scrollbar_horizontal_thumb, node.clip, "", Color{0.38, 0.48, 0.62, 1}})
	}
	if node.scrollbar_vertical_visible && node.scrollbar_horizontal_visible {
		corner := Rect{node.scrollbar_vertical_track.x, node.scrollbar_horizontal_track.y, node.scrollbar_vertical_track.w, node.scrollbar_horizontal_track.h}
		append(&rt.display, Display_Command{node.id, .Scrollbar_Corner, corner, node.clip, "", Color{0.06, 0.08, 0.11, 1}})
	}
}

compose_subtree :: proc(rt: ^Runtime, id: Node_ID) {
	node, ok := rt.nodes[id]
	if !ok || !node.active { return }

	node.display_index = -1
	for command in node.paint {
		if node.display_index < 0 { node.display_index = len(rt.display) }
		append(&rt.display, command)
		rt.stats.composition_nodes_visited += 1
		rt.stats.stage_visits[.Composite] += 1
	}
	for child in node.children {
		compose_subtree(rt, child)
	}
	// Scrollbars are local retained chrome: they paint above their scroll
	// region's descendants, but remain below later siblings and top-level
	// overlays such as modal command palettes.
	append_scrollbar_display(rt, node)
}

rebuild_display :: proc(rt: ^Runtime) {
	clear(&rt.display)
	for id in rt.top_level {
		compose_subtree(rt, id)
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
		rt.stats.stage_visits[.Paint] += 1
		if dirty_has(node.dirty, .Paint) || len(node.paint) == 0 {
			if node.kind == .Text_Field && node.composition.active {
				prepare_text_composition_node(rt, node)
			}
			for command in node.paint { if len(command.text) > 0 { delete(command.text, rt.persistent_allocator) } }
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
						allocator=rt.scratch_allocator,
						scratch_allocator=rt.scratch_allocator,
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
						allocator=rt.scratch_allocator,
						scratch_allocator=rt.scratch_allocator,
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
			if node.kind == .Root || node.kind == .Modal_Overlay || node.kind == .Container || node.kind == .Virtual_List || node.kind == .Virtual_Row || node.kind == .Split || node.kind == .Scroll_Region {
				// Layout containers are non-painting unless the caller explicitly
				// supplied a background. This keeps structural wrappers from
				// producing accidental rectangles in the compositor.
				if node.paint_background {
					append(&node.paint, Display_Command{node.id, node.kind, node.bounds, node.clip, "", node.color})
				}
				if node.kind == .Scroll_Region && rt.focused == node.id {
					append_focus_outline(node, Color{0.76, 0.86, 1.0, 1}, 1.5)
				}
			} else if node.kind == .Button {
				padding_x := maxf(node.button_content_style.padding_x, 0)
				padding_y := maxf(node.button_content_style.padding_y, 0)
				content_bounds := Rect{
					node.bounds.x + padding_x,
					node.bounds.y + padding_y,
					maxf(node.bounds.w - 2*padding_x, 0),
					maxf(node.bounds.h - 2*padding_y, 0),
				}
				text_bounds := content_bounds
				if node.text_run_valid {
					#partial switch node.button_content_style.horizontal {
					case .Center:
						text_bounds.x += (content_bounds.w-node.text_run.width)/2
					case .End:
						text_bounds.x += content_bounds.w-node.text_run.width
					}
					#partial switch node.button_content_style.vertical {
					case .Center:
						text_bounds.y += (content_bounds.h-node.text_run.height)/2
					case .End:
						text_bounds.y += content_bounds.h-node.text_run.height
					}
				}
				text_clip := rect_intersection(node.clip, content_bounds)
				quiet := (node.paint_value & 4) != 0
				button_color := Color{0.08, 0.10, 0.14, 1}
				if !quiet { button_color = Color{0.15, 0.25, 0.42, 1} }
				if node.selected { button_color = Color{0.27, 0.48, 0.70, 1} }
				if node.pressed {
					button_color = Color{0.15, 0.22, 0.32, 1}
					if !quiet { button_color = Color{0.24, 0.42, 0.68, 1} }
					if node.selected { button_color = Color{0.36, 0.62, 0.86, 1} }
				} else if node.hovered {
					button_color = Color{0.12, 0.16, 0.23, 1}
					if !quiet { button_color = Color{0.20, 0.34, 0.54, 1} }
					if node.selected { button_color = Color{0.33, 0.57, 0.80, 1} }
				}
				text_color := Color{0.90, 0.95, 1.0, 1.0}
				if node.disabled {
					button_color = Color{0.10, 0.13, 0.18, 1}
					text_color = Color{0.48, 0.53, 0.62, 1.0}
				}
				append(&node.paint, Display_Command{node.id, .Button, node.bounds, node.clip, "", button_color})
				if node.semantic_active {
					append_focus_outline(node, Color{0.12, 0.78, 0.82, 1}, 1)
				}
				if rt.focused == node.id && !node.disabled {
					// Focus is an independent outline so it remains visible without
					// replacing the selected, hover, or pressed fill.
					focus_color := Color{0.76, 0.86, 1.0, 1}
					append_focus_outline(node, focus_color, 1.5)
				}
				append(&node.paint, Display_Command{node.id, .Text, text_bounds, text_clip, owned(display_text, rt.persistent_allocator), text_color})
			} else if node.kind == .Checkbox {
				box_size := minf(18, maxf(node.bounds.h-6, 12))
				box := Rect{node.bounds.x+4, node.bounds.y+(node.bounds.h-box_size)*0.5, box_size, box_size}
				box_color := Color{0.32, 0.38, 0.48, 1}
				if node.disabled { box_color = Color{0.20, 0.23, 0.29, 1} }
				if node.hovered && !node.disabled { box_color = Color{0.48, 0.60, 0.76, 1} }
				if node.pressed && !node.disabled { box_color = Color{0.58, 0.70, 0.86, 1} }
				append(&node.paint, Display_Command{node.id, .Button, box, node.clip, "", box_color})
				inner := Rect{box.x+2, box.y+2, maxf(box.w-4, 0), maxf(box.h-4, 0)}
				inner_color := Color{0.035, 0.045, 0.065, 1}
				if node.paint_value&1 != 0 { inner_color = Color{0.20, 0.48, 0.76, 1} }
				if node.disabled {
					inner_color = Color{0.08, 0.09, 0.12, 1}
					if node.paint_value&1 != 0 { inner_color = Color{0.18, 0.24, 0.31, 1} }
				}
				append(&node.paint, Display_Command{node.id, .Button, inner, node.clip, "", inner_color})
				if node.paint_value&1 != 0 {
					check_color := Color{0.94, 0.97, 1, 1}
					append(&node.paint,
						Display_Command{node.id, .Button, Rect{box.x+4, box.y+box.h*0.55, box.w*0.24, 2}, node.clip, "", check_color},
						Display_Command{node.id, .Button, Rect{box.x+7, box.y+box.h*0.48, box.w*0.27, 2}, node.clip, "", check_color},
						Display_Command{node.id, .Button, Rect{box.x+10, box.y+box.h*0.36, box.w*0.26, 2}, node.clip, "", check_color},
					)
				}
				if rt.focused == node.id && !node.disabled {
					append_focus_outline(node, Color{0.76, 0.86, 1.0, 1}, 1.5)
				}
				text_color := Color{0.88, 0.91, 0.96, 1}
				if node.disabled { text_color = Color{0.48, 0.53, 0.62, 1} }
				text_bounds := Rect{node.bounds.x+30, node.bounds.y, maxf(node.bounds.w-34, 0), node.bounds.h}
				if node.text_run_valid { text_bounds.y += (text_bounds.h-node.text_run.height)*0.5 }
				append(&node.paint, Display_Command{node.id, .Text, text_bounds, rect_intersection(node.clip, text_bounds), owned(display_text, rt.persistent_allocator), text_color})
			} else if node.kind == .Slider {
				text_color := Color{0.88, 0.91, 0.96, 1}
				if node.disabled { text_color = Color{0.48, 0.53, 0.62, 1} }
				label_bounds := Rect{node.bounds.x+8, node.bounds.y+1, maxf(node.bounds.w-16, 0), minf(maxf(node.bounds.h-14, 0), node.text_run.height)}
				append(&node.paint, Display_Command{node.id, .Text, label_bounds, rect_intersection(node.clip, label_bounds), owned(display_text, rt.persistent_allocator), text_color})
				track_x := node.bounds.x + minf(8, node.bounds.w*0.25)
				track_width := maxf(node.bounds.w-minf(16, node.bounds.w*0.5), 1)
				track_y := node.bounds.y + node.bounds.h - 8
				track := Rect{track_x, track_y-2, track_width, 4}
				fraction: f32 = 0
				if node.control_maximum > node.control_minimum {
					fraction = clampf((node.control_value-node.control_minimum)/(node.control_maximum-node.control_minimum), 0, 1)
				}
				thumb_x := track_x + fraction*track_width
				track_color := Color{0.16, 0.20, 0.27, 1}
				fill_color := Color{0.25, 0.54, 0.82, 1}
				thumb_color := Color{0.78, 0.86, 0.96, 1}
				if node.disabled {
					fill_color = Color{0.23, 0.29, 0.36, 1}
					thumb_color = Color{0.46, 0.50, 0.57, 1}
				} else if node.hovered || node.pressed {
					fill_color = Color{0.32, 0.66, 0.94, 1}
					thumb_color = Color{0.94, 0.97, 1, 1}
				}
				append(&node.paint,
					Display_Command{node.id, .Button, track, node.clip, "", track_color},
					Display_Command{node.id, .Button, Rect{track_x, track_y-2, maxf(thumb_x-track_x, 0), 4}, node.clip, "", fill_color},
					Display_Command{node.id, .Button, Rect{thumb_x-5, track_y-6, 10, 12}, node.clip, "", thumb_color},
				)
				if rt.focused == node.id && !node.disabled {
					append_focus_outline(node, Color{0.76, 0.86, 1.0, 1}, 1.5)
				}
			} else if node.kind == .Split_Handle {
				handle_color := Color{0.20, 0.24, 0.31, 1}
				if node.hovered { handle_color = Color{0.35, 0.53, 0.72, 1} }
				if node.pressed { handle_color = Color{0.42, 0.66, 0.90, 1} }
				append(&node.paint, Display_Command{node.id, .Split_Handle, node.bounds, node.clip, "", handle_color})
			} else {
				text_clip := node.clip
				if node.text_style.overflow != .Wrap {
					text_clip = rect_intersection(node.clip, node.bounds)
				}
				append(&node.paint, Display_Command{node.id, display_kind, node.bounds, text_clip, owned(display_text, rt.persistent_allocator), node.color})
			}
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
			dirty_set(&node.dirty, .Composite, true)
			record_trace(rt, .Paint, id, node.last_reason)
		}
		if !rt.composition_rebuild && node.kind != .Scroll_Region && node.display_index >= 0 && len(node.paint) == 1 {
			rt.display[node.display_index] = node.paint[0]
			rt.stats.composition_nodes_visited += 1
			rt.stats.stage_visits[.Composite] += 1
			rt.stats.composite_updates += 1
			record_trace(rt, .Composite, id, "retained display command updated")
		} else {
			rt.composition_rebuild = true
		}
		dirty_set(&node.dirty, .Description, false)
		dirty_set(&node.dirty, .Paint, false)
		dirty_set(&node.dirty, .Composite, false)
	}
	clear(&rt.paint_queue)
	if rt.composition_rebuild {
		rebuild_display(rt)
	}
}
