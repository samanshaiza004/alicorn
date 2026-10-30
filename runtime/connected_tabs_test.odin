package alicorn

import "core:testing"

connected_tabs_test_flex_bar_build :: proc(rt: ^Runtime) -> (selected: Node_ID, bar: Node_ID) {
	ui, ready := begin_frame(rt)
	if !ready { return }
	container_begin_simple(&ui, .Root, key=key_string("flex-tab-root"), style=layout_style(.Column))
	row := container_begin_simple(&ui, .Container, key=key_string("flex-tab-row"),
		style=layout_style(.Row, width=560, height=42, clip=true))
	container_begin_simple(&ui, .Container, key=key_string("flex-tab-leading-band"),
		style=layout_style(.Row, width=360, height=42))
	container_end(&ui)
	items := [6]Tab_Bar_Item{
		{key=key_string("flex-doc-0"), label="zero", semantic_id=tab_bar_test_semantic(10)},
		{key=key_string("flex-doc-1"), label="one", semantic_id=tab_bar_test_semantic(11)},
		{key=key_string("flex-doc-2"), label="two", semantic_id=tab_bar_test_semantic(12)},
		{key=key_string("flex-doc-3"), label="three", semantic_id=tab_bar_test_semantic(13)},
		{key=key_string("flex-doc-4"), label="four", semantic_id=tab_bar_test_semantic(14)},
		{key=key_string("flex-doc-5"), label="five", selected=true, semantic_id=tab_bar_test_semantic(15)},
	}
	opts := DEFAULT_TAB_BAR_OPTIONS
	opts.min_tab_width, opts.max_tab_width, opts.gap = 84, 180, 0
	opts.height, opts.appearance, opts.presentation = 42, .Connected, .Compact
	_ = tab_bar(&ui, key_string("flex-tab-bar"), items[:], opts,
		layout_style(.Row, grow=1, height=42, clip=true))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	selected, _ = tab_bar_test_item_node(rt, items[5].semantic_id)
	bar, _ = tab_bar_test_bar_node(rt)
	return
}

