package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

// Write a dependency-free screenshot artifact for diagnostics captures. PPM
// is intentionally used instead of pulling an image encoder into the host;
// it is trivial for humans, scripts, and agents to inspect or convert.
native_capture_display_ppm :: proc(
	device: ^sdl3.GPUDevice,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	display: []alicorn.Display_Command,
	width, height: sdl3.Uint32,
	scale_x, scale_y: f32,
	path: string,
	debug_bounds := false,
	inspector: ^Native_Inspector_Overlay = nil,
	scratch_allocator := context.temp_allocator,
) -> bool {
	if width == 0 || height == 0 { return false }
	if !sdl3.GPUTextureSupportsFormat(device, text_renderer.swapchain_format, .D2, sdl3.GPUTextureUsageFlags{.COLOR_TARGET}) {
		return false
	}
	texture := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=text_renderer.swapchain_format, usage=sdl3.GPUTextureUsageFlags{.COLOR_TARGET},
		width=width, height=height, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if texture == nil { return false }
	defer sdl3.ReleaseGPUTexture(device, texture)
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.DOWNLOAD, size=width * height * 4})
	if download == nil { return false }
	defer sdl3.ReleaseGPUTransferBuffer(device, download)
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil { return false }
	if !draw_display_list(command, texture, width, height, text_renderer, surface_renderer, solid_renderer, display, scale_x, scale_y, debug_bounds=debug_bounds, scratch_allocator=scratch_allocator) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	if !native_inspector_render(inspector, surface_renderer, command, texture, width, height, scale_x, scale_y,
		scratch_allocator=scratch_allocator) {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil {
		_ = sdl3.CancelGPUCommandBuffer(command)
		return false
	}
	source := sdl3.GPUTextureRegion{texture=texture, mip_level=0, layer=0, x=0, y=0, z=0, w=width, h=height, d=1}
	destination := sdl3.GPUTextureTransferInfo{transfer_buffer=download, offset=0, pixels_per_row=width, rows_per_layer=height}
	sdl3.DownloadFromGPUTexture(copy_pass, source, destination)
	sdl3.EndGPUCopyPass(copy_pass)
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	if fence == nil { return false }
	defer sdl3.ReleaseGPUFence(device, fence)
	fences := [1]^sdl3.GPUFence{fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) { return false }
	mapped := sdl3.MapGPUTransferBuffer(device, download, false)
	if mapped == nil { return false }
	defer sdl3.UnmapGPUTransferBuffer(device, download)
	pixels := cast([^]u8)mapped
	builder, builder_err := strings.builder_make_len_cap(0, int(width*height*3)+64)
	if builder_err != nil { return false }
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, "P6\n%d %d\n255\n", width, height)
	for i := u64(0); i < u64(width)*u64(height); i += 1 {
		src := i * 4
		strings.write_byte(&builder, pixels[src+0])
		strings.write_byte(&builder, pixels[src+1])
		strings.write_byte(&builder, pixels[src+2])
	}
	image := strings.to_string(builder)
	if err := os.write_entire_file(path, image); err != nil { return false }
	native_text_commit_submission(text_renderer)
	native_surface_commit_submission(surface_renderer)
	native_solid_commit_submission(solid_renderer)
	if native_inspector_visible(inspector) {
		native_text_commit_submission(&inspector.text_renderer)
		native_solid_commit_submission(&inspector.solid_renderer)
	}
	return true
}
