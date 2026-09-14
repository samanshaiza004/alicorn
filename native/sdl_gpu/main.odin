package main

// Native SDL3/SDL_GPU proof path. It renders Alicorn's retained display list
// as solid rectangles using a 1x1 offscreen texture and GPU blits. This keeps
// the compositor shader-free while exercising real swapchain acquisition,
// render passes, logical-to-physical composition and asynchronous resource
// retirement.
import "core:fmt"
import "core:os"
import "core:c"
import alicorn "../../runtime"
import "vendor:sdl3"

RESIZE_STRESS_ITERATIONS :: 300

Window_Metrics :: struct {
	logical_width:  int,
	logical_height: int,
	pixel_width:    int,
	pixel_height:   int,
	pixel_density:  f32,
	display_scale:  f32,
}

Native_In_Flight :: struct {
	fence:   ^sdl3.GPUFence,
	texture: ^sdl3.GPUTexture,
}

fail :: proc(message: string) -> ! {
	fmt.println("SDL validation FAILED:", message, "SDL error:", sdl3.GetError())
	os.exit(1)
}

read_window_metrics :: proc(window: ^sdl3.Window, metrics: ^Window_Metrics) -> bool {
	logical_width, logical_height: c.int
	pixel_width, pixel_height: c.int
	if !sdl3.GetWindowSize(window, &logical_width, &logical_height) {
		return false
	}
	if !sdl3.GetWindowSizeInPixels(window, &pixel_width, &pixel_height) {
		return false
	}
	metrics^ = Window_Metrics{
		logical_width = int(logical_width),
		logical_height = int(logical_height),
		pixel_width = int(pixel_width),
		pixel_height = int(pixel_height),
		pixel_density = sdl3.GetWindowPixelDensity(window),
		display_scale = sdl3.GetWindowDisplayScale(window),
	}
	return metrics.logical_width > 0 && metrics.logical_height > 0 &&
		metrics.pixel_width > 0 && metrics.pixel_height > 0 &&
		metrics.pixel_density > 0 && metrics.display_scale > 0
}

print_window_metrics :: proc(label: string, metrics: Window_Metrics) {
	fmt.println(
		"window_metrics", label,
		"logical", metrics.logical_width, "x", metrics.logical_height,
		"pixels", metrics.pixel_width, "x", metrics.pixel_height,
		"pixel_density", metrics.pixel_density,
		"display_scale", metrics.display_scale,
	)
}

pointer_from_sdl :: proc(event: sdl3.Event) -> (value: alicorn.Pointer_Event, ok: bool) {
	// SDL mouse coordinates are window-logical coordinates. They are passed
	// through unchanged; only the compositor converts logical geometry to pixels.
	if event.type == .MOUSE_MOTION {
		return alicorn.Pointer_Event{.Move, event.motion.x, event.motion.y, 0}, true
	}
	if event.type == .MOUSE_BUTTON_DOWN {
		return alicorn.Pointer_Event{.Down, event.button.x, event.button.y, int(event.button.button)}, true
	}
	if event.type == .MOUSE_BUTTON_UP {
		return alicorn.Pointer_Event{.Up, event.button.x, event.button.y, int(event.button.button)}, true
	}
	return alicorn.Pointer_Event{}, false
}

validate_pointer_coordinates :: proc() {
	// This is intentionally a native-adapter regression check: a fractional
	// logical coordinate must reach Alicorn unchanged, with no Retina scaling.
	event := sdl3.Event{}
	event.type = .MOUSE_MOTION
	event.motion.x = 123.25
	event.motion.y = 234.75
	pointer, ok := pointer_from_sdl(event)
	if !ok || pointer.x != event.motion.x || pointer.y != event.motion.y {
		fail("SDL pointer coordinates were scaled or translated before hit testing")
	}
}

logical_to_pixel_bounds :: proc(bounds: alicorn.Rect, scale_x, scale_y: f32) -> (x0, y0, x1, y1: int) {
	x0 = int(bounds.x * scale_x)
	y0 = int(bounds.y * scale_y)
	x1 = int((bounds.x + bounds.w) * scale_x)
	y1 = int((bounds.y + bounds.h) * scale_y)
	return
}

validate_pixel_transform :: proc() {
	// This guards the compositor boundary independently of SDL window state.
	x0, y0, x1, y1 := logical_to_pixel_bounds(alicorn.Rect{10, 20, 100, 50}, 2, 2)
	if x0 != 20 || y0 != 40 || x1 != 220 || y1 != 140 {
		fail("logical compositor bounds did not scale exactly once")
	}
}

