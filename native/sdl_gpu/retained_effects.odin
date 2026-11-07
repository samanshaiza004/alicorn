package alicorn_sdl_gpu

import "core:c"
import "core:math"
import alicorn "../../runtime"
import "vendor:sdl3"

// Supported bounded backdrop blur for semantic surfaces. Filtering is encoded
// SDR_UNORM, not a linear-light blur.
//
// Caller protocol: prepare -> capture the opaque generic paint prefix into
// cache.source (translated by -plan.source_bounds.xy) -> encode -> composite ->
// submit -> commit on success, abort on cancellation/failure. Cached skips source
// capture and encode. All render/copy passes must be closed before these calls.
// The captured prefix uses RGBA8_UNORM; filter targets use RGBA16_FLOAT to
// avoid quantizing every weighted tap. The composite pipeline matches the
// owning window's actual swapchain format (for example BGRA8 on Metal).
// Cancel/submit a command before preparing/resetting its cache again; a cache
// belongs to one device and one caller, with at most one pending command.
//
// The application integration uses two fence-tracked slots, matching the
// primary host's two-frame submission limit. Ordinary replacement only uses a
// slot after its last submission fence retires; it never drains the device.
// The byte budget counts requested texel + vertex + transfer bytes; SDL
// pipeline/sampler metadata and opaque driver allocation overhead are unknown.

NATIVE_EFFECT_MAX_DIMENSION :: 2048
NATIVE_EFFECT_MAX_COORD :: 1_048_576
NATIVE_EFFECT_MAX_SCALE :: 64
NATIVE_EFFECT_MAX_SIGMA_PIXELS :: 32.0
NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS :: 96
NATIVE_EFFECT_MAX_GAUSSIAN_KERNEL_WIDTH :: 2*NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS+1
NATIVE_EFFECT_MAX_FILTER_TAPS :: 97
NATIVE_EFFECT_VERTEX_COUNT :: NATIVE_EFFECT_MAX_FILTER_TAPS*12+6
NATIVE_EFFECT_VERTEX_BYTES :: u64(NATIVE_EFFECT_VERTEX_COUNT * size_of(Native_Text_Vertex))
NATIVE_EFFECT_SOURCE_FORMAT :: sdl3.GPUTextureFormat.R8G8B8A8_UNORM
NATIVE_EFFECT_FILTER_FORMAT :: sdl3.GPUTextureFormat.R16G16B16A16_FLOAT

Native_Effect_Tap :: struct {
	offset_pixels: f32,
	weight: f32,
}

Native_Effect_Request :: struct {
	enabled: bool,
	key, source_generation: u64,
	region, clip: alicorn.Rect,
	scale: f32,
	sigma: f32, // Gaussian standard deviation in logical pixels, [0,8]; zero bypasses
	depth: int, // exactly one; nesting is unsupported
}

Native_Effect_Plan :: struct {
	active: bool,
	source_bounds: alicorn.Rect,
	output_clip: alicorn.Rect,
	width, height: sdl3.Uint32,
	scale, sigma_pixels: f32,
	filter_tap_count: int,
	key, source_generation: u64,
	bytes: u64,
}

Native_Effect_Status :: enum { Inactive, Cached, Render, Deferred, Fallback }

Native_Effect_Cache :: struct {
	device: ^sdl3.GPUDevice,
	budget_bytes: u64,
	composite_format: sdl3.GPUTextureFormat,
	plan: Native_Effect_Plan,
	source, ping, output: ^sdl3.GPUTexture,
	filter_pipeline, composite_pipeline: ^sdl3.GPUGraphicsPipeline,
	sampler: ^sdl3.GPUSampler,
	vertex_buffer: ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	vertices: [NATIVE_EFFECT_VERTEX_COUNT]Native_Text_Vertex,
	valid, pending, encoded: bool,
	vertex_upload_pending, vertex_upload_encoded: bool,
	pending_command: ^sdl3.GPUCommandBuffer,
	texture_bytes: [3]u64, // source, horizontal, and vertical texture charges
	// Lifetime counters survive reset/deactivation. Allocations counts retained
	// SDL objects (textures, pipelines, sampler, buffer, transfer), not shaders.
	allocations, filter_passes, composites, cache_hits: u64,
	vertex_upload_bytes: u64,
	output_generation, live_bytes, peak_bytes: u64,
}

NATIVE_RETAINED_EFFECT_SLOT_COUNT :: 2
NATIVE_RETAINED_EFFECT_BUDGET_BYTES :: 48 * 1024 * 1024

// One slot is read by the current frame while the other can be rebuilt. A
// slot becomes writable only after the primary host retires its last-use
// submission fence. This bounds in-flight effect storage without device-idle
// waits during normal UI changes.
Native_Retained_Effects :: struct {
	slots: [NATIVE_RETAINED_EFFECT_SLOT_COUNT]Native_Effect_Cache,
	slot_last_use_serial: [NATIVE_RETAINED_EFFECT_SLOT_COUNT]u64,
	device: ^sdl3.GPUDevice,
	budget_bytes: u64,
	composite_format: sdl3.GPUTextureFormat,
	completed_serial: u64,
	pending_slot: int,
	pending_status: Native_Effect_Status,
	pending_key: u64,
	retry_pending: bool,
	direct_fallbacks: u64,
}

