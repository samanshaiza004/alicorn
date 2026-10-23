package alicorn_sdl_gpu

import "core:math"
import alicorn "../../runtime"

// Analytic relief uses a fixed upper-left light. Directional edge response is
// intentionally small and deterministic; physical height changes its optical
// sign/strength but never the paint command's compositor depth or order.
NATIVE_MATERIAL_LIGHT_COMPONENT :: 0.70710678118
NATIVE_ROUNDED_CORNER_SEGMENTS :: 8
NATIVE_ROUNDED_CONTOUR_POINTS :: 4 * NATIVE_ROUNDED_CORNER_SEGMENTS + 3
NATIVE_ROUNDED_FILL_VERTICES :: NATIVE_ROUNDED_CONTOUR_POINTS * 9
NATIVE_ROUNDED_RING_VERTICES :: NATIVE_ROUNDED_CONTOUR_POINTS * 6
NATIVE_ROUNDED_ANTIALIAS_FRINGE :: 0.75

// Native material effects are expanded into ordinary surface vertices. The
// flat path remains one quad per Surface_Paint and needs no material geometry.
native_solid_shape_is_rounded :: proc(shape: alicorn.Surface_Shape) -> bool {
	return shape.kind == .Rounded_Rectangle && shape.corner_radius > 0 && shape.corner_radius == shape.corner_radius
}

native_solid_material_vertex_count :: proc(
	material: alicorn.Style_Material,
	physical_height: f32,
	shape := alicorn.Surface_Shape{kind=.Rectangle},
	stroke := alicorn.Paint_Stroke{},
) -> int {
	if native_solid_shape_is_rounded(shape) {
		count := NATIVE_ROUNDED_FILL_VERTICES
		if material.kind == .Analytic_Relief && physical_height != 0 {
			if physical_height > 0 && material.outer_shadow_strength > 0 && material.outer_shadow_radius > 0 { count += NATIVE_ROUNDED_FILL_VERTICES*2 }
			if material.bevel_strength > 0 && material.bevel_width > 0 { count += NATIVE_ROUNDED_RING_VERTICES }
			if material.inner_shadow_strength > 0 { count += NATIVE_ROUNDED_RING_VERTICES }
		}
		if stroke.width > 0 { count += NATIVE_ROUNDED_RING_VERTICES*3 }
		return count
	}
	count := 6 // the filled surface itself
	if material.kind != .Analytic_Relief || physical_height == 0 { return count }
	if physical_height > 0 && material.outer_shadow_strength > 0 && material.outer_shadow_radius > 0 { count += 12 }
	if material.bevel_strength > 0 && material.bevel_width > 0 { count += 24 }
	if material.inner_shadow_strength > 0 { count += 24 }
	return count
}

native_solid_rounded_contour_point :: proc(bounds: alicorn.Rect, radius, inset: f32, index: int) -> (point, normal: [2]f32) {
	contour_index := index % NATIVE_ROUNDED_CONTOUR_POINTS
	corner := contour_index / (NATIVE_ROUNDED_CORNER_SEGMENTS + 1)
	step := contour_index % (NATIVE_ROUNDED_CORNER_SEGMENTS + 1)
	left, top := bounds.x+inset, bounds.y+inset
	width, height := max(bounds.w-2*inset, 0), max(bounds.h-2*inset, 0)
	corner_radius := clamp(radius-inset, 0, min(width, height)*0.5)
	centers := [4][2]f32{
		{left+corner_radius, top+corner_radius},
		{left+width-corner_radius, top+corner_radius},
		{left+width-corner_radius, top+height-corner_radius},
		{left+corner_radius, top+height-corner_radius},
	}
	starts := [4]f32{3.141592653589793, 4.71238898038469, 0, 1.5707963267948966}
	angle := starts[corner] + f32(step)*1.5707963267948966/f32(NATIVE_ROUNDED_CORNER_SEGMENTS)
	normal = {math.cos(angle), math.sin(angle)}
	point = {centers[corner][0]+normal[0]*corner_radius, centers[corner][1]+normal[1]*corner_radius}
	return
}

native_solid_append_rounded_ring :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	bounds: alicorn.Rect,
	radius, outer_inset, inner_inset: f32,
	outer_color, inner_color: [4]f32,
) {
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		outer_a, _ := native_solid_rounded_contour_point(bounds, radius, outer_inset, i)
		outer_b, _ := native_solid_rounded_contour_point(bounds, radius, outer_inset, next)
		inner_a, _ := native_solid_rounded_contour_point(bounds, radius, inner_inset, i)
		inner_b, _ := native_solid_rounded_contour_point(bounds, radius, inner_inset, next)
		append(vertices,
			Native_Text_Vertex{[3]f32{outer_a[0], outer_a[1], 0}, outer_color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{outer_b[0], outer_b[1], 0}, outer_color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_b[0], inner_b[1], 0}, inner_color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{outer_a[0], outer_a[1], 0}, outer_color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_b[0], inner_b[1], 0}, inner_color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_a[0], inner_a[1], 0}, inner_color, {0.5, 0.5}},
		)
	}
}

