package main

import "core:fmt"
import "core:mem"
import alicorn "../runtime"

Bench_Allocation_Phase :: enum {
	Runtime_Init,
	Initial_Description,
	Initial_End_Frame,
}

Bench_Allocation_Site :: struct {
	file_path: string,
	procedure: string,
	line: i32,
	column: i32,
	phase: Bench_Allocation_Phase,
	allocations: u64,
	allocated_bytes: u64,
}

Bench_Attribution_State :: struct {
	backing: mem.Allocator,
	phase: Bench_Allocation_Phase,
	sites: [dynamic]Bench_Allocation_Site,
	phase_allocations: [Bench_Allocation_Phase]u64,
	phase_allocated_bytes: [Bench_Allocation_Phase]u64,
	sites_overflow: u64,
}

bench_attribution_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	state := (^Bench_Attribution_State)(data)
	result, err := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, loc)
	if mode != .Alloc && mode != .Alloc_Non_Zeroed && mode != .Resize && mode != .Resize_Non_Zeroed {
		return result, err
	}
	state.phase_allocations[state.phase] += 1
	state.phase_allocated_bytes[state.phase] += u64(size)
	for &site in state.sites {
		if site.file_path == loc.file_path && site.procedure == loc.procedure &&
		   site.line == loc.line && site.column == loc.column && site.phase == state.phase {
			site.allocations += 1
			site.allocated_bytes += u64(size)
			return result, err
		}
	}
	if len(state.sites) == cap(state.sites) {
		state.sites_overflow += 1
		return result, err
	}
	append(&state.sites, Bench_Allocation_Site{
		file_path=loc.file_path,
		procedure=loc.procedure,
		line=loc.line,
		column=loc.column,
		phase=state.phase,
		allocations=1,
		allocated_bytes=u64(size),
	})
	return result, err
}

bench_allocation_phase_name :: proc(phase: Bench_Allocation_Phase) -> string {
	switch phase {
	case .Runtime_Init: return "runtime_init"
	case .Initial_Description: return "initial_description"
	case .Initial_End_Frame: return "initial_end_frame"
	}
	return "unknown"
}

measure_tree_allocation_attribution :: proc() {
	state := Bench_Attribution_State{backing=context.allocator}
	state.sites = make([dynamic]Bench_Allocation_Site, 0, 512, allocator=state.backing)
	context.allocator = mem.Allocator{procedure=bench_attribution_allocator_proc, data=&state}

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	state.phase = .Initial_Description
	ui, build := describe_tree_numeric(&rt, 10_000, -1, false)
	state.phase = .Initial_End_Frame
	if build { alicorn.end_frame(&ui) }
	context.allocator = state.backing

	fmt.println("allocation_attribution tree 10000 retained", len(rt.nodes))
	for phase in Bench_Allocation_Phase {
		fmt.println("allocation_phase", bench_allocation_phase_name(phase),
			"allocations", state.phase_allocations[phase],
			"allocated_bytes", state.phase_allocated_bytes[phase])
	}
	fmt.println("allocation_site_count", len(state.sites), "site_overflow", state.sites_overflow)
	print_count := min(len(state.sites), 30)
	for rank in 0..<print_count {
		best := -1
		for index in 0..<len(state.sites) {
			if state.sites[index].allocated_bytes == 0 { continue }
			if best < 0 || state.sites[index].allocated_bytes > state.sites[best].allocated_bytes {
				best = index
			}
		}
		if best < 0 { break }
		site := &state.sites[best]
		fmt.println("allocation_site", bench_allocation_phase_name(site.phase),
			site.file_path, site.line,
			site.procedure,
			"allocations", site.allocations,
			"allocated_bytes", site.allocated_bytes)
		site.allocated_bytes = 0
	}
	alicorn.destroy_runtime(&rt)
	delete(state.sites)
}
