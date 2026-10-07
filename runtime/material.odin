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

// Style_Material_Definition is an immutable setup-time value emitted by the
// theme compiler. Names are static in generated themes and applications map
// them to Material_ID once during setup; frame descriptions carry only IDs.
Style_Material_Definition :: struct {
	name:     string,
	material: Style_Material,
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

// style_material_accessibility_variant resolves appearance preferences into
// an immutable material handle at the paint-producing boundary. Variants are
// deduplicated in the existing Runtime registry so repeated descriptions do
// not grow material storage. Flat materials stay on the zero-cost path.
style_material_accessibility_variant :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	source: Material_ID,
) -> Material_ID {
	if rt == nil || source == MATERIAL_FLAT { return source }
	prefs := environment.accessibility
	if !prefs.increased_contrast && !prefs.reduce_transparency { return source }
	material, ok := style_material_resolve(rt, source)
	if !ok || material.kind != .Analytic_Relief { return source }
	resolved := material
	if prefs.increased_contrast {
		resolved.bevel_width = maxf(resolved.bevel_width, 1.5)
		resolved.bevel_strength = maxf(resolved.bevel_strength, 0.75)
	}
	if prefs.reduce_transparency {
		// Outer shadows are the material's only intrinsically translucent
		// overlay. The source surface role is made opaque by the same scope.
		resolved.outer_shadow_strength = 0
	}
	if resolved == material { return source }
	for existing, index in rt.style_materials {
		if existing == resolved { return Material_ID(u32(index+1)) }
	}
	return style_material_register(rt, resolved)
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
