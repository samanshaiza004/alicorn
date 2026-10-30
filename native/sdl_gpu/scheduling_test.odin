package alicorn_sdl_gpu

import "core:testing"
import "vendor:sdl3"

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
	testing.expect(t, !should_sample && state.suspended && !found,
		"a hidden or minimized window should drop its presentation deadline")
	should_sample = native_motion_scheduler_prepare(&state, 2, true, now+10_000_000_000)
	testing.expect(t, should_sample && state.stats.restore_samples == 1,
		"restoring should request one sample at the current clock rather than replay missed frames")
	native_motion_scheduler_finish_sample(&state, 2, 0, now+10_000_000_000)
	next_deadline, found_after_restore := native_motion_scheduler_next_deadline(&state)
	testing.expect(t, found_after_restore && next_deadline == now+10_000_000_000+NATIVE_MOTION_SAMPLE_INTERVAL_NS &&
		state.stats.timer_wakes == 0,
		"the restored motion should continue from now with one future deadline")
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
