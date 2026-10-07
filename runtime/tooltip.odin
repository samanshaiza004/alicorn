package alicorn

TOOLTIP_DEFAULT_DELAY_MS :: u32(500)
TOOLTIP_MAX_DELAY_MS :: u32(5000)
TOOLTIP_MAX_TEXT_BYTES :: 512
TOOLTIP_MAX_WIDTH :: f32(360)
TOOLTIP_HORIZONTAL_PADDING :: f32(9)
TOOLTIP_VERTICAL_PADDING :: f32(6)

// tooltip attaches delayed help text to the most recently described node.
// It never changes focus or input ownership; the native host only needs to
// include tooltip_next_deadline in its event wait and call tooltip_advance
// after timed waits.
tooltip :: proc(ui: ^UI, text: string, delay_ms := TOOLTIP_DEFAULT_DELAY_MS) -> bool {
	if ui == nil || ui.runtime == nil || len(ui.runtime.pending) == 0 || len(text) == 0 ||
	   len(text) > TOOLTIP_MAX_TEXT_BYTES || delay_ms > TOOLTIP_MAX_DELAY_MS {
		return false
	}
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description { return false }
	description := &ui.runtime.pending[last].description
	description.tooltip_text = text
	description.tooltip_delay_ms = delay_ms
	return true
}

tooltip_source_at :: proc(rt: ^Runtime, hit: Node_ID) -> Node_ID {
	current := hit
	for current != 0 {
		node, ok := rt.nodes[current]
		if !ok { break }
		if node.active && len(node.tooltip_text) > 0 { return current }
		current = node.parent
	}
	return 0
}

tooltip_remove_display_commands :: proc(rt: ^Runtime) {
	if rt == nil || rt.transient_overlay_kind != .Tooltip { return }
	write_index := 0
	for read_index := 0; read_index < len(rt.display_target); read_index += 1 {
		command := rt.display_target[read_index]
		if command.owner == Node_ID(0) { continue }
		rt.display_target[write_index] = command
		write_index += 1
	}
	for len(rt.display_target) > write_index { _ = pop(&rt.display_target) }
	rt.transient_overlay_kind = .None
	rt.composition_rebuild = true
}

tooltip_dismiss :: proc(rt: ^Runtime) {
	if rt == nil { return }
	was_presented := rt.tooltip.visible
	tooltip_remove_display_commands(rt)
	if rt.tooltip.run_ready { text_run_destroy(&rt.tooltip.run) }
	rt.tooltip = Tooltip_State{}
	if was_presented {
		request_presentation(rt, "tooltip dismissed")
	}
}

tooltip_pointer_update :: proc(rt: ^Runtime, hit: Node_ID, now_ns: u64) {
	if rt == nil { return }
	if rt.context_menu.open || rt.context_menu.dismissed || rt.drag.phase != .Idle || rt.captured_node != 0 ||
	   modal_overlay_root(rt) != 0 {
		tooltip_dismiss(rt)
		return
	}
	next_target := tooltip_source_at(rt, hit)
	if next_target == rt.tooltip.target { return }
	tooltip_dismiss(rt)
	if next_target == 0 { return }
	node, ok := rt.nodes[next_target]
	if !ok || !node.active { return }
	delay_ns := u64(node.tooltip_delay_ms) * 1_000_000
	deadline := now_ns + delay_ns
	if deadline < now_ns { deadline = u64(0xFFFFFFFFFFFFFFFF) }
	// Zero is the no-deadline sentinel, but synthetic hosts may legitimately
	// provide timestamp_ns=0 with a zero-delay tooltip. Keep that armed.
	if deadline == 0 { deadline = 1 }
	rt.tooltip.target = next_target
	rt.tooltip.deadline_ns = deadline
}

tooltip_next_deadline :: proc(rt: ^Runtime) -> u64 {
	if rt == nil || rt.tooltip.target == 0 || rt.tooltip.visible { return 0 }
	return rt.tooltip.deadline_ns
}

tooltip_advance :: proc(rt: ^Runtime, now_ns: u64) -> bool {
	if rt == nil || rt.tooltip.visible || rt.tooltip.target == 0 || rt.tooltip.deadline_ns == 0 || now_ns < rt.tooltip.deadline_ns {
		return false
	}
	target := rt.tooltip.target
	node, ok := rt.nodes[target]
	if !ok || !node.active || len(node.tooltip_text) == 0 || rt.drag.phase != .Idle ||
	   rt.context_menu.open || rt.context_menu.dismissed || modal_overlay_root(rt) != 0 {
		tooltip_dismiss(rt)
		return false
	}
	run, built := text_run_build_with_overflow(
		&rt.text_engine,
		node.tooltip_text,
		13,
		TOOLTIP_MAX_WIDTH-2*TOOLTIP_HORIZONTAL_PADDING,
		rt.persistent_allocator,
		rt.scratch_allocator,
		.UI,
		FONT_WEIGHT_REGULAR,
		.Ellipsis,
	)
	if !built {
		// Do not leave an expired deadline armed when a backend has no text
		// shaping resources or the label cannot be represented.
		rt.tooltip.deadline_ns = 0
		return false
	}
	rt.tooltip.run = run
	rt.tooltip.run_ready = true
	rt.tooltip.run_generation = paint_next_resource_generation(rt)
	rt.tooltip.visible = true
	rt.tooltip.deadline_ns = 0
	rt.composition_rebuild = true
	request_presentation(rt, "tooltip delay elapsed")
	return true
}

tooltip_placement :: proc(viewport, anchor: Rect, width, height: f32) -> Rect {
	return context_menu_placement(viewport, anchor, width, height)
}

append_tooltip_overlay :: proc(rt: ^Runtime) {
	if rt == nil || !rt.tooltip.visible || !rt.tooltip.run_ready || rt.transient_overlay_kind != .None { return }
	node, ok := rt.nodes[rt.tooltip.target]
	if !ok || !node.active { return }
	run := &rt.tooltip.run
	width := minf(maxf(run.width+2*TOOLTIP_HORIZONTAL_PADDING, 72), TOOLTIP_MAX_WIDTH)
	height := maxf(run.height+2*TOOLTIP_VERTICAL_PADDING, 26)
	anchor := layout_node_finalized_geometry(rt, node.id).bounds
	bounds := tooltip_placement(rt.viewport, anchor, width, height)
	background := Color{0.075, 0.09, 0.125, 0.99}
	border := Color{0.24, 0.29, 0.37, 1}
	append(&rt.display_target,
		paint_surface_command(Node_ID(0), bounds, rt.viewport, background),
		paint_surface_command(Node_ID(0), Rect{bounds.x, bounds.y, bounds.w, 1}, rt.viewport, border),
		paint_surface_command(Node_ID(0), Rect{bounds.x, bounds.y+bounds.h-1, bounds.w, 1}, rt.viewport, border),
		paint_surface_command(Node_ID(0), Rect{bounds.x, bounds.y, 1, bounds.h}, rt.viewport, border),
		paint_surface_command(Node_ID(0), Rect{bounds.x+bounds.w-1, bounds.y, 1, bounds.h}, rt.viewport, border),
		paint_text_command(
			Node_ID(0),
			Rect{bounds.x+TOOLTIP_HORIZONTAL_PADDING, bounds.y+(bounds.h-run.height)/2, maxf(bounds.w-2*TOOLTIP_HORIZONTAL_PADDING, 0), run.height},
			rt.viewport, paint_text_handle_for_tooltip(rt), Color{0.91, 0.94, 0.98, 1},
		),
	)
	rt.transient_overlay_kind = .Tooltip
}
