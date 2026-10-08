package alicorn_sdl_gpu

// SDL_GPU rendering consumes Alicorn's generic retained paint stream through
// contiguous surface batches and text/geometry ordering barriers.

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
		style=alicorn.layout_style(.Column, -1, -1, 0, -1, 0, -1, 0, 12, 8, .Stretch, true),
		color=alicorn.Color{0.04, 0.05, 0.08, 1},
	)
	field := alicorn.text_field(&ui, value, style=alicorn.layout_style(.Column, -1, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false))
	alicorn.button(&ui, "GPU frame", style=alicorn.layout_style(.Column, 180, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false))
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
	display: []alicorn.Paint_Command,
	logical_to_pixel_x, logical_to_pixel_y: f32,
	debug_bounds := false,
	clear_background := true,
	reserve_solid_vertices := 0,
	content_inset_top: f32 = 0,
	native_menu: ^Native_Menu_Runtime = nil,
	scratch_allocator := context.temp_allocator,
) -> bool {
	render_display := display
	chrome: []alicorn.Paint_Command
	when ODIN_OS == .Windows {
		if native_menu != nil {
			chrome = native_menu_overlay_commands(
				native_menu,
				f32(swap_w)/logical_to_pixel_x,
				f32(swap_h)/logical_to_pixel_y,
				scratch_allocator,
			)
		}
	}
	if content_inset_top > 0 || len(chrome) > 0 {
		owned := make([dynamic]alicorn.Paint_Command, 0, len(display)+len(chrome), allocator=scratch_allocator)
		if owned == nil && len(display)+len(chrome) > 0 { return false }
		for original in display {
			draw := original
			if content_inset_top > 0 {
				draw.bounds.y += content_inset_top
				draw.clip.y += content_inset_top
			}
			append(&owned, draw)
		}
		for overlay in chrome { append(&owned, overlay) }
		render_display = owned[:]
	}
	if !native_text_rebuild_mesh(text_renderer, render_display, logical_to_pixel_x, logical_to_pixel_y, scratch_allocator) { return false }
	if !native_text_sync_atlas(text_renderer, command, scratch_allocator) { return false }
	if !native_text_upload_vertices(text_renderer, command) { return false }
	if !native_solid_build(solid_renderer, render_display, logical_to_pixel_x, logical_to_pixel_y, swap_w, swap_h) { return false }
	debug_draw_start := len(solid_renderer.draws)
	if debug_bounds {
		native_solid_append_debug_bounds(solid_renderer, render_display, logical_to_pixel_x, logical_to_pixel_y, swap_w, swap_h)
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
	if clear_background {
		background := make_color_target(swapchain, sdl3.FColor{0.035, 0.045, 0.065, 1}, false)
		pass := sdl3.BeginGPURenderPass(command, &background, 1, nil)
		if pass == nil { return false }
		sdl3.EndGPURenderPass(pass)
	}

	display_index := 0
	for display_index < len(render_display) {
		run_kind, run_end := native_paint_run(render_display, display_index)
		draw := render_display[display_index]
		if run_kind == .Text {
			if !native_text_render_command(text_renderer, command, draw, display_index, swapchain, swap_w, swap_h, logical_to_pixel_x, logical_to_pixel_y) {
				return false
			}
			display_index = run_end
			continue
		}
		if run_kind == .Geometry {
			if !native_surface_render_command(surface_renderer, command, draw, swapchain, swap_w, swap_h, logical_to_pixel_x, logical_to_pixel_y, content_inset_top=content_inset_top) {
				return false
			}
			display_index = run_end
			continue
		}
		if !native_solid_render_batch(solid_renderer, command, swapchain, swap_w, swap_h, solid_renderer.draws[display_index:run_end]) {
			return false
		}
		display_index = run_end
	}
	if debug_bounds && len(solid_renderer.draws) > debug_draw_start {
		if !native_solid_render_batch(solid_renderer, command, swapchain, swap_w, swap_h, solid_renderer.draws[debug_draw_start:]) {
			return false
		}
	}
	return true
}

Native_Paint_Run_Kind :: enum { Surface, Text, Geometry }

// Only neighboring surface primitives batch together. Text and geometry each
// remain barriers, preserving exact heterogeneous retained paint order.
native_paint_run :: proc(display: []alicorn.Paint_Command, start: int) -> (kind: Native_Paint_Run_Kind, end: int) {
	if start < 0 || start >= len(display) { return .Surface, len(display) }
	if alicorn.paint_command_is_text(display[start]) { return .Text, start+1 }
	if alicorn.paint_command_is_geometry(display[start]) { return .Geometry, start+1 }
	kind = .Surface
	end = start+1
	for end < len(display) {
		if alicorn.paint_command_is_text(display[end]) || alicorn.paint_command_is_geometry(display[end]) { break }
		end += 1
	}
	return
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
