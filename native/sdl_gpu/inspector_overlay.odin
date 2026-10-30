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
	application_buttons: u32,
	inspector_buttons: u32,
	pick_buttons: u32,
	keyboard_owned: bool,
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
	overlay.solid_renderer, solid_ok = native_solid_make(device, format, &overlay.runtime)
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
		motion_samples=timing.motion_samples,
		motion_timer_wakes=timing.motion_timer_wakes,
		motion_restore_samples=timing.motion_restore_samples,
		motion_coalesced_owners=timing.motion_coalesced_owners,
		motion_bounded_snaps=timing.motion_bounded_snaps,
		motion_sample_ns=timing.motion_sample_ns,
		motion_sample_max_ns=timing.motion_sample_max_ns,
		motion_max_active_owners=timing.motion_max_active_owners,
		motion_max_lateness_ns=timing.motion_max_lateness_ns,
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
			overlay.swallowed_buttons |= overlay.inspector_buttons | overlay.pick_buttons
			overlay.inspector_buttons, overlay.pick_buttons = 0, 0
			overlay.keyboard_owned = false
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
	content_inset_top: f32 = 0,
	scratch_allocator := context.temp_allocator,
) -> bool {
	if !native_inspector_visible(overlay) { return true }
	return draw_display_list(
		command, target, width, height, &overlay.text_renderer, surface_renderer,
		&overlay.solid_renderer, overlay.runtime.display[:], scale_x, scale_y,
		clear_background=false, scratch_allocator=scratch_allocator,
		content_inset_top=content_inset_top,
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
	text_input_coordinator: ^Native_Text_Input_Coordinator = nil,
) {
	if overlay == nil || !overlay.enabled || overlay.state.visible == visible { return }
	if visible {
		// Visibility is independent of input ownership. Preserve the application's
		// current text composition and pointer capture until the user interacts
		// with the inspector itself.
		alicorn.inspector_overlay_open(&overlay.state)
		alicorn.invalidate_root(&overlay.runtime, "visual inspector opened")
	} else {
		overlay.swallowed_buttons |= overlay.inspector_buttons | overlay.pick_buttons
		overlay.inspector_buttons, overlay.pick_buttons = 0, 0
		native_inspector_cancel_keyboard_ownership(overlay, text_input, window)
		_ = alicorn.cancel_pointer_capture(&overlay.runtime)
		alicorn.inspector_overlay_close(&overlay.state)
	}
	overlay.redraw_pending = true
	if window != nil {
		if text_input != nil {
			sync_text_input_focus(window, source, text_input, application, text_input_coordinator)
		}
	}
}

native_inspector_keyboard_owns_input :: proc(overlay: ^Native_Inspector_Overlay) -> bool {
	return native_inspector_visible(overlay) && overlay.keyboard_owned
}

native_inspector_cancel_keyboard_ownership :: proc(
	overlay: ^Native_Inspector_Overlay,
	text_input: ^Native_Text_Input_State,
	window: ^sdl3.Window,
) {
	if overlay == nil || !overlay.keyboard_owned { return }
	overlay.keyboard_owned = false
	overlay.suppress_text_until_drain = true
	if text_input != nil { text_input.suspended = false }
	if window != nil {
		_ = sdl3.ClearComposition(window)
		sdl3.FlushEvent(.TEXT_INPUT)
		sdl3.FlushEvent(.TEXT_EDITING)
	}
}

native_inspector_take_keyboard_ownership :: proc(
	overlay: ^Native_Inspector_Overlay,
	application: ^Application,
	source: ^alicorn.Runtime,
	text_input: ^Native_Text_Input_State,
	window: ^sdl3.Window,
) {
	if overlay == nil || !native_inspector_visible(overlay) || overlay.keyboard_owned { return }
	if text_input != nil {
		native_cancel_current_text_composition(application, source, text_input, "inspector took keyboard input")
		text_input.suspended = true
	}
	overlay.keyboard_owned = true
	overlay.suppress_text_until_drain = true
	if window != nil {
		_ = sdl3.ClearComposition(window)
		sdl3.FlushEvent(.TEXT_INPUT)
		sdl3.FlushEvent(.TEXT_EDITING)
	}
}

native_inspector_finish_input_pump :: proc(overlay: ^Native_Inspector_Overlay, text_input: ^Native_Text_Input_State) {
	if overlay == nil || !overlay.enabled { return }
	overlay.suppress_text_until_drain = false
	if text_input != nil { text_input.suspended = native_inspector_keyboard_owns_input(overlay) }
}

native_inspector_pointer_button_mask :: proc(button: int) -> u32 {
	return u32(1) << u32(button-1) if button > 0 && button <= 32 else 0
}

// Called before application semantic routing. Inspector-owned gestures stay
// with the overlay through release; input outside its panel normally falls
// through to the application. Pick mode is the only outside-panel exception.
// Window, worker and close events continue through the ordinary host pump.
native_inspector_route_event :: proc(
	overlay: ^Native_Inspector_Overlay,
	source: ^alicorn.Runtime,
	event: sdl3.Event,
	modifiers: sdl3.Keymod,
	application: ^Application = nil,
	text_input: ^Native_Text_Input_State = nil,
	window: ^sdl3.Window = nil,
	text_input_coordinator: ^Native_Text_Input_Coordinator = nil,
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
			if event.type == .KEY_UP { overlay.swallowed_keys[index] = false }
		}
		if event.type == .KEY_DOWN && event.key.down && !event.key.repeat && event.key.key == sdl3.K_F9 {
			if valid_index { overlay.swallowed_keys[index] = true }
			native_inspector_set_visible(
				overlay, !visible, source, application, text_input, window, text_input_coordinator,
			)
			return true
		}
		if event.type == .KEY_UP { return was_swallowed }
		if !visible || !overlay.keyboard_owned { return was_swallowed }
		if event.type == .KEY_DOWN && event.key.down && event.key.key == sdl3.K_ESCAPE {
			native_inspector_set_visible(
				overlay, false, source, application, text_input, window, text_input_coordinator,
			)
			if valid_index { overlay.swallowed_keys[index] = true }
			return true
		}
		if event.type == .KEY_DOWN && event.key.down {
			if valid_index { overlay.swallowed_keys[index] = true }
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
		was_swallowed := mask != 0 && overlay.swallowed_buttons & mask != 0
		if pointer.kind == .Down { overlay.buttons_down |= mask }
		if pointer.kind == .Up { overlay.buttons_down &= ~mask }
		if overlay.swallowed_buttons != 0 {
			if pointer.kind == .Down { overlay.swallowed_buttons |= mask }
			if pointer.kind == .Up && was_swallowed { overlay.swallowed_buttons &= ~mask }
			return true
		}
		if overlay.application_buttons != 0 {
			if pointer.kind == .Down { overlay.application_buttons |= mask }
			if pointer.kind == .Up { overlay.application_buttons &= ~mask }
			return false
		}
		if overlay.inspector_buttons != 0 {
			_ = alicorn.process_pointer(&overlay.runtime, pointer)
			if pointer.kind == .Up { overlay.inspector_buttons &= ~mask }
			return true
		}
		if overlay.pick_buttons != 0 {
			if pointer.kind == .Up { overlay.pick_buttons &= ~mask }
			return true
		}
		if pointer.kind == .Down {
			if !visible {
				overlay.application_buttons |= mask
				return false
			}
			bounds := overlay.state.panel_bounds
			in_panel := pointer.x >= bounds.x && pointer.y >= bounds.y && pointer.x < bounds.x+bounds.w && pointer.y < bounds.y+bounds.h
			if in_panel {
				overlay.inspector_buttons |= mask
				native_inspector_take_keyboard_ownership(overlay, application, source, text_input, window)
				_ = alicorn.process_pointer(&overlay.runtime, pointer)
				return true
			}
			if overlay.state.picking && pointer.button == 1 {
				overlay.pick_buttons |= mask
				_ = alicorn.inspector_overlay_pick(&overlay.state, source, pointer.x, pointer.y)
				alicorn.invalidate_root(&overlay.runtime, "inspector picked application node")
				return true
			}
			native_inspector_cancel_keyboard_ownership(overlay, text_input, window)
			overlay.application_buttons |= mask
			return false
		}
		if !visible { return false }
		bounds := overlay.state.panel_bounds
		in_panel := pointer.x >= bounds.x && pointer.y >= bounds.y && pointer.x < bounds.x+bounds.w && pointer.y < bounds.y+bounds.h
		if in_panel || overlay.runtime.captured_node != 0 {
			_ = alicorn.process_pointer(&overlay.runtime, pointer)
			return true
		}
		return false
	}
	if event.type == .MOUSE_WHEEL {
		if !visible { return false }
		bounds := overlay.state.panel_bounds
		inside := event.wheel.mouse_x >= bounds.x && event.wheel.mouse_y >= bounds.y &&
			event.wheel.mouse_x < bounds.x+bounds.w && event.wheel.mouse_y < bounds.y+bounds.h
		if !inside { return false }
		_ = alicorn.process_scroll(&overlay.runtime, native_scroll_event_from_sdl(event.wheel, pointer_modifiers_from_sdl(modifiers)))
		return true
	}
	if event.type == .TEXT_INPUT || event.type == .TEXT_EDITING {
		return overlay.suppress_text_until_drain || native_inspector_keyboard_owns_input(overlay)
	}
	if event.type == .WINDOW_FOCUS_LOST {
		_ = alicorn.cancel_pointer_capture(&overlay.runtime)
		overlay.buttons_down, overlay.swallowed_buttons = 0, 0
		overlay.application_buttons, overlay.inspector_buttons, overlay.pick_buttons = 0, 0, 0
		overlay.keyboard_owned = false
		overlay.keys_down, overlay.swallowed_keys = {}, {}
	}
	return false
}
