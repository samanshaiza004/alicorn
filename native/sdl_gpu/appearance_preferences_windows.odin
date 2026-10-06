#+build windows

package alicorn_sdl_gpu

import "base:runtime"
import "core:mem"
import "core:sync"
import win "core:sys/windows"
import sdl3 "vendor:sdl3"
import alicorn "../../runtime"

WIN32_APPEARANCE_SUBCLASS_ID :: win.UINT_PTR(0x414C49434F524E01)
WIN32_HCF_HIGHCONTRASTON :: win.DWORD(0x00000001)

Win32_High_Contrast :: struct {
	cb_size: win.UINT,
	dw_flags: win.DWORD,
	default_scheme: win.LPWSTR,
}

Win32_Appearance_State :: struct {
	allocator: mem.Allocator,
	monitor:   ^Native_Appearance_Monitor,
	hwnd:      win.HWND,
	installed: bool,
}

win32_appearance_snapshot_read :: proc() -> Native_Appearance_Snapshot {
	snapshot := Native_Appearance_Snapshot{}
	high_contrast := Win32_High_Contrast{cb_size=win.UINT(size_of(Win32_High_Contrast))}
	if win.SystemParametersInfoW(win.UINT(win.SPI_GETHIGHCONTRAST), high_contrast.cb_size, rawptr(&high_contrast), 0) {
		snapshot.known += {.Increased_Contrast}
		snapshot.preferences.increased_contrast = (high_contrast.dw_flags & WIN32_HCF_HIGHCONTRASTON) != 0
	}
	animations_enabled := win.BOOL(true)
	if win.SystemParametersInfoW(win.UINT(win.SPI_GETCLIENTAREAANIMATION), 0, rawptr(&animations_enabled), 0) {
		snapshot.known += {.Reduce_Motion}
		snapshot.preferences.reduce_motion = animations_enabled == false
	}
	disable_overlapped_content := win.BOOL(false)
	if win.SystemParametersInfoW(win.UINT(win.SPI_GETDISABLEOVERLAPPEDCONTENT), 0, rawptr(&disable_overlapped_content), 0) {
		snapshot.known += {.Reduce_Transparency}
		snapshot.preferences.reduce_transparency = disable_overlapped_content != false
	}
	return snapshot
}

win32_appearance_subclass :: proc "system" (
	hwnd: win.HWND,
	message: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
	subclass_id: win.UINT_PTR,
	ref_data: win.DWORD_PTR,
) -> win.LRESULT {
	context = runtime.default_context()
	state := cast(^Win32_Appearance_State)uintptr(ref_data)
	if state != nil && (message == win.WM_SETTINGCHANGE || message == win.WM_SYSCOLORCHANGE || message == win.WM_THEMECHANGED) {
		native_appearance_monitor_request_refresh(state.monitor)
	}
	return win.DefSubclassProc(hwnd, message, wparam, lparam)
}

native_appearance_monitor_init :: proc(
	monitor: ^Native_Appearance_Monitor,
	window: ^sdl3.Window,
	host_waker: ^Native_Host_Event_Waker,
	rt: ^alicorn.Runtime,
) -> bool {
	if monitor == nil || window == nil { return false }
	sync.atomic_store(&monitor.active, 1)
	monitor.host_waker = host_waker
	props := sdl3.GetWindowProperties(window)
	hwnd := cast(win.HWND)sdl3.GetPointerProperty(props, "SDL.window.win32.hwnd", nil)
	if hwnd == nil {
		sync.atomic_store(&monitor.active, 0)
		return false
	}
	state := new(Win32_Appearance_State, allocator=context.allocator)
	state.allocator = context.allocator
	state.monitor = monitor
	state.hwnd = hwnd
	win.SetWindowSubclass(hwnd, win32_appearance_subclass, WIN32_APPEARANCE_SUBCLASS_ID, win.DWORD_PTR(uintptr(state)))
	state.installed = true
	monitor.platform_data = rawptr(state)
	_ = native_appearance_monitor_apply_snapshot(monitor, rt, win32_appearance_snapshot_read())
	return state.installed
}

native_appearance_monitor_refresh :: proc(monitor: ^Native_Appearance_Monitor, rt: ^alicorn.Runtime) -> bool {
	if monitor == nil || sync.atomic_load(&monitor.active) == 0 || !native_appearance_monitor_take_pending(monitor) { return false }
	return native_appearance_monitor_apply_snapshot(monitor, rt, win32_appearance_snapshot_read())
}

native_appearance_monitor_destroy :: proc(monitor: ^Native_Appearance_Monitor) {
	if monitor == nil { return }
	sync.atomic_store(&monitor.active, 0)
	if monitor.platform_data != nil {
		state := cast(^Win32_Appearance_State)monitor.platform_data
		if state.installed { _ = RemoveWindowSubclass(state.hwnd, win32_appearance_subclass, WIN32_APPEARANCE_SUBCLASS_ID) }
		free(state, allocator=state.allocator)
		monitor.platform_data = nil
	}
	monitor.host_waker = nil
}
