package theme

import "core:testing"

TEST_THEME_METADATA :: Theme_Source_Metadata{
	schema_version=THEME_SOURCE_SCHEMA_VERSION,
	contract=THEME_CONTRACT_VERSION,
	span=Source_Span{path="theme.test", start_offset=0, end_offset=1, line=1, column=1},
}

test_span :: proc(offset: u64) -> Source_Span {
	return Source_Span{path="theme.test", start_offset=offset, end_offset=offset+1, line=u32(offset+1), column=1}
}

test_color :: proc(r, g, b: f32) -> Theme_Token_Value {
	return Theme_Color{r, g, b, 1}
}

test_length :: proc(value: f32) -> Theme_Token_Value {
	return Theme_Length(value)
}

test_alias :: proc(target: string) -> Theme_Token_Value {
	return Theme_Alias{target}
}

test_definition :: proc(name: string, kind: Token_Kind, value: Theme_Token_Value, offset: u64) -> Token_Definition {
	return Token_Definition{name=name, kind=kind, value=value, span=test_span(offset)}
}

test_diagnostic_index :: proc(output: Theme_Compile_Output, code: Diagnostic_Code) -> int {
	for diagnostic, index in output.diagnostics { if diagnostic.code == code { return index } }
	return -1
}

test_runtime_style_extension_hash :: proc(namespace, name: string, type_tag: u64) -> u64 {
	h: u64 = 1469598103934665603
	h = (h ~ type_tag) * 1099511628211
	for index := 0; index < len(namespace); index += 1 { h = (h ~ u64(namespace[index])) * 1099511628211 }
	h = (h ~ u64('.')) * 1099511628211
	for index := 0; index < len(name); index += 1 { h = (h ~ u64(name[index])) * 1099511628211 }
	if h == 0 { return 1 }
	return h
}

@(test)
test_theme_alias_chain_compiles_to_typed_value :: proc(t: ^testing.T) {
	source := Theme_Source_Model{metadata=TEST_THEME_METADATA, tokens={
		test_definition("palette.ink", .Color, test_color(0.1, 0.2, 0.3), 1),
		test_definition("text.primary", .Color, test_alias("palette.ink"), 2),
		test_definition("text.editor", .Color, test_alias("text.primary"), 3),
	}}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	testing.expect(t, output.ok, "a valid same-kind alias chain should compile")
	testing.expect(t, len(output.theme.colors) == 3 && len(output.theme.lengths) == 0,
		"compiled values should be stored in compact arrays by type")
	last := output.debug.tokens[1]
	value := output.theme.colors[int(last.id)-1]
	testing.expect(t, value == Theme_Color{0.1, 0.2, 0.3, 1}, "aliases should flatten to the resolved color value")
	testing.expect(t, last.alias_target == "text.primary", "debug provenance should retain the immediate authored alias")
}

@(test)
test_theme_alias_wrong_type_is_structured_error :: proc(t: ^testing.T) {
	source := Theme_Source_Model{metadata=TEST_THEME_METADATA, tokens={
		test_definition("space.small", .Length, test_length(8), 1),
		test_definition("color.bad", .Color, test_alias("space.small"), 8),
	}}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	index := test_diagnostic_index(output, .Alias_Type_Mismatch)
	testing.expect(t, !output.ok && index >= 0, "a color alias to a length must fail type checking")
	if index >= 0 {
		diagnostic := output.diagnostics[index]
		testing.expect(t, diagnostic.severity == .Error && diagnostic.path == "theme.test" && diagnostic.span.start_offset == 8,
			"the wrong-type diagnostic should carry severity, source path, and authored span")
		testing.expect(t, diagnostic.expected_kind == .Color && diagnostic.actual_kind == .Length,
			"the wrong-type diagnostic should identify both types")
	}
}

