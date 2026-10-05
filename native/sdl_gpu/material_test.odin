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
