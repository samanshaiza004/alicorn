package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_surface_shadow_visible_without_its_surface :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime({0, 0, 100, 60})
	defer alicorn.destroy_runtime(&rt)
	material := alicorn.style_material_register(&rt, alicorn.Style_Material{
		kind=.Analytic_Relief, outer_shadow_radius=8, outer_shadow_strength=0.6,
	})
	renderer := Native_Solid_Renderer{runtime=&rt,
		vertices=make([dynamic]Native_Text_Vertex, 0, 2048, allocator=context.temp_allocator),
		draws=make([dynamic]Native_Solid_Draw, 0, 1, allocator=context.temp_allocator),
		vertex_capacity=2048,
	}
	defer delete(renderer.vertices)
	defer delete(renderer.draws)
	for shape in ([2]alicorn.Surface_Shape{{}, {kind=.Rounded_Rectangle, corner_radius=6}}) {
		for clipped in ([2]bool{false, true}) {
			bounds, clip := alicorn.Rect{-34, 10, 30, 24}, alicorn.Rect{0, 0, 100, 60}
			if clipped { bounds = {14, 10, 30, 24}; clip = {48, 0, 52, 60} }
			for scale in ([3][2]f32{{1, 1}, {1.25, 1.5}, {2, 2}}) {
				display := [1]alicorn.Paint_Command{
					alicorn.paint_surface_command(1, bounds, clip, {0.5, 0.4, 0.3, 1},
						material=material, physical_height=1, shape=shape),
				}
				testing.expect(t, native_solid_build(&renderer, display[:], scale[0], scale[1], u32(100*scale[0]), u32(60*scale[1])),
					"an offscreen surface with a visible shadow should build")
				testing.expect(t, renderer.draws[0].vertex_count > 0 && renderer.draws[0].has_scissor,
					"a shadow intersecting the viewport or parent clip must survive culling even when its surface is outside")
				visible_shadow := false
				scissor := renderer.draws[0].scissor
				for vertex in renderer.vertices {
					if vertex.color[3] > 0 && vertex.position[0] >= f32(scissor.x) && vertex.position[0] < f32(scissor.x+scissor.w) &&
					   vertex.position[1] >= f32(scissor.y) && vertex.position[1] < f32(scissor.y+scissor.h) {
						visible_shadow = true
					}
				}
				testing.expect(t, visible_shadow, "the emitted shadow must have nonzero coverage inside its resolved scissor")
				display[0].translation = {-64, 0}
				testing.expect(t, native_solid_build(&renderer, display[:], scale[0], scale[1], u32(100*scale[0]), u32(60*scale[1])) && renderer.draws[0].vertex_count == 0,
					"a translated surface whose entire paint footprint is outside must still be culled")
			}
		}
	}
}

@(test)
test_flat_material_stays_one_quad :: proc(t: ^testing.T) {
	vertices := make([dynamic]Native_Text_Vertex, 0, 128, allocator=context.temp_allocator)
	defer delete(vertices)
	native_solid_append_material_surface(
		&vertices,
		alicorn.Rect{10, 20, 100, 40},
		alicorn.Rect{10, 20, 100, 40},
		alicorn.Color{0.4, 0.5, 0.6, 1},
		alicorn.STYLE_MATERIAL_FLAT,
		0,
		1,
	)
	testing.expect(t, len(vertices) == 6, "flat materials should emit exactly the existing solid quad")
	testing.expect(t, native_solid_material_vertex_count(alicorn.STYLE_MATERIAL_FLAT, 0) == 6,
		"flat surfaces should reserve no material geometry")
}

