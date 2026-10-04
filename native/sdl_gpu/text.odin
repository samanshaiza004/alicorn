package alicorn_sdl_gpu

import "core:c"
import "core:math"
import "core:time"
import alicorn "../../runtime"
import runa "../../third_party/Runa"
import "vendor:sdl3"

NATIVE_TEXT_INITIAL_VERTICES :: 65536
NATIVE_TEXT_SUBPIXEL_BUCKETS :: 4

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
	node:         alicorn.Node_ID,
	page_index:   u16,
	is_color:     bool,
}

Native_Text_Renderer :: struct {
	device:         ^sdl3.GPUDevice,
	swapchain_format: sdl3.GPUTextureFormat,
	pipeline:       ^sdl3.GPUGraphicsPipeline,
	sampler:        ^sdl3.GPUSampler,
	atlas_transfer: ^sdl3.GPUTransferBuffer,
	vertex_buffer:  ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	runtime:        ^alicorn.Runtime,
	pages:          [dynamic]Native_Atlas_Page,
	vertices:       [dynamic]Native_Text_Vertex,
	vertex_capacity: int,
	draws:          [dynamic]Native_Text_Draw,
	pending_dirty:  [dynamic]runa.Atlas_Dirty_View,
	mesh_valid:     bool,
	vertex_upload_pending: bool,
	last_scale_x:   f32,
	last_scale_y:   f32,
	mesh_fingerprint: u64,
	fingerprint_ns:   u64,
	fingerprint_bytes: u64,
	mesh_rebuild_ns:  u64,
	atlas_uploads: u64,
	atlas_upload_bytes: u64,
	mesh_rebuilds: u64,
	mesh_cache_hits: u64,
	mesh_text_commands: u64,
	vertex_uploads: u64,
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

native_text_make :: proc(device: ^sdl3.GPUDevice, swapchain_format: sdl3.GPUTextureFormat, runtime: ^alicorn.Runtime) -> (renderer: Native_Text_Renderer, ok: bool) {
	renderer.device = device
	renderer.swapchain_format = swapchain_format
	renderer.runtime = runtime
	renderer.pages = make([dynamic]Native_Atlas_Page, 0, 4)
	renderer.vertices = make([dynamic]Native_Text_Vertex, 0, 4096)
	renderer.draws = make([dynamic]Native_Text_Draw, 0, 512)
	renderer.pending_dirty = make([dynamic]runa.Atlas_Dirty_View, 0, 4)

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
	renderer.vertex_capacity = NATIVE_TEXT_INITIAL_VERTICES
	initial_vertex_bytes := sdl3.Uint32(renderer.vertex_capacity * size_of(Native_Text_Vertex))
	renderer.vertex_buffer = sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{usage=sdl3.GPUBufferUsageFlags{.VERTEX}, size=initial_vertex_bytes})
	renderer.vertex_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=initial_vertex_bytes})
	renderer.atlas_transfer = sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=4 * 1024 * 1024})
	if renderer.sampler == nil || renderer.vertex_buffer == nil || renderer.vertex_transfer == nil || renderer.atlas_transfer == nil {
		return renderer, false
	}
	ok = true
	return
}

native_text_destroy :: proc(renderer: ^Native_Text_Renderer) {
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
	renderer^ = {}
}

native_text_is_text :: proc(kind: alicorn.Node_Kind) -> bool {
	return kind == .Text || kind == .Text_Field || kind == .Text_Composition || kind == .Tooltip_Text
}

native_text_hash_mix :: proc(h, value: u64) -> u64 {
	result := h ~ value
	result *= 1099511628211
	return result
}

native_text_hash_string :: proc(value: string) -> u64 {
	h: u64 = 1469598103934665603
	for i := 0; i < len(value); i += 1 {
		h = native_text_hash_mix(h, u64(value[i]))
	}
	return h
}

native_text_hash_rect :: proc(h: u64, rect: alicorn.Rect) -> u64 {
	result := h
	result = native_text_hash_mix(result, u64(transmute(u32)rect.x))
	result = native_text_hash_mix(result, u64(transmute(u32)rect.y))
	result = native_text_hash_mix(result, u64(transmute(u32)rect.w))
	result = native_text_hash_mix(result, u64(transmute(u32)rect.h))
	return result
}

native_text_hash_color :: proc(h: u64, color: alicorn.Color) -> u64 {
	result := h
	result = native_text_hash_mix(result, u64(transmute(u32)color.r))
	result = native_text_hash_mix(result, u64(transmute(u32)color.g))
	result = native_text_hash_mix(result, u64(transmute(u32)color.b))
	result = native_text_hash_mix(result, u64(transmute(u32)color.a))
	return result
}