native_retained_effects_make :: proc(
	device: ^sdl3.GPUDevice,
	budget_bytes := u64(NATIVE_RETAINED_EFFECT_BUDGET_BYTES),
	composite_format := sdl3.GPUTextureFormat.R8G8B8A8_UNORM,
) -> Native_Retained_Effects {
	result := Native_Retained_Effects{device=device, budget_bytes=budget_bytes, composite_format=composite_format, pending_slot=-1}
	for &slot in result.slots { slot = native_effect_make(device, budget_bytes, composite_format) }
	return result
}

native_retained_effects_note_completed :: proc(effects: ^Native_Retained_Effects, completed_serial: u64) {
	if effects == nil { return }
	effects.completed_serial = max(effects.completed_serial, completed_serial)
}

native_retained_effects_slot_in_flight :: proc(effects: ^Native_Retained_Effects, index: int) -> bool {
	return effects != nil && index >= 0 && index < NATIVE_RETAINED_EFFECT_SLOT_COUNT &&
		effects.slot_last_use_serial[index] > effects.completed_serial
}

native_retained_effects_next_busy_serial :: proc(effects: ^Native_Retained_Effects) -> u64 {
	if effects == nil { return 0 }
	next := u64(0xffff_ffff_ffff_ffff)
	for serial in effects.slot_last_use_serial {
		if serial > effects.completed_serial { next = min(next, serial) }
	}
	return 0 if next == u64(0xffff_ffff_ffff_ffff) else next
}

native_retained_effects_prepare :: proc(effects: ^Native_Retained_Effects, plan: Native_Effect_Plan) -> Native_Effect_Status {
	if effects == nil { return .Fallback }
	effects.retry_pending = false
	if !plan.active || !native_effect_plan_valid(plan) || effects.pending_slot >= 0 ||
	   effects.device == nil || plan.bytes > effects.budget_bytes {
		effects.direct_fallbacks += 1
		return .Fallback
	}
	// Prefer an exact cached prefix even if its output is still referenced by
	// older frames; sampling a retained texture is read-only and safe.
	for &slot, index in effects.slots {
		if slot.valid && slot.plan == plan {
			effects.pending_slot = index
			effects.pending_status = .Cached
			effects.pending_key = plan.key
			return .Cached
		}
	}
	may_retry_after_fence := false
	for &slot, index in effects.slots {
		other_index := 1-index
		if native_retained_effects_slot_in_flight(effects, index) {
			may_retry_after_fence = true
			continue
		}
		other_bytes := effects.slots[other_index].live_bytes
		available := u64(0)
		if other_bytes < effects.budget_bytes { available = effects.budget_bytes-other_bytes }
		if plan.bytes > available {
			if native_retained_effects_slot_in_flight(effects, other_index) {
				may_retry_after_fence = true
				continue
			}
			// A completed cache generation is safe to evict. The swapchain keeps
			// the last presented image; its offscreen texture need not stay resident
			// merely to preserve a cache entry that blocks a replacement.
			native_effect_reset(&effects.slots[other_index])
			available = effects.budget_bytes
		}
		slot.budget_bytes = available
		status := native_effect_prepare(&slot, plan)
		if status == .Render || status == .Cached {
			effects.pending_slot = index
			effects.pending_status = status
			effects.pending_key = plan.key
			return status
		}
	}
	if may_retry_after_fence {
		effects.retry_pending = true
		return .Deferred
	}
	effects.direct_fallbacks += 1
	return .Fallback
}

native_retained_effects_encode :: proc(effects: ^Native_Retained_Effects, command: ^sdl3.GPUCommandBuffer) -> bool {
	if effects == nil || effects.pending_slot < 0 || effects.pending_status != .Render { return false }
	return native_effect_encode(&effects.slots[effects.pending_slot], command)
}

native_retained_effects_composite :: proc(
	effects: ^Native_Retained_Effects,
	command: ^sdl3.GPUCommandBuffer,
	target: ^sdl3.GPUTexture,
	w, h: sdl3.Uint32,
) -> bool {
	if effects == nil || effects.pending_slot < 0 { return true }
	return native_effect_composite(&effects.slots[effects.pending_slot], command, target, w, h)
}

native_retained_effects_composite_at :: proc(
	effects: ^Native_Retained_Effects,
	owner: alicorn.Node_ID,
	command: ^sdl3.GPUCommandBuffer,
	target: ^sdl3.GPUTexture,
	w, h: sdl3.Uint32,
) -> bool {
	if effects == nil || effects.pending_slot < 0 || effects.pending_key != u64(owner) { return true }
	return native_effect_composite(&effects.slots[effects.pending_slot], command, target, w, h)
}

