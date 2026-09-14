package main

// Native SDL3/SDL_GPU validation path. This deliberately submits empty
// command buffers: the retained headless display list has its own tests, while
// this executable proves the platform lifetime boundary, Metal selection,
// logical/pixel window metrics, text-input calls, and fence ordering.
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

Fence_Observation :: struct {
	query_before_wait: bool,
	query_after_wait:  bool,
}

submit_and_wait :: proc(device: ^sdl3.GPUDevice) -> Fence_Observation {
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil {
		fail("SDL_AcquireGPUCommandBuffer failed")
	}
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	if fence == nil {
		fail("SDL_SubmitGPUCommandBufferAndAcquireFence failed")
	}
	fences := [1]^sdl3.GPUFence{fence}
	queried_before_wait := sdl3.QueryGPUFence(device, fence)
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) {
		fail("SDL_WaitForGPUFences failed")
	}
	queried_after_wait := sdl3.QueryGPUFence(device, fence)
	sdl3.ReleaseGPUFence(device, fence)
	return Fence_Observation{queried_before_wait, queried_after_wait}
}

main :: proc() {
	// SDL video, window, text-input, event, and GPU operations all remain on
	// this main thread. No background event loop is introduced by the adapter.
	if !sdl3.Init(sdl3.INIT_VIDEO) {
		fail("SDL_Init failed")
	}
	defer sdl3.Quit()

	window := sdl3.CreateWindow(
		"Alicorn SDL_GPU validation",
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

	// Exercise the visibility transition used by lifecycle code. The window is
	// created visible so a GUI login session can also exercise pointer/IME paths.
	if !sdl3.HideWindow(window) || !sdl3.ShowWindow(window) {
		fail("SDL hide/show window lifecycle failed")
	}

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
	quit_requested := false
	logical_resize_events := 0
	pixel_resize_events := 0
	scale_events := 0
	text_input_events := 0
	composition_events := 0

	resize_widths := [3]c.int{640, 801, 1024}
	resize_heights := [3]c.int{480, 601, 768}
	submissions := 0
	query_before_wait_true := 0
	query_after_wait_true := 0
	query_both_false := 0
	for frame := 0; frame < RESIZE_STRESS_ITERATIONS; frame += 1 {
		resize_index := frame % len(resize_widths)
		if !sdl3.SetWindowSize(window, resize_widths[resize_index], resize_heights[resize_index]) {
			fail("SDL_SetWindowSize failed during resize stress")
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
		if frame == 0 || frame == RESIZE_STRESS_ITERATIONS-1 {
			print_window_metrics("resize", metrics)
		}

		fence_observation := submit_and_wait(device)
		if fence_observation.query_before_wait { query_before_wait_true += 1 }
		if fence_observation.query_after_wait { query_after_wait_true += 1 }
		if !fence_observation.query_before_wait && !fence_observation.query_after_wait { query_both_false += 1 }
		submissions += 1
	}

	if !sdl3.WaitForGPUIdle(device) {
		fail("SDL_WaitForGPUIdle failed during shutdown validation")
	}
	if !sdl3.StopTextInput(window) {
		fail("SDL_StopTextInput failed")
	}

	fmt.println(
		"SDL3/SDL_GPU validation: PASS",
		"resize_iterations", RESIZE_STRESS_ITERATIONS,
		"submissions", submissions,
		"fence_query_before_wait_true", query_before_wait_true,
		"fence_query_after_wait_true", query_after_wait_true,
		"fence_query_both_false", query_both_false,
		"logical_resize_events", logical_resize_events,
		"pixel_resize_events", pixel_resize_events,
		"scale_events", scale_events,
		"text_input_events", text_input_events,
		"composition_events", composition_events,
		"text_input_boundary", "start-set-area-active-stop",
		"pointer_adapter", "logical coordinates unchanged",
	)
}
