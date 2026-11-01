package alicorn_sdl_gpu

import "core:testing"
import "vendor:sdl3"
import alicorn "../../runtime"

@(test)
test_event_wait_timeout_keeps_earliest_deadline :: proc(t: ^testing.T) {
	testing.expect(t, native_event_wait_timeout_min(-1, 100) == 100,
		"a bounded retry should replace an indefinite event wait")
	testing.expect(t, native_event_wait_timeout_min(100, 250) == 100,
		"later deadlines must not postpone the swapchain retry")
	testing.expect(t, native_event_wait_timeout_min(100, 16) == 16,
		"earlier application ticks or scheduled wakes should still run first")
}

@(test)
test_windows_event_wait_timeout_adds_rounding_slack :: proc(t: ^testing.T) {
	testing.expect(t, native_event_wait_windows_timeout_ms(-1) == -1,
		"an indefinite event wait should remain indefinite")
	testing.expect(t, native_event_wait_windows_timeout_ms(0) == 0,
		"an already-due deadline should keep requesting an immediate event-loop turn")
	testing.expect(t, native_event_wait_windows_timeout_ms(1) == 2,
		"positive Windows deadlines should retain one millisecond for SDL's truncated sub-millisecond remainder")
	testing.expect(t, native_event_wait_windows_timeout_ms(250) == 251,
		"the bounded slack should be independent of the requested deadline")
	testing.expect(t, native_event_wait_windows_timeout_ms(0x7fff_ffff) == 0x7fff_ffff,
		"timeout padding must not overflow the largest supported SDL wait")
}

@(test)
test_scheduled_wake_deadlines_replace_coalesce_and_select_nearest :: proc(t: ^testing.T) {
	state := Native_Scheduled_Wake_State{active=true}
	testing.expect(t, scheduled_wake_schedule(&state, .Frequent, 1_000, 250_000_000), "frequent deadline should schedule")
	testing.expect(t, scheduled_wake_schedule(&state, .Frequent, 2_000, 500_000_000), "a class deadline should be replaceable")
	testing.expect(t, state.stats.coalesced == 1, "replacing pending same-class work should be observable as coalesced")
	testing.expect(t, scheduled_wake_schedule(&state, .Opportunistic, 3_000, 100_000_000), "opportunistic deadline should schedule")
	deadline, found := scheduled_wake_next_deadline(&state)
	testing.expect(t, found && deadline == 100_003_000, "the host should wait for the nearest pending class")
	testing.expect(t, !scheduled_wake_is_due(&state, .Frequent, 100_000_000), "future frequent work should not run early")
	testing.expect(t, scheduled_wake_is_due(&state, .Opportunistic, 100_003_000), "opportunistic work should become due at its deadline")
	scheduled_wake_record_run(&state, .Opportunistic, 7_000)
	_ = scheduled_wake_cancel(&state, .Frequent)
	_, found = scheduled_wake_next_deadline(&state)
	testing.expect(t, !found, "a scheduled wake is one-shot unless the application rearms it")
	testing.expect(t, state.stats.opportunistic_wakes == 1 && state.stats.maximum_lateness_ns == 7_000,
		"run counts and lateness should be inspectable")
}

@(test)
test_scheduled_wake_opportunistic_policy_waits_for_quiet :: proc(t: ^testing.T) {
	deadline, deferred := scheduled_wake_defer_until_quiet(1_100, 1_050, 200)
	testing.expect(t, deferred && deadline == 1_250, "opportunistic work should move past the quiet interval")
	_, deferred = scheduled_wake_defer_until_quiet(1_300, 1_050, 200)
	testing.expect(t, !deferred, "opportunistic work should run after the user is quiet")
	_, deferred = scheduled_wake_defer_until_quiet(1_100, 0, 200)
	testing.expect(t, !deferred, "startup work without a prior input should not be deferred")
}

@(test)
test_scheduled_wake_deadline_saturates_instead_of_wrapping :: proc(t: ^testing.T) {
	deadline := scheduled_wake_deadline_after(SCHEDULED_WAKE_MAX_U64-5, 20)
	testing.expect(t, deadline == SCHEDULED_WAKE_MAX_U64, "deadline arithmetic must not wrap into an immediate wake")
	testing.expect(t, scheduled_wake_timeout_ms(1_000_001, 0) == 2, "SDL timeout conversion should round up rather than run early")
	testing.expect(t, scheduled_wake_timeout_ms(900, 1_000) == 0, "an expired deadline should request an immediate event-loop turn")
}