native_retained_effects_commit :: proc(effects: ^Native_Retained_Effects, submission_serial: u64) {
	if effects == nil || effects.pending_slot < 0 { return }
	index := effects.pending_slot
	if effects.pending_status == .Render { native_effect_commit(&effects.slots[index]) }
	effects.slot_last_use_serial[index] = max(effects.slot_last_use_serial[index], submission_serial)
	effects.pending_slot = -1
	effects.pending_status = .Inactive
	effects.pending_key = 0
}

native_retained_effects_abort :: proc(effects: ^Native_Retained_Effects) {
	if effects == nil || effects.pending_slot < 0 { return }
	if effects.pending_status == .Render { native_effect_abort(&effects.slots[effects.pending_slot]) }
	effects.pending_slot = -1
	effects.pending_status = .Inactive
	effects.pending_key = 0
}

native_retained_effects_destroy :: proc(effects: ^Native_Retained_Effects, device_already_idle := false) {
	if effects == nil { return }
	if !device_already_idle {
		for &slot in effects.slots {
			if native_effect_has_resources(&slot) && effects.device != nil {
				_ = sdl3.WaitForGPUIdle(effects.device)
				break
			}
		}
	}
	for &slot in effects.slots { native_effect_reset(&slot) }
	effects.pending_slot = -1
	effects.pending_key = 0
	effects.slot_last_use_serial = [NATIVE_RETAINED_EFFECT_SLOT_COUNT]u64{}
}

native_effect_rect_bounded :: proc(rect: alicorn.Rect) -> bool {
	for value in ([4]f32{rect.x, rect.y, rect.w, rect.h}) {
		if !alicorn.number_is_finite(value) || abs(value) > NATIVE_EFFECT_MAX_COORD { return false }
	}
	return abs(f64(rect.x)+f64(rect.w)) <= NATIVE_EFFECT_MAX_COORD &&
	       abs(f64(rect.y)+f64(rect.h)) <= NATIVE_EFFECT_MAX_COORD
}

native_effect_byte_size :: proc(width, height: sdl3.Uint32) -> u64 {
	return u64(width)*u64(height)*(4+8+8) + 2*NATIVE_EFFECT_VERTEX_BYTES
}

native_effect_gaussian_radius :: proc(sigma_pixels: f32) -> (radius: int, ok: bool) {
	if !alicorn.number_is_finite(sigma_pixels) || sigma_pixels <= 0 || sigma_pixels > NATIVE_EFFECT_MAX_SIGMA_PIXELS {
		return 0, false
	}
	radius_f64 := math.ceil(3*f64(sigma_pixels))
	if radius_f64 < 1 || radius_f64 > NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS { return 0, false }
	return int(radius_f64), true
}

native_effect_gaussian_tap_count :: proc(sigma_pixels: f32) -> (count: int, ok: bool) {
	radius, valid := native_effect_gaussian_radius(sigma_pixels)
	if !valid { return 0, false }
	// Pair adjacent positive and negative texel weights into one bilinear
	// sample per side, retaining the center sample and any unpaired edge tap.
	return 1+2*((radius+1)/2), true
}

native_effect_gaussian_weights :: proc(sigma_pixels: f32) -> (weights: [NATIVE_EFFECT_MAX_GAUSSIAN_KERNEL_WIDTH]f32, radius: int, ok: bool) {
	computed_radius, valid := native_effect_gaussian_radius(sigma_pixels)
	if !valid { return weights, 0, false }

	radius = computed_radius
	count := radius*2+1
	center := NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS
	unnormalized: [NATIVE_EFFECT_MAX_GAUSSIAN_KERNEL_WIDTH]f64
	total := f64(0)
	denominator := 2*f64(sigma_pixels)*f64(sigma_pixels)
	for index in 0..<count {
		offset := index-radius
		x := f64(offset)
		weight := math.exp(-(x*x)/denominator)
		unnormalized[center+offset] = weight
		total += weight
	}
	for index in 0..<count {
		offset := index-radius
		weights[center+offset] = f32(unnormalized[center+offset]/total)
	}
	return weights, radius, true
}

native_effect_gaussian_taps :: proc(sigma_pixels: f32) -> (taps: [NATIVE_EFFECT_MAX_FILTER_TAPS]Native_Effect_Tap, count: int, ok: bool) {
	weights, radius, valid := native_effect_gaussian_weights(sigma_pixels)
	if !valid { return taps, 0, false }
	center := NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS
	taps[0] = Native_Effect_Tap{0, weights[center]}
	count = 1
	for distance := 1; distance <= radius; distance += 2 {
		near_weight := f64(weights[center+distance])
		far_weight := f64(0)
		if distance < radius { far_weight = f64(weights[center+distance+1]) }
		combined := near_weight+far_weight
		offset := f64(distance)
		if combined > 0 {
			offset = (f64(distance)*near_weight+f64(distance+1)*far_weight)/combined
		}
		weight := f32(combined)
		taps[count] = Native_Effect_Tap{-f32(offset), weight}
		taps[count+1] = Native_Effect_Tap{f32(offset), weight}
		count += 2
	}
	return taps, count, true
}

