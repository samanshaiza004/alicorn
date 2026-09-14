package main

import "core:strings"
import alicorn "../../runtime"
import runa "../../third_party/Runa"
import "vendor:sdl3"

MAX_TEXT_VERTICES :: 65536
TEXT_LOGICAL_SIZE: f32 = 16

Native_Text_Vertex :: struct {
	position: [3]f32,
	color:    [4]f32,
	uv:       [2]f32,
}

Native_Text_Uniforms :: struct {
	proj_view: [4][4]f32,
	model:     [4][4]f32,
}

Native_Atlas_Page :: struct {
	page_index: u16,
	is_color:   bool,
	width:      u16,
	height:     u16,
	texture:    ^sdl3.GPUTexture,
}

Native_Text_Draw :: struct {
	first_vertex: sdl3.Uint32,
	page_index:   u16,
	is_color:     bool,
}

Native_Text_Cached_Run :: struct {
	run:          alicorn.Text_Run,
	raster_scale: f32,
	bounds:       alicorn.Rect,
	has_bounds:   bool,
}

Native_Text_Renderer :: struct {
	device:         ^sdl3.GPUDevice,
	swapchain_format: sdl3.GPUTextureFormat,
	pipeline:       ^sdl3.GPUGraphicsPipeline,
	sampler:        ^sdl3.GPUSampler,
	atlas_transfer: ^sdl3.GPUTransferBuffer,
	vertex_buffer:  ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	engine:         alicorn.Text_Engine,
	runs:           map[alicorn.Node_ID]^Native_Text_Cached_Run,
	pages:          [dynamic]Native_Atlas_Page,
	vertices:       [dynamic]Native_Text_Vertex,
	draws:          [dynamic]Native_Text_Draw,
	pending_dirty:  [dynamic]runa.Atlas_Dirty_View,
	mesh_valid:     bool,
	vertex_upload_pending: bool,
	last_scale_x:   f32,
	last_scale_y:   f32,
	run_cache_hits: u64,
	run_cache_misses: u64,
}

native_shader_supported :: proc(supported: sdl3.GPUShaderFormat, format: sdl3.GPUShaderFormat) -> bool {
	return (supported & format) != sdl3.GPUShaderFormat{}
}

native_text_shader :: proc(device: ^sdl3.GPUDevice, stage: sdl3.GPUShaderStage, fragment: bool) -> ^sdl3.GPUShader {
	supported := sdl3.GetGPUShaderFormats(device)
	info := sdl3.GPUShaderCreateInfo{stage=stage}
	if native_shader_supported(supported, sdl3.GPUShaderFormat{.DXIL}) {
		info.format = sdl3.GPUShaderFormat{.DXIL}
		if fragment {
			info.code = &GPU_TEXT_FRAG_DXIL[0]
			info.code_size = uint(len(GPU_TEXT_FRAG_DXIL))
			info.entrypoint = "PSMain"
		} else {
			info.code = &GPU_TEXT_VERT_DXIL[0]
			info.code_size = uint(len(GPU_TEXT_VERT_DXIL))
			info.entrypoint = "VSMain"
		}
	} else if native_shader_supported(supported, sdl3.GPUShaderFormat{.MSL}) {
		info.format = sdl3.GPUShaderFormat{.MSL}
		if fragment {
			info.code = &GPU_TEXT_FRAG_MSL[0]
			info.code_size = uint(len(GPU_TEXT_FRAG_MSL))
			info.entrypoint = "main0"
		} else {
			info.code = &GPU_TEXT_VERT_MSL[0]
			info.code_size = uint(len(GPU_TEXT_VERT_MSL))
			info.entrypoint = "main0"
		}
	} else if native_shader_supported(supported, sdl3.GPUShaderFormat{.SPIRV}) {
		info.format = sdl3.GPUShaderFormat{.SPIRV}
		if fragment {
			info.code = &GPU_TEXT_FRAG_SPV[0]
			info.code_size = uint(len(GPU_TEXT_FRAG_SPV))
			info.entrypoint = "main"
		} else {
			info.code = &GPU_TEXT_VERT_SPV[0]
			info.code_size = uint(len(GPU_TEXT_VERT_SPV))
			info.entrypoint = "main"
		}
	}
	if info.code == nil { return nil }
	if fragment { info.num_samplers = 1 } else { info.num_uniform_buffers = 1 }
	return sdl3.CreateGPUShader(device, info)
}

native_text_page :: proc(renderer: ^Native_Text_Renderer, page_index: u16, is_color: bool) -> ^Native_Atlas_Page {
	for &page in renderer.pages {
		if page.page_index == page_index && page.is_color == is_color { return &page }
	}
	return nil
}

