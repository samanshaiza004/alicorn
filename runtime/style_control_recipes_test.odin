package alicorn

import "core:testing"
import "core:strings"

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
	invalid_inset := Text_Field_Recipe{defined=true, horizontal_inset=-1}
	valid := style_text_field_recipe_is_valid(DEFAULT_TEXT_FIELD_RECIPE)
	testing.expect(t, valid, "the built-in text-field recipe should satisfy the typed recipe contract")
	testing.expect(t, !style_text_field_recipe_is_valid(invalid_role), "invalid semantic roles should be rejected")
	testing.expect(t, !style_text_field_recipe_is_valid(invalid_mix), "out-of-range state mixes should be rejected")
	testing.expect(t, !style_text_field_recipe_is_valid(invalid_inset), "negative content insets should be rejected")
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
	theme.text_field_recipe.horizontal_inset = 12
	theme.scrollbar_recipe.thumb_role = .Accent
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "theme with valid control recipes should register")
	environment := DEFAULT_STYLE_ENVIRONMENT
	environment.theme = theme_id

	field_recipe := style_text_field_recipe(&rt, environment)
	dense_environment := environment
	dense_environment.density = 1.25
	field := style_text_field_resolve(&rt, environment, field_recipe, Text_Field_Visual_State{focused=true})
	scroll_recipe := style_scrollbar_recipe(&rt, environment)
	scroll := style_scrollbar_resolve(&rt, environment, scroll_recipe, {})
	testing.expect(t, field.surface == theme.colors[int(Style_Color_Role.Surface)] && field.border == theme.colors[int(Style_Color_Role.Danger)],
		"registered text-field recipe should resolve through the owning theme")
	testing.expect(t, style_text_field_horizontal_inset(&rt, environment) == 12 &&
		style_text_field_horizontal_inset(&rt, dense_environment) == 15,
		"text-field content inset should resolve from its theme recipe and scale with environment density")
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
	invalid_checkbox_theme := DEFAULT_STYLE_THEME
	invalid_checkbox_theme.checkbox_recipe.checkmark.text_role = .Count
	invalid_slider_theme := DEFAULT_STYLE_THEME
	invalid_slider_theme.slider_recipe.thumb.border_role = .Count
	testing.expect(t, style_theme_register(&rt, invalid_field_theme) == 0,
		"theme registration should reject invalid text-field recipe roles")
	testing.expect(t, style_theme_register(&rt, invalid_scrollbar_theme) == 0,
		"theme registration should reject invalid scrollbar recipe roles")
	testing.expect(t, style_theme_register(&rt, invalid_checkbox_theme) == 0,
		"theme registration should reject invalid checkbox recipe roles")
	testing.expect(t, style_theme_register(&rt, invalid_slider_theme) == 0,
		"theme registration should reject invalid slider recipe roles")
}