@(test)
test_theme_alias_cycle_reports_symbol_path :: proc(t: ^testing.T) {
	source := Theme_Source_Model{metadata=TEST_THEME_METADATA, tokens={
		test_definition("a", .Color, test_alias("b"), 4),
		test_definition("b", .Color, test_alias("c"), 5),
		test_definition("c", .Color, test_alias("a"), 6),
	}}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	index := test_diagnostic_index(output, .Alias_Cycle)
	testing.expect(t, !output.ok && index >= 0, "an alias cycle must fail compilation")
	if index >= 0 {
		cycle := output.diagnostics[index].symbol_path
		testing.expect(t, len(cycle) == 4 && cycle[0] == cycle[3], "the cycle path should repeat its first symbol at the end")
		testing.expect(t, (cycle[0] == "a" && cycle[1] == "b" && cycle[2] == "c") ||
			(cycle[0] == "b" && cycle[1] == "c" && cycle[2] == "a") ||
			(cycle[0] == "c" && cycle[1] == "a" && cycle[2] == "b"),
			"the diagnostic should expose the actual directed alias cycle")
	}
}

@(test)
test_theme_inherited_alias_resolves_after_child_override :: proc(t: ^testing.T) {
	base := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={
			test_definition("color.ink", .Color, test_color(0.05, 0.05, 0.05), 1),
			test_definition("text.primary", .Color, test_alias("color.ink"), 2),
		},
		core_roles={Core_Role_Binding{role=.Text, token="text.primary", span=test_span(3)}},
	}
	child := Theme_Source_Model{metadata=TEST_THEME_METADATA, tokens={
		test_definition("color.ink", .Color, test_color(0.9, 0.8, 0.7), 20),
	}}
	output := theme_compile({base, child})
	defer theme_output_destroy(&output)
	testing.expect(t, output.ok, "a child may override a base token without invalidating inherited aliases")
	role_id := output.theme.core_color_roles[int(Core_Color_Role.Text)]
	resolved := output.theme.colors[int(role_id)-1]
	testing.expect(t, resolved == Theme_Color{0.9, 0.8, 0.7, 1},
		"inherited aliases should resolve against the merged symbolic definitions")
	ink := output.theme.colors[int(output.debug.tokens[0].id)-1]
	testing.expect(t, ink == resolved, "the effective child definition should be the target of the inherited alias")
}

@(test)
test_theme_duplicate_token_is_rejected :: proc(t: ^testing.T) {
	source := Theme_Source_Model{metadata=TEST_THEME_METADATA, tokens={
		test_definition("color.same", .Color, test_color(0, 0, 0), 2),
		test_definition("color.same", .Color, test_color(1, 1, 1), 9),
	}}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	index := test_diagnostic_index(output, .Duplicate_Token)
	testing.expect(t, !output.ok && index >= 0, "duplicate declarations in one layer should be rejected")
	if index >= 0 { testing.expect(t, output.diagnostics[index].span.start_offset == 9, "duplicate diagnostic should point at the later declaration") }
}

@(test)
test_theme_compilation_is_declaration_order_independent :: proc(t: ^testing.T) {
	first := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={
			test_definition("space.large", .Length, test_length(24), 1),
			test_definition("color.accent", .Color, test_color(0.8, 0.3, 0.2), 2),
			test_definition("color.alias", .Color, test_alias("color.accent"), 3),
		},
		core_roles={
			Core_Role_Binding{role=.Accent, token="color.alias", span=test_span(4)},
			Core_Role_Binding{role=.Text, token="color.accent", span=test_span(5)},
		},
		extension_roles={
			Extension_Role_Declaration{name="app.editor.gutter", kind=.Length, token="space.large", span=test_span(6)},
			Extension_Role_Declaration{name="vendor.audio.meter.hot", kind=.Color, token="color.accent", span=test_span(7)},
		},
	}
	second := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={first.tokens[2], first.tokens[0], first.tokens[1]},
		core_roles={first.core_roles[1], first.core_roles[0]},
		extension_roles={first.extension_roles[1], first.extension_roles[0]},
	}
	a := theme_compile({first})
	defer theme_output_destroy(&a)
	b := theme_compile({second})
	defer theme_output_destroy(&b)
	testing.expect(t, a.ok && b.ok, "both declaration orders should compile")
	testing.expect(t, a.theme.content_signature == b.theme.content_signature,
		"the compiled signature should not depend on declaration order")
	testing.expect(t, len(a.theme.colors) == len(b.theme.colors) && len(a.theme.lengths) == len(b.theme.lengths),
		"typed token arrays should have identical shape after reordered compilation")
	if len(a.theme.colors) == len(b.theme.colors) && len(a.theme.lengths) == len(b.theme.lengths) {
		for index in 0..<len(a.theme.colors) { testing.expect(t, a.theme.colors[index] == b.theme.colors[index], "color token ordering should be deterministic") }
		for index in 0..<len(a.theme.lengths) { testing.expect(t, a.theme.lengths[index] == b.theme.lengths[index], "length token ordering should be deterministic") }
	}
}

