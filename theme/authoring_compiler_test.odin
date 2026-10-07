package theme

import "core:testing"

@(test)
test_material_replacement_and_sparse_recipe_overlay_preserve_layer_values :: proc(t: ^testing.T) {
	base := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		materials={Theme_Material_Definition{
			name="app.editor.paper",
			value=Theme_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.2},
			span=test_span(1),
		}},
		button_recipes={Theme_Button_Recipe_Override{
			variant=.Tab,
			has_selected_indicator_role=true,
			selected_indicator_role=.Accent,
			span=test_span(2),
		}},
	}
	overlay := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		materials={Theme_Material_Definition{
			name="app.editor.paper",
			value=Theme_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.36, inner_shadow_strength=0.18},
			span=test_span(10),
		}},
		button_recipes={Theme_Button_Recipe_Override{
			variant=.Tab,
			states={
				Theme_Button_Transform_Override{},
				Theme_Button_Transform_Override{has_surface_mix=true, surface_mix=0.42},
				Theme_Button_Transform_Override{},
				Theme_Button_Transform_Override{},
			},
			span=test_span(11),
		}},
	}
	compiled := theme_compile({base, overlay})
	defer theme_output_destroy(&compiled)
	testing.expect(t, compiled.ok && len(compiled.theme.materials) == 1 && len(compiled.theme.button_recipes) == 1,
		"same-kind material replacement and sparse recipe overlays should compile")
	if !compiled.ok || len(compiled.theme.materials) != 1 || len(compiled.theme.button_recipes) != 1 { return }
	material := compiled.theme.materials[0]
	testing.expect(t, material.bevel_strength == 0.36 && material.inner_shadow_strength == 0.18,
		"a later same-kind material definition should replace the earlier material values")
	recipe := compiled.theme.button_recipes[0]
	testing.expect(t, recipe.has_selected_indicator_role && recipe.selected_indicator_role == .Accent &&
		recipe.states[int(Theme_Button_State.Hovered)].has_surface_mix &&
		recipe.states[int(Theme_Button_State.Hovered)].surface_mix == 0.42,
		"sparse recipe overlays should preserve earlier fields while adding later state values")
	testing.expect(t, compiled.debug.button_recipes[0].span.start_offset == 11 &&
		compiled.debug.materials[0].span.start_offset == 10,
		"provenance should identify the latest source layer for each resolved authored object")
}

@(test)
test_theme_compiler_rejects_out_of_range_material_and_recipe_values :: proc(t: ^testing.T) {
	source := Theme_Source_Model{
		metadata=TEST_THEME_METADATA,
		materials={Theme_Material_Definition{
			name="vendor.scratchpad.editor.paper",
			value=Theme_Material{kind=.Analytic_Relief, bevel_width=9},
			span=test_span(20),
		}},
		button_recipes={Theme_Button_Recipe_Override{
			variant=.Tab,
			states={
				Theme_Button_Transform_Override{has_surface_mix=true, surface_mix=1.1},
				Theme_Button_Transform_Override{},
				Theme_Button_Transform_Override{},
				Theme_Button_Transform_Override{},
			},
			span=test_span(21),
		}},
	}
	compiled := theme_compile({source})
	defer theme_output_destroy(&compiled)
	testing.expect(t, !compiled.ok && test_diagnostic_index(compiled, .Invalid_Material) >= 0,
		"theme compilation must reject material values outside runtime bounds")
	testing.expect(t, !compiled.ok && test_diagnostic_index(compiled, .Invalid_Button_Recipe) >= 0,
		"theme compilation must reject recipe transforms outside runtime bounds")
}
