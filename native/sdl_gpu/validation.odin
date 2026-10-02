package alicorn_sdl_gpu

import "core:fmt"
import "core:math"
import "core:os"
import "base:runtime"
import "core:c"
import "core:strings"
import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

RESIZE_STRESS_ITERATIONS :: 300

NATIVE_TEXT_BASE :: "Alicorn retained display list"

NATIVE_TEXT_MUTATED :: "Alicorn retained display list Z"

validate_pointer_coordinates :: proc() {
	// This is intentionally a native-adapter regression check: a fractional
	// logical coordinate must reach Alicorn unchanged, with no Retina scaling.
	event := sdl3.Event{}
	event.type = .MOUSE_MOTION
	event.motion.x = 123.25
	event.motion.y = 234.75
	pointer, ok := pointer_from_sdl_with_modifiers(event, {})
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

validate_text_pixel_snapping :: proc() {
	// Keep the raster phase in the glyph bitmap while the sampled quad starts
	// on an integer physical pixel. These boundaries also guard carry from the
	// fourth quarter-pixel bucket into the next pixel.
	fractions := [4]f32{0.12, 0.26, 0.51, 0.76}
	for fractional, expected_bucket in fractions {
		pixel_x, bucket := native_text_snap_x(10 + fractional)
		if pixel_x != 10 || bucket != u8(expected_bucket) {
			fail("text X phase was not quantized to the expected Runa bucket")
		}
	}
	pixel_x, bucket := native_text_snap_x(10.90)
	if pixel_x != 11 || bucket != 0 {
		fail("text X phase did not carry the rounded fourth bucket")
	}
	if native_text_snap_y(20.49) != 20 || native_text_snap_y(20.50) != 21 {
		fail("text Y origin was not snapped to physical pixels")
	}
}

// Render one retained frame into a software-readable GPU target matching the
// text pipeline's swapchain format. This is a small deterministic visual validation:
// it verifies that glyph coverage lands in
// the expected text bounds and gives us a stable observation point for atlas
// cycling and display-list ordering without depending on a screenshot of a
// window manager surface.
native_text_readback_probe :: proc(
	device: ^sdl3.GPUDevice,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	display: []alicorn.Display_Command,
	width, height: sdl3.Uint32,
	scratch_allocator := context.temp_allocator,
) -> (ok: bool, non_background: int) {
	if width == 0 || height == 0 { return false, 0 }
	if !sdl3.GPUTextureSupportsFormat(device, text_renderer.swapchain_format, .D2, sdl3.GPUTextureUsageFlags{.COLOR_TARGET}) {
		return false, 0
	}
	probe_texture := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=text_renderer.swapchain_format, usage=sdl3.GPUTextureUsageFlags{.COLOR_TARGET},
		width=width, height=height, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if probe_texture == nil { return false, 0 }
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage=.DOWNLOAD, size=width * height * 4,
	})
	if download == nil {
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil {
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	if !draw_display_list(command, probe_texture, width, height, text_renderer, surface_renderer, solid_renderer, display, 1, 1, false, scratch_allocator=scratch_allocator) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil {
		_ = sdl3.CancelGPUCommandBuffer(command)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	source := sdl3.GPUTextureRegion{texture=probe_texture, mip_level=0, layer=0, x=0, y=0, z=0, w=width, h=height, d=1}
	destination := sdl3.GPUTextureTransferInfo{transfer_buffer=download, offset=0, pixels_per_row=width, rows_per_layer=height}
	sdl3.DownloadFromGPUTexture(copy_pass, source, destination)
	sdl3.EndGPUCopyPass(copy_pass)
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	if fence == nil {
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	fences := [1]^sdl3.GPUFence{fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) {
		sdl3.ReleaseGPUFence(device, fence)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	mapped := sdl3.MapGPUTransferBuffer(device, download, false)
	if mapped == nil {
		sdl3.ReleaseGPUFence(device, fence)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	text_bounds: alicorn.Rect
	text_found := false
	for draw in display {
		if native_text_is_text(draw.kind) {
			text_bounds = draw.bounds
			text_found = true
			break
		}
	}
	if text_found {
		x0, y0, x1, y1 := logical_to_pixel_bounds(text_bounds, 1, 1)
		if x0 < 0 { x0 = 0 }
		if y0 < 0 { y0 = 0 }
		if x1 > int(width) { x1 = int(width) }
		if y1 > int(height) { y1 = int(height) }
		pixels := cast([^]u8)mapped
		for y in y0..<y1 {
			for x in x0..<x1 {
				index := (y * int(width) + x) * 4
				if pixels[index+0] > 50 || pixels[index+1] > 50 || pixels[index+2] > 50 {
					non_background += 1
				}
			}
		}
	}
	sdl3.UnmapGPUTransferBuffer(device, download)
	native_text_commit_submission(text_renderer)
	native_surface_commit_submission(surface_renderer)
	sdl3.ReleaseGPUFence(device, fence)
	sdl3.ReleaseGPUTransferBuffer(device, download)
	sdl3.ReleaseGPUTexture(device, probe_texture)
	ok = text_found && non_background > 0
	return
}

fill_surface_samples :: proc(samples: ^[dynamic]f32, phase: f32) {
	for i := 0; i < len(samples^); i += 1 {
		x := f32(i) / f32(len(samples^)-1)
		samples^[i] = 0.5 + 0.30*math.sin(x*18 + phase) + 0.12*math.sin(x*43 - phase*0.7)
	}
}

Native_Validation_Result :: struct {
	ok: bool,
	failure: string,
}

native_validation_failed :: proc(loc := #caller_location) -> Native_Validation_Result {
	return Native_Validation_Result{
		ok=false,
		failure=fmt.tprintf("%s:%d:%d", loc.file_path, loc.line, loc.column),
	}
}

RunFoundation :: proc() {
	// SDL video, window, text-input, event polling, and GPU operations all run
	// on this main thread. No background event loop is introduced by the adapter.
	manual_ime := false
	surface_stress := false
	surface_geometry_test := false
	text_input_contract_test := false
	for argument in os.args {
		if argument == "--manual-ime" {
			manual_ime = true
		}
		if argument == "--surface-stress" {
			surface_stress = true
		}
		if argument == "--surface-geometry-test" {
			surface_geometry_test = true
		}
		if argument == "--text-input-contract-test" {
			text_input_contract_test = true
		}
	}
	if text_input_contract_test {
		paint_result := native_text_paint_span_contract_test()
		if !paint_result.ok { fail(fmt.tprintf("native text paint-span contract failed at %s", paint_result.failure)) }
		input_result := native_generic_text_input_contract_test()
		if !input_result.ok { fail(fmt.tprintf("generic text-input host contract failed at %s", input_result.failure)) }
		navigation_result := native_generic_text_navigation_contract_test()
		if !navigation_result.ok { fail(fmt.tprintf("generic text-navigation host contract failed at %s", navigation_result.failure)) }
		fmt.println("Alicorn generic text-input/navigation/paint-span host contract: PASS")
		return
	}
	if surface_geometry_test {
		surface_result := native_surface_geometry_self_test()
		if !surface_result.ok { fail(fmt.tprintf("native GPU surface geometry test failed at %s", surface_result.failure)) }
		fmt.println("Alicorn SDL_GPU surface geometry tests: PASS")
		return
	}
	// Alicorn renders the inline preedit and underline; the operating system
	// continues to own candidate-list presentation.
	if !sdl3.SetHint(sdl3.HINT_IME_IMPLEMENTED_UI, "composition") {
		fail("SDL_IME_IMPLEMENTED_UI hint could not be set")
	}
	configure_platform_activation()
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
	if !sdl3.RaiseWindow(window) {
		fail("SDL_RaiseWindow failed")
	}

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
	validate_text_pixel_snapping()

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
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)})
	host_scratch := native_host_scratch_make()
	defer native_host_scratch_destroy(&host_scratch)

	if !native_load_default_fonts(&rt) {
		fail("GPU bundled Runa fonts could not be initialized")
	}
	text_renderer, text_ok := native_text_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !text_ok {
		fail("GPU text pipeline or atlas initialization failed")
	}
	defer native_text_destroy(&text_renderer)
	surface_renderer, surface_ok := native_surface_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !surface_ok {
		fail("GPU surface pipeline initialization failed")
	}
	defer native_surface_destroy(&surface_renderer)
	solid_renderer, solid_ok := native_solid_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window))
	if !solid_ok { fail("GPU solid rectangle pipeline initialization failed") }
	defer native_solid_destroy(&solid_renderer)
	// Establish a deterministic visual validation before the resize stress. The
	// runtime display is rendered into an offscreen RGBA8 target, downloaded
	// only after its submission fence signals, and checked inside the text
	// bounds.
	nodes := render_native_ui(&rt, 0)
	field := nodes.field
	alicorn.focus(&rt, field)
	render_native_ui(&rt, 0)
	readback_ok, readback_non_background := native_text_readback_probe(
		device,
		&text_renderer,
		&surface_renderer,
		&solid_renderer,
		rt.display[:],
		sdl3.Uint32(metrics.logical_width),
		sdl3.Uint32(metrics.logical_height),
		scratch_allocator=host_scratch.allocator,
	)
	if !readback_ok {
		fmt.println("GPU text readback probe failed", "non_background", readback_non_background, "display_commands", len(rt.display))
		fail("GPU text offscreen readback found no glyph coverage")
	}

	in_flight: [dynamic; 3]Native_In_Flight
	quit_requested := false
	logical_resize_events := 0
	pixel_resize_events := 0
	scale_events := 0
	text_input_events := 0
	composition_events := 0
	app_text, app_text_err := strings.clone(NATIVE_TEXT_BASE)
	if app_text_err != nil { fail("native text state allocation failed") }
	defer { if len(app_text) > 0 { delete(app_text) } }
	window_flags := sdl3.GetWindowFlags(window)
	text_input_state := Native_Text_Input_State{window_focused=(window_flags & sdl3.WindowFlags{.INPUT_FOCUS}) != sdl3.WindowFlags{}}
	sync_text_input_focus(window, &rt, &text_input_state)
	if !text_input_state.active {
		fmt.println("Waiting up to 5 seconds for window focus before text-input validation; click the Alicorn SDL_GPU validation window if needed")
	}
	focus_wait_start := time.now()
	for !text_input_state.active && !quit_requested &&
		time.duration_nanoseconds(time.since(focus_wait_start)) < 5_000_000_000 {
		pump_events(
			window, &rt, &metrics, &quit_requested,
			&logical_resize_events, &pixel_resize_events, &scale_events,
			&text_input_events, &composition_events, &app_text,
			text_input_state=&text_input_state,
		)
		window_flags = sdl3.GetWindowFlags(window)
		has_input_focus := (window_flags & sdl3.WindowFlags{.INPUT_FOCUS}) != sdl3.WindowFlags{}
		if has_input_focus {
			text_input_state.window_focused = true
			sync_text_input_focus(window, &rt, &text_input_state)
		}
		if !text_input_state.active { sdl3.Delay(16) }
	}
	if !text_input_state.active || !sdl3.TextInputActive(window) {
		when ODIN_OS == .Darwin {
			focus := darwin_focus_state(window)
			fmt.println(
				"native_text_input_focus",
				"app_active", focus.app_active,
				"key_window", focus.key_window,
				"sdl_input_focus", focus.input_focus,
				"runtime_focus", rt.focused,
				"field", field,
			)
		}
		fail("focused text field did not activate SDL text input after waiting for window focus")
	}
	// Feed one deterministic pair through SDL's own event queue. This is not
	// a substitute for manual OS-IME validation, but it proves the native
	// adapter consumes the real SDL_TEXT_EDITING/TEXT_INPUT union fields,
	// copies their strings into runtime-owned state, and commits only on the
	// committed event.
	preedit_event := sdl3.Event{type=.TEXT_EDITING}
	preedit_event.edit.text = "かな"
	preedit_event.edit.start = 1
	preedit_event.edit.length = 1
	if !sdl3.PushEvent(&preedit_event) { fail("SDL_PushEvent failed for text-editing probe") }
	pump_events(
		window, &rt, &metrics, &quit_requested,
		&logical_resize_events, &pixel_resize_events, &scale_events,
		&text_input_events, &composition_events, &app_text,
		text_input_state=&text_input_state,
	)
	if rt.nodes[field].text != NATIVE_TEXT_BASE || !rt.nodes[field].composition.active {
		fail("SDL text-editing probe mutated committed text or failed to retain preedit")
	}
	render_native_ui(&rt, 0, app_text)
	composition_command_found := false
	for command in rt.display {
		if command.kind == .Text_Composition { composition_command_found = true; break }
	}
	if !composition_command_found { fail("SDL text-editing probe did not produce a composition display command") }
	commit_event := sdl3.Event{type=.TEXT_INPUT}
	commit_event.text.text = "世界"
	if !sdl3.PushEvent(&commit_event) { fail("SDL_PushEvent failed for text-input probe") }
	pump_events(
		window, &rt, &metrics, &quit_requested,
		&logical_resize_events, &pixel_resize_events, &scale_events,
		&text_input_events, &composition_events, &app_text,
		text_input_state=&text_input_state,
	)
	expected_probe_text := fmt.tprintf("%s%s", NATIVE_TEXT_BASE, "世界")
	if app_text != expected_probe_text || rt.nodes[field].composition.active {
		fail("SDL text-input probe failed to commit and clear preedit")
	}
	if manual_ime {
		fmt.println("manual_ime_mode", "focus the text field, activate Microsoft Japanese IME or Microsoft Pinyin, type a composition, and close the window when finished")
	}
	submitted := 0
	retired := 0
	max_in_flight := 0
	query_before_wait_true := 0
	query_after_wait_true := 0
	wait_count := 0

	resize_widths := [3]c.int{801, 1024, 640}
	resize_heights := [3]c.int{601, 768, 480}
	frame_limit: int = RESIZE_STRESS_ITERATIONS
	if manual_ime {
		// Five minutes at the manual fixture's 60 Hz pacing is enough for a
		// real-OS IME check while keeping accidental unattended runs bounded.
		frame_limit = 18_000
	}
	if surface_stress {
		// 120 Hz for ten seconds. The surface revision path is exercised while
		// the ordinary procedural description is intentionally left asleep.
		frame_limit = 1_200
	}
	surface_samples := make([dynamic]f32, 0, 512)
	defer delete(surface_samples)
	for i := 0; i < 512; i += 1 { append(&surface_samples, 0) }
	if surface_stress && rt.invalidated {
		// Settle the deterministic input probe before measuring surface-only
		// frames. The following counter window starts after this one ordinary
		// application description has been adopted.
		nodes = render_native_ui(&rt, 0, app_text)
	}
	ordinary_before_surface := rt.stats
	surface_encodes_before := surface_renderer.encodes
	surface_uploads_before := surface_renderer.vertex_uploads
	surface_start := time.now()
	// Submit an initial three-frame burst before any programmatic resize. This
	// proves the configured frames-in-flight retirement path independently of
	// the swapchain invalidation that a resize can trigger.
	// The first burst also changes the text after the first submission, so a new
	// glyph is rasterized and uploaded while the old text submission is allowed
	// to remain in flight. The conservative full-page upload policy is exercised
	// by that mutation.
	// The following 300 iterations then drain before each resize and retire each
	// resized frame before the next resize, matching SDL's swapchain lifecycle.
	for step := -3; step < frame_limit; step += 1 {
		native_host_scratch_reset(&host_scratch)
		if step >= 0 && !manual_ime && !surface_stress {
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
			&app_text,
			manual_log=manual_ime,
			text_input_state=&text_input_state,
		)
		if quit_requested {
			if manual_ime {
				break
			}
			fail("window close requested during validation")
		}
		if !read_window_metrics(window, &metrics) {
			fail("window metrics became unavailable during resize stress")
		}
		if step == 0 || step == RESIZE_STRESS_ITERATIONS-1 {
			print_window_metrics("resize", metrics)
		}

		sync_text_input_focus(window, &rt, &text_input_state)
		if surface_stress && step >= 0 {
			if step == 0 && len(in_flight) >= 3 {
				if !wait_and_retire_oldest(device, &in_flight, &query_before_wait_true, &query_after_wait_true, &wait_count) {
					fail("SDL_WaitForGPUFences failed before surface stress")
				}
				retired += 1
			}
			fill_surface_samples(&surface_samples, f32(step) * 0.08)
			if !alicorn.gpu_surface_update(&rt, nodes.surface, u64(step+1), surface_samples[:]) {
				fail("explicit GPU surface update failed during surface stress")
			}
		}
		// Preserve the fixture's second-frame atlas mutation without replacing
		// text that a real SDL_TEXT_INPUT event has already committed.
		if !manual_ime && step == -2 && text_input_events == 0 && composition_events == 0 {
			if len(app_text) > 0 { delete(app_text) }
			app_text, app_text_err = strings.clone(NATIVE_TEXT_MUTATED)
			if app_text_err != nil { fail("native text mutation allocation failed") }
		}
		should_submit := !manual_ime || rt.invalidated
		if surface_stress && step >= 0 {
			should_submit = rt.invalidated || alicorn.gpu_surface_needs_frame(&rt)
		}
		if surface_stress && step < 0 {
			// Pre-fill the three SDL frames-in-flight using the already retained
			// display list. This proves submission depth without re-running the
			// procedural application description.
			should_submit = true
		}
		if should_submit {
			text_value := app_text
			frame := u64(step+3)
			if manual_ime || surface_stress { frame = 0 }
			if rt.invalidated {
				nodes = render_native_ui(&rt, frame, text_value)
			}
			sync_text_input_focus(window, &rt, &text_input_state)
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
		if !draw_display_list(command, swapchain, swap_w, swap_h, &text_renderer, &surface_renderer, &solid_renderer, rt.display[:], logical_to_pixel_x, logical_to_pixel_y, scratch_allocator=host_scratch.allocator) {
			_ = sdl3.CancelGPUCommandBuffer(command)
			fail("Alicorn retained display-list pass failed")
		}
		fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
		if fence == nil {
			fail("SDL_SubmitGPUCommandBufferAndAcquireFence failed")
		}
		append(&in_flight, Native_In_Flight{fence})
			native_text_commit_submission(&text_renderer)
			native_surface_commit_submission(&surface_renderer)
			if surface_stress { alicorn.gpu_surface_frame_consumed(&rt) }
			alicorn.frame_submission_succeeded(&rt)
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
		if manual_ime {
			sdl3.Delay(16)
		}
		if surface_stress && step >= 0 {
			sdl3.Delay(8)
		}
	}

	if !sdl3.WaitForGPUIdle(device) {
		fail("SDL_WaitForGPUIdle failed during shutdown validation")
	}
	for entry in in_flight {
		sdl3.ReleaseGPUFence(device, entry.fence)
		retired += 1
	}
	clear(&in_flight)
	if text_input_state.active {
		if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed during shutdown") }
		if !sdl3.StopTextInput(window) { fail("SDL_StopTextInput failed") }
		text_input_state.active = false
		text_input_state.owner = 0
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
		"text_shape_calls", rt.text_engine.shape_calls,
		"text_glyph_cache_hits", rt.text_engine.glyph_cache_hits,
		"text_glyph_cache_misses", rt.text_engine.glyph_cache_misses,
		"text_rasterizations", rt.text_engine.glyph_rasterizations,
		"text_atlas_pages", len(text_renderer.pages),
		"text_quads", len(text_renderer.draws),
		"text_atlas_full_page_uploads", text_renderer.atlas_uploads,
		"text_atlas_upload_bytes", text_renderer.atlas_upload_bytes,
		"text_readback_non_background", readback_non_background,
		"text_input_boundary", "focus-start-caret-area-stop",
		"pointer_adapter", "logical coordinates unchanged",
		"logical_to_physical", "compositor boundary only",
	)
	if surface_stress {
		surface_elapsed_ns := time.duration_nanoseconds(time.since(surface_start))
		fmt.println(
			"surface_stress", "frames", frame_limit,
			"wall_ns", surface_elapsed_ns,
			"surface_updates", rt.stats.surface_updates-ordinary_before_surface.surface_updates,
			"surface_frames_consumed", rt.stats.surface_frames_consumed-ordinary_before_surface.surface_frames_consumed,
			"surface_encodes", surface_renderer.encodes-surface_encodes_before,
			"surface_vertex_uploads", surface_renderer.vertex_uploads-surface_uploads_before,
			"surface_resource_creations", surface_renderer.resource_creations,
			"ordinary_descriptions", rt.stats.descriptions_emitted-ordinary_before_surface.descriptions_emitted,
			"ordinary_reconcile_visits", rt.stats.reconcile_nodes_visited-ordinary_before_surface.reconcile_nodes_visited,
			"ordinary_layout_visits", rt.stats.layout_nodes_visited-ordinary_before_surface.layout_nodes_visited,
			"ordinary_paint_visits", rt.stats.paint_nodes_visited-ordinary_before_surface.paint_nodes_visited,
			"ordinary_composition_visits", rt.stats.composition_nodes_visited-ordinary_before_surface.composition_nodes_visited,
			"max_frames_in_flight", max_in_flight,
		)
	}
	alicorn.destroy_runtime(&rt)
}
