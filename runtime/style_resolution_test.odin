package alicorn

import "core:testing"
import "core:strings"

@(test)
test_retained_computed_style_is_scoped_to_theme_identity :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)

	red_theme := DEFAULT_STYLE_THEME
	red_theme.colors[int(Style_Color_Role.Accent)] = Color{0.9, 0.1, 0.1, 1}
	red_theme.color_tokens = {red_theme.colors[int(Style_Color_Role.Accent)]}
	red_theme.core_color_tokens[int(Style_Color_Role.Accent)] = Style_Color_Token_ID(1)
	red_id := style_theme_register(&rt, red_theme)
	blue_theme := DEFAULT_STYLE_THEME
	blue_theme.colors[int(Style_Color_Role.Accent)] = Color{0.1, 0.1, 0.9, 1}
	blue_theme.color_tokens = {blue_theme.colors[int(Style_Color_Role.Accent)]}
	blue_theme.core_color_tokens[int(Style_Color_Role.Accent)] = Style_Color_Token_ID(1)
	blue_id := style_theme_register(&rt, blue_theme)

	node := Node{
		style_environment=Style_Environment{theme=red_id, density=1, text_scale=1},
		button_variant=.Primary,
	}
	first := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, first.surface == red_theme.colors[int(Style_Color_Role.Accent)], "computed style should resolve through the node's initial theme")
	testing.expect(t, node.computed_style.valid && node.computed_style.provenance.theme == red_id,
		"retained computed style should carry its theme identity and provenance")
	testing.expect(t, node.computed_style.dependencies == BUTTON_STYLE_DEPENDENCIES &&
		node.computed_style.provenance.variant == u8(Button_Variant.Primary) &&
		node.computed_style.provenance.state_bits == 0,
		"button style provenance should identify the recipe inputs and paint dependency")
	testing.expect(t, style_theme_color_token(&rt, red_id, .Accent) == Style_Color_Token_ID(1),
		"inspector provenance can resolve semantic roles to theme-local token IDs")
	hovered := style_button_resolve_retained(&rt, &node, Button_Visual_State{hovered=true})
	testing.expect(t, node.computed_style.provenance.state_bits == style_button_state_bits(Button_Visual_State{hovered=true}) &&
		hovered.applied_transforms == {.Hovered},
		"a state change must recompute and retain provenance for the transform that produced the style")
	hovered_cached := style_button_resolve_retained(&rt, &node, Button_Visual_State{hovered=true})
	testing.expect(t, hovered_cached == hovered && node.computed_style.provenance.state_bits == style_button_state_bits(Button_Visual_State{hovered=true}),
		"an unchanged state should reuse both the resolved result and its matching provenance")

	// The token indices and recipe slots are allowed to repeat between themes;
	// the node must recompute when theme identity changes.
	node.style_environment.theme = blue_id
	second := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, second.surface == blue_theme.colors[int(Style_Color_Role.Accent)] && second.surface != first.surface,
		"a stale computed style from another theme must never be reused")
	again := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, again == second, "an unchanged node/theme/state should reuse its retained computed result")
	resolved_generations := node.computed_style.generations
	style_generations_advance(&node.style_generations, {.Metrics, .Typography})
	metric_only := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, metric_only == second && node.computed_style.generations == resolved_generations,
		"paint-only button style should reuse its computed result after metric/typography generations change")
	style_generations_advance(&node.style_generations, {.Material})
	material_only := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, material_only == second && node.computed_style.generations == resolved_generations,
		"flat button style should not depend on material generations")
	style_generations_advance(&node.style_generations, {.Paint})
	paint_changed := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, paint_changed == second && node.computed_style.generations.paint == node.style_generations.paint,
		"a changed paint generation should recompute and record only the dependent generation")
	wrapped_generations := Style_Generations{paint=0xFFFFFFFF}
	wrapped := style_generations_advance(&wrapped_generations, {.Paint})
	testing.expect(t, wrapped && wrapped_generations.paint == 1,
		"generation wrap should report that retained snapshots must be invalidated")

	node.style_environment.accent = style_accent(Color{0.2, 0.8, 0.3, 1})
	accented := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, accented.surface == style_accent_color(node.style_environment.accent),
		"the paint-relevant accent override must participate in retained style provenance")
}

@(test)
test_computed_style_inspector_reports_dependency_and_token_provenance :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 80})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.color_tokens = {theme.colors[int(Style_Color_Role.Accent)]}
	theme.core_color_tokens[int(Style_Color_Role.Accent)] = Style_Color_Token_ID(1)
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "provenance theme should register")

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "first style inspector frame should build"); return }
	container_begin(&ui, .Root, key=key_string("computed-style-root"), style=layout_style())
	scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	button(&ui, "Save", key=key_string("computed-style-save"), variant=.Primary)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Button {
			_ = style_button_resolve_retained(&rt, node, Button_Visual_State{hovered=true})
			break
		}
	}
	inspection := inspect(&rt)
	defer delete(inspection)
	testing.expect(t, strings.contains(inspection, "computed style: dependencies=paint") && strings.contains(inspection, "generations=(metrics="),
		"inspector should expose style dependency domains and the generations used by the retained result")
	testing.expect(t, strings.contains(inspection, "token provenance: button.primary") && strings.contains(inspection, "hovered") &&
		strings.contains(inspection, "token=1"),
		"inspector should explain the semantic recipe, applied state, and theme-local token ID")
}
