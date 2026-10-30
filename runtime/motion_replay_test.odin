package alicorn

import "core:testing"

Motion_Replay_Result :: struct {
	after_b: Motion_Diagnostic_Owner_Snapshot,
	after_c: Motion_Diagnostic_Owner_Snapshot,
	after_restore: Motion_Diagnostic_Owner_Snapshot,
	trace_sequence: u64,
	stats: Motion_Diagnostic_Stats,
	retired: bool,
	retargets: int,
	saw_reduced_motion: bool,
	saw_hidden_gap: bool,
	saw_settlement: bool,
}

motion_replay_has_kind :: proc(rt: ^Runtime, kind: Motion_Diagnostic_Kind) -> bool {
	for offset in 0..<motion_diagnostics_event_count(rt) {
		event, found := motion_diagnostics_event_recent(rt, offset)
		if found && event.kind == kind { return true }
	}
	return false
}

// motion_replay_fixture is the deterministic application-event log used by
// both runs. The only difference is how often the retained response is sampled
// between identical target-change timestamps.
motion_replay_fixture :: proc(extra_irregular_samples: bool) -> Motion_Replay_Result {
	rt := new_runtime(Rect{0, 0, 320, 180}, Runtime_Config{trace_capacity=128})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	config := Motion_Config{omega=13, position_tolerance=0.01, velocity_tolerance=0.05}
	source := Source_Site{"motion_replay_fixture.odin", 25, 5, "selected tab indicator"}
	cause_a := Cause_Context{id=701, kind=.Pointer, action_id=Action_ID(1)}
	cause_b := Cause_Context{id=702, kind=.Pointer, action_id=Action_ID(2)}
	cause_c := Cause_Context{id=703, kind=.Pointer, action_id=Action_ID(3)}
	target_a := Motion_Target{translation=Motion_Vector2{120, 0}, has_translation=true}
	target_b := Motion_Target{translation=Motion_Vector2{260, 0}, has_translation=true}
	target_c := Motion_Target{translation=Motion_Vector2{40, 0}, has_translation=true}
	_ = motion_clock_set_time(&rt, Motion_Time(0), .Injected)
	_ = motion_apply_intent(&rt, child, target_a, .Settle, source=source, cause=cause_a)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(7_000_000))
		_ = motion_tick(&rt, Motion_Time(31_000_000))
		_ = motion_tick(&rt, Motion_Time(66_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(53_000_000))
	}
	_ = motion_clock_set_time(&rt, Motion_Time(100_000_000), .Injected)
	_ = motion_apply_intent(&rt, child, target_b, .Settle, source=source, cause=cause_b)
	result := Motion_Replay_Result{}
	result.after_b = motion_diagnostics_owner_snapshot(&rt, child)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(109_000_000))
		_ = motion_tick(&rt, Motion_Time(141_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(137_000_000))
	}
	_ = motion_clock_set_time(&rt, Motion_Time(160_000_000), .Injected)
	_ = motion_apply_intent(&rt, child, target_c, .Settle, source=source, cause=cause_c)
	result.after_c = motion_diagnostics_owner_snapshot(&rt, child)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(171_000_000))
		_ = motion_tick(&rt, Motion_Time(219_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(204_000_000))
	}
	motion_diagnostic_host_event(&rt, .Host_Suspended, Motion_Time(280_000_000), source=.Injected)
	// No intermediate samples represent the hidden interval. Restore evaluates
	// the same analytic response directly at the supplied current timestamp.
	_ = motion_tick(&rt, Motion_Time(900_000_000))
	motion_diagnostic_host_event(&rt, .Hidden_Gap_Fast_Forward,
		Motion_Time(900_000_000), 620_000_000, .Injected)
	result.after_restore = motion_diagnostics_owner_snapshot(&rt, child)
	result.saw_settlement = motion_replay_has_kind(&rt, .Settled)
	if node, found := rt.nodes[child]; found { node.style_environment.accessibility.reduce_motion = true }
	_ = motion_clock_set_time(&rt, Motion_Time(901_000_000), .Injected)
	target_d := Motion_Target{translation=Motion_Vector2{300, 0}, has_translation=true}
	_ = motion_apply_intent(&rt, child, target_d, .Settle, source=source,
		cause=Cause_Context{id=704, kind=.Keyboard, action_id=Action_ID(4)})
	result.saw_reduced_motion = motion_replay_has_kind(&rt, .Reduced_Motion_Rewrite)
	result.saw_hidden_gap = motion_replay_has_kind(&rt, .Hidden_Gap_Fast_Forward)
	for offset in 0..<motion_diagnostics_event_count(&rt) {
		event, found := motion_diagnostics_event_recent(&rt, offset)
		if found && event.kind == .Retarget { result.retargets += 1 }
	}
	invalidate_root(&rt, "virtual replay retires the selected marker")
	_, _, _ = motion_retained_test_build(&rt, false)
	_, result.retired = rt.motion_owners[child]
	result.retired = !result.retired && motion_replay_has_kind(&rt, .Owner_Retired)
	result.trace_sequence = rt.motion_diagnostics.sequence
	result.stats = motion_diagnostics_stats(&rt)
	return result
}

motion_replay_near :: proc(a, b: f64, tolerance: f64 = 0.00001) -> bool {
	return abs(a-b) <= tolerance
}

motion_replay_expect_equal_checkpoint :: proc(t: ^testing.T, left, right: Motion_Diagnostic_Owner_Snapshot) {
	testing.expect(t, left.valid && right.valid && left.owner == right.owner && left.generation == right.generation,
		"replay checkpoints should refer to the same retained owner generation")
	testing.expect(t, motion_replay_near(left.translation.target.x, right.translation.target.x) &&
		motion_replay_near(left.translation.presented.x, right.translation.presented.x) &&
		motion_replay_near(left.translation.velocity.x, right.translation.velocity.x),
		"uneven sample histories should reproduce target, presentation and residual velocity at the same event time")
}

@(test)
test_motion_virtual_replay_is_sampling_history_independent_and_traces_lifecycle :: proc(t: ^testing.T) {
	sparse := motion_replay_fixture(false)
	dense := motion_replay_fixture(true)
	motion_replay_expect_equal_checkpoint(t, sparse.after_b, dense.after_b)
	motion_replay_expect_equal_checkpoint(t, sparse.after_c, dense.after_c)
	motion_replay_expect_equal_checkpoint(t, sparse.after_restore, dense.after_restore)
	testing.expect(t, sparse.retargets == 2 && dense.retargets == 2 && sparse.saw_settlement && dense.saw_settlement,
		"the replay should preserve both interrupted retargets and the post-suspend settlement")
	testing.expect(t, sparse.saw_reduced_motion && dense.saw_reduced_motion &&
		sparse.saw_hidden_gap && dense.saw_hidden_gap && sparse.retired && dense.retired,
		"the lifecycle trace should include reduced motion, hidden-gap fast-forward and owner retirement")
	testing.expect(t, sparse.trace_sequence == dense.trace_sequence &&
		sparse.stats.sample_ticks != dense.stats.sample_ticks,
		"transition history should be cadence-independent while aggregate sampling work reflects actual samples")
}
