package alicorn

import "core:testing"

// The retained contract is Scroll_Region(label="tab-bar") > Virtual_List >
// Tab > content row > optional Tab_Close, plus a semantic selected-indicator
// surface. Selection and close requests remain application-owned.

TAB_BAR_TEST_DRAG_TYPE :: Drag_Type(901)
TAB_BAR_TEST_NAMESPACE :: u64(901)

tab_bar_test_semantic :: proc(value: u64) -> Semantic_ID {
	return Semantic_ID{namespace=TAB_BAR_TEST_NAMESPACE, value=value}
}

tab_bar_test_items :: proc(selected_index: int = 0) -> [3]Tab_Bar_Item {
	return [3]Tab_Bar_Item{
		{key=key_string("document-a"), label="architecture.md", selected=selected_index == 0,
			closable=true, semantic_id=tab_bar_test_semantic(1)},
		{key=key_string("document-b"), label="scratchpad-editor.odin", selected=selected_index == 1,
			closable=true, dirty=true, semantic_id=tab_bar_test_semantic(2)},
		{key=key_string("document-c"), label="README.md", selected=selected_index == 2,
			closable=true, semantic_id=tab_bar_test_semantic(3)},
	}
}

tab_bar_test_options :: proc() -> Tab_Bar_Options {
	return Tab_Bar_Options{
		min_tab_width=72,
		max_tab_width=240,
		height=36,
		gap=4,
		close_policy=.Auto,
		drag_type=TAB_BAR_TEST_DRAG_TYPE,
	}
}

tab_bar_test_options_always_close :: proc() -> Tab_Bar_Options {
	return Tab_Bar_Options{
		min_tab_width=72,
		max_tab_width=240,
		height=36,
		gap=4,
		close_policy=.Always,
		drag_type=TAB_BAR_TEST_DRAG_TYPE,
	}
}

tab_bar_test_build :: proc(
	rt: ^Runtime,
	items: []Tab_Bar_Item,
	width: f32,
	options: Tab_Bar_Options,
) -> Tab_Bar_Result {
	ui, should_build := begin_frame(rt)
	if !should_build { return Tab_Bar_Result{item_index=-1} }
	container_begin_simple(
		&ui,
		.Root,
		label="tab-bar-test-root",
		key=key_string("tab-bar-test-root"),
		style=layout_style(.Row, width=width, height=48),
	)
	result := tab_bar(
		&ui,
		key_string("tab-bar-test"),
		items,
		options,
		layout_style(.Row, width=width, height=options.height, gap=options.gap, clip=true),
	)
	container_end(&ui)
	end_frame(&ui)
	return result
}

tab_bar_test_bar_node :: proc(rt: ^Runtime) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.kind == .Scroll_Region && node.label == "tab-bar" {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_child_count :: proc(rt: ^Runtime, parent: Node_ID, kind: Node_Kind) -> int {
	count := 0
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.parent == parent && node.kind == kind { count += 1 }
	}
	return count
}

tab_bar_test_item_node :: proc(rt: ^Runtime, semantic: Semantic_ID) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.kind == .Tab && node.semantic_id == semantic {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_close_node :: proc(rt: ^Runtime, tab: Node_ID) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.kind == .Tab_Close && tab_ancestor(rt, node) != nil && tab_ancestor(rt, node).id == tab {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_part :: proc(rt: ^Runtime, tab: Node_ID, label: string) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.label == label && tab_ancestor(rt, node) != nil && tab_ancestor(rt, node).id == tab {
			id = candidate
			count += 1
		}
	}
	return
}

