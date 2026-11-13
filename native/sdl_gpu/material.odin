package alicorn_sdl_gpu

import "core:math"
import alicorn "../../runtime"

// Analytic relief uses a fixed upper-left light. Directional edge response is
// intentionally small and deterministic; physical height changes its optical
// sign/strength but never the paint command's compositor depth or order.
NATIVE_MATERIAL_LIGHT_COMPONENT :: 0.70710678118
NATIVE_ROUNDED_CORNER_SEGMENTS :: 8
NATIVE_ROUNDED_CONTOUR_POINTS :: 4 * (NATIVE_ROUNDED_CORNER_SEGMENTS + 1)
NATIVE_ROUNDED_FILL_VERTICES :: NATIVE_ROUNDED_CONTOUR_POINTS * 9
NATIVE_ROUNDED_RING_VERTICES :: NATIVE_ROUNDED_CONTOUR_POINTS * 6
NATIVE_ROUNDED_ANTIALIAS_FRINGE :: 0.75
NATIVE_CONNECTED_TAB_STEPS :: 20
NATIVE_CONNECTED_TAB_VERTICES :: NATIVE_CONNECTED_TAB_STEPS*18+6
NATIVE_VECTOR_CURVE_MIN_SEGMENTS :: 16
NATIVE_VECTOR_CURVE_MAX_SEGMENTS :: 96
NATIVE_VECTOR_ANTIALIAS_FRINGE :: 0.75

// Native material effects are expanded into ordinary surface vertices. The
// flat path remains one quad per Surface_Paint and needs no material geometry.
native_solid_shape_is_rounded :: proc(shape: alicorn.Surface_Shape) -> bool {
	return (shape.kind == .Rounded_Rectangle || shape.kind == .Rounded_Rectangle_Per_Corner) &&
	       alicorn.surface_shape_has_rounded_corners(shape)
}

native_solid_material_vertex_count :: proc(
	material: alicorn.Style_Material,
	physical_height: f32,
	shape := alicorn.Surface_Shape{kind=.Rectangle},
	stroke := alicorn.Paint_Stroke{},
	top_edge_gap := [2]f32{},
	bounds := alicorn.Rect{},
	scale_x: f32 = 1,
	scale_y: f32 = 1,
	fill := alicorn.Color{1, 1, 1, 1},
) -> int {
	if shape.kind == .Connected_Tab { return NATIVE_CONNECTED_TAB_VERTICES }
	if shape.kind == .Circle {
		segments := native_solid_vector_segments(shape, bounds, scale_x, scale_y)
		fill_vertices := segments*9 if fill.a > 0 else 0
		stroke_vertices := segments*18 if stroke.width > 0 else 0
		return fill_vertices + stroke_vertices
	}
	if shape.kind == .Arc || shape.kind == .Cubic_Bezier {
		segments := native_solid_vector_segments(shape, bounds, scale_x, scale_y)
		if segments < 2 || stroke.width <= 0 { return 0 }
		return segments*18+12
	}
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
	if stroke.width > 0 { count += 24 }
	if top_edge_gap[1] > top_edge_gap[0] && stroke.width > 0 { count += 6 }
	if material.kind != .Analytic_Relief || physical_height == 0 { return count }
	if physical_height > 0 && material.outer_shadow_strength > 0 && material.outer_shadow_radius > 0 { count += 12 }
	if material.bevel_strength > 0 && material.bevel_width > 0 { count += 24 }
	if material.inner_shadow_strength > 0 { count += 24 }
	if top_edge_gap[1] > top_edge_gap[0] {
		if material.bevel_strength > 0 && material.bevel_width > 0 { count += 6 }
		if material.inner_shadow_strength > 0 { count += 6 }
	}
	return count
}

// Curved paths use a pixel-sensitive but strictly bounded segment budget.
// Ordinary rectangles, lines and rounded rectangles never enter this path.
native_solid_vector_segments :: proc(shape: alicorn.Surface_Shape, bounds: alicorn.Rect, scale_x, scale_y: f32) -> int {
	maximum_scale := max(scale_x, scale_y)
	length_pixels: f32
	#partial switch shape.kind {
	case .Circle:
		length_pixels = min(bounds.w, bounds.h)*0.5*maximum_scale*6.2831853
	case .Arc:
		length_pixels = shape.arc.radius*min(bounds.w, bounds.h)*abs(shape.arc.sweep_angle)*maximum_scale
	case .Cubic_Bezier:
		points := shape.bezier.points
		for index in 0..<3 {
			dx := (points[index+1][0]-points[index][0])*bounds.w*scale_x
			dy := (points[index+1][1]-points[index][1])*bounds.h*scale_y
			length_pixels += math.sqrt(dx*dx+dy*dy)
		}
	case:
		return 0
	}
	if length_pixels <= 0 { return 0 }
	segments := int(math.ceil(6.2831853*math.sqrt(max(length_pixels, 1))))
	return clamp(segments, NATIVE_VECTOR_CURVE_MIN_SEGMENTS, NATIVE_VECTOR_CURVE_MAX_SEGMENTS)
}