native_effect_plan :: proc(request: Native_Effect_Request) -> (plan: Native_Effect_Plan, ok: bool) {
	// A zero-initialized disabled request needs no device, key, generation, scale,
	// or depth. Enabled requests are validated.
	if !request.enabled { return plan, true }
	if !alicorn.number_is_finite(request.scale) || request.scale <= 0 || request.scale > NATIVE_EFFECT_MAX_SCALE ||
	   !alicorn.number_is_finite(request.sigma) || request.sigma < 0 || request.sigma > 8 ||
	   !native_effect_rect_bounded(request.region) || !native_effect_rect_bounded(request.clip) ||
	   request.depth != 1 || request.key == 0 || request.source_generation == 0 { return plan, false }
	output_clip := alicorn.rect_intersection(request.region, request.clip)
	if request.sigma == 0 || request.region.w <= 0 || request.region.h <= 0 ||
	   request.clip.w <= 0 || request.clip.h <= 0 || output_clip.w <= 0 || output_clip.h <= 0 { return plan, true }
	sigma_pixels := request.sigma*request.scale
	radius, radius_ok := native_effect_gaussian_radius(sigma_pixels)
	tap_count, tap_count_ok := native_effect_gaussian_tap_count(sigma_pixels)
	if !radius_ok || !tap_count_ok { return Native_Effect_Plan{}, false }
	// Capture the complete finite 3-sigma Gaussian support and round outward in
	// physical pixels before conversion back to logical layout coordinates.
	scale, halo := f64(request.scale), f64(radius)/f64(request.scale)
	left := math.floor((f64(request.region.x)-halo)*scale)
	top := math.floor((f64(request.region.y)-halo)*scale)
	right := math.ceil((f64(request.region.x)+f64(request.region.w)+halo)*scale)
	bottom := math.ceil((f64(request.region.y)+f64(request.region.h)+halo)*scale)
	w, h := right-left, bottom-top
	if abs(left) > NATIVE_EFFECT_MAX_COORD || abs(top) > NATIVE_EFFECT_MAX_COORD ||
	   abs(right) > NATIVE_EFFECT_MAX_COORD || abs(bottom) > NATIVE_EFFECT_MAX_COORD ||
	   w < 1 || h < 1 || w > NATIVE_EFFECT_MAX_DIMENSION || h > NATIVE_EFFECT_MAX_DIMENSION { return plan, false }
	// Extremely small scales can make the snapped logical extent unbounded.
	source := alicorn.Rect{f32(left/scale), f32(top/scale), f32(w/scale), f32(h/scale)}
	if !native_effect_rect_bounded(source) { return plan, false }
	plan = Native_Effect_Plan{
		active=true, source_bounds=source, output_clip=output_clip,
		width=sdl3.Uint32(w), height=sdl3.Uint32(h),
		scale=request.scale, sigma_pixels=sigma_pixels, filter_tap_count=tap_count,
		key=request.key, source_generation=request.source_generation,
	}
	plan.bytes = native_effect_byte_size(plan.width, plan.height)
	// Include f32 round-trip/underflow checks in planning, so an accepted plan
	// also passes prepare's allocation-boundary validation.
	if !native_effect_plan_valid(plan) { return Native_Effect_Plan{}, false }
	return plan, true
}

// Defend the allocation boundary as well: callers must not be able to bypass
// caps or supply a forged, smaller byte count by constructing a plan directly.
native_effect_plan_valid :: proc(plan: Native_Effect_Plan) -> bool {
	if !plan.active { return true }
	if plan.key == 0 || plan.source_generation == 0 ||
	   plan.width == 0 || plan.height == 0 || plan.width > NATIVE_EFFECT_MAX_DIMENSION || plan.height > NATIVE_EFFECT_MAX_DIMENSION ||
	   !alicorn.number_is_finite(plan.scale) || plan.scale <= 0 || plan.scale > NATIVE_EFFECT_MAX_SCALE ||
	   !alicorn.number_is_finite(plan.sigma_pixels) || plan.sigma_pixels <= 0 || plan.sigma_pixels > NATIVE_EFFECT_MAX_SIGMA_PIXELS ||
	   !native_effect_rect_bounded(plan.source_bounds) || !native_effect_rect_bounded(plan.output_clip) ||
	   plan.source_bounds.w <= 0 || plan.source_bounds.h <= 0 || plan.output_clip.w <= 0 || plan.output_clip.h <= 0 ||
	   plan.bytes != native_effect_byte_size(plan.width, plan.height) { return false }
	expected_taps, taps_ok := native_effect_gaussian_tap_count(plan.sigma_pixels)
	if !taps_ok || plan.filter_tap_count != expected_taps { return false }
	left, top := f64(plan.source_bounds.x)*f64(plan.scale), f64(plan.source_bounds.y)*f64(plan.scale)
	w, h := f64(plan.source_bounds.w)*f64(plan.scale), f64(plan.source_bounds.h)*f64(plan.scale)
	if abs(left) > NATIVE_EFFECT_MAX_COORD || abs(top) > NATIVE_EFFECT_MAX_COORD ||
	   abs(left+w) > NATIVE_EFFECT_MAX_COORD || abs(top+h) > NATIVE_EFFECT_MAX_COORD ||
	   abs(left-math.round(left)) > 0.125 || abs(top-math.round(top)) > 0.125 ||
	   abs(w-f64(plan.width)) > 0.001 || abs(h-f64(plan.height)) > 0.001 { return false }
	// Allow only the f32 round-trip tolerance at the logical source boundary.
	epsilon := f32(0.25)/plan.scale
	return plan.output_clip.x >= plan.source_bounds.x-epsilon && plan.output_clip.y >= plan.source_bounds.y-epsilon &&
	       f64(plan.output_clip.x)+f64(plan.output_clip.w) <= f64(plan.source_bounds.x)+f64(plan.source_bounds.w)+f64(epsilon) &&
	       f64(plan.output_clip.y)+f64(plan.output_clip.h) <= f64(plan.source_bounds.y)+f64(plan.source_bounds.h)+f64(epsilon)
}

