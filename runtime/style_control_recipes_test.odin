package alicorn

import "core:testing"

@(test)
test_text_field_recipe_keeps_focus_independent_from_hover :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)

	base := style_text_field_resolve(&rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_TEXT_FIELD_RECIPE, {})
	hovered := style_text_field_resolve(&rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_TEXT_FIELD_RECIPE, Text_Field_Visual_State{hovered=true})
	focused := style_text_field_resolve(&rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_TEXT_FIELD_RECIPE, Text_Field_Visual_State{focused=true})
	both := style_text_field_resolve(&rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_TEXT_FIELD_RECIPE, Text_Field_Visual_State{hovered=true, focused=true})

	text_role := style_color(&UI{runtime=&rt}, .Text)
	focus_role := style_color(&UI{runtime=&rt}, .Focus)
	selection_role := style_color(&UI{runtime=&rt}, .Selection)
	caret_role := style_color(&UI{runtime=&rt}, .Accent)
	testing.expect(t, base.text == text_role && base.selection == selection_role && base.caret == caret_role,
		"the text-field base recipe should resolve text, selection, and caret through semantic roles")
	testing.expect(t, base.border != focused.border && focused.focus == focus_role,
		"focus should strengthen the field border while remaining available as an independent overlay")
	testing.expect(t, hovered.surface != base.surface && hovered.border != base.border,
		"hover should transform the field surface and border independently from focus")
	testing.expect(t, both.surface == hovered.surface && both.border == focused.border && both.focus == focus_role,
		"hover and focus should compose without focus erasing the hover surface")
}

@(test)
test_text_field_recipe_rejects_invalid_roles_and_mixes :: proc(t: ^testing.T) {
	invalid_role := Text_Field_Recipe{defined=true, border_role=.Count}
	invalid_mix := Text_Field_Recipe{defined=true, hovered=Control_Part_Transform{border_mix=1.5}}
	valid := style_text_field_recipe_is_valid(DEFAULT_TEXT_FIELD_RECIPE)
	testing.expect(t, valid, "the built-in text-field recipe should satisfy the typed recipe contract")
	testing.expect(t, !style_text_field_recipe_is_valid(invalid_role), "invalid semantic roles should be rejected")
	testing.expect(t, !style_text_field_recipe_is_valid(invalid_mix), "out-of-range state mixes should be rejected")
}

@(test)
test_scrollbar_recipe_transforms_thumb_states_in_order :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	state := Scrollbar_Visual_State{hovered=true, pressed=true}
	resolved := style_scrollbar_resolve(&rt, DEFAULT_STYLE_ENVIRONMENT, DEFAULT_SCROLLBAR_RECIPE, state)
	base_thumb := style_color(&UI{runtime=&rt}, .Scrollbar_Thumb)
	track := style_color(&UI{runtime=&rt}, .Scrollbar_Track)
	text := style_color(&UI{runtime=&rt}, .Text)
	accent := style_color(&UI{runtime=&rt}, .Accent)
	expected := style_color_mix(style_color_mix(base_thumb, text, 0.14), accent, 0.22)
	testing.expect(t, resolved.track == track && resolved.corner == style_color(&UI{runtime=&rt}, .Surface),
		"scrollbar track and corner should use independent semantic parts")
	testing.expect(t, resolved.thumb == expected,
		"thumb hover and press should compose in a deterministic order")
	testing.expect(t, resolved.hovered && resolved.pressed, "resolved style should preserve interaction provenance")
}

@(test)
test_scrollbar_recipe_rejects_invalid_roles :: proc(t: ^testing.T) {
	invalid := Scrollbar_Recipe{defined=true, thumb_role=.Count}
	testing.expect(t, style_scrollbar_recipe_is_valid(DEFAULT_SCROLLBAR_RECIPE),
		"the built-in scrollbar recipe should satisfy the typed recipe contract")
	testing.expect(t, !style_scrollbar_recipe_is_valid(invalid), "invalid scrollbar part roles should be rejected")
}

