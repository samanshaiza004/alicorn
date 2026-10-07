package main

import "core:strings"
import "core:testing"
import alicorn "../../runtime"

@(test)
test_theme_codegen_emits_owned_runtime_factory_and_cleanup :: proc(t: ^testing.T) {
	value := alicorn.DEFAULT_STYLE_THEME
	value.color_tokens = make([]alicorn.Color, 1)
	value.color_tokens[0] = alicorn.Color{0.25, 0.5, 0.75, 1}
	defer delete(value.color_tokens)
	value.length_tokens = make([]alicorn.Style_Length, 1)
	value.length_tokens[0] = alicorn.Style_Length{logical_units=12}
	defer delete(value.length_tokens)
	value.core_color_tokens[int(alicorn.Style_Color_Role.Text)] = alicorn.Style_Color_Token_ID(1)
	value.extension_color_roles = make([]alicorn.Style_Extension_Color_Role_Binding, 1)
	value.extension_color_roles[0] = alicorn.Style_Extension_Color_Role_Binding{
		role=alicorn.Style_Extension_Color_Role_ID(7),
		token=alicorn.Style_Color_Token_ID(1),
	}
	defer delete(value.extension_color_roles)
	value.extension_length_roles = make([]alicorn.Style_Extension_Length_Role_Binding, 1)
	value.extension_length_roles[0] = alicorn.Style_Extension_Length_Role_Binding{
		role=alicorn.Style_Extension_Length_Role_ID(8),
		token=alicorn.Style_Length_Token_ID(1),
	}
	defer delete(value.extension_length_roles)
	value.color_token_provenance = make([]alicorn.Style_Token_Provenance, 1)
	value.color_token_provenance[0] = alicorn.Style_Token_Provenance{
		id=1,
		name="surface.active",
		alias_target="chrome.active",
	}
	defer delete(value.color_token_provenance)
	value.extension_color_role_provenance = make([]alicorn.Style_Extension_Color_Role_Provenance, 1)
	value.extension_color_role_provenance[0] = alicorn.Style_Extension_Color_Role_Provenance{
		role=alicorn.Style_Extension_Color_Role_ID(7),
		name="app.shell.surface",
	}
	defer delete(value.extension_color_role_provenance)
	value.button_recipes.recipes[int(alicorn.Button_Variant.Tab)].selected_indicator_role = .Accent
	value.button_recipes.recipes[int(alicorn.Button_Variant.Tab)].hovered.surface_mix = 0.42
	materials := []alicorn.Style_Material_Definition{{
		name="app.scratchpad.editor.paper",
		material=alicorn.Style_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.36, inner_shadow_strength=0.18},
	}}

	generated, ok := theme_cli_codegen_odin(value, materials,
		"TEST_THEME", "main", "../runtime")
	defer delete(generated)
	generated_again, generated_again_ok := theme_cli_codegen_odin(value, materials,
		"TEST_THEME", "main", "../runtime")
	defer delete(generated_again)
	testing.expect(t, ok, "a valid runtime theme should generate Odin source")
	if !ok { return }
	testing.expect(t, generated_again_ok && generated_again == generated,
		"the same typed theme should generate byte-for-byte stable Odin source")
	testing.expect(t, strings.contains(generated, "package main\n"),
		"generated source should declare the selected package")
	testing.expect(t, strings.contains(generated, "import alicorn \"../runtime\""),
		"generated source should use the selected Alicorn runtime import")
	testing.expect(t, strings.contains(generated, "TEST_THEME :: proc(allocator := context.allocator) -> alicorn.Style_Theme"),
		"the requested symbol should be a runtime-theme factory")
	testing.expect(t, strings.contains(generated, "TEST_THEME_destroy :: proc(value: ^alicorn.Style_Theme"),
		"generated owned slices should have a matching cleanup helper")
	testing.expect(t, strings.contains(generated, "result.colors = {"),
		"the complete semantic color table should be represented")
	testing.expect(t, strings.contains(generated, "result.color_tokens[0] = alicorn.Color{"),
		"typed color token data should be emitted")
	testing.expect(t, strings.contains(generated, "result.length_tokens[0] = alicorn.Style_Length{"),
		"typed length token data should be emitted")
	testing.expect(t, strings.contains(generated, "Style_Extension_Color_Role_Binding{"),
		"extension color bindings should be emitted")
	testing.expect(t, strings.contains(generated, "Style_Extension_Length_Role_Binding{"),
		"extension length bindings should be emitted")
	testing.expect(t, strings.contains(generated, "name=\"surface.active\", alias_target=\"chrome.active\""),
		"generated themes should carry token names and alias edges into the runtime inspector")
	testing.expect(t, strings.contains(generated, "name=\"app.shell.surface\""),
		"generated themes should carry namespaced extension-role names into the runtime inspector")
	testing.expect(t, strings.contains(generated, "Provenance strings are static generated literals") &&
		!strings.contains(generated, "delete(provenance.name, allocator)") &&
		!strings.contains(generated, "delete(provenance.alias_target, allocator)"),
		"generated cleanup should release owned slices without freeing static provenance literals")
	testing.expect(t, strings.contains(generated, "selected_indicator_role = alicorn.Style_Color_Role.Accent") &&
		strings.contains(generated, "hovered.surface_mix ="),
		"authored button recipe differences should be emitted as static resolved runtime values")
	testing.expect(t, strings.contains(generated, "TEST_THEME_materials :: [1]alicorn.Style_Material_Definition") &&
		strings.contains(generated, "name=\"app.scratchpad.editor.paper\"") &&
		strings.contains(generated, "bevel_strength=0.36") &&
		!strings.contains(generated, "%!(MISSING"),
		"named material definitions should be emitted as static runtime setup data")
}

@(test)
test_theme_codegen_rejects_invalid_identifiers_and_import_paths :: proc(t: ^testing.T) {
	testing.expect(t, theme_cli_codegen_identifier_is_valid("Theme_1"),
		"ordinary Odin identifiers should be accepted")
	testing.expect(t, !theme_cli_codegen_identifier_is_valid("1Theme"),
		"identifiers cannot start with a digit")
	testing.expect(t, !theme_cli_codegen_identifier_is_valid("Theme; os.exit(1)"),
		"symbols must not allow source injection")
	testing.expect(t, theme_cli_codegen_import_is_valid("alicorn:runtime"),
		"module imports should be accepted")
	testing.expect(t, !theme_cli_codegen_import_is_valid("runtime\"; os.exit(1) //"),
		"import paths must not allow source injection")
}