native_effect_make :: proc(
	device: ^sdl3.GPUDevice,
	budget_bytes: u64,
	composite_format := sdl3.GPUTextureFormat.R8G8B8A8_UNORM,
) -> Native_Effect_Cache {
	// Pure CPU construction, with no SDL calls and no dynamic allocation.
	return Native_Effect_Cache{device=device, budget_bytes=budget_bytes, composite_format=composite_format}
}

native_effect_allocation :: proc(cache: ^Native_Effect_Cache, bytes: u64 = 0) {
	cache.allocations += 1
	cache.live_bytes += bytes
	cache.peak_bytes = max(cache.peak_bytes, cache.live_bytes)
}

native_effect_release_textures :: proc(cache: ^Native_Effect_Cache) {
	for slot, index in ([3]^^sdl3.GPUTexture{&cache.source, &cache.ping, &cache.output}) {
		if slot^ != nil {
			sdl3.ReleaseGPUTexture(cache.device, slot^)
			slot^ = nil
			cache.live_bytes -= cache.texture_bytes[index]
		}
		cache.texture_bytes[index] = 0
	}
}

native_effect_has_resources :: proc(cache: ^Native_Effect_Cache) -> bool {
	return cache.source != nil || cache.ping != nil || cache.output != nil || cache.filter_pipeline != nil ||
	       cache.composite_pipeline != nil || cache.sampler != nil || cache.vertex_buffer != nil || cache.vertex_transfer != nil
}

native_effect_abort :: proc(cache: ^Native_Effect_Cache) {
	if cache == nil { return }
	cache.valid, cache.pending, cache.encoded = false, false, false
	if cache.vertex_upload_encoded { cache.vertex_upload_pending = true }
	cache.vertex_upload_encoded = false
	cache.pending_command = nil
}

native_effect_reset :: proc(cache: ^Native_Effect_Cache) {
	if cache == nil { return }
	native_effect_abort(cache)
	native_effect_release_textures(cache)
	if cache.vertex_transfer != nil { sdl3.ReleaseGPUTransferBuffer(cache.device, cache.vertex_transfer) }
	if cache.vertex_buffer != nil { sdl3.ReleaseGPUBuffer(cache.device, cache.vertex_buffer) }
	if cache.sampler != nil { sdl3.ReleaseGPUSampler(cache.device, cache.sampler) }
	if cache.filter_pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(cache.device, cache.filter_pipeline) }
	if cache.composite_pipeline != nil { sdl3.ReleaseGPUGraphicsPipeline(cache.device, cache.composite_pipeline) }
	cache.vertex_transfer, cache.vertex_buffer, cache.sampler = nil, nil, nil
	cache.filter_pipeline, cache.composite_pipeline = nil, nil
	cache.plan = {}
	cache.vertex_upload_pending = false
	cache.live_bytes = 0
}

native_effect_destroy :: proc(cache: ^Native_Effect_Cache) {
	if cache == nil { return }
	if native_effect_has_resources(cache) && cache.device != nil {
		// Shutdown is the only place the retained-effect cache may drain the
		// device. The application loop already waits before calling this.
		_ = sdl3.WaitForGPUIdle(cache.device)
	}
	native_effect_reset(cache)
}

