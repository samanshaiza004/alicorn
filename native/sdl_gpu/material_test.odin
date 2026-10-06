package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

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
