package theme

import alicorn "../runtime"
import "core:os"
import "core:testing"

THEME_COMPAT_SCRATCHPAD_WARM_COMPILED :: u64(14928254554106585465)
THEME_COMPAT_SCRATCHPAD_WARM_RESOLVED :: u64(6428365980246866365)
THEME_COMPAT_SCRATCHPAD_COOL_COMPILED :: u64(1850998788596845100)
THEME_COMPAT_SCRATCHPAD_COOL_RESOLVED :: u64(1733854783087550626)
THEME_COMPAT_SPARSE_RESOLVED :: u64(7211035369368032307)

@(test)
test_supported_theme_contract_matrix_and_sparse_fallbacks :: proc(t: ^testing.T) {
	theme_test_expect_contract_fixture(t, "theme/testdata/compat-contract-0.0.json", 0)
	theme_test_expect_contract_fixture(t, "theme/testdata/compat-contract-0.1-sparse.json", 1)
	theme_test_expect_contract_fixture(t, "theme/testdata/compat-contract-0.2-sparse.json", 2)

	compiled := theme_test_compile_json_fixture(t, "theme/testdata/compat-contract-0.1-sparse.json")
	defer theme_output_destroy(&compiled)
	if !compiled.ok { return }
	runtime_theme, adapted := theme_runtime_style_theme(compiled)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	testing.expect(t, adapted, "a sparse historical theme should adapt with all required core values")
	if !adapted { return }
	defaults := alicorn.DEFAULT_STYLE_THEME
	for role in alicorn.Style_Color_Role {
		if role == .Count { continue }
		if role == .Text {
			ink := compiled.theme.core_color_roles[int(Core_Color_Role.Text)]
			actual := compiled.theme.colors[int(u32(ink))-1]
			testing.expect(t, runtime_theme.colors[int(role)] == alicorn.Color{actual.r, actual.g, actual.b, actual.a},
				"the explicitly bound text role should resolve to the fixture token")
		} else {
			testing.expect(t, runtime_theme.colors[int(role)] == defaults.colors[int(role)],
				"an omitted core role in an older contract should keep its required Alicorn fallback")
		}
	}
	testing.expect(t, len(runtime_theme.extension_color_roles) == 1 && len(runtime_theme.extension_length_roles) == 1,
		"app and vendor extensions should remain typed separately from core roles")
	testing.expect(t, len(compiled.debug.core_roles) == 1 && compiled.debug.core_roles[0].role == .Text &&
		compiled.debug.core_roles[0].token == "compat.ink" &&
		compiled.debug.core_roles[0].span.path == "theme/testdata/compat-contract-0.1-sparse.json",
		"core-role debug metadata should preserve its binding source independently from token provenance")
	testing.expect(t, len(compiled.debug.extension_roles) == 2 &&
		compiled.debug.extension_roles[0].name == "app.scratchpad.gutter" &&
		compiled.debug.extension_roles[1].name == "vendor.example.scratchpad.meter",
		"extension names should remain explicit and deterministically ordered")
	materials, materials_ok := theme_runtime_style_materials(compiled)
	defer theme_runtime_style_materials_destroy(&materials)
	testing.expect(t, materials_ok && len(materials) == 0,
		"omitted named materials should not synthesize app/vendor definitions")
	testing.expect(t, alicorn.STYLE_MATERIAL_FLAT.kind == .Flat && alicorn.MATERIAL_FLAT == 0,
		"the runtime flat material should remain the safe zero-cost fallback")
}

@(test)
test_theme_compatibility_rejects_negative_fixtures :: proc(t: ^testing.T) {
	paths := [3]string{
		"theme/testdata/compat-schema-2.json",
		"theme/testdata/compat-contract-0.3.json",
		"theme/testdata/compat-contract-1.0.json",
	}
	expected_codes := [3]Theme_JSON_Diagnostic_Code{.Invalid_Schema, .Invalid_Contract, .Invalid_Contract}
	for path, index in paths {
		parsed := theme_test_parse_json_fixture(t, path)
		found := false
		for diagnostic in parsed.diagnostics { if diagnostic.code == expected_codes[index] { found = true } }
		testing.expect(t, !parsed.ok && found,
			"unsupported schema, future contract minor, and different major fixtures should fail with the specific parser diagnostic")
		theme_json_output_destroy(&parsed)
	}

	unknown := theme_test_parse_json_fixture(t, "theme/testdata/compat-unknown-core-role.json")
	defer theme_json_output_destroy(&unknown)
	unknown_role := false
	for diagnostic in unknown.diagnostics { if diagnostic.code == .Invalid_Core_Role { unknown_role = true } }
	testing.expect(t, !unknown.ok && unknown_role,
		"an unknown core role must fail during source validation instead of becoming an extension")

	color := theme_test_parse_json_fixture(t, "theme/testdata/compat-extension-color.json")
	defer theme_json_output_destroy(&color)
	dimension := theme_test_parse_json_fixture(t, "theme/testdata/compat-extension-dimension.json")
	defer theme_json_output_destroy(&dimension)
	testing.expect(t, color.ok && dimension.ok, "extension type-change fixtures should parse before layered compilation")
	if color.ok && dimension.ok {
		incompatible := theme_compile({color.source, dimension.source})
		defer theme_output_destroy(&incompatible)
		found := false
		for diagnostic in incompatible.diagnostics { if diagnostic.code == .Extension_Role_Type_Changed { found = true } }
		testing.expect(t, !incompatible.ok && found,
			"an overlay must not change an app/vendor extension role's type")
	}
}

