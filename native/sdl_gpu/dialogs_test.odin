package alicorn_sdl_gpu

import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

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
