package theme

import "core:testing"
import "core:math"

json_test_find :: proc(haystack, needle: string) -> int {
	if len(needle) > len(haystack) { return -1 }
	for start in 0..=len(haystack)-len(needle) {
		if haystack[start:start+len(needle)] == needle { return start }
	}
	return -1
}

json_test_line_column :: proc(source: string, offset: int) -> (line, column: u32) {
	line, column = 1, 1
	for index in 0..<offset {
		if source[index] == '\n' { line += 1; column = 1 } else { column += 1 }
	}
	return
}

json_test_has_diagnostic :: proc(output: Theme_JSON_Output, code: Theme_JSON_Diagnostic_Code) -> bool {
	for diagnostic in output.diagnostics {
		if diagnostic.code == code { return true }
	}
	return false
}

@(test)
test_theme_json_frontend_maps_strict_dtcg_subset :: proc(t: ^testing.T) {
	input := "{\"schema\":1,\"contract\":\"0.2\",\"extends\":\"alicorn.base\",\"tokens\":{\"color.ink\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0.08,0.1,0.14],\"alpha\":0.9}},\"space.small\":{\"$type\":\"dimension\",\"$value\":{\"value\":8,\"unit\":\"px\"}},\"color.primary\":{\"$type\":\"color\",\"$value\":\"{color.ink}\"}},\"roles\":{\"core\":{\"text\":\"{color.primary}\"},\"extensions\":{\"app.editor.gutter\":{\"$type\":\"dimension\",\"$value\":\"{space.small}\"}}}}"
	output := theme_json_parse(input, "themes/workstation.json")
	defer theme_json_output_destroy(&output)
	testing.expect(t, output.ok && output.has_source, "valid strict DTCG-subset input should produce a source model")
	testing.expect(t, output.source.metadata.schema_version == THEME_SOURCE_SCHEMA_VERSION &&
		output.source.metadata.contract == THEME_CONTRACT_VERSION && output.source.metadata.span.path == "themes/workstation.json",
		"top-level schema/contract and their source span must populate Theme_Source_Metadata")
	testing.expect(t, output.extends == "alicorn.base", "optional extends metadata should be retained")
	testing.expect(t, len(output.source.tokens) == 3 && len(output.source.core_roles) == 1 &&
		len(output.source.extension_roles) == 1, "tokens and both role namespaces should map to the source model")
	if len(output.source.tokens) == 3 {
		for definition in output.source.tokens {
			if definition.name == "color.primary" {
				alias, is_alias := definition.value.(Theme_Alias)
				testing.expect(t, is_alias && alias.target == "color.ink", "DTCG references should remain symbolic aliases")
			}
			if definition.name == "space.small" {
				length, is_length := definition.value.(Theme_Length)
				testing.expect(t, is_length && f32(length) == 8, "px dimensions should map directly to logical units")
			}
		}
	}
	if len(output.source.core_roles) == 1 {
		testing.expect(t, output.source.core_roles[0].role == .Text && output.source.core_roles[0].token == "color.primary",
			"core role mapping should use the fixed semantic enum")
	}
	if len(output.source.extension_roles) == 1 {
		role := output.source.extension_roles[0]
		testing.expect(t, role.name == "app.editor.gutter" && role.kind == .Length && role.token == "space.small",
			"extension roles should preserve namespace, kind, and token reference")
	}
}

@(test)
test_theme_json_frontend_maps_material_and_button_recipe_authoring :: proc(t: ^testing.T) {
	input := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"scratchpad.ink\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0.2,0.2,0.2]}}},\"materials\":{\"app.scratchpad.editor.paper\":{\"kind\":\"analytic_relief\",\"bevel_width\":1,\"bevel_strength\":0.36,\"inner_shadow_strength\":0.18}},\"recipes\":{\"button\":{\"tab\":{\"selected_indicator_role\":\"accent\",\"states\":{\"hovered\":{\"surface_mix\":0.42}}}}}}"
	parsed := theme_json_parse(input, "scratchpad-paper.json")
	defer theme_json_output_destroy(&parsed)
	testing.expect(t, parsed.ok && len(parsed.source.materials) == 1 && len(parsed.source.button_recipes) == 1,
		"strict JSON should map a namespaced material and sparse button recipe")
	if !parsed.ok || len(parsed.source.materials) != 1 || len(parsed.source.button_recipes) != 1 { return }

	material := parsed.source.materials[0]
	testing.expect(t, material.name == "app.scratchpad.editor.paper" && material.value.kind == .Analytic_Relief &&
		material.value.bevel_width == 1 && material.value.bevel_strength == 0.36 &&
		material.value.inner_shadow_strength == 0.18,
		"material names and bounded analytic parameters should survive strict JSON parsing")
	recipe := parsed.source.button_recipes[0]
	testing.expect(t, recipe.variant == .Tab && recipe.has_selected_indicator_role &&
		recipe.selected_indicator_role == .Accent && recipe.states[int(Theme_Button_State.Hovered)].has_surface_mix &&
		recipe.states[int(Theme_Button_State.Hovered)].surface_mix == 0.42,
		"recipe parsing should preserve the selected indicator and only the authored hover transform")
}

