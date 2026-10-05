package alicorn

// paint_retained_command_capacity_bytes reports the inline backing storage for
// node paint caches plus the composed display list. Referenced text spans and
// shaped runs remain owned resources and are intentionally excluded.
paint_retained_command_capacity_bytes :: proc(rt: ^Runtime) -> int {
	if rt == nil { return 0 }
	capacity := cap(rt.display)
	for _, node in rt.nodes {
		if node != nil { capacity += cap(node.paint) }
	}
	return capacity * size_of(Paint_Command)
}

// Generations are runtime-wide so a removed node recreated at the same
// structural identity cannot accidentally validate an old renderer handle.
paint_next_resource_generation :: proc(rt: ^Runtime) -> u64 {
	if rt == nil { return 0 }
	rt.paint_resource_generation += 1
	if rt.paint_resource_generation == 0 { rt.paint_resource_generation = 1 }
	return rt.paint_resource_generation
}

paint_text_handle_for_node :: proc(node: ^Node) -> Text_Run_Handle {
	if node == nil || !node.text_run_valid || node.text_run_handle_generation == 0 { return {} }
	return Text_Run_Handle{.Retained, u64(node.id), node.text_run_handle_generation}
}

paint_text_handle_for_composition :: proc(node: ^Node) -> Text_Run_Handle {
	if node == nil || !node.composition_run_valid || node.composition_run_handle_generation == 0 { return {} }
	return Text_Run_Handle{.Composition, u64(node.id), node.composition_run_handle_generation}
}

paint_text_handle_for_tooltip :: proc(rt: ^Runtime) -> Text_Run_Handle {
	if rt == nil || !rt.tooltip.run_ready || rt.tooltip.run_generation == 0 { return {} }
	return Text_Run_Handle{.Tooltip, 0, rt.tooltip.run_generation}
}

paint_text_handle_for_drag_preview :: proc(rt: ^Runtime) -> Text_Run_Handle {
	if rt == nil || !rt.drag_preview.ready || rt.drag_preview.run_generation == 0 { return {} }
	return Text_Run_Handle{.Drag_Preview, 0, rt.drag_preview.run_generation}
}

// paint_text_run_resolve returns only shaped glyph/layout data. Renderers must
// use this generation-checked handle rather than inspect Runtime.nodes.
paint_text_run_resolve :: proc(rt: ^Runtime, handle: Text_Run_Handle) -> (run: ^Text_Run, ok: bool) {
	if rt == nil || handle.generation == 0 { return }
	switch handle.source {
	case .Retained:
		node, found := rt.nodes[Node_ID(handle.resource)]
		if !found || node == nil || !node.active || !node.text_run_valid || node.text_run_handle_generation != handle.generation { return }
		return &node.text_run, true
	case .Composition:
		node, found := rt.nodes[Node_ID(handle.resource)]
		if !found || node == nil || !node.active || !node.composition_run_valid || node.composition_run_handle_generation != handle.generation { return }
		return &node.composition_run, true
	case .Tooltip:
		if handle.resource != 0 || !rt.tooltip.run_ready || rt.tooltip.run_generation != handle.generation { return }
		return &rt.tooltip.run, true
	case .Drag_Preview:
		if handle.resource != 0 || !rt.drag_preview.ready || rt.drag_preview.run_generation != handle.generation { return }
		return &rt.drag_preview.run, true
	case .Host:
		return
	}
	return
}

paint_geometry_handle_for_node :: proc(node: ^Node) -> Geometry_Handle {
	if node == nil || node.surface_resource_generation == 0 { return {} }
	return Geometry_Handle{node.id, node.surface_resource_generation}
}

// gpu_surface_payload_resolve returns payload slices only. Bounds and clip
// must come from the paint command, never be recovered from the owner node.
gpu_surface_payload_resolve :: proc(rt: ^Runtime, handle: Geometry_Handle) -> (payload: GPU_Surface_Payload_View, ok: bool) {
	if rt == nil || handle.resource == 0 || handle.generation == 0 { return }
	node, found := rt.nodes[handle.resource]
	if !found || node == nil || !node.active || node.surface_resource_generation != handle.generation { return }
	return GPU_Surface_Payload_View{
		revision=node.surface_payload_revision,
		samples=node.surface_samples[:],
		segments=node.surface_segments[:],
		circles=node.surface_circles[:],
	}, true
}
