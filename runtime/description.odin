package alicorn
import "core:fmt"
import "core:strings"

current_node_parent :: proc(ui: ^UI) -> Node_ID {
	if len(ui.runtime.stack) == 0 {
		return 0
	}
	return ui.runtime.stack[len(ui.runtime.stack)-1]
}

current_identity_parent :: proc(ui: ^UI) -> Node_ID {
	if len(ui.runtime.identity_stack) == 0 {
		return 0
	}
	return ui.runtime.identity_stack[len(ui.runtime.identity_stack)-1]
}

push_identity_scope :: proc(rt: ^Runtime, id: Node_ID, label: string, kind: u8, numeric: u64 = 0, pair := UI_Key_Pair{}) {
	append(&rt.identity_stack, id)
	append(&rt.identity_labels, label)
	append(&rt.identity_key_u64, numeric)
	append(&rt.identity_key_numeric, kind == 2)
	append(&rt.identity_key_kind, kind)
	append(&rt.identity_key_pair, pair)
}

identity_declaration :: proc(
	rt: ^Runtime,
	source: Source_Site,
	key: UI_Key,
	parent: Node_ID,
	kind: Identity_Declaration_Kind,
	node_kind: Node_Kind = .Root,
	label := "",
) -> Identity_Declaration {
	result := Identity_Declaration{
		source=source,
		parent=parent,
		kind=kind,
		node_kind=node_kind,
		label=label,
		key=key,
		scope_depth=len(rt.identity_stack),
	}
	if len(rt.identity_key_kind) > 0 {
		last := len(rt.identity_key_kind)-1
		result.scope_key_kind = rt.identity_key_kind[last]
		result.scope_key_text = rt.identity_labels[last]
		result.scope_key_u64 = rt.identity_key_u64[last]
		result.scope_key_pair = rt.identity_key_pair[last]
	}
	return result
}

append_identity_key_text :: proc(sb: ^strings.Builder, key: UI_Key) {
	switch value in key {
	case UI_Unkeyed:
		fmt.sbprintf(sb, "unkeyed")
	case string:
		fmt.sbprintf(sb, "string:%q", value)
	case u64:
		fmt.sbprintf(sb, "u64:%d", value)
	case UI_Key_Pair:
		fmt.sbprintf(sb, "pair:(%d,%d)", value.first, value.second)
	}
}

identity_declaration_text :: proc(rt: ^Runtime, declaration: Identity_Declaration) -> string {
	sb := strings.builder_make(0, 128, allocator=rt.scratch_allocator)
	fmt.sbprintf(&sb, "%s:%d:%d component=%q declaration=%v",
		declaration.source.file, declaration.source.line, declaration.source.column,
		declaration.source.component, declaration.kind)
	if declaration.kind == .Node {
		fmt.sbprintf(&sb, " node-kind=%v label=%q", declaration.node_kind, declaration.label)
	} else if declaration.label != "" {
		fmt.sbprintf(&sb, " label=%q", declaration.label)
	}
	fmt.sbprintf(&sb, " identity-parent=%d scope-depth=%d scope-leaf=",
		declaration.parent, declaration.scope_depth)
	switch declaration.scope_key_kind {
	case 1:
		fmt.sbprintf(&sb, "string:%q", declaration.scope_key_text)
	case 2:
		fmt.sbprintf(&sb, "u64:%d", declaration.scope_key_u64)
	case 3:
		pair := declaration.scope_key_pair
		fmt.sbprintf(&sb, "pair:(%d,%d)", pair.first, pair.second)
	case:
		fmt.sbprintf(&sb, "<root-or-node>")
	}
	fmt.sbprintf(&sb, " item-key=")
	append_identity_key_text(&sb, declaration.key)
	return strings.to_string(sb)
}

pop_identity_scope :: proc(rt: ^Runtime) {
	if len(rt.identity_stack) > 0 { pop(&rt.identity_stack) }
	if len(rt.identity_labels) > 0 { pop(&rt.identity_labels) }
	if len(rt.identity_key_u64) > 0 { pop(&rt.identity_key_u64) }
	if len(rt.identity_key_numeric) > 0 { pop(&rt.identity_key_numeric) }
	if len(rt.identity_key_kind) > 0 { pop(&rt.identity_key_kind) }
	if len(rt.identity_key_pair) > 0 { pop(&rt.identity_key_pair) }
}

