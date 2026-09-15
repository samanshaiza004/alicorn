package alicorn_sdl_gpu

import "core:c"
import alicorn "../../runtime"
import "vendor:sdl3"

// Solid rectangles use the same simple sampled-white shader contract as the
// custom-surface renderer, but own their vertex storage so rectangle batches
// cannot overwrite a surface mesh that is still needed later in the display
// list. Geometry is clipped on the CPU; text and custom surfaces remain hard
// ordering boundaries in the compositor.
MAX_SOLID_VERTICES :: 65536

Native_Solid_Draw :: struct {
	first_vertex:  sdl3.Uint32,
	vertex_count:  sdl3.Uint32,
}

Native_Solid_Renderer :: struct {
	device:          ^sdl3.GPUDevice,
	pipeline:        ^sdl3.GPUGraphicsPipeline,
	sampler:         ^sdl3.GPUSampler,
	white_texture:   ^sdl3.GPUTexture,
	vertex_buffer:   ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	vertices:        [dynamic]Native_Text_Vertex,
	draws:           [dynamic]Native_Solid_Draw,
	white_initialized: bool,
	upload_pending:  bool,
	batches:         u64,
	vertices_uploaded: u64,
}

native_solid_make :: proc(device: ^sdl3.GPUDevice, swapchain_format: sdl3.GPUTextureFormat) -> (renderer: Native_Solid_Renderer, ok: bool) {
	renderer.device = device
	renderer.vertices = make([dynamic]Native_Text_Vertex, 0, 4096)
	renderer.draws = make([dynamic]Native_Solid_Draw, 0, 1024)

	vertex_shader := native_text_shader(device, .VERTEX, false)
	fragment_shader := native_text_shader(device, .FRAGMENT, true)
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
		color_blend_op=.ADD, src_alpha_blendfactor=.SRC_ALPHA,
		dst_alpha_blendfactor=.ONE_MINUS_SRC_ALPHA, alpha_blend_op=.ADD,
		enable_blend=true,
	}
	targets := [1]sdl3.GPUColorTargetDescription{{format=swapchain_format, blend_state=blend}}
	pipeline_info := sdl3.GPUGraphicsPipelineCreateInfo{
		vertex_shader=vertex_shader, fragment_shader=fragment_shader,
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
		min_filter=.NEAREST, mag_filter=.NEAREST, mipmap_mode=.NEAREST,
		address_mode_u=.CLAMP_TO_EDGE, address_mode_v=.CLAMP_TO_EDGE, address_mode_w=.CLAMP_TO_EDGE,
		max_lod=1,
	})
	renderer.white_texture = sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=.R8G8B8A8_UNORM,
		usage=sdl3.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET},
		width=1, height=1, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	renderer.vertex_buffer = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage=sdl3.GPUBufferUsageFlags{.VERTEX},
		size=sdl3.Uint32(MAX_SOLID_VERTICES * size_of(Native_Text_Vertex)),
	})
	renderer.vertex_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage=.UPLOAD,
		size=sdl3.Uint32(MAX_SOLID_VERTICES * size_of(Native_Text_Vertex)),
	})
	if renderer.sampler == nil || renderer.white_texture == nil || renderer.vertex_buffer == nil || renderer.vertex_transfer == nil {
		return renderer, false
	}
	return renderer, true
}

native_solid_destroy :: proc(renderer: ^Native_Solid_Renderer) {
	if renderer.vertex_transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer) }
	if renderer.vertex_buffer != nil { sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer) }
	if renderer.white_texture != nil { sdl3.ReleaseGPUTexture(renderer.device, renderer.white_texture) }
	if renderer.sampler != nil { sdl3.ReleaseGPUSampler(renderer.device, renderer.sampler) }
	if renderer.pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(renderer.device, renderer.pipeline) }
	delete(renderer.vertices)
	delete(renderer.draws)
	renderer^ = {}
}

native_solid_append_quad :: proc(vertices: ^[dynamic]Native_Text_Vertex, x0, y0, x1, y1: f32, color: [4]f32) {
	uv := [2]f32{0.5, 0.5}
	append(vertices,
		Native_Text_Vertex{[3]f32{x0, y0, 0}, color, uv},
		Native_Text_Vertex{[3]f32{x1, y0, 0}, color, uv},
		Native_Text_Vertex{[3]f32{x1, y1, 0}, color, uv},
		Native_Text_Vertex{[3]f32{x0, y0, 0}, color, uv},
		Native_Text_Vertex{[3]f32{x1, y1, 0}, color, uv},
		Native_Text_Vertex{[3]f32{x0, y1, 0}, color, uv},
	)
}