@(test)
test_checkbox_and_slider_recipes_compose_states_in_order_and_keep_focus_independent :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 140})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.colors[int(Style_Color_Role.Surface)] = Color{0.08, 0.10, 0.14, 1}
	theme.colors[int(Style_Color_Role.Accent)] = Color{0.80, 0.10, 0.10, 1}
	theme.colors[int(Style_Color_Role.Accent_Hover)] = Color{0.10, 0.80, 0.10, 1}
	theme.colors[int(Style_Color_Role.Accent_Pressed)] = Color{0.10, 0.10, 0.80, 1}
	theme.colors[int(Style_Color_Role.Danger)] = Color{0.80, 0.80, 0.10, 1}
	theme.checkbox_recipe.box.selected.surface_role = .Accent
	theme.checkbox_recipe.box.selected.surface_mix = 0.25
	theme.checkbox_recipe.box.hovered.surface_role = .Accent_Hover
	theme.checkbox_recipe.box.hovered.surface_mix = 0.50
	theme.checkbox_recipe.box.pressed.surface_role = .Accent_Pressed
	theme.checkbox_recipe.box.pressed.surface_mix = 0.75
	theme.checkbox_recipe.box.disabled.surface_role = .Danger
	theme.checkbox_recipe.box.disabled.surface_mix = 0.20
	theme.slider_recipe.track.hovered.surface_role = .Accent
	theme.slider_recipe.track.hovered.surface_mix = 0.25
	theme.slider_recipe.track.pressed.surface_role = .Accent_Hover
	theme.slider_recipe.track.pressed.surface_mix = 0.50
	theme.slider_recipe.track.disabled.surface_role = .Danger
	theme.slider_recipe.track.disabled.surface_mix = 0.20
	theme.checkbox_recipe.focus_role = .Success
	theme.slider_recipe.focus_role = .Success
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "valid checkbox and slider recipes should register with a theme")
	if theme_id == 0 { return }
	environment := DEFAULT_STYLE_ENVIRONMENT
	environment.theme = theme_id

	checkbox_state := Checkbox_Visual_State{checked=true, hovered=true, pressed=true, disabled=true}
	checkbox := style_checkbox_resolve(&rt, environment, theme.checkbox_recipe, checkbox_state)
	checkbox_focused := style_checkbox_resolve(&rt, environment, theme.checkbox_recipe, Checkbox_Visual_State{
		checked=true, hovered=true, pressed=true, disabled=true, focused=true,
	})
	checkbox_expected := style_color_mix(
		style_color_mix(
			style_color_mix(
				style_color_mix(style_environment_color(&rt, environment, .Surface), theme.colors[int(Style_Color_Role.Accent)], 0.25),
				theme.colors[int(Style_Color_Role.Accent_Hover)], 0.50),
			theme.colors[int(Style_Color_Role.Accent_Pressed)], 0.75),
		theme.colors[int(Style_Color_Role.Danger)], 0.20)
	testing.expect(t, checkbox.box.surface == checkbox_expected,
		"checkbox transforms should apply in selected, hovered, pressed, disabled order")
	testing.expect(t, checkbox_focused.box.surface == checkbox.box.surface && checkbox_focused.focus == theme.colors[int(Style_Color_Role.Success)],
		"checkbox focus should be an independent overlay that does not replace composed fills")
	testing.expect(t, Style_Control_State.Selected in checkbox.applied_transforms &&
		Style_Control_State.Hovered in checkbox.applied_transforms &&
		Style_Control_State.Pressed in checkbox.applied_transforms &&
		Style_Control_State.Disabled in checkbox.applied_transforms,
		"the resolved checkbox style should report all applied state transforms")

	slider_state := Slider_Visual_State{hovered=true, pressed=true, disabled=true}
	slider := style_slider_resolve(&rt, environment, theme.slider_recipe, slider_state)
	slider_focused := style_slider_resolve(&rt, environment, theme.slider_recipe, Slider_Visual_State{
		hovered=true, pressed=true, disabled=true, focused=true,
	})
	slider_expected := style_color_mix(
		style_color_mix(
			style_color_mix(style_environment_color(&rt, environment, .Border), theme.colors[int(Style_Color_Role.Accent)], 0.25),
			theme.colors[int(Style_Color_Role.Accent_Hover)], 0.50),
		theme.colors[int(Style_Color_Role.Danger)], 0.20)
	testing.expect(t, slider.track.surface == slider_expected,
		"slider part transforms should apply hovered, pressed, disabled in deterministic order")
	testing.expect(t, slider_focused.track.surface == slider.track.surface && slider_focused.focus == theme.colors[int(Style_Color_Role.Success)],
		"slider focus should remain separate from track/fill/thumb state transforms")
	testing.expect(t, Style_Control_State.Hovered in slider.applied_transforms &&
		Style_Control_State.Pressed in slider.applied_transforms &&
		Style_Control_State.Disabled in slider.applied_transforms,
		"the resolved slider style should report all applied state transforms")
}