native_solid_shape_vertex :: proc(point: [2]f32, color: [4]f32) -> Native_Text_Vertex {
	return Native_Text_Vertex{[3]f32{point[0], point[1], 0}, color, [2]f32{0.5, 0.5}}
}

native_solid_append_triangle :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	a, b, c: [2]f32,
	color_a, color_b, color_c: [4]f32,
) {
	append(vertices,
		native_solid_shape_vertex(a, color_a),
		native_solid_shape_vertex(b, color_b),
		native_solid_shape_vertex(c, color_c),
	)
}

native_solid_append_circle_ring :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	cx, cy, rx, ry, inner_radius, outer_radius: f32,
	inner_color, outer_color: [4]f32,
	segments: int,
) {
	if segments < 3 || rx <= 0 || ry <= 0 || outer_radius <= inner_radius { return }
	for index in 0..<segments {
		a0 := 6.2831853*f32(index)/f32(segments)
		a1 := 6.2831853*f32(index+1)/f32(segments)
		inner_a := [2]f32{cx+math.cos(a0)*rx*inner_radius, cy+math.sin(a0)*ry*inner_radius}
		inner_b := [2]f32{cx+math.cos(a1)*rx*inner_radius, cy+math.sin(a1)*ry*inner_radius}
		outer_a := [2]f32{cx+math.cos(a0)*rx*outer_radius, cy+math.sin(a0)*ry*outer_radius}
		outer_b := [2]f32{cx+math.cos(a1)*rx*outer_radius, cy+math.sin(a1)*ry*outer_radius}
		native_solid_append_triangle(vertices, inner_a, inner_b, outer_b, inner_color, inner_color, outer_color)
		native_solid_append_triangle(vertices, inner_a, outer_b, outer_a, inner_color, outer_color, outer_color)
	}
}

native_solid_append_circle_surface :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	bounds: alicorn.Rect,
	fill: alicorn.Color,
	stroke: alicorn.Paint_Stroke,
	placement: alicorn.Paint_Stroke_Placement,
	opacity, scale_x, scale_y: f32,
	segments: int,
) {
	if bounds.w <= 0 || bounds.h <= 0 || segments < 3 { return }
	cx, cy := bounds.x+bounds.w*0.5, bounds.y+bounds.h*0.5
	radius := min(bounds.w, bounds.h)*0.5
	rx, ry := radius*scale_x, radius*scale_y
	fringe := f32(NATIVE_VECTOR_ANTIALIAS_FRINGE)
	fill_color := [4]f32{fill.r, fill.g, fill.b, fill.a*opacity}
	transparent_fill := fill_color
	transparent_fill[3] = 0
	if fill.a > 0 {
		core_scale := max(1-fringe/max(radius*max(scale_x, scale_y), 0.001), 0)
		pixel_cx, pixel_cy := cx*scale_x, cy*scale_y
		center := [2]f32{pixel_cx, pixel_cy}
		for index in 0..<segments {
			a0 := 6.2831853*f32(index)/f32(segments)
			a1 := 6.2831853*f32(index+1)/f32(segments)
			p0 := [2]f32{pixel_cx+math.cos(a0)*rx*core_scale, pixel_cy+math.sin(a0)*ry*core_scale}
			p1 := [2]f32{pixel_cx+math.cos(a1)*rx*core_scale, pixel_cy+math.sin(a1)*ry*core_scale}
			native_solid_append_triangle(vertices, center, p0, p1, fill_color, fill_color, fill_color)
		}
		inner_scale := core_scale
		outer_scale := 1+fringe/max(radius*max(scale_x, scale_y), 0.001)
		native_solid_append_circle_ring(vertices, pixel_cx, pixel_cy, rx, ry,
			inner_scale, outer_scale, fill_color, transparent_fill, segments)
	}
	if stroke.width <= 0 { return }
	stroke_color := [4]f32{stroke.color.r, stroke.color.g, stroke.color.b, stroke.color.a*opacity}
	transparent_stroke := stroke_color
	transparent_stroke[3] = 0
	width := stroke.width*max(scale_x, scale_y)
	inner, outer := radius*max(scale_x, scale_y), radius*max(scale_x, scale_y)
	switch placement {
	case .Centered:
		inner -= width*0.5
		outer += width*0.5
	case .Inside:
		inner -= width
	case .Outside:
		outer += width
	case .Count:
		return
	case:
		return
	}
	inner = max(inner, 0)
	nominal_radius := max(radius*max(scale_x, scale_y), 0.001)
	inner_scale := inner/nominal_radius
	outer_scale := outer/nominal_radius
	fringe_scale := fringe/nominal_radius
	native_solid_append_circle_ring(vertices, cx*scale_x, cy*scale_y, rx, ry,
		inner_scale, outer_scale, stroke_color, stroke_color, segments)
	if outer > 0 {
		native_solid_append_circle_ring(vertices, cx*scale_x, cy*scale_y, rx, ry,
			outer_scale, outer_scale+fringe_scale, stroke_color, transparent_stroke, segments)
	}
	if inner > 0 {
		native_solid_append_circle_ring(vertices, cx*scale_x, cy*scale_y, rx, ry,
			max(inner_scale-fringe_scale, 0), inner_scale, transparent_stroke, stroke_color, segments)
	}
}

