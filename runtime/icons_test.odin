package alicorn

import "core:testing"

@(test)
test_builtin_icon_masks_cover_all_ids_and_physical_sizes :: proc(t: ^testing.T) {
    testing.expect(t, icon_atlas_validate(), "embedded icon masks and manifest must be valid")
    for raw_id in int(Icon_ID.Check)..<int(Icon_ID.Count) {
        for size in ICON_ATLAS_MIN_SIZE..=ICON_ATLAS_MAX_SIZE {
            entry, valid := icon_atlas_lookup(Icon_ID(raw_id), size)
            testing.expect(t, valid && entry.size == size, "every built-in icon has a distinct rasterization at every supported physical size")
            page := ICON_ATLAS_PAGES[entry.page]
            coverage, partial := false, false
            for y in entry.y..<entry.y+entry.size {
                for x in entry.x..<entry.x+entry.size {
                    pixel := page.pixels[y*page.width+x]
                    if pixel > 0 { coverage = true }
                    if pixel > 0 && pixel < 255 { partial = true }
                }
            }
            testing.expect(t, coverage && partial, "each mask must contain artwork and antialiased edge coverage")
            gutters_clear := true
            for y in entry.y-ICON_ATLAS_GUTTER..<entry.y+entry.size+ICON_ATLAS_GUTTER {
                for x in entry.x-ICON_ATLAS_GUTTER..<entry.x+entry.size+ICON_ATLAS_GUTTER {
                    if x >= entry.x && x < entry.x+entry.size && y >= entry.y && y < entry.y+entry.size { continue }
                    if page.pixels[y*page.width+x] != 0 { gutters_clear = false }
                }
            }
            testing.expect(t, gutters_clear, "transparent gutters must isolate icons during atlas filtering")
        }
    }
    _, invalid := icon_atlas_lookup(.None, 16)
    small, _ := icon_atlas_lookup(.Search, 4)
    large, _ := icon_atlas_lookup(.Search, 128)
    testing.expect(t, !invalid && small.size == 8 && large.size == 64, "invalid IDs must be rejected and unsupported sizes must choose the nearest endpoint")
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
		"the icon should retain its theme tint and mask identity without depending on a text glyph")
	close_node, close_found := rt.nodes[close_id]
	close_icon_seen, close_text_seen := false, false
	for command in close_node.paint {
		if painted, ok := command.payload.(Icon_Paint); ok && painted.id == .Close { close_icon_seen = true }
		if paint_command_is_text(command) { close_text_seen = true }
	}
	close_semantic, close_semantic_found := semantic_node_lookup(&rt, semantic_visual_id(close_id))
	testing.expect(t, close_found && close_icon_seen && !close_text_seen && close_semantic_found &&
		close_semantic.role == .Button && close_semantic.label == "Dismiss example",
		"an icon-only control should retain its mask visual while exposing a proper accessible button name")
}

icons_test_describe_accent :: proc(rt: ^Runtime, tint: Color) -> Node_ID {
	invalidate_root(rt, "icon tint changed")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin_simple(&ui, .Root, key=key_string("tint-root"), style=layout_style(.Row, width=100, height=40))
	scope := style_environment_push(&ui, Style_Environment{accent=style_accent(tint)})
	id := icon(&ui, .Search, key=key_string("search"), size=20, color_role=.Accent)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	return id
}

@(test)
test_icon_tint_change_preserves_measurement_layout_and_mask_identity :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,100,40})
	defer destroy_runtime(&rt)
	id := icons_test_describe_accent(&rt, Color{0.2,0.4,0.8,1})
	if id == 0 { testing.expect(t, false, "icon should be retained"); return }
	bounds := rt.nodes[id].bounds
	old_color := rt.nodes[id].color
	measures, layouts := rt.stats.measure_requests, rt.stats.layout_nodes_visited
	next := icons_test_describe_accent(&rt, Color{0.8,0.4,0.2,1})
	testing.expect(t, next == id && rt.nodes[id].bounds == bounds && rt.nodes[id].icon_id == .Search && rt.nodes[id].color != old_color,
		"theme tint should update retained paint without changing the icon or its geometry")
	testing.expect(t, rt.stats.measure_requests == measures && rt.stats.layout_nodes_visited == layouts,
		"an icon tint change should perform no measurement or layout work")
}
