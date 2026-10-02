package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_native_text_vertex_capacity_grows_without_truncating :: proc(t: ^testing.T) {
	testing.expect(t, native_text_next_vertex_capacity(65536, 65536, 1000000) == 65536, "mesh within current capacity should not reallocate")
	testing.expect(t, native_text_next_vertex_capacity(65536, 65542, 1000000) == 131072, "mesh above current capacity should grow geometrically")
	testing.expect(t, native_text_next_vertex_capacity(65536, 100000, 100000) == 100000, "capacity should clamp to the representable maximum")
	testing.expect(t, native_text_next_vertex_capacity(65536, 100001, 100000) == 0, "unrepresentable GPU buffer size should be rejected")
}

@(test)
test_native_text_quad_clip_intersection :: proc(t: ^testing.T) {
	clip := alicorn.Rect{10, 20, 100, 40}
	testing.expect(t, native_text_quad_visible(20, 30, 25, 35, clip, 1, 1), "quad fully inside clip should render")
	testing.expect(t, native_text_quad_visible(8, 30, 12, 35, clip, 1, 1), "quad crossing clip edge should render")
	testing.expect(t, !native_text_quad_visible(0, 30, 9, 35, clip, 1, 1), "quad outside horizontal clip should be culled")
	testing.expect(t, !native_text_quad_visible(20, 61, 25, 70, clip, 1, 1), "quad outside vertical clip should be culled")
	testing.expect(t, native_text_quad_visible(40, 50, 50, 60, clip, 2, 2), "clip should use the same physical scale as glyph geometry")
}