native_solid_append_stroked_path :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	points: [][2]f32,
	stroke: alicorn.Paint_Stroke,
	opacity: f32,
) {
	if len(points) < 2 || stroke.width <= 0 { return }
	half := stroke.width*0.5
	fringe := f32(NATIVE_VECTOR_ANTIALIAS_FRINGE)
	color := [4]f32{stroke.color.r, stroke.color.g, stroke.color.b, stroke.color.a*opacity}
	transparent := color
	transparent[3] = 0
	left: [NATIVE_VECTOR_CURVE_MAX_SEGMENTS+1][2]f32
	right: [NATIVE_VECTOR_CURVE_MAX_SEGMENTS+1][2]f32
	for index in 0..<len(points) {
		previous := points[max(index-1, 0)]
		next := points[min(index+1, len(points)-1)]
		dx, dy := next[0]-previous[0], next[1]-previous[1]
		length := math.sqrt(dx*dx+dy*dy)
		if length <= 0.0001 {
			dx, dy = next[0]-points[index][0], next[1]-points[index][1]
			length = math.sqrt(dx*dx+dy*dy)
		}
		if length <= 0.0001 {
			dx, dy = points[index][0]-previous[0], points[index][1]-previous[1]
			length = math.sqrt(dx*dx+dy*dy)
		}
		if length <= 0.0001 { return }
		normal := [2]f32{-dy/length, dx/length}
		left[index] = [2]f32{points[index][0]+normal[0]*half, points[index][1]+normal[1]*half}
		right[index] = [2]f32{points[index][0]-normal[0]*half, points[index][1]-normal[1]*half}
	}
	for index in 0..<len(points)-1 {
		p0, p1 := left[index], left[index+1]
		q0, q1 := right[index], right[index+1]
		native_solid_append_triangle(vertices, p0, q0, q1, color, color, color)
		native_solid_append_triangle(vertices, p0, q1, p1, color, color, color)
		previous_normal := [2]f32{(p0[0]-q0[0])/(2*half), (p0[1]-q0[1])/(2*half)}
		next_normal := [2]f32{(p1[0]-q1[0])/(2*half), (p1[1]-q1[1])/(2*half)}
		outer_p0 := [2]f32{p0[0]+previous_normal[0]*fringe, p0[1]+previous_normal[1]*fringe}
		outer_p1 := [2]f32{p1[0]+next_normal[0]*fringe, p1[1]+next_normal[1]*fringe}
		outer_q0 := [2]f32{q0[0]-previous_normal[0]*fringe, q0[1]-previous_normal[1]*fringe}
		outer_q1 := [2]f32{q1[0]-next_normal[0]*fringe, q1[1]-next_normal[1]*fringe}
		native_solid_append_triangle(vertices, p0, p1, outer_p1, color, color, transparent)
		native_solid_append_triangle(vertices, p0, outer_p1, outer_p0, color, transparent, transparent)
		native_solid_append_triangle(vertices, q0, outer_q1, q1, color, transparent, color)
		native_solid_append_triangle(vertices, q0, outer_q0, outer_q1, color, transparent, transparent)
	}
	first_delta := [2]f32{points[1][0]-points[0][0], points[1][1]-points[0][1]}
	first_length := math.sqrt(first_delta[0]*first_delta[0]+first_delta[1]*first_delta[1])
	last_delta := [2]f32{points[len(points)-1][0]-points[len(points)-2][0], points[len(points)-1][1]-points[len(points)-2][1]}
	last_length := math.sqrt(last_delta[0]*last_delta[0]+last_delta[1]*last_delta[1])
	if first_length > 0.0001 {
		direction := [2]f32{first_delta[0]/first_length, first_delta[1]/first_length}
		outer_left := [2]f32{left[0][0]-direction[0]*fringe, left[0][1]-direction[1]*fringe}
		outer_right := [2]f32{right[0][0]-direction[0]*fringe, right[0][1]-direction[1]*fringe}
		native_solid_append_triangle(vertices, left[0], right[0], outer_right, color, color, transparent)
		native_solid_append_triangle(vertices, left[0], outer_right, outer_left, color, transparent, transparent)
	}
	if last_length > 0.0001 {
		direction := [2]f32{last_delta[0]/last_length, last_delta[1]/last_length}
		last := len(points)-1
		outer_left := [2]f32{left[last][0]+direction[0]*fringe, left[last][1]+direction[1]*fringe}
		outer_right := [2]f32{right[last][0]+direction[0]*fringe, right[last][1]+direction[1]*fringe}
		native_solid_append_triangle(vertices, left[last], outer_right, right[last], color, transparent, color)
		native_solid_append_triangle(vertices, left[last], outer_left, outer_right, color, transparent, transparent)
	}
}