pump_events :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	metrics: ^Window_Metrics,
	quit_requested: ^bool,
	logical_resize_events, pixel_resize_events, scale_events: ^int,
	text_input_events, composition_events: ^int,
) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			quit_requested^ = true
		}
		if pointer, ok := pointer_from_sdl(event); ok {
			alicorn.process_pointer(rt, pointer)
		}

		#partial switch event.type {
		case .WINDOW_RESIZED:
			// data1/data2 are logical window coordinates for this event.
			metrics.logical_width = int(event.window.data1)
			metrics.logical_height = int(event.window.data2)
			logical_resize_events^ += 1
			rt.viewport.w = f32(metrics.logical_width)
			rt.viewport.h = f32(metrics.logical_height)
			alicorn.invalidate_root(rt, "SDL logical window size changed")
		case .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_METAL_VIEW_RESIZED:
			// data1/data2 are physical drawable pixels for these events. Do not
			// feed them into the logical layout viewport.
			metrics.pixel_width = int(event.window.data1)
			metrics.pixel_height = int(event.window.data2)
			pixel_resize_events^ += 1
		case .WINDOW_DISPLAY_SCALE_CHANGED:
			scale_events^ += 1
			metrics.pixel_density = sdl3.GetWindowPixelDensity(window)
			metrics.display_scale = sdl3.GetWindowDisplayScale(window)
			alicorn.invalidate_root(rt, "SDL display scale changed")
		case .TEXT_INPUT:
			text_input_events^ += 1
		case .TEXT_EDITING:
			composition_events^ += 1
		}

		if event.type == .WINDOW_RESIZED ||
			event.type == .WINDOW_PIXEL_SIZE_CHANGED ||
			event.type == .WINDOW_METAL_VIEW_RESIZED ||
			event.type == .WINDOW_DISPLAY_SCALE_CHANGED {
			if !read_window_metrics(window, metrics) {
				fail("window metrics became unavailable after a window event")
			}
		}
	}
}

