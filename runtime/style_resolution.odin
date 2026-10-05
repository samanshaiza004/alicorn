package alicorn

// Theme-local token IDs are valid only while both their theme and the
// dependency generations that produced the resolved value still match.
BUTTON_STYLE_DEPENDENCIES :: Style_Domains{.Paint}
TEXT_FIELD_STYLE_DEPENDENCIES :: Style_Domains{.Paint}
SCROLLBAR_STYLE_DEPENDENCIES :: Style_Domains{.Paint}
SEMANTIC_SURFACE_STYLE_DEPENDENCIES :: Style_Domains{.Paint, .Material}

style_button_state_bits :: proc(state: Button_Visual_State) -> u8 {
	bits := u8(0)
	if state.selected { bits |= 1 << 0 }
	if state.hovered { bits |= 1 << 1 }
	if state.pressed { bits |= 1 << 2 }
	if state.disabled { bits |= 1 << 3 }
	return bits
}

style_button_state_from_bits :: proc(bits: u8) -> Button_Visual_State {
	return Button_Visual_State{
		selected=(bits & (1 << 0)) != 0,
		hovered=(bits & (1 << 1)) != 0,
		pressed=(bits & (1 << 2)) != 0,
		disabled=(bits & (1 << 3)) != 0,
	}
}

style_text_field_state_bits :: proc(state: Text_Field_Visual_State) -> u8 {
	bits := u8(0)
	if state.hovered { bits |= 1 << 0 }
	if state.focused { bits |= 1 << 1 }
	return bits
}

style_scrollbar_state_bits :: proc(state: Scrollbar_Visual_State) -> u8 {
	bits := u8(0)
	if state.hovered { bits |= 1 << 0 }
	if state.pressed { bits |= 1 << 1 }
	return bits
}

style_button_provenance :: proc(
	environment: Style_Environment,
	variant: Button_Variant,
	state: Button_Visual_State,
	drop_target_on: bool,
) -> Style_Provenance {
	return Style_Provenance{
		theme=environment.theme,
		accent=environment.accent,
		variant=u8(variant),
		state_bits=style_button_state_bits(state),
		drop_target_on=drop_target_on,
	}
}

style_text_field_provenance :: proc(environment: Style_Environment, state: Text_Field_Visual_State) -> Style_Provenance {
	return Style_Provenance{
		theme=environment.theme,
		accent=environment.accent,
		state_bits=style_text_field_state_bits(state),
	}
}

style_scrollbar_provenance :: proc(environment: Style_Environment, state: Scrollbar_Visual_State) -> Style_Provenance {
	return Style_Provenance{
		theme=environment.theme,
		accent=environment.accent,
		state_bits=style_scrollbar_state_bits(state),
	}
}

style_semantic_surface_provenance :: proc(environment: Style_Environment, style: Semantic_Surface_Style) -> Style_Provenance {
	return Style_Provenance{
		theme=environment.theme,
		accent=environment.accent,
		surface_signature=semantic_surface_style_hash(style),
	}
}

// A cache hit is allowed only for the same recipe family, semantic inputs and
// declared dependency generations. This is also used by focused tests to
// assert exact cache boundaries without adding renderer counters to Runtime.
style_computed_cache_matches :: proc(
	rt: ^Runtime,
	node: ^Node,
	family: Computed_Style_Family,
	provenance: Style_Provenance,
	dependencies: Style_Domains,
) -> bool {
	if rt == nil || node == nil { return false }
	computed, found := rt.computed_styles[node.id]
	return found && computed.valid && computed.family == family &&
	       computed.provenance == provenance && computed.dependencies == dependencies &&
	       style_generations_match(node.style_generations, computed.generations, dependencies)
}

style_computed_cache_invalidate :: proc(rt: ^Runtime, node: Node_ID) {
	if rt == nil { return }
	computed, found := rt.computed_styles[node]
	if !found { return }
	computed.valid = false
	rt.computed_styles[node] = computed
}

style_computed_cache_store :: proc(rt: ^Runtime, node: ^Node, computed: Computed_Style) {
	if rt == nil || node == nil { return }
	entry := computed
	entry.generations = style_generations_snapshot(node.style_generations, entry.dependencies)
	entry.valid = true
	rt.computed_styles[node.id] = entry
}

