package alicorn

import "core:fmt"

TAB_CLOSE_SLOT_WIDTH :: f32(28)
TAB_CLOSE_CONTROL_SIZE :: f32(24)
TAB_AUTO_CLOSE_ALWAYS_WIDTH :: f32(156)
TAB_BAR_SCROLL_CONTROL_WIDTH :: f32(22)

Tab_Bar_Item :: struct {
	key:         UI_Key,
	label:       string,
	label_italic: bool,
	label_muted:  bool,
	tooltip:     string,
	selected:    bool,
	closable:    bool,
	dirty:       bool,
	semantic_id: Semantic_ID,
}

Tab_Bar_Presentation :: enum { Standard = 0, Compact }

Tab_Bar_Appearance :: enum { Standard = 0, Connected }

Tab_Bar_Options :: struct {
	min_tab_width: f32,
	max_tab_width: f32,
	height:        f32,
	gap:           f32,
	close_policy:  Tab_Close_Policy,
	drag_type:     Drag_Type,
	presentation:  Tab_Bar_Presentation,
	appearance:    Tab_Bar_Appearance,
	// Applications resolve their controlled surface's theme separately from
	// the workbench environment containing the tabs.
	selected_fill: Color,
	selected_text: Color,
	selected_fill_set: bool,
}

DEFAULT_TAB_BAR_OPTIONS :: Tab_Bar_Options{
	min_tab_width=84,
	max_tab_width=220,
	height=34,
	gap=1,
	close_policy=.Auto,
}

DEFAULT_TAB_BAR_STYLE :: Layout_Style{
	direction=.Column,
	width=-1,
	height=38,
	min_width=0,
	max_width=-1,
	min_height=0,
	max_height=-1,
	align=.Stretch,
	clip=true,
}

// Connected tabs share one contour; selection changes their paint treatment
// and visual depth without changing their retained bounds or hit targets.
CONNECTED_TAB_INACTIVE_DROP :: f32(3)

connected_tab_visual_bounds :: proc(bounds: Rect, selected: bool) -> Rect {
	if selected { return bounds }
	drop := minf(CONNECTED_TAB_INACTIVE_DROP, maxf(bounds.h, 0))
	return Rect{bounds.x, bounds.y+drop, bounds.w, maxf(bounds.h-drop, 0)}
}

connected_tab_visual_colors :: proc(
	rt: ^Runtime,
	node: ^Node,
	resolved: Button_Resolved_Style,
	hovered: bool,
	pressed: bool,
	drop_target_on: bool,
) -> (fill, text: Color) {
	if rt == nil || node == nil { return }
	fill = style_color_mix(
		style_environment_color(rt, node.style_environment, .Window_Background),
		resolved.surface,
		0.68,
	)
	// Tab's shared recipe intentionally keeps a transparent surface. Use its
	// themed workbench channels for the contour, then add only a small state
	// cue so inactive tabs stay recessed without becoming indistinguishable.
	fill.a = 1
	if hovered { fill = style_color_mix(fill, style_environment_color(rt, node.style_environment, .Border), 0.12) }
	if pressed { fill = style_color_mix(fill, style_environment_color(rt, node.style_environment, .Border), 0.28) }
	if drop_target_on { fill = style_color_mix(fill, style_environment_color(rt, node.style_environment, .Success), 0.32) }
	text = resolved.text
	if node.selected {
		if surface, exists := rt.semantic_surfaces[node.id]; exists && surface.shape.kind == .Connected_Tab {
			if surface.fill_override_set {
				fill = surface.fill_override
			} else if role_color, role_ok := semantic_surface_role_resolve(rt, node.style_environment, surface.role); role_ok {
				fill = role_color
			}
		}
		text = node.color
	}
	if node.style_environment.accessibility.increased_contrast {
		text = style_contrast_fallback(text, fill, 4.5)
	}
	return
}

Tab_Bar_Action :: enum { None, Select, Close }

