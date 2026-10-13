package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_icon_renderer_missing_device_fails_without_retained_resources :: proc(t: ^testing.T) {
	renderer, ok := native_icon_make(nil, .R8G8B8A8_UNORM, nil)
	testing.expect(t, !ok && renderer.pipeline == nil && renderer.vertex_buffer == nil && len(renderer.vertices) == 0,
		"icon initialization without a GPU device should fail before allocating resources")
	native_icon_destroy(&renderer)
	native_icon_destroy(&renderer)
	testing.expect(t, renderer.device == nil && renderer.pipeline == nil,
		"teardown should remain safe after failed initialization and repeated destruction")
}

@(test)
test_icon_mask_quad_preserves_clipping_dpi_and_tint :: proc(t: ^testing.T) {
	vertices := make([dynamic]Native_Text_Vertex, 0, 32, context.temp_allocator)
	defer delete(vertices)
	draw := alicorn.paint_icon_command(
		1,
		alicorn.Rect{0, 0, 20, 20},
		alicorn.Rect{5, 0, 10, 20},
		.Chevron_Down,
		alicorn.Color{0.2, 0.4, 0.8, 0.8},
		opacity=0.5,
	)
	scales := [4]f32{1, 1.25, 1.5, 2}
	for scale in scales {
		clear(&vertices)
		cx0, cy0, cx1, cy1 := logical_to_pixel_bounds(draw.clip, scale, scale)
		entry, added := native_icon_append_quad(&vertices, draw, scale, scale, 800, 600)
		testing.expect(t, added && len(vertices) == 6 && entry.size == int(20*scale),
			"an icon should use one mask quad selected from its full physical size before clipping")
		for vertex in vertices {
			testing.expect(t, vertex.position[0] >= f32(cx0) && vertex.position[0] <= f32(cx1) &&
				vertex.position[1] >= f32(cy0) && vertex.position[1] <= f32(cy1),
				"physical icon mask vertices should be clipped to the device-scaled command bounds")
			testing.expect(t, vertex.color == [4]f32{0.2, 0.4, 0.8, 0.4},
				"icon tint and retained paint opacity should reach the GPU vertex color")
		}
	}
}