@(test)
test_theme_deprecation_warning_carries_a_replacement :: proc(t: ^testing.T) {
	diagnostic := Theme_Diagnostic{
		code=.Deprecated_Theme_Feature,
		severity=.Warning,
		path="legacy-theme.json",
		span=Source_Span{path="legacy-theme.json", line=4, column=9},
		related_name="old.role",
		replacement="new.role",
	}
	copy := theme_copy_diagnostic(diagnostic, context.allocator)
	warnings := [1]Theme_Diagnostic{copy}
	testing.expect(t, copy.severity == .Warning && copy.code == .Deprecated_Theme_Feature &&
		copy.path == "legacy-theme.json" && copy.span.path == copy.path &&
		copy.related_name == "old.role" && copy.replacement == "new.role",
		"a nonfatal deprecation diagnostic should retain a source location and an exact replacement")
	testing.expect(t, !theme_diagnostics_have_errors(warnings[:]),
		"a deprecation warning should not make a compatible theme fail compilation")
	error := Theme_Diagnostic{severity=.Error}
	errors := [1]Theme_Diagnostic{error}
	testing.expect(t, theme_diagnostics_have_errors(errors[:]),
		"ordinary validation errors should still reject compilation")
	delete(copy.path)
	delete(copy.related_name)
	delete(copy.replacement)
}

@(test)
test_scratchpad_theme_compatibility_fixtures_have_frozen_resolutions :: proc(t: ^testing.T) {
	paths := [2]string{
		"theme/testdata/scratchpad-warm-0.2.json",
		"theme/testdata/scratchpad-cool-light-0.2.json",
	}
	for index in 0..<len(paths) {
		compiled := theme_test_compile_json_fixture(t, paths[index])
		if !compiled.ok {
			testing.expect(t, false, "Scratchpad compatibility fixture should compile")
			theme_output_destroy(&compiled)
			continue
		}
		runtime_theme, adapted := theme_runtime_style_theme(compiled)
		if !adapted {
			testing.expect(t, false, "Scratchpad compatibility fixtures must adapt to Alicorn's runtime theme")
			theme_output_destroy(&compiled)
			continue
		}
		compiled_signature := compiled.theme.content_signature
		materials, materials_ok := theme_runtime_style_materials(compiled)
		if !materials_ok {
			testing.expect(t, false, "Scratchpad named materials must adapt to runtime material definitions")
			theme_runtime_style_theme_destroy(&runtime_theme)
			theme_output_destroy(&compiled)
			continue
		}
		runtime_signature := theme_test_resolved_theme_signature(runtime_theme, materials)
		expected_compiled := THEME_COMPAT_SCRATCHPAD_WARM_COMPILED
		expected_resolved := THEME_COMPAT_SCRATCHPAD_WARM_RESOLVED
		if index == 1 {
			expected_compiled = THEME_COMPAT_SCRATCHPAD_COOL_COMPILED
			expected_resolved = THEME_COMPAT_SCRATCHPAD_COOL_RESOLVED
		}
		testing.expect(t, compiled_signature == expected_compiled && runtime_signature == expected_resolved,
			"real Scratchpad theme values and inherited Alicorn defaults must match their release-contract snapshots")
		theme_runtime_style_materials_destroy(&materials)
		theme_runtime_style_theme_destroy(&runtime_theme)
		theme_output_destroy(&compiled)
	}

	sparse := theme_test_compile_json_fixture(t, "theme/testdata/compat-contract-0.2-sparse.json")
	defer theme_output_destroy(&sparse)
	if !sparse.ok {
		testing.expect(t, false, "the sparse current compatibility fixture should compile")
		return
	}
	runtime_theme, adapted := theme_runtime_style_theme(sparse)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	if adapted {
		materials, materials_ok := theme_runtime_style_materials(sparse)
		defer theme_runtime_style_materials_destroy(&materials)
		testing.expect(t, materials_ok && theme_test_resolved_theme_signature(runtime_theme, materials) == THEME_COMPAT_SPARSE_RESOLVED,
			"the sparse theme's inherited runtime values must match the frozen Alicorn fallback snapshot")
		defaults := alicorn.DEFAULT_STYLE_THEME
		for index in 0..<alicorn.BUTTON_VARIANT_COUNT {
			testing.expect(t, runtime_theme.button_recipes.recipes[index] == defaults.button_recipes.recipes[index],
				"an omitted recipe must inherit the exact typed default for every button variant")
		}
	} else {
		testing.expect(t, false, "the sparse current theme should adapt")
	}
}

