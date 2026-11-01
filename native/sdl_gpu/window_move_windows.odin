#+build windows

package alicorn_sdl_gpu

import win "core:sys/windows"
import "base:runtime"
import alicorn "../../runtime"
import "vendor:sdl3"

// A per-HWND timer runs inside Windows' modal move loop. Its callback only
// samples and presents an already-due retained motion response; it never
// pumps SDL events or rebuilds the application description.
NATIVE_WINDOWS_MOVE_TIMER_ID :: win.UINT_PTR(0xA11C)
NATIVE_WINDOWS_MOVE_TIMER_INTERVAL_MS :: win.UINT(17)
NATIVE_WINDOWS_MOVE_REDRAW_INTERVAL_NS :: u64(16_666_667)

native_windows_move_hook_state: ^Native_Live_Resize_State

native_live_resize_windows_hook_install :: proc(state: ^Native_Live_Resize_State) -> bool {
	if state == nil || state.window == nil { return false }
	if native_windows_move_hook_state != nil && native_windows_move_hook_state != state { return false }
	if native_live_resize_windows_window_handle(state.window) == nil { return false }
	native_windows_move_hook_state = state
	sdl3.SetWindowsMessageHook(native_live_resize_windows_message_hook, rawptr(state))
	return true
}

native_live_resize_windows_hook_remove :: proc(state: ^Native_Live_Resize_State) {
	if state == nil { return }
	native_live_resize_windows_stop(state, .Primary, nil)
	if state.secondary_manager != nil {
		native_live_resize_windows_stop(state, .Secondary, state.secondary_manager.child)
	}
	if native_windows_move_hook_state == state {
		sdl3.SetWindowsMessageHook(nil, nil)
		native_windows_move_hook_state = nil
	}
}

native_live_resize_windows_move_reconcile :: proc(state: ^Native_Live_Resize_State) {
	if state == nil || !state.move_active { return }
	// The modal pointer-move loop may consume WM_EXITSIZEMOVE before SDL's
	// message hook sees it. The first normal host-loop turn after release is a
	// final, bounded cleanup point for the per-window timer.
	if win.GetAsyncKeyState(win.VK_LBUTTON) >= 0 {
		target, child := native_live_resize_windows_target(state, cast(win.HWND)state.move_hwnd)
		native_live_resize_windows_stop(state, target, child)
	}
}

native_live_resize_windows_message_hook :: proc "c" (userdata: rawptr, message: ^win.MSG) -> bool {
	context = runtime.default_context()
	state := cast(^Native_Live_Resize_State)userdata
	if state == nil || !state.active || message == nil { return true }
	switch message.message {
	case win.WM_ENTERSIZEMOVE:
		target, child := native_live_resize_windows_target(state, message.hwnd)
		if target == .None { return true }
		native_live_resize_windows_start(state, target, child, message.hwnd)
	case win.WM_EXITSIZEMOVE:
		target, child := native_live_resize_windows_target(state, message.hwnd)
		if target == .None { return true }
		state.windows_move_exit_messages += 1
		native_live_resize_windows_stop(state, target, child)
	case win.WM_MOVING:
		primary_active := native_live_resize_windows_primary_active_for_hwnd(state, message.hwnd)
		secondary_active := native_live_resize_windows_secondary_active_for_hwnd(state, message.hwnd)
		if primary_active || secondary_active {
			state.windows_move_position_messages += 1
		}
	case win.WM_WINDOWPOSCHANGED:
		primary_active := native_live_resize_windows_primary_active_for_hwnd(state, message.hwnd)
		secondary_active := native_live_resize_windows_secondary_active_for_hwnd(state, message.hwnd)
		if primary_active || secondary_active {
			state.windows_move_position_changed_messages += 1
		}
	}
	return true
}

native_live_resize_windows_primary_active_for_hwnd :: proc(state: ^Native_Live_Resize_State, hwnd: win.HWND) -> bool {
	return state != nil && state.move_active && state.move_hwnd == rawptr(hwnd)
}

native_live_resize_windows_secondary_active_for_hwnd :: proc(state: ^Native_Live_Resize_State, hwnd: win.HWND) -> bool {
	if state == nil || state.secondary_manager == nil { return false }
	child := state.secondary_manager.child
	return child != nil && child.move_active && child.move_hwnd == rawptr(hwnd)
}

