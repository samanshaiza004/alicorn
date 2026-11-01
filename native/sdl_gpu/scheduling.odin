package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

SCHEDULED_WAKE_CLASS_COUNT :: 2
SCHEDULED_WAKE_MAX_U64 :: u64(0xffff_ffff_ffff_ffff)

// Native motion is sampled at a bounded display-like cadence. SDL's event
// wait has millisecond granularity, so this is a requested opportunity rate,
// not a promise about the compositor's actual present timestamp. The
// uncertified grace period below is a per-window motion-work budget: once its
// first uncertified response is observed, all uncertified responses active at
// expiry are snapped together, even if some started later.
NATIVE_MOTION_SAMPLE_INTERVAL_NS :: u64(16_666_667)
NATIVE_MOTION_UNCERTIFIED_LIMIT_NS :: u64(5_000_000_000)

Native_Motion_Scheduler_Stats :: struct {
	samples: u64,
	timer_wakes: u64,
	restore_samples: u64,
	hidden_active_observations: u64,
	coalesced_owners: u64,
	bounded_snaps: u64,
	missed_intervals: u64,
	maximum_lateness_ns: u64,
	sample_ns_total: u64,
	sample_ns_max: u64,
}

// Every native window has an independent motion deadline. The event loop may
// wait for the earliest deadline across windows, but each state owns only one
// outstanding presentation demand regardless of its number of active records.
Native_Motion_Scheduler_State :: struct {
	active: bool,
	suspended: bool,
	suspension_breadcrumb_recorded: bool,
	idle_breadcrumb_pending: bool,
	suspended_since_ns: u64,
	next_deadline_ns: u64,
	uncertified_since_ns: u64,
	stats: Native_Motion_Scheduler_Stats,
}

native_motion_clock_now :: proc(_data: rawptr) -> alicorn.Motion_Time {
	return alicorn.Motion_Time(i64(sdl3.GetTicksNS()))
}

native_motion_clock_service :: proc() -> Application_Motion_Clock {
	return Application_Motion_Clock{now=native_motion_clock_now}
}

application_motion_time_now :: proc(clock: Application_Motion_Clock) -> alicorn.Motion_Time {
	if clock.now == nil { return 0 }
	return clock.now(clock.data)
}

native_motion_window_renderable :: proc(flags: sdl3.WindowFlags) -> bool {
	unavailable := sdl3.WindowFlags{.HIDDEN, .MINIMIZED, .OCCLUDED}
	return (flags & unavailable) == sdl3.WindowFlags{}
}

native_motion_window_native_minimized :: proc(window: ^sdl3.Window) -> bool {
	when ODIN_OS == .Windows { return native_motion_window_windows_minimized(window) }
	return false
}

native_motion_window_renderable_for_window :: proc(window: ^sdl3.Window, flags: sdl3.WindowFlags) -> bool {
	return native_motion_window_renderable(flags) && !native_motion_window_native_minimized(window)
}

// native_motion_scheduler_prepare consumes a due demand exactly once. Missed
// opportunities are dropped: the caller samples at now_ns rather than replaying
// intermediate poses. A hidden/minimized/occluded window loses its deadline;
// restoring it asks for one immediate current-time sample.
native_motion_scheduler_prepare :: proc(
	state: ^Native_Motion_Scheduler_State,
	active_owners: int,
	window_renderable: bool,
	now_ns: u64,
) -> bool {
	if state == nil { return false }
	if !window_renderable {
		if active_owners > 0 {
			state.stats.hidden_active_observations += 1
			if !state.suspended || state.suspended_since_ns == 0 {
				state.suspended_since_ns = now_ns if now_ns != 0 else 1
			}
		} else {
			state.suspended_since_ns = 0
			state.suspension_breadcrumb_recorded = false
		}
		state.active = active_owners > 0
		state.suspended = true
		state.next_deadline_ns = 0
		if active_owners <= 0 { state.uncertified_since_ns = 0 }
		return false
	}
	if state.suspended {
		state.suspended = false
		state.suspension_breadcrumb_recorded = false
		state.active = active_owners > 0
		state.next_deadline_ns = 0
		state.suspended_since_ns = 0
		if active_owners <= 0 { state.uncertified_since_ns = 0 }
		if active_owners > 0 {
			state.stats.restore_samples += 1
			return true
		}
		return false
	}
	if active_owners <= 0 {
		state.active = false
		state.next_deadline_ns = 0
		state.uncertified_since_ns = 0
		return false
	}
	if !state.active {
		state.active = true
		state.next_deadline_ns = scheduled_wake_deadline_after(now_ns, NATIVE_MOTION_SAMPLE_INTERVAL_NS)
		return false
	}
	if state.next_deadline_ns == 0 {
		state.next_deadline_ns = scheduled_wake_deadline_after(now_ns, NATIVE_MOTION_SAMPLE_INTERVAL_NS)
		return false
	}
	if now_ns < state.next_deadline_ns { return false }
	lateness := now_ns-state.next_deadline_ns
	state.stats.timer_wakes += 1
	state.stats.maximum_lateness_ns = max(state.stats.maximum_lateness_ns, lateness)
	state.stats.missed_intervals += lateness/NATIVE_MOTION_SAMPLE_INTERVAL_NS
	state.next_deadline_ns = 0
	return true
}

