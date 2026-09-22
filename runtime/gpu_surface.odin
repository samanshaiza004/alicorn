package alicorn

GPU_Fence :: distinct u64
GPU_Command_Buffer :: distinct u64

GPU_Backend :: struct {
	next_command: GPU_Command_Buffer,
	next_fence: GPU_Fence,
	completed_fence: GPU_Fence,
	command_open: bool,
	submitted: map[GPU_Fence]bool,
	retirement_queue: [dynamic]GPU_Fence,
	resource_replacements: u64,
	resource_retirements: u64,
}

// gpu_surface_update is the explicit high-frequency update path. The sample
// slice is copied into runtime-owned storage before this procedure returns;
// no application pointer is retained. It deliberately does not invalidate
// the procedural root or queue ordinary layout/paint work.
gpu_surface_update :: proc(rt: ^Runtime, id: Node_ID, revision: u64, samples: []f32) -> bool {
	node, ok := rt.nodes[id]
	if !ok || node == nil || !node.active || node.kind != .Custom_Surface {
		return false
	}
	if node.surface_revision == revision {
		return false
	}
	clear(&node.surface_samples)
	clear(&node.surface_segments)
	clear(&node.surface_circles)
	for sample in samples {
		append(&node.surface_samples, sample)
	}
	node.surface_geometry_active = false
	node.surface_revision = revision
	rt.surface_frame_pending = true
	advance_presentation_revision(rt)
	rt.stats.surface_updates += 1
	record_trace_literal(rt, .Invalidation, id, "explicit GPU surface revision update")
	return true
}

gpu_surface_geometry_scalar_valid :: proc(value: f32) -> bool {
	// Comparisons reject NaN and infinity while keeping this validation
	// independent of backend math helpers.
	return value == value && value >= -10_000_000 && value <= 10_000_000
}

gpu_surface_geometry_color_valid :: proc(color: Color) -> bool {
	return color.r >= 0 && color.r <= 1 && color.g >= 0 && color.g <= 1 && color.b >= 0 && color.b <= 1 && color.a >= 0 && color.a <= 1
}

gpu_surface_geometry_valid :: proc(segments: []GPU_Surface_Line_Segment, circles: []GPU_Surface_Filled_Circle) -> bool {
	for segment in segments {
		if !gpu_surface_geometry_scalar_valid(segment.start.x) || !gpu_surface_geometry_scalar_valid(segment.start.y) ||
		   !gpu_surface_geometry_scalar_valid(segment.end.x) || !gpu_surface_geometry_scalar_valid(segment.end.y) ||
		   !gpu_surface_geometry_scalar_valid(segment.thickness) || segment.thickness <= 0 ||
		   !gpu_surface_geometry_color_valid(segment.color) {
			return false
		}
	}
	for circle in circles {
		if !gpu_surface_geometry_scalar_valid(circle.center.x) || !gpu_surface_geometry_scalar_valid(circle.center.y) ||
		   !gpu_surface_geometry_scalar_valid(circle.radius) || circle.radius <= 0 ||
		   !gpu_surface_geometry_color_valid(circle.color) {
			return false
		}
	}
	return true
}

gpu_surface_geometry_fits :: proc(segment_count, circle_count: int) -> bool {
	if segment_count < 0 || circle_count < 0 || GPU_SURFACE_MAX_VERTICES < 0 { return false }
	remaining := GPU_SURFACE_MAX_VERTICES
	if segment_count > remaining / 6 { return false }
	remaining -= segment_count * 6
	circle_vertices := GPU_SURFACE_CIRCLE_SEGMENTS * 3
	return circle_count <= remaining / circle_vertices
}

