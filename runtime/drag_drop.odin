package alicorn

DRAG_SOURCE_OPACITY :: f32(0.55)
DRAG_PREVIEW_POINTER_OFFSET :: f32(12)
DRAG_PREVIEW_MAX_WIDTH :: f32(280)
DRAG_PREVIEW_MAX_LABEL_BYTES :: 256
DRAG_PREVIEW_MAX_SUBTREE_COMMANDS :: 512
DRAG_PREVIEW_MAX_SUBTREE_SPANS :: 2048

// drag_source marks the most recently described node as a local drag source.
// The application identity must remain meaningful if virtualization removes
// the node while the drag is in progress. Horizontal_Magnetic bounds the
// preview and reorder targeting to the nearest horizontal scroll viewport
// until the real pointer crosses detach_distance; reattach_distance prevents
// edge flicker. Sources without such a viewport retain vertical-only tracking.
drag_source :: proc(
	ui: ^UI,
	drag_type: Drag_Type,
	identity: Semantic_ID,
	preview_mode := Drag_Preview_Mode.Label,
	tracking := DEFAULT_DRAG_TRACKING_OPTIONS,
) -> bool {
	if ui == nil || ui.runtime == nil || drag_type == Drag_Type(0) || !semantic_id_is_valid(identity) { return false }
	if len(ui.runtime.pending) == 0 { return false }
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description { return false }
	description := &ui.runtime.pending[last].description
	description.drag_source_type = drag_type
	description.drag_source_id = identity
	if preview_mode == .Source_Subtree {
		if ui.runtime.drag_preview_modes == nil {
			ui.runtime.drag_preview_modes = make(map[Node_ID]Drag_Preview_Mode, allocator=ui.runtime.persistent_allocator)
		}
		ui.runtime.drag_preview_modes[description.id] = preview_mode
	} else {
		delete_key(&ui.runtime.drag_preview_modes, description.id)
	}
	if tracking.mode == .Horizontal_Magnetic {
		normalized_tracking := tracking
		normalized_tracking.detach_distance = maxf(normalized_tracking.detach_distance, 0)
		normalized_tracking.reattach_distance = clampf(normalized_tracking.reattach_distance, 0, normalized_tracking.detach_distance)
		if ui.runtime.drag_tracking_options == nil {
			ui.runtime.drag_tracking_options = make(map[Node_ID]Drag_Tracking_Options, allocator=ui.runtime.persistent_allocator)
		}
		ui.runtime.drag_tracking_options[description.id] = normalized_tracking
	} else if ui.runtime.drag_tracking_options != nil {
		delete_key(&ui.runtime.drag_tracking_options, description.id)
	}
	return true
}

// drop_target marks the most recently described node as a target for one
// local drag category. Between modes derive Before/After from the target's
// midpoint; On treats the whole target as a single destination.
drop_target :: proc(ui: ^UI, drag_type: Drag_Type, identity: Semantic_ID, mode: Drop_Target_Mode) -> bool {
	if ui == nil || ui.runtime == nil || drag_type == Drag_Type(0) || !semantic_id_is_valid(identity) { return false }
	if len(ui.runtime.pending) == 0 { return false }
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description { return false }
	description := &ui.runtime.pending[last].description
	description.drop_target_type = drag_type
	description.drop_target_id = identity
	description.drop_target_mode = mode
	return true
}

drag_is_active :: proc(rt: ^Runtime) -> bool {
	return rt != nil && rt.drag.phase == .Dragging
}

drag_session :: proc(rt: ^Runtime) -> Drag_Session {
	if rt == nil { return {} }
	return rt.drag
}

drag_event_take :: proc(rt: ^Runtime) -> (event: Drag_Event, ok: bool) {
	if rt == nil || !rt.drag_event_pending { return {}, false }
	event = rt.drag_event
	rt.drag_event_pending = false
	return event, true
}

drag_event_clear :: proc(rt: ^Runtime) {
	if rt != nil { rt.drag_event_pending = false }
}

