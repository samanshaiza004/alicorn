package alicorn

import "core:testing"
import "core:strings"

@(test)
test_accessibility_appearance_domains_and_color_recipes :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)

	theme := DEFAULT_STYLE_THEME
	theme.colors[int(Style_Color_Role.Surface)] = Color{0.48, 0.48, 0.48, 0.72}
	theme.colors[int(Style_Color_Role.Subtle_Surface)] = Color{0.50, 0.50, 0.50, 0.72}
	theme.colors[int(Style_Color_Role.Editor_Background)] = Color{0.45, 0.45, 0.45, 0.72}
	theme.colors[int(Style_Color_Role.Accent)] = Color{0.50, 0.50, 0.50, 0.72}
	theme.colors[int(Style_Color_Role.Accent_Hover)] = Color{0.52, 0.52, 0.52, 0.72}
	theme.colors[int(Style_Color_Role.Accent_Pressed)] = Color{0.48, 0.48, 0.48, 0.72}
	theme.colors[int(Style_Color_Role.Selection)] = Color{0.2, 0.4, 0.8, 0.25}
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "appearance fixture theme should register")

	environment := Style_Environment{
		theme=theme_id,
		accessibility=Accessibility_Appearance_Preferences{
			increased_contrast=true,
			reduce_transparency=true,
			differentiate_without_color=true,
		},
		accessibility_set=true,
	}
	text_color := style_environment_color(&rt, environment, .Text)
	background := style_theme_color(&rt, theme_id, .Surface)
	focus := style_environment_color(&rt, environment, .Focus)
	selection := style_environment_color(&rt, environment, .Selection)
	testing.expect(t, style_color_contrast_ratio(text_color, background) >= 4.5,
		"increased contrast should choose an accessible ink color against the semantic control surface")
	testing.expect(t, focus != theme.colors[int(Style_Color_Role.Focus)] && focus.a == 1,
		"increased contrast should strengthen focus/border roles instead of relying on hue")
	testing.expect(t, selection.a == 1,
		"reduced transparency should resolve translucent semantic selection colors as opaque")

	button := style_button_resolve(&rt, environment, .Default, Button_Visual_State{selected=true})
	testing.expect(t, button.selected_indicator == .Underline && button.selected_indicator_color == focus,
		"selected buttons should gain a non-color underline when differentiation is requested")
	checkbox := style_checkbox_resolve(&rt, environment, DEFAULT_CHECKBOX_RECIPE, Checkbox_Visual_State{checked=true})
	slider := style_slider_resolve(&rt, environment, DEFAULT_SLIDER_RECIPE, Slider_Visual_State{})
	testing.expect(t, checkbox.box.border == focus && checkbox.checked,
		"high-contrast Checkbox should retain its check glyph and strengthen the checked-state boundary")
	testing.expect(t, style_color_contrast_ratio(slider.thumb.border, slider.thumb.surface) >= 3,
		"high-contrast Slider should outline its geometric value marker with a distinct high-contrast boundary")
	testing.expect(t, style_color_contrast_ratio(button.text, button.surface) >= 4.5 &&
		style_color_contrast_ratio(button.focus, button.surface) >= 3,
		"built-in Button text and focus should meet contrast fallback ratios")

	// Even a custom recipe that points text/focus at a surface role cannot opt
	// out of the required high-contrast fallback after its transforms resolve.
	hostile_theme := theme
	hostile_recipe := DEFAULT_BUTTON_RECIPES.recipes[int(Button_Variant.Default)]
	hostile_recipe.text_role = .Surface
	hostile_recipe.focus_role = .Surface
	hostile_recipe.selected_indicator_role = .Surface
	hostile_theme.button_recipes.recipes[int(Button_Variant.Default)] = hostile_recipe
	hostile_theme_id := style_theme_register(&rt, hostile_theme)
	hostile_button := style_button_resolve(&rt,
		Style_Environment{theme=hostile_theme_id, accessibility=environment.accessibility, accessibility_set=true},
		.Default, Button_Visual_State{selected=true})
	testing.expect(t, hostile_theme_id != 0 && style_color_contrast_ratio(hostile_button.text, hostile_button.surface) >= 4.5 &&
		style_color_contrast_ratio(hostile_button.focus, hostile_button.surface) >= 3 &&
		style_color_contrast_ratio(hostile_button.selected_indicator_color, hostile_button.surface) >= 3,
		"custom recipe roles must not bypass text, focus, or selected-indicator contrast fallbacks")

	preferences_environment := DEFAULT_STYLE_ENVIRONMENT
	preferences_environment.accessibility = environment.accessibility
	preferences_only := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, preferences_environment)
	text_scale_only := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, Style_Environment{text_scale=1.25})
	contrast_environment := DEFAULT_STYLE_ENVIRONMENT
	contrast_environment.accessibility = Accessibility_Appearance_Preferences{increased_contrast=true}
	differentiate_environment := DEFAULT_STYLE_ENVIRONMENT
	differentiate_environment.accessibility = Accessibility_Appearance_Preferences{differentiate_without_color=true}
	transparency_environment := DEFAULT_STYLE_ENVIRONMENT
	transparency_environment.accessibility = Accessibility_Appearance_Preferences{reduce_transparency=true}
	motion_environment := DEFAULT_STYLE_ENVIRONMENT
	motion_environment.accessibility = Accessibility_Appearance_Preferences{reduce_motion=true}
	contrast_only := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, contrast_environment)
	differentiate_only := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, differentiate_environment)
	transparency_only := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, transparency_environment)
	motion_only := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, motion_environment)
	preferences_stages := style_domains_dirty_stages(preferences_only)
	text_scale_stages := style_domains_dirty_stages(text_scale_only)
	testing.expect(t, Style_Domain.Paint in preferences_only && Style_Domain.Material in preferences_only &&
		Style_Domain.Metrics not_in preferences_only && Style_Domain.Typography not_in preferences_only &&
		Dirty_Stage.Paint in preferences_stages && Dirty_Stage.Composite in preferences_stages && Dirty_Stage.Layout not_in preferences_stages,
		"appearance preferences should invalidate visual/material products without changing semantics or layout")
	testing.expect(t, Style_Domain.Metrics in text_scale_only && Style_Domain.Typography in text_scale_only &&
		Dirty_Stage.Measure in text_scale_stages && Dirty_Stage.Layout not_in text_scale_stages,
		"text_scale should invalidate measurement; layout follows only when measured geometry changes")
	testing.expect(t, Style_Domain.Paint in contrast_only && Style_Domain.Material in contrast_only &&
		Style_Domain.Metrics not_in contrast_only && Style_Domain.Typography not_in contrast_only,
		"increased contrast should invalidate Paint and Material only")
	testing.expect(t, Style_Domain.Paint in differentiate_only && Style_Domain.Material not_in differentiate_only,
		"non-color differentiation should invalidate Paint only")
	testing.expect(t, Style_Domain.Paint in transparency_only && Style_Domain.Material in transparency_only,
		"reduced transparency should invalidate Paint and Material")
	testing.expect(t, Style_Domain.Material in motion_only && Style_Domain.Paint not_in motion_only,
		"reduced motion should invalidate Material only")
	cleared, clear_valid := style_environment_resolve(
		Style_Environment{accessibility=Accessibility_Appearance_Preferences{increased_contrast=true}, accessibility_set=true},
		Style_Environment{accessibility_set=true}, &rt)
	testing.expect(t, clear_valid && cleared.accessibility == {},
		"an explicit all-disabled nested scope should clear inherited accessibility appearance preferences")
}

