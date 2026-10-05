package alicorn

import "core:testing"

@(test)
test_retained_computed_style_is_scoped_to_theme_identity :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)

	red_theme := DEFAULT_STYLE_THEME
	red_theme.colors[int(Style_Color_Role.Accent)] = Color{0.9, 0.1, 0.1, 1}
	red_id := style_theme_register(&rt, red_theme)
	blue_theme := DEFAULT_STYLE_THEME
	blue_theme.colors[int(Style_Color_Role.Accent)] = Color{0.1, 0.1, 0.9, 1}
	blue_id := style_theme_register(&rt, blue_theme)

	node := Node{
		style_environment=Style_Environment{theme=red_id, density=1, text_scale=1},
		button_variant=.Primary,
	}
	first := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, first.surface == red_theme.colors[int(Style_Color_Role.Accent)], "computed style should resolve through the node's initial theme")
	testing.expect(t, node.computed_button_style_valid && node.computed_button_style_signature.theme == red_id,
		"retained computed style should carry its theme identity/generation")

	// The token indices and recipe slots are allowed to repeat between themes;
	// the node must recompute when theme identity changes.
	node.style_environment.theme = blue_id
	second := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, second.surface == blue_theme.colors[int(Style_Color_Role.Accent)] && second.surface != first.surface,
		"a stale computed style from another theme must never be reused")
	again := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, again == second, "an unchanged node/theme/state should reuse its retained computed result")

	node.style_environment.accent = style_accent(Color{0.2, 0.8, 0.3, 1})
	accented := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, accented.surface == style_accent_color(node.style_environment.accent),
		"the full scoped environment must participate in the retained style signature")
}