append_diagnostic :: proc(rt: ^Runtime, message: string) {
	rt.hard_error = true
	if len(rt.diagnostic) > 0 { delete(rt.diagnostic, rt.persistent_allocator) }
	rt.diagnostic = owned(message, rt.persistent_allocator)
	record_trace(rt, .Reconcile, 0, message)
}

	emit :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, region_revision: u64 = 0, is_region := false, focusable := false, surface_kind := GPU_Surface_Kind.Waveform, surface_interaction := GPU_Surface_Interaction.Inert, surface_pixel_width: int = 0, surface_pixel_height: int = 0, surface_dpi_scale: f32 = 1, paint_background := true, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_content_height: f32 = 0, scroll_viewport_height: f32 = 0, scroll_line_height: f32 = 0, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1, scroll_content_width: f32 = 0, scroll_viewport_width: f32 = 0, scroll_line_width: f32 = 0, scroll_axes := Scroll_Axes.Both, scroll_axis_behavior := Scroll_Axis_Behavior.Auto_Lock, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE, button_content := DEFAULT_BUTTON_CONTENT_STYLE, button_variant := Button_Variant.Default) -> Node_ID {
	rt := ui.runtime
	parent_node := current_node_parent(ui)
	parent_identity := current_identity_parent(ui)
	id := identity_hash(parent_identity, source, key, explicit_key)
	identity_key_value: UI_Key = UI_Unkeyed{}
	if explicit_key { identity_key_value = key }
	current_context := identity_declaration(rt, source, identity_key_value, parent_identity, .Node, kind, label)
	if first_context, exists := rt.seen[id]; exists {
		kind_text := explicit_key ? "duplicate key" : "repeated unkeyed sibling"
		append_diagnostic(rt, fmt.tprintf("%s resolved to retained identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: give repeated data items stable unique keys with ui.key_scope/component_begin, and keep the widget call site stable.", kind_text, id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return 0
	}
	rt.seen[id] = current_context
	identity_key := ""
	if len(rt.identity_labels) > 0 { identity_key = rt.identity_labels[len(rt.identity_labels)-1] }
	identity_key_u64: u64 = 0
	identity_key_numeric := false
	if len(rt.identity_key_u64) > 0 {
		identity_key_u64 = rt.identity_key_u64[len(rt.identity_key_u64)-1]
		identity_key_numeric = rt.identity_key_numeric[len(rt.identity_key_numeric)-1]
	}
	effective_layout_scroll_offset_y := layout_scroll_offset_y
	if effective_layout_scroll_offset_y < 0 { effective_layout_scroll_offset_y = scroll_offset_y }
	effective_layout_scroll_offset_x := layout_scroll_offset_x
	if effective_layout_scroll_offset_x < 0 { effective_layout_scroll_offset_x = scroll_offset_x }
	resolved_color := color
	if (kind == .Text || kind == .Text_Field || kind == .Text_Composition) && color_equal(resolved_color, DEFAULT_COLOR) {
		resolved_color = style_environment_color(rt, rt.style_environment, .Text)
	}
	description := Description{
		id=id, parent=parent_node, site=source, key=key, explicit_key=explicit_key,
		kind=kind, label=label, text=text, font=font, text_style=text_style,
		style_environment=rt.style_environment, style_scope_boundary=false,
		button_content_style=button_content, button_variant=button_variant, style=style, color=resolved_color, paint_background=paint_background,
		paint_value=paint_value, region_revision=region_revision, region=is_region,
		focusable=focusable, identity_key=identity_key,
		identity_key_u64=identity_key_u64, identity_key_numeric=identity_key_numeric,
		surface_kind=surface_kind, surface_interaction=surface_interaction,
		surface_pixel_width=surface_pixel_width,
		surface_pixel_height=surface_pixel_height, surface_dpi_scale=surface_dpi_scale,
		scroll_offset_y=scroll_offset_y, scroll_offset_x=scroll_offset_x,
		layout_scroll_offset_y=effective_layout_scroll_offset_y, layout_scroll_offset_x=effective_layout_scroll_offset_x,
		scroll_content_height=scroll_content_height, scroll_viewport_height=scroll_viewport_height, scroll_line_height=scroll_line_height,
		scroll_content_width=scroll_content_width, scroll_viewport_width=scroll_viewport_width, scroll_line_width=scroll_line_width,
		scroll_axes=scroll_axes, scroll_axis_behavior=scroll_axis_behavior,
	}
	append(&rt.pending, Pending_Item{.Description, description, 0, {}})
	rt.stats.descriptions_emitted += 1
	rt.stats.stage_visits[.Description] += 1
	return id
}

	emit_key :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := DEFAULT_COLOR, state_bits: u64 = 0, selected := false, disabled := false, region_revision: u64 = 0, is_region := false, focusable := false, surface_kind := GPU_Surface_Kind.Waveform, surface_pixel_width: int = 0, surface_pixel_height: int = 0, surface_dpi_scale: f32 = 1, paint_background := true, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_content_height: f32 = 0, scroll_viewport_height: f32 = 0, scroll_line_height: f32 = 0, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1, scroll_content_width: f32 = 0, scroll_viewport_width: f32 = 0, scroll_line_width: f32 = 0, scroll_axes := Scroll_Axes.Both, scroll_axis_behavior := Scroll_Axis_Behavior.Auto_Lock, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE, button_content := DEFAULT_BUTTON_CONTENT_STYLE, button_variant := Button_Variant.Default) -> Node_ID {
	rt := ui.runtime
	parent_node := current_node_parent(ui)
	parent_identity := current_identity_parent(ui)
	id := identity_hash_key(parent_identity, source, key)
	current_context := identity_declaration(rt, source, key, parent_identity, .Node, kind, label)
	if first_context, exists := rt.seen[id]; exists {
		kind_text := ui_key_is_explicit(key) ? "duplicate key" : "repeated unkeyed sibling"
		append_diagnostic(rt, fmt.tprintf("%s resolved to retained identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: give repeated data items stable unique keys with ui.key_scope/component_begin, and keep the widget call site stable.", kind_text, id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return 0
	}
	rt.seen[id] = current_context
	identity_key := ""
	identity_key_u64: u64 = 0
	identity_key_numeric := false
	identity_key_kind: u8 = 0
	identity_key_pair := UI_Key_Pair{}
	if len(rt.identity_labels) > 0 { identity_key = rt.identity_labels[len(rt.identity_labels)-1] }
	if len(rt.identity_key_u64) > 0 {
		identity_key_u64 = rt.identity_key_u64[len(rt.identity_key_u64)-1]
		identity_key_numeric = rt.identity_key_numeric[len(rt.identity_key_numeric)-1]
		identity_key_kind = rt.identity_key_kind[len(rt.identity_key_kind)-1]
		identity_key_pair = rt.identity_key_pair[len(rt.identity_key_pair)-1]
	}
	key_string_value := ""
	key_kind: u8 = 0
	switch value in key {
	case UI_Unkeyed:
		key_kind = 0
	case string:
		key_string_value = value
		key_kind = 1
	case u64:
		identity_key_u64 = value
		identity_key_numeric = true
		key_kind = 2
	case UI_Key_Pair:
		identity_key_pair = value
		key_kind = 3
	}
	effective_layout_scroll_offset_y := layout_scroll_offset_y
	if effective_layout_scroll_offset_y < 0 { effective_layout_scroll_offset_y = scroll_offset_y }
	effective_layout_scroll_offset_x := layout_scroll_offset_x
	if effective_layout_scroll_offset_x < 0 { effective_layout_scroll_offset_x = scroll_offset_x }
	resolved_color := color
	if (kind == .Text || kind == .Text_Field || kind == .Text_Composition) && color_equal(resolved_color, DEFAULT_COLOR) {
		resolved_color = style_environment_color(rt, rt.style_environment, .Text)
	}
	description := Description{
		id=id, parent=parent_node, site=source, key=key_string_value, explicit_key=ui_key_is_explicit(key),
		identity_key_kind=key_kind, identity_key_pair=identity_key_pair,
		kind=kind, label=label, text=text, font=font, text_style=text_style,
		style_environment=rt.style_environment, style_scope_boundary=false,
		button_content_style=button_content, button_variant=button_variant, style=style, color=resolved_color, paint_background=paint_background,
		paint_value=state_bits, region_revision=region_revision, region=is_region,
		focusable=focusable, selected=selected, disabled=disabled, identity_key=identity_key,
		identity_key_u64=identity_key_u64, identity_key_numeric=identity_key_numeric,
		surface_kind=surface_kind, surface_pixel_width=surface_pixel_width,
		surface_pixel_height=surface_pixel_height, surface_dpi_scale=surface_dpi_scale,
		scroll_offset_y=scroll_offset_y, scroll_offset_x=scroll_offset_x,
		layout_scroll_offset_y=effective_layout_scroll_offset_y, layout_scroll_offset_x=effective_layout_scroll_offset_x,
		scroll_content_height=scroll_content_height, scroll_viewport_height=scroll_viewport_height, scroll_line_height=scroll_line_height,
		scroll_content_width=scroll_content_width, scroll_viewport_width=scroll_viewport_width, scroll_line_width=scroll_line_width,
		scroll_axes=scroll_axes, scroll_axis_behavior=scroll_axis_behavior,
	}
	append(&rt.pending, Pending_Item{.Description, description, 0, {}})
	rt.stats.descriptions_emitted += 1
	rt.stats.stage_visits[.Description] += 1
	return id
}

key_scope :: proc(ui: ^UI, key: string, source: Source_Site, body: proc()) {
	if !key_scope_begin_ex(ui, key, source) { return }
	body()
	key_scope_end(ui)
}

key_scope_begin_ex :: proc(ui: ^UI, key: string, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope", loc)
	parent := current_identity_parent(ui)
	id := identity_hash(parent, resolved_source, key, true)
	current_context := identity_declaration(rt, resolved_source, UI_Key(key), parent, .Key_Scope, label=key)
	if first_context, exists := rt.identity_scopes[id]; exists {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope resolved to identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: use a different stable key for each sibling item.", id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return false
	}
	rt.identity_scopes[id] = current_context
	push_identity_scope(rt, id, key, 1)
	return true
}

key_scope_begin_key :: proc(ui: ^UI, key: UI_Key, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope", loc)
	parent := current_identity_parent(ui)
	id := identity_hash_key(parent, resolved_source, key)
	current_context := identity_declaration(rt, resolved_source, key, parent, .Key_Scope)
	if first_context, exists := rt.identity_scopes[id]; exists {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope resolved to identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: use a different stable key for each sibling item.", id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return false
	}
	rt.identity_scopes[id] = current_context
	switch value in key {
	case UI_Unkeyed:
		push_identity_scope(rt, id, "", 0)
	case string:
		push_identity_scope(rt, id, value, 1)
	case u64:
		push_identity_scope(rt, id, "", 2, value)
	case UI_Key_Pair:
		push_identity_scope(rt, id, "", 3, pair=value)
	}
	return true
}

key_scope_begin :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return key_scope_begin_key(ui, key, Source_Site{}, loc)
}

// key_scope_u64 is the allocation-free typed-key path used by large keyed
// trees. It has the same identity and ambiguity rules as string keys.
key_scope_u64 :: proc(ui: ^UI, key: u64, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope_u64", loc)
	parent := current_identity_parent(ui)
	id := identity_hash_u64(parent, resolved_source, key)
	current_context := identity_declaration(rt, resolved_source, UI_Key(key), parent, .Numeric_Key_Scope)
	if first_context, exists := rt.identity_scopes[id]; exists {
		append_diagnostic(rt, fmt.tprintf("duplicate numeric key scope resolved to identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: use a different stable numeric key for each sibling item.", id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return false
	}
	rt.identity_scopes[id] = current_context
	push_identity_scope(rt, id, "", 2, key)
	return true
}

// component_begin creates an invocation scope from the actual application
// call site. It is the ergonomic boundary for reusable helpers that need
// distinct identity even when their widget call sites are shared.
component_begin_key :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return key_scope_begin_key(ui, key, resolve_source(Source_Site{}, "component", loc))
}

component_begin_ex :: proc(ui: ^UI, key: string, loc := #caller_location) -> bool {
	return key_scope_begin_ex(ui, key, resolve_source(Source_Site{}, "component", loc))
}

component_begin :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return component_begin_key(ui, key, loc)
}

component_end :: proc(ui: ^UI) {
	key_scope_end(ui)
}

key_scope_end :: proc(ui: ^UI) {
	pop_identity_scope(ui.runtime)
}

container_begin_ex :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=resolved_color, paint_value=paint_value, focusable=focusable, paint_background=paints, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y, scroll_offset_x=scroll_offset_x, layout_scroll_offset_x=layout_scroll_offset_x)
	if id != 0 {
		append(&ui.runtime.stack, id)
		push_identity_scope(ui.runtime, id, "", 0)
	}
	return id
}

