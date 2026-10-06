#+build linux

package alicorn_sdl_gpu

import sdl3 "vendor:sdl3"
import "core:sync"
import alicorn "../../runtime"

native_appearance_monitor_init :: proc(
	monitor: ^Native_Appearance_Monitor,
	window: ^sdl3.Window,
	host_waker: ^Native_Host_Event_Waker,
	rt: ^alicorn.Runtime,
) -> bool {
	_ = window
	_ = host_waker
	_ = rt
	if monitor != nil { sync.atomic_store(&monitor.active, 1) }
	return false
}

native_appearance_monitor_refresh :: proc(monitor: ^Native_Appearance_Monitor, rt: ^alicorn.Runtime) -> bool {
	_ = monitor
	_ = rt
	return false
}

native_appearance_monitor_destroy :: proc(monitor: ^Native_Appearance_Monitor) {
	if monitor != nil { sync.atomic_store(&monitor.active, 0) }
}
