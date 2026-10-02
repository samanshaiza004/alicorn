package alicorn
import "core:fmt"
import "core:math"

// Split_Handle is a lightweight description-time handle for one retained
// two-pane split. Its position and drag state live on the keyed runtime node.
Split_Handle :: struct {
	id:       Node_ID,
	axis:     Split_Axis,
	position: f32,
}

DEFAULT_SPLIT_STYLE :: Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 1, 0, 0, .Stretch, true}
SPLIT_DIVIDER_MIN_THICKNESS :: 1.0
SPLIT_DIVIDER_MAX_THICKNESS :: 4.0
SPLIT_DIVIDER_MIN_HIT_SIZE :: 8.0
SPLIT_DIVIDER_MAX_HIT_SIZE :: 12.0

// split_begin opens a keyed split container. Compose two panes with
// split_first_begin/end and split_second_begin/end, placing split_divider
// between them, then close the split with split_end. The preferred position
// seeds new retained state; later application builds preserve the user's drag.
split_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	axis: Split_Axis,
	initial: f32,
	min_first: f32 = 0,
	min_second: f32 = 0,
	style := DEFAULT_SPLIT_STYLE,
	label := "split",
	loc := #caller_location,
) -> Split_Handle {
	split_style := style
	split_style.direction = .Row if axis == .Horizontal else .Column
	source := resolve_source(Source_Site{}, "split", loc)
	id := emit_key(ui, .Split, source, label=label, key=key, style=split_style, paint_background=false)
	if id == 0 { return {} }
	item := &ui.runtime.pending[len(ui.runtime.pending)-1].description
	item.split_axis = axis
	item.split_position = maxf(initial, 0)
	item.split_min_first = maxf(min_first, 0)
	item.split_min_second = maxf(min_second, 0)
	append(&ui.runtime.stack, id)
	push_identity_scope(ui.runtime, id, "", 0)
	position := item.split_position
	if previous, ok := ui.runtime.nodes[id]; ok && previous.kind == .Split {
		position = previous.split_position
	}
	return Split_Handle{id, axis, position}
}

split_first_begin :: proc(ui: ^UI, split: Split_Handle) -> Node_ID {
	return container_begin_simple(
		ui, .Container, label="split-first", key=key_string("first"),
		style=layout_style(grow=1, clip=true),
	)
}

split_first_end :: proc(ui: ^UI, split: Split_Handle) { container_end(ui) }

split_second_begin :: proc(ui: ^UI, split: Split_Handle) -> Node_ID {
	return container_begin_simple(
		ui, .Container, label="split-second", key=key_string("second"),
		style=layout_style(grow=1, clip=true),
	)
}

split_second_end :: proc(ui: ^UI, split: Split_Handle) { container_end(ui) }

// split_divider inserts the runtime-owned interaction target between the two
// panes. Visual thickness is kept narrow while hit_size makes it easy to grab.
split_divider :: proc(ui: ^UI, split: Split_Handle, thickness: f32 = 2, hit_size: f32 = 10, loc := #caller_location) -> Node_ID {
	if split.id == 0 { return 0 }
	visible_thickness := clampf(thickness, SPLIT_DIVIDER_MIN_THICKNESS, SPLIT_DIVIDER_MAX_THICKNESS)
	interaction_size := clampf(hit_size, SPLIT_DIVIDER_MIN_HIT_SIZE, SPLIT_DIVIDER_MAX_HIT_SIZE)
	style := layout_style(width=visible_thickness, height=-1) if split.axis == .Horizontal else layout_style(width=-1, height=visible_thickness)
	id := emit_key(ui, .Split_Handle, resolve_source(Source_Site{}, "split_divider", loc), label="split-divider", key=key_string("divider"), style=style)
	if id != 0 {
		description := &ui.runtime.pending[len(ui.runtime.pending)-1].description
		description.split_owner = split.id
		description.split_axis = split.axis
		description.split_handle_size = visible_thickness
		description.split_hit_size = maxf(interaction_size, visible_thickness)
	}
	return id
}

split_end :: proc(ui: ^UI, split: Split_Handle) { container_end(ui) }

root :: proc(ui: ^UI, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return root_simple(ui, body, style, loc)
}

