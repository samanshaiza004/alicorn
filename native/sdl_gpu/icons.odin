package alicorn_sdl_gpu

import "core:c"
import "core:math"
import alicorn "../../runtime"
import "vendor:sdl3"

NATIVE_ICON_INITIAL_VERTICES :: 4096

Native_Icon_Draw :: struct {
    first_vertex, vertex_count: sdl3.Uint32,
    page: int,
}

// Owns immutable device-local mask textures independently of Runa's text atlas.
// The host's solid renderer owns this renderer's lifetime as its compositor bundle.
Native_Icon_Renderer :: struct {
    device: ^sdl3.GPUDevice,
    runtime: ^alicorn.Runtime,
    pipeline: ^sdl3.GPUGraphicsPipeline,
    sampler: ^sdl3.GPUSampler,
    pages: [len(alicorn.ICON_ATLAS_PAGES)]^sdl3.GPUTexture,
    vertex_buffer: ^sdl3.GPUBuffer,
    vertex_transfer: ^sdl3.GPUTransferBuffer,
    vertices: [dynamic]Native_Text_Vertex,
    vertex_capacity: int,
    draws: [dynamic]Native_Icon_Draw,
    upload_pending, mesh_valid: bool,
    mesh_fingerprint: u64,
    atlas_uploads, atlas_upload_bytes, vertices_uploaded, mesh_rebuilds, mesh_cache_hits: u64,
}

native_icon_fragment_shader :: proc(device: ^sdl3.GPUDevice) -> ^sdl3.GPUShader {
    supported := sdl3.GetGPUShaderFormats(device)
    info := sdl3.GPUShaderCreateInfo{stage=.FRAGMENT, num_samplers=1}
    if native_shader_supported(supported, {.DXIL}) {
        info.format = {.DXIL}; info.code = &GPU_ICON_FRAG_DXIL[0]; info.code_size = uint(len(GPU_ICON_FRAG_DXIL)); info.entrypoint = "PSMain"
    } else if native_shader_supported(supported, {.MSL}) {
        info.format = {.MSL}; info.code = &GPU_ICON_FRAG_MSL[0]; info.code_size = uint(len(GPU_ICON_FRAG_MSL)); info.entrypoint = "PSMain"
    } else if native_shader_supported(supported, {.SPIRV}) {
        info.format = {.SPIRV}; info.code = &GPU_ICON_FRAG_SPV[0]; info.code_size = uint(len(GPU_ICON_FRAG_SPV)); info.entrypoint = "main"
    }
    if info.code == nil { return nil }
    return sdl3.CreateGPUShader(device, info)
}

native_icon_upload_atlases :: proc(renderer: ^Native_Icon_Renderer) -> bool {
    total := 0
    for page in alicorn.ICON_ATLAS_PAGES { total += len(page.pixels) }
    transfer := sdl3.CreateGPUTransferBuffer(renderer.device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=sdl3.Uint32(total)})
    if transfer == nil { return false }
    defer sdl3.ReleaseGPUTransferBuffer(renderer.device, transfer)
    mapped := sdl3.MapGPUTransferBuffer(renderer.device, transfer, false)
    if mapped == nil { return false }
    bytes := cast([^]u8)mapped
    offset := 0
    for page, index in alicorn.ICON_ATLAS_PAGES {
        for value, i in page.pixels { bytes[offset+i] = value }
        offset += len(page.pixels)
    }
    sdl3.UnmapGPUTransferBuffer(renderer.device, transfer)
    for page, index in alicorn.ICON_ATLAS_PAGES {
        renderer.pages[index] = sdl3.CreateGPUTexture(renderer.device, sdl3.GPUTextureCreateInfo{
            type=.D2, format=.R8_UNORM, usage={.SAMPLER}, width=sdl3.Uint32(page.width), height=sdl3.Uint32(page.height),
            layer_count_or_depth=1, num_levels=1, sample_count=._1,
        })
        if renderer.pages[index] == nil { return false }
    }
    command := sdl3.AcquireGPUCommandBuffer(renderer.device)
    if command == nil { return false }
    copy_pass := sdl3.BeginGPUCopyPass(command)
    if copy_pass == nil { _ = sdl3.CancelGPUCommandBuffer(command); return false }
    offset = 0
    for page, index in alicorn.ICON_ATLAS_PAGES {
        // R8 row pitches are multiples of 256; all page offsets are multiples
        // of 512. One staging buffer is filled before any copy references it.
        source := sdl3.GPUTextureTransferInfo{transfer_buffer=transfer, offset=sdl3.Uint32(offset), pixels_per_row=sdl3.Uint32(page.width), rows_per_layer=sdl3.Uint32(page.height)}
        destination := sdl3.GPUTextureRegion{texture=renderer.pages[index], w=sdl3.Uint32(page.width), h=sdl3.Uint32(page.height), d=1}
        sdl3.UploadToGPUTexture(copy_pass, source, destination, false)
        offset += len(page.pixels)
    }
    sdl3.EndGPUCopyPass(copy_pass)
    if !sdl3.SubmitGPUCommandBuffer(command) { return false }
    if !sdl3.WaitForGPUIdle(renderer.device) { return false }
    renderer.atlas_uploads = u64(len(renderer.pages))
    renderer.atlas_upload_bytes = u64(total)
    return true
}

