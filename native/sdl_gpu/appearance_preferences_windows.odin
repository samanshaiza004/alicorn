#+build windows

package alicorn_sdl_gpu

import "base:runtime"
import "core:mem"
import "core:sync"
import win "core:sys/windows"
import sdl3 "vendor:sdl3"
import alicorn "../../runtime"

foreign import runtimeobject "system:RuntimeObject.lib"
foreign runtimeobject {
	RoInitialize         :: proc "system" (init_type: u32) -> win.HRESULT ---
	RoUninitialize       :: proc "system" () ---
	RoActivateInstance   :: proc "system" (class_id: rawptr, instance: ^rawptr) -> win.HRESULT ---
	WindowsCreateString  :: proc "system" (source: ^u16, length: u32, value: ^rawptr) -> win.HRESULT ---
	WindowsDeleteString  :: proc "system" (value: rawptr) -> win.HRESULT ---
}

WIN32_APPEARANCE_SUBCLASS_ID :: win.UINT_PTR(0x414C49434F524E01)
WIN32_APPEARANCE_REFRESH_MESSAGE :: win.UINT(0x84C1)
WIN32_HCF_HIGHCONTRASTON :: win.DWORD(0x00000001)

Win32_High_Contrast :: struct {
	cb_size: win.UINT,
	dw_flags: win.DWORD,
	default_scheme: win.LPWSTR,
}

Win32_Appearance_State :: struct {
	allocator:                 mem.Allocator,
	monitor:                   ^Native_Appearance_Monitor,
	hwnd:                      win.HWND,
	ui_settings4:               rawptr,
	ui_settings2:               rawptr,
	settings_event_handler:     ^WinRT_Appearance_Event_Handler,
	advanced_effects_token:    WinRT_Event_Token,
	text_scale_token:          WinRT_Event_Token,
	ro_initialized:            bool,
	advanced_effects_subscribed: bool,
	text_scale_subscribed:     bool,
	installed:                 bool,
}

WinRT_Inspectable_VTable :: struct {
	query_interface:      proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:              proc "system" (this: rawptr) -> win.ULONG,
	release:              proc "system" (this: rawptr) -> win.ULONG,
	get_iids:             rawptr,
	get_runtime_class_name: rawptr,
	get_trust_level:      rawptr,
}

WinRT_Inspectable :: struct {
	vtable: ^WinRT_Inspectable_VTable,
}

WinRT_UI_Settings4_VTable :: struct {
	query_interface:               proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:                       proc "system" (this: rawptr) -> win.ULONG,
	release:                       proc "system" (this: rawptr) -> win.ULONG,
	get_iids:                      rawptr,
	get_runtime_class_name:        rawptr,
	get_trust_level:               rawptr,
	get_advanced_effects_enabled:  proc "system" (this: rawptr, enabled: ^bool) -> win.HRESULT,
	add_advanced_effects_changed:  proc "system" (this: rawptr, handler: rawptr, token: ^WinRT_Event_Token) -> win.HRESULT,
	remove_advanced_effects_changed: proc "system" (this: rawptr, token: WinRT_Event_Token) -> win.HRESULT,
}

WinRT_UI_Settings4 :: struct {
	vtable: ^WinRT_UI_Settings4_VTable,
}

// IUISettings2 exposes TextScaleFactor and TextScaleFactorChanged. Its vtable
// begins with IInspectable's six entries, then these three interface methods.
WinRT_UI_Settings2_VTable :: struct {
	query_interface:                  proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:                          proc "system" (this: rawptr) -> win.ULONG,
	release:                          proc "system" (this: rawptr) -> win.ULONG,
	get_iids:                         rawptr,
	get_runtime_class_name:           rawptr,
	get_trust_level:                  rawptr,
	get_text_scale_factor:            proc "system" (this: rawptr, value: ^f64) -> win.HRESULT,
	add_text_scale_factor_changed:    proc "system" (this: rawptr, handler: rawptr, token: ^WinRT_Event_Token) -> win.HRESULT,
	remove_text_scale_factor_changed: proc "system" (this: rawptr, token: WinRT_Event_Token) -> win.HRESULT,
}

