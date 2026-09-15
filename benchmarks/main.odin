package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import alicorn "../runtime"

ROOT :: alicorn.Source_Site{"benchmarks/main.odin", 1, 1, "root"}
NODE :: alicorn.Source_Site{"benchmarks/main.odin", 10, 1, "node"}
REGION_SCOPE :: alicorn.Source_Site{"benchmarks/main.odin", 20, 1, "region_scope"}
REGION :: alicorn.Source_Site{"benchmarks/main.odin", 21, 1, "region"}
REGION_NODE :: alicorn.Source_Site{"benchmarks/main.odin", 22, 1, "region_node"}
LARGE_SCOPE :: alicorn.Source_Site{"benchmarks/main.odin", 30, 1, "large_scope"}
LARGE_REGION :: alicorn.Source_Site{"benchmarks/main.odin", 31, 1, "large_region"}
ROW :: alicorn.Source_Site{"benchmarks/main.odin", 40, 1, "virtual_row"}
SURFACE :: alicorn.Source_Site{"benchmarks/main.odin", 50, 1, "surface"}

Bench_Allocator_State :: struct {
	backing: mem.Allocator,
	allocations: u64,
	allocated_bytes: u64,
	frees: u64,
	freed_bytes: u64,
}

bench_allocator_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	state := (^Bench_Allocator_State)(data)
	result, err := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, loc)
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		state.allocations += 1
		state.allocated_bytes += u64(size)
	case .Free:
		state.frees += 1
		state.freed_bytes += u64(old_size)
	case .Resize, .Resize_Non_Zeroed:
		state.allocations += 1
		state.allocated_bytes += u64(size)
		if old_memory != nil {
			state.frees += 1
			state.freed_bytes += u64(old_size)
		}
	}
	return result, err
}

bench_allocator :: proc(state: ^Bench_Allocator_State) -> mem.Allocator {
	return mem.Allocator{procedure = bench_allocator_proc, data = state}
}

Alloc_Snapshot :: struct {
	allocations: u64,
	allocated_bytes: u64,
	frees: u64,
	freed_bytes: u64,
}

allocation_snapshot :: proc(state: ^Bench_Allocator_State) -> Alloc_Snapshot {
	return Alloc_Snapshot{state.allocations, state.allocated_bytes, state.frees, state.freed_bytes}
}

allocation_delta :: proc(before, after: Alloc_Snapshot) -> Alloc_Snapshot {
	return Alloc_Snapshot{after.allocations-before.allocations, after.allocated_bytes-before.allocated_bytes, after.frees-before.frees, after.freed_bytes-before.freed_bytes}
}

benchmark_failure :: proc(message: string) {
	fmt.println("BENCHMARK FAILURE:", message)
	os.exit(1)
}

Bench_Delta :: struct {
	descriptions_emitted: u64,
	descriptions_reused: u64,
	regions_skipped: u64,
	retained_subtrees_reused: u64,
	reconcile_nodes_visited: u64,
	layout_nodes_visited: u64,
	paint_nodes_visited: u64,
	composition_nodes_visited: u64,
	adjacency_rebuilds: u64,
	nodes_created: u64,
	nodes_retired: u64,
	paint_updates: u64,
	composite_updates: u64,
	surface_updates: u64,
	surface_frames_consumed: u64,
}

delta :: proc(before, after: alicorn.Frame_Stats) -> Bench_Delta {
	return Bench_Delta{
		after.descriptions_emitted-before.descriptions_emitted,
		after.descriptions_reused-before.descriptions_reused,
		after.regions_skipped-before.regions_skipped,
		after.retained_subtrees_reused-before.retained_subtrees_reused,
		after.reconcile_nodes_visited-before.reconcile_nodes_visited,
		after.layout_nodes_visited-before.layout_nodes_visited,
		after.paint_nodes_visited-before.paint_nodes_visited,
		after.composition_nodes_visited-before.composition_nodes_visited,
		after.adjacency_rebuilds-before.adjacency_rebuilds,
		after.nodes_created-before.nodes_created,
		after.nodes_retired-before.nodes_retired,
		after.paint_updates-before.paint_updates,
		after.composite_updates-before.composite_updates,
		after.surface_updates-before.surface_updates,
		after.surface_frames_consumed-before.surface_frames_consumed,
	}
}

