package main

import "core:fmt"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

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
	}
}
