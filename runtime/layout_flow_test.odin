package alicorn

import "core:testing"
import "core:math"

LAYOUT_FLOW_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

layout_flow_test_describe_row :: proc(
	rt: ^Runtime,
	distribution: Main_Axis_Distribution,
	writing_direction: Writing_Direction = .Inherit,
) -> (row, first, second: Node_ID) {
	invalidate_root(rt, "1D flow distribution fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	row = container_begin(
		&ui,
		.Root,
		key=key_string("flow-distribution-root"),
		style=layout_style(.Row, width=200, height=60, gap=10, justify=distribution, writing_direction=writing_direction),
	)
	first = container_begin(&ui, .Container, key=key_string("flow-distribution-first"), style=layout_style(.Column, width=30, height=20))
	container_end(&ui)
	second = container_begin(&ui, .Container, key=key_string("flow-distribution-second"), style=layout_style(.Column, width=50, height=20))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

layout_flow_test_close :: proc(a, b: f32) -> bool {
	return math.abs(a-b) <= 0.02
}

@(test)
test_row_main_axis_distribution_and_rtl_order :: proc(t: ^testing.T) {
	distributions := [5]Main_Axis_Distribution{
		.Start,
		.Center,
		.End,
		.Space_Between,
		.Space_Around,
	}
	for distribution in distributions {
		rt := new_runtime(Rect{0, 0, 200, 60})
		row_id, first_id, second_id := layout_flow_test_describe_row(&rt, distribution)
		row, row_ok := rt.nodes[row_id]
		first, first_ok := rt.nodes[first_id]
		second, second_ok := rt.nodes[second_id]
		testing.expect(t, row_ok && first_ok && second_ok, "distribution fixture should retain both children")
		if row_ok && first_ok && second_ok {
			first_expected, second_expected := f32(0), f32(40)
			switch distribution {
			case .Start:
			case .Center: first_expected, second_expected = 55, 95
			case .End: first_expected, second_expected = 110, 150
			case .Space_Between: first_expected, second_expected = 0, 150
			case .Space_Around: first_expected, second_expected = 27.5, 122.5
			}
			testing.expect(t, layout_flow_test_close(first.bounds.x-row.bounds.x, first_expected) &&
				layout_flow_test_close(second.bounds.x-row.bounds.x, second_expected),
				"main-axis distribution should resolve free space in stable layout-unit shares")
		}
		destroy_runtime(&rt)
	}

	rt := new_runtime(Rect{0, 0, 200, 60})
	defer destroy_runtime(&rt)
	row_id, first_id, second_id := layout_flow_test_describe_row(&rt, .Start, .Right_To_Left)
	row, _ := rt.nodes[row_id]
	first, _ := rt.nodes[first_id]
	second, _ := rt.nodes[second_id]
	testing.expect(t, layout_flow_test_close(first.bounds.x-row.bounds.x, 170) &&
		layout_flow_test_close(second.bounds.x-row.bounds.x, 110),
		"RTL Row Start should place the first logical child at the physical right and preserve logical sibling order")
}

@(test)
test_main_axis_distribution_remainders_follow_logical_order :: proc(t: ^testing.T) {
	free := Layout_Unit(101)
	between_first := layout_distribution_gap(free, 3, 0, .Space_Between)
	between_second := layout_distribution_gap(free, 3, 1, .Space_Between)
	around_leading := layout_distribution_leading(free, 3, .Space_Around)
	around_first := layout_distribution_gap(free, 3, 0, .Space_Around)
	around_second := layout_distribution_gap(free, 3, 1, .Space_Around)
	testing.expect(t, between_first == 51 && between_second == 50,
		"Space_Between should give an indivisible unit to the earlier logical gap")
	testing.expect(t, around_leading == 17 && around_first == 34 && around_second == 33,
		"Space_Around should distribute odd units in stable logical order")
}

layout_flow_test_describe_compressible_row :: proc(rt: ^Runtime, width, first_width, second_width, first_min, second_min: f32) -> (first, second: Node_ID) {
	invalidate_root(rt, "compressible Row fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("compression-root"), style=layout_style(.Row, width=width, height=60))
	first = container_begin(&ui, .Container, key=key_string("compression-first"), style=layout_style(.Column, width=first_width, min_width=first_min, height=20, compress_weight=1))
	container_end(&ui)
	second = container_begin(&ui, .Container, key=key_string("compression-second"), style=layout_style(.Column, width=second_width, min_width=second_min, height=20, compress_weight=3))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_row_compression_weights_and_hard_minimum_overflow :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 60})
	defer destroy_runtime(&rt)
	first_id, second_id := layout_flow_test_describe_compressible_row(&rt, 200, 120, 120, 40, 40)
	first, first_ok := rt.nodes[first_id]
	second, second_ok := rt.nodes[second_id]
	testing.expect(t, first_ok && second_ok, "compressible children should be retained")
	if first_ok && second_ok {
		testing.expect(t, layout_flow_test_close(first.bounds.w, 110) && layout_flow_test_close(second.bounds.w, 90),
			"compression should shrink natural ideals by their relative weights while preserving hard minima")
	}

	overflow := new_runtime(Rect{0, 0, 100, 60})
	defer destroy_runtime(&overflow)
	first_id, second_id = layout_flow_test_describe_compressible_row(&overflow, 100, 60, 60, 55, 55)
	first, first_ok = overflow.nodes[first_id]
	second, second_ok = overflow.nodes[second_id]
	if first_ok && second_ok {
		testing.expect(t, first.bounds.w == 55 && second.bounds.w == 55 && second.bounds.x == 55,
			"when hard minima exceed the Row, the allocator must preserve them and expose the overflow instead of shrinking below them")
	}
}

