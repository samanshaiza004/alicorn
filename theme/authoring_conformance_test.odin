package theme

import alicorn "../runtime"
import "core:os"
import "core:testing"

@(test)
test_theme_authoring_compiles_adapts_and_preserves_material_and_recipe :: proc(t: ^testing.T) {
	input := "{\"schema\":1,\"contract\":\"0.2\",\"tokens\":{\"scratchpad.ink\":{\"$type\":\"color\",\"$value\":{\"colorSpace\":\"srgb\",\"components\":[0.2,0.2,0.2]}}},\"materials\":{\"app.scratchpad.editor.paper\":{\"kind\":\"analytic_relief\",\"bevel_width\":1,\"bevel_strength\":0.36,\"inner_shadow_strength\":0.18}},\"recipes\":{\"button\":{\"tab\":{\"selected_indicator_role\":\"accent\",\"states\":{\"hovered\":{\"surface_mix\":0.42}}}}}}"
	parsed := theme_json_parse(input, "scratchpad-paper.json")
	defer theme_json_output_destroy(&parsed)
	if !parsed.ok { testing.expect(t, false, "authoring fixture should parse"); return }
	compiled := theme_compile({parsed.source})
	defer theme_output_destroy(&compiled)
	if !compiled.ok { testing.expect(t, false, "authoring fixture should compile"); return }

	runtime_theme, theme_ok := theme_runtime_style_theme(compiled)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	materials, materials_ok := theme_runtime_style_materials(compiled)
	defer theme_runtime_style_materials_destroy(&materials)
	testing.expect(t, theme_ok && materials_ok, "compiler output should adapt into immutable runtime style inputs")
	if !theme_ok || !materials_ok || len(materials) != 1 { return }
	testing.expect(t, materials[0].name == "app.scratchpad.editor.paper" &&
		materials[0].material.kind == .Analytic_Relief && materials[0].material.bevel_width == 1 &&
		materials[0].material.bevel_strength == 0.36 && materials[0].material.inner_shadow_strength == 0.18,
		"the generated material definition should retain its authored name and analytic values")

	tab := runtime_theme.button_recipes.recipes[int(alicorn.Button_Variant.Tab)]
	testing.expect(t, tab.selected_indicator_role == .Accent && tab.hovered.surface_mix == 0.42,
		"sparse recipe overrides should resolve over defaults without losing unspecified fields")
	testing.expect(t, tab.hovered.surface_role == alicorn.DEFAULT_STYLE_THEME.button_recipes.recipes[int(alicorn.Button_Variant.Tab)].hovered.surface_role,
		"unspecified recipe fields should inherit the existing typed defaults")
}

@(test)
test_palette_only_0_2_fixture_keeps_its_default_materials_and_recipes :: proc(t: ^testing.T) {
	data, read_error := os.read_entire_file("theme/testdata/scratchpad-paper-contract-0.2.json", context.allocator)
	if read_error != nil {
		testing.expect(t, false, "the frozen pre-recipe/material v0.2 fixture should be readable from repository root")
		return
	}
	defer delete(data)
	parsed := theme_json_parse(string(data), "theme/testdata/scratchpad-paper-contract-0.2.json")
	defer theme_json_output_destroy(&parsed)
	if !parsed.ok { testing.expect(t, false, "the frozen palette-only v0.2 theme should remain parseable"); return }
	compiled := theme_compile({parsed.source})
	defer theme_output_destroy(&compiled)
	if !compiled.ok { testing.expect(t, false, "the frozen palette-only v0.2 theme should remain compilable"); return }
	testing.expect(t, len(compiled.theme.materials) == 0 && len(compiled.theme.button_recipes) == 0,
		"the historical fixture should remain a genuine palette-only source")
	runtime_theme, ok := theme_runtime_style_theme(compiled)
	defer theme_runtime_style_theme_destroy(&runtime_theme)
	testing.expect(t, ok, "the new compiler should adapt the historical theme without migration")
	if ok {
		expected := alicorn.DEFAULT_STYLE_THEME.button_recipes
		actual := runtime_theme.button_recipes
		testing.expect(t, actual == expected,
			"a palette-only v0.2 theme should inherit exactly the old built-in button recipe defaults")
	}
}
