package alicorn

import "core:testing"

Motion_Replay_Result :: struct {
	after_a: Motion_Diagnostic_Owner_Snapshot,
	after_b: Motion_Diagnostic_Owner_Snapshot,
	after_c: Motion_Diagnostic_Owner_Snapshot,
	after_suspend: Motion_Diagnostic_Owner_Snapshot,
	during_hidden: Motion_Diagnostic_Owner_Snapshot,
	after_restore: Motion_Diagnostic_Owner_Snapshot,
	trace_sequence: u64,
	stats: Motion_Diagnostic_Stats,
	retired: bool,
	retargets: int,
	unchanged_target_noops: int,
	active_when_suspended: bool,
	presentation_stayed_frozen: bool,
	reduced_preference_snapped: bool,
	saw_suspend: bool,
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
	_, child, preference_owner := motion_retained_test_build(&rt, true)
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
	result := Motion_Replay_Result{}
	result.after_a = motion_diagnostics_owner_snapshot(&rt, child)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(7_000_000))
		_ = motion_tick(&rt, Motion_Time(31_000_000))
		_ = motion_tick(&rt, Motion_Time(66_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(53_000_000))
	}
	_ = motion_clock_set_time(&rt, Motion_Time(100_000_000), .Injected)
	_ = motion_apply_intent(&rt, child, target_b, .Settle, source=source, cause=cause_b)
	result.after_b = motion_diagnostics_owner_snapshot(&rt, child)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(109_000_000))
		_ = motion_tick(&rt, Motion_Time(141_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(137_000_000))
	}
	// Repeating B at the same application-event time in both runs is a
	// declaration no-op: it must preserve velocity and avoid a new response.
	_ = motion_clock_set_time(&rt, Motion_Time(145_000_000), .Injected)
	_ = motion_apply_intent(&rt, child, target_b, .Settle, source=source, cause=cause_b)
	_ = motion_clock_set_time(&rt, Motion_Time(160_000_000), .Injected)
	_ = motion_apply_intent(&rt, child, target_c, .Settle, source=source, cause=cause_c)
	result.after_c = motion_diagnostics_owner_snapshot(&rt, child)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(171_000_000))
		_ = motion_tick(&rt, Motion_Time(219_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(204_000_000))
	}
	// A second decorative owner makes the preference transition explicit while
	// the main A→B→C response remains in flight for the hidden-window replay.
	_ = motion_clock_set_time(&rt, Motion_Time(220_000_000), .Injected)
	preference_target := Motion_Target{translation=Motion_Vector2{32, 0}, has_translation=true}
	preference_cause := Cause_Context{id=704, kind=.Keyboard, action_id=Action_ID(4)}
	_ = motion_apply_intent(&rt, preference_owner, preference_target, .Settle, source=source, cause=preference_cause)
	if extra_irregular_samples {
		_ = motion_tick(&rt, Motion_Time(230_000_000))
		_ = motion_tick(&rt, Motion_Time(245_000_000))
	} else {
		_ = motion_tick(&rt, Motion_Time(237_000_000))
	}
	if node, found := rt.nodes[preference_owner]; found { node.style_environment.accessibility.reduce_motion = true }
	_ = motion_clock_set_time(&rt, Motion_Time(250_000_000), .Injected)
	_ = motion_apply_intent(&rt, preference_owner, preference_target, .Settle, source=source, cause=preference_cause)
	preference_snapshot := motion_diagnostics_owner_snapshot(&rt, preference_owner)
	result.reduced_preference_snapped = preference_snapshot.valid && !preference_snapshot.translation.active &&
		preference_snapshot.translation.presented == preference_target.translation
	result.saw_reduced_motion = motion_replay_has_kind(&rt, .Reduced_Motion_Rewrite)
	activity_before_suspend := motion_activity(&rt)
	result.active_when_suspended = activity_before_suspend.active_owners > 0
	motion_diagnostic_host_event(&rt, .Host_Suspended, Motion_Time(280_000_000), source=.Injected)
	result.after_suspend = motion_diagnostics_owner_snapshot(&rt, child)
	result.saw_suspend = motion_replay_has_kind(&rt, .Host_Suspended)
	// No intermediate samples represent the hidden interval. Restore evaluates
	// the same analytic response directly at the supplied current timestamp.
	_ = motion_clock_set_time(&rt, Motion_Time(900_000_000), .Injected)
	// Inspection during suspension still reports the last presented sample. It
	// must not advance the owner just because the monotonic clock has advanced.
	result.during_hidden = motion_diagnostics_owner_snapshot(&rt, child)
	result.presentation_stayed_frozen = result.after_suspend.translation.presented == result.during_hidden.translation.presented &&
		result.after_suspend.translation.velocity == result.during_hidden.translation.velocity &&
		result.after_suspend.translation.sampled_at == result.during_hidden.translation.sampled_at
	_ = motion_tick(&rt, Motion_Time(900_000_000))
	motion_diagnostic_host_event(&rt, .Hidden_Gap_Fast_Forward,
		Motion_Time(900_000_000), 620_000_000, .Injected)
	result.after_restore = motion_diagnostics_owner_snapshot(&rt, child)
	result.saw_settlement = motion_replay_has_kind(&rt, .Settled)
	result.saw_hidden_gap = motion_replay_has_kind(&rt, .Hidden_Gap_Fast_Forward)
	for offset in 0..<motion_diagnostics_event_count(&rt) {
		event, found := motion_diagnostics_event_recent(&rt, offset)
		if found && event.kind == .Retarget { result.retargets += 1 }
		if found && event.kind == .Unchanged_Target { result.unchanged_target_noops += int(event.repeat_count) }
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
		motion_replay_near(left.translation.velocity.x, right.translation.velocity.x) &&
		left.intent == right.intent && left.source == right.source && left.cause == right.cause &&
		left.translation.config == right.translation.config && left.translation.mode == right.translation.mode,
		"uneven sample histories should reproduce cause, intent, target, presentation, velocity, tolerances and mode at the same event time")
}

