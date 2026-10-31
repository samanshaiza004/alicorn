package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import alicorn "../../runtime"

Bench_Allocator_State :: struct {
	backing: mem.Allocator,
	allocations: u64,
	allocated_bytes: u64,
}

@(private)
allocator_state: Bench_Allocator_State

bench_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	state := (^Bench_Allocator_State)(data)
	result, err := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, loc)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		state.allocations += 1
		state.allocated_bytes += u64(size)
	}
	return result, err
}

bench_allocator :: proc(state: ^Bench_Allocator_State) -> mem.Allocator {
	return mem.Allocator{procedure=bench_allocator_proc, data=state}
}

fail :: proc(message: string) {
	fmt.println("MOTION BENCHMARK FAILURE:", message)
	os.exit(1)
}

build_motion_owners :: proc(count: int) -> (rt: alicorn.Runtime, handles: []alicorn.Motion_Owner_Handle) {
	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 1600, 1400}, alicorn.Runtime_Config{trace_capacity=256})
	nodes := make([]alicorn.Node_ID, count, allocator=context.temp_allocator)
	handles = make([]alicorn.Motion_Owner_Handle, count, allocator=context.temp_allocator)
	ui, build := alicorn.begin_frame(&rt)
	if !build { fail("fresh runtime unexpectedly skipped its initial description"); return }
	alicorn.container_begin_ex(&ui, .Root, label="motion benchmark", key="motion-benchmark-root",
		explicit_key=true, style=alicorn.layout_style(.Column, width=1500, height=1300))
	for index in 0..<count {
		key := fmt.tprintf("owner-%d", index)
		nodes[index] = alicorn.container_begin_ex(&ui, .Container, key=key, explicit_key=true,
			style=alicorn.layout_style(.Row, width=20, height=1))
		alicorn.container_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if rt.diagnostic != "" { fail(rt.diagnostic); return }

	_ = alicorn.motion_clock_set_time(&rt, alicorn.Motion_Time(0))
	config := alicorn.Motion_Config{omega=2, position_tolerance=0.001, velocity_tolerance=0.01}
	// MOTION_SETUP_DIAGNOSTICS_BEFORE
	setup_started := time.now()
	setup_allocations_before := allocator_state.allocations
	setup_bytes_before := allocator_state.allocated_bytes
	for index in 0..<count {
		handle, status := alicorn.motion_owner_begin(&rt, nodes[index])
		if status != .Ok { fail(fmt.tprintf("owner %d rejected: %v", index, status)); return }
		handles[index] = handle
		status = alicorn.motion_target_translation(&rt, handle,
			alicorn.Motion_Vector2{96 + f64(index%7), 0}, config, .Settle, alicorn.Motion_Time(0))
		if status != .Ok { fail(fmt.tprintf("target %d rejected: %v", index, status)); return }
	}
	setup_ns := time.duration_nanoseconds(time.since(setup_started))
	fmt.printf("owner_setup count=%d ns=%d allocations=%d allocated_bytes=%d\n",
		count, setup_ns, allocator_state.allocations-setup_allocations_before,
		allocator_state.allocated_bytes-setup_bytes_before)
	// MOTION_SETUP_DIAGNOSTICS_AFTER
	activity := alicorn.motion_activity(&rt)
	if activity.active_owners != count || activity.active_properties != count {
		fail(fmt.tprintf("expected %d active owners/properties, got %d/%d", count, activity.active_owners, activity.active_properties))
	}
	return
}

