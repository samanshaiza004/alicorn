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

image_validation_decode_srgb :: proc(value: f32) -> f32 {
	if value <= 0.04045 { return value/12.92 }
	return math.pow((value+0.055)/1.055, f32(2.4))
}

image_validation_encode_srgb :: proc(value: f32) -> f32 {
	if value <= 0.0031308 { return value*12.92 }
	return 1.055*math.pow(value, f32(1.0/2.4))-0.055
}

native_image_readback_case :: proc(
	renderer: ^Native_Image_Renderer,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	display: []alicorn.Paint_Command,
	scale: f32,
	source_rgba: [4]u8,
	target_srgb: bool,
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
	draw := display[0]
	bounds := draw.bounds
	bounds.x += draw.translation[0]; bounds.y += draw.translation[1]
	left, top, right, bottom := logical_to_pixel_bounds(alicorn.rect_intersection(bounds, draw.clip), scale, scale)
	blend_alpha := (f32(source_rgba[3])/255)*draw.opacity
	background_channels := [4]f32{background.r, background.g, background.b, background.a}
	for y in 0..<int(height) {
		for x in 0..<int(width) {
			inside := x >= left && x < right && y >= top && y < bottom
			alpha := f32(0)
			if inside { alpha = blend_alpha }
			offset := (y*int(width)+x)*4
			for channel in 0..<4 {
				expected := alpha+background_channels[channel]*(1-alpha)
				if channel < 3 {
					source := f32(source_rgba[channel])/255
					if target_srgb { source = image_validation_decode_srgb(source) }
					expected = source*alpha+background_channels[channel]*(1-alpha)
					if target_srgb { expected = image_validation_encode_srgb(expected) }
				}
				want := math.round(expected*255)
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
	formats := [?]sdl3.GPUTextureFormat{.R8G8B8A8_UNORM, .R8G8B8A8_UNORM_SRGB}
	for format in formats {
		if !native_image_validate_target(device, &rt, format) { return false }
	}
	fmt.println("image_gpu_validation", "driver", sdl3.GetGPUDeviceDriver(device), "scales", "1,1.25,1.5,2", "targets", "SDR,SDR_LINEAR", "midtone_fidelity", true, "clipped_translation", true, "correct_source_over", true)
	return true
}

native_image_validate_target :: proc(device: ^sdl3.GPUDevice, rt: ^alicorn.Runtime, format: sdl3.GPUTextureFormat) -> bool {
	renderer, renderer_ok := native_image_make(device, format, rt)
	if !renderer_ok { return false }
	defer native_image_destroy(&renderer)
	target := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=format, usage={.COLOR_TARGET},
		width=64, height=64, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if target == nil { return false }
	defer sdl3.ReleaseGPUTexture(device, target)
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.DOWNLOAD, size=64*64*4})
	if download == nil { return false }
	defer sdl3.ReleaseGPUTransferBuffer(device, download)
	scales := [4]f32{1,1.25,1.5,2}
	clip_cases := [2]bool{false,true}
	colors := [?][4]u8{{255,255,255,128}, {128,96,180,255}, {35,120,193,128}}
	for color in colors {
		encoded := image_validation_qoi
		for channel in 0..<4 { encoded[15+channel] = color[channel] }
		handle, load_error := alicorn.image_load_bytes(rt, encoded[:])
		if load_error != .None { return false }
		defer _ = alicorn.image_release(rt, handle)
		for scale in scales {
			for clipped in clip_cases {
				clip := alicorn.Rect{0,0,64,64}
				if clipped { clip = alicorn.Rect{5,5,5,5} }
				display := [1]alicorn.Paint_Command{
					alicorn.paint_image_command(1, alicorn.Rect{2,2,8,8}, clip, handle, opacity=1 if color[3] == 255 else 0.5, translation={2,2}),
				}
				if !native_image_readback_case(&renderer, target, download, display[:], scale, color, format == .R8G8B8A8_UNORM_SRGB) { return false }
				if len(renderer.images) != 1 || !renderer.images[0].ready || len(renderer.uploads) != 0 { return false }
			}
		}
	}
	return true
}

// RunImageValidation exercises real sampled-image rendering and transparent
// source-over readback on the platform's selected SDL_GPU backend.
RunImageValidation :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("image validation SDL initialization failed") }
	defer sdl3.Quit()
	if !native_image_validate_device() { fail("image texture GPU validation failed") }
}