drag_cancel :: proc(rt: ^Runtime) -> bool {
	if rt == nil || rt.drag.phase == .Idle { return false }
	drag_cancel_session(rt)
	if node, ok := rt.nodes[rt.captured_node]; ok && node.pressed {
		node.pressed = false
		invalidate_interaction_paint(rt, node.id, "drag canceled")
	}
	rt.captured_node = 0
	rt.activation_node = 0
	return true
}

drag_cancel_session :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase == .Idle { return }
	if rt.drag.phase == .Dragging {
		rt.drag_event = Drag_Event{
			kind=.Cancelled,
			drag_type=rt.drag.drag_type,
			source=rt.drag.source,
			previous_target=rt.drag.target,
			presentation_state=rt.drag.presentation_state,
		}
		rt.drag_event_pending = true
	}
	drag_clear_target_visual(rt)
	drag_preview_clear(rt)
	rt.drag = {}
}

drag_preview_begin :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	drag_preview_clear(rt)
	if source, ok := rt.nodes[rt.drag.source_node]; ok && source.active {
		preview_mode := rt.drag_preview_modes[source.id]
		if preview_mode == .Source_Subtree && drag_preview_capture_subtree(rt, source.id) {
			rt.drag_preview.mode = .Source_Subtree
			rt.drag_preview.width = source.bounds.w
			rt.drag_preview.height = source.bounds.h
			rt.composition_rebuild = true
			request_presentation(rt, "dragged subtree lifted")
			return
		}
		label := source.label if source.label != "" else source.text
		if len(label) > DRAG_PREVIEW_MAX_LABEL_BYTES {
			label = label[:grapheme_floor_boundary(label, DRAG_PREVIEW_MAX_LABEL_BYTES)]
		}
		size := f32(14)
		font := source.font
		weight := effective_font_weight(source.text_style.font_weight)
		styles: []Text_Style_Span
		if source.text_run_valid {
			size = source.text_run.size
			styles = source.text_style_spans[:]
		}
		if len(label) > 0 {
			run, built := text_run_build_with_overflow(
				&rt.text_engine,
				label,
				maxf(size, 10),
				DRAG_PREVIEW_MAX_WIDTH-24,
				rt.persistent_allocator,
				rt.scratch_allocator,
				font,
				weight,
				.Ellipsis,
				text_style_spans=styles,
			)
			if built {
				rt.drag_preview.run = run
				rt.drag_preview.run_generation = paint_next_resource_generation(rt)
				rt.drag_preview.width = minf(run.width+24, DRAG_PREVIEW_MAX_WIDTH)
				rt.drag_preview.height = maxf(run.height+12, 28)
				rt.drag_preview.ready = true
			}
		}
	}
	if !rt.drag_preview.ready {
		rt.drag_preview.width = 96
		rt.drag_preview.height = 28
	}
	rt.composition_rebuild = true
	request_presentation(rt, "drag preview started")
}

drag_preview_capture_subtree :: proc(rt: ^Runtime, source: Node_ID) -> bool {
	if rt == nil || source == 0 || len(rt.display_target) == 0 { return false }
	command_count, span_count := 0, 0
	for command in rt.display_target {
		if !drag_preview_owner_is_descendant(rt, command.owner, source) { continue }
		command_count += 1
		if text, ok := command.payload.(Text_Paint); ok { span_count += len(text.spans) }
		if command_count > DRAG_PREVIEW_MAX_SUBTREE_COMMANDS || span_count > DRAG_PREVIEW_MAX_SUBTREE_SPANS { return false }
	}
	if command_count == 0 { return false }

	preview := &rt.drag_preview
	preview.commands = make([dynamic]Paint_Command, 0, command_count, allocator=rt.persistent_allocator)
	preview.spans = make([dynamic]Text_Paint_Span, span_count, allocator=rt.persistent_allocator)
	span_start := 0
	for original in rt.display_target {
		if !drag_preview_owner_is_descendant(rt, original.owner, source) { continue }
		command := original
		command.owner = 0
		// The snapshot is an inert overlay. It follows the pointer outside the
		// original tab and is clipped only by the native window viewport.
		command.clip = rt.viewport
		if text, ok := command.payload.(Text_Paint); ok {
			count := len(text.spans)
			if count > 0 {
				copy(preview.spans[span_start:span_start+count], text.spans)
				text.spans = preview.spans[span_start:span_start+count]
				span_start += count
			}
			command.payload = text
		}
		append(&preview.commands, command)
	}
	return len(preview.commands) == command_count
}