@(test)
test_accessibility_appearance_adapts_analytic_material_once :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	source := style_material_register(&rt, Style_Material{
		kind=.Analytic_Relief,
		bevel_width=0.75,
		bevel_strength=0.12,
		inner_shadow_strength=0.05,
		outer_shadow_strength=0.2,
		outer_shadow_radius=3,
	})
	preferences := Style_Environment{
		accessibility=Accessibility_Appearance_Preferences{increased_contrast=true, reduce_transparency=true},
		accessibility_set=true,
	}
	adapted_id := style_material_accessibility_variant(&rt, preferences, source)
	adapted, adapted_ok := style_material_resolve(&rt, adapted_id)
	source_after, source_ok := style_material_resolve(&rt, source)
	adapted_again := style_material_accessibility_variant(&rt, preferences, source)
	testing.expect(t, adapted_id != source && adapted_again == adapted_id && adapted_ok &&
		adapted.bevel_width >= 1.5 && adapted.bevel_strength >= 0.75 && adapted.outer_shadow_strength == 0,
		"preference-adapted analytic materials should strengthen boundaries, remove translucent shadows, and deduplicate")
	testing.expect(t, source_ok && source_after.bevel_width == 0.75 && source_after.bevel_strength == 0.12 && source_after.outer_shadow_strength == 0.2,
		"appearance adaptation must not mutate the theme/app-registered source material")
	flat := style_material_accessibility_variant(&rt, preferences, MATERIAL_FLAT)
	testing.expect(t, flat == MATERIAL_FLAT,
		"appearance preferences should preserve the flat material's zero-cost path")
}

