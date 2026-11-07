#+build darwin

package alicorn_sdl_gpu

import "base:intrinsics"
import Foundation "core:sys/darwin/Foundation"
import NS "vendor:darwin/AppKit"
import "core:mem"
import "base:runtime"
import "core:strings"
import "core:sync"
import sdl3 "vendor:sdl3"
import alicorn "../../runtime"

// NSWorkspace notifications are process-wide; the shared observer fans each
// change out to the per-window monitors and their host event queues.
Darwin_Appearance_Service :: struct {
	allocator: mem.Allocator,
	workspace: ^NS.Object,
	center:    ^NS.NotificationCenter,
	observer:  ^NS.Object,
	name:      ^NS.String,
	selector:  NS.SEL,
	registered: bool,
	monitors: [dynamic]^Native_Appearance_Monitor,
}

darwin_appearance_service_mutex: sync.Mutex
darwin_appearance_service: ^Darwin_Appearance_Service

darwin_appearance_notification_callback :: proc "c" (
	unused: rawptr,
	selector: NS.SEL,
	notification: ^NS.Object,
) {
	_ = unused
	_ = selector
	_ = notification
	context = runtime.default_context()
	sync.mutex_lock(&darwin_appearance_service_mutex)
	service := darwin_appearance_service
	if service != nil {
		for monitor in service.monitors {
			native_appearance_monitor_request_refresh(monitor)
		}
	}
	sync.mutex_unlock(&darwin_appearance_service_mutex)
}

darwin_appearance_selector :: proc(value: string) -> NS.SEL {
	utf8, err := strings.clone_to_cstring(value, context.temp_allocator)
	if err != nil { return nil }
	defer delete(utf8, context.temp_allocator)
	name := Foundation.String_initWithCString_encoding(
		NS.alloc(NS.String), utf8, Foundation.StringEncoding(Foundation.UTF8StringEncoding),
	)
	if name == nil { return nil }
	defer darwin_objc_release(cast(^NS.Object)name)
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
	if monitor == nil { return false }
	sync.mutex_lock(&darwin_appearance_service_mutex)
	if monitor.platform_data != nil {
		sync.mutex_unlock(&darwin_appearance_service_mutex)
		return false
	}
	service := darwin_appearance_service
	new_service := service == nil
	if new_service {
		service = darwin_appearance_service_make()
		if service == nil {
			sync.mutex_unlock(&darwin_appearance_service_mutex)
			return false
		}
	}
	_, append_error := append(&service.monitors, monitor)
	if append_error != nil {
		if new_service { darwin_appearance_service_destroy(service) }
		sync.mutex_unlock(&darwin_appearance_service_mutex)
		return false
	}
	if new_service { darwin_appearance_service = service }
	monitor.host_waker = host_waker
	monitor.platform_data = rawptr(service)
	sync.atomic_store(&monitor.active, 1)
	workspace := service.workspace
	sync.mutex_unlock(&darwin_appearance_service_mutex)
	_ = native_appearance_monitor_apply_snapshot(monitor, rt, darwin_appearance_snapshot_read(workspace))
	return true
}

darwin_appearance_service_make :: proc() -> ^Darwin_Appearance_Service {
	workspace_class := intrinsics.objc_find_class("NSWorkspace")
	if workspace_class == nil { return nil }
	workspace := intrinsics.objc_send(^NS.Object, cast(^NS.Object)workspace_class, "sharedWorkspace")
	if workspace == nil { return nil }
	center := intrinsics.objc_send(^NS.NotificationCenter, workspace, "notificationCenter")
	if center == nil { return nil }
	name := Foundation.String_initWithCString_encoding(
		NS.alloc(NS.String),
		"NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification",
		Foundation.StringEncoding(Foundation.UTF8StringEncoding),
	)
	if name == nil { return nil }
	observer := NS.new(NS.Object)
	if observer == nil {
		darwin_objc_release(cast(^NS.Object)name)
		return nil
	}
	selector := NS.MenuItem_registerActionCallback("alicornAppearanceDisplayOptionsDidChange", darwin_appearance_notification_callback)
	if selector == nil {
		darwin_objc_release(cast(^NS.Object)observer)
		darwin_objc_release(cast(^NS.Object)name)
		return nil
	}
	service := new(Darwin_Appearance_Service, allocator=context.allocator)
	if service == nil {
		darwin_objc_release(cast(^NS.Object)observer)
		darwin_objc_release(cast(^NS.Object)name)
		return nil
	}
	service.allocator = context.allocator
	service.workspace = workspace
	service.center = center
	service.observer = observer
	service.name = name
	service.selector = selector
	service.monitors = make([dynamic]^Native_Appearance_Monitor, 0, allocator=service.allocator)
	Foundation.NotificationCenter_addObserver(center, observer, selector, name, workspace)
	service.registered = true
	return service
}

darwin_appearance_service_destroy :: proc(service: ^Darwin_Appearance_Service) {
	if service == nil { return }
	if service.registered { Foundation.NotificationCenter_removeObserver(service.center, service.observer) }
	if darwin_appearance_service == service { darwin_appearance_service = nil }
	delete(service.monitors)
	if service.observer != nil { darwin_objc_release(service.observer) }
	if service.name != nil { darwin_objc_release(cast(^NS.Object)service.name) }
	free(service, allocator=service.allocator)
}

native_appearance_monitor_refresh :: proc(monitor: ^Native_Appearance_Monitor, rt: ^alicorn.Runtime) -> bool {
	if monitor == nil || sync.atomic_load(&monitor.active) == 0 || monitor.platform_data == nil ||
		!native_appearance_monitor_take_pending(monitor) { return false }
	service := cast(^Darwin_Appearance_Service)monitor.platform_data
	return native_appearance_monitor_apply_snapshot(monitor, rt, darwin_appearance_snapshot_read(service.workspace))
}

native_appearance_monitor_destroy :: proc(monitor: ^Native_Appearance_Monitor) {
	if monitor == nil { return }
	sync.mutex_lock(&darwin_appearance_service_mutex)
	sync.atomic_store(&monitor.active, 0)
	service := cast(^Darwin_Appearance_Service)monitor.platform_data
	monitor.platform_data = nil
	monitor.host_waker = nil
	if service != nil {
		for registered_monitor, index in service.monitors {
			if registered_monitor == monitor {
				ordered_remove(&service.monitors, index)
				break
			}
		}
		if len(service.monitors) == 0 {
			darwin_appearance_service_destroy(service)
		}
	}
	sync.mutex_unlock(&darwin_appearance_service_mutex)
}