native_motion_scheduler_record_suspension :: proc(
	state: ^Native_Motion_Scheduler_State,
	rt: ^alicorn.Runtime,
	activity: alicorn.Motion_Activity,
	now_ns: u64,
	window_flags: sdl3.WindowFlags,
	native_minimized: bool,
	window_id: sdl3.WindowID,
	gpu_submissions: u64,
	window_renderable: bool,
	breadcrumbs: ^Native_Breadcrumb_Recorder,
) {
	if state == nil || rt == nil || activity.active_owners <= 0 || state.suspension_breadcrumb_recorded { return }
	state.suspension_breadcrumb_recorded = true
	alicorn.motion_diagnostic_host_event(rt, .Host_Suspended, alicorn.Motion_Time(i64(now_ns)))
	native_breadcrumb_motion_window_state(
		breadcrumbs, "motion.window.suspended", window_id, window_flags,
		window_renderable, native_minimized, gpu_submissions, state, rt, activity,
	)
}

native_motion_scheduler_uncertified_limit_reached :: proc(
	state: ^Native_Motion_Scheduler_State,
	unestablished_deadlines: int,
	now_ns: u64,
) -> bool {
	if state == nil { return false }
	if unestablished_deadlines <= 0 {
		state.uncertified_since_ns = 0
		return false
	}
	if state.uncertified_since_ns == 0 {
		state.uncertified_since_ns = now_ns if now_ns != 0 else 1
		return false
	}
	return now_ns >= state.uncertified_since_ns &&
		now_ns-state.uncertified_since_ns >= NATIVE_MOTION_UNCERTIFIED_LIMIT_NS
}

native_motion_scheduler_finish_sample :: proc(
	state: ^Native_Motion_Scheduler_State,
	active_owners, unestablished_deadlines: int,
	now_ns: u64,
) {
	if state == nil { return }
	state.stats.samples += 1
	if active_owners <= 0 {
		state.active = false
		state.next_deadline_ns = 0
		state.uncertified_since_ns = 0
		return
	}
	state.active = true
	state.next_deadline_ns = scheduled_wake_deadline_after(now_ns, NATIVE_MOTION_SAMPLE_INTERVAL_NS)
	if unestablished_deadlines > 0 && state.uncertified_since_ns == 0 {
		state.uncertified_since_ns = now_ns if now_ns != 0 else 1
	}
	state.stats.coalesced_owners += u64(max(active_owners-1, 0))
}

native_motion_scheduler_next_deadline :: proc(state: ^Native_Motion_Scheduler_State) -> (u64, bool) {
	if state == nil || !state.active || state.suspended || state.next_deadline_ns == 0 { return 0, false }
	return state.next_deadline_ns, true
}

Native_Motion_Update_Result :: struct {
	sampled: bool,
	bounded_snap: bool,
	active_properties: int,
	active_owners: int,
	unestablished_deadlines: int,
	status: alicorn.Motion_Runtime_Status,
}

