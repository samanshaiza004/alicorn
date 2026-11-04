package main

// Keep this fixture on the common low-level API so the identical source can
// measure historical snapshots. Allocation tracking is opt-in and is never
// used for the ordinary timing samples.
import "core:fmt"
import "core:c/libc"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:time"
import alicorn "alicorn:runtime"

Construction_Phase :: enum { Init, Description, End_Frame, Destroy }

Construction_Allocator :: struct {
	backing: mem.Allocator,
	phase: Construction_Phase,
	tracking: bool,
	calls: [Construction_Phase]u64,
	bytes: [Construction_Phase]u64,
	live, high_water: u64,
}

construction_allocator :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	s := (^Construction_Allocator)(data)
	result, err := s.backing.procedure(s.backing.data, mode, size, alignment, old_memory, old_size, loc)
	if err != .None { return result, err }
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		s.calls[s.phase] += 1
		s.bytes[s.phase] += u64(size)
		s.live += u64(size)
	case .Resize, .Resize_Non_Zeroed:
		s.calls[s.phase] += 1
		s.bytes[s.phase] += u64(size)
		if old_memory == nil { s.live += u64(size) }
		else if u64(old_size) <= s.live { s.live = s.live-u64(old_size)+u64(size) }
	case .Free:
		if u64(old_size) <= s.live { s.live -= u64(old_size) }
	case .Free_All:
		s.live = 0
	}
	s.high_water = max(s.high_water, s.live)
	return result, err
}

CONSTRUCTION_ROOT :: alicorn.Source_Site{"construction_cpu_probe.odin", 1, 1, "root"}
CONSTRUCTION_KEY :: alicorn.Source_Site{"construction_cpu_probe.odin", 2, 1, "key"}
CONSTRUCTION_LEAF :: alicorn.Source_Site{"construction_cpu_probe.odin", 3, 1, "leaf"}
CONSTRUCTION_GROUP :: alicorn.Source_Site{"construction_cpu_probe.odin", 4, 1, "group"}
CONSTRUCTION_HEADING :: alicorn.Source_Site{"construction_cpu_probe.odin", 5, 1, "heading"}
CONSTRUCTION_ROW :: alicorn.Source_Site{"construction_cpu_probe.odin", 6, 1, "row"}
CONSTRUCTION_APPLY :: alicorn.Source_Site{"construction_cpu_probe.odin", 7, 1, "apply"}
CONSTRUCTION_RESET :: alicorn.Source_Site{"construction_cpu_probe.odin", 8, 1, "reset"}
CONSTRUCTION_WRAPPED :: "A small amount of wrapped text exercises shaping, line breaking, measurement, retained paint, and final geometry without using an unusually large document."

construction_describe :: proc(rt: ^alicorn.Runtime, workload: string, count: int) -> (ui: alicorn.UI, build: bool) {
	alicorn.invalidate_root(rt, "construction CPU probe")
	ui, build = alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, CONSTRUCTION_ROOT,
		style=alicorn.layout_style(.Column, width=640, height=900))
	for i := 0; i < count; i += 1 {
		if !alicorn.key_scope_u64(&ui, u64(i), CONSTRUCTION_KEY) { continue }
		switch workload {
		case "containers":
			alicorn.container_begin_ex(&ui, .Container, CONSTRUCTION_LEAF)
			alicorn.container_end(&ui)
		case "short":
			alicorn.text_ex(&ui, "node", CONSTRUCTION_LEAF)
		case "wrapped":
			alicorn.text_ex(&ui, CONSTRUCTION_WRAPPED, CONSTRUCTION_LEAF,
				style=alicorn.layout_style(width=320),
				text_style=alicorn.Text_Style{overflow=.Wrap})
		case "panel":
			alicorn.container_begin_ex(&ui, .Container, CONSTRUCTION_GROUP,
				style=alicorn.layout_style(.Column, height=96, padding=8, gap=4))
			alicorn.text_ex(&ui, "Settings section", CONSTRUCTION_HEADING)
			alicorn.container_begin_ex(&ui, .Container, CONSTRUCTION_ROW,
				style=alicorn.layout_style(.Row, height=32, gap=8))
			alicorn.text_ex(&ui, "Application preference", CONSTRUCTION_LEAF)
			alicorn.button_ex(&ui, "Apply", CONSTRUCTION_APPLY, style=alicorn.layout_style(width=80, height=32))
			alicorn.button_ex(&ui, "Reset", CONSTRUCTION_RESET, style=alicorn.layout_style(width=80, height=32))
			alicorn.container_end(&ui)
			alicorn.container_end(&ui)
		}
		alicorn.key_scope_end(&ui)
	}
	alicorn.container_end(&ui)
	return
}

Construction_Result :: struct {
	init_ns, description_ns, end_frame_ns, destroy_ns: i64,
	init_cpu_ns, description_cpu_ns, end_frame_cpu_ns, destroy_cpu_ns: i64,
	retained, display_count: int,
	requested_live: u64,
	geometry_sum: f64,
}

// MSVCRT clock() measures elapsed time; do not mislabel it as process CPU.
construction_cpu_now :: proc() -> i64 {
	when ODIN_OS == .Windows { return 0 }
	else { return i64(libc.clock())*(1_000_000_000/i64(libc.CLOCKS_PER_SEC)) }
}