// Bounded component-private contour: two cubic shoulders joined by a flat
// crown and an open baseline. Every vertex stays in the tab's own allocation,
// so its decoration cannot cover an adjacent label or close target.
native_solid_append_connected_tab :: proc(vertices: ^[dynamic]Native_Text_Vertex, bounds: alicorn.Rect, fill: alicorn.Color, opacity: f32, scale: f32) {
	if bounds.w <= 0 || bounds.h <= 0 { return }
	shoulder, crown := alicorn.connected_tab_contour_insets(bounds.w, bounds.h, scale)
	top := bounds.y+crown
	bottom := bounds.y+bounds.h
	color := [4]f32{fill.r, fill.g, fill.b, fill.a*opacity}
	transparent := color
	transparent[3] = 0
	fringe := f32(NATIVE_ROUNDED_ANTIALIAS_FRINGE)
	previous_x, previous_y := bounds.x, bottom
	for step in 1..=NATIVE_CONNECTED_TAB_STEPS {
		t := f32(step)/f32(NATIVE_CONNECTED_TAB_STEPS)
		u := 1-t
		// Cubic control points give horizontal tangents at both endpoints.
		x := bounds.x+shoulder*(3*u*u*t*0.48+3*u*t*t*0.52+t*t*t)
		y := bottom+(top-bottom)*(3*u*t*t+t*t*t)
		previous_right := bounds.x+bounds.w-(previous_x-bounds.x)
		right := bounds.x+bounds.w-(x-bounds.x)
		uv := [2]f32{0.5,0.5}
		append(vertices,
			Native_Text_Vertex{{previous_x,previous_y,0},color,uv}, Native_Text_Vertex{{previous_right,previous_y,0},color,uv}, Native_Text_Vertex{{right,y,0},color,uv},
			Native_Text_Vertex{{previous_x,previous_y,0},color,uv}, Native_Text_Vertex{{right,y,0},color,uv}, Native_Text_Vertex{{x,y,0},color,uv},
			Native_Text_Vertex{{previous_x,previous_y,0},color,uv}, Native_Text_Vertex{{x,y,0},color,uv}, Native_Text_Vertex{{x-fringe,y,0},transparent,uv},
			Native_Text_Vertex{{previous_x,previous_y,0},color,uv}, Native_Text_Vertex{{x-fringe,y,0},transparent,uv}, Native_Text_Vertex{{previous_x-fringe,previous_y,0},transparent,uv},
			Native_Text_Vertex{{previous_right,previous_y,0},color,uv}, Native_Text_Vertex{{right+fringe,y,0},transparent,uv}, Native_Text_Vertex{{right,y,0},color,uv},
			Native_Text_Vertex{{previous_right,previous_y,0},color,uv}, Native_Text_Vertex{{previous_right+fringe,previous_y,0},transparent,uv}, Native_Text_Vertex{{right+fringe,y,0},transparent,uv},
		)
		previous_x, previous_y = x,y
	}
	uv := [2]f32{0.5,0.5}
	left, right := bounds.x+shoulder, bounds.x+bounds.w-shoulder
	append(vertices,
		Native_Text_Vertex{{left,top,0},color,uv}, Native_Text_Vertex{{right,top,0},color,uv}, Native_Text_Vertex{{right,top-fringe,0},transparent,uv},
		Native_Text_Vertex{{left,top,0},color,uv}, Native_Text_Vertex{{right,top-fringe,0},transparent,uv}, Native_Text_Vertex{{left,top-fringe,0},transparent,uv},
	)
}

