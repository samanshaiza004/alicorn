package alicorn

import "core:testing"
import "core:math"
import "core:strings"

LAYOUT_MEASURE_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
LAYOUT_MEASURE_TEST_MONO_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")

layout_measure_test_describe_text :: proc(rt: ^Runtime, value: string, color: Color, font := Font_Role.UI) -> Node_ID {
	invalidate_root(rt, "layout measure test description")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("layout-measure-test-root"), style=layout_style(.Column, width=240, height=120))
	id := text(&ui, value, key=key_string("layout-measure-test-text"), style=layout_style(width=200, height=40), font=font)
	if len(rt.pending) > 0 { rt.pending[len(rt.pending)-1].description.color = color }
	container_end(&ui)
	end_frame(&ui)
	return id
}

layout_measure_test_describe_scoped_text :: proc(rt: ^Runtime, scale: f32, density: f32 = 1) -> (editor, sidebar: Node_ID) {
	invalidate_root(rt, "layout boundary scale test description")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("measure-boundary-root"), style=layout_style(.Row, width=240, height=120))
	container_begin(&ui, .Container, key=key_string("measure-boundary-editor"), style=layout_style(.Column, width=120, height=120), layout_boundary=true)
	scope := style_environment_push(&ui, Style_Environment{text_scale=scale, density=density})
	editor = text_field(&ui, "A short editor line", key=key_string("measure-boundary-editor-text"), style=layout_style(width=110))
	style_environment_pop(&ui, scope)
	container_end(&ui)
	sidebar = text(&ui, "Sidebar", key=key_string("measure-boundary-sidebar"), style=layout_style(width=120, height=24))
	container_end(&ui)
	end_frame(&ui)
	return
}

layout_measure_test_describe_directional_row :: proc(rt: ^Runtime, direction: Writing_Direction) -> (first, second: Node_ID) {
	invalidate_root(rt, "writing-direction measurement dependency fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("measure-direction-root"), style=layout_style(.Row, width=240, height=120, writing_direction=direction))
	first = text(&ui, "First", key=key_string("measure-direction-first"), style=layout_style(width=60, height=24))
	second = text(&ui, "Second", key=key_string("measure-direction-second"), style=layout_style(width=80, height=24))
	container_end(&ui)
	end_frame(&ui)
	return
}

layout_measure_test_trace_has_reason :: proc(rt: ^Runtime, node: Node_ID, fragment: string) -> bool {
	if rt == nil { return false }
	for event in rt.trace.events {
		if event.kind == .Measure && event.node == node && strings.contains(event.reason, fragment) { return true }
	}
	return false
}

layout_measure_test_describe_controls :: proc(rt: ^Runtime, theme: Style_Theme_ID, density, text_scale: f32) -> (button_id, checkbox_id, slider_id, field_id, explicit_id: Node_ID) {
	invalidate_root(rt, "control metrics fixture description")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("control-metrics-root"), style=layout_style(.Column, width=400, height=320, gap=4))
	scope := style_environment_push(&ui, Style_Environment{theme=theme, density=density, text_scale=text_scale})
	_ = button(&ui, "Button", key=key_string("control-metrics-button"))
	button_id = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	_ = checkbox(&ui, "Checkbox", false, key=key_string("control-metrics-checkbox"))
	checkbox_id = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	_ = slider_f32(&ui, "Slider", 0.5, 0, 1, key=key_string("control-metrics-slider"))
	slider_id = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	field_id = text_field(&ui, "Field", key=key_string("control-metrics-field"))
	_ = button(&ui, "Explicit", key=key_string("control-metrics-explicit"), style=layout_style(.Row, height=18))
	explicit_id = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_theme_control_metrics_invalidate_measurement_without_identity_changes :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 420, 340})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT) {
		testing.expect(t, false, "control metrics fixture font should load")
		return
	}
	button_id, checkbox_id, slider_id, field_id, explicit_id := layout_measure_test_describe_controls(&rt, DEFAULT_STYLE_THEME_ID, 1, 1)
	if button_id == 0 || checkbox_id == 0 || slider_id == 0 || field_id == 0 || explicit_id == 0 {
		testing.expect(t, false, "default controls should be retained")
		return
	}
	base_button_id := button_id
	base_checkbox_id := checkbox_id
	base_slider_id := slider_id
	base_field_id := field_id
	base_explicit_metric_generation := rt.nodes[explicit_id].style_generations.metrics
	base_generations := [4]u32{
		rt.nodes[button_id].style_generations.metrics,
		rt.nodes[checkbox_id].style_generations.metrics,
		rt.nodes[slider_id].style_generations.metrics,
		rt.nodes[field_id].style_generations.metrics,
	}
	base_height := layout_unit_to_f32(rt.measure_states[button_id].result.size.height)
	testing.expect(t, layout_unit_to_f32(rt.measure_states[explicit_id].result.size.height) == 18,
		"explicit control height should override the theme's preferred and minimum target heights")

	metrics_theme := DEFAULT_STYLE_THEME
	metrics_theme.control_metrics.button = Control_Metric{preferred_height=24, minimum_hit_height=24, content_padding_y=4}
	metrics_theme_id := style_theme_register(&rt, metrics_theme)
	if metrics_theme_id == 0 { testing.expect(t, false, "valid control metrics should register"); return }
	button_id, checkbox_id, slider_id, field_id, explicit_id = layout_measure_test_describe_controls(&rt, metrics_theme_id, 1, 1)
	custom_heights := [4]f32{
		layout_unit_to_f32(rt.measure_states[button_id].result.size.height),
		layout_unit_to_f32(rt.measure_states[checkbox_id].result.size.height),
		layout_unit_to_f32(rt.measure_states[slider_id].result.size.height),
		layout_unit_to_f32(rt.measure_states[field_id].result.size.height),
	}
	expected_preferred := [4]f32{24, 32, 44, 32}
	for height, index in custom_heights {
		testing.expect(t, height >= expected_preferred[index], "theme control preferences should affect intrinsic geometry")
	}
	testing.expect(t, button_id == base_button_id && checkbox_id == base_checkbox_id && slider_id == base_slider_id && field_id == base_field_id,
		"changing theme metrics must preserve retained control identity")
	testing.expect(t, rt.nodes[button_id].style_generations.metrics > base_generations[0],
		"the changed Button metric should advance its measurement dependency")
	testing.expect(t, rt.nodes[checkbox_id].style_generations.metrics == base_generations[1] &&
		rt.nodes[slider_id].style_generations.metrics == base_generations[2] &&
		rt.nodes[field_id].style_generations.metrics == base_generations[3],
		"a Button-only metric change must not invalidate other controls")
	testing.expect(t, layout_unit_to_f32(rt.measure_states[explicit_id].result.size.height) == 18,
		"explicit dimensions should remain authoritative under a theme metric and density change")
	testing.expect(t, rt.nodes[explicit_id].style_generations.metrics == base_explicit_metric_generation,
		"an explicit control height must not depend on or invalidate for the theme's preferred height")
	testing.expect(t, layout_unit_to_f32(rt.measure_states[button_id].result.size.height) < base_height,
		"a compact theme should be able to lower the preferred button height")

	button_id, checkbox_id, slider_id, field_id, explicit_id = layout_measure_test_describe_controls(&rt, metrics_theme_id, 1.5, 1)
	testing.expect(t, layout_unit_to_f32(rt.measure_states[button_id].result.size.height) >= 36 &&
		layout_unit_to_f32(rt.measure_states[checkbox_id].result.size.height) >= 48 &&
		layout_unit_to_f32(rt.measure_states[slider_id].result.size.height) >= 66 &&
		layout_unit_to_f32(rt.measure_states[field_id].result.size.height) >= 48,
		"density should scale theme control geometry once across control families")

	before_text_scale := layout_unit_to_f32(rt.measure_states[button_id].result.size.height)
	executed_before_text_scale := rt.stats.measure_nodes_executed
	button_id, checkbox_id, slider_id, field_id, explicit_id = layout_measure_test_describe_controls(&rt, metrics_theme_id, 1, 2)
	testing.expect(t, rt.stats.measure_nodes_executed > executed_before_text_scale,
		"text scale should invalidate and remeasure controls that depend on shaped text")
	testing.expect(t, layout_unit_to_f32(rt.measure_states[button_id].result.size.height) > before_text_scale,
		"large text should expand a control beyond its theme preferred height when needed")

	paint_theme := metrics_theme
	paint_theme.colors[int(Style_Color_Role.Surface)] = Color{0.3, 0.2, 0.1, 1}
	paint_theme_id := style_theme_register(&rt, paint_theme)
	if paint_theme_id == 0 { testing.expect(t, false, "paint-only control theme should register"); return }
	metrics_before_paint_change := rt.stats.measure_nodes_executed
	button_id, checkbox_id, slider_id, field_id, explicit_id = layout_measure_test_describe_controls(&rt, paint_theme_id, 1, 2)
	testing.expect(t, rt.stats.measure_nodes_executed == metrics_before_paint_change,
		"palette-only theme changes must not invalidate control measurements")
}