@(test)
test_motion_virtual_replay_is_sampling_history_independent_and_traces_lifecycle :: proc(t: ^testing.T) {
	sparse := motion_replay_fixture(false)
	dense := motion_replay_fixture(true)
	motion_replay_expect_equal_checkpoint(t, sparse.after_b, dense.after_b)
	motion_replay_expect_equal_checkpoint(t, sparse.after_c, dense.after_c)
	motion_replay_expect_equal_checkpoint(t, sparse.after_restore, dense.after_restore)
	testing.expect(t, sparse.after_a.cause.id == 701 && sparse.after_b.cause.id == 702 &&
		sparse.after_c.cause.id == 703 && sparse.after_c.translation.target == Motion_Vector2{40, 0},
		"the fixed A→B→C event log should preserve each triggering cause and committed target")
	testing.expect(t, sparse.retargets == 2 && dense.retargets == 2 &&
		sparse.unchanged_target_noops == 1 && dense.unchanged_target_noops == 1 &&
		sparse.saw_settlement && dense.saw_settlement,
		"the replay should preserve both interrupted retargets and the post-suspend settlement")
	testing.expect(t, sparse.active_when_suspended && dense.active_when_suspended &&
		sparse.saw_suspend && dense.saw_suspend && sparse.presentation_stayed_frozen && dense.presentation_stayed_frozen,
		"the hidden-window replay must suspend an active response without advancing its last presented pose")
	testing.expect(t, sparse.saw_reduced_motion && dense.saw_reduced_motion &&
		sparse.reduced_preference_snapped && dense.reduced_preference_snapped &&
		sparse.saw_hidden_gap && dense.saw_hidden_gap && sparse.retired && dense.retired,
		"the lifecycle trace should include a mid-flight reduced-motion rewrite, hidden-gap fast-forward and owner retirement")
	testing.expect(t, sparse.trace_sequence == dense.trace_sequence &&
		sparse.stats.sample_ticks != dense.stats.sample_ticks,
		"transition history should be cadence-independent while aggregate sampling work reflects actual samples")
}