print_row :: proc(name: string, elapsed_ns: i64, before, after: alicorn.Frame_Stats, retained: int, alloc_before := Alloc_Snapshot{}, alloc_after := Alloc_Snapshot{}) {
	d := delta(before, after)
	a := allocation_delta(alloc_before, alloc_after)
	fmt.println(name,
		"wall_ns", elapsed_ns,
		"emit", d.descriptions_emitted,
		"reuse", d.descriptions_reused,
		"region_skip", d.regions_skipped,
		"subtree_reuse", d.retained_subtrees_reused,
		"alloc", a.allocations,
		"alloc_bytes", a.allocated_bytes,
		"frees", a.frees,
		"reconcile", d.reconcile_nodes_visited,
		"layout", d.layout_nodes_visited,
		"paint_visit", d.paint_nodes_visited,
		"compose_visit", d.composition_nodes_visited,
		"adjacency", d.adjacency_rebuilds,
		"created", d.nodes_created,
		"retired", d.nodes_retired,
		"paint", d.paint_updates,
		"composite", d.composite_updates,
		"retained", retained)
}

render_tree_numeric :: proc(rt: ^alicorn.Runtime, count: int, changed: int, reverse: bool) {
	alicorn.invalidate_root(rt, "benchmark root frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="benchmark")
	for n := 0; n < count; n += 1 {
		i := reverse ? count-1-n : n
		if alicorn.key_scope_u64(&ui, u64(i), NODE) {
			alicorn.text_ex(&ui, "node", NODE, paint_value=u64(i == changed))
			alicorn.key_scope_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_tree_formatted :: proc(rt: ^alicorn.Runtime, count: int) {
	alicorn.invalidate_root(rt, "benchmark formatted-key frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="formatted")
	for i := 0; i < count; i += 1 {
		key := fmt.aprintf("%d", i)
		if alicorn.key_scope_begin_ex(&ui, key, NODE) {
			alicorn.text_ex(&ui, "node", NODE)
			alicorn.key_scope_end(&ui)
		}
		delete(key)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_regional :: proc(rt: ^alicorn.Runtime, revisions: []u64, changed_value: u64, body_calls: ^int) {
	alicorn.invalidate_root(rt, "benchmark regional frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="regional")
	alicorn.text_ex(&ui, "toolbar", NODE, paint_value=changed_value)
	for i := 0; i < len(revisions); i += 1 {
		if !alicorn.key_scope_u64(&ui, u64(i), REGION_SCOPE) { continue }
		id, reused := alicorn.region_begin(&ui, "region", revisions[i], REGION)
		if id != 0 && !reused {
			body_calls^ += 1
			start := len(rt.pending)
			for j := 0; j < 100; j += 1 {
				if alicorn.key_scope_u64(&ui, u64(j), REGION_NODE) {
					alicorn.text_ex(&ui, "region-node", REGION_NODE, paint_value=revisions[i])
					alicorn.key_scope_end(&ui)
				}
			}
			alicorn.region_end(&ui, id, false, start)
		}
		alicorn.key_scope_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_large_region :: proc(rt: ^alicorn.Runtime, revision: u64, sibling_value: u64, body_calls: ^int) {
	alicorn.invalidate_root(rt, "benchmark large-region frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="large-region")
	alicorn.text_ex(&ui, "unrelated sibling", NODE, paint_value=sibling_value)
	if alicorn.key_scope_u64(&ui, 1, LARGE_SCOPE) {
		id, reused := alicorn.region_begin(&ui, "large", revision, LARGE_REGION)
		if id != 0 && !reused {
			body_calls^ += 1
			start := len(rt.pending)
			for i := 0; i < 10_000; i += 1 {
				if alicorn.key_scope_u64(&ui, u64(i), REGION_NODE) {
					alicorn.text_ex(&ui, "large-node", REGION_NODE)
					alicorn.key_scope_end(&ui)
				}
			}
			alicorn.region_end(&ui, id, false, start)
		}
		alicorn.key_scope_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_order :: proc(rt: ^alicorn.Runtime, order: []int) {
	alicorn.invalidate_root(rt, "benchmark structural frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="structural")
	for value in order {
		if alicorn.key_scope_u64(&ui, u64(value), NODE) {
			alicorn.text_ex(&ui, "node", NODE)
			alicorn.key_scope_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_virtual_row :: proc(ui: ^alicorn.UI, index: int) {
	alicorn.text_ex(ui, "row", ROW, paint_value=u64(index))
}

render_virtual_key :: proc(index: int) -> string {
	return fmt.tprintf("item-%d", index)
}

render_virtual :: proc(rt: ^alicorn.Runtime, scroll: f32) {
	alicorn.invalidate_root(rt, "benchmark virtual scroll")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, ROOT)
	alicorn.virtual_list_ex(&ui, 1_000_000, scroll, 400, 20, ROW, render_virtual_key, render_virtual_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_surface :: proc(rt: ^alicorn.Runtime, revision: u64) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "benchmark surface description")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, ROOT, label="surface-root")
	id := alicorn.custom_surface(&ui, "waveform", revision, alicorn.Rect{0, 0, 640, 240}, 1280, 480, 2, SURFACE)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return id
}

measure_surface_locality :: proc(allocator_state: ^Bench_Allocator_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 300})
	id := render_surface(&rt, 0)
	samples := make([]f32, 512)
	for i := 0; i < len(samples); i += 1 { samples[i] = f32(i) / f32(len(samples)-1) }
	// Warm the retained sample capacity so the measured loop isolates the
	// explicit update path rather than dynamic-array growth.
	alicorn.gpu_surface_update(&rt, id, 1, samples)
	alicorn.gpu_surface_frame_consumed(&rt)
	before := rt.stats
	alloc_before := allocation_snapshot(allocator_state)
	start := time.now()
	for i := 0; i < 1_200; i += 1 {
		if !alicorn.gpu_surface_update(&rt, id, u64(i+2), samples) { benchmark_failure("surface update rejected during locality benchmark") }
		_, build := alicorn.begin_frame(&rt)
		if build { benchmark_failure("surface-only benchmark executed the application description") }
		alicorn.gpu_surface_frame_consumed(&rt)
	}
	elapsed := time.duration_nanoseconds(time.since(start))
	after := rt.stats
	d := delta(before, after)
	a := allocation_delta(alloc_before, allocation_snapshot(allocator_state))
	if d.descriptions_emitted != 0 || d.reconcile_nodes_visited != 0 || d.layout_nodes_visited != 0 || d.paint_nodes_visited != 0 || d.composition_nodes_visited != 0 {
		benchmark_failure("surface-only updates visited ordinary retained work")
	}
	fmt.println(
		"surface_locality_1200_updates",
		"wall_ns", elapsed,
		"surface_updates", d.surface_updates,
		"surface_frames_consumed", d.surface_frames_consumed,
		"ordinary_emit", d.descriptions_emitted,
		"ordinary_reconcile", d.reconcile_nodes_visited,
		"ordinary_layout", d.layout_nodes_visited,
		"ordinary_paint", d.paint_nodes_visited,
		"ordinary_compose", d.composition_nodes_visited,
		"alloc", a.allocations,
		"alloc_bytes", a.allocated_bytes,
		"retained", len(rt.nodes),
	)
	delete(samples)
	alicorn.destroy_runtime(&rt)
}

measure_tree :: proc(count: int, allocator_state: ^Bench_Allocator_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	before := rt.stats
	alloc_before := allocation_snapshot(allocator_state)
	start := time.now()
	render_tree_numeric(&rt, count, -1, false)
	first := time.duration_nanoseconds(time.since(start))
	first_after := rt.stats
	first_alloc_after := allocation_snapshot(allocator_state)
	start = time.now()
	render_tree_numeric(&rt, count, -1, false)
	root_wake := time.duration_nanoseconds(time.since(start))
	root_after := rt.stats
	root_alloc_after := allocation_snapshot(allocator_state)
	start = time.now()
	render_tree_numeric(&rt, count, count/2, false)
	one_change := time.duration_nanoseconds(time.since(start))
	one_after := rt.stats
	one_alloc_after := allocation_snapshot(allocator_state)
	start = time.now()
	render_tree_numeric(&rt, count, -1, true)
	reorder := time.duration_nanoseconds(time.since(start))
	reorder_after := rt.stats
	reorder_alloc_after := allocation_snapshot(allocator_state)
	fmt.println("tree", count)
	print_row("  initial", first, before, first_after, len(rt.nodes), alloc_before, first_alloc_after)
	print_row("  root_invalidated_unchanged", root_wake, first_after, root_after, len(rt.nodes), first_alloc_after, root_alloc_after)
	print_row("  root_invalidated_one_value", one_change, root_after, one_after, len(rt.nodes), root_alloc_after, one_alloc_after)
	print_row("  full_keyed_reorder", reorder, one_after, reorder_after, len(rt.nodes), one_alloc_after, reorder_alloc_after)
	alicorn.destroy_runtime(&rt)
}

measure_idle :: proc(allocator_state: ^Bench_Allocator_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	render_tree_numeric(&rt, 10_000, -1, false)
	before := rt.stats
	alloc_before := allocation_snapshot(allocator_state)
	start := time.now()
	for i := 0; i < 10_000; i += 1 {
		_, build := alicorn.begin_frame(&rt)
		if build { fmt.println("unexpected idle build") }
	}
	elapsed := time.duration_nanoseconds(time.since(start))
	after := rt.stats
	idle_delta := delta(before, after)
	if idle_delta.descriptions_emitted != 0 || idle_delta.reconcile_nodes_visited != 0 || idle_delta.layout_nodes_visited != 0 || idle_delta.paint_nodes_visited != 0 || idle_delta.composition_nodes_visited != 0 || idle_delta.adjacency_rebuilds != 0 || idle_delta.nodes_created != 0 || idle_delta.nodes_retired != 0 {
		benchmark_failure("true idle visited retained work")
	}
	print_row("true_idle_10k_tree_10000_frames", elapsed, before, after, len(rt.nodes), alloc_before, allocation_snapshot(allocator_state))
	fmt.println("  idle_frames", after.idle_frames-before.idle_frames, "gpu_submits", after.gpu_submits)
	alicorn.destroy_runtime(&rt)
}

measure_regions :: proc(allocator_state: ^Bench_Allocator_State) {
	revisions := make([]u64, 100)
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	body_calls: int = 0
	alloc_before := allocation_snapshot(allocator_state)
	start := time.now()
	render_regional(&rt, revisions, 0, &body_calls)
	first := time.duration_nanoseconds(time.since(start))
	first_after := rt.stats
	first_alloc_after := allocation_snapshot(allocator_state)
	start = time.now()
	render_regional(&rt, revisions, 0, &body_calls)
	unchanged := time.duration_nanoseconds(time.since(start))
	unchanged_after := rt.stats
	unchanged_alloc_after := allocation_snapshot(allocator_state)
	revisions[37] += 1
	start = time.now()
	render_regional(&rt, revisions, 0, &body_calls)
	changed := time.duration_nanoseconds(time.since(start))
	changed_after := rt.stats
	changed_alloc_after := allocation_snapshot(allocator_state)
	unchanged_delta := delta(first_after, unchanged_after)
	changed_delta := delta(unchanged_after, changed_after)
	if unchanged_delta.descriptions_emitted != 102 || unchanged_delta.reconcile_nodes_visited != 102 || unchanged_delta.retained_subtrees_reused != 100 || changed_delta.descriptions_emitted != 202 || changed_delta.reconcile_nodes_visited != 202 || changed_delta.retained_subtrees_reused != 99 {
		benchmark_failure("regional locality counters changed unexpectedly")
	}
	fmt.println("regional_application logical_nodes", 10_102, "body_calls", body_calls)
	print_row("  first", first, alicorn.Frame_Stats{}, first_after, len(rt.nodes), alloc_before, first_alloc_after)
	print_row("  one_100_node_region_unchanged_root_wake", unchanged, first_after, unchanged_after, len(rt.nodes), first_alloc_after, unchanged_alloc_after)
	print_row("  one_100_node_region_changed", changed, unchanged_after, changed_after, len(rt.nodes), unchanged_alloc_after, changed_alloc_after)
	alicorn.destroy_runtime(&rt)

	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	body_calls = 0
	alloc_before = allocation_snapshot(allocator_state)
	start = time.now()
	render_large_region(&rt, 1, 0, &body_calls)
	large_first := time.duration_nanoseconds(time.since(start))
	large_first_after := rt.stats
	large_first_alloc_after := allocation_snapshot(allocator_state)
	start = time.now()
	render_large_region(&rt, 1, 1, &body_calls)
	large_reuse := time.duration_nanoseconds(time.since(start))
	large_reuse_after := rt.stats
	large_reuse_alloc_after := allocation_snapshot(allocator_state)
	large_reuse_delta := delta(large_first_after, large_reuse_after)
	if large_reuse_delta.descriptions_emitted != 3 || large_reuse_delta.reconcile_nodes_visited != 3 || large_reuse_delta.retained_subtrees_reused != 1 {
		benchmark_failure("large retained-region reuse enumerated descendants")
	}
	fmt.println("large_retained_region logical_descendants", 10_000, "body_calls", body_calls)
	print_row("  initial", large_first, alicorn.Frame_Stats{}, large_first_after, len(rt.nodes), alloc_before, large_first_alloc_after)
	print_row("  reused_for_unrelated_sibling", large_reuse, large_first_after, large_reuse_after, len(rt.nodes), large_first_alloc_after, large_reuse_alloc_after)
	alicorn.destroy_runtime(&rt)
}

measure_key_paths :: proc(allocator_state: ^Bench_Allocator_State) {
	count := 10_000
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	formatted_alloc_before := allocation_snapshot(allocator_state)
	start := time.now()
	render_tree_formatted(&rt, count)
	formatted := time.duration_nanoseconds(time.since(start))
	formatted_alloc_after := allocation_snapshot(allocator_state)
	formatted_alloc := allocation_delta(formatted_alloc_before, formatted_alloc_after)
	fmt.println("key_path formatted_string_10k wall_ns", formatted, "alloc", formatted_alloc.allocations, "alloc_bytes", formatted_alloc.allocated_bytes, "retained", len(rt.nodes))
	alicorn.destroy_runtime(&rt)
	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	numeric_alloc_before := allocation_snapshot(allocator_state)
	start = time.now()
	render_tree_numeric(&rt, count, -1, false)
	numeric := time.duration_nanoseconds(time.since(start))
	numeric_alloc_after := allocation_snapshot(allocator_state)
	numeric_alloc := allocation_delta(numeric_alloc_before, numeric_alloc_after)
	fmt.println("key_path typed_u64_10k wall_ns", numeric, "alloc", numeric_alloc.allocations, "alloc_bytes", numeric_alloc.allocated_bytes, "retained", len(rt.nodes), "formatted_minus_numeric_ns", formatted-numeric, "formatted_minus_numeric_alloc", formatted_alloc.allocations-numeric_alloc.allocations, "formatted_minus_numeric_bytes", formatted_alloc.allocated_bytes-numeric_alloc.allocated_bytes)
	alicorn.destroy_runtime(&rt)
}

measure_churn :: proc(allocator_state: ^Bench_Allocator_State) {
	count := 10_000
	order := make([]int, count)
	for i := 0; i < count; i += 1 { order[i] = i }
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	render_order(&rt, order)
	order[0], order[1] = order[1], order[0]
	before := rt.stats
	alloc_before := allocation_snapshot(allocator_state)
	start := time.now()
	render_order(&rt, order)
	print_row("churn_swap_two", time.duration_nanoseconds(time.since(start)), before, rt.stats, len(rt.nodes), alloc_before, allocation_snapshot(allocator_state))
	last := order[count-1]
	for i := count-1; i > 0; i -= 1 { order[i] = order[i-1] }
	order[0] = last
	before = rt.stats
	alloc_before = allocation_snapshot(allocator_state)
	start = time.now()
	render_order(&rt, order)
	print_row("churn_move_last_first", time.duration_nanoseconds(time.since(start)), before, rt.stats, len(rt.nodes), alloc_before, allocation_snapshot(allocator_state))
	for i, j := 0, count-1; i < j; i, j = i+1, j-1 { order[i], order[j] = order[j], order[i] }
	before = rt.stats
	alloc_before = allocation_snapshot(allocator_state)
	start = time.now()
	render_order(&rt, order)
	print_row("churn_reverse", time.duration_nanoseconds(time.since(start)), before, rt.stats, len(rt.nodes), alloc_before, allocation_snapshot(allocator_state))
	for i := 0; i < count/100; i += 1 { order[i] = count+i }
	before = rt.stats
	alloc_before = allocation_snapshot(allocator_state)
	start = time.now()
	render_order(&rt, order)
	print_row("churn_replace_one_percent", time.duration_nanoseconds(time.since(start)), before, rt.stats, len(rt.nodes), alloc_before, allocation_snapshot(allocator_state))
	before = rt.stats
	alloc_before = allocation_snapshot(allocator_state)
	for i := 0; i < 1_000; i += 1 {
		at := i % (count-1)
		order[at], order[at+1] = order[at+1], order[at]
		render_order(&rt, order)
	}
	final := rt.stats
	after_alloc := allocation_snapshot(allocator_state)
	a := allocation_delta(alloc_before, after_alloc)
	if final.adjacency_rebuilds-before.adjacency_rebuilds != 1000 || final.nodes_created-before.nodes_created != 0 || final.nodes_retired-before.nodes_retired != 0 {
		benchmark_failure("structural reorder churn created or leaked nodes")
	}
	fmt.println("churn_reorder_every_frame frames", 1000, "adjacency", final.adjacency_rebuilds-before.adjacency_rebuilds, "created", final.nodes_created-before.nodes_created, "retired", final.nodes_retired-before.nodes_retired, "reconcile", final.reconcile_nodes_visited-before.reconcile_nodes_visited, "alloc", a.allocations, "alloc_bytes", a.allocated_bytes, "retained", len(rt.nodes))
	delete(order)
	alicorn.destroy_runtime(&rt)
}

main :: proc() {
	allocator_state := Bench_Allocator_State{backing = context.allocator}
	context.allocator = bench_allocator(&allocator_state)
	fmt.println("Alicorn retained-work benchmark suite (headless; raw wall-clock nanoseconds)")
	fmt.println("columns: emit reuse region_skip subtree_reuse alloc alloc_bytes frees reconcile layout paint_visit compose_visit adjacency created retired paint composite retained")
	measure_idle(&allocator_state)
	measure_tree(100, &allocator_state)
	measure_tree(1000, &allocator_state)
	measure_tree(10_000, &allocator_state)
	measure_regions(&allocator_state)
	measure_key_paths(&allocator_state)
	measure_churn(&allocator_state)
	measure_surface_locality(&allocator_state)
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	render_virtual(&rt, 0)
	start := time.now()
	for i := 0; i < 100; i += 1 { render_virtual(&rt, f32(i*400)) }
	virtual_ns := time.duration_nanoseconds(time.since(start))
	fmt.println("virtual logical_items 1000000 frames 100 elapsed_ns", virtual_ns, "retained_nodes", len(rt.nodes))
	alicorn.destroy_runtime(&rt)
	context.allocator = allocator_state.backing
}