@(test)
test_theme_control_minimum_survives_compression_with_explicit_overrides :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 160, 16})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "theme control minimum fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "control minimum fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("control-minimum-root"), style=layout_style(.Column, width=160, height=16))
	_ = button(&ui, "Target", key=key_string("control-minimum-default"))
	default_id := ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	_ = button(&ui, "Capped", key=key_string("control-minimum-capped"), style=layout_style(.Row, max_height=20))
	capped_id := ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	_ = button(&ui, "Explicit", key=key_string("control-minimum-explicit"), style=layout_style(.Row, height=18))
	explicit_id := ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	container_end(&ui)
	end_frame(&ui)
	testing.expect(t, default_id != 0 && capped_id != 0 && explicit_id != 0, "control targets should be retained")
	testing.expect(t, rt.nodes[default_id].bounds.h == 32,
		"the theme minimum target must survive compression by a too-short Column")
	testing.expect(t, rt.nodes[capped_id].bounds.h == 20,
		"an explicit maximum may cap the implicit theme target")
	testing.expect(t, rt.nodes[explicit_id].bounds.h == 18,
		"an explicit height must override the theme target minimum")
}

@(test)
test_measure_cache_miss_with_equal_result_does_not_relayout_ancestors :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "measurement fixture font should load")
	black := Color{0.1, 0.1, 0.1, 1}
	first_id := layout_measure_test_describe_text(&rt, "cat", black)
	if first_id == 0 { testing.expect(t, false, "first text fixture should be retained"); return }
	first_measure := rt.measure_states[first_id]
	first_layout_visits := rt.stats.layout_nodes_visited
	first_shape_requests := rt.stats.text_shape_requests
	first_misses := rt.stats.measure_cache_misses
	first_examined := rt.stats.measure_nodes_examined
	first_executed := rt.stats.measure_nodes_executed

	second_id := layout_measure_test_describe_text(&rt, "dog", black)
	second_measure := rt.measure_states[second_id]
	testing.expect(t, second_id == first_id && second_measure.input_revision > first_measure.input_revision,
		"text changes should advance the reconciliation-derived local measurement revision")
	testing.expect(t, rt.stats.measure_cache_misses > first_misses && rt.stats.text_shape_requests > first_shape_requests,
		"a changed input fingerprint should miss measurement and reshape its text product")
	testing.expect(t, rt.stats.measure_nodes_examined == first_examined+1 &&
		rt.stats.measure_nodes_executed == first_executed+1,
		"a text edit should schedule and execute only the changed text measurement")
	testing.expect(t, layout_measure_result_equal(first_measure.result, second_measure.result),
		"equal fixed-size text should produce the same retained measure result despite different content")
	testing.expect(t, rt.stats.layout_nodes_visited == first_layout_visits,
		"a measurement miss with an unchanged result must not invalidate parent placement")

	measures_before_color := rt.stats.measure_requests
	layout_before_color := rt.stats.layout_nodes_visited
	_ = layout_measure_test_describe_text(&rt, "dog", Color{0.8, 0.2, 0.1, 1})
	testing.expect(t, rt.stats.measure_requests == measures_before_color && rt.stats.layout_nodes_visited == layout_before_color,
		"paint-only color changes must not request measurement or layout")
}

@(test)
test_measure_work_queue_deduplicates_and_font_generation_remains_broad :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "measurement fixture font should load")
	id := layout_measure_test_describe_text(&rt, "stable", Color{0.1, 0.1, 0.1, 1})
	if id == 0 { testing.expect(t, false, "font-generation fixture text should be retained"); return }

	node := rt.nodes[id]
	before_examined := rt.stats.measure_nodes_examined
	layout_measure_mark_dirty(&rt, node)
	layout_measure_mark_dirty(&rt, node)
	layout_measure_retained_dirty_nodes(&rt)
	testing.expect(t, rt.stats.measure_nodes_examined == before_examined+1 &&
		!dirty_has(node.dirty, .Measure) && len(rt.measure_queue) == 0,
		"repeated invalidation of one node should occupy one queue entry and settle once")

	before_generation := rt.text_engine.font_generation
	before_work := rt.stats.global_work_by_reason[.Measure_Font_Generation]
	before_examined = rt.stats.measure_nodes_examined
	before_executed := rt.stats.measure_nodes_executed
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_MONO_FONT),
		"a second font face should load for broad-generation invalidation")
	if rt.text_engine.font_generation == before_generation {
		testing.expect(t, false, "loading a new face should advance the font generation")
		return
	}
	_ = layout_measure_test_describe_text(&rt, "stable", Color{0.1, 0.1, 0.1, 1})
	testing.expect(t, rt.stats.global_work_by_reason[.Measure_Font_Generation] == before_work+1 &&
		rt.stats.measure_nodes_examined-before_examined == u64(len(rt.order)+1) &&
		rt.stats.measure_nodes_executed > before_executed,
		"font changes should explicitly scan retained nodes, then execute affected text measurements")
}