// gpu_surface_update_geometry copies surface-local logical geometry into the
// runtime's persistent allocator. Updates are atomic: equal revisions,
// invalid primitives, and meshes exceeding GPU_SURFACE_MAX_VERTICES return
// false without replacing the currently displayed payload. Colors are
// normalized RGBA; segment thickness and circle radius are positive logical
// units. Circles are rendered as deterministic 16-triangle fans.
gpu_surface_update_geometry :: proc(
	rt: ^Runtime,
	id: Node_ID,
	revision: u64,
	segments: []GPU_Surface_Line_Segment,
	circles: []GPU_Surface_Filled_Circle,
) -> bool {
	node, ok := rt.nodes[id]
	if !ok || node == nil || !node.active || node.kind != .Custom_Surface { return false }
	if node.surface_revision == revision { return false }
	if !gpu_surface_geometry_fits(len(segments), len(circles)) {
		rt.stats.surface_geometry_overflow_rejections += 1
		return false
	}
	if !gpu_surface_geometry_valid(segments, circles) { return false }
	clear(&node.surface_segments)
	clear(&node.surface_circles)
	clear(&node.surface_samples)
	for segment in segments { append(&node.surface_segments, segment) }
	for circle in circles { append(&node.surface_circles, circle) }
	node.surface_geometry_active = true
	node.surface_revision = revision
	rt.surface_frame_pending = true
	advance_presentation_revision(rt)
	rt.stats.surface_updates += 1
	rt.stats.surface_geometry_updates += 1
	record_trace_literal(rt, .Invalidation, id, "explicit GPU surface geometry revision update")
	return true
}

gpu_surface_context :: proc(rt: ^Runtime, id: Node_ID) -> (ctx: GPU_Surface_Context, ok: bool) {
	node, found := rt.nodes[id]
	if !found || node == nil || !node.active || node.kind != .Custom_Surface {
		return ctx, false
	}
	ctx = GPU_Surface_Context{
		logical_bounds=node.bounds,
		pixel_width=node.surface_pixel_width,
		pixel_height=node.surface_pixel_height,
		dpi_scale=node.surface_dpi_scale,
		clip=rect_intersection(node.clip, node.bounds),
		revision=node.surface_revision,
	}
	if node.surface_geometry_active || node.surface_kind == .Geometry {
		ctx.pixel_width = int(node.bounds.w * node.surface_dpi_scale + 0.5)
		ctx.pixel_height = int(node.bounds.h * node.surface_dpi_scale + 0.5)
		if ctx.pixel_width < 0 { ctx.pixel_width = 0 }
		if ctx.pixel_height < 0 { ctx.pixel_height = 0 }
	}
	return ctx, true
}

gpu_surface_needs_frame :: proc(rt: ^Runtime) -> bool {
	return rt.surface_frame_pending
}

gpu_surface_frame_consumed :: proc(rt: ^Runtime) {
	if rt.surface_frame_pending {
		rt.surface_frame_pending = false
		rt.stats.surface_frames_consumed += 1
	}
}

new_gpu_backend :: proc() -> GPU_Backend {
	return GPU_Backend{submitted=make(map[GPU_Fence]bool), retirement_queue=make([dynamic]GPU_Fence, 0)}
}

gpu_begin_commands :: proc(gpu: ^GPU_Backend) -> GPU_Command_Buffer {
	if gpu.command_open {
		return 0
	}
	gpu.next_command += 1
	if gpu.next_command == 0 { gpu.next_command = 1 }
	gpu.command_open = true
	return gpu.next_command
}

gpu_submit :: proc(gpu: ^GPU_Backend, command: GPU_Command_Buffer) -> GPU_Fence {
	if !gpu.command_open || command == 0 || command != gpu.next_command {
		return 0
	}
	gpu.next_fence += 1
	if gpu.next_fence == 0 { gpu.next_fence = 1 }
	gpu.submitted[gpu.next_fence] = true
	append(&gpu.retirement_queue, gpu.next_fence)
	gpu.command_open = false
	return gpu.next_fence
}

gpu_retire_completed :: proc(gpu: ^GPU_Backend, completed: GPU_Fence) -> int {
	retired: int = 0
	write: int = 0
	for read := 0; read < len(gpu.retirement_queue); read += 1 {
		fence := gpu.retirement_queue[read]
		if fence <= completed && gpu.submitted[fence] {
			delete_key(&gpu.submitted, fence)
			retired += 1
			gpu.resource_retirements += 1
			if fence > gpu.completed_fence { gpu.completed_fence = fence }
		} else {
			gpu.retirement_queue[write] = fence
			write += 1
		}
	}
	for len(gpu.retirement_queue) > write { pop(&gpu.retirement_queue) }
	return retired
}

gpu_replace_resource :: proc(gpu: ^GPU_Backend, in_flight_fence: GPU_Fence) {
	// A resource is queued behind the fence that references it. The backend must
	// not destroy the old resource at node-retirement time.
	gpu.resource_replacements += 1
	if in_flight_fence != 0 && in_flight_fence > gpu.completed_fence {
		gpu.submitted[in_flight_fence] = true
	}
}
