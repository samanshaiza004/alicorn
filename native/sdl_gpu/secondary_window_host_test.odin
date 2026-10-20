package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

@(test)
test_secondary_unavailable_swapchain_does_not_force_idle_spin :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	child := Native_Secondary_Window{active=true, runtime=&rt, presentation_suspended=true}
	child.native_menu.chrome_redraw_pending = true
	manager := Native_Secondary_Window_Manager{child=&child}
	testing.expect(t, !native_secondary_window_has_work(&manager), "a hidden/minimized child must not keep the host polling for an unavailable swapchain")
	child.presentation_suspended = false
	testing.expect(t, native_secondary_window_has_work(&manager), "a restore/input event must make the retained pending frame eligible for submission")
	child.presentation_suspended = true
	manager.pending_close = true
	testing.expect(t, native_secondary_window_has_work(&manager), "closing a suspended child must still be processed immediately")
}

secondary_window_test_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	return 0
}

@(test)
test_secondary_window_topmost_updates_are_idempotent :: proc(t: ^testing.T) {
	plain := sdl3.WindowFlags{}
	topmost := sdl3.WindowFlags{.ALWAYS_ON_TOP}
	testing.expect(t, native_secondary_window_topmost_matches(plain, false),
		"requesting the current normal z-order should be a no-op")
	testing.expect(t, native_secondary_window_topmost_matches(topmost, true),
		"requesting the current topmost z-order should be a no-op")
	testing.expect(t, !native_secondary_window_topmost_matches(plain, true) &&
		!native_secondary_window_topmost_matches(topmost, false),
		"a changed topmost state should still reach SDL")
}

@(test)
test_secondary_window_event_routing_isolated_by_window_and_wake_id :: proc(t: ^testing.T) {
	child := Native_Secondary_Window{
		active=true,
		window_id=sdl3.WindowID(22),
		wake_state=Native_Application_Waker{event_type=sdl3.EventType(0x8001), active=true},
		host_wake_state=Native_Host_Event_Waker{event_type=sdl3.EventType(0x8002), active=true},
	}
	manager := Native_Secondary_Window_Manager{child=&child}

	primary_focus := sdl3.Event{type=.WINDOW_FOCUS_GAINED}
	primary_focus.window.windowID = sdl3.WindowID(11)
	child_focus := sdl3.Event{type=.WINDOW_FOCUS_GAINED}
	child_focus.window.windowID = sdl3.WindowID(22)
	child_scale := sdl3.Event{type=.WINDOW_DISPLAY_SCALE_CHANGED}
	child_scale.window.windowID = sdl3.WindowID(22)
	child_key := sdl3.Event{type=.KEY_DOWN}
	child_key.key.windowID = sdl3.WindowID(22)
	
	testing.expect(t, !native_secondary_window_routes_event(&manager, primary_focus), "primary focus must remain with the primary Runtime")
	testing.expect(t, native_secondary_window_routes_event(&manager, child_focus), "secondary focus events must route to the secondary Runtime")
	testing.expect(t, native_secondary_window_routes_event(&manager, child_scale), "display-scale changes must route by their SDL window ID")
	testing.expect(t, native_secondary_window_routes_event(&manager, child_key), "keyboard input must route by its focused window ID")

	child_wake := sdl3.Event{type=child.wake_state.event_type}
	child_host_wake := sdl3.Event{type=child.host_wake_state.event_type}
	other_wake := sdl3.Event{type=sdl3.EventType(0x8003)}
	testing.expect(t, native_secondary_window_routes_event(&manager, child_wake), "the secondary application wake must be routed to its own loop context")
	testing.expect(t, native_secondary_window_routes_event(&manager, child_host_wake), "secondary host wakeups must stay in the secondary context")
	testing.expect(t, !native_secondary_window_routes_event(&manager, other_wake), "an unrelated user event must not enter the secondary context")
}