@(test)
test_rounded_material_uses_bounded_contours_and_scaled_tangents :: proc(t: ^testing.T) {
	shape := alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=6}
	fill := alicorn.Color{0.7, 0.6, 0.5, 1}
	flat_vertices := make([dynamic]Native_Text_Vertex, 0, 512, allocator=context.temp_allocator)
	defer delete(flat_vertices)
	native_solid_append_rounded_material_surface(
		&flat_vertices, {10, 20, 60, 32}, {10, 20, 60, 32}, fill,
		alicorn.STYLE_MATERIAL_FLAT, 0, 1, shape,
	)
	testing.expect(t, len(flat_vertices) == NATIVE_ROUNDED_FILL_VERTICES && len(flat_vertices) == 315,
		"flat rounded surfaces should use a fixed 35-point contour and a one-pixel antialias fringe")
	if len(flat_vertices) == NATIVE_ROUNDED_FILL_VERTICES {
		min_x := flat_vertices[0].position[0]
		max_x := min_x
		for vertex in flat_vertices {
			min_x = min(min_x, vertex.position[0])
			max_x = max(max_x, vertex.position[0])
		}
		testing.expect(t, min_x == 9.25 && max_x == 70.75,
			"the antialias fringe should extend a bounded 0.75 physical pixels around the rounded contour")
	}

	material := alicorn.Style_Material{
		kind=.Analytic_Relief, bevel_width=2, bevel_strength=0.8,
		inner_shadow_strength=0.5, outer_shadow_strength=0.6, outer_shadow_radius=4,
	}
	material_vertices := make([dynamic]Native_Text_Vertex, 0, 2048, allocator=context.temp_allocator)
	defer delete(material_vertices)
	expected := native_solid_material_vertex_count(material, 1, shape)
	native_solid_append_rounded_material_surface(
		&material_vertices, {10, 20, 60, 32}, {6, 16, 68, 40}, fill,
		material, 1, 1, shape,
	)
	testing.expect(t, expected == 1365 && len(material_vertices) == expected && expected <= 1400,
		"rounded analytic relief should use a deterministic bounded mesh for fill, two shadows, bevel, and inner contour")
	if len(material_vertices) == expected {
		testing.expect(t, material_vertices[expected-1].position[2] == 0,
			"curved relief remains optical paint and never changes compositor depth")
	}
	for scale in ([4]f32{1, 1.25, 1.5, 2}) {
		scaled := shape
		scaled.corner_radius *= scale
		testing.expect(t, native_solid_material_vertex_count(material, 1, scaled) == expected,
			"DPI changes contour coordinates without changing the published vertex bound")
	}
}

@(test)
test_rounded_surface_clips_by_scissor_without_rounding_the_clip_edge :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime({0, 0, 100, 60})
	defer alicorn.destroy_runtime(&rt)
	shape := alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=6}
	display := [1]alicorn.Paint_Command{
		alicorn.paint_surface_command(1, {10, 10, 40, 24}, {0, 0, 20, 40}, {0.5, 0.4, 0.3, 1}, shape=shape),
	}
	renderer := Native_Solid_Renderer{
		runtime=&rt,
		vertices=make([dynamic]Native_Text_Vertex, 0, 512, allocator=context.temp_allocator),
		draws=make([dynamic]Native_Solid_Draw, 0, 2, allocator=context.temp_allocator),
		vertex_capacity=512,
	}
	defer delete(renderer.vertices)
	defer delete(renderer.draws)
	testing.expect(t, native_solid_build(&renderer, display[:], 1, 1, 100, 60),
		"rounded surface expansion should build under a partial parent clip")
	if len(renderer.draws) != 1 { testing.expect(t, false, "the rounded surface should retain one ordered draw slot"); return }
	draw := renderer.draws[0]
	testing.expect(t, draw.has_scissor && draw.scissor.x == 0 && draw.scissor.y == 0 && draw.scissor.w == 20 && draw.scissor.h == 40,
		"the parent clip should become a rectangular GPU scissor independent of the rounded contour")
	max_x := f32(0)
	for vertex in renderer.vertices { max_x = max(max_x, vertex.position[0]) }
	testing.expect(t, max_x > 20 && draw.vertex_count == NATIVE_ROUNDED_FILL_VERTICES,
		"the original shape mesh must extend beyond the clip so clipping cannot introduce a false curved edge")

	clear(&renderer.vertices)
	clear(&renderer.draws)
	display[0] = alicorn.paint_surface_command(1, {10, 10, 40, 24}, {0, 0, 100, 60}, {0.5, 0.4, 0.3, 1}, shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle})
	testing.expect(t, native_solid_build(&renderer, display[:], 1, 1, 100, 60) && len(renderer.vertices) == 6,
		"a rounded shape with radius zero should use the exact rectangular fast path")
}