@(test)
test_text_field_paint_emits_recipe_surface_border_and_focus_overlay :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "text-field recipe fixture should build"); return }
	container_begin(&ui, .Root, label="text-field-recipe-root")
	id := text_field(&ui, "query", key=key_string("field"), style=layout_style(width=180, height=32))
	container_end(&ui)
	end_frame(&ui)

	node, found := rt.nodes[id]
	testing.expect(t, found && len(node.paint) >= 6, "text-field paint should include a surface, text, border, and focus treatment")
	if !found || len(node.paint) < 6 { return }
	background, background_ok := paint_surface_color(node.paint[0])
	testing.expect(t, background_ok && background == style_color(&UI{runtime=&rt}, DEFAULT_TEXT_FIELD_RECIPE.surface_role),
		"text fields should paint their semantic recipe surface before content")
	base_border := style_color(&UI{runtime=&rt}, DEFAULT_TEXT_FIELD_RECIPE.border_role)
	focus_border := style_color(&UI{runtime=&rt}, DEFAULT_TEXT_FIELD_RECIPE.focus_role)
	base_border_seen := false
	for command in node.paint {
		if color, ok := paint_surface_color(command); ok && color == base_border { base_border_seen = true; break }
	}
	testing.expect(t, base_border_seen, "the text-field recipe should paint a distinct outline in the unfocused state")
	testing.expect(t, focus(&rt, id), "text field should accept focus for overlay paint validation")
	update_paint(&rt)
	node = rt.nodes[id]
	focus_overlay_seen := false
	for command in node.paint {
		if color, ok := paint_surface_color(command); ok && color == focus_border { focus_overlay_seen = true; break }
	}
	testing.expect(t, focus_overlay_seen, "focused text fields should paint an independent semantic focus overlay")
}

@(test)
test_registered_theme_overrides_text_field_and_scrollbar_recipes :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.colors[int(Style_Color_Role.Surface)] = Color{0.31, 0.42, 0.53, 1}
	theme.colors[int(Style_Color_Role.Danger)] = Color{0.75, 0.08, 0.12, 1}
	theme.text_field_recipe.surface_role = .Surface
	theme.text_field_recipe.focused_border_role = .Danger
	theme.scrollbar_recipe.thumb_role = .Accent
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "theme with valid control recipes should register")
	environment := DEFAULT_STYLE_ENVIRONMENT
	environment.theme = theme_id

	field_recipe := style_text_field_recipe(&rt, environment)
	field := style_text_field_resolve(&rt, environment, field_recipe, Text_Field_Visual_State{focused=true})
	scroll_recipe := style_scrollbar_recipe(&rt, environment)
	scroll := style_scrollbar_resolve(&rt, environment, scroll_recipe, {})
	testing.expect(t, field.surface == theme.colors[int(Style_Color_Role.Surface)] && field.border == theme.colors[int(Style_Color_Role.Danger)],
		"registered text-field recipe should resolve through the owning theme")
	testing.expect(t, scroll.thumb == theme.colors[int(Style_Color_Role.Accent)],
		"registered scrollbar recipe should resolve its thumb role through the owning theme")

	next_environment := DEFAULT_STYLE_ENVIRONMENT
	next_environment.theme = theme_id
	theme_domains := style_environment_changed_domains(DEFAULT_STYLE_ENVIRONMENT, next_environment)
	theme_dirty_stages := style_domains_dirty_stages(theme_domains)
	testing.expect(t, Style_Domain.Paint in theme_domains &&
		Style_Domain.Metrics not_in theme_domains && Style_Domain.Typography not_in theme_domains &&
		Style_Domain.Material not_in theme_domains &&
		Dirty_Stage.Paint in theme_dirty_stages && Dirty_Stage.Composite in theme_dirty_stages &&
		Dirty_Stage.Layout not_in theme_dirty_stages,
		"current theme switches should remain paint-only while control recipes consume color roles only")
}

@(test)
test_invalid_control_recipe_prevents_theme_registration :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	invalid_field_theme := DEFAULT_STYLE_THEME
	invalid_field_theme.text_field_recipe.focus_role = .Count
	invalid_scrollbar_theme := DEFAULT_STYLE_THEME
	invalid_scrollbar_theme.scrollbar_recipe.corner_role = .Count
	testing.expect(t, style_theme_register(&rt, invalid_field_theme) == 0,
		"theme registration should reject invalid text-field recipe roles")
	testing.expect(t, style_theme_register(&rt, invalid_scrollbar_theme) == 0,
		"theme registration should reject invalid scrollbar recipe roles")
}
