package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

NATIVE_IMAGE_INITIAL_VERTICES :: 4096

Native_GPU_Image :: struct {
	handle: alicorn.Image_Handle,
	texture: ^sdl3.GPUTexture,
	live: bool,
	ready: bool,
}

Native_Image_Upload :: struct {
	handle: alicorn.Image_Handle,
	texture: ^sdl3.GPUTexture,
	transfer: ^sdl3.GPUTransferBuffer,
}

Native_Image_Draw :: struct {
	first_vertex: sdl3.Uint32,
	vertex_count: sdl3.Uint32,
	handle: alicorn.Image_Handle,
}

// Image textures and their transient upload buffers belong to one GPU device.
// CPU pixels remain Runtime-owned, allowing texture recreation after a host
// restart without transferring image ownership to the renderer.
Native_Image_Renderer :: struct {
	device: ^sdl3.GPUDevice,
	runtime: ^alicorn.Runtime,
	texture_format: sdl3.GPUTextureFormat,
	pipeline: ^sdl3.GPUGraphicsPipeline,
	sampler: ^sdl3.GPUSampler,
	vertex_buffer: ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	vertex_capacity: int,
	vertices: [dynamic]Native_Text_Vertex,
	draws: [dynamic]Native_Image_Draw,
	images: [dynamic]Native_GPU_Image,
	uploads: [dynamic]Native_Image_Upload,
	mesh_valid, upload_pending: bool,
	mesh_fingerprint: u64,
}

native_image_fragment_shader :: proc(device: ^sdl3.GPUDevice) -> ^sdl3.GPUShader {
	supported := sdl3.GetGPUShaderFormats(device)
	info := sdl3.GPUShaderCreateInfo{stage=.FRAGMENT, num_samplers=1}
	if native_shader_supported(supported, {.DXIL}) {
		info.format = {.DXIL}; info.code = &GPU_IMAGE_FRAG_DXIL[0]; info.code_size = uint(len(GPU_IMAGE_FRAG_DXIL)); info.entrypoint = "PSMain"
	} else if native_shader_supported(supported, {.MSL}) {
		info.format = {.MSL}; info.code = &GPU_IMAGE_FRAG_MSL[0]; info.code_size = uint(len(GPU_IMAGE_FRAG_MSL)); info.entrypoint = "PSMain"
	} else if native_shader_supported(supported, {.SPIRV}) {
		info.format = {.SPIRV}; info.code = &GPU_IMAGE_FRAG_SPV[0]; info.code_size = uint(len(GPU_IMAGE_FRAG_SPV)); info.entrypoint = "main"
	}
	if info.code == nil { return nil }
	return sdl3.CreateGPUShader(device, info)
}

