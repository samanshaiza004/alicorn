package alicorn

import "core:testing"

LAYOUT_ALLOCATION_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

layout_allocation_test_describe :: proc(
	rt: ^Runtime,
	grow_weight: f32,
) -> (row, fixed, grow_limited, nested_column, grow_tail, nested_fixed, nested_grow: Node_ID) {
	invalidate_root(rt, "layout allocation integration fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, label="allocation-root", key=key_string("allocation-root"), style=layout_style(.Column))
	row = container_begin(
		&ui, .Container, label="allocation-row", key=key_string("allocation-row"),
		style=layout_style(.Row, height=80, padding=5, gap=3),
	)
	fixed = text(&ui, "fixed", key=key_string("allocation-fixed"), style=layout_style(.Row, width=50, height=20))
	grow_limited = text(
		&ui, "grow limited", key=key_string("allocation-grow-limited"),
		style=layout_style(.Row, min_width=20, max_width=80, height=20, grow=grow_weight),
	)
	nested_column = container_begin(
		&ui, .Container, label="allocation-nested-column", key=key_string("allocation-nested-column"),
		style=layout_style(.Column, min_width=30, max_width=200, grow=2, padding=2, gap=2, clip=true),
	)
	nested_fixed = text(&ui, "nested fixed", key=key_string("allocation-nested-fixed"), style=layout_style(.Column, height=16))
	nested_grow = text(
		&ui, "nested grow", key=key_string("allocation-nested-grow"),
		style=layout_style(.Column, min_height=12, max_height=36, grow=1),
	)
	container_end(&ui)
	grow_tail = text(
		&ui, "grow tail", key=key_string("allocation-grow-tail"),
		style=layout_style(.Row, min_width=10, grow=1),
	)
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

layout_allocation_test_geometry_matches :: proc(a, b: ^Runtime) -> bool {
	if len(a.order) != len(b.order) { return false }
	for index in 0..<len(a.order) {
		a_id, b_id := a.order[index], b.order[index]
		a_node, a_ok := a.nodes[a_id]
		b_node, b_ok := b.nodes[b_id]
		if !a_ok || !b_ok || a_node.kind != b_node.kind || a_node.identity_key != b_node.identity_key || a_node.bounds != b_node.bounds {
			return false
		}
		a_geometry, a_geometry_ok := a.finalized_geometry[a_id]
		b_geometry, b_geometry_ok := b.finalized_geometry[b_id]
		if !a_geometry_ok || !b_geometry_ok || a_geometry.bounds != b_geometry.bounds || a_geometry.clip != b_geometry.clip {
			return false
		}
		a_measure, a_measure_ok := a.measure_states[a_id]
		b_measure, b_measure_ok := b.measure_states[b_id]
		if a_measure_ok != b_measure_ok { return false }
		if a_measure_ok && (a_measure.result != b_measure.result || a_measure.cache_key.constraints != b_measure.cache_key.constraints) {
			return false
		}
	}
	return true
}

@(test)
test_row_column_main_axis_uses_measured_fixed_sizes_and_weighted_growth :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 140})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, LAYOUT_ALLOCATION_TEST_FONT) {
		testing.expect(t, false, "layout fixture font should load")
		return
	}
	row, fixed, grow_limited, nested_column, grow_tail, nested_fixed, nested_grow := layout_allocation_test_describe(&rt, 1)
	if row == 0 || fixed == 0 || grow_limited == 0 || nested_column == 0 || grow_tail == 0 || nested_fixed == 0 || nested_grow == 0 {
		testing.expect(t, false, "nested Row/Column allocation fixture should retain all keyed nodes")
		return
	}
	row_node := rt.nodes[row]
	fixed_node := rt.nodes[fixed]
	limited_node := rt.nodes[grow_limited]
	nested_node := rt.nodes[nested_column]
	tail_node := rt.nodes[grow_tail]
	nested_fixed_node := rt.nodes[nested_fixed]
	nested_grow_node := rt.nodes[nested_grow]
	allocated: [4]f32
	shape_calls_before := rt.text_engine.shape_calls
	_ = resolve_main_sizes(&rt, row_node.children[:], .Row, layout_unit_extent(301), allocated[:])
	testing.expect(t, rt.text_engine.shape_calls == shape_calls_before,
		"the allocator should consume retained measurement results without initiating text shaping")
	testing.expect(t, fixed_node.bounds.w == 50 && limited_node.bounds.w == 67.75 && nested_node.bounds.w == 125.5 && tail_node.bounds.w == 57.75,
		"Row should preserve fixed/natural sizes and distribute surplus by grow weight in stable unit shares")
	testing.expect(t, nested_fixed_node.bounds.h == 16 && nested_grow_node.bounds.h == 36,
		"nested Column should apply the same allocator while respecting a child maximum")
	testing.expect(t, fixed_node.bounds.x < limited_node.bounds.x && limited_node.bounds.x < nested_node.bounds.x && nested_node.bounds.x < tail_node.bounds.x,
		"main-axis placement should retain logical child order and existing gaps")

	// Non-growing text used to pass through resolved_main_size(), so its
	// measured extent must still honor the main-axis min/max style bounds.
	fixed_node.style.min_width = 60
	rt.nodes[fixed] = fixed_node
	clamped_sizes: [4]f32
	_ = resolve_main_sizes(&rt, row_node.children[:], .Row, layout_unit_extent(301), clamped_sizes[:])
	testing.expect(t, clamped_sizes[0] == 60,
		"fixed text children should retain the existing min/max clamp after measurement is routed through the allocator")
}