native_text_hash_spans :: proc(h: u64, spans: []alicorn.Text_Paint_Span) -> u64 {
	color_count: u64 = 0
	for span in spans { if span.color_set { color_count += 1 } }
	result := native_text_hash_mix(h, color_count)
	for span in spans {
		if !span.color_set { continue }
		result = native_text_hash_mix(result, u64(span.start))
		result = native_text_hash_mix(result, u64(span.end))
		result = native_text_hash_color(result, span.color)
	}
	return result
}

Native_Text_Span_Strategy :: enum {
	None,
	Single,
	Sorted_Non_Overlapping,
	Segment_Tree,
}

// Most syntax projections are a sorted, non-overlapping list. Keep those out
// of the byte-sized winner map below; the painter can resolve their colors
// directly from shaped cluster ranges. Preserve the span-array ordering as
// the precedence rule for every overlapping/unsorted case.
native_text_span_strategy :: proc(text_length: int, spans: []alicorn.Text_Paint_Span) -> (strategy: Native_Text_Span_Strategy, single_index: int, starts_sorted: bool) {
	color_count := 0
	previous_color_start := -1
	previous_color_end := -1
	color_spans_sorted := true
	previous_start := -1
	starts_sorted = true
	single_index = -1
	for span, index in spans {
		start := clamp(span.start, 0, text_length)
		end := clamp(span.end, 0, text_length)
		if start < previous_start { starts_sorted = false }
		previous_start = start
		if !span.color_set || start >= end { continue }
		if start < previous_color_start || start < previous_color_end { color_spans_sorted = false }
		previous_color_start = start
		previous_color_end = max(previous_color_end, end)
		color_count += 1
		single_index = index
	}
	if color_count == 0 { return .None, -1, starts_sorted }
	if color_count == 1 { return .Single, single_index, starts_sorted }
	if color_spans_sorted { return .Sorted_Non_Overlapping, -1, starts_sorted }
	return .Segment_Tree, -1, starts_sorted
}

// Produce the last matching span index for each UTF-8 byte. This allocation-
// heavy path is reserved for genuinely overlapping or unsorted spans; a
// max-index segment tree preserves last-span-wins semantics in that case.
native_text_span_winners :: proc(text: string, spans: []alicorn.Text_Paint_Span, scratch_allocator := context.temp_allocator) -> []int {
	if len(text) == 0 || len(spans) == 0 { return nil }
	has_color := false
	for span in spans { if span.color_set { has_color = true; break } }
	if !has_color { return nil }
	byte_count := len(text)
	start_head := make([]int, byte_count+1, allocator=scratch_allocator)
	end_head := make([]int, byte_count+1, allocator=scratch_allocator)
	start_next := make([]int, len(spans), allocator=scratch_allocator)
	end_next := make([]int, len(spans), allocator=scratch_allocator)
	for i in 0..=byte_count { start_head[i], end_head[i] = -1, -1 }
	for i in 0..<len(spans) {
		start_next[i], end_next[i] = -1, -1
		start := clamp(spans[i].start, 0, byte_count)
		end := clamp(spans[i].end, 0, byte_count)
		if !spans[i].color_set || start >= end { continue }
		start_next[i] = start_head[start]
		start_head[start] = i
		end_next[i] = end_head[end]
		end_head[end] = i
	}
	leaf_count := 1
	for leaf_count < len(spans) { leaf_count *= 2 }
	tree := make([]int, leaf_count*2, allocator=scratch_allocator)
	for i in 0..<len(tree) { tree[i] = -1 }
	winners := make([]int, byte_count, allocator=scratch_allocator)
	for byte in 0..<byte_count {
		for index := end_head[byte]; index >= 0; index = end_next[index] {
			pos := leaf_count + index
			tree[pos] = -1
			for pos /= 2; pos > 0; pos /= 2 { tree[pos] = max(tree[pos*2], tree[pos*2+1]) }
		}
		for index := start_head[byte]; index >= 0; index = start_next[index] {
			pos := leaf_count + index
			tree[pos] = index
			for pos /= 2; pos > 0; pos /= 2 { tree[pos] = max(tree[pos*2], tree[pos*2+1]) }
		}
		winners[byte] = tree[1]
	}
	delete(start_head, scratch_allocator)
	delete(end_head, scratch_allocator)
	delete(start_next, scratch_allocator)
	delete(end_next, scratch_allocator)
	delete(tree, scratch_allocator)
	return winners
}

native_text_color_for_cluster :: proc(spans: []alicorn.Text_Paint_Span, winners: []int, cluster_start, cluster_end: int, fallback: alicorn.Color) -> alicorn.Color {
	winning_index := -1
	start := clamp(cluster_start, 0, len(winners))
	end := clamp(cluster_end, 0, len(winners))
	for byte in start..<end { winning_index = max(winning_index, winners[byte]) }
	if winning_index >= 0 && winning_index < len(spans) && spans[winning_index].color_set { return spans[winning_index].color }
	return fallback
}