@(test)
test_measure_dirty_without_valid_constraints_waits_for_layout :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)

	node := new(Node, allocator=rt.persistent_allocator)
	node.id = 7004
	node.kind = .Text
	node.active = true
	rt.nodes[node.id] = node
	rt.measure_states[node.id] = Measure_State{input_revision=1}

	layout_measure_mark_dirty(&rt, node)
	state := rt.measure_states[node.id]
	testing.expect(t, dirty_has(node.dirty, .Measure) && !node.measure_queued && len(rt.measure_queue) == 0,
		"a node without a prior constraint key must remain dirty without an unprocessable queue entry")

	state.cache_key.valid = true
	rt.measure_states[node.id] = state
	layout_measure_mark_dirty(&rt, node)
	testing.expect(t, dirty_has(node.dirty, .Measure) && node.measure_queued && len(rt.measure_queue) == 1,
		"once layout has supplied constraints, later invalidation must enter the retained measurement queue")
}

@(test)
test_constraint_change_with_equal_result_stays_local_and_results_honor_exact_bounds :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 120})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "constraint fixture font should load")
	parent := new(Node, allocator=rt.persistent_allocator)
	parent.id = 7002
	parent.kind = .Container
	parent.style.direction = .Row
	parent.active = true
	rt.nodes[parent.id] = parent
	node := new(Node, allocator=rt.persistent_allocator)
	node.id = 7003
	node.parent = parent.id
	node.kind = .Text
	node.text = owned("hello", rt.persistent_allocator)
	node.text_style.overflow = .Clip
	node.active = true
	rt.nodes[node.id] = node
	rt.measure_states[node.id] = Measure_State{input_revision=1}

	constraints_510 := Layout_Constraints{
		width=layout_axis_constraint_normalize(0, 510),
		height=layout_axis_constraint_normalize(0, -1),
	}
	first := layout_measure_node(&rt, node, constraints_510)
	misses_before := rt.stats.measure_cache_misses
	layout_visits_before := rt.stats.layout_nodes_visited
	constraints_509 := constraints_510
	constraints_509.width = layout_axis_constraint_normalize(0, 509)
	second := layout_measure_node(&rt, node, constraints_509)
	testing.expect(t, rt.stats.measure_cache_misses == misses_before+1,
		"a changed normalized incoming width must miss the exact measurement cache")
	testing.expect(t, layout_measure_result_equal(first, second),
		"a non-wrapping short label should retain the same measured output under widths 510 and 509")
	testing.expect(t, !rt.layout_pending && rt.stats.layout_nodes_visited == layout_visits_before,
		"a constraint cache miss with identical output must not propagate placement or ancestor layout")

	exact := Layout_Constraints{
		width=layout_axis_constraint_normalize(180, 180),
		height=layout_axis_constraint_normalize(40, 40),
	}
	exact_result := layout_measure_node(&rt, node, exact)
	testing.expect(t, exact_result.size.width == layout_unit_extent(180) && exact_result.size.height == layout_unit_extent(40),
		"the retained measure result must honor exact parent-provided width and height constraints")
}

@(test)
test_scoped_text_measure_reflows_inside_explicit_layout_boundary :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "measurement fixture font should load")
	editor, sidebar := layout_measure_test_describe_scoped_text(&rt, 1)
	if editor == 0 || sidebar == 0 { testing.expect(t, false, "scoped editor and sidebar should be retained"); return }
	rt.layout_visit_probe[editor] = 0
	rt.layout_visit_probe[sidebar] = 0
	old_revision := rt.measure_states[editor].input_revision
	old_height := rt.measure_states[editor].result.size.height
	old_shape_requests := rt.stats.text_shape_requests

	next_editor, next_sidebar := layout_measure_test_describe_scoped_text(&rt, 1.5)
	testing.expect(t, next_editor == editor && next_sidebar == sidebar, "the scale update should preserve retained node identities")
	testing.expect(t, rt.measure_states[editor].input_revision == old_revision,
		"external typography generation changes should invalidate dependencies without changing local input revision")
	testing.expect(t, rt.measure_states[editor].result.size.height > old_height && rt.stats.text_shape_requests > old_shape_requests,
		"text scale should reshape and change the editor's measured height")
	testing.expect(t, rt.layout_visit_probe[editor] > 0 && rt.layout_visit_probe[sidebar] == 0,
		"the editor layout boundary should contain the reflow and leave its sibling unvisited")
	testing.expect(t, layout_measure_test_trace_has_reason(&rt, editor, "metrics and typography dependency generations changed"),
		"the inspector measurement trace should name both metric and typography dependencies changed by text scale")
}

@(test)
test_density_change_invalidates_only_scoped_measurement_and_explains_metrics_dependency :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "density fixture font should load")
	editor, sidebar := layout_measure_test_describe_scoped_text(&rt, 1, 1)
	if editor == 0 || sidebar == 0 { testing.expect(t, false, "density fixture should retain its scoped editor and sibling"); return }
	old_revision := rt.measure_states[editor].input_revision
	old_width := rt.nodes[editor].text_run.max_width
	misses_before := rt.stats.measure_cache_misses
	shape_before := rt.stats.text_shape_requests
	sidebar_dependencies := rt.measure_states[sidebar].cache_key.dependencies

	next_editor, next_sidebar := layout_measure_test_describe_scoped_text(&rt, 1, 1.5)
	testing.expect(t, next_editor == editor && next_sidebar == sidebar, "density change should retain identities")
	testing.expect(t, rt.measure_states[editor].input_revision == old_revision,
		"density changes should use the typed metrics generation rather than masquerading as local text changes")
	testing.expect(t, rt.stats.measure_cache_misses == misses_before+1 && rt.stats.text_shape_requests > shape_before &&
		rt.nodes[editor].text_run.max_width != old_width,
		"density should remeasure the text field using its updated logical content inset")
	testing.expect(t, rt.measure_states[sidebar].cache_key.dependencies == sidebar_dependencies,
		"density changes should leave the unaffected sibling's measurement dependencies unchanged")
	testing.expect(t, layout_measure_test_trace_has_reason(&rt, editor, "metrics dependency generation changed"),
		"the inspector measurement trace should identify the metrics dependency")
}

