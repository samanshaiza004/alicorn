package alicorn

import "core:testing"

@(test)
test_style_tokens_are_typed_theme_local_and_immutable :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 100})
	defer destroy_runtime(&rt)

	app_role := style_extension_color_role_id("app.editor", "current-line")
	length_role := style_extension_length_role_id("app.editor", "gutter-width")
	colors := []Color{Color{0.9, 0.1, 0.1, 1}}
	lengths := []Style_Length{Style_Length{logical_units=24}}
	theme := DEFAULT_STYLE_THEME
	theme.color_tokens = colors
	theme.length_tokens = lengths
	theme.core_color_tokens[int(Style_Color_Role.Text)] = Style_Color_Token_ID(1)
	theme.extension_color_roles = []Style_Extension_Color_Role_Binding{
		Style_Extension_Color_Role_Binding{role=app_role, token=Style_Color_Token_ID(1)},
	}
	theme.extension_length_roles = []Style_Extension_Length_Role_Binding{
		Style_Extension_Length_Role_Binding{role=length_role, token=Style_Length_Token_ID(1)},
	}
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "a well-typed theme should register")

	// Registration owns an immutable copy, and token 1 only has meaning under
	// this theme ID. Mutating caller storage must not mutate retained theme data.
	colors[0] = Color{0.1, 0.1, 0.9, 1}
	lengths[0] = Style_Length{logical_units=96}
	core_text := style_theme_color(&rt, theme_id, .Text)
	app_color, app_color_found := style_extension_color(&rt, theme_id, app_role)
	app_length, app_length_found := style_extension_length(&rt, theme_id, length_role)
	testing.expect(t, core_text == Color{0.9, 0.1, 0.1, 1}, "core semantic roles should resolve through a typed color token")
	testing.expect(t, app_color_found && app_color == Color{0.9, 0.1, 0.1, 1}, "extension roles should resolve through namespaced typed IDs")
	testing.expect(t, app_length_found && app_length.logical_units == 24, "length tokens should retain their logical-unit value")

	other := DEFAULT_STYLE_THEME
	other.color_tokens = []Color{Color{0.1, 0.1, 0.9, 1}}
	other_id := style_theme_register(&rt, other)
	other_color, other_found := style_token_color(&rt, other_id, Style_Color_Token_ID(1))
	testing.expect(t, other_found && other_color == Color{0.1, 0.1, 0.9, 1}, "the same local token index must be scoped by its theme identity")
	testing.expect(t, style_theme_color(&rt, theme_id, .Text) == Color{0.9, 0.1, 0.1, 1}, "registering another theme must not invalidate earlier theme-local IDs")
	_, bad_theme := style_token_color(&rt, other_id, Style_Color_Token_ID(2))
	testing.expect(t, !bad_theme, "out-of-range theme-local token IDs must be rejected")
}

@(test)
test_style_extension_role_ids_are_namespaced_and_theme_validation_is_strict :: proc(t: ^testing.T) {
	first := style_extension_color_role_id("app.editor", "modified")
	other_namespace := style_extension_color_role_id("vendor.editor", "modified")
	other_kind := style_extension_length_role_id("app.editor", "modified")
	testing.expect(t, first != 0 && first != other_namespace, "extension role identity must include its namespace")
	testing.expect(t, u64(first) != u64(other_kind), "extension role IDs must distinguish value kinds")
	testing.expect(t, style_extension_color_role_id("", "modified") == 0, "an extension role without a namespace is invalid")

	rt := new_runtime(Rect{0, 0, 100, 100})
	defer destroy_runtime(&rt)
	bad := DEFAULT_STYLE_THEME
	bad.color_tokens = []Color{Color{0.2, 0.3, 0.4, 1}}
	bad.core_color_tokens[int(Style_Color_Role.Text)] = Style_Color_Token_ID(2)
	testing.expect(t, style_theme_register(&rt, bad) == 0, "a core role cannot reference an out-of-range token")

	role := style_extension_color_role_id("app", "duplicate")
	bad.core_color_tokens = {}
	bad.extension_color_roles = []Style_Extension_Color_Role_Binding{
		Style_Extension_Color_Role_Binding{role=role, token=Style_Color_Token_ID(1)},
		Style_Extension_Color_Role_Binding{role=role, token=Style_Color_Token_ID(1)},
	}
	testing.expect(t, style_theme_register(&rt, bad) == 0, "duplicate extension role bindings must be rejected")
}
