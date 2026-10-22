package alicorn_sdl_gpu

import "core:os"
import alicorn "../../runtime"
import "vendor:sdl3"

Native_Inspector_Options :: struct {
	enabled: bool,
	start_visible: bool,
}

native_inspector_options :: proc(arguments: []string) -> Native_Inspector_Options {
	options: Native_Inspector_Options
	for argument in arguments {
		if argument == "--inspector" || argument == "--inspector-fixture" { options.enabled = true }
		if argument == "--inspector-open" { options.enabled, options.start_visible = true, true }
	}
	return options
}

// The inspector owns a distinct retained tree, font engine, and GPU meshes.
// No application node stores or borrows inspector state. A second mesh is
// required because both displays can be encoded in the same command buffer.
Native_Inspector_Overlay :: struct {
	enabled: bool,
	runtime_ready: bool,
	gpu_ready: bool,
	state: alicorn.Inspector_Overlay,
	runtime: alicorn.Runtime,
	text_renderer: Native_Text_Renderer,
	solid_renderer: Native_Solid_Renderer,
	source_fingerprint: u64,
	source_seen: bool,
	redraw_pending: bool,
	// Track the complete gesture, including events received before opening.
	buttons_down: u32,
	swallowed_buttons: u32,
	keys_down: [512]bool,
	swallowed_keys: [512]bool,
	suppress_text_until_drain: bool,
	builds: u64,
}

native_inspector_runtime_init :: proc(overlay: ^Native_Inspector_Overlay, options: Native_Inspector_Options, viewport: alicorn.Rect) {
	if overlay == nil || !options.enabled { return }
	overlay.enabled = true
	overlay.runtime = alicorn.new_runtime(viewport)
	overlay.runtime_ready = true
	overlay.state = alicorn.inspector_overlay_make()
	if options.start_visible { alicorn.inspector_overlay_open(&overlay.state) }
	overlay.redraw_pending = options.start_visible
}

native_inspector_init :: proc(
	overlay: ^Native_Inspector_Overlay,
	device: ^sdl3.GPUDevice,
	format: sdl3.GPUTextureFormat,
	viewport: alicorn.Rect,
) -> bool {
	native_inspector_runtime_init(overlay, native_inspector_options(os.args), viewport)
	if !overlay.enabled { return true }
	if !native_load_default_fonts(&overlay.runtime) { return false }
	text_ok, solid_ok: bool
	overlay.text_renderer, text_ok = native_text_make(device, format, &overlay.runtime)
	if !text_ok { return false }
	overlay.solid_renderer, solid_ok = native_solid_make(device, format)
	if !solid_ok { return false }
	overlay.gpu_ready = true
	return true
}

native_inspector_destroy :: proc(overlay: ^Native_Inspector_Overlay) {
	if overlay == nil || !overlay.runtime_ready { return }
	// The loop waits for device idle and retires all submissions before this
	// destructor runs, just as it does for the application's renderers.
	native_text_destroy(&overlay.text_renderer)
	native_solid_destroy(&overlay.solid_renderer)
	alicorn.inspector_overlay_destroy(&overlay.state)
	alicorn.destroy_runtime(&overlay.runtime)
	overlay^ = {}
}

native_inspector_visible :: proc(overlay: ^Native_Inspector_Overlay) -> bool {
	return overlay != nil && overlay.enabled && overlay.state.visible
}

native_inspector_submission_pending :: proc(overlay: ^Native_Inspector_Overlay) -> bool {
	if overlay == nil || !overlay.enabled { return false }
	return overlay.redraw_pending || (overlay.state.visible && alicorn.frame_needs_submission(&overlay.runtime))
}

native_application_has_pending_work :: proc(rt: ^alicorn.Runtime, suspend_hard_error := false) -> bool {
	return rt != nil && ((rt.invalidated && (!suspend_hard_error || !rt.hard_error)) || alicorn.frame_needs_submission(rt))
}

native_inspector_host_summary :: proc(timing: ^Native_Host_Timing, rt: ^alicorn.Runtime, host_wakes: u64) -> alicorn.Inspector_Host_Summary {
	return alicorn.Inspector_Host_Summary{
		host_wakes=host_wakes,
		application_builds=rt.stats.frames_built,
		application_submits=rt.stats.gpu_submits,
		overlay_submits=timing.inspector_submissions,
		event_ms=f64(timing.event_pump_ns)/1_000_000,
		build_ms=f64(timing.application_build_ns)/1_000_000,
		encode_ms=f64(timing.application_gpu_encode_ns)/1_000_000,
		submit_ms=f64(timing.gpu_submit_ns)/1_000_000,
	}
}