@(test)
test_theme_extension_roles_require_app_or_vendor_namespace :: proc(t: ^testing.T) {
	valid := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.hot", .Color, test_color(1, 0, 0), 1)},
		extension_roles={
			Extension_Role_Declaration{name="app.editor.current_line", kind=.Color, token="color.hot", span=test_span(2)},
			Extension_Role_Declaration{name="vendor.audio.meter.hot", kind=.Color, token="color.hot", span=test_span(3)},
		},
	}
	output := theme_compile({valid})
	defer theme_output_destroy(&output)
	testing.expect(t, output.ok && len(output.theme.extension_color_roles) == 2,
		"app and vendor extension roles should compile outside Alicorn's fixed core enum")
	testing.expect(t, output.debug.extension_roles[0].name == "app.editor.current_line" &&
		output.debug.extension_roles[1].name == "vendor.audio.meter.hot",
		"extension role names should remain available in separate provenance metadata")
	expected_app_id := Extension_Color_Role_ID(test_runtime_style_extension_hash("app.editor", "current_line", 1))
	expected_vendor_id := Extension_Color_Role_ID(test_runtime_style_extension_hash("vendor.audio", "meter.hot", 1))
	testing.expect(t, output.theme.extension_color_roles[0].id == expected_app_id &&
		output.theme.extension_color_roles[1].id == expected_vendor_id,
		"compiled extension role IDs must match runtime/style_tokens.odin's stable namespace/name hash contract")

	invalid := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.hot", .Color, test_color(1, 0, 0), 1)},
		extension_roles={Extension_Role_Declaration{name="editor.current_line", kind=.Color, token="color.hot", span=test_span(7)}},
	}
	bad := theme_compile({invalid})
	defer theme_output_destroy(&bad)
	testing.expect(t, !bad.ok && test_diagnostic_index(bad, .Invalid_Extension_Role_Namespace) >= 0,
		"unqualified app roles should be rejected with a structured namespace diagnostic")
}

@(test)
test_theme_source_versions_are_checked_before_compiled_output :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=Theme_Source_Metadata{
			schema_version=THEME_SOURCE_SCHEMA_VERSION+1,
			contract=Theme_Contract_Version{major=THEME_CONTRACT_VERSION.major, minor=THEME_CONTRACT_VERSION.minor+1},
			span=test_span(30),
		},
		tokens={test_definition("color.red", .Color, test_color(1, 0, 0), 1)},
	}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	schema_index := test_diagnostic_index(output, .Unsupported_Schema_Version)
	contract_index := test_diagnostic_index(output, .Unsupported_Contract_Version)
	testing.expect(t, !output.ok && schema_index >= 0 && contract_index >= 0,
		"unsupported source schema and contract versions should produce separate diagnostics")
	testing.expect(t, len(output.theme.colors) == 0 && len(output.debug.tokens) == 0,
		"failed compilation must not expose partially compiled runtime or debug data")
	if schema_index >= 0 {
		diagnostic := output.diagnostics[schema_index]
		testing.expect(t, diagnostic.path == "theme.test" && diagnostic.span.path == diagnostic.path &&
			diagnostic.actual_schema_version == THEME_SOURCE_SCHEMA_VERSION+1 &&
			diagnostic.expected_schema_version == THEME_SOURCE_SCHEMA_VERSION,
			"schema diagnostics should carry owned path/span and expected/actual versions")
	}
	if contract_index >= 0 {
		diagnostic := output.diagnostics[contract_index]
		testing.expect(t, diagnostic.supported_contract_major == THEME_CONTRACT_VERSION.major &&
			diagnostic.supported_contract_minor == THEME_CONTRACT_VERSION.minor &&
			diagnostic.actual_contract.minor == THEME_CONTRACT_VERSION.minor+1,
			"contract diagnostics should state both supported and actual versions")
	}

	wrong_major := Theme_Source_Model{
		metadata=Theme_Source_Metadata{
			schema_version=THEME_SOURCE_SCHEMA_VERSION,
			contract=Theme_Contract_Version{major=THEME_CONTRACT_VERSION.major+1, minor=0},
			span=test_span(50),
		},
	}
	major_output := theme_compile({wrong_major})
	defer theme_output_destroy(&major_output)
	testing.expect(t, !major_output.ok && test_diagnostic_index(major_output, .Unsupported_Contract_Version) >= 0,
		"contract major mismatches must be rejected even when the minor is supported")

	older_minor := Theme_Source_Model{
		metadata=Theme_Source_Metadata{
			schema_version=THEME_SOURCE_SCHEMA_VERSION,
			contract=Theme_Contract_Version{major=THEME_CONTRACT_VERSION.major, minor=THEME_CONTRACT_VERSION.minor-1},
			span=test_span(60),
		},
	}
	older_output := theme_compile({older_minor})
	defer theme_output_destroy(&older_output)
	testing.expect(t, older_output.ok, "same-major themes with an older minor contract should remain compatible")
}