@(test)
test_theme_json_srgb_midpoint_decodes_to_linear_srgb :: proc(t: ^testing.T) {
	input := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"color.midpoint\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0.5,0.5,0.5]}}}}"
	parsed := theme_json_parse(input, "linear-color.json")
	defer theme_json_output_destroy(&parsed)
	testing.expect(t, parsed.ok, "valid sRGB color should decode successfully")
	if parsed.ok {
		compiled := theme_compile({parsed.source})
		defer theme_output_destroy(&compiled)
		testing.expect(t, compiled.ok, "decoded color should be accepted by the format-neutral compiler")
		if compiled.ok && len(compiled.debug.tokens) == 1 {
			id := compiled.debug.tokens[0].id
			color := compiled.theme.colors[int(id)-1]
			testing.expect(t, math.abs(color.r-0.21404114) < 0.000001 &&
				math.abs(color.g-0.21404114) < 0.000001 && math.abs(color.b-0.21404114) < 0.000001,
				"encoded sRGB midpoint 0.5 must become approximately 0.21404114 linear-sRGB")
		}
	}
}

@(test)
test_theme_json_frontend_preserves_byte_line_and_column_spans :: proc(t: ^testing.T) {
	input := "{\n  \"schema\": 1,\n  \"contract\": \"0.2\",\n  \"tokens\": {\n    \"color.red\": {\"$type\":\"color\", \"$value\":{\"colorSpace\":\"srgb\",\"components\":[1,0,0]}}\n  }\n}"
	output := theme_json_parse(input, "span.json")
	defer theme_json_output_destroy(&output)
	key_offset := json_test_find(input, "\"color.red\"")
	line, column := json_test_line_column(input, key_offset)
	testing.expect(t, output.ok && len(output.source.tokens) == 1, "span fixture should parse")
	if len(output.source.tokens) == 1 {
		span := output.source.tokens[0].span
		testing.expect(t, span.path == "span.json" && span.start_offset == u64(key_offset) &&
			span.end_offset == u64(key_offset+len("\"color.red\"")) && span.line == line && span.column == column,
			"token spans should retain exact source byte range and one-based line/column")
	}
	metadata_span := output.source.metadata.span
	testing.expect(t, metadata_span.path == "span.json" && metadata_span.start_offset == 0 &&
		metadata_span.line == 1 && metadata_span.column == 1,
		"source metadata should carry the root location and source path")
}

@(test)
test_theme_json_frontend_detects_duplicate_token_and_role_declarations :: proc(t: ^testing.T) {
	tokens := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"a\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,0]}},\"a\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[1,1,1]}}}}"
	token_output := theme_json_parse(tokens, "duplicate-token.json")
	defer theme_json_output_destroy(&token_output)
	testing.expect(t, !token_output.ok && json_test_has_diagnostic(token_output, .Duplicate_Token_Declaration),
		"duplicate token names must be rejected with a token-specific diagnostic")
	if json_test_has_diagnostic(token_output, .Duplicate_Token_Declaration) {
		for diagnostic in token_output.diagnostics {
			if diagnostic.code == .Duplicate_Token_Declaration {
				expected := json_test_find(tokens, "\"a\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[1,1,1]}")
				testing.expect(t, diagnostic.span.path == "duplicate-token.json" && diagnostic.span.start_offset == u64(expected),
					"duplicate token diagnostic should point at the later declaration")
			}
		}
	}

	roles := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"ink\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,0]}}},\"roles\":{\"core\":{\"text\":\"{ink}\",\"text\":\"{ink}\"}}}"
	role_output := theme_json_parse(roles, "duplicate-role.json")
	defer theme_json_output_destroy(&role_output)
	testing.expect(t, !role_output.ok && json_test_has_diagnostic(role_output, .Duplicate_Role_Declaration),
		"duplicate role names must be rejected with a role-specific diagnostic")
}