native_image_make :: proc(device: ^sdl3.GPUDevice, swapchain_format: sdl3.GPUTextureFormat, runtime: ^alicorn.Runtime) -> (renderer: Native_Image_Renderer, ok: bool) {
	if device == nil || runtime == nil { return renderer, false }
	renderer.device = device
	renderer.runtime = runtime
	// SDL's default SDR swapchain consumes sRGB-encoded values without a
	// hardware transfer function. Only linear/sRGB targets should decode the
	// source texture; decoding for an ordinary UNORM target darkens midtones.
	renderer.texture_format = .R8G8B8A8_UNORM
	if swapchain_format == .R8G8B8A8_UNORM_SRGB || swapchain_format == .B8G8R8A8_UNORM_SRGB {
		renderer.texture_format = .R8G8B8A8_UNORM_SRGB
	}
	defer if !ok { native_image_destroy(&renderer) }
	renderer.vertex_capacity = NATIVE_IMAGE_INITIAL_VERTICES
	renderer.vertices = make([dynamic]Native_Text_Vertex, 0, 4096)
	renderer.draws = make([dynamic]Native_Image_Draw, 0, 512)
	renderer.images = make([dynamic]Native_GPU_Image, 0, 16)
	renderer.uploads = make([dynamic]Native_Image_Upload, 0, 4)
	vertex_shader := native_text_shader(device, .VERTEX, false)
	fragment_shader := native_image_fragment_shader(device)
	if vertex_shader == nil || fragment_shader == nil {
		if vertex_shader != nil { sdl3.ReleaseGPUShader(device, vertex_shader) }
		if fragment_shader != nil { sdl3.ReleaseGPUShader(device, fragment_shader) }
		return renderer, false
	}
	vertex_buffers := [1]sdl3.GPUVertexBufferDescription{{slot=0, pitch=sdl3.Uint32(size_of(Native_Text_Vertex)), input_rate=.VERTEX}}
	attributes := [3]sdl3.GPUVertexAttribute{
		{location=0, buffer_slot=0, format=.FLOAT3, offset=0},
		{location=1, buffer_slot=0, format=.FLOAT4, offset=sdl3.Uint32(size_of([3]f32))},
		{location=2, buffer_slot=0, format=.FLOAT2, offset=sdl3.Uint32(size_of([3]f32) + size_of([4]f32))},
	}
	blend := sdl3.GPUColorTargetBlendState{
		src_color_blendfactor=.SRC_ALPHA, dst_color_blendfactor=.ONE_MINUS_SRC_ALPHA,
		color_blend_op=.ADD, src_alpha_blendfactor=.ONE,
		dst_alpha_blendfactor=.ONE_MINUS_SRC_ALPHA, alpha_blend_op=.ADD,
		enable_blend=true,
	}
	targets := [1]sdl3.GPUColorTargetDescription{{format=swapchain_format, blend_state=blend}}
	pipeline_info := sdl3.GPUGraphicsPipelineCreateInfo{
		vertex_shader=vertex_shader,
		fragment_shader=fragment_shader,
		vertex_input_state=sdl3.GPUVertexInputState{
			vertex_buffer_descriptions=&vertex_buffers[0], num_vertex_buffers=1,
			vertex_attributes=&attributes[0], num_vertex_attributes=3,
		},
		primitive_type=.TRIANGLELIST,
		rasterizer_state=sdl3.GPURasterizerState{fill_mode=.FILL, cull_mode=.NONE, front_face=.COUNTER_CLOCKWISE, enable_depth_clip=true},
		target_info=sdl3.GPUGraphicsPipelineTargetInfo{color_target_descriptions=&targets[0], num_color_targets=1},
	}
	renderer.pipeline = sdl3.CreateGPUGraphicsPipeline(device, pipeline_info)
	sdl3.ReleaseGPUShader(device, vertex_shader)
	sdl3.ReleaseGPUShader(device, fragment_shader)
	if renderer.pipeline == nil { return renderer, false }
	renderer.sampler = sdl3.CreateGPUSampler(device, sdl3.GPUSamplerCreateInfo{
		min_filter=.LINEAR, mag_filter=.LINEAR, mipmap_mode=.NEAREST,
		address_mode_u=.CLAMP_TO_EDGE, address_mode_v=.CLAMP_TO_EDGE, address_mode_w=.CLAMP_TO_EDGE,
		max_lod=1,
	})
	renderer.vertex_buffer = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage={.VERTEX}, size=sdl3.Uint32(renderer.vertex_capacity*size_of(Native_Text_Vertex)),
	})
	renderer.vertex_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage=.UPLOAD, size=sdl3.Uint32(renderer.vertex_capacity*size_of(Native_Text_Vertex)),
	})
	if renderer.sampler == nil || renderer.vertex_buffer == nil || renderer.vertex_transfer == nil { return renderer, false }
	return renderer, true
}

native_image_cache_index :: proc(renderer: ^Native_Image_Renderer, handle: alicorn.Image_Handle) -> int {
	for image, index in renderer.images {
		if image.handle == handle { return index }
	}
	return -1
}

native_image_release_unsubmitted :: proc(renderer: ^Native_Image_Renderer) {
	if renderer == nil { return }
	for upload in renderer.uploads {
		if upload.transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, upload.transfer) }
		if upload.texture != nil { sdl3.ReleaseGPUTexture(renderer.device, upload.texture) }
		index := native_image_cache_index(renderer, upload.handle)
		if index >= 0 {
			for i in index+1..<len(renderer.images) { renderer.images[i-1] = renderer.images[i] }
			pop(&renderer.images)
		}
	}
	clear(&renderer.uploads)
}