native_text_make :: proc(device: ^sdl3.GPUDevice, swapchain_format: sdl3.GPUTextureFormat, font_data: []u8) -> (renderer: Native_Text_Renderer, ok: bool) {
	renderer.device = device
	renderer.swapchain_format = swapchain_format
	renderer.engine = alicorn.new_text_engine("Runa GPU text", true)
	renderer.runs = make(map[alicorn.Node_ID]^Native_Text_Cached_Run)
	renderer.pages = make([dynamic]Native_Atlas_Page, 0, 4)
	renderer.vertices = make([dynamic]Native_Text_Vertex, 0, 4096)
	renderer.draws = make([dynamic]Native_Text_Draw, 0, 512)
	renderer.pending_dirty = make([dynamic]runa.Atlas_Dirty_View, 0, 4)
	if !alicorn.text_engine_load_font(&renderer.engine, font_data) { return renderer, false }

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
		src_color_blendfactor=.SRC_ALPHA,
		dst_color_blendfactor=.ONE_MINUS_SRC_ALPHA,
		color_blend_op=.ADD,
		src_alpha_blendfactor=.SRC_ALPHA,
		dst_alpha_blendfactor=.ONE_MINUS_SRC_ALPHA,
		alpha_blend_op=.ADD,
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
	renderer.vertex_buffer = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{usage=sdl3.GPUBufferUsageFlags{.VERTEX}, size=sdl3.Uint32(MAX_TEXT_VERTICES * size_of(Native_Text_Vertex))})
	renderer.vertex_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=sdl3.Uint32(MAX_TEXT_VERTICES * size_of(Native_Text_Vertex))})
	renderer.atlas_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=4 * 1024 * 1024})
	if renderer.sampler == nil || renderer.vertex_buffer == nil || renderer.vertex_transfer == nil || renderer.atlas_transfer == nil {
		return renderer, false
	}
	ok = true
	return
}

native_text_destroy :: proc(renderer: ^Native_Text_Renderer) {
	for _, cached in renderer.runs {
		if cached != nil {
			alicorn.text_run_destroy(&cached.run)
			free(cached)
		}
	}
	delete(renderer.runs)
	for page in renderer.pages {
		if page.texture != nil { sdl3.ReleaseGPUTexture(renderer.device, page.texture) }
	}
	delete(renderer.pages)
	if renderer.atlas_transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.atlas_transfer) }
	if renderer.vertex_transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer) }
	if renderer.vertex_buffer != nil { sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer) }
	if renderer.sampler != nil { sdl3.ReleaseGPUSampler(renderer.device, renderer.sampler) }
	if renderer.pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(renderer.device, renderer.pipeline) }
	delete(renderer.vertices)
	delete(renderer.draws)
	delete(renderer.pending_dirty)
	alicorn.text_engine_destroy(&renderer.engine)
	renderer^ = {}
}

native_text_get_run :: proc(renderer: ^Native_Text_Renderer, command: alicorn.Display_Command, raster_scale: f32) -> (^Native_Text_Cached_Run, bool) {
	cached: ^Native_Text_Cached_Run
	if existing, found := renderer.runs[command.node]; found && existing != nil {
		cached = existing
		if cached.run.value == command.text && cached.raster_scale == raster_scale {
			renderer.run_cache_hits += 1
			return cached, false
		}
		alicorn.text_run_destroy(&cached.run)
	} else {
		cached = new(Native_Text_Cached_Run)
		renderer.runs[command.node] = cached
	}
	renderer.run_cache_misses += 1
	run, ok := alicorn.text_run_build(&renderer.engine, command.text, TEXT_LOGICAL_SIZE * raster_scale)
	if !ok {
		return cached, false
	}
	cached.run = run
	cached.raster_scale = raster_scale
	cached.has_bounds = false
	return cached, true
}

native_text_is_text :: proc(kind: alicorn.Node_Kind) -> bool {
	return kind == .Text || kind == .Text_Field
}