drag_preview_owner_is_descendant :: proc(rt: ^Runtime, owner, ancestor: Node_ID) -> bool {
	if rt == nil || owner == 0 || ancestor == 0 { return false }
	current := owner
	for current != 0 {
		if current == ancestor { return true }
		node, ok := rt.nodes[current]
		if !ok || node == nil { return false }
		current = node.parent
	}
	return false
}

// drag_preview_clear removes borrowed text commands before releasing the
// shaped label they refer to. The pending presentation rebuild restores the
// ordinary retained list without waking the application.
drag_preview_clear :: proc(rt: ^Runtime) {
	if rt == nil { return }
	if rt.transient_overlay_kind == .Drag_Preview {
		start := rt.drag_preview.display_start
		count := len(rt.drag_preview.commands)
		if rt.drag_preview.mode != .Source_Subtree { count = 0 }
		if count == 0 && start >= 0 && start < len(rt.display_target) {
			// The label preview occupies two surfaces and, if shaping succeeded,
			// one text command. Remove only that bounded tail segment; unrelated
			// runtime overlays such as tooltips remain intact.
			count = 2
			if rt.drag_preview.ready { count += 1 }
		}
		if start >= 0 && start+count <= len(rt.display_target) {
			new_len := len(rt.display_target)-count
			for read_index := start+count; read_index < len(rt.display_target); read_index += 1 {
				rt.display_target[read_index-count] = rt.display_target[read_index]
			}
			for len(rt.display_target) > new_len { _ = pop(&rt.display_target) }
		}
	}
	if rt.transient_overlay_kind == .Drag_Preview { rt.transient_overlay_kind = .None }
	if rt.drag_preview.ready { text_run_destroy(&rt.drag_preview.run) }
	if len(rt.drag_preview.commands) > 0 { delete(rt.drag_preview.commands) }
	if len(rt.drag_preview.spans) > 0 { delete(rt.drag_preview.spans) }
	rt.drag_preview = Drag_Preview{}
	rt.composition_rebuild = true
	request_presentation(rt, "drag preview cleared")
}

// A drag preview is a retained display overlay with a source-independent
// label. Its node ID is zero, which is reserved for runtime-generated display
// commands and never participates in hit testing.
append_drag_preview :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	rt.transient_overlay_kind = .Drag_Preview
	preview := &rt.drag_preview
	preview.display_start = len(rt.display_target)
	if preview.mode == .Source_Subtree && len(preview.commands) > 0 {
		delta := drag_preview_translation(rt)
		for base in preview.commands {
			command := base
			command.translation[0] += delta[0]
			command.translation[1] += delta[1]
			append(&rt.display_target, command)
		}
		return
	}
	shadow := Rect{2, 3, preview.width, preview.height}
	card := Rect{0, 0, preview.width, preview.height}
	append(&rt.display_target,
		paint_surface_command(Node_ID(0), shadow, rt.viewport, Color{0, 0, 0, 0.38}, translation=drag_preview_translation(rt)),
		paint_surface_command(Node_ID(0), card, rt.viewport, Color{0.12, 0.16, 0.23, 0.96}, translation=drag_preview_translation(rt)),
	)
	if preview.ready {
		text_bounds := Rect{11, (preview.height-preview.run.height)/2, maxf(preview.width-22, 0), preview.run.height}
		append(&rt.display_target, paint_text_command(
			Node_ID(0), text_bounds, rt.viewport, paint_text_handle_for_drag_preview(rt),
			Color{0.91, 0.94, 0.98, 0.96}, translation=drag_preview_translation(rt),
		))
	}
}

drag_preview_translation :: proc(rt: ^Runtime) -> [2]f32 {
	if rt == nil { return {} }
	return drag_preview_translation_at(rt, rt.drag.x, rt.drag.y, rt.drag.presentation_state)
}

