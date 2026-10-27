package alicorn_sdl_gpu

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

// The first native secondary-window proof is intentionally bounded to one
// secondary window. A single host GPU device owns both swapchains; every
// window has its own Runtime, text/input state, metrics, and renderer resources.
// Application domain state remains owned by the application and is shared only
// when its window callback state explicitly points at the same owner.
NATIVE_SECONDARY_EVENT_CAPACITY :: 4096
Native_Secondary_Window_Queued_Event :: struct {
	event: sdl3.Event,
	allocator: mem.Allocator,
	owned_text: cstring,
	owned_candidates: []cstring,
}

Native_Secondary_Window :: struct {
	active: bool,
	presentation_suspended: bool,
	closing: bool,
	claimed: bool,
	callbacks_started: bool,
	window: ^sdl3.Window,
	window_id: sdl3.WindowID,
	application: Application,
	owned_title: string,
	runtime: ^alicorn.Runtime,
	metrics: Window_Metrics,
	native_menu: Native_Menu_Runtime,
	appearance_monitor: Native_Appearance_Monitor,
	text_renderer: Native_Text_Renderer,
	surface_renderer: Native_Surface_Renderer,
	solid_renderer: Native_Solid_Renderer,
	text_input_state: Native_Text_Input_State,
	pointer_modifier_state: sdl3.Keymod,
	pointer_button_state: Native_Pointer_Button_State,
	wake_state: Native_Application_Waker,
	host_wake_state: Native_Host_Event_Waker,
	scheduler_state: Native_Scheduled_Wake_State,
	application_waker: Application_Waker,
	application_scheduler: Application_Scheduler,
	dialog_bridge: ^Native_Dialog_Bridge,
	accessibility_host: Native_Accessibility_Host,
	accessibility_ready: bool,
	quit_requested: bool,
	event_queue: [dynamic]Native_Secondary_Window_Queued_Event,
	event_queue_read: int,
	replay_event: Native_Secondary_Window_Queued_Event,
	logical_resize_events: int,
	pixel_resize_events: int,
	scale_events: int,
	text_input_events: int,
	composition_events: int,
	platform_text: string,
	last_user_interaction_ns: u64,
	drag_autoscroll_deadline_ns: u64,
	last_tick_ns: u64,
	timing: Native_Host_Timing,
	flight_recorder: Native_Flight_Recorder,
	host_scratch: Native_Host_Scratch,
}

Native_Secondary_Window_Manager :: struct {
	device: ^sdl3.GPUDevice,
	primary_window: ^sdl3.Window,
	child: ^Native_Secondary_Window,
	pending: bool,
	pending_close: bool,
	pending_description: Application_Window_Description,
	pending_title: string,
	create_failures: int,
	event_overflows: int,
}

Native_Secondary_Window_Lifecycle :: enum { Vacant, Requested, Live, Closing }

native_secondary_window_lifecycle :: proc(manager: ^Native_Secondary_Window_Manager) -> Native_Secondary_Window_Lifecycle {
	if manager == nil { return .Vacant }
	if manager.child != nil && (manager.pending_close || manager.child.quit_requested || manager.child.closing) { return .Closing }
	if manager.child != nil && manager.child.active { return .Live }
	if manager.pending { return .Requested }
	return .Vacant
}

native_secondary_window_open_request :: proc(data: rawptr, description: Application_Window_Description) -> bool {
	manager := cast(^Native_Secondary_Window_Manager)data
	if manager == nil || manager.device == nil || manager.primary_window == nil ||
	   manager.child != nil || manager.pending || description.application.build == nil {
		return false
	}
	title := description.application.title
	if title == "" { title = "Alicorn tool window" }
	owned_title, err := strings.clone(title, context.allocator)
	if err != nil { return false }
	manager.pending_description = description
	manager.pending_description.application.title = owned_title
	manager.pending_title = owned_title
	manager.pending = true
	return true
}

native_secondary_window_close_request :: proc(data: rawptr) {
	manager := cast(^Native_Secondary_Window_Manager)data
	if manager == nil { return }
	manager.pending_close = true
}

native_secondary_window_topmost_matches :: proc(flags: sdl3.WindowFlags, requested: bool) -> bool {
	current := (flags & sdl3.WindowFlags{.ALWAYS_ON_TOP}) != sdl3.WindowFlags{}
	return current == requested
}

