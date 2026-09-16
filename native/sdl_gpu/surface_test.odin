package alicorn_sdl_gpu

import "core:math"
import "core:testing"

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
