package main

// Native SDL3/SDL_GPU proof path. It renders Alicorn's retained display list
// as rectangles using a 1x1 offscreen texture and GPU blits, and renders text
// commands through the retained Runa glyph pipeline. This exercises real
// swapchain acquisition, ordered render passes, logical-to-physical composition
// and asynchronous resource retirement.
import "core:fmt"
import "core:math"
import "core:os"
import "core:c"
import "core:strings"
import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

RESIZE_STRESS_ITERATIONS :: 300
NATIVE_TEXT_BASE :: "Alicorn retained display list"
NATIVE_TEXT_MUTATED :: "Alicorn retained display list Z"

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

Native_UI_Nodes :: struct {
	field:   alicorn.Node_ID,
	surface: alicorn.Node_ID,
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

sync_text_input_focus :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	active: ^bool,
	owner: ^alicorn.Node_ID,
) {
	desired := rt.focused
	if node, ok := rt.nodes[desired]; !ok || !node.active || node.kind != .Text_Field {
		desired = 0
	}
	if desired != owner^ {
		if active^ {
			// Clear the platform preedit before changing the Alicorn owner;
			// otherwise a late platform event could be applied to the wrong
			// retained field.
			if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed during focus transfer") }
			if !sdl3.StopTextInput(window) { fail("SDL_StopTextInput failed during focus transfer") }
			active^ = false
		}
		owner^ = 0
		if desired != 0 {
			if !sdl3.StartTextInput(window) { fail("SDL_StartTextInput failed for focused text field") }
			active^ = true
			owner^ = desired
		}
	}
	if active^ && owner^ != 0 {
		area, cursor, ok := alicorn.text_field_input_area(rt, owner^)
		if !ok { return }
		width := int(area.w)
		height := int(area.h)
		if width < 1 { width = 1 }
		if height < 1 { height = 1 }
		input_area := sdl3.Rect{
			x=c.int(area.x), y=c.int(area.y), w=c.int(width), h=c.int(height),
		}
		if !sdl3.SetTextInputArea(window, &input_area, c.int(cursor)) {
			fail("SDL_SetTextInputArea failed for focused text field")
		}
	}
}

adopt_text_change :: proc(app_text: ^string, change: alicorn.Text_Change) {
	if change.changed {
		if len(app_text^) > 0 { delete(app_text^) }
		app_text^ = change.text
	} else if len(change.text) > 0 {
		delete(change.text)
	}
}

