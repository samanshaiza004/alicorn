package alicorn_sdl_gpu

import "core:fmt"
import "base:runtime"
import "core:c"
import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

Window_Metrics :: struct {
	logical_width:  int,
	logical_height: int,
	// window_logical_height is the full SDL client area. logical_height is the
	// application viewport after host-owned chrome has been reserved.
	window_logical_height: int,
	pixel_width:    int,
	pixel_height:   int,
	pixel_density:  f32,
	display_scale:  f32,
}

Native_Content_Transform :: struct {
	window_height: f32,
	app_height:    f32,
	inset_top:     f32,
}

native_content_transform_make :: proc(window_height, inset_top: f32) -> Native_Content_Transform {
	clamped_height := max(window_height, 0)
	clamped_inset := clamp(inset_top, 0, clamped_height)
	app_height := max(clamped_height-clamped_inset, min(clamped_height, 1))
	return Native_Content_Transform{
		window_height=clamped_height,
		app_height=app_height,
		inset_top=clamped_inset,
	}
}

native_application_point_from_window :: proc(transform: Native_Content_Transform, x, y: f32) -> (f32, f32, bool) {
	if y < transform.inset_top || y >= transform.window_height { return x, 0, false }
	return x, y-transform.inset_top, true
}

native_application_rect_to_window :: proc(transform: Native_Content_Transform, rect: alicorn.Rect) -> alicorn.Rect {
	result := rect
	result.y += transform.inset_top
	return result
}

read_window_metrics :: proc(window: ^sdl3.Window, metrics: ^Window_Metrics, content_inset_top: f32 = 0) -> bool {
	logical_width, logical_height: c.int
	pixel_width, pixel_height: c.int
	if !sdl3.GetWindowSize(window, &logical_width, &logical_height) {
		return false
	}
	if !sdl3.GetWindowSizeInPixels(window, &pixel_width, &pixel_height) {
		return false
	}
	transform := native_content_transform_make(f32(logical_height), content_inset_top)
	metrics^ = Window_Metrics{
		logical_width = int(logical_width),
		logical_height = int(transform.app_height),
		window_logical_height = int(logical_height),
		pixel_width = int(pixel_width),
		pixel_height = int(pixel_height),
		pixel_density = sdl3.GetWindowPixelDensity(window),
		display_scale = sdl3.GetWindowDisplayScale(window),
	}
	return metrics.logical_width > 0 && metrics.logical_height > 0 &&
		metrics.pixel_width > 0 && metrics.pixel_height > 0 &&
		metrics.pixel_density > 0 && metrics.display_scale > 0
}

native_live_resize_redraw :: proc(state: ^Native_Live_Resize_State) {
	if state == nil || !state.active || state.window == nil || state.device == nil || state.rt == nil ||
		state.application == nil || state.metrics == nil || state.text_renderer == nil ||
		state.surface_renderer == nil || state.solid_renderer == nil || state.timing == nil ||
		state.host_scratch == nil || state.in_flight == nil {
		return
	}
	if state.rendering {
		state.pending = true
		return
	}
	state.rendering = true
	defer state.rendering = false
	for pass in 0..<2 {
		state.pending = false
		native_live_resize_redraw_once(state)
		if !state.pending { return }
	}
}

