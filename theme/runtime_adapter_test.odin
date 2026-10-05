package theme

import alicorn "../runtime"
import "core:testing"

@(test)
test_theme_runtime_adapter_preserves_typed_bindings_and_owns_its_values :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={
			test_definition("palette.ink", .Color, Theme_Color{0.12, 0.24, 0.36, 1}, 1),
			test_definition("space.gutter", .Length, Theme_Length(18), 2),
			test_definition("text.primary", .Color, Theme_Alias{"palette.ink"}, 3),
		},
		core_roles={Core_Role_Binding{role=.Text, token="text.primary", span=test_span(4)}},
		extension_roles={
			Extension_Role_Declaration{
				name="app.editor.current_line",
				kind=.Color,
				token="palette.ink",
				span=test_span(5),
			},
			Extension_Role_Declaration{
				name="vendor.editor.gutter.width",
				kind=.Length,
				token="space.gutter",
				span=test_span(6),
			},
		},
	}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	runtime_theme, adapted := theme_runtime_style_theme(output)
	if !adapted { return }
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	testing.expect(t, adapted, "a valid compiler output should adapt to a runtime theme")
	testing.expect(t, runtime_theme.colors[int(alicorn.Style_Color_Role.Text)] == alicorn.Color{0.12, 0.24, 0.36, 1},
		"core semantic role values should populate the runtime role table")
	testing.expect(t, runtime_theme.core_color_tokens[int(alicorn.Style_Color_Role.Text)] == alicorn.Style_Color_Token_ID(u32(output.theme.core_color_roles[int(Core_Color_Role.Text)])),
		"core roles should retain their typed theme-local token binding")
	testing.expect(t, len(runtime_theme.color_tokens) == len(output.theme.colors) && len(runtime_theme.length_tokens) == len(output.theme.lengths),
		"the adapter should preserve each typed token array")
	if len(runtime_theme.length_tokens) > 0 {
		testing.expect(t, runtime_theme.length_tokens[0].logical_units == 18,
			"length tokens should remain context-free Alicorn logical units")
	}
	current_line := alicorn.style_extension_color_role_id("app.editor", "current_line")
	gutter_width := alicorn.style_extension_length_role_id("vendor.editor", "gutter.width")
	testing.expect(t, u64(output.theme.extension_color_roles[0].id) == u64(current_line),
		"compiler and runtime extension-color IDs must use the same namespaced hash")
	testing.expect(t, u64(output.theme.extension_length_roles[0].id) == u64(gutter_width),
		"compiler and runtime extension-length IDs must use the same namespaced hash")
	testing.expect(t, len(runtime_theme.extension_color_roles) == 1 && runtime_theme.extension_color_roles[0].role == current_line,
		"extension color role names should map to Alicorn's namespaced role identity")
	testing.expect(t, len(runtime_theme.extension_length_roles) == 1 && runtime_theme.extension_length_roles[0].role == gutter_width,
		"extension length roles should remain distinct and namespaced")
	testing.expect(t, u32(runtime_theme.extension_color_roles[0].token) == u32(output.theme.extension_color_roles[0].token),
		"extension color bindings should preserve typed local token indices")
	testing.expect(t, u32(runtime_theme.extension_length_roles[0].token) == u32(output.theme.extension_length_roles[0].token),
		"extension length bindings should preserve typed local token indices")

	// The adapter's copy must not borrow compiler-owned arrays or names.
	output.theme.colors[0] = Theme_Color{}
	output.theme.lengths[0] = 999
	testing.expect(t, runtime_theme.colors[int(alicorn.Style_Color_Role.Text)] == alicorn.Color{0.12, 0.24, 0.36, 1},
		"mutating compiler color storage must not alter the adapted value")
	testing.expect(t, runtime_theme.length_tokens[0].logical_units == 18,
		"mutating compiler length storage must not alter the adapted value")
}

@(test)
test_theme_runtime_adapter_output_survives_compiler_destruction_and_registration :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.text", .Color, Theme_Color{0.7, 0.6, 0.5, 1}, 1)},
		core_roles={Core_Role_Binding{role=.Text, token="color.text", span=test_span(2)}},
	}
	output := theme_compile({source})
	runtime_theme, adapted := theme_runtime_style_theme(output)
	theme_output_destroy(&output)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	testing.expect(t, adapted, "the adapter should return an owned unregistered value")
	if !adapted { return }

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 100, 100})
	defer alicorn.destroy_runtime(&rt)
	registered_id := alicorn.style_theme_register(&rt, runtime_theme)
	testing.expect(t, registered_id != 0, "adapted values should satisfy runtime registration")
	if registered_id == 0 { return }

	// Runtime registration takes its own immutable copy, so the adapter-owned
	// slices may be released immediately after registration.
	theme_runtime_style_theme_destroy(&runtime_theme)
	resolved := alicorn.style_theme_color(&rt, registered_id, .Text)
	testing.expect(t, resolved == alicorn.Color{0.7, 0.6, 0.5, 1},
		"registered runtime themes must remain valid after compiler and adapter storage are destroyed")
}

