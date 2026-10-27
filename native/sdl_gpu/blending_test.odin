package alicorn_sdl_gpu

import "core:testing"

@(test)
test_native_source_over_blend_state_uses_distinct_rgb_and_alpha_factors :: proc(t: ^testing.T) {
	blend := NATIVE_SOURCE_OVER_BLEND
	testing.expect(t,
		blend.src_color_blendfactor == .SRC_ALPHA && blend.dst_color_blendfactor == .ONE_MINUS_SRC_ALPHA,
		"straight-alpha source-over should weight source RGB by source alpha")
	testing.expect(t,
		blend.src_alpha_blendfactor == .ONE && blend.dst_alpha_blendfactor == .ONE_MINUS_SRC_ALPHA,
		"source-over should add source alpha once and attenuate destination alpha")
	testing.expect(t,
		blend.color_blend_op == .ADD && blend.alpha_blend_op == .ADD && blend.enable_blend,
		"source-over should use additive enabled blending for both channels")
}
