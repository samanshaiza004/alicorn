package alicorn

// Style_Material_Kind selects the opt-in optical treatment for a surface.
// Flat is the canonical zero-cost path used by ordinary paint commands.
Style_Material_Kind :: enum {
	Flat,
	Analytic_Relief,
}

// Style_Material contains backend-neutral parameters for the first analytic
// material renderer. physical_height remains on Surface_Paint because it is
// per-surface state; it never changes layout or compositor ordering.
Style_Material :: struct {
	kind:                   Style_Material_Kind,
	bevel_width:            f32,
	bevel_strength:         f32,
	inner_shadow_strength:  f32,
	outer_shadow_strength:  f32,
	outer_shadow_radius:    f32,
}

STYLE_MATERIAL_FLAT :: Style_Material{
	kind=.Flat,
	bevel_width=0,
	bevel_strength=0,
	inner_shadow_strength=0,
	outer_shadow_strength=0,
	outer_shadow_radius=0,
}

// style_material_register appends an immutable material to this Runtime.
// Material_ID(0) is reserved for the zero-cost flat path.
style_material_register :: proc(rt: ^Runtime, material: Style_Material) -> Material_ID {
	if rt == nil || !style_material_is_valid(material) {
		if rt != nil { append_diagnostic(rt, "style material contains an invalid kind or out-of-range analytic parameter") }
		return MATERIAL_FLAT
	}
	if material.kind == .Flat { return MATERIAL_FLAT }
	if rt.style_materials == nil {
		rt.style_materials = make([dynamic]Style_Material, 0, allocator=rt.persistent_allocator)
	}
	if u64(len(rt.style_materials)) >= u64(0xFFFFFFFF) {
		append_diagnostic(rt, "style material registry exhausted Material_ID values")
		return MATERIAL_FLAT
	}
	append(&rt.style_materials, material)
	return Material_ID(u32(len(rt.style_materials)))
}

style_material_resolve :: proc(rt: ^Runtime, id: Material_ID) -> (material: Style_Material, ok: bool) {
	if id == MATERIAL_FLAT { return STYLE_MATERIAL_FLAT, true }
	if rt == nil { return }
	index := u64(u32(id))
	if index == 0 || index > u64(len(rt.style_materials)) { return }
	material = rt.style_materials[index-1]
	return material, true
}

// Material parameters are intentionally bounded. Apart from keeping malformed
// values out of native paint, the small maximum prevents a theme or app from
// turning a subtle control treatment into unbounded per-surface geometry.
style_material_is_valid :: proc(material: Style_Material) -> bool {
	if material.kind != .Flat && material.kind != .Analytic_Relief { return false }
	if material.bevel_width != material.bevel_width || material.bevel_width < 0 || material.bevel_width > 8 { return false }
	if material.bevel_strength != material.bevel_strength || material.bevel_strength < 0 || material.bevel_strength > 1 { return false }
	if material.inner_shadow_strength != material.inner_shadow_strength || material.inner_shadow_strength < 0 || material.inner_shadow_strength > 1 { return false }
	if material.outer_shadow_strength != material.outer_shadow_strength || material.outer_shadow_strength < 0 || material.outer_shadow_strength > 1 { return false }
	if material.outer_shadow_radius != material.outer_shadow_radius || material.outer_shadow_radius < 0 || material.outer_shadow_radius > 16 { return false }
	if material.kind == .Flat && (material.bevel_width != 0 || material.bevel_strength != 0 || material.inner_shadow_strength != 0 || material.outer_shadow_strength != 0 || material.outer_shadow_radius != 0) {
		return false
	}
	return true
}