native_icon_destroy :: proc(renderer: ^Native_Icon_Renderer) {
    if renderer.vertex_transfer != nil { sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer) }
    if renderer.vertex_buffer != nil { sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer) }
    for page in renderer.pages { if page != nil { sdl3.ReleaseGPUTexture(renderer.device, page) } }
    if renderer.sampler != nil { sdl3.ReleaseGPUSampler(renderer.device, renderer.sampler) }
    if renderer.pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(renderer.device, renderer.pipeline) }
    delete(renderer.vertices); delete(renderer.draws)
    renderer^ = {}
}

native_icon_make :: proc(device: ^sdl3.GPUDevice, swapchain_format: sdl3.GPUTextureFormat, runtime: ^alicorn.Runtime) -> (renderer: Native_Icon_Renderer, ok: bool) {
	if device == nil { return renderer, false }
	renderer.device = device
	renderer.runtime = runtime
	if !alicorn.icon_atlas_validate() { return renderer, false }
	defer if !ok { native_icon_destroy(&renderer) }
	renderer.vertex_capacity = NATIVE_ICON_INITIAL_VERTICES
	renderer.vertices = make([dynamic]Native_Text_Vertex, 0, 4096)
	renderer.draws = make([dynamic]Native_Icon_Draw, 0, 1024)

	vertex_shader := native_text_shader(device, .VERTEX, false)
	fragment_shader := native_icon_fragment_shader(device)
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
		min_filter=.LINEAR, mag_filter=.LINEAR, mipmap_mode=.NEAREST,
		address_mode_u=.CLAMP_TO_EDGE, address_mode_v=.CLAMP_TO_EDGE, address_mode_w=.CLAMP_TO_EDGE,
		max_lod=1,
	})
	renderer.vertex_buffer = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage=sdl3.GPUBufferUsageFlags{.VERTEX},
		size=sdl3.Uint32(renderer.vertex_capacity * size_of(Native_Text_Vertex)),
	})
	renderer.vertex_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage=.UPLOAD,
		size=sdl3.Uint32(renderer.vertex_capacity * size_of(Native_Text_Vertex)),
	})
	if renderer.sampler == nil || renderer.vertex_buffer == nil || renderer.vertex_transfer == nil {
		return renderer, false
	}
	if !native_icon_upload_atlases(&renderer) { return renderer, false }
	return renderer, true
}

