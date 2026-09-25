package alicorn

import "core:testing"
import "core:strings"

causality_test_build_root :: proc(ui: ^UI) {
	container_begin_simple(ui, .Root, label="causality-test-root", key=key_string("causality-test-root"), style=layout_style())
	text(ui, "Causal trace", style=layout_style(.Row, height=24))
	container_end(ui)
}

@(test)
test_cause_flows_through_command_invalidation_frame_and_submit :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)

	cause := cause_begin(&rt, .Keyboard, "F key")
	action_id := Action_ID(17)
	trace_action(&rt, action_id, "Fit Selection")
	trace_mutation(&rt, "Scope timeline viewport changed")
	invalidate_root(&rt, "fit selection")
	cause_end(&rt, cause)

	ui, should_build := begin_frame(&rt)
	testing.expect(t, should_build, "a caused invalidation should request one app frame")
	if !should_build { return }
	causality_test_build_root(&ui)
	end_frame(&ui)
	frame_submission_succeeded(&rt)

	events := trace_snapshot(&rt)
	defer delete(events)
	found: [Trace_Kind]bool
	for event in events {
		if event.kind == .Action || event.kind == .Mutation || event.kind == .Invalidation ||
			event.kind == .Reconcile || event.kind == .Layout || event.kind == .Paint ||
			event.kind == .Composite || event.kind == .Submit {
			testing.expect(t, event.cause_id == cause.cause.id,
				"command, mutation, invalidation, frame work, and submission should share one cause ID")
			testing.expect(t, event.cause_kind == .Keyboard,
				"the transaction should preserve its external keyboard origin")
			testing.expect(t, event.action_id == action_id,
				"the semantic action ID should flow through the rest of its frame")
		}
		found[event.kind] = true
	}
	expected_kinds := [8]Trace_Kind{
		Trace_Kind.Action, Trace_Kind.Mutation, Trace_Kind.Invalidation, Trace_Kind.Reconcile,
		Trace_Kind.Layout, Trace_Kind.Paint, Trace_Kind.Composite, Trace_Kind.Submit,
	}
	for kind in expected_kinds {
		testing.expect(t, found[kind], "the causal transaction should include every expected lifecycle stage")
	}
	for event in events {
		if event.kind == .Action {
			testing.expect(t, event.action_id == action_id && event.reason == "Fit Selection",
				"semantic action records should preserve the action ID and readable label")
		}
	}

	sequence_before_idle := rt.trace.sequence
	cause_sequence_before_idle := rt.cause_sequence
	_, idle_build := begin_frame(&rt)
	testing.expect(t, !idle_build, "a settled runtime must not build a second frame")
	testing.expect(t, rt.trace.sequence == sequence_before_idle && rt.cause_sequence == cause_sequence_before_idle,
		"idle checks must not manufacture trace events or causes")
}

@(test)
test_mixed_pending_causes_do_not_blame_the_latest_input :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)

	keyboard := cause_begin(&rt, .Keyboard, "first input")
	invalidate_root(&rt, "first input invalidation")
	cause_end(&rt, keyboard)
	pointer := cause_begin(&rt, .Pointer, "second input")
	invalidate_root(&rt, "second input invalidation")
	cause_end(&rt, pointer)

	ui, should_build := begin_frame(&rt)
	testing.expect(t, should_build, "coalesced invalidations should still build once")
	if !should_build { return }
	causality_test_build_root(&ui)
	end_frame(&ui)
	frame_submission_succeeded(&rt)

	events := trace_snapshot(&rt)
	defer delete(events)
	first_cause_seen, second_cause_seen := false, false
	for event in events {
		if event.kind == .Invalidation && event.reason == "first input invalidation" {
			first_cause_seen = event.cause_id == keyboard.cause.id && event.cause_kind == .Keyboard
		}
		if event.kind == .Invalidation && event.reason == "second input invalidation" {
			second_cause_seen = event.cause_id == pointer.cause.id && event.cause_kind == .Pointer
		}
		if event.kind == .Reconcile || event.kind == .Layout || event.kind == .Paint || event.kind == .Composite || event.kind == .Submit {
			testing.expect(t, event.cause_id == 0,
				"a frame coalescing independent causes must remain explicitly unattributed")
		}
	}
	testing.expect(t, first_cause_seen && second_cause_seen,
		"the original input/invalidation records should retain their distinct cause identities")
}

@(test)
test_cause_trace_ring_is_bounded_and_sequences_remain_ordered :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 100}, Runtime_Config{trace_capacity=4})
	defer destroy_runtime(&rt)

	first := cause_begin(&rt, .Keyboard, "first")
	trace_mutation(&rt, "first mutation")
	cause_end(&rt, first)
	second := cause_begin(&rt, .Async_Wake, "second")
	trace_mutation(&rt, "second mutation")
	cause_end(&rt, second)
	third := cause_begin(&rt, .Pointer, "third")
	trace_mutation(&rt, "third mutation")
	cause_end(&rt, third)

	events := trace_snapshot(&rt)
	defer delete(events)
	testing.expect(t, len(events) == 4, "trace history must remain at the configured fixed capacity")
	for index in 1..<len(events) {
		testing.expect(t, events[index-1].sequence < events[index].sequence,
			"ring snapshots should remain ordered after bounded overwrite")
	}
	testing.expect(t, first.cause.id < second.cause.id && second.cause.id < third.cause.id,
		"cause IDs must remain monotonically increasing even as old trace entries roll off")
}