pump_events :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	metrics: ^Window_Metrics,
	quit_requested: ^bool,
	logical_resize_events, pixel_resize_events, scale_events: ^int,
	text_input_events, composition_events: ^int,
	app_text: ^string,
	manual_log := false,
) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			quit_requested^ = true
		}
		if pointer, ok := pointer_from_sdl(event); ok {
			alicorn.process_pointer(rt, pointer)
		}
		if event.type == .KEY_DOWN && event.key.down {
			modifier_key := false
			switch event.key.key {
			case sdl3.K_LCTRL, sdl3.K_LSHIFT, sdl3.K_LALT, sdl3.K_LGUI,
				sdl3.K_RCTRL, sdl3.K_RSHIFT, sdl3.K_RALT, sdl3.K_RGUI:
				modifier_key = true
			}
			if manual_log && (!event.key.repeat || !modifier_key) {
				composition_active := false
				if node, ok := rt.nodes[rt.focused]; ok {
					composition_active = node.composition.active
				}
				fmt.println("sdl_event", "KEY_DOWN", "key", event.key.key, "repeat", event.key.repeat, "composition_active", composition_active)
			}
			if event.key.key == sdl3.K_ESCAPE {
				if alicorn.cancel_text_composition(rt, rt.focused, "Escape canceled text composition") {
					if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed for Escape") }
				}
			} else if node, ok := rt.nodes[rt.focused]; ok && node.active && node.kind == .Text_Field && !node.composition.active {
				handled := true
				switch event.key.key {
				case sdl3.K_BACKSPACE:
					adopt_text_change(app_text, alicorn.process_text_edit(rt, rt.focused, alicorn.Text_Edit{.Backspace, ""}))
				case sdl3.K_DELETE:
					adopt_text_change(app_text, alicorn.process_text_edit(rt, rt.focused, alicorn.Text_Edit{.Delete, ""}))
				case sdl3.K_LEFT:
					position := alicorn.text_move_logical(node.text, node.caret, -1)
					_ = alicorn.set_text_caret(rt, rt.focused, position.byte)
				case sdl3.K_RIGHT:
					position := alicorn.text_move_logical(node.text, node.caret, 1)
					_ = alicorn.set_text_caret(rt, rt.focused, position.byte)
				case:
					handled = false
				}
				if manual_log && handled {
					fmt.println("alicorn_key_handled", "key", event.key.key, "text", app_text^)
				}
			}
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
			if manual_log {
				raw_text := ""
				if event.text.text != nil { raw_text = string(event.text.text) }
				fmt.println("sdl_event", "TEXT_INPUT", "text", raw_text)
			}
			if event.text.text != nil {
				adopt_text_change(app_text, alicorn.process_text_input(rt, rt.focused, string(event.text.text)))
				if manual_log { fmt.println("alicorn_after_TEXT_INPUT", "text", app_text^) }
			}
		case .TEXT_EDITING:
			composition_events^ += 1
			if manual_log {
				raw_text := ""
				if event.edit.text != nil { raw_text = string(event.edit.text) }
				fmt.println("sdl_event", "TEXT_EDITING", "text", raw_text, "start_chars", event.edit.start, "length_chars", event.edit.length)
			}
			if event.edit.text != nil {
				alicorn.process_text_editing(
					rt,
					rt.focused,
					string(event.edit.text),
					int(event.edit.start),
					int(event.edit.length),
				)
				if manual_log {
					if node, ok := rt.nodes[rt.focused]; ok {
						fmt.println(
							"alicorn_after_TEXT_EDITING",
							"preedit", node.composition.text,
							"selection_bytes", node.composition.selection_start, node.composition.selection_end,
						)
					}
				}
			}
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

render_native_ui :: proc(rt: ^alicorn.Runtime, frame: u64, value := NATIVE_TEXT_BASE) -> Native_UI_Nodes {
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
	surface := alicorn.custom_surface(&ui, "animated-surface", frame, alicorn.Rect{0, 0, 280, 120}, 560, 240, 2, style_source())
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return Native_UI_Nodes{field, surface}
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
	surface_renderer: ^Native_Surface_Renderer,
	display: []alicorn.Display_Command,
	logical_to_pixel_x, logical_to_pixel_y: f32,
	skip_root := false,
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
		if skip_root && draw.kind == .Root { continue }
		if native_text_is_text(draw.kind) {
			if !native_text_render_command(text_renderer, command, draw, swapchain, swap_w, swap_h, logical_to_pixel_x, logical_to_pixel_y) {
				return false
			}
			continue
		}
		if draw.kind == .Custom_Surface {
			if !native_surface_render_command(surface_renderer, command, draw, swapchain, swap_w, swap_h, logical_to_pixel_x, logical_to_pixel_y) {
				return false
			}
			continue
		}
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
			// The destination is a retained display target. Cycling it here
			// would invalidate earlier display-list items, including text.
			cycle = false,
		}
		sdl3.BlitGPUTexture(command, blit)
		index += 1
	}
	return true
}

// Render one retained frame into a software-readable GPU target matching the
// text pipeline's swapchain format. This is a deliberately small visual proof:
// it verifies that glyph coverage lands in
// the expected text bounds and gives us a stable observation point for atlas
// cycling and display-list ordering without depending on a screenshot of a
// window manager surface.
native_text_readback_probe :: proc(
	device: ^sdl3.GPUDevice,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	display: []alicorn.Display_Command,
	width, height: sdl3.Uint32,
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
	temporary := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=.R8G8B8A8_UNORM, usage=sdl3.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET},
		width=1, height=1, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if temporary == nil {
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage=.DOWNLOAD, size=width * height * 4,
	})
	if download == nil {
		sdl3.ReleaseGPUTexture(device, temporary)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil {
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, temporary)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	if !draw_display_list(command, probe_texture, width, height, temporary, text_renderer, surface_renderer, display, 1, 1, false) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, temporary)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil {
		_ = sdl3.CancelGPUCommandBuffer(command)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, temporary)
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
		sdl3.ReleaseGPUTexture(device, temporary)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	fences := [1]^sdl3.GPUFence{fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) {
		sdl3.ReleaseGPUFence(device, fence)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, temporary)
		sdl3.ReleaseGPUTexture(device, probe_texture)
		return false, 0
	}
	mapped := sdl3.MapGPUTransferBuffer(device, download, false)
	if mapped == nil {
		sdl3.ReleaseGPUFence(device, fence)
		sdl3.ReleaseGPUTransferBuffer(device, download)
		sdl3.ReleaseGPUTexture(device, temporary)
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
	sdl3.ReleaseGPUTexture(device, temporary)
	sdl3.ReleaseGPUTexture(device, probe_texture)
	ok = text_found && non_background > 0
	return
}