// Scroll_Region_Handle is the resolved, retained state of a fixed-height
// scroll region. The offset is owned by the runtime; applications use the
// handle only to virtualize their content during the current description.
Scroll_Region_Handle :: struct {
	id:              Node_ID,
	offset_y:        f32,
	offset_x:        f32,
	viewport_height: f32,
	viewport_width:  f32,
	content_height:  f32,
	content_width:   f32,
	max_scroll_y:    f32,
	max_scroll_x:    f32,
	viewport_bounds: Rect,
	vertical_bar_visible: bool,
	horizontal_bar_visible: bool,
}

scroll_region_begin :: proc(
	ui: ^UI,
	key: UI_Key = UI_Unkeyed{},
	viewport_height: f32 = 0,
	content_height: f32 = 0,
	line_height: f32 = 24,
	viewport_width: f32 = 0,
	content_width: f32 = 0,
	line_width: f32 = 24,
	style := DEFAULT_STYLE,
	color := NO_BACKGROUND_COLOR,
	label := "scroll-region",
	loc := #caller_location,
	axes := Scroll_Axes.Both,
	axis_behavior := Scroll_Axis_Behavior.Auto_Lock,
	scrollbars := Scrollbar_Policy.Auto,
	focusable := false,
) -> Scroll_Region_Handle {
	rt := ui.runtime
	resolved_source := resolve_source(Source_Site{}, "scroll_region", loc)
	resolved_color, paints := resolve_container_color(.Scroll_Region, color)
	resolved_viewport := viewport_height
	if resolved_viewport <= 0 {
		if style.height >= 0 { resolved_viewport = style.height }
		if resolved_viewport <= 0 { resolved_viewport = 180 }
	}
	resolved_width := viewport_width
	if resolved_width <= 0 {
		if style.width >= 0 { resolved_width = style.width }
		if resolved_width <= 0 { resolved_width = 320 }
	}
	outer_height, outer_width := resolved_viewport, resolved_width
	geometry := scroll_bar_geometry(Rect{0, 0, outer_width, outer_height}, content_width, content_height, style.padding, axes, scrollbars)
	resolved_viewport = geometry.viewport.h
	resolved_width = geometry.viewport.w
	max_scroll := maxf(content_height-resolved_viewport, 0)
	max_scroll_x := maxf(content_width-resolved_width, 0)
	id := emit_key(
		ui, .Scroll_Region, resolved_source, label=label, key=key,
		style=style, color=resolved_color, paint_background=paints, focusable=focusable,
		scroll_content_height=content_height,
		scroll_viewport_height=resolved_viewport,
		scroll_line_height=line_height,
		scroll_content_width=content_width,
		scroll_viewport_width=resolved_width,
		scroll_line_width=line_width,
		scroll_axes=axes,
		scroll_axis_behavior=axis_behavior,
	)
	if id == 0 { return {} }
	last := len(rt.pending)-1
	if last >= 0 && rt.pending[last].kind == .Description && rt.pending[last].description.id == id {
		rt.pending[last].description.scrollbar_policy = scrollbars
	}
	// A description is emitted before layout resolves the new bounds. Reuse
	// the previous retained offset so a rebuild does not jump to the top.
	offset_y := f32(0)
	offset_x := f32(0)
	if previous, ok := rt.nodes[id]; ok {
		// An explicit viewport is authoritative (useful for fixed layouts and
		// resize tests). Grow-based regions pass zero and reuse the last
		// resolved layout height until the new layout has run.
		if viewport_height <= 0 && style.height < 0 && previous.bounds.h > 0 {
			outer_height = previous.bounds.h
		}
		if viewport_width <= 0 && style.width < 0 && previous.bounds.w > 0 {
			outer_width = previous.bounds.w
		}
		geometry = scroll_bar_geometry(Rect{0, 0, outer_width, outer_height}, content_width, content_height, style.padding, axes, scrollbars, previous.scroll_offset_x, previous.scroll_offset_y)
		resolved_viewport = geometry.viewport.h
		resolved_width = geometry.viewport.w
		offset_y = clampf(previous.scroll_offset_y, 0, maxf(content_height-resolved_viewport, 0))
		offset_x = clampf(previous.scroll_offset_x, 0, maxf(content_width-resolved_width, 0))
		max_scroll = maxf(content_height-resolved_viewport, 0)
		max_scroll_x = maxf(content_width-resolved_width, 0)
	}
	last = len(rt.pending)-1
	if last >= 0 && rt.pending[last].kind == .Description && rt.pending[last].description.id == id {
		rt.pending[last].description.scroll_offset_y = offset_y
		rt.pending[last].description.scroll_viewport_height = resolved_viewport
		rt.pending[last].description.layout_scroll_offset_y = 0
		rt.pending[last].description.scroll_offset_x = offset_x
		rt.pending[last].description.scroll_viewport_width = resolved_width
		rt.pending[last].description.layout_scroll_offset_x = 0
	}
	append(&rt.stack, id)
	push_identity_scope(rt, id, "", 0)
	return Scroll_Region_Handle{
		id=id,
		offset_y=offset_y,
		offset_x=offset_x,
		viewport_height=resolved_viewport,
		viewport_width=resolved_width,
		content_height=content_height,
		content_width=content_width,
		max_scroll_y=max_scroll,
		max_scroll_x=max_scroll_x,
		vertical_bar_visible=geometry.vertical_visible,
		horizontal_bar_visible=geometry.horizontal_visible,
	}
}