// Synchronize only newly visible image handles. Texture creation and upload are
// retained until the corresponding frame submission succeeds; ordinary frames
// perform no asset upload work.
native_image_sync :: proc(renderer: ^Native_Image_Renderer, command: ^sdl3.GPUCommandBuffer, display: []alicorn.Paint_Command) -> bool {
	if renderer == nil || renderer.runtime == nil { return false }
	if len(renderer.uploads) > 0 { native_image_release_unsubmitted(renderer) }
	for &image in renderer.images { image.live = false }
	for draw in display {
		paint, is_image := draw.payload.(alicorn.Image_Paint)
		if !is_image { continue }
		pixels, valid := alicorn.image_resolve(renderer.runtime, paint.image)
		if !valid { continue }
		index := native_image_cache_index(renderer, paint.image)
		if index >= 0 {
			renderer.images[index].live = true
			continue
		}
		width, height := sdl3.Uint32(pixels.width), sdl3.Uint32(pixels.height)
		texture := sdl3.CreateGPUTexture(renderer.device, sdl3.GPUTextureCreateInfo{
			type=.D2, format=renderer.texture_format, usage={.SAMPLER},
			width=width, height=height, layer_count_or_depth=1, num_levels=1, sample_count=._1,
		})
		if texture == nil { return false }
		transfer_size := width*height*4
		transfer := sdl3.CreateGPUTransferBuffer(renderer.device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=transfer_size})
		if transfer == nil { sdl3.ReleaseGPUTexture(renderer.device, texture); return false }
		mapped := sdl3.MapGPUTransferBuffer(renderer.device, transfer, false)
		if mapped == nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, transfer); sdl3.ReleaseGPUTexture(renderer.device, texture); return false }
		transfer_bytes := cast([^]u8)mapped
		for value, index in pixels.rgba8 { transfer_bytes[index] = value }
		sdl3.UnmapGPUTransferBuffer(renderer.device, transfer)
		append(&renderer.images, Native_GPU_Image{handle=paint.image, texture=texture, live=true, ready=false})
		append(&renderer.uploads, Native_Image_Upload{paint.image, texture, transfer})
	}
	retired := false
	for i := len(renderer.images)-1; i >= 0; i -= 1 {
		if renderer.images[i].live { continue }
		sdl3.ReleaseGPUTexture(renderer.device, renderer.images[i].texture)
		for j in i+1..<len(renderer.images) { renderer.images[j-1] = renderer.images[j] }
		pop(&renderer.images)
		retired = true
	}
	if retired { renderer.mesh_valid = false }
	if len(renderer.uploads) == 0 { return true }
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	for upload in renderer.uploads {
		pixels, ok := alicorn.image_resolve(renderer.runtime, upload.handle)
		if !ok { sdl3.EndGPUCopyPass(copy_pass); return false }
		source := sdl3.GPUTextureTransferInfo{transfer_buffer=upload.transfer, offset=0}
		destination := sdl3.GPUTextureRegion{texture=upload.texture, w=sdl3.Uint32(pixels.width), h=sdl3.Uint32(pixels.height), d=1}
		sdl3.UploadToGPUTexture(copy_pass, source, destination, false)
	}
	sdl3.EndGPUCopyPass(copy_pass)
	return true
}

native_image_commit_submission :: proc(renderer: ^Native_Image_Renderer) {
	if renderer == nil { return }
	for upload in renderer.uploads {
		index := native_image_cache_index(renderer, upload.handle)
		if index >= 0 { renderer.images[index].ready = true }
		if upload.transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, upload.transfer) }
	}
	clear(&renderer.uploads)
}

