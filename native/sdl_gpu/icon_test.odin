package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_vector_icon_builds_clipped_dpi_scaled_stroke_vertices :: proc(t: ^testing.T) {
	vertices := make([dynamic]Native_Text_Vertex, 0, 32, context.temp_allocator)
	defer delete(vertices)
	draw := alicorn.paint_icon_command(
		1,
		alicorn.Rect{0, 0, 20, 20},
		alicorn.Rect{5, 0, 10, 20},
		.Chevron_Down,
		alicorn.Color{0.2, 0.4, 0.8, 0.8},
		stroke_width=2,
		opacity=0.5,
	)
	scales := [4]f32{1, 1.25, 1.5, 2}
	for scale in scales {
		clear(&vertices)
		added := native_solid_append_icon(&vertices, draw, scale, scale)
		testing.expect(t, added == 12 && len(vertices) == 12,
			"a two-segment chevron should produce one independent GPU quad at each tested DPI scale")
		for vertex in vertices {
			testing.expect(t, vertex.position[0] >= 5*scale && vertex.position[0] <= 15*scale &&
				vertex.position[1] >= 0 && vertex.position[1] <= 20*scale,
				"physical icon stroke vertices should be clipped to the device-scaled command bounds")
			testing.expect(t, vertex.color == [4]f32{0.2, 0.4, 0.8, 0.4},
				"icon tint and retained paint opacity should reach the GPU vertex color")
		}
	}
}