scroll_region_end :: proc(ui: ^UI) {
	container_end(ui)
}

scroll_region_offset :: proc(rt: ^Runtime, id: Node_ID) -> f32 {
	if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region { return node.scroll_offset_y }
	return 0
}

scroll_region_offset_x :: proc(rt: ^Runtime, id: Node_ID) -> f32 {
	if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region { return node.scroll_offset_x }
	return 0
}

// scroll_region_state exposes the retained geometry needed by event handlers
// and other explicit application commands. It does not expose the retained
// node or transfer ownership of any runtime state.
scroll_region_state :: proc(rt: ^Runtime, id: Node_ID) -> Scroll_Region_Handle {
	if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region {
		viewport_height := node.scroll_viewport_height
		if viewport_height <= 0 && !node.scroll_geometry_resolved { viewport_height = node.bounds.h }
		viewport_width := node.scroll_viewport_width
		if viewport_width <= 0 && !node.scroll_geometry_resolved { viewport_width = node.bounds.w }
		return Scroll_Region_Handle{
			id = id,
			offset_y = node.scroll_offset_y,
			offset_x = node.scroll_offset_x,
			viewport_height = viewport_height,
			viewport_width = viewport_width,
			content_height = node.scroll_content_height,
			content_width = node.scroll_content_width,
			max_scroll_y = maxf(node.scroll_content_height-viewport_height, 0),
			max_scroll_x = maxf(node.scroll_content_width-viewport_width, 0),
			viewport_bounds = node.scroll_viewport_bounds,
			vertical_bar_visible = node.scrollbar_vertical_visible,
			horizontal_bar_visible = node.scrollbar_horizontal_visible,
		}
	}
	return {}
}

scroll_region_set_offset :: proc(rt: ^Runtime, id: Node_ID, offset_y: f32, reason := "scroll region offset changed") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region { return false }
	viewport := node.scroll_viewport_height
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.h }
	max_scroll := maxf(node.scroll_content_height-viewport, 0)
	next := clampf(offset_y, 0, max_scroll)
	if next == node.scroll_offset_y { return false }
	node.scroll_offset_y = next
	invalidate_root(rt, reason)
	return true
}

scroll_region_set_offset_x :: proc(rt: ^Runtime, id: Node_ID, offset_x: f32, reason := "horizontal scroll region offset changed") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region { return false }
	viewport := node.scroll_viewport_width
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.w }
	max_scroll := maxf(node.scroll_content_width-viewport, 0)
	next := clampf(offset_x, 0, max_scroll)
	if next == node.scroll_offset_x { return false }
	node.scroll_offset_x = next
	node.layout_scroll_offset_x = next
	invalidate_root(rt, reason)
	return true
}

// virtual_list_ensure_visible is the intent-level companion to
// virtual_list_begin. The retained region already knows its fixed row height
// and viewport, so selection/navigation code need not duplicate scroll math.
virtual_list_ensure_visible :: proc(rt: ^Runtime, id: Node_ID, index: int, reason := "virtual list selection visibility changed") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region || index < 0 { return false }
	row_height := node.scroll_line_height
	if row_height <= 0 { return false }
	viewport := node.scroll_viewport_height
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.h }
	if viewport <= 0 { return false }
	top := f32(index) * row_height
	bottom := top + row_height
	next := node.scroll_offset_y
	if top < next {
		next = top
	} else if bottom > next+viewport {
		next = bottom-viewport
	}
	return scroll_region_set_offset(rt, id, next, reason)
}