@(test)
test_analytic_relief_emits_only_bounded_local_geometry :: proc(t: ^testing.T) {
	material := alicorn.Style_Material{
		kind=.Analytic_Relief,
		bevel_width=2,
		bevel_strength=0.2,
		inner_shadow_strength=0.1,
		outer_shadow_strength=0.2,
		outer_shadow_radius=4,
	}
	vertices := make([dynamic]Native_Text_Vertex, 0, 128, allocator=context.temp_allocator)
	defer delete(vertices)
	native_solid_append_material_surface(
		&vertices,
		alicorn.Rect{20, 30, 80, 40},
		alicorn.Rect{16, 26, 88, 48},
		alicorn.Color{0.7, 0.6, 0.5, 1},
		material,
		1,
		1,
	)
	expected := native_solid_material_vertex_count(material, 1)
	testing.expect(t, len(vertices) == expected && expected == 66,
		"analytic relief should emit one fill, two shadow layers, four bevel edges, and four inner-shadow edges")
	testing.expect(t, vertices[0].position[0] == 16 && vertices[0].position[1] == 26,
		"first shadow layer should use the caller-clipped shadow bounds")
	flat_height_count := native_solid_material_vertex_count(material, 0)
	testing.expect(t, flat_height_count == 6, "zero optical height should use the flat rendering path")
	recessed_vertex_count := native_solid_material_vertex_count(material, -1)
	testing.expect(t, recessed_vertex_count == 54,
		"recessed surfaces should use inner shading and bevel but should not cast an outer shadow")
}

@(test)
test_analytic_relief_has_directional_signed_and_height_scaled_shading :: proc(t: ^testing.T) {
	material := alicorn.Style_Material{kind=.Analytic_Relief, bevel_width=2, bevel_strength=0.8, inner_shadow_strength=0.5}
	fill := alicorn.Color{0.7, 0.6, 0.5, 1}
	vertices := make([dynamic]Native_Text_Vertex, 0, 128, allocator=context.temp_allocator)
	defer delete(vertices)

	native_solid_append_material_surface(&vertices, {10, 20, 80, 40}, {10, 20, 80, 40}, fill, material, 1, 1)
	raised := make([]Native_Text_Vertex, len(vertices), allocator=context.temp_allocator)
	defer delete(raised, context.temp_allocator)
	copy(raised, vertices[:])
	base := raised[0].color[0]
	testing.expect(t, raised[6].color[0] > base && raised[12].color[0] > base,
		"upper and left bevels should face the fixed upper-left light on raised surfaces")
	testing.expect(t, raised[18].color[0] < base && raised[24].color[0] < base,
		"lower and right bevels should fall away from the fixed upper-left light")
	for vertex in raised {
		testing.expect(t, vertex.position[2] == 0,
			"physical height is optical only and must not become compositor Z")
	}

	clear(&vertices)
	native_solid_append_material_surface(&vertices, {10, 20, 80, 40}, {10, 20, 80, 40}, fill, material, -1, 1)
	testing.expect(t, vertices[6].color[0] < base && vertices[18].color[0] > base,
		"negative physical height should reverse the bevel response for a recess")
	for vertex, i in vertices {
		testing.expect(t, vertex.position == raised[i].position,
			"changing optical height must not move or reorder the emitted surface geometry")
	}

	clear(&vertices)
	native_solid_append_material_surface(&vertices, {10, 20, 80, 40}, {10, 20, 80, 40}, fill, material, 0.5, 1)
	half_response := vertices[6].color[0] - base
	full_response := raised[6].color[0] - base
	testing.expect(t, abs(half_response*2-full_response) < 0.0001,
		"bevel response should scale continuously with bounded physical height")
}