@(test)
test_font_generation_invalidates_retained_text_and_explains_font_dependency :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font_role(&rt.text_engine, .Monospace, LAYOUT_MEASURE_TEST_MONO_FONT),
		"monospace fixture font should load")
	black := Color{0.1, 0.1, 0.1, 1}
	id := layout_measure_test_describe_text(&rt, "iii WWW", black, .Monospace)
	if id == 0 { testing.expect(t, false, "font fixture text should be retained"); return }
	old_revision := rt.measure_states[id].input_revision
	misses_before := rt.stats.measure_cache_misses
	shape_before := rt.stats.text_shape_requests
	old_font_generation := rt.text_engine.font_generation

	testing.expect(t, text_engine_load_font_role(&rt.text_engine, .Monospace, LAYOUT_MEASURE_TEST_FONT),
		"replacement font fixture should load")
	_ = layout_measure_test_describe_text(&rt, "iii WWW", black, .Monospace)
	testing.expect(t, rt.text_engine.font_generation > old_font_generation && rt.measure_states[id].input_revision == old_revision,
		"font resource changes should advance the Runtime dependency without changing application text input")
	testing.expect(t, rt.stats.measure_cache_misses == misses_before+1 && rt.stats.text_shape_requests > shape_before,
		"a font generation change should invalidate and reshape the retained text measurement")
	testing.expect(t, layout_measure_test_trace_has_reason(&rt, id, "font dependency generation changed"),
		"the inspector measurement trace should identify the font dependency")
}

@(test)
test_writing_direction_changes_placement_without_invalidating_intrinsic_measurement :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "direction fixture font should load")
	first, second := layout_measure_test_describe_directional_row(&rt, .Left_To_Right)
	if first == 0 || second == 0 { testing.expect(t, false, "direction fixture should retain both text nodes"); return }
	misses_before := rt.stats.measure_cache_misses
	shapes_before := rt.stats.text_shape_requests
	ltr_first := rt.nodes[first].bounds.x
	ltr_second := rt.nodes[second].bounds.x

	next_first, next_second := layout_measure_test_describe_directional_row(&rt, .Right_To_Left)
	testing.expect(t, next_first == first && next_second == second, "direction change should preserve retained text identities")
	testing.expect(t, rt.nodes[first].bounds.x > rt.nodes[second].bounds.x && ltr_first < ltr_second,
		"writing direction should reverse physical placement while preserving logical child identity")
	testing.expect(t, rt.stats.measure_cache_misses == misses_before && rt.stats.text_shape_requests == shapes_before,
		"writing direction changes placement only and must not invalidate intrinsic text measurement")
}

layout_measure_test_describe_axis_scoped_text :: proc(rt: ^Runtime, scale: f32) -> (panel, sibling: Node_ID) {
	invalidate_root(rt, "axis-scoped layout boundary fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("axis-boundary-root"), style=layout_style(.Column, width=240, height=160))
	panel = container_begin(
		&ui,
		.Container,
		key=key_string("axis-boundary-panel"),
		style=layout_style(.Column, width=120, height=LAYOUT_SIZE_FIT_CONTENT),
		layout_boundary_axes={.Width},
	)
	scope := style_environment_push(&ui, Style_Environment{text_scale=scale})
	text_field(&ui, "A wrapped editor line whose measured height grows with text scale", key=key_string("axis-boundary-editor"), style=layout_style(width=110))
	style_environment_pop(&ui, scope)
	container_end(&ui)
	sibling = text(&ui, "Sibling", key=key_string("axis-boundary-sibling"), style=layout_style(width=100, height=24))
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_axis_scoped_layout_boundary_allows_fit_content_height_to_escape :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 160}, Runtime_Config{trace_capacity=32})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "axis-boundary fixture font should load")
	panel, sibling := layout_measure_test_describe_axis_scoped_text(&rt, 1)
	if panel == 0 || sibling == 0 { testing.expect(t, false, "axis-boundary fixture should be retained"); return }
	if rt.nodes[panel].layout_boundary_axes != {.Width} {
		testing.expect(t, false, "axis-selective boundary API should retain only the requested width axis")
		return
	}
	old_height := rt.nodes[panel].bounds.h
	rt.layout_visit_probe[panel] = 0
	rt.layout_visit_probe[sibling] = 0
	next_panel, next_sibling := layout_measure_test_describe_axis_scoped_text(&rt, 1.5)
	if next_panel != panel || next_sibling != sibling { testing.expect(t, false, "text scale should preserve fixture identities"); return }
	testing.expect(t, rt.nodes[panel].bounds.h > old_height,
		"the auto-height boundary should adopt the larger wrapped-text measurement")
	testing.expect(t, rt.layout_visit_probe[panel] > 0 && rt.layout_visit_probe[sibling] > 0,
		"height invalidation must escape a width-only boundary and refresh ancestor placement")
}

@(test)
test_fit_content_boundary_axis_is_not_claimed_stable :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 160}, Runtime_Config{trace_capacity=32})
	defer destroy_runtime(&rt)
	root := new(Node, allocator=rt.persistent_allocator)
	root.id = 7901
	root.kind = .Root
	root.active = true
	root.layout_boundary_axes = {.Width, .Height}
	rt.nodes[root.id] = root
	boundary := new(Node, allocator=rt.persistent_allocator)
	boundary.id = 7902
	boundary.parent = root.id
	boundary.kind = .Container
	boundary.active = true
	boundary.style.height = LAYOUT_SIZE_FIT_CONTENT
	boundary.layout_boundary_axes = {.Width, .Height}
	rt.nodes[boundary.id] = boundary
	child := new(Node, allocator=rt.persistent_allocator)
	child.id = 7903
	child.parent = boundary.id
	child.kind = .Text
	child.active = true
	rt.nodes[child.id] = child

	mark_layout_ancestors(&rt, child.id, {.Height})
	root_dirty := dirty_has(root.dirty, .Layout)
	boundary_queued := boundary.layout_root_queued
	found_unstable_trace := false
	for event in rt.trace.events {
		if event.kind == .Invalidation && strings.contains(event.reason, "cannot contain") && strings.contains(event.reason, "FIT_CONTENT") {
			found_unstable_trace = true
		}
	}
	testing.expect(t, root_dirty && !boundary_queued,
		"FIT_CONTENT height must continue to the ancestor instead of becoming a local boundary root")
	testing.expect(t, found_unstable_trace, "trace should explain that FIT_CONTENT makes the boundary height unstable")
}

