package ui

import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"
import "core:testing"
import alicorn "alicorn:runtime"

Run_Wake_Test_Queue :: struct {
	available: sync.Sema,
	live: bool,
	woke_while_live: bool,
	count: int,
}

run_test_enqueue_wake :: proc(data: rawptr) {
	queue := cast(^Run_Wake_Test_Queue)data
	queue.woke_while_live = queue.live
	queue.count += 1
	sync.sema_post(&queue.available)
}

Run_Lifecycle_Test_App :: struct {
	worker: ^thread.Thread,
	release_worker: sync.Sema,
	mutex: sync.Mutex,
	waker: Application_Waker,
	ready: bool,
	result, adopted: int,
	starts, wakes, stops, renders: int,
	joined: bool,
	text: Node_ID,
}

run_lifecycle_test_worker :: proc(data: rawptr) {
	app := cast(^Run_Lifecycle_Test_App)data
	sync.sema_wait(&app.release_worker)
	sync.mutex_lock(&app.mutex)
	app.result = 42
	app.ready = true
	sync.mutex_unlock(&app.mutex)
	wake(app.waker)
}

run_lifecycle_test_start :: proc(app: ^Run_Lifecycle_Test_App, waker: Application_Waker) {
	app.starts += 1
	app.waker = waker
	app.worker = thread.create_and_start_with_data(rawptr(app), run_lifecycle_test_worker)
}

run_lifecycle_test_wake :: proc(app: ^Run_Lifecycle_Test_App, ctx: Application_Context) {
	app.wakes += 1
	sync.mutex_lock(&app.mutex)
	ready, result := app.ready, app.result
	sync.mutex_unlock(&app.mutex)
	if ready && app.adopted != result {
		app.adopted = result
		invalidate(ctx, "adopt test worker completion")
	}
}

run_lifecycle_test_stop :: proc(app: ^Run_Lifecycle_Test_App) {
	app.stops += 1
	if app.worker != nil {
		sync.sema_post(&app.release_worker)
		thread.join(app.worker)
		thread.destroy(app.worker)
		app.worker = nil
		app.joined = true
	}
}

run_lifecycle_test_render :: proc(app: ^Run_Lifecycle_Test_App, ctx: ^UI) {
	app.renders += 1
	app.text = text(ctx, fmt.tprintf("Result: %d", app.adopted))
}

@(test)
test_typed_wake_adopts_result_with_explicit_invalidation_and_returns_to_idle :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	app := Run_Lifecycle_Test_App{}
	state := Run_State(Run_Lifecycle_Test_App){app=&app, render=run_lifecycle_test_render,
		on_start=run_lifecycle_test_start, on_wake=run_lifecycle_test_wake, on_stop=run_lifecycle_test_stop}
	application := run_application(&state, "Async test", 240, 120)
	queue := Run_Wake_Test_Queue{live=true}
	application.on_start(application.state, Application_Waker{data=rawptr(&queue), wake=run_test_enqueue_wake})
	defer application.on_stop(application.state)
	if app.worker == nil { testing.expect(t, false, "the app-owned worker must start"); return }
	testing.expect(t, application.build(application.state, &rt, 240, 120, 1) != 0 && app.renders == 1 && app.starts == 1)
	application.on_wake(application.state, &rt)
	testing.expect(t, application.build(application.state, &rt, 240, 120, 1) == 0 && app.renders == 1,
		"a wake without adopted data must not implicitly invalidate or describe the app")
	sync.sema_post(&app.release_worker)
	if !sync.sema_wait_with_timeout(&queue.available, 5*time.Second) {
		testing.expect(t, false, "the worker must publish and request one host event"); return
	}
	wake_cause := alicorn.cause_begin(&rt, .Async_Wake, "application wake event")
	application.on_wake(application.state, &rt)
	alicorn.cause_end(&rt, wake_cause)
	testing.expect(t, rt.pending_work_cause.id == wake_cause.cause.id,
		"explicit invalidation through the typed context must retain the native wake's causal attribution")
	testing.expect(t, application.build(application.state, &rt, 240, 120, 1) != 0 && app.adopted == 42 && app.renders == 2 && queue.count == 1)
	value, found := alicorn.node_info(&rt, app.text)
	testing.expect(t, found && value.active && rt.nodes[app.text].text == "Result: 42",
		"the first adopted description must contain the worker's completed result")
	before := rt.allocation_stats^
	for _ in 0..<10 {
		testing.expect(t, application.build(application.state, &rt, 240, 120, 1) == 0)
	}
	testing.expect(t, app.renders == 2 && rt.allocation_stats.persistent_alloc_calls == before.persistent_alloc_calls &&
		rt.allocation_stats.scratch_alloc_calls == before.scratch_alloc_calls,
		"after result adoption the bridge must perform no descriptions or allocations while idle")
}

@(test)
test_typed_stop_joins_a_worker_that_wakes_during_shutdown :: proc(t: ^testing.T) {
	app := Run_Lifecycle_Test_App{}
	state := Run_State(Run_Lifecycle_Test_App){app=&app, render=run_lifecycle_test_render,
		on_start=run_lifecycle_test_start, on_stop=run_lifecycle_test_stop}
	application := run_application(&state, "Shutdown test", 240, 120)
	queue := Run_Wake_Test_Queue{live=true}
	application.on_start(application.state, Application_Waker{data=rawptr(&queue), wake=run_test_enqueue_wake})
	application.on_stop(application.state)
	queue.live = false // The host retires the borrowed backing state only now.
	testing.expect(t, app.starts == 1 && app.stops == 1 && app.joined && app.worker == nil && queue.count == 1 && queue.woke_while_live,
		"typed shutdown must finish the app-owned join while late producer wakes remain valid")
}

@(test)
test_runner_keeps_optional_hooks_absent_and_preserves_simple_app_policy :: proc(t: ^testing.T) {
	app := Run_Lifecycle_Test_App{}
	state := Run_State(Run_Lifecycle_Test_App){app=&app, render=run_lifecycle_test_render}
	application := run_application(&state, "Simple test", 240, 120)
	testing.expect(t, application.on_start == nil && application.on_wake == nil && application.on_stop == nil && application.on_tick == nil &&
		application.interaction_update_policy == .Correct_After_Interaction,
		"ordinary ui.run users must retain the existing policy and no polling or synthetic lifecycle callbacks")
	wake(Application_Waker{})
	invalidate(Application_Context(nil))
}