// native_motion_scheduler_advance is the per-window bridge between injected
// monotonic time and the retained runtime. It never builds the application;
// when due, it samples each active owner once, coalescing all properties into
// one future retained presentation frame.
native_motion_scheduler_advance :: proc(
	state: ^Native_Motion_Scheduler_State,
	rt: ^alicorn.Runtime,
	window_renderable: bool,
	now_ns: u64,
	window_flags: sdl3.WindowFlags = {},
	window_id: sdl3.WindowID = 0,
	native_minimized: bool = false,
	gpu_submissions: u64 = 0,
	breadcrumbs: ^Native_Breadcrumb_Recorder = nil,
) -> Native_Motion_Update_Result {
	if state == nil || rt == nil {
		return Native_Motion_Update_Result{status=.Invalid_Runtime}
	}
	activity := alicorn.motion_activity(rt)
	had_active_motion := activity.active_owners > 0
	if had_active_motion { state.idle_breadcrumb_pending = false }
	was_suspended := state.suspended
	suspended_since_ns := state.suspended_since_ns
	should_sample := native_motion_scheduler_prepare(
		state, activity.active_owners, window_renderable, now_ns,
	)
	if !window_renderable && activity.active_owners > 0 {
		native_motion_scheduler_record_suspension(
			state, rt, activity, now_ns, window_flags, native_minimized, window_id,
			gpu_submissions, window_renderable, breadcrumbs,
		)
	}
	result := Native_Motion_Update_Result{
		active_properties=activity.active_properties,
		active_owners=activity.active_owners,
		unestablished_deadlines=activity.unestablished_deadlines,
		status=.Ok,
	}
	if !should_sample {
		if state.idle_breadcrumb_pending && activity.active_owners <= 0 && window_renderable {
			native_breadcrumb_motion_window_state(
				breadcrumbs, "motion.window.idle", window_id, window_flags,
				window_renderable, native_minimized, gpu_submissions, state, rt, activity,
			)
			state.idle_breadcrumb_pending = false
		}
		if was_suspended && window_renderable {
			native_breadcrumb_motion_window_state(
				breadcrumbs, "motion.window.restored", window_id, window_flags,
				window_renderable, native_minimized, gpu_submissions, state, rt, activity,
			)
		}
		return result
	}
	result.sampled = true
	started_ns := u64(sdl3.GetTicksNS())
	tick := alicorn.motion_tick(rt, alicorn.Motion_Time(i64(now_ns)))
	if tick.status != .Ok {
		result.status = tick.status
		return result
	}
	activity = alicorn.motion_activity(rt)
	if native_motion_scheduler_uncertified_limit_reached(
		state, activity.unestablished_deadlines, now_ns,
	) {
		bounded := alicorn.motion_snap_unestablished(rt, alicorn.Motion_Time(i64(now_ns)))
		if bounded.status != .Ok {
			result.status = bounded.status
			return result
		}
		state.stats.bounded_snaps += 1
		result.bounded_snap = true
		activity = alicorn.motion_activity(rt)
	}
	if was_suspended && window_renderable && had_active_motion {
		gap_ns := now_ns-suspended_since_ns if suspended_since_ns != 0 && now_ns >= suspended_since_ns else 0
		alicorn.motion_diagnostic_host_event(rt, .Hidden_Gap_Fast_Forward, alicorn.Motion_Time(i64(now_ns)), gap_ns)
	}
	finished_ns := u64(sdl3.GetTicksNS())
	sample_elapsed := finished_ns-started_ns if finished_ns >= started_ns else 0
	state.stats.sample_ns_total += sample_elapsed
	state.stats.sample_ns_max = max(state.stats.sample_ns_max, sample_elapsed)
	native_motion_scheduler_finish_sample(
		state, activity.active_owners, activity.unestablished_deadlines, now_ns,
	)
	if had_active_motion && activity.active_owners <= 0 {
		// Record the settled state on the next host-loop visit, after any final
		// presentation submission caused by this sample has been accounted for.
		state.idle_breadcrumb_pending = true
	}
	if was_suspended && window_renderable {
		native_breadcrumb_motion_window_state(
			breadcrumbs, "motion.window.restored", window_id, window_flags,
			window_renderable, native_minimized, gpu_submissions, state, rt, activity,
		)
	}
	result.active_properties = activity.active_properties
	result.active_owners = activity.active_owners
	result.unestablished_deadlines = activity.unestablished_deadlines
	return result
}

