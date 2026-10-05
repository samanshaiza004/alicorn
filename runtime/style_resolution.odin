package alicorn

// A theme ID is an append-only identity/generation within one Runtime. Token
// IDs are meaningful only under that theme. Style_Provenance stores only the
// paint-relevant environment and component inputs; domain generations handle
// changes to the other resolved dependencies.
BUTTON_STYLE_DEPENDENCIES :: Style_Domains{.Paint}

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

// style_button_resolve_retained stores the computed result on the retained
// node. This is intentionally per-node, not a global memoization table: the
// signature prevents stale theme-local token IDs from surviving a theme switch.
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
	if node.computed_style.valid && node.computed_style.provenance == provenance &&
		style_generations_match(node.style_generations, node.computed_style.generations, node.computed_style.dependencies) {
		return node.computed_style.button
	}
	resolved := style_button_resolve(rt, node.style_environment, node.button_variant, state, drop_target_on)
	node.computed_style = Computed_Style{
		button=resolved,
		dependencies=BUTTON_STYLE_DEPENDENCIES,
		generations=style_generations_snapshot(node.style_generations, BUTTON_STYLE_DEPENDENCIES),
		provenance=provenance,
		valid=true,
	}
	return resolved
}
