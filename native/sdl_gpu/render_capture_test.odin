package alicorn_sdl_gpu

import "core:testing"
import "vendor:sdl3"

@(test)
test_capture_outputs_rgb_for_rgba_and_bgra_swapchains :: proc(t: ^testing.T) {
	for format in ([4]sdl3.GPUTextureFormat{.R8G8B8A8_UNORM, .R8G8B8A8_UNORM_SRGB, .B8G8R8A8_UNORM, .B8G8R8A8_UNORM_SRGB}) {
		offsets, supported := native_capture_rgb_offsets(format)
		pixel := [4]u8{210, 140, 60, 255}
		if format == .B8G8R8A8_UNORM || format == .B8G8R8A8_UNORM_SRGB { pixel = {60, 140, 210, 255} }
		output := [3]u8{pixel[offsets[0]], pixel[offsets[1]], pixel[offsets[2]]}
		testing.expect(t, supported && output == [3]u8{210, 140, 60}, "diagnostic captures must preserve asymmetric warm colors on either channel order")
	}
	_, supported := native_capture_rgb_offsets(.R16G16B16A16_FLOAT)
	testing.expect(t, !supported, "capture must reject formats with a different pixel size instead of reading them as four-byte pixels")
}
