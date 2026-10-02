package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_native_text_quad_clip_intersection :: proc(t: ^testing.T) {
	clip := alicorn.Rect{10, 20, 100, 40}
	testing.expect(t, native_text_quad_visible(20, 30, 25, 35, clip, 1, 1), "quad fully inside clip should render")
	testing.expect(t, native_text_quad_visible(8, 30, 12, 35, clip, 1, 1), "quad crossing clip edge should render")
	testing.expect(t, !native_text_quad_visible(0, 30, 9, 35, clip, 1, 1), "quad outside horizontal clip should be culled")
	testing.expect(t, !native_text_quad_visible(20, 61, 25, 70, clip, 1, 1), "quad outside vertical clip should be culled")
	testing.expect(t, native_text_quad_visible(40, 50, 50, 60, clip, 2, 2), "clip should use the same physical scale as glyph geometry")
}
