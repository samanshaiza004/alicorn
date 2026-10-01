package alicorn

import "core:fmt"

CONTEXT_MENU_DEFAULT_WIDTH :: f32(224)
CONTEXT_MENU_DEFAULT_ITEM_HEIGHT :: f32(32)
CONTEXT_MENU_DEFAULT_SEPARATOR_HEIGHT :: f32(9)
CONTEXT_MENU_DEFAULT_PADDING :: f32(5)
CONTEXT_MENU_VIEWPORT_MARGIN :: f32(8)

// context_menu_placement prefers below/right of the anchor, flips when that
// side does not fit, then clamps the result to the logical viewport.
context_menu_placement :: proc(viewport, anchor: Rect, width, height: f32, margin := CONTEXT_MENU_VIEWPORT_MARGIN) -> Rect {
	margin_value := maxf(margin, 0)
	left := viewport.x + margin_value
	top := viewport.y + margin_value
	right := viewport.x + maxf(viewport.w-margin_value, 0)
	bottom := viewport.y + maxf(viewport.h-margin_value, 0)
	resolved_width := minf(maxf(width, 0), maxf(right-left, 0))
	resolved_height := minf(maxf(height, 0), maxf(bottom-top, 0))

	x := anchor.x
	if anchor.w > 0 && x+resolved_width > right { x = anchor.x+anchor.w-resolved_width }
	if x+resolved_width > right { x = right-resolved_width }
	if x < left { x = left }

	y := anchor.y
	if anchor.h > 0 { y += anchor.h }
	if y+resolved_height > bottom {
		above := anchor.y-resolved_height
		if above >= top { y = above } else { y = bottom-resolved_height }
	}
	if y < top { y = top }
	return Rect{x, y, resolved_width, resolved_height}
}

// context_menu_open requests one transient menu at a pointer point or item
// rectangle. The application owns the context target and menu contents; the
// runtime owns this popup's interaction state and restores the supplied
// focus owner (or the current focus when omitted) when it closes.
context_menu_open :: proc(
	rt: ^Runtime,
	anchor: Rect,
	restore_focus_to: Node_ID = 0,
	width: f32 = CONTEXT_MENU_DEFAULT_WIDTH,
	item_height: f32 = CONTEXT_MENU_DEFAULT_ITEM_HEIGHT,
) -> bool {
	if rt == nil { return false }
	if width <= 0 || item_height <= 0 { return false }

	was_open := rt.context_menu.open
	restore := restore_focus_to
	if restore == 0 {
		if was_open { restore = rt.context_menu.restore_focus } else { restore = rt.focused }
	}
	_ = cancel_pointer_capture(rt)
	rt.context_menu.open = true
	rt.context_menu.dismissed = false
	rt.context_menu.described = false
	rt.context_menu.pointer_consumed = false
	rt.context_menu.focus_initial_pending = !was_open
	rt.context_menu.anchor = anchor
	rt.context_menu.restore_focus = restore
	rt.context_menu.preferred_width = width
	rt.context_menu.item_height = item_height
	rt.context_menu.separator_height = CONTEXT_MENU_DEFAULT_SEPARATOR_HEIGHT
	rt.context_menu.padding = CONTEXT_MENU_DEFAULT_PADDING
	rt.context_menu.activation_action = 0
	invalidate_root(rt, "context menu opened")
	return true
}

// context_menu_open_for_focused uses the retained focused control as the
// keyboard invocation anchor. The application still chooses the semantic
// context target when it handles Shift+F10.
context_menu_open_for_focused :: proc(rt: ^Runtime, width: f32 = CONTEXT_MENU_DEFAULT_WIDTH) -> bool {
	if rt == nil { return false }
	node, ok := rt.nodes[rt.focused]
	if !ok || !node.active { return false }
	return context_menu_open(rt, node.bounds, node.id, width)
}

context_menu_is_open :: proc(rt: ^Runtime) -> bool {
	return rt != nil && rt.context_menu.open
}

context_menu_input_active :: proc(rt: ^Runtime) -> bool {
	return rt != nil && (rt.context_menu.open || rt.context_menu.dismissed)
}

context_menu_pointer_consumed :: proc(rt: ^Runtime) -> bool {
	return rt != nil && rt.context_menu.pointer_consumed
}

context_menu_restore_focus :: proc(rt: ^Runtime) {
	previous := rt.focused
	target := rt.context_menu.restore_focus
	if node, ok := rt.nodes[target]; ok && node.active && node.focusable {
		rt.focused = target
	} else {
		rt.focused = 0
	}
	if rt.focused != previous {
		if old, ok := rt.nodes[previous]; ok && clear_text_composition(old, rt.persistent_allocator) {
			invalidate_interaction_paint(rt, previous, "context menu closed and composition canceled")
		}
		invalidate_interaction_paint(rt, previous, "context menu focus restored")
		invalidate_interaction_paint(rt, rt.focused, "context menu focus restored")
		record_trace(rt, .Focus, rt.focused, "context menu focus restored")
	}
}