native_live_resize_redraw_once :: proc(state: ^Native_Live_Resize_State) {
	if state == nil || !state.active { return }
	frame_start := time.now()
	native_host_scratch_reset(state.host_scratch)

	current_metrics: Window_Metrics
	inset_top := f32(0)
	if state.native_menu != nil { inset_top = state.native_menu.content_inset_top }
	if !read_window_metrics(state.window, &current_metrics, inset_top) { return }
	cause_scope := alicorn.cause_begin(state.rt, .Host_Event, "SDL live resize expose")
	defer alicorn.cause_end(state.rt, cause_scope)
	cause := cause_scope.cause
	old_metrics := state.metrics^
	logical_changed := current_metrics.logical_width != old_metrics.logical_width ||
	                   current_metrics.logical_height != old_metrics.logical_height
	scale_changed := current_metrics.pixel_density != old_metrics.pixel_density ||
	                 current_metrics.display_scale != old_metrics.display_scale
	state.metrics^ = current_metrics
	if logical_changed {
		state.rt.viewport.w = f32(current_metrics.logical_width)
		state.rt.viewport.h = f32(current_metrics.logical_height)
		alicorn.invalidate_root(state.rt, "SDL live-resize logical size changed")
	} else if scale_changed {
		alicorn.invalidate_root(state.rt, "SDL live-resize display scale changed")
	}
	inspector_enabled := state.inspector != nil && state.inspector.enabled
	if state.rt.invalidated && (!inspector_enabled || !state.rt.hard_error) {
		stabilization := native_application_build_until_stable(state.application, state.rt, state.metrics, state.timing, stop_on_hard_error=inspector_enabled)
		if !stabilization.stable { return }
	}
	inspector_summary := native_inspector_host_summary(state.timing, state.rt, state.timing.frames)
	native_inspector_update(state.inspector, state.rt,
		alicorn.Rect{0, 0, f32(current_metrics.logical_width), f32(current_metrics.logical_height)}, &inspector_summary)
	if state.text_input_state != nil {
		state.text_input_state.content_inset_top = inset_top
		state.text_input_state.suspended = native_inspector_visible(state.inspector) ||
			(state.inspector != nil && state.inspector.suppress_text_until_drain)
		sync_text_input_focus(state.window, state.rt, state.text_input_state, state.application)
	}
	if (!inspector_enabled || !state.rt.hard_error) && alicorn.presentation_needs_frame(state.rt) {
		presentation_ui, ready := alicorn.begin_presentation_frame(state.rt)
		if ready { alicorn.end_presentation_frame(&presentation_ui) }
	}

	application_submission_pending := alicorn.frame_needs_submission(state.rt)
	inspector_submission_pending := native_inspector_submission_pending(state.inspector)
	if len(state.in_flight^) >= 2 {
		if !wait_and_retire_oldest(
			state.device, state.in_flight,
			state.query_before_wait_true, state.query_after_wait_true, state.wait_count,
			state.timing,
		) {
			return
		}
		if state.retired != nil { state.retired^ += 1 }
	}
	command := sdl3.AcquireGPUCommandBuffer(state.device)
	if command == nil { return }
	swapchain: ^sdl3.GPUTexture
	swap_w, swap_h: sdl3.Uint32
	if !sdl3.AcquireGPUSwapchainTexture(command, state.window, &swapchain, &swap_w, &swap_h) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return
	}
	if swapchain == nil || swap_w == 0 || swap_h == 0 {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return
	}
	state.metrics.pixel_width = int(swap_w)
	state.metrics.pixel_height = int(swap_h)
	scale_x := f32(swap_w)/f32(state.metrics.logical_width)
	scale_y := f32(swap_h)/f32(state.metrics.window_logical_height)
	preview_time := u64(sdl3.GetTicksNS())
	preview := native_devtools_make_sample(
		state.devtools_cursor, state.rt, state.timing, state.text_events,
		cause, preview_time, host_wakes=1,
	)
	preview.gpu_submissions += 1
	renderer_metrics_before := native_devtools_renderer_metrics_capture(
		state.text_renderer, state.surface_renderer, state.solid_renderer,
	)
	encode_start := time.now()
	hud_vertex_reserve := 0
	if state.devtools_hud != nil && state.devtools_hud.visible {
		hud_vertex_reserve = NATIVE_DEVTOOLS_HUD_RESERVE_VERTICES
	}
	if !draw_display_list(
		command, swapchain, swap_w, swap_h,
		state.text_renderer, state.surface_renderer, state.solid_renderer, state.rt.display[:],
		scale_x, scale_y,
		debug_bounds=state.debug_bounds,
		content_inset_top=inset_top,
		native_menu=state.native_menu,
		reserve_solid_vertices=hud_vertex_reserve,
		scratch_allocator=state.host_scratch.allocator,
	) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		fail("SDL live-resize display-list draw failed")
	}
	encode_elapsed := u64(time.duration_nanoseconds(time.since(encode_start)))
	if application_submission_pending { state.timing.application_gpu_encode_ns += encode_elapsed }
	else if inspector_submission_pending { state.timing.inspector_encode_ns += encode_elapsed }
	else { state.timing.devtools_hud_encode_ns += encode_elapsed }
	hud_start := time.now()
	if !native_devtools_hud_render(
		state.devtools_hud, state.solid_renderer, command, swapchain, swap_w, swap_h,
		scale_x, scale_y,
		state.devtools_recorder, u64(sdl3.GetTicksNS()), preview,
		preview_valid=state.devtools_hud != nil && state.devtools_hud.visible,
		last_invalidation=state.rt.last_invalidation_reason,
	) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		fail("Alicorn DevTools live-resize HUD draw failed")
	}
	if !application_submission_pending {
		native_devtools_renderer_metrics_restore(
			state.text_renderer, state.surface_renderer, state.solid_renderer,
			renderer_metrics_before,
		)
	}
	if state.devtools_hud != nil && state.devtools_hud.visible {
		state.timing.devtools_hud_encode_ns += u64(time.duration_nanoseconds(time.since(hud_start)))
	}
	inspector_start := time.now()
	if !native_inspector_render(state.inspector, state.surface_renderer, command, swapchain, swap_w, swap_h,
		scale_x, scale_y, scratch_allocator=state.host_scratch.allocator) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		fail("Alicorn visual inspector live-resize draw failed")
	}
	if native_inspector_visible(state.inspector) {
		state.timing.inspector_encode_ns += u64(time.duration_nanoseconds(time.since(inspector_start)))
	}
	native_timing_accumulate(&state.timing.gpu_encode_ns, &state.timing.gpu_encode_max_ns,
		u64(time.duration_nanoseconds(time.since(encode_start))))
	submit_start := time.now()
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	native_timing_accumulate(&state.timing.gpu_submit_ns, &state.timing.gpu_submit_max_ns,
		u64(time.duration_nanoseconds(time.since(submit_start))))
	if fence == nil { fail("SDL live-resize frame submission failed") }
	append(state.in_flight, Native_In_Flight{fence})
	native_text_commit_submission(state.text_renderer)
	native_surface_commit_submission(state.surface_renderer)
	native_solid_commit_submission(state.solid_renderer)
	native_inspector_submission_succeeded(state.inspector)
	if native_inspector_visible(state.inspector) { state.timing.inspector_submissions += 1 }
	if application_submission_pending {
		alicorn.gpu_surface_frame_consumed(state.rt)
		alicorn.frame_submission_succeeded(state.rt)
		state.rt.stats.gpu_submits += 1
	}
	if state.submitted != nil { state.submitted^ += 1 }
	state.timing.gpu_submissions += 1
	if application_submission_pending {
		post_submit_summary := native_inspector_host_summary(state.timing, state.rt, state.timing.frames)
		native_inspector_update(state.inspector, state.rt,
			alicorn.Rect{0, 0, f32(current_metrics.logical_width), f32(current_metrics.logical_height)}, &post_submit_summary)
	}
	if state.max_in_flight != nil && len(state.in_flight^) > state.max_in_flight^ {
		state.max_in_flight^ = len(state.in_flight^)
	}
	native_timing_add_frame(state.timing, u64(time.duration_nanoseconds(time.since(frame_start))))
	if state.devtools_recorder != nil && state.devtools_cursor != nil && state.text_events != nil {
		native_devtools_record_wake(
			state.devtools_recorder, state.devtools_cursor, state.rt, state.timing, state.text_events,
			cause, u64(sdl3.GetTicksNS()), 1,
		)
	}
}