button_ex :: proc(ui: ^UI, label: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location, text_style := DEFAULT_BUTTON_TEXT_STYLE, content_style := DEFAULT_BUTTON_CONTENT_STYLE) -> (id: Node_ID, clicked: bool) {
	resolved_source := resolve_source(source, "button", loc)
	id = emit(ui, .Button, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value, focusable=true, text_style=text_style, button_content=content_style)
	clicked = consume_activation(ui.runtime, id)
	return
}

text_ex :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	resolved_source := resolve_source(source, "text", loc)
	return emit(ui, .Text, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value, font=font, text_style=text_style)
}

// text_interaction opts the just-emitted Text node into retained selection and
// caret decoration. anchor and focus are UTF-8 byte offsets local to that
// node's text, with affinity disambiguating visual boundaries. Their direction
// is preserved as supplied. The selection is painted regardless of keyboard
// focus; show_caret independently controls whether a caret is painted at focus.
// Geometry and both decorations use the Text node's one retained Runa run.
text_interaction :: proc(ui: ^UI, id: Node_ID, anchor, focus: Text_Position, show_caret: bool) -> bool {
	rt := ui.runtime
	if rt == nil || !rt.frame_open || id == 0 || len(rt.pending) == 0 { return false }
	item := &rt.pending[len(rt.pending)-1]
	if item.kind != .Description || item.description.id != id || item.description.kind != .Text {
		return false
	}
	item.description.text_interaction = true
	item.description.text_interaction_anchor = anchor
	item.description.text_interaction_focus = focus
	item.description.text_interaction_show_caret = show_caret
	return true
}

// visual_row_background paints one shaped visual row behind an editor row
// container. The row can be wider than the text node, so the same call may be
// made for the source lane and its gutter. The text node's retained Text_Run
// supplies wrapped-row geometry; no paint-span byte slicing is involved.
visual_row_background :: proc(ui: ^UI, row, text: Node_ID, position: Text_Position, color: Color) -> bool {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open || row == 0 || text == 0 || position.byte < 0 { return false }
	rt := ui.runtime
	row_index, text_index := -1, -1
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := rt.pending[index]
		if item.kind != .Description { continue }
		if item.description.id == row { row_index = index }
		if item.description.id == text { text_index = index }
		if row_index >= 0 && text_index >= 0 { break }
	}
	if row_index < 0 || text_index < 0 { return false }
	row_description := &rt.pending[row_index].description
	text_description := rt.pending[text_index].description
	if text_description.kind != .Text { return false }
	if row_description.kind != .Container && row_description.kind != .Virtual_Row && row_description.kind != .Virtual_List {
		return false
	}
	row_description.visual_row_text_node = text
	row_description.visual_row_position = position
	row_description.visual_row_color = color
	row_description.visual_row_enabled = true
	return true
}

// text_paint_spans assigns the ordered span list to the just-emitted Text
// description. Offsets are half-open UTF-8 byte offsets into its displayed
// string. Later spans win for foreground and background; underline and strike
// are additive. The runtime copies the borrowed slice during reconcile.
text_paint_spans :: proc(ui: ^UI, id: Node_ID, spans: []Text_Paint_Span) -> bool {
	rt := ui.runtime
	if rt == nil || !rt.frame_open || id == 0 || len(rt.pending) == 0 { return false }
	item := &rt.pending[len(rt.pending)-1]
	if item.kind != .Description || item.description.id != id || item.description.kind != .Text { return false }
	item.description.text_paint_spans = spans
	return true
}

// text_style_spans assigns shaping-aware typography ranges to the just-emitted
// Text node. Byte offsets refer to its UTF-8 text; spans are retained until the
// next frame and copied into runtime-owned storage during reconciliation.
text_style_spans :: proc(ui: ^UI, id: Node_ID, spans: []Text_Style_Span) -> bool {
	rt := ui.runtime
	if rt == nil || !rt.frame_open || id == 0 || len(rt.pending) == 0 { return false }
	item := &rt.pending[len(rt.pending)-1]
	if item.kind != .Description || item.description.id != id || item.description.kind != .Text {
		return false
	}
	item.description.text_style_spans = spans
	return true
}

text_field_ex :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	resolved_source := resolve_source(source, "text_field", loc)
	return emit(ui, .Text_Field, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, focusable=true, font=font, text_style=text_style)
}

consume_activation :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if id == 0 || rt.activation_node != id || rt.activation_sequence == 0 { return false }
	if node, ok := rt.nodes[id]; ok && node.last_consumed_activation < rt.activation_sequence {
		node.last_consumed_activation = rt.activation_sequence
		// Activation is an event, not retained state. Clear it globally so a
		// later incarnation of this keyed node cannot replay the same click.
		rt.activation_node = 0
		return true
	}
	return false
}

