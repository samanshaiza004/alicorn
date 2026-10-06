package alicorn

import "core:testing"
import "core:strings"

style_recipe_test_button :: proc(rt: ^Runtime, label: string) -> Node_ID {
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Button && node.label == label { return id }
	}
	return 0
}

@(test)
test_button_recipe_variants_use_neutral_defaults_and_explicit_primary :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 220})
	defer destroy_runtime(&rt)
	environment := DEFAULT_STYLE_ENVIRONMENT

	ordinary := style_button_resolve(&rt, environment, .Default, Button_Visual_State{})
	primary := style_button_resolve(&rt, environment, .Primary, Button_Visual_State{})
	toolbar := style_button_resolve(&rt, environment, .Toolbar, Button_Visual_State{})
	quiet := style_button_resolve(&rt, environment, .Quiet, Button_Visual_State{})
	tab := style_button_resolve(&rt, environment, .Tab, Button_Visual_State{selected=true})
	danger := style_button_resolve(&rt, environment, .Danger, Button_Visual_State{})
	danger_hover := style_button_resolve(&rt, environment, .Danger, Button_Visual_State{hovered=true})
	danger_pressed := style_button_resolve(&rt, environment, .Danger, Button_Visual_State{pressed=true})

	testing.expect(t, ordinary.surface == style_color(&UI{runtime=&rt}, .Subtle_Surface),
		"ordinary buttons should use a neutral surface by default")
	testing.expect(t, ordinary.text == style_color(&UI{runtime=&rt}, .Text), "ordinary buttons should use the semantic text role")
	testing.expect(t, primary.surface == style_color(&UI{runtime=&rt}, .Accent), "primary buttons should use the accent recipe")
	testing.expect(t, primary.text == style_color(&UI{runtime=&rt}, .Accent_Text), "primary buttons should use the accent text role")
	testing.expect(t, toolbar.surface == style_color(&UI{runtime=&rt}, .Surface) && toolbar.surface != style_color(&UI{runtime=&rt}, .Accent),
		"toolbar buttons should use their distinct neutral surface recipe")
	testing.expect(t, quiet.surface.a == 0, "quiet buttons should leave the idle surface transparent")
	testing.expect(t, tab.surface == style_color(&UI{runtime=&rt}, .Subtle_Surface) && tab.text == style_color(&UI{runtime=&rt}, .Text),
		"selected tabs should use the tab recipe's selected surface and text transforms")
	testing.expect(t, tab.selected_indicator == .Underline, "selected tabs should add a non-color selection indicator")
	testing.expect(t, tab.focus_indicator_mode == .Keyboard_Only,
		"the Tab recipe should show its focus indicator only for keyboard focus modality")
	testing.expect(t, danger.surface.a == 0 && danger.text == style_color(&UI{runtime=&rt}, .Danger),
		"destructive controls should stay transparent at rest and use the semantic danger color for their glyph")
	testing.expect(t, danger_hover.surface == style_color_mix(danger.surface, style_color(&UI{runtime=&rt}, .Danger), 0.3) &&
		danger_hover.text == style_color(&UI{runtime=&rt}, .Accent_Text),
		"hovering a destructive control should show a muted danger tint with readable contrasting text")
	testing.expect(t, danger_pressed.surface == style_color(&UI{runtime=&rt}, .Danger),
		"pressing a destructive control should show the full danger surface")
}

