package alicorn

TAB_CLOSE_SLOT_WIDTH :: f32(28)
TAB_CLOSE_CONTROL_SIZE :: f32(24)
TAB_AUTO_CLOSE_ALWAYS_WIDTH :: f32(156)

Tab_Bar_Item :: struct {
	key:         UI_Key,
	label:       string,
	selected:    bool,
	closable:    bool,
	dirty:       bool,
	semantic_id: Semantic_ID,
}

Tab_Bar_Options :: struct {
	min_tab_width: f32,
	max_tab_width: f32,
	height:        f32,
	gap:           f32,
	close_policy:  Tab_Close_Policy,
	drag_type:     Drag_Type,
}

DEFAULT_TAB_BAR_OPTIONS :: Tab_Bar_Options{
	min_tab_width=84,
	max_tab_width=220,
	height=34,
	gap=1,
	close_policy=.Auto,
}

DEFAULT_TAB_BAR_STYLE :: Layout_Style{.Column, -1, 38, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}

Tab_Bar_Action :: enum { None, Select, Close }

Tab_Bar_Result :: struct {
	action:     Tab_Bar_Action,
	item_index: int,
}

Tab_Bar_Navigation :: enum {
	Next,
	Previous,
	Index_1,
	Index_2,
	Index_3,
	Index_4,
	Index_5,
	Index_6,
	Index_7,
	Index_8,
	Last,
}

