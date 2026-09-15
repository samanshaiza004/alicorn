package alicorn_sdl_gpu

// Native SDL3/SDL_GPU proof path. It renders Alicorn's retained display list
// with persistent solid-quad batches and renders text
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
	fence: ^sdl3.GPUFence,
}

#assert(offset_of(Native_Text_Vertex, position) == 0)
#assert(offset_of(Native_Text_Vertex, color) == size_of([3]f32))
#assert(offset_of(Native_Text_Vertex, uv) == size_of([3]f32) + size_of([4]f32))
#assert(size_of(Native_Text_Vertex) == size_of([9]f32))
#assert(size_of(Native_Text_Uniforms) == size_of([32]f32))

Native_UI_Nodes :: struct {
	field:   alicorn.Node_ID,
	surface: alicorn.Node_ID,
}

// Application_Key is the small cross-platform command vocabulary exposed by
// the SDL host. Applications do not need to depend on SDL keycode constants
// just to implement navigation or a few commands.
Application_Key :: enum {
	Up,
	Down,
	Page_Up,
	Page_Down,
	Command_1,
	Command_2,
	Command_3,
	Toggle,
}

Application_Build_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID
Application_Text_Change_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, change: alicorn.Text_Change)
Application_Key_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, key: Application_Key) -> bool
Application_Scroll_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, delta_y: f32)
Application_Tick_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime)

