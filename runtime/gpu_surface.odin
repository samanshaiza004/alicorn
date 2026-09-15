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
	for sample in samples {
		append(&node.surface_samples, sample)
	}
	node.surface_revision = revision
	rt.surface_frame_pending = true
	advance_presentation_revision(rt)
	rt.stats.surface_updates += 1
	record_trace_literal(rt, .Invalidation, id, "explicit GPU surface revision update")
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
