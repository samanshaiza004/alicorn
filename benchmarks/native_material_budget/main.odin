package main

import "core:fmt"
import "core:mem"
import "core:time"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

run_workload :: proc(rt: ^alicorn.Runtime, material: alicorn.Material_ID, scale: f32, scrolling: bool, treatment: int) {
	commands: [500]alicorn.Paint_Command
	shape: alicorn.Surface_Shape
	if treatment > 0 { shape = {kind=.Rounded_Rectangle, corner_radius=6} }
	for &command, i in commands {
		bounds := alicorn.Rect{f32(i%20)*60+4, f32(i/20)*30+4, 52, 24}
		if scrolling { bounds = {4, f32(i-250)*30+4, 1192, 24} }
		command = alicorn.paint_surface_command(alicorn.Node_ID(i+1), bounds, {0, 0, 1200, 800}, {0.3, 0.4, 0.5, 1},
			shape=shape, material=material if treatment == 2 else alicorn.MATERIAL_FLAT,
			physical_height=1 if treatment == 2 else 0)
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	renderer := host.Native_Solid_Renderer{runtime=rt,
		vertices=make([dynamic]host.Native_Text_Vertex, 0, 1, allocator=mem.tracking_allocator(&tracking)),
		draws=make([dynamic]host.Native_Solid_Draw, 0, 1, allocator=mem.tracking_allocator(&tracking)),
		vertex_capacity=500*1365,
	}
	defer delete(renderer.vertices)
	defer delete(renderer.draws)
	assert(host.native_solid_build(&renderer, commands[:], scale, scale, u32(1200*scale), u32(800*scale)))
	warm_allocations := tracking.total_allocation_count
	start := time.now()
	for _ in 0..<20 {
		assert(host.native_solid_build(&renderer, commands[:], scale, scale, u32(1200*scale), u32(800*scale)))
	}
	elapsed := time.duration_nanoseconds(time.since(start))
	visible := 0
	for draw in renderer.draws { if draw.vertex_count > 0 { visible += 1 } }
	allocations := tracking.total_allocation_count-warm_allocations
	assert(allocations == 0)
	treatments := [3]string{"flat", "rounded-flat", "rounded-relief"}
	fmt.println("material_workload", "scene", "scrolling-list" if scrolling else "controls-tabs-cards",
		"treatment", treatments[treatment], "scale", scale,
		"commands", len(commands), "visible_draws", visible,
		"vertices", len(renderer.vertices), "vertex_bytes", len(renderer.vertices)*size_of(host.Native_Text_Vertex),
		"vertex_capacity", cap(renderer.vertices), "draw_capacity", cap(renderer.draws),
		"warm_allocations", allocations, "cpu_ns_per_rebuild", elapsed/20)
}

main :: proc() {
	// Report actual expansion/draw budgets at fractional and integral scales.
	// These are CPU display-list products, not GPU timing or savings claims.
	rt := alicorn.new_runtime({0, 0, 640, 480})
	defer alicorn.destroy_runtime(&rt)
	material := alicorn.style_material_register(&rt, alicorn.Style_Material{
		kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.42,
		inner_shadow_strength=0.14, outer_shadow_strength=0.18, outer_shadow_radius=3,
	})
	for scale in ([4]f32{1, 1.25, 1.5, 2}) {
		for height in ([4]f32{0, 0.5, -0.25, 1}) {
			command := alicorn.paint_surface_command(1, {20, 20, 100, 40}, {0, 0, 640, 480}, {0.3, 0.4, 0.5, 1}, material=material, physical_height=height)
			renderer := host.Native_Solid_Renderer{runtime=&rt,
				vertices=make([dynamic]host.Native_Text_Vertex, 0, 66, allocator=context.temp_allocator),
				draws=make([dynamic]host.Native_Solid_Draw, 0, 1, allocator=context.temp_allocator), vertex_capacity=66}
			ok := host.native_solid_build(&renderer, {command}, scale, scale, u32(640*scale), u32(480*scale))
			fmt.println("material_budget", "scale", scale, "height", height, "ok", ok,
				"surface_draw_slots", len(renderer.draws), "vertices", len(renderer.vertices))
			delete(renderer.vertices)
			delete(renderer.draws)
		}
		for treatment in 0..<3 {
			run_workload(&rt, material, scale, false, treatment)
			run_workload(&rt, material, scale, true, treatment)
		}
	}
}