native_text_color_for_single_span :: proc(text_length: int, spans: []alicorn.Text_Paint_Span, span_index: int, cluster_start, cluster_end: int, fallback: alicorn.Color) -> alicorn.Color {
	if span_index < 0 || span_index >= len(spans) { return fallback }
	span := spans[span_index]
	if !span.color_set { return fallback }
	start := clamp(cluster_start, 0, text_length)
	end := clamp(cluster_end, 0, text_length)
	span_start := clamp(span.start, 0, text_length)
	span_end := clamp(span.end, 0, text_length)
	if start < span_end && span_start < end { return span.color }
	return fallback
}

// Resolve an ordered source cluster against sorted, disjoint spans. The cursor
// only moves forward when shaped clusters are also source-ordered; bidi runs
// that violate that condition use the general winner map instead.
native_text_color_for_sorted_cluster :: proc(
	text_length: int,
	spans: []alicorn.Text_Paint_Span,
	cursor: ^int,
	cluster_start, cluster_end: int,
	fallback: alicorn.Color,
) -> alicorn.Color {
	start := clamp(cluster_start, 0, text_length)
	end := clamp(cluster_end, 0, text_length)
	if start >= end { return fallback }
	for cursor^ < len(spans) {
		span := spans[cursor^]
		span_start := clamp(span.start, 0, text_length)
		span_end := clamp(span.end, 0, text_length)
		if !span.color_set || span_start >= span_end || span_end <= start {
			cursor^ += 1
			continue
		}
		break
	}
	winner := -1
	for index := cursor^; index < len(spans); index += 1 {
		span := spans[index]
		if !span.color_set { continue }
		span_start := clamp(span.start, 0, text_length)
		span_end := clamp(span.end, 0, text_length)
		if span_start >= end { break }
		if span_start < span_end && span_end > start { winner = index }
	}
	if winner >= 0 { return spans[winner].color }
	return fallback
}

// A visual bidi run may visit source clusters out of order. Sorted disjoint
// spans still need no byte-winner array in that case: binary-search the span
// start, then inspect only ranges that can intersect this cluster.
native_text_color_for_sorted_cluster_binary :: proc(
	text_length: int,
	spans: []alicorn.Text_Paint_Span,
	cluster_start, cluster_end: int,
	fallback: alicorn.Color,
) -> alicorn.Color {
	start := clamp(cluster_start, 0, text_length)
	end := clamp(cluster_end, 0, text_length)
	if start >= end { return fallback }
	low, high := 0, len(spans)
	for low < high {
		mid := low + (high-low)/2
		span_start := clamp(spans[mid].start, 0, text_length)
		if span_start < start { low = mid + 1 } else { high = mid }
	}
	first := low
	for first > 0 {
		first -= 1
		if spans[first].color_set { break }
	}
	winner := -1
	for index := first; index < len(spans); index += 1 {
		span := spans[index]
		span_start := clamp(span.start, 0, text_length)
		if span_start >= end { break }
		span_end := clamp(span.end, 0, text_length)
		if span.color_set && span_start < span_end && span_end > start { winner = index }
	}
	if winner >= 0 { return spans[winner].color }
	return fallback
}

native_text_glyph_clusters_are_ordered :: proc(glyphs: []alicorn.Text_Glyph) -> bool {
	previous_start := -1
	previous_end := -1
	for glyph in glyphs {
		if glyph.cluster_start < previous_start || glyph.cluster_end < previous_end { return false }
		previous_start = glyph.cluster_start
		previous_end = glyph.cluster_end
	}
	return true
}

// Runa's mono rasterizer stores the fractional X phase in four quarter-pixel
// variants. Keep the sampled quad origin on an integer physical pixel so the
// phase is supplied by the bitmap rather than by fractional texture
// placement. Rounding to the nearest quarter keeps the positional error below
// 1/8 physical pixel; a rounded fourth bucket carries into the next pixel.
native_text_snap_x :: proc(physical_x: f32) -> (pixel_x: f32, subpixel_bucket: u8) {
	pixel_x = math.floor(physical_x)
	phase := physical_x - pixel_x
	bucket := int(math.floor(phase * f32(NATIVE_TEXT_SUBPIXEL_BUCKETS) + 0.5))
	if bucket >= NATIVE_TEXT_SUBPIXEL_BUCKETS {
		pixel_x += 1
		bucket = 0
	}
	return pixel_x, u8(bucket)
}

native_text_snap_y :: proc(physical_y: f32) -> f32 {
	return math.floor(physical_y + 0.5)
}