@(test)
test_retained_row_column_reallocation_matches_clean_fractional_dpi_layout :: proc(t: ^testing.T) {
	incremental := new_runtime(Rect{0, 0, 320, 140})
	defer destroy_runtime(&incremental)
	if !text_engine_load_font(&incremental.text_engine, LAYOUT_ALLOCATION_TEST_FONT) {
		testing.expect(t, false, "incremental fixture font should load")
		return
	}
	incremental.presentation_scale_x = 1.25
	incremental.presentation_scale_y = 1.25
	_, _, _, _, _, _, _ = layout_allocation_test_describe(&incremental, 1)
	layout_visits_before := incremental.stats.layout_nodes_visited
	shape_requests_before := incremental.stats.text_shape_requests
	incremental.viewport = Rect{0, 0, 257.333, 140}
	_, _, _, _, _, _, _ = layout_allocation_test_describe(&incremental, 1.5)
	if incremental.stats.layout_nodes_visited <= layout_visits_before {
		testing.expect(t, false, "changed viewport and grow weight should reallocate retained Row/Column geometry")
		return
	}
	testing.expect(t, incremental.stats.text_shape_requests >= shape_requests_before,
		"reallocation may reuse or reshape retained text, but it must keep shaping in the measure stage")

	cold := new_runtime(Rect{0, 0, 257.333, 140})
	defer destroy_runtime(&cold)
	if !text_engine_load_font(&cold.text_engine, LAYOUT_ALLOCATION_TEST_FONT) {
		testing.expect(t, false, "cold fixture font should load")
		return
	}
	cold.presentation_scale_x = 1.25
	cold.presentation_scale_y = 1.25
	_, _, _, _, _, _, _ = layout_allocation_test_describe(&cold, 1.5)
	testing.expect(t, layout_allocation_test_geometry_matches(&incremental, &cold),
		"incremental retained reallocation must match a clean solve for target/finalized geometry and measured results")

	old_target := incremental.nodes[incremental.order[1]].bounds
	old_measure_requests := incremental.stats.measure_requests
	old_layout_visits := incremental.stats.layout_nodes_visited
	_ = set_presentation_scale(&incremental, 1.5, 1.25)
	testing.expect(t, incremental.nodes[incremental.order[1]].bounds == old_target &&
		incremental.stats.measure_requests == old_measure_requests && incremental.stats.layout_nodes_visited == old_layout_visits,
		"fractional DPI changes should refinalize shared edges without remeasuring or reallocating logical layout")
}