render_native_ui :: proc(rt: ^alicorn.Runtime, frame: u64) {
	alicorn.invalidate_root(rt, "native frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="native-root", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 12, 8, .Stretch, true})
	alicorn.text(&ui, "Alicorn retained display list", style=alicorn.Layout_Style{.Column, -1, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.button(&ui, "GPU frame", style=alicorn.Layout_Style{.Column, 180, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.custom_surface(&ui, "animated-surface", frame, alicorn.Rect{0, 0, 280, 120}, 560, 240, 2, style_source())
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

style_source :: proc() -> alicorn.Source_Site {
	return alicorn.caller_site("custom_surface")
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
	temporary: ^sdl3.GPUTexture,
	text_renderer: ^Native_Text_Renderer,
	display: []alicorn.Display_Command,
	logical_to_pixel_x, logical_to_pixel_y: f32,
) -> bool {
	if !native_text_rebuild_mesh(text_renderer, display, logical_to_pixel_x, logical_to_pixel_y) { return false }
	if !native_text_sync_atlas(text_renderer, command) { return false }
	if !native_text_upload_vertices(text_renderer, command) { return false }
	// The retained display list remains in logical window units. Only this
	// compositor boundary converts its geometry to the physical swapchain.
	background := make_color_target(swapchain, sdl3.FColor{0.035, 0.045, 0.065, 1}, false)
	pass := sdl3.BeginGPURenderPass(command, &background, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)

	index: int = 0
	for draw in display {
		x0, y0, x1, y1 := logical_to_pixel_bounds(draw.bounds, logical_to_pixel_x, logical_to_pixel_y)
		if x0 < 0 { x0 = 0 }
		if y0 < 0 { y0 = 0 }
		if x1 > int(swap_w) { x1 = int(swap_w) }
		if y1 > int(swap_h) { y1 = int(swap_h) }
		if x1 <= x0 || y1 <= y0 { continue }

		color := sdl3.FColor{draw.color.r, draw.color.g, draw.color.b, draw.color.a}
		target := make_color_target(temporary, color, index > 0)
		offscreen_pass := sdl3.BeginGPURenderPass(command, &target, 1, nil)
		if offscreen_pass == nil { return false }
		sdl3.EndGPURenderPass(offscreen_pass)

		blit := sdl3.GPUBlitInfo{
			source = sdl3.GPUBlitRegion{texture=temporary, w=1, h=1},
			destination = sdl3.GPUBlitRegion{texture=swapchain, x=sdl3.Uint32(x0), y=sdl3.Uint32(y0), w=sdl3.Uint32(x1-x0), h=sdl3.Uint32(y1-y0)},
			load_op = .LOAD,
			flip_mode = .NONE,
			filter = .NEAREST,
			cycle = index > 0,
		}
		sdl3.BlitGPUTexture(command, blit)
		index += 1
	}
	if !native_text_render(text_renderer, command, swapchain, swap_w, swap_h) { return false }
	return true
}

native_font_path :: proc() -> string {
	when ODIN_OS == .Windows {
		return "C:/Windows/Fonts/segoeui.ttf"
	} else when ODIN_OS == .Darwin {
		return "/System/Library/Fonts/SFNS.ttf"
	} else {
		return "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
	}
}

wait_and_retire_oldest :: proc(
	device: ^sdl3.GPUDevice,
	in_flight: ^[dynamic]Native_In_Flight,
	query_before_wait_true, query_after_wait_true, wait_count: ^int,
) -> bool {
	if len(in_flight) == 0 { return true }
	old := in_flight[0]
	if sdl3.QueryGPUFence(device, old.fence) {
		query_before_wait_true^ += 1
	}
	fences := [1]^sdl3.GPUFence{old.fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) {
		return false
	}
	wait_count^ += 1
	if sdl3.QueryGPUFence(device, old.fence) {
		query_after_wait_true^ += 1
	}
	// The blocking wait is the authoritative completion point for this known
	// oldest submission. Query behavior is recorded but not required for safe
	// retirement, including SDL backend implementations with unusual query
	// semantics for completed work.
	sdl3.ReleaseGPUTexture(device, old.texture)
	sdl3.ReleaseGPUFence(device, old.fence)
	for i := 1; i < len(in_flight); i += 1 {
		in_flight[i-1] = in_flight[i]
	}
	pop(in_flight)
	return true
}

main :: proc() {
	// SDL video, window, text-input, event polling, and GPU operations all run
	// on this main thread. No background event loop is introduced by the adapter.
	if !sdl3.Init(sdl3.INIT_VIDEO) {
		fail("SDL_Init failed")
	}
	defer sdl3.Quit()

	window := sdl3.CreateWindow(
		"Alicorn SDL_GPU proof",
		640,
		480,
		sdl3.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY},
	)
	if window == nil {
		fail("SDL_CreateWindow failed")
	}
	defer sdl3.DestroyWindow(window)

	metrics: Window_Metrics
	if !read_window_metrics(window, &metrics) {
		fail("initial window metrics are unavailable")
	}
	print_window_metrics("initial", metrics)
	when ODIN_OS == .Darwin {
		if metrics.pixel_density > 1 &&
			(metrics.pixel_width == metrics.logical_width || metrics.pixel_height == metrics.logical_height) {
			fail("high-density macOS window did not expose distinct logical and pixel dimensions")
		}
	}
	validate_pointer_coordinates()
	validate_pixel_transform()

	formats := sdl3.GPUShaderFormat{.SPIRV, .DXIL, .MSL}
	gpu_driver_name: cstring = nil
	when ODIN_OS == .Darwin {
		// Driver policy belongs to this platform adapter, not the retained
		// runtime. Other SDL platforms continue to use their default driver.
		gpu_driver_name = "metal"
	}
	device := sdl3.CreateGPUDevice(formats, false, gpu_driver_name)
	if device == nil {
		fail("SDL_CreateGPUDevice failed")
	}
	defer sdl3.DestroyGPUDevice(device)

	selected_driver := sdl3.GetGPUDeviceDriver(device)
	fmt.println("gpu_driver_requested", gpu_driver_name, "gpu_driver_selected", selected_driver)
	when ODIN_OS == .Darwin {
		if selected_driver == nil || string(selected_driver) != "metal" {
			fail("macOS SDL_GPU did not select the requested Metal driver")
		}
	}

	if !sdl3.ClaimWindowForGPUDevice(device, window) {
		fail("SDL_ClaimWindowForGPUDevice failed")
	}
	defer sdl3.ReleaseWindowFromGPUDevice(device, window)
	if !sdl3.SetGPUAllowedFramesInFlight(device, 3) {
		fail("SDL_SetGPUAllowedFramesInFlight failed")
	}

	font_data, font_err := os.read_entire_file_from_path(native_font_path(), context.allocator)
	if font_err != nil {
		fail("GPU text font could not be loaded from the platform font path")
	}
	text_renderer, text_ok := native_text_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), font_data)
	delete(font_data)
	if !text_ok {
		fail("GPU text pipeline, atlas, or Runa font initialization failed")
	}
	defer native_text_destroy(&text_renderer)

	// SDL text input is opt-in. The input rectangle is in logical window
	// coordinates, never physical pixels.
	input_area := sdl3.Rect{16, 16, 320, 24}
	if !sdl3.StartTextInput(window) {
		fail("SDL_StartTextInput failed")
	}
	if !sdl3.SetTextInputArea(window, &input_area, 0) {
		fail("SDL_SetTextInputArea failed")
	}
	if !sdl3.TextInputActive(window) {
		fail("SDL_TextInputActive returned false after SDL_StartTextInput")
	}

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)})
	in_flight := make([dynamic]Native_In_Flight, 0, 3)
	defer delete(in_flight)
	quit_requested := false
	logical_resize_events := 0
	pixel_resize_events := 0
	scale_events := 0
	text_input_events := 0
	composition_events := 0
	submitted := 0
	retired := 0
	max_in_flight := 0
	query_before_wait_true := 0
	query_after_wait_true := 0
	wait_count := 0

	resize_widths := [3]c.int{801, 1024, 640}
	resize_heights := [3]c.int{601, 768, 480}
	// Submit an initial three-frame burst before any programmatic resize. This
	// proves the configured frames-in-flight retirement path independently of
	// the swapchain invalidation that a resize can trigger.
	// The following 300 iterations then drain before each resize and retire each
	// resized frame before the next resize, matching SDL's swapchain lifecycle.
	for step := -3; step < RESIZE_STRESS_ITERATIONS; step += 1 {
		if step >= 0 {
			for len(in_flight) > 0 {
				if !wait_and_retire_oldest(device, &in_flight, &query_before_wait_true, &query_after_wait_true, &wait_count) {
					fail("SDL_WaitForGPUFences failed before resize")
				}
				retired += 1
			}
			if !sdl3.WaitForGPUIdle(device) {
				fail("SDL_WaitForGPUIdle failed before resize")
			}
			// SDL 3.4.14's Metal swapchain on this host does not reliably
			// expose a new drawable after a programmatic resize while the old
			// claim remains active. Recreate only the SDL window claim at this
			// validation boundary; the Alicorn runtime and GPU device remain
			// alive, and all old resources are already idle.
			sdl3.ReleaseWindowFromGPUDevice(device, window)
			resize_index := step % len(resize_widths)
			if !sdl3.SetWindowSize(window, resize_widths[resize_index], resize_heights[resize_index]) {
				fail("SDL_SetWindowSize failed during resize stress")
			}
			if !sdl3.ClaimWindowForGPUDevice(device, window) {
				fail("SDL_ClaimWindowForGPUDevice failed after resize")
			}
			if !sdl3.SetGPUAllowedFramesInFlight(device, 3) {
				fail("SDL_SetGPUAllowedFramesInFlight failed after resize")
			}
		}

		pump_events(
			window,
			&rt,
			&metrics,
			&quit_requested,
			&logical_resize_events,
			&pixel_resize_events,
			&scale_events,
			&text_input_events,
			&composition_events,
		)
		if quit_requested {
			fail("window close requested during validation")
		}
		if !read_window_metrics(window, &metrics) {
			fail("window metrics became unavailable during resize stress")
		}
		if step == 0 || step == RESIZE_STRESS_ITERATIONS-1 {
			print_window_metrics("resize", metrics)
		}

		render_native_ui(&rt, u64(step+3))
		command := sdl3.AcquireGPUCommandBuffer(device)
		if command == nil {
			fail("SDL_AcquireGPUCommandBuffer failed")
		}
		swapchain: ^sdl3.GPUTexture
		swap_w, swap_h: sdl3.Uint32
		if !sdl3.AcquireGPUSwapchainTexture(command, window, &swapchain, &swap_w, &swap_h) {
			_ = sdl3.CancelGPUCommandBuffer(command)
			fail("SDL_AcquireGPUSwapchainTexture failed")
		}
		if swapchain == nil || swap_w == 0 || swap_h == 0 {
			// SDL documents a nil texture as the normal signal that the
			// swapchain is temporarily unavailable. The oldest in-flight fence
			// has already been retired above. A device-idle drain also flushes
			// the swapchain's presentation bookkeeping on Metal before retrying.
			if !sdl3.WaitForGPUIdle(device) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL_WaitForGPUIdle before swapchain retry failed")
			}
			if !sdl3.AcquireGPUSwapchainTexture(command, window, &swapchain, &swap_w, &swap_h) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL_AcquireGPUSwapchainTexture retry failed")
			}
			if swapchain == nil || swap_w == 0 || swap_h == 0 {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL_AcquireGPUSwapchainTexture retry returned no drawable texture")
			}
		}
		metrics.pixel_width = int(swap_w)
		metrics.pixel_height = int(swap_h)
		logical_to_pixel_x := f32(swap_w) / f32(metrics.logical_width)
		logical_to_pixel_y := f32(swap_h) / f32(metrics.logical_height)
		temporary := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = sdl3.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET},
			width = 1,
			height = 1,
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		})
		if temporary == nil {
			_ = sdl3.CancelGPUCommandBuffer(command)
			fail("SDL_CreateGPUTexture failed")
		}
		if !draw_display_list(command, swapchain, swap_w, swap_h, temporary, &text_renderer, rt.display[:], logical_to_pixel_x, logical_to_pixel_y) {
			sdl3.ReleaseGPUTexture(device, temporary)
			_ = sdl3.CancelGPUCommandBuffer(command)
			fail("Alicorn retained display-list pass failed")
		}
		fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
		if fence == nil {
			sdl3.ReleaseGPUTexture(device, temporary)
			fail("SDL_SubmitGPUCommandBufferAndAcquireFence failed")
		}
		append(&in_flight, Native_In_Flight{fence, temporary})
		native_text_commit_submission(&text_renderer)
		submitted += 1
		rt.stats.gpu_submits += 1
		if len(in_flight) > max_in_flight { max_in_flight = len(in_flight) }
		if step >= 0 {
			if !wait_and_retire_oldest(device, &in_flight, &query_before_wait_true, &query_after_wait_true, &wait_count) {
				fail("SDL_WaitForGPUFences failed after resize")
			}
			retired += 1
		}
	}

	if !sdl3.WaitForGPUIdle(device) {
		fail("SDL_WaitForGPUIdle failed during shutdown validation")
	}
	for entry in in_flight {
		sdl3.ReleaseGPUTexture(device, entry.texture)
		sdl3.ReleaseGPUFence(device, entry.fence)
		retired += 1
	}
	clear(&in_flight)
	if !sdl3.StopTextInput(window) {
		fail("SDL_StopTextInput failed")
	}
	if !sdl3.HideWindow(window) || !sdl3.ShowWindow(window) {
		fail("SDL hide/show window lifecycle failed")
	}

	fmt.println(
		"SDL3/SDL_GPU retained compositor: PASS",
		"resize_iterations", RESIZE_STRESS_ITERATIONS,
		"submissions", submitted,
		"retired", retired,
		"display_commands", len(rt.display),
		"max_frames_in_flight", max_in_flight,
		"fence_waits", wait_count,
		"fence_query_before_wait_true", query_before_wait_true,
		"fence_query_after_wait_true", query_after_wait_true,
		"logical_resize_events", logical_resize_events,
		"pixel_resize_events", pixel_resize_events,
		"scale_events", scale_events,
		"text_input_events", text_input_events,
		"composition_events", composition_events,
		"text_shape_calls", text_renderer.engine.shape_calls,
		"text_run_cache_hits", text_renderer.run_cache_hits,
		"text_run_cache_misses", text_renderer.run_cache_misses,
		"text_glyph_cache_hits", text_renderer.engine.glyph_cache_hits,
		"text_glyph_cache_misses", text_renderer.engine.glyph_cache_misses,
		"text_rasterizations", text_renderer.engine.glyph_rasterizations,
		"text_atlas_pages", len(text_renderer.pages),
		"text_quads", len(text_renderer.draws),
		"text_input_boundary", "start-set-area-active-stop",
		"pointer_adapter", "logical coordinates unchanged",
		"logical_to_physical", "compositor boundary only",
	)
	alicorn.destroy_runtime(&rt)
}