native_inspector_update :: proc(overlay: ^Native_Inspector_Overlay, source: ^alicorn.Runtime, viewport: alicorn.Rect, summary: ^alicorn.Inspector_Host_Summary = nil) {
	if !native_inspector_visible(overlay) { return }
	fingerprint := alicorn.inspector_overlay_source_fingerprint(source)
	if !overlay.source_seen || fingerprint != overlay.source_fingerprint || viewport != overlay.runtime.viewport {
		overlay.runtime.viewport = viewport
		alicorn.invalidate_root(&overlay.runtime, "inspected runtime changed")
	}
	// A button activation may request one follow-up description (for example
	// a tab change). Keep this bounded without introducing an idle timer.
	for pass in 0..<NATIVE_DESCRIPTION_STABILIZATION_LIMIT {
		if !overlay.runtime.invalidated || overlay.runtime.hard_error { break }
		ui, ready := alicorn.begin_frame(&overlay.runtime)
		if !ready { break }
		alicorn.inspector_overlay_build(&ui, &overlay.state, source, summary)
		alicorn.end_frame(&ui)
		overlay.builds += 1
		if !overlay.state.visible {
			_ = alicorn.cancel_pointer_capture(&overlay.runtime)
			overlay.suppress_text_until_drain = true
			overlay.redraw_pending = true
			break
		}
		if overlay.state.initial_focus != 0 {
			_ = alicorn.focus(&overlay.runtime, overlay.state.initial_focus)
			overlay.state.initial_focus = 0
		}
	}
	if !overlay.runtime.invalidated && alicorn.presentation_needs_frame(&overlay.runtime) {
		ui, ready := alicorn.begin_presentation_frame(&overlay.runtime)
		if ready { alicorn.end_presentation_frame(&ui) }
	}
	overlay.source_fingerprint, overlay.source_seen = fingerprint, true
}

native_inspector_render :: proc(
	overlay: ^Native_Inspector_Overlay,
	surface_renderer: ^Native_Surface_Renderer,
	command: ^sdl3.GPUCommandBuffer,
	target: ^sdl3.GPUTexture,
	width, height: sdl3.Uint32,
	scale_x, scale_y: f32,
	scratch_allocator := context.temp_allocator,
) -> bool {
	if !native_inspector_visible(overlay) { return true }
	return draw_display_list(
		command, target, width, height, &overlay.text_renderer, surface_renderer,
		&overlay.solid_renderer, overlay.runtime.display[:], scale_x, scale_y,
		clear_background=false, scratch_allocator=scratch_allocator,
	)
}

native_inspector_submission_succeeded :: proc(overlay: ^Native_Inspector_Overlay) {
	if overlay == nil || !overlay.enabled { return }
	if overlay.state.visible {
		native_text_commit_submission(&overlay.text_renderer)
		native_solid_commit_submission(&overlay.solid_renderer)
		alicorn.frame_submission_succeeded(&overlay.runtime)
	}
	overlay.redraw_pending = false
}

native_inspector_set_visible :: proc(
	overlay: ^Native_Inspector_Overlay,
	visible: bool,
	source: ^alicorn.Runtime,
	application: ^Application = nil,
	text_input: ^Native_Text_Input_State = nil,
	window: ^sdl3.Window = nil,
) {
	if overlay == nil || !overlay.enabled || overlay.state.visible == visible { return }
	if visible {
		// Preserve app focus while canceling its native composition and any
		// captured press/drag that will no longer receive matching input.
		if text_input != nil {
			native_cancel_current_text_composition(application, source, text_input, "visual inspector opened")
			text_input.suspended = true
		}
		captured := source.captured_node
		cancelled := alicorn.cancel_pointer_capture(source)
		_ = native_dispatch_drag_event(application, source)
		if cancelled && application != nil && application.on_pointer != nil {
			application.on_pointer(application.state, source, alicorn.Pointer_Event{kind=.Cancel}, captured)
		}
		overlay.swallowed_buttons |= overlay.buttons_down
		for down, index in overlay.keys_down { if down { overlay.swallowed_keys[index] = true } }
		alicorn.inspector_overlay_open(&overlay.state)
		alicorn.invalidate_root(&overlay.runtime, "visual inspector opened")
	} else {
		_ = alicorn.cancel_pointer_capture(&overlay.runtime)
		alicorn.inspector_overlay_close(&overlay.state)
	}
	overlay.suppress_text_until_drain = true
	overlay.redraw_pending = true
	if window != nil {
		if text_input != nil { sync_text_input_focus(window, source, text_input, application) }
		_ = sdl3.ClearComposition(window)
		// TEXT_INPUT/EDITING already queued for the previous owner must never
		// enter either runtime after a toggle.
		sdl3.FlushEvent(.TEXT_INPUT)
		sdl3.FlushEvent(.TEXT_EDITING)
	}
}

native_inspector_finish_input_pump :: proc(overlay: ^Native_Inspector_Overlay, text_input: ^Native_Text_Input_State) {
	if overlay == nil || !overlay.enabled { return }
	overlay.suppress_text_until_drain = false
	if text_input != nil { text_input.suspended = overlay.state.visible }
}

