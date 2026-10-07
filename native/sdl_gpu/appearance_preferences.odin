package alicorn_sdl_gpu

import alicorn "../../runtime"
import "core:sync"
import "vendor:sdl3"

Native_Appearance_Field :: alicorn.Accessibility_Appearance_Field
Native_Appearance_Known_Fields :: alicorn.Accessibility_Appearance_Known_Fields

// Native_Appearance_Snapshot distinguishes unsupported/failed native queries
// from a known false preference. Unknown values never erase the last known
// value or the Alicorn default.
Native_Appearance_Snapshot :: struct {
	preferences: alicorn.Accessibility_Appearance_Preferences,
	known:       Native_Appearance_Known_Fields,
}

Native_Appearance_Monitor :: struct {
	host_waker:      ^Native_Host_Event_Waker,
	platform_data:   rawptr,
	snapshot:        Native_Appearance_Snapshot,
	refresh_pending: u32,
	wake_queued:     u32,
	active:          u32,
}

native_appearance_snapshot_merge :: proc(
	previous: Native_Appearance_Snapshot,
	observed: Native_Appearance_Snapshot,
) -> (merged: Native_Appearance_Snapshot, preferences_changed: bool) {
	merged = previous
	for field in Native_Appearance_Field {
		if field not_in observed.known { continue }
		merged.known += {field}
		switch field {
		case .Increased_Contrast:
			merged.preferences.increased_contrast = observed.preferences.increased_contrast
		case .Reduce_Motion:
			merged.preferences.reduce_motion = observed.preferences.reduce_motion
		case .Reduce_Transparency:
			merged.preferences.reduce_transparency = observed.preferences.reduce_transparency
		case .Differentiate_Without_Color:
			merged.preferences.differentiate_without_color = observed.preferences.differentiate_without_color
		}
	}
	preferences_changed = merged.preferences != previous.preferences
	return
}

// Native notification callbacks only mark a refresh and queue one host-only
// wake. Platform queries and Runtime mutation happen later on the event loop.
native_appearance_monitor_request_refresh :: proc(monitor: ^Native_Appearance_Monitor) {
	if monitor == nil || sync.atomic_load(&monitor.active) == 0 { return }
	sync.atomic_store(&monitor.refresh_pending, 1)
	if monitor.host_waker != nil && sync.atomic_exchange(&monitor.wake_queued, 1) == 0 {
		if !native_host_event_wake(monitor.host_waker) {
			sync.atomic_store(&monitor.wake_queued, 0)
		}
	}
}

native_appearance_monitor_pending :: proc(monitor: ^Native_Appearance_Monitor) -> bool {
	return monitor != nil && sync.atomic_load(&monitor.refresh_pending) != 0
}

native_appearance_monitor_take_pending :: proc(monitor: ^Native_Appearance_Monitor) -> bool {
	if monitor == nil { return false }
	sync.atomic_store(&monitor.wake_queued, 0)
	return sync.atomic_exchange(&monitor.refresh_pending, 0) != 0
}

native_appearance_monitor_apply_snapshot :: proc(
	monitor: ^Native_Appearance_Monitor,
	rt: ^alicorn.Runtime,
	observed: Native_Appearance_Snapshot,
) -> bool {
	if monitor == nil { return false }
	next, _ := native_appearance_snapshot_merge(monitor.snapshot, observed)
	monitor.snapshot = next
	if rt != nil {
		return alicorn.style_root_accessibility_observation_set(rt, alicorn.Accessibility_Appearance_Observation{
			preferences=next.preferences,
			known=next.known,
		})
	}
	return false
}

// Platform-specific implementations live in appearance_preferences_{windows,darwin,other}.odin.