measure_active_sampling :: proc(count: int) {
	rt, _ := build_motion_owners(count)
	defer alicorn.destroy_runtime(&rt)
	latencies := make([]i64, 180, allocator=context.temp_allocator)
	tick_allocations: u64
	tick_bytes: u64
	ack_allocations: u64
	ack_bytes: u64
	frames_before := rt.stats.frames_built
	reconcile_before := rt.stats.reconcile_nodes_visited
	measure_before := rt.stats.measure_requests
	shape_before := rt.stats.text_shape_requests
	layout_before := rt.stats.layout_nodes_visited
	paint_before := rt.stats.paint_nodes_visited
	compose_before := rt.stats.composition_nodes_visited
	// MOTION_SAMPLE_DIAGNOSTICS_BEFORE
	for sample in 0..<len(latencies) {
		at := alicorn.Motion_Time(i64(sample+1)*16_666_667)
		started := time.now()
		allocations_before_tick := allocator_state.allocations
		bytes_before_tick := allocator_state.allocated_bytes
		result := alicorn.motion_tick(&rt, at)
		latencies[sample] = time.duration_nanoseconds(time.since(started))
		tick_allocations += allocator_state.allocations-allocations_before_tick
		tick_bytes += allocator_state.allocated_bytes-bytes_before_tick
		if result.status != .Ok { fail(fmt.tprintf("sample %d failed: %v", sample, result.status)) }
		allocations_before_ack := allocator_state.allocations
		bytes_before_ack := allocator_state.allocated_bytes
		alicorn.frame_submission_succeeded(&rt)
		ack_allocations += allocator_state.allocations-allocations_before_ack
		ack_bytes += allocator_state.allocated_bytes-bytes_before_ack
	}
	activity := alicorn.motion_activity(&rt)
	fmt.printf("tick_summary count=%d samples=%d active_after=%d frame_builds=%d reconcile_visits=%d measure_requests=%d text_shapes=%d layout_visits=%d paint_visits=%d composition_visits=%d tick_allocations=%d tick_bytes=%d ack_allocations=%d ack_bytes=%d\n",
		count, len(latencies), activity.active_owners,
		rt.stats.frames_built-frames_before,
		rt.stats.reconcile_nodes_visited-reconcile_before,
		rt.stats.measure_requests-measure_before,
		rt.stats.text_shape_requests-shape_before,
		rt.stats.layout_nodes_visited-layout_before,
		rt.stats.paint_nodes_visited-paint_before,
		rt.stats.composition_nodes_visited-compose_before,
		tick_allocations, tick_bytes, ack_allocations, ack_bytes)
	for sample in 0..<len(latencies) { fmt.printf("tick_sample count=%d ns=%d\n", count, latencies[sample]) }
	// MOTION_SAMPLE_DIAGNOSTICS_AFTER
	settled := alicorn.motion_tick(&rt, alicorn.Motion_Time(30_000_000_000))
	if settled.status != .Ok { fail("fast-forward settlement sample failed") }
	activity = alicorn.motion_activity(&rt)
	if activity.active_owners != 0 || activity.active_properties != 0 { fail("large timestamp did not settle all owners") }
	// No additional sample call occurs after settlement. The native scheduler's
	// deadline/wake behavior is measured separately by the #146 host fixture.
	fmt.printf("settled_idle count=%d active_owners=%d active_properties=%d sampled_ticks_after_settle=0\n",
		count, activity.active_owners, activity.active_properties)
}

measure_target_churn :: proc(changes: int) {
	rt, handles := build_motion_owners(1)
	defer alicorn.destroy_runtime(&rt)
	handle := handles[0]
	latencies := make([]i64, changes, allocator=context.temp_allocator)
	config := alicorn.Motion_Config{omega=2, position_tolerance=0.001, velocity_tolerance=0.01}
	retarget_allocations: u64
	retarget_bytes: u64
	ack_allocations: u64
	ack_bytes: u64
	// MOTION_CHURN_DIAGNOSTICS_BEFORE
	for index in 0..<changes {
		at := alicorn.Motion_Time(i64(index+1)*1_000_000)
		x := f64(220) if index%2 == 0 else f64(80)
		started := time.now()
		allocations_before_retarget := allocator_state.allocations
		bytes_before_retarget := allocator_state.allocated_bytes
		status := alicorn.motion_target_translation(&rt, handle, alicorn.Motion_Vector2{x, 0}, config, .Settle, at)
		latencies[index] = time.duration_nanoseconds(time.since(started))
		retarget_allocations += allocator_state.allocations-allocations_before_retarget
		retarget_bytes += allocator_state.allocated_bytes-bytes_before_retarget
		if status != .Ok { fail(fmt.tprintf("retarget %d failed: %v", index, status)) }
		allocations_before_ack := allocator_state.allocations
		bytes_before_ack := allocator_state.allocated_bytes
		alicorn.frame_submission_succeeded(&rt)
		ack_allocations += allocator_state.allocations-allocations_before_ack
		ack_bytes += allocator_state.allocated_bytes-bytes_before_ack
	}
	activity := alicorn.motion_activity(&rt)
	fmt.printf("retarget_summary changes=%d active_after=%d retarget_allocations=%d retarget_bytes=%d ack_allocations=%d ack_bytes=%d\n",
		changes, activity.active_owners,
		retarget_allocations, retarget_bytes, ack_allocations, ack_bytes)
	for index in 0..<len(latencies) { fmt.printf("retarget_sample changes=%d ns=%d\n", changes, latencies[index]) }
	// MOTION_CHURN_DIAGNOSTICS_AFTER
}

main :: proc() {
	allocator_state = Bench_Allocator_State{backing=context.allocator}
	context.allocator = bench_allocator(&allocator_state)
	fmt.println("Alicorn motion diagnostics overhead benchmark (headless, no inspector instance)")
	fmt.println("timing uses monotonic per-operation elapsed time; allocations separate motion from submit acknowledgement")
	counts := [3]int{1, 100, 1000}
	for count in counts { measure_active_sampling(count) }
	measure_target_churn(1000)
	context.allocator = allocator_state.backing
}
