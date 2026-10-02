package alicorn

import "core:testing"

DRAG_TEST_TYPE :: Drag_Type(41)
DRAG_TEST_SOURCE :: Semantic_ID{namespace=701, value=1}
DRAG_TEST_TARGET :: Semantic_ID{namespace=701, value=2}
DRAG_SCROLL_SOURCE :: Semantic_ID{namespace=702, value=1}
DRAG_SCROLL_TARGET :: Semantic_ID{namespace=702, value=2}
DRAG_TEST_UI_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

drag_test_build :: proc(rt: ^Runtime, include_source := true, target_width: f32 = 180) -> (source: Node_ID, target_container: Node_ID, target_button: Node_ID) {
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(&ui, .Root, label="drag-test-root", key=key_string("drag-test-root"), style=layout_style(.Row, width=400, height=100, gap=20, padding=10))
	if include_source {
		source, _ = button_ex(&ui, "source", key="drag-test-source", style=layout_style(width=80, height=50))
		_ = semantic_bind(&ui, DRAG_TEST_SOURCE)
		_ = drag_source(&ui, DRAG_TEST_TYPE, DRAG_TEST_SOURCE)
	}
	target_container = container_begin_simple(&ui, .Container, label="drop-group", key=key_string("drag-test-target-container"), style=layout_style(.Row, width=target_width, height=50))
	_ = drop_target(&ui, DRAG_TEST_TYPE, DRAG_TEST_TARGET, .Between_Horizontal)
	target_button, _ = button_ex(&ui, "nested target", key="drag-test-target-button", style=layout_style(width=170, height=45))
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_drag_requires_threshold_and_keeps_click_activation :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 100})
	defer destroy_runtime(&rt)
	source, _, _ := drag_test_build(&rt)
	if source == 0 { testing.expect(t, false, "drag source should be retained"); return }
	node := rt.nodes[source]
	x := node.bounds.x+node.bounds.w/2
	y := node.bounds.y+node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=x+2, y=y+1})
	testing.expect(t, rt.drag.phase == .Candidate, "motion below the threshold should remain an ordinary click candidate")
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x+2, y=y+1, button=POINTER_BUTTON_PRIMARY})
	testing.expect(t, rt.drag.phase == .Idle && rt.activation_node == source,
		"a press released before crossing the threshold should preserve ordinary button activation")
	_, event_pending := drag_event_take(&rt)
	testing.expect(t, !event_pending, "a normal click should not emit a drag event")
}

@(test)
test_drag_resolves_ancestor_targets_and_emits_only_semantic_transitions :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 100})
	defer destroy_runtime(&rt)
	source, target_container, target_button := drag_test_build(&rt)
	if source == 0 || target_container == 0 || target_button == 0 {
		testing.expect(t, false, "source, drop target, and nested hit target should be retained")
		return
	}
	source_node := rt.nodes[source]
	target_node := rt.nodes[target_container]
	hit_node := rt.nodes[target_button]
	sx := source_node.bounds.x+source_node.bounds.w/2
	sy := source_node.bounds.y+source_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=sx, y=sy, button=POINTER_BUTTON_PRIMARY})
	rt.invalidated = false
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=sx+2, y=sy})
	testing.expect(t, rt.drag.phase == .Candidate, "small movement should not start a drag")
	left_x := target_node.bounds.x+2
	y := hit_node.bounds.y+hit_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=left_x, y=y})
	event, found := drag_event_take(&rt)
	testing.expect(t, found && event.kind == .Started, "crossing the threshold should emit one Started event")
	testing.expect(t, event.source == DRAG_TEST_SOURCE && event.target == DRAG_TEST_TARGET && event.position == .Before,
		"hit testing a nested control should resolve its accepting ancestor and before position")
	testing.expect(t, rt.drag.target_node == target_container && rt.nodes[target_container].drop_position == .Before,
		"the retained target feedback should belong to the accepting ancestor")
	testing.expect(t, !rt.invalidated, "starting and highlighting a drag should not request an application-description rebuild")

	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=left_x+1, y=y})
	_, found = drag_event_take(&rt)
	testing.expect(t, !found, "motion inside the same target position should not emit another app event")
	testing.expect(t, !rt.invalidated, "pointer motion within a target should remain retained-only work")

	// The point is in blank space inside the declared target container, past
	// the narrower nested button. Active drags may hit that background surface.
	right_x := target_node.bounds.x+target_node.bounds.w-2
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=right_x, y=y})
	event, found = drag_event_take(&rt)
	testing.expect(t, found && event.kind == .Target_Changed && event.position == .After,
		"crossing a tab-like target midpoint should emit a semantic Before-to-After transition")
	testing.expect(t, !rt.invalidated, "changing the insertion side should not rebuild the app description")

	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=right_x, y=y, button=POINTER_BUTTON_PRIMARY})
	event, found = drag_event_take(&rt)
	testing.expect(t, found && event.kind == .Dropped && event.target == DRAG_TEST_TARGET && event.position == .After,
		"release on an accepted target should deliver one completed drop")
	testing.expect(t, rt.drag.phase == .Idle && rt.captured_node == 0 && rt.activation_node == 0,
		"a completed drag should release capture and must not activate its source button")
}