@(test)
test_tab_bar_builds_retained_scroll_list_tab_and_close_hierarchy :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 720, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	options := tab_bar_test_options()

	result := tab_bar_test_build(&rt, items[:], 640, options)
	bar_id, bar_count := tab_bar_test_bar_node(&rt)
	testing.expect(t, bar_count == 1, "tab_bar should retain one Scroll_Region labelled tab-bar")
	testing.expect(t, result.action == .None && result.item_index == -1,
		"an idle tab bar should return no action and the sentinel item index")
	if bar_count != 1 { return }

	list_count := tab_bar_test_child_count(&rt, bar_id, .Virtual_List)
	testing.expect(t, list_count == 1, "the tab-bar scroll region should contain one virtual-list node")
	list_id: Node_ID
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.parent == bar_id && node.kind == .Virtual_List {
			list_id = candidate
			break
		}
	}
	if list_id == 0 { return }

	testing.expect(t, tab_bar_test_child_count(&rt, list_id, .Tab) == len(items),
		"the virtual list should retain one direct Tab node per item")
	for item in items {
		tab_id, matches := tab_bar_test_item_node(&rt, item.semantic_id)
		testing.expect(t, matches == 1, "each stable item semantic ID should identify exactly one retained Tab")
		if matches != 1 { continue }
		testing.expect(t, rt.nodes[tab_id].parent == list_id,
			"each tab item should be a child of the bar's Virtual_List")
		testing.expect(t, tab_bar_test_child_count(&rt, tab_id, .Container) == 2,
			"a tab should compose its content row and selected-indicator surface as retained layout children")
		close_id, close_count := tab_bar_test_close_node(&rt, tab_id)
		testing.expect(t, close_count == 1,
			"a closable tab should represent its close affordance as a Tab_Close child")
		if close_count == 1 {
			testing.expect(t, tab_ancestor(&rt, rt.nodes[close_id]) == rt.nodes[tab_id],
				"the close action should be structurally composed inside its Tab, not adjacent to it")
			close := rt.nodes[close_id]
			tab := rt.nodes[tab_id]
			testing.expect(t, abs(close.bounds.w-TAB_CLOSE_CONTROL_SIZE) < 0.01 &&
				abs(close.bounds.x+close.bounds.w-(tab.bounds.x+tab.bounds.w)) < 0.01,
				"Tab_Close should be a compact trailing control inside its tab's reserved action slot")
		}
		if item.selected {
			indicator_id, indicator_count := tab_bar_test_part(&rt, tab_id, "tab-selected-indicator")
			indicator_ok := false
			if indicator_count == 1 {
				indicator := rt.nodes[indicator_id]
				tab := rt.nodes[tab_id]
				if len(indicator.paint) == 1 {
					_, is_surface := indicator.paint[0].payload.(Surface_Paint)
					indicator_ok = is_surface && indicator.paint[0].bounds == indicator.bounds &&
						indicator.bounds.w == tab.bounds.w && indicator.bounds.h == 2 &&
						indicator.paint[0].clip == indicator.clip
				}
			}
			testing.expect(t, indicator_count == 1 && indicator_ok,
				"the selected underline should be a theme-resolved semantic surface part using retained layout bounds and clip")
		}
	}
	bar := rt.nodes[bar_id]
	testing.expect(t, bar.bounds.w == 640 && bar.scroll_viewport_width == 640,
		"the scroll region should own the requested tab-bar viewport")
}

@(test)
test_tab_bar_shrinks_tabs_then_overflows_at_minimum_width :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 720, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	options := tab_bar_test_options_always_close()

	_ = tab_bar_test_build(&rt, items[:], 640, options)
	wide_widths: [3]f32
	for index in 0..<len(items) {
		id, count := tab_bar_test_item_node(&rt, items[index].semantic_id)
		testing.expect(t, count == 1, "wide layout should retain each tab once")
		if count != 1 { continue }
		wide_widths[index] = rt.nodes[id].bounds.w
		testing.expect(t, wide_widths[index] > options.min_tab_width && wide_widths[index] <= options.max_tab_width,
			"wide tabs should use available space without exceeding their configured maximum")
		testing.expect(t, rt.nodes[id].bounds.h == options.height,
			"each tab should use the configured height")
	}

	// At 180 logical pixels, three minimum-width tabs plus their gaps cannot fit.
	_ = tab_bar_test_build(&rt, items[:], 180, options)
	bar_id, bar_count := tab_bar_test_bar_node(&rt)
	testing.expect(t, bar_count == 1, "narrow layout should preserve its scroll-region owner")
	if bar_count != 1 { return }
	bar := rt.nodes[bar_id]
	content_width := bar.scroll_content_width
	viewport_width := bar.scroll_viewport_width
	max_scroll_x := scroll_region_state(&rt, bar_id).max_scroll_x
	testing.expect(t, content_width > viewport_width && max_scroll_x > 0,
		"the bar should enter horizontal overflow after tabs reach their minimum width")
	shrunk_tab_count := 0
	for index in 0..<len(items) {
		id, count := tab_bar_test_item_node(&rt, items[index].semantic_id)
		testing.expect(t, count == 1, "overflow should retain every logical tab")
		if count != 1 { continue }
		width := rt.nodes[id].bounds.w
		if width < wide_widths[index] { shrunk_tab_count += 1 }
		testing.expect(t, width >= options.min_tab_width && width <= options.max_tab_width,
			"tab widths should stop shrinking at the configured minimum")
	}
	testing.expect(t, shrunk_tab_count > 0,
		"reducing available width should shrink tabs before horizontal overflow")
}