connected_tabs_test_build :: proc(rt: ^Runtime, fill, ink: Color) -> (tab, paper, divider: Node_ID) {
	ui, ready := begin_frame(rt)
	if !ready { return }
	container_begin_simple(&ui,.Root,key="connected-root",style=layout_style(.Column))
	split:=split_begin(&ui,key_string("connected-split"),.Horizontal,50,min_first=20,min_second=100)
	split_first_begin(&ui,split)
	split_first_end(&ui,split)
	divider=split_divider(&ui,split)
	split_second_begin(&ui,split)
	items := tab_bar_test_items(0)
	options := DEFAULT_TAB_BAR_OPTIONS
	options.height=42
	options.min_tab_width=130
	options.max_tab_width=130
	options.presentation=.Compact
	options.appearance=.Connected
	options.selected_fill,options.selected_text,options.selected_fill_set=fill,ink,true
	result := tab_bar(&ui,key_string("connected-tabs"),items[:],options,layout_style(.Row,height=42,clip=true))
	tab=result.selected_tab
	paper=surface_begin(&ui,surface_core_color_role(.Surface),key="connected-paper",style=layout_style(.Column,grow=1),fill=fill,open_top_edge=tab)
	surface_end(&ui)
	split_second_end(&ui,split)
	split_end(&ui,split)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_connected_tab_appearance_is_scoped_retained_and_preserves_close_target :: proc(t:^testing.T) {
	rt:=new_runtime(Rect{0,0,350,180})
	defer destroy_runtime(&rt)
	fill,ink:=Color{0.94,0.91,0.82,1},Color{0.1,0.12,0.13,1}
	_,_,_=connected_tabs_test_build(&rt,fill,ink)
	tab,paper,_:=connected_tabs_test_build(&rt,fill,ink)
	testing.expect(t,tab!=0 && paper!=0,"the component should publish its selected visual for an adjoining surface")
	if tab==0 || paper==0 { return }
	node:=rt.nodes[tab]
	paint,ok:=node.paint[0].payload.(Surface_Paint)
	testing.expect(t,ok && paint.shape.kind==.Connected_Tab && paint.fill==fill && node.color==ink,
		"connected selection should paint the supplied controlled-surface fill and foreground")
	indicator,count:=tab_bar_test_visual_part(&rt,tab,.Selected_Indicator)
	testing.expect(t,count==1 && rt.nodes[indicator].bounds.h==0,"the connected join must not retain an underline")
	close,close_count:=tab_bar_test_close_node(&rt,tab)
	testing.expect(t,close_count==1 && rt.nodes[close].bounds.w==TAB_CLOSE_CONTROL_SIZE && rt.nodes[close].bounds.h==TAB_CLOSE_CONTROL_SIZE,
		"decoration must preserve the independently interactive close target")
	label,label_count:=tab_bar_test_visual_part(&rt,tab,.Label)
	// Both the document label and the clean close glyph inherit the paper ink.
	testing.expect(t,label_count==2 && label!=0,"the title and close glyph should share selected-surface contrast")
	items := tab_bar_test_items(0)
	for item in items {
		item_id, matches := tab_bar_test_item_node(&rt, item.semantic_id)
		if matches != 1 || item_id == 0 { continue }
		item_node := rt.nodes[item_id]
		shape, has_shape := rt.semantic_surfaces[item_id]
		item_paint := Surface_Paint{}
		paint_bounds := Rect{}
		has_paint := false
		if len(item_node.paint) > 0 {
			item_paint, has_paint = item_node.paint[0].payload.(Surface_Paint)
			paint_bounds = item_node.paint[0].bounds
		}
		expected_bounds := connected_tab_visual_bounds(item_node.bounds, item.selected)
		geometry_matches := paint_bounds == expected_bounds
		if item.selected {
			testing.expect(t, has_shape && has_paint && shape.shape.kind == .Connected_Tab && item_paint.fill == fill &&
				geometry_matches && expected_bounds == item_node.bounds,
				"the selected tab should use the shared curved contour at full height with the editor-paper fill")
		} else {
			close_id, close_matches := tab_bar_test_close_node(&rt, item_id)
			testing.expect(t, has_shape && has_paint && shape.shape.kind == .Connected_Tab && item_paint.shape.kind == .Connected_Tab,
				"inactive tabs should retain the connected contour")
			testing.expect(t, item_paint.fill != fill && geometry_matches && expected_bounds.y == item_node.bounds.y+CONNECTED_TAB_INACTIVE_DROP,
				"inactive tabs should use workbench fill and lower only their paint bounds")
			expected_close_width := f32(TAB_CLOSE_CONTROL_SIZE)
			if item.dirty { expected_close_width = TAB_CLOSE_SLOT_WIDTH }
			testing.expect(t, close_matches == 1 && rt.nodes[close_id].bounds.w == expected_close_width &&
				rt.nodes[close_id].bounds.h == TAB_CLOSE_CONTROL_SIZE,
				"inactive tab decoration should retain the original close hit target")
		}
		indicator_id, indicator_count := tab_bar_test_visual_part(&rt, item_id, .Selected_Indicator)
		testing.expect(t, indicator_count == 1 && rt.nodes[indicator_id].bounds.h == 0,
			"connected tabs should not retain a contradictory rectangular selected underline")
	}
	recipe:=style_button_recipe(&rt,DEFAULT_STYLE_ENVIRONMENT,.Tab)
	testing.expect(t,!recipe.surface_visible && recipe.selected_indicator==.Underline,"the global Tab recipe must retain its established appearance")
	before_shapes,before_layout:=rt.stats.text_shape_requests,rt.stats.layout_nodes_visited
	invalidate_root(&rt,"selected surface theme changed")
	tab_after,_,_:=connected_tabs_test_build(&rt,Color{0.82,0.9,0.96,1},ink)
	testing.expect(t,tab_after==tab && rt.stats.text_shape_requests==before_shapes && rt.stats.layout_nodes_visited==before_layout,
		"a selected fill change must preserve identity and invalidate paint without reshaping or layout")
	ui,ready:=begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	before:=rt.stats.paint_nodes_visited
	ui,ready=begin_presentation_frame(&rt)
	testing.expect(t,!ready && rt.stats.paint_nodes_visited==before,"unchanged connected tabs must require no idle paint work")
}

@(test)
test_connected_inactive_hover_and_focus_preserve_tab_geometry :: proc(t:^testing.T) {
	rt := new_runtime(Rect{0, 0, 720, 90})
	defer destroy_runtime(&rt)
	fill, ink := Color{0.94, 0.91, 0.82, 1}, Color{0.1, 0.12, 0.13, 1}
	_, _, _ = connected_tabs_test_build(&rt, fill, ink)
	_, _, _ = connected_tabs_test_build(&rt, fill, ink)
	items := tab_bar_test_items(0)
	inactive_id, count := tab_bar_test_item_node(&rt, items[1].semantic_id)
	testing.expect(t, count == 1 && inactive_id != 0, "the inactive tab should retain one stable Button identity")
	if inactive_id == 0 { return }
	owner := rt.nodes[inactive_id]
	bounds := owner.bounds
	rest_style := style_button_resolve(&rt, owner.style_environment, .Tab, Button_Visual_State{})
	rest_fill, _ := connected_tab_visual_colors(&rt, owner, rest_style, false, false, false)
	hover_style := style_button_resolve(&rt, owner.style_environment, .Tab, Button_Visual_State{hovered=true})
	hover_fill, _ := connected_tab_visual_colors(&rt, owner, hover_style, true, false, false)
	testing.expect(t, hover_fill != rest_fill,
		"hover should brighten the curved inactive-tab decoration through its retained state colors")
	testing.expect(t, connected_tab_visual_bounds(bounds, false).y == bounds.y+CONNECTED_TAB_INACTIVE_DROP && owner.bounds == bounds,
		"inactive visual depth should not alter retained hit geometry")
	test_environment := owner.style_environment
	test_environment.accessibility.increased_contrast = true
	test_node := owner^
	test_node.style_environment = test_environment
	resolved := style_button_resolve(&rt, test_environment, .Tab, Button_Visual_State{hovered=true})
	focus_fill, text := connected_tab_visual_colors(&rt, &test_node, resolved, true, false, false)
	testing.expect(t, style_color_contrast_ratio(text, focus_fill) >= 4.5,
		"inactive connected-tab text should retain minimum contrast against its state-resolved fill")
	rt.focus_visible = true
	testing.expect(t, focus(&rt, inactive_id), "an inactive document tab should remain keyboard-focusable")
	testing.expect(t, rt.focused == inactive_id && rt.nodes[inactive_id].bounds == bounds &&
		rt.nodes[inactive_id].button_variant == .Tab &&
		style_button_recipe(&rt, rt.nodes[inactive_id].style_environment, .Tab).focus_indicator_mode == .Keyboard_Only &&
		style_color_contrast_ratio(style_environment_color(&rt, test_environment, .Focus), focus_fill) >= 3,
		"connected tabs should preserve keyboard focus, focus visibility policy, and contrast without changing hit geometry")
}

@(test)
test_connected_surface_join_follows_retained_scroll_and_rejects_intervening_geometry :: proc(t:^testing.T) {
	rt:=new_runtime(Rect{0,0,350,180})
	defer destroy_runtime(&rt)
	fill,ink:=Color{0.94,0.91,0.82,1},Color{0.1,0.12,0.13,1}
	_,_,_=connected_tabs_test_build(&rt,fill,ink)
	tab,paper,divider:=connected_tabs_test_build(&rt,fill,ink)
	if tab==0 || paper==0 { testing.expect(t,false,"fixture must create tab and paper"); return }
	before:=rt.nodes[paper].paint[0].payload.(Surface_Paint).top_edge_gap
	scroll,count:=tab_bar_test_bar_node(&rt)
	testing.expect(t,count==1 && before[1]>before[0],"an abutting selected tab should open the matching paper edge")
	if count!=1 { return }
	testing.expect(t,scroll_region_set_offset_x(&rt,scroll,35,"connected-tab scroll"),"fixture must accept horizontal scroll")
	_,_,_=connected_tabs_test_build(&rt,fill,ink)
	after:=rt.nodes[paper].paint[0].payload.(Surface_Paint).top_edge_gap
	visible:=rect_intersection(rt.nodes[tab].bounds,rt.nodes[tab].clip)
	testing.expect(t,after!=before && after==[2]f32{visible.x,visible.x+visible.w},
		"horizontal scrolling must move the material opening to the selected tab's visible bounds")
	before_split:=after
	reconciles:=rt.stats.reconcile_nodes_visited
	adaptive_retained_split_drag(&rt,divider,25)
	ui,ready:=begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	after_split:=rt.nodes[paper].paint[0].payload.(Surface_Paint).top_edge_gap
	visible=rect_intersection(rt.nodes[tab].bounds,rt.nodes[tab].clip)
	testing.expect(t,ready && after_split!=before_split && after_split==[2]f32{visible.x,visible.x+visible.w} && rt.stats.reconcile_nodes_visited==reconciles,
		"a retained Split drag must move paper and its tab opening together in one presentation without application reconstruction")
	style:=rt.semantic_surfaces[paper]
	rt.nodes[tab].bounds.y-=8
	testing.expect(t,semantic_surface_top_edge_gap(&rt,rt.nodes[paper],style)==[2]f32{},
		"a surface separated from its tab by another strip must keep its complete top edge")
}

@(test)
test_tab_bar_reveals_selected_tab_after_flex_viewport_allocation :: proc(t:^testing.T) {
	rt := new_runtime(Rect{0, 0, 560, 100})
	defer destroy_runtime(&rt)
	selected, bar_id := connected_tabs_test_flex_bar_build(&rt)
	testing.expect(t, selected != 0 && bar_id != 0, "the flex viewport fixture should retain its selected tab and scroll region")
	if selected == 0 || bar_id == 0 { return }
	bar := rt.nodes[bar_id]
	tab := rt.nodes[selected]
	viewport := bar.scroll_viewport_bounds
	testing.expect(t, viewport.w < 320 && bar.scroll_content_width > viewport.w,
		"the tab scroller should receive a flex-allocated viewport narrower than its initial estimate")
	testing.expect(t, tab.bounds.x >= viewport.x-1 && tab.bounds.x+tab.bounds.w <= viewport.x+viewport.w+1,
		"the last selected tab should be visible on the very first layout using the actual assigned viewport")
	testing.expect(t, len(rt.scroll_visibility_requests) == 0,
		"the one-frame selection visibility intent should be released after layout")
}
