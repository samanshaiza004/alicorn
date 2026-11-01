package alicorn

import "core:mem"
import "core:testing"

SCROLL_FOCUS_TEST_ENTITY :: Semantic_ID{namespace=143, value=1}

scroll_focus_test_describe :: proc(ui: ^UI, visual: Scroll_Focus_Visual, use_default, realize_semantic: bool) {
	style := layout_style(.Column, width=240, height=72)
	location := #location()
	region: Scroll_Region_Handle
	if use_default {
		// Exercise the public default by actually omitting the option.
		region = scroll_region_begin(ui, key=key_string("scroll-focus-owner"),
			viewport_height=72, content_height=240, style=style, scrollbars=.Hidden, focusable=true, loc=location)
	} else {
		region = scroll_region_begin(ui, key=key_string("scroll-focus-owner"),
			viewport_height=72, content_height=240, style=style, scrollbars=.Hidden,
			focusable=true, focus_visual=visual, loc=location)
	}
	_ = text_input_target(ui, region.id)
	_ = semantic_description(ui, .Text_Area, "Source editor", value="source",
		actions={.Focus, .Set_Text_Selection, .Replace_Selected_Text})
	// Caller-owned active-line and caret surfaces must survive suppression of
	// the generic outline. No font/native host is required for this fixture.
	container_begin(ui, .Container, key=key_string("scroll-focus-line"),
		style=layout_style(.Row, width=240, height=24), color=Color{0.1, 0.2, 0.3, 1})
	if realize_semantic { _ = semantic_bind(ui, SCROLL_FOCUS_TEST_ENTITY) }
	container_begin(ui, .Container, key=key_string("scroll-focus-caret"),
		style=layout_style(width=2, height=16), color=Color{0.9, 0.9, 0.9, 1})
	container_end(ui)
	container_end(ui)
	scroll_region_end(ui)
}

scroll_focus_test_render :: proc(
	rt: ^Runtime,
	visual := Scroll_Focus_Visual.Outline,
	use_default := false,
	include_owner := true,
	cache_revision: u64 = 0,
	realize_semantic := false,
) -> Node_ID {
	invalidate_root(rt, "scroll focus presentation fixture")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("scroll-focus-root"),
		style=layout_style(.Column, width=320, height=120))
	if cache_revision == 0 {
		if include_owner { scroll_focus_test_describe(&ui, visual, use_default, realize_semantic) }
	} else {
		cache, reused := region_begin(&ui, "scroll-focus-cache", cache_revision,
			style=layout_style(.Column, width=240, height=72))
		if cache != 0 && !reused {
			if include_owner { scroll_focus_test_describe(&ui, visual, use_default, realize_semantic) }
			region_end(&ui, cache, false, 0)
		}
	}
	container_end(&ui)
	end_frame(&ui)
	owner, _ := node_by_key(rt, key_string("scroll-focus-owner"), .Scroll_Region)
	return owner
}

scroll_focus_test_outline_count :: proc(rt: ^Runtime, owner: Node_ID) -> int {
	node, found := rt.nodes[owner]
	if !found { return 0 }
	focus_color := style_environment_color(rt, node.style_environment, .Focus)
	count := 0
	for command in node.paint {
		if color, ok := paint_surface_color(command); ok && color == focus_color { count += 1 }
	}
	return count
}

@(test)
test_scroll_focus_visual_default_outline_and_content :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	owner := scroll_focus_test_render(&rt, use_default=true)
	testing.expect(t, owner != 0 && focus_traverse(&rt, .Next) == owner,
		"the default scroll region must participate in keyboard traversal")
	_ = scroll_focus_test_render(&rt, use_default=true)
	testing.expect(t, scroll_focus_test_outline_count(&rt, owner) == 4,
		"omitting focus_visual must preserve the default four-edge focus outline")
	testing.expect(t, !rt.scroll_focus_visuals_initialized && rt.scroll_focus_visuals == nil && rt.pending_scroll_focus_visuals == nil,
		"ordinary scroll regions must not allocate opt-in presentation storage")

	content_owner := scroll_focus_test_render(&rt, .Content)
	testing.expect(t, content_owner == owner && focused_node(&rt) == owner && rt.nodes[owner].focusable,
		"Content must preserve the keyed owner and its keyboard focusability")
	testing.expect(t, scroll_focus_test_outline_count(&rt, owner) == 0 && len(rt.nodes[owner].paint) == 0,
		"Content must suppress the generic outline, including its rectangular paint commands")
	content_keys := [2]string{"scroll-focus-line", "scroll-focus-caret"}
	for key in content_keys {
		id, found := node_by_key(&rt, key_string(key), .Container)
		testing.expect(t, found && len(rt.nodes[id].paint) == 1,
			"caller-owned active-line and caret visuals must continue painting")
		in_display := false
		for command in rt.display { if command.owner == id { in_display = true } }
		testing.expect(t, in_display, "caller focus visuals must remain in the composed display list")
	}
	testing.expect(t, focus_traverse(&rt, .Previous) == owner,
		"Content must remain eligible for keyboard traversal")
}

