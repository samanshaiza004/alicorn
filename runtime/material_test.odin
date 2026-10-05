package alicorn

import "core:testing"

@(test)
test_flat_material_is_canonical_zero_cost_value :: proc(t: ^testing.T) {
	testing.expect(t, style_material_is_valid(STYLE_MATERIAL_FLAT), "flat material should be valid")
	testing.expect(t, STYLE_MATERIAL_FLAT.kind == .Flat, "flat material should select the ordinary surface path")
	testing.expect(t, STYLE_MATERIAL_FLAT.bevel_width == 0 && STYLE_MATERIAL_FLAT.outer_shadow_radius == 0,
		"flat material should have no analytic effects to render")
}

@(test)
test_analytic_material_bounds_and_rejects_invalid_parameters :: proc(t: ^testing.T) {
	material := Style_Material{
		kind=.Analytic_Relief,
		bevel_width=2,
		bevel_strength=0.16,
		inner_shadow_strength=0.08,
		outer_shadow_strength=0.12,
		outer_shadow_radius=4,
	}
	testing.expect(t, style_material_is_valid(material), "small analytic relief material should be valid")
	invalid := material
	invalid.bevel_width = 9
	testing.expect(t, !style_material_is_valid(invalid), "bevel work must remain bounded")
	invalid = material
	invalid.outer_shadow_strength = transmute(f32)u32(0x7FC00000)
	testing.expect(t, !style_material_is_valid(invalid), "NaN material parameters must be rejected")
	invalid = STYLE_MATERIAL_FLAT
	invalid.inner_shadow_strength = 0.1
	testing.expect(t, !style_material_is_valid(invalid), "flat material must stay effect-free")
}

@(test)
test_material_registration_is_immutable_and_theme_locality_is_not_assumed :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	material := Style_Material{
		kind=.Analytic_Relief,
		bevel_width=1.5,
		bevel_strength=0.12,
		inner_shadow_strength=0.05,
		outer_shadow_strength=0.1,
		outer_shadow_radius=3,
	}
	id := style_material_register(&rt, material)
	material.bevel_width = 7
	resolved, ok := style_material_resolve(&rt, id)
	testing.expect(t, id != MATERIAL_FLAT && ok && resolved.bevel_width == 1.5,
		"registered material descriptors should be immutable snapshots")
	_, unknown_ok := style_material_resolve(&rt, Material_ID(999))
	testing.expect(t, !unknown_ok, "unknown material IDs should be rejected rather than interpreted as flat")
	flat_id := style_material_register(&rt, STYLE_MATERIAL_FLAT)
	testing.expect(t, flat_id == MATERIAL_FLAT && len(rt.style_materials) == 1,
		"flat should use reserved ID zero and avoid registry allocation")
}
