package alicorn

import "core:testing"
import "core:math"
import "core:strings"

LAYOUT_GRID_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
LAYOUT_GRID_TEST_MONO_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")

layout_grid_test_near :: proc(a, b: f32) -> bool { return math.abs(a-b) <= 0.03 }

layout_grid_test_describe_resize :: proc(rt: ^Runtime, width, height: f32) -> (grid_id, wrapped_id: Node_ID) {
	invalidate_root(rt, "Grid incremental resize fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("grid-resize-root"), style=layout_style(.Column, width=width, height=height))
	columns := [2]Grid_Track{grid_fixed(82), grid_fraction(1)}
	rows := [2]Grid_Track{grid_auto(), grid_min_max(24, 80)}
	grid_id = grid_begin(&ui, key_string("grid-resize"), columns[:], rows[:], style=layout_style(width=width, height=height), gap_x=7, gap_y=6)
	label := text(&ui, "Message", key=key_string("grid-resize-label"))
	_ = grid_cell(&ui, label, 0, 0, align_y=.Baseline)
	wrapped_id = text(&ui, "A long message wraps as the available fraction column changes during a retained resize.", key=key_string("grid-resize-wrapped"))
	_ = grid_cell(&ui, wrapped_id, 0, 1, align_y=.Baseline)
	status := text(&ui, "Ready", key=key_string("grid-resize-status"))
	_ = grid_cell(&ui, status, 1, 0, align_y=.Baseline)
	value := text(&ui, "unchanged", key=key_string("grid-resize-value"))
	_ = grid_cell(&ui, value, 1, 1, align_y=.Baseline)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

layout_grid_test_describe_randomized :: proc(
	rt: ^Runtime,
	width, height, fraction_weight, second_column_max, second_row_max, gap_x, gap_y: f32,
	message_variant: u64,
	reverse_emission, rtl: bool,
) {
	invalidate_root(rt, "randomized retained Grid fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	direction := Writing_Direction(.Left_To_Right)
	if rtl { direction = .Right_To_Left }
	container_begin(&ui, .Root, key=key_string("random-grid-root"), style=layout_style(.Column, width=width, height=height))
	columns := [2]Grid_Track{grid_min_max(42, second_column_max), grid_fraction(fraction_weight)}
	rows := [2]Grid_Track{grid_auto(), grid_min_max(18, second_row_max)}
	grid_begin(&ui, key_string("random-grid"), columns[:], rows[:], style=layout_style(width=width, height=height, writing_direction=direction), gap_x=gap_x, gap_y=gap_y)
	labels := [4]string{
		"Author",
		"Alice Chen",
		"Message",
		"A retained Grid measures this wrapped commit description after resolving its final column width.",
	}
	if message_variant % 3 == 1 { labels[1] = "Mikaël"; labels[3] = "Refine layout." }
	if message_variant % 3 == 2 { labels[1] = "李明"; labels[3] = "Grid width changes should produce deterministic line wrapping and row heights." }
	keys := [4]string{"random-author-label", "random-author-value", "random-message-label", "random-message-value"}
	items: [4]Node_ID
	if reverse_emission {
		for offset in 0..<len(items) {
			index := len(items)-1-offset
			items[index] = text(&ui, labels[index], key=key_string(keys[index]))
		}
	} else {
		for index in 0..<len(items) { items[index] = text(&ui, labels[index], key=key_string(keys[index])) }
	}
	for index in 0..<len(items) {
		row, column := index/2, index%2
		_ = grid_cell(&ui, items[index], row, column, align_y=.Baseline)
	}
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
}

layout_grid_test_describe_locality :: proc(rt: ^Runtime, message: string) -> (grid, cell, sidebar: Node_ID) {
	invalidate_root(rt, "Grid locality fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("grid-locality-root"), style=layout_style(.Row, width=520, height=220, gap=12))
	columns := [1]Grid_Track{grid_fraction(1)}
	rows := [1]Grid_Track{grid_auto()}
	grid = grid_begin(&ui, key_string("grid-locality-grid"), columns[:], rows[:], style=layout_style(width=320, height=200), layout_boundary=true)
	cell = text(&ui, message, key=key_string("grid-locality-cell"), text_style=Text_Style{overflow=.Wrap})
	_ = grid_cell(&ui, cell, 0, 0)
	grid_end(&ui)
	sidebar = text(&ui, "Unchanged sibling", key=key_string("grid-locality-sidebar"), style=layout_style(width=180, height=40))
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_grid_fixed_auto_fraction_and_minmax_tracks :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 300, 120})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_GRID_TEST_FONT), "Grid fixture font should load")
	invalidate_root(&rt, "Grid mixed track fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "Grid fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("grid-root"), style=layout_style(.Column, width=300, height=120))
	columns := [3]Grid_Track{grid_fixed(50), grid_auto(), grid_fraction(1)}
	rows := [1]Grid_Track{grid_auto()}
	grid_id := grid_begin(&ui, key_string("mixed-grid"), columns[:], rows[:], style=layout_style(width=300, height=100), gap_x=10)
	first := text(&ui, "Name", key=key_string("fixed-cell"))
	_ = grid_cell(&ui, first, 0, 0)
	second := text(&ui, "A longer value", key=key_string("auto-cell"))
	_ = grid_cell(&ui, second, 0, 1)
	third := text(&ui, "Fraction", key=key_string("fraction-cell"))
	_ = grid_cell(&ui, third, 0, 2)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	a, aok := rt.nodes[first]
	b, bok := rt.nodes[second]
	c, cok := rt.nodes[third]
	grid, gok := rt.nodes[grid_id]
	testing.expect(t, aok && bok && cok && gok, "all explicit Grid cells should be retained")
	if aok && bok && cok && gok {
		testing.expect(t, layout_grid_test_near(a.bounds.w, 50), "Fixed tracks should preserve their declared extent")
		testing.expect(t, b.bounds.w > 50, "Auto tracks should use their measured non-spanning contribution")
		testing.expect(t, c.bounds.w > 0 && c.bounds.x > b.bounds.x, "Fraction tracks should receive remaining width after fixed and auto tracks")
		testing.expect(t, layout_grid_test_near(c.bounds.x+c.bounds.w, 300), "the final fraction track should fill the remaining Grid width")
		testing.expect(t, grid.grid_work_units < 100, "small retained Grid should report bounded track/item work")
	}

	bounded := new_runtime(Rect{0, 0, 200, 80})
	defer destroy_runtime(&bounded)
	invalidate_root(&bounded, "Grid minmax fixture")
	ui, build = begin_frame(&bounded)
	if !build { testing.expect(t, false, "MinMax Grid fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("minmax-root"), style=layout_style(.Column, width=200, height=80))
	bounded_columns := [2]Grid_Track{grid_min_max(60, 80), grid_fraction(1)}
	bounded_rows := [1]Grid_Track{grid_auto()}
	grid_begin(&ui, key_string("minmax-grid"), bounded_columns[:], bounded_rows[:], style=layout_style(width=200, height=80))
	minimum_cell := text(&ui, "Property", key=key_string("minmax-cell"))
	_ = grid_cell(&ui, minimum_cell, 0, 0)
	remaining_cell := text(&ui, "Value", key=key_string("fraction-value"))
	_ = grid_cell(&ui, remaining_cell, 0, 1)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	min_node := bounded.nodes[minimum_cell]
	remaining_node := bounded.nodes[remaining_cell]
	testing.expect(t, min_node.bounds.w >= 60 && min_node.bounds.w <= 80,
		"MinMax should preserve its minimum and never exceed its maximum")
	testing.expect(t, layout_grid_test_near(remaining_node.bounds.x, min_node.bounds.x+min_node.bounds.w),
		"Fraction tracks should begin after the resolved MinMax extent")
}

@(test)
test_grid_resolves_width_before_wrapped_row_height_and_rtl_start :: proc(t: ^testing.T) {
	wrapped := new_runtime(Rect{0, 0, 92, 150})
	defer destroy_runtime(&wrapped)
	testing.expect(t, text_engine_load_font(&wrapped.text_engine, LAYOUT_GRID_TEST_FONT), "Grid fixture font should load")
	invalidate_root(&wrapped, "Grid wrapped text fixture")
	ui, build := begin_frame(&wrapped)
	if !build { testing.expect(t, false, "wrapped Grid fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("wrapped-grid-root"), style=layout_style(.Column, width=92, height=150))
	columns := [1]Grid_Track{grid_fraction(1)}
	rows := [1]Grid_Track{grid_auto()}
	grid_begin(&ui, key_string("wrapped-grid"), columns[:], rows[:], style=layout_style(width=92, height=150))
	wrapped_text := text(&ui, "A narrow Grid column wraps this sentence onto several visual lines.", key=key_string("wrapped-text"))
	_ = grid_cell(&ui, wrapped_text, 0, 0)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	text_node := wrapped.nodes[wrapped_text]
	testing.expect(t, text_node.text_run_valid && len(text_node.text_run.lines) > 1,
		"Grid must resolve column width before shaping wrapped cell text")
	testing.expect(t, text_node.bounds.h > text_node.text_run.lines[0].height,
		"Auto row height should reflect the width-constrained wrapped measurement")

	rtl := new_runtime(Rect{0, 0, 180, 60})
	defer destroy_runtime(&rtl)
	testing.expect(t, text_engine_load_font(&rtl.text_engine, LAYOUT_GRID_TEST_FONT), "Grid fixture font should load")
	invalidate_root(&rtl, "Grid RTL alignment fixture")
	ui, build = begin_frame(&rtl)
	if !build { testing.expect(t, false, "RTL Grid fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("rtl-grid-root"), style=layout_style(.Column, width=180, height=60, writing_direction=.Right_To_Left))
	rtl_columns := [2]Grid_Track{grid_fixed(80), grid_fraction(1)}
	rtl_rows := [1]Grid_Track{grid_auto()}
	grid_begin(&ui, key_string("rtl-grid"), rtl_columns[:], rtl_rows[:], style=layout_style(width=180, height=60))
	start_text := text(&ui, "Start", key=key_string("rtl-start"), style=layout_style(width=30), text_style=Text_Style{font_weight=FONT_WEIGHT_REGULAR})
	_ = grid_cell(&ui, start_text, 0, 0, align_x=.Start)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	start_node := rtl.nodes[start_text]
	first_cell_left := f32(100) // In RTL, logical column zero is the physical rightmost 80-unit track.
	testing.expect(t, layout_grid_test_near(start_node.bounds.x, first_cell_left+50),
		"logical Start alignment should resolve to the physical right under RTL")

	baseline := new_runtime(Rect{0, 0, 360, 100})
	defer destroy_runtime(&baseline)
	_ = text_engine_load_font(&baseline.text_engine, LAYOUT_GRID_TEST_FONT)
	_ = text_engine_load_font_role(&baseline.text_engine, .Monospace, LAYOUT_GRID_TEST_MONO_FONT)
	invalidate_root(&baseline, "Grid mixed-font baseline fixture")
	ui, build = begin_frame(&baseline)
	if !build { testing.expect(t, false, "mixed-font Grid fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("grid-baseline-root"), style=layout_style(.Column, width=360, height=100))
	baseline_columns := [2]Grid_Track{grid_fraction(1), grid_fraction(1)}
	baseline_rows := [1]Grid_Track{grid_auto()}
	grid_begin(&ui, key_string("grid-baseline"), baseline_columns[:], baseline_rows[:], style=layout_style(width=360, height=80))
	ui_text := text(&ui, "Alice Chen", key=key_string("grid-baseline-ui"), font=.UI)
	_ = grid_cell(&ui, ui_text, 0, 0, align_y=.Baseline)
	mono_text := text(&ui, "a82f91c", key=key_string("grid-baseline-mono"), font=.Monospace)
	_ = grid_cell(&ui, mono_text, 0, 1, align_y=.Baseline)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	ui_node, ui_ok := baseline.nodes[ui_text]
	mono_node, mono_ok := baseline.nodes[mono_text]
	ui_measure, ui_measure_ok := baseline.measure_states[ui_text]
	mono_measure, mono_measure_ok := baseline.measure_states[mono_text]
	testing.expect(t, ui_ok && mono_ok && ui_measure_ok && mono_measure_ok &&
		ui_measure.result.baseline_valid && mono_measure.result.baseline_valid,
		"the Grid baseline fixture should retain first-line measurements for UI and monospace text")
	if ui_ok && mono_ok && ui_measure_ok && mono_measure_ok {
		ui_baseline := ui_node.bounds.y+layout_unit_to_f32(ui_measure.result.baseline)
		mono_baseline := mono_node.bounds.y+layout_unit_to_f32(mono_measure.result.baseline)
		testing.expect(t, layout_grid_test_near(ui_baseline, mono_baseline),
			"mixed-font Grid cells should align their measured first baselines")
	}
}

@(test)
test_grid_spanning_item_minimum_respects_track_maxima :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 250, 100}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "Grid spanning minimum fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "spanning minimum fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("grid-span-min-root"), style=layout_style(.Column, width=250, height=100))
	columns := [2]Grid_Track{grid_min_max(20, 100), grid_min_max(20, 60)}
	rows := [1]Grid_Track{grid_auto()}
	grid_id := grid_begin(&ui, key_string("grid-span-min"), columns[:], rows[:], style=layout_style(width=80, height=80))
	child := text(&ui, "x", key=key_string("grid-span-min-child"), style=layout_style(min_width=170))
	_ = grid_cell(&ui, child, 0, 0, column_span=2)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	grid_node := rt.nodes[grid_id]
	child_node := rt.nodes[child]
	work_bound := u64(8*(len(columns)+len(rows)+2))
	testing.expect(t, child_node.bounds.w == 160 && grid_node.bounds.w == 80,
		"a spanning item minimum should preserve track maxima and overflow when its minimum cannot fit")
	testing.expect(t, grid_node.grid_work_units < work_bound,
		"a two-track minimum span should use bounded work")
	span_minimum_diagnostic := false
	for event in rt.trace.events {
		if event.kind == .Layout && strings.contains(event.reason, "span [0,2) minimum=170.000") && strings.contains(event.reason, "unresolved=10.000") {
			span_minimum_diagnostic = true
		}
	}
	testing.expect(t, span_minimum_diagnostic,
		"the bounded span adjustment should leave an inspectable contribution diagnostic")
}

@(test)
test_grid_virtual_list_cell_keeps_realization_bounded :: proc(t: ^testing.T) {
	ROW_COUNT :: 10_000
	rt := new_runtime(Rect{0, 0, 240, 180})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "Grid virtual-list fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "Grid virtual-list fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("grid-virtual-root"), style=layout_style(.Column, width=240, height=180))
	columns := [1]Grid_Track{grid_fraction(1)}
	rows := [1]Grid_Track{grid_fraction(1)}
	grid_begin(&ui, key_string("grid-virtual"), columns[:], rows[:], style=layout_style(width=240, height=180))
	list := virtual_list_begin(&ui, ROW_COUNT, 20, key=key_string("grid-virtual-list"), style=layout_style(.Column, height=80, clip=true))
	for index in list.first..<list.last {
		row := container_begin(&ui, .Virtual_Row, key=key_u64(u64(index+1)), style=layout_style(.Column, height=20))
		container_end(&ui)
		_ = row
	}
	virtual_list_end(&ui, list)
	_ = grid_cell(&ui, list.scroll.id, 0, 0)
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	active_rows := 0
	for _, node in rt.nodes { if node != nil && node.active && node.kind == .Virtual_Row { active_rows += 1 } }
	testing.expect(t, active_rows <= list.last-list.first && active_rows < 16,
		"Grid must not realize offscreen virtual-list items to size or place a cell")
}

@(test)
test_retained_grid_resize_matches_clean_fractional_dpi_layout :: proc(t: ^testing.T) {
	incremental := new_runtime(Rect{0, 0, 360, 220})
	defer destroy_runtime(&incremental)
	if !text_engine_load_font(&incremental.text_engine, LAYOUT_GRID_TEST_FONT) {
		testing.expect(t, false, "incremental Grid fixture font should load")
		return
	}
	incremental.presentation_scale_x = 1.25
	incremental.presentation_scale_y = 1.25
	_, _ = layout_grid_test_describe_resize(&incremental, 360, 220)
	incremental.viewport = Rect{0, 0, 235.375, 174.625}
	_, wrapped_id := layout_grid_test_describe_resize(&incremental, 235.375, 174.625)
	wrapped := incremental.nodes[wrapped_id]
	testing.expect(t, wrapped.text_run_valid && len(wrapped.text_run.lines) > 1,
		"the retained resize should remeasure text after the fraction column narrows")

	cold := new_runtime(Rect{0, 0, 235.375, 174.625})
	defer destroy_runtime(&cold)
	if !text_engine_load_font(&cold.text_engine, LAYOUT_GRID_TEST_FONT) {
		testing.expect(t, false, "clean Grid fixture font should load")
		return
	}
	cold.presentation_scale_x = 1.25
	cold.presentation_scale_y = 1.25
	_, _ = layout_grid_test_describe_resize(&cold, 235.375, 174.625)
	testing.expect(t, layout_allocation_test_geometry_matches(&incremental, &cold),
		"incremental Grid resize should match clean target/finalized bounds and retained measurement products")
}

@(test)
test_randomized_retained_grid_replays_match_clean_layouts :: proc(t: ^testing.T) {
	initial_viewport := Rect{0, 0, 420, 240}
	incremental := new_runtime(initial_viewport)
	defer destroy_runtime(&incremental)
	if !text_engine_load_font(&incremental.text_engine, LAYOUT_GRID_TEST_FONT) {
		testing.expect(t, false, "randomized Grid fixture font should load")
		return
	}
	layout_grid_test_describe_randomized(&incremental, initial_viewport.w, initial_viewport.h, 1, 160, 96, 8, 5, 0, false, false)

	seed: u64 = 0x26A110CA7E
	for iteration in 0..<64 {
		width := f32(180+layout_allocate_next(&seed)%620) + f32(layout_allocate_next(&seed)%1024)/1024
		height := f32(100+layout_allocate_next(&seed)%340) + f32(layout_allocate_next(&seed)%1024)/1024
		fraction_weight := f32(1+layout_allocate_next(&seed)%24)/8
		second_column_max := f32(100+layout_allocate_next(&seed)%300)
		second_row_max := f32(36+layout_allocate_next(&seed)%180)
		gap_x := f32(layout_allocate_next(&seed)%16)
		gap_y := f32(layout_allocate_next(&seed)%12)
		message_variant := layout_allocate_next(&seed)%3
		reverse_emission := iteration%2 != 0
		 rtl := iteration%3 == 0
		scale_x := f32(1+layout_allocate_next(&seed)%4)/2
		scale_y := f32(1+layout_allocate_next(&seed)%4)/2
		viewport := Rect{0, 0, width, height}
		incremental.viewport = viewport
		incremental.presentation_scale_x = scale_x
		incremental.presentation_scale_y = scale_y
		layout_grid_test_describe_randomized(
			&incremental, width, height, fraction_weight, second_column_max, second_row_max,
			gap_x, gap_y, u64(message_variant), reverse_emission, rtl,
		)

		cold := new_runtime(viewport)
		if !text_engine_load_font(&cold.text_engine, LAYOUT_GRID_TEST_FONT) {
			destroy_runtime(&cold)
			testing.expect(t, false, "clean randomized Grid fixture font should load")
			return
		}
		cold.presentation_scale_x = scale_x
		cold.presentation_scale_y = scale_y
		layout_grid_test_describe_randomized(
			&cold, width, height, fraction_weight, second_column_max, second_row_max,
			gap_x, gap_y, u64(message_variant), reverse_emission, rtl,
		)
		matches := layout_allocation_test_geometry_matches(&incremental, &cold)
		if !matches {
			testing.expect(t, false, "randomized retained Grid mutations should equal a clean solve for identical dimensions, tracks, text, ordering, direction, and scale")
			return
		}
		destroy_runtime(&cold)
	}
}

@(test)
test_grid_local_measurement_does_not_relayout_fixed_sibling :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 520, 220})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, LAYOUT_GRID_TEST_FONT) {
		testing.expect(t, false, "Grid locality fixture font should load")
		return
	}
	grid, cell, sidebar := layout_grid_test_describe_locality(&rt, "Short")
	if grid == 0 || cell == 0 || sidebar == 0 {
		testing.expect(t, false, "Grid locality fixture should retain all nodes")
		return
	}
	old_grid_bounds, old_sidebar_bounds := rt.nodes[grid].bounds, rt.nodes[sidebar].bounds
	rt.layout_visit_probe[grid] = 0
	rt.layout_visit_probe[cell] = 0
	rt.layout_visit_probe[sidebar] = 0
	next_grid, next_cell, next_sidebar := layout_grid_test_describe_locality(
		&rt,
		"A changed message in one fixed Grid should rewrap and resize its row without making an unrelated sibling participate in layout.",
	)
	testing.expect(t, next_grid == grid && next_cell == cell && next_sidebar == sidebar,
		"local Grid content changes should preserve retained node identities")
	testing.expect(t, rt.nodes[grid].bounds == old_grid_bounds && rt.nodes[sidebar].bounds == old_sidebar_bounds,
		"a content change inside fixed Grid bounds should leave both parent-assigned geometries stable")
	testing.expect(t, rt.layout_visit_probe[grid] > 0, "the changed Grid should be visited for layout")
	testing.expect(t, rt.layout_visit_probe[cell] > 0, "the changed Grid cell should be visited for layout")
	testing.expect(t, rt.layout_visit_probe[sidebar] == 0, "the unrelated fixed sibling should not be visited for layout")
}