native_image_pixel_quad :: proc(vertices: ^[dynamic]Native_Text_Vertex, draw: alicorn.Paint_Command, scale_x, scale_y: f32, target_w, target_h: sdl3.Uint32) -> bool {
	paint, ok := draw.payload.(alicorn.Image_Paint)
	if !ok || scale_x <= 0 || scale_y <= 0 { return false }
	bounds := draw.bounds
	bounds.x += draw.translation[0]; bounds.y += draw.translation[1]
	x0, y0, x1, y1 := logical_to_pixel_bounds(bounds, scale_x, scale_y)
	if x1 <= x0 || y1 <= y0 { return false }
	cx0, cy0, cx1, cy1 := logical_to_pixel_bounds(draw.clip, scale_x, scale_y)
	left, top := max(x0, cx0, 0), max(y0, cy0, 0)
	right, bottom := min(x1, cx1, int(target_w)), min(y1, cy1, int(target_h))
	if right <= left || bottom <= top { return false }
	u0, v0 := f32(left-x0)/f32(x1-x0), f32(top-y0)/f32(y1-y0)
	u1, v1 := f32(right-x0)/f32(x1-x0), f32(bottom-y0)/f32(y1-y0)
	color := [4]f32{1, 1, 1, draw.opacity}
	a := Native_Text_Vertex{{f32(left), f32(top), 0}, color, {u0,v0}}
	b := Native_Text_Vertex{{f32(right), f32(top), 0}, color, {u1,v0}}
	c := Native_Text_Vertex{{f32(right), f32(bottom), 0}, color, {u1,v1}}
	d := Native_Text_Vertex{{f32(left), f32(bottom), 0}, color, {u0,v1}}
	append(vertices, a,b,c,a,c,d)
	_ = paint
	return true
}

native_image_hash_handle :: proc(h: u64, handle: alicorn.Image_Handle) -> u64 {
	return native_text_hash_mix(h, u64(handle))
}

native_image_build :: proc(renderer: ^Native_Image_Renderer, display: []alicorn.Paint_Command, scale_x, scale_y: f32, target_w, target_h: sdl3.Uint32) -> bool {
	h := native_text_hash_mix(1469598103934665603, u64(len(display)))
	h = native_text_hash_mix(h, u64(transmute(u32)scale_x)); h = native_text_hash_mix(h, u64(transmute(u32)scale_y))
	h = native_text_hash_mix(h, u64(target_w)); h = native_text_hash_mix(h, u64(target_h))
	for command, index in display {
		paint, ok := command.payload.(alicorn.Image_Paint)
		if !ok { continue }
		h = native_image_hash_handle(h, paint.image); h = native_text_hash_mix(h, u64(index))
		h = native_text_hash_rect(h, command.bounds); h = native_text_hash_rect(h, command.clip)
		h = native_text_hash_mix(h, u64(transmute(u32)command.opacity))
		h = native_text_hash_mix(h, u64(transmute(u32)command.translation[0])); h = native_text_hash_mix(h, u64(transmute(u32)command.translation[1]))
	}
	if renderer.mesh_valid && renderer.mesh_fingerprint == h { return true }
	clear(&renderer.vertices); clear(&renderer.draws)
	for command in display {
		append(&renderer.draws, Native_Image_Draw{})
	}
	needed := 0
	for command in display { if alicorn.paint_command_is_image(command) { needed += 6 } }
	maximum := int(sdl3.Uint32(0xFFFFFFFF)/sdl3.Uint32(size_of(Native_Text_Vertex)))
	new_capacity := native_next_vertex_capacity(renderer.vertex_capacity, needed, maximum)
	if new_capacity == 0 { return false }
	if new_capacity != renderer.vertex_capacity {
		new_buffer := sdl3.CreateGPUBuffer(renderer.device, sdl3.GPUBufferCreateInfo{usage={.VERTEX}, size=sdl3.Uint32(new_capacity*size_of(Native_Text_Vertex))})
		if new_buffer == nil { return false }
		new_transfer := sdl3.CreateGPUTransferBuffer(renderer.device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=sdl3.Uint32(new_capacity*size_of(Native_Text_Vertex))})
		if new_transfer == nil { sdl3.ReleaseGPUBuffer(renderer.device, new_buffer); return false }
		if !sdl3.WaitForGPUIdle(renderer.device) { sdl3.ReleaseGPUTransferBuffer(renderer.device,new_transfer); sdl3.ReleaseGPUBuffer(renderer.device,new_buffer); return false }
		sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer); sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer)
		renderer.vertex_buffer, renderer.vertex_transfer, renderer.vertex_capacity = new_buffer, new_transfer, new_capacity
	}
	for command, index in display {
		if !alicorn.paint_command_is_image(command) { continue }
		paint, _ := command.payload.(alicorn.Image_Paint)
		if native_image_cache_index(renderer, paint.image) < 0 { continue }
		first := sdl3.Uint32(len(renderer.vertices))
		if native_image_pixel_quad(&renderer.vertices, command, scale_x, scale_y, target_w, target_h) {
			renderer.draws[index] = Native_Image_Draw{first, 6, paint.image}
		}
	}
	renderer.mesh_valid = true
	renderer.mesh_fingerprint = h
	renderer.upload_pending = len(renderer.vertices) > 0
	return true
}

