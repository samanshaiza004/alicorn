package main

import "core:fmt"
import "core:time"
import alicorn "../runtime"

ROOT :: alicorn.Source_Site{"benchmarks/main.odin", 1, 1, "root"}
NODE :: alicorn.Source_Site{"benchmarks/main.odin", 10, 1, "node"}
ROW :: alicorn.Source_Site{"benchmarks/main.odin", 20, 1, "virtual_row"}

render_tree :: proc(rt: ^alicorn.Runtime, count: int, changed: int, reverse: bool) {
	alicorn.invalidate_root(rt, "benchmark frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, ROOT, label="benchmark")
	for n := 0; n < count; n += 1 {
		i := reverse ? count-1-n : n
		if alicorn.key_scope_begin(&ui, fmt.aprintf("%d", i), NODE) {
			alicorn.text(&ui, "node", NODE, paint_value=u64(i == changed))
			alicorn.key_scope_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_virtual_row :: proc(ui: ^alicorn.UI, index: int) {
	alicorn.text(ui, "row", ROW, paint_value=u64(index))
}

render_virtual :: proc(rt: ^alicorn.Runtime, scroll: f32) {
	alicorn.invalidate_root(rt, "benchmark scroll")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, ROOT)
	alicorn.virtual_list(&ui, 1_000_000, scroll, 400, 20, ROW, render_virtual_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

measure_tree :: proc(count: int) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	start := time.now()
	render_tree(&rt, count, -1, false)
	first := time.duration_nanoseconds(time.since(start))
	start = time.now()
	render_tree(&rt, count, -1, false)
	unchanged := time.duration_nanoseconds(time.since(start))
	start = time.now()
	render_tree(&rt, count, count/2, false)
	one_change := time.duration_nanoseconds(time.since(start))
	start = time.now()
	render_tree(&rt, count, -1, true)
	reorder := time.duration_nanoseconds(time.since(start))
	fmt.println("tree", count, "first_ns", first, "unchanged_ns", unchanged, "one_change_ns", one_change, "keyed_reorder_ns", reorder, "nodes", len(rt.nodes), "paint_updates", rt.stats.paint_updates, "layout_updates", rt.stats.layout_updates)
}

main :: proc() {
	fmt.println("Alicorn benchmark suite (headless; raw wall-clock nanoseconds)")
	measure_tree(100)
	measure_tree(1000)
	measure_tree(10000)
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1280, 900})
	render_virtual(&rt, 0)
	start := time.now()
	for i := 0; i < 100; i += 1 { render_virtual(&rt, f32(i*400)) }
	virtual_ns := time.duration_nanoseconds(time.since(start))
	fmt.println("virtual logical_items 1000000 frames 100 elapsed_ns", virtual_ns, "retained_nodes", len(rt.nodes))
	start = time.now()
	for i := 0; i < 10000; i += 1 { _, build := alicorn.begin_frame(&rt); if build { fmt.println("unexpected idle miss") } }
	idle_ns := time.duration_nanoseconds(time.since(start))
	fmt.println("idle frames 10000 elapsed_ns", idle_ns, "idle_count", rt.stats.idle_frames, "gpu_submits", rt.stats.gpu_submits)
}