native_icon_ensure_vertex_capacity :: proc(renderer: ^Native_Icon_Renderer, required: int) -> bool {
	maximum := int(sdl3.Uint32(0xFFFFFFFF) / sdl3.Uint32(size_of(Native_Text_Vertex)))
	new_capacity := native_next_vertex_capacity(renderer.vertex_capacity, required, maximum)
	if new_capacity == 0 { return false }
	if new_capacity == renderer.vertex_capacity { return true }
	new_size := sdl3.Uint32(new_capacity * size_of(Native_Text_Vertex))
	new_buffer := sdl3.CreateGPUBuffer(renderer.device, sdl3.GPUBufferCreateInfo{
		usage=sdl3.GPUBufferUsageFlags{.VERTEX}, size=new_size,
	})
	if new_buffer == nil { return false }
	new_transfer := sdl3.CreateGPUTransferBuffer(renderer.device, sdl3.GPUTransferBufferCreateInfo{
		usage=.UPLOAD, size=new_size,
	})
	if new_transfer == nil {
		sdl3.ReleaseGPUBuffer(renderer.device, new_buffer)
		return false
	}
	// These buffers are shared by submissions. Wait before replacing them so
	// earlier frames cannot still be reading the old vertex buffer.
	if !sdl3.WaitForGPUIdle(renderer.device) {
		sdl3.ReleaseGPUTransferBuffer(renderer.device, new_transfer)
		sdl3.ReleaseGPUBuffer(renderer.device, new_buffer)
		return false
	}
	sdl3.ReleaseGPUBuffer(renderer.device, renderer.vertex_buffer)
	sdl3.ReleaseGPUTransferBuffer(renderer.device, renderer.vertex_transfer)
	renderer.vertex_buffer = new_buffer
	renderer.vertex_transfer = new_transfer
	renderer.vertex_capacity = new_capacity
	return true
}

