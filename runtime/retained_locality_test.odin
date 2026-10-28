package alicorn

import "core:testing"

RETAINED_LOCALITY_ROOT :: Source_Site{"runtime/retained_locality_test.odin", 10, 1, "locality_root"}
RETAINED_LOCALITY_SIBLING :: Source_Site{"runtime/retained_locality_test.odin", 20, 1, "locality_sibling"}
RETAINED_LOCALITY_SCOPE :: Source_Site{"runtime/retained_locality_test.odin", 30, 1, "locality_scope"}
RETAINED_LOCALITY_REGION :: Source_Site{"runtime/retained_locality_test.odin", 31, 1, "locality_region"}
RETAINED_LOCALITY_LEAF :: Source_Site{"runtime/retained_locality_test.odin", 32, 1, "locality_leaf"}

retained_locality_describe :: proc(
	rt: ^Runtime,
	count: int,
	sibling_color: Color,
	body_calls: ^int,
) -> Node_ID {
	invalidate_root(rt, "retained locality fixture")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin_ex(&ui, .Root, RETAINED_LOCALITY_ROOT, key="locality-root", explicit_key=true, style=layout_style(.Column, width=640, height=480))
	sibling := container_begin_ex(
		&ui, .Container, RETAINED_LOCALITY_SIBLING, key="locality-sibling",
		explicit_key=true, style=layout_style(width=80, height=24), color=sibling_color,
	)
	container_end(&ui)
	if key_scope_u64(&ui, 1, RETAINED_LOCALITY_SCOPE) {
		region, reused := region_begin(
			&ui, "locality-region", 1, RETAINED_LOCALITY_REGION,
			style=layout_style(.Column, width=520, height=400),
		)
		if region != 0 && !reused {
			body_calls^ += 1
			for i := 0; i < count; i += 1 {
				if key_scope_u64(&ui, u64(i), RETAINED_LOCALITY_LEAF) {
					container_begin_ex(
						&ui, .Container, RETAINED_LOCALITY_LEAF, key="leaf",
						explicit_key=true, style=layout_style(width=1, height=1), color=Color{0.2, 0.3, 0.4, 1},
					)
					container_end(&ui)
					key_scope_end(&ui)
				}
			}
			region_end(&ui, region, reused, 0)
		}
		key_scope_end(&ui)
	}
	container_end(&ui)
	end_frame(&ui)
	return sibling
}

retained_locality_commands_match :: proc(a, b: Paint_Command) -> bool {
	if a.owner != b.owner || a.bounds != b.bounds || a.clip != b.clip || a.opacity != b.opacity ||
		a.translation != b.translation || a.stroke_placement != b.stroke_placement { return false }
	a_surface, a_ok := a.payload.(Surface_Paint)
	b_surface, b_ok := b.payload.(Surface_Paint)
	return a_ok && b_ok && a_surface == b_surface
}

retained_locality_finalized_commands_match :: proc(a, b: Paint_Command) -> bool {
	if a.owner != b.owner || a.bounds != b.bounds || a.clip != b.clip || a.opacity != b.opacity ||
		a.translation != b.translation || a.stroke_placement != b.stroke_placement { return false }
	a_surface, a_surface_ok := a.payload.(Surface_Paint)
	b_surface, b_surface_ok := b.payload.(Surface_Paint)
	if a_surface_ok || b_surface_ok { return a_surface_ok && b_surface_ok && a_surface == b_surface }
	a_text, a_text_ok := a.payload.(Text_Paint)
	b_text, b_text_ok := b.payload.(Text_Paint)
	if !a_text_ok || !b_text_ok || a_text.run != b_text.run || a_text.color != b_text.color || len(a_text.spans) != len(b_text.spans) {
		return false
	}
	for span, index in a_text.spans {
		if span != b_text.spans[index] { return false }
	}
	return true
}

