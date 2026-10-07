package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_fractional_finalized_edges_survive_native_pixel_conversion :: proc(t: ^testing.T) {
	scales := [4]f32{1.1, 1.2, 1.3, 1.75}
	for scale in scales {
		for pixel_edge in 3..<96 {
			logical_edge := f32(pixel_edge)/scale
			bounds := alicorn.Rect{logical_edge, logical_edge, 1/scale, 1/scale}
			x0, y0, x1, y1 := logical_to_pixel_bounds(bounds, scale, scale)
			solid_x0, solid_y0, solid_x1, solid_y1, visible := native_solid_pixel_bounds(
				alicorn.Paint_Command{bounds=bounds, clip=bounds},
				scale,
				scale,
				256,
				256,
			)
			testing.expect(t, x0 == pixel_edge && y0 == pixel_edge && x1 == pixel_edge+1 && y1 == pixel_edge+1,
				"shared clip conversion should recover the intended absolute pixel edges at fractional scales")
			testing.expect(t, visible && solid_x0 == pixel_edge && solid_y0 == pixel_edge &&
				solid_x1 == pixel_edge+1 && solid_y1 == pixel_edge+1,
				"solid geometry bounds should match finalized paint and hit-test edges after float round-trip")
		}
	}
}