// Each retained node owns at most one current recipe-family result in
// Runtime side storage. Button, Text Field, Scrollbar, and Semantic Surface
// cache values share the same domain/provenance checks without growing Node.
style_button_resolve_retained :: proc(
	rt: ^Runtime,
	node: ^Node,
	state: Button_Visual_State,
	drop_target_on := false,
) -> Button_Resolved_Style {
	if rt == nil || node == nil {
		return style_button_resolve(rt, DEFAULT_STYLE_ENVIRONMENT, .Default, state, drop_target_on)
	}
	provenance := style_button_provenance(node.style_environment, node.button_variant, state, drop_target_on)
	if style_computed_cache_matches(rt, node, .Button, provenance, BUTTON_STYLE_DEPENDENCIES) {
		computed := rt.computed_styles[node.id]
		return computed.payload.(Button_Resolved_Style)
	}
	resolved := style_button_resolve(rt, node.style_environment, node.button_variant, state, drop_target_on)
	style_computed_cache_store(rt, node, Computed_Style{
		family=.Button,
		payload=resolved,
		dependencies=BUTTON_STYLE_DEPENDENCIES,
		provenance=provenance,
	})
	return resolved
}

style_text_field_resolve_retained :: proc(
	rt: ^Runtime,
	node: ^Node,
	state: Text_Field_Visual_State,
) -> Text_Field_Resolved_Style {
	if rt == nil || node == nil {
		return style_text_field_resolve(rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_TEXT_FIELD_RECIPE, state)
	}
	provenance := style_text_field_provenance(node.style_environment, state)
	if style_computed_cache_matches(rt, node, .Text_Field, provenance, TEXT_FIELD_STYLE_DEPENDENCIES) {
		computed := rt.computed_styles[node.id]
		return computed.payload.(Text_Field_Resolved_Style)
	}
	recipe := style_text_field_recipe(rt, node.style_environment)
	resolved := style_text_field_resolve(rt, node.style_environment, recipe, state)
	style_computed_cache_store(rt, node, Computed_Style{
		family=.Text_Field,
		payload=resolved,
		dependencies=TEXT_FIELD_STYLE_DEPENDENCIES,
		provenance=provenance,
	})
	return resolved
}

style_scrollbar_resolve_retained :: proc(
	rt: ^Runtime,
	node: ^Node,
	state: Scrollbar_Visual_State,
) -> Scrollbar_Resolved_Style {
	if rt == nil || node == nil {
		return style_scrollbar_resolve(rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_SCROLLBAR_RECIPE, state)
	}
	provenance := style_scrollbar_provenance(node.style_environment, state)
	if style_computed_cache_matches(rt, node, .Scrollbar, provenance, SCROLLBAR_STYLE_DEPENDENCIES) {
		computed := rt.computed_styles[node.id]
		return computed.payload.(Scrollbar_Resolved_Style)
	}
	recipe := style_scrollbar_recipe(rt, node.style_environment)
	resolved := style_scrollbar_resolve(rt, node.style_environment, recipe, state)
	style_computed_cache_store(rt, node, Computed_Style{
		family=.Scrollbar,
		payload=resolved,
		dependencies=SCROLLBAR_STYLE_DEPENDENCIES,
		provenance=provenance,
	})
	return resolved
}

style_semantic_surface_resolve_retained :: proc(
	rt: ^Runtime,
	node: ^Node,
	style: Semantic_Surface_Style,
) -> Semantic_Surface_Resolved_Style {
	if rt == nil || node == nil || !style.defined { return {} }
	provenance := style_semantic_surface_provenance(node.style_environment, style)
	if style_computed_cache_matches(rt, node, .Semantic_Surface, provenance, SEMANTIC_SURFACE_STYLE_DEPENDENCIES) {
		computed := rt.computed_styles[node.id]
		return computed.payload.(Semantic_Surface_Resolved_Style)
	}
	fill, fill_ok := semantic_surface_role_resolve(rt, node.style_environment, style.role)
	if !fill_ok { return {} }
	resolved := Semantic_Surface_Resolved_Style{fill=fill}
	style_computed_cache_store(rt, node, Computed_Style{
		family=.Semantic_Surface,
		payload=resolved,
		dependencies=SEMANTIC_SURFACE_STYLE_DEPENDENCIES,
		provenance=provenance,
	})
	return resolved
}