native_secondary_window_set_always_on_top :: proc(data: rawptr, always_on_top: bool) -> bool {
	manager := cast(^Native_Secondary_Window_Manager)data
	if manager == nil || manager.child == nil || !manager.child.active || manager.child.window == nil { return false }
	flags := sdl3.GetWindowFlags(manager.child.window)
	if native_secondary_window_topmost_matches(flags, always_on_top) { return true }
	return sdl3.SetWindowAlwaysOnTop(manager.child.window, always_on_top)
}

native_secondary_window_set_title :: proc(data: rawptr, title: string) -> bool {
	manager := cast(^Native_Secondary_Window_Manager)data
	if manager == nil || manager.child == nil || !manager.child.callbacks_started || manager.child.window == nil { return false }
	child := manager.child
	owned_title, err := strings.clone(title, context.allocator)
	if err != nil { return false }
	title_cstring, cstring_error := strings.clone_to_cstring(owned_title, context.temp_allocator)
	if cstring_error != nil {
		delete(owned_title, context.allocator)
		return false
	}
	if !sdl3.SetWindowTitle(child.window, title_cstring) {
		delete(owned_title, context.allocator)
		return false
	}
	if len(child.owned_title) > 0 { delete(child.owned_title, context.allocator) }
	child.owned_title = owned_title
	child.application.title = owned_title
	when ODIN_OS == .Windows {
		if child.native_menu.platform_data != nil {
			menu_state := cast(^Win32_Menu_State)child.native_menu.platform_data
			menu_state.title_text = owned_title
			menu_state.text_scale = 0
			// Resolve appearance after the application callback returns. A title
			// change during build must not re-enter a window's build context.
			native_menu_request_chrome_redraw(&child.native_menu)
		}
	}
	return true
}

native_secondary_window_has_work :: proc(manager: ^Native_Secondary_Window_Manager) -> bool {
	if manager == nil { return false }
	return manager.pending || manager.pending_close || (manager.child != nil && manager.child.active && !manager.child.presentation_suspended &&
		(manager.child.runtime.invalidated || alicorn.presentation_needs_frame(manager.child.runtime) ||
		 manager.child.native_menu.chrome_redraw_pending))
}

