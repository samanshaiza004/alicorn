package alicorn_sdl_gpu

import "core:fmt"
import "core:math"
import alicorn "../../runtime"
import "vendor:sdl3"

image_validation_qoi :: [27]u8{
	'q','o','i','f', 0,0,0,1, 0,0,0,1, 4,0,
	0xFF, 0xFF, 0xFF, 0xFF, 0x80,
	0,0,0,0,0,0,0,1,
}

native_image_readback_case :: proc(
	renderer: ^Native_Image_Renderer,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	display: []alicorn.Paint_Command,
	scale: f32,
) -> bool {
	device := renderer.device
	width, height := sdl3.Uint32(64), sdl3.Uint32(64)
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil { return false }
	submitted := false
	defer if !submitted { _ = sdl3.CancelGPUCommandBuffer(command) }
	if !native_image_sync(renderer, command, display) { return false }
	if !native_image_build(renderer, display, scale, scale, width, height) { return false }
	if !native_image_upload_vertices(renderer, command) { return false }
	background := sdl3.FColor{0.10, 0.20, 0.30, 0.40}
	clear_target := sdl3.GPUColorTargetInfo{texture=target, clear_color=background, load_op=.CLEAR, store_op=.STORE}
	clear_pass := sdl3.BeginGPURenderPass(command, &clear_target, 1, nil)
	if clear_pass == nil { return false }
	sdl3.EndGPURenderPass(clear_pass)
	if !native_image_render_batch(renderer, command, target, width, height, renderer.draws[:]) { return false }
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTextureRegion{texture=target, w=width, h=height, d=1}
	destination := sdl3.GPUTextureTransferInfo{transfer_buffer=download, pixels_per_row=width, rows_per_layer=height}
	sdl3.DownloadFromGPUTexture(copy_pass, source, destination)
	sdl3.EndGPUCopyPass(copy_pass)
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	submitted = true
	if fence == nil { return false }
	defer sdl3.ReleaseGPUFence(device, fence)
	// Release staging buffers only after the command containing their uploads
	// was accepted, matching the application compositor's submission contract.
	native_image_commit_submission(renderer)
	fences := [1]^sdl3.GPUFence{fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) { return false }
	mapped := sdl3.MapGPUTransferBuffer(device, download, false)
	if mapped == nil { return false }
	defer sdl3.UnmapGPUTransferBuffer(device, download)
	pixels := cast([^]u8)mapped
	left, top, right, bottom := logical_to_pixel_bounds(alicorn.Rect{4,4,8,8}, scale, scale)
	blend_alpha := (f32(128)/f32(255))*0.5
	background_channels := [4]f32{background.r, background.g, background.b, background.a}
	for y in 0..<int(height) {
		for x in 0..<int(width) {
			inside := x >= left && x < right && y >= top && y < bottom
			alpha := f32(0)
			if inside { alpha = blend_alpha }
			expected := [4]f32{
				alpha + background_channels[0]*(1-alpha),
				alpha + background_channels[1]*(1-alpha),
				alpha + background_channels[2]*(1-alpha),
				alpha + background_channels[3]*(1-alpha),
			}
			offset := (y*int(width)+x)*4
			for channel in 0..<4 {
				want := math.round(expected[channel]*255)
				if abs(f32(pixels[offset+channel])-want) > 2 {
					fmt.println("image_readback_mismatch", "scale", scale, "pixel", x, y, "channel", channel, "actual", pixels[offset+channel], "expected", want)
					return false
				}
			}
		}
	}
	return true
}

native_image_validate_device :: proc() -> bool {
	driver: cstring = nil
	when ODIN_OS == .Windows { driver = "direct3d12" }
	when ODIN_OS == .Darwin { driver = "metal" }
	device := sdl3.CreateGPUDevice({.DXIL,.MSL,.SPIRV}, false, driver)
	if device == nil { return false }
	defer sdl3.DestroyGPUDevice(device)
	rt := alicorn.new_runtime(alicorn.Rect{0,0,64,64})
	defer alicorn.destroy_runtime(&rt)
	encoded := image_validation_qoi
	handle, load_error := alicorn.image_load_bytes(&rt, encoded[:])
	if load_error != .None { return false }
	defer _ = alicorn.image_release(&rt, handle)
	renderer, renderer_ok := native_image_make(device, .R8G8B8A8_UNORM, &rt)
	if !renderer_ok { return false }
	defer native_image_destroy(&renderer)
	target := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=.R8G8B8A8_UNORM, usage={.COLOR_TARGET},
		width=64, height=64, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if target == nil { return false }
	defer sdl3.ReleaseGPUTexture(device, target)
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.DOWNLOAD, size=64*64*4})
	if download == nil { return false }
	defer sdl3.ReleaseGPUTransferBuffer(device, download)
	display := [1]alicorn.Paint_Command{
		alicorn.paint_image_command(1, alicorn.Rect{4,4,8,8}, alicorn.Rect{0,0,64,64}, handle, opacity=0.5),
	}
	scales := [4]f32{1,1.25,1.5,2}
	for scale in scales {
		if !native_image_readback_case(&renderer, target, download, display[:], scale) { return false }
	}
	if len(renderer.images) != 1 || !renderer.images[0].ready || len(renderer.uploads) != 0 { return false }
	fmt.println("image_gpu_validation", "driver", sdl3.GetGPUDeviceDriver(device), "scales", "1,1.25,1.5,2", "cached_textures", len(renderer.images), "correct_source_over", true)
	return true
}

// RunImageValidation exercises real sampled-image rendering and transparent
// source-over readback on the platform's selected SDL_GPU backend.
RunImageValidation :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("image validation SDL initialization failed") }
	defer sdl3.Quit()
	if !native_image_validate_device() { fail("image texture GPU validation failed") }
}