@(test)
test_pointer_press_motion_release_share_cause_but_hover_motion_does_not_create_one :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 100}, Runtime_Config{trace_capacity=16})
	defer destroy_runtime(&rt)

	down := pointer_cause_begin(&rt, .Down)
	down_id := down.cause.id
	record_trace(&rt, .Pointer, 9, "pointer down")
	cause_end(&rt, down)

	motion := pointer_cause_begin(&rt, .Move)
	testing.expect(t, motion.cause.id == down_id, "captured pointer motion should continue the press cause")
	record_trace(&rt, .Pointer, 9, "captured pointer move")
	cause_end(&rt, motion)

	up := pointer_cause_begin(&rt, .Up)
	testing.expect(t, up.cause.id == down_id, "pointer release should continue the press cause")
	trace_action(&rt, Action_ID(23), "Select Event")
	record_trace(&rt, .Pointer, 9, "pointer up")
	cause_end(&rt, up)

	sequence_before_hover := rt.cause_sequence
	hover := pointer_cause_begin(&rt, .Move)
	testing.expect(t, hover.cause.id == 0, "uncaptured hover motion should not start a transaction")
	cause_end(&rt, hover)
	testing.expect(t, rt.cause_sequence == sequence_before_hover,
		"hover-only motion should not manufacture causal identities")

	events := trace_snapshot(&rt)
	defer delete(events)
	command_found := false
	for event in events {
		if event.kind == .Action {
			command_found = true
			testing.expect(t, event.cause_id == down_id && event.cause_kind == .Pointer,
				"a semantic command dispatched on pointer-up should link to the whole gesture")
		}
	}
	testing.expect(t, command_found, "pointer gesture test should record its semantic command")
}

@(test)
test_async_completion_has_a_distinct_cause_through_submission :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180}, Runtime_Config{trace_capacity=48})
	defer destroy_runtime(&rt)

	wake := cause_begin(&rt, .Async_Wake, "worker completion")
	trace_mutation(&rt, "application applied worker result")
	invalidate_root(&rt, "worker result changed visible state")
	cause_end(&rt, wake)

	ui, should_build := begin_frame(&rt)
	testing.expect(t, should_build, "async completion should request a visible frame")
	if !should_build { return }
	causality_test_build_root(&ui)
	end_frame(&ui)
	frame_submission_succeeded(&rt)

	events := trace_snapshot(&rt)
	defer delete(events)
	for event in events {
		if event.kind == .Mutation || event.kind == .Invalidation || event.kind == .Reconcile ||
			event.kind == .Layout || event.kind == .Paint || event.kind == .Composite || event.kind == .Submit {
			testing.expect(t, event.cause_id == wake.cause.id && event.cause_kind == .Async_Wake,
				"async completion and the resulting runtime work should share their own cause")
		}
	}
}

@(test)
test_unscoped_explicit_invalidation_creates_application_cause :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180}, Runtime_Config{trace_capacity=32})
	defer destroy_runtime(&rt)

	invalidate_root(&rt, "programmatic model update")
	ui, should_build := begin_frame(&rt)
	testing.expect(t, should_build, "explicit app invalidation should request a frame")
	if !should_build { return }
	causality_test_build_root(&ui)
	end_frame(&ui)
	frame_submission_succeeded(&rt)

	events := trace_snapshot(&rt)
	defer delete(events)
	application_cause: u64
	for event in events {
		if event.kind == .Cause && event.cause_kind == .Application { application_cause = event.cause_id }
	}
	testing.expect(t, application_cause != 0, "unscoped invalidation should establish an application cause")
	for event in events {
		if event.kind == .Invalidation || event.kind == .Reconcile || event.kind == .Layout ||
			event.kind == .Paint || event.kind == .Composite || event.kind == .Submit {
			testing.expect(t, event.cause_id == application_cause && event.cause_kind == .Application,
				"programmatic invalidation should explain the frame it requested")
		}
	}
}

@(test)
test_runtime_action_metadata_is_explicit_and_identity_is_stable :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180}, Runtime_Config{trace_capacity=32})
	defer destroy_runtime(&rt)

	action_id := Action_ID(41)
	descriptor := Action_Descriptor{id=action_id, name="scope.fit_selection", label="Fit Selection"}
	initial_state := Action_State{enabled=true, checked=false}
	testing.expect(t, action_update(&rt, descriptor, initial_state), "runtime should accept a valid application action")
	stored_descriptor, stored_state, found := action_lookup(&rt, action_id)
	testing.expect(t, found && stored_descriptor.name == "scope.fit_selection" && stored_descriptor.label == "Fit Selection",
		"runtime should expose stable machine identity and readable label")
	testing.expect(t, stored_state.enabled && !stored_state.checked, "runtime should expose explicit action state")

	updated_state := Action_State{enabled=false, checked=true}
	testing.expect(t, action_update(&rt, descriptor, updated_state), "application may explicitly publish changed state")
	_, stored_state, found = action_lookup(&rt, action_id)
	testing.expect(t, found && !stored_state.enabled && stored_state.checked,
		"state refresh should not require hidden observation or polling")

	changed_name := Action_Descriptor{id=action_id, name="scope.different_action", label="Fit Selection"}
	testing.expect(t, !action_update(&rt, changed_name, updated_state), "one action ID must not silently change its stable machine name")
	_, stored_state, found = action_lookup(&rt, action_id)
	testing.expect(t, found && !stored_state.enabled && stored_state.checked,
		"rejected descriptor changes must leave the published action intact")

	cause := cause_begin(&rt, .Keyboard, "F key", action_id)
	trace_action(&rt, action_id, descriptor.label)
	cause_end(&rt, cause)
	inspection := inspect(&rt)
	defer delete(inspection)
	testing.expect(t, strings.contains(inspection, "scope.fit_selection · Fit Selection"),
		"runtime inspector should resolve causal action IDs to their metadata")
	testing.expect(t, strings.contains(inspection, "enabled=false checked=true"),
		"runtime inspector should report current enabled/checked state")
}
