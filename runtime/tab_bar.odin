package alicorn

TAB_CLOSE_SLOT_WIDTH :: f32(28)
TAB_CLOSE_CONTROL_SIZE :: f32(24)
TAB_AUTO_CLOSE_ALWAYS_WIDTH :: f32(156)
TAB_BAR_SCROLL_CONTROL_WIDTH :: f32(22)

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
	// Closable tabs retain a 24x24 logical hit target. Keep the row tall enough
	// for that target rather than silently shrinking it below the intended size.
	opts.height = clampf(opts.height, 26, 256)
	opts.gap = clampf(opts.gap, 0, 64)
	bar_style.direction = .Row
	bar_style.clip = true
	viewport_guess := tab_bar_viewport_guess(ui, bar_style)
	minimum_content_width := f32(0)
	if len(items) > 0 {
		minimum_content_width = f32(len(items))*opts.min_tab_width + f32(len(items)-1)*opts.gap
	}
	show_scroll_controls := minimum_content_width > viewport_guess
	scroll_control_width := minf(TAB_BAR_SCROLL_CONTROL_WIDTH, maxf(viewport_guess*0.25, 0))
	scroll_viewport_guess := viewport_guess
	if show_scroll_controls { scroll_viewport_guess = maxf(viewport_guess-2*scroll_control_width, 0) }
	initial_content_width := maxf(scroll_viewport_guess, minimum_content_width)
	selected_index := -1
	selected_key_hash: u64 = 0
	for item, index in items {
		if !item.selected { continue }
		selected_index = index
		selected_key_hash = u64(identity_hash_key(0, Source_Site{}, item.key))
		break
	}
	selected_state_hash := hash_mix(selected_key_hash, u64(selected_index+1))

	previous_selection_hash: u64 = 0
	previous_state_valid := false
	previous_scroll_width: f32 = 0
	previous_content_width: f32 = 0
	if previous_bar_id, found := node_by_key(rt, key, .Container); found {
		previous_bar := rt.nodes[previous_bar_id]
		previous_selection_hash = previous_bar.paint_value
		previous_state_valid = true
		for child_id in previous_bar.children {
			if child, child_found := rt.nodes[child_id]; child_found && child.kind == .Scroll_Region {
				previous_scroll_width = child.scroll_viewport_width
				previous_content_width = child.scroll_content_width
				break
			}
		}
	} else if previous_scroll_id, found := node_by_key(rt, key, .Scroll_Region); found {
		// One-time compatibility with a tab bar retained by the pre-composite
		// structure. Its current selected state will be initialized below.
		previous_scroll := rt.nodes[previous_scroll_id]
		previous_scroll_width = previous_scroll.scroll_viewport_width
		previous_content_width = previous_scroll.scroll_content_width
	}
	previous_offset_x: f32 = 0
	if previous_bar_id, found := node_by_key(rt, key, .Container); found {
		previous_bar := rt.nodes[previous_bar_id]
		for child_id in previous_bar.children {
			if child, child_found := rt.nodes[child_id]; child_found && child.kind == .Scroll_Region {
				previous_offset_x = child.scroll_offset_x
				break
			}
		}
	} else if previous_scroll_id, found := node_by_key(rt, key, .Scroll_Region); found {
		previous_offset_x = rt.nodes[previous_scroll_id].scroll_offset_x
	}
	outer_id := container_begin_simple(
		ui,
		.Container,
		label="tab-bar-control",
		key=key,
		style=bar_style,
		loc=loc,
	)
	if outer_id == 0 { return result }
	outer_pending := &rt.pending[len(rt.pending)-1].description
	outer_pending.paint_value = selected_state_hash

	left_scroll_clicked := false
	left_scroll_id: Node_ID = 0
	if show_scroll_controls {
		left_scroll_id, left_scroll_clicked = tab_bar_scroll_button(
			ui,
			key_u64(2),
			"Scroll tabs left",
			"‹",
			scroll_control_width,
			opts.height,
			previous_offset_x <= 0,
			loc,
		)
	}

	scroll_style := layout_style(.Column, width=scroll_viewport_guess, height=opts.height, clip=true)
	scroll := scroll_region_begin(
		ui,
		key=key_u64(1),
		viewport_width=scroll_viewport_guess,
		content_width=initial_content_width,
		line_width=maxf(opts.min_tab_width, 24),
		style=scroll_style,
		label="tab-bar",
		loc=loc,
		axes=.Horizontal,
		axis_behavior=.Auto_Lock,
		scrollbars=.Hidden,
	)
	if scroll.id == 0 { return result }

	viewport_width := maxf(scroll.viewport_width, 0)
	content_width := maxf(viewport_width, minimum_content_width)
	tab_width: f32 = 0
	if len(items) > 0 {
		available := maxf(content_width-opts.gap*f32(len(items)-1), 0)
		tab_width = clampf(available/f32(len(items)), opts.min_tab_width, opts.max_tab_width)
		content_width = maxf(viewport_width, tab_width*f32(len(items))+opts.gap*f32(len(items)-1))
	}
	offset_x := scroll.offset_x
	selection_changed := !previous_state_valid || previous_selection_hash != selected_state_hash
	viewport_changed := previous_scroll_width > 0 && abs(previous_scroll_width-viewport_width) > 0.5
	content_changed := previous_content_width > 0 && abs(previous_content_width-content_width) > 0.5
	if selected_index >= 0 && tab_width > 0 && (selection_changed || viewport_changed || content_changed) {
		left := f32(selected_index)*(tab_width+opts.gap)
		right := left+tab_width
		if left < offset_x {
			offset_x = left
		} else if right > offset_x+viewport_width {
			offset_x = right-viewport_width
		}
	}
	offset_x = clampf(offset_x, 0, maxf(content_width-viewport_width, 0))
	if left_scroll_clicked {
		offset_x = maxf(offset_x-maxf(viewport_width*0.75, opts.min_tab_width+opts.gap), 0)
	}
	offset_x = clampf(offset_x, 0, maxf(content_width-viewport_width, 0))
	tab_bar_pending_scroll_set(rt, scroll.id, offset_x, content_width)

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
	if show_scroll_controls {
		right_scroll_id: Node_ID
		right_scroll_clicked: bool
		right_scroll_id, right_scroll_clicked = tab_bar_scroll_button(
			ui,
			key_u64(3),
			"Scroll tabs right",
			"›",
			scroll_control_width,
			opts.height,
			offset_x >= maxf(content_width-viewport_width, 0),
			loc,
		)
		if right_scroll_clicked {
			offset_x = minf(offset_x+maxf(viewport_width*0.75, opts.min_tab_width+opts.gap), maxf(content_width-viewport_width, 0))
			tab_bar_pending_scroll_set(rt, scroll.id, offset_x, content_width)
		}
		tab_bar_pending_button_disabled_set(rt, left_scroll_id, offset_x <= 0)
		tab_bar_pending_button_disabled_set(rt, right_scroll_id, offset_x >= maxf(content_width-viewport_width, 0))
	}
	container_end(ui)
	return result
}