native_solid_corner_radii_adjust :: proc(radii: alicorn.Surface_Corner_Radii, amount: f32) -> alicorn.Surface_Corner_Radii {
	adjust := proc(radius, amount: f32) -> f32 { return max(radius+amount, 0) if radius > 0 else 0 }
	return alicorn.Surface_Corner_Radii{
		adjust(radii.top_left, amount),
		adjust(radii.top_right, amount),
		adjust(radii.bottom_right, amount),
		adjust(radii.bottom_left, amount),
	}
}

native_solid_rounded_contour_radii :: proc(bounds: alicorn.Rect, radii: alicorn.Surface_Corner_Radii, inset: f32) -> alicorn.Surface_Corner_Radii {
	width, height := max(bounds.w-2*inset, 0), max(bounds.h-2*inset, 0)
	return alicorn.surface_corner_radii_normalize(native_solid_corner_radii_adjust(radii, -inset), width, height)
}

native_solid_rounded_contour_point :: proc(bounds: alicorn.Rect, radii: alicorn.Surface_Corner_Radii, inset: f32, index: int) -> (point, normal: [2]f32) {
	contour_index := index % NATIVE_ROUNDED_CONTOUR_POINTS
	corner := contour_index / (NATIVE_ROUNDED_CORNER_SEGMENTS + 1)
	step := contour_index % (NATIVE_ROUNDED_CORNER_SEGMENTS + 1)
	left, top := bounds.x+inset, bounds.y+inset
	width, height := max(bounds.w-2*inset, 0), max(bounds.h-2*inset, 0)
	corner_radii := [4]f32{radii.top_left, radii.top_right, radii.bottom_right, radii.bottom_left}
	corner_radius := corner_radii[corner]
	centers := [4][2]f32{
		{left+corner_radius, top+corner_radius},
		{left+width-corner_radii[1], top+corner_radius},
		{left+width-corner_radii[2], top+height-corner_radius},
		{left+corner_radii[3], top+height-corner_radii[3]},
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
	radii: alicorn.Surface_Corner_Radii,
	outer_inset, inner_inset: f32,
	outer_color, inner_color: [4]f32,
) {
	outer_radii := native_solid_rounded_contour_radii(bounds, radii, outer_inset)
	inner_radii := native_solid_rounded_contour_radii(bounds, radii, inner_inset)
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		outer_a, _ := native_solid_rounded_contour_point(bounds, outer_radii, outer_inset, i)
		outer_b, _ := native_solid_rounded_contour_point(bounds, outer_radii, outer_inset, next)
		inner_a, _ := native_solid_rounded_contour_point(bounds, inner_radii, inner_inset, i)
		inner_b, _ := native_solid_rounded_contour_point(bounds, inner_radii, inner_inset, next)
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
	radii: alicorn.Surface_Corner_Radii,
	outer_inset, inner_inset: f32,
	fill: alicorn.Color,
	physical_height: f32,
	strength, max_amount, opacity: f32,
) {
	outer_radii := native_solid_rounded_contour_radii(bounds, radii, outer_inset)
	inner_radii := native_solid_rounded_contour_radii(bounds, radii, inner_inset)
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		outer_a, normal_a := native_solid_rounded_contour_point(bounds, outer_radii, outer_inset, i)
		outer_b, normal_b := native_solid_rounded_contour_point(bounds, outer_radii, outer_inset, next)
		inner_a, _ := native_solid_rounded_contour_point(bounds, inner_radii, inner_inset, i)
		inner_b, _ := native_solid_rounded_contour_point(bounds, inner_radii, inner_inset, next)
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
	radii: alicorn.Surface_Corner_Radii,
	color: [4]f32,
) {
	if bounds.w <= 0 || bounds.h <= 0 || color[3] <= 0 { return }
	center := [2]f32{bounds.x+bounds.w*0.5, bounds.y+bounds.h*0.5}
	contour_radii := native_solid_rounded_contour_radii(bounds, radii, 0)
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		a, _ := native_solid_rounded_contour_point(bounds, contour_radii, 0, i)
		b, _ := native_solid_rounded_contour_point(bounds, contour_radii, 0, next)
		append(vertices,
			Native_Text_Vertex{[3]f32{center[0], center[1], 0}, color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{a[0], a[1], 0}, color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{b[0], b[1], 0}, color, {0.5, 0.5}},
		)
	}
	transparent := color
	transparent[3] = 0
	native_solid_append_rounded_ring(vertices, bounds, radii, -NATIVE_ROUNDED_ANTIALIAS_FRINGE, 0, transparent, color)
}

