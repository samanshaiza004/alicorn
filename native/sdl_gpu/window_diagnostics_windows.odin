#+build windows

package alicorn_sdl_gpu

import "core:c"
import "core:fmt"
import "core:strings"
import win "core:sys/windows"
import "vendor:sdl3"

WIN32_WINDOW_GEOMETRY_CAPACITY :: 64

Win32_Window_Geometry_Sample :: struct {
	timestamp_ns: u64,
	message: win.UINT,
	outer: win.RECT,
	client_origin: win.POINT,
	sdl_x, sdl_y: i32,
	dpi: u32,
	native_topmost: bool,
	requested_x, requested_y: i32,
	requested_flags, effective_flags: win.UINT,
	move_preserved: bool,
}

Win32_Window_Geometry_Recorder :: struct {
	samples: [WIN32_WINDOW_GEOMETRY_CAPACITY]Win32_Window_Geometry_Sample,
	next_index, count: int,
	topmost_promotions_preserved: u64,
}

win32_window_geometry_snapshot :: proc(state: ^Win32_Menu_State) -> Win32_Window_Geometry_Sample {
	sample := Win32_Window_Geometry_Sample{timestamp_ns=u64(sdl3.GetTicksNS())}
	if state == nil || state.hwnd == nil { return sample }
	_ = win.GetWindowRect(state.hwnd, &sample.outer)
	_ = win.ClientToScreen(state.hwnd, &sample.client_origin)
	sample.dpi = win.GetDpiForWindow(state.hwnd)
	sample.native_topmost = (cast(win.UINT)win.GetWindowLongW(state.hwnd, win.GWL_EXSTYLE) & win.WS_EX_TOPMOST) != 0
	if state.menu != nil && state.menu.window != nil {
		x, y: c.int
		_ = sdl3.GetWindowPosition(state.menu.window, &x, &y)
		sample.sdl_x, sample.sdl_y = i32(x), i32(y)
	}
	return sample
}

win32_window_geometry_record :: proc(state: ^Win32_Menu_State, message: win.UINT,
	position: ^win.WINDOWPOS, requested_flags: win.UINT, move_preserved: bool) {
	if state == nil { return }
	sample := win32_window_geometry_snapshot(state)
	sample.message = message
	sample.move_preserved = move_preserved
	if position != nil {
		sample.requested_x, sample.requested_y = i32(position.x), i32(position.y)
		sample.requested_flags = requested_flags
		sample.effective_flags = position.flags
	}
	recorder := &state.window_geometry
	recorder.samples[recorder.next_index] = sample
	recorder.next_index = (recorder.next_index+1) % WIN32_WINDOW_GEOMETRY_CAPACITY
	recorder.count = min(recorder.count+1, WIN32_WINDOW_GEOMETRY_CAPACITY)
}

win32_window_geometry_message_name :: proc(message: win.UINT) -> string {
	switch message {
	case win.WM_WINDOWPOSCHANGING: return "window_position_changing"
	case win.WM_WINDOWPOSCHANGED: return "window_position_changed"
	case win.WM_MOUSEMOVE: return "client_mouse_entry"
	case win.WM_MOUSELEAVE: return "client_mouse_leave"
	case win.WM_ACTIVATE: return "activation_changed"
	case win.WM_DPICHANGED: return "dpi_changed"
	}
	return "snapshot"
}

native_window_append_platform_diagnostics :: proc(builder: ^strings.Builder, menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { strings.write_string(builder, `, "win32": null`); return }
	state := cast(^Win32_Menu_State)menu.platform_data
	current := win32_window_geometry_snapshot(state)
	fmt.sbprintf(builder, `, "win32": {{
    "hwnd": %d,
    "outer_rect": [%d, %d, %d, %d],
    "client_origin": [%d, %d],
    "dpi": %d,
    "native_always_on_top": %t,
    "topmost_promotions_preserved": %d,
    "position_history": [`, uintptr(state.hwnd),
		current.outer.left, current.outer.top, current.outer.right, current.outer.bottom,
		current.client_origin.x, current.client_origin.y, current.dpi, current.native_topmost,
		state.window_geometry.topmost_promotions_preserved)
	recorder := &state.window_geometry
	oldest := (recorder.next_index-recorder.count+WIN32_WINDOW_GEOMETRY_CAPACITY) % WIN32_WINDOW_GEOMETRY_CAPACITY
	for i in 0..<recorder.count {
		if i > 0 { strings.write_string(builder, ",") }
		s := recorder.samples[(oldest+i) % WIN32_WINDOW_GEOMETRY_CAPACITY]
		fmt.sbprintf(builder, `
      {{"timestamp_ns": %d, "message": "%s", "outer_rect": [%d, %d, %d, %d], "client_origin": [%d, %d], "sdl_position": [%d, %d], "dpi": %d, "native_always_on_top": %t, "requested_position": [%d, %d], "requested_flags": %d, "effective_flags": %d, "move_preserved": %t}}`,
			s.timestamp_ns, win32_window_geometry_message_name(s.message),
			s.outer.left, s.outer.top, s.outer.right, s.outer.bottom, s.client_origin.x, s.client_origin.y,
			s.sdl_x, s.sdl_y, s.dpi, s.native_topmost, s.requested_x, s.requested_y,
			s.requested_flags, s.effective_flags, s.move_preserved)
	}
	strings.write_string(builder, "]}")
}