construction_measure :: proc(workload: string, count: int, allocator: ^Construction_Allocator) -> Construction_Result {
	r: Construction_Result
	previous_allocator := context.allocator
	if allocator.tracking {
		context.allocator = mem.Allocator{procedure=construction_allocator, data=rawptr(allocator)}
	}
	allocator.phase = .Init
	start := time.now()
	cpu_start := construction_cpu_now()
	rt: alicorn.Runtime
	if allocator.tracking {
		backing := mem.Allocator{procedure=construction_allocator, data=rawptr(allocator)}
		rt = alicorn.Construction_Benchmark_New_Runtime(alicorn.Rect{0, 0, 1280, 900}, backing)
	} else {
		rt = alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	}
	r.init_cpu_ns = construction_cpu_now()-cpu_start
	r.init_ns = time.duration_nanoseconds(time.since(start))
	allocator.phase = .Description
	start = time.now()
	cpu_start = construction_cpu_now()
	ui, build := construction_describe(&rt, workload, count)
	r.description_cpu_ns = construction_cpu_now()-cpu_start
	r.description_ns = time.duration_nanoseconds(time.since(start))
	allocator.phase = .End_Frame
	start = time.now()
	cpu_start = construction_cpu_now()
	if build { alicorn.end_frame(&ui) }
	r.end_frame_cpu_ns = construction_cpu_now()-cpu_start
	r.end_frame_ns = time.duration_nanoseconds(time.since(start))
	r.retained = len(rt.nodes)
	r.display_count = len(rt.display)
	r.requested_live = allocator.live
	for id in rt.order {
		node := rt.nodes[id]
		r.geometry_sum += f64(node.bounds.x+node.bounds.y+node.bounds.w+node.bounds.h)
	}
	allocator.phase = .Destroy
	start = time.now()
	cpu_start = construction_cpu_now()
	alicorn.destroy_runtime(&rt)
	r.destroy_cpu_ns = construction_cpu_now()-cpu_start
	r.destroy_ns = time.duration_nanoseconds(time.since(start))
	context.allocator = previous_allocator
	return r
}

main :: proc() {
	if len(os.args) != 6 {
		fmt.eprintln("usage: construction_cpu_probe <containers|short|wrapped|panel> <items> <repeats> <allocations:0|1> <wait_ms>")
		os.exit(2)
	}
	workload := os.args[1]
	count, count_ok := strconv.parse_int(os.args[2])
	repeats, repeats_ok := strconv.parse_int(os.args[3])
	wait_ms, wait_ok := strconv.parse_int(os.args[5])
	if !count_ok || !repeats_ok || !wait_ok || count < 1 || repeats < 1 || wait_ms < 0 ||
	   (workload != "containers" && workload != "short" && workload != "wrapped" && workload != "panel") {
		fmt.eprintln("invalid construction workload or count")
		os.exit(2)
	}
	tracked := os.args[4] == "1"
	allocator := Construction_Allocator{backing=context.allocator, tracking=tracked}
	if wait_ms > 0 { time.sleep(time.Duration(wait_ms)*time.Millisecond) }
	total: Construction_Result
	for _ in 0..<repeats {
		r := construction_measure(workload, count, &allocator)
		total.init_ns += r.init_ns
		total.description_ns += r.description_ns
		total.end_frame_ns += r.end_frame_ns
		total.destroy_ns += r.destroy_ns
		total.init_cpu_ns += r.init_cpu_ns
		total.description_cpu_ns += r.description_cpu_ns
		total.end_frame_cpu_ns += r.end_frame_cpu_ns
		total.destroy_cpu_ns += r.destroy_cpu_ns
		total.retained, total.display_count = r.retained, r.display_count
		total.requested_live, total.geometry_sum = r.requested_live, r.geometry_sum
	}
	expected := count+1
	if workload == "panel" { expected = count*6+1 }
	if total.retained != expected {
		fmt.eprintln("construction retained-node count mismatch", total.retained, expected)
		os.exit(1)
	}
	fmt.println("construction", "items", count, "repeats", repeats, "tracked", tracked,
		"init_ns", total.init_ns, "description_ns", total.description_ns,
		"end_frame_ns", total.end_frame_ns, "total_ns", total.description_ns+total.end_frame_ns,
		"cpu_supported", ODIN_OS != .Windows,
		"init_cpu_ns", total.init_cpu_ns, "description_cpu_ns", total.description_cpu_ns,
		"end_frame_cpu_ns", total.end_frame_cpu_ns, "total_cpu_ns", total.description_cpu_ns+total.end_frame_cpu_ns,
		"destroy_cpu_ns", total.destroy_cpu_ns,
		"destroy_ns", total.destroy_ns, "retained", total.retained,
		"display", total.display_count, "geometry_sum", total.geometry_sum)
	fmt.println("record_sizes", "pending", size_of(alicorn.Pending_Item),
		"description", size_of(alicorn.Description), "node", size_of(alicorn.Node),
		"trace_event", size_of(alicorn.Trace_Event))
	if tracked {
		for phase in Construction_Phase {
			fmt.println("allocations", phase, "calls", allocator.calls[phase], "requested_bytes", allocator.bytes[phase])
		}
		fmt.println("requested_memory", "live_after_end_frame", total.requested_live,
			"high_water", allocator.high_water, "live_after_destroy", allocator.live)
	}
}