native_text_ensure_vertex_capacity :: proc(renderer: ^Native_Text_Renderer, required: int) -> bool {
	maximum := int(sdl3.Uint32(0xFFFFFFFF) / sdl3.Uint32(size_of(Native_Text_Vertex)))
	new_capacity := native_next_vertex_capacity(renderer.vertex_capacity, required, maximum)
	if new_capacity == 0 { return false }
	if new_capacity == renderer.vertex_capacity { return true }
	new_size := sdl3.Uint32(new_capacity * size_of(Native_Text_Vertex))
	new_buffer := sdl3.CreateGPUBuffer(renderer.device, sdl3.GPUBufferCreateInfo{usage=sdl3.GPUBufferUsageFlags{.VERTEX}, size=new_size})
	if new_buffer == nil { return false }
	new_transfer := sdl3.CreateGPUTransferBuffer(renderer.device, sdl3.GPUTransferBufferCreateInfo{usage=.UPLOAD, size=new_size})
	if new_transfer == nil {
		sdl3.ReleaseGPUBuffer(renderer.device, new_buffer)
		return false
	}
	// Replacing the shared buffers is rare. Retire prior submissions before
	// releasing them so the current larger mesh cannot race an in-flight draw.
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

native_text_quad_visible :: proc(x0, y0, x1, y1: f32, clip: alicorn.Rect, scale_x, scale_y: f32) -> bool {
	if clip.w <= 0 || clip.h <= 0 || x1 <= x0 || y1 <= y0 { return false }
	clip_x0, clip_y0 := clip.x * scale_x, clip.y * scale_y
	clip_x1, clip_y1 := (clip.x + clip.w) * scale_x, (clip.y + clip.h) * scale_y
	return x0 < clip_x1 && x1 > clip_x0 && y0 < clip_y1 && y1 > clip_y0
}

native_text_rects_intersect :: proc(a, b: alicorn.Rect) -> bool {
	if a.w <= 0 || a.h <= 0 || b.w <= 0 || b.h <= 0 { return false }
	return a.x < b.x+b.w && a.x+a.w > b.x && a.y < b.y+b.h && a.y+a.h > b.y
}

native_text_command_intersects_clip :: proc(command: alicorn.Display_Command) -> bool {
	// Drag-preview text is translated at draw time. Its mesh-space bounds do
	// not describe the final clip-space location, so leave it to exact culling.
	if command.node == alicorn.Node_ID(0) && command.kind != .Tooltip_Text { return true }
	return native_text_rects_intersect(command.bounds, command.clip)
}

// This is a deliberately broad logical bound, not a substitute for the exact
// raster-bounds clip test below. The em-sized margin admits bearings, accents,
// italic overhang, combining marks, and zero-advance glyphs while still
// excluding glyphs far outside a long line's viewport before atlas lookup.
native_text_glyph_may_intersect_clip :: proc(
	glyph: alicorn.Text_Glyph,
	run_size: f32,
	command: alicorn.Display_Command,
	scale_x, scale_y: f32,
) -> bool {
	// The drag preview receives a host-side model translation after mesh build.
	// Do not apply an untransformed logical bound that could drop its glyphs.
	if command.node == alicorn.Node_ID(0) && command.kind != .Tooltip_Text { return true }
	if command.clip.w <= 0 || command.clip.h <= 0 { return false }
	clip_xa := command.clip.x * scale_x
	clip_ya := command.clip.y * scale_y
	clip_xb := (command.clip.x + command.clip.w) * scale_x
	clip_yb := (command.clip.y + command.clip.h) * scale_y
	clip_x0, clip_x1 := min(clip_xa, clip_xb), max(clip_xa, clip_xb)
	clip_y0, clip_y1 := min(clip_ya, clip_yb), max(clip_ya, clip_yb)
	run_size_abs := run_size
	if run_size_abs < 0 { run_size_abs = -run_size_abs }
	scale_x_abs, scale_y_abs := scale_x, scale_y
	if scale_x_abs < 0 { scale_x_abs = -scale_x_abs }
	if scale_y_abs < 0 { scale_y_abs = -scale_y_abs }
	margin_x := max(run_size_abs * scale_x_abs, 1)
	margin_y := max(run_size_abs * scale_y_abs, 1)
	glyph_xa := (command.bounds.x + glyph.x) * scale_x
	glyph_xb := (command.bounds.x + glyph.x + glyph.x_advance) * scale_x
	glyph_ya := (command.bounds.y + glyph.y) * scale_y
	glyph_yb := (command.bounds.y + glyph.y + glyph.y_advance) * scale_y
	x0 := min(glyph_xa, glyph_xb) - margin_x
	x1 := max(glyph_xa, glyph_xb) + margin_x
	y0 := min(glyph_ya, glyph_yb) - margin_y
	y1 := max(glyph_ya, glyph_yb) + margin_y
	return x0 < clip_x1 && x1 > clip_x0 && y0 < clip_y1 && y1 > clip_y0
}

native_text_command_run :: proc(renderer: ^Native_Text_Renderer, command: alicorn.Display_Command) -> (run: alicorn.Text_Run, ok: bool) {
	if command.node == alicorn.Node_ID(0) {
		if command.kind == .Tooltip_Text {
			if !renderer.runtime.tooltip.run_ready { return }
			return renderer.runtime.tooltip.run, true
		}
		if !renderer.runtime.drag_preview.ready { return }
		return renderer.runtime.drag_preview.run, true
	}
	node, found := renderer.runtime.nodes[command.node]
	if !found { return }
	if command.kind == .Text_Composition {
		if !node.composition_run_valid { return }
		return node.composition_run, true
	}
	if !node.text_run_valid { return }
	return node.text_run, true
}

native_text_reserve_shaped_vertices :: proc(
	renderer: ^Native_Text_Renderer,
	display: []alicorn.Display_Command,
	scale_x, scale_y: f32,
) {
	visible_glyphs := 0
	for command in display {
		if !native_text_is_text(command.kind) || !native_text_command_intersects_clip(command) { continue }
		run, ok := native_text_command_run(renderer, command)
		if !ok { continue }
		for glyph in run.glyphs {
			if glyph.control_advance || !native_text_glyph_may_intersect_clip(glyph, run.size, command, scale_x, scale_y) { continue }
			visible_glyphs += 1
		}
	}
	maximum_vertices := int(sdl3.Uint32(0xFFFFFFFF) / sdl3.Uint32(size_of(Native_Text_Vertex)))
	// If the estimate exceeds what the GPU buffer size can represent, let the
	// existing incremental capacity checks fail safely; don't reserve a
	// theoretical maximum-sized CPU mesh for an already-unrenderable demand.
	if visible_glyphs <= maximum_vertices/6 {
		required_vertices := visible_glyphs * 6
		if required_vertices > cap(renderer.vertices) {
			reserve(&renderer.vertices, required_vertices)
		}
	}
}

// The mesh fingerprint includes only the ordered display state that can affect
// text pixels. Solid and surface commands are intentionally excluded: their
// changes must not invalidate the retained text vertex mesh.
native_text_mesh_fingerprint :: proc(display: []alicorn.Display_Command, scale_x, scale_y: f32) -> (fingerprint: u64, bytes_hashed: u64) {
	h: u64 = 1469598103934665603
	bytes_hashed = 0
	h = native_text_hash_mix(h, u64(transmute(u32)scale_x))
	h = native_text_hash_mix(h, u64(transmute(u32)scale_y))
	text_index: u64 = 0
	for command in display {
		if !native_text_is_text(command.kind) { continue }
		bytes_hashed += u64(len(command.text))
		// Span hashing makes one count pass and one content pass.
		bytes_hashed += u64(len(command.text_paint_spans) * size_of(alicorn.Text_Paint_Span) * 2)
		h = native_text_hash_mix(h, text_index)
		text_index += 1
		h = native_text_hash_mix(h, u64(command.node))
		h = native_text_hash_mix(h, u64(command.kind))
		h = native_text_hash_rect(h, command.bounds)
		h = native_text_hash_rect(h, command.clip)
		h = native_text_hash_color(h, command.color)
		h = native_text_hash_mix(h, native_text_hash_string(command.text))
		h = native_text_hash_spans(h, command.text_paint_spans)
	}
	h = native_text_hash_mix(h, text_index)
	return h, bytes_hashed
}

native_text_rebuild_mesh :: proc(renderer: ^Native_Text_Renderer, display: []alicorn.Display_Command, scale_x, scale_y: f32, scratch_allocator := context.temp_allocator) -> bool {
	fingerprint_start := time.now()
	fingerprint, fingerprint_bytes := native_text_mesh_fingerprint(display, scale_x, scale_y)
	text_command_count: u64 = 0
	for command in display {
		if !native_text_is_text(command.kind) { continue }
		text_command_count += 1
		fingerprint = native_text_hash_mix(
			fingerprint,
		u64(transmute(u32)alicorn.drag_source_opacity(renderer.runtime, command.node)),
		)
		if command.node == alicorn.Node_ID(0) {
			if command.kind == .Tooltip_Text && renderer.runtime.tooltip.run_ready {
				run := &renderer.runtime.tooltip.run
				fingerprint = native_text_hash_mix(fingerprint, u64(run.font))
				fingerprint = native_text_hash_mix(fingerprint, u64(run.font_source))
				fingerprint = native_text_hash_mix(fingerprint, u64(transmute(u32)run.size))
				fingerprint = native_text_hash_mix(fingerprint, u64(transmute(u32)run.font_weight))
				fingerprint = native_text_hash_mix(fingerprint, run.style_hash)
			} else if renderer.runtime.drag_preview.ready {
				run := &renderer.runtime.drag_preview.run
				fingerprint = native_text_hash_mix(fingerprint, u64(run.font))
				fingerprint = native_text_hash_mix(fingerprint, u64(run.font_source))
				fingerprint = native_text_hash_mix(fingerprint, u64(transmute(u32)run.size))
				fingerprint = native_text_hash_mix(fingerprint, u64(transmute(u32)run.font_weight))
				fingerprint = native_text_hash_mix(fingerprint, run.style_hash)
			}
		} else if node, found := renderer.runtime.nodes[command.node]; found {
			generation := node.text_run_generation
			if command.kind == .Text_Composition { generation = node.composition_run_generation }
			fingerprint = native_text_hash_mix(fingerprint, generation)
		}
	}
	// Font replacement can preserve every display-command field while changing
	// the retained run's atlas slots. Include the runtime text generation so a
	// same-string font swap cannot leave old vertices resident.
	fingerprint = native_text_hash_mix(fingerprint, renderer.runtime.text_engine.font_generation)
	renderer.fingerprint_ns += u64(time.duration_nanoseconds(time.since(fingerprint_start)))
	renderer.fingerprint_bytes += fingerprint_bytes
	renderer.mesh_text_commands = text_command_count
	if renderer.mesh_valid && renderer.mesh_fingerprint == fingerprint {
		renderer.mesh_cache_hits += 1
		return true
	}
	renderer.mesh_rebuilds += 1
	mesh_rebuild_start := time.now()
	// The old mesh is no longer available once its arrays are cleared. If a
	// capacity/allocation failure interrupts this rebuild, do not let a later
	// frame reuse the old fingerprint with this partial data.
	renderer.mesh_valid = false
	clear(&renderer.vertices)
	clear(&renderer.draws)
	// Reserve once from the shaped glyphs that can plausibly reach a text
	// command's clip; don't couple CPU allocation to maximum GPU capacity.
	native_text_reserve_shaped_vertices(renderer, display, scale_x, scale_y)
	for command in display {
		if !native_text_is_text(command.kind) || !native_text_command_intersects_clip(command) { continue }
		run, run_ok := native_text_command_run(renderer, command)
		if !run_ok { continue }
		span_strategy, single_span_index, starts_sorted := native_text_span_strategy(len(command.text), command.text_paint_spans)
		clusters_ordered := native_text_glyph_clusters_are_ordered(run.glyphs[:])
		winners: []int
		if span_strategy == .Segment_Tree || (span_strategy == .Sorted_Non_Overlapping && !clusters_ordered && !starts_sorted) {
			winners = native_text_span_winners(command.text, command.text_paint_spans, scratch_allocator)
		}
		span_cursor := 0
		for glyph in run.glyphs {
			// Tabs and unsupported controls retain logical advance/caret geometry
			// but must never reach the atlas or produce fallback glyphs.
			if glyph.control_advance { continue }
			// Avoid atlas lookup/rasterization for glyphs well outside the clip.
			// Bitmap bearings and overhang still get the exact check after lookup.
			if !native_text_glyph_may_intersect_clip(glyph, run.size, command, scale_x, scale_y) { continue }
			// Text_Run stores logical geometry only. Resolve the physical glyph
			// resource at the current raster scale so moving a window to a Retina
			// display does not stretch a low-resolution atlas slot. The raster
			// phase is retained in the atlas variant while the quad origin is
			// snapped to physical pixels for stable texture sampling.
			raster_size := run.size * scale_y
			physical_x := (command.bounds.x + glyph.x) * scale_x
			physical_y := (command.bounds.y + glyph.y) * scale_y
			snapped_x, subpixel_bucket := native_text_snap_x(physical_x)
			snapped_y := native_text_snap_y(physical_y)
			slot, drawable, glyph_ok := alicorn.text_engine_glyph(&renderer.runtime.text_engine, glyph.glyph_id, raster_size, subpixel_bucket, scratch_allocator=scratch_allocator, font_role=run.font, font_source=run.font_source, font_weight=glyph.font_weight, italic=glyph.italic)
			if !glyph_ok || !drawable { continue }
			slot_view := runa.atlas_slot_view(slot)
			x0 := snapped_x + slot_view.Bearing[0]
			y0 := snapped_y + slot_view.Bearing[1]
			x1 := x0 + f32(slot_view.Px_Size[0])
			y1 := y0 + f32(slot_view.Px_Size[1])
			if !native_text_quad_visible(x0, y0, x1, y1, command.clip, scale_x, scale_y) { continue }
			if len(renderer.vertices) + 6 > renderer.vertex_capacity && !native_text_ensure_vertex_capacity(renderer, len(renderer.vertices) + 6) {
				if len(winners) > 0 { delete(winners, scratch_allocator) }
				renderer.mesh_rebuild_ns += u64(time.duration_nanoseconds(time.since(mesh_rebuild_start)))
				return false
			}
			u0, v0, u1, v1 := slot_view.UV_Rect[0], slot_view.UV_Rect[1], slot_view.UV_Rect[2], slot_view.UV_Rect[3]
			glyph_color := command.color
			if span_strategy == .Single {
				glyph_color = native_text_color_for_single_span(len(command.text), command.text_paint_spans, single_span_index, glyph.cluster_start, glyph.cluster_end, command.color)
			} else if span_strategy == .Sorted_Non_Overlapping {
				if clusters_ordered {
					glyph_color = native_text_color_for_sorted_cluster(len(command.text), command.text_paint_spans, &span_cursor, glyph.cluster_start, glyph.cluster_end, command.color)
				} else if starts_sorted {
					glyph_color = native_text_color_for_sorted_cluster_binary(len(command.text), command.text_paint_spans, glyph.cluster_start, glyph.cluster_end, command.color)
				} else {
					glyph_color = native_text_color_for_cluster(command.text_paint_spans, winners, glyph.cluster_start, glyph.cluster_end, command.color)
				}
			} else if span_strategy == .Segment_Tree {
				glyph_color = native_text_color_for_cluster(command.text_paint_spans, winners, glyph.cluster_start, glyph.cluster_end, command.color)
			}
			glyph_color.a *= alicorn.drag_source_opacity(renderer.runtime, command.node)
			color := [4]f32{glyph_color.r, glyph_color.g, glyph_color.b, glyph_color.a}
			first := sdl3.Uint32(len(renderer.vertices))
			append(&renderer.vertices,
				Native_Text_Vertex{[3]f32{x0, y0, 0}, color, [2]f32{u0, v0}},
				Native_Text_Vertex{[3]f32{x1, y0, 0}, color, [2]f32{u1, v0}},
				Native_Text_Vertex{[3]f32{x1, y1, 0}, color, [2]f32{u1, v1}},
				Native_Text_Vertex{[3]f32{x0, y0, 0}, color, [2]f32{u0, v0}},
				Native_Text_Vertex{[3]f32{x1, y1, 0}, color, [2]f32{u1, v1}},
				Native_Text_Vertex{[3]f32{x0, y1, 0}, color, [2]f32{u0, v1}},
			)
			append(&renderer.draws, Native_Text_Draw{first, command.node, slot_view.Page_Index, slot_view.Is_Color})
		}
		if len(winners) > 0 { delete(winners, scratch_allocator) }
	}
	renderer.last_scale_x = scale_x
	renderer.last_scale_y = scale_y
	renderer.mesh_fingerprint = fingerprint
	renderer.mesh_valid = true
	renderer.vertex_upload_pending = len(renderer.vertices) > 0
	renderer.mesh_rebuild_ns += u64(time.duration_nanoseconds(time.since(mesh_rebuild_start)))
	return true
}

native_text_sync_atlas :: proc(renderer: ^Native_Text_Renderer, command: ^sdl3.GPUCommandBuffer, scratch_allocator := context.temp_allocator) -> bool {
	snapshot := runa.atlas_dirty_snapshot(&renderer.runtime.text_engine.atlas, scratch_allocator)
	if len(snapshot) == 0 { return true }
	for dirty in snapshot {
		view, ok := runa.atlas_page_view(&renderer.runtime.text_engine.atlas, dirty.Page_Index, dirty.Is_Color)
		if !ok { delete(snapshot, scratch_allocator); return false }
		page := native_text_page(renderer, dirty.Page_Index, dirty.Is_Color)
		if page == nil {
			texture := sdl3.CreateGPUTexture(renderer.device, sdl3.GPUTextureCreateInfo{
				type=.D2, format=.R8G8B8A8_UNORM, usage=sdl3.GPUTextureUsageFlags{.SAMPLER},
				width=sdl3.Uint32(view.Width), height=sdl3.Uint32(view.Height), layer_count_or_depth=1, num_levels=1, sample_count=._1,
			})
			if texture == nil { delete(snapshot, scratch_allocator); return false }
			append(&renderer.pages, Native_Atlas_Page{dirty.Page_Index, dirty.Is_Color, view.Width, view.Height, texture})
			page = &renderer.pages[len(renderer.pages)-1]
		}
		// The atlas texture is cycled because earlier submissions may still
		// sample it. SDL cycles the complete texture, not only the destination
		// rectangle, so the safe first implementation rewrites the complete
		// page whenever any glyph makes it dirty.
		upload_width := int(view.Width)
		upload_height := int(view.Height)
		upload_bytes := upload_width * upload_height * 4
		mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.atlas_transfer, true)
		if mapped == nil || upload_bytes > 4*1024*1024 { delete(snapshot, scratch_allocator); return false }
		destination := cast([^]u8)mapped
		for y in 0..<upload_height {
			src_row := y * upload_width
			for x in 0..<upload_width {
				src := view.Pixels[src_row + x]
				dst := (y * upload_width + x) * 4
				if dirty.Is_Color {
					src4 := (src_row + x) * 4
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
		if copy_pass == nil { delete(snapshot, scratch_allocator); return false }
		source := sdl3.GPUTextureTransferInfo{transfer_buffer=renderer.atlas_transfer, offset=0, pixels_per_row=sdl3.Uint32(upload_width), rows_per_layer=sdl3.Uint32(upload_height)}
		destination_region := sdl3.GPUTextureRegion{texture=page.texture, mip_level=0, layer=0, x=0, y=0, z=0, w=sdl3.Uint32(view.Width), h=sdl3.Uint32(view.Height), d=1}
		sdl3.UploadToGPUTexture(copy_pass, source, destination_region, true)
		sdl3.EndGPUCopyPass(copy_pass)
		renderer.atlas_uploads += 1
		renderer.atlas_upload_bytes += u64(upload_bytes)
		append(&renderer.pending_dirty, dirty)
	}
	delete(snapshot, scratch_allocator)
	return true
}

native_text_upload_vertices :: proc(renderer: ^Native_Text_Renderer, command: ^sdl3.GPUCommandBuffer) -> bool {
	if !renderer.vertex_upload_pending { return true }
	mapped := sdl3.MapGPUTransferBuffer(renderer.device, renderer.vertex_transfer, true)
	if mapped == nil || len(renderer.vertices) > renderer.vertex_capacity { return false }
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

native_text_render_command :: proc(
	renderer: ^Native_Text_Renderer,
	command_buffer: ^sdl3.GPUCommandBuffer,
	command: alicorn.Display_Command,
	target: ^sdl3.GPUTexture,
	target_w, target_h: sdl3.Uint32,
	scale_x, scale_y: f32,
) -> bool {
	has_draw := false
	for draw in renderer.draws {
		if draw.node == command.node {
			has_draw = true
			break
		}
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
	if command.node == alicorn.Node_ID(0) && command.kind != .Tooltip_Text &&
	   renderer.runtime.transient_overlay_kind == .Drag_Preview {
		uniforms.model[3][0] = (renderer.runtime.drag.x+alicorn.DRAG_PREVIEW_POINTER_OFFSET)*scale_x
		uniforms.model[3][1] = (renderer.runtime.drag.y+alicorn.DRAG_PREVIEW_POINTER_OFFSET)*scale_y
	}
	sdl3.PushGPUVertexUniformData(command_buffer, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
	target_info := sdl3.GPUColorTargetInfo{texture=target, clear_color=sdl3.FColor{}, load_op=.LOAD, store_op=.STORE}
	pass := sdl3.BeginGPURenderPass(command_buffer, &target_info, 1, nil)
	if pass == nil { return false }
	sdl3.BindGPUGraphicsPipeline(pass, renderer.pipeline)
	sdl3.SetGPUViewport(pass, sdl3.GPUViewport{0, 0, f32(target_w), f32(target_h), 0, 1})
	x0, y0, x1, y1 := logical_to_pixel_bounds(command.clip, scale_x, scale_y)
	if x0 < 0 { x0 = 0 }
	if y0 < 0 { y0 = 0 }
	if x1 > int(target_w) { x1 = int(target_w) }
	if y1 > int(target_h) { y1 = int(target_h) }
	if x1 <= x0 || y1 <= y0 {
		sdl3.EndGPURenderPass(pass)
		return true
	}
	sdl3.SetGPUScissor(pass, sdl3.Rect{x=c.int(x0), y=c.int(y0), w=c.int(x1-x0), h=c.int(y1-y0)})
	vertex_binding := sdl3.GPUBufferBinding{buffer=renderer.vertex_buffer, offset=0}
	sdl3.BindGPUVertexBuffers(pass, 0, &vertex_binding, 1)
	for draw in renderer.draws {
		if draw.node != command.node { continue }
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
		runa.atlas_dirty_ack(&renderer.runtime.text_engine.atlas, renderer.pending_dirty[:])
		clear(&renderer.pending_dirty)
	}
	renderer.vertex_upload_pending = false
}