native_effect_create_fixed :: proc(cache: ^Native_Effect_Cache) -> bool {
	vertex := native_text_shader(cache.device, .VERTEX, false)
	if vertex == nil { return false }
	defer sdl3.ReleaseGPUShader(cache.device, vertex)
	fragment := native_fragment_shader(
		cache.device, GPU_IMAGE_FRAG_DXIL, GPU_IMAGE_FRAG_MSL, GPU_IMAGE_FRAG_SPV,
	)
	if fragment == nil { return false }
	defer sdl3.ReleaseGPUShader(cache.device, fragment)
	vertex_buffers := [1]sdl3.GPUVertexBufferDescription{{slot=0, pitch=sdl3.Uint32(size_of(Native_Text_Vertex)), input_rate=.VERTEX}}
	attributes := [3]sdl3.GPUVertexAttribute{
		{location=0, buffer_slot=0, format=.FLOAT3, offset=0},
		{location=1, buffer_slot=0, format=.FLOAT4, offset=sdl3.Uint32(size_of([3]f32))},
		{location=2, buffer_slot=0, format=.FLOAT2, offset=sdl3.Uint32(size_of([3]f32)+size_of([4]f32))},
	}
	// All sampled channels are already premultiplied from source rendering.
	// Each Gaussian weight appears ONCE in all four vertex-color channels.
	additive := sdl3.GPUColorTargetBlendState{
		src_color_blendfactor=.ONE, dst_color_blendfactor=.ONE, color_blend_op=.ADD,
		src_alpha_blendfactor=.ONE, dst_alpha_blendfactor=.ONE, alpha_blend_op=.ADD, enable_blend=true,
	}
	premultiplied := sdl3.GPUColorTargetBlendState{
		src_color_blendfactor=.ONE, dst_color_blendfactor=.ONE_MINUS_SRC_ALPHA, color_blend_op=.ADD,
		src_alpha_blendfactor=.ONE, dst_alpha_blendfactor=.ONE_MINUS_SRC_ALPHA, alpha_blend_op=.ADD, enable_blend=true,
	}
	targets := [1]sdl3.GPUColorTargetDescription{{format=NATIVE_EFFECT_FILTER_FORMAT, blend_state=additive}}
	info := sdl3.GPUGraphicsPipelineCreateInfo{
		vertex_shader=vertex, fragment_shader=fragment,
		vertex_input_state={vertex_buffer_descriptions=&vertex_buffers[0], num_vertex_buffers=1, vertex_attributes=&attributes[0], num_vertex_attributes=3},
		primitive_type=.TRIANGLELIST,
		rasterizer_state={fill_mode=.FILL, cull_mode=.NONE, front_face=.COUNTER_CLOCKWISE, enable_depth_clip=true},
		target_info={color_target_descriptions=&targets[0], num_color_targets=1},
	}
	cache.filter_pipeline = sdl3.CreateGPUGraphicsPipeline(cache.device, info)
	if cache.filter_pipeline == nil { return false }
	native_effect_allocation(cache)
	targets[0].format = cache.composite_format
	targets[0].blend_state = premultiplied
	cache.composite_pipeline = sdl3.CreateGPUGraphicsPipeline(cache.device, info)
	if cache.composite_pipeline == nil { return false }
	native_effect_allocation(cache)
	cache.sampler = sdl3.CreateGPUSampler(cache.device, {
		min_filter=.LINEAR, mag_filter=.LINEAR, mipmap_mode=.NEAREST,
		address_mode_u=.CLAMP_TO_EDGE, address_mode_v=.CLAMP_TO_EDGE, address_mode_w=.CLAMP_TO_EDGE, max_lod=0,
	})
	if cache.sampler == nil { return false }
	native_effect_allocation(cache)
	cache.vertex_buffer = sdl3.CreateGPUBuffer(cache.device, {usage={.VERTEX}, size=sdl3.Uint32(NATIVE_EFFECT_VERTEX_BYTES)})
	if cache.vertex_buffer == nil { return false }
	native_effect_allocation(cache, NATIVE_EFFECT_VERTEX_BYTES)
	cache.vertex_transfer = sdl3.CreateGPUTransferBuffer(cache.device, {usage=.UPLOAD, size=sdl3.Uint32(NATIVE_EFFECT_VERTEX_BYTES)})
	if cache.vertex_transfer == nil { return false }
	native_effect_allocation(cache, NATIVE_EFFECT_VERTEX_BYTES)
	return true
}

native_effect_quad :: proc(vertices: ^[NATIVE_EFFECT_VERTEX_COUNT]Native_Text_Vertex, first: int, x0, y0, x1, y1, u0, v0, u1, v1, weight: f32) {
	color := [4]f32{weight, weight, weight, weight}
	a := Native_Text_Vertex{{x0,y0,0}, color, {u0,v0}}
	b := Native_Text_Vertex{{x1,y0,0}, color, {u1,v0}}
	c := Native_Text_Vertex{{x1,y1,0}, color, {u1,v1}}
	d := Native_Text_Vertex{{x0,y1,0}, color, {u0,v1}}
	vertices[first+0], vertices[first+1], vertices[first+2] = a,b,c
	vertices[first+3], vertices[first+4], vertices[first+5] = a,c,d
}

native_effect_build_vertices :: proc(cache: ^Native_Effect_Cache) {
	w, h := f32(cache.plan.width), f32(cache.plan.height)
	taps, tap_count, ok := native_effect_gaussian_taps(cache.plan.sigma_pixels)
	if !ok || tap_count != cache.plan.filter_tap_count { return }
	for tap in 0..<tap_count {
		sample := taps[tap]
		du, dv := sample.offset_pixels/w, sample.offset_pixels/h
		native_effect_quad(&cache.vertices, tap*6, 0,0,w,h, du,0,1+du,1, sample.weight)
		native_effect_quad(&cache.vertices, tap_count*6+tap*6, 0,0,w,h, 0,dv,1,1+dv, sample.weight)
	}
	// Use the physical snapped origin, avoiding subpixel texture resampling.
	x := f32(math.round(f64(cache.plan.source_bounds.x)*f64(cache.plan.scale)))
	y := f32(math.round(f64(cache.plan.source_bounds.y)*f64(cache.plan.scale)))
	native_effect_quad(&cache.vertices, tap_count*12, x,y,x+w,y+h, 0,0,1,1, 1)
	cache.vertex_upload_pending = true
}