layout_measure_test_describe_centered_row :: proc(rt: ^Runtime, child_height: f32) -> (row, child: Node_ID) {
	invalidate_root(rt, "centered Row child height fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	row = container_begin(&ui, .Root, key=key_string("centered-row-root"), style=layout_style(.Row, align=.Center))
	child = text(&ui, "label", key=key_string("centered-row-child"), style=layout_style(width=80, height=child_height))
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_row_height_only_child_change_recomputes_cross_axis_placement :: proc(t: ^testing.T) {
	incremental := new_runtime(Rect{0, 0, 240, 100})
	defer destroy_runtime(&incremental)
	if !text_engine_load_font(&incremental.text_engine, LAYOUT_MEASURE_TEST_FONT) {
		testing.expect(t, false, "centered Row fixture font should load")
		return
	}
	row, child := layout_measure_test_describe_centered_row(&incremental, 20)
	if row == 0 || child == 0 { testing.expect(t, false, "initial centered Row fixture should be retained"); return }
	initial_bounds := incremental.nodes[child].bounds
	_, updated_child := layout_measure_test_describe_centered_row(&incremental, 40)
	if updated_child != child { testing.expect(t, false, "height-only update should preserve child identity"); return }
	for _ in 0..<8 {
		if !incremental.invalidated { break }
		_, updated_child = layout_measure_test_describe_centered_row(&incremental, 40)
	}
	updated_bounds := incremental.nodes[child].bounds

	fresh := new_runtime(Rect{0, 0, 240, 100})
	defer destroy_runtime(&fresh)
	if !text_engine_load_font(&fresh.text_engine, LAYOUT_MEASURE_TEST_FONT) {
		testing.expect(t, false, "fresh centered Row fixture font should load")
		return
	}
	_, fresh_child := layout_measure_test_describe_centered_row(&fresh, 40)
	if fresh_child == 0 { testing.expect(t, false, "fresh centered Row fixture should be retained"); return }
	fresh_bounds := fresh.nodes[fresh_child].bounds

	testing.expect(t, initial_bounds.h == 20 && initial_bounds.y == 40,
		"the initial Row child should be centered using its 20-pixel height")
	testing.expect(t, updated_bounds.h == 40 && updated_bounds.y == 30 && updated_bounds == fresh_bounds,
		"incremental Row placement should match a fresh centered layout after the child height changes")
}

@(test)
test_measure_dirty_without_parent_constraints_defers_measurement :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 40})
	defer destroy_runtime(&rt)
	node := new(Node, allocator=rt.persistent_allocator)
	node.id = 7001
	node.kind = .Text
	node.active = true
	rt.nodes[node.id] = node
	append(&rt.order, node.id)
	rt.measure_states[node.id] = Measure_State{input_revision=1}
	dirty_set(&node.dirty, .Measure, true)
	layout_measure_retained_dirty_nodes(&rt)
	testing.expect(t, rt.stats.measure_requests == 0 && dirty_has(node.dirty, .Measure),
		"a new measure-dirty node must wait for parent-supplied constraints instead of guessing an unconstrained size")
}

@(test)
test_layout_measure_baseline_is_first_text_baseline_from_outer_top :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 80})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "measurement fixture font should load")
	invalidate_root(&rt, "baseline fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "baseline fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("measure-baseline-root"), style=layout_style(.Column, width=200, height=80))
	content := Button_Content_Style{horizontal=.Start, vertical=.Start, padding_x=0, padding_y=7}
	id := emit_key(&ui, .Button, resolve_source(Source_Site{}, "baseline-test"), label="first line\nsecond line", key=key_string("measure-baseline-button"), style=layout_style(width=180, height=60), text_style=Text_Style{font_weight=FONT_WEIGHT_REGULAR, overflow=.Wrap}, button_content=content)
	container_end(&ui)
	end_frame(&ui)
	node := rt.nodes[id]
	state := rt.measure_states[id]
	want := layout_unit_position(node.text_run.lines[0].baseline + 7)
	testing.expect(t, state.result.baseline_valid && state.result.baseline == want,
		"baseline should be the first shaped text baseline measured from the outer top, including button content padding")
}

@(test)
test_layout_constraints_and_quantization_are_normalized_and_conservative :: proc(t: ^testing.T) {
	finite := layout_axis_constraint_normalize(-3, 10.0001)
	unbounded := layout_axis_constraint_normalize(2.25, -1)
	testing.expect(t, finite.min == 0 && !finite.unbounded_max && layout_unit_to_f32(finite.max) <= 10.0001,
		"finite maximum constraints should round inward and negative minima should normalize to zero")
	testing.expect(t, unbounded.min <= unbounded.max && unbounded.unbounded_max && layout_unit_to_f32(unbounded.min) >= 2.25,
		"unbounded constraints should retain an explicit bound flag and conservatively quantized minimum")

	values := [4]f32{0.1, 1.333, 1024.125, 8192.75}
	scales := [3]f32{64, 256, 1024}
	for scale in scales {
		for value in values {
			units := Layout_Unit(i64(math.ceil(value*scale)))
			measured := f32(i64(units))/scale
			testing.expect(t, measured >= value && measured-value <= 1/scale+0.001,
				"candidate fixed-point scales should round measured extents conservatively within one unit")
		}
	}
	testing.expect(t, layout_unit_to_f32(layout_unit_extent(1e12)) >= 1e12,
		"large retained extents should remain finite and conservative")
}

@(test)
test_finalization_uses_shared_absolute_edges_without_mutating_target :: proc(t: ^testing.T) {
	target_a := layout_target_rect_from_rect(Rect{0, 0, 10.5, 20})
	target_b := layout_target_rect_from_rect(Rect{10.5, 0, 10.5, 20})
	a := layout_finalize_target_rect(target_a, 1.25, 1.25)
	b := layout_finalize_target_rect(target_b, 1.25, 1.25)
	testing.expect(t, a.x+a.w == b.x,
		"adjacent target rectangles should share one snapped absolute edge at fractional display scale")

	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	id := layout_measure_test_describe_text(&rt, "target geometry", Color{0.2, 0.2, 0.2, 1})
	if id == 0 { testing.expect(t, false, "geometry fixture should be retained"); return }
	node := rt.nodes[id]
	node.bounds = Rect{0.2, 0.4, 10.1, 20.2}
	layout_finalize_node_geometry(&rt)
	target_before := node.bounds
	measure_before := rt.stats.measure_requests
	layout_before := rt.stats.layout_nodes_visited
	builds_before_scale := rt.stats.frames_built
	testing.expect(t, !rt.invalidated, "device-scale fixture should be settled before a scale-only change")
	one_x := rt.finalized_geometry[id].bounds.x
	one_w := rt.finalized_geometry[id].bounds.w
	testing.expect(t, set_presentation_scale(&rt, 1.25, 1.25), "a new device scale should request geometry finalization")
	finalized := rt.finalized_geometry[id].bounds
	testing.expect(t, node.bounds == target_before && rt.stats.measure_requests == measure_before && rt.stats.layout_nodes_visited == layout_before &&
		!rt.invalidated && rt.stats.frames_built == builds_before_scale,
		"DPI finalization must preserve targets and avoid application rebuild, measure, and layout")
	testing.expect(t, presentation_needs_frame(&rt), "DPI finalization should schedule presentation without an application rebuild")
	testing.expect(t, finalized.x != one_x || finalized.w != one_w,
		"fractional target edges should be recomputed for the new device pixel grid")
	_ = set_presentation_scale(&rt, 1, 1)
	testing.expect(t, rt.finalized_geometry[id].bounds == layout_finalize_rect(target_before, 1, 1),
		"returning to a previous scale should reproduce its finalized geometry without cumulative snap drift")
}

