package alicorn_sdl_gpu

// SDL_GPU rendering composes Alicorn's retained display list through persistent
// solid batches and the retained Runa glyph pipeline.

import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

#assert(offset_of(Native_Text_Vertex, position) == 0)
#assert(offset_of(Native_Text_Vertex, color) == size_of([3]f32))
#assert(offset_of(Native_Text_Vertex, uv) == size_of([3]f32) + size_of([4]f32))
#assert(size_of(Native_Text_Vertex) == size_of([9]f32))
#assert(size_of(Native_Text_Uniforms) == size_of([32]f32))

Native_In_Flight :: struct {
	fence: ^sdl3.GPUFence,
}

Native_UI_Nodes :: struct {
	field:   alicorn.Node_ID,
	surface: alicorn.Node_ID,
}

render_native_ui :: proc(rt: ^alicorn.Runtime, value := NATIVE_TEXT_BASE) -> Native_UI_Nodes {
	alicorn.invalidate_root(rt, "native frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return Native_UI_Nodes{} }
	alicorn.container_begin(
		&ui,
		.Root,
		label="native-root",
		style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 12, 8, .Stretch, true},
		color=alicorn.Color{0.04, 0.05, 0.08, 1},
	)
	field := alicorn.text_field(&ui, value, style=alicorn.Layout_Style{.Column, -1, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.button(&ui, "GPU frame", style=alicorn.Layout_Style{.Column, 180, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	surface := alicorn.custom_surface(&ui, "animated-surface", alicorn.Rect{0, 0, 280, 120}, 560, 240, 2)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return Native_UI_Nodes{field, surface}
}

make_color_target :: proc(texture: ^sdl3.GPUTexture, color: sdl3.FColor, cycle: bool) -> sdl3.GPUColorTargetInfo {
	return sdl3.GPUColorTargetInfo{
		texture = texture,
		clear_color = color,
		load_op = .CLEAR,
		store_op = .STORE,
		cycle = cycle,
	}
}

draw_display_list :: proc(
	command: ^sdl3.GPUCommandBuffer,
	swapchain: ^sdl3.GPUTexture,
	swap_w, swap_h: sdl3.Uint32,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	display: []alicorn.Display_Command,
	logical_to_pixel_x, logical_to_pixel_y: f32,
	skip_root := false,
	debug_bounds := false,
	reserve_solid_vertices := 0,
	scratch_allocator := context.temp_allocator,
) -> bool {
	solid_renderer.runtime = text_renderer.runtime
	if !native_text_rebuild_mesh(text_renderer, display, logical_to_pixel_x, logical_to_pixel_y, scratch_allocator) { return false }
	if !native_text_sync_atlas(text_renderer, command, scratch_allocator) { return false }
	if !native_text_upload_vertices(text_renderer, command) { return false }
	if !native_solid_build(solid_renderer, display, logical_to_pixel_x, logical_to_pixel_y, swap_w, swap_h, skip_root) { return false }
	debug_draw_start := len(solid_renderer.draws)
	if debug_bounds {
		native_solid_append_debug_bounds(solid_renderer, display, logical_to_pixel_x, logical_to_pixel_y, swap_w, swap_h, skip_root)
	}
	// Optional host overlays (currently the DevTools HUD) append to this mesh
	// after app draws are recorded. Reserve their bounded space now, before any
	// current-command draw can retain the existing GPU buffer.
	if reserve_solid_vertices > 0 {
		_ = native_solid_ensure_vertex_capacity(solid_renderer, len(solid_renderer.vertices)+reserve_solid_vertices)
	}
	if len(solid_renderer.vertices) > 0 {
		if !native_solid_prepare_white_texture(solid_renderer, command) { return false }
		if !native_solid_upload(solid_renderer, command) { return false }
	}
	// The retained display list remains in logical window units. Only this
	// compositor boundary converts its geometry to the physical swapchain.
	background := make_color_target(swapchain, sdl3.FColor{0.035, 0.045, 0.065, 1}, false)
	pass := sdl3.BeginGPURenderPass(command, &background, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)

	display_index := 0
	for display_index < len(display) {
		draw := display[display_index]
		if native_text_is_text(draw.kind) {
			if !native_text_render_command(text_renderer, command, draw, swapchain, swap_w, swap_h, logical_to_pixel_x, logical_to_pixel_y) {
				return false
			}
			display_index += 1
			continue
		}
		if draw.kind == .Custom_Surface {
			if !native_surface_render_command(surface_renderer, command, draw, swapchain, swap_w, swap_h, logical_to_pixel_x, logical_to_pixel_y) {
				return false
			}
			display_index += 1
			continue
		}
		batch_start := display_index
		for display_index < len(display) {
			batch_draw := display[display_index]
			if native_text_is_text(batch_draw.kind) || batch_draw.kind == .Custom_Surface { break }
			display_index += 1
		}
		if !native_solid_render_batch(solid_renderer, command, swapchain, swap_w, swap_h, solid_renderer.draws[batch_start:display_index]) {
			return false
		}
	}
	if debug_bounds && len(solid_renderer.draws) > debug_draw_start {
		if !native_solid_render_batch(solid_renderer, command, swapchain, swap_w, swap_h, solid_renderer.draws[debug_draw_start:]) {
			return false
		}
	}
	return true
}

wait_and_retire_oldest :: proc(
	device: ^sdl3.GPUDevice,
	in_flight: ^[dynamic; 3]Native_In_Flight,
	query_before_wait_true, query_after_wait_true, wait_count: ^int,
	timing: ^Native_Host_Timing = nil,
) -> bool {
	if len(in_flight) == 0 { return true }
	old := in_flight[0]
	if sdl3.QueryGPUFence(device, old.fence) {
		query_before_wait_true^ += 1
	}
	fences := [1]^sdl3.GPUFence{old.fence}
	wait_start := time.now()
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) {
		if timing != nil {
			native_timing_accumulate(&timing.fence_wait_ns, &timing.fence_wait_max_ns, u64(time.duration_nanoseconds(time.since(wait_start))) )
		}
		return false
	}
	if timing != nil {
		native_timing_accumulate(&timing.fence_wait_ns, &timing.fence_wait_max_ns, u64(time.duration_nanoseconds(time.since(wait_start))) )
		timing.fence_waits += 1
	}
	wait_count^ += 1
	if sdl3.QueryGPUFence(device, old.fence) {
		query_after_wait_true^ += 1
	}
	// The blocking wait is the authoritative completion point for this known
	// oldest submission. Query behavior is recorded but not required for safe
	// retirement, including SDL backend implementations with unusual query
	// semantics for completed work.
	sdl3.ReleaseGPUFence(device, old.fence)
	for i := 1; i < len(in_flight); i += 1 {
		in_flight[i-1] = in_flight[i]
	}
	pop(in_flight)
	return true
}