@(test)
test_theme_json_frontend_rejects_malformed_and_unsupported_forms :: proc(t: ^testing.T) {
	malformed := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{},}"
	bad_json := theme_json_parse(malformed, "malformed.json")
	defer theme_json_output_destroy(&bad_json)
	testing.expect(t, !bad_json.ok && json_test_has_diagnostic(bad_json, .Syntax),
		"strict JSON must reject trailing commas")
	if len(bad_json.diagnostics) > 0 {
		testing.expect(t, bad_json.diagnostics[0].span.path == "malformed.json" &&
			bad_json.diagnostics[0].span.start_offset > 0 && bad_json.diagnostics[0].span.line == 1,
			"syntax errors should include deterministic source locations")
	}
	malformed_array := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"c\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,0,]}}}}"
	bad_array := theme_json_parse(malformed_array, "malformed-array.json")
	defer theme_json_output_destroy(&bad_array)
	testing.expect(t, !bad_array.ok && json_test_has_diagnostic(bad_array, .Syntax),
		"array parse failure must reject trailing comma and safely release partial child nodes")

	bad_nul := theme_json_parse("{}\x00{}", "nul.json")
	defer theme_json_output_destroy(&bad_nul)
	testing.expect(t, !bad_nul.ok && json_test_has_diagnostic(bad_nul, .Syntax),
		"NUL must not be treated as end-of-document by the strict theme frontend")

	display_p3 := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"c\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"display-p3\",\"components\":[0,0,0]}}}}"
	p3_output := theme_json_parse(display_p3, "p3.json")
	defer theme_json_output_destroy(&p3_output)
	testing.expect(t, !p3_output.ok && json_test_has_diagnostic(p3_output, .Unsupported_Value),
		"unsupported color spaces must be rejected rather than coerced")

	unsupported_length := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"space\":{\"$type\":\"dimension\",\"$value\":{\"value\":2,\"unit\":\"em\"}}}}"
	length_output := theme_json_parse(unsupported_length, "unit.json")
	defer theme_json_output_destroy(&length_output)
	testing.expect(t, !length_output.ok && json_test_has_diagnostic(length_output, .Unsupported_Value),
		"unsupported dimensions must not be silently interpreted")

	bad_color := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"c\":{\"$type\":\"color\",\"$value\":\"#ffffff\"}}}"
	color_output := theme_json_parse(bad_color, "hex.json")
	defer theme_json_output_destroy(&color_output)
	testing.expect(t, !color_output.ok && json_test_has_diagnostic(color_output, .Unsupported_Value),
		"hex strings are not silently accepted as an alternate color encoding")

	transparent := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"c\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0.2,0.3,0.4],\"alpha\":0}}}}"
	transparent_output := theme_json_parse(transparent, "transparent.json")
	defer theme_json_output_destroy(&transparent_output)
	testing.expect(t, !transparent_output.ok && json_test_has_diagnostic(transparent_output, .Invalid_Color),
		"zero alpha must be rejected consistently with the core/runtime color contract")
}

@(test)
test_theme_json_frontend_requires_supported_versions :: proc(t: ^testing.T) {
	wrong_schema := "{\"schema\":2,\"contract\":\"0.2\",\"tokens\":{\"c\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,0]}}}}"
	schema_output := theme_json_parse(wrong_schema, "schema.json")
	defer theme_json_output_destroy(&schema_output)
	testing.expect(t, !schema_output.ok && !schema_output.has_source &&
		json_test_has_diagnostic(schema_output, .Invalid_Schema),
		"unsupported schema versions must not produce a compiler-ready model")
	testing.expect(t, len(schema_output.source.tokens) == 0 && schema_output.source.metadata.schema_version == 0,
		"invalid-version input must not be represented as a source model with fabricated version metadata")

	wrong_contract := "{\"schema\":1,\"contract\":\"0.3\",\"tokens\":{\"c\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,0]}}}}"
	contract_output := theme_json_parse(wrong_contract, "contract.json")
	defer theme_json_output_destroy(&contract_output)
	testing.expect(t, !contract_output.ok && !contract_output.has_source &&
		json_test_has_diagnostic(contract_output, .Invalid_Contract),
		"newer contracts must be rejected before constructing a source model")

	missing_version := "{\"contract\":\"0.2\",\"tokens\":{}}"
	missing_output := theme_json_parse(missing_version, "missing-version.json")
	defer theme_json_output_destroy(&missing_output)
	testing.expect(t, !missing_output.ok && !missing_output.has_source &&
		json_test_has_diagnostic(missing_output, .Missing_Field),
		"missing version declarations must prevent source-model construction")
}

@(test)
test_theme_json_frontend_mapping_is_declaration_order_independent :: proc(t: ^testing.T) {
	first := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"color.blue\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,1]}},\"color.red\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[1,0,0]}},\"color.alias\":{\"$type\":\"color\",\"$value\":\"{color.red}\"}},\"roles\":{\"core\":{\"accent\":\"{color.alias}\",\"text\":\"{color.blue}\"},\"extensions\":{\"app.editor.line\":{\"$type\":\"color\",\"$value\":\"{color.red}\"}}}}"
	second := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"color.alias\":{\"$type\":\"color\",\"$value\":\"{color.red}\"},\"color.red\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[1,0,0]}},\"color.blue\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0,0,1]}}},\"roles\":{\"extensions\":{\"app.editor.line\":{\"$value\":\"{color.red}\",\"$type\":\"color\"}},\"core\":{\"text\":\"{color.blue}\",\"accent\":\"{color.alias}\"}}}"
	a := theme_json_parse(first, "a.json")
	defer theme_json_output_destroy(&a)
	b := theme_json_parse(second, "b.json")
	defer theme_json_output_destroy(&b)
	testing.expect(t, a.ok && b.ok, "both valid declaration orders should parse")
	if a.ok && b.ok {
		compiled_a := theme_compile({a.source})
		defer theme_output_destroy(&compiled_a)
		compiled_b := theme_compile({b.source})
		defer theme_output_destroy(&compiled_b)
		testing.expect(t, compiled_a.ok && compiled_b.ok &&
			compiled_a.theme.content_signature == compiled_b.theme.content_signature,
			"frontend mapping and compilation should be deterministic across declaration order")
	}
}
