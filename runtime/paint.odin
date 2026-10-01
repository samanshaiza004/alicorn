package alicorn

import runa "../third_party/Runa"

Text_Paint_Caret_Key :: struct {
	line_index: int,
	byte: int,
	affinity: Text_Affinity,
}

Text_Paint_Geometry :: struct {
	grapheme_boundaries: [dynamic]int,
	caret_x: map[Text_Paint_Caret_Key]f32,
}

text_paint_insert_caret :: proc(geometry: ^Text_Paint_Geometry, line_index: int, position: Text_Position, x: f32) {
	key := Text_Paint_Caret_Key{line_index, position.byte, position.affinity}
	if _, found := geometry.caret_x[key]; !found { geometry.caret_x[key] = x }
}

text_paint_boundary_lower_bound :: proc(boundaries: []int, byte: int, strict := false) -> int {
	low, high := 0, len(boundaries)
	for low < high {
		middle := (low+high)/2
		if boundaries[middle] < byte || (strict && boundaries[middle] == byte) { low = middle+1 }
		else { high = middle }
	}
	return low
}

text_paint_geometry_make :: proc(run: ^Text_Run, allocator := context.temp_allocator) -> Text_Paint_Geometry {
	geometry := Text_Paint_Geometry{
		grapheme_boundaries=make([dynamic]int, 0, len(run.value)+1, allocator),
		caret_x=make(map[Text_Paint_Caret_Key]f32, allocator=allocator),
	}
	append(&geometry.grapheme_boundaries, 0)
	it := runa.grapheme_iter_make(run.value)
	for {
		_, end, ok := runa.grapheme_iter_next(&it)
		if !ok { break }
		append(&geometry.grapheme_boundaries, end)
	}
	for line, line_index in run.lines {
		for glyph_index := line.glyph_start; glyph_index < line.glyph_end; glyph_index += 1 {
			glyph := run.glyphs[glyph_index]
			start, end := glyph.cluster_start, glyph.cluster_end
			if start < 0 { start = 0 }
			if end > len(run.value) { end = len(run.value) }
			if end < start { end = start }
			if start == end {
				text_paint_insert_caret(&geometry, line_index, Text_Position{start, .Leading}, glyph.x)
				text_paint_insert_caret(&geometry, line_index, Text_Position{start, .Trailing}, glyph.x)
				continue
			}
			text_paint_insert_caret(&geometry, line_index, Text_Position{start, .Leading}, text_glyph_boundary_x(glyph, start))
			boundary_index := text_paint_boundary_lower_bound(geometry.grapheme_boundaries[:], start, true)
			for boundary_index < len(geometry.grapheme_boundaries) {
				byte := geometry.grapheme_boundaries[boundary_index]
				if byte > end { break }
				x := text_glyph_boundary_x(glyph, byte)
				if byte == end {
					text_paint_insert_caret(&geometry, line_index, Text_Position{byte, .Trailing}, x)
				} else {
					text_paint_insert_caret(&geometry, line_index, Text_Position{byte, .Leading}, x)
					text_paint_insert_caret(&geometry, line_index, Text_Position{byte, .Trailing}, x)
				}
				boundary_index += 1
			}
		}
		text_paint_insert_caret(&geometry, line_index, Text_Position{line.byte_start, .Leading}, line.x)
		text_paint_insert_caret(&geometry, line_index, Text_Position{line.byte_end, .Trailing}, line.width)
	}
	return geometry
}

text_paint_geometry_destroy :: proc(geometry: ^Text_Paint_Geometry) {
	if geometry == nil { return }
	if len(geometry.grapheme_boundaries) > 0 { delete(geometry.grapheme_boundaries) }
	if geometry.caret_x != nil { delete(geometry.caret_x) }
	geometry^ = Text_Paint_Geometry{}
}

text_paint_geometry_position_x :: proc(geometry: ^Text_Paint_Geometry, run: ^Text_Run, line_index: int, byte: int, affinity: Text_Affinity) -> f32 {
	key := Text_Paint_Caret_Key{line_index, byte, affinity}
	if x, found := geometry.caret_x[key]; found { return x }
	line := run.lines[line_index]
	if byte <= line.byte_start { return line.x }
	if byte >= line.byte_end { return line.width }
	return line.x
}

text_paint_grapheme_floor :: proc(boundaries: []int, byte: int) -> int {
	index := text_paint_boundary_lower_bound(boundaries, byte)
	if index < len(boundaries) && boundaries[index] == byte { return byte }
	if index > 0 { return boundaries[index-1] }
	return 0
}