native_live_resize_windows_secondary_destroy :: proc(child: ^Native_Secondary_Window) {
	state := native_windows_move_hook_state
	if state != nil && child != nil && child.move_active {
		native_live_resize_windows_stop(state, .Secondary, child)
	}
}

native_live_resize_windows_start :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
	hwnd: win.HWND,
) {
	if state == nil || hwnd == nil { return }
	state.windows_move_enter_messages += 1
	native_live_resize_windows_set_active(state, target, child, hwnd, true)
	// Keyboard system-menu moves are left to their ordinary event semantics.
	// The live timer is specifically for a visible pointer drag, where the
	// Windows modal loop otherwise withholds ordinary SDL host turns.
	if win.GetAsyncKeyState(win.VK_LBUTTON) >= 0 { return }
	scheduler := native_live_resize_windows_scheduler(state, target, child)
	if scheduler == nil { return }
	_, has_deadline := native_motion_scheduler_next_deadline(scheduler)
	if !has_deadline { return }
	timer_id := win.SetTimer(hwnd, NATIVE_WINDOWS_MOVE_TIMER_ID,
		NATIVE_WINDOWS_MOVE_TIMER_INTERVAL_MS, native_live_resize_windows_timer_proc)
	if timer_id != 0 {
		native_live_resize_windows_set_timer_active(state, target, child, true)
	}
}

native_live_resize_windows_timer_proc :: proc "system" (
	hwnd: win.HWND,
	message: win.UINT,
	timer_id: win.UINT_PTR,
	_tick: win.DWORD,
) {
	context = runtime.default_context()
	if message != win.WM_TIMER || timer_id != NATIVE_WINDOWS_MOVE_TIMER_ID { return }
	state := native_windows_move_hook_state
	if state == nil || !state.active { return }
	target, child := native_live_resize_windows_target(state, hwnd)
	if target == .None || !native_live_resize_windows_active(state, target, child) { return }
	state.windows_move_timer_wakes += 1
	if win.GetAsyncKeyState(win.VK_LBUTTON) >= 0 {
		native_live_resize_windows_stop(state, target, child)
		return
	}
	scheduler := native_live_resize_windows_scheduler(state, target, child)
	if scheduler == nil { native_live_resize_windows_stop(state, target, child); return }
	activity := alicorn.motion_activity(native_live_resize_windows_runtime(state, target, child))
	if activity.active_owners <= 0 {
		native_live_resize_windows_stop(state, target, child)
		return
	}
	native_live_resize_windows_present_if_due(state, target, child, u64(sdl3.GetTicksNS()))
}

native_live_resize_windows_present_if_due :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
	now_ns: u64,
) {
	if state == nil || !native_live_resize_windows_active(state, target, child) { return }
	last_ns := native_live_resize_windows_last_redraw(state, target, child)
	if last_ns != 0 && now_ns >= last_ns && now_ns-last_ns < NATIVE_WINDOWS_MOVE_REDRAW_INTERVAL_NS { return }
	scheduler := native_live_resize_windows_scheduler(state, target, child)
	if scheduler == nil { return }
	deadline, found := native_motion_scheduler_next_deadline(scheduler)
	if !found {
		native_live_resize_windows_stop(state, target, child)
		return
	}
	if now_ns < deadline { return }
	native_live_resize_windows_set_last_redraw(state, target, child, now_ns)
	before_samples := scheduler.stats.samples
	before_submissions := u64(0)
	if target == .Primary { before_submissions = state.timing.gpu_submissions }
	else if child != nil { before_submissions = child.timing.gpu_submissions }
	if target == .Primary { native_live_resize_redraw(state) }
	else if target == .Secondary { native_secondary_window_live_resize_redraw(state.secondary_manager, child) }
	after_samples := scheduler.stats.samples
	after_submissions := before_submissions
	if target == .Primary { after_submissions = state.timing.gpu_submissions }
	else if child != nil { after_submissions = child.timing.gpu_submissions }
	state.windows_move_redraws += 1
	state.windows_move_motion_samples += after_samples-before_samples
	state.windows_move_gpu_submissions += after_submissions-before_submissions
}

