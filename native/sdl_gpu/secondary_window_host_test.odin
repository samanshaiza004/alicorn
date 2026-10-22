package alicorn_sdl_gpu

import "core:sync"
import "core:testing"
import "core:thread"
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
	child.event_queue = make([dynamic]Native_Secondary_Window_Queued_Event, 0, allocator=context.allocator)
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

@(test)
test_secondary_window_event_queue_owns_variable_text_payloads :: proc(t: ^testing.T) {
	child := Native_Secondary_Window{active=true}
	child.event_queue = make([dynamic]Native_Secondary_Window_Queued_Event, 0, allocator=context.allocator)
	defer delete(child.event_queue)
	manager := Native_Secondary_Window_Manager{child=&child}

	committed := [6]u8{'h', 'e', 'l', 'l', 'o', 0}
	commit := sdl3.Event{type=.TEXT_INPUT}
	commit.text.text = cast(cstring)raw_data(committed[:])
	testing.expect(t, native_secondary_window_enqueue_event(&manager, commit), "the child should accept committed text")
	committed[0] = 'x'
	got: sdl3.Event
	testing.expect(t, native_secondary_window_pop_event(&child, &got), "the committed text event should dequeue")
	testing.expect(t, string(got.text.text) == "hello", "queued committed text must not borrow SDL's temporary event payload")

	preedit_bytes := [5]u8{'i', 'm', 'e', 0, 0}
	preedit := sdl3.Event{type=.TEXT_EDITING}
	preedit.edit.text = cast(cstring)raw_data(preedit_bytes[:])
	preedit.edit.start = 1
	preedit.edit.length = 1
	testing.expect(t, native_secondary_window_enqueue_event(&manager, preedit), "the child should accept composition text")
	preedit_bytes[0] = 'x'
	testing.expect(t, native_secondary_window_pop_event(&child, &got), "the composition event should dequeue")
	testing.expect(t, string(got.edit.text) == "ime" && got.edit.start == 1 && got.edit.length == 1,
		"queued composition text must retain its bytes and selection range")

	first_candidate := [4]u8{'o', 'n', 'e', 0}
	second_candidate := [4]u8{'t', 'w', 'o', 0}
	candidate_pointers := [2]cstring{
		cast(cstring)raw_data(first_candidate[:]),
		cast(cstring)raw_data(second_candidate[:]),
	}
	candidates := sdl3.Event{type=.TEXT_EDITING_CANDIDATES}
	candidates.edit_candidates.candidates = raw_data(candidate_pointers[:])
	candidates.edit_candidates.num_candidates = 2
	candidates.edit_candidates.selected_candidate = 1
	testing.expect(t, native_secondary_window_enqueue_event(&manager, candidates), "the child should accept composition candidates")
	first_candidate[0] = 'x'
	second_candidate[0] = 'x'
	candidate_pointers[0] = cast(cstring)raw_data(second_candidate[:])
	testing.expect(t, native_secondary_window_pop_event(&child, &got), "the candidates event should dequeue")
	testing.expect(t, got.edit_candidates.num_candidates == 2 &&
		string(got.edit_candidates.candidates[0]) == "one" &&
		string(got.edit_candidates.candidates[1]) == "two" &&
		got.edit_candidates.selected_candidate == 1,
		"queued candidate strings and their pointer array must be independently owned")
	testing.expect(t, !native_secondary_window_pop_event(&child, &got), "draining owned text events should release the replay payload")

	pending := sdl3.Event{type=.TEXT_INPUT}
	pending.text.text = cast(cstring)raw_data(committed[:])
	testing.expect(t, native_secondary_window_enqueue_event(&manager, pending), "the child should accept text before queue teardown")
	native_secondary_window_event_queue_clear(&child)
	testing.expect(t, len(child.event_queue) == 0 && child.event_queue_read == 0 && child.replay_event.owned_text == nil,
		"destroying an undrained child queue should release its owned event payloads")
}

Secondary_Window_Stop_Probe :: struct {
	child: ^Native_Secondary_Window,
	application_waker_active: bool,
	host_waker_active: bool,
	stop_worker: u32,
	waker_reads: u64,
	worker: ^thread.Thread,
	worker_joined: bool,
}

secondary_window_waker_probe_thread :: proc(t: ^thread.Thread) {
	probe := cast(^Secondary_Window_Stop_Probe)t.data
	for sync.atomic_load(&probe.stop_worker) == 0 {
		_ = probe.child.wake_state.active
		sync.atomic_add(&probe.waker_reads, 1)
	}
}

secondary_window_stop_probe :: proc(state: rawptr) {
	probe := cast(^Secondary_Window_Stop_Probe)state
	probe.application_waker_active = probe.child.wake_state.active
	probe.host_waker_active = probe.child.host_wake_state.active
	sync.atomic_store(&probe.stop_worker, 1)
	thread.join(probe.worker)
	probe.worker_joined = true
}

@(test)
test_secondary_window_wakers_remain_live_until_application_stop :: proc(t: ^testing.T) {
	child := new(Native_Secondary_Window, allocator=context.allocator)
	child^ = Native_Secondary_Window{
		active=true,
		callbacks_started=true,
		wake_state=Native_Application_Waker{event_type=sdl3.EventType(0x8001), active=true},
		host_wake_state=Native_Host_Event_Waker{event_type=sdl3.EventType(0x8002), active=true},
	}
	probe := Secondary_Window_Stop_Probe{child=child}
	probe.worker = thread.create(secondary_window_waker_probe_thread)
	if probe.worker == nil {
		testing.expect(t, false, "the secondary wake regression worker should start")
		free(child, allocator=context.allocator)
		return
	}
	defer thread.destroy(probe.worker)
	probe.worker.data = rawptr(&probe)
	thread.start(probe.worker)
	for sync.atomic_load(&probe.waker_reads) == 0 {}
	child.application = Application{state=rawptr(&probe), on_stop=secondary_window_stop_probe}
	manager := Native_Secondary_Window_Manager{child=child}

	native_secondary_window_destroy(&manager, wait_for_gpu=false)

	testing.expect(t, probe.application_waker_active,
		"on_stop must be able to join producers while the application waker remains valid")
	testing.expect(t, probe.host_waker_active,
		"on_stop must complete before host wake state begins teardown")
	testing.expect(t, probe.worker_joined && sync.atomic_load(&probe.stop_worker) != 0,
		"on_stop must join the worker before secondary destruction continues")
	testing.expect(t, manager.child == nil,
		"secondary destruction should release the child after on_stop completes")
}