@(test)
test_secondary_window_runtime_keeps_dpi_and_focus_independent :: proc(t: ^testing.T) {
	primary := alicorn.new_runtime(alicorn.Rect{0, 0, 1200, 760})
	defer alicorn.destroy_runtime(&primary)
	secondary := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 480})
	defer alicorn.destroy_runtime(&secondary)

	_ = alicorn.set_presentation_scale(&primary, 1, 1)
	_ = alicorn.set_presentation_scale(&secondary, 1.5, 1.5)
	primary_nodes := render_native_ui(&primary)
	secondary_nodes := render_native_ui(&secondary)
	_ = alicorn.focus(&primary, primary_nodes.field)
	testing.expect(t, alicorn.focused_node(&primary) == primary_nodes.field, "the primary Runtime should retain its own focus")
	testing.expect(t, alicorn.focused_node(&secondary) == 0, "focusing the primary Runtime must not focus the secondary Runtime")
	_ = alicorn.focus(&secondary, secondary_nodes.field)
	testing.expect(t, alicorn.focused_node(&secondary) == secondary_nodes.field, "the secondary Runtime should accept independent focus")
	testing.expect(t, alicorn.focused_node(&primary) == primary_nodes.field, "secondary focus must not steal primary retained focus")
	testing.expect(t, primary.presentation_scale_x == 1 && secondary.presentation_scale_x == 1.5 &&
		primary.viewport.w == 1200 && secondary.viewport.w == 640,
		"each Runtime should retain its own logical viewport and pixel presentation scale")
}

@(test)
test_secondary_window_request_is_deferred_single_slot_and_closable :: proc(t: ^testing.T) {
	manager: Native_Secondary_Window_Manager
	manager.device = cast(^sdl3.GPUDevice)rawptr(&manager)
	manager.primary_window = cast(^sdl3.Window)rawptr(&manager)
	service := Application_Window_Service{
		data=rawptr(&manager),
		open=native_secondary_window_open_request,
		close=native_secondary_window_close_request,
		set_always_on_top=native_secondary_window_set_always_on_top,
	}
	description := Application_Window_Description{
		application=Application{title="Inspector", build=secondary_window_test_build},
		width=500,
		height=360,
	}

	testing.expect(t, native_secondary_window_lifecycle(&manager) == .Vacant, "a new host should start without a secondary window")
	testing.expect(t, application_open_window(service, description), "the host should accept one valid deferred window request")
	testing.expect(t, manager.pending && manager.child == nil && native_secondary_window_lifecycle(&manager) == .Requested,
		"open requests should defer SDL/GPU creation to the host's safe point")
	testing.expect(t, !application_open_window(service, description), "the v1 host should reject a second live or pending secondary window")

	child := Native_Secondary_Window{active=true}
	manager.child = &child
	manager.pending = false
	manager.pending_close = false
	testing.expect(t, native_secondary_window_lifecycle(&manager) == .Live, "an active child context should report Live")
	application_close_window(service)
	testing.expect(t, manager.pending_close && native_secondary_window_lifecycle(&manager) == .Closing,
		"closing requests should transition the active child through Closing")
	manager.child = nil
	manager.pending_close = false
	native_secondary_window_request_storage_clear(&manager)
	testing.expect(t, native_secondary_window_lifecycle(&manager) == .Vacant, "closing should return the slot to Vacant for a later reopen")
}

@(test)
test_secondary_window_event_queue_is_bounded_and_preserves_order :: proc(t: ^testing.T) {
	child := Native_Secondary_Window{active=true}
	child.event_queue = make([dynamic]sdl3.Event, 0, allocator=context.allocator)
	defer delete(child.event_queue)
	manager := Native_Secondary_Window_Manager{child=&child}
	first := sdl3.Event{type=.WINDOW_FOCUS_GAINED}
	second := sdl3.Event{type=.WINDOW_DISPLAY_SCALE_CHANGED}

	testing.expect(t, native_secondary_window_enqueue_event(&manager, first), "the child should accept routed SDL events")
	testing.expect(t, native_secondary_window_enqueue_event(&manager, second), "the child should queue independent scale events")
	got: sdl3.Event
	testing.expect(t, native_secondary_window_pop_event(&child, &got) && got.type == first.type, "child events should retain FIFO order")
	testing.expect(t, native_secondary_window_pop_event(&child, &got) && got.type == second.type, "the second child event should follow the first")
	testing.expect(t, !native_secondary_window_pop_event(&child, &got), "draining the child queue should leave no stale input")
}