Accessibility_Fixture_Nodes :: struct { button, sibling, surface: Node_ID }

accessibility_fixture_describe :: proc(
	rt: ^Runtime,
	preferences: Accessibility_Appearance_Preferences,
	material: Material_ID,
) -> Accessibility_Fixture_Nodes {
	invalidate_root(rt, "accessibility appearance fixture")
	ui, build := begin_frame(rt)
	if !build { return {} }
	container_begin(&ui, .Root, key=key_string("accessibility-root"), style=layout_style())
	scope := style_environment_push(&ui, Style_Environment{
		accessibility=preferences,
		accessibility_set=true,
	})
	result := Accessibility_Fixture_Nodes{}
	_ = button(&ui, "Selected", key=key_string("accessibility-selected"), state=Button_State{selected=true})
	_ = semantic_description(&ui, .Button, "Selected", states=semantic_states_add({}, .Selected))
	result.surface = surface_begin(&ui, surface_core_color_role(.Surface),
		key=key_string("accessibility-surface"), style=layout_style(width=120, height=40),
		material=material, physical_height=0.5)
	text(&ui, "Panel")
	surface_end(&ui)
	style_environment_pop(&ui, scope)
	result.sibling = text(&ui, "Unaffected")
	container_end(&ui)
	end_frame(&ui)
	result.button = style_recipe_test_button(rt, "Selected")
	return result
}

@(test)
test_scoped_appearance_preferences_do_not_change_semantic_projection :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 160})
	defer destroy_runtime(&rt)
	material := style_material_register(&rt, Style_Material{
		kind=.Analytic_Relief,
		bevel_width=1,
		bevel_strength=0.2,
		outer_shadow_strength=0.15,
		outer_shadow_radius=2,
	})
	initial := accessibility_fixture_describe(&rt, {}, material)
	if initial.button == 0 || initial.surface == 0 || initial.sibling == 0 {
		testing.expect(t, false, "appearance fixture should retain controls and an analytic surface")
		return
	}
	semantic_revision := rt.semantic_revision
	button_before := rt.nodes[initial.button].style_generations
	sibling_before := rt.nodes[initial.sibling].style_generations
	preferences := Accessibility_Appearance_Preferences{
		increased_contrast=true,
		reduce_motion=true,
		reduce_transparency=true,
		differentiate_without_color=true,
	}
	updated := accessibility_fixture_describe(&rt, preferences, material)
	button_node := rt.nodes[updated.button]
	sibling_node := rt.nodes[updated.sibling]
	semantic, semantic_found := rt.semantic_entities[semantic_visual_id(updated.button)]
	testing.expect(t, updated.button == initial.button && updated.surface == initial.surface && updated.sibling == initial.sibling,
		"changing appearance preferences should preserve retained control and surface identities")
	testing.expect(t, button_node.style_generations.paint > button_before.paint &&
		button_node.style_generations.material > button_before.material &&
		button_node.style_generations.metrics == button_before.metrics &&
		button_node.style_generations.typography == button_before.typography,
		"appearance preference changes should advance paint/material only in their scoped subtree")
	testing.expect(t, sibling_node.style_generations == sibling_before,
		"a sibling outside the appearance scope should retain all style generations")
	testing.expect(t, rt.semantic_revision == semantic_revision && len(rt.semantic_entities) == 1 && semantic_found &&
		semantic.node.role == .Button && semantic.node.label == "Selected" &&
		semantic_states_has(semantic.node.states, .Selected),
		"visual appearance changes must leave the semantic projection and its revision unchanged")
	button_style := style_button_resolve_retained(&rt, button_node, Button_Visual_State{selected=true})
	testing.expect(t, button_style.selected_indicator == .Underline,
		"the retained recipe result should consume the non-color differentiation preference")
	inspection := inspect(&rt)
	defer delete(inspection)
	testing.expect(t, strings.contains(inspection, "accessibility-appearance=(increased-contrast=true reduce-motion=true reduce-transparency=true differentiate-without-color=true)") &&
		strings.contains(inspection, "semantics: revision="),
		"the inspector should report appearance inputs on the style side without mixing them into semantic records")
}

