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
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, x, y, 1})
	alicorn.invalidate_root(&rt, "stabilization test pointer down")
	_ = native_application_build_until_stable(&application, &rt, &metrics, &timing)
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, x, y, 1})
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