@(test)
test_native_motion_window_coalesces_active_owners_and_retires_to_idle :: proc(t: ^testing.T) {
	state := Native_Motion_Scheduler_State{}
	deadline := u64(1_000_000_000)
	should_sample := native_motion_scheduler_prepare(&state, 1, true, deadline)
	first_deadline, found := native_motion_scheduler_next_deadline(&state)
	testing.expect(t, !should_sample && found && first_deadline == deadline+NATIVE_MOTION_SAMPLE_INTERVAL_NS,
		"a new active motion set should schedule one bounded per-window deadline")
	should_sample = native_motion_scheduler_prepare(&state, 1000, true, first_deadline+5_000_000)
	testing.expect(t, should_sample && state.stats.timer_wakes == 1,
		"one due deadline should sample the whole active owner set once")
	native_motion_scheduler_finish_sample(&state, 1000, 0, first_deadline+5_000_000)
	_, found = native_motion_scheduler_next_deadline(&state)
	testing.expect(t, found && state.stats.samples == 1 && state.stats.coalesced_owners == 999,
		"one thousand owners should coalesce into one sample and one next deadline")
	native_motion_scheduler_finish_sample(&state, 0, 0, first_deadline+10_000_000)
	settled_deadline, settled_deadline_found := native_motion_scheduler_next_deadline(&state)
	should_sample = native_motion_scheduler_prepare(&state, 0, true, first_deadline+1_000_000_000)
	testing.expect(t, !settled_deadline_found && settled_deadline == 0,
		"the settled per-window state should have no deadline")
	testing.expect(t, !should_sample, "settled motion must not request an idle sample")
	testing.expect(t, state.stats.samples == 2, "the settling sample is counted, but later idle opportunities are not")
}

@(test)
test_native_motion_suspend_and_restore_samples_current_time_once :: proc(t: ^testing.T) {
	state := Native_Motion_Scheduler_State{}
	now := u64(2_000_000_000)
	_ = native_motion_scheduler_prepare(&state, 2, true, now)
	should_sample := native_motion_scheduler_prepare(&state, 2, false, now+5_000_000)
	_, found := native_motion_scheduler_next_deadline(&state)
	testing.expect(t, !should_sample && state.suspended && !found && state.suspended_since_ns == now+5_000_000,
		"a hidden or minimized window should drop its deadline and retain the first suspended timestamp")
	should_sample = native_motion_scheduler_prepare(&state, 2, true, now+10_000_000_000)
	testing.expect(t, should_sample && state.stats.restore_samples == 1 && !state.suspended && state.suspended_since_ns == 0,
		"restoring should request one current-time sample, clear the gap origin, and avoid replaying missed frames")
	native_motion_scheduler_finish_sample(&state, 2, 0, now+10_000_000_000)
	next_deadline, found_after_restore := native_motion_scheduler_next_deadline(&state)
	testing.expect(t, found_after_restore && next_deadline == now+10_000_000_000+NATIVE_MOTION_SAMPLE_INTERVAL_NS &&
		state.stats.timer_wakes == 0,
		"the restored motion should continue from now with one future deadline")
}

@(test)
test_live_resize_motion_sample_uses_retained_path_without_rebuilding_application :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	ui, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false, "the live-resize motion fixture should describe once"); return }
	alicorn.container_begin(&ui, .Root, key=alicorn.key_string("live-resize-motion-root"), style=alicorn.layout_style())
	owner, _ := alicorn.button_ex(&ui, "Motion", key="live-resize-motion-owner", explicit_key=true,
		style=alicorn.layout_style(.Row, width=120, height=30))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.motion_policy = alicorn.DEFAULT_MOTION_THEME_POLICY
	theme.motion_policy.translation.omega = 1.5
	theme_id := alicorn.style_theme_register(&rt, theme)
	if node, found := rt.nodes[owner]; found { node.style_environment.theme = theme_id }
	start_ns := u64(4_000_000_000)
	_ = alicorn.motion_clock_set_time(&rt, alicorn.Motion_Time(i64(start_ns)), .Native_Monotonic)
	target := alicorn.Motion_Target{translation=alicorn.Motion_Vector2{80, 0}, has_translation=true}
	if alicorn.motion_apply_intent(&rt, owner, target) != .Ok {
		testing.expect(t, false, "the decorative owner should accept a retained target")
		return
	}
	scheduler := Native_Motion_Scheduler_State{}
	timing := Native_Host_Timing{}
	first := native_live_resize_motion_advance(&scheduler, &rt, &timing, true, start_ns)
	stats_before_sample := rt.stats
	due_ns := start_ns+NATIVE_MOTION_SAMPLE_INTERVAL_NS
	update := native_live_resize_motion_advance(&scheduler, &rt, &timing, true, due_ns)
	stats_after_sample := rt.stats
	testing.expect(t, first.status == .Ok && !first.sampled,
		"the first visible visit should arm one per-window motion deadline")
	testing.expect(t, update.status == .Ok && update.sampled && scheduler.stats.samples == 1 && timing.motion_samples == 1,
		"a live-redraw opportunity at the due time should sample through the existing per-window scheduler")
	testing.expect(t, alicorn.presentation_needs_frame(&rt),
		"a changed retained pose should request presentation from the live-redraw path")
	testing.expect(t,
		stats_after_sample.frames_built == stats_before_sample.frames_built &&
		stats_after_sample.reconcile_nodes_visited == stats_before_sample.reconcile_nodes_visited &&
		stats_after_sample.measure_requests == stats_before_sample.measure_requests &&
		stats_after_sample.text_shape_requests == stats_before_sample.text_shape_requests &&
		stats_after_sample.layout_nodes_visited == stats_before_sample.layout_nodes_visited,
		"motion sampling during a native move/resize redraw must not rebuild, reconcile, measure, shape text, or layout")
}