@(test)
test_retained_region_paint_update_work_is_independent_of_cached_descendants :: proc(t: ^testing.T) {
	counts := [3]int{100, 1000, 10000}
	for count in counts {
		rt := new_runtime(Rect{0, 0, 640, 480})
		body_calls: int = 0
		sibling := retained_locality_describe(&rt, count, Color{0.1, 0.2, 0.3, 1}, &body_calls)
		if sibling == 0 || body_calls != 1 {
			testing.expect(t, false, "initial region should retain its requested descendant set")
			destroy_runtime(&rt)
			continue
		}
		retained_count := len(rt.nodes)
		before := rt.stats
		_ = retained_locality_describe(&rt, count, Color{0.8, 0.2, 0.1, 1}, &body_calls)
		testing.expect(t, body_calls == 1 && len(rt.nodes) == retained_count,
			"a sibling paint update must reuse the region and retain every cached descendant")
		testing.expect(t, rt.stats.measure_nodes_examined-before.measure_nodes_examined == 0 &&
			rt.stats.measure_requests == before.measure_requests &&
			rt.stats.layout_nodes_visited == before.layout_nodes_visited,
			"a paint-only sibling update must schedule no measurement or layout work, independent of region size")
		testing.expect(t, rt.stats.semantic_order_nodes_examined-before.semantic_order_nodes_examined == 0,
			"an unchanged tree must not receive an accessibility preorder refresh")
		testing.expect(t, rt.stats.display_commands_finalized-before.display_commands_finalized == 1 &&
			rt.stats.display_finalization_full_passes == before.display_finalization_full_passes &&
			rt.stats.global_fallbacks == before.global_fallbacks &&
			rt.stats.global_work_by_reason[.Display_Incremental_Fallback] == before.global_work_by_reason[.Display_Incremental_Fallback],
			"one changed paint command must finalize only its own validated display slot")
		if len(rt.display) == len(rt.display_target) && len(rt.display) > 0 {
			incremental := make([]Paint_Command, len(rt.display), allocator=rt.persistent_allocator)
			copy(incremental, rt.display[:])
			layout_finalize_display(&rt, .Display_Structure_Rebuild)
			matches := len(rt.display) == len(incremental)
			for i in 0..<min(len(rt.display), len(incremental)) {
				matches = matches && retained_locality_commands_match(incremental[i], rt.display[i])
			}
			delete(incremental, rt.persistent_allocator)
			testing.expect(t, matches, "incremental slot finalization must match a fresh full-list finalization")
		} else {
			testing.expect(t, false, "fixture display and target lists should remain aligned")
		}
		destroy_runtime(&rt)
	}
}

@(test)
test_incremental_display_finalization_survives_fractional_and_round_trip_scales :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)
	body_calls: int = 0
	sibling := retained_locality_describe(&rt, 0, Color{0.1, 0.2, 0.3, 1}, &body_calls)
	sibling_node, found := rt.nodes[sibling]
	if sibling == 0 || !found || sibling_node.display_index < 0 || sibling_node.display_index >= len(rt.display) {
		testing.expect(t, false, "scale fixture should retain a finalized sibling surface command")
		return
	}
	index := sibling_node.display_index
	original_target := rt.display_target[index]
	scales := [3]f32{1.25, 2, 1}
	for scale in scales {
		_ = set_presentation_scale(&rt, scale, scale)
		expected := layout_finalize_paint_command(original_target, scale, scale)
		testing.expect(t, retained_locality_commands_match(expected, rt.display[index]) &&
			retained_locality_commands_match(original_target, rt.display_target[index]),
			"full DPI finalization must derive from the original target geometry at each scale")
	}
	full_passes := rt.stats.display_finalization_full_passes
	finalized := rt.stats.display_commands_finalized
	_ = retained_locality_describe(&rt, 0, Color{0.75, 0.25, 0.15, 1}, &body_calls)
	testing.expect(t, rt.stats.display_finalization_full_passes == full_passes &&
		rt.stats.display_commands_finalized == finalized+1 && !retained_locality_commands_match(rt.display_target[index], original_target),
		"a paint change at the current scale should update one slot while preserving its unsnapped target")
	return_scales := [2]f32{1.25, 1}
	for scale in return_scales {
		_ = set_presentation_scale(&rt, scale, scale)
		expected := layout_finalize_paint_command(rt.display_target[index], scale, scale)
		testing.expect(t, retained_locality_commands_match(expected, rt.display[index]),
			"later scale changes must use the updated unsnapped paint command without accumulated rounding")
	}
}

@(test)
test_incremental_display_finalization_rejects_mismatched_new_owner :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)
	body_calls: int = 0
	sibling := retained_locality_describe(&rt, 0, Color{0.1, 0.2, 0.3, 1}, &body_calls)
	node, found := rt.nodes[sibling]
	if !found || node.display_index < 0 || node.display_index >= len(rt.display_target) {
		testing.expect(t, false, "fixture should retain the sibling's finalized display slot")
		return
	}
	wrong_owner := rt.display_target[node.display_index]
	wrong_owner.owner = 0
	testing.expect(t, !layout_finalize_display_slot(&rt, sibling, node.display_index, wrong_owner),
		"the local finalization fast path must reject a replacement command owned by a different node")
}