native_solid_gradient_color_at :: proc(
	start, end: alicorn.Color,
	axis: alicorn.Surface_Gradient_Axis,
	bounds: alicorn.Rect,
	x, y, opacity: f32,
	inverse_extent: f32,
) -> [4]f32 {
	t := f32(0)
	if axis == .Horizontal {
		t = clamp((x-bounds.x)*inverse_extent, 0, 1)
	} else if axis == .Vertical {
		t = clamp((y-bounds.y)*inverse_extent, 0, 1)
	}
	return [4]f32{
		start.r+(end.r-start.r)*t,
		start.g+(end.g-start.g)*t,
		start.b+(end.b-start.b)*t,
		(start.a+(end.a-start.a)*t)*opacity,
	}
}

native_solid_append_gradient_quad :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	bounds: alicorn.Rect,
	start: alicorn.Color,
	gradient: alicorn.Surface_Gradient,
	opacity: f32,
) {
	if bounds.w <= 0 || bounds.h <= 0 || start.a <= 0 { return }
	if gradient.axis == .None {
		native_solid_append_quad(vertices, bounds.x, bounds.y, bounds.x+bounds.w, bounds.y+bounds.h,
			[4]f32{start.r, start.g, start.b, start.a*opacity})
		return
	}
	if !alicorn.Surface_Gradient_Is_Valid(start, gradient) {
		native_solid_append_quad(vertices, bounds.x, bounds.y, bounds.x+bounds.w, bounds.y+bounds.h,
			[4]f32{start.r, start.g, start.b, start.a*opacity})
		return
	}
	x0, y0 := bounds.x, bounds.y
	x1, y1 := bounds.x+bounds.w, bounds.y+bounds.h
	inverse_extent := f32(1)/bounds.w
	if gradient.axis == .Vertical { inverse_extent = f32(1)/bounds.h }
	color00 := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, x0, y0, opacity, inverse_extent)
	color10 := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, x1, y0, opacity, inverse_extent)
	color11 := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, x1, y1, opacity, inverse_extent)
	color01 := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, x0, y1, opacity, inverse_extent)
	uv := [2]f32{0.5, 0.5}
	append(vertices,
		Native_Text_Vertex{[3]f32{x0, y0, 0}, color00, uv},
		Native_Text_Vertex{[3]f32{x1, y0, 0}, color10, uv},
		Native_Text_Vertex{[3]f32{x1, y1, 0}, color11, uv},
		Native_Text_Vertex{[3]f32{x0, y0, 0}, color00, uv},
		Native_Text_Vertex{[3]f32{x1, y1, 0}, color11, uv},
		Native_Text_Vertex{[3]f32{x0, y1, 0}, color01, uv},
	)
}

native_solid_append_rounded_gradient_fill :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	bounds: alicorn.Rect,
	radii: alicorn.Surface_Corner_Radii,
	start: alicorn.Color,
	gradient: alicorn.Surface_Gradient,
	opacity: f32,
) {
	if bounds.w <= 0 || bounds.h <= 0 || start.a <= 0 { return }
	contour_radii := alicorn.surface_corner_radii_normalize(radii, bounds.w, bounds.h)
	if gradient.axis == .None || !alicorn.Surface_Gradient_Is_Valid(start, gradient) {
		native_solid_append_rounded_fill(vertices, bounds, contour_radii,
			[4]f32{start.r, start.g, start.b, start.a*opacity})
		return
	}
	inverse_extent := f32(1)/bounds.w
	if gradient.axis == .Vertical { inverse_extent = f32(1)/bounds.h }
	center := [2]f32{bounds.x+bounds.w*0.5, bounds.y+bounds.h*0.5}
	center_color := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, center[0], center[1], opacity, inverse_extent)
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		a, _ := native_solid_rounded_contour_point(bounds, contour_radii, 0, i)
		b, _ := native_solid_rounded_contour_point(bounds, contour_radii, 0, next)
		color_a := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, a[0], a[1], opacity, inverse_extent)
		color_b := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, b[0], b[1], opacity, inverse_extent)
		append(vertices,
			Native_Text_Vertex{[3]f32{center[0], center[1], 0}, center_color, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{a[0], a[1], 0}, color_a, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{b[0], b[1], 0}, color_b, {0.5, 0.5}},
		)
	}
	// Preserve the existing antialias fringe topology and vertex count while
	// carrying each contour point's local gradient color through its inner edge.
	outer_radii := native_solid_rounded_contour_radii(bounds, contour_radii, -NATIVE_ROUNDED_ANTIALIAS_FRINGE)
	for i in 0..<NATIVE_ROUNDED_CONTOUR_POINTS {
		next := (i+1) % NATIVE_ROUNDED_CONTOUR_POINTS
		outer_a, _ := native_solid_rounded_contour_point(bounds, outer_radii, -NATIVE_ROUNDED_ANTIALIAS_FRINGE, i)
		outer_b, _ := native_solid_rounded_contour_point(bounds, outer_radii, -NATIVE_ROUNDED_ANTIALIAS_FRINGE, next)
		inner_a, _ := native_solid_rounded_contour_point(bounds, contour_radii, 0, i)
		inner_b, _ := native_solid_rounded_contour_point(bounds, contour_radii, 0, next)
		outer_color_a := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, inner_a[0], inner_a[1], opacity, inverse_extent)
		outer_color_b := native_solid_gradient_color_at(start, gradient.end, gradient.axis, bounds, inner_b[0], inner_b[1], opacity, inverse_extent)
		inner_color_a, inner_color_b := outer_color_a, outer_color_b
		outer_color_a[3], outer_color_b[3] = 0, 0
		append(vertices,
			Native_Text_Vertex{[3]f32{outer_a[0], outer_a[1], 0}, outer_color_a, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{outer_b[0], outer_b[1], 0}, outer_color_b, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_b[0], inner_b[1], 0}, inner_color_b, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{outer_a[0], outer_a[1], 0}, outer_color_a, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_b[0], inner_b[1], 0}, inner_color_b, {0.5, 0.5}},
			Native_Text_Vertex{[3]f32{inner_a[0], inner_a[1], 0}, inner_color_a, {0.5, 0.5}},
		)
	}
}

