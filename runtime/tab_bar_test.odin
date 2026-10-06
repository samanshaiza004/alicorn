package alicorn

import "core:testing"

// The retained contract is Scroll_Region(label="tab-bar") > Virtual_List >
// Button owner > tagged visual parts. Selection and close requests remain
// application-owned; close remains an independently interactive child.

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
		if found && node.active && node.kind == .Button && node.button_variant == .Tab && node.semantic_id == semantic {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_close_node :: proc(rt: ^Runtime, tab: Node_ID) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		part, tagged := rt.visual_parts[candidate]
		if found && tagged && part.defined && part.owner == tab && part.identity == visual_part_core(.Overlay) && node.active && node.kind == .Button {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_part :: proc(rt: ^Runtime, tab: Node_ID, label: string) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		part, tagged := rt.visual_parts[candidate]
		if found && tagged && part.defined && part.owner == tab && node.active && node.label == label {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_visual_part :: proc(rt: ^Runtime, owner: Node_ID, role: Visual_Part_Core_ID) -> (id: Node_ID, count: int) {
	if rt == nil { return }
	for candidate in rt.order {
		if node, found := rt.nodes[candidate]; found && node.active && visual_part_has_core_role(rt, candidate, owner, role) {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_button :: proc(rt: ^Runtime, label: string) -> (id: Node_ID, count: int) {
	for candidate in rt.order {
		node, found := rt.nodes[candidate]
		if found && node.active && node.kind == .Button && node.label == label {
			id = candidate
			count += 1
		}
	}
	return
}

tab_bar_test_click :: proc(rt: ^Runtime, id: Node_ID) {
	if rt == nil || id == 0 { return }
	node, found := rt.nodes[id]
	if !found { return }
	x, y := node.bounds.x+node.bounds.w*0.5, node.bounds.y+node.bounds.h*0.5
	_ = process_pointer(rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
}

tab_bar_test_focus_outline_count :: proc(node: ^Node) -> int {
	if node == nil { return 0 }
	count := 0
	for command in node.paint {
		if _, ok := command.payload.(Surface_Paint); !ok { continue }
		if abs(command.bounds.w-1.5) < 0.01 || abs(command.bounds.h-1.5) < 0.01 { count += 1 }
	}
	return count
}

tab_bar_test_text_bounds :: proc(rt: ^Runtime, owner_id: Node_ID) -> (bounds: Rect, found: bool) {
	if rt == nil { return }
	stack := make([dynamic]Node_ID, 0, allocator=context.temp_allocator)
	append(&stack, owner_id)
	for len(stack) > 0 {
		id := pop(&stack)
		node, exists := rt.nodes[id]
		if !exists { continue }
		part, tagged := rt.visual_parts[id]
		is_label := id == owner_id || (tagged && part.defined && part.owner == owner_id && part.identity == visual_part_core(.Label))
		if is_label {
			for command in node.paint {
				if _, ok := command.payload.(Text_Paint); ok { return command.bounds, true }
			}
		}
		for child_id in node.children { append(&stack, child_id) }
	}
	return
}

tab_bar_test_label_color :: proc(rt: ^Runtime, owner_id: Node_ID) -> (color: Color, found: bool) {
	if rt == nil { return }
	stack := make([dynamic]Node_ID, 0, allocator=context.temp_allocator)
	append(&stack, owner_id)
	for len(stack) > 0 {
		id := pop(&stack)
		node, exists := rt.nodes[id]
		if !exists { continue }
		if visual_part_has_core_role(rt, id, owner_id, .Label) {
			for command in node.paint {
				if text, ok := command.payload.(Text_Paint); ok { return text.color, true }
			}
		}
		for child_id in node.children { append(&stack, child_id) }
	}
	return
}

tab_bar_test_display_has_text :: proc(rt: ^Runtime, owner: Node_ID) -> bool {
	if rt == nil { return false }
	for command in rt.display {
		if command.owner == owner { if _, ok := command.payload.(Text_Paint); ok { return true } }
	}
	return false
}

tab_bar_test_display_has_surface :: proc(rt: ^Runtime, owner: Node_ID) -> bool {
	if rt == nil { return false }
	for command in rt.display {
		if command.owner == owner {
			if surface, ok := command.payload.(Surface_Paint); ok && surface.fill.a > 0 { return true }
		}
	}
	return false
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

	testing.expect(t, tab_bar_test_child_count(&rt, list_id, .Button) == len(items),
		"the virtual list should retain one direct Button owner per item")
	for item in items {
		tab_id, matches := tab_bar_test_item_node(&rt, item.semantic_id)
		testing.expect(t, matches == 1, "each stable item semantic ID should identify exactly one retained tab Button")
		if matches != 1 { continue }
		testing.expect(t, rt.nodes[tab_id].parent == list_id,
			"each tab item should be a child of the bar's Virtual_List")
		testing.expect(t, tab_bar_test_child_count(&rt, tab_id, .Container) == 2,
			"a tab should compose its content row and selected-indicator surface as retained layout children")
		close_id, close_count := tab_bar_test_close_node(&rt, tab_id)
		testing.expect(t, close_count == 1,
			"a closable tab should represent its close affordance as an independent Button visual part")
		if close_count == 1 {
			part := rt.visual_parts[close_id]
			testing.expect(t, part.owner == tab_id && part.identity == visual_part_core(.Overlay),
				"the close action should be a typed visual part owned by its tab Button")
			close := rt.nodes[close_id]
			tab := rt.nodes[tab_id]
			expected_close_width := TAB_CLOSE_CONTROL_SIZE
			if item.dirty && item.closable && options.close_policy != .Always { expected_close_width = TAB_CLOSE_SLOT_WIDTH }
			testing.expect(t, abs(close.bounds.w-expected_close_width) < 0.01 &&
				close.bounds.x >= tab.bounds.x && close.bounds.x+close.bounds.w <= tab.bounds.x+tab.bounds.w,
				"the close action should be a compact retained control inside its tab's trailing slot")
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
	left_id, left_count := tab_bar_test_button(&rt, "Scroll tabs left")
	right_id, right_count := tab_bar_test_button(&rt, "Scroll tabs right")
	testing.expect(t, left_count == 1 && right_count == 1,
		"overflow should expose accessible previous/next controls so hidden tabs are discoverable")
	if left_count != 1 || right_count != 1 { return }
	testing.expect(t, rt.nodes[left_id].disabled && !rt.nodes[right_id].disabled,
		"the left control should be disabled at the leading edge while the right control remains actionable")
	tab_bar_test_click(&rt, right_id)
	_ = tab_bar_test_build(&rt, items[:], 180, options)
	right_offset := scroll_region_state(&rt, bar_id).offset_x
	testing.expect(t, right_offset > 0,
		"activating the right overflow control should reveal later tabs without taking ownership of selection")
	left_id, left_count = tab_bar_test_button(&rt, "Scroll tabs left")
	testing.expect(t, left_count == 1 && !rt.nodes[left_id].disabled,
		"the left overflow control should become actionable after scrolling right")
	if left_count == 1 {
		tab_bar_test_click(&rt, left_id)
		_ = tab_bar_test_build(&rt, items[:], 180, options)
		testing.expect(t, scroll_region_state(&rt, bar_id).offset_x < right_offset,
			"activating the left overflow control should return toward earlier tabs")
	}
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
	testing.expect(t, close_count == 1, "the tab should contain an independent close Button hit target")
	if close_count != 1 { return }
	close_bounds := close_rt.nodes[close_id].bounds
	close_x := close_bounds.x+close_bounds.w*0.5
	close_y := close_bounds.y+close_bounds.h*0.5
	_ = process_pointer(&close_rt, Pointer_Event{kind=.Down, x=close_x, y=close_y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&close_rt, Pointer_Event{kind=.Up, x=close_x, y=close_y, button=POINTER_BUTTON_PRIMARY})
	close_request := tab_bar_test_build(&close_rt, items[:], 440, options)
	testing.expect(t, close_request.action == .Close && close_request.item_index == 1,
			"clicking the close part should request close of its item instead of selecting the tab")
}

@(test)
test_tab_bar_selection_is_distinct_from_keyboard_focus_indicator :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 480, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	options := tab_bar_test_options_always_close()
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	selected_id, selected_count := tab_bar_test_item_node(&rt, items[0].semantic_id)
	other_id, other_count := tab_bar_test_item_node(&rt, items[1].semantic_id)
	testing.expect(t, selected_count == 1 && other_count == 1,
		"selected and inactive tabs should both be retained for focus-modality checks")
	if selected_count != 1 || other_count != 1 { return }
	selected_bounds := rt.nodes[selected_id].bounds
	x, y := selected_bounds.x+selected_bounds.w*0.4, selected_bounds.y+selected_bounds.h*0.5
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	testing.expect(t, rt.focused == selected_id && !rt.focus_visible && tab_bar_test_focus_outline_count(rt.nodes[selected_id]) == 0,
		"pointer selection should keep logical focus but avoid visually duplicating the selected treatment with a keyboard ring")

	keyboard_focus := focus_traverse(&rt, .Next)
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	testing.expect(t, keyboard_focus == other_id,
		"Tab traversal should move keyboard focus to the next document tab")
	testing.expect(t, rt.focus_visible,
		"keyboard traversal should enable the keyboard-focus visual modality")
	testing.expect(t, tab_bar_test_focus_outline_count(rt.nodes[other_id]) == 4,
		"keyboard traversal should paint the distinct four-edge focus outline on the focused tab")
	testing.expect(t, rt.nodes[selected_id].selected && !rt.nodes[other_id].selected,
		"keyboard focus movement must not mutate the application-owned selected tab")
}

@(test)
test_tab_bar_label_uses_owner_recipe_for_idle_hover_and_selected_states :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 480, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	options := tab_bar_test_options_always_close()
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	// The virtual list may request one follow-up layout pass after its initial
	// viewport is measured. Settle that before testing retained-only hover paint.
	_ = tab_bar_test_build(&rt, items[:], 440, options)
	selected_id, selected_count := tab_bar_test_item_node(&rt, items[0].semantic_id)
	idle_id, idle_count := tab_bar_test_item_node(&rt, items[1].semantic_id)
	testing.expect(t, selected_count == 1 && idle_count == 1,
		"the selected and idle tabs should both retain their semantic Button owners")
	if selected_count != 1 || idle_count != 1 { return }

	selected_color, selected_found := tab_bar_test_label_color(&rt, selected_id)
	idle_color, idle_found := tab_bar_test_label_color(&rt, idle_id)
	expected_selected := style_button_resolve_retained(&rt, rt.nodes[selected_id], Button_Visual_State{selected=true}).text
	expected_idle := style_button_resolve_retained(&rt, rt.nodes[idle_id], Button_Visual_State{}).text
	testing.expect(t, selected_found && selected_color == expected_selected,
		"a selected composed label should use the text color from its owner's selected recipe")
	testing.expect(t, idle_found && idle_color == expected_idle && idle_color != selected_color,
		"an idle composed label should use its owner's muted recipe color rather than ordinary Text color")

	idle_bounds := rt.nodes[idle_id].bounds
	_ = process_pointer(&rt, Pointer_Event{
		kind=.Move,
		x=idle_bounds.x+idle_bounds.w*0.35,
		y=idle_bounds.y+idle_bounds.h*0.5,
	})
	ui, ready := begin_presentation_frame(&rt)
	testing.expect(t, ready, "hovering a tab should queue a retained presentation frame")
	if ready { end_presentation_frame(&ui) }
	hovered_color, hovered_found := tab_bar_test_label_color(&rt, idle_id)
	expected_hovered := style_button_resolve_retained(&rt, rt.nodes[idle_id], Button_Visual_State{hovered=true}).text
	testing.expect(t, rt.nodes[idle_id].hovered,
		"pointer movement over the tab body should mark the tab owner hovered")
	testing.expect(t, hovered_found && hovered_color == expected_hovered,
		"a hovered composed label should use its owner's hovered recipe color")
	testing.expect(t, hovered_color != idle_color,
		"hovering should visibly transform the Tab label color from its muted idle color")
}

@(test)
test_tab_bar_drag_shows_a_clear_between_tab_insertion_marker :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 480, 120})
	defer destroy_runtime(&rt)
	items := tab_bar_test_items()
	_ = tab_bar_test_build(&rt, items[:], 440, tab_bar_test_options_always_close())
	source_id, source_count := tab_bar_test_item_node(&rt, items[0].semantic_id)
	target_id, target_count := tab_bar_test_item_node(&rt, items[1].semantic_id)
	testing.expect(t, source_count == 1 && target_count == 1,
		"drag reorder should begin and end on retained tab nodes")
	if source_count != 1 || target_count != 1 { return }
	source, target := rt.nodes[source_id], rt.nodes[target_id]
	sx, sy := source.bounds.x+source.bounds.w*0.5, source.bounds.y+source.bounds.h*0.5
	tx, ty := target.bounds.x+2, target.bounds.y+target.bounds.h*0.5
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=sx, y=sy, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=tx, y=ty})
	event, found := drag_event_take(&rt)
	testing.expect(t, found && event.kind == .Started && event.target == items[1].semantic_id && event.position == .Before,
		"dragging across tabs should report a semantic before-position request")
	_ = tab_bar_test_build(&rt, items[:], 440, tab_bar_test_options_always_close())
	target = rt.nodes[target_id]
	marker_found, halo_found := false, false
	for command in rt.nodes[target_id].paint {
		if _, ok := command.payload.(Surface_Paint); !ok { continue }
		if abs(command.bounds.w-3) < 0.01 { marker_found = true }
		if abs(command.bounds.w-7) < 0.01 { halo_found = true }
	}
	testing.expect(t, marker_found && halo_found,
		"the insertion edge should be legible through both a crisp marker and a soft halo")
	_ = process_pointer(&rt, Pointer_Event{kind=.Cancel})
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

	testing.expect(t, !visual_part_is_visible(&rt, selected_close),
		"Auto should hide the close part on a compact selected tab until it is hovered")
	dirty_marker, dirty_marker_count := tab_bar_test_visual_part(&rt, dirty_close, .Indicator)
	testing.expect(t, dirty_marker_count == 1 && tab_bar_test_display_has_surface(&rt, dirty_marker),
		"a hidden close action should retain its composed dirty indicator")
	testing.expect(t, !tab_bar_test_display_has_text(&rt, clean_close),
		"an unselected clean compact tab should omit its hidden close action from the composed paint stream")
	clean_title_bounds, clean_title_found := tab_bar_test_text_bounds(&rt, clean_tab)
	hidden_close_bounds := rt.nodes[clean_close].bounds
	testing.expect(t, hit_test(&rt, hidden_close_bounds.x+hidden_close_bounds.w*0.5, hidden_close_bounds.y+hidden_close_bounds.h*0.5) == clean_tab,
		"an invisible reserved close slot should fall through to its tab instead of acting like a hidden button")

	invalidate_root(&rt, "tab-bar responsive width increased")
	_ = tab_bar_test_build(&rt, items[:], 640, options)
	wide_close_visible := visual_part_is_visible(&rt, selected_close) && tab_bar_test_display_has_text(&rt, selected_close)
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
	close_glyph_visible := visual_part_is_visible(&rt, clean_close) && tab_bar_test_display_has_text(&rt, clean_close)
	testing.expect(t, rt.nodes[clean_tab].hovered && close_glyph_visible,
		"hovering any part of a compact tab should reveal its close glyph without changing geometry")
	testing.expect(t, same_rect(rt.nodes[clean_tab].bounds, clean_bounds),
		"revealing the close glyph should not shift or resize its tab")

	close_bounds := rt.nodes[clean_close].bounds
	testing.expect(t, close_bounds.w == TAB_CLOSE_CONTROL_SIZE && close_bounds.h == TAB_CLOSE_CONTROL_SIZE,
		"the embedded close hit target should remain at least 24x24 logical units")
	close_target := process_pointer(&rt, Pointer_Event{
		kind=.Move,
		x=close_bounds.x+close_bounds.w*0.5,
		y=close_bounds.y+close_bounds.h*0.5,
	})
	testing.expect(t, close_target == clean_close,
		"the visible internal close slot should receive pointer hits independently from the tab body")
	ui, ready = begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	close_paint := rt.nodes[clean_close].paint
	hover_surface_found := false
	for command in close_paint {
		if surface, ok := command.payload.(Surface_Paint); ok {
			if surface.fill.a > 0 { hover_surface_found = true }
		}
	}
	testing.expect(t, hover_surface_found,
		"hovering the close Button should paint its generic recipe surface")
	testing.expect(t, same_rect(rt.nodes[clean_tab].bounds, clean_bounds),
		"hovering the close action must not resize or reflow its tab")
	close_title_bounds, close_title_found := tab_bar_test_text_bounds(&rt, clean_tab)
	testing.expect(t, clean_title_found && close_title_found && same_rect(clean_title_bounds, close_title_bounds),
		"showing and hovering the close affordance must not move or rewrap the tab title")
}

@(test)
test_tab_bar_dirty_marker_only_yields_to_close_hover :: proc(t: ^testing.T) {
	items := [1]Tab_Bar_Item{{
		key=key_string("dirty-document"),
		label="README.md",
		selected=true,
		closable=true,
		dirty=true,
		semantic_id=tab_bar_test_semantic(11),
	}}
	options := tab_bar_test_options()
	options.close_policy = .Selected_Or_Hover
	rt := new_runtime(Rect{0, 0, 360, 120})
	defer destroy_runtime(&rt)
	_ = tab_bar_test_build(&rt, items[:], 320, options)
	_ = tab_bar_test_build(&rt, items[:], 320, options)
	tab_id, tab_count := tab_bar_test_item_node(&rt, items[0].semantic_id)
	close_id, close_count := tab_bar_test_close_node(&rt, tab_id)
	testing.expect(t, tab_count == 1 && close_count == 1,
		"the dirty document should have one retained tab and one internal close action")
	if tab_count != 1 || close_count != 1 { return }
	marker_id, marker_count := tab_bar_test_visual_part(&rt, close_id, .Indicator)
	glyph_id, glyph_count := tab_bar_test_visual_part(&rt, close_id, .Label)
	testing.expect(t, marker_count == 1 && glyph_count == 1,
		"a dirty close action should compose one marker and one close glyph as its own visual parts")
	if marker_count != 1 || glyph_count != 1 { return }

	tab_bounds := rt.nodes[tab_id].bounds
	close_bounds := rt.nodes[close_id].bounds
	testing.expect(t, tab_bar_test_display_has_surface(&rt, marker_id) && !tab_bar_test_display_has_text(&rt, glyph_id),
		"a selected dirty tab should show its dirty marker until the close action itself is hovered")
	testing.expect(t, hit_test(&rt, close_bounds.x+close_bounds.w*0.5, close_bounds.y+close_bounds.h*0.5) == tab_id,
		"the hidden close slot should not activate from pointer hit testing before it has been revealed")

	body_x := tab_bounds.x+tab_bounds.w*0.35
	body_y := tab_bounds.y+tab_bounds.h*0.5
	testing.expect(t, process_pointer(&rt, Pointer_Event{kind=.Move, x=body_x, y=body_y}) == tab_id,
		"moving over the tab body should target the tab, not its hidden close action")
	ui, ready := begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	testing.expect(t, tab_bar_test_display_has_surface(&rt, marker_id) && !tab_bar_test_display_has_text(&rt, glyph_id),
		"tab-body hover and selected state must not replace a dirty marker with a close glyph")

	close_x := close_bounds.x+close_bounds.w*0.5
	close_y := close_bounds.y+close_bounds.h*0.5
	testing.expect(t, process_pointer(&rt, Pointer_Event{kind=.Move, x=close_x, y=close_y}) == close_id,
		"pointer motion must be able to reveal the close action in its reserved slot")
	ui, ready = begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	close_paint := rt.nodes[close_id].paint
	hover_surface := false
	for command in close_paint {
		if surface, ok := command.payload.(Surface_Paint); ok && surface.fill.a > 0 {
			hover_surface = command.bounds == close_bounds
		}
	}
	testing.expect(t, rt.nodes[close_id].hovered && tab_bar_test_display_has_text(&rt, glyph_id) &&
		!tab_bar_test_display_has_surface(&rt, marker_id) && hover_surface,
		"the close glyph should replace the dirty marker while its generic Button recipe paints the hovered action")
	testing.expect(t, same_rect(rt.nodes[tab_id].bounds, tab_bounds) && same_rect(rt.nodes[close_id].bounds, close_bounds),
		"revealing the close action must not move or resize the tab or its title slot")

	testing.expect(t, process_pointer(&rt, Pointer_Event{kind=.Move, x=body_x, y=body_y}) == tab_id,
		"leaving the close slot should return pointer ownership to the tab body")
	ui, ready = begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	testing.expect(t, tab_bar_test_display_has_surface(&rt, marker_id) && !tab_bar_test_display_has_text(&rt, glyph_id),
		"leaving the close action should restore the dirty marker even while the tab remains hovered")

	// A click that arrives before any hover/motion event must not activate a
	// visually hidden close action. Native pointer streams normally include
	// motion, but keep this safety property explicit at the input boundary.
	direct_rt := new_runtime(Rect{0, 0, 360, 120})
	defer destroy_runtime(&direct_rt)
	_ = tab_bar_test_build(&direct_rt, items[:], 320, options)
	direct_tab, _ := tab_bar_test_item_node(&direct_rt, items[0].semantic_id)
	direct_close, _ := tab_bar_test_close_node(&direct_rt, direct_tab)
	if direct_tab == 0 || direct_close == 0 {
		testing.expect(t, false, "a second dirty tab should be available for direct-click hit testing")
		return
	}
	direct_bounds := direct_rt.nodes[direct_close].bounds
	direct_x, direct_y := direct_bounds.x+direct_bounds.w*0.5, direct_bounds.y+direct_bounds.h*0.5
	testing.expect(t, process_pointer(&direct_rt, Pointer_Event{kind=.Down, x=direct_x, y=direct_y, button=POINTER_BUTTON_PRIMARY}) == direct_tab,
		"a direct click on an unrevealed dirty marker should be routed to the parent tab")
	_ = process_pointer(&direct_rt, Pointer_Event{kind=.Up, x=direct_x, y=direct_y, button=POINTER_BUTTON_PRIMARY})
	direct_result := tab_bar_test_build(&direct_rt, items[:], 320, options)
	testing.expect(t, direct_result.action != .Close,
		"a hidden close action must not produce a close request from a direct click")
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
		if node, found := rt.nodes[candidate]; found && node.active && node.kind == .Button && node.button_variant == .Tab {
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