native_text_rebuild_mesh :: proc(renderer: ^Native_Text_Renderer, display: []alicorn.Display_Command, scale_x, scale_y: f32) -> bool {
	raster_scale := scale_x
	if scale_y > raster_scale { raster_scale = scale_y }
	if raster_scale <= 0 { raster_scale = 1 }
	needs_rebuild := !renderer.mesh_valid || renderer.last_scale_x != scale_x || renderer.last_scale_y != scale_y
	for command in display {
		if !native_text_is_text(command.kind) { continue }
		cached, changed := native_text_get_run(renderer, command, raster_scale)
		if cached == nil || cached.run.value != command.text { continue }
		if changed || !cached.has_bounds || cached.bounds != command.bounds { needs_rebuild = true }
	}
	if !needs_rebuild { return true }
	clear(&renderer.vertices)
	clear(&renderer.draws)
	for command in display {
		if !native_text_is_text(command.kind) { continue }
		cached, _ := native_text_get_run(renderer, command, raster_scale)
		if cached == nil || cached.run.value != command.text { continue }
		cached.bounds = command.bounds
		cached.has_bounds = true
		for glyph in cached.run.glyphs {
			if !glyph.drawable { continue }
			if len(renderer.vertices) + 6 > MAX_TEXT_VERTICES { return false }
			slot := runa.atlas_slot_view(glyph.slot)
			x0 := (command.bounds.x + (glyph.x + slot.Bearing[0]) / raster_scale) * scale_x
			y0 := (command.bounds.y + (glyph.y + slot.Bearing[1]) / raster_scale) * scale_y
			x1 := x0 + f32(slot.Px_Size[0]) * scale_x / raster_scale
			y1 := y0 + f32(slot.Px_Size[1]) * scale_y / raster_scale
			u0, v0, u1, v1 := slot.UV_Rect[0], slot.UV_Rect[1], slot.UV_Rect[2], slot.UV_Rect[3]
			color := [4]f32{command.color.r, command.color.g, command.color.b, command.color.a}
			first := sdl3.Uint32(len(renderer.vertices))
			append(&renderer.vertices,
				Native_Text_Vertex{[3]f32{x0, y0, 0}, color, [2]f32{u0, v0}},
				Native_Text_Vertex{[3]f32{x1, y0, 0}, color, [2]f32{u1, v0}},
				Native_Text_Vertex{[3]f32{x1, y1, 0}, color, [2]f32{u1, v1}},
				Native_Text_Vertex{[3]f32{x0, y0, 0}, color, [2]f32{u0, v0}},
				Native_Text_Vertex{[3]f32{x1, y1, 0}, color, [2]f32{u1, v1}},
				Native_Text_Vertex{[3]f32{x0, y1, 0}, color, [2]f32{u0, v1}},
			)
			append(&renderer.draws, Native_Text_Draw{first, slot.Page_Index, slot.Is_Color})
		}
	}
	renderer.last_scale_x = scale_x
	renderer.last_scale_y = scale_y
	renderer.mesh_valid = true
	renderer.vertex_upload_pending = true
	return true
}

native_text_sync_atlas :: proc(renderer: ^Native_Text_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	snapshot := runa.atlas_dirty_snapshot(&renderer.engine.atlas, context.temp_allocator)
	if len(snapshot) == 0 { return true }
	for dirty in snapshot {
		view, ok := runa.atlas_page_view(&renderer.engine.atlas, dirty.Page_Index, dirty.Is_Color)
		if !ok { delete(snapshot, context.temp_allocator); return false }
		page := native_text_page(renderer, dirty.Page_Index, dirty.Is_Color)
		if page == nil {
			texture := sdl3.CreateGPUTexture(renderer.device, sdl3.GPUTextureCreateInfo{
				type=.D2, format=.R8G8B8A8_UNORM, usage=sdl3.GPUTextureUsageFlags{.SAMPLER},
				width=sdl3.Uint32(view.Width), height=sdl3.Uint32(view.Height), layer_count_or_depth=1, num_levels=1, sample_count=._1,
			})
			if texture == nil { delete(snapshot, context.temp_allocator); return false }
			append(&renderer.pages, Native_Atlas_Page{dirty.Page_Index, dirty.Is_Color, view.Width, view.Height, texture})
			page = &renderer.pages[len(renderer.pages)-1]
		}
		bpp := 4
		row_bytes := int(dirty.W) * bpp
		upload_bytes := row_bytes * int(dirty.H)
		mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.atlas_transfer, true)
		if mapped == nil || upload_bytes > 4*1024*1024 { delete(snapshot, context.temp_allocator); return false }
		destination := cast([^]u8)mapped
		for y in 0..<int(dirty.H) {
			src_row := (int(dirty.Y)+y) * int(view.Width)
			for x in 0..<int(dirty.W) {
				src := view.Pixels[src_row + int(dirty.X) + x]
				dst := (y * int(dirty.W) + x) * 4
				if dirty.Is_Color {
					src4 := (src_row + int(dirty.X) + x) * 4
					destination[dst+0] = view.Pixels[src4+0]
					destination[dst+1] = view.Pixels[src4+1]
					destination[dst+2] = view.Pixels[src4+2]
					destination[dst+3] = view.Pixels[src4+3]
				} else {
					destination[dst+0] = 255
					destination[dst+1] = 255
					destination[dst+2] = 255
					destination[dst+3] = src
				}
			}
		}
		sdl3.UnmapGPUTransferBuffer(renderer.device, renderer.atlas_transfer)
		copy_pass := sdl3.BeginGPUCopyPass(command)
		if copy_pass == nil { delete(snapshot, context.temp_allocator); return false }
		source := sdl3.GPUTextureTransferInfo{transfer_buffer=renderer.atlas_transfer, offset=0, pixels_per_row=sdl3.Uint32(dirty.W), rows_per_layer=sdl3.Uint32(dirty.H)}
		destination_region := sdl3.GPUTextureRegion{texture=page.texture, mip_level=0, layer=0, x=sdl3.Uint32(dirty.X), y=sdl3.Uint32(dirty.Y), z=0, w=sdl3.Uint32(dirty.W), h=sdl3.Uint32(dirty.H), d=1}
		sdl3.UploadToGPUTexture(copy_pass, source, destination_region, true)
		sdl3.EndGPUCopyPass(copy_pass)
		append(&renderer.pending_dirty, dirty)
	}
	delete(snapshot, context.temp_allocator)
	return true
}