@(test)
test_tab_bar_reveals_initially_selected_and_newly_selected_tab :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 120})
	defer destroy_runtime(&rt)
	options := tab_bar_test_options_always_close()
	items := tab_bar_test_items(selected_index=0)
	_ = tab_bar_test_build(&rt, items[:], 180, options)
	bar_id, bar_count := tab_bar_test_bar_node(&rt)
	testing.expect(t, bar_count == 1, "the narrow tab bar should be retained")
	if bar_count != 1 { return }
	initial_offset := scroll_region_state(&rt, bar_id).offset_x
	initial_selected_id, initial_selected_count := tab_bar_test_item_node(&rt, items[0].semantic_id)
	testing.expect(t, initial_selected_count == 1, "the initial selected tab should be retained")
	if initial_selected_count != 1 { return }
	bar := rt.nodes[bar_id]
	initial_selected := rt.nodes[initial_selected_id]
	testing.expect(t, initial_selected.bounds.x >= bar.bounds.x &&
		initial_selected.bounds.x+initial_selected.bounds.w <= bar.bounds.x+bar.bounds.w,
		"the initially selected first tab should be fully visible")

	items = tab_bar_test_items(selected_index=2)
	invalidate_root(&rt, "tab-bar selected item changed")
	_ = tab_bar_test_build(&rt, items[:], 180, options)
	bar_id, bar_count = tab_bar_test_bar_node(&rt)
	selected_id, selected_count := tab_bar_test_item_node(&rt, items[2].semantic_id)
	testing.expect(t, bar_count == 1 && selected_count == 1,
		"changing selection should preserve the bar and reveal its new selected tab")
	if bar_count != 1 || selected_count != 1 { return }
	bar = rt.nodes[bar_id]
	selected := rt.nodes[selected_id]
	new_offset := scroll_region_state(&rt, bar_id).offset_x
	testing.expect(t, new_offset > initial_offset,
		"selection change to an offscreen tab should advance the retained horizontal offset")
	testing.expect(t, selected.bounds.x >= bar.bounds.x &&
		selected.bounds.x+selected.bounds.w <= bar.bounds.x+bar.bounds.w,
		"the newly selected last tab should be fully visible after automatic reveal")
}