@(test)
test_native_motion_suspension_clock_starts_with_active_work :: proc(t: ^testing.T) {
	state := Native_Motion_Scheduler_State{}
	_ = native_motion_scheduler_prepare(&state, 0, false, 1_000)
	testing.expect(t, state.suspended && state.suspended_since_ns == 0,
		"an idle hidden window should not start a motion-gap interval")
	_ = native_motion_scheduler_prepare(&state, 2, false, 4_000)
	testing.expect(t, state.suspended_since_ns == 4_000,
		"motion first observed in an already hidden window should start its own gap interval")
	_ = native_motion_scheduler_prepare(&state, 0, false, 8_000)
	testing.expect(t, state.suspended_since_ns == 0,
		"retiring all motion while hidden should clear the old gap origin")
	_ = native_motion_scheduler_prepare(&state, 1, false, 12_000)
	testing.expect(t, state.suspended_since_ns == 12_000,
		"later hidden motion should be measured from its own first observed active time")
}

@(test)
test_native_motion_suspend_and_restore_are_recorded_with_the_clock_gap :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	ui, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false, "the native motion fixture should describe once"); return }
	alicorn.container_begin(&ui, .Root, key=alicorn.key_string("suspend-motion-root"), style=alicorn.layout_style())
	owner, _ := alicorn.button_ex(&ui, "Motion", key="suspend-motion-owner", explicit_key=true,
		style=alicorn.layout_style(.Row, width=120, height=30))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.motion_policy = alicorn.DEFAULT_MOTION_THEME_POLICY
	theme.motion_policy.translation.omega = 1.5
	theme_id := alicorn.style_theme_register(&rt, theme)
	if node, found := rt.nodes[owner]; found { node.style_environment.theme = theme_id }
	start_ns := u64(1_000_000_000)
	_ = alicorn.motion_clock_set_time(&rt, alicorn.Motion_Time(i64(start_ns)), .Native_Monotonic)
	target := alicorn.Motion_Target{translation=alicorn.Motion_Vector2{80, 0}, has_translation=true}
	testing.expect(t, alicorn.motion_apply_intent(&rt, owner, target) == .Ok,
		"the selected native owner should have an active motion response")
	state := Native_Motion_Scheduler_State{}
	_ = native_motion_scheduler_advance(&state, &rt, true, start_ns)
	hide_ns := start_ns+5_000_000
	hidden := native_motion_scheduler_advance(&state, &rt, false, hide_ns)
	samples_at_hide := state.stats.samples
	restore_ns := start_ns+900_000_000
	restored := native_motion_scheduler_advance(&state, &rt, true, restore_ns)
	testing.expect(t, !hidden.sampled && restored.sampled && state.suspended_since_ns == 0,
		"the hidden interval should suspend one window and restore with a current-time sample")
	testing.expect(t, state.stats.hidden_active_observations == 1 && samples_at_hide == 0 &&
		state.stats.samples == samples_at_hide+1 && state.stats.restore_samples == 1,
		"hidden active motion should not be sampled, and restore should consume exactly one current-time sample")
	found_suspend, found_gap := false, false
	for offset in 0..<alicorn.motion_diagnostics_event_count(&rt) {
		event, found := alicorn.motion_diagnostics_event_recent(&rt, offset)
		if !found { continue }
		if event.kind == .Host_Suspended {
			found_suspend = event.time == alicorn.Motion_Time(i64(hide_ns)) && event.clock_source == .Native_Monotonic
		}
		if event.kind == .Hidden_Gap_Fast_Forward {
			found_gap = event.time == alicorn.Motion_Time(i64(restore_ns)) &&
				event.elapsed_ns == restore_ns-hide_ns && event.clock_source == .Native_Monotonic
		}
	}
	testing.expect(t, found_suspend && found_gap,
		"the motion trace should record the first suspend time and exact hidden gap using the native monotonic clock")
	settle_now_ns := restore_ns+10_000_000_000
	settled := native_motion_scheduler_advance(&state, &rt, true, settle_now_ns)
	samples_at_settlement := state.stats.samples
	idle_snapshot_pending_at_settlement := state.idle_breadcrumb_pending
	idle := native_motion_scheduler_advance(&state, &rt, true, settle_now_ns+1)
	testing.expect(t, settled.sampled,
		"a far-future host visit should sample the active response")
	testing.expect(t, settled.active_owners == 0 && !state.active && state.next_deadline_ns == 0,
		"the far-future response should be settled and have no scheduled deadline")
	testing.expect(t, idle_snapshot_pending_at_settlement,
		"the first post-settlement host visit should retain one pending idle snapshot after its final presentation sample")
	testing.expect(t, !idle.sampled && idle.active_owners == 0 && state.stats.samples == samples_at_settlement &&
		!state.idle_breadcrumb_pending,
		"the following idle host visit should record the settled scheduler state without sampling motion again")
}