native_effect_prepare :: proc(cache: ^Native_Effect_Cache, plan: Native_Effect_Plan) -> Native_Effect_Status {
	if cache == nil { return .Fallback }
	if !plan.active { native_effect_reset(cache); return .Inactive }
	if !native_effect_plan_valid(plan) || cache.device == nil || plan.bytes > cache.budget_bytes {
		native_effect_reset(cache)
		return .Fallback
	}
	if cache.valid && cache.plan == plan {
		cache.cache_hits += 1
		return .Cached
	}
	// Callers select this cache only after its last-use fence has retired. This
	// permits bounded reuse without a device-wide wait on resize or repaint.
	native_effect_abort(cache)
	if !sdl3.GPUTextureSupportsFormat(cache.device, NATIVE_EFFECT_SOURCE_FORMAT, .D2, {.SAMPLER, .COLOR_TARGET}) ||
	   !sdl3.GPUTextureSupportsFormat(cache.device, NATIVE_EFFECT_FILTER_FORMAT, .D2, {.SAMPLER, .COLOR_TARGET}) ||
	   !sdl3.GPUTextureSupportsFormat(cache.device, cache.composite_format, .D2, {.COLOR_TARGET}) {
		native_effect_reset(cache)
		return .Fallback
	}
	if cache.filter_pipeline == nil && !native_effect_create_fixed(cache) {
		native_effect_reset(cache)
		return .Fallback
	}
	if cache.source == nil || cache.plan.width != plan.width || cache.plan.height != plan.height {
		// Release BEFORE allocating replacements: the budget covers the peak,
		// including the unchanged fixed buffer and transfer buffer.
		native_effect_release_textures(cache)
		formats := [3]sdl3.GPUTextureFormat{NATIVE_EFFECT_SOURCE_FORMAT, NATIVE_EFFECT_FILTER_FORMAT, NATIVE_EFFECT_FILTER_FORMAT}
		bytes_per_pixel := [3]u64{4, 8, 8}
		for slot, index in ([3]^^sdl3.GPUTexture{&cache.source, &cache.ping, &cache.output}) {
			slot^ = sdl3.CreateGPUTexture(cache.device, {
			type=.D2, format=formats[index], usage={.SAMPLER, .COLOR_TARGET},
				width=plan.width, height=plan.height, layer_count_or_depth=1, num_levels=1, sample_count=._1,
			})
			if slot^ == nil { native_effect_reset(cache); return .Fallback }
			cache.texture_bytes[index] = u64(plan.width)*u64(plan.height)*bytes_per_pixel[index]
			native_effect_allocation(cache, cache.texture_bytes[index])
		}
	}
	// Source/resource generations invalidate pixels, not the filter quad mesh.
	// Keep geometry uploaded through a repaint with unchanged bounds/parameters.
	changed := cache.plan.source_bounds != plan.source_bounds || cache.plan.width != plan.width ||
	           cache.plan.height != plan.height || cache.plan.scale != plan.scale ||
	           cache.plan.sigma_pixels != plan.sigma_pixels || cache.plan.filter_tap_count != plan.filter_tap_count
	cache.plan = plan
	if changed { native_effect_build_vertices(cache) }
	cache.pending = true
	return .Render
}

native_effect_uniforms :: proc(command: ^sdl3.GPUCommandBuffer, width, height: sdl3.Uint32) {
	uniforms := Native_Text_Uniforms{
		proj_view={{2/f32(width),0,0,0},{0,-2/f32(height),0,0},{0,0,1,0},{-1,1,0,1}},
		model={{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}},
	}
	sdl3.PushGPUVertexUniformData(command, 0, &uniforms, sdl3.Uint32(size_of(Native_Text_Uniforms)))
}