@(test)
test_tab_bar_click_select_and_tab_close_are_distinct_requests :: proc(t: ^testing.T) {
	options := tab_bar_test_options_always_close()
	items := tab_bar_test_items()
	rt := new_runtime(Rect{0, 0, 480, 120})
	defer destroy_runtime(&rt)
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	tab_id, tab_count := tab_bar_test_item_node(&rt, items[1].semantic_id)
	testing.expect(t, tab_count == 1, "the unselected target tab should be retained")
	if tab_count != 1 { return }
	tab_bounds := rt.nodes[tab_id].bounds
	select_x := tab_bounds.x+tab_bounds.w*0.45
	select_y := tab_bounds.y+tab_bounds.h*0.5
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=select_x, y=select_y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=select_x, y=select_y, button=POINTER_BUTTON_PRIMARY})
	select_request := tab_bar_test_build(&rt, items[:], 440, options)
	testing.expect(t, select_request.action == .Select && select_request.item_index == 1,
		"clicking the tab body should request selection of that item")

	// Use the retained close child itself as the hit target: its width is the
	// trailing 28 logical pixels of the parent Tab.
	close_rt := new_runtime(Rect{0, 0, 480, 120})
	defer destroy_runtime(&close_rt)
	_ = tab_bar_test_build(&close_rt, items[:], 440, options)
	tab_id, tab_count = tab_bar_test_item_node(&close_rt, items[1].semantic_id)
	testing.expect(t, tab_count == 1, "the closable target tab should have one retained owner")
	if tab_count != 1 { return }
	close_id, close_count := tab_bar_test_close_node(&close_rt, tab_id)
	testing.expect(t, close_count == 1, "the tab should contain its Tab_Close hit target")
	if close_count != 1 { return }
	close_bounds := close_rt.nodes[close_id].bounds
	close_x := close_bounds.x+close_bounds.w*0.5
	close_y := close_bounds.y+close_bounds.h*0.5
	_ = process_pointer(&close_rt, Pointer_Event{kind=.Down, x=close_x, y=close_y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&close_rt, Pointer_Event{kind=.Up, x=close_x, y=close_y, button=POINTER_BUTTON_PRIMARY})
	close_request := tab_bar_test_build(&close_rt, items[:], 440, options)
	testing.expect(t, close_request.action == .Close && close_request.item_index == 1,
		"clicking Tab_Close should request close of its item instead of selecting the tab")
}

@(test)
test_tab_bar_navigation_wraps_and_selects_one_based_indices :: proc(t: ^testing.T) {
	count := 8
	index, found := tab_bar_navigate(count, 7, .Next)
	testing.expect(t, found && index == 0, "Next should wrap from the final item to the first")
	index, found = tab_bar_navigate(count, 0, .Previous)
	testing.expect(t, found && index == 7, "Previous should wrap from the first item to the final")
	index, found = tab_bar_navigate(count, 4, .Index_1)
	testing.expect(t, found && index == 0, "Index_1 should select zero-based item index 0")
	index, found = tab_bar_navigate(count, 0, .Index_8)
	testing.expect(t, found && index == 7, "Index_8 should select zero-based item index 7")
	index, found = tab_bar_navigate(count, 1, .Last)
	testing.expect(t, found && index == 7, "Last should select the final item")
	index, found = tab_bar_navigate(0, -1, .Next)
	testing.expect(t, !found && index == -1, "navigation on an empty bar should report no destination")
	index, found = tab_bar_navigate(3, 0, .Index_8)
	testing.expect(t, !found && index == -1, "an index beyond the item count should report no destination")
}

@(test)
test_tab_bar_requires_explicit_item_keys :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 480, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	items[1].key = UI_Unkeyed{}
	result := tab_bar_test_build(&rt, items[:], 440, tab_bar_test_options())
	_, bar_count := tab_bar_test_bar_node(&rt)
	testing.expect(t, rt.hard_error,
		"a tab without a stable explicit key should produce a clear runtime diagnostic")
	testing.expect(t, bar_count == 0 && result.action == .None && result.item_index == -1,
		"invalid item identity should reject the tab-bar description without retaining a partial list")
}