root_appearance_layer_fixture :: proc(rt: ^Runtime) -> (inherited, overridden: Node_ID) {
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin(&ui, .Root, key=key_string("root-appearance-layer"), style=layout_style())
	_ = button(&ui, "Inherits system", key=key_string("root-appearance-inherited"))
	scope := style_environment_push(&ui, Style_Environment{
		accessibility=Accessibility_Appearance_Preferences{increased_contrast=true},
		accessibility_set=true,
	})
	_ = button(&ui, "App override", key=key_string("root-appearance-overridden"))
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	inherited, _ = node_by_key(rt, key_string("root-appearance-inherited"), .Button)
	overridden, _ = node_by_key(rt, key_string("root-appearance-overridden"), .Button)
	return
}

@(test)
test_root_host_appearance_inherits_and_respects_explicit_override :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)
	inherited, overridden := root_appearance_layer_fixture(&rt)
	if inherited == 0 || overridden == 0 {
		testing.expect(t, false, "root appearance fixture should retain both inherited and overridden controls")
		return
	}
	semantic_revision := rt.semantic_revision
	inherited_before := rt.nodes[inherited].style_generations
	overridden_before := rt.nodes[overridden].style_generations
	preferences := Accessibility_Appearance_Preferences{increased_contrast=true}
	observation := Accessibility_Appearance_Observation{
		preferences=preferences,
		known={.Increased_Contrast, .Reduce_Motion, .Reduce_Transparency},
	}
	testing.expect(t, style_root_accessibility_observation_set(&rt, observation) && rt.invalidated,
		"a changed host appearance base should request one application description")
	observed := style_root_accessibility_observation_get(&rt)
	testing.expect(t, observed == observation &&
		Accessibility_Appearance_Field.Increased_Contrast in observed.known &&
		Accessibility_Appearance_Field.Differentiate_Without_Color not_in observed.known,
		"host diagnostics should report inherited values separately from unsupported/unavailable fields")
	updated_inherited, updated_overridden := root_appearance_layer_fixture(&rt)
	inherited_node := rt.nodes[updated_inherited]
	overridden_node := rt.nodes[updated_overridden]
	testing.expect(t, updated_inherited == inherited && updated_overridden == overridden &&
		inherited_node.style_generations.paint > inherited_before.paint &&
		inherited_node.style_generations.material > inherited_before.material &&
		inherited_node.style_generations.metrics == inherited_before.metrics &&
		inherited_node.style_generations.typography == inherited_before.typography,
		"the inherited scope should receive the native base and invalidate Paint/Material only")
	testing.expect(t, overridden_node.style_environment.accessibility.increased_contrast &&
		overridden_node.style_generations == overridden_before,
		"an explicit application override already equal to the new base should not be invalidated")
	testing.expect(t, rt.semantic_revision == semantic_revision,
		"a root visual appearance change must not advance semantic revision")
	testing.expect(t, !style_root_accessibility_observation_set(&rt, observation) && !rt.invalidated,
		"an identical host preference notification should not invalidate the runtime")
}

@(test)
test_root_appearance_observation_tracks_support_without_value_change :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)
	observation := Accessibility_Appearance_Observation{
		preferences=Accessibility_Appearance_Preferences{},
		known={.Reduce_Transparency},
	}
	testing.expect(t, style_root_accessibility_observation_set(&rt, observation) && rt.invalidated,
		"newly available host-field knowledge should refresh diagnostic consumers even when its value is false")
	observed := style_root_accessibility_observation_get(&rt)
	testing.expect(t, Accessibility_Appearance_Field.Reduce_Transparency in observed.known &&
		observed.preferences.reduce_transparency == false,
		"known false must remain distinguishable from unsupported or unavailable")
	rt.invalidated = false
	testing.expect(t, !style_root_accessibility_observation_set(&rt, observation) && !rt.invalidated,
		"identical value and support metadata should not cause another wake")
}