native_live_resize_event_watch :: proc "c" (userdata: rawptr, event: ^sdl3.Event) -> bool {
	// AddEventWatch can run from arbitrary producer threads for most events.
	// Filter those without touching host state; SDL guarantees live-resize
	// WINDOW_EXPOSED events arrive on the main thread for direct redraw.
	if event == nil || event.type != .WINDOW_EXPOSED || event.window.data1 != 1 { return true }
	state := cast(^Native_Live_Resize_State)userdata
	if state == nil || !state.active || state.window == nil || event.window.windowID != sdl3.GetWindowID(state.window) {
		return true
	}
	if state.rendering {
		state.pending = true
		return true
	}
	context = runtime.default_context()
	native_live_resize_redraw(state)
	return true
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

// SDL's live-resize expose callback runs while the platform's interactive
// sizing loop has control. Keep the host references together so that callback
// can rebuild and submit one current frame without entering the normal event
// loop recursively.
Native_Live_Resize_State :: struct {
	active: bool,
	rendering: bool,
	pending: bool,
	window: ^sdl3.Window,
	device: ^sdl3.GPUDevice,
	rt: ^alicorn.Runtime,
	application: ^Application,
	metrics: ^Window_Metrics,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	text_input_state: ^Native_Text_Input_State,
	timing: ^Native_Host_Timing,
	host_scratch: ^Native_Host_Scratch,
	in_flight: ^[dynamic; 3]Native_In_Flight,
	retired: ^int,
	max_in_flight: ^int,
	query_before_wait_true: ^int,
	query_after_wait_true: ^int,
	wait_count: ^int,
	submitted: ^int,
	text_events: ^Native_Text_Event_Telemetry,
	devtools_recorder: ^Native_Flight_Recorder,
	devtools_cursor: ^Native_DevTools_Cursor,
	devtools_hud: ^Native_DevTools_HUD,
	inspector: ^Native_Inspector_Overlay,
	native_menu: ^Native_Menu_Runtime,
	debug_bounds: bool,
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