@(test)
test_drag_target_refreshes_after_rebuild_without_pointer_motion :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 100})
	defer destroy_runtime(&rt)
	source, target_container, target_button := drag_test_build(&rt)
	if source == 0 || target_container == 0 || target_button == 0 {
		testing.expect(t, false, "source and drop target should be retained")
		return
	}
	source_node := rt.nodes[source]
	target_node := rt.nodes[target_container]
	hit_node := rt.nodes[target_button]
	sx := source_node.bounds.x+source_node.bounds.w/2
	sy := source_node.bounds.y+source_node.bounds.h/2
	pointer_x := target_node.bounds.x+3
	pointer_y := hit_node.bounds.y+hit_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=sx, y=sy, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=pointer_x, y=pointer_y})
	started, started_ok := drag_event_take(&rt)
	testing.expect(t, started_ok && started.kind == .Started && started.position == .Before,
		"the pointer should start over the leading side of the original target")

	// Simulate a virtualized/autoscrolled rebuild that changes target geometry
	// while the host pointer remains stationary.
	_, _, _ = drag_test_build(&rt, target_width=4)
	drag_refresh_target(&rt)
	changed, changed_ok := drag_event_take(&rt)
	testing.expect(t, changed_ok && changed.kind == .Target_Changed &&
		changed.target == DRAG_TEST_TARGET && changed.position == .After,
		"a stationary pointer should retarget when rebuilt geometry moves the target midpoint beneath it")
	testing.expect(t, rt.drag.position == .After,
		"retained insertion feedback should follow the refreshed semantic target position")
}

@(test)
test_drag_source_identity_survives_virtualized_node_retirement :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 100})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, DRAG_TEST_UI_FONT_DATA), "drag preview test UI font should load")
	source, _, target_button := drag_test_build(&rt)
	if source == 0 || target_button == 0 { testing.expect(t, false, "drag test controls should be retained"); return }
	source_node := rt.nodes[source]
	target_node := rt.nodes[target_button]
	sx := source_node.bounds.x+source_node.bounds.w/2
	sy := source_node.bounds.y+source_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=sx, y=sy, button=POINTER_BUTTON_PRIMARY})
	rt.invalidated = false
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=target_node.bounds.x+target_node.bounds.w/2, y=target_node.bounds.y+target_node.bounds.h/2})
	started, started_ok := drag_event_take(&rt)
	testing.expect(t, started_ok && started.kind == .Started && started.source == DRAG_TEST_SOURCE,
		"a stable semantic source identity should be captured when the drag starts")
	testing.expect(t, rt.drag_preview.ready && rt.drag_preview.run.value == "source",
		"starting a local drag should retain a shaped source-label preview")
	testing.expect(t, drag_source_opacity(&rt, source) == DRAG_SOURCE_OPACITY,
		"the active source should be dimmed while its preview follows the pointer")
	ui, presentation_ready := begin_presentation_frame(&rt)
	if presentation_ready { end_presentation_frame(&ui) }
	preview_card_found, preview_text_found := false, false
	for command in rt.display {
		if command.node != 0 { continue }
		if command.kind == .Button { preview_card_found = true }
		if command.kind == .Text && command.text == "source" { preview_text_found = true }
	}
	testing.expect(t, presentation_ready && preview_card_found && preview_text_found,
		"the retained display should compose a non-hit-testable card and source label for the drag preview")
	frames_before_motion := rt.stats.frames_built
	drag_x_before_motion, drag_y_before_motion := rt.drag.x, rt.drag.y
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=drag_x_before_motion+1, y=drag_y_before_motion+1})
	testing.expect(t, rt.drag.x == drag_x_before_motion+1 && rt.drag.y == drag_y_before_motion+1,
		"the drag preview position should track retained pointer coordinates")
	testing.expect(t, rt.stats.frames_built == frames_before_motion && !rt.invalidated,
		"drag preview pointer motion should not rebuild application descriptions")

	invalidate_root(&rt, "retire virtualized drag source")
	_, target_container_after, target_button_after := drag_test_build(&rt, include_source=false)
	testing.expect(t, rt.drag.phase == .Dragging && rt.drag.source == DRAG_TEST_SOURCE,
		"retiring the source node during virtualization should not invalidate the semantic drag session")
	testing.expect(t, rt.drag_preview.ready && rt.drag_preview.run.value == "source",
		"the drag preview should remain available after virtualization retires its source row")
	if target_container_after == 0 || target_button_after == 0 { testing.expect(t, false, "drop target should remain available after source virtualization"); return }
	ui, presentation_ready = begin_presentation_frame(&rt)
	if presentation_ready { end_presentation_frame(&ui) }
	preview_text_found = false
	for command in rt.display {
		if command.node == 0 && command.kind == .Text && command.text == "source" { preview_text_found = true }
	}
	testing.expect(t, preview_text_found, "virtualized source retirement should not remove the pointer-following preview")
	target_node = rt.nodes[target_button_after]
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=target_node.bounds.x+target_node.bounds.w/2, y=target_node.bounds.y+target_node.bounds.h/2, button=POINTER_BUTTON_PRIMARY})
	dropped, dropped_ok := drag_event_take(&rt)
	testing.expect(t, dropped_ok && dropped.kind == .Dropped && dropped.source == DRAG_TEST_SOURCE,
		"the completed drop should report the stable source identity without dereferencing its retired node")
	ui, presentation_ready = begin_presentation_frame(&rt)
	if presentation_ready { end_presentation_frame(&ui) }
	preview_commands_remain := false
	for command in rt.display { if command.node == 0 { preview_commands_remain = true } }
	testing.expect(t, !rt.drag_preview.ready && !preview_commands_remain && drag_source_opacity(&rt, source) == 1,
		"drop completion should remove the ghost and restore the source presentation state")
}

