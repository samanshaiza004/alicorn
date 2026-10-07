package alicorn

import "core:testing"
import "core:math"

LAYOUT_MEASURE_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

layout_measure_test_describe_text :: proc(rt: ^Runtime, value: string, color: Color) -> Node_ID {
	invalidate_root(rt, "layout measure test description")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("layout-measure-test-root"), style=layout_style(.Column, width=240, height=120))
	id := text(&ui, value, key=key_string("layout-measure-test-text"), style=layout_style(width=200, height=40))
	if len(rt.pending) > 0 { rt.pending[len(rt.pending)-1].description.color = color }
	container_end(&ui)
	end_frame(&ui)
	return id
}

layout_measure_test_describe_scoped_text :: proc(rt: ^Runtime, scale: f32) -> (editor, sidebar: Node_ID) {
	invalidate_root(rt, "layout boundary scale test description")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("measure-boundary-root"), style=layout_style(.Row, width=240, height=120))
	container_begin(&ui, .Container, key=key_string("measure-boundary-editor"), style=layout_style(.Column, width=120, height=120), layout_boundary=true)
	scope := style_environment_push(&ui, Style_Environment{text_scale=scale})
	editor = text_field(&ui, "A short editor line", key=key_string("measure-boundary-editor-text"), style=layout_style(width=110))
	style_environment_pop(&ui, scope)
	container_end(&ui)
	sidebar = text(&ui, "Sidebar", key=key_string("measure-boundary-sidebar"), style=layout_style(width=120, height=24))
	container_end(&ui)
	end_frame(&ui)
	return
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

	second_id := layout_measure_test_describe_text(&rt, "dog", black)
	second_measure := rt.measure_states[second_id]
	testing.expect(t, second_id == first_id && second_measure.input_revision > first_measure.input_revision,
		"text changes should advance the reconciliation-derived local measurement revision")
	testing.expect(t, rt.stats.measure_cache_misses > first_misses && rt.stats.text_shape_requests > first_shape_requests,
		"a changed input fingerprint should miss measurement and reshape its text product")
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
	rt := new_runtime(Rect{0, 0, 240, 120})
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
