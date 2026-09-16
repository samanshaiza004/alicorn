package alicorn_sdl_gpu

import "core:math"
import "core:c"
import alicorn "../../runtime"
import "vendor:sdl3"

MAX_SURFACE_VERTICES :: 8192

Native_Surface_Renderer :: struct {
	device: ^sdl3.GPUDevice,
	pipeline: ^sdl3.GPUGraphicsPipeline,
	sampler: ^sdl3.GPUSampler,
	white_texture: ^sdl3.GPUTexture,
	vertex_buffer: ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	runtime: ^alicorn.Runtime,
	vertices: [dynamic]Native_Text_Vertex,
	mesh_valid: bool,
	mesh_fingerprint: u64,
	vertex_upload_pending: bool,
	white_texture_initialized: bool,
	resource_creations: u64,
	vertex_uploads: u64,
	encodes: u64,
}

native_surface_mix :: proc(h, value: u64) -> u64 {
	return native_text_hash_mix(h, value)
}

native_surface_color :: proc(r, g, b, a: f32) -> [4]f32 {
	return [4]f32{r, g, b, a}
}

native_surface_vertex :: proc(x, y: f32, color: [4]f32) -> Native_Text_Vertex {
	return Native_Text_Vertex{[3]f32{x, y, 0}, color, [2]f32{0.5, 0.5}}
}

native_surface_append_quad :: proc(vertices: ^[dynamic]Native_Text_Vertex, x0, y0, x1, y1, scale_x, scale_y: f32, color: [4]f32) {
	append(vertices,
		native_surface_vertex(x0*scale_x, y0*scale_y, color),
		native_surface_vertex(x1*scale_x, y0*scale_y, color),
		native_surface_vertex(x1*scale_x, y1*scale_y, color),
		native_surface_vertex(x0*scale_x, y0*scale_y, color),
		native_surface_vertex(x1*scale_x, y1*scale_y, color),
		native_surface_vertex(x0*scale_x, y1*scale_y, color),
	)
}

native_surface_append_segment :: proc(vertices: ^[dynamic]Native_Text_Vertex, ax, ay, bx, by, scale_x, scale_y, thickness: f32, color: [4]f32) -> bool {
	dx := bx - ax
	dy := by - ay
	length := math.sqrt(dx*dx + dy*dy)
	if length <= 0.001 { return true }
	half := thickness * 0.5
	nx := -dy / length * half
	ny := dx / length * half
	if len(vertices^) + 6 > MAX_SURFACE_VERTICES { return false }
	append(vertices,
		native_surface_vertex((ax-nx)*scale_x, (ay-ny)*scale_y, color),
		native_surface_vertex((bx-nx)*scale_x, (by-ny)*scale_y, color),
		native_surface_vertex((bx+nx)*scale_x, (by+ny)*scale_y, color),
		native_surface_vertex((ax-nx)*scale_x, (ay-ny)*scale_y, color),
		native_surface_vertex((bx+nx)*scale_x, (by+ny)*scale_y, color),
		native_surface_vertex((ax+nx)*scale_x, (ay+ny)*scale_y, color),
	)
	return true
}

native_surface_make :: proc(device: ^sdl3.GPUDevice, swapchain_format: sdl3.GPUTextureFormat, runtime: ^alicorn.Runtime) -> (renderer: Native_Surface_Renderer, ok: bool) {
	renderer.device = device
	renderer.runtime = runtime
	renderer.vertices = make([dynamic]Native_Text_Vertex, 0, 4096)

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
	renderer.vertex_buffer = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{usage=sdl3.GPUBufferUsageFlags{.VERTEX}, size=sdl3.Uint32(MAX_SURFACE_VERTICES * size_of(Native_Text_Vertex))})
	renderer.vertex_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=sdl3.Uint32(MAX_SURFACE_VERTICES * size_of(Native_Text_Vertex))})
	if renderer.sampler == nil || renderer.white_texture == nil || renderer.vertex_buffer == nil || renderer.vertex_transfer == nil {
		return renderer, false
	}
	renderer.resource_creations = 5
	return renderer, true
}