@(test)
test_checkbox_slider_recipes_drive_retained_paint_cache_and_inspector :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 160})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.colors[int(Style_Color_Role.Danger)] = Color{0.72, 0.12, 0.16, 1}
	theme.colors[int(Style_Color_Role.Success)] = Color{0.12, 0.68, 0.42, 1}
	theme.colors[int(Style_Color_Role.Accent_Hover)] = Color{0.96, 0.74, 0.24, 1}
	theme.colors[int(Style_Color_Role.Accent_Text)] = Color{0.98, 0.90, 0.72, 1}
	theme.checkbox_recipe.box.border_role = .Danger
	// Keep the checked-state box border transform out of this role-routing test;
	// transform order and composition are covered by the resolver test above.
	theme.checkbox_recipe.box.selected.border_mix = 0
	theme.checkbox_recipe.checkmark.selected.text_role = .Success
	theme.checkbox_recipe.checkmark.selected.text_mix = 1
	theme.checkbox_recipe.label.text_role = .Accent_Hover
	theme.slider_recipe.track.surface_role = .Danger
	theme.slider_recipe.fill.surface_role = .Success
	theme.slider_recipe.thumb.surface_role = .Accent_Hover
	theme.slider_recipe.label.text_role = .Accent_Text
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "themes should allow separate Checkbox and Slider part recipes")
	if theme_id == 0 { return }

	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "control recipe fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("recipe-controls-root"), style=layout_style(.Column, width=300, height=120, gap=8))
	scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	_ = checkbox(&ui, "Enabled", true, key=key_string("recipe-checkbox"))
	_ = slider_f32(&ui, "Gain", 0.6, 0, 1, key=key_string("recipe-slider"))
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)

	checkbox_id, slider_id := Node_ID(0), Node_ID(0)
	for id in rt.order {
		node := rt.nodes[id]
		if node.kind == .Checkbox { checkbox_id = id }
		if node.kind == .Slider { slider_id = id }
	}
	checkbox_node, checkbox_found := rt.nodes[checkbox_id]
	slider_node, slider_found := rt.nodes[slider_id]
	testing.expect(t, checkbox_found && slider_found, "the fixture should retain both styled controls")
	if !checkbox_found || !slider_found { return }

	checkbox_style := rt.computed_styles[checkbox_id].payload.(Checkbox_Resolved_Style)
	slider_style := rt.computed_styles[slider_id].payload.(Slider_Resolved_Style)
	testing.expect(t, checkbox_style.box.border == theme.colors[int(Style_Color_Role.Danger)],
		"Checkbox box border should resolve its independent recipe role")
	testing.expect(t, checkbox_style.checkmark.text == theme.colors[int(Style_Color_Role.Success)],
		"Checkbox checkmark should resolve its checked-state recipe transform")
	testing.expect(t, checkbox_style.label.text == theme.colors[int(Style_Color_Role.Accent_Hover)],
		"Checkbox label should resolve its independent recipe role")
	testing.expect(t, slider_style.track.surface == theme.colors[int(Style_Color_Role.Danger)] &&
		slider_style.fill.surface == theme.colors[int(Style_Color_Role.Success)] &&
		slider_style.thumb.surface == theme.colors[int(Style_Color_Role.Accent_Hover)] &&
		slider_style.label.text == theme.colors[int(Style_Color_Role.Accent_Text)],
		"Slider track, fill, thumb, and label should resolve independent theme recipe parts")

	checkbox_border_seen, checkbox_mark_seen, checkbox_label_seen := false, false, false
	for command in checkbox_node.paint {
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Danger)] { checkbox_border_seen = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Success)] { checkbox_mark_seen = true }
		if text, ok := command.payload.(Text_Paint); ok && text.color == theme.colors[int(Style_Color_Role.Accent_Hover)] { checkbox_label_seen = true }
	}
	slider_track_seen, slider_fill_seen, slider_thumb_seen, slider_label_seen := false, false, false, false
	for command in slider_node.paint {
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Danger)] { slider_track_seen = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Success)] { slider_fill_seen = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Accent_Hover)] { slider_thumb_seen = true }
		if text, ok := command.payload.(Text_Paint); ok && text.color == theme.colors[int(Style_Color_Role.Accent_Text)] { slider_label_seen = true }
	}
	testing.expect(t, checkbox_border_seen, "Checkbox retained paint should consume its resolved border color")
	testing.expect(t, checkbox_mark_seen, "Checkbox retained paint should consume its resolved checkmark color")
	testing.expect(t, checkbox_label_seen, "Checkbox retained paint should consume its resolved label color")
	testing.expect(t, slider_track_seen && slider_fill_seen && slider_thumb_seen && slider_label_seen,
		"Slider retained paint should consume its resolved track, fill, thumb, and label recipe colors")
	inspector := inspect(&rt)
	testing.expect(t, strings.contains(inspector, "checkbox style: recipe=checkbox.default") &&
		strings.contains(inspector, "slider style: recipe=slider.default") &&
		strings.contains(inspector, "token provenance: checkbox.default") &&
		strings.contains(inspector, "token provenance: slider.default"),
		"the inspector should expose resolved Checkbox and Slider recipe provenance")
	delete(inspector)

	focus_color := theme.colors[int(Style_Color_Role.Focus)]
	testing.expect(t, focus(&rt, checkbox_id), "Checkbox should accept retained keyboard focus")
	update_paint(&rt)
	checkbox_node = rt.nodes[checkbox_id]
	checkbox_focus_seen, checkbox_mark_after_focus := false, false
	for command in checkbox_node.paint {
		if color, ok := paint_surface_color(command); ok && color == focus_color { checkbox_focus_seen = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Success)] { checkbox_mark_after_focus = true }
	}
	testing.expect(t, checkbox_focus_seen && checkbox_mark_after_focus,
		"Checkbox focus should paint as an independent outline without replacing the checked mark")

	testing.expect(t, focus(&rt, slider_id), "Slider should accept retained keyboard focus")
	update_paint(&rt)
	slider_node = rt.nodes[slider_id]
	slider_focus_seen, slider_track_after_focus, slider_fill_after_focus, slider_thumb_after_focus := false, false, false, false
	for command in slider_node.paint {
		if color, ok := paint_surface_color(command); ok && color == focus_color { slider_focus_seen = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Danger)] { slider_track_after_focus = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Success)] { slider_fill_after_focus = true }
		if color, ok := paint_surface_color(command); ok && color == theme.colors[int(Style_Color_Role.Accent_Hover)] { slider_thumb_after_focus = true }
	}
	testing.expect(t, slider_focus_seen && slider_track_after_focus && slider_fill_after_focus && slider_thumb_after_focus,
		"Slider focus should paint as an independent outline without replacing track, fill, or thumb")
}

@(test)
test_checkbox_slider_recipes_reject_invalid_parts_and_transforms :: proc(t: ^testing.T) {
	invalid_checkbox_role := Checkbox_Recipe{defined=true, box=Control_Part_Recipe{surface_role=.Count}}
	invalid_slider_mix := Slider_Recipe{defined=true, thumb=Control_Part_Recipe{
		pressed=Control_Part_Transform{surface_mix=1.25},
	}}
	testing.expect(t, style_checkbox_recipe_is_valid(DEFAULT_CHECKBOX_RECIPE),
		"the built-in Checkbox recipe should satisfy the typed part contract")
	testing.expect(t, style_slider_recipe_is_valid(DEFAULT_SLIDER_RECIPE),
		"the built-in Slider recipe should satisfy the typed part contract")
	testing.expect(t, !style_checkbox_recipe_is_valid(invalid_checkbox_role),
		"invalid Checkbox part roles should be rejected")
	testing.expect(t, !style_slider_recipe_is_valid(invalid_slider_mix),
		"out-of-range Slider transform mixes should be rejected")
}