text_paint_first_line_for_byte :: proc(run: ^Text_Run, byte: int) -> int {
	low, high := 0, len(run.lines)
	for low < high {
		middle := (low+high)/2
		if run.lines[middle].byte_end <= byte { low = middle+1 }
		else { high = middle }
	}
	return low
}

text_paint_geometry_needed :: proc(node: ^Node) -> bool {
	if node == nil { return false }
	for span in node.text_paint_spans {
		if span.background_set || span.underline || span.strikethrough { return true }
	}
	return false
}

append_text_paint_geometry :: proc(node: ^Node, geometry: ^Text_Paint_Geometry, command_clip: Rect, backgrounds: bool) {
	if node == nil || !node.text_run_valid || len(node.text_paint_spans) == 0 { return }
	for span in node.text_paint_spans {
		if backgrounds && !span.background_set { continue }
		if !backgrounds && !span.underline && !span.strikethrough { continue }
		start := clamp(span.start, 0, len(node.text_run.value))
		end := clamp(span.end, 0, len(node.text_run.value))
		if start >= end { continue }
		start = text_paint_grapheme_floor(geometry.grapheme_boundaries[:], start)
		end = text_paint_grapheme_floor(geometry.grapheme_boundaries[:], end)
		low, high := start, end
		if low > high { low, high = high, low }
		if low == high { continue }
		line_start_index := text_paint_first_line_for_byte(&node.text_run, low)
		for line_index := line_start_index; line_index < len(node.text_run.lines); line_index += 1 {
			line := node.text_run.lines[line_index]
			if high <= line.byte_start { break }
			if high <= line.byte_start || low >= line.byte_end { continue }
			selection_start := max(low, line.byte_start)
			selection_end := min(high, line.byte_end)
			left := line.x
			right := line.width
			if selection_start > line.byte_start {
				left = text_paint_geometry_position_x(geometry, &node.text_run, line_index, selection_start, .Leading)
			}
			if selection_end < line.byte_end {
				right = text_paint_geometry_position_x(geometry, &node.text_run, line_index, selection_end, .Trailing)
			}
			if right < left { left, right = right, left }
			if right <= left { continue }
			bounds := Rect{left, line.y, right-left, line.height}
			bounds.x += node.bounds.x
			bounds.y += node.bounds.y
			if backgrounds && span.background_set {
				append(&node.paint, Display_Command{node.id, .Text_Selection, bounds, command_clip, "", span.background, []Text_Paint_Span{}})
			}
			if !backgrounds {
				if span.underline {
					append(&node.paint, Display_Command{node.id, .Text_Selection, Rect{bounds.x, bounds.y+line.baseline+1, bounds.w, 1}, command_clip, "", span.color if span.color_set else node.color, []Text_Paint_Span{}})
				}
				if span.strikethrough {
					append(&node.paint, Display_Command{node.id, .Text_Selection, Rect{bounds.x, bounds.y+line.baseline-node.text_run.size*0.32, bounds.w, 1}, command_clip, "", span.color if span.color_set else node.color, []Text_Paint_Span{}})
				}
			}
		}
	}
}

append_focus_outline :: proc(node: ^Node, color: Color, thickness: f32) {
	width := min(max(thickness, 0), node.bounds.w/2)
	height := min(max(thickness, 0), node.bounds.h/2)
	if width <= 0 || height <= 0 { return }
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x, node.bounds.y, node.bounds.w, height}, node.clip, "", color, []Text_Paint_Span{}})
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x, node.bounds.y+node.bounds.h-height, node.bounds.w, height}, node.clip, "", color, []Text_Paint_Span{}})
	interior_height := max(0, node.bounds.h-height*2)
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x, node.bounds.y+height, width, interior_height}, node.clip, "", color, []Text_Paint_Span{}})
	append(&node.paint, Display_Command{node.id, .Button, Rect{node.bounds.x+node.bounds.w-width, node.bounds.y+height, width, interior_height}, node.clip, "", color, []Text_Paint_Span{}})
}