native_text_upload_vertices :: proc(renderer: ^Native_Text_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if !renderer.vertex_upload_pending { return true }
	mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.vertex_transfer, true)
	if mapped == nil || len(renderer.vertices) > MAX_TEXT_VERTICES { return false }
	destination := cast([^]Native_Text_Vertex)mapped
	for vertex, i in renderer.vertices { destination[i] = vertex }
	sdl3.UnmapGPUTransferBuffer(renderer.device, renderer.vertex_transfer)
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTransferBufferLocation{transfer_buffer=renderer.vertex_transfer, offset=0}
	destination_region := sdl3.GPUBufferRegion{buffer=renderer.vertex_buffer, offset=0, size=sdl3.Uint32(len(renderer.vertices) * size_of(Native_Text_Vertex))}
	sdl3.UploadToGPUBuffer(copy_pass, source, destination_region, true)
	sdl3.EndGPUCopyPass(copy_pass)
	return true
}

native_text_render :: proc(renderer: ^Native_Text_Renderer, command: ^sdl3.GPUCommandBuffer, swapchain: ^sdl3.GPUTexture, swap_w, swap_h: sdl3.Uint32) -> bool {
	if len(renderer.draws) == 0 { return true }
	uniforms := Native_Text_Uniforms{
		proj_view = [4][4]f32{
			{2/f32(swap_w), 0, 0, 0},
			{0, -2/f32(swap_h), 0, 0},
			{0, 0, 1, 0},
			{-1, 1, 0, 1},
		},
		model = [4][4]f32{{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}},
	}
	sdl3.PushGPUVertexUniformData(command, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
	target := sdl3.GPUColorTargetInfo{texture=swapchain, clear_color=sdl3.FColor{}, load_op=.LOAD, store_op=.STORE}
	pass := sdl3.BeginGPURenderPass(command, &target, 1, nil)
	if pass == nil { return false }
	sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)
	sdl3.SetGPUViewport(pass, sdl3.GPUViewport{0, 0, f32(swap_w), f32(swap_h), 0, 1})
	vertex_binding := sdl3.GPUBufferBinding{buffer=renderer.vertex_buffer, offset=0}
	sdl3.BindGPUVertexBuffers(pass, 0, &vertex_binding, 1)
	for draw in renderer.draws {
		page := native_text_page(renderer, draw.page_index, draw.is_color)
		if page == nil || page.texture == nil { continue }
		binding := sdl3.GPUTextureSamplerBinding{texture=page.texture, sampler=renderer.sampler}
		sdl3.BindGPUFragmentSamplers(pass, 0, &binding, 1)
		sdl3.DrawGPUPrimitives(pass, 6, 1, draw.first_vertex, 0)
	}
	sdl3.EndGPURenderPass(pass)
	return true
}

native_text_commit_submission :: proc(renderer: ^Native_Text_Renderer) {
	if len(renderer.pending_dirty) > 0 {
		runa.atlas_dirty_ack(&renderer.engine.atlas, renderer.pending_dirty[:])
		clear(&renderer.pending_dirty)
	}
	renderer.vertex_upload_pending = false
}