@(test)
test_scroll_focus_visual_is_scoped_to_owner :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "the mixed-policy fixture must build"); return }
	container_begin(&ui, .Root, key=key_string("mixed-scroll-focus-root"),
		style=layout_style(.Column, width=320, height=180))
	scroll_focus_test_describe(&ui, .Content, false, false)
	list := virtual_list_begin(&ui, 0, 24, key=key_string("default-scroll-focus-list"),
		style=layout_style(width=240, height=72), focusable=true)
	virtual_list_end(&ui, list)
	container_end(&ui)
	end_frame(&ui)
	content, _ := node_by_key(&rt, key_string("scroll-focus-owner"), .Scroll_Region)
	testing.expect(t, focus_traverse(&rt, .Next) == content, "the Content owner must remain in traversal order")
	update_paint(&rt)
	testing.expect(t, scroll_focus_test_outline_count(&rt, content) == 0, "the opted-in owner must suppress its outline")
	testing.expect(t, focus_traverse(&rt, .Next) == list.scroll.id, "the default list must remain in traversal order")
	update_paint(&rt)
	testing.expect(t, scroll_focus_test_outline_count(&rt, list.scroll.id) == 4,
		"opting one region into Content must not suppress a separate default list's focus outline")
}

@(test)
test_scroll_focus_visual_changes_only_paint :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	owner := scroll_focus_test_render(&rt, use_default=true)
	_ = focus(&rt, owner)
	_ = scroll_focus_test_render(&rt, use_default=true)
	node := rt.nodes[owner]
	description_before, layout_before := node.description_hash, node.layout_hash
	measure_before := rt.measure_states[owner].input_revision
	bounds_before := node.bounds

	visuals := [2]Scroll_Focus_Visual{.Content, .Outline}
	for visual in visuals {
		before := rt.stats
		_ = scroll_focus_test_render(&rt, visual, use_default=visual == .Outline)
		testing.expect(t, rt.stats.paint_updates == before.paint_updates+1 &&
			rt.stats.paint_nodes_visited == before.paint_nodes_visited+1,
			"each policy transition must rebuild only the scroll owner's paint")
		testing.expect(t, rt.stats.layout_nodes_visited == before.layout_nodes_visited &&
			rt.stats.layout_updates == before.layout_updates &&
			rt.stats.measure_nodes_examined == before.measure_nodes_examined &&
			rt.stats.measure_nodes_executed == before.measure_nodes_executed,
			"changing only focus_visual must not schedule measurement or layout")
		testing.expect(t, node.description_hash == description_before && node.layout_hash == layout_before &&
			rt.measure_states[owner].input_revision == measure_before && node.bounds == bounds_before,
			"the policy belongs only to paint dependencies, with stable description and layout products")
		expected := 0 if visual == .Content else 4
		testing.expect(t, scroll_focus_test_outline_count(&rt, owner) == expected,
			"changing or omitting the option must immediately update the retained focus outline")
		stable := rt.stats
		_ = scroll_focus_test_render(&rt, visual, use_default=visual == .Outline)
		testing.expect(t, rt.stats.paint_updates == stable.paint_updates &&
			rt.stats.layout_nodes_visited == stable.layout_nodes_visited,
			"an unchanged policy must reuse its paint without layout work")
	}
}

