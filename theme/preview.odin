package theme

// Theme_JSON_Compile_Output owns both strict-JSON diagnostics and the typed
// compiler result. It is suitable for passing from a build worker to the UI
// thread when paired with the allocator used by theme_compile_json.
Theme_JSON_Compile_Output :: struct {
	parsed:             Theme_JSON_Output,
	compiled:           Theme_Compile_Output,
	unsupported_extends: bool,
	ok:                 bool,
}

theme_compile_json :: proc(
	input: string,
	path := "<theme>",
	allocator := context.allocator,
) -> Theme_JSON_Compile_Output {
	result := Theme_JSON_Compile_Output{}
	result.parsed = theme_json_parse(input, path, allocator)
	if !result.parsed.ok { return result }
	if result.parsed.extends != "" && result.parsed.extends != "alicorn.base" {
		result.unsupported_extends = true
		return result
	}
	if result.parsed.extends == "alicorn.base" {
		base := theme_builtin_base_source_create(allocator)
		defer theme_builtin_base_source_destroy(&base, allocator)
		if len(base.tokens) == 0 { return result }
		result.compiled = theme_compile({base.model, result.parsed.source}, allocator=allocator)
	} else {
		result.compiled = theme_compile({result.parsed.source}, allocator=allocator)
	}
	result.ok = result.compiled.ok
	return result
}

theme_json_compile_output_destroy :: proc(output: ^Theme_JSON_Compile_Output, allocator := context.allocator) {
	if output == nil { return }
	theme_json_output_destroy(&output.parsed, allocator)
	theme_output_destroy(&output.compiled, allocator)
	output^ = Theme_JSON_Compile_Output{}
}

// theme_preview_structure_compatible permits color-value edits while keeping
// token identity, aliases, role bindings, lengths, recipes, materials, and
// provenance names fixed. Source spans and JSON formatting are intentionally
// ignored.
theme_preview_structure_compatible :: proc(previous, candidate: Theme_JSON_Compile_Output) -> bool {
	if !previous.ok || !candidate.ok { return false }
	a, b := previous.compiled, candidate.compiled
	if a.theme.contract != b.theme.contract || len(a.theme.colors) != len(b.theme.colors) ||
		len(a.theme.lengths) != len(b.theme.lengths) || len(a.theme.materials) != len(b.theme.materials) ||
		len(a.theme.button_recipes) != len(b.theme.button_recipes) ||
		len(a.theme.extension_color_roles) != len(b.theme.extension_color_roles) ||
		len(a.theme.extension_length_roles) != len(b.theme.extension_length_roles) ||
		len(a.debug.tokens) != len(b.debug.tokens) || len(a.debug.core_roles) != len(b.debug.core_roles) ||
		len(a.debug.extension_roles) != len(b.debug.extension_roles) ||
		len(a.debug.materials) != len(b.debug.materials) ||
		len(a.debug.button_recipes) != len(b.debug.button_recipes) {
		return false
	}
	for left, index in a.theme.lengths { if left != b.theme.lengths[index] { return false } }
	for left, index in a.theme.materials { if left != b.theme.materials[index] { return false } }
	for left, index in a.theme.core_color_roles { if left != b.theme.core_color_roles[index] { return false } }
	for left, index in a.theme.extension_color_roles { if left != b.theme.extension_color_roles[index] { return false } }
	for left, index in a.theme.extension_length_roles { if left != b.theme.extension_length_roles[index] { return false } }
	for left, index in a.theme.button_recipes {
		if !theme_preview_button_recipe_equal(left, b.theme.button_recipes[index]) { return false }
	}
	for left, index in a.debug.tokens {
		right := b.debug.tokens[index]
		if left.id != right.id || left.name != right.name || left.kind != right.kind || left.alias_target != right.alias_target { return false }
	}
	for left, index in a.debug.core_roles {
		right := b.debug.core_roles[index]
		if left.role != right.role || left.token != right.token { return false }
	}
	for left, index in a.debug.extension_roles {
		right := b.debug.extension_roles[index]
		if left.color_id != right.color_id || left.length_id != right.length_id ||
			left.name != right.name || left.kind != right.kind { return false }
	}
	for left, index in a.debug.materials {
		if left.name != b.debug.materials[index].name { return false }
	}
	for left, index in a.debug.button_recipes {
		if left.variant != b.debug.button_recipes[index].variant { return false }
	}
	return true
}

theme_preview_button_recipe_equal :: proc(a, b: Theme_Button_Recipe_Override) -> bool {
	if a.variant != b.variant || a.has_surface_role != b.has_surface_role || a.surface_role != b.surface_role ||
		a.has_text_role != b.has_text_role || a.text_role != b.text_role ||
		a.has_surface_visible != b.has_surface_visible || a.surface_visible != b.surface_visible ||
		a.has_selected_indicator != b.has_selected_indicator || a.selected_indicator != b.selected_indicator ||
		a.has_selected_indicator_role != b.has_selected_indicator_role || a.selected_indicator_role != b.selected_indicator_role ||
		a.has_focus_indicator_keyboard != b.has_focus_indicator_keyboard ||
		a.focus_indicator_keyboard_only != b.focus_indicator_keyboard_only ||
		a.has_focus_role != b.has_focus_role || a.focus_role != b.focus_role ||
		a.has_semantic_active_role != b.has_semantic_active_role || a.semantic_active_role != b.semantic_active_role {
		return false
	}
	if len(a.states) != len(b.states) { return false }
	for left, index in a.states {
		right := b.states[index]
		if left.has_surface_role != right.has_surface_role || left.surface_role != right.surface_role ||
			left.has_surface_mix != right.has_surface_mix || left.surface_mix != right.surface_mix ||
			left.has_text_role != right.has_text_role || left.text_role != right.text_role ||
			left.has_text_mix != right.has_text_mix || left.text_mix != right.text_mix { return false }
	}
	return true
}