native_font_path :: proc() -> string {
	when ODIN_OS == .Windows {
		// Segoe UI is a good Latin default but is not a reliable source for
		// Japanese glyphs. Prefer the installed open Noto Sans JP variable font
		// for this native proof; fall back to Segoe UI on minimal Windows images.
		japanese_font := "C:/Windows/Fonts/NotoSansJP-VF.ttf"
		if os.exists(japanese_font) { return japanese_font }
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

fill_surface_samples :: proc(samples: ^[dynamic]f32, phase: f32) {
	for i := 0; i < len(samples^); i += 1 {
		x := f32(i) / f32(len(samples^)-1)
		samples^[i] = 0.5 + 0.30*math.sin(x*18 + phase) + 0.12*math.sin(x*43 - phase*0.7)
	}
}

main :: proc() {
	// SDL video, window, text-input, event polling, and GPU operations all run
	// on this main thread. No background event loop is introduced by the adapter.
	manual_ime := false
	surface_stress := false
	for argument in os.args {
		if argument == "--manual-ime" {
			manual_ime = true
		}
		if argument == "--surface-stress" {
			surface_stress = true
		}
	}
	// Alicorn renders the inline preedit and underline; the operating system
	// continues to own candidate-list presentation.
	if !sdl3.SetHint(sdl3.HINT_IME_IMPLEMENTED_UI, "composition") {
		fail("SDL_IME_IMPLEMENTED_UI hint could not be set")
	}
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
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)})

	font_data, font_err := os.read_entire_file_from_path(native_font_path(), context.allocator)
	if font_err != nil {
		fail("GPU text font could not be loaded from the platform font path")
	}
	if !alicorn.text_engine_load_font(&rt.text_engine, font_data) {
		delete(font_data)
		fail("Runa font initialization failed")
	}
	delete(font_data)
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
	// Establish a deterministic visual proof before the resize stress. The
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
		rt.display[:],
		sdl3.Uint32(metrics.logical_width),
		sdl3.Uint32(metrics.logical_height),
	)
	if !readback_ok {
		fmt.println("GPU text readback probe failed", "non_background", readback_non_background, "display_commands", len(rt.display))
		fail("GPU text offscreen readback found no glyph coverage")
	}

	in_flight := make([dynamic]Native_In_Flight, 0, 3)
	defer delete(in_flight)
	quit_requested := false
	logical_resize_events := 0
	pixel_resize_events := 0
	scale_events := 0
	text_input_events := 0
	composition_events := 0
	app_text, app_text_err := strings.clone(NATIVE_TEXT_BASE)
	if app_text_err != nil { fail("native text state allocation failed") }
	defer { if len(app_text) > 0 { delete(app_text) } }
	text_input_active := false
	text_input_owner: alicorn.Node_ID = 0
	sync_text_input_focus(window, &rt, &text_input_active, &text_input_owner)
	if !text_input_active || !sdl3.TextInputActive(window) {
		fail("focused text field did not activate SDL text input")
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

		sync_text_input_focus(window, &rt, &text_input_active, &text_input_owner)
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
			sync_text_input_focus(window, &rt, &text_input_active, &text_input_owner)
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
		if !draw_display_list(command, swapchain, swap_w, swap_h, temporary, &text_renderer, &surface_renderer, rt.display[:], logical_to_pixel_x, logical_to_pixel_y) {
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
			native_surface_commit_submission(&surface_renderer)
			if surface_stress { alicorn.gpu_surface_frame_consumed(&rt) }
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
		sdl3.ReleaseGPUTexture(device, entry.texture)
		sdl3.ReleaseGPUFence(device, entry.fence)
		retired += 1
	}
	clear(&in_flight)
	if text_input_active {
		if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed during shutdown") }
		if !sdl3.StopTextInput(window) { fail("SDL_StopTextInput failed") }
		text_input_active = false
		text_input_owner = 0
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