drag_preview_translation_at :: proc(
	rt: ^Runtime,
	x, y: f32,
	state: Drag_Presentation_State,
) -> [2]f32 {
	if rt == nil { return {} }
	if rt.drag.tracking.mode == .Horizontal_Magnetic {
		if state == .Detached && rt.drag.detached_anchor_valid {
			return rt.drag.detached_preview_translation +
				[2]f32{x-rt.drag.detached_anchor_x, y-rt.drag.detached_anchor_y}
		}
		if state == .Horizontal_Track {
			if rt.drag_preview.mode == .Source_Subtree {
				x_translation := x-rt.drag.start_x
				if rt.drag.track_bounds_is_viewport {
					if source, found := rt.nodes[rt.drag.source_node]; found && source != nil {
						track := rt.drag.track_bounds
						max_left := maxf(track.x, track.x+track.w-source.bounds.w)
						left := clampf(source.bounds.x+x_translation, track.x, max_left)
						x_translation = left-source.bounds.x
					}
				}
				return [2]f32{x_translation, 0}
			}
			track := rt.drag.track_bounds
			preview_x := x+DRAG_PREVIEW_POINTER_OFFSET
			preview_y := track.y+track.h*0.5+DRAG_PREVIEW_POINTER_OFFSET
			if rt.drag.track_bounds_is_viewport {
				max_left := maxf(track.x, track.x+track.w-rt.drag_preview.width)
				preview_x = clampf(preview_x, track.x, max_left)
			}
			return [2]f32{preview_x, preview_y}
		}
	}
	if rt.drag_preview.mode == .Source_Subtree {
		return [2]f32{x-rt.drag.start_x, y-rt.drag.start_y}
	}
	return [2]f32{x+DRAG_PREVIEW_POINTER_OFFSET, y+DRAG_PREVIEW_POINTER_OFFSET}
}

// Magnetic sources use the nearest horizontal scroll viewport as their finite
// track. Sources outside a horizontal scroll region retain their original
// source-rectangle vertical behavior.
drag_tracking_region_for_source :: proc(rt: ^Runtime, source: Node_ID, fallback: Rect) -> (bounds: Rect, is_viewport: bool) {
	bounds = fallback
	if rt == nil { return }
	current := source
	for current != 0 {
		node, found := rt.nodes[current]
		if !found || node == nil { break }
		if node.kind == .Scroll_Region && (node.scroll_axes == .Horizontal || node.scroll_axes == .Both) {
			bounds = node.scroll_viewport_bounds
			if bounds.w <= 0 || bounds.h <= 0 {
				bounds = layout_node_finalized_geometry(rt, current).bounds
			}
			if bounds.w <= 0 || bounds.h <= 0 { bounds = node.bounds }
			return bounds, true
		}
		current = node.parent
	}
	return
}

drag_preview_pointer_moved :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	// Translation is ordinary command state. Refresh only the transient preview
	// commands; retain its shaped mesh and do not recompose the app tree.
	translation := drag_preview_translation(rt)
	if rt.transient_overlay_kind == .Drag_Preview {
		if rt.drag_preview.mode == .Source_Subtree {
			start := rt.drag_preview.display_start
			count := len(rt.drag_preview.commands)
			if start < 0 || start+count > len(rt.display_target) {
				rt.composition_rebuild = true
				request_presentation(rt, "dragged subtree overlay needs rebuilding")
				return
			}
			for offset in 0..<count {
				command := rt.drag_preview.commands[offset]
				command.translation[0] += translation[0]
				command.translation[1] += translation[1]
				rt.display_target[start+offset] = command
				rt.display[start+offset] = layout_finalize_paint_command(command, rt.presentation_scale_x, rt.presentation_scale_y)
				rt.stats.display_commands_finalized += 1
			}
		} else {
			count := 2
			if rt.drag_preview.ready { count += 1 }
			for index := rt.drag_preview.display_start; index < min(rt.drag_preview.display_start+count, len(rt.display_target)); index += 1 {
				if rt.display_target[index].owner == 0 {
					rt.display_target[index].translation = translation
				}
			}
			layout_finalize_display(rt, .Display_Transient_Update)
			request_presentation(rt, "drag preview followed pointer")
			return
		}
		rt.stats.global_work_by_reason[.Display_Transient_Update] += 1
	}
	request_presentation(rt, "drag preview followed pointer")
}