theme_test_expect_contract_fixture :: proc(t: ^testing.T, path: string, expected_minor: u16) {
	compiled := theme_test_compile_json_fixture(t, path)
	defer theme_output_destroy(&compiled)
	testing.expect(t, compiled.ok && compiled.theme.contract.major == THEME_CONTRACT_VERSION.major &&
		compiled.theme.contract.minor == expected_minor,
		"supported historical contract fixtures should compile and retain their declared effective minor")
}

theme_test_compile_json_fixture :: proc(t: ^testing.T, path: string) -> Theme_Compile_Output {
	parsed := theme_test_parse_json_fixture(t, path)
	defer theme_json_output_destroy(&parsed)
	testing.expect(t, parsed.ok, "positive compatibility fixtures should parse")
	if !parsed.ok { return {} }
	return theme_compile({parsed.source})
}

theme_test_parse_json_fixture :: proc(t: ^testing.T, path: string) -> Theme_JSON_Output {
	data, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		testing.expect(t, false, "theme compatibility fixture must exist and be readable")
		return {}
	}
	defer delete(data)
	return theme_json_parse(string(data), path)
}

theme_test_resolved_theme_signature :: proc(value: alicorn.Style_Theme, materials: []alicorn.Style_Material_Definition) -> u64 {
	h: u64 = 14695981039346656037
	for color, index in value.colors {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_u64(h, u64(transmute(u32)color.r))
		h = theme_hash_u64(h, u64(transmute(u32)color.g))
		h = theme_hash_u64(h, u64(transmute(u32)color.b))
		h = theme_hash_u64(h, u64(transmute(u32)color.a))
	}
	for color, index in value.color_tokens {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_test_hash_color(h, color)
	}
	for length, index in value.length_tokens {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_u64(h, u64(transmute(u32)length.logical_units))
	}
	for token, index in value.core_color_tokens {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_u64(h, u64(token))
	}
	for binding in value.extension_color_roles {
		h = theme_hash_u64(h, u64(binding.role))
		h = theme_hash_u64(h, u64(binding.token))
	}
	for binding in value.extension_length_roles {
		h = theme_hash_u64(h, u64(binding.role))
		h = theme_hash_u64(h, u64(binding.token))
	}
	for recipe, index in value.button_recipes.recipes {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_u64(h, u64(recipe.defined))
		h = theme_hash_u64(h, u64(recipe.surface_role))
		h = theme_hash_u64(h, u64(recipe.text_role))
		h = theme_hash_u64(h, u64(recipe.surface_visible))
		h = theme_hash_u64(h, u64(recipe.selected_indicator))
		h = theme_hash_u64(h, u64(recipe.selected_indicator_role))
		h = theme_hash_u64(h, u64(recipe.focus_indicator_mode))
		h = theme_hash_u64(h, u64(recipe.focus_role))
		h = theme_hash_u64(h, u64(recipe.semantic_active_role))
		transforms := [4]alicorn.Style_Transform{recipe.selected, recipe.hovered, recipe.pressed, recipe.disabled}
		for transform in transforms {
			h = theme_hash_u64(h, u64(transform.surface_role))
			h = theme_hash_u64(h, u64(transmute(u32)transform.surface_mix))
			h = theme_hash_u64(h, u64(transform.text_role))
			h = theme_hash_u64(h, u64(transmute(u32)transform.text_mix))
		}
	}
	h = theme_hash_u64(h, u64(value.checkbox_recipe.defined))
	h = theme_test_hash_control_part_recipe(h, value.checkbox_recipe.box)
	h = theme_test_hash_control_part_recipe(h, value.checkbox_recipe.checkmark)
	h = theme_test_hash_control_part_recipe(h, value.checkbox_recipe.label)
	h = theme_hash_u64(h, u64(value.checkbox_recipe.focus_role))
	h = theme_hash_u64(h, u64(value.checkbox_recipe.focus_indicator_mode))
	h = theme_hash_u64(h, u64(value.slider_recipe.defined))
	h = theme_test_hash_control_part_recipe(h, value.slider_recipe.track)
	h = theme_test_hash_control_part_recipe(h, value.slider_recipe.fill)
	h = theme_test_hash_control_part_recipe(h, value.slider_recipe.thumb)
	h = theme_test_hash_control_part_recipe(h, value.slider_recipe.label)
	h = theme_hash_u64(h, u64(value.slider_recipe.focus_role))
	h = theme_hash_u64(h, u64(value.slider_recipe.focus_indicator_mode))
	h = theme_hash_u64(h, u64(value.text_field_recipe.defined))
	h = theme_hash_u64(h, u64(transmute(u32)value.text_field_recipe.horizontal_inset))
	h = theme_hash_u64(h, u64(value.text_field_recipe.surface_role))
	h = theme_hash_u64(h, u64(value.text_field_recipe.text_role))
	h = theme_hash_u64(h, u64(value.text_field_recipe.border_role))
	h = theme_hash_u64(h, u64(value.text_field_recipe.focused_border_role))
	h = theme_hash_u64(h, u64(value.text_field_recipe.focus_role))
	h = theme_hash_u64(h, u64(value.text_field_recipe.selection_role))
	h = theme_hash_u64(h, u64(value.text_field_recipe.caret_role))
	h = theme_test_hash_control_part_transform(h, value.text_field_recipe.hovered)
	h = theme_hash_u64(h, u64(value.scrollbar_recipe.defined))
	h = theme_hash_u64(h, u64(value.scrollbar_recipe.track_role))
	h = theme_hash_u64(h, u64(value.scrollbar_recipe.thumb_role))
	h = theme_hash_u64(h, u64(value.scrollbar_recipe.corner_role))
	h = theme_hash_u64(h, u64(value.scrollbar_recipe.hovered_thumb.role))
	h = theme_hash_u64(h, u64(transmute(u32)value.scrollbar_recipe.hovered_thumb.mix))
	h = theme_hash_u64(h, u64(value.scrollbar_recipe.pressed_thumb.role))
	h = theme_hash_u64(h, u64(transmute(u32)value.scrollbar_recipe.pressed_thumb.mix))
	for material, index in materials {
		h = theme_hash_u64(h, u64(index+1))
		h = theme_hash_string(h, material.name)
		h = theme_hash_u64(h, u64(material.material.kind))
		h = theme_hash_u64(h, u64(transmute(u32)material.material.bevel_width))
		h = theme_hash_u64(h, u64(transmute(u32)material.material.bevel_strength))
		h = theme_hash_u64(h, u64(transmute(u32)material.material.inner_shadow_strength))
		h = theme_hash_u64(h, u64(transmute(u32)material.material.outer_shadow_strength))
		h = theme_hash_u64(h, u64(transmute(u32)material.material.outer_shadow_radius))
	}
	return h
}

