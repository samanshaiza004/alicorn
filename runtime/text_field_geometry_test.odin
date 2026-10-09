package alicorn

import "core:testing"

TEXT_FIELD_GEOMETRY_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

text_field_geometry_test_render :: proc(rt: ^Runtime, scale: f32, font_size: f32) -> Node_ID {
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("text-field-geometry-root"), style=layout_style(.Column, grow=1))
	scope := style_environment_push(&ui, Style_Environment{text_scale=scale})
	id := text_field(
		&ui,
		"aé界",
		key=key_string("text-field-geometry-input"),
		style=layout_style(width=200, height=40),
		text_style=Text_Style{font_weight=FONT_WEIGHT_REGULAR, font_size=font_size},
	)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	return id
}

@(test)
test_text_field_content_geometry_matches_paint_input_and_ime_at_fractional_scales :: proc(t: ^testing.T) {
	scales := [3]f32{1, 1.25, 1.5}
	for scale in scales {
		rt := new_runtime(Rect{0, 0, 320, 120})
		rt.presentation_scale_x = scale
		rt.presentation_scale_y = scale
		defer destroy_runtime(&rt)
		if !text_engine_load_font(&rt.text_engine, TEXT_FIELD_GEOMETRY_TEST_FONT) {
			testing.expect(t, false, "the text-field geometry fixture should load its UI font")
			continue
		}
		id := text_field_geometry_test_render(&rt, 1, 18)
		if id == 0 || !rt.nodes[id].text_run_valid {
			testing.expect(t, false, "the fixture should retain a shaped text field")
			continue
		}
		node := rt.nodes[id]
		outer := layout_node_finalized_geometry(&rt, id).bounds
		content := text_field_content_bounds(&rt, node)
		expected_content := layout_finalize_rect(
			Rect{outer.x+10, outer.y, maxf(outer.w-20, 0), outer.h},
			scale,
			scale,
		)
		testing.expect(t, content == expected_content,
			"the recipe inset should define the same DPI-finalized content box for every input geometry consumer")
		testing.expect(t, node.text_run.size == 18 && node.text_run.max_width == 180,
			"an 18-unit field should shape within the outer width minus both ten-unit insets")
		origin := text_field_run_origin(&rt, node, &node.text_run)
		expected_y := content.y+(content.h-node.text_run.height)*0.5
		testing.expect(t, abs(origin.y-expected_y) < 0.01,
			"field text should be vertically centered from the measured Text_Run height")

		_ = set_text_selection(&rt, id, 1, 6)
		caret := text_field_caret_geometry(&rt, id)
		selection := text_field_selection_rects(&rt, id, allocator=context.temp_allocator)
		testing.expect(t, caret.valid && caret.rect.x >= content.x && caret.rect.y >= content.y && caret.rect.y+caret.rect.h <= content.y+content.h+1,
			"caret geometry should use the inset, vertically centered content origin")
		testing.expect(t, len(selection) > 0 && selection[0].rect.x >= content.x,
			"selection rectangles should share the content origin rather than starting at the field border")

		if line_index := text_run_line_for_byte(&node.text_run, Text_Position{6, .Trailing}); line_index >= 0 {
			local_x, x_ok := text_run_position_x(&node.text_run, line_index, Text_Position{6, .Trailing}, rt.scratch_allocator)
			if x_ok {
				position := text_field_hit_test(&rt, id, origin.x+local_x, origin.y+node.text_run.lines[line_index].height*0.5+node.text_run.lines[line_index].y)
				testing.expect(t, position.byte == 6,
					"pointer hit testing should map the UTF-8 text end using the same inset and vertical alignment")
			} else {
				testing.expect(t, false, "the fixture should resolve a UTF-8 caret position for pointer hit testing")
			}
		} else {
			testing.expect(t, false, "the final UTF-8 caret should map to a shaped line")
		}

		_ = focus(&rt, id)
		_ = process_text_editing(&rt, id, "語", 0, 1)
		area, area_ok := text_input_area(&rt, id)
		composition_caret := text_field_caret_geometry(&rt, id)
		testing.expect(t, area_ok && area.rect == content && composition_caret.valid &&
			abs(area.rect.x+area.cursor_x-composition_caret.rect.x) < 0.01,
			"IME candidate bounds and cursor should follow the same content box and composition caret")
	}
}

@(test)
test_text_field_font_size_override_and_accessibility_scale :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, TEXT_FIELD_GEOMETRY_TEST_FONT) {
		testing.expect(t, false, "the text-field font-size fixture should load its UI font")
		return
	}
	id := text_field_geometry_test_render(&rt, 1.5, 18)
	if id == 0 || !rt.nodes[id].text_run_valid {
		testing.expect(t, false, "the font-size fixture should shape its input")
		return
	}
	testing.expect(t, rt.nodes[id].text_run.size == 27,
		"the per-control 18-unit size should multiply by the inherited 150% text scale")
	measure_requests := rt.stats.measure_requests
	invalidate_root(&rt, "text-field font-size override changed")
	updated := text_field_geometry_test_render(&rt, 1.5, 20)
	testing.expect(t, updated == id,
		"changing local input typography should preserve the keyed field identity")
	updated_node := rt.nodes[id]
	testing.expect(t, updated_node.text_run_valid && updated_node.text_run.size == 30,
		"changing local input typography should reshape at the new scaled override")
	testing.expect(t, rt.stats.measure_requests > measure_requests,
		"a local font-size change should invalidate measurement without relying on global text-scale generations")
}