@(test)
test_drag_cancel_releases_capture_and_delivers_cancellation :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 100})
	defer destroy_runtime(&rt)
	source, _, target_button := drag_test_build(&rt)
	if source == 0 || target_button == 0 { testing.expect(t, false, "drag test controls should be retained"); return }
	source_node := rt.nodes[source]
	target_node := rt.nodes[target_button]
	sx := source_node.bounds.x+source_node.bounds.w/2
	sy := source_node.bounds.y+source_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=sx, y=sy, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=target_node.bounds.x+target_node.bounds.w/2, y=target_node.bounds.y+target_node.bounds.h/2})
	_, _ = drag_event_take(&rt)
	_ = process_pointer(&rt, Pointer_Event{kind=.Cancel})
	event, found := drag_event_take(&rt)
	testing.expect(t, found && event.kind == .Cancelled && event.source == DRAG_TEST_SOURCE,
		"host cancellation should notify the application and clear the active drag")
	testing.expect(t, rt.drag.phase == .Idle && rt.captured_node == 0 && rt.activation_node == 0,
		"cancellation should release pointer capture and suppress click activation")
}

drag_autoscroll_test_build :: proc(rt: ^Runtime) -> (source: Node_ID, scroll: Node_ID, target: Node_ID) {
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(&ui, .Root, label="drag-scroll-root", key=key_string("drag-scroll-root"), style=layout_style(.Column, width=240, height=240, gap=8))
	source, _ = button_ex(&ui, "source", key="drag-scroll-source", style=layout_style(width=100, height=36))
	_ = drag_source(&ui, DRAG_TEST_TYPE, DRAG_SCROLL_SOURCE)
	region := scroll_region_begin(&ui, key=key_string("drag-scroll-region"), viewport_height=150, content_height=900, style=layout_style(.Column, width=240, height=150), label="drag-scroll-region")
	scroll = region.id
	target, _ = button_ex(&ui, "target", key="drag-scroll-target", style=layout_style(width=180, height=36))
	_ = drop_target(&ui, DRAG_TEST_TYPE, DRAG_SCROLL_TARGET, .On)
	scroll_region_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_drag_autoscroll_repeats_at_scroll_edges_without_pointer_motion :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 240})
	defer destroy_runtime(&rt)
	source, scroll, target := drag_autoscroll_test_build(&rt)
	if source == 0 || scroll == 0 || target == 0 {
		testing.expect(t, false, "drag autoscroll test nodes should be retained")
		return
	}
	source_node := rt.nodes[source]
	viewport := scroll_region_state(&rt, scroll).viewport_bounds
	start_x := source_node.bounds.x+source_node.bounds.w/2
	start_y := source_node.bounds.y+source_node.bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=start_x, y=start_y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=viewport.x+viewport.w/2, y=viewport.y+viewport.h-2})
	_, started := drag_event_take(&rt)
	initial_offset := scroll_region_offset(&rt, scroll)
	testing.expect(t, started && drag_autoscroll_can_step(&rt), "a drag held near a scroll edge should request a bounded host tick")
	rt.invalidated = false
	_ = drag_autoscroll_step(&rt, 16_000_000)
	after_downward_tick := scroll_region_offset(&rt, scroll)
	testing.expect(t, after_downward_tick > initial_offset, "one scheduled edge tick should advance the scroll region without another pointer move")
	testing.expect(t, rt.invalidated, "scrolling must rebuild the virtualized viewport so newly visible rows can be described")

	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=viewport.x+viewport.w/2, y=viewport.y+2})
	_ = drag_autoscroll_step(&rt, 16_000_000)
	testing.expect(t, scroll_region_offset(&rt, scroll) < after_downward_tick, "moving to the top edge should autoscroll back toward earlier rows")
	_ = process_pointer(&rt, Pointer_Event{kind=.Cancel})
	event, cancelled := drag_event_take(&rt)
	testing.expect(t, cancelled && event.kind == .Cancelled && !drag_autoscroll_can_step(&rt), "canceling the drag should stop scheduled autoscroll")
}