drag_source_opacity :: proc(rt: ^Runtime, id: Node_ID) -> f32 {
	if rt != nil && rt.drag.phase == .Dragging && rt.drag.source_node == id {
		// A lifted source subtree already has a full-contrast paint-only copy.
		// Hide its original visual slot so displaced siblings don't overlap it;
		// the retained node and its hit/semantic identity remain present.
		if rt.drag_preview.mode == .Source_Subtree { return 0 }
		return DRAG_SOURCE_OPACITY
	}
	return 1
}

drag_clear_target_visual :: proc(rt: ^Runtime) {
	if rt == nil { return }
	if target, ok := rt.nodes[rt.drag.target_node]; ok && target.drop_position != .None {
		target.drop_position = .None
		invalidate_interaction_paint(rt, target.id, "drag target cleared")
	}
}

drag_source_at :: proc(rt: ^Runtime, hit: Node_ID) -> (node: Node_ID, drag_type: Drag_Type, identity: Semantic_ID, found: bool) {
	if rt == nil { return }
	current := hit
	for current != 0 {
		candidate, ok := rt.nodes[current]
		if !ok { break }
		if node_is_presentation_active(rt, current) && candidate.drag_source_type != Drag_Type(0) && semantic_id_is_valid(candidate.drag_source_id) {
			return current, candidate.drag_source_type, candidate.drag_source_id, true
		}
		// A nested interactive target owns the click unless it explicitly opts
		// into dragging. Do not let an ancestor row/tab steal actions such as a
		// close button just because it is also a drag source.
		if drag_source_interaction_boundary(candidate) { return }
		current = candidate.parent
	}
	return
}

drag_source_interaction_boundary :: proc(node: ^Node) -> bool {
	if node == nil { return false }
	return node.kind == .Button ||
		node.kind == .Checkbox || node.kind == .Slider || node.kind == .Text_Field ||
		(node.kind == .Custom_Surface && node.surface_interaction == .Pointer) ||
		(node.text_input_target && node.focusable)
}

drag_target_at :: proc(rt: ^Runtime, hit: Node_ID, drag_type: Drag_Type, x, y: f32) -> (node: Node_ID, identity: Semantic_ID, position: Drop_Position, mode: Drop_Target_Mode) {
	if rt == nil || drag_type == Drag_Type(0) { return }
	current := hit
	for current != 0 {
		candidate, ok := rt.nodes[current]
		if !ok { break }
		if node_is_presentation_active(rt, current) && candidate.drop_target_type == drag_type && semantic_id_is_valid(candidate.drop_target_id) {
			candidate_bounds := layout_node_finalized_geometry(rt, current).bounds
			position := Drop_Position.On
			#partial switch candidate.drop_target_mode {
			case .On:
			case .Between_Horizontal:
				position = .Before if x < candidate_bounds.x+candidate_bounds.w*0.5 else .After
			case .Between_Vertical:
				position = .Before if y < candidate_bounds.y+candidate_bounds.h*0.5 else .After
			}
			return current, candidate.drop_target_id, position, candidate.drop_target_mode
		}
		current = candidate.parent
	}
	return
}