// tab_bar describes a complete horizontal tab list. Item selection, closing,
// and ordering remain application-owned: the result reports one requested
// action by index, and configured drag targets emit the normal Drag_Event.
// Item keys must be stable and explicit because tabs survive reordering.
tab_bar :: proc(
	ui: ^UI,
	key: UI_Key,
	items: []Tab_Bar_Item,
	options := DEFAULT_TAB_BAR_OPTIONS,
	style := DEFAULT_TAB_BAR_STYLE,
	loc := #caller_location,
) -> Tab_Bar_Result {
	result := Tab_Bar_Result{item_index=-1}
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return result }
	rt := ui.runtime
	opts := options
	bar_style := style
	for item in items {
		if !ui_key_is_explicit(item.key) {
			append_diagnostic(rt, "tab_bar items require an explicit stable UI_Key")
			return result
		}
	}
	selected_count := 0
	for item in items { if item.selected { selected_count += 1 } }
	if selected_count > 1 {
		append_diagnostic(rt, "tab_bar accepts at most one selected item")
		return result
	}

	opts.min_tab_width = clampf(opts.min_tab_width, 48, 1024)
	opts.max_tab_width = clampf(opts.max_tab_width, opts.min_tab_width, 2048)
	opts.height = clampf(opts.height, 18, 256)
	opts.gap = clampf(opts.gap, 0, 64)
	bar_style.direction = .Column
	bar_style.clip = true
	viewport_guess := tab_bar_viewport_guess(ui, bar_style)
	initial_content_width := maxf(viewport_guess, f32(len(items))*(opts.min_tab_width+opts.gap)-opts.gap)
	scroll := scroll_region_begin(
		ui,
		key=key,
		viewport_width=viewport_guess,
		content_width=initial_content_width,
		line_width=maxf(opts.min_tab_width, 24),
		style=bar_style,
		label="tab-bar",
		loc=loc,
		axes=.Horizontal,
		axis_behavior=.Auto_Lock,
		scrollbars=.Hidden,
	)
	if scroll.id == 0 { return result }

	viewport_width := maxf(scroll.viewport_width, 0)
	content_width := maxf(viewport_width, f32(len(items))*(opts.min_tab_width+opts.gap)-opts.gap)
	tab_width: f32 = 0
	if len(items) > 0 {
		available := maxf(content_width-opts.gap*f32(len(items)-1), 0)
		tab_width = clampf(available/f32(len(items)), opts.min_tab_width, opts.max_tab_width)
		content_width = maxf(viewport_width, tab_width*f32(len(items))+opts.gap*f32(len(items)-1))
	}
	selected_index := -1
	for item, index in items {
		if !item.selected { continue }
		selected_index = index
		break
	}
	offset_x := scroll.offset_x
	if selected_index >= 0 && tab_width > 0 {
		left := f32(selected_index)*(tab_width+opts.gap)
		right := left+tab_width
		if left < offset_x {
			offset_x = left
		} else if right > offset_x+viewport_width {
			offset_x = right-viewport_width
		}
	}
	offset_x = clampf(offset_x, 0, maxf(content_width-viewport_width, 0))
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		pending := &rt.pending[index]
		if pending.kind != .Description || pending.description.id != scroll.id { continue }
		pending.description.scroll_content_width = content_width
		pending.description.scroll_offset_x = offset_x
		pending.description.layout_scroll_offset_x = 0
		break
	}

	row_style := layout_style(.Row, width=content_width, height=scroll.viewport_height, gap=opts.gap, clip=true)
	container_begin_simple(
		ui,
		.Virtual_List,
		label="tab-bar-items",
		key=key_u64(1),
		style=row_style,
		loc=loc,
		scroll_offset_x=offset_x,
		layout_scroll_offset_x=offset_x,
	)
	for item, index in items {
		// A Tab is a semantic button whose visible pieces are composed from
		// retained layout nodes: its content row, close/dirty action, and a
	// theme-resolved selected indicator. The renderer never needs tab-specific
	// bounds arithmetic for those parts.
		tab_style := layout_style(.Column, width=tab_width, height=opts.height, gap=0, clip=true)
		text_style := DEFAULT_BUTTON_TEXT_STYLE
		text_style.overflow = .Ellipsis
		tab_id := emit_key(
			ui,
			.Tab,
			resolve_source(Source_Site{}, "tab", loc),
			label=item.label,
			key=item.key,
			style=tab_style,
			state_bits=1 if item.selected else 0,
			selected=item.selected,
			focusable=true,
			font=Font_Role.UI,
			text_style=text_style,
			button_content=button_content_style(.Start, padding_x=10, padding_y=0),
			button_variant=.Tab,
		)
		if tab_id == 0 { continue }
		pending := &rt.pending[len(rt.pending)-1].description
		// Keep the fixed-size description contract compact by encoding the
		// tab-only presentation flags in the existing paint state word.
		pending.paint_value |= u64(opts.close_policy) << 1
		pending.paint_value |= 1 << 5 // selected underline is a composed surface part
		if item.closable { pending.paint_value |= 1 << 3 }
		if item.dirty { pending.paint_value |= 1 << 4 }
		pending.semantic_id = item.semantic_id
		if opts.drag_type != Drag_Type(0) && semantic_id_is_valid(item.semantic_id) {
			_ = drag_source(ui, opts.drag_type, item.semantic_id)
			_ = drop_target(ui, opts.drag_type, item.semantic_id, .Between_Horizontal)
		}
		if consume_activation(rt, tab_id) && result.action == .None {
			result = Tab_Bar_Result{.Select, index}
		}

		append(&rt.stack, tab_id)
		push_identity_scope(rt, tab_id, "", 0)
		container_begin_simple(
			ui,
			.Container,
			label="tab-content",
			key=key_u64(1),
			style=layout_style(.Row, width=tab_width, height=maxf(opts.height-2, 0), gap=0, align=.Center, clip=true),
		)
		container_begin_simple(
			ui,
			.Container,
			label="tab-content-spacer",
			key=key_u64(1),
			style=layout_style(.Row, height=maxf(opts.height-2, 0), grow=1),
		)
		container_end(ui)
		if item.closable {
			close_id := emit_key(
				ui,
				.Tab_Close,
				resolve_source(Source_Site{}, "tab_close", loc),
				label="Close tab",
				text="×",
				key=key_u64(2),
				style=layout_style(.Row, width=TAB_CLOSE_CONTROL_SIZE, height=minf(TAB_CLOSE_CONTROL_SIZE, maxf(opts.height-2, 18)), align=.Center),
				color=style_environment_color(rt, rt.style_environment, .Text),
				font=Font_Role.UI,
				text_style=DEFAULT_BUTTON_TEXT_STYLE,
				button_variant=.Quiet,
			)
			if consume_activation(rt, close_id) && result.action == .None {
				result = Tab_Bar_Result{.Close, index}
			}
		} else if item.dirty {
			// The dirty mark is a normal semantic surface part. Its location is
			// determined by the content row's layout, not paint-time geometry.
			_ = surface_begin(
				ui,
				surface_core_color_role(.Accent),
				key=key_u64(2),
				style=layout_style(.Row, width=6, height=6),
				label="tab-dirty-indicator",
			)
			surface_end(ui)
		}
		container_end(ui)
		_ = surface_begin(
			ui,
			surface_core_color_role(.Accent),
			key=key_u64(3),
			style=layout_style(.Row, width=tab_width, height=2 if item.selected else 0),
			label="tab-selected-indicator",
		)
		surface_end(ui)
		pop(&rt.stack)
		pop_identity_scope(rt)
	}
	container_end(ui)
	scroll_region_end(ui)
	return result
}

