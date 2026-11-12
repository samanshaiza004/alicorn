package main

import "core:fmt"
import "core:time"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

SURFACE_COUNT :: 4096
ITERATIONS    :: 80
SAMPLES       :: 3
SHAPE_SURFACE_COUNT :: 256
SHAPE_SAMPLES       :: 101

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

build_shape_geometry :: proc(vertices: ^[dynamic]host.Native_Text_Vertex, shape: alicorn.Surface_Shape) {
	clear(vertices)
	for i in 0..<SHAPE_SURFACE_COUNT {
		bounds := alicorn.Rect{f32(i%16)*52, f32(i/16)*30, 48, 24}
		if !host.native_solid_shape_is_rounded(shape) {
			host.native_solid_append_quad(vertices, bounds.x, bounds.y, bounds.x+bounds.w, bounds.y+bounds.h,
				[4]f32{0.3, 0.4, 0.5, 1})
		} else {
			host.native_solid_append_rounded_material_surface(
				vertices, bounds, bounds, alicorn.Color{0.3, 0.4, 0.5, 1},
				alicorn.STYLE_MATERIAL_FLAT, 0, 1, shape,
			)
		}
	}
}

sort_durations :: proc(samples: []i64) {
	for i in 1..<len(samples) {
		value := samples[i]
		j := i
		for j > 0 && samples[j-1] > value {
			samples[j] = samples[j-1]
			j -= 1
		}
		samples[j] = value
	}
}

benchmark_shape_geometry :: proc(name: string, shape: alicorn.Surface_Shape) {
	vertices := make([dynamic]host.Native_Text_Vertex, 0,
		SHAPE_SURFACE_COUNT*host.NATIVE_ROUNDED_FILL_VERTICES, allocator=context.temp_allocator)
	defer delete(vertices)
	samples := make([dynamic]i64, 0, SHAPE_SAMPLES, allocator=context.temp_allocator)
	defer delete(samples)
	for _ in 0..<3 { build_shape_geometry(&vertices, shape) }
	for _ in 0..<SHAPE_SAMPLES {
		started := time.now()
		build_shape_geometry(&vertices, shape)
		append(&samples, time.duration_nanoseconds(time.since(started)))
	}
	sort_durations(samples[:])
	p50_index := SHAPE_SAMPLES/2
	p95_index := (SHAPE_SAMPLES*95+99)/100-1
	fmt.println("native_shape_geometry", name,
		"surfaces", SHAPE_SURFACE_COUNT,
		"vertices_per_surface", len(vertices)/SHAPE_SURFACE_COUNT,
		"p50_batch_ns", samples[p50_index],
		"p95_batch_ns", samples[p95_index],
		"p50_ns_per_surface", f64(samples[p50_index])/f64(SHAPE_SURFACE_COUNT),
		"p95_ns_per_surface", f64(samples[p95_index])/f64(SHAPE_SURFACE_COUNT),
	)
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

	// Compare the unchanged six-vertex rectangle path with legacy uniform
	// rounding and asymmetric per-corner tessellation at a realistic control
	// group size. These CPU timings exclude layout, command composition, GPU
	// upload, and presentation; raw batches report p50 and p95 to expose tails.
	fmt.println("Alicorn native surface geometry benchmark; 256 surfaces per batch; CPU vertex expansion only")
	benchmark_shape_geometry("rectangle", alicorn.Surface_Shape{kind=.Rectangle})
	benchmark_shape_geometry("uniform-rounded", alicorn.surface_shape_uniform_corner_radius(10))
	benchmark_shape_geometry("per-corner-rounded", alicorn.surface_shape_rounded_corners(
		alicorn.Surface_Corner_Radii{top_left=4, top_right=14, bottom_right=8, bottom_left=2},
	))
}
