package alicorn

// Semantic_Surface_Color_Role keeps core roles and namespaced app roles in
// separate type domains while allowing either to drive a composed surface.
Semantic_Surface_Color_Role :: union #no_nil {
	Style_Color_Role,
	Style_Extension_Color_Role_ID,
}

surface_core_color_role :: proc(role: Style_Color_Role) -> Semantic_Surface_Color_Role {
	return role
}

surface_extension_color_role :: proc(role: Style_Extension_Color_Role_ID) -> Semantic_Surface_Color_Role {
	return role
}

// Semantic_Surface_Style is description metadata for a container-owned
// surface. It lives in the pending description and Runtime sidecar map rather
// than Node, preserving the retained-node size budget.
Semantic_Surface_Style :: struct {
	defined: bool,
	role: Semantic_Surface_Color_Role,
	shape: Surface_Shape,
	material: Material_ID,
	physical_height: f32,
	material_group: Material_Group_ID,
}

Semantic_Surface_Resolved_Style :: struct {
	fill: Color,
}

SURFACE_PHYSICAL_HEIGHT_LIMIT :: 2.0

semantic_surface_role_resolve :: proc(rt: ^Runtime, environment: Style_Environment, role: Semantic_Surface_Color_Role) -> (color: Color, ok: bool) {
	switch value in role {
	case Style_Color_Role:
		if !style_color_role_is_valid(value) { return }
		return style_environment_color(rt, environment, value), true
	case Style_Extension_Color_Role_ID:
		return style_extension_color(rt, environment.theme, value)
	}
	return
}

semantic_surface_style_is_valid :: proc(rt: ^Runtime, environment: Style_Environment, style: Semantic_Surface_Style) -> bool {
	if !style.defined { return false }
	if _, role_ok := semantic_surface_role_resolve(rt, environment, style.role); !role_ok { return false }
	if style.physical_height != style.physical_height || abs(style.physical_height) > SURFACE_PHYSICAL_HEIGHT_LIMIT { return false }
	// The current SDL_GPU surface path paints rectangles. Keep richer shapes in
	// the lower-level paint contract, but don't claim a treatment it can't draw.
	if style.shape.kind != .Rectangle || style.shape.corner_radius != 0 { return false }
	_, material_ok := style_material_resolve(rt, style.material)
	return material_ok
}

semantic_surface_style_hash :: proc(style: Semantic_Surface_Style) -> u64 {
	if !style.defined { return 0 }
	h := u64(1469598103934665603)
	switch role in style.role {
	case Style_Color_Role:
		h = hash_mix(h, 1)
		h = hash_mix(h, u64(role))
	case Style_Extension_Color_Role_ID:
		h = hash_mix(h, 2)
		h = hash_mix(h, u64(role))
	}
	h = hash_mix(h, u64(style.shape.kind))
	h = hash_mix(h, u64(transmute(u32)style.shape.corner_radius))
	h = hash_mix(h, u64(u32(style.material)))
	h = hash_mix(h, u64(transmute(u32)style.physical_height))
	h = hash_mix(h, u64(u32(style.material_group)))
	return h
}

// surface_begin opens an ordinary layout container and decorates its resolved
// bounds with a theme-role surface. Children are laid out normally inside it;
// neither bounds nor renderer commands are part of this API.
surface_begin :: proc(
	ui: ^UI,
	role: Semantic_Surface_Color_Role,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	shape := Surface_Shape{kind=.Rectangle},
	material := MATERIAL_FLAT,
	physical_height: f32 = 0,
	material_group := MATERIAL_GROUP_NONE,
	label := "surface",
	loc := #caller_location,
) -> Node_ID {
	if ui == nil || ui.runtime == nil { return 0 }
	rt := ui.runtime
	semantic_style := Semantic_Surface_Style{
		defined=true,
		role=role,
		shape=shape,
		material=material,
		physical_height=physical_height,
		material_group=material_group,
	}
	if !rt.frame_open || !semantic_surface_style_is_valid(rt, rt.style_environment, semantic_style) {
		append_diagnostic(rt, "surface_begin requires an open frame, resolvable theme role, rectangular shape, bounded optical height, and registered material")
		return 0
	}
	id := container_begin_simple(
		ui,
		.Container,
		label=label,
		key=key,
		style=style,
		color=NO_BACKGROUND_COLOR,
		loc=loc,
	)
	if id == 0 { return 0 }
	last := len(rt.pending)-1
	if last < 0 || rt.pending[last].kind != .Description || rt.pending[last].description.id != id {
		append_diagnostic(rt, "surface_begin could not associate its semantic paint recipe with the described container")
		container_end(ui)
		return 0
	}
	rt.pending[last].semantic_surface_style = semantic_style
	return id
}

// surface_end closes the layout scope opened by surface_begin.
surface_end :: proc(ui: ^UI) {
	container_end(ui)
}
