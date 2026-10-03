package alicorn_sdl_gpu

import "core:math"
import "core:testing"
import alicorn "../../runtime"

surface_test_near :: proc(a, b: f32, epsilon: f32 = 0.001) -> bool {
	delta := a - b
	if delta < 0 { delta = -delta }
	return delta <= epsilon
}

@(test)
test_surface_segment_scales_vertices :: proc(t: ^testing.T) {
	vertices: [dynamic]Native_Text_Vertex
	defer delete(vertices)

	ok := native_surface_append_segment(
		&vertices,
		10, 20,
		30, 40,
		2, 2,
		2,
		[4]f32{1, 1, 1, 1},
	)
	testing.expect(t, ok && len(vertices) == 6, "scaled surface segment must emit its complete triangle")
	if len(vertices) != 6 { return }

	// The first vertex is the logical start minus the normalized line normal.
	// At 2x Retina scale both coordinates must be in physical pixels.
	logical_nx := -1 / math.sqrt(f32(2))
	logical_ny := 1 / math.sqrt(f32(2))
	testing.expect(t,
		surface_test_near(vertices[0].position.x, (10-logical_nx)*2) &&
			surface_test_near(vertices[0].position.y, (20-logical_ny)*2),
		"surface line vertices must convert logical coordinates to physical pixels")
}

@(test)
test_waveform_mesh_fits_exact_runtime_sample_limit :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 120, 40})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "waveform mesh capacity test")
	ui, should_build := alicorn.begin_frame(&rt)
	if !should_build {
		testing.expect(t, false, "initial waveform tree should build")
		return
	}
	alicorn.container_begin(&ui, .Root, label="waveform-capacity-root")
	surface := alicorn.gpu_surface(&ui, "waveform-capacity-surface", alicorn.Rect{0, 0, 120, 40}, 120, 40, 1)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)

	samples := make([]f32, alicorn.GPU_SURFACE_MAX_WAVEFORM_SAMPLES)
	defer delete(samples)
	for i in 0..<len(samples) { samples[i] = 0.5 }
	testing.expect(t, alicorn.gpu_surface_update(&rt, surface, samples),
		"runtime should accept exactly the waveform capacity")

	renderer := Native_Surface_Renderer{
		runtime=&rt,
		vertices=make([dynamic]Native_Text_Vertex, 0, alicorn.GPU_SURFACE_MAX_VERTICES),
	}
	defer delete(renderer.vertices)
	testing.expect(t, native_surface_rebuild_mesh(&renderer, surface, 1, 1),
		"native waveform mesh at the documented maximum should build")
	testing.expect(t, len(renderer.vertices) == alicorn.GPU_SURFACE_MAX_WAVEFORM_SAMPLES*6,
		"maximum waveform should use 8,190 vertices, within the 8,192-vertex budget")
}
