package alicorn

import "core:testing"

@(test)
test_style_tokens_are_scoped_to_immutable_theme_ids :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	first := DEFAULT_STYLE_THEME
	first.color_tokens = {Color{0.8, 0.1, 0.2, 1}}
	first.length_tokens = {Style_Length{logical_units=12}}
	first.core_color_tokens[int(Style_Color_Role.Text)] = Style_Color_Token_ID(1)
	first_id := style_theme_register(&rt, first)
	testing.expect(t, first_id != 0, "valid typed token theme should register")

	other := DEFAULT_STYLE_THEME
	other.color_tokens = {Color{0.1, 0.2, 0.8, 1}}
	other.length_tokens = {Style_Length{logical_units=28}}
	other_id := style_theme_register(&rt, other)
	testing.expect(t, other_id != 0, "a second theme may reuse local token index 1")

	first_text := style_theme_color(&rt, first_id, .Text)
	other_color, other_found := style_token_color(&rt, other_id, Style_Color_Token_ID(1))
	length, length_found := style_token_length(&rt, other_id, Style_Length_Token_ID(1))
	testing.expect(t, first_text == Color{0.8, 0.1, 0.2, 1}, "core roles should resolve typed tokens using their theme identity")
	testing.expect(t, other_found && other_color == Color{0.1, 0.2, 0.8, 1}, "local token index 1 should address the other theme's own token")
	testing.expect(t, length_found && length.logical_units == 28, "length tokens should preserve logical units")
	_, invalid_color := style_token_color(&rt, first_id, Style_Color_Token_ID(2))
	_, invalid_length := style_token_length(&rt, other_id, Style_Length_Token_ID(2))
	testing.expect(t, !invalid_color && !invalid_length, "out-of-range local IDs must fail safely")
}

@(test)
test_style_theme_registration_copies_token_storage :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	colors := [1]Color{Color{0.7, 0.6, 0.5, 1}}
	lengths := [1]Style_Length{Style_Length{logical_units=16}}
	color_roles := [1]Style_Extension_Color_Role_Binding{{
		role=style_extension_color_role_id("app.editor", "marker"), token=Style_Color_Token_ID(1),
	}}
	length_roles := [1]Style_Extension_Length_Role_Binding{{
		role=style_extension_length_role_id("vendor.audio", "meter.width"), token=Style_Length_Token_ID(1),
	}}
	theme := DEFAULT_STYLE_THEME
	theme.color_tokens = colors[:]
	theme.length_tokens = lengths[:]
	theme.extension_color_roles = color_roles[:]
	theme.extension_length_roles = length_roles[:]
	id := style_theme_register(&rt, theme)
	testing.expect(t, id != 0, "valid extension role bindings should register")
	if id == 0 { return }

	colors[0] = Color{}
	lengths[0] = Style_Length{}
	color_roles[0] = Style_Extension_Color_Role_Binding{}
	length_roles[0] = Style_Extension_Length_Role_Binding{}
	color, color_found := style_extension_color(&rt, id, style_extension_color_role_id("app.editor", "marker"))
	length, length_found := style_extension_length(&rt, id, style_extension_length_role_id("vendor.audio", "meter.width"))
	_, role_found := style_extension_color_token(&rt, id, style_extension_color_role_id("app.editor", "marker"))
	testing.expect(t, color_found && color == Color{0.7, 0.6, 0.5, 1}, "registered colors must not borrow the caller's slices")
	testing.expect(t, length_found && length.logical_units == 16, "registered lengths must not borrow the caller's slices")
	testing.expect(t, role_found, "extension roles should resolve to a typed local token during setup")
}

@(test)
test_style_extension_role_ids_are_namespaced_and_type_separated :: proc(t: ^testing.T) {
	app := style_extension_color_role_id("app.editor", "current_line")
	other_namespace := style_extension_color_role_id("vendor.editor", "current_line")
	length := style_extension_length_role_id("app.editor", "current_line")
	testing.expect(t, app != 0 && app != other_namespace, "qualified names should produce distinct stable color role IDs")
	testing.expect(t, u64(app) != u64(length), "color and length role IDs should use distinct type tags")
	testing.expect(t, style_extension_color_role_id("app.editor", "current_line") == app,
		"the same qualified role should have a stable ID across calls")
}

@(test)
test_style_theme_rejects_invalid_typed_bindings :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	bad_index := DEFAULT_STYLE_THEME
	bad_index.color_tokens = {Color{1, 1, 1, 1}}
	bad_index.core_color_tokens[int(Style_Color_Role.Text)] = Style_Color_Token_ID(2)
	testing.expect(t, style_theme_register(&rt, bad_index) == 0, "core bindings cannot point outside a theme-local token array")

	bad_duplicate := DEFAULT_STYLE_THEME
	role := style_extension_color_role_id("app.editor", "marker")
	bad_duplicate.color_tokens = {Color{1, 1, 1, 1}}
	bad_duplicate.extension_color_roles = {
		Style_Extension_Color_Role_Binding{role=role, token=Style_Color_Token_ID(1)},
		Style_Extension_Color_Role_Binding{role=role, token=Style_Color_Token_ID(1)},
	}
	testing.expect(t, style_theme_register(&rt, bad_duplicate) == 0, "duplicate extension role bindings must be rejected")

	bad_length := DEFAULT_STYLE_THEME
	bad_length.length_tokens = {Style_Length{logical_units=-1}}
	testing.expect(t, style_theme_register(&rt, bad_length) == 0, "negative logical lengths must be rejected")
}
