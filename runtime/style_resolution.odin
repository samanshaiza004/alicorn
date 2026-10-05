package alicorn

// A theme ID is an append-only identity/generation within one Runtime. Token
// IDs are meaningful only under that theme. The remaining fields capture the
// resolved environment and component state that influence a button recipe.
Style_Resolution_Signature :: struct {
	theme:        Style_Theme_ID,
	environment:  Style_Environment,
	variant:      Button_Variant,
	state:        Button_Visual_State,
	drop_target_on: bool,
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
	signature := Style_Resolution_Signature{
		theme=node.style_environment.theme,
		environment=node.style_environment,
		variant=node.button_variant,
		state=state,
		drop_target_on=drop_target_on,
	}
	if node.computed_button_style_valid && node.computed_button_style_signature == signature {
		return node.computed_button_style
	}
	resolved := style_button_resolve(rt, node.style_environment, node.button_variant, state, drop_target_on)
	node.computed_button_style = resolved
	node.computed_button_style_signature = signature
	node.computed_button_style_valid = true
	return resolved
}
