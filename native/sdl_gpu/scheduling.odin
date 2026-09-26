package alicorn_sdl_gpu

SCHEDULED_WAKE_CLASS_COUNT :: 2
SCHEDULED_WAKE_MAX_U64 :: u64(0xffff_ffff_ffff_ffff)

Native_Scheduled_Wake_State :: struct {
	deadlines_ns: [SCHEDULED_WAKE_CLASS_COUNT]u64,
	pending:      [SCHEDULED_WAKE_CLASS_COUNT]bool,
	active:       bool,
	stats:        Application_Scheduler_Stats,
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