native_surface_destroy :: proc(renderer: ^Native_Surface_Renderer) {
	if renderer.vertex_transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer) }
	if renderer.vertex_buffer != nil { sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer) }
	if renderer.white_texture != nil { sdl3.ReleaseGPUTexture(renderer.device, renderer.white_texture) }
	if renderer.sampler != nil { sdl3.ReleaseGPUSampler(renderer.device, renderer.sampler) }
	if renderer.pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(renderer.device, renderer.pipeline) }
	delete(renderer.vertices)
	renderer^ = {}
}

native_surface_rebuild_mesh :: proc(renderer: ^Native_Surface_Renderer, id: alicorn.Node_ID, scale_x, scale_y: f32) -> bool {
	node, ok := renderer.runtime.nodes[id]
	if !ok || node == nil || !node.active || node.kind != .Custom_Surface { return false }
	h: u64 = 1469598103934665603
	h = native_surface_mix(h, u64(node.surface_revision))
	h = native_surface_mix(h, u64(len(node.surface_samples)))
	h = native_surface_mix(h, u64(transmute(u32)scale_x))
	h = native_surface_mix(h, u64(transmute(u32)scale_y))
	h = native_surface_mix(h, native_text_hash_rect(h, node.bounds))
	h = native_surface_mix(h, native_text_hash_rect(h, node.clip))
	if renderer.mesh_valid && renderer.mesh_fingerprint == h { return true }
	clear(&renderer.vertices)
	native_surface_append_quad(&renderer.vertices, node.bounds.x, node.bounds.y, node.bounds.x+node.bounds.w, node.bounds.y+node.bounds.h, scale_x, scale_y, native_surface_color(0.08, 0.14, 0.24, 1))
	if len(node.surface_samples) > 1 {
		line_color := native_surface_color(0.30, 0.88, 0.96, 1)
		for i := 0; i+1 < len(node.surface_samples); i += 1 {
			a := node.surface_samples[i]
			b := node.surface_samples[i+1]
			if a < 0 { a = 0 }; if a > 1 { a = 1 }
			if b < 0 { b = 0 }; if b > 1 { b = 1 }
			x0 := node.bounds.x + node.bounds.w * f32(i) / f32(len(node.surface_samples)-1)
			x1 := node.bounds.x + node.bounds.w * f32(i+1) / f32(len(node.surface_samples)-1)
			y0 := node.bounds.y + node.bounds.h * (1-a)
			y1 := node.bounds.y + node.bounds.h * (1-b)
			if !native_surface_append_segment(&renderer.vertices, x0, y0, x1, y1, scale_x, scale_y, 2, line_color) { return false }
		}
	}
	renderer.mesh_fingerprint = h
	renderer.mesh_valid = true
	renderer.vertex_upload_pending = len(renderer.vertices) > 0
	return true
}

native_surface_prepare_white_texture :: proc(renderer: ^Native_Surface_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if renderer.white_texture_initialized { return true }
	target := sdl3.GPUColorTargetInfo{
		texture=renderer.white_texture, clear_color=sdl3.FColor{1, 1, 1, 1},
		load_op=.CLEAR, store_op=.STORE,
	}
	pass := sdl3.BeginGPURenderPass(command, &target, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)
	renderer.white_texture_initialized = true
	return true
}

native_surface_upload_vertices :: proc(renderer: ^Native_Surface_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if !renderer.vertex_upload_pending { return true }
	mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.vertex_transfer, true)
	if mapped == nil || len(renderer.vertices) > MAX_SURFACE_VERTICES { return false }
	destination := cast([^]Native_Text_Vertex)mapped
	for vertex, i in renderer.vertices { destination[i] = vertex }
	sdl3.UnmapGPUTransferBuffer(renderer.device, renderer.vertex_transfer)
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTransferBufferLocation{transfer_buffer=renderer.vertex_transfer, offset=0}
	destination_region := sdl3.GPUBufferRegion{buffer=renderer.vertex_buffer, offset=0, size=sdl3.Uint32(len(renderer.vertices) * size_of(Native_Text_Vertex))}
	sdl3.UploadToGPUBuffer(copy_pass, source, destination_region, true)
	sdl3.EndGPUCopyPass(copy_pass)
	renderer.vertex_uploads += 1
	return true
}