@(test)
test_scale_finalization_publishes_semantic_bounds_without_rebuilding :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	id, _ := semantic_action_test_render(&rt)
	if id == 0 { testing.expect(t, false, "semantic geometry fixture should be retained"); return }
	node := rt.nodes[id]
	node.bounds = Rect{0.2, 0.4, 10.1, 20.2}
	layout_finalize_node_geometry(&rt)
	semantic_sync_bounds(&rt, node)
	_ = semantic_commit(&rt)
	base_revision := semantic_revision(&rt)
	semantic_id := semantic_visual_id(id)
	before, found := semantic_node_lookup(&rt, semantic_id)
	if !found { testing.expect(t, false, "text semantic node should exist before scale change"); return }
	base_bounds := before.bounds
	builds_before := rt.stats.frames_built

	testing.expect(t, set_presentation_scale(&rt, 1.25, 1.25), "scale change should finalize geometry")
	updated, updated_found := semantic_node_lookup(&rt, semantic_id)
	change := semantic_update_since(&rt, base_revision)
	changed_id_found := false
	for changed_id in change.changed_ids { if changed_id == semantic_id { changed_id_found = true } }
	testing.expect(t, updated_found && updated.bounds == rt.finalized_geometry[id].bounds && updated.bounds != base_bounds,
		"semantic snapshot entities should expose the newly finalized device-grid bounds")
	testing.expect(t, semantic_revision(&rt) == base_revision+1 && !change.requires_snapshot &&
		change.to_revision == base_revision+1 && changed_id_found,
		"scale-only finalization should publish one revisioned semantic bounds delta")
	snapshot := semantic_snapshot(&rt)
	defer semantic_snapshot_destroy(&snapshot)
	snapshot_bounds_found := false
	for semantic_node in snapshot.nodes {
		if semantic_node.id == semantic_id {
			snapshot_bounds_found = semantic_node.has_bounds && semantic_node.bounds == rt.finalized_geometry[id].bounds
		}
	}
	testing.expect(t, snapshot.revision == base_revision+1 && snapshot_bounds_found,
		"full semantic snapshots should carry the same finalized bounds revision as the latest delta")
	testing.expect(t, rt.stats.frames_built == builds_before,
		"publishing finalized semantic geometry must not rebuild the application")
}

@(test)
test_split_drag_uses_unsnapped_target_extent :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 60})
	defer destroy_runtime(&rt)
	rt.presentation_scale_x, rt.presentation_scale_y = 1.25, 1.25
	owner := new(Node, allocator=rt.persistent_allocator)
	owner.id = 7010
	owner.kind = .Split
	owner.active = true
	owner.split_axis = .Horizontal
	owner.bounds = Rect{0, 0, 101, 40}
	owner.split_position = 90
	owner.split_drag_start_position = 100
	rt.nodes[owner.id] = owner
	layout_finalize_node_geometry_for_node(&rt, owner)
	handle := Node{
		id=7011,
		kind=.Split_Handle,
		active=true,
		split_owner=owner.id,
		split_axis=.Horizontal,
		split_handle_size=10,
	}
	update_split_drag(&rt, &handle, 0, 0)
	testing.expect(t, owner.split_position == 91,
		"split drag clamping should use the same unsnapped logical extent as split placement")
}

@(test)
test_parent_placement_and_external_size_dependencies_are_distinct :: proc(t: ^testing.T) {
	state := Measure_State{parent_layout_dependencies={.Height}, parent_size_dependencies={.Height_To_Height}}
	testing.expect(t, layout_parent_placement_depends_on(state, {.Height}) && !layout_parent_placement_depends_on(state, {.Width}),
		"child output axes should independently determine whether parent placement needs recomputation")
	testing.expect(t, layout_map_child_size_change(state.parent_size_dependencies, {.Height}) == {.Height} &&
		layout_map_child_size_change(state.parent_size_dependencies, {.Width}) == {},
		"child-to-parent external-size propagation should use its separate axis map")
}

layout_content_test_describe_rows :: proc(rt: ^Runtime, heights: []f32, min_height: f32 = -1, max_height: f32 = -1) -> Node_ID {
	invalidate_root(rt, "content-sized container fixture")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("content-size-root"), style=layout_style(.Column, width=300, height=300))
	panel_style := layout_style(.Column, width=200, height=LAYOUT_SIZE_FIT_CONTENT, min_height=min_height, max_height=max_height, padding=10, gap=5, clip=true)
	panel := container_begin(&ui, .Container, key=key_string("content-size-panel"), style=panel_style)
	for height, index in heights {
		container_begin(&ui, .Container, key=key_pair(u64(index+1), 0xC017), style=layout_style(.Column, height=height))
		container_end(&ui)
	}
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return panel
}

@(test)
test_content_height_measures_column_children_and_clamps_min_max :: proc(t: ^testing.T) {
	heights := [2]f32{20, 30}
	for clamp_case in 0..<3 {
		rt := new_runtime(Rect{0, 0, 300, 300})
		panel_id := Node_ID(0)
		if clamp_case == 0 { panel_id = layout_content_test_describe_rows(&rt, heights[:], -1, -1) }
		else if clamp_case == 1 { panel_id = layout_content_test_describe_rows(&rt, heights[:], -1, 60) }
		else { panel_id = layout_content_test_describe_rows(&rt, heights[:], 90, -1) }
		panel, ok := rt.nodes[panel_id]
		testing.expect(t, ok, "content-sized panel should be retained")
		if ok {
			want_height := f32(75)
			if clamp_case == 1 { want_height = 60 }
			if clamp_case == 2 { want_height = 90 }
			testing.expect(t, panel.bounds.w == 200 && panel.bounds.h == want_height,
				"content height should include realized child heights, gap, padding, and deterministic min/max clamping")
			state := rt.measure_states[panel_id]
			testing.expect(t, layout_unit_to_f32(state.result.size.height) == want_height,
				"retained Measure_Result should match the laid out content height")
		}
		destroy_runtime(&rt)
	}
}

