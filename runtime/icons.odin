package alicorn

ICON_TRAILING_SLOT_WIDTH :: f32(26)

icon_id_is_valid :: proc(id: Icon_ID) -> bool {
    return id > .None && id < .Count
}

icon :: proc(
	ui: ^UI,
	id: Icon_ID,
	key: UI_Key = UI_Unkeyed{},
	size: f32 = 16,
	color_role := Style_Color_Role.Muted_Text,
	loc := #caller_location,
) -> Node_ID {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return 0 }
	if !icon_id_is_valid(id) || size <= 0 || !style_color_role_is_valid(color_role) {
		append_diagnostic(ui.runtime, "icon requires a built-in icon ID, positive size, and valid theme color role")
		return 0
	}
	rt := ui.runtime
	node := container_begin_simple(
		ui,
		.Container,
		label="",
		key=key,
		style=layout_style(width=size, height=size),
		loc=loc,
	)
	if node == 0 { return 0 }
	pending := &rt.pending[len(rt.pending)-1]
	if pending.kind == .Description && pending.description.id == node {
		pending.description.icon_id = id
		pending.description.color   = style_color(ui, color_role)
	}
	container_end(ui)
	return node
}
