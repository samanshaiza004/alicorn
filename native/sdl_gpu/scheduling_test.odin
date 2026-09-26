package alicorn_sdl_gpu

import "core:testing"

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
