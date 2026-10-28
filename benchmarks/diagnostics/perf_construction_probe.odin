package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import alicorn "../../runtime"

Probe_Phase :: enum { Init, Reserve, Description, End_Frame }

Probe_Allocator_State :: struct {
	backing: mem.Allocator,
	phase: Probe_Phase,
	allocations: [Probe_Phase]u64,
	allocated_bytes: [Probe_Phase]u64,
	live_bytes: u64,
	high_water_bytes: u64,
}

probe_allocator_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	state := (^Probe_Allocator_State)(data)
	result, err := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, loc)
	if err != .None { return result, err }
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		state.allocations[state.phase] += 1
		state.allocated_bytes[state.phase] += u64(size)
		state.live_bytes += u64(size)
	case .Free:
		if u64(old_size) <= state.live_bytes { state.live_bytes -= u64(old_size) }
	case .Resize, .Resize_Non_Zeroed:
		state.allocations[state.phase] += 1
		state.allocated_bytes[state.phase] += u64(size)
		if old_memory == nil {
			state.live_bytes += u64(size)
		} else if u64(old_size) <= state.live_bytes {
			state.live_bytes = state.live_bytes - u64(old_size) + u64(size)
		}
	case .Free_All:
		state.live_bytes = 0
	}
	if state.live_bytes > state.high_water_bytes { state.high_water_bytes = state.live_bytes }
	return result, err
}

probe_phase_name :: proc(phase: Probe_Phase) -> string {
	switch phase {
	case .Init: return "init"
	case .Reserve: return "reserve"
	case .Description: return "description"
	case .End_Frame: return "end_frame"
	}
	return "unknown"
}

PROBE_ROOT :: alicorn.Source_Site{"benchmarks/diagnostics/perf_construction_probe.odin", 1, 1, "probe_root"}
PROBE_NODE :: alicorn.Source_Site{"benchmarks/diagnostics/perf_construction_probe.odin", 2, 1, "probe_node"}
WRAPPED_VALUE :: "A small amount of wrapped text exercises shaping, line breaking, measurement, semantic publication, retained paint, and final geometry without using an unusually large document."

describe_probe_tree :: proc(rt: ^alicorn.Runtime, kind: string, count: int) -> (ui: alicorn.UI, build: bool) {
	alicorn.invalidate_root(rt, "construction composition probe")
	ui, build = alicorn.begin_frame(rt)
	if !build { return }
	root_style := alicorn.layout_style(.Column, width=640, height=900)
	alicorn.container_begin_ex(&ui, .Root, PROBE_ROOT, label="probe root", style=root_style)
	for i := 0; i < count; i += 1 {
		if !alicorn.key_scope_u64(&ui, u64(i), PROBE_NODE) { continue }
		switch kind {
	case "containers":
			alicorn.container_begin_ex(&ui, .Container, PROBE_NODE)
			alicorn.container_end(&ui)
	case "short":
			alicorn.text_ex(&ui, "node", PROBE_NODE, paint_value=u64(i))
	case "wrapped":
			alicorn.text_ex(&ui, WRAPPED_VALUE, PROBE_NODE,
				style=alicorn.layout_style(width=320),
				text_style=alicorn.Text_Style{overflow=.Wrap})
		}
		alicorn.key_scope_end(&ui)
	}
	alicorn.container_end(&ui)
	return
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usage: perf_construction_probe <containers|short|short-reserve|wrapped>")
		os.exit(2)
	}
	mode := os.args[1]
	kind := mode
	pre_reserve := false
	if mode == "short-reserve" { kind = "short"; pre_reserve = true }
	if kind != "containers" && kind != "short" && kind != "wrapped" {
		fmt.println("unknown workload", mode)
		os.exit(2)
	}
	state := Probe_Allocator_State{backing=context.allocator}
	context.allocator = mem.Allocator{procedure=probe_allocator_proc, data=&state}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	state.phase = .Reserve
	reserve_start := time.now()
	if pre_reserve { reserve(&rt.pending, 10_001) }
	reserve_ns := time.duration_nanoseconds(time.since(reserve_start))
	state.phase = .Description
	start := time.now()
	ui, build := describe_probe_tree(&rt, kind, 10_000)
	description_ns := time.duration_nanoseconds(time.since(start))
	state.phase = .End_Frame
	end_start := time.now()
	if build { alicorn.end_frame(&ui) }
	end_frame_ns := time.duration_nanoseconds(time.since(end_start))
	stats := rt.stats
	fmt.println("construction_probe", mode, "logical_items", 10_000, "retained_nodes", len(rt.nodes),
		"pending_item_size", size_of(alicorn.Pending_Item), "pending_capacity", cap(rt.pending),
		"pending_capacity_bytes", cap(rt.pending)*size_of(alicorn.Pending_Item))
	fmt.println("phase_timing_ns", "reserve", reserve_ns, "description", description_ns,
		"end_frame", end_frame_ns, "total", reserve_ns+description_ns+end_frame_ns)
	for phase in Probe_Phase {
		fmt.println("phase_allocations", probe_phase_name(phase),
			"calls", state.allocations[phase], "requested_bytes", state.allocated_bytes[phase])
	}
	fmt.println("memory_requested", "live_after_end_frame", state.live_bytes,
		"high_water", state.high_water_bytes)
	fmt.println("work_counters", "description", stats.descriptions_emitted,
		"reconcile", stats.reconcile_nodes_visited, "measure_examined", stats.measure_nodes_examined,
		"measure_executed", stats.measure_nodes_executed, "layout", stats.layout_nodes_visited,
		"semantic_descriptions", stats.semantic_descriptions_emitted,
		"semantic_resolved", stats.semantic_entities_resolved,
		"paint", stats.paint_nodes_visited, "compose", stats.composition_nodes_visited,
		"shape_requests", stats.text_shape_requests)
	alicorn.destroy_runtime(&rt)
	context.allocator = state.backing
}
