// Standalone regression probe for the #109 correctness cases, first captured
// at 829e463. Equivalent assertions live in ui/ui_authoring_test.odin; this
// executable remains a quick, inspectable reproduction of the old failures.
package main

import "core:fmt"
import alicorn "alicorn:runtime"
import gui "alicorn:ui"

describe_cached_percentage :: proc(rt: ^alicorn.Runtime, parent_width: f32) -> f32 {
	alicorn.invalidate_root(rt, "research parent resize")
	ctx, needed := alicorn.begin_frame(rt)
	if !needed { return -1 }
	alicorn.container_begin(&ctx, .Root, key="probe-root", style=alicorn.layout_style(.Column))
	region, reused := alicorn.region_begin(&ctx, "cached-size-parent", 1,
		style=alicorn.layout_style(.Column, width=parent_width, height=100))
	if !reused {
		if gui.panel(&ctx, key="percentage-child", height=30,
			sizing=gui.sizing(width=gui.percent(0.5))) {}
		alicorn.region_end(&ctx, region, reused, 0)
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	id, found := alicorn.node_by_key(rt, alicorn.key_string("percentage-child"), .Container)
	if !found { fmt.println(rt.diagnostic); return -1 }
	info, ok := alicorn.node_info(rt, id)
	return info.bounds.w if ok else -1
}

main :: proc() {
	incremental := alicorn.new_runtime({0, 0, 1000, 200})
	defer alicorn.destroy_runtime(&incremental)
	first := describe_cached_percentage(&incremental, 400)
	second := describe_cached_percentage(&incremental, 600)
	fresh := alicorn.new_runtime({0, 0, 1000, 200})
	defer alicorn.destroy_runtime(&fresh)
	clean := describe_cached_percentage(&fresh, 600)
	fmt.printf("parent=400 child=%.0f; parent=600 cached-child=%.0f fresh-child=%.0f regions_skipped=%d expected=200/300/300\n",
		first, second, clean, incremental.stats.regions_skipped)

	panel_runtime := alicorn.new_runtime({0, 0, 600, 300})
	defer alicorn.destroy_runtime(&panel_runtime)
	ctx, _ := alicorn.begin_frame(&panel_runtime)
	alicorn.container_begin(&ctx, .Root, key="fixed-height-root")
	opened := false
	panel_id := alicorn.Node_ID(0)
	if gui.panel(&ctx, key="typed-fixed-height", sizing=gui.sizing(height=gui.logical(120))) {
		opened = true
		panel_id = ctx.runtime.pending[len(ctx.runtime.pending)-1].description.id
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	panel, found := alicorn.node_info(&panel_runtime, panel_id)
	actual_height := f32(-1) if !found else panel.bounds.h
	fmt.printf("panel typed height=120 opened=%v actual=%.0f error=%v expected=true/120/false\n",
		opened, actual_height, panel_runtime.hard_error)
}
