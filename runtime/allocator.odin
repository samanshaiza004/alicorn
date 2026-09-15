#+vet explicit-allocators
package alicorn

import "core:mem"

// Runtime_Allocator_State is deliberately small and pointer-stable. The
// allocator wrapper records requested allocation sizes; it does not pretend to
// measure RSS, committed pages, allocator metadata, GPU memory, or driver
// residency.
Runtime_Allocator_State :: struct {
	backing: mem.Allocator,
	stats:   ^Runtime_Allocation_Stats,
	scratch: bool,
}

runtime_allocator :: proc(state: ^Runtime_Allocator_State) -> mem.Allocator {
	return mem.Allocator{
		procedure = runtime_allocator_proc,
		data = state,
	}
}

runtime_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (result: []byte, err: mem.Allocator_Error) {
	state := (^Runtime_Allocator_State)(data)
	if state == nil || state.backing.procedure == nil {
		return nil, .Invalid_Argument
	}

	result, err = state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
	if state.stats == nil || err != .None {
		return
	}

	stats := state.stats
	if state.scratch {
		#partial switch mode {
		case .Alloc, .Alloc_Non_Zeroed:
			stats.scratch_alloc_calls += 1
			stats.scratch_requested_bytes_epoch += u64(size)
			if stats.scratch_requested_bytes_epoch > stats.scratch_requested_bytes_peak {
				stats.scratch_requested_bytes_peak = stats.scratch_requested_bytes_epoch
			}
		}
		return
	}

	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		stats.persistent_alloc_calls += 1
		stats.persistent_requested_bytes_live += i64(size)
		if stats.persistent_requested_bytes_live > stats.persistent_requested_bytes_peak {
			stats.persistent_requested_bytes_peak = stats.persistent_requested_bytes_live
		}
	case .Free:
		if old_memory != nil {
			stats.persistent_free_calls += 1
			stats.persistent_requested_bytes_live -= i64(old_size)
			if stats.persistent_requested_bytes_live < 0 {
				stats.persistent_requested_bytes_live = 0
			}
		}
	case .Free_All:
		stats.persistent_free_calls += 1
		stats.persistent_requested_bytes_live = 0
	case .Resize, .Resize_Non_Zeroed:
		stats.persistent_free_calls += 1
		stats.persistent_requested_bytes_live += i64(size) - i64(old_size)
		if stats.persistent_requested_bytes_live < 0 {
			stats.persistent_requested_bytes_live = 0
		}
		if stats.persistent_requested_bytes_live > stats.persistent_requested_bytes_peak {
			stats.persistent_requested_bytes_peak = stats.persistent_requested_bytes_live
		}
	}
	return
}

runtime_scratch_reset :: proc(rt: ^Runtime) {
	if rt.scratch_arena != nil {
		mem.dynamic_arena_reset(rt.scratch_arena)
	}
	rt.allocation_stats.scratch_requested_bytes_epoch = 0
	rt.allocation_stats.scratch_resets += 1
}