@(test)
test_scroll_focus_visual_preserves_semantic_focus_and_text_input :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	owner := scroll_focus_test_render(&rt, .Content)
	_ = focus(&rt, owner)
	_ = semantic_focus_set(&rt, SCROLL_FOCUS_TEST_ENTITY, owner)
	area := Text_Input_Area{rect=Rect{12, 8, 2, 16}, cursor_x=1}
	testing.expect(t, text_input_target_area_set(&rt, owner, area), "the focused editor must accept its IME caret anchor")
	_ = scroll_focus_test_render(&rt, .Content)
	logical_before := semantic_focus_state(&rt)
	selected_before := rt.selected
	before := semantic_snapshot(&rt)
	defer semantic_snapshot_destroy(&before)
	testing.expect(t, before.keyboard_focus == semantic_visual_id(owner) && logical_before.owner == owner &&
		logical_before.id == SCROLL_FOCUS_TEST_ENTITY && logical_before.realized_node == 0,
		"Content must publish accessibility focus while retaining an unrealized logical focus entity")

	visuals := [2]Scroll_Focus_Visual{.Outline, .Content}
	for visual in visuals {
		_ = scroll_focus_test_render(&rt, visual)
		after := semantic_snapshot(&rt)
		testing.expect(t, after.revision == before.revision && after.keyboard_focus == before.keyboard_focus &&
			len(after.nodes) == len(before.nodes),
			"a visual policy transition must not publish an accessibility change")
		if len(after.nodes) == len(before.nodes) {
			for semantic_node, index in after.nodes {
				testing.expect(t, semantic_node_equal(semantic_node, before.nodes[index]),
					"accessible roles, actions, values, geometry, and focus must remain unchanged")
			}
		}
		semantic_snapshot_destroy(&after)
		testing.expect(t, semantic_focus_state(&rt) == logical_before && focused_node(&rt) == owner && rt.selected == selected_before,
			"visual policy changes must preserve logical focus, keyboard focus, and selection")
		actual_area, area_ok := text_input_area(&rt, owner)
		testing.expect(t, text_input_target_is_active(&rt, owner) && !text_input_target_is_suspended(&rt, owner) &&
			area_ok && actual_area == area,
			"native text-input eligibility and IME candidate geometry must survive policy transitions")
	}

	_ = scroll_focus_test_render(&rt, .Content, realize_semantic=true)
	line, _ := node_by_key(&rt, key_string("scroll-focus-line"), .Container)
	testing.expect(t, semantic_focus_state(&rt).realized_node == line && rt.nodes[line].semantic_active,
		"Content must allow the logical focus entity to reconnect to a realized descendant")
	_ = scroll_focus_test_render(&rt, .Content)
	testing.expect(t, semantic_focus_state(&rt) == logical_before && scroll_focus_test_outline_count(&rt, owner) == 0,
		"losing a semantic realization must preserve logical focus without adding an owner fallback outline in Content")
}

@(test)
test_scroll_focus_visual_reuse_retirement_and_storage_lifetime :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	rt := new_runtime(Rect{0, 0, 320, 120}, Runtime_Config{persistent_allocator=mem.tracking_allocator(&tracking)})
	runtime_alive := true
	defer { if runtime_alive { destroy_runtime(&rt) } }
	owner := scroll_focus_test_render(&rt, .Content, cache_revision=1)
	_ = focus(&rt, owner)
	before := rt.stats.retained_subtrees_reused
	_ = scroll_focus_test_render(&rt, use_default=true, cache_revision=1)
	testing.expect(t, rt.stats.retained_subtrees_reused == before+1 && rt.scroll_focus_visuals[owner] == .Content &&
		focused_node(&rt) == owner && scroll_focus_test_outline_count(&rt, owner) == 0,
		"a cached subtree must retain Content when its scroll owner is not re-described")

	// Force a retained-only repaint after pending declarations have been cleared.
	invalidate_interaction_paint(&rt, owner, "test retained Content repaint")
	update_paint(&rt)
	testing.expect(t, scroll_focus_test_outline_count(&rt, owner) == 0,
		"paint must read the retained policy rather than transient pending declarations")
	_ = scroll_focus_test_render(&rt, use_default=true, cache_revision=2)
	testing.expect(t, scroll_focus_test_outline_count(&rt, owner) == 4 && owner not_in rt.scroll_focus_visuals,
		"an explicit cached-region rebuild omitting the option must remove stale Content state")
	_ = scroll_focus_test_render(&rt, .Content, cache_revision=3)
	_ = scroll_focus_test_render(&rt, include_owner=false, cache_revision=4)
	testing.expect(t, owner not_in rt.nodes && owner not_in rt.scroll_focus_visuals,
		"retiring a scroll owner must remove its presentation sidecar entry")
	owner_again := scroll_focus_test_render(&rt, use_default=true, cache_revision=5)
	testing.expect(t, owner_again == owner && focus(&rt, owner_again), "the same keyed owner must be recreatable")
	_ = scroll_focus_test_render(&rt, use_default=true, cache_revision=5)
	testing.expect(t, scroll_focus_test_outline_count(&rt, owner_again) == 4,
		"a recreated default region must not inherit its retired Content policy")

	destroy_runtime(&rt)
	runtime_alive = false
	testing.expect(t, len(tracking.allocation_map) == 0,
		"runtime destruction must release both pending and retained scroll presentation storage")
}