native_live_resize_windows_stop :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) {
	if state == nil || target == .None { return }
	hwnd := cast(win.HWND)native_live_resize_windows_move_hwnd(state, target, child)
	timer_active := native_live_resize_windows_timer_active(state, target, child)
	if timer_active && hwnd != nil { _ = win.KillTimer(hwnd, NATIVE_WINDOWS_MOVE_TIMER_ID) }
	native_live_resize_windows_set_timer_active(state, target, child, false)
	native_live_resize_windows_set_active(state, target, child, nil, false)
}

native_live_resize_windows_target :: proc(
	state: ^Native_Live_Resize_State,
	hwnd: win.HWND,
) -> (Native_Live_Resize_Target, ^Native_Secondary_Window) {
	if state == nil || hwnd == nil { return .None, nil }
	if native_live_resize_windows_move_hwnd(state, .Primary, nil) == rawptr(hwnd) { return .Primary, nil }
	if state.secondary_manager != nil {
		child := state.secondary_manager.child
		if child != nil && child.active && native_live_resize_windows_move_hwnd(state, .Secondary, child) == rawptr(hwnd) {
			return .Secondary, child
		}
	}
	return .None, nil
}

native_live_resize_windows_window_handle :: proc(window: ^sdl3.Window) -> win.HWND {
	if window == nil { return nil }
	properties := sdl3.GetWindowProperties(window)
	return cast(win.HWND)sdl3.GetPointerProperty(properties, sdl3.PROP_WINDOW_WIN32_HWND_POINTER, nil)
}

native_live_resize_windows_move_hwnd :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) -> rawptr {
	if target == .Primary {
		if state.move_hwnd != nil { return state.move_hwnd }
		return rawptr(native_live_resize_windows_window_handle(state.window))
	}
	if target == .Secondary && child != nil {
		if child.move_hwnd != nil { return child.move_hwnd }
		return rawptr(native_live_resize_windows_window_handle(child.window))
	}
	return nil
}

native_live_resize_windows_scheduler :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) -> ^Native_Motion_Scheduler_State {
	if target == .Primary { return state.motion_scheduler_state }
	if target == .Secondary && child != nil { return &child.motion_scheduler }
	return nil
}

native_live_resize_windows_runtime :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) -> ^alicorn.Runtime {
	if target == .Primary { return state.rt }
	if target == .Secondary && child != nil { return child.runtime }
	return nil
}

native_live_resize_windows_active :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) -> bool {
	if target == .Primary { return state.move_active }
	if target == .Secondary && child != nil { return child.move_active }
	return false
}

native_live_resize_windows_timer_active :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) -> bool {
	if target == .Primary { return state.move_timer_active }
	if target == .Secondary && child != nil { return child.move_timer_active }
	return false
}

native_live_resize_windows_last_redraw :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
) -> u64 {
	if target == .Primary { return state.move_last_redraw_ns }
	if target == .Secondary && child != nil { return child.move_last_redraw_ns }
	return 0
}

native_live_resize_windows_set_active :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
	hwnd: win.HWND,
	active: bool,
) {
	if target == .Primary {
		state.move_active = active
		if hwnd != nil { state.move_hwnd = rawptr(hwnd) }
		if !active { state.move_hwnd = nil; state.move_last_redraw_ns = 0 }
	} else if target == .Secondary && child != nil {
		child.move_active = active
		if hwnd != nil { child.move_hwnd = rawptr(hwnd) }
		if !active { child.move_hwnd = nil; child.move_last_redraw_ns = 0 }
	}
}

native_live_resize_windows_set_timer_active :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
	active: bool,
) {
	if target == .Primary { state.move_timer_active = active }
	else if target == .Secondary && child != nil { child.move_timer_active = active }
}

native_live_resize_windows_set_last_redraw :: proc(
	state: ^Native_Live_Resize_State,
	target: Native_Live_Resize_Target,
	child: ^Native_Secondary_Window,
	now_ns: u64,
) {
	if target == .Primary { state.move_last_redraw_ns = now_ns }
	else if target == .Secondary && child != nil { child.move_last_redraw_ns = now_ns }
}
