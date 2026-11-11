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

@(test)
test_native_text_color_glyph_preserves_embedded_rgb :: proc(t: ^testing.T) {
	paint := alicorn.Color{r=0.2, g=0.4, b=0.8, a=0.6}
	monochrome := native_text_vertex_color(paint, 0.5, false)
	color_glyph := native_text_vertex_color(paint, 0.5, true)
	testing.expect(t, monochrome == [4]f32{0.2, 0.4, 0.8, 0.3},
		"monochrome glyphs should retain syntax tint and multiply alpha by command opacity")
	testing.expect(t, color_glyph == [4]f32{1, 1, 1, 0.3},
		"color glyph RGB should remain from the atlas while paint alpha and opacity still apply")
}