WinRT_UI_Settings2 :: struct {
	vtable: ^WinRT_UI_Settings2_VTable,
}

WinRT_Event_Token :: struct {
	value: i64,
}

WinRT_Appearance_Event_Handler :: struct {
	vtable:    ^WinRT_Appearance_Event_Handler_VTable,
	hwnd:      win.HWND,
	allocator: mem.Allocator,
	ref_count: i32,
}

WinRT_Appearance_Event_Handler_VTable :: struct {
	query_interface: proc "system" (this: rawptr, iid: ^win.GUID, result: ^rawptr) -> win.HRESULT,
	add_ref:         proc "system" (this: rawptr) -> win.ULONG,
	release:         proc "system" (this: rawptr) -> win.ULONG,
	invoke:          proc "system" (this: rawptr, sender: rawptr, args: rawptr) -> win.HRESULT,
}

WINRT_IID_IUNKNOWN :: win.GUID{0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
WINRT_IID_UI_SETTINGS4 :: win.GUID{0x52BB3002, 0x919B, 0x4D6B, {0x9B, 0x78, 0x8D, 0xD6, 0x6F, 0xF4, 0xB9, 0x3B}}
WINRT_IID_UI_SETTINGS2 :: win.GUID{0xBAD82401, 0x2721, 0x44F9, {0xBB, 0x91, 0x2B, 0xB2, 0x28, 0xBE, 0x44, 0x2F}}
WINRT_IID_UI_SETTINGS_EFFECTS_CHANGED :: win.GUID{0x2DBDBA9D, 0x20DA, 0x519D, {0x90, 0x78, 0x09, 0xF8, 0x35, 0xBC, 0x5B, 0xC7}}
WINRT_HRESULT_NO_INTERFACE :: win.HRESULT(i32(-2147467262))
WINRT_HRESULT_CHANGED_MODE :: win.HRESULT(i32(-2147417850))
WINRT_RO_INIT_MULTITHREADED :: u32(1)

winrt_appearance_event_handler_query_interface :: proc "system" (
	this: rawptr,
	iid: ^win.GUID,
	result: ^rawptr,
) -> win.HRESULT {
	if result == nil { return win.HRESULT(i32(-2147467261)) }
	result^ = nil
	if iid == nil || (iid^ != WINRT_IID_IUNKNOWN && iid^ != WINRT_IID_UI_SETTINGS_EFFECTS_CHANGED) {
		return WINRT_HRESULT_NO_INTERFACE
	}
	result^ = this
	_ = winrt_appearance_event_handler_add_ref(this)
	return win.S_OK
}

winrt_appearance_event_handler_add_ref :: proc "system" (this: rawptr) -> win.ULONG {
	handler := cast(^WinRT_Appearance_Event_Handler)this
	return win.ULONG(sync.atomic_add(&handler.ref_count, 1) + 1)
}

winrt_appearance_event_handler_release :: proc "system" (this: rawptr) -> win.ULONG {
	context = runtime.default_context()
	handler := cast(^WinRT_Appearance_Event_Handler)this
	remaining := sync.atomic_add(&handler.ref_count, -1) - 1
	if remaining == 0 {
		free(handler, allocator=handler.allocator)
	}
	return win.ULONG(remaining)
}

winrt_appearance_event_handler_invoke :: proc "system" (this: rawptr, sender, args: rawptr) -> win.HRESULT {
	context = runtime.default_context()
	handler := cast(^WinRT_Appearance_Event_Handler)this
	if handler.hwnd != nil {
		_ = win.PostMessageW(handler.hwnd, WIN32_APPEARANCE_REFRESH_MESSAGE, 0, 0)
	}
	return win.S_OK
}

WINRT_APPEARANCE_EVENT_HANDLER_VTABLE := WinRT_Appearance_Event_Handler_VTable{
	winrt_appearance_event_handler_query_interface,
	winrt_appearance_event_handler_add_ref,
	winrt_appearance_event_handler_release,
	winrt_appearance_event_handler_invoke,
}

winrt_ui_settings_release :: proc(instance: rawptr) {
	if instance == nil { return }
	inspectable := cast(^WinRT_Inspectable)instance
	inspectable.vtable.release(instance)
}

winrt_appearance_monitor_init :: proc(state: ^Win32_Appearance_State) -> bool {
	if state == nil { return false }
	hr := RoInitialize(WINRT_RO_INIT_MULTITHREADED)
	if win.SUCCEEDED(hr) {
		state.ro_initialized = true
	} else if hr != WINRT_HRESULT_CHANGED_MODE {
		return false
	}

	class_name := win.utf8_to_utf16("Windows.UI.ViewManagement.UISettings", context.temp_allocator)
	if len(class_name) == 0 { return false }
	class_id: rawptr
	if !win.SUCCEEDED(WindowsCreateString(&class_name[0], u32(len(class_name)), &class_id)) { return false }
	defer _ = WindowsDeleteString(class_id)

	instance: rawptr
	if !win.SUCCEEDED(RoActivateInstance(class_id, &instance)) || instance == nil { return false }
	defer winrt_ui_settings_release(instance)

	inspectable := cast(^WinRT_Inspectable)instance
	iid_ui_settings4 := WINRT_IID_UI_SETTINGS4
	if win.SUCCEEDED(inspectable.vtable.query_interface(instance, &iid_ui_settings4, &state.ui_settings4)) {
		// Keep this reference through event unsubscription at shutdown.
	} else {
		state.ui_settings4 = nil
	}
	iid_ui_settings2 := WINRT_IID_UI_SETTINGS2
	if win.SUCCEEDED(inspectable.vtable.query_interface(instance, &iid_ui_settings2, &state.ui_settings2)) {
		// Keep this reference through event unsubscription at shutdown.
	} else {
		state.ui_settings2 = nil
	}
	if state.ui_settings4 == nil && state.ui_settings2 == nil { return false }

	handler := new(WinRT_Appearance_Event_Handler, allocator=state.allocator)
	handler^ = WinRT_Appearance_Event_Handler{
		vtable = &WINRT_APPEARANCE_EVENT_HANDLER_VTABLE,
		hwnd = state.hwnd,
		allocator = state.allocator,
		ref_count = 1,
	}
	state.settings_event_handler = handler
	if state.ui_settings4 != nil {
		settings := cast(^WinRT_UI_Settings4)state.ui_settings4
		state.advanced_effects_subscribed = win.SUCCEEDED(settings.vtable.add_advanced_effects_changed(
			state.ui_settings4, rawptr(handler), &state.advanced_effects_token))
	}
	if state.ui_settings2 != nil {
		settings := cast(^WinRT_UI_Settings2)state.ui_settings2
		state.text_scale_subscribed = win.SUCCEEDED(settings.vtable.add_text_scale_factor_changed(
			state.ui_settings2, rawptr(handler), &state.text_scale_token))
	}
	if !state.advanced_effects_subscribed && !state.text_scale_subscribed {
		_ = winrt_appearance_event_handler_release(rawptr(handler))
		state.settings_event_handler = nil
	}
	return true
}

winrt_ui_settings_advanced_effects_enabled :: proc(state: ^Win32_Appearance_State) -> (enabled: bool, available: bool) {
	if state == nil || state.ui_settings4 == nil { return }
	settings := cast(^WinRT_UI_Settings4)state.ui_settings4
	available = win.SUCCEEDED(settings.vtable.get_advanced_effects_enabled(state.ui_settings4, &enabled))
	return
}

winrt_ui_settings_text_scale_factor :: proc(state: ^Win32_Appearance_State) -> (scale: f32, available: bool) {
	if state == nil || state.ui_settings2 == nil { return }
	settings := cast(^WinRT_UI_Settings2)state.ui_settings2
	value: f64
	if !win.SUCCEEDED(settings.vtable.get_text_scale_factor(state.ui_settings2, &value)) || value < 1 || value > 2.25 {
		return
	}
	scale = f32(value)
	available = true
	return
}

win32_appearance_snapshot_read :: proc(state: ^Win32_Appearance_State) -> Native_Appearance_Snapshot {
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
	advanced_effects_enabled, advanced_effects_available := winrt_ui_settings_advanced_effects_enabled(state)
	if advanced_effects_available {
		snapshot.known += {.Reduce_Transparency}
		snapshot.preferences.reduce_transparency = !advanced_effects_enabled
	} else {
		disable_overlapped_content := win.BOOL(false)
		if win.SystemParametersInfoW(win.UINT(win.SPI_GETDISABLEOVERLAPPEDCONTENT), 0, rawptr(&disable_overlapped_content), 0) {
			snapshot.known += {.Reduce_Transparency}
			snapshot.preferences.reduce_transparency = disable_overlapped_content != false
		}
	}
	text_scale, text_scale_available := winrt_ui_settings_text_scale_factor(state)
	if text_scale_available {
		snapshot.text_scale = text_scale
		snapshot.text_scale_known = true
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
	if state != nil && message == WIN32_APPEARANCE_REFRESH_MESSAGE {
		native_appearance_monitor_request_refresh(state.monitor)
	} else if state != nil && (message == win.WM_SETTINGCHANGE || message == win.WM_SYSCOLORCHANGE || message == win.WM_THEMECHANGED) {
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
	_ = winrt_appearance_monitor_init(state)
	_ = native_appearance_monitor_apply_snapshot(monitor, rt, win32_appearance_snapshot_read(state))
	return state.installed
}

native_appearance_monitor_refresh :: proc(monitor: ^Native_Appearance_Monitor, rt: ^alicorn.Runtime) -> bool {
	if monitor == nil || sync.atomic_load(&monitor.active) == 0 || !native_appearance_monitor_take_pending(monitor) { return false }
	return native_appearance_monitor_apply_snapshot(monitor, rt, win32_appearance_snapshot_read(cast(^Win32_Appearance_State)monitor.platform_data))
}

native_appearance_monitor_destroy :: proc(monitor: ^Native_Appearance_Monitor) {
	if monitor == nil { return }
	sync.atomic_store(&monitor.active, 0)
	if monitor.platform_data != nil {
		state := cast(^Win32_Appearance_State)monitor.platform_data
		if state.installed { _ = RemoveWindowSubclass(state.hwnd, win32_appearance_subclass, WIN32_APPEARANCE_SUBCLASS_ID) }
		if state.ui_settings4 != nil {
			settings := cast(^WinRT_UI_Settings4)state.ui_settings4
			if state.advanced_effects_subscribed {
				_ = settings.vtable.remove_advanced_effects_changed(state.ui_settings4, state.advanced_effects_token)
			}
			winrt_ui_settings_release(state.ui_settings4)
			state.ui_settings4 = nil
		}
		if state.ui_settings2 != nil {
			settings := cast(^WinRT_UI_Settings2)state.ui_settings2
			if state.text_scale_subscribed {
				_ = settings.vtable.remove_text_scale_factor_changed(state.ui_settings2, state.text_scale_token)
			}
			winrt_ui_settings_release(state.ui_settings2)
			state.ui_settings2 = nil
		}
		if state.settings_event_handler != nil {
			state.settings_event_handler.hwnd = nil
			_ = winrt_appearance_event_handler_release(rawptr(state.settings_event_handler))
			state.settings_event_handler = nil
		}
		if state.ro_initialized { RoUninitialize() }
		free(state, allocator=state.allocator)
		monitor.platform_data = nil
	}
	monitor.host_waker = nil
}
