// Headless benchmark for the optional retained percentage-width sidecar.
// Build optimized and run five fresh processes for the #109 evidence record.
package main

import "core:fmt"
import "core:time"
import alicorn "alicorn:runtime"
import ui "alicorn:ui"

WARMUP_FRAMES :: 100
SAMPLE_FRAMES :: 2_000
PARENT_NARROW :: f32(800)
PARENT_WIDE :: f32(960)
CHILD_HEIGHT :: f32(2)
CHILD_COUNTS :: [5]int{1, 8, 32, 128, 256}

describe_frame :: proc(rt: ^alicorn.Runtime, parent_width: f32, children: int, percentage: bool) -> bool {
	alicorn.invalidate_root(rt, "issue 109 percentage sidecar benchmark")
	ctx, build := alicorn.begin_frame(rt)
	if !build { return false }
	alicorn.container_begin(&ctx, .Root, key="issue109-bench-root",
		style=alicorn.layout_style(.Column, width=1280, height=1600))
	region, reused := alicorn.region_begin(&ctx, "issue109-cached-region", 1,
		style=alicorn.layout_style(.Column, width=parent_width, height=1500))
	if region != 0 && !reused {
		start := len(rt.pending)
		for i in 0..<children {
			declaration := ui.sizing(width=ui.logical(PARENT_NARROW*0.5))
			if percentage { declaration = ui.sizing(width=ui.percent(0.5)) }
			if ui.layout_sized(&ctx, alicorn.layout_style(.Column, height=CHILD_HEIGHT),
				declaration, key=ui.key_u64(u64(i)), label="sidecar-benchmark-child") {}
		}
		alicorn.region_end(&ctx, region, reused, start)
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return true
}

sort_times :: proc(values: []u64) {
	// Insertion sort is sufficient for this 2,000-sample diagnostic and keeps
	// the benchmark independent of a sorting package's allocation behavior.
	for i in 1..<len(values) {
		value := values[i]
		j := i
		for j > 0 && values[j-1] > value {
			values[j] = values[j-1]
			j -= 1
		}
		values[j] = value
	}
}

measure_scenario :: proc(rt: ^alicorn.Runtime, children: int, percentage, resize: bool) -> (p95_ns: u64, persistent_alloc_calls: u64, persistent_live_delta_bytes: u64, layout_updates: u64, measures: u64) {
	width := PARENT_NARROW
	for i in 0..<WARMUP_FRAMES {
		if resize && i%2 == 1 { width = PARENT_WIDE } else { width = PARENT_NARROW }
		if !describe_frame(rt, width, children, percentage) { return }
	}

	samples := make([]u64, SAMPLE_FRAMES, allocator=context.temp_allocator)
	allocation_before := rt.allocation_stats^
	stats_before := rt.stats
	for i in 0..<SAMPLE_FRAMES {
		if resize && i%2 == 1 { width = PARENT_WIDE } else if resize { width = PARENT_NARROW } else { width = PARENT_NARROW }
		start := time.now()
		if !describe_frame(rt, width, children, percentage) { return }
		samples[i] = u64(time.duration_nanoseconds(time.since(start)))
	}
	allocation_after := rt.allocation_stats^
	stats_after := rt.stats
	sort_times(samples)
	p95_ns = samples[int(f32(len(samples)-1)*0.95)]
	persistent_alloc_calls = allocation_after.persistent_alloc_calls-allocation_before.persistent_alloc_calls
	persistent_live_delta_bytes = u64(max(allocation_after.persistent_requested_bytes_live-allocation_before.persistent_requested_bytes_live, 0))
	layout_updates = stats_after.layout_updates-stats_before.layout_updates
	measures = stats_after.measure_nodes_executed-stats_before.measure_nodes_executed
	delete(samples)
	return
}

run_case :: proc(children: int, percentage: bool) {
	allocations := alicorn.Runtime_Allocation_Stats{}
	rt := alicorn.new_runtime({0, 0, 1280, 1600}, alicorn.Runtime_Config{allocation_stats=&allocations})
	defer alicorn.destroy_runtime(&rt)
	if !describe_frame(&rt, PARENT_NARROW, children, percentage) || rt.hard_error {
		fmt.println("BENCHMARK FAILURE: setup frame rejected", rt.diagnostic)
		return
	}
	// Warm both traces before recording settled storage. The benchmark compares
	// identical retained shapes: fixed 400-unit children vs 50% children.
	_, _, _, _, _ = measure_scenario(&rt, children, percentage, false)
	_, _, _, _, _ = measure_scenario(&rt, children, percentage, true)
	settled_live := allocations.persistent_requested_bytes_live
	dependency_count := len(rt.percent_width_dependencies)
	if !rt.percent_width_sidecar_initialized { dependency_count = 0 }
	same_p95, same_allocs, same_live_delta, same_layout_updates, same_measures := measure_scenario(&rt, children, percentage, false)
	resize_p95, resize_allocs, resize_live_delta, resize_layout_updates, resize_measures := measure_scenario(&rt, children, percentage, true)
	peak_after_traces := allocations.persistent_requested_bytes_peak
	fmt.println(
		"case", "children", children, "percentage", percentage,
		"dependencies", dependency_count,
		"settled_persistent_bytes", settled_live, "peak_after_traces_persistent_bytes", peak_after_traces,
		"same_width_p95_ns", same_p95, "same_persistent_alloc_calls", same_allocs, "same_live_delta_bytes", same_live_delta,
		"same_layout_updates", same_layout_updates, "same_measure_nodes", same_measures,
		"resize_p95_ns", resize_p95, "resize_persistent_alloc_calls", resize_allocs, "resize_live_delta_bytes", resize_live_delta,
		"resize_layout_updates", resize_layout_updates, "resize_measure_nodes", resize_measures,
	)
}

main :: proc() {
	fmt.println("Alicorn #109 percentage-width sidecar benchmark; optimized headless retained frames")
	fmt.println("warmup_frames", WARMUP_FRAMES, "sample_frames", SAMPLE_FRAMES, "parent_widths", PARENT_NARROW, PARENT_WIDE)
	for count in CHILD_COUNTS {
		run_case(count, false)
		run_case(count, true)
	}
}
