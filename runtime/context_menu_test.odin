package alicorn

import "core:testing"

context_menu_test_find :: proc(rt: ^Runtime, label: string, kind: Node_Kind) -> Node_ID {
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.active && node.kind == kind && node.label == label { return id }
	}
	return 0
}

context_menu_test_build :: proc(rt: ^Runtime) -> (action: Action_ID, opener: Node_ID) {
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(&ui, .Root, label="context-menu-test-root", key=key_string("root"), style=layout_style())
	opener, _ = button_ex(&ui, "Workspace row", key="workspace-row", style=layout_style(width=180, height=32))
	container_end(&ui)
	if context_menu_is_open(rt) && context_menu_begin(&ui, key_string("context-menu-test"), width=180, item_height=28) {
		context_menu_item(&ui, Action_ID(11), "Rename")
		context_menu_separator(&ui)
		context_menu_item(&ui, Action_ID(12), "Unavailable", enabled=false)
		context_menu_item(&ui, Action_ID(13), "Move to Trash")
		action = context_menu_end(&ui)
	}
	end_frame(&ui)
	return
}

@(test)
test_context_menu_placement_flips_and_clamps_to_viewport :: proc(t: ^testing.T) {
	viewport := Rect{10, 20, 100, 80}
	point_anchor := Rect{103, 95, 0, 0}
	placed := context_menu_placement(viewport, point_anchor, 50, 40, margin=5)
	testing.expect(t, placed.x == 55 && placed.y == 55 && placed.w == 50 && placed.h == 40,
		"a pointer-anchored menu should flip left and above when the preferred sides do not fit")
	for_anchor := Rect{75, 80, 25, 15}
	placed = context_menu_placement(viewport, for_anchor, 90, 90, margin=5)
	testing.expect(t, placed.x == 15 && placed.y == 25 && placed.w == 90 && placed.h == 70,
		"oversized menus should be clamped inside the safe viewport")
}

@(test)
test_context_menu_navigation_skips_disabled_items_and_dispatches_action :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 300})
	defer destroy_runtime(&rt)
	_, opener := context_menu_test_build(&rt)
	testing.expect(t, opener != 0, "test workspace row should be retained")
	if opener == 0 { return }
	testing.expect(t, context_menu_open(&rt, Rect{380, 280, 0, 0}, opener), "application should be able to open a menu at a pointer point")
	action, _ := context_menu_test_build(&rt)
	testing.expect(t, action == 0 && context_menu_is_open(&rt), "a menu with no activation should remain open")
	first := context_menu_test_find(&rt, "Rename", .Button)
	disabled := context_menu_test_find(&rt, "Unavailable", .Button)
	last := context_menu_test_find(&rt, "Move to Trash", .Button)
	separator := context_menu_test_find(&rt, "context-menu-separator-slot", .Container)
	separator_line := context_menu_test_find(&rt, "context-menu-separator-line", .Container)
	panel := rt.nodes[rt.context_menu.panel]
	testing.expect(t, first != 0 && disabled != 0 && last != 0, "all menu commands should be retained")
	testing.expect(t, separator != 0 && separator_line != 0, "the separator should use a transparent spacing slot and a separate line")
	if first == 0 || disabled == 0 || last == 0 || separator == 0 || separator_line == 0 { return }
	separator_slot_node := rt.nodes[separator]
	separator_line_node := rt.nodes[separator_line]
	testing.expect(t, !separator_slot_node.paint_background, "separator spacing should not paint a filled band")
	testing.expect(t, separator_slot_node.bounds.h == CONTEXT_MENU_DEFAULT_SEPARATOR_HEIGHT && separator_line_node.bounds.h == 1,
		"separator should preserve breathing room while drawing only a one-pixel line")
	testing.expect(t, separator_line_node.bounds.x > separator_slot_node.bounds.x && separator_line_node.bounds.x+separator_line_node.bounds.w < separator_slot_node.bounds.x+separator_slot_node.bounds.w,
		"separator line should be inset from the menu edges")
	button_paints := 0
	for command in rt.nodes[first].paint {
		if color, ok := paint_surface_color(command); ok && same_rect(command.bounds, rt.nodes[first].bounds) && color.a > 0 { button_paints += 1 }
	}
	testing.expect(t, button_paints == 1, "keyboard focus on a menu item should use a row highlight without the ordinary button outline")
	panel_outline_segments := 0
	for command in panel.paint {
		if paint_command_is_surface(command) && !same_rect(command.bounds, panel.bounds) { panel_outline_segments += 1 }
	}
	testing.expect(t, panel_outline_segments == 4, "the popup should have a subtle four-sided border")
	testing.expect(t, rt.focused == first, "opening should focus the first enabled menu item")
	testing.expect(t, panel.clip.x == rt.viewport.x && panel.clip.y == rt.viewport.y && panel.clip.w == rt.viewport.w && panel.clip.h == rt.viewport.h,
		"the top-level popup should escape clipping from the invoking workspace pane")
	testing.expect(t, panel.bounds.x+panel.bounds.w <= rt.viewport.x+rt.viewport.w && panel.bounds.y+panel.bounds.h <= rt.viewport.y+rt.viewport.h,
		"the popup panel should remain within the viewport")
	testing.expect(t, context_menu_handle_key(&rt, .Down), "menu navigation should consume Down")
	testing.expect(t, rt.focused == last, "Down should skip both the separator and disabled item")
	testing.expect(t, !rt.invalidated, "moving menu focus should repaint retained state without rebuilding the application")
	testing.expect(t, context_menu_handle_key(&rt, .Activate), "menu activation should consume Enter")
	action, _ = context_menu_test_build(&rt)
	testing.expect(t, action == Action_ID(13), "activation should return the selected semantic Action_ID exactly once")
	testing.expect(t, !context_menu_is_open(&rt), "activating a command should close the menu")
	testing.expect(t, rt.focused == opener, "closing should restore focus to the invoking control")
	_, _ = context_menu_test_build(&rt)
	testing.expect(t, !rt.context_menu.dismissed, "the old popup should stop blocking input after it is retired")
}