drag_assign_target :: proc(rt: ^Runtime, node: Node_ID, identity: Semantic_ID, position: Drop_Position, mode: Drop_Target_Mode, emit_event: bool) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	previous := rt.drag.target
	previous_position := rt.drag.position
	previous_node := rt.drag.target_node
	changed := previous != identity || previous_position != position
	next_node := node
	next_identity := identity
	next_position := position
	next_mode := mode
	if previous_node != node {
		if old, ok := rt.nodes[previous_node]; ok && old.drop_position != .None {
			old.drop_position = .None
			invalidate_interaction_paint(rt, old.id, "drag left drop target")
		}
	}
	if next, ok := rt.nodes[next_node]; ok {
		if next.drop_position != next_position {
			next.drop_position = next_position
			invalidate_interaction_paint(rt, next.id, "drag entered drop target")
		}
	} else {
		next_node = 0
		next_identity = {}
		next_position = .None
	}
	rt.drag.target = next_identity
	rt.drag.target_node = next_node
	rt.drag.position = next_position
	rt.drag.target_mode = next_mode
	if changed && emit_event {
		rt.drag_event = Drag_Event{
			kind=.Target_Changed,
			drag_type=rt.drag.drag_type,
			source=rt.drag.source,
			previous_target=previous,
			target=next_identity,
			position=next_position,
			presentation_state=rt.drag.presentation_state,
		}
		rt.drag_event_pending = true
	}
}

drag_update_target :: proc(rt: ^Runtime, hit: Node_ID, x, y: f32, emit_event := true) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	target_x, target_y := drag_target_coordinates(rt, x, y)
	target_hit := hit
	if target_y != y { target_hit = hit_test(rt, target_x, target_y) }
	node, identity, position, mode := drag_target_at(rt, target_hit, rt.drag.drag_type, target_x, target_y)
	drag_assign_target(rt, node, identity, position, mode, emit_event)
}

// drag_refresh_target re-evaluates the retained target after an application
// rebuild changes geometry under a stationary pointer, such as edge autoscroll.
drag_refresh_target :: proc(rt: ^Runtime) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	target_x, target_y := drag_target_coordinates(rt, rt.drag.x, rt.drag.y)
	hit := hit_test(rt, target_x, target_y)
	drag_update_target(rt, hit, rt.drag.x, rt.drag.y)
}

drag_tracking_update_state :: proc(rt: ^Runtime, pointer_x, pointer_y: f32) {
	if rt == nil || rt.drag.tracking.mode != .Horizontal_Magnetic { return }
	track := rt.drag.track_bounds
	distance_x := f32(0)
	if rt.drag.track_bounds_is_viewport {
		distance_x = maxf(maxf(track.x-pointer_x, pointer_x-(track.x+track.w)), 0)
	}
	distance_y := maxf(maxf(track.y-pointer_y, pointer_y-(track.y+track.h)), 0)
	distance_outside := maxf(distance_x, distance_y)
	if rt.drag.presentation_state == .Detached {
		if distance_outside <= rt.drag.tracking.reattach_distance {
			rt.drag.presentation_state = .Horizontal_Track
			rt.drag.detached_anchor_valid = false
		}
	} else if distance_outside >= rt.drag.tracking.detach_distance {
		anchor_x, anchor_y := pointer_x, pointer_y
		if distance_x >= rt.drag.tracking.detach_distance {
			anchor_x = track.x-rt.drag.tracking.detach_distance
			if pointer_x > track.x+track.w {
				anchor_x = track.x+track.w+rt.drag.tracking.detach_distance
			}
		}
		if distance_y >= rt.drag.tracking.detach_distance {
			anchor_y = track.y-rt.drag.tracking.detach_distance
			if pointer_y > track.y+track.h {
				anchor_y = track.y+track.h+rt.drag.tracking.detach_distance
			}
		}
		rt.drag.detached_preview_translation = drag_preview_translation_at(
			rt,
			anchor_x,
			anchor_y,
			.Horizontal_Track,
		)
		rt.drag.detached_anchor_x = anchor_x
		rt.drag.detached_anchor_y = anchor_y
		rt.drag.detached_anchor_valid = true
		rt.drag.presentation_state = .Detached
	}
}

// While magnetized, pointer drift is ignored only for reorder hit testing.
// Drag_Session.x/y always retain the real pointer position for host behavior.
drag_target_coordinates :: proc(rt: ^Runtime, x, y: f32) -> (target_x, target_y: f32) {
	target_x, target_y = x, y
	if rt != nil && rt.drag.tracking.mode == .Horizontal_Magnetic &&
		rt.drag.presentation_state == .Horizontal_Track {
		target_y = rt.drag.track_bounds.y+rt.drag.track_bounds.h*0.5
	}
	return
}

