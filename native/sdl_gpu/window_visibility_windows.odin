#+build windows

package alicorn_sdl_gpu

import win "core:sys/windows"
import "vendor:sdl3"

// SDL's cached visibility flags can lag or miss an externally initiated
// minimize transition. The native HWND state is authoritative on Windows.
native_motion_window_windows_minimized :: proc(window: ^sdl3.Window) -> bool {
	if window == nil { return false }
	properties := sdl3.GetWindowProperties(window)
	hwnd := cast(win.HWND)sdl3.GetPointerProperty(
		properties, sdl3.PROP_WINDOW_WIN32_HWND_POINTER, nil,
	)
	return hwnd != nil && win.IsIconic(hwnd) == win.TRUE
}