native_solid_build :: proc(
	renderer: ^Native_Solid_Renderer,
	display: []alicorn.Display_Command,
	scale_x, scale_y: f32,
	target_w, target_h: sdl3.Uint32,
	skip_root := false,
) -> bool {
	clear(&renderer.vertices)
	clear(&renderer.draws)
	for draw in display {
		append(&renderer.draws, Native_Solid_Draw{})
	}
	for draw, i in display {
		if native_text_is_text(draw.kind) || draw.kind == .Custom_Surface { continue }
		if skip_root && draw.kind == .Root { continue }
		left := draw.bounds.x
		top := draw.bounds.y
		right := draw.bounds.x + draw.bounds.w
		bottom := draw.bounds.y + draw.bounds.h
		if draw.clip.x > left { left = draw.clip.x }
		if draw.clip.y > top { top = draw.clip.y }
		if draw.clip.x + draw.clip.w < right { right = draw.clip.x + draw.clip.w }
		if draw.clip.y + draw.clip.h < bottom { bottom = draw.clip.y + draw.clip.h }
		x0 := int(left * scale_x)
		y0 := int(top * scale_y)
		x1 := int(right * scale_x)
		y1 := int(bottom * scale_y)
		if x0 < 0 { x0 = 0 }
		if y0 < 0 { y0 = 0 }
		if x1 > int(target_w) { x1 = int(target_w) }
		if y1 > int(target_h) { y1 = int(target_h) }
		if x1 <= x0 || y1 <= y0 { continue }
		if len(renderer.vertices) + 6 > MAX_SOLID_VERTICES { return false }
		first := sdl3.Uint32(len(renderer.vertices))
		color := [4]f32{draw.color.r, draw.color.g, draw.color.b, draw.color.a}
		native_solid_append_quad(&renderer.vertices, f32(x0), f32(y0), f32(x1), f32(y1), color)
		renderer.draws[i] = Native_Solid_Draw{first, 6}
	}
	renderer.upload_pending = len(renderer.vertices) > 0
	return true
}

native_solid_prepare_white_texture :: proc(renderer: ^Native_Solid_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if renderer.white_initialized { return true }
	target := sdl3.GPUColorTargetInfo{
		texture=renderer.white_texture, clear_color=sdl3.FColor{1, 1, 1, 1},
		load_op=.CLEAR, store_op=.STORE,
	}
	pass := sdl3.BeginGPURenderPass(command, &target, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)
	renderer.white_initialized = true
	return true
}

native_solid_upload :: proc(renderer: ^Native_Solid_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if !renderer.upload_pending { return true }
	mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.vertex_transfer, true)
	if mapped == nil { return false }
	destination := cast([^]Native_Text_Vertex)mapped
	for vertex, i in renderer.vertices { destination[i] = vertex }
	sdl3.UnmapGPUTransferBuffer(renderer.device, renderer.vertex_transfer)
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTransferBufferLocation{transfer_buffer=renderer.vertex_transfer, offset=0}
	destination_region := sdl3.GPUBufferRegion{
		buffer=renderer.vertex_buffer,
		offset=0,
		size=sdl3.Uint32(len(renderer.vertices) * size_of(Native_Text_Vertex)),
	}
	sdl3.UploadToGPUBuffer(copy_pass, source, destination_region, true)
	sdl3.EndGPUCopyPass(copy_pass)
	renderer.vertices_uploaded += 1
	return true
}

native_solid_render_batch :: proc(
	renderer: ^Native_Solid_Renderer,
	command: ^sdl3.GPUCommandBuffer,
	target: ^sdl3.GPUTexture,
	target_w, target_h: sdl3.Uint32,
	draws: []Native_Solid_Draw,
) -> bool {
	has_draw := false
	for draw in draws {
		if draw.vertex_count > 0 { has_draw = true; break }
	}
	if !has_draw { return true }
	uniforms := Native_Text_Uniforms{
		proj_view = [4][4]f32{
			{2/f32(target_w), 0, 0, 0},
			{0, -2/f32(target_h), 0, 0},
			{0, 0, 1, 0},
			{-1, 1, 0, 1},
		},
		model = [4][4]f32{{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}},
	}
	sdl3.PushGPUVertexUniformData(command, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
	target_info := sdl3.GPUColorTargetInfo{texture=target, load_op=.LOAD, store_op=.STORE}
	pass := sdl3.BeginGPURenderPass(command, &target_info, 1, nil)
	if pass == nil { return false }
	sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)
	sdl3.SetGPUViewport(pass, sdl3.GPUViewport{0, 0, f32(target_w), f32(target_h), 0, 1})
	binding := sdl3.GPUBufferBinding{buffer=renderer.vertex_buffer, offset=0}
	sdl3.BindGPUVertexBuffers(pass, 0, &binding, 1)
	texture_binding := sdl3.GPUTextureSamplerBinding{texture=renderer.white_texture, sampler=renderer.sampler}
	sdl3.BindGPUFragmentSamplers(pass, 0, &texture_binding, 1)
	for draw in draws {
		if draw.vertex_count > 0 {
			sdl3.DrawGPUPrimitives(pass, draw.vertex_count, 1, draw.first_vertex, 0)
		}
	}
	sdl3.EndGPURenderPass(pass)
	renderer.batches += 1
	return true
}

native_solid_commit_submission :: proc(renderer: ^Native_Solid_Renderer) {
	renderer.upload_pending = false
}