native_inspector_pointer_button_mask :: proc(button: int) -> u32 {
	return u32(1) << u32(button-1) if button > 0 && button <= 32 else 0
}

// Called before application semantic routing. Consumed input never reaches
// app process_pointer/process_scroll, shortcuts, or application callbacks.
// Window, worker and close events continue through the ordinary host pump.
native_inspector_route_event :: proc(
	overlay: ^Native_Inspector_Overlay,
	source: ^alicorn.Runtime,
	event: sdl3.Event,
	modifiers: sdl3.Keymod,
	application: ^Application = nil,
	text_input: ^Native_Text_Input_State = nil,
	window: ^sdl3.Window = nil,
	translated_pointer: alicorn.Pointer_Event = {},
	translated_pointer_ok := false,
) -> bool {
	if overlay == nil || !overlay.enabled { return false }
	visible := overlay.state.visible
	if event.type == .KEY_DOWN || event.type == .KEY_UP {
		index := int(event.key.scancode)
		valid_index := index >= 0 && index < len(overlay.keys_down)
		was_swallowed := valid_index && overlay.swallowed_keys[index]
		if valid_index {
			overlay.keys_down[index] = event.type == .KEY_DOWN
			if visible && event.type == .KEY_DOWN { overlay.swallowed_keys[index] = true }
			if event.type == .KEY_UP { overlay.swallowed_keys[index] = false }
		}
		if event.type == .KEY_DOWN && event.key.down && !event.key.repeat && event.key.key == sdl3.K_F9 {
			if valid_index { overlay.swallowed_keys[index] = true }
			native_inspector_set_visible(overlay, !visible, source, application, text_input, window)
			return true
		}
		if visible && event.type == .KEY_DOWN && event.key.down && event.key.key == sdl3.K_ESCAPE {
			native_inspector_set_visible(overlay, false, source, application, text_input, window)
			return true
		}
		if !visible { return was_swallowed }
		if event.type == .KEY_DOWN && event.key.down {
			if event.key.key == sdl3.K_P {
				overlay.state.picking = !overlay.state.picking
				alicorn.invalidate_root(&overlay.runtime, "inspector pick mode changed")
			} else if event.key.key == sdl3.K_TAB {
				direction: alicorn.Focus_Direction = .Previous if native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) else .Next
				_ = alicorn.focus_traverse(&overlay.runtime, direction)
			} else {
				_ = native_route_focused_control_key(&overlay.runtime, event.key.key)
			}
		}
		// Diagnostics remain available while the overlay owns keyboard input.
		return true
	}
	pointer := translated_pointer
	ok := translated_pointer_ok
	if !translated_pointer_ok {
		pointer, ok = pointer_from_sdl_with_modifiers(event, modifiers)
	}
	if ok {
		mask := native_inspector_pointer_button_mask(pointer.button)
		was_swallowed := overlay.swallowed_buttons & mask != 0
		if pointer.kind == .Down {
			overlay.buttons_down |= mask
			if visible { overlay.swallowed_buttons |= mask }
		} else if pointer.kind == .Up {
			overlay.buttons_down &= ~mask
			overlay.swallowed_buttons &= ~mask
		}
		if !visible {
			return was_swallowed || (pointer.kind == .Move && overlay.swallowed_buttons != 0)
		}
		bounds := overlay.state.panel_bounds
		in_panel := pointer.x >= bounds.x && pointer.y >= bounds.y && pointer.x < bounds.x+bounds.w && pointer.y < bounds.y+bounds.h
		if overlay.state.picking && !in_panel {
			if pointer.kind == .Down && pointer.button == 1 {
				_ = alicorn.inspector_overlay_pick(&overlay.state, source, pointer.x, pointer.y)
				alicorn.invalidate_root(&overlay.runtime, "inspector picked application node")
			}
		} else if in_panel || overlay.runtime.captured_node != 0 {
			_ = alicorn.process_pointer(&overlay.runtime, pointer)
		}
		return true
	}
	if event.type == .MOUSE_WHEEL {
		if !visible { return overlay.swallowed_buttons != 0 }
		_ = alicorn.process_scroll(&overlay.runtime, alicorn.Scroll_Event{
			delta_x=event.wheel.x, delta_y=event.wheel.y,
			ticks_x=int(event.wheel.integer_x), ticks_y=int(event.wheel.integer_y),
			x=event.wheel.mouse_x, y=event.wheel.mouse_y,
			modifiers=pointer_modifiers_from_sdl(modifiers),
		})
		return true
	}
	if event.type == .TEXT_INPUT || event.type == .TEXT_EDITING {
		return visible || overlay.suppress_text_until_drain
	}
	if event.type == .WINDOW_FOCUS_LOST {
		_ = alicorn.cancel_pointer_capture(&overlay.runtime)
		overlay.buttons_down, overlay.swallowed_buttons = 0, 0
		overlay.keys_down, overlay.swallowed_keys = {}, {}
	}
	return false
}