native_solid_append_rounded_tinted_ring :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	bounds: alicorn.Rect,
	radius, outer_inset, inner_inset: f32,
	fill: alicorn.Color,
	physical_height: f32,
	strength, max_amount, opacity: f32,
) {
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		outer_a, normal_a := native_solid_rounded_contour_point(bounds, radius, outer_inset, i)
		outer_b, normal_b := native_solid_rounded_contour_point(bounds, radius, outer_inset, next)
		inner_a, _ := native_solid_rounded_contour_point(bounds, radius, inner_inset, i)
		inner_b, _ := native_solid_rounded_contour_point(bounds, radius, inner_inset, next)
		color_a := native_solid_material_edge_tint(fill, physical_height, normal_a[0], normal_a[1], strength, max_amount)
		color_b := native_solid_material_edge_tint(fill, physical_height, normal_b[0], normal_b[1], strength, max_amount)
		color_a[3] *= opacity
		color_b[3] *= opacity
		append(vertices,
			Native_Text_Vertex{[3]f32{outer_a[0], outer_a[1], 0}, color_a, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{outer_b[0], outer_b[1], 0}, color_b, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_b[0], inner_b[1], 0}, color_b, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{outer_a[0], outer_a[1], 0}, color_a, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_b[0], inner_b[1], 0}, color_b, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_a[0], inner_a[1], 0}, color_a, {0.5, 0.5}},
		)
	}
}

native_solid_append_rounded_fill :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	bounds: alicorn.Rect,
	radius: f32,
	color: [4]f32,
) {
	if bounds.w <= 0 || bounds.h <= 0 || color[3] <= 0 { return }
	center := [2]f32{bounds.x+bounds.w*0.5, bounds.y+bounds.h*0.5}
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		a, _ := native_solid_rounded_contour_point(bounds, radius, 0, i)
		b, _ := native_solid_rounded_contour_point(bounds, radius, 0, next)
		append(vertices,
			Native_Text_Vertex{[3]f32{center[0], center[1], 0}, color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{a[0], a[1], 0}, color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{b[0], b[1], 0}, color, {0.5, 0.5}},
		)
	}
	transparent := color
	transparent[3] = 0
	native_solid_append_rounded_ring(vertices, bounds, radius, -NATIVE_ROUNDED_ANTIALIAS_FRINGE, 0, transparent, color)
}

native_solid_append_rounded_material_surface :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	base, shadow: alicorn.Rect,
	fill: alicorn.Color,
	material: alicorn.Style_Material,
	physical_height, opacity: f32,
	shape: alicorn.Surface_Shape,
	stroke := alicorn.Paint_Stroke{},
) {
	if base.w <= 0 || base.h <= 0 { return }
	radius := clamp(shape.corner_radius, 0, min(base.w, base.h)*0.5)
	height_factor := native_solid_material_height_factor(physical_height)
	if material.kind == .Analytic_Relief && physical_height > 0 && material.outer_shadow_radius > 0 && material.outer_shadow_strength > 0 {
		expand := max(material.outer_shadow_radius, 0)
		outer := [4]f32{0, 0, 0, material.outer_shadow_strength*0.07*height_factor*opacity}
		middle := [4]f32{0, 0, 0, material.outer_shadow_strength*0.12*height_factor*opacity}
		native_solid_append_rounded_fill(vertices, shadow, radius+expand, outer)
		mid := alicorn.Rect{
			shadow.x+(base.x-shadow.x)*0.5,
			shadow.y+(base.y-shadow.y)*0.5,
			shadow.w-(base.x-shadow.x)*0.5-(shadow.x+shadow.w-base.x-base.w)*0.5,
			shadow.h-(base.y-shadow.y)*0.5-(shadow.y+shadow.h-base.y-base.h)*0.5,
		}
		native_solid_append_rounded_fill(vertices, mid, radius+expand*0.5, middle)
	}

	base_color := [4]f32{fill.r, fill.g, fill.b, fill.a*opacity}
	native_solid_append_rounded_fill(vertices, base, radius, base_color)
	bevel_width := min(max(material.bevel_width, 0), min(base.w, base.h)*0.5)
	if material.kind == .Analytic_Relief && physical_height != 0 {
		if bevel_width > 0 && material.bevel_strength > 0 {
			native_solid_append_rounded_tinted_ring(vertices, base, radius, 0, bevel_width,
				fill, physical_height, material.bevel_strength, 0.22, opacity)
		}
		if material.inner_shadow_strength > 0 {
			inner_width := min(max(bevel_width, 1), min(base.w, base.h)*0.5)
			native_solid_append_rounded_tinted_ring(vertices, base, radius, bevel_width, bevel_width+inner_width,
				fill, physical_height, material.inner_shadow_strength, 0.18, opacity)
		}
	}

	if stroke.width > 0 {
		stroke_color := [4]f32{stroke.color.r, stroke.color.g, stroke.color.b, stroke.color.a*opacity}
		transparent_stroke := stroke_color
		transparent_stroke[3] = 0
		half_width := stroke.width*0.5
		native_solid_append_rounded_ring(vertices, base, radius, -half_width-NATIVE_ROUNDED_ANTIALIAS_FRINGE, -half_width, transparent_stroke, stroke_color)
		native_solid_append_rounded_ring(vertices, base, radius, -half_width, half_width, stroke_color, stroke_color)
		native_solid_append_rounded_ring(vertices, base, radius, half_width, half_width+NATIVE_ROUNDED_ANTIALIAS_FRINGE, stroke_color, transparent_stroke)
	}

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