@(test)
test_flat_and_zero_height_take_the_direct_quad_path :: proc(t: ^testing.T) {
	material := alicorn.Style_Material{kind=.Analytic_Relief, bevel_width=2, bevel_strength=0.8, inner_shadow_strength=0.5, outer_shadow_strength=0.6, outer_shadow_radius=4}
	for variant in 0..<2 {
		vertices := make([dynamic]Native_Text_Vertex, 0, 16, allocator=context.temp_allocator)
		defer delete(vertices)
		if variant == 0 {
			native_solid_append_material_surface(&vertices, {5, 7, 30, 22}, {1, 2, 38, 30}, {0.3, 0.4, 0.5, 1}, alicorn.STYLE_MATERIAL_FLAT, 0, 1)
		} else {
			native_solid_append_material_surface(&vertices, {5, 7, 30, 22}, {1, 2, 38, 30}, {0.3, 0.4, 0.5, 1}, material, 0, 1)
		}
		expected := make([dynamic]Native_Text_Vertex, 0, 16, allocator=context.temp_allocator)
		defer delete(expected)
		native_solid_append_quad(&expected, 5, 7, 35, 29, [4]f32{0.3, 0.4, 0.5, 1})
		testing.expect(t, len(vertices) == 6 && len(expected) == 6,
			"flat and zero-height surfaces must emit exactly one ordinary quad")
		for i := 0; i < 6; i += 1 {
			testing.expect(t, vertices[i].position == expected[i].position && vertices[i].color == expected[i].color,
				"flat and zero-height material output must match ordinary solid geometry exactly")
		}
	}
}

@(test)
test_optical_height_preserves_surface_order_and_depth :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime({0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	material := alicorn.style_material_register(&rt, alicorn.Style_Material{
		kind=.Analytic_Relief, bevel_width=2, bevel_strength=0.4,
		inner_shadow_strength=0.2, outer_shadow_strength=0.2, outer_shadow_radius=3,
	})
	display := [5]alicorn.Paint_Command{
		alicorn.paint_surface_command(1, {10, 10, 30, 22}, {0, 0, 240, 120}, {0.2, 0.3, 0.4, 1}),
		alicorn.paint_text_command(2, {45, 10, 40, 22}, {0, 0, 240, 120}, {}, {1, 1, 1, 1}),
		alicorn.paint_surface_command(3, {90, 10, 30, 22}, {0, 0, 240, 120}, {0.3, 0.4, 0.5, 1}, material=material, physical_height=0.5),
		alicorn.paint_geometry_command(4, {135, 10, 30, 22}, {0, 0, 240, 120}, {}),
		alicorn.paint_surface_command(5, {180, 10, 30, 22}, {0, 0, 240, 120}, {0.4, 0.5, 0.6, 1}, material=material, physical_height=-0.5),
	}
	renderer := Native_Solid_Renderer{
		runtime=&rt,
		vertices=make([dynamic]Native_Text_Vertex, 0, 256, allocator=context.temp_allocator),
		draws=make([dynamic]Native_Solid_Draw, 0, 8, allocator=context.temp_allocator),
		vertex_capacity=256,
	}
	defer delete(renderer.vertices)
	defer delete(renderer.draws)
	testing.expect(t, native_solid_build(&renderer, display[:], 1, 1, 240, 120),
		"CPU material expansion should build without a GPU device")
	testing.expect(t, len(renderer.draws) == len(display) && renderer.draws[0].vertex_count == 6 &&
		renderer.draws[1].vertex_count == 0 && renderer.draws[2].vertex_count == 66 &&
		renderer.draws[3].vertex_count == 0 && renderer.draws[4].vertex_count == 54,
		"surface draw slots should remain aligned with intervening text and geometry commands")
	testing.expect(t, renderer.draws[0].first_vertex == 0 && renderer.draws[2].first_vertex == 6 && renderer.draws[4].first_vertex == 72,
		"raised and recessed expansion should preserve display-list surface order")
	for vertex in renderer.vertices {
		testing.expect(t, vertex.position[2] == 0,
			"surface height must not change emitted vertex depth or compositor order")
	}
}