DRAG_AUTOSCROLL_EDGE :: 24.0
DRAG_AUTOSCROLL_MAX_SPEED :: 720.0

// drag_autoscroll_can_step reports whether an active local drag is within the
// edge zone of a scroll region that can still move in that direction. The
// native host uses this to schedule bounded ticks while the pointer is held
// still; ordinary pointer motion remains retained-only.
drag_autoscroll_can_step :: proc(rt: ^Runtime) -> bool {
	_, _, _, _, found := drag_autoscroll_edge(rt)
	return found
}

// drag_autoscroll_step advances the nearest scroll region under the pointer.
// elapsed_ns is capped so delayed wakeups cannot produce a large jump.
drag_autoscroll_step :: proc(rt: ^Runtime, elapsed_ns: u64) -> bool {
	region_id, direction, strength, horizontal, found := drag_autoscroll_edge(rt)
	if !found || elapsed_ns == 0 { return false }
	seconds := min(f32(elapsed_ns)*0.000000001, 0.05)
	region := scroll_region_state(rt, region_id)
	if horizontal {
		return scroll_region_set_offset_x(
			rt,
			region_id,
			region.offset_x + direction*DRAG_AUTOSCROLL_MAX_SPEED*strength*seconds,
			"horizontal drag edge autoscroll",
		)
	}
	return scroll_region_set_offset(
		rt,
		region_id,
		region.offset_y + direction*DRAG_AUTOSCROLL_MAX_SPEED*strength*seconds,
		"drag edge autoscroll",
	)
}

drag_autoscroll_edge :: proc(rt: ^Runtime) -> (region_id: Node_ID, direction, strength: f32, horizontal, found: bool) {
	if rt == nil || rt.drag.phase != .Dragging { return }
	_, horizontal_pointer_y := drag_target_coordinates(rt, rt.drag.x, rt.drag.y)
	for index := len(rt.order)-1; index >= 0; index -= 1 {
		id := rt.order[index]
		node, ok := rt.nodes[id]
		if !ok || !node_is_presentation_active(rt, id) || node.kind != .Scroll_Region { continue }
		viewport := layout_finalize_rect(node.scroll_viewport_bounds, rt.presentation_scale_x, rt.presentation_scale_y)
		if viewport.w <= 0 || viewport.h <= 0 { viewport = layout_node_finalized_geometry(rt, id).bounds }
		if node.scroll_axes == .Horizontal || node.scroll_axes == .Both {
			if horizontal_pointer_y >= viewport.y && horizontal_pointer_y <= viewport.y+viewport.h {
				left_distance := rt.drag.x-viewport.x
				right_distance := viewport.x+viewport.w-rt.drag.x
				if left_distance >= -DRAG_AUTOSCROLL_EDGE && left_distance < DRAG_AUTOSCROLL_EDGE && node.scroll_offset_x > 0 {
					return id, -1, clampf((DRAG_AUTOSCROLL_EDGE-left_distance)/DRAG_AUTOSCROLL_EDGE, 0.15, 1), true, true
				}
				max_scroll_x := maxf(node.scroll_content_width-node.scroll_viewport_width, 0)
				if right_distance >= -DRAG_AUTOSCROLL_EDGE && right_distance < DRAG_AUTOSCROLL_EDGE && node.scroll_offset_x < max_scroll_x {
					return id, 1, clampf((DRAG_AUTOSCROLL_EDGE-right_distance)/DRAG_AUTOSCROLL_EDGE, 0.15, 1), true, true
				}
			}
		}
		if rt.drag.x < viewport.x || rt.drag.x > viewport.x+viewport.w { continue }
		top_distance := rt.drag.y-viewport.y
		bottom_distance := viewport.y+viewport.h-rt.drag.y
		if top_distance >= -DRAG_AUTOSCROLL_EDGE && top_distance < DRAG_AUTOSCROLL_EDGE {
			if node.scroll_offset_y <= 0 { continue }
			return id, -1, clampf((DRAG_AUTOSCROLL_EDGE-top_distance)/DRAG_AUTOSCROLL_EDGE, 0.15, 1), false, true
		}
		if bottom_distance >= -DRAG_AUTOSCROLL_EDGE && bottom_distance < DRAG_AUTOSCROLL_EDGE {
			max_scroll := maxf(node.scroll_content_height-node.scroll_viewport_height, 0)
			if node.scroll_offset_y >= max_scroll { continue }
			return id, 1, clampf((DRAG_AUTOSCROLL_EDGE-bottom_distance)/DRAG_AUTOSCROLL_EDGE, 0.15, 1), false, true
		}
	}
	return
}