@(test)
test_tab_bar_close_policy_keeps_dirty_marker_and_reveals_on_hover :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 720, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	options := tab_bar_test_options()
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	// Complete any geometry-driven follow-up frame from initial layout before
	// checking retained-only hover presentation.
	_ = tab_bar_test_build(&rt, items[:], 440, options)

	selected_tab, selected_count := tab_bar_test_item_node(&rt, items[0].semantic_id)
	selected_close, selected_close_count := tab_bar_test_close_node(&rt, selected_tab)
	dirty_tab, dirty_count := tab_bar_test_item_node(&rt, items[1].semantic_id)
	dirty_close, dirty_close_count := tab_bar_test_close_node(&rt, dirty_tab)
	clean_tab, clean_count := tab_bar_test_item_node(&rt, items[2].semantic_id)
	clean_close, clean_close_count := tab_bar_test_close_node(&rt, clean_tab)
	testing.expect(t, selected_count == 1 && selected_close_count == 1,
		"the selected tab should retain one close affordance")
	testing.expect(t, dirty_count == 1 && dirty_close_count == 1,
		"the dirty tab should retain one close affordance")
	testing.expect(t, clean_count == 1 && clean_close_count == 1,
		"the clean tab should retain one close affordance")
	if selected_count != 1 || selected_close_count != 1 || dirty_count != 1 || dirty_close_count != 1 || clean_count != 1 || clean_close_count != 1 {
		return
	}

	selected_paint := rt.nodes[selected_close].paint
	dirty_paint := rt.nodes[dirty_close].paint
	clean_paint := rt.nodes[clean_close].paint
	dirty_marker_ok := false
	if len(dirty_paint) > 0 { _, dirty_marker_ok = dirty_paint[0].payload.(Surface_Paint) }
	testing.expect(t, len(selected_paint) == 0,
		"Auto should hide the close glyph on a compact selected tab until it is hovered")
	testing.expect(t, dirty_marker_ok && len(dirty_paint) == 1,
		"a hidden close glyph should leave the dirty tab's marker visible")
	testing.expect(t, len(clean_paint) == 0,
		"an unselected clean compact tab should not paint its hidden close action")

	invalidate_root(&rt, "tab-bar responsive width increased")
	_ = tab_bar_test_build(&rt, items[:], 640, options)
	selected_paint = rt.nodes[selected_close].paint
	wide_close_visible := false
	if len(selected_paint) > 0 { _, wide_close_visible = selected_paint[0].payload.(Text_Paint) }
	testing.expect(t, wide_close_visible,
		"Auto should keep the close glyph visible when a tab has comfortable width")

	invalidate_root(&rt, "tab-bar responsive width decreased")
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	_ = tab_bar_test_build(&rt, items[:], 440, options)

	clean_bounds := rt.nodes[clean_tab].bounds
	hover_target := process_pointer(&rt, Pointer_Event{
		kind=.Move,
		x=clean_bounds.x+clean_bounds.w*0.35,
		y=clean_bounds.y+clean_bounds.h*0.5,
	})
	testing.expect(t, hover_target == clean_tab,
		"the tab body should remain the pointer target outside the embedded close slot")
	testing.expect(t, rt.nodes[clean_tab].hovered,
		"pointer movement over the tab body should update its retained hover state")
	ui, ready := begin_presentation_frame(&rt)
	testing.expect(t, ready, "hovering a tab should request retained presentation work")
	if ready { end_presentation_frame(&ui) }
	close_paint := rt.nodes[clean_close].paint
	close_glyph_visible := false
	if len(close_paint) > 0 { _, close_glyph_visible = close_paint[0].payload.(Text_Paint) }
	testing.expect(t, rt.nodes[clean_tab].hovered && close_glyph_visible,
		"hovering any part of a compact tab should reveal its close glyph without changing geometry")
	testing.expect(t, same_rect(rt.nodes[clean_tab].bounds, clean_bounds),
		"revealing the close glyph should not shift or resize its tab")
}

@(test)
test_tab_bar_dirty_state_is_visible_without_a_close_action :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	items := [1]Tab_Bar_Item{{key=key_string("untitled"), label="Untitled", dirty=true}}
	options := tab_bar_test_options_always_close()
	_ = tab_bar_test_build(&rt, items[:], 280, options)

	tab_id: Node_ID = 0
	for candidate in rt.order {
		if node, found := rt.nodes[candidate]; found && node.active && node.kind == .Tab {
			tab_id = candidate
			break
		}
	}
	testing.expect(t, tab_id != 0, "a dirty non-closable tab should still be retained")
	if tab_id == 0 { return }
	_, close_count := tab_bar_test_close_node(&rt, tab_id)
	testing.expect(t, close_count == 0,
		"a non-closable tab should not receive an interactive close child")
	marker_id, marker_count := tab_bar_test_part(&rt, tab_id, "tab-dirty-indicator")
	marker_found := false
	for command in rt.nodes[marker_id].paint {
		if _, is_surface := command.payload.(Surface_Paint); is_surface { marker_found = true }
	}
	testing.expect(t, marker_count == 1 && marker_found,
		"dirty state should be composed as a semantic surface part in the tab's trailing slot")
}