// text_input_target marks a described focus owner as a native text-input
// destination without tying that ownership to a particular widget kind. The
// node must be emitted in the current description; it becomes focusable as
// part of the same retained description.
text_input_target :: proc(ui: ^UI, id: Node_ID) -> bool {
	rt := ui.runtime
	if rt == nil || !rt.frame_open || id == 0 {
		if rt != nil { append_diagnostic(rt, "text_input_target requires a live node in an open description frame") }
		return false
	}
	for i := len(rt.pending)-1; i >= 0; i -= 1 {
		item := &rt.pending[i]
		if item.kind != .Description || item.description.id != id { continue }
		if item.description.disabled {
			append_diagnostic(rt, fmt.tprintf("disabled node %d cannot own native text input", id))
			return false
		}
		item.description.text_input_target = true
		item.description.focusable = true
		return true
	}
	append_diagnostic(rt, fmt.tprintf("text_input_target references node %d that was not emitted in the current frame", id))
	return false
}

container_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) > 0 { pop(&ui.runtime.stack) }
	pop_identity_scope(ui.runtime)
}

// A structural wrapper can be made identity-transparent when a caller wants a
// keyed item's descendants to survive that wrapper being introduced or
// removed. The retained hierarchy still records the wrapper for layout.
transparent_container_begin :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=resolved_color, paint_value=paint_value, focusable=focusable, paint_background=paints)
	if id != 0 { append(&ui.runtime.stack, id) }
	return id
}