context_menu_set_focus :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || !node.focusable || node.disabled || !node_is_in_modal_overlay(rt, id, modal_overlay_root(rt)) { return false }
	previous := rt.focused
	if previous == id { return true }
	if old, old_ok := rt.nodes[previous]; old_ok && clear_text_composition(old, rt.persistent_allocator) {
		invalidate_interaction_paint(rt, previous, "context menu focus canceled composition")
	}
	rt.focused = id
	record_trace(rt, .Focus, id, "context menu item focused")
	invalidate_interaction_paint(rt, previous, "context menu focus changed")
	invalidate_interaction_paint(rt, id, "context menu focus changed")
	return true
}

context_menu_close_internal :: proc(rt: ^Runtime, invalidate: bool) {
	if rt == nil || !rt.context_menu.open { return }
	rt.context_menu.open = false
	rt.context_menu.dismissed = rt.context_menu.overlay != 0
	rt.context_menu.focus_initial_pending = false
	context_menu_restore_focus(rt)
	if invalidate { invalidate_root(rt, "context menu closed") }
}

context_menu_close :: proc(rt: ^Runtime) {
	context_menu_close_internal(rt, true)
}

// context_menu_begin adds the active context menu after the ordinary root has
// been closed. Pair a true result with context_menu_end.
context_menu_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	width: f32 = CONTEXT_MENU_DEFAULT_WIDTH,
	item_height: f32 = CONTEXT_MENU_DEFAULT_ITEM_HEIGHT,
	loc := #caller_location,
) -> bool {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open || !ui.runtime.context_menu.open { return false }
	rt := ui.runtime
	if len(rt.stack) != 0 {
		append_diagnostic(rt, "context_menu_begin must follow the ordinary root")
		return false
	}
	if width > 0 { rt.context_menu.preferred_width = width }
	if item_height > 0 { rt.context_menu.item_height = item_height }
	rt.context_menu.described = true
	rt.context_menu.item_index = 0
	rt.context_menu.content_height = 2 * rt.context_menu.padding
	rt.context_menu.activation_action = 0
	rt.context_menu.pending_start = len(rt.pending)

	root := container_begin_simple(
		ui,
		.Context_Menu_Overlay,
		label="context-menu-overlay",
		key=key,
		style=layout_style(.Column, clip=true),
		color=NO_BACKGROUND_COLOR,
		loc=loc,
	)
	if root == 0 { return false }
	rt.context_menu.overlay = root
	rt.context_menu.panel = container_begin_simple(
		ui,
		.Context_Menu_Panel,
		label="context-menu-panel",
		key=key_string("panel"),
		style=layout_style(.Column, width=rt.context_menu.preferred_width, height=1, padding=rt.context_menu.padding, clip=true),
		color=Color{0.075, 0.09, 0.125, 1},
		loc=loc,
	)
	return rt.context_menu.panel != 0
}

// context_menu_item describes a single-level command. If an Action_ID is
// registered, its explicit disabled state is honored; the runtime does not own
// or invoke the application's command handler.
context_menu_item :: proc(
	ui: ^UI,
	action: Action_ID,
	label: string,
	enabled := true,
	loc := #caller_location,
) {
	if ui == nil || ui.runtime == nil || !ui.runtime.context_menu.open || ui.runtime.context_menu.panel == 0 { return }
	rt := ui.runtime
	if action == Action_ID(0) || len(label) == 0 {
		append_diagnostic(rt, "context_menu_item requires a nonzero action and nonempty label")
		return
	}
	item_enabled := enabled
	if _, state, found := action_lookup(rt, action); found && !state.enabled { item_enabled = false }
	index := rt.context_menu.item_index
	key := key_pair(u64(u32(action)), u64(index+1))
	source := resolve_source(Source_Site{}, "context-menu-item", loc)
	id := emit_key(
		ui,
		.Button,
		source,
		label=label,
		key=key,
		style=layout_style(.Row, height=rt.context_menu.item_height),
		focusable=item_enabled,
		disabled=!item_enabled,
		text_style=DEFAULT_BUTTON_TEXT_STYLE,
		button_content=button_content_style(.Start, .Center, padding_x=10, padding_y=3),
	)
	if len(rt.pending) > 0 {
		pending := &rt.pending[len(rt.pending)-1]
		if pending.kind == .Description && pending.description.id == id {
			pending.description.selected = rt.focused == id
		}
	}
	if consume_activation(rt, id) {
		rt.context_menu.activation_action = action
		trace_action(rt, action, label)
	}
	rt.context_menu.content_height += rt.context_menu.item_height
	rt.context_menu.item_index += 1
}

context_menu_separator :: proc(ui: ^UI, loc := #caller_location) {
	if ui == nil || ui.runtime == nil || !ui.runtime.context_menu.open || ui.runtime.context_menu.panel == 0 { return }
	rt := ui.runtime
	index := rt.context_menu.item_index
	source := resolve_source(Source_Site{}, "context-menu-separator", loc)
	_ = emit_key(
		ui,
		.Container,
		source,
		label="context-menu-separator",
		key=key_pair(0, u64(index+1)),
		style=layout_style(.Row, height=rt.context_menu.separator_height),
		color=Color{0.24, 0.28, 0.36, 1},
		paint_background=true,
	)
	rt.context_menu.content_height += rt.context_menu.separator_height
	rt.context_menu.item_index += 1
}