layout_content_test_describe_text :: proc(rt: ^Runtime, value: string) -> Node_ID {
	invalidate_root(rt, "content-sized text fixture")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("content-text-root"), style=layout_style(.Column, width=300, height=300))
	panel := container_begin(&ui, .Container, key=key_string("content-text-panel"), style=layout_style(.Column, width=200, height=LAYOUT_SIZE_FIT_CONTENT, padding=8, gap=4))
	text(&ui, value, key=key_string("content-text-leaf"), style=layout_style(width=120, height=24))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return panel
}

@(test)
test_content_height_tracks_changed_child_axis_and_equal_measurement_stays_local :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 300, 300})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "content text fixture font should load")
	panel_id := layout_content_test_describe_text(&rt, "cat")
	if panel_id == 0 { testing.expect(t, false, "initial content panel should be retained"); return }
	panel := rt.nodes[panel_id]
	first_result := rt.measure_states[panel_id].result
	layout_visits := rt.stats.layout_nodes_visited
	_ = layout_content_test_describe_text(&rt, "dog")
	second_result := rt.measure_states[panel_id].result
	testing.expect(t, layout_measure_result_equal(first_result, second_result) && rt.stats.layout_nodes_visited == layout_visits,
		"a child measure miss with identical dimensions should not propagate layout through its content-sized parent")

	changed_heights := [1]f32{64}
	changed_panel_id := layout_content_test_describe_rows(&rt, changed_heights[:], -1, -1)
	changed_panel := rt.nodes[changed_panel_id]
	testing.expect(t, changed_panel.bounds.w == panel.bounds.w && changed_panel.bounds.h == 84,
		"a child height change should update only the content panel's measured height while preserving its width")

	fresh := new_runtime(Rect{0, 0, 300, 300})
	defer destroy_runtime(&fresh)
	fresh_panel_id := layout_content_test_describe_rows(&fresh, changed_heights[:], -1, -1)
	fresh_panel := fresh.nodes[fresh_panel_id]
	testing.expect(t, changed_panel.bounds == fresh_panel.bounds &&
		layout_measure_result_equal(rt.measure_states[changed_panel_id].result, fresh.measure_states[fresh_panel_id].result),
		"incremental content sizing should match a clean solve for the same final tree")
}

@(test)
test_content_height_column_in_row_uses_measured_cross_axis_extent :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 300, 160})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "new runtime should request its first description"); return }
	container_begin(&ui, .Root, key=key_string("content-row-root"), style=layout_style(.Row, width=300, height=160, gap=10, align=.Center))
	column_id := container_begin(
		&ui,
		.Container,
		key=key_string("content-row-fit-column"),
		style=layout_style(.Column, height=LAYOUT_SIZE_FIT_CONTENT, grow=1, padding=8, gap=6),
	)
	container_begin(&ui, .Container, key=key_string("content-row-first"), style=layout_style(.Column, height=20))
	container_end(&ui)
	container_begin(&ui, .Container, key=key_string("content-row-second"), style=layout_style(.Column, height=30))
	container_end(&ui)
	container_end(&ui)
	sidebar_id := container_begin(&ui, .Container, key=key_string("content-row-sidebar"), style=layout_style(.Column, width=100, height=100))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	column, column_ok := rt.nodes[column_id]
	sidebar, sidebar_ok := rt.nodes[sidebar_id]
	state, measure_ok := rt.measure_states[column_id]
	testing.expect(t, column_ok && sidebar_ok && measure_ok, "fit-height column and sibling should be retained and measured")
	if column_ok && sidebar_ok && measure_ok {
		testing.expect(t, column.bounds.w == 190 && column.bounds.h == 72,
			"a content-height Column in a Row should keep its allocated width and measure children, gap, and padding instead of stretching to the Row height")
		testing.expect(t, column.bounds.y == 44 && sidebar.bounds.y == 30,
			"center alignment should position each child from its own cross-axis extent")
		testing.expect(t, layout_unit_to_f32(state.result.size.height) == column.bounds.h,
			"the Row should place the content-sized Column using its retained measured height")
	}
}

layout_content_test_describe_empty_row :: proc(
	rt: ^Runtime,
	min_height: f32 = -1,
	max_height: f32 = -1,
) -> Node_ID {
	rt.viewport = Rect{0, 0, 200, 120}
	invalidate_root(rt, "empty content-sized Row fixture")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("content-empty-row-root"), style=layout_style(.Column, height=120))
	row := container_begin(&ui, .Container, key=key_string("content-empty-row"), style=layout_style(
		.Row,
		height=LAYOUT_SIZE_FIT_CONTENT,
		min_height=min_height,
		max_height=max_height,
		padding=6,
	))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return row
}

@(test)
test_content_height_measures_empty_row_and_keeps_ordinary_row_stretch :: proc(t: ^testing.T) {
	for clamp_case in 0..<3 {
		rt := new_runtime(Rect{0, 0, 200, 120})
		row_id := Node_ID(0)
		if clamp_case == 0 { row_id = layout_content_test_describe_empty_row(&rt) }
		else if clamp_case == 1 { row_id = layout_content_test_describe_empty_row(&rt, min_height=20) }
		else { row_id = layout_content_test_describe_empty_row(&rt, max_height=8) }
		row, ok := rt.nodes[row_id]
		want_height := f32(12)
		if clamp_case == 1 { want_height = 20 }
		if clamp_case == 2 { want_height = 8 }
		testing.expect(t, ok && row.bounds.h == want_height,
			"an empty content-sized Row should contain its vertical padding and obey min/max clamps")
		if ok {
			testing.expect(t, rt.measure_states[row_id].result.size.height == layout_unit_extent(want_height),
				"the empty Row's retained result should match its final constrained height")
		}
		destroy_runtime(&rt)
	}

	rt := new_runtime(Rect{0, 0, 200, 120})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "ordinary Row fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("ordinary-row-content-root"), style=layout_style(.Row, height=100))
	child := container_begin(&ui, .Container, key=key_string("ordinary-row-content-child"), style=layout_style(.Column, width=48))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	testing.expect(t, rt.nodes[child].bounds.h == rt.viewport.h,
		"an ordinary Row still stretches an unspecified child to the externally assigned cross axis")
}

