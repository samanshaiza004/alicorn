package alicorn_sdl_gpu

// Experimental application compositor integration for bounded backdrop blur.
// The request is a paint-stream boundary: the host captures only commands
// before it, then composites the cached result immediately before the owning
// surface. Applications never see textures, command buffers, or fences.

import "core:mem"
import alicorn "../../runtime"
import "vendor:sdl3"

when ALICORN_RETAINED_EFFECTS_EXPERIMENT {

NATIVE_EFFECT_PREFIX_CLEAR :: sdl3.FColor{0.035, 0.045, 0.065, 1}

native_effect_hash_mix :: proc(hash, value: u64) -> u64 {
	return (hash ~ value) * 1099511628211
}

native_effect_hash_f32 :: proc(hash: u64, value: f32) -> u64 {
	return native_effect_hash_mix(hash, u64(transmute(u32)value))
}

native_effect_hash_rect :: proc(hash: u64, rect: alicorn.Rect) -> u64 {
	result := hash
	for value in ([4]f32{rect.x, rect.y, rect.w, rect.h}) { result = native_effect_hash_f32(result, value) }
	return result
}

native_effect_hash_color :: proc(hash: u64, color: alicorn.Color) -> u64 {
	result := hash
	for value in ([4]f32{color.r, color.g, color.b, color.a}) { result = native_effect_hash_f32(result, value) }
	return result
}

native_effect_hash_command :: proc(hash: u64, draw: alicorn.Paint_Command) -> u64 {
	result := native_effect_hash_mix(hash, u64(draw.owner))
	result = native_effect_hash_rect(result, draw.bounds)
	result = native_effect_hash_rect(result, draw.clip)
	result = native_effect_hash_mix(result, u64(draw.stroke_placement))
	result = native_effect_hash_f32(result, draw.opacity)
	result = native_effect_hash_f32(result, draw.translation[0])
	result = native_effect_hash_f32(result, draw.translation[1])
	switch payload in draw.payload {
	case alicorn.Surface_Paint:
		result = native_effect_hash_mix(result, 1)
		result = native_effect_hash_mix(result, u64(payload.shape.kind))
		result = native_effect_hash_f32(result, payload.shape.corner_radius)
		result = native_effect_hash_color(result, payload.fill)
		result = native_effect_hash_color(result, payload.stroke.color)
		result = native_effect_hash_f32(result, payload.stroke.width)
		result = native_effect_hash_mix(result, u64(payload.material))
		result = native_effect_hash_f32(result, payload.physical_height)
		result = native_effect_hash_mix(result, u64(payload.material_group))
		result = native_effect_hash_f32(result, payload.top_edge_gap[0])
		result = native_effect_hash_f32(result, payload.top_edge_gap[1])
	case alicorn.Backdrop_Effect_Paint:
		result = native_effect_hash_mix(result, 2)
	case alicorn.Icon_Paint:
		result = native_effect_hash_mix(result, 3)
		result = native_effect_hash_mix(result, u64(payload.id))
		result = native_effect_hash_color(result, payload.color)
	case alicorn.Image_Paint:
		result = native_effect_hash_mix(result, 4)
		result = native_effect_hash_mix(result, u64(payload.image))
	case alicorn.Text_Paint:
		result = native_effect_hash_mix(result, 5)
		result = native_effect_hash_mix(result, u64(payload.run.source))
		result = native_effect_hash_mix(result, payload.run.resource)
		result = native_effect_hash_mix(result, payload.run.generation)
		result = native_effect_hash_color(result, payload.color)
		for span in payload.spans {
			result = native_effect_hash_mix(result, u64(span.start))
			result = native_effect_hash_mix(result, u64(span.end))
			result = native_effect_hash_color(result, span.color)
			result = native_effect_hash_mix(result, u64(span.color_set))
			result = native_effect_hash_mix(result, u64(span.underline))
			result = native_effect_hash_mix(result, u64(span.strikethrough))
			result = native_effect_hash_color(result, span.background)
			result = native_effect_hash_mix(result, u64(span.background_set))
		}
	case alicorn.Geometry_Paint:
		result = native_effect_hash_mix(result, 6)
		result = native_effect_hash_mix(result, u64(payload.geometry.resource))
		result = native_effect_hash_mix(result, payload.geometry.generation)
	}
	return result
}

native_effect_prefix_generation :: proc(
	display: []alicorn.Paint_Command,
	region, clip: alicorn.Rect,
	scale_x, scale_y, radius: f32,
) -> u64 {
	hash := u64(1469598103934665603)
	hash = native_effect_hash_rect(hash, region)
	hash = native_effect_hash_rect(hash, clip)
	hash = native_effect_hash_f32(hash, scale_x)
	hash = native_effect_hash_f32(hash, scale_y)
	hash = native_effect_hash_f32(hash, radius)
	hash = native_effect_hash_mix(hash, u64(len(display)))
	for draw in display { hash = native_effect_hash_command(hash, draw) }
	if hash == 0 { return 1 }
	return hash
}

native_effect_prefix_before_first_marker :: proc(display: []alicorn.Paint_Command) -> (prefix: []alicorn.Paint_Command, marker: alicorn.Paint_Command, marker_index: int, found: bool) {
	for draw, index in display {
		if alicorn.paint_command_is_backdrop_effect(draw) {
			return display[:index], draw, index, true
		}
	}
	return nil, {}, -1, false
}

native_effect_local_prefix :: proc(display: []alicorn.Paint_Command, origin: alicorn.Rect, allocator: mem.Allocator) -> []alicorn.Paint_Command {
	result := make([]alicorn.Paint_Command, len(display), allocator=allocator)
	for draw, index in display {
		result[index] = draw
		result[index].bounds.x -= origin.x
		result[index].bounds.y -= origin.y
		result[index].clip.x -= origin.x
		result[index].clip.y -= origin.y
	}
	return result
}

native_effect_capture_clear :: proc(command: ^sdl3.GPUCommandBuffer, texture: ^sdl3.GPUTexture) -> bool {
	if command == nil || texture == nil { return false }
	info := make_color_target(texture, NATIVE_EFFECT_PREFIX_CLEAR, false)
	pass := sdl3.BeginGPURenderPass(command, &info, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)
	return true
}

native_effects_prepare_display_prefix :: proc(
	command: ^sdl3.GPUCommandBuffer,
	swap_w, swap_h: sdl3.Uint32,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	display: []alicorn.Paint_Command,
	scale_x, scale_y: f32,
	effects: ^Native_Retained_Effects,
	scratch_allocator: mem.Allocator,
) -> bool {
	if effects == nil { return true }
	prefix, marker, marker_index, found := native_effect_prefix_before_first_marker(display)
	if !found { return true }
	// A second boundary would imply nested sampling semantics that this narrow
	// API intentionally does not define. Keep the ordinary panel draw instead.
	for draw in display[marker_index+1:] {
		if alicorn.paint_command_is_backdrop_effect(draw) { return true }
	}
	payload, is_effect := marker.payload.(alicorn.Backdrop_Effect_Paint)
	if !is_effect || marker.owner == 0 || abs(scale_x-scale_y) > 0.001 { return true }
	key := u64(marker.owner)
	generation := native_effect_prefix_generation(prefix, marker.bounds, marker.clip, scale_x, scale_y, payload.radius)
	request := Native_Effect_Request{
		enabled=true,
		key=key,
		source_generation=generation,
		region=marker.bounds,
		clip=marker.clip,
		scale=scale_x,
		spacing=payload.radius,
		depth=1,
	}
	plan, valid := native_effect_plan(request)
	if !valid || !plan.active { return true }
	status := native_retained_effects_prepare(effects, plan)
	if status != .Render { return true }
	slot := &effects.slots[effects.pending_slot]
	if !native_effect_capture_clear(command, slot.source) {
		native_retained_effects_abort(effects)
		return false
	}
	local := native_effect_local_prefix(prefix, plan.source_bounds, scratch_allocator)
	if local == nil && len(prefix) > 0 {
		native_retained_effects_abort(effects)
		return false
	}
	if !draw_display_list(
		command, slot.source, plan.width, plan.height,
		text_renderer, surface_renderer, solid_renderer,
		local, scale_x, scale_y,
		clear_background=false,
		scratch_allocator=scratch_allocator,
	) {
		native_retained_effects_abort(effects)
		return false
	}
	if !native_retained_effects_encode(effects, command) {
		native_retained_effects_abort(effects)
		// Filtering is optional: preserve the ordinary panel path if an
		// effect pipeline cannot be encoded on this host.
		return true
	}
	return true
}

} // ALICORN_RETAINED_EFFECTS_EXPERIMENT