context_menu_end :: proc(ui: ^UI) -> Action_ID {
	if ui == nil || ui.runtime == nil || !ui.runtime.context_menu.open { return 0 }
	rt := ui.runtime
	if len(rt.stack) < 2 || rt.context_menu.overlay == 0 || rt.context_menu.panel == 0 {
		append_diagnostic(rt, "context_menu_end called without an open context menu")
		return 0
	}
	container_end(ui) // panel
	container_end(ui) // full-viewport input layer

	content_height := maxf(rt.context_menu.content_height, 2*rt.context_menu.padding+rt.context_menu.item_height)
	bounds := context_menu_placement(rt.viewport, rt.context_menu.anchor, rt.context_menu.preferred_width, content_height)
	rt.context_menu.panel_bounds = bounds
	for index := len(rt.pending)-1; index >= rt.context_menu.pending_start; index -= 1 {
		item := &rt.pending[index]
		if item.kind == .Description && item.description.id == rt.context_menu.panel {
			item.description.style.width = bounds.w
			item.description.style.height = bounds.h
			item.description.context_menu_bounds = bounds
			break
		}
	}

	action := rt.context_menu.activation_action
	if action != 0 {
		context_menu_close_internal(rt, false)
		for len(rt.pending) > rt.context_menu.pending_start { _ = pop(&rt.pending) }
	}
	return action
}

context_menu_direct_item :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if rt.context_menu.panel == 0 { return false }
	node, ok := rt.nodes[id]
	return ok && node.active && node.parent == rt.context_menu.panel && node.kind == .Button
}

context_menu_focus_edge :: proc(rt: ^Runtime, reverse := false) -> Node_ID {
	if reverse {
		for index := len(rt.order)-1; index >= 0; index -= 1 {
			id := rt.order[index]
			if context_menu_direct_item(rt, id) && rt.nodes[id].focusable && !rt.nodes[id].disabled { return id }
		}
	} else {
		for id in rt.order {
			if context_menu_direct_item(rt, id) && rt.nodes[id].focusable && !rt.nodes[id].disabled { return id }
		}
	}
	return 0
}

context_menu_focus_step :: proc(rt: ^Runtime, delta: int) -> Node_ID {
	if len(rt.order) == 0 { return 0 }
	focused_index := -1
	for id, index in rt.order { if id == rt.focused && context_menu_direct_item(rt, id) { focused_index = index; break } }
	start := focused_index
	if start < 0 { return context_menu_focus_edge(rt, delta < 0) }
	for offset in 1..=len(rt.order) {
		index := (start + delta*offset) % len(rt.order)
		if index < 0 { index += len(rt.order) }
		id := rt.order[index]
		if context_menu_direct_item(rt, id) && rt.nodes[id].focusable && !rt.nodes[id].disabled {
			if context_menu_set_focus(rt, id) { return id }
		}
	}
	return rt.focused
}

context_menu_handle_key :: proc(rt: ^Runtime, key: Context_Menu_Key) -> bool {
	if !context_menu_input_active(rt) { return false }
	if !rt.context_menu.open { return true }
	switch key {
	case .Up:
		_ = context_menu_focus_step(rt, -1)
	case .Down:
		_ = context_menu_focus_step(rt, 1)
	case .Home:
		if id := context_menu_focus_edge(rt); id != 0 { _ = context_menu_set_focus(rt, id) }
	case .End:
		if id := context_menu_focus_edge(rt, true); id != 0 { _ = context_menu_set_focus(rt, id) }
	case .Activate:
		if context_menu_direct_item(rt, rt.focused) { _ = activate_focused(rt, .Enter) }
	case .Cancel:
		context_menu_close_internal(rt, true)
	case .Other:
		// Keep unimplemented menu accelerators and typing from reaching the
		// workspace while this transient menu owns input.
	}
	return true
}

context_menu_layout_children :: proc(rt: ^Runtime, parent: ^Node, children: []Node_ID) {
	if len(children) != 1 { return }
	rt.stats.layout_nodes_visited += 1
	rt.stats.stage_visits[.Layout] += 1
	child := rt.nodes[children[0]]
	old_bounds := child.bounds
	old_clip := child.clip
	child.bounds = child.context_menu_bounds
	child.hit_bounds = child.bounds
	child.clip = parent.clip
	if !same_rect(old_bounds, child.bounds) || !same_rect(old_clip, child.clip) || dirty_has(child.dirty, .Layout) {
		dirty_set(&child.dirty, .Layout, true)
		dirty_set(&child.dirty, .Paint, true)
		dirty_set(&child.dirty, .Composite, true)
		queue_paint(rt, child.id)
		layout_children(rt, child.id)
	}
	dirty_set(&child.dirty, .Layout, false)
}