@(test)
test_grid_span_work_scales_with_covered_tracks :: proc(t: ^testing.T) {
	TRACKS :: 128
	ITEMS :: 64
	rt := new_runtime(Rect{0, 0, 1280, 120})
	defer destroy_runtime(&rt)
	columns: [TRACKS]Grid_Track
	for i in 0..<TRACKS { columns[i] = grid_fraction(1) }
	rows := [1]Grid_Track{grid_auto()}
	invalidate_root(&rt, "large Grid span work fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "large Grid fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("large-grid-root"), style=layout_style(.Column, width=1280, height=120))
	grid_id := grid_begin(&ui, key_string("large-grid"), columns[:], rows[:], style=layout_style(width=1280, height=100))
	for item_index in 0..<ITEMS {
		cell := text(&ui, "span", key=key_u64(u64(item_index)))
		_ = grid_cell(&ui, cell, 0, item_index*2, column_span=2)
	}
	grid_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	grid := rt.nodes[grid_id]
	linear_bound := u64(8*(TRACKS+ITEMS+2*ITEMS))
	testing.expect(t, grid.grid_work_units < linear_bound,
		"large Grid work should scale with tracks, items, and total covered span length")
}

@(test)
test_grid_large_span_extents_saturate_without_integer_overflow :: proc(t: ^testing.T) {
	large_sizes := [3]Layout_Unit{
		LAYOUT_ALLOCATOR_UNIT_LIMIT,
		LAYOUT_ALLOCATOR_UNIT_LIMIT,
		LAYOUT_ALLOCATOR_UNIT_LIMIT,
	}
	large_items := [3]Elastic_Item{
		{minimum=LAYOUT_ALLOCATOR_UNIT_LIMIT},
		{minimum=LAYOUT_ALLOCATOR_UNIT_LIMIT},
		{minimum=LAYOUT_ALLOCATOR_UNIT_LIMIT},
	}
	span_extent := grid_span_extent(large_sizes[:], 0, len(large_sizes), LAYOUT_ALLOCATOR_UNIT_LIMIT)
	span_minimum := grid_span_minimum_extent(large_items[:], 0, len(large_items), LAYOUT_ALLOCATOR_UNIT_LIMIT)
	testing.expect(t, span_extent == LAYOUT_ALLOCATOR_UNIT_LIMIT,
		"Grid spanned extent should saturate at the allocator limit")
	testing.expect(t, span_minimum == LAYOUT_ALLOCATOR_UNIT_LIMIT,
		"Grid spanned minimum should saturate at the allocator limit")
}