@(test)
test_row_baseline_alignment_uses_retained_text_baselines_and_icon_bottom :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 80})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, LAYOUT_FLOW_TEST_FONT) {
		testing.expect(t, false, "baseline fixture font should load")
		return
	}
	invalidate_root(&rt, "baseline row fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "baseline fixture should request a description"); return }
	container_begin(&ui, .Root, key=key_string("baseline-root"), style=layout_style(.Row, width=360, height=80, gap=8, align=.Baseline))
	scope := style_environment_push(&ui, Style_Environment{text_scale=1.5})
	large_id := text(&ui, "Large", key=key_string("baseline-large"), style=layout_style(width=90, height=36))
	style_environment_pop(&ui, scope)
	small_id := text(&ui, "Small", key=key_string("baseline-small"), style=layout_style(width=80, height=24))
	button_id, _ := button_ex(&ui, "Run", key="baseline-button", explicit_key=true, style=layout_style(width=80, height=32))
	icon_id := container_begin(&ui, .Container, key=key_string("baseline-icon"), style=layout_style(.Column, width=20, height=14))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	large, large_ok := rt.nodes[large_id]
	small, small_ok := rt.nodes[small_id]
	button, button_ok := rt.nodes[button_id]
	icon, icon_ok := rt.nodes[icon_id]
	large_measure := rt.measure_states[large_id].result
	small_measure := rt.measure_states[small_id].result
	button_measure := rt.measure_states[button_id].result
	testing.expect(t, large_ok && small_ok && button_ok && icon_ok, "baseline controls and icon should be retained")
	if large_ok && small_ok && button_ok && icon_ok {
		large_baseline := large.bounds.y+layout_unit_to_f32(large_measure.baseline)
		small_baseline := small.bounds.y+layout_unit_to_f32(small_measure.baseline)
		button_baseline := button.bounds.y+layout_unit_to_f32(button_measure.baseline)
		icon_baseline := icon.bounds.y+icon.bounds.h
		testing.expect(t, large_measure.baseline_valid && small_measure.baseline_valid && button_measure.baseline_valid,
			"text and button measurement results should expose their first-line baselines")
		testing.expect(t, layout_flow_test_close(large_baseline, small_baseline) &&
			layout_flow_test_close(large_baseline, button_baseline) && layout_flow_test_close(large_baseline, icon_baseline),
			"mixed-size text, a button label, and an icon bottom should share one Row baseline")
	}
}