native_solid_append_rounded_material_surface :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	base, shadow: alicorn.Rect,
	fill: alicorn.Color,
	material: alicorn.Style_Material,
	physical_height, opacity: f32,
	shape: alicorn.Surface_Shape,
	stroke := alicorn.Paint_Stroke{},
	stroke_placement := alicorn.Paint_Stroke_Placement.Centered,
	gradient := alicorn.SURFACE_GRADIENT_NONE,
) {
	if base.w <= 0 || base.h <= 0 { return }
	radii := alicorn.surface_corner_radii_normalize(alicorn.surface_shape_corner_radii(shape), base.w, base.h)
	height_factor := native_solid_material_height_factor(physical_height)
	if material.kind == .Analytic_Relief && physical_height > 0 && material.outer_shadow_radius > 0 && material.outer_shadow_strength > 0 {
		expand := max(material.outer_shadow_radius, 0)
		outer := [4]f32{0, 0, 0, material.outer_shadow_strength*0.07*height_factor*opacity}
		middle := [4]f32{0, 0, 0, material.outer_shadow_strength*0.12*height_factor*opacity}
		native_solid_append_rounded_fill(vertices, shadow, native_solid_corner_radii_adjust(radii, expand), outer)
		mid := alicorn.Rect{
			shadow.x+(base.x-shadow.x)*0.5,
			shadow.y+(base.y-shadow.y)*0.5,
			shadow.w-(base.x-shadow.x)*0.5-(shadow.x+shadow.w-base.x-base.w)*0.5,
			shadow.h-(base.y-shadow.y)*0.5-(shadow.y+shadow.h-base.y-base.h)*0.5,
		}
		native_solid_append_rounded_fill(vertices, mid, native_solid_corner_radii_adjust(radii, expand*0.5), middle)
	}

	if gradient.axis == .None {
		native_solid_append_rounded_fill(vertices, base, radii, [4]f32{fill.r, fill.g, fill.b, fill.a*opacity})
	} else {
		native_solid_append_rounded_gradient_fill(vertices, base, radii, fill, gradient, opacity)
	}
	bevel_width := min(max(material.bevel_width, 0), min(base.w, base.h)*0.5)
	if material.kind == .Analytic_Relief && physical_height != 0 {
		if bevel_width > 0 && material.bevel_strength > 0 {
			native_solid_append_rounded_tinted_ring(vertices, base, radii, 0, bevel_width,
				fill, physical_height, material.bevel_strength, 0.22, opacity)
		}
		if material.inner_shadow_strength > 0 {
			inner_width := min(max(bevel_width, 1), min(base.w, base.h)*0.5)
			native_solid_append_rounded_tinted_ring(vertices, base, radii, bevel_width, bevel_width+inner_width,
				fill, physical_height, material.inner_shadow_strength, 0.18, opacity)
		}
	}

	if stroke.width > 0 {
		stroke_color := [4]f32{stroke.color.r, stroke.color.g, stroke.color.b, stroke.color.a*opacity}
		transparent_stroke := stroke_color
		transparent_stroke[3] = 0
		inside := stroke.width*0.5
		outside := stroke.width*0.5
		if stroke_placement == .Inside {
			inside, outside = stroke.width, 0
		} else if stroke_placement == .Outside {
			inside, outside = 0, stroke.width
		}
		inside = min(inside, min(base.w, base.h)*0.5)
		native_solid_append_rounded_ring(vertices, base, radii, -outside-NATIVE_ROUNDED_ANTIALIAS_FRINGE, -outside, transparent_stroke, stroke_color)
		native_solid_append_rounded_ring(vertices, base, radii, -outside, inside, stroke_color, stroke_color)
		native_solid_append_rounded_ring(vertices, base, radii, inside, inside+NATIVE_ROUNDED_ANTIALIAS_FRINGE, stroke_color, transparent_stroke)
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

native_solid_append_rect_stroke :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	base: alicorn.Rect,
	stroke: alicorn.Paint_Stroke,
	opacity: f32,
	stroke_placement := alicorn.Paint_Stroke_Placement.Centered,
	top_edge_gap := [2]f32{},
	gradient := alicorn.SURFACE_GRADIENT_NONE,
) {
	if stroke.width <= 0 || base.w <= 0 || base.h <= 0 { return }
	inside := stroke.width*0.5
	outside := stroke.width*0.5
	if stroke_placement == .Inside {
		inside, outside = stroke.width, 0
	} else if stroke_placement == .Outside {
		inside, outside = 0, stroke.width
	}
	inside = min(inside, min(base.w, base.h)*0.5)
	color := [4]f32{stroke.color.r, stroke.color.g, stroke.color.b, stroke.color.a*opacity}
	left := base.x-outside
	top := base.y-outside
	right := base.x+base.w+outside
	bottom := base.y+base.h+outside
	native_solid_append_top_edge(vertices, left, top, right, base.y+inside, color, top_edge_gap)
	native_solid_append_material_edge(vertices, left, base.y+base.h-inside, right, bottom, color)
	native_solid_append_material_edge(vertices, left, base.y+inside, base.x+inside, base.y+base.h-inside, color)
	native_solid_append_material_edge(vertices, base.x+base.w-inside, base.y+inside, right, base.y+base.h-inside, color)
}

native_solid_append_material_surface :: proc(
	vertices: ^[dynamic]Native_Text_Vertex,
	base, shadow: alicorn.Rect,
	fill: alicorn.Color,
	material: alicorn.Style_Material,
	physical_height: f32,
	opacity: f32,
	stroke := alicorn.Paint_Stroke{},
	stroke_placement := alicorn.Paint_Stroke_Placement.Centered,
	top_edge_gap := [2]f32{},
	gradient := alicorn.SURFACE_GRADIENT_NONE,
) {
	if base.w <= 0 || base.h <= 0 { return }
	if material.kind != .Analytic_Relief || physical_height == 0 {
		// Keep flat and zero-height surfaces exactly on the original one-quad
		// path: no shadow/bevel geometry and no intermediate material work.
		native_solid_append_gradient_quad(vertices, base, fill, gradient, opacity)
		native_solid_append_rect_stroke(vertices, base, stroke, opacity, stroke_placement, top_edge_gap)
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

	native_solid_append_gradient_quad(vertices, base, fill, gradient, opacity)

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
		native_solid_append_top_edge(vertices, base.x, base.y, base.x+base.w, base.y+bevel_width, top, top_edge_gap)
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
		native_solid_append_top_edge(vertices, base.x+bevel_width, base.y+bevel_width, base.x+base.w-bevel_width, base.y+bevel_width+inner_width, inner_top, top_edge_gap)
		native_solid_append_material_edge(vertices, base.x+bevel_width, base.y+bevel_width+inner_width, base.x+bevel_width+inner_width, base.y+base.h-bevel_width, inner_left)
		native_solid_append_material_edge(vertices, base.x+bevel_width, base.y+base.h-bevel_width-inner_width, base.x+base.w-bevel_width, base.y+base.h-bevel_width, inner_bottom)
		native_solid_append_material_edge(vertices, base.x+base.w-bevel_width-inner_width, base.y+bevel_width+inner_width, base.x+base.w-bevel_width, base.y+base.h-bevel_width-inner_width, inner_right)
	}
	native_solid_append_rect_stroke(vertices, base, stroke, opacity, stroke_placement, top_edge_gap)
}

native_solid_append_top_edge :: proc(vertices: ^[dynamic]Native_Text_Vertex, x0,y0,x1,y1:f32, color:[4]f32, gap:[2]f32) {
	if gap[1] <= gap[0] || gap[1] <= x0 || gap[0] >= x1 {
		native_solid_append_material_edge(vertices,x0,y0,x1,y1,color)
		return
	}
	native_solid_append_material_edge(vertices,x0,y0,max(x0,gap[0]),y1,color)
	native_solid_append_material_edge(vertices,min(x1,gap[1]),y0,x1,y1,color)
}