theme_test_hash_control_part_recipe :: proc(h: u64, recipe: alicorn.Control_Part_Recipe) -> u64 {
	hash := h
	hash = theme_hash_u64(hash, u64(recipe.surface_role))
	hash = theme_hash_u64(hash, u64(recipe.text_role))
	hash = theme_hash_u64(hash, u64(recipe.border_role))
	hash = theme_test_hash_control_part_transform(hash, recipe.selected)
	hash = theme_test_hash_control_part_transform(hash, recipe.hovered)
	hash = theme_test_hash_control_part_transform(hash, recipe.pressed)
	hash = theme_test_hash_control_part_transform(hash, recipe.disabled)
	return hash
}

theme_test_hash_control_part_transform :: proc(h: u64, transform: alicorn.Control_Part_Transform) -> u64 {
	hash := h
	hash = theme_hash_u64(hash, u64(transform.surface_role))
	hash = theme_hash_u64(hash, u64(transmute(u32)transform.surface_mix))
	hash = theme_hash_u64(hash, u64(transform.text_role))
	hash = theme_hash_u64(hash, u64(transmute(u32)transform.text_mix))
	hash = theme_hash_u64(hash, u64(transform.border_role))
	hash = theme_hash_u64(hash, u64(transmute(u32)transform.border_mix))
	return hash
}

theme_test_hash_color :: proc(h: u64, color: alicorn.Color) -> u64 {
	hash := h
	hash = theme_hash_u64(hash, u64(transmute(u32)color.r))
	hash = theme_hash_u64(hash, u64(transmute(u32)color.g))
	hash = theme_hash_u64(hash, u64(transmute(u32)color.b))
	hash = theme_hash_u64(hash, u64(transmute(u32)color.a))
	return hash
}