drag_process_pointer :: proc(rt: ^Runtime, event: Pointer_Event, hit: Node_ID) -> bool {
	if rt == nil { return false }
	if event.kind == .Move {
		if rt.drag.phase == .Candidate {
			dx := event.x-rt.drag.start_x
			dy := event.y-rt.drag.start_y
			if dx*dx+dy*dy >= DRAG_START_THRESHOLD*DRAG_START_THRESHOLD {
				if _, ok := rt.nodes[rt.drag.source_node]; !ok || !node_is_presentation_active(rt, rt.drag.source_node) {
					rt.drag = {}
					return false
				}
				rt.drag.phase = .Dragging
				rt.drag.x = event.x
				rt.drag.y = event.y
				if rt.drag.tracking.mode == .Horizontal_Magnetic {
					rt.drag.presentation_state = .Horizontal_Track
				}
				drag_preview_begin(rt)
				if rt.drag.tracking.mode == .Horizontal_Magnetic {
					drag_tracking_update_state(rt, event.x, event.y)
				}
				drag_update_target(rt, hit, event.x, event.y, false)
				rt.drag_event = Drag_Event{
					kind=.Started,
					drag_type=rt.drag.drag_type,
					source=rt.drag.source,
					target=rt.drag.target,
					position=rt.drag.position,
					pointer_x=event.x,
					pointer_y=event.y,
					has_pointer_position=true,
					presentation_state=rt.drag.presentation_state,
				}
				rt.drag_event_pending = true
			}
		}
		if rt.drag.phase == .Dragging {
			rt.drag.x = event.x
			rt.drag.y = event.y
			drag_tracking_update_state(rt, event.x, event.y)
			drag_update_target(rt, hit, event.x, event.y)
			drag_preview_pointer_moved(rt)
			return true
		}
	} else if event.kind == .Up {
		if rt.drag.phase == .Candidate {
			rt.drag = {}
		} else if rt.drag.phase == .Dragging {
			rt.drag.x = event.x
			rt.drag.y = event.y
			drag_tracking_update_state(rt, event.x, event.y)
			drag_update_target(rt, hit, event.x, event.y, false)
			if rt.drag.target != (Semantic_ID{}) && rt.drag.position != .None {
				rt.drag_event = Drag_Event{
					kind=.Dropped,
					drag_type=rt.drag.drag_type,
					source=rt.drag.source,
					target=rt.drag.target,
					position=rt.drag.position,
					pointer_x=event.x,
					pointer_y=event.y,
					has_pointer_position=true,
					presentation_state=rt.drag.presentation_state,
				}
				rt.drag_event_pending = true
			} else {
				rt.drag_event = Drag_Event{
					kind=.Cancelled, drag_type=rt.drag.drag_type, source=rt.drag.source,
					pointer_x=event.x, pointer_y=event.y, has_pointer_position=true,
					presentation_state=rt.drag.presentation_state,
				}
				rt.drag_event_pending = true
			}
			drag_clear_target_visual(rt)
			drag_preview_clear(rt)
			rt.drag = {}
			if node, ok := rt.nodes[rt.captured_node]; ok && node.pressed {
				node.pressed = false
				invalidate_interaction_paint(rt, node.id, "drag released")
			}
			rt.captured_node = 0
			rt.activation_node = 0
			return true
		}
	} else if event.kind == .Cancel {
		drag_cancel_session(rt)
	}
	return false
}