append_scrollbar_display :: proc(rt: ^Runtime, node: ^Node) {
	if node.kind != .Scroll_Region { return }
	if node.scrollbar_vertical_visible {
		append(&rt.display, Display_Command{node.id, .Scrollbar_Track, node.scrollbar_vertical_track, node.clip, "", Color{0.08, 0.10, 0.14, 1}, []Text_Paint_Span{}})
		append(&rt.display, Display_Command{node.id, .Scrollbar_Thumb, node.scrollbar_vertical_thumb, node.clip, "", Color{0.38, 0.48, 0.62, 1}, []Text_Paint_Span{}})
	}
	if node.scrollbar_horizontal_visible {
		append(&rt.display, Display_Command{node.id, .Scrollbar_Track, node.scrollbar_horizontal_track, node.clip, "", Color{0.08, 0.10, 0.14, 1}, []Text_Paint_Span{}})
		append(&rt.display, Display_Command{node.id, .Scrollbar_Thumb, node.scrollbar_horizontal_thumb, node.clip, "", Color{0.38, 0.48, 0.62, 1}, []Text_Paint_Span{}})
	}
	if node.scrollbar_vertical_visible && node.scrollbar_horizontal_visible {
		corner := Rect{node.scrollbar_vertical_track.x, node.scrollbar_horizontal_track.y, node.scrollbar_vertical_track.w, node.scrollbar_horizontal_track.h}
		append(&rt.display, Display_Command{node.id, .Scrollbar_Corner, corner, node.clip, "", Color{0.06, 0.08, 0.11, 1}, []Text_Paint_Span{}})
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
							Color{0.20, 0.42, 0.78, 0.45}, []Text_Paint_Span{},
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
							Color{0.70, 0.86, 1.0, 0.95}, []Text_Paint_Span{},
						})
					}
					delete(selection)
				}
			}
			if node.kind == .Root || node.kind == .Modal_Overlay || node.kind == .Context_Menu_Overlay || node.kind == .Context_Menu_Panel || node.kind == .Container || node.kind == .Virtual_List || node.kind == .Virtual_Row || node.kind == .Split || node.kind == .Scroll_Region {
				// Layout containers are non-painting unless the caller explicitly
				// supplied a background. This keeps structural wrappers from
				// producing accidental rectangles in the compositor.
				if node.paint_background {
					append(&node.paint, Display_Command{node.id, node.kind, node.bounds, node.clip, "", node.color, []Text_Paint_Span{}})
				}
				if node.kind == .Scroll_Region && semantic_focus_owner_needs_outline(rt, node.id) {
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
				append(&node.paint, Display_Command{node.id, .Button, node.bounds, node.clip, "", button_color, []Text_Paint_Span{}})
				if node.semantic_active {
					append_focus_outline(node, Color{0.12, 0.78, 0.82, 1}, 1)
				}
				if rt.focused == node.id && !node.disabled {
					// Focus is an independent outline so it remains visible without
					// replacing the selected, hover, or pressed fill.
					focus_color := Color{0.76, 0.86, 1.0, 1}
					append_focus_outline(node, focus_color, 1.5)
				}
				append(&node.paint, Display_Command{node.id, .Text, text_bounds, text_clip, owned(display_text, rt.persistent_allocator), text_color, []Text_Paint_Span{}})
			} else if node.kind == .Checkbox {
				box_size := minf(18, maxf(node.bounds.h-6, 12))
				box := Rect{node.bounds.x+4, node.bounds.y+(node.bounds.h-box_size)*0.5, box_size, box_size}
				box_color := Color{0.32, 0.38, 0.48, 1}
				if node.disabled { box_color = Color{0.20, 0.23, 0.29, 1} }
				if node.hovered && !node.disabled { box_color = Color{0.48, 0.60, 0.76, 1} }
				if node.pressed && !node.disabled { box_color = Color{0.58, 0.70, 0.86, 1} }
				append(&node.paint, Display_Command{node.id, .Button, box, node.clip, "", box_color, []Text_Paint_Span{}})
				inner := Rect{box.x+2, box.y+2, maxf(box.w-4, 0), maxf(box.h-4, 0)}
				inner_color := Color{0.035, 0.045, 0.065, 1}
				if node.paint_value&1 != 0 { inner_color = Color{0.20, 0.48, 0.76, 1} }
				if node.disabled {
					inner_color = Color{0.08, 0.09, 0.12, 1}
					if node.paint_value&1 != 0 { inner_color = Color{0.18, 0.24, 0.31, 1} }
				}
				append(&node.paint, Display_Command{node.id, .Button, inner, node.clip, "", inner_color, []Text_Paint_Span{}})
				if node.paint_value&1 != 0 {
					check_color := Color{0.94, 0.97, 1, 1}
					append(&node.paint,
						Display_Command{node.id, .Button, Rect{box.x+4, box.y+box.h*0.55, box.w*0.24, 2}, node.clip, "", check_color, []Text_Paint_Span{}},
						Display_Command{node.id, .Button, Rect{box.x+7, box.y+box.h*0.48, box.w*0.27, 2}, node.clip, "", check_color, []Text_Paint_Span{}},
						Display_Command{node.id, .Button, Rect{box.x+10, box.y+box.h*0.36, box.w*0.26, 2}, node.clip, "", check_color, []Text_Paint_Span{}},
					)
				}
				if rt.focused == node.id && !node.disabled {
					append_focus_outline(node, Color{0.76, 0.86, 1.0, 1}, 1.5)
				}
				text_color := Color{0.88, 0.91, 0.96, 1}
				if node.disabled { text_color = Color{0.48, 0.53, 0.62, 1} }
				text_bounds := Rect{node.bounds.x+30, node.bounds.y, maxf(node.bounds.w-34, 0), node.bounds.h}
				if node.text_run_valid { text_bounds.y += (text_bounds.h-node.text_run.height)*0.5 }
				append(&node.paint, Display_Command{node.id, .Text, text_bounds, rect_intersection(node.clip, text_bounds), owned(display_text, rt.persistent_allocator), text_color, []Text_Paint_Span{}})
			} else if node.kind == .Slider {
				text_color := Color{0.88, 0.91, 0.96, 1}
				if node.disabled { text_color = Color{0.48, 0.53, 0.62, 1} }
				label_bounds := Rect{node.bounds.x+8, node.bounds.y+1, maxf(node.bounds.w-16, 0), minf(maxf(node.bounds.h-14, 0), node.text_run.height)}
				append(&node.paint, Display_Command{node.id, .Text, label_bounds, rect_intersection(node.clip, label_bounds), owned(display_text, rt.persistent_allocator), text_color, []Text_Paint_Span{}})
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
					Display_Command{node.id, .Button, track, node.clip, "", track_color, []Text_Paint_Span{}},
					Display_Command{node.id, .Button, Rect{track_x, track_y-2, maxf(thumb_x-track_x, 0), 4}, node.clip, "", fill_color, []Text_Paint_Span{}},
					Display_Command{node.id, .Button, Rect{thumb_x-5, track_y-6, 10, 12}, node.clip, "", thumb_color, []Text_Paint_Span{}},
				)
				if rt.focused == node.id && !node.disabled {
					append_focus_outline(node, Color{0.76, 0.86, 1.0, 1}, 1.5)
				}
			} else if node.kind == .Split_Handle {
				handle_color := Color{0.20, 0.24, 0.31, 1}
				if node.hovered { handle_color = Color{0.35, 0.53, 0.72, 1} }
				if node.pressed { handle_color = Color{0.42, 0.66, 0.90, 1} }
				append(&node.paint, Display_Command{node.id, .Split_Handle, node.bounds, node.clip, "", handle_color, []Text_Paint_Span{}})
			} else {
				text_clip := node.clip
				if node.text_style.overflow != .Wrap {
					text_clip = rect_intersection(node.clip, node.bounds)
				}
				paint_geometry := Text_Paint_Geometry{}
				if node.kind == .Text && node.text_run_valid && text_paint_geometry_needed(node) {
					paint_geometry = text_paint_geometry_make(&node.text_run, rt.scratch_allocator)
				}
				append_text_paint_geometry(node, &paint_geometry, text_clip, true)
				if node.kind == .Text && node.text_interaction && node.text_run_valid {
					selection := text_run_selection_rects(
						&node.text_run,
						node.text_interaction_anchor,
						node.text_interaction_focus,
						allocator=rt.scratch_allocator,
						scratch_allocator=rt.scratch_allocator,
					)
					for selected in selection {
						bounds := selected.rect
						bounds.x += node.bounds.x
						bounds.y += node.bounds.y
						append(&node.paint, Display_Command{
							node.id, .Text_Selection, bounds, text_clip, "",
							Color{0.20, 0.42, 0.78, 0.45}, []Text_Paint_Span{},
						})
					}
					delete(selection)
				}
				append(&node.paint, Display_Command{node.id, display_kind, node.bounds, text_clip, owned(display_text, rt.persistent_allocator), node.color, node.text_paint_spans[:]})
				append_text_paint_geometry(node, &paint_geometry, text_clip, false)
				text_paint_geometry_destroy(&paint_geometry)
			}
			if node.kind == .Text && node.text_interaction && node.text_interaction_show_caret && node.text_run_valid {
				caret := text_node_caret_geometry(rt, node.id, node.text_interaction_focus)
				if caret.valid {
					append(&node.paint, Display_Command{
						// A caret belongs to a text boundary, which can sit just
						// beyond the glyph extent (including at byte 0 of an
						// empty run). Keep it clipped by the containing viewport,
						// not by the text node's glyph-sized bounds.
						node.id, .Text_Caret, caret.rect, node.clip, "",
						Color{0.92, 0.95, 1.0, 1.0}, []Text_Paint_Span{},
					})
				}
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
						Color{0.92, 0.95, 1.0, 1.0}, []Text_Paint_Span{},
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