native_surface_commit_submission :: proc(renderer: ^Native_Surface_Renderer) {
	renderer.vertex_upload_pending = false
}

native_surface_render_command :: proc(
	renderer: ^Native_Surface_Renderer,
	command_buffer: ^sdl3.GPUCommandBuffer,
	command: alicorn.Display_Command,
	target: ^sdl3.GPUTexture,
	target_w, target_h: sdl3.Uint32,
	scale_x, scale_y: f32,
) -> bool {
	if !native_surface_prepare_white_texture(renderer, command_buffer) { return false }
	if !native_surface_rebuild_mesh(renderer, command.node, scale_x, scale_y) { return false }
	if !native_surface_upload_vertices(renderer, command_buffer) { return false }
	if len(renderer.vertices) == 0 { return true }
	uniforms := Native_Text_Uniforms{
		proj_view = [4][4]f32{
			{2/f32(target_w), 0, 0, 0},
			{0, -2/f32(target_h), 0, 0},
			{0, 0, 1, 0},
			{-1, 1, 0, 1},
		},
		model = [4][4]f32{{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}},
	}
	sdl3.PushGPUVertexUniformData(command_buffer, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
	target_info := sdl3.GPUColorTargetInfo{texture=target, clear_color=sdl3.FColor{}, load_op=.LOAD, store_op=.STORE}
	pass := sdl3.BeginGPURenderPass(command_buffer, &target_info, 1, nil)
	if pass == nil { return false }
	sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)
	sdl3.SetGPUViewport(pass, sdl3.GPUViewport{0, 0, f32(target_w), f32(target_h), 0, 1})
	// A surface cannot draw outside either its retained parent clip or its own
	// logical bounds. The intersection is the surface's effective scissor.
	clip := command.clip
	left := command.clip.x if command.clip.x > command.bounds.x else command.bounds.x
	top := command.clip.y if command.clip.y > command.bounds.y else command.bounds.y
	right_clip := command.clip.x + command.clip.w
	right_bounds := command.bounds.x + command.bounds.w
	right := right_clip if right_clip < right_bounds else right_bounds
	bottom_clip := command.clip.y + command.clip.h
	bottom_bounds := command.bounds.y + command.bounds.h
	bottom := bottom_clip if bottom_clip < bottom_bounds else bottom_bounds
	clip = alicorn.Rect{left, top, right-left, bottom-top}
	x0, y0, x1, y1 := logical_to_pixel_bounds(clip, scale_x, scale_y)
	if x0 < 0 { x0 = 0 }; if y0 < 0 { y0 = 0 }
	if x1 > int(target_w) { x1 = int(target_w) }; if y1 > int(target_h) { y1 = int(target_h) }
	if x1 > x0 && y1 > y0 {
		sdl3.SetGPUScissor(pass, sdl3.Rect{x=c.int(x0), y=c.int(y0), w=c.int(x1-x0), h=c.int(y1-y0)})
		binding := sdl3.GPUBufferBinding{buffer=renderer.vertex_buffer, offset=0}
		sdl3.BindGPUVertexBuffers(pass, 0, &binding, 1)
		texture_binding := sdl3.GPUTextureSamplerBinding{texture=renderer.white_texture, sampler=renderer.sampler}
		sdl3.BindGPUFragmentSamplers(pass, 0, &texture_binding, 1)
		sdl3.DrawGPUPrimitives(pass, sdl3.Uint32(len(renderer.vertices)), 1, 0, 0)
	}
	sdl3.EndGPURenderPass(pass)
	renderer.encodes += 1
	return true
}
