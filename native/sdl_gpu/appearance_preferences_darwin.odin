#+build darwin

package alicorn_sdl_gpu

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import "core:mem"
import "base:runtime"
import "core:strings"
import "core:sync"
import sdl3 "vendor:sdl3"
import alicorn "../../runtime"

Darwin_Appearance_State :: struct {
	allocator: mem.Allocator,
	workspace: ^NS.Object,
	center:    ^NS.NotificationCenter,
	observer:  ^NS.Object,
	name:      ^NS.String,
	selector:  NS.SEL,
	registered: bool,
}

darwin_active_appearance_monitor: ^Native_Appearance_Monitor

darwin_appearance_notification_callback :: proc "c" (
	unused: rawptr,
	selector: NS.SEL,
	notification: ^NS.Object,
) {
	_ = unused
	_ = selector
	_ = notification
	context = runtime.default_context()
	native_appearance_monitor_request_refresh(darwin_active_appearance_monitor)
}

darwin_appearance_selector :: proc(value: string) -> NS.SEL {
	utf8, err := strings.clone_to_cstring(value, context.temp_allocator)
	if err != nil { return nil }
	defer delete(utf8, context.temp_allocator)
	name := NS.String_initWithCString(NS.String_alloc(), utf8, .UTF8)
	if name == nil { return nil }
	defer NS.release(cast(^NS.Object)name)
	return NS.SelectorFromString(name)
}

darwin_appearance_snapshot_read :: proc(workspace: ^NS.Object) -> Native_Appearance_Snapshot {
	if workspace == nil { return {} }
	snapshot: Native_Appearance_Snapshot
	selector := darwin_appearance_selector("accessibilityDisplayShouldIncreaseContrast")
	if selector != nil && intrinsics.objc_send(NS.BOOL, workspace, "respondsToSelector:", selector) {
		snapshot.known += {.Increased_Contrast}
		snapshot.preferences.increased_contrast = intrinsics.objc_send(NS.BOOL, workspace, "accessibilityDisplayShouldIncreaseContrast")
	}
	selector = darwin_appearance_selector("accessibilityDisplayShouldReduceMotion")
	if selector != nil && intrinsics.objc_send(NS.BOOL, workspace, "respondsToSelector:", selector) {
		snapshot.known += {.Reduce_Motion}
		snapshot.preferences.reduce_motion = intrinsics.objc_send(NS.BOOL, workspace, "accessibilityDisplayShouldReduceMotion")
	}
	selector = darwin_appearance_selector("accessibilityDisplayShouldReduceTransparency")
	if selector != nil && intrinsics.objc_send(NS.BOOL, workspace, "respondsToSelector:", selector) {
		snapshot.known += {.Reduce_Transparency}
		snapshot.preferences.reduce_transparency = intrinsics.objc_send(NS.BOOL, workspace, "accessibilityDisplayShouldReduceTransparency")
	}
	selector = darwin_appearance_selector("accessibilityDisplayShouldDifferentiateWithoutColor")
	if selector != nil && intrinsics.objc_send(NS.BOOL, workspace, "respondsToSelector:", selector) {
		snapshot.known += {.Differentiate_Without_Color}
		snapshot.preferences.differentiate_without_color = intrinsics.objc_send(NS.BOOL, workspace, "accessibilityDisplayShouldDifferentiateWithoutColor")
	}
	return snapshot
}

native_appearance_monitor_init :: proc(
	monitor: ^Native_Appearance_Monitor,
	window: ^sdl3.Window,
	host_waker: ^Native_Host_Event_Waker,
	rt: ^alicorn.Runtime,
) -> bool {
	_ = window // NSWorkspace settings are process-wide; window is required by the common host contract.
	if monitor == nil || darwin_active_appearance_monitor != nil { return false }
	workspace_class := intrinsics.objc_find_class("NSWorkspace")
	if workspace_class == nil { return false }
	workspace := intrinsics.objc_send(^NS.Object, cast(^NS.Object)workspace_class, "sharedWorkspace")
	if workspace == nil { return false }
	center := intrinsics.objc_send(^NS.NotificationCenter, workspace, "notificationCenter")
	if center == nil { return false }
	name := NS.String_initWithCString(
		NS.String_alloc(),
		"NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification",
		.UTF8,
	)
	if name == nil { return false }
	observer := NS.new(NS.Object)
	if observer == nil {
		NS.release(cast(^NS.Object)name)
		return false
	}
	state := new(Darwin_Appearance_State, allocator=context.allocator)
	state.allocator = context.allocator
	state.workspace = workspace
	state.center = center
	state.observer = observer
	state.name = name
	state.selector = NS.MenuItem_registerActionCallback("alicornAppearanceDisplayOptionsDidChange", darwin_appearance_notification_callback)
	sync.atomic_store(&monitor.active, 1)
	monitor.host_waker = host_waker
	monitor.platform_data = rawptr(state)
	darwin_active_appearance_monitor = monitor
	NS.NotificationCenter_addObserver(center, observer, state.selector, name, workspace)
	state.registered = true
	_ = native_appearance_monitor_apply_snapshot(monitor, rt, darwin_appearance_snapshot_read(workspace))
	return true
}

native_appearance_monitor_refresh :: proc(monitor: ^Native_Appearance_Monitor, rt: ^alicorn.Runtime) -> bool {
	if monitor == nil || sync.atomic_load(&monitor.active) == 0 || monitor.platform_data == nil ||
		!native_appearance_monitor_take_pending(monitor) { return false }
	state := cast(^Darwin_Appearance_State)monitor.platform_data
	return native_appearance_monitor_apply_snapshot(monitor, rt, darwin_appearance_snapshot_read(state.workspace))
}

native_appearance_monitor_destroy :: proc(monitor: ^Native_Appearance_Monitor) {
	if monitor == nil { return }
	sync.atomic_store(&monitor.active, 0)
	if monitor.platform_data != nil {
		state := cast(^Darwin_Appearance_State)monitor.platform_data
		if state.registered { NS.NotificationCenter_removeObserver(state.center, state.observer) }
		if state.observer != nil { NS.release(state.observer) }
		if state.name != nil { NS.release(cast(^NS.Object)state.name) }
		free(state, allocator=state.allocator)
		monitor.platform_data = nil
	}
	if darwin_active_appearance_monitor == monitor { darwin_active_appearance_monitor = nil }
	monitor.host_waker = nil
}