@(test)
test_native_motion_suspension_clears_uncertified_grace_when_all_motion_retires :: proc(t: ^testing.T) {
	state := Native_Motion_Scheduler_State{
		active=true,
		suspended=false,
		uncertified_since_ns=1_000_000_000,
		next_deadline_ns=2_000_000_000,
	}
	should_sample := native_motion_scheduler_prepare(&state, 0, false, 3_000_000_000)
	_ = native_motion_scheduler_prepare(&state, 0, true, 10_000_000_000)
	testing.expect(t, !should_sample && state.uncertified_since_ns == 0,
		"a window suspended after its last response retires must not carry stale uncertified grace into later motion")
	should_sample = native_motion_scheduler_prepare(&state, 1, true, 10_000_000_000)
	testing.expect(t, !should_sample && state.uncertified_since_ns == 0,
		"a later response should receive a fresh bounded grace period")
}

@(test)
test_native_motion_uncertified_deadline_has_bounded_policy :: proc(t: ^testing.T) {
	state := Native_Motion_Scheduler_State{}
	now := u64(3_000_000_000)
	native_motion_scheduler_finish_sample(&state, 1, 1, now)
	testing.expect(t, !native_motion_scheduler_uncertified_limit_reached(
		&state, 1, now+NATIVE_MOTION_UNCERTIFIED_LIMIT_NS-1,
	), "uncertified motion should retain a finite grace period")
	testing.expect(t, native_motion_scheduler_uncertified_limit_reached(
		&state, 1, now+NATIVE_MOTION_UNCERTIFIED_LIMIT_NS,
	), "the host should bound responses with no certified retirement time")
	native_motion_scheduler_uncertified_limit_reached(&state, 0, now+NATIVE_MOTION_UNCERTIFIED_LIMIT_NS)
	testing.expect(t, state.uncertified_since_ns == 0,
		"the uncertified-motion bound should clear after all such responses retire")
}

@(test)
test_native_motion_uncertified_grace_is_a_window_wide_work_budget :: proc(t: ^testing.T) {
	state := Native_Motion_Scheduler_State{}
	first_started_ns := u64(1_000_000_000)
	second_started_ns := first_started_ns+4_900_000_000
	native_motion_scheduler_finish_sample(&state, 1, 1, first_started_ns)
	native_motion_scheduler_finish_sample(&state, 2, 2, second_started_ns)
	testing.expect(t, state.uncertified_since_ns == first_started_ns,
		"a later uncertified response shares the existing window grace-period origin")
	testing.expect(t, !native_motion_scheduler_uncertified_limit_reached(
		&state, 2, first_started_ns+NATIVE_MOTION_UNCERTIFIED_LIMIT_NS-1,
	), "the first response retains nearly the full five-second window budget")
	testing.expect(t, native_motion_scheduler_uncertified_limit_reached(
		&state, 2, first_started_ns+NATIVE_MOTION_UNCERTIFIED_LIMIT_NS,
	), "at expiry, the window budget bounds all currently active uncertified responses")
}

@(test)
test_native_motion_visibility_ignores_hidden_minimized_and_occluded_windows :: proc(t: ^testing.T) {
	testing.expect(t, native_motion_window_renderable(sdl3.WindowFlags{}) &&
		!native_motion_window_renderable(sdl3.WindowFlags{.HIDDEN}) &&
		!native_motion_window_renderable(sdl3.WindowFlags{.MINIMIZED}) &&
		!native_motion_window_renderable(sdl3.WindowFlags{.OCCLUDED}),
		"unavailable windows should not request motion samples")
}
