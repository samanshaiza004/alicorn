package alicorn

// Typed token IDs are indices into one immutable Style_Theme. Their value is
// meaningful only with that theme's Style_Theme_ID.
Style_Color_Token_ID  :: distinct u32
Style_Length_Token_ID :: distinct u32

// Style_Length is expressed in context-free Alicorn logical units. Relative
// typography/layout units require explicit dependency tracking and are not
// part of this contract.
Style_Length :: struct {
	logical_units: f32,
}

// Extension roles are stable namespaced identifiers, separate from the fixed
// core Style_Color_Role enum. Hashes are computed during setup, not per frame.
Style_Extension_Color_Role_ID  :: distinct u64
Style_Extension_Length_Role_ID :: distinct u64

Style_Extension_Color_Role_Binding :: struct {
	role:  Style_Extension_Color_Role_ID,
	token: Style_Color_Token_ID,
}

Style_Extension_Length_Role_Binding :: struct {
	role:  Style_Extension_Length_Role_ID,
	token: Style_Length_Token_ID,
}

// Optional authored names and immediate aliases let the inspector explain a
// compiled token's path without putting parsing or source files in Runtime.
// IDs use the same one-based indices as their corresponding typed token arrays.
Style_Token_Provenance :: struct {
	id:           u32,
	name:         string,
	alias_target: string,
}

Style_Extension_Color_Role_Provenance :: struct {
	role: Style_Extension_Color_Role_ID,
	name: string,
}

Style_Extension_Length_Role_Provenance :: struct {
	role: Style_Extension_Length_Role_ID,
	name: string,
}

style_extension_role_hash :: proc(namespace, name: string, type_tag: u64) -> u64 {
	if len(namespace) == 0 || len(name) == 0 { return 0 }
	h := hash_mix(1469598103934665603, type_tag)
	for index := 0; index < len(namespace); index += 1 { h = hash_mix(h, u64(namespace[index])) }
	h = hash_mix(h, u64('.'))
	for index := 0; index < len(name); index += 1 { h = hash_mix(h, u64(name[index])) }
	if h == 0 { return 1 }
	return h
}

style_extension_color_role_id :: proc(namespace, name: string) -> Style_Extension_Color_Role_ID {
	return Style_Extension_Color_Role_ID(style_extension_role_hash(namespace, name, 1))
}

style_extension_length_role_id :: proc(namespace, name: string) -> Style_Extension_Length_Role_ID {
	return Style_Extension_Length_Role_ID(style_extension_role_hash(namespace, name, 2))
}

style_token_provenance :: proc(rt: ^Runtime, theme: Style_Theme_ID, token: Style_Color_Token_ID) -> (value: Style_Token_Provenance, found: bool) {
	theme_index := u64(u32(theme))
	token_index := u64(u32(token))
	if rt == nil || theme_index == 0 || theme_index > u64(len(rt.style_themes)) || token_index == 0 { return }
	metadata := rt.style_themes[theme_index-1].color_token_provenance
	if token_index > u64(len(metadata)) { return }
	value = metadata[token_index-1]
	return value, value.id == u32(token_index) && value.name != ""
}

style_length_token_provenance :: proc(rt: ^Runtime, theme: Style_Theme_ID, token: Style_Length_Token_ID) -> (value: Style_Token_Provenance, found: bool) {
	theme_index := u64(u32(theme))
	token_index := u64(u32(token))
	if rt == nil || theme_index == 0 || theme_index > u64(len(rt.style_themes)) || token_index == 0 { return }
	metadata := rt.style_themes[theme_index-1].length_token_provenance
	if token_index > u64(len(metadata)) { return }
	value = metadata[token_index-1]
	return value, value.id == u32(token_index) && value.name != ""
}

style_extension_color_role_name :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Extension_Color_Role_ID) -> (name: string, found: bool) {
	theme_index := u64(u32(theme))
	if rt == nil || theme_index == 0 || theme_index > u64(len(rt.style_themes)) || role == 0 { return }
	for provenance in rt.style_themes[theme_index-1].extension_color_role_provenance {
		if provenance.role == role { return provenance.name, provenance.name != "" }
	}
	return
}

style_extension_length_role_name :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Extension_Length_Role_ID) -> (name: string, found: bool) {
	theme_index := u64(u32(theme))
	if rt == nil || theme_index == 0 || theme_index > u64(len(rt.style_themes)) || role == 0 { return }
	for provenance in rt.style_themes[theme_index-1].extension_length_role_provenance {
		if provenance.role == role { return provenance.name, provenance.name != "" }
	}
	return
}

style_token_color :: proc(rt: ^Runtime, theme: Style_Theme_ID, token: Style_Color_Token_ID) -> (value: Color, ok: bool) {
	index := u64(u32(token))
	theme_index := u64(u32(theme))
	if rt == nil || index == 0 || theme_index == 0 || theme_index > u64(len(rt.style_themes)) { return }
	colors := rt.style_themes[theme_index-1].color_tokens
	if index > u64(len(colors)) { return }
	return colors[index-1], true
}

style_token_length :: proc(rt: ^Runtime, theme: Style_Theme_ID, token: Style_Length_Token_ID) -> (value: Style_Length, ok: bool) {
	index := u64(u32(token))
	theme_index := u64(u32(theme))
	if rt == nil || index == 0 || theme_index == 0 || theme_index > u64(len(rt.style_themes)) { return }
	lengths := rt.style_themes[theme_index-1].length_tokens
	if index > u64(len(lengths)) { return }
	return lengths[index-1], true
}

// Resolve role names once during setup and retain the returned token ID.
// These small per-theme binding tables intentionally avoid a global interner.
style_extension_color_token :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Extension_Color_Role_ID) -> (token: Style_Color_Token_ID, found: bool) {
	theme_index := u64(u32(theme))
	if rt == nil || role == 0 || theme_index == 0 || theme_index > u64(len(rt.style_themes)) { return }
	for binding in rt.style_themes[theme_index-1].extension_color_roles {
		if binding.role == role { return binding.token, true }
	}
	return
}

style_extension_length_token :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Extension_Length_Role_ID) -> (token: Style_Length_Token_ID, found: bool) {
	theme_index := u64(u32(theme))
	if rt == nil || role == 0 || theme_index == 0 || theme_index > u64(len(rt.style_themes)) { return }
	for binding in rt.style_themes[theme_index-1].extension_length_roles {
		if binding.role == role { return binding.token, true }
	}
	return
}

style_extension_color :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Extension_Color_Role_ID) -> (value: Color, found: bool) {
	token, ok := style_extension_color_token(rt, theme, role)
	if !ok { return }
	return style_token_color(rt, theme, token)
}

style_extension_length :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Extension_Length_Role_ID) -> (value: Style_Length, found: bool) {
	token, ok := style_extension_length_token(rt, theme, role)
	if !ok { return }
	return style_token_length(rt, theme, token)
}