layout_content_test_describe_wrapped_row :: proc(rt: ^Runtime, width: f32) -> (row, fixed, wrapped: Node_ID) {
	rt.viewport = Rect{0, 0, width, 180}
	invalidate_root(rt, "wrapped content-sized Row fixture")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("content-wrapped-row-root"), style=layout_style(.Column, height=180))
	row = container_begin(&ui, .Container, key=key_string("content-wrapped-row"), style=layout_style(
		.Row,
		height=LAYOUT_SIZE_FIT_CONTENT,
		padding=8,
		gap=8,
	))
	fixed = container_begin(&ui, .Container, key=key_string("content-wrapped-row-fixed"), style=layout_style(.Column, width=64, height=52))
	container_end(&ui)
	wrapped = text(
		&ui,
		"A width dependent toolbar label should wrap when the available Row space becomes narrow and unwrap again when it expands.",
		key=key_string("content-wrapped-row-text"),
		style=layout_style(.Row, grow=1, min_width=48),
		text_style=Text_Style{overflow=.Wrap},
	)
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_content_height_row_uses_allocated_width_for_wrapped_children_and_tracks_resize :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 220, 180})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT) {
		testing.expect(t, false, "wrapped Row measurement fixture font should load")
		return
	}
	row_id, fixed_id, wrapped_id := layout_content_test_describe_wrapped_row(&rt, 220)
	row, row_ok := rt.nodes[row_id]
	fixed, fixed_ok := rt.nodes[fixed_id]
	wrapped, wrapped_ok := rt.nodes[wrapped_id]
	row_measure, measure_ok := rt.measure_states[row_id]
	wrapped_measure, wrapped_measure_ok := rt.measure_states[wrapped_id]
	testing.expect(t, row_ok && fixed_ok && wrapped_ok && measure_ok && wrapped_measure_ok,
		"the content Row, fixed child, wrapped label, and retained measures should exist")
	if row_ok && fixed_ok && wrapped_ok && measure_ok && wrapped_measure_ok {
		expected_height := max(fixed.bounds.h, layout_unit_to_f32(wrapped_measure.result.size.height))+16
		testing.expect(t, row.bounds.h == expected_height,
			"a content Row should use the greatest measured child height plus its vertical padding, not sum horizontal children or gaps")
		testing.expect(t, len(wrapped.text_run.lines) > 1 && wrapped.bounds.w < 180,
			"the wrapped label should be shaped at its allocated width inside the mixed fixed/content Row")
		testing.expect(t, row_measure.cache_key.constraints.width.min == layout_unit_extent(220) &&
			row_measure.cache_key.constraints.width.max == layout_unit_extent(220),
			"the retained Row result should preserve the exact incoming assigned width")
		testing.expect(t, row_measure.cache_key.constraints.height.min == 0 &&
			row_measure.cache_key.constraints.height.max == layout_unit_extent(180),
			"the retained Row result should also preserve the parent's bounded cross-axis constraint")
		testing.expect(t, wrapped_measure.cache_key.constraints.width.min == layout_unit_extent(wrapped.bounds.w) &&
			wrapped_measure.cache_key.constraints.width.max == layout_unit_extent(wrapped.bounds.w),
			"width-dependent child measurement should retain the exact width assigned by the Row allocator")
		testing.expect(t, .Width_To_Width in row_measure.result.input_axis_dependencies &&
			.Height_To_Height in row_measure.result.input_axis_dependencies &&
			.Width_To_Height in row_measure.result.input_axis_dependencies &&
			.Width_To_Height in wrapped_measure.result.input_axis_dependencies,
			"the Row should retain incoming-axis and wrapped-child cross-axis dependencies")
	}
	if !row_ok || !measure_ok { return }
	narrow_height := row.bounds.h

	row_id, _, _ = layout_content_test_describe_wrapped_row(&rt, 400)
	row = rt.nodes[row_id]
	wide_height := row.bounds.h
	testing.expect(t, wide_height < narrow_height,
		"resizing the assigned Row width should remeasure its wrapped child and reduce the content height")

	fresh := new_runtime(Rect{0, 0, 400, 180})
	defer destroy_runtime(&fresh)
	_ = text_engine_load_font(&fresh.text_engine, LAYOUT_MEASURE_TEST_FONT)
	fresh_row_id, _, _ := layout_content_test_describe_wrapped_row(&fresh, 400)
	fresh_row := fresh.nodes[fresh_row_id]
	testing.expect(t, row.bounds == fresh_row.bounds &&
		layout_measure_result_equal(rt.measure_states[row_id].result, fresh.measure_states[fresh_row_id].result),
		"a resized content Row should replay to the same geometry and retained measurement as a clean wide layout")
}

@(test)
test_content_sized_scroll_region_caps_virtual_list_and_keeps_virtualization_bounded :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 260})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "new runtime should request its first description"); return }
	container_begin(&ui, .Root, key=key_string("content-scroll-root"), style=layout_style(.Column, width=400, height=260))
	panel_id := container_begin(&ui, .Container, key=key_string("content-scroll-panel"), style=layout_style(.Column, width=300, height=LAYOUT_SIZE_FIT_CONTENT, max_height=140, padding=10, gap=8, clip=true))
	container_begin(&ui, .Container, key=key_string("content-scroll-query-row"), style=layout_style(.Row, height=30))
	container_end(&ui)
	list := virtual_list_begin(&ui, 100, 20, key=key_string("content-scroll-list"), style=layout_style(.Column, height=LAYOUT_SIZE_FIT_CONTENT, max_height=80, grow=1, clip=true))
	for index in list.first..<list.last {
		container_begin(&ui, .Virtual_Row, key=key_pair(u64(index+1), 0xA551), style=layout_style(.Column, height=20))
		container_end(&ui)
	}
	virtual_list_end(&ui, list)
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	panel, panel_ok := rt.nodes[panel_id]
	region, region_ok := rt.nodes[list.scroll.id]
	active_rows := 0
	for _, node in rt.nodes { if node != nil && node.active && node.kind == .Virtual_Row { active_rows += 1 } }
	testing.expect(t, panel_ok && region_ok, "content panel and capped scroll region should be retained")
	if panel_ok && region_ok {
		testing.expect(t, panel.bounds.h == 138 && region.bounds.h == 80 && list.scroll.viewport_height == 80,
			"the panel should include the capped scroll viewport without a manually assigned outer height")
		testing.expect(t, region.scroll_content_height == 2000 && region.scroll_offset_y <= region.scroll_content_height-region.bounds.h,
			"the bounded viewport should preserve the full logical extent and clamp its scroll offset")
	}
	testing.expect(t, list.last-list.first <= 5 && active_rows == list.last-list.first,
		"only visible virtual rows should be realized for a content-sized capped list")
}
