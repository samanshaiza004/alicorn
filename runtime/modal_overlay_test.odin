package alicorn

import "core:testing"

modal_overlay_test_button :: proc(rt: ^Runtime, label: string) -> Node_ID {
	for id in rt.order {
		node, ok := rt.nodes[id]
		if ok && node.kind == .Button && node.label == label { return id }
	}
	return 0
}

@(test)
test_modal_overlay_blocks_workspace_and_limits_focus :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "new runtime should request its first description"); return }

	container_begin_simple(&ui, .Root, label="overlay-test-root", key=key_string("root"), style=layout_style())
	button(&ui, "Underlying action", key=key_string("underlying"), style=layout_style(width=800, height=600))
	container_end(&ui)

	overlay_id := modal_overlay_begin(
		&ui,
		key_string("test-overlay"),
		style=layout_style(.Column, align=.Center, clip=true),
		backdrop_color=Color{0.02, 0.025, 0.04, 0.68},
	)
	container_begin_simple(
		&ui,
		.Container,
		label="overlay-test-panel",
		key=key_string("panel"),
		style=layout_style(width=320, height=180, padding=8, gap=4),
		color=Color{0.06, 0.08, 0.12, 1},
	)
	field_id := text_field(&ui, "", key=key_string("query"), style=layout_style(.Row, height=32))
	button(&ui, "Run command", key=key_string("overlay-command"), style=layout_style(.Row, height=32), state=Button_State{quiet=true})
	container_end(&ui)
	modal_overlay_end(&ui)
	end_frame(&ui)

	underlying_id := modal_overlay_test_button(&rt, "Underlying action")
	overlay_button_id := modal_overlay_test_button(&rt, "Run command")
	testing.expect(t, overlay_id != 0 && field_id != 0 && underlying_id != 0 && overlay_button_id != 0,
		"workspace and modal controls should both remain retained")
	if overlay_id == 0 || field_id == 0 || underlying_id == 0 || overlay_button_id == 0 { return }
	quiet_button, quiet_button_ok := rt.nodes[overlay_button_id]
	quiet_fill_found := false
	if quiet_button_ok {
		for command in quiet_button.paint {
			if command.color.r == 0.08 && command.color.g == 0.10 && command.color.b == 0.14 { quiet_fill_found = true; break }
		}
	}
	testing.expect(t, quiet_fill_found, "quiet buttons should use a neutral fill while remaining interactive")

	testing.expect(t, hit_test(&rt, 10, 590) == overlay_id,
		"an empty backdrop hit must stop at the modal layer instead of reaching the workspace")
	testing.expect(t, hit_test(&rt, -1, -1) == 0, "modal input blocking must not extend beyond its viewport")
	button_bounds := rt.nodes[overlay_button_id].bounds
	testing.expect(t, hit_test(&rt, button_bounds.x+button_bounds.w/2, button_bounds.y+button_bounds.h/2) == overlay_button_id,
		"interactive modal descendants must remain hit-testable")
	testing.expect(t, focus(&rt, field_id), "modal query field should accept focus")
	testing.expect(t, !focus(&rt, underlying_id), "modal state should reject programmatic focus of the covered workspace")
	testing.expect(t, focus_traverse(&rt, .Next) == overlay_button_id,
		"forward focus traversal should stay inside the modal subtree")
	testing.expect(t, focus_traverse(&rt, .Next) == field_id,
		"focus traversal should wrap within the modal subtree")
	testing.expect(t, process_scroll(&rt, Scroll_Event{x=10, y=590, delta_y=1}),
		"wheel input outside modal controls must be consumed instead of scrolling the workspace")

	ui, should_build = begin_frame(&rt)
	if !should_build { testing.expect(t, false, "closing the modal description should rebuild"); return }
	container_begin_simple(&ui, .Root, label="overlay-test-root", key=key_string("root"), style=layout_style())
	button(&ui, "Underlying action", key=key_string("underlying"), style=layout_style(width=800, height=600))
	container_end(&ui)
	end_frame(&ui)
	underlying_after := modal_overlay_test_button(&rt, "Underlying action")
	testing.expect(t, underlying_after != 0 && hit_test(&rt, 10, 590) == underlying_after,
		"removing the modal should reveal the still-retained workspace")
}