native_secondary_window_create :: proc(manager: ^Native_Secondary_Window_Manager) -> bool {
	if manager == nil || !manager.pending || manager.device == nil { return false }
	description := manager.pending_description
	application := description.application
	manager.pending = false
	created := false
	callbacks_started := false
	defer if !created {
		manager.create_failures += 1
		// Once callbacks have started, on_stop owns application-state cleanup.
		// The failure callback is only for failures before that lifecycle point.
		// This avoids double-disposing caller state when (for example) showing a
		// fully initialized native window fails after on_start has run.
		native_secondary_window_request_storage_clear(manager)
		if !callbacks_started && description.on_open_failed != nil {
			description.on_open_failed(description.application.state)
		}
	}
	if len(manager.pending_title) > 0 { application.title = manager.pending_title }
	width := description.width if description.width > 0 else (application.width if application.width > 0 else 640)
	height := description.height if description.height > 0 else (application.height if application.height > 0 else 480)
	title_cstring, title_error := strings.clone_to_cstring(application.title, context.temp_allocator)
	if title_error != nil {
		return false
	}
	flags := sdl3.WindowFlags{.HIDDEN, .RESIZABLE, .HIGH_PIXEL_DENSITY}
	if description.always_on_top { flags += {.ALWAYS_ON_TOP} }
	window := sdl3.CreateWindow(title_cstring, c.int(width), c.int(height), flags)
	if window == nil {
		return false
	}
	child := new(Native_Secondary_Window, allocator=context.allocator)
	if child == nil {
		sdl3.DestroyWindow(window)
		return false
	}
	manager.child = child
	child.window = window
	child.window_id = sdl3.GetWindowID(window)
	child.application = application
	when ODIN_OS == .Windows {
		if child.application.window_decorations == .Integrated_Title_Bar {
			child.native_menu = Native_Menu_Runtime{window=window, application=&child.application}
			if !native_menu_prepare(&child.native_menu) {
				native_secondary_window_destroy(manager, wait_for_gpu=false)
				return false
			}
		} else {
			child.application.menus = nil
			child.application.window_decorations = .System
		}
	} else {
		// Menus are application-global on macOS, and integrated child chrome is
		// currently implemented only by the per-window Win32 adapter.
		child.application.menus = nil
		child.application.window_decorations = .System
	}
	child.event_queue = make([dynamic]Native_Secondary_Window_Queued_Event, 0, allocator=context.allocator)
	child.host_scratch = native_host_scratch_make()
	child.last_tick_ns = u64(sdl3.GetTicksNS())
	child.scheduler_state = Native_Scheduled_Wake_State{active=true}
	child.application_scheduler = Application_Scheduler{
		data=rawptr(&child.scheduler_state),
		schedule=native_application_schedule_after,
		cancel=native_application_cancel_scheduled,
		read_stats=native_application_scheduler_stats,
	}
	if !sdl3.ClaimWindowForGPUDevice(manager.device, window) {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.claimed = true
	if !read_window_metrics(window, &child.metrics, child.native_menu.content_inset_top) {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.runtime = new(alicorn.Runtime, allocator=context.allocator)
	if child.runtime == nil {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.runtime^ = alicorn.new_runtime(
		alicorn.Rect{0, 0, f32(child.metrics.logical_width), f32(child.metrics.logical_height)},
	)
	_ = alicorn.set_presentation_scale(
		child.runtime,
		f32(child.metrics.pixel_width)/f32(child.metrics.logical_width),
		f32(child.metrics.pixel_height)/f32(child.metrics.window_logical_height),
	)
	if application.on_initialize != nil { application.on_initialize(application.state, child.runtime) }
	if !native_load_default_fonts(child.runtime) {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	format := sdl3.GetGPUSwapchainTextureFormat(manager.device, window)
	text_ok, surface_ok, solid_ok: bool
	child.text_renderer, text_ok = native_text_make(manager.device, format, child.runtime)
	if !text_ok {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.surface_renderer, surface_ok = native_surface_make(manager.device, format, child.runtime)
	if !surface_ok {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.solid_renderer, solid_ok = native_solid_make(manager.device, format, child.runtime)
	if !solid_ok {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.wake_state.event_type = sdl3.EventType(sdl3.RegisterEvents(1))
	child.wake_state.active = child.wake_state.event_type != sdl3.EventType(0)
	child.host_wake_state.event_type = sdl3.EventType(sdl3.RegisterEvents(1))
	child.host_wake_state.active = child.host_wake_state.event_type != sdl3.EventType(0)
	if !child.wake_state.active || !child.host_wake_state.active {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	child.application_waker = Application_Waker{data=rawptr(&child.wake_state), wake=native_application_wake}
	child.native_menu.host_waker = &child.host_wake_state
	child.native_menu.runtime = child.runtime
	when ODIN_OS == .Windows {
		if child.native_menu.application != nil &&
		   !native_menu_prepare_gpu(&child.native_menu, child.runtime, &child.text_renderer) {
			native_secondary_window_destroy(manager, wait_for_gpu=false)
			return false
		}
	}
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		if !native_appearance_monitor_init(&child.appearance_monitor, window, &child.host_wake_state, child.runtime) {
			fmt.println("appearance", "secondary native preference notifications unavailable; using default appearance inputs")
		}
		native_menu_accessibility_appearance_changed(
			&child.native_menu,
			child.appearance_monitor.snapshot.preferences.increased_contrast,
			request_redraw=false,
		)
	}
	child.dialog_bridge = native_dialog_bridge_make(window, child.application_waker)
	child.callbacks_started = true
	callbacks_started = true
	if application.on_services != nil {
		application.on_services(application.state, Application_Services{
			dialogs=Dialog_Service{handle=rawptr(child.dialog_bridge)},
			clipboard=native_clipboard_service(),
			scheduler=child.application_scheduler,
			quit=Application_Quit_Request{data=rawptr(&child.quit_requested), request=native_application_request_quit},
			windows=Application_Window_Service{
				data=rawptr(manager),
				open=native_secondary_window_open_request,
				close=native_secondary_window_close_request,
				set_always_on_top=native_secondary_window_set_always_on_top,
				set_title=native_secondary_window_set_title,
			},
		})
	}
	flags_now := sdl3.GetWindowFlags(window)
	child.text_input_state = Native_Text_Input_State{
		window_focused=(flags_now & sdl3.WindowFlags{.INPUT_FOCUS}) != sdl3.WindowFlags{},
		content_inset_top=child.native_menu.content_inset_top,
	}
	if application.on_start != nil { application.on_start(application.state, child.application_waker) }
	child.active = true
	alicorn.invalidate_root(child.runtime, "secondary native window initial frame")
	_ = native_application_build_until_stable(&child.application, child.runtime, &child.metrics, &child.timing)
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		child.accessibility_ready = native_accessibility_host_init(&child.accessibility_host, &child.host_wake_state)
		if child.accessibility_ready {
			if !native_accessibility_adapter_init(&child.accessibility_host, window) {
				fmt.println("accessibility", "secondary adapter initialization failed")
				child.accessibility_ready = false
			}
		}
	}
	if !sdl3.ShowWindow(window) || !sdl3.RaiseWindow(window) {
		native_secondary_window_destroy(manager, wait_for_gpu=false)
		return false
	}
	created = true
	return true
}

native_secondary_window_request_storage_clear :: proc(manager: ^Native_Secondary_Window_Manager) {
	if manager == nil { return }
	if len(manager.pending_title) > 0 { delete(manager.pending_title, context.allocator) }
	manager.pending_title = ""
	manager.pending_description = {}
}

native_secondary_window_stop_application :: proc(child: ^Native_Secondary_Window) {
	if child == nil { return }
	if child.callbacks_started && child.application.on_stop != nil {
		// Application workers may still use the borrowed waker while on_stop joins them.
		child.application.on_stop(child.application.state)
	}
}

native_secondary_window_deactivate_wakers :: proc(child: ^Native_Secondary_Window) {
	if child == nil { return }
	child.wake_state.active = false
	child.host_wake_state.active = false
}

native_secondary_window_gpu_release_safe :: proc(
	wait_requested: bool,
	device_available: bool,
	idle_wait_succeeded: bool,
) -> bool {
	return !wait_requested || !device_available || idle_wait_succeeded
}

native_secondary_window_destroy :: proc(manager: ^Native_Secondary_Window_Manager, wait_for_gpu := true) {
	if manager == nil || manager.child == nil { return }
	child := manager.child
	child.active = false
	child.scheduler_state.active = false
	for &pending in child.scheduler_state.pending { pending = false }
	native_secondary_window_stop_application(child)
	native_appearance_monitor_destroy(&child.appearance_monitor)
	native_accessibility_host_destroy(&child.accessibility_host)
	native_menu_destroy(&child.native_menu)
	if child.dialog_bridge != nil {
		native_dialog_bridge_shutdown(child.dialog_bridge)
		native_dialog_bridge_release(child.dialog_bridge)
		child.dialog_bridge = nil
	}
	// Accessibility shutdown waits for its callbacks; appearance shutdown above
	// stops its notifications. Keep the host waker alive until both producers
	// have been retired.
	native_secondary_window_deactivate_wakers(child)
	idle_wait_succeeded := true
	if wait_for_gpu && manager.device != nil {
		idle_wait_succeeded = sdl3.WaitForGPUIdle(manager.device)
	}
	if !native_secondary_window_gpu_release_safe(wait_for_gpu, manager.device != nil, idle_wait_succeeded) {
		fail("secondary window GPU idle wait failed before resource release")
	}
	native_solid_destroy(&child.solid_renderer)
	native_surface_destroy(&child.surface_renderer)
	native_text_destroy(&child.text_renderer)
	native_host_scratch_destroy(&child.host_scratch)
	if child.runtime != nil {
		alicorn.destroy_runtime(child.runtime)
		free(child.runtime, allocator=context.allocator)
		child.runtime = nil
	}
	if child.window != nil {
		if manager.device != nil && child.claimed { sdl3.ReleaseWindowFromGPUDevice(manager.device, child.window) }
		sdl3.DestroyWindow(child.window)
		child.window = nil
	}
	native_secondary_window_event_queue_clear(child)
	delete(child.event_queue)
	if len(child.owned_title) > 0 { delete(child.owned_title, context.allocator) }
	free(child, allocator=context.allocator)
	manager.child = nil
	if !manager.pending { native_secondary_window_request_storage_clear(manager) }
}

native_secondary_window_manager_destroy :: proc(manager: ^Native_Secondary_Window_Manager) {
	if manager == nil { return }
	native_secondary_window_destroy(manager, wait_for_gpu=true)
	native_secondary_window_request_storage_clear(manager)
}

native_secondary_window_queued_event_destroy :: proc(queued: ^Native_Secondary_Window_Queued_Event) {
	if queued == nil { return }
	if queued.owned_text != nil { delete(queued.owned_text, queued.allocator) }
	for candidate in queued.owned_candidates {
		if candidate != nil { _ = mem.delete_cstring(candidate, queued.allocator) }
	}
	if len(queued.owned_candidates) > 0 { delete(queued.owned_candidates, queued.allocator) }
	queued^ = {}
}

native_secondary_window_queued_event_copy :: proc(event: sdl3.Event) -> (queued: Native_Secondary_Window_Queued_Event, ok: bool) {
	queued.event = event
	queued.allocator = context.allocator
	#partial switch event.type {
	case .TEXT_INPUT:
		if event.text.text != nil {
			owned_text, err := strings.clone_to_cstring(string(event.text.text), context.allocator)
			if err != nil { return {}, false }
			queued.owned_text = owned_text
			queued.event.text.text = owned_text
		}
	case .TEXT_EDITING:
		if event.edit.text != nil {
			owned_text, err := strings.clone_to_cstring(string(event.edit.text), context.allocator)
			if err != nil { return {}, false }
			queued.owned_text = owned_text
			queued.event.edit.text = owned_text
		}
	case .TEXT_EDITING_CANDIDATES:
		count := int(event.edit_candidates.num_candidates)
		if count < 0 { return {}, false }
		if count == 0 {
			queued.event.edit_candidates.candidates = nil
			return queued, true
		}
		if event.edit_candidates.candidates == nil { return {}, false }
		owned_candidates, err := make([]cstring, count, context.allocator)
		if err != nil { return {}, false }
		queued.owned_candidates = owned_candidates
		for index in 0..<count {
			candidate := event.edit_candidates.candidates[index]
			if candidate == nil {
				native_secondary_window_queued_event_destroy(&queued)
				return {}, false
			}
			owned_candidate, err := strings.clone_to_cstring(string(candidate), context.allocator)
			if err != nil {
				native_secondary_window_queued_event_destroy(&queued)
				return {}, false
			}
			queued.owned_candidates[index] = owned_candidate
		}
		queued.event.edit_candidates.candidates = raw_data(queued.owned_candidates)
	}
	return queued, true
}

native_secondary_window_replay_event_clear :: proc(child: ^Native_Secondary_Window) {
	if child == nil { return }
	native_secondary_window_queued_event_destroy(&child.replay_event)
}

native_secondary_window_event_queue_clear :: proc(child: ^Native_Secondary_Window) {
	if child == nil { return }
	native_secondary_window_replay_event_clear(child)
	for index in child.event_queue_read..<len(child.event_queue) {
		native_secondary_window_queued_event_destroy(&child.event_queue[index])
	}
	clear(&child.event_queue)
	child.event_queue_read = 0
}

native_secondary_window_event_queue_full :: proc(manager: ^Native_Secondary_Window_Manager) -> bool {
	if manager == nil || manager.child == nil || !manager.child.active { return false }
	child := manager.child
	return len(child.event_queue)-child.event_queue_read >= NATIVE_SECONDARY_EVENT_CAPACITY
}

native_secondary_window_enqueue_event :: proc(manager: ^Native_Secondary_Window_Manager, event: sdl3.Event) -> bool {
	if manager == nil || manager.child == nil || !manager.child.active { return false }
	child := manager.child
	if native_secondary_window_event_queue_full(manager) {
		manager.event_overflows += 1
		// Motion samples are replaceable under overload. Never displace a
		// transition or committed text just to retain another motion sample.
		if event.type == .MOUSE_MOTION { return true }
		motion_index := -1
		for index in child.event_queue_read..<len(child.event_queue) {
			if child.event_queue[index].event.type == .MOUSE_MOTION {
				motion_index = index
				break
			}
		}
		if motion_index < 0 { return false }
		native_secondary_window_queued_event_destroy(&child.event_queue[motion_index])
		ordered_remove(&child.event_queue, motion_index)
	}
	queued, ok := native_secondary_window_queued_event_copy(event)
	if !ok { return false }
	// Reuse consumed slots even when delivery and enqueue interleave without
	// an empty pop; the backing queue must not grow with the read cursor.
	if len(child.event_queue) >= NATIVE_SECONDARY_EVENT_CAPACITY && child.event_queue_read > 0 {
		pending := len(child.event_queue)-child.event_queue_read
		copy(child.event_queue[:], child.event_queue[child.event_queue_read:])
		resize(&child.event_queue, pending)
		child.event_queue_read = 0
	}
	appended, _ := append(&child.event_queue, queued)
	if appended != 1 {
		native_secondary_window_queued_event_destroy(&queued)
		return false
	}
	return true
}

native_secondary_window_routes_event :: proc(manager: ^Native_Secondary_Window_Manager, event: sdl3.Event) -> bool {
	if manager == nil || manager.child == nil || !manager.child.active { return false }
	child := manager.child
	return event.type == child.wake_state.event_type || event.type == child.host_wake_state.event_type ||
		native_event_window_id(event) == child.window_id
}

native_secondary_window_pop_event :: proc(child: ^Native_Secondary_Window, event: ^sdl3.Event) -> bool {
	if child == nil || event == nil { return false }
	// The returned union may point at owned text in replay_event. Retain it
	// through dispatch and retire it on the next pop or at the end of the pump.
	native_secondary_window_replay_event_clear(child)
	if child.event_queue_read >= len(child.event_queue) {
		clear(&child.event_queue)
		child.event_queue_read = 0
		return false
	}
	queued := child.event_queue[child.event_queue_read]
	child.event_queue[child.event_queue_read] = {}
	child.replay_event = queued
	event^ = queued.event
	child.event_queue_read += 1
	return true
}

native_secondary_window_render :: proc(
	manager: ^Native_Secondary_Window_Manager,
	child: ^Native_Secondary_Window,
	debug_bounds := false,
) -> bool {
	if manager == nil || manager.device == nil || child == nil || !child.active || child.runtime == nil {
		return true
	}
	application_submission_pending := alicorn.frame_needs_submission(child.runtime)
	chrome_submission_pending := child.native_menu.chrome_redraw_pending
	if !application_submission_pending && !chrome_submission_pending { return true }
	command := sdl3.AcquireGPUCommandBuffer(manager.device)
	if command == nil { return false }
	swapchain: ^sdl3.GPUTexture
	swap_w, swap_h: sdl3.Uint32
	if !sdl3.AcquireGPUSwapchainTexture(command, child.window, &swapchain, &swap_w, &swap_h) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	if swapchain == nil || swap_w == 0 || swap_h == 0 {
		_ = sdl3.CancelGPUCommandBuffer(command)
		// Keep the unsubmitted frame for restore, but let the event loop sleep
		// while a minimized/hidden window has no drawable swapchain.
		child.presentation_suspended = true
		return true
	}
	child.presentation_suspended = false
	child.metrics.pixel_width = int(swap_w)
	child.metrics.pixel_height = int(swap_h)
	scale_x := f32(swap_w)/f32(max(child.metrics.logical_width, 1))
	scale_y := f32(swap_h)/f32(max(child.metrics.window_logical_height, 1))
	_ = alicorn.set_presentation_scale(child.runtime, scale_x, scale_y)
	if !draw_display_list(
		command, swapchain, swap_w, swap_h,
		&child.text_renderer, &child.surface_renderer, &child.solid_renderer,
		child.runtime.display[:], scale_x, scale_y,
		debug_bounds=debug_bounds,
		content_inset_top=child.native_menu.content_inset_top,
		native_menu=&child.native_menu,
		scratch_allocator=child.host_scratch.allocator,
	) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	if fence == nil { return false }
	if !sdl3.WaitForGPUFences(manager.device, true, &fence, 1) {
		sdl3.ReleaseGPUFence(manager.device, fence)
		return false
	}
	sdl3.ReleaseGPUFence(manager.device, fence)
	native_text_commit_submission(&child.text_renderer)
	native_surface_commit_submission(&child.surface_renderer)
	native_solid_commit_submission(&child.solid_renderer)
	if application_submission_pending {
		alicorn.gpu_surface_frame_consumed(child.runtime)
		alicorn.frame_submission_succeeded(child.runtime)
		child.runtime.stats.gpu_submits += 1
	}
	child.timing.gpu_submissions += 1
	child.native_menu.chrome_redraw_pending = false
	return true
}