@(test)
test_context_menu_outside_click_is_consumed_and_restores_focus :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 300})
	defer destroy_runtime(&rt)
	_, opener := context_menu_test_build(&rt)
	if opener == 0 { testing.expect(t, false, "test workspace row should be retained"); return }
	_ = context_menu_open(&rt, Rect{120, 80, 0, 0}, opener)
	_, _ = context_menu_test_build(&rt)
	root := rt.context_menu.overlay
	target := process_pointer(&rt, Pointer_Event{kind=.Down, x=10, y=10, button=POINTER_BUTTON_PRIMARY})
	testing.expect(t, target == root, "an outside press should hit the popup blocker rather than a workspace control")
	testing.expect(t, context_menu_pointer_consumed(&rt), "outside dismissal must be reported as consumed to the native host")
	testing.expect(t, !context_menu_is_open(&rt), "outside press should dismiss the menu")
	testing.expect(t, rt.focused == opener, "outside dismissal should restore the invoking focus owner")
	_, _ = context_menu_test_build(&rt)
	testing.expect(t, hit_test(&rt, 10, 10) == opener, "after dismissal the invoking workspace control should be revealed")
}

@(test)
test_context_menu_pointer_activation_returns_one_action :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 300})
	defer destroy_runtime(&rt)
	_, opener := context_menu_test_build(&rt)
	if opener == 0 { testing.expect(t, false, "test workspace row should be retained"); return }
	_ = context_menu_open(&rt, Rect{120, 80, 0, 0}, opener)
	_, _ = context_menu_test_build(&rt)
	first := context_menu_test_find(&rt, "Rename", .Button)
	if first == 0 { testing.expect(t, false, "first menu action should be retained"); return }
	item := rt.nodes[first]
	x := item.bounds.x + item.bounds.w/2
	y := item.bounds.y + item.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	action, _ := context_menu_test_build(&rt)
	testing.expect(t, action == Action_ID(11), "clicking an item should return its semantic action")
	testing.expect(t, !context_menu_is_open(&rt), "pointer activation should close the menu")
	testing.expect(t, rt.focused == opener, "pointer activation should restore the invoking focus owner")
	action, _ = context_menu_test_build(&rt)
	testing.expect(t, action == 0, "a menu action must be delivered only once")
}

@(test)
test_secondary_click_does_not_activate_or_focus_workspace_button :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 300})
	defer destroy_runtime(&rt)
	_, opener := context_menu_test_build(&rt)
	if opener == 0 { testing.expect(t, false, "test workspace row should be retained"); return }
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=10, y=10, button=POINTER_BUTTON_SECONDARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=10, y=10, button=POINTER_BUTTON_SECONDARY})
	testing.expect(t, rt.activation_node == 0, "secondary-click should not activate an ordinary workspace button")
	testing.expect(t, rt.focused == 0, "secondary-click should leave ordinary keyboard focus unchanged")
}
