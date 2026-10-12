package alicorn

import "core:testing"

@(test)
test_builtin_icons_have_font_independent_vector_paths :: proc(t: ^testing.T) {
	for raw_id in int(Icon_ID.Check)..<int(Icon_ID.Count) {
		id := Icon_ID(raw_id)
		geometry := icon_geometry(id)
		testing.expect(t, icon_id_is_valid(id) && geometry.count > 0 && geometry.count <= ICON_MAX_SEGMENTS,
			"every built-in icon should resolve to a bounded, nonempty vector path")
		for segment in geometry.segments[:geometry.count] {
			testing.expect(t, segment.x0 >= 0 && segment.x0 <= 1 && segment.y0 >= 0 && segment.y0 <= 1 &&
				segment.x1 >= 0 && segment.x1 <= 1 && segment.y1 >= 0 && segment.y1 <= 1,
				"normalized icon points should remain inside their stable drawing box")
		}
	}
	testing.expect(t, !icon_id_is_valid(.None) && !icon_id_is_valid(.Count),
		"sentinel IDs should not be drawable icons")
}

@(test)
test_icon_widget_retains_theme_tinted_paint_without_text :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 160, 80})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "icon fixture should begin a frame"); return }
	container_begin_simple(&ui, .Root, label="icon-test-root", key=key_string("root"), style=layout_style(.Row, width=120, height=40))
	expected_color := style_color(&ui, .Accent)
	id := icon(&ui, .Folder_Open, key=key_string("folder"), size=20, color_role=.Accent)
	close_id, _ := icon_button(&ui, "Dismiss example", .Close, key=key_string("dismiss"))
	container_end(&ui)
	end_frame(&ui)
	node, found := rt.nodes[id]
	if !found { testing.expect(t, false, "the icon should be retained in the layout tree"); return }
	icon_seen := false
	for command in node.paint {
		if retained, ok := command.payload.(Icon_Paint); ok && retained.id == .Folder_Open &&
			retained.color == expected_color {
			icon_seen = true
		}
	}
	testing.expect(t, icon_seen && node.text == "" && node.label == "",
		"the icon should paint theme-tinted vector geometry without depending on a text glyph")
	close_node, close_found := rt.nodes[close_id]
	close_icon_seen, close_text_seen := false, false
	for command in close_node.paint {
		if painted, ok := command.payload.(Icon_Paint); ok && painted.id == .Close { close_icon_seen = true }
		if paint_command_is_text(command) { close_text_seen = true }
	}
	close_semantic, close_semantic_found := semantic_node_lookup(&rt, semantic_visual_id(close_id))
	testing.expect(t, close_found && close_icon_seen && !close_text_seen && close_semantic_found &&
		close_semantic.role == .Button && close_semantic.label == "Dismiss example",
		"an icon-only control should retain its vector visual while exposing a proper accessible button name")
}