native_image_upload_vertices :: proc(renderer: ^Native_Image_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if !renderer.upload_pending { return true }
	mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.vertex_transfer, true)
	if mapped == nil { return false }
	vertex_destination := cast([^]Native_Text_Vertex)mapped
	for vertex, index in renderer.vertices { vertex_destination[index] = vertex }
	sdl3.UnmapGPUTransferBuffer(renderer.device, renderer.vertex_transfer)
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTransferBufferLocation{transfer_buffer=renderer.vertex_transfer, offset=0}
	destination_region := sdl3.GPUBufferRegion{buffer=renderer.vertex_buffer, offset=0, size=sdl3.Uint32(len(renderer.vertices)*size_of(Native_Text_Vertex))}
	sdl3.UploadToGPUBuffer(copy_pass, source, destination_region, true)
	sdl3.EndGPUCopyPass(copy_pass)
	return true
}

native_image_render_batch :: proc(renderer: ^Native_Image_Renderer, command: ^sdl3.GPUCommandBuffer, target: ^sdl3.GPUTexture, target_w, target_h: sdl3.Uint32, draws: []Native_Image_Draw) -> bool {
	any := false
	for draw in draws { if draw.vertex_count > 0 { any = true; break } }
	if !any { return true }
	uniforms := Native_Text_Uniforms{proj_view=[4][4]f32{{2/f32(target_w),0,0,0},{0,-2/f32(target_h),0,0},{0,0,1,0},{-1,1,0,1}}, model=[4][4]f32{{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}}}
	sdl3.PushGPUVertexUniformData(command, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
	target_info := sdl3.GPUColorTargetInfo{texture=target, load_op=.LOAD, store_op=.STORE}
	pass := sdl3.BeginGPURenderPass(command, &target_info, 1, nil)
	if pass == nil { return false }
	sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)
	sdl3.SetGPUViewport(pass, sdl3.GPUViewport{0,0,f32(target_w),f32(target_h),0,1})
	binding := sdl3.GPUBufferBinding{buffer=renderer.vertex_buffer}
	sdl3.BindGPUVertexBuffers(pass, 0, &binding, 1)
	for draw in draws {
		if draw.vertex_count == 0 { continue }
		index := native_image_cache_index(renderer, draw.handle)
		if index < 0 { continue }
		sampler := sdl3.GPUTextureSamplerBinding{texture=renderer.images[index].texture, sampler=renderer.sampler}
		sdl3.BindGPUFragmentSamplers(pass, 0, &sampler, 1)
		sdl3.DrawGPUPrimitives(pass, draw.vertex_count, 1, draw.first_vertex, 0)
	}
	sdl3.EndGPURenderPass(pass)
	return true
}

native_image_destroy :: proc(renderer: ^Native_Image_Renderer) {
	if renderer == nil { return }
	for upload in renderer.uploads { if upload.transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, upload.transfer) } }
	for image in renderer.images { if image.texture != nil { sdl3.ReleaseGPUTexture(renderer.device, image.texture) } }
	if renderer.vertex_transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer) }
	if renderer.vertex_buffer != nil { sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer) }
	if renderer.sampler != nil { sdl3.ReleaseGPUSampler(renderer.device, renderer.sampler) }
	if renderer.pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(renderer.device, renderer.pipeline) }
	delete(renderer.vertices); delete(renderer.draws); delete(renderer.images); delete(renderer.uploads)
	renderer^ = {}
}
