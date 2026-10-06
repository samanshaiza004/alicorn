package alicorn_sdl_gpu

import alicorn "../../runtime"

// Analytic relief uses a fixed upper-left light. Directional edge response is
// intentionally small and deterministic; physical height changes its optical
// sign/strength but never the paint command's compositor depth or order.
NATIVE_MATERIAL_LIGHT_COMPONENT :: 0.70710678118

// Native material effects are expanded into ordinary surface vertices. The
// flat path remains one quad per Surface_Paint and needs no material geometry.
native_solid_material_vertex_count :: proc(material: alicorn.Style_Material, physical_height: f32) -> int {
	count := 6 // the filled surface itself
	if material.kind != .Analytic_Relief || physical_height == 0 { return count }
	if physical_height > 0 && material.outer_shadow_strength > 0 && material.outer_shadow_radius > 0 { count += 12 }
	if material.bevel_strength > 0 && material.bevel_width > 0 { count += 24 }
	if material.inner_shadow_strength > 0 { count += 24 }
	return count
}

native_solid_material_tint :: proc(color: alicorn.Color, toward_white: bool, amount: f32) -> [4]f32 {
	mix := clamp(amount, 0, 1)
	if toward_white {
		return [4]f32{
			color.r+(1-color.r)*mix,
			color.g+(1-color.g)*mix,
			color.b+(1-color.b)*mix,
			color.a,
		}
	}
	return [4]f32{color.r*(1-mix), color.g*(1-mix), color.b*(1-mix), color.a}
}

native_solid_material_height_factor :: proc(physical_height: f32) -> f32 {
	return clamp(abs(physical_height), 0, 2) * 0.5
}

native_solid_material_edge_tint :: proc(
	fill: alicorn.Color,
	physical_height: f32,
	normal_x, normal_y: f32,
	strength, max_amount: f32,
) -> [4]f32 {
	// Dot the edge normal with a normalized upper-left light direction. A
	// negative height turns the same geometry into a recess by inverting the
	// response; zero height returns to the flat path before this is called.
	response := -(normal_x + normal_y) * NATIVE_MATERIAL_LIGHT_COMPONENT
	if physical_height < 0 { response = -response }
	amount := abs(response) * strength * max_amount * native_solid_material_height_factor(physical_height)
	return native_solid_material_tint(fill, response > 0, amount)
}

native_solid_append_material_edge :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	x0, y0, x1, y1: f32,
	color: [4]f32,
) {
	if x1 <= x0 || y1 <= y0 { return }
	native_solid_append_quad(vertices, x0, y0, x1, y1, color)
}

native_solid_append_material_surface :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	base, shadow: alicorn.Rect,
	fill: alicorn.Color,
	material: alicorn.Style_Material,
	physical_height: f32,
	opacity: f32,
) {
	if base.w <= 0 || base.h <= 0 { return }
	if material.kind != .Analytic_Relief || physical_height == 0 {
		// Keep flat and zero-height surfaces exactly on the original one-quad
		// path: no shadow/bevel geometry and no intermediate material work.
		native_solid_append_quad(vertices, base.x, base.y, base.x+base.w, base.y+base.h,
			[4]f32{fill.r, fill.g, fill.b, fill.a*opacity})
		return
	}
	height_factor := native_solid_material_height_factor(physical_height)
	if material.kind == .Analytic_Relief && physical_height > 0 && material.outer_shadow_strength > 0 && material.outer_shadow_radius > 0 {
		// Two low-alpha, clipped layers approximate a small broad shadow without
		// a framebuffer, blur, texture, or additional render pass.
		outer_color := [4]f32{0, 0, 0, material.outer_shadow_strength*0.07*height_factor*opacity}
		middle_color := [4]f32{0, 0, 0, material.outer_shadow_strength*0.12*height_factor*opacity}
		native_solid_append_material_edge(vertices, shadow.x, shadow.y, shadow.x+shadow.w, shadow.y+shadow.h, outer_color)
		mid := alicorn.Rect{
			shadow.x+(base.x-shadow.x)*0.5,
			shadow.y+(base.y-shadow.y)*0.5,
			shadow.w-(base.x-shadow.x)*0.5-(shadow.x+shadow.w-base.x-base.w)*0.5,
			shadow.h-(base.y-shadow.y)*0.5-(shadow.y+shadow.h-base.y-base.h)*0.5,
		}
		native_solid_append_material_edge(vertices, mid.x, mid.y, mid.x+mid.w, mid.y+mid.h, middle_color)
	}

	base_color := [4]f32{fill.r, fill.g, fill.b, fill.a*opacity}
	native_solid_append_quad(vertices, base.x, base.y, base.x+base.w, base.y+base.h, base_color)

	bevel_width := min(material.bevel_width, min(base.w, base.h)*0.5)
	if bevel_width > 0 && material.bevel_strength > 0 {
		top := native_solid_material_edge_tint(fill, physical_height, 0, -1, material.bevel_strength, 0.22)
		left := native_solid_material_edge_tint(fill, physical_height, -1, 0, material.bevel_strength, 0.22)
		bottom := native_solid_material_edge_tint(fill, physical_height, 0, 1, material.bevel_strength, 0.22)
		right := native_solid_material_edge_tint(fill, physical_height, 1, 0, material.bevel_strength, 0.22)
		top[3] *= opacity
		left[3] *= opacity
		bottom[3] *= opacity
		right[3] *= opacity
		native_solid_append_material_edge(vertices, base.x, base.y, base.x+base.w, base.y+bevel_width, top)
		native_solid_append_material_edge(vertices, base.x, base.y+bevel_width, base.x+bevel_width, base.y+base.h-bevel_width, left)
		native_solid_append_material_edge(vertices, base.x, base.y+base.h-bevel_width, base.x+base.w, base.y+base.h, bottom)
		native_solid_append_material_edge(vertices, base.x+base.w-bevel_width, base.y+bevel_width, base.x+base.w, base.y+base.h-bevel_width, right)
	}
	if material.inner_shadow_strength > 0 {
		inner_width := min(max(material.bevel_width, 1), min(base.w, base.h)*0.5)
		inner_top := native_solid_material_edge_tint(fill, physical_height, 0, -1, material.inner_shadow_strength, 0.18)
		inner_left := native_solid_material_edge_tint(fill, physical_height, -1, 0, material.inner_shadow_strength, 0.18)
		inner_bottom := native_solid_material_edge_tint(fill, physical_height, 0, 1, material.inner_shadow_strength, 0.18)
		inner_right := native_solid_material_edge_tint(fill, physical_height, 1, 0, material.inner_shadow_strength, 0.18)
		inner_top[3] *= opacity
		inner_left[3] *= opacity
		inner_bottom[3] *= opacity
		inner_right[3] *= opacity
		native_solid_append_material_edge(vertices, base.x+bevel_width, base.y+bevel_width, base.x+base.w-bevel_width, base.y+bevel_width+inner_width, inner_top)
		native_solid_append_material_edge(vertices, base.x+bevel_width, base.y+bevel_width+inner_width, base.x+bevel_width+inner_width, base.y+base.h-bevel_width, inner_left)
		native_solid_append_material_edge(vertices, base.x+bevel_width, base.y+base.h-bevel_width-inner_width, base.x+base.w-bevel_width, base.y+base.h-bevel_width, inner_bottom)
		native_solid_append_material_edge(vertices, base.x+base.w-bevel_width-inner_width, base.y+bevel_width+inner_width, base.x+base.w-bevel_width, base.y+base.h-bevel_width-inner_width, inner_right)
	}
}