// native_live_resize_motion_advance shares the ordinary window scheduler with
// SDL's main-thread live-redraw callback. It does not build or reconcile the
// application; a due response only requests a retained presentation frame.
native_live_resize_motion_advance :: proc(
	scheduler: ^Native_Motion_Scheduler_State,
	rt: ^alicorn.Runtime,
	timing: ^Native_Host_Timing,
	window_renderable: bool,
	now_ns: u64,
	window_flags: sdl3.WindowFlags = {},
	window_id: sdl3.WindowID = 0,
	native_minimized := false,
	breadcrumbs: ^Native_Breadcrumb_Recorder = nil,
) -> Native_Motion_Update_Result {
	if scheduler == nil || rt == nil {
		return Native_Motion_Update_Result{status=.Invalid_Runtime}
	}
	gpu_submissions := u64(timing.gpu_submissions) if timing != nil else 0
	update := native_motion_scheduler_advance(
		scheduler, rt, window_renderable, now_ns,
		window_flags, window_id, native_minimized, gpu_submissions, breadcrumbs,
	)
	if update.status == .Ok && timing != nil {
		native_motion_scheduler_sync_timing(scheduler, timing, update.active_owners)
	}
	return update
}

native_motion_scheduler_sync_timing :: proc(
	state: ^Native_Motion_Scheduler_State,
	timing: ^Native_Host_Timing,
	active_owners: int,
) {
	if state == nil || timing == nil { return }
	timing.motion_samples = state.stats.samples
	timing.motion_timer_wakes = state.stats.timer_wakes
	timing.motion_restore_samples = state.stats.restore_samples
	timing.motion_hidden_active_observations = state.stats.hidden_active_observations
	timing.motion_coalesced_owners = state.stats.coalesced_owners
	timing.motion_bounded_snaps = state.stats.bounded_snaps
	timing.motion_missed_intervals = state.stats.missed_intervals
	timing.motion_sample_ns = state.stats.sample_ns_total
	timing.motion_sample_max_ns = state.stats.sample_ns_max
	timing.motion_max_active_owners = max(timing.motion_max_active_owners, u64(max(active_owners, 0)))
	timing.motion_max_lateness_ns = state.stats.maximum_lateness_ns
}

Native_Scheduled_Wake_State :: struct {
	deadlines_ns: [SCHEDULED_WAKE_CLASS_COUNT]u64,
	pending:      [SCHEDULED_WAKE_CLASS_COUNT]bool,
	active:       bool,
	stats:        Application_Scheduler_Stats,
}

Native_Event_Wait_Deadline_Source :: enum {
	None,
	Swapchain_Retry,
	Primary_Tick,
	Primary_Motion,
	Drag_Autoscroll,
	Tooltip,
	Notice,
	Application_Scheduled,
	Devtools_Hud,
	Child_Motion,
	Child_Tick,
	Child_Scheduled,
	Child_Tooltip,
	Child_Notice,
	Smoke_Exit,
	Validation_Exit,
}

NATIVE_EVENT_WAIT_DEADLINE_SOURCE_COUNT :: 16

// SDL event waits use a negative timeout for an indefinite wait. Merge a new
// nonnegative deadline without accidentally replacing an earlier retry/tick.
// The optional source output is diagnostic-only and records which candidate
// supplied the shortest timeout for the upcoming event wait.
native_event_wait_timeout_min :: proc(
	current_ms, candidate_ms: i32,
	selected_source: ^Native_Event_Wait_Deadline_Source = nil,
	candidate_source: Native_Event_Wait_Deadline_Source = .None,
) -> i32 {
	if candidate_ms < 0 { return current_ms }
	if current_ms < 0 || candidate_ms < current_ms {
		if selected_source != nil { selected_source^ = candidate_source }
		return candidate_ms
	}
	return current_ms
}

