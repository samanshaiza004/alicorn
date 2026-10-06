package main

import "core:fmt"
import "core:time"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

SURFACE_COUNT :: 4096
ITERATIONS    :: 80
SAMPLES       :: 3

run_batch :: proc(vertices: ^[dynamic]host.Native_Text_Vertex, material_path: bool) -> (elapsed_ns: i64, checksum: f64) {
	start := time.now()
	for _ in 0..<ITERATIONS {
		clear(vertices)
		for i in 0..<SURFACE_COUNT {
			x := f32(i % 128)
			if material_path {
				host.native_solid_append_material_surface(
					vertices,
					alicorn.Rect{x, 10, 48, 24},
					alicorn.Rect{x, 10, 48, 24},
					alicorn.Color{0.3, 0.4, 0.5, 1},
					alicorn.STYLE_MATERIAL_FLAT,
					0,
					1,
				)
			} else {
				host.native_solid_append_quad(vertices, x, 10, x+48, 34, [4]f32{0.3, 0.4, 0.5, 1})
			}
		}
	}
	elapsed_ns = time.duration_nanoseconds(time.since(start))
	for vertex in vertices^ {
		checksum += f64(vertex.position[0]) + f64(vertex.position[1]) + f64(vertex.position[2])
		checksum += f64(vertex.color[0]) + f64(vertex.color[1]) + f64(vertex.color[2]) + f64(vertex.color[3])
	}
	return
}

main :: proc() {
	vertices := make([dynamic]host.Native_Text_Vertex, 0, SURFACE_COUNT*6, allocator=context.temp_allocator)
	defer delete(vertices)

	// Warm the same preallocated storage before reporting. Both cases create the
	// same vertex stream and perform no buffer allocation inside the timed loop.
	_, _ = run_batch(&vertices, false)
	_, _ = run_batch(&vertices, true)
	fmt.println("Alicorn native material flat-path benchmark; CPU vertex expansion only")
	fmt.println("surfaces_per_sample", SURFACE_COUNT, "iterations", ITERATIONS, "vertices_per_batch", SURFACE_COUNT*6)
	for sample in 0..<SAMPLES {
		direct_ns, direct_checksum := run_batch(&vertices, false)
		flat_ns, flat_checksum := run_batch(&vertices, true)
		fmt.println(
			"sample", sample+1,
			"direct_quad_ns", direct_ns,
			"flat_material_ns", flat_ns,
			"direct_ns_per_surface", f64(direct_ns)/f64(SURFACE_COUNT*ITERATIONS),
			"flat_ns_per_surface", f64(flat_ns)/f64(SURFACE_COUNT*ITERATIONS),
			"vertices", len(vertices),
			"capacity", cap(vertices),
			"same_output", direct_checksum == flat_checksum,
		)
	}
}