Tab_Bar_Result :: struct {
	action:     Tab_Bar_Action,
	item_index: int,
	// Stable visual identity for a surface's optional open_top_edge link.
	selected_tab: Node_ID,
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
	compact := opts.presentation == .Compact
	connected_appearance := opts.appearance == .Connected
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

	outer_id := container_begin_simple(
		ui,
		.Container,
		label="tab-bar-control",
		key=key,
		style=bar_style,
		loc=loc,
	)
	if outer_id == 0 { return result }
	previous_selection_hash: u64 = 0
	previous_state_valid := false
	previous_scroll_width: f32 = 0
	previous_content_width: f32 = 0
	previous_offset_x: f32 = 0
	if previous_bar, found := rt.nodes[outer_id]; found && previous_bar.active {
		if previous_bar.kind == .Container {
			previous_selection_hash = previous_bar.paint_value
			previous_state_valid = true
			for child_id in previous_bar.children {
				if child, child_found := rt.nodes[child_id]; child_found && child.kind == .Scroll_Region {
					previous_scroll_width = child.scroll_viewport_width
					previous_content_width = child.scroll_content_width
					previous_offset_x = child.scroll_offset_x
					break
				}
			}
		} else if previous_bar.kind == .Scroll_Region {
			// One-time compatibility with a tab bar retained by the pre-composite
			// structure. Its current selected state will be initialized below.
			previous_scroll_width = previous_bar.scroll_viewport_width
			previous_content_width = previous_bar.scroll_content_width
			previous_offset_x = previous_bar.scroll_offset_x
		}
	}
	outer_pending := &rt.pending[len(rt.pending)-1].description
	outer_pending.paint_value = selected_state_hash
	selected_semantic_id := Semantic_ID{}
	collection := semantic_collection_begin(
		ui,
		outer_id,
		semantic_visual_id(outer_id),
		.Tab_List,
		"Open documents",
		u64(len(items)),
		realized_first=0,
		realized_last=u64(len(items)),
	)

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
	if connected_appearance { scroll_style.width, scroll_style.grow = -1, 1 }
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
	selection_visibility_pending := selected_index >= 0 && tab_width > 0 && (selection_changed || viewport_changed || content_changed)
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
		// Selection remains an ordinary Button interaction. Its content, close
		// action, dirty mark and underline are inspectable retained visual parts.
		tab_id, tab_activated := button_begin(
			ui,
			"",
			key=item.key,
			style=layout_style(.Column, width=tab_width, height=opts.height, gap=0,
				align=.Center if compact else .Stretch, clip=true),
			state=Button_State{selected=item.selected},
			loc=loc,
			text_style=DEFAULT_BUTTON_TEXT_STYLE,
			content_style=button_content_style(.Start, padding_x=0, padding_y=0),
			variant=.Tab,
		)
		if tab_id == 0 { continue }
		if item.selected { result.selected_tab = tab_id }
		if len(item.tooltip) > 0 { _ = tooltip(ui, item.tooltip) }
		_ = visual_part_attach(ui, tab_id, tab_id, visual_part_core(.Surface))
		pending := &rt.pending[len(rt.pending)-1].description
		// Keep the fixed-size description contract compact by encoding the
		// tab-only presentation flags in the existing paint state word.
		pending.paint_value |= u64(opts.close_policy) << 1
		pending.paint_value |= 1 << 5 // selected underline is a composed surface part
		if item.closable { pending.paint_value |= 1 << 3 }
		if item.dirty { pending.paint_value |= 1 << 4 }
		connected_shape := connected_appearance
		selected_connected := connected_shape && item.selected
		connected_ink := style_color(ui, .Muted_Text)
		if connected_shape {
			fill := style_color(ui, .Surface)
			ink := style_color(ui, .Text)
			fill_override_set := false
			if selected_connected && opts.selected_fill_set && semantic_surface_color_is_valid(opts.selected_fill) && semantic_surface_color_is_valid(opts.selected_text) {
				fill, ink = opts.selected_fill, opts.selected_text
				fill_override_set = true
			}
			rt.pending[len(rt.pending)-1].semantic_surface_style = Semantic_Surface_Style{
				defined=true, role=surface_core_color_role(.Surface),
				fill_override=fill, fill_override_set=fill_override_set,
				shape=Surface_Shape{kind=.Connected_Tab},
			}
			if selected_connected {
				if !fill_override_set { fill, ink = style_color(ui, .Surface), style_color(ui, .Text) }
				if rt.style_environment.accessibility.increased_contrast { ink = style_contrast_fallback(ink, fill, 4.5) }
				pending.color = ink
				connected_ink = ink
			}
		}
		item_semantic_id := item.semantic_id
		if !semantic_id_is_valid(item_semantic_id) { item_semantic_id = semantic_visual_id(tab_id) }
		pending.semantic_id = item_semantic_id
		tab_states := rt.pending[len(rt.pending)-1].semantic.states
		if item.dirty { tab_states = semantic_states_add(tab_states, .Modified) }
		_ = semantic_collection_item(ui, collection, u64(index), Semantic_Node_Description{
			id=item_semantic_id,
			role=.Tab,
			label=item.label,
			states=tab_states,
			actions=semantic_actions_add({}, .Select),
		})
		if item.selected { selected_semantic_id = item_semantic_id }
		if opts.drag_type != Drag_Type(0) && semantic_id_is_valid(item.semantic_id) {
			_ = drag_source(ui, opts.drag_type, item.semantic_id)
			_ = drop_target(ui, opts.drag_type, item.semantic_id, .Between_Horizontal)
		}
		if tab_activated && result.action == .None { result.action, result.item_index = .Select, index }

		// Equal top and selected-indicator tracks center the content in the tab.
		track_height := f32(1 if compact else 2)
		_ = container_begin_simple(
			ui,
			.Container,
			label="tab-content-top-inset",
			key=key_u64(7),
			style=layout_style(.Row, height=track_height),
		)
		container_end(ui)
		content_height := maxf(opts.height-2*track_height, 0)
		content_id := container_begin_simple(
			ui,
			.Container,
			label="tab-content",
			key=key_u64(1),
			style=layout_style(.Row, width=maxf(tab_width-(40 if connected_appearance else 16), 0) if compact else tab_width,
				height=content_height, gap=0, align=.Center, clip=true, padding=0 if compact else 8),
		)
		_ = visual_part_attach(ui, content_id, tab_id, visual_part_core(.Content))
		label_style := DEFAULT_BUTTON_TEXT_STYLE
		label_layout := layout_style(.Row, height=content_height, grow=1)
		if compact {
			// A Column measures the label's intrinsic height; main-axis centering
			// then aligns the actual text run with the existing 24-unit close target.
			_ = container_begin_simple(ui, .Container, label="tab-label-slot", key=key_u64(8),
				style=layout_style(.Column, height=content_height, grow=1, justify=.Center))
			label_layout = layout_style(.Row)
		}
		label_id := text(ui, item.label, key=key_u64(2), style=label_layout, font=Font_Role.UI, text_style=label_style)
		if item.label_italic && len(item.label) > 0 {
			italic_span := make([dynamic]Text_Style_Span, 0, 1, allocator=context.temp_allocator)
			append(&italic_span, Text_Style_Span{start=0, end=len(item.label), italic=true, italic_set=true})
			_ = text_style_spans(ui, label_id, italic_span[:])
		}
		if item.label_muted && !selected_connected && len(item.label) > 0 {
			muted_span := make([dynamic]Text_Paint_Span, 0, 1, allocator=context.temp_allocator)
			append(&muted_span, Text_Paint_Span{
				start=0,
				end=len(item.label),
				color=style_color(ui, .Muted_Text),
				color_set=true,
			})
			_ = text_paint_spans(ui, label_id, muted_span[:])
		}
		_ = visual_part_attach(ui, label_id, tab_id, visual_part_core(.Label))
		if compact { container_end(ui) }

		trailing_width := f32(0)
		close_width := TAB_CLOSE_CONTROL_SIZE
		dirty_close_reveal := item.dirty && item.closable && opts.close_policy != .Always
		if item.closable {
			if dirty_close_reveal { close_width = TAB_CLOSE_SLOT_WIDTH }
			trailing_width = close_width
		}
		else if item.dirty { trailing_width = 16 }
		if trailing_width > 0 {
			trailing := container_begin_simple(
				ui,
				.Container,
				label="tab-trailing-parts",
				key=key_u64(3),
				style=layout_style(.Row, width=trailing_width, height=content_height, gap=0, align=.Center),
			)
			_ = visual_part_attach(ui, trailing, tab_id, visual_part_core(.Content))
			if item.dirty && !item.closable {
				marker_id := surface_begin(
					ui,
					surface_core_color_role(.Accent),
					key=key_u64(4),
					style=layout_style(.Row, width=4, height=4),
					label="tab-dirty-indicator",
				)
				_ = visual_part_attach(ui, marker_id, tab_id, visual_part_core(.Indicator))
				surface_end(ui)
			}
			if item.closable {
				close_visibility := Visual_Part_Visibility.Always
				if !dirty_close_reveal {
					switch opts.close_policy {
					case .Always: close_visibility = .Always
					case .Hover: close_visibility = .Owner_Hovered
					case .Selected_Or_Hover: close_visibility = .Owner_Selected_Or_Hovered
					case .Auto:
						if tab_width < TAB_AUTO_CLOSE_ALWAYS_WIDTH { close_visibility = .Owner_Hovered }
				}
				}
				close_id, close_activated := button_begin(
					ui,
					"×" if !dirty_close_reveal && !connected_shape else "",
					key=key_u64(5),
					style=layout_style(.Row, width=close_width, height=TAB_CLOSE_CONTROL_SIZE, align=.Center),
					text_style=DEFAULT_BUTTON_TEXT_STYLE,
					content_style=button_content_style(padding_x=0, padding_y=0),
					variant=.Quiet,
					focusable=false,
				)
				if close_id != 0 {
					_ = semantic_description(ui, .Button, fmt.tprintf("Close %s", item.label),
						actions=semantic_actions_add({}, .Press))
				}
				_ = visual_part_attach(ui, close_id, tab_id, visual_part_core(.Overlay), close_visibility,
					reveal_on_direct_hover=dirty_close_reveal)
				if close_activated && result.action == .None { result.action, result.item_index = .Close, index }
				if connected_shape && !dirty_close_reveal {
					glyph := text(ui, "×", key=key_u64(1), style=layout_style(.Row, width=close_width, height=TAB_CLOSE_CONTROL_SIZE, align=.Center), text_style=DEFAULT_BUTTON_TEXT_STYLE)
					_ = visual_part_attach(ui, glyph, tab_id, visual_part_core(.Label))
				}
				if dirty_close_reveal {
					close_content := container_begin_simple(
						ui,
						.Container,
						label="tab-close-content",
						key=key_u64(1),
						style=layout_style(.Row, width=close_width, height=TAB_CLOSE_CONTROL_SIZE, gap=0, align=.Center),
					)
					_ = visual_part_attach(ui, close_content, close_id, visual_part_core(.Content))
					marker_id := surface_begin(
						ui,
						surface_core_color_role(.Accent),
						key=key_u64(2),
						style=layout_style(.Row, width=4, height=4),
						label="tab-dirty-indicator",
					)
					_ = visual_part_attach(ui, marker_id, close_id, visual_part_core(.Indicator), .Owner_Not_Hovered)
					surface_end(ui)
					glyph_id := text(ui, "×", key=key_u64(3),
						style=layout_style(.Row, width=TAB_CLOSE_CONTROL_SIZE, height=TAB_CLOSE_CONTROL_SIZE, align=.Center),
						text_style=DEFAULT_BUTTON_TEXT_STYLE)
					_ = visual_part_attach(ui, glyph_id, close_id, visual_part_core(.Label), .Owner_Hovered)
					if selected_connected {
						span := [1]Text_Paint_Span{{start=0,end=2,color=connected_ink,color_set=true}}
						_ = text_paint_spans(ui,glyph_id,span[:])
					}
					container_end(ui)
				}
				button_end(ui)
			}
			container_end(ui)
		}
		container_end(ui)
		indicator_id := surface_begin(
			ui,
			surface_core_color_role(.Accent),
			key=key_u64(6),
			style=layout_style(.Row, height=track_height if item.selected && !selected_connected else 0),
			label="tab-selected-indicator",
		)
		_ = visual_part_attach(ui, indicator_id, tab_id, visual_part_core(.Selected_Indicator))
		surface_end(ui)
		button_end(ui)
	}
	container_end(ui)
	scroll_region_end(ui)
	// Tabs expose selection as their active state. A separate Current state is
	// redundant for TabList semantics and can cause duplicate AT announcements.
	_ = semantic_collection_selection_set(ui, outer_id, selected_semantic_id, {})
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
			selection_visibility_pending = false
			offset_x = minf(offset_x+maxf(viewport_width*0.75, opts.min_tab_width+opts.gap), maxf(content_width-viewport_width, 0))
			tab_bar_pending_scroll_set(rt, scroll.id, offset_x, content_width)
		}
		tab_bar_pending_button_disabled_set(rt, left_scroll_id, offset_x <= 0)
		tab_bar_pending_button_disabled_set(rt, right_scroll_id, offset_x >= maxf(content_width-viewport_width, 0))
	}
	if left_scroll_clicked { selection_visibility_pending = false }
	if selection_visibility_pending {
		left := f32(selected_index)*(tab_width+opts.gap)
		scroll_region_request_visible_range_x(rt, scroll.id, left, left+tab_width)
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
	id, clicked = button_begin(
		ui,
		"",
		key=key,
		style=layout_style(.Row, width=width, height=height, align=.Center),
		state=Button_State{disabled=disabled},
		loc=loc,
		content_style=button_content_style(padding_x=0, padding_y=0),
		variant=.Toolbar,
	)
	if id == 0 { return }
	actions := Semantic_Actions{}
	states := Semantic_States{}
	if !disabled { actions = semantic_actions_add(actions, .Press) }
	if disabled { states = semantic_states_add(states, .Disabled) }
	_ = semantic_description(ui, .Button, accessible_label, states=states, actions=actions)
	glyph_id := text(
		ui,
		glyph,
		key=key_u64(1),
		style=layout_style(.Row, grow=1, height=height, align=.Center),
		font=Font_Role.UI,
		text_style=DEFAULT_BUTTON_TEXT_STYLE,
	)
	_ = visual_part_attach(ui, glyph_id, id, visual_part_core(.Label))
	button_end(ui)
	return
}

tab_bar_pending_button_disabled_set :: proc(rt: ^Runtime, id: Node_ID, disabled: bool) {
	if rt == nil || id == 0 { return }
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		pending := &rt.pending[index]
		if pending.kind == .Description && pending.description.id == id {
			pending.description.disabled = disabled
			if disabled {
				pending.semantic.states = semantic_states_add(pending.semantic.states, .Disabled)
				pending.semantic.actions -= {.Press}
			} else {
				pending.semantic.states = semantic_states_remove(pending.semantic.states, .Disabled)
				pending.semantic.actions = semantic_actions_add(pending.semantic.actions, .Press)
			}
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

tab_bar_viewport_guess :: proc(ui: ^UI, style: Layout_Style) -> f32 {
	if style.width > 0 { return maxf(style.width-2*maxf(style.padding, 0), 0) }
	if parent_id := current_node_parent(ui); parent_id != 0 {
		if parent, found := ui.runtime.nodes[parent_id]; found && parent.bounds.w > 0 {
			return maxf(parent.bounds.w-2*maxf(parent.style.padding, 0)-2*maxf(style.padding, 0), 0)
		}
	}
	return 320
}