transparent_container_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) > 0 { pop(&ui.runtime.stack) }
}

container_ex :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, body: proc(), label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	id := container_begin_ex(ui, kind, resolved_source, label, key, explicit_key, style, color, paint_value, focusable, loc, scroll_offset_y, layout_scroll_offset_y, scroll_offset_x, layout_scroll_offset_x)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root_ex :: proc(ui: ^UI, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "root", loc)
	return container_ex(ui, .Root, resolved_source, body, label="root", style=style)
}

container_begin_simple :: proc(ui: ^UI, kind: Node_Kind, label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, state_bits: u64 = 0, selected := false, disabled := false, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(Source_Site{}, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit_key(ui, kind, resolved_source, label=label, key=key, style=style, color=resolved_color, state_bits=state_bits, selected=selected, disabled=disabled, focusable=focusable && !disabled, paint_background=paints, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y, scroll_offset_x=scroll_offset_x, layout_scroll_offset_x=layout_scroll_offset_x)
	if id != 0 {
		append(&ui.runtime.stack, id)
		push_identity_scope(ui.runtime, id, "", 0)
	}
	return id
}

container_simple :: proc(ui: ^UI, kind: Node_Kind, body: proc(), label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	id := container_begin_simple(ui, kind, label, key, style, color, 0, false, false, false, loc, scroll_offset_y, layout_scroll_offset_y, scroll_offset_x, layout_scroll_offset_x)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root_simple :: proc(ui: ^UI, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return container_simple(ui, .Root, body, label="root", style=style, loc=loc)
}

container_begin :: proc(ui: ^UI, kind: Node_Kind, label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, state_bits: u64 = 0, selected := false, disabled := false, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	return container_begin_simple(ui, kind, label, key, style, color, state_bits, selected, disabled, focusable, loc, scroll_offset_y, layout_scroll_offset_y, scroll_offset_x, layout_scroll_offset_x)
}

container :: proc(ui: ^UI, kind: Node_Kind, body: proc(), label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, loc := #caller_location) -> Node_ID {
	return container_simple(ui, kind, body, label, key, style, color, loc)
}

// modal_overlay_begin starts a viewport-sized top-level layer. Describe the
// ordinary application roots first, close them, then describe the overlay.
// Its children paint above the workspace; pointer, wheel, and focus traversal
// stay inside the overlay until it is removed from the next description.
modal_overlay_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	style := DEFAULT_STYLE,
	backdrop_color := Color{0.02, 0.025, 0.04, 0.68},
	loc := #caller_location,
) -> Node_ID {
	if len(ui.runtime.stack) != 0 {
		append_diagnostic(ui.runtime, "modal_overlay_begin must be called after closing the ordinary root")
		return 0
	}
	tooltip_dismiss(ui.runtime)
	return container_begin_simple(
		ui,
		.Modal_Overlay,
		label="modal-overlay",
		key=key,
		style=style,
		color=backdrop_color,
		loc=loc,
	)
}

modal_overlay_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) == 0 {
		append_diagnostic(ui.runtime, "modal_overlay_end called without an open modal overlay")
		return
	}
	id := ui.runtime.stack[len(ui.runtime.stack)-1]
	is_overlay := false
	for item in ui.runtime.pending {
		if item.kind == .Description && item.description.id == id && item.description.kind == .Modal_Overlay {
			is_overlay = true
			break
		}
	}
	if !is_overlay {
		append_diagnostic(ui.runtime, "modal_overlay_end must follow its overlay children")
		return
	}
	container_end(ui)
}