@(test)
test_theme_runtime_adapter_uses_compiled_extension_ids_without_provenance :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.marker", .Color, Theme_Color{1, 0, 0, 1}, 1)},
		extension_roles={Extension_Role_Declaration{
			name="app.editor.marker",
			kind=.Color,
			token="color.marker",
			span=test_span(2),
		}},
	}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	for role in output.debug.extension_roles {
		delete(role.name)
		delete(role.span.path)
	}
	delete(output.debug.extension_roles)
	output.debug.extension_roles = nil
	runtime_theme, ok := theme_runtime_style_theme(output)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	testing.expect(t, ok, "compiled role IDs should adapt without debug provenance")
	testing.expect(t, len(runtime_theme.color_tokens) == 1 && len(runtime_theme.extension_color_roles) == 1,
		"extension bindings should remain available from compact compiled output alone")
}

@(test)
test_theme_runtime_adapter_rejects_invalid_compiled_token_indices :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("color.marker", .Color, Theme_Color{1, 0, 0, 1}, 1)},
		extension_roles={Extension_Role_Declaration{
			name="app.editor.marker",
			kind=.Color,
			token="color.marker",
			span=test_span(2),
		}},
	}
	output := theme_compile({source})
	defer theme_output_destroy(&output)
	output.theme.extension_color_roles[0].token = Color_Token_ID(2)
	runtime_theme, ok := theme_runtime_style_theme(output)
	if ok { theme_runtime_style_theme_destroy(&runtime_theme) }
	testing.expect(t, !ok, "out-of-range compiled token indices must be rejected")
}

@(test)
test_theme_builtin_base_is_a_typed_source_projection_of_runtime_defaults :: proc(t: ^testing.T) {
	base := theme_builtin_base_source_create()
	defer theme_builtin_base_source_destroy(&base)
	compiled := theme_compile({base.model})
	defer theme_output_destroy(&compiled)
	if !compiled.ok { return }
	runtime_theme, adapted := theme_runtime_style_theme(compiled)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	testing.expect(t, adapted, "the compiler projection of the typed base should adapt to a runtime theme")
	if !adapted { return }
	testing.expect(t, len(compiled.theme.colors) == CORE_COLOR_ROLE_COUNT,
		"the built-in source should expose one typed color token per fixed core role")
	default_theme := alicorn.DEFAULT_STYLE_THEME
	for role in Core_Color_Role {
		if role == .Count { continue }
		runtime_role, mapped := theme_runtime_adapter_core_role(role)
		if !mapped { continue }
		testing.expect(t, runtime_theme.colors[int(runtime_role)] == default_theme.colors[int(runtime_role)],
			"compiled built-in core roles should match the typed runtime defaults")
	}
}

@(test)
test_theme_child_alias_can_resolve_a_builtin_base_token :: proc(t: ^testing.T) {
	base := theme_builtin_base_source_create()
	defer theme_builtin_base_source_destroy(&base)
	child := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		tokens={test_definition("app.editor.primary_text", .Color,
			test_alias("alicorn.color.text"), 10)},
		core_roles={Core_Role_Binding{role=.Text, token="app.editor.primary_text", span=test_span(11)}},
	}
	compiled := theme_compile({base.model, child})
	defer theme_output_destroy(&compiled)
	testing.expect(t, compiled.ok, "a child alias should resolve after the built-in symbolic layer is overlaid")
	if compiled.ok {
		role_id := compiled.theme.core_color_roles[int(Core_Color_Role.Text)]
		color := compiled.theme.colors[int(u32(role_id))-1]
		default_theme := alicorn.DEFAULT_STYLE_THEME
		default := default_theme.colors[int(alicorn.Style_Color_Role.Text)]
		testing.expect(t, color == Theme_Color{default.r, default.g, default.b, default.a},
			"the inherited alias and overridden core role should retain the base color value")
	}
}