native_icon_upload :: proc(renderer: ^Native_Icon_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if !renderer.upload_pending { return true }
	if len(renderer.vertices) > renderer.vertex_capacity { return false }
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


// Uses the same finalized edge conversion as surfaces, clipping and text.
// Clipping changes UVs, never the raster resource size or the widget geometry.
native_icon_append_quad :: proc(vertices: ^[dynamic]Native_Text_Vertex, draw: alicorn.Paint_Command, scale_x, scale_y: f32, target_w, target_h: sdl3.Uint32) -> (entry: alicorn.Icon_Atlas_Entry, added: bool) {
    icon, ok := draw.payload.(alicorn.Icon_Paint)
    if !ok || scale_x <= 0 || scale_y <= 0 { return }
    bounds := draw.bounds
    bounds.x += draw.translation[0]; bounds.y += draw.translation[1]
    x0, y0, x1, y1 := logical_to_pixel_bounds(bounds, scale_x, scale_y)
    if x1 <= x0 || y1 <= y0 { return }
    entry, ok = alicorn.icon_atlas_lookup(icon.id, max(x1-x0, y1-y0))
    if !ok { return }
    cx0, cy0, cx1, cy1 := logical_to_pixel_bounds(draw.clip, scale_x, scale_y)
    left, top := max(x0, cx0, 0), max(y0, cy0, 0)
    right, bottom := min(x1, cx1, int(target_w)), min(y1, cy1, int(target_h))
    if right <= left || bottom <= top { return }
    page := alicorn.ICON_ATLAS_PAGES[entry.page]
    u0 := (f32(entry.x)+f32(left-x0)*f32(entry.size)/f32(x1-x0))/f32(page.width)
    v0 := (f32(entry.y)+f32(top-y0)*f32(entry.size)/f32(y1-y0))/f32(page.height)
    u1 := (f32(entry.x)+f32(right-x0)*f32(entry.size)/f32(x1-x0))/f32(page.width)
    v1 := (f32(entry.y)+f32(bottom-y0)*f32(entry.size)/f32(y1-y0))/f32(page.height)
    color := [4]f32{icon.color.r, icon.color.g, icon.color.b, icon.color.a*draw.opacity}
    a := Native_Text_Vertex{{f32(left), f32(top), 0}, color, {u0,v0}}
    b := Native_Text_Vertex{{f32(right), f32(top), 0}, color, {u1,v0}}
    c := Native_Text_Vertex{{f32(right), f32(bottom), 0}, color, {u1,v1}}
    d := Native_Text_Vertex{{f32(left), f32(bottom), 0}, color, {u0,v1}}
    append(vertices, a,b,c,a,c,d)
    return entry, true
}

native_icon_mesh_fingerprint :: proc(display: []alicorn.Paint_Command, scale_x, scale_y: f32, target_w, target_h: sdl3.Uint32) -> u64 {
    h := native_text_hash_mix(1469598103934665603, u64(len(display)))
    h = native_text_hash_mix(h, u64(transmute(u32)scale_x)); h = native_text_hash_mix(h, u64(transmute(u32)scale_y))
    h = native_text_hash_mix(h, u64(target_w)); h = native_text_hash_mix(h, u64(target_h))
    for draw, index in display {
        icon, ok := draw.payload.(alicorn.Icon_Paint)
        if !ok { continue }
        h = native_text_hash_mix(h, u64(index)); h = native_text_hash_mix(h, u64(icon.id))
        h = native_text_hash_rect(h, draw.bounds); h = native_text_hash_rect(h, draw.clip)
        h = native_text_hash_color(h, icon.color)
        h = native_text_hash_mix(h, u64(transmute(u32)draw.opacity))
        for axis in draw.translation { h = native_text_hash_mix(h, u64(transmute(u32)axis)) }
    }
    return h
}

native_icon_build :: proc(renderer: ^Native_Icon_Renderer, display: []alicorn.Paint_Command, scale_x, scale_y: f32, target_w, target_h: sdl3.Uint32) -> bool {
    fingerprint := native_icon_mesh_fingerprint(display, scale_x, scale_y, target_w, target_h)
    if renderer.mesh_valid && fingerprint == renderer.mesh_fingerprint { renderer.mesh_cache_hits += 1; return true }
    clear(&renderer.vertices); clear(&renderer.draws)
    for draw in display { append(&renderer.draws, Native_Icon_Draw{}) }
    required := 0
    for draw in display { if alicorn.paint_command_is_icon(draw) { required += 6 } }
    if !native_icon_ensure_vertex_capacity(renderer, required) { return false }
    for draw, index in display {
        if !alicorn.paint_command_is_icon(draw) { continue }
        first := sdl3.Uint32(len(renderer.vertices))
        entry, added := native_icon_append_quad(&renderer.vertices, draw, scale_x, scale_y, target_w, target_h)
        if added { renderer.draws[index] = Native_Icon_Draw{first, 6, entry.page} }
    }
    renderer.mesh_valid = true; renderer.mesh_fingerprint = fingerprint
    renderer.upload_pending = len(renderer.vertices) > 0
    renderer.mesh_rebuilds += 1
    return true
}

native_icon_render_batch :: proc(renderer: ^Native_Icon_Renderer, command: ^sdl3.GPUCommandBuffer, target: ^sdl3.GPUTexture, target_w, target_h: sdl3.Uint32, draws: []Native_Icon_Draw) -> bool {
    has_draw := false
    for draw in draws { if draw.vertex_count > 0 { has_draw = true; break } }
    if !has_draw { return true }
    uniforms := Native_Text_Uniforms{
        proj_view=[4][4]f32{{2/f32(target_w),0,0,0},{0,-2/f32(target_h),0,0},{0,0,1,0},{-1,1,0,1}},
        model=[4][4]f32{{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}},
    }
    sdl3.PushGPUVertexUniformData(command, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
    target_info := sdl3.GPUColorTargetInfo{texture=target, load_op=.LOAD, store_op=.STORE}
    pass := sdl3.BeginGPURenderPass(command, &target_info, 1, nil)
    if pass == nil { return false }
    sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)
    sdl3.SetGPUViewport(pass, sdl3.GPUViewport{0,0,f32(target_w),f32(target_h),0,1})
    binding := sdl3.GPUBufferBinding{buffer=renderer.vertex_buffer}
    sdl3.BindGPUVertexBuffers(pass, 0, &binding, 1)
    previous_page := -1
    for draw in draws {
        if draw.vertex_count == 0 { continue }
        if draw.page != previous_page {
            sampler := sdl3.GPUTextureSamplerBinding{texture=renderer.pages[draw.page], sampler=renderer.sampler}
            sdl3.BindGPUFragmentSamplers(pass, 0, &sampler, 1)
            previous_page = draw.page
        }
        sdl3.DrawGPUPrimitives(pass, draw.vertex_count, 1, draw.first_vertex, 0)
    }
    sdl3.EndGPURenderPass(pass)
    return true
}