// tab_bar_navigate maps a semantic navigation command to an item index. It
// leaves actual selection to the app and intentionally contains no platform
// shortcut policy.
tab_bar_navigate :: proc(item_count, selected_index: int, navigation: Tab_Bar_Navigation) -> (index: int, found: bool) {
	if item_count <= 0 { return -1, false }
	switch navigation {
	case .Next:
		if selected_index < 0 || selected_index >= item_count { return 0, true }
		return (selected_index+1)%item_count, true
	case .Previous:
		if selected_index < 0 || selected_index >= item_count { return item_count-1, true }
		return (selected_index+item_count-1)%item_count, true
	case .Index_1: return 0, true
	case .Index_2: if item_count > 1 { return 1, true }
	case .Index_3: if item_count > 2 { return 2, true }
	case .Index_4: if item_count > 3 { return 3, true }
	case .Index_5: if item_count > 4 { return 4, true }
	case .Index_6: if item_count > 5 { return 5, true }
	case .Index_7: if item_count > 6 { return 6, true }
	case .Index_8: if item_count > 7 { return 7, true }
	case .Last: return item_count-1, true
	}
	return -1, false
}

tab_close_should_show :: proc(tab, close: ^Node) -> bool {
	if tab == nil || close == nil || !tab.tab_closable { return false }
	hovered := tab.hovered || close.hovered
	switch tab.tab_close_policy {
	case .Always: return true
	case .Hover: return hovered
	case .Selected_Or_Hover: return tab.selected || hovered
	case .Auto:
		return tab.bounds.w >= TAB_AUTO_CLOSE_ALWAYS_WIDTH || hovered
	}
	return false
}

tab_ancestor :: proc(rt: ^Runtime, node: ^Node) -> ^Node {
	if rt == nil || node == nil { return nil }
	parent_id := node.parent
	for parent_id != 0 {
		parent, found := rt.nodes[parent_id]
		if !found { return nil }
		if parent.kind == .Tab { return parent }
		parent_id = parent.parent
	}
	return nil
}

tab_trailing_slot_width :: proc(node: ^Node) -> f32 {
	if node == nil { return 0 }
	if node.tab_closable { return TAB_CLOSE_SLOT_WIDTH }
	if node.tab_dirty { return 16 }
	return 0
}

tab_bar_viewport_guess :: proc(ui: ^UI, style: Layout_Style) -> f32 {
	if style.width > 0 { return maxf(style.width-2*maxf(style.padding, 0), 0) }
	if parent_id := current_node_parent(ui); parent_id != 0 {
		if parent, found := ui.runtime.nodes[parent_id]; found && parent.bounds.w > 0 {
			return maxf(parent.bounds.w-2*maxf(parent.style.padding, 0)-2*maxf(style.padding, 0), 0)
		}
	}
	return 320
}
