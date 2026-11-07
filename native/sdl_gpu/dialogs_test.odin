package alicorn_sdl_gpu

import "core:c"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import "vendor:sdl3"

dialog_message_box_test_show :: proc "c" (#by_ptr data: sdl3.MessageBoxData, selected: ^c.int) -> bool {
	_ = data
	selected^ = 42
	return true
}

@(test)
test_native_message_box_returns_selected_button_id :: proc(t: ^testing.T) {
	button_id, ok := dialog_show_message_box_result({}, dialog_message_box_test_show)
	testing.expect(t, ok, "message-box result should preserve SDL's success status")
	testing.expect(t, button_id == 42, "message-box result should read the selected ID after SDL writes it")
}

@(test)
test_native_file_dialog_callback_uses_request_id_after_destroy :: proc(t: ^testing.T) {
	bridge := native_dialog_bridge_make(nil, {})
	if bridge == nil {
		testing.expect(t, false, "the native dialog bridge should initialize")
		return
	}
	request := new(Native_Dialog_Request, allocator=bridge.allocator)
	request.bridge = bridge
	request.id = Dialog_ID(42)
	sync.mutex_lock(&bridge.mutex)
	bridge.refs += 1 // the in-flight callback owns a reference
	bridge.active = true
	bridge.active_id = request.id
	sync.mutex_unlock(&bridge.mutex)

	native_dialog_file_callback(rawptr(request), nil, 0)
	testing.expect(t, len(bridge.completions) == 1,
		"an SDL error callback should queue exactly one completion")
	if len(bridge.completions) == 1 {
		testing.expect(t, bridge.completions[0].id == Dialog_ID(42),
			"the completion should retain the request ID after the request is destroyed")
		testing.expect(t, bridge.completions[0].status == .Error,
			"a nil SDL file list should be reported as an error")
	}
	testing.expect(t, !bridge.active && bridge.active_id == 0,
		"completion should release the active-dialog slot")
	native_dialog_bridge_release(bridge)
}

@(test)
test_native_show_file_dialog_survives_synchronous_sdl_error_callback :: proc(t: ^testing.T) {
	bridge := native_dialog_bridge_make(nil, {})
	if bridge == nil {
		testing.expect(t, false, "the native dialog bridge should initialize")
		return
	}
	filters := [1]Dialog_Filter{{"Invalid extension", "bad/path"}}
	accepted := ShowFileDialog(
		Dialog_Service{handle=rawptr(bridge)},
		File_Dialog_Request{id=Dialog_ID(73), kind=.Open_File, filters=filters[:]},
	)
	testing.expect(t, accepted, "the dialog request should reach SDL even when SDL reports an inline error")
	testing.expect(t, len(bridge.completions) == 1,
		"the invalid-filter callback should complete synchronously on this SDL error path")
	if len(bridge.completions) == 1 {
		testing.expect(t, bridge.completions[0].id == Dialog_ID(73) && bridge.completions[0].status == .Error,
			"the synchronous callback should preserve its request ID and error status")
	}
	testing.expect(t, !bridge.active && bridge.active_id == 0,
		"the synchronous callback should release the active-dialog slot before SDL returns")
	native_dialog_bridge_release(bridge)
}

Native_Dialog_Shutdown_Test_State :: struct {
	bridge:    ^Native_Dialog_Bridge,
	mutex:     sync.Mutex,
	cond:      sync.Cond,
	completed: bool,
}

native_dialog_shutdown_test_thread :: proc(t: ^thread.Thread) {
	state := cast(^Native_Dialog_Shutdown_Test_State)t.data
	native_dialog_bridge_shutdown(state.bridge)

	sync.mutex_lock(&state.mutex)
	state.completed = true
	sync.cond_broadcast(&state.cond)
	sync.mutex_unlock(&state.mutex)
}

@(test)
test_native_dialog_shutdown_waits_for_copied_waker :: proc(t: ^testing.T) {
	// Model a callback that already copied the host waker. Shutdown must not
	// return until that callback has finished invoking it.
	bridge := Native_Dialog_Bridge{accepting=true, wakes_in_flight=1}
	state := Native_Dialog_Shutdown_Test_State{bridge=&bridge}
	worker := thread.create(native_dialog_shutdown_test_thread)
	if worker == nil {
		testing.expect(t, false, "shutdown regression thread should start")
		return
	}
	worker.data = rawptr(&state)
	thread.start(worker)
	defer thread.destroy(worker)

	// The bridge condition is signalled when shutdown closes admission. Since
	// shutdown holds this mutex through its in-flight-wake wait, acquiring it
	// after the signal proves the worker is blocked on the copied wake.
	sync.mutex_lock(&bridge.mutex)
	for bridge.accepting {
		sync.cond_wait(&bridge.wake_cond, &bridge.mutex)
	}
	shutdown_waiting := bridge.wakes_in_flight == 1
	sync.mutex_unlock(&bridge.mutex)
	testing.expect(t, shutdown_waiting, "shutdown should disable new callbacks while waiting for the copied waker")

	// Give a shutdown implementation that fails to wait time to return and
	// publish completion. The correct implementation remains blocked here.
	sync.mutex_lock(&state.mutex)
	if !state.completed {
		_ = sync.cond_wait_with_timeout(&state.cond, &state.mutex, 20*time.Millisecond)
	}
	completed_before_wake := state.completed
	sync.mutex_unlock(&state.mutex)
	testing.expect(t, !completed_before_wake, "shutdown must remain blocked until the copied waker returns")

	native_dialog_bridge_finish_wake(&bridge)
	thread.join(worker)
	sync.mutex_lock(&state.mutex)
	completed_after_wake := state.completed
	sync.mutex_unlock(&state.mutex)
	testing.expect(t, completed_after_wake, "shutdown should finish once the callback releases its in-flight wake")
}