slider_normalize :: proc(value, minimum, maximum, step: f32) -> f32 {
	// Unlike layout's sentinel-aware clampf, slider ranges may legitimately be
	// entirely negative, so both bounds are always applied explicitly here.
	result := minf(maxf(value, minimum), maximum)
	// Keep the endpoints reachable even when the range is not an exact multiple
	// of the snapping increment (for example 0..1 with step 0.3).
	if result <= minimum || result >= maximum { return result }
	if step > 0 {
		steps := int((result-minimum)/step + 0.5)
		result = minf(maximum, minimum+f32(steps)*step)
	}
	return result
}

// checkbox is app-authoritative: store the returned value when changed. A
// focused checkbox activates with Space; pointer activation uses the same
// one-shot retained input path as button.
checkbox :: proc(
	ui: ^UI,
	label: string,
	checked: bool,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	disabled := false,
	loc := #caller_location,
) -> Control_Change_Bool {
	source := resolve_source(Source_Site{}, "checkbox", loc)
	paint_value: u64 = 0
	if checked { paint_value = 1 }
	id := emit_key(ui, .Checkbox, source, label=label, key=key, style=style, state_bits=paint_value, disabled=disabled, focusable=!disabled, text_style=DEFAULT_BUTTON_TEXT_STYLE)
	result := Control_Change_Bool{value=checked}
	if id == 0 || disabled { return result }
	if consume_activation(ui.runtime, id) {
		result.value = !checked
		result.changed = true
		ui.runtime.pending[len(ui.runtime.pending)-1].description.paint_value = 1 if result.value else 0
	}
	return result
}

// slider_f32 describes a horizontal, controlled slider. A zero step is
// continuous; arrow keys then move by one percent of the range. Positive
// steps quantize to the nearest step from `minimum` and clamp at both ends.
// Store the returned value when changed. Pointer coordinates and dimensions
// are logical units, so the control follows the runtime's DPI-independent
// layout contract.
slider_f32 :: proc(
	ui: ^UI,
	label: string,
	value, minimum, maximum: f32,
	step: f32 = 0,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	disabled := false,
	loc := #caller_location,
) -> Control_Change_F32 {
	result := Control_Change_F32{value=value}
	range := maximum-minimum
	if math.is_nan(minimum) || math.is_inf(minimum) || math.is_nan(maximum) || math.is_inf(maximum) ||
		math.is_nan(value) || math.is_inf(value) || math.is_nan(step) || math.is_inf(step) ||
		math.is_inf(range) || maximum <= minimum || step < 0 {
		append_diagnostic(ui.runtime, fmt.tprintf("slider_f32 requires a finite value, an increasing finite range, and a finite step >= 0 (got value=%.4f range=%.4f..%.4f step=%.4f).\nSuggestion: use step=0 for continuous input.", value, minimum, maximum, step))
		return result
	}
	result.value = slider_normalize(value, minimum, maximum, step)
	result.changed = result.value != value
	source := resolve_source(Source_Site{}, "slider_f32", loc)
	id := emit_key(ui, .Slider, source, label=label, key=key, style=style, disabled=disabled, focusable=!disabled, text_style=DEFAULT_BUTTON_TEXT_STYLE)
	if id == 0 { return result }
	if node, ok := ui.runtime.nodes[id]; ok && node.control_pending {
		result.value = slider_normalize(node.control_pending_value, minimum, maximum, step)
		result.changed = result.value != value
		node.control_pending = false
	}
	description := &ui.runtime.pending[len(ui.runtime.pending)-1].description
	description.control_value = result.value
	description.control_minimum = minimum
	description.control_maximum = maximum
	description.control_step = step
	return result
}

button_simple :: proc(ui: ^UI, label: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, state := Button_State{}, loc := #caller_location, text_style := DEFAULT_BUTTON_TEXT_STYLE, content_style := DEFAULT_BUTTON_CONTENT_STYLE) -> bool {
	resolved_source := resolve_source(Source_Site{}, "button", loc)
	paint_state: u64 = 0
	if state.selected { paint_state |= 1 }
	if state.disabled { paint_state |= 2 }
	if state.quiet { paint_state |= 4 }
	id := emit_key(ui, .Button, resolved_source, label=label, key=key, style=style, state_bits=paint_state, selected=state.selected, disabled=state.disabled, focusable=!state.disabled, text_style=text_style, button_content=content_style)
	if id == 0 || state.disabled { return false }
	return consume_activation(ui.runtime, id)
}

