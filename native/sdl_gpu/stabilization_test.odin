package alicorn_sdl_gpu

import "core:fmt"
import "core:testing"
import alicorn "../../runtime"

Description_Stabilization_Test_State :: struct {
	builds:             int,
	actions:            int,
	revision:           int,
	invalidate_always:  bool,
}

Restore_Stabilization_Test_State :: struct {
	request: alicorn.Scroll_Restore_Request,
	builds: int,
	first, last: int,
	owner: alicorn.Node_ID,
}

restore_stabilization_test_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	test_state := cast(^Restore_Stabilization_Test_State)state
	test_state.builds += 1
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="restore-stabilization-root",
		style=alicorn.layout_style(.Column, width=f32(logical_width), height=f32(logical_height)),
	)
	list := alicorn.virtual_list_begin(
		&ui,
		500,
		20,
		key=alicorn.key_string("restore-stabilization-list"),
		style=alicorn.layout_style(.Column, grow=1, clip=true),
		label="restore-stabilization-list",
		restore=test_state.request,
	)
	test_state.owner = list.scroll.id
	test_state.first, test_state.last = list.first, list.last
	for index := list.first; index < list.last; index += 1 {
		alicorn.text(&ui, fmt.tprintf("row %d", index), key=fmt.tprintf("restore-stabilization-row-%d", index), style=alicorn.layout_style(.Row, height=20))
	}
	alicorn.virtual_list_end(&ui, list)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

description_stabilization_test_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	test_state := cast(^Description_Stabilization_Test_State)state
	test_state.builds += 1
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="stabilization-test-root",
		style=alicorn.layout_style(.Column, width=f32(logical_width), height=f32(logical_height), padding=8),
	)
	if alicorn.button(&ui, "Mutate", key=alicorn.key_string("stabilization-action"), style=alicorn.layout_style(.Row, width=100, height=32)) {
		test_state.actions += 1
		test_state.revision += 1
		alicorn.invalidate_root(rt, "stabilization test mutation during description")
	}
	if test_state.invalidate_always {
		alicorn.invalidate_root(rt, "stabilization test persistent invalidation")
	}
	alicorn.text(&ui, fmt.tprintf("revision %d", test_state.revision))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

@(test)
test_native_host_coalesces_in_build_invalidation_before_presentation :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	state: Description_Stabilization_Test_State
	application := Application{state=rawptr(&state), build=description_stabilization_test_build}
	metrics := Window_Metrics{logical_width=320, logical_height=200, display_scale=1}
	timing: Native_Host_Timing

	alicorn.invalidate_root(&rt, "stabilization test initial description")
	initial := native_application_build_until_stable(&application, &rt, &metrics, &timing)
	testing.expect(t, initial.stable, "the initial description should stabilize")
	button_bounds: alicorn.Rect
	for node_id in rt.order {
		if node, found := rt.nodes[node_id]; found && node.kind == .Button && node.label == "Mutate" {
			button_bounds = node.bounds
		}
	}
	testing.expect(t, button_bounds.w > 0 && button_bounds.h > 0, "the test action should be laid out for pointer activation")
	x, y := button_bounds.x+button_bounds.w/2, button_bounds.y+button_bounds.h/2
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Down, x=x, y=y, button=1})
	alicorn.invalidate_root(&rt, "stabilization test pointer down")
	_ = native_application_build_until_stable(&application, &rt, &metrics, &timing)
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Up, x=x, y=y, button=1})
	alicorn.invalidate_root(&rt, "stabilization test pointer up")
	result := native_application_build_until_stable(&application, &rt, &metrics, &timing)
	testing.expect(t, result.stable && result.passes == 2, "the host should rebuild once after an action mutates state during description")
	testing.expect(t, state.actions == 1 && state.revision == 1,
		"coalescing must not dispatch a consumed pointer activation more than once")
	testing.expect(t, !rt.invalidated, "the stabilized description should leave no follow-up invalidation")
	final_revision_visible := false
	for node_id in rt.order {
		if node, found := rt.nodes[node_id]; found && node.text == "revision 1" { final_revision_visible = true }
	}
	testing.expect(t, final_revision_visible, "only the final state should remain in the retained description before submission")
	testing.expect(t, alicorn.frame_needs_submission(&rt), "the stable result should yield one pending presentation")
	alicorn.frame_submission_succeeded(&rt)
	testing.expect(t, !alicorn.frame_needs_submission(&rt), "one successful submit should consume all coalesced description work")
}

@(test)
test_native_host_description_stabilization_is_bounded :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	state := Description_Stabilization_Test_State{invalidate_always=true}
	application := Application{state=rawptr(&state), build=description_stabilization_test_build}
	metrics := Window_Metrics{logical_width=320, logical_height=200, display_scale=1}
	timing: Native_Host_Timing

	alicorn.invalidate_root(&rt, "stabilization bound test initial description")
	result := native_application_build_until_stable(&application, &rt, &metrics, &timing)
	testing.expect(t, !result.stable && result.passes == NATIVE_DESCRIPTION_STABILIZATION_LIMIT,
		"a pathological self-invalidating application must stop at the host's pass limit")
	testing.expect(t, state.builds == NATIVE_DESCRIPTION_STABILIZATION_LIMIT && rt.invalidated,
		"the bounded fallback should preserve remaining work for the next host iteration")
	testing.expect(t, timing.application_stabilization_limit_hits == 1,
		"the diagnostic counter should record the stabilization limit hit")
}

@(test)
test_native_host_presents_virtualized_scroll_restore_after_one_correction :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 320})
	defer alicorn.destroy_runtime(&rt)
	state := Restore_Stabilization_Test_State{
		request=alicorn.Scroll_Restore_Request{token=alicorn.restore_token_next(&rt), offset_y=9900},
	}
	application := Application{state=rawptr(&state), build=restore_stabilization_test_build}
	metrics := Window_Metrics{logical_width=320, logical_height=320, display_scale=1}
	timing: Native_Host_Timing

	alicorn.invalidate_root(&rt, "restore stabilization test initial description")
	result := native_application_build_until_stable(&application, &rt, &metrics, &timing)
	state_after, found := alicorn.restore_state_query(&rt, .Scroll, state.owner, state.request.token)
	testing.expect(t, result.stable && result.passes == 2 && state.builds == 2,
		"the host should run exactly one corrective description when final geometry changes a virtual range")
	testing.expect(t, found && state_after.outcome == .Clamped && state_after.resolved.y == 9680,
		"the final scroll restore should report its actual clamped offset")
	testing.expect(t, state.first == 484 && state.last == 500,
		"the first presented virtual range should match the restored final viewport")
	testing.expect(t, !rt.invalidated && alicorn.frame_needs_submission(&rt),
		"the corrective description should leave one stable presentation pending")
	alicorn.frame_submission_succeeded(&rt)
	testing.expect(t, !alicorn.frame_needs_submission(&rt), "one successful submit should acknowledge the stable result")

	_ = alicorn.scroll_region_set_offset(&rt, state.owner, 100, "user scroll after restore completed")
	result = native_application_build_until_stable(&application, &rt, &metrics, &timing)
	testing.expect(t, result.stable && result.passes == 1 && state.first == 5 &&
		alicorn.scroll_region_state(&rt, state.owner).offset_y == 100,
		"repeating a completed token must not restore over a later user scroll")
}