tab_bar_scroll_button :: proc(
	ui: ^UI,
	key: UI_Key,
	accessible_label, glyph: string,
	width, height: f32,
	disabled: bool,
	loc := #caller_location,
) -> (id: Node_ID, clicked: bool) {
	if ui == nil || ui.runtime == nil { return }
	id = emit_key(
		ui,
		.Button,
		resolve_source(Source_Site{}, "tab_bar_scroll_button", loc),
		label=accessible_label,
		text=glyph,
		key=key,
		style=layout_style(.Row, width=width, height=height, align=.Center),
		focusable=true,
		disabled=disabled,
		button_variant=.Toolbar,
	)
	return id, id != 0 && !disabled && consume_activation(ui.runtime, id)
}

tab_bar_pending_button_disabled_set :: proc(rt: ^Runtime, id: Node_ID, disabled: bool) {
	if rt == nil || id == 0 { return }
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		pending := &rt.pending[index]
		if pending.kind == .Description && pending.description.id == id {
			pending.description.disabled = disabled
			return
		}
	}
}

tab_bar_pending_scroll_set :: proc(rt: ^Runtime, scroll_id: Node_ID, offset_x, content_width: f32) {
	if rt == nil { return }
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		pending := &rt.pending[index]
		if pending.kind != .Description { continue }
		if pending.description.id == scroll_id {
			pending.description.scroll_content_width = content_width
			pending.description.scroll_offset_x = offset_x
			pending.description.layout_scroll_offset_x = 0
		} else if pending.description.kind == .Virtual_List && pending.description.parent == scroll_id {
			pending.description.scroll_offset_x = offset_x
			pending.description.layout_scroll_offset_x = offset_x
		}
	}
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
	hovered := tab.hovered || close.hovered || close.pressed
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