native_effect_encode :: proc(cache: ^Native_Effect_Cache, command: ^sdl3.GPUCommandBuffer) -> bool {
	if cache == nil { return false }
	if command == nil || !cache.pending || cache.source == nil {
		native_effect_abort(cache)
		return false
	}
	if cache.encoded {
		if cache.pending_command == command { return true }
		native_effect_abort(cache)
		return false
	}
	if cache.vertex_upload_pending {
		mapped := sdl3.MapGPUTransferBuffer(cache.device, cache.vertex_transfer, false)
		if mapped == nil { native_effect_abort(cache); return false }
		destination := cast([^]Native_Text_Vertex)mapped
		for vertex, index in cache.vertices { destination[index] = vertex }
		sdl3.UnmapGPUTransferBuffer(cache.device, cache.vertex_transfer)
		copy_pass := sdl3.BeginGPUCopyPass(command)
		if copy_pass == nil { native_effect_abort(cache); return false }
		sdl3.UploadToGPUBuffer(copy_pass,
			{transfer_buffer=cache.vertex_transfer, offset=0},
			{buffer=cache.vertex_buffer, offset=0, size=sdl3.Uint32(NATIVE_EFFECT_VERTEX_BYTES)}, false)
		sdl3.EndGPUCopyPass(copy_pass)
		cache.vertex_upload_bytes += NATIVE_EFFECT_VERTEX_BYTES
		cache.vertex_upload_encoded = true
	}
	native_effect_uniforms(command, cache.plan.width, cache.plan.height)
	for axis in 0..<2 {
		source, target := cache.source, cache.ping
		if axis == 1 { source, target = cache.ping, cache.output }
		info := sdl3.GPUColorTargetInfo{texture=target, clear_color={}, load_op=.CLEAR, store_op=.STORE, cycle=false}
		pass := sdl3.BeginGPURenderPass(command, &info, 1, nil)
		if pass == nil { native_effect_abort(cache); return false }
		sdl3.BindGPUGraphicsPipeline(pass, cache.filter_pipeline)
		sdl3.SetGPUViewport(pass, {0,0,f32(cache.plan.width),f32(cache.plan.height),0,1})
		binding := sdl3.GPUBufferBinding{buffer=cache.vertex_buffer}
		sdl3.BindGPUVertexBuffers(pass, 0, &binding, 1)
		sampler := sdl3.GPUTextureSamplerBinding{texture=source, sampler=cache.sampler}
		sdl3.BindGPUFragmentSamplers(pass, 0, &sampler, 1)
		// Bilinear-paired Gaussian taps, accumulated into half-float targets.
		first_vertex := axis*cache.plan.filter_tap_count*6
		sdl3.DrawGPUPrimitives(pass, sdl3.Uint32(cache.plan.filter_tap_count*6), 1, sdl3.Uint32(first_vertex), 0)
		sdl3.EndGPURenderPass(pass)
		cache.filter_passes += 1
	}
	cache.encoded = true
	cache.pending_command = command
	return true
}

native_effect_composite :: proc(cache: ^Native_Effect_Cache, command: ^sdl3.GPUCommandBuffer, target: ^sdl3.GPUTexture, w, h: sdl3.Uint32) -> bool {
	if cache == nil { return false }
	if command == nil || target == nil || w == 0 || h == 0 || w > NATIVE_EFFECT_MAX_COORD || h > NATIVE_EFFECT_MAX_COORD ||
	   target == cache.source || target == cache.ping || target == cache.output ||
	   !(cache.valid || (cache.pending && cache.encoded && cache.pending_command == command)) {
		native_effect_abort(cache)
		return false
	}
	// Match ordinary paint-stream edge finalization; only the input halo rounds
	// outward. The output scissor is the resolved logical region/clip overlap.
	x0,y0,x1,y1 := logical_to_pixel_bounds(cache.plan.output_clip, cache.plan.scale, cache.plan.scale)
	x0,y0 = clamp(x0,0,int(w)),clamp(y0,0,int(h))
	x1,y1 = clamp(x1,0,int(w)),clamp(y1,0,int(h))
	if x1 <= x0 || y1 <= y0 { return true }
	native_effect_uniforms(command, w, h)
	info := sdl3.GPUColorTargetInfo{texture=target, load_op=.LOAD, store_op=.STORE, cycle=false}
	pass := sdl3.BeginGPURenderPass(command, &info, 1, nil)
	if pass == nil { native_effect_abort(cache); return false }
	sdl3.BindGPUGraphicsPipeline(pass, cache.composite_pipeline)
	sdl3.SetGPUViewport(pass, {0,0,f32(w),f32(h),0,1})
	sdl3.SetGPUScissor(pass, {x=c.int(x0), y=c.int(y0), w=c.int(x1-x0), h=c.int(y1-y0)})
	binding := sdl3.GPUBufferBinding{buffer=cache.vertex_buffer}
	sdl3.BindGPUVertexBuffers(pass, 0, &binding, 1)
	sampler := sdl3.GPUTextureSamplerBinding{texture=cache.output, sampler=cache.sampler}
	sdl3.BindGPUFragmentSamplers(pass, 0, &sampler, 1)
	sdl3.DrawGPUPrimitives(pass, 6, 1, sdl3.Uint32(cache.plan.filter_tap_count*12), 0)
	sdl3.EndGPURenderPass(pass)
	cache.composites += 1
	return true
}

// Call ONLY after successful submission of the command passed to encode.
// Encoding, compositing, or merely preparing never publishes a cache hit.
native_effect_commit :: proc(cache: ^Native_Effect_Cache) {
	if cache == nil || !cache.pending || !cache.encoded { return }
	cache.valid, cache.pending, cache.encoded = true, false, false
	if cache.vertex_upload_encoded { cache.vertex_upload_pending = false }
	cache.vertex_upload_encoded = false
	cache.pending_command = nil
	cache.output_generation += 1
}