// Application is the intended public boundary for a small native Alicorn
// program. State is borrowed by callbacks for the duration of Run; retained
// runtime nodes never store this pointer.
Application :: struct {
	state:          rawptr,
	title:          string,
	width:          int,
	height:         int,
	build:          Application_Build_Proc,
	on_text_change: Application_Text_Change_Proc,
	on_key:         Application_Key_Proc,
	on_scroll:      Application_Scroll_Proc,
	on_tick:        Application_Tick_Proc,
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
	application: ^Application = nil,
	diagnostics_capture_requested: ^bool = nil,
) {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if manual_log {
			if event.type == .WINDOW_FOCUS_GAINED {
				fmt.println("sdl_event", "WINDOW_FOCUS_GAINED")
			} else if event.type == .WINDOW_FOCUS_LOST {
				fmt.println("sdl_event", "WINDOW_FOCUS_LOST")
			} else if event.type == .MOUSE_BUTTON_DOWN || event.type == .MOUSE_BUTTON_UP {
				fmt.println("sdl_event", "MOUSE_BUTTON", "x", event.button.x, "y", event.button.y, "button", event.button.button, "down", event.button.down)
			}
		}
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			quit_requested^ = true
		}
		if pointer, ok := pointer_from_sdl(event); ok {
			alicorn.process_pointer(rt, pointer)
		}
		if application != nil && event.type == .MOUSE_WHEEL {
			if application.on_scroll != nil {
				application.on_scroll(application.state, rt, event.wheel.y)
			}
		}
		if event.type == .KEY_DOWN && event.key.down {
			if event.key.key == sdl3.K_F12 && diagnostics_capture_requested != nil {
				diagnostics_capture_requested^ = true
				fmt.println("alicorn_diagnostics", "capture_requested", "F12")
			}
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
			if application != nil {
				text_field_focused := false
				if node, ok := rt.nodes[rt.focused]; ok {
					text_field_focused = node.active && node.kind == .Text_Field
				}
				if !text_field_focused {
					application_key: Application_Key
					handled := true
					switch event.key.key {
					case sdl3.K_UP: application_key = .Up
					case sdl3.K_DOWN: application_key = .Down
					case sdl3.K_PAGEUP: application_key = .Page_Up
					case sdl3.K_PAGEDOWN: application_key = .Page_Down
					case sdl3.K_1: application_key = .Command_1
					case sdl3.K_2: application_key = .Command_2
					case sdl3.K_3: application_key = .Command_3
					case sdl3.K_SPACE: application_key = .Toggle
					case: handled = false
					}
					if handled && application.on_key != nil && application.on_key(application.state, rt, application_key) {
						alicorn.invalidate_root(rt, "application keyboard command")
					}
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
			alicorn.invalidate_root(rt, "SDL drawable size changed")
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
				change := alicorn.process_text_input(rt, rt.focused, string(event.text.text))
				if application != nil {
					if application.on_text_change != nil {
						application.on_text_change(application.state, rt, change)
					} else if len(change.text) > 0 {
						delete(change.text)
					}
				} else {
					adopt_text_change(app_text, change)
				}
				if manual_log && application == nil { fmt.println("alicorn_after_TEXT_INPUT", "text", app_text^) }
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
	surface := alicorn.custom_surface(&ui, "animated-surface", frame, alicorn.Rect{0, 0, 280, 120}, 560, 240, 2)
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
) -> bool {
	if !native_text_rebuild_mesh(text_renderer, display, logical_to_pixel_x, logical_to_pixel_y) { return false }
	if !native_text_sync_atlas(text_renderer, command) { return false }
	if !native_text_upload_vertices(text_renderer, command) { return false }
	if !native_solid_build(solid_renderer, display, logical_to_pixel_x, logical_to_pixel_y, swap_w, swap_h, skip_root) { return false }
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
	solid_renderer: ^Native_Solid_Renderer,
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
	if !draw_display_list(command, probe_texture, width, height, text_renderer, surface_renderer, solid_renderer, display, 1, 1, false) {
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

// Write a dependency-free screenshot artifact for diagnostics captures. PPM
// is intentionally used instead of pulling an image encoder into the host;
// it is trivial for humans, scripts, and agents to inspect or convert.
native_capture_display_ppm :: proc(
	device: ^sdl3.GPUDevice,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	display: []alicorn.Display_Command,
	width, height: sdl3.Uint32,
	scale_x, scale_y: f32,
	path: string,
) -> bool {
	if width == 0 || height == 0 { return false }
	if !sdl3.GPUTextureSupportsFormat(device, text_renderer.swapchain_format, .D2, sdl3.GPUTextureUsageFlags{.COLOR_TARGET}) {
		return false
	}
	texture := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=text_renderer.swapchain_format, usage=sdl3.GPUTextureUsageFlags{.COLOR_TARGET},
		width=width, height=height, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if texture == nil { return false }
	defer sdl3.ReleaseGPUTexture(device, texture)
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.DOWNLOAD, size=width * height * 4})
	if download == nil { return false }
	defer sdl3.ReleaseGPUTransferBuffer(device, download)
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil { return false }
	if !draw_display_list(command, texture, width, height, text_renderer, surface_renderer, solid_renderer, display, scale_x, scale_y) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	source := sdl3.GPUTextureRegion{texture=texture, mip_level=0, layer=0, x=0, y=0, z=0, w=width, h=height, d=1}
	destination := sdl3.GPUTextureTransferInfo{transfer_buffer=download, offset=0, pixels_per_row=width, rows_per_layer=height}
	sdl3.DownloadFromGPUTexture(copy_pass, source, destination)
	sdl3.EndGPUCopyPass(copy_pass)
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	if fence == nil { return false }
	defer sdl3.ReleaseGPUFence(device, fence)
	fences := [1]^sdl3.GPUFence{fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) { return false }
	mapped := sdl3.MapGPUTransferBuffer(device, download, false)
	if mapped == nil { return false }
	defer sdl3.UnmapGPUTransferBuffer(device, download)
	pixels := cast([^]u8)mapped
	builder, builder_err := strings.builder_make_len_cap(0, int(width*height*3)+64)
	if builder_err != nil { return false }
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "P6\n%d %d\n255\n", width, height)
	for i := u64(0); i < u64(width)*u64(height); i += 1 {
		src := i * 4
		strings.write_byte(&builder, pixels[src+0])
		strings.write_byte(&builder, pixels[src+1])
		strings.write_byte(&builder, pixels[src+2])
	}
	image := strings.to_string(builder)
	if err := os.write_entire_file(path, image); err != nil { return false }
	native_text_commit_submission(text_renderer)
	native_surface_commit_submission(surface_renderer)
	native_solid_commit_submission(solid_renderer)
	return true
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

configure_platform_activation :: proc() {
	when ODIN_OS == .Darwin {
		// A bare executable launched from a terminal can create a visible SDL
		// window without becoming the active macOS application. That leaves the
		// retained UI looking healthy while keyboard and mouse events continue to
		// go to the launching application. Make the host's foreground policy
		// explicit before SDL initializes its Cocoa application object.
		if !sdl3.SetHint(sdl3.HINT_MAC_BACKGROUND_APP, "0") {
			fail("SDL_MAC_BACKGROUND_APP hint could not be set")
		}
		if !sdl3.SetHint(sdl3.HINT_WINDOW_ACTIVATE_WHEN_SHOWN, "1") {
			fail("SDL_WINDOW_ACTIVATE_WHEN_SHOWN hint could not be set")
		}
		if !sdl3.SetHint(sdl3.HINT_WINDOW_ACTIVATE_WHEN_RAISED, "1") {
			fail("SDL_WINDOW_ACTIVATE_WHEN_RAISED hint could not be set")
		}
	}
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
		if timing != nil { timing.fence_wait_ns += u64(time.duration_nanoseconds(time.since(wait_start))) }
		return false
	}
	if timing != nil {
		timing.fence_wait_ns += u64(time.duration_nanoseconds(time.since(wait_start)))
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

fill_surface_samples :: proc(samples: ^[dynamic]f32, phase: f32) {
	for i := 0; i < len(samples^); i += 1 {
		x := f32(i) / f32(len(samples^)-1)
		samples^[i] = 0.5 + 0.30*math.sin(x*18 + phase) + 0.12*math.sin(x*43 - phase*0.7)
	}
}

// run_application_loop is the reusable native shell. Application state is
// borrowed only through callbacks; retained runtime nodes do not store the
// pointer. SDL, render-pass scheduling, and GPU resource retirement remain
// host responsibilities.
run_application_loop :: proc(
	window: ^sdl3.Window,
	device: ^sdl3.GPUDevice,
	rt: ^alicorn.Runtime,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	metrics: ^Window_Metrics,
	application: Application,
	smoke := false,
	manual_log := false,
	gpu_driver := "unknown",
) {
	application_instance := application
	quit_requested := false
	logical_resize_events := 0
	pixel_resize_events := 0
	scale_events := 0
	text_input_events := 0
	composition_events := 0
	text_input_active := false
	text_input_owner: alicorn.Node_ID = 0
	in_flight: [dynamic; 3]Native_In_Flight
	retired := 0
	max_in_flight := 0
	query_before_wait_true := 0
	query_after_wait_true := 0
	wait_count := 0
	submitted := 0
	timing := Native_Host_Timing{}
	diagnostics := native_parse_diagnostics_options()

	platform_text := ""
	start := time.now()
	alicorn.invalidate_root(rt, "SDL application initial frame")
	build_start := time.now()
	_ = application.build(application.state, rt, metrics.logical_width, metrics.logical_height, metrics.display_scale)
	timing.application_build_ns += u64(time.duration_nanoseconds(time.since(build_start)))
	sync_text_input_focus(window, rt, &text_input_active, &text_input_owner)

	last_tick := time.now()
	for !quit_requested {
		frame_start := time.now()
		event_start := time.now()
		pump_events(
			window, rt, metrics, &quit_requested,
			&logical_resize_events, &pixel_resize_events, &scale_events,
			&text_input_events, &composition_events, &platform_text,
			manual_log=manual_log,
			application=&application_instance,
			diagnostics_capture_requested=&diagnostics.capture_requested,
		)
		timing.event_pump_ns += u64(time.duration_nanoseconds(time.since(event_start)))
		if quit_requested { break }

		now := time.now()
		if smoke && time.duration_nanoseconds(time.since(start)) >= 3_000_000_000 {
			quit_requested = true
			continue
		}
		if time.duration_nanoseconds(time.since(last_tick)) >= 16_666_667 {
			if application.on_tick != nil {
				tick_start := time.now()
				application.on_tick(application.state, rt)
				timing.application_tick_ns += u64(time.duration_nanoseconds(time.since(tick_start)))
			}
			last_tick = now
		}

		if rt.invalidated {
			alicorn.invalidate_root(rt, "SDL application wake")
			build_start = time.now()
			_ = application.build(application.state, rt, metrics.logical_width, metrics.logical_height, metrics.display_scale)
			timing.application_build_ns += u64(time.duration_nanoseconds(time.since(build_start)))
			sync_text_input_focus(window, rt, &text_input_active, &text_input_owner)
		}

		// Interaction-only invalidation updates retained paint without asking the
		// application to rebuild its procedural description. Flush that retained
		// presentation before submitting the next GPU frame.
		presentation_flushed := false
		if !rt.invalidated && alicorn.presentation_needs_frame(rt) {
			presentation_ui, ready := alicorn.begin_presentation_frame(rt)
			if ready {
				alicorn.end_presentation_frame(&presentation_ui)
				presentation_flushed = true
			}
		}

		if alicorn.frame_needs_submission(rt) || presentation_flushed {
			if len(in_flight) >= 2 {
				if !wait_and_retire_oldest(device, &in_flight, &query_before_wait_true, &query_after_wait_true, &wait_count, &timing) {
					fail("SDL application fence retirement failed")
				}
				retired += 1
			}
			encode_start := time.now()
			command := sdl3.AcquireGPUCommandBuffer(device)
			if command == nil { fail("SDL application command acquisition failed") }
			swapchain: ^sdl3.GPUTexture
			swap_w, swap_h: sdl3.Uint32
			if !sdl3.AcquireGPUSwapchainTexture(command, window, &swapchain, &swap_w, &swap_h) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL application swapchain acquisition failed")
			}
			if swapchain == nil || swap_w == 0 || swap_h == 0 {
				_ = sdl3.CancelGPUCommandBuffer(command)
				continue
			}
			metrics.pixel_width = int(swap_w)
			metrics.pixel_height = int(swap_h)
			logical_to_pixel_x := f32(swap_w) / f32(metrics.logical_width)
			logical_to_pixel_y := f32(swap_h) / f32(metrics.logical_height)
			if !draw_display_list(
				command, swapchain, swap_w, swap_h,
				text_renderer, surface_renderer, solid_renderer, rt.display[:],
				logical_to_pixel_x, logical_to_pixel_y,
			) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL application display-list draw failed")
			}
			timing.gpu_encode_ns += u64(time.duration_nanoseconds(time.since(encode_start)))
			submit_start := time.now()
			fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
			timing.gpu_submit_ns += u64(time.duration_nanoseconds(time.since(submit_start)))
			if fence == nil {
				fail("SDL application submission failed")
			}
			append(&in_flight, Native_In_Flight{fence})
			native_text_commit_submission(text_renderer)
			native_surface_commit_submission(surface_renderer)
			alicorn.gpu_surface_frame_consumed(rt)
			if presentation_flushed { alicorn.presentation_frame_consumed(rt) }
			submitted += 1
			timing.gpu_submissions += 1
			rt.stats.gpu_submits += 1
			if len(in_flight) > max_in_flight { max_in_flight = len(in_flight) }
		}
		if !rt.invalidated && !alicorn.frame_needs_submission(rt) {
			sdl3.Delay(1)
		}
		native_timing_add_frame(&timing, u64(time.duration_nanoseconds(time.since(frame_start))))
		if native_write_diagnostics(&diagnostics, start, gpu_driver, metrics^, rt, text_renderer, surface_renderer, solid_renderer, &timing) {
			screenshot_path := fmt.tprintf("%s/screenshot.ppm", diagnostics.capture_dir)
			if native_capture_display_ppm(
				device, text_renderer, surface_renderer, solid_renderer, rt.display[:],
				sdl3.Uint32(metrics.pixel_width), sdl3.Uint32(metrics.pixel_height),
				f32(metrics.pixel_width) / f32(metrics.logical_width),
				f32(metrics.pixel_height) / f32(metrics.logical_height),
				screenshot_path,
			) {
				fmt.println("alicorn_diagnostics", "screenshot", screenshot_path)
			} else {
				fmt.println("alicorn_diagnostics", "screenshot_failed", screenshot_path)
			}
		}
	}

	if !sdl3.WaitForGPUIdle(device) { fail("SDL application GPU idle wait failed") }
	for entry in in_flight {
		sdl3.ReleaseGPUFence(device, entry.fence)
		retired += 1
	}
	clear(&in_flight)
	if text_input_active {
		_ = sdl3.ClearComposition(window)
		_ = sdl3.StopTextInput(window)
	}
	elapsed_ns := time.duration_nanoseconds(time.since(start))
	fmt.println(
		"SDL application PASS",
		"submissions", submitted,
		"retired", retired,
		"max_frames_in_flight", max_in_flight,
		"wall_ns", elapsed_ns,
		"logical_resize_events", logical_resize_events,
		"pixel_resize_events", pixel_resize_events,
		"scale_events", scale_events,
		"text_input_events", text_input_events,
		"composition_events", composition_events,
		"frame_p95_ns", native_timing_percentile(timing.frame_samples[:], 0.95),
		"gpu_encode_ns", timing.gpu_encode_ns,
		"gpu_submit_ns", timing.gpu_submit_ns,
		"fence_wait_ns", timing.fence_wait_ns,
	)
}

// Run owns the complete SDL3/SDL_GPU application shell for external dogfood
// programs. The app supplies only its state pointer and ordinary callbacks.
Run :: proc(application: Application, smoke := false) {
	input_debug := false
	for argument in os.args {
		if argument == "--input-debug" { input_debug = true }
	}
	if !sdl3.SetHint(sdl3.HINT_IME_IMPLEMENTED_UI, "composition") {
		fail("SDL_IME_IMPLEMENTED_UI hint could not be set")
	}
	configure_platform_activation()
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("SDL_Init failed") }
	defer sdl3.Quit()
	title := application.title
	if title == "" { title = "Alicorn application" }
	width := application.width
	if width <= 0 { width = 960 }
	height := application.height
	if height <= 0 { height = 640 }
	title_cstring, title_err := strings.clone_to_cstring(title, context.temp_allocator)
	if title_err != nil { fail("application title allocation failed") }
	window := sdl3.CreateWindow(title_cstring, c.int(width), c.int(height), sdl3.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil { fail("SDL_CreateWindow failed") }
	defer sdl3.DestroyWindow(window)
	if !sdl3.RaiseWindow(window) { fail("SDL_RaiseWindow failed") }
	if input_debug {
		fmt.println("sdl_input_debug", "window_flags", sdl3.GetWindowFlags(window))
	}
	metrics: Window_Metrics
	if !read_window_metrics(window, &metrics) { fail("initial application window metrics unavailable") }
	formats := sdl3.GPUShaderFormat{.SPIRV, .DXIL, .MSL}
	gpu_driver_name: cstring = nil
	when ODIN_OS == .Darwin { gpu_driver_name = "metal" }
	device := sdl3.CreateGPUDevice(formats, false, gpu_driver_name)
	if device == nil { fail("SDL_CreateGPUDevice failed") }
	defer sdl3.DestroyGPUDevice(device)
	selected_driver := sdl3.GetGPUDeviceDriver(device)
	fmt.println("gpu_driver_requested", gpu_driver_name, "gpu_driver_selected", selected_driver)
	when ODIN_OS == .Darwin {
		if selected_driver == nil || string(selected_driver) != "metal" {
			fail("macOS SDL_GPU did not select the requested Metal driver")
		}
	}
		if !sdl3.ClaimWindowForGPUDevice(device, window) { fail("SDL_ClaimWindowForGPUDevice failed") }
	defer sdl3.ReleaseWindowFromGPUDevice(device, window)
	// The reusable desktop host favors interaction latency. The foundation
	// stress fixture below intentionally uses three frames; ordinary apps use
	// two unless they explicitly opt into throughput-oriented stress behavior.
	if !sdl3.SetGPUAllowedFramesInFlight(device, 2) { fail("SDL_SetGPUAllowedFramesInFlight failed") }
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)})
	defer alicorn.destroy_runtime(&rt)
	font_data, font_err := os.read_entire_file_from_path(native_font_path(), context.allocator)
	if font_err != nil { fail("application font could not be loaded") }
	if !alicorn.text_engine_load_font(&rt.text_engine, font_data) {
		delete(font_data)
		fail("application Runa font initialization failed")
	}
	delete(font_data)
	text_renderer, text_ok := native_text_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !text_ok { fail("application GPU text pipeline initialization failed") }
	defer native_text_destroy(&text_renderer)
	surface_renderer, surface_ok := native_surface_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !surface_ok { fail("application GPU surface pipeline initialization failed") }
	defer native_surface_destroy(&surface_renderer)
	solid_renderer, solid_ok := native_solid_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window))
	if !solid_ok { fail("application solid rectangle pipeline initialization failed") }
	defer native_solid_destroy(&solid_renderer)
	// Metal/text/surface setup can briefly return focus to the launching
	// terminal on macOS. Raise again only after the application is ready so a
	// visible-but-inert window is not handed to the user.
	if !sdl3.RaiseWindow(window) { fail("SDL_RaiseWindow failed after host initialization") }
	run_application_loop(window, device, &rt, &text_renderer, &surface_renderer, &solid_renderer, &metrics, application, smoke, input_debug, string(selected_driver))
}

RunFoundation :: proc() {
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
	configure_platform_activation()
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
	solid_renderer, solid_ok := native_solid_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window))
	if !solid_ok { fail("GPU solid rectangle pipeline initialization failed") }
	defer native_solid_destroy(&solid_renderer)
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
		&solid_renderer,
		rt.display[:],
		sdl3.Uint32(metrics.logical_width),
		sdl3.Uint32(metrics.logical_height),
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
		if !draw_display_list(command, swapchain, swap_w, swap_h, &text_renderer, &surface_renderer, &solid_renderer, rt.display[:], logical_to_pixel_x, logical_to_pixel_y) {
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