text_simple :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return emit_key(ui, .Text, resolve_source(Source_Site{}, "text", loc), text=value, key=key, style=style, font=font, text_style=text_style)
}

text_field_simple :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return emit_key(ui, .Text_Field, resolve_source(Source_Site{}, "text_field", loc), text=value, key=key, style=style, focusable=true, font=font, text_style=text_style)
}

button :: proc(ui: ^UI, label: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, state := Button_State{}, loc := #caller_location, text_style := DEFAULT_BUTTON_TEXT_STYLE, content_style := DEFAULT_BUTTON_CONTENT_STYLE) -> bool {
	return button_simple(ui, label, key, style, state, loc, text_style, content_style)
}

// semantic_bind associates the most recently described presentation node with
// an application-owned logical identity. Call it immediately after describing
// the widget; the identity is retained independently from that node's lifetime.
semantic_bind :: proc(ui: ^UI, id: Semantic_ID) -> bool {
	if !semantic_id_is_valid(id) { return false }
	rt := ui.runtime
	if len(rt.pending) == 0 { return false }
	last := len(rt.pending)-1
	if rt.pending[last].kind != .Description { return false }
	rt.pending[last].description.semantic_id = id
	return true
}

text :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return text_simple(ui, value, key, style, loc, font, text_style)
}

text_field :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return text_field_simple(ui, value, key, style, loc, font, text_style)
}

region_begin :: proc(ui: ^UI, key: string, revision: u64, source := Source_Site{}, style := DEFAULT_STYLE, loc := #caller_location) -> (id: Node_ID, reused: bool) {
	rt := ui.runtime
	resolved_source := resolve_source(source, "region", loc)
	id = emit(ui, .Container, resolved_source, label=key, key=key, explicit_key=true, style=style, region_revision=revision, is_region=true)
	if id == 0 {
		return 0, false
	}
	effective_revision := revision
	if old, ok := rt.nodes[id]; ok && old.region && revision < old.region_revision {
		append_diagnostic(rt, fmt.tprintf("region revision regressed for %q.\n  retained region: %s:%d:%d component=%q key=%q scope=%q revision=%d\n  new description: %s:%d:%d component=%q key=%q scope-depth=%d revision=%d\nSuggestion: keep the region revision monotonic; increment it when the region's logical output changes.", key, old.site.file, old.site.line, old.site.column, old.site.component, old.key, old.identity_key, old.region_revision, resolved_source.file, resolved_source.line, resolved_source.column, resolved_source.component, key, len(rt.identity_stack), revision))
		// Preserve the retained high-water revision so another stale description
		// cannot make the cache appear current on a later frame.
		effective_revision = old.region_revision
		rt.pending[len(rt.pending)-1].description.region_revision = effective_revision
	}
	if old, ok := rt.nodes[id]; ok && old.region && old.region_cached && old.region_revision == effective_revision {
		rt.stats.regions_skipped += 1
		rt.stats.retained_subtrees_reused += 1
		// The cached retained hierarchy is already authoritative. A marker is
		// enough to keep the subtree present; descendants are not copied into a
		// flat pending description list.
		append(&rt.pending, Pending_Item{.Reuse_Subtree, Description{}, id})
		record_trace(rt, .Reconcile, id, "retained subtree reused without descendant descriptions")
		return id, true
	}
	append(&rt.stack, id)
	push_identity_scope(rt, id, "", 0)
	return id, false
}

region_end :: proc(ui: ^UI, id: Node_ID, reused: bool, start: int) {
	if reused || id == 0 { return }
	pop(&ui.runtime.stack)
	pop_identity_scope(ui.runtime)
}

region_ex :: proc(ui: ^UI, key: string, revision: u64, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "region", loc)
	id, reused := region_begin(ui, key, revision, resolved_source, style)
	if !reused && id != 0 {
		start := len(ui.runtime.pending)
		body()
		region_end(ui, id, false, start)
	}
	return id
}

region_simple :: proc(ui: ^UI, key: string, revision: u64, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return region_ex(ui, key, revision, Source_Site{}, body, style, loc)
}

region :: proc(ui: ^UI, key: string, revision: u64, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return region_simple(ui, key, revision, body, style, loc)
}