layout_flow_test_describe_split :: proc(
	rt: ^Runtime,
	width, initial, first_minimum, second_minimum, first_maximum: f32,
	writing_direction: Writing_Direction = .Inherit,
) -> (split: Split_Handle, first, second: Node_ID) {
	invalidate_root(rt, "elastic Split fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("elastic-split-root"), style=layout_style(.Column, width=width, height=100, writing_direction=writing_direction))
	split = split_begin(&ui, key=key_string("elastic-split"), axis=.Horizontal, initial=initial, min_first=first_minimum, min_second=second_minimum, style=layout_style(.Row, grow=1, clip=true))
	first = split_first_begin(&ui, split, style=layout_style(.Column, grow=1, max_width=first_maximum, clip=true))
	split_first_end(&ui, split)
	split_divider(&ui, split, thickness=2, hit_size=10)
	second = split_second_begin(&ui, split, style=layout_style(.Column, grow=1, clip=true))
	split_second_end(&ui, split)
	split_end(&ui, split)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_split_uses_shared_allocator_for_absolute_position_bounds_and_overflow :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 300, 100})
	defer destroy_runtime(&rt)
	split, first_id, second_id := layout_flow_test_describe_split(&rt, 300, 120, 50, 60, 180)
	first, first_ok := rt.nodes[first_id]
	second, second_ok := rt.nodes[second_id]
	testing.expect(t, first_ok && second_ok, "split panes should be retained")
	if first_ok && second_ok {
		testing.expect(t, first.bounds.w == 120 && second.bounds.w == 178,
			"Split should resolve its preferred first-pane extent through the shared allocator")
	}
	rt.viewport = Rect{0, 0, 600, 100}
	_, _, _ = layout_flow_test_describe_split(&rt, 600, 120, 50, 60, 180)
	first = rt.nodes[first_id]
	second = rt.nodes[second_id]
	testing.expect(t, first.bounds.w == 120 && second.bounds.w == 478,
		"a resized Split should preserve its absolute preferred position while the shared allocator fills the remaining pane")

	overflow := new_runtime(Rect{0, 0, 100, 100})
	defer destroy_runtime(&overflow)
	_, first_id, second_id = layout_flow_test_describe_split(&overflow, 100, 40, 70, 60, -1)
	first = overflow.nodes[first_id]
	second = overflow.nodes[second_id]
	testing.expect(t, first.bounds.w == 70 && second.bounds.w == 60,
		"when pane minima do not fit, Split should preserve both minima and report overflow instead of violating them")
	_ = split

	capped := new_runtime(Rect{0, 0, 300, 100})
	defer destroy_runtime(&capped)
	_, first_id, second_id = layout_flow_test_describe_split(&capped, 300, 250, 50, 60, 180)
	first = capped.nodes[first_id]
	second = capped.nodes[second_id]
	testing.expect(t, first.bounds.w == 180 && second.bounds.w == 118,
		"a Split pane at its maximum should release the remaining share to the other pane")

	rtl := new_runtime(Rect{0, 0, 300, 100})
	defer destroy_runtime(&rtl)
	rtl_split, _, _ := layout_flow_test_describe_split(&rtl, 300, 120, 50, 60, -1, .Right_To_Left)
	owner := rtl.nodes[rtl_split.id]
	handle := rtl.nodes[owner.children[1]]
	owner.split_drag_start_position = owner.split_position
	owner.split_drag_start_coordinate = handle.bounds.x+handle.bounds.w*0.5
	rtl.nodes[owner.id] = owner
	start := owner.split_drag_start_coordinate
	update_split_drag(&rtl, handle, start+20, handle.bounds.y+handle.bounds.h*0.5)
	testing.expect(t, rtl.nodes[owner.id].split_position == 100,
		"dragging a horizontal RTL divider toward the physical right should reduce the first logical pane's extent")
}

@(test)
test_column_compression_uses_weighted_main_axis_allocation :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 80, 200})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "Column compression fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "Column compression fixture should request a description"); return }
	container_begin(&ui, .Root, key=key_string("column-compression-root"), style=layout_style(.Column, width=80, height=200))
	first_id := container_begin(&ui, .Container, key=key_string("column-compression-first"), style=layout_style(.Row, width=30, height=120, min_height=40, compress_weight=1))
	container_end(&ui)
	second_id := container_begin(&ui, .Container, key=key_string("column-compression-second"), style=layout_style(.Row, width=30, height=120, min_height=40, compress_weight=3))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	first, first_ok := rt.nodes[first_id]
	second, second_ok := rt.nodes[second_id]
	testing.expect(t, first_ok && second_ok, "Column compression participants should be retained")
	if first_ok && second_ok {
		testing.expect(t, layout_flow_test_close(first.bounds.h, 110) && layout_flow_test_close(second.bounds.h, 90) && layout_flow_test_close(second.bounds.y-first.bounds.y, 110),
			"Column compression should use weighted measured ideals, preserve minima, and place later children after resized predecessors")
	}
}