// SDL's Windows backend converts the remaining nanosecond timeout to a Win32
// millisecond wait by truncating it. Near a deadline, SDL can therefore
// return early after a zero-millisecond OS wait, leaving the host to retry in
// a tight loop for the final fraction of a millisecond. One millisecond of
// slack keeps deadline waits event-driven while allowing a bounded late wake.
native_event_wait_windows_timeout_ms :: proc(timeout_ms: i32) -> i32 {
	if timeout_ms <= 0 || timeout_ms >= 0x7fff_ffff { return timeout_ms }
	return timeout_ms+1
}

scheduled_wake_class_index :: proc(class: Scheduled_Wake_Class) -> int {
	switch class {
	case .Frequent: return 0
	case .Opportunistic: return 1
	}
	return -1
}

scheduled_wake_deadline_after :: proc(now_ns, delay_ns: u64) -> u64 {
	if delay_ns > SCHEDULED_WAKE_MAX_U64-now_ns { return SCHEDULED_WAKE_MAX_U64 }
	return now_ns+delay_ns
}

scheduled_wake_schedule :: proc(
	state: ^Native_Scheduled_Wake_State,
	class: Scheduled_Wake_Class,
	now_ns, delay_ns: u64,
) -> bool {
	index := scheduled_wake_class_index(class)
	if state == nil || !state.active || index < 0 { return false }
	if state.pending[index] { state.stats.coalesced += 1 }
	state.pending[index] = true
	state.deadlines_ns[index] = scheduled_wake_deadline_after(now_ns, delay_ns)
	state.stats.scheduled += 1
	return true
}

scheduled_wake_cancel :: proc(state: ^Native_Scheduled_Wake_State, class: Scheduled_Wake_Class) -> bool {
	index := scheduled_wake_class_index(class)
	if state == nil || index < 0 { return false }
	state.pending[index] = false
	return true
}

scheduled_wake_next_deadline :: proc(state: ^Native_Scheduled_Wake_State) -> (deadline_ns: u64, found: bool) {
	if state == nil || !state.active { return }
	for index in 0..<SCHEDULED_WAKE_CLASS_COUNT {
		if state.pending[index] && (!found || state.deadlines_ns[index] < deadline_ns) {
			deadline_ns = state.deadlines_ns[index]
			found = true
		}
	}
	return deadline_ns, found
}

scheduled_wake_is_due :: proc(state: ^Native_Scheduled_Wake_State, class: Scheduled_Wake_Class, now_ns: u64) -> bool {
	index := scheduled_wake_class_index(class)
	return state != nil && index >= 0 && state.active && state.pending[index] && state.deadlines_ns[index] <= now_ns
}

scheduled_wake_defer_until_quiet :: proc(now_ns, last_interaction_ns, quiet_ns: u64) -> (deadline_ns: u64, deferred: bool) {
	if last_interaction_ns == 0 || now_ns < last_interaction_ns { return }
	quiet_deadline := scheduled_wake_deadline_after(last_interaction_ns, quiet_ns)
	if now_ns < quiet_deadline {
		return quiet_deadline, true
	}
	return
}

scheduled_wake_record_run :: proc(state: ^Native_Scheduled_Wake_State, class: Scheduled_Wake_Class, lateness_ns: u64) {
	if state == nil { return }
	index := scheduled_wake_class_index(class)
	if index < 0 { return }
	state.pending[index] = false
	if class == .Frequent { state.stats.frequent_wakes += 1 }
	else { state.stats.opportunistic_wakes += 1 }
	state.stats.maximum_lateness_ns = max(state.stats.maximum_lateness_ns, lateness_ns)
}

scheduled_wake_read_stats :: proc(state: ^Native_Scheduled_Wake_State) -> Application_Scheduler_Stats {
	if state == nil { return {} }
	result := state.stats
	result.frequent_pending = state.pending[0]
	result.opportunistic_pending = state.pending[1]
	return result
}

scheduled_wake_timeout_ms :: proc(deadline_ns, now_ns: u64) -> u64 {
	remaining := u64(0)
	if deadline_ns > now_ns { remaining = deadline_ns-now_ns }
	milliseconds := remaining/1_000_000
	if remaining%1_000_000 != 0 { milliseconds += 1 }
	return min(milliseconds, u64(0x7fff_ffff))
}