retained_clipped_slot_describe :: proc(rt: ^Runtime, clip_width: f32) -> (clipper, child: Node_ID) {
	invalidate_root(rt, "retained clipped-slot description")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("retained-clipped-slot-root"), style=layout_style(.Column, width=320, height=120))
	clipper = container_begin(&ui, .Container, key=key_string("retained-clipped-slot-clipper"),
		style=layout_style(.Column, width=clip_width, height=80, clip=true))
	child = container_begin(&ui, .Container, key=key_string("retained-clipped-slot-child"),
		style=layout_style(width=120, height=24), color=Color{0.2, 0.3, 0.4, 1})
	container_end(&ui)
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_incremental_display_finalization_updates_changed_clip_geometry :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	_, child := retained_clipped_slot_describe(&rt, 100)
	node, found := rt.nodes[child]
	if !found || node.display_index < 0 || node.display_index >= len(rt.display_target) {
		testing.expect(t, false, "clip fixture should retain the child's finalized display slot")
		return
	}
	old_command := rt.display_target[node.display_index]
	full_passes_before := rt.stats.display_finalization_full_passes
	finalized_before := rt.stats.display_commands_finalized
	_, _ = retained_clipped_slot_describe(&rt, 70)
	updated := rt.display_target[node.display_index]
	expected := layout_finalize_paint_command(updated, rt.presentation_scale_x, rt.presentation_scale_y)
	testing.expect(t, updated.bounds == old_command.bounds && updated.clip.w == 70 && updated.clip != old_command.clip,
		"changing a clipped ancestor should preserve child bounds while updating the child's clip geometry")
	testing.expect(t, rt.stats.display_finalization_full_passes == full_passes_before+1 &&
		rt.stats.display_commands_finalized-finalized_before == u64(len(rt.display_target)),
		"a clip-geometry change should take the full display fallback and finalize every command")
	all_match := len(rt.display) == len(rt.display_target)
	for target, index in rt.display_target {
		finalized := layout_finalize_paint_command(target, rt.presentation_scale_x, rt.presentation_scale_y)
		all_match = all_match && retained_locality_commands_match(finalized, rt.display[index])
	}
	testing.expect(t, all_match && retained_locality_commands_match(expected, rt.display[node.display_index]),
		"the clip-geometry fallback should rebuild every paint command from its unsnapped target")
}

retained_locality_slider_describe :: proc(rt: ^Runtime, value: f32) -> Node_ID {
	invalidate_root(rt, "retained locality multi-command slider description")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("retained-locality-slider-root"), style=layout_style(.Column, width=320, height=120, clip=true))
	_ = slider_f32(&ui, "Gain", value, 0, 1, 0, key=key_string("retained-locality-slider"), style=layout_style(width=260, height=56))
	id := ui.runtime.pending[len(ui.runtime.pending)-1].description.id
	container_end(&ui)
	end_frame(&ui)
	return id
}

@(test)
test_multi_command_paint_update_uses_full_display_rebuild :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	slider := retained_locality_slider_describe(&rt, 0.2)
	node, found := rt.nodes[slider]
	if !found || len(node.paint) <= 1 {
		testing.expect(t, false, "slider fixture should retain multiple paint commands")
		return
	}
	full_passes_before := rt.stats.display_finalization_full_passes
	finalized_before := rt.stats.display_commands_finalized
	_ = retained_locality_slider_describe(&rt, 0.8)
	updated := rt.nodes[slider]
	testing.expect(t, len(updated.paint) > 1 && rt.stats.display_finalization_full_passes == full_passes_before+1 &&
		rt.stats.display_commands_finalized-finalized_before == u64(len(rt.display_target)),
		"a multi-command paint update should use the full display rebuild and finalize every target command")
	if len(rt.display) != len(rt.display_target) {
		testing.expect(t, false, "the rebuilt display should remain aligned with its retained target")
		return
	}
	for target, index in rt.display_target {
		expected := layout_finalize_paint_command(target, rt.presentation_scale_x, rt.presentation_scale_y)
		testing.expect(t, retained_locality_finalized_commands_match(expected, rt.display[index]),
			"the multi-command fallback should finalize every command from its unsnapped target")
	}
}