@(test)
test_theme_compiled_contract_is_highest_compatible_layer_minor :: proc(t: ^testing.T) {
	base := Theme_Source_Model{
		metadata=Theme_Source_Metadata{
			schema_version=THEME_SOURCE_SCHEMA_VERSION,
			contract=Theme_Contract_Version{major=THEME_CONTRACT_VERSION.major, minor=THEME_CONTRACT_VERSION.minor-1},
			span=test_span(1),
		},
		tokens={test_definition("color.base", .Color, test_color(0.1, 0.2, 0.3), 2)},
	}
	derived := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.derived", .Color, test_color(0.7, 0.8, 0.9), 3)},
	}
	output := theme_compile({base, derived})
	defer theme_output_destroy(&output)
	testing.expect(t, output.ok, "compatible layered source contracts should compile")
	testing.expect(t, output.theme.contract == THEME_CONTRACT_VERSION,
		"compiled runtime metadata should retain the highest compatible contract minor from all layers")
}

@(test)
test_theme_color_alpha_matches_runtime_registration_contract :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.transparent", .Color, Theme_Color{0.2, 0.3, 0.4, 0}, 4)},
	}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	index := test_diagnostic_index(output, .Invalid_Color)
	testing.expect(t, !output.ok && index >= 0,
		"fully transparent colors must be rejected to match runtime style_color_is_valid")
}

@(test)
test_theme_lengths_match_runtime_registration_range :: proc(t: ^testing.T) {
	valid := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={
			test_definition("space.zero", .Length, Theme_Length(0), 1),
			test_definition("space.max", .Length, Theme_Length(THEME_LENGTH_MAX_LOGICAL_UNITS), 2),
		},
	}
	accepted := theme_compile({valid})
	defer theme_output_destroy(&accepted)
	testing.expect(t, accepted.ok, "zero and the maximum registered logical length should compile")

	invalid := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={
			test_definition("space.negative", .Length, Theme_Length(-0.01), 3),
			test_definition("space.too_large", .Length, Theme_Length(THEME_LENGTH_MAX_LOGICAL_UNITS+1), 4),
		},
	}
	rejected := theme_compile({invalid})
	defer theme_output_destroy(&rejected)
	testing.expect(t, !rejected.ok && len(rejected.diagnostics) == 2,
		"negative and over-limit lengths must be rejected before runtime registration")
	for diagnostic in rejected.diagnostics {
		testing.expect(t, diagnostic.code == .Invalid_Length, "out-of-range logical lengths should have a specific diagnostic")
	}
}

@(test)
test_theme_diagnostics_have_stable_source_order :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={
			test_definition("token.later", .Color, test_alias("missing.later"), 40),
			test_definition("token.earlier", .Color, test_alias("missing.earlier"), 10),
		},
	}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	testing.expect(t, !output.ok && len(output.diagnostics) == 2,
		"both independent missing aliases should be reported")
	if len(output.diagnostics) == 2 {
		testing.expect(t, output.diagnostics[0].span.start_offset == 10 && output.diagnostics[1].span.start_offset == 40,
			"diagnostics should be sorted by source path and span, independent of traversal order")
		testing.expect(t, output.diagnostics[0].path == output.diagnostics[0].span.path &&
			output.diagnostics[1].path == output.diagnostics[1].span.path,
			"returned diagnostic path and source-span path should share the output-owned path string")
	}
}