@(test)
test_button_recipe_transforms_have_deterministic_order_and_separate_focus :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 220})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.button_recipes.recipes[int(Button_Variant.Toolbar)] = Button_Recipe{
		defined=true,
		surface_role=.Surface,
		text_role=.Text,
		surface_visible=true,
		selected=Style_Transform{surface_role=.Accent, surface_mix=1},
		hovered=Style_Transform{surface_role=.Accent_Hover, surface_mix=1},
		pressed=Style_Transform{surface_role=.Accent_Pressed, surface_mix=1},
		disabled=Style_Transform{surface_role=.Subtle_Surface, surface_mix=1, text_role=.Muted_Text, text_mix=1},
		focus_role=.Focus,
		semantic_active_role=.Semantic_Focus,
	}
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "valid button recipes should register with their theme")
	environment := Style_Environment{theme=theme_id}

	selected := style_button_resolve(&rt, environment, .Toolbar, Button_Visual_State{selected=true})
	hovered := style_button_resolve(&rt, environment, .Toolbar, Button_Visual_State{selected=true, hovered=true})
	pressed := style_button_resolve(&rt, environment, .Toolbar, Button_Visual_State{selected=true, hovered=true, pressed=true})
	all_states := style_button_resolve(&rt, environment, .Toolbar, Button_Visual_State{selected=true, hovered=true, pressed=true, disabled=true})
	testing.expect(t, selected.surface == style_environment_color(&rt, environment, .Accent), "selected transform should apply after the base recipe")
	testing.expect(t, hovered.surface == style_environment_color(&rt, environment, .Accent_Hover), "hover should compose after selection")
	testing.expect(t, pressed.surface == style_environment_color(&rt, environment, .Accent_Pressed), "pressed should compose after hover")
	testing.expect(t, all_states.surface == style_environment_color(&rt, environment, .Subtle_Surface), "disabled should apply last")
	testing.expect(t, all_states.text == style_environment_color(&rt, environment, .Muted_Text), "disabled text transform should apply last")
	testing.expect(t, Style_Button_State.Selected in all_states.applied_transforms &&
		Style_Button_State.Hovered in all_states.applied_transforms &&
		Style_Button_State.Pressed in all_states.applied_transforms &&
		Style_Button_State.Disabled in all_states.applied_transforms,
		"the resolved recipe should retain the applied-transform provenance")
	testing.expect(t, selected.focus == style_environment_color(&rt, environment, .Focus) &&
		selected.semantic_active == style_environment_color(&rt, environment, .Semantic_Focus),
		"focus and semantic-active overlays should remain independent of selected styling")

	invalid := DEFAULT_STYLE_THEME
	invalid.button_recipes.recipes[int(Button_Variant.Quiet)] = Button_Recipe{
		defined=true,
		surface_role=.Surface,
		text_role=.Text,
		surface_visible=false,
		hovered=Style_Transform{surface_role=.Accent, surface_mix=1.2},
		focus_role=.Focus,
		semantic_active_role=.Semantic_Focus,
	}
	testing.expect(t, style_theme_register(&rt, invalid) == 0, "invalid transform amounts should be rejected")
}

@(test)
test_button_variant_is_retained_and_inspectable :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 220})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "first button recipe frame should build"); return }
	container_begin(&ui, .Root, key=key_string("button-recipe-root"), style=layout_style())
	button(&ui, "Save", key=key_string("save"), variant=.Default)
	button(&ui, "Legacy quiet", key=key_string("legacy-quiet"), state=Button_State{quiet=true})
	container_end(&ui)
	end_frame(&ui)
	button_id := style_recipe_test_button(&rt, "Save")
	testing.expect(t, button_id != 0 && rt.nodes[button_id].button_variant == .Default,
		"button variant should be stored in the retained node")
	legacy_quiet_id := style_recipe_test_button(&rt, "Legacy quiet")
	testing.expect(t, legacy_quiet_id != 0 && rt.nodes[legacy_quiet_id].button_variant == .Quiet,
		"the compatibility quiet flag should map to the quiet recipe")

	invalidate_root(&rt, "change button recipe variant")
	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "variant change should rebuild the invalidated description"); return }
	container_begin(&ui, .Root, key=key_string("button-recipe-root"), style=layout_style())
	button(&ui, "Save", key=key_string("save"), variant=.Primary)
	button(&ui, "Legacy quiet", key=key_string("legacy-quiet"), state=Button_State{quiet=true})
	container_end(&ui)
	end_frame(&ui)
	button_id = style_recipe_test_button(&rt, "Save")
	button_node := rt.nodes[button_id]
	testing.expect(t, button_node.button_variant == .Primary, "changing variant should update retained state")
	primary_surface, primary_surface_ok := paint_surface_color(button_node.paint[0])
	testing.expect(t, primary_surface_ok && primary_surface == style_environment_color(&rt, button_node.style_environment, .Accent),
		"changing variant should select the primary recipe paint")
	inspector := inspect(&rt)
	defer delete(inspector)
	testing.expect(t, strings.contains(inspector, "recipe=button.primary") && strings.contains(inspector, "focus overlay=Focus"),
		"inspector output should expose recipe, state provenance, and independent focus treatment")
}
