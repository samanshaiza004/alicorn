package alicorn_sdl_gpu

import "vendor:sdl3"

// Fragment shaders output straight-alpha color. Coverage and command opacity
// multiply source alpha, not source RGB. Source-over therefore accumulates
// RGB = Cs*As + Cd*(1-As), alpha = As + Ad*(1-As).
NATIVE_SOURCE_OVER_BLEND :: sdl3.GPUColorTargetBlendState{
	src_color_blendfactor=.SRC_ALPHA, dst_color_blendfactor=.ONE_MINUS_SRC_ALPHA,
	color_blend_op=.ADD, src_alpha_blendfactor=.ONE,
	dst_alpha_blendfactor=.ONE_MINUS_SRC_ALPHA, alpha_blend_op=.ADD,
	enable_blend=true,
}
