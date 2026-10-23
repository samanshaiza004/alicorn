#+build windows

package alicorn_sdl_gpu

import "core:mem"
import "base:runtime"
import win "core:sys/windows"
import "core:c"
import "core:fmt"
import sdl3 "vendor:sdl3"
import alicorn "../../runtime"

foreign import dwmapi "system:Dwmapi.lib"
foreign dwmapi {
	DwmDefWindowProc :: proc "system" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, result: ^win.LRESULT) -> win.BOOL ---
	DwmGetWindowAttribute :: proc "system" (hwnd: win.HWND, attribute: u32, value: rawptr, value_size: win.DWORD) -> win.HRESULT ---
	DwmExtendFrameIntoClientArea :: proc "system" (hwnd: win.HWND, margins: ^win.MARGINS) -> win.HRESULT ---
}

foreign import comctl32 "system:Comctl32.lib"
foreign comctl32 {
	RemoveWindowSubclass :: proc "system" (hwnd: win.HWND, callback: win.SUBCLASSPROC, subclass_id: win.UINT_PTR) -> win.BOOL ---
}

foreign import user32 "system:User32.lib"
foreign user32 {
	DrawMenuBar :: proc "system" (hwnd: win.HWND) -> win.BOOL ---
	CheckMenuItem :: proc "system" (menu: win.HMENU, item: win.UINT, check: win.UINT) -> win.UINT ---
}

WIN32_MENU_SUBCLASS_ID :: win.UINT_PTR(0x414C49434F524E)
WIN32_MF_GRAYED          :: win.UINT(0x00000001)
WIN32_MF_POPUP           :: win.UINT(0x00000010)
WIN32_MF_SEPARATOR       :: win.UINT(0x00000800)
WIN32_MF_CHECKED         :: win.UINT(0x00000008)
WIN32_MF_BYPOSITION      :: win.UINT(0x00000400)
WIN32_VK_SPACE            :: 0x20
WIN32_VK_F10              :: 0x79
WIN32_VK_RETURN           :: 0x0D
WIN32_VK_ESCAPE           :: 0x1B
WIN32_VK_LEFT             :: 0x25
WIN32_VK_RIGHT            :: 0x27
WIN32_DWMWA_CAPTION_BUTTON_BOUNDS :: u32(5)
WIN32_MENU_HOVER_MIX              :: 0.10
WIN32_MENU_OPEN_MIX               :: 0.14
WIN32_MENU_PRESSED_MIX            :: 0.20

NATIVE_MENU_HOST_NODE_BASE :: alicorn.Node_ID(0xFFFF_FFFF_FFFF_F000)
NATIVE_MENU_HOST_SOLID_NODE :: alicorn.Node_ID(0xFFFF_FFFF_FFFF_E000)

Win32_Menu_Label :: struct {
	text:   []u16,
	length: int,
	bounds: win.RECT,
	popup:  win.HMENU,
	host_node: alicorn.Node_ID,
	direct_menu: ^Application_Menu,
}

Win32_Caption_Control :: struct {
	// Client-relative physical pixels used for WM_NCHITTEST.
	bounds: win.RECT,
	// Icon alignment can follow the visible button while leaving the resize
	// gutter outside the native button hit target.
	glyph_bounds: win.RECT,
	// Hover paint may cover the resize gutter without changing its hit target.
	hover_bounds: win.RECT,
	hit_test: win.LRESULT,
}

Win32_Chrome_Hit_Region :: struct {
	bounds: win.RECT,
	kind: Window_Chrome_Region_Kind,
}

Win32_Chrome_Gesture_Owner :: enum u8 {
	None,
	Alicorn,
	Window,
	Native_Menu,
}

Win32_Chrome_Geometry :: struct {
	header: win.RECT,
	regions: [WINDOW_CHROME_REGION_CAPACITY]Win32_Chrome_Hit_Region,
	region_count: int,
	application_owned: bool,
}

Win32_Menu_Item_Binding :: struct {
	menu:       win.HMENU,
	position:   win.UINT,
	item:       ^Application_Menu_Item,
	top_menu:   ^Application_Menu,
	is_command: bool,
}

Win32_Menu_State :: struct {
	menu:       ^Native_Menu_Runtime,
	hwnd:       win.HWND,
	allocator:  mem.Allocator,
	root:       win.HMENU,
	labels:     []Win32_Menu_Label,
	commands:   [dynamic]Application_Command_ID,
	bindings:   [dynamic]Win32_Menu_Item_Binding,
	title:      Win32_Menu_Label,
	title_text: string,
	active:     bool,
	hovered:    int,
	active_menu: int,
	menu_mode: bool,
	chrome_height: f32,
	chrome_height_pixels: i32,
	pixels_per_unit: f32,
	maximized: bool,
	windows_11: bool,
	caption_button_bounds: win.RECT,
	caption_button_bounds_valid: bool,
	caption_controls: [3]Win32_Caption_Control,
	caption_hovered: int,
	caption_pressed: int,
	caption_masks: [4]Win32_Caption_Mask,
	caption_mask_dpi: u32,
	caption_mask_windows_11: bool,
	caption_mask_builds: u64,
	text_scale: f32,
	ellipsis_host_node: alicorn.Node_ID,
	high_contrast: bool,
	dpi:        u32,
	installed:  bool,
	menu_attached: bool,
	frame_extended: bool,
	frame_enabled: bool,
	chrome_geometry: Win32_Chrome_Geometry,
	chrome_metrics: Window_Chrome_Metrics,
	chrome_metrics_valid: bool,
	gesture_owner: Win32_Chrome_Gesture_Owner,
	text_renderer: ^Native_Text_Renderer,
	window_geometry: Win32_Window_Geometry_Recorder,
}

win32_menu_state :: proc(data: win.DWORD_PTR) -> ^Win32_Menu_State {
	return cast(^Win32_Menu_State)uintptr(data)
}

win32_menu_wide :: proc(state: ^Win32_Menu_State, value: string) -> []u16 {
	return win.utf8_to_utf16(value, state.allocator)
}

win32_menu_shortcut_label :: proc(shortcut: Application_Menu_Shortcut) -> string {
	if shortcut.key == 0 { return "" }
	modifiers := shortcut.modifiers
	primary, shift, alt, super := "", "", "", ""
	if Application_Menu_Modifier.Primary in modifiers { primary = "Ctrl+" }
	if Application_Menu_Modifier.Shift in modifiers { shift = "Shift+" }
	if Application_Menu_Modifier.Alt in modifiers { alt = "Alt+" }
	if Application_Menu_Modifier.Super in modifiers { super = "Win+" }
	return fmt.tprintf(
		"%s%s%s%s%c",
		primary,
		shift,
		alt,
		super,
		shortcut.key,
	)
}

win32_menu_build_items :: proc(state: ^Win32_Menu_State, menu: win.HMENU, items: []Application_Menu_Item) -> bool {
	for position in 0..<len(items) {
		item := &items[position]
		switch item.kind {
		case .Separator:
			if !win.AppendMenuW(menu, WIN32_MF_SEPARATOR, 0, nil) { return false }
		case .Submenu:
			popup := win.CreatePopupMenu()
			if popup == nil { return false }
			if !win32_menu_build_items(state, popup, item.items) {
				win.DestroyMenu(popup)
				return false
			}
			wide := win32_menu_wide(state, item.label)
			if wide == nil {
				win.DestroyMenu(popup)
				return false
			}
			flags := WIN32_MF_POPUP
			if !item.state.enabled { flags |= WIN32_MF_GRAYED }
			ok := win.AppendMenuW(menu, flags, win.UINT_PTR(uintptr(popup)), win.LPCWSTR(&wide[0]))
			delete(wide, state.allocator)
			if !ok {
				win.DestroyMenu(popup)
				return false
			}
			append(&state.bindings, Win32_Menu_Item_Binding{menu=menu, position=win.UINT(position), item=item})
		case .Command:
			if len(state.commands) >= 0x10000 { return false }
			native_id := win.UINT(len(state.commands))
			append(&state.commands, item.command)
			flags := win.UINT(0)
			if !item.state.enabled { flags |= WIN32_MF_GRAYED }
			if item.state.checked { flags |= WIN32_MF_CHECKED }
			label := item.label
			if item.shortcut.key != 0 {
				label = fmt.tprintf("%s\t%s", item.label, win32_menu_shortcut_label(item.shortcut))
			}
			wide := win32_menu_wide(state, label)
			if wide == nil { return false }
			ok := win.AppendMenuW(menu, flags, win.UINT_PTR(native_id), win.LPCWSTR(&wide[0]))
			delete(wide, state.allocator)
			if !ok { return false }
			append(&state.bindings, Win32_Menu_Item_Binding{menu=menu, position=win.UINT(position), item=item, is_command=true})
		}
	}
	return true
}

win32_menu_refresh_state :: proc(state: ^Win32_Menu_State) {
	if state == nil { return }
	for binding in state.bindings {
		flags := WIN32_MF_BYPOSITION
		item_state := binding.item.state if binding.item != nil else binding.top_menu.state
		if !item_state.enabled { flags |= WIN32_MF_GRAYED }
		_ = win.EnableMenuItem(binding.menu, binding.position, flags)
		if binding.is_command {
			check := WIN32_MF_BYPOSITION
			if item_state.checked { check |= WIN32_MF_CHECKED }
			_ = CheckMenuItem(binding.menu, binding.position, check)
		}
	}
}

win32_menu_point_from_lparam :: proc(value: win.LPARAM) -> win.POINT {
	packed := uintptr(value)
	return win.POINT{
		x=win.LONG(cast(i16)u16(packed & 0xffff)),
		y=win.LONG(cast(i16)u16((packed >> 16) & 0xffff)),
	}
}

win32_menu_label_at_window_point :: proc(state: ^Win32_Menu_State, x, y: i32) -> int {
	if state == nil { return -1 }
	for label, i in state.labels {
		if x >= label.bounds.left && x < label.bounds.right && y >= label.bounds.top && y < label.bounds.bottom {
			return i
		}
	}
	return -1
}

// Win32 hit testing and menu placement stay in client-relative physical pixels.
// In particular, fractional DPI must not round a one-pixel resize strip away.
win32_screen_point_to_client_pixels :: proc(screen_x, screen_y, client_origin_x, client_origin_y: i32) -> (i32, i32) {
	return screen_x-client_origin_x, screen_y-client_origin_y
}

win32_menu_screen_point_to_window :: proc(state: ^Win32_Menu_State, x, y: i32) -> (i32, i32, bool) {
	client_origin := win.POINT{}
	if !win.ClientToScreen(state.hwnd, &client_origin) { return 0, 0, false }
	client_x, client_y := win32_screen_point_to_client_pixels(x, y, i32(client_origin.x), i32(client_origin.y))
	return client_x, client_y, true
}

win32_menu_client_point_to_window :: proc(state: ^Win32_Menu_State, point: ^win.POINT) -> bool {
	if !win.ClientToScreen(state.hwnd, point) { return false }
	x, y, ok := win32_menu_screen_point_to_window(state, i32(point.x), i32(point.y))
	if !ok { return false }
	point.x = win.LONG(x)
	point.y = win.LONG(y)
	return true
}

win32_rect_contains :: proc(bounds: win.RECT, x, y: i32) -> bool {
	return x >= i32(bounds.left) && x < i32(bounds.right) &&
		y >= i32(bounds.top) && y < i32(bounds.bottom)
}

win32_integrated_frame_hit_test :: proc(
	x, y, width, height: i32,
	chrome_height, resize_x, resize_y: i32,
	maximized: bool,
	caption_controls: []Win32_Caption_Control,
	labels: []win.RECT,
	chrome_regions: []Win32_Chrome_Hit_Region = nil,
	application_owned_header := false,
	gesture_owner: Win32_Chrome_Gesture_Owner = .None,
) -> win.LRESULT {
	// The owner is fixed by the initial pointer-down. In particular, a tab drag
	// stays client input when it crosses blank titlebar space, and a window move
	// stays a caption gesture until release/cancellation.
	if gesture_owner == .Alicorn || gesture_owner == .Native_Menu {
		return win.LRESULT(win.HTCLIENT)
	}
	if gesture_owner == .Window { return win.LRESULT(win.HTCAPTION) }
	for control in caption_controls {
		if win32_rect_contains(control.bounds, x, y) {
			return control.hit_test
		}
	}
	if !maximized && resize_x > 0 && resize_y > 0 {
		left := x < resize_x
		right := x >= width-resize_x
		top := y < resize_y
		bottom := y >= height-resize_y
		if top && left { return win.LRESULT(win.HTTOPLEFT) }
		if top && right { return win.LRESULT(win.HTTOPRIGHT) }
		if bottom && left { return win.LRESULT(win.HTBOTTOMLEFT) }
		if bottom && right { return win.LRESULT(win.HTBOTTOMRIGHT) }
		if left { return win.LRESULT(win.HTLEFT) }
		if right { return win.LRESULT(win.HTRIGHT) }
		if top { return win.LRESULT(win.HTTOP) }
		if bottom { return win.LRESULT(win.HTBOTTOM) }
	}
	for label in labels {
		if win32_rect_contains(label, x, y) {
			return win.LRESULT(win.HTCLIENT)
		}
	}
	for region in chrome_regions {
		if !win32_rect_contains(region.bounds, x, y) { continue }
		if region.kind == .Interactive { return win.LRESULT(win.HTCLIENT) }
		return win.LRESULT(win.HTCAPTION)
	}
	if y >= 0 && y < chrome_height {
		return win.LRESULT(win.HTCLIENT) if application_owned_header else win.LRESULT(win.HTCAPTION)
	}
	return win.LRESULT(win.HTCLIENT)
}

win32_integrated_frame_resolve_hit_test :: proc(
	frame_result: win.LRESULT,
	dwm_handled: bool,
	dwm_result: win.LRESULT,
) -> win.LRESULT {
	// DWM owns standard caption-button hit testing. Alicorn owns every other
	// point because the frame is extended over the client area; allowing an
	// unrelated DWM non-client classification to replace this result can turn
	// editor pixels into caption or resize targets.
	if frame_result == win.LRESULT(win.HTMINBUTTON) || frame_result == win.LRESULT(win.HTMAXBUTTON) ||
		frame_result == win.LRESULT(win.HTCLOSE) {
		return frame_result
	}
	if dwm_handled && (dwm_result == win.LRESULT(win.HTMINBUTTON) || dwm_result == win.LRESULT(win.HTMAXBUTTON) ||
		dwm_result == win.LRESULT(win.HTCLOSE)) {
		return dwm_result
	}
	return frame_result
}

win32_integrated_frame_resolve_gesture_hit_test :: proc(
	frame_result: win.LRESULT,
	gesture_owner: Win32_Chrome_Gesture_Owner,
	dwm_handled: bool,
	dwm_result: win.LRESULT,
) -> win.LRESULT {
	if gesture_owner != .None { return frame_result }
	return win32_integrated_frame_resolve_hit_test(frame_result, dwm_handled, dwm_result)
}

win32_caption_control_rects :: proc(bounds: win.RECT, valid: bool) -> [3]win.RECT {
	if !valid || bounds.right <= bounds.left || bounds.bottom <= bounds.top { return {} }
	width := i32(bounds.right-bounds.left)
	first_width := width/3
	second_width := width/3
	third_width := width-first_width-second_width
	return [3]win.RECT{
		{left=bounds.left, top=bounds.top, right=bounds.left+win.LONG(first_width), bottom=bounds.bottom},
		{left=bounds.left+win.LONG(first_width), top=bounds.top, right=bounds.left+win.LONG(first_width+second_width), bottom=bounds.bottom},
		{left=bounds.right-win.LONG(third_width), top=bounds.top, right=bounds.right, bottom=bounds.bottom},
	}
}

win32_caption_control_at :: proc(x, y: i32, controls: []Win32_Caption_Control) -> int {
	for control, i in controls {
		if x >= i32(control.bounds.left) && x < i32(control.bounds.right) &&
			y >= i32(control.bounds.top) && y < i32(control.bounds.bottom) {
			return i
		}
	}
	return -1
}

win32_menu_update_caption_button_bounds :: proc(state: ^Win32_Menu_State, client_width_pixels: i32) -> bool {
	if state == nil || state.hwnd == nil { return false }
	state.caption_button_bounds_valid = false
	window_bounds: win.RECT
	if DwmGetWindowAttribute(state.hwnd, WIN32_DWMWA_CAPTION_BUTTON_BOUNDS, rawptr(&window_bounds), win.DWORD(size_of(window_bounds))) < 0 {
		return false
	}
	window_rect: win.RECT
	client_origin := win.POINT{}
	if !win.GetWindowRect(state.hwnd, &window_rect) || !win.ClientToScreen(state.hwnd, &client_origin) { return false }
	bounds := win32_caption_bounds_to_client_pixels(
		window_bounds,
		window_rect,
		i32(client_origin.x),
		i32(client_origin.y),
	)
	button_width := i32(bounds.right-bounds.left)
	if bounds.right <= bounds.left || bounds.bottom <= bounds.top ||
		button_width > i32(native_pixel_edge(320, f32(state.dpi)/96)) { return false }
	if bounds.left < 0 || bounds.left >= win.LONG(client_width_pixels) { return false }
	state.caption_button_bounds = bounds
	state.caption_button_bounds_valid = true
	return true
}

win32_menu_frame_hit_test :: proc(state: ^Win32_Menu_State, screen_x, screen_y: i32) -> win.LRESULT {
	if state == nil || !state.frame_enabled { return win.LRESULT(win.HTCLIENT) }
	client_rect: win.RECT
	if !win.GetClientRect(state.hwnd, &client_rect) { return win.LRESULT(win.HTCLIENT) }
	client_origin := win.POINT{}
	if !win.ClientToScreen(state.hwnd, &client_origin) { return win.LRESULT(win.HTCLIENT) }
	dpi := win.GetDpiForWindow(state.hwnd)
	if dpi == 0 { dpi = 96 }
	x, y := win32_screen_point_to_client_pixels(screen_x, screen_y, i32(client_origin.x), i32(client_origin.y))
	width := i32(client_rect.right-client_rect.left)
	height := i32(client_rect.bottom-client_rect.top)
	resize_x := i32(win.GetSystemMetricsForDpi(win.SM_CXSIZEFRAME, dpi)+win.GetSystemMetricsForDpi(win.SM_CXPADDEDBORDER, dpi))
	resize_y := i32(win.GetSystemMetricsForDpi(win.SM_CYSIZEFRAME, dpi)+win.GetSystemMetricsForDpi(win.SM_CXPADDEDBORDER, dpi))
	labels := make([]win.RECT, len(state.labels), allocator=context.temp_allocator)
	for label, i in state.labels { labels[i] = label.bounds }
	defer delete(labels, context.temp_allocator)
	return win32_integrated_frame_hit_test(x, y, width, height, state.chrome_height_pixels, resize_x, resize_y,
		state.maximized, state.caption_controls[:], labels,
		state.chrome_geometry.regions[:state.chrome_geometry.region_count],
		state.chrome_geometry.application_owned,
		state.gesture_owner)
}

win32_menu_caption_control_at_screen :: proc(state: ^Win32_Menu_State, screen_x, screen_y: i32) -> int {
	if state == nil { return -1 }
	x, y, ok := win32_menu_screen_point_to_window(state, screen_x, screen_y)
	if !ok { return -1 }
	return win32_caption_control_at(x, y, state.caption_controls[:])
}

win32_menu_update_caption_pointer :: proc(state: ^Win32_Menu_State, message: win.UINT, lparam: win.LPARAM) {
	if state == nil { return }
	if message == win.WM_NCMOUSELEAVE {
		if state.caption_hovered >= 0 {
			state.caption_hovered = -1
			native_menu_request_chrome_redraw(state.menu)
		}
		return
	}
	point := win32_menu_point_from_lparam(lparam)
	index := win32_menu_caption_control_at_screen(state, i32(point.x), i32(point.y))
	if message == win.WM_NCMOUSEMOVE {
		if state.caption_hovered != index {
			state.caption_hovered = index
			native_menu_request_chrome_redraw(state.menu)
		}
		if index >= 0 {
			track := win.TRACKMOUSEEVENT{
				cbSize=win.DWORD(size_of(win.TRACKMOUSEEVENT)),
				dwFlags=win.TME_LEAVE | win.TME_NONCLIENT,
				hwndTrack=state.hwnd,
			}
			_ = win.TrackMouseEvent(&track)
		}
	} else if message == win.WM_NCLBUTTONDOWN {
		if state.caption_pressed != index {
			state.caption_pressed = index
			native_menu_request_chrome_redraw(state.menu)
		}
	} else if message == win.WM_NCLBUTTONUP {
		if state.caption_pressed >= 0 {
			state.caption_pressed = -1
			native_menu_request_chrome_redraw(state.menu)
		}
	}
}

win32_menu_layout_labels :: proc(state: ^Win32_Menu_State) {
	if state == nil || state.menu == nil || state.menu.application == nil || !state.frame_enabled { return }
	state.dpi = win.GetDpiForWindow(state.hwnd)
	if state.dpi == 0 { state.dpi = 96 }
	scale := f32(state.dpi)/96
	state.pixels_per_unit = sdl3.GetWindowPixelDensity(state.menu.window)
	if state.pixels_per_unit <= 0 { state.pixels_per_unit = 1 }
	state.maximized = win.IsZoomed(state.hwnd) != false
	client: win.RECT
	if !win.GetClientRect(state.hwnd, &client) { return }
	client_width := i32(client.right-client.left)
	caption_h := i32(win.GetSystemMetricsForDpi(win.SM_CYCAPTION, state.dpi))
	frame_y := i32(win.GetSystemMetricsForDpi(win.SM_CYSIZEFRAME, state.dpi)+win.GetSystemMetricsForDpi(win.SM_CXPADDEDBORDER, state.dpi))
	state.chrome_height_pixels = max(caption_h+frame_y, i32(native_pixel_edge(32, scale)))
	state.chrome_height = f32(state.chrome_height_pixels)/state.pixels_per_unit
	state.menu.content_inset_top = state.chrome_height if !win32_menu_application_owns_chrome(state) else 0
	_ = win32_menu_update_caption_button_bounds(state, client_width)
	state.caption_controls = win32_caption_layout_controls(state.caption_button_bounds, state.caption_button_bounds_valid,
		client_width, state.chrome_height_pixels, state.dpi, state.maximized)
	win32_menu_layout_label_bounds(state)
}

win32_menu_layout_label_bounds :: proc(state: ^Win32_Menu_State) {
	scale := f32(state.dpi if state.dpi != 0 else 96)/96
	usable_right := max(i32(state.caption_controls[0].bounds.left)-i32(native_pixel_edge(8, scale)), 0)
	left := i32(native_pixel_edge(8, scale))
	if title_run := native_text_host_run(state.text_renderer, state.title.host_node);
	   title_run != nil && state.title_text != "" {
		title_width := i32(native_pixel_edge(title_run.width, state.pixels_per_unit)+native_pixel_edge(16, scale))
		state.title.bounds = win.RECT{left=win.LONG(min(left, usable_right)), top=0, right=win.LONG(min(left+title_width, usable_right)), bottom=win.LONG(state.chrome_height_pixels)}
		left += title_width+i32(native_pixel_edge(8, scale))
	} else {
		state.title.bounds = win.RECT{}
	}
	for i in 0..<len(state.labels) {
		label := &state.labels[i]
		label.bounds = win.RECT{}
		if left >= usable_right { continue }
		run := native_text_host_run(state.text_renderer, label.host_node)
		if run == nil { continue }
		width := i32(native_pixel_edge(run.width, state.pixels_per_unit)+native_pixel_edge(24, scale))
		label.bounds = win.RECT{left=win.LONG(left), top=0, right=win.LONG(min(left+width, usable_right)), bottom=win.LONG(state.chrome_height_pixels)}
		left += width
	}
}

win32_menu_application_owns_chrome :: proc(state: ^Win32_Menu_State) -> bool {
	return state != nil && state.menu != nil && state.menu.application != nil &&
		state.menu.application.window_chrome_layout != nil
}

win32_rect_intersection :: proc(a, b: win.RECT) -> win.RECT {
	left := max(a.left, b.left)
	top := max(a.top, b.top)
	right := min(a.right, b.right)
	bottom := min(a.bottom, b.bottom)
	return win.RECT{left, top, max(right, left), max(bottom, top)}
}

win32_window_chrome_metrics_equal :: proc(a, b: Window_Chrome_Metrics) -> bool {
	if a.header != b.header || a.native_control_count != b.native_control_count ||
		a.content_start_x != b.content_start_x || a.content_end_x != b.content_end_x ||
		a.display_scale != b.display_scale || a.fullscreen != b.fullscreen { return false }
	for i in 0..<min(max(a.native_control_count, 0), len(a.native_controls)) {
		if a.native_controls[i] != b.native_controls[i] { return false }
	}
	return true
}

// Publish the native menu/caption geometry in the same logical coordinate
// space as the retained tree. Native menu labels and caption buttons remain
// host-owned exclusions; the application may place tabs only between them.
win32_menu_sync_window_chrome_metrics :: proc(
	state: ^Win32_Menu_State,
	rt: ^alicorn.Runtime,
	request_invalidation := true,
) -> bool {
	if state == nil || state.menu == nil || state.menu.application == nil || rt == nil ||
		!win32_menu_application_owns_chrome(state) || state.menu.application.window_chrome_metrics == nil { return false }
	client: win.RECT
	if !win.GetClientRect(state.hwnd, &client) { return false }
	client_width := i32(client.right-client.left)
	client_height := i32(client.bottom-client.top)
	density := state.pixels_per_unit if state.pixels_per_unit > 0 else 1
	content_start_pixels := i32(native_pixel_edge(8, f32(state.dpi if state.dpi != 0 else 96)/96))
	for label in state.labels {
		if label.bounds.right > label.bounds.left {
			content_start_pixels = max(content_start_pixels, i32(label.bounds.right)+
				i32(native_pixel_edge(8, f32(state.dpi if state.dpi != 0 else 96)/96)))
		}
	}
	content_end_pixels := max(i32(state.caption_controls[0].bounds.left)-
		i32(native_pixel_edge(8, f32(state.dpi if state.dpi != 0 else 96)/96)), 0)
	content_start_pixels = min(content_start_pixels, content_end_pixels)
	next := Window_Chrome_Metrics{
		header=alicorn.Rect{0, 0, f32(client_width)/density, min(f32(state.chrome_height_pixels)/density, f32(client_height)/density)},
		content_start_x=f32(content_start_pixels)/density,
		content_end_x=f32(content_end_pixels)/density,
		display_scale=sdl3.GetWindowDisplayScale(state.menu.window),
		fullscreen=(sdl3.GetWindowFlags(state.menu.window) & sdl3.WindowFlags{.FULLSCREEN}) != sdl3.WindowFlags{},
	}
	for control in state.caption_controls {
		if control.bounds.right <= control.bounds.left || control.bounds.bottom <= control.bounds.top { continue }
		if next.native_control_count >= len(next.native_controls) { break }
		next.native_controls[next.native_control_count] = win32_chrome_rect_to_window(control.bounds, density)
		next.native_control_count += 1
	}
	changed := !state.chrome_metrics_valid || !win32_window_chrome_metrics_equal(state.chrome_metrics, next)
	state.chrome_metrics = next
	state.chrome_metrics_valid = true
	if !changed { return true }
	state.menu.application.window_chrome_metrics(state.menu.application.state, rt, next)
	if request_invalidation { alicorn.invalidate_root(rt, "measured Windows titlebar geometry changed") }
	return true
}

// The native hit-test adapter consumes only finalized retained bounds, copied
// into physical client pixels once. This runs after app descriptions/layout,
// not during hit testing, so pointer callbacks do no tree traversal.
native_menu_sync_chrome_layout :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil || menu.runtime == nil || menu.application == nil { return }
	state := cast(^Win32_Menu_State)menu.platform_data
	if !state.frame_enabled || !win32_menu_application_owns_chrome(state) { return }
	geometry := Win32_Chrome_Geometry{application_owned=true}
	layout := menu.application.window_chrome_layout(menu.application.state, menu.runtime)
	header, header_ok := alicorn.node_info(menu.runtime, layout.header)
	client: win.RECT
	if !win.GetClientRect(state.hwnd, &client) { return }
	native_header := win.RECT{left=0, top=0,
		right=client.right,
		bottom=win.LONG(min(state.chrome_height_pixels, i32(client.bottom)))}
	if header_ok && header.active {
		x0, y0, x1, y1 := logical_to_pixel_bounds(header.bounds, state.pixels_per_unit, state.pixels_per_unit)
		retained_header := win.RECT{win.LONG(x0), win.LONG(y0), win.LONG(x1), win.LONG(y1)}
		geometry.header = win32_rect_intersection(retained_header, native_header)
	}
	if geometry.header.right <= geometry.header.left || geometry.header.bottom <= geometry.header.top {
		state.chrome_geometry = geometry
		return
	}
	for region in layout.regions {
		if region.node == 0 || geometry.region_count >= len(geometry.regions) { continue }
		node, ok := alicorn.node_info(menu.runtime, region.node)
		if !ok || !node.active { continue }
		x0, y0, x1, y1 := logical_to_pixel_bounds(node.bounds, state.pixels_per_unit, state.pixels_per_unit)
		bounds := win32_rect_intersection(
			win.RECT{win.LONG(x0), win.LONG(y0), win.LONG(x1), win.LONG(y1)},
			geometry.header,
		)
		if bounds.right <= bounds.left || bounds.bottom <= bounds.top { continue }
		geometry.regions[geometry.region_count] = Win32_Chrome_Hit_Region{bounds, region.kind}
		geometry.region_count += 1
	}
	state.chrome_geometry = geometry
}

win32_menu_extend_frame :: proc(state: ^Win32_Menu_State) -> bool {
	if state == nil || state.hwnd == nil || !state.frame_enabled { return false }
	// A negative top margin extends DWM's frame across the complete client area.
	margins := win.MARGINS{0, 0, -1, 0}
	if DwmExtendFrameIntoClientArea(state.hwnd, &margins) < 0 { return false }
	state.frame_extended = true
	return true
}

win32_menu_frame_changed :: proc(state: ^Win32_Menu_State) -> bool {
	if state == nil || state.hwnd == nil { return false }
	flags := win.UINT(win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOZORDER | win.SWP_NOACTIVATE | win.SWP_FRAMECHANGED)
	if !win.SetWindowPos(state.hwnd, nil, 0, 0, 0, 0, flags) { return false }
	return true
}

win32_menu_reapply_frame :: proc(state: ^Win32_Menu_State) -> bool {
	if state == nil || !state.frame_enabled { return true }
	if !win32_menu_extend_frame(state) { return false }
	if !win32_menu_frame_changed(state) { return false }
	win32_menu_layout_labels(state)
	native_menu_request_chrome_redraw(state.menu)
	return true
}

win32_menu_disable_frame :: proc(state: ^Win32_Menu_State) {
	if state == nil { return }
	state.frame_enabled = false
	state.frame_extended = false
	state.chrome_height = 0
	if state.menu != nil {
		state.menu.content_inset_top = 0
		native_menu_request_chrome_redraw(state.menu)
	}
	// Stop extending DWM and force Windows to recalculate the standard frame
	// after the subclass stops handling WM_NCCALCSIZE.
	if state.hwnd != nil {
		margins := win.MARGINS{}
		_ = DwmExtendFrameIntoClientArea(state.hwnd, &margins)
		_ = win32_menu_frame_changed(state)
	}
}

native_menu_prepare_gpu :: proc(menu: ^Native_Menu_Runtime, rt: ^alicorn.Runtime, renderer: ^Native_Text_Renderer) -> bool {
	if menu == nil { return false }
	// A system-decorated application may intentionally have no menus. The
	// platform preparation already accepted that case, so GPU chrome setup is a
	// no-op rather than a startup failure.
	if menu.platform_data == nil { return menu.application != nil && len(menu.application.menus) == 0 && menu.application.window_decorations == .System }
	if rt == nil || renderer == nil { return false }
	state := cast(^Win32_Menu_State)menu.platform_data
	if !state.frame_enabled { return true }
	state.text_renderer = renderer
	title := menu.application.title
	if title == "" { title = "Alicorn application" }
	if menu.application.window_chrome_layout != nil { title = "" }
	state.title_text = title
	state.title.host_node = NATIVE_MENU_HOST_NODE_BASE
	for &label, i in state.labels {
		label.host_node = NATIVE_MENU_HOST_NODE_BASE+alicorn.Node_ID(i+1)
	}
	state.ellipsis_host_node = NATIVE_MENU_HOST_NODE_BASE+alicorn.Node_ID(len(state.labels)+2)
	if !win32_menu_refresh_text(state, rt) || !win32_caption_sync_masks(state) { return false }
	win32_menu_layout_labels(state)
	if win32_menu_application_owns_chrome(state) {
		if !win32_menu_sync_window_chrome_metrics(state, rt, request_invalidation=false) { return false }
	}
	native_menu_request_chrome_redraw(menu)
	return true
}

win32_menu_refresh_text :: proc(state: ^Win32_Menu_State, rt: ^alicorn.Runtime) -> bool {
	if state == nil || rt == nil || state.text_renderer == nil || state.menu == nil || state.menu.application == nil ||
		state.title.host_node == 0 || state.ellipsis_host_node == 0 || len(state.labels) != len(state.menu.application.menus) { return false }
	for label in state.labels { if label.host_node == 0 { return false } }
	scale := (f32(state.dpi if state.dpi != 0 else 96)/96)/(state.pixels_per_unit if state.pixels_per_unit > 0 else 1)
	if state.text_scale == scale { return true }
	count := len(state.labels)+2
	runs := make([]alicorn.Text_Run, count, allocator=rt.scratch_allocator)
	defer delete(runs, rt.scratch_allocator)
	for i in 0..<count {
		text := state.title_text
		if i == count-1 { text = "…" }
		else if i > 0 { text = state.menu.application.menus[i-1].label }
		run, ok := alicorn.text_run_build(&rt.text_engine, text, 14*scale,
			allocator=rt.persistent_allocator, scratch_allocator=rt.scratch_allocator)
		if !ok {
			for j in 0..<i { alicorn.text_run_destroy(&runs[j]) }
			return false
		}
		runs[i] = run
	}
	for run, i in runs {
		id := state.title.host_node
		if i == count-1 { id = state.ellipsis_host_node }
		else if i > 0 { id = state.labels[i-1].host_node }
		if !native_text_set_host_run(state.text_renderer, id, run) {
			for j in i..<count { alicorn.text_run_destroy(&runs[j]) }
			return false
		}
	}
	state.text_scale = scale
	return true
}

win32_color_ref :: proc(value: win.COLORREF) -> alicorn.Color {
	color := u32(value)
	return alicorn.Color{f32(color&0xff)/255, f32((color>>8)&0xff)/255, f32((color>>16)&0xff)/255, 1}
}

win32_color_rgb :: proc(red, green, blue: u8) -> alicorn.Color {
	return alicorn.Color{f32(red)/255, f32(green)/255, f32(blue)/255, 1}
}

win32_color_mix :: proc(background, foreground: alicorn.Color, amount: f32) -> alicorn.Color {
	mix := clamp(amount, 0, 1)
	return alicorn.Color{
		background.r+(foreground.r-background.r)*mix,
		background.g+(foreground.g-background.g)*mix,
		background.b+(foreground.b-background.b)*mix,
		background.a+(foreground.a-background.a)*mix,
	}
}

win32_menu_feedback_colors :: proc(background, foreground: alicorn.Color) -> (hover, open, pressed: alicorn.Color) {
	// Derive the interactive surfaces from the actual chrome colors. Legacy
	// button/menu system colors can collapse to the same value on modern themes.
	hover = win32_color_mix(background, foreground, WIN32_MENU_HOVER_MIX)
	open = win32_color_mix(background, foreground, WIN32_MENU_OPEN_MIX)
	pressed = win32_color_mix(background, foreground, WIN32_MENU_PRESSED_MIX)
	return
}

win32_menu_chrome_colors :: proc(state: ^Win32_Menu_State) -> (background, foreground: alicorn.Color) {
	if state != nil && !state.high_contrast && state.menu != nil && state.menu.chrome_appearance.defined {
		background = state.menu.chrome_appearance.background
		foreground = state.menu.chrome_appearance.foreground
		if !state.active {
			// Keep inactive chrome legible while softly reducing its emphasis.
			foreground = win32_color_mix(background, foreground, 0.72)
		}
		return
	}
	background = win32_color_ref(win.GetSysColor(win.COLOR_MENU))
	foreground_index := i32(win.COLOR_MENUTEXT)
	if !state.active && !state.high_contrast { foreground_index = i32(win.COLOR_GRAYTEXT) }
	foreground = win32_color_ref(win.GetSysColor(foreground_index))
	return
}

win32_menu_high_contrast_selection_colors :: proc() -> (background, foreground: alicorn.Color) {
	return win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHT)),
		win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHTTEXT))
}

native_menu_overlay_commands :: proc(menu: ^Native_Menu_Runtime, width, height: f32, allocator: mem.Allocator) -> []alicorn.Paint_Command {
	if menu == nil || menu.application == nil || menu.application.window_decorations != .Integrated_Title_Bar || menu.platform_data == nil { return nil }
	state := cast(^Win32_Menu_State)menu.platform_data
	if !state.frame_enabled || state.chrome_height <= 0 { return nil }
	if !win32_caption_sync_masks(state) { fail("native caption masks could not be built") }
	if state.text_renderer != nil && menu.runtime != nil {
		previous_scale := state.text_scale
		if !win32_menu_refresh_text(state, menu.runtime) { fail("native caption text scale could not be refreshed") }
		if previous_scale != state.text_scale { win32_menu_layout_labels(state) }
	}
	commands := make([dynamic]alicorn.Paint_Command, 0, len(state.labels)*2+96, allocator=allocator)
	background, foreground := win32_menu_chrome_colors(state)
	hover_background, open_background, pressed_background := win32_menu_feedback_colors(background, foreground)
	full := alicorn.Rect{0, 0, width, min(state.chrome_height, height)}
	application_chrome := win32_menu_application_owns_chrome(state)
	if !application_chrome {
		append(&commands, alicorn.paint_surface_command(NATIVE_MENU_HOST_SOLID_NODE, full, full, background))
	}
	active_index := state.hovered
	if state.menu_mode && state.active_menu >= 0 { active_index = state.active_menu }
	selection_background, selection_foreground := alicorn.Color{}, alicorn.Color{}
	if state.high_contrast {
		selection_background, selection_foreground = win32_menu_high_contrast_selection_colors()
	}
	if active_index >= 0 && active_index < len(state.labels) {
		bounds := state.labels[active_index].bounds
		if bounds.right > bounds.left {
			label_background := hover_background
			if state.menu_mode && state.active_menu == active_index { label_background = open_background }
			if state.high_contrast {
				label_background = selection_background
			}
			append(&commands, alicorn.paint_surface_command(
				NATIVE_MENU_HOST_SOLID_NODE+1,
				win32_chrome_rect_to_window(bounds, state.pixels_per_unit),
				full, label_background,
			))
		}
	}
	for label in state.labels {
		if label.direct_menu == nil || !label.direct_menu.state.checked || label.bounds.right <= label.bounds.left { continue }
		selected_background := open_background
		if state.high_contrast { selected_background = selection_background }
		append(&commands, alicorn.paint_surface_command(
			NATIVE_MENU_HOST_SOLID_NODE+1,
			win32_chrome_rect_to_window(label.bounds, state.pixels_per_unit),
			full, selected_background,
		))
	}
	maximized := state.maximized
	for control, index in state.caption_controls {
		if control.bounds.right <= control.bounds.left || control.bounds.bottom <= control.bounds.top { continue }
		button_foreground := foreground
		if index == state.caption_hovered {
			hover_color := hover_background
			if index == 2 && !state.high_contrast {
				hover_color = win32_color_rgb(232, 17, 35)
				button_foreground = win32_color_rgb(255, 255, 255)
				if index == state.caption_pressed { hover_color = win32_color_mix(background, hover_color, 0.60) }
			} else if state.high_contrast {
				hover_color = selection_background
				button_foreground = selection_foreground
			} else if index == state.caption_pressed {
				hover_color = pressed_background
			}
			append(&commands, alicorn.paint_surface_command(
				NATIVE_MENU_HOST_SOLID_NODE+2+alicorn.Node_ID(index),
				win32_chrome_rect_to_window(control.hover_bounds, state.pixels_per_unit),
				full, hover_color,
			))
		}
		win32_caption_append_glyph(&commands, state, index, button_foreground, full, maximized)
	}
	if !application_chrome { win32_menu_append_text(&commands, state, state.title, 8, foreground, ellipsis=true) }
	for label, i in state.labels {
		run := native_text_host_run(state.text_renderer, label.host_node)
		if run == nil || label.bounds.right <= label.bounds.left { continue }
		label_color := foreground
		if label.direct_menu != nil {
			if !label.direct_menu.state.enabled {
				if state.high_contrast { label_color = win32_color_ref(win.GetSysColor(win.COLOR_GRAYTEXT)) }
				else { label_color = win32_color_mix(background, foreground, 0.48) }
			} else if i == active_index && state.high_contrast || (label.direct_menu.state.checked && state.high_contrast) {
				label_color = selection_foreground
			}
		} else if i == active_index && state.high_contrast { label_color = selection_foreground }
		win32_menu_append_text(&commands, state, label, 12, label_color)
	}
	return commands[:]
}

win32_menu_append_text :: proc(
	commands: ^[dynamic]alicorn.Paint_Command, state: ^Win32_Menu_State,
	label: Win32_Menu_Label, padding: f32, color: alicorn.Color, ellipsis := false,
) {
	run := native_text_host_run(state.text_renderer, label.host_node)
	if run == nil || label.bounds.right <= label.bounds.left { return }
	bounds := label.bounds
	inset := win.LONG(native_pixel_edge(padding, f32(state.dpi if state.dpi != 0 else 96)/96))
	bounds.left = min(bounds.left+inset, bounds.right)
	bounds.right = max(bounds.right-inset, bounds.left)
	clip := win32_chrome_rect_to_window(bounds, state.pixels_per_unit)
	if clip.w <= 0 { return }
	y := clip.y+max((clip.h-run.height)/2, 0)
	text_clip := clip
	if ellipsis && run.width > clip.w {
		if mark := native_text_host_run(state.text_renderer, state.ellipsis_host_node); mark != nil {
			text_clip.w = max(clip.w-mark.width, 0)
			append(commands, alicorn.paint_text_command(state.ellipsis_host_node,
				alicorn.Rect{clip.x+text_clip.w, y, mark.width, mark.height}, clip,
				native_text_host_handle(state.text_renderer, state.ellipsis_host_node), color))
		}
	}
	if text_clip.w > 0 {
		append(commands, alicorn.paint_text_command(label.host_node,
			alicorn.Rect{clip.x, y, run.width, run.height}, text_clip,
			native_text_host_handle(state.text_renderer, label.host_node), color))
	}
}

win32_menu_dispatch_native_id :: proc(state: ^Win32_Menu_State, native_id: u32) {
	if state == nil { return }
	if state.menu != nil && native_id != 0 && int(native_id) < len(state.commands) {
		state.menu.pending_command = state.commands[native_id]
		state.menu.has_pending = true
	}
	win32_menu_exit_mode(state, -1)
}

win32_menu_exit_mode_state :: proc(state: ^Win32_Menu_State, hovered_index: int) {
	if state == nil { return }
	state.menu_mode = false
	state.active_menu = -1
	state.hovered = hovered_index
}

win32_menu_exit_mode :: proc(state: ^Win32_Menu_State, hovered_index: int) {
	if state == nil { return }
	win32_menu_exit_mode_state(state, hovered_index)
	if state.menu != nil { native_menu_request_chrome_redraw(state.menu) }
}

win32_menu_hovered_label_at_cursor :: proc(state: ^Win32_Menu_State) -> int {
	if state == nil { return -1 }
	point := win.POINT{}
	if !win.GetCursorPos(&point) { return -1 }
	x, y, ok := win32_menu_screen_point_to_window(state, i32(point.x), i32(point.y))
	if !ok { return -1 }
	return win32_menu_label_at_window_point(state, x, y)
}

win32_menu_finish_popup :: proc(state: ^Win32_Menu_State, native_id: u32, hovered_index: int) {
	if state == nil { return }
	if native_id == 0 {
		win32_menu_exit_mode(state, hovered_index)
	} else {
		win32_menu_dispatch_native_id(state, native_id)
	}
}

win32_menu_open_popup :: proc(state: ^Win32_Menu_State, index: int) {
	if state == nil || index < 0 || index >= len(state.labels) { return }
	label := state.labels[index]
	if label.popup == nil { return }
	win32_menu_refresh_state(state)
	client_origin := win.POINT{}
	if !win.ClientToScreen(state.hwnd, &client_origin) { return }
	flags := win.UINT(win.TPM_RETURNCMD | win.TPM_NONOTIFY | win.TPM_LEFTALIGN | win.TPM_TOPALIGN)
	command := win.TrackPopupMenu(label.popup, flags,
		win.INT(client_origin.x+label.bounds.left),
		win.INT(client_origin.y+label.bounds.bottom),
		0, state.hwnd, nil)
	hovered_index := -1
	if command == 0 { hovered_index = win32_menu_hovered_label_at_cursor(state) }
	win32_menu_finish_popup(state, u32(command), hovered_index)
	_ = win.PostMessageW(state.hwnd, win.WM_NULL, 0, 0)
}

win32_menu_label_activate :: proc(state: ^Win32_Menu_State, index: int) {
	if state == nil || state.menu == nil || state.menu.application == nil || index < 0 || index >= len(state.labels) { return }
	label := &state.labels[index]
	if label.direct_menu != nil {
		if label.direct_menu.state.enabled {
			// Subclass callbacks enqueue intent; the host dispatches it after
			// the event pump returns to its normal application safe point.
			state.menu.pending_command = label.direct_menu.command
			state.menu.has_pending = true
		}
		win32_menu_exit_mode(state, -1)
		return
	}
	state.active_menu = index
	win32_menu_open_popup(state, index)
}

native_menu_handle_keydown :: proc(menu: ^Native_Menu_Runtime, keycode: int, modifiers: sdl3.Keymod) -> bool {
	if menu == nil || menu.application == nil || menu.application.window_decorations != .Integrated_Title_Bar || menu.platform_data == nil { return false }
	state := cast(^Win32_Menu_State)menu.platform_data
	alt := native_text_modifier(modifiers, sdl3.KMOD_ALT)
	control := native_text_modifier(modifiers, sdl3.KMOD_CTRL)
	super := native_text_modifier(modifiers, sdl3.KMOD_GUI)
	if alt && keycode == int(sdl3.K_SPACE) { return false }
	if (keycode == int(sdl3.K_LALT) || keycode == int(sdl3.K_RALT)) && !control && !super {
		if len(state.labels) == 0 { return false }
		state.menu_mode = true
		state.active_menu = 0
		state.hovered = -1
		native_menu_request_chrome_redraw(menu)
		return true
	}
	if alt && !control && !super {
		upper := keycode
		if upper >= 'a' && upper <= 'z' { upper -= ('a' - 'A') }
		for description, i in menu.application.menus {
			if len(description.label) > 0 {
				first := int(description.label[0])
				if first >= 'a' && first <= 'z' { first -= ('a' - 'A') }
				if first == upper {
					state.menu_mode = true
					state.active_menu = i
					state.hovered = -1
					win32_menu_label_activate(state, i)
					return true
				}
			}
		}
	}
	if !state.menu_mode { return false }
	if keycode == int(sdl3.K_ESCAPE) {
		win32_menu_exit_mode(state, win32_menu_hovered_label_at_cursor(state))
		return true
	}
	if keycode == int(sdl3.K_LEFT) || keycode == int(sdl3.K_RIGHT) {
		count := len(state.labels)
		if count == 0 { return true }
		delta := 1
		if keycode == int(sdl3.K_LEFT) { delta = count-1 }
		state.active_menu = (state.active_menu+delta)%count
		native_menu_request_chrome_redraw(menu)
		return true
	}
	if !alt && !control && !super {
		upper := keycode
		if upper >= 'a' && upper <= 'z' { upper -= ('a' - 'A') }
		for description, i in menu.application.menus {
			if len(description.label) > 0 {
				first := int(description.label[0])
				if first >= 'a' && first <= 'z' { first -= ('a' - 'A') }
				if first == upper {
					state.active_menu = i
					state.hovered = -1
					win32_menu_label_activate(state, i)
					return true
				}
			}
		}
	}
	if keycode == int(sdl3.K_RETURN) || keycode == int(sdl3.K_KP_ENTER) || keycode == int(sdl3.K_SPACE) {
		win32_menu_label_activate(state, state.active_menu)
		return true
	}
	return false
}

win32_menu_cancel_app_pointer :: proc(state: ^Win32_Menu_State) {
	if state == nil || state.menu == nil || state.menu.runtime == nil { return }
	menu := state.menu
	rt := menu.runtime
	captured := rt.captured_node
	drag_was_active := alicorn.drag_is_active(rt)
	if captured == 0 && !drag_was_active { return }
	cancel_cause := alicorn.pointer_cause_begin(rt, .Cancel)
	_ = alicorn.cancel_pointer_capture(rt)
	if drag_was_active {
		// cancel_pointer_capture may already reset the drag phase while queuing
		// its terminal event. Only cancel explicitly if capture cancellation
		// left the drag active, but always deliver the terminal event below.
		if alicorn.drag_is_active(rt) {
			_ = alicorn.drag_cancel(rt)
		}
		_ = native_dispatch_drag_event(menu.application, rt)
	}
	if menu.application != nil && menu.application.on_pointer != nil {
		cancelled := alicorn.Pointer_Event{kind=.Cancel}
		if key, ok := alicorn.node_identity_key(rt, captured); ok { cancelled.target_key = key }
		menu.application.on_pointer(menu.application.state, rt, cancelled, captured)
	}
	alicorn.cause_end(rt, cancel_cause)
}

win32_menu_set_active :: proc(state: ^Win32_Menu_State, active: bool) -> bool {
	if state == nil || state.active == active { return false }
	state.active = active
	state.caption_hovered = -1
	state.caption_pressed = -1
	native_menu_request_chrome_redraw(state.menu)
	return true
}

win32_menu_preserve_topmost_promotion_position :: proc(state: ^Win32_Menu_State, position: ^win.WINDOWPOS) -> bool {
	if state == nil || !state.frame_enabled || position == nil { return false }
	required := win.UINT(win.SWP_NOSIZE | win.SWP_NOACTIVATE)
	excluded := win.UINT(win.SWP_NOMOVE | win.SWP_NOZORDER | win.SWP_FRAMECHANGED)
	if (position.flags & required) != required || (position.flags & excluded) != 0 { return false }
	if state.menu == nil || state.menu.window == nil { return false }
	topmost := (sdl3.GetWindowFlags(state.menu.window) & sdl3.WindowFlags{.ALWAYS_ON_TOP}) != sdl3.WindowFlags{}
	if !topmost { return false }
	// Windows may replace HWND_TOPMOST with an actual insertion HWND before
	// sending WINDOWPOSCHANGING, so identify SDL's standard-frame adjustment
	// from the requested coordinates rather than the normalized z-order target.
	standard_frame: win.RECT
	style := cast(win.DWORD)win.GetWindowLongW(state.hwnd, win.GWL_STYLE)
	ex_style := cast(win.DWORD)win.GetWindowLongW(state.hwnd, win.GWL_EXSTYLE)
	if !win.AdjustWindowRectExForDpi(&standard_frame, style, win.BOOL(state.menu_attached), ex_style, win.GetDpiForWindow(state.hwnd)) { return false }
	if standard_frame.left == 0 && standard_frame.top == 0 { return false }
	x, y: c.int
	if !sdl3.GetWindowPosition(state.menu.window, &x, &y) ||
		position.x != x+standard_frame.left || position.y != y+standard_frame.top { return false }
	// SDL's WIN_OnWindowEnter promotes topmost windows with an adjusted position
	// and no SWP_NOMOVE. Its standard-frame adjustment disagrees with our full
	// client WM_NCCALCSIZE contract. This is a z-order promotion: preserve the
	// HWND rectangle before Windows applies it. Explicit moves keep SWP_NOZORDER
	// and resize/DPI/frame changes do not satisfy this predicate.
	position.flags |= win.SWP_NOMOVE
	state.window_geometry.topmost_promotions_preserved += 1
	return true
}

win32_menu_subclass :: proc "system" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, subclass_id: win.UINT_PTR, ref_data: win.DWORD_PTR) -> win.LRESULT {
	context = runtime.default_context()
	state := win32_menu_state(ref_data)
	if state == nil { return win.DefSubclassProc(hwnd, message, wparam, lparam) }
	state.hwnd = hwnd
	integrated := state.frame_enabled
	if message == win.WM_CANCELMODE || message == win.WM_CAPTURECHANGED || message == win.WM_KILLFOCUS {
		state.gesture_owner = .None
	} else if message == win.WM_LBUTTONUP &&
		(state.gesture_owner == .Alicorn || state.gesture_owner == .Native_Menu) {
		state.gesture_owner = .None
	} else if message == win.WM_NCLBUTTONUP && state.gesture_owner == .Window {
		state.gesture_owner = .None
	} else if (message == win.WM_NCLBUTTONDOWN || message == win.WM_NCLBUTTONDBLCLK) &&
		wparam == win.WPARAM(win.HTCAPTION) {
		state.gesture_owner = .Window
	}
	if integrated && message == win.WM_WINDOWPOSCHANGING {
		position := cast(^win.WINDOWPOS)uintptr(lparam)
		requested_flags := position.flags if position != nil else win.UINT(0)
		preserved := win32_menu_preserve_topmost_promotion_position(state, position)
		win32_window_geometry_record(state, message, position, requested_flags, preserved)
	} else if integrated && (message == win.WM_MOUSELEAVE ||
		(message == win.WM_MOUSEMOVE && sdl3.GetMouseFocus() != state.menu.window)) {
		win32_window_geometry_record(state, message, nil, 0, false)
	}

	if integrated && message == win.WM_NCCALCSIZE {
		// Keep the outer window and client coordinates aligned. On maximize,
		// preserve the monitor work area so the client never covers the taskbar.
		if win.IsZoomed(hwnd) != false {
			monitor := win.MonitorFromWindow(hwnd, .MONITOR_DEFAULTTONEAREST)
			monitor_info := win.MONITORINFO{cbSize=win.DWORD(size_of(win.MONITORINFO))}
			if monitor != nil && win.GetMonitorInfoW(monitor, &monitor_info) {
				if wparam != 0 {
					params := cast(^win.NCCALCSIZE_PARAMS)uintptr(lparam)
					if params != nil { params.rgrc[0] = monitor_info.rcWork }
				} else {
					rect := cast(^win.RECT)uintptr(lparam)
					if rect != nil { rect^ = monitor_info.rcWork }
				}
			}
		}
		return 0
	}
	if integrated && (message == win.WM_NCMOUSEMOVE || message == win.WM_NCLBUTTONDOWN ||
		message == win.WM_NCRBUTTONDOWN || message == win.WM_NCLBUTTONUP || message == win.WM_NCRBUTTONUP) {
		win32_menu_cancel_app_pointer(state)
	}

	dwm_result: win.LRESULT
	dwm_handled := false
	if message == win.WM_NCHITTEST || message == win.WM_NCMOUSEMOVE || message == win.WM_NCMOUSELEAVE ||
		message == win.WM_NCLBUTTONDOWN || message == win.WM_NCLBUTTONUP || message == win.WM_NCLBUTTONDBLCLK ||
		message == win.WM_NCRBUTTONDOWN || message == win.WM_NCRBUTTONUP || message == win.WM_NCRBUTTONDBLCLK {
		dwm_handled = DwmDefWindowProc(hwnd, message, wparam, lparam, &dwm_result) != false
	}
	if integrated && (message == win.WM_NCMOUSEMOVE || message == win.WM_NCMOUSELEAVE ||
		message == win.WM_NCLBUTTONDOWN || message == win.WM_NCLBUTTONUP) {
		win32_menu_update_caption_pointer(state, message, lparam)
	}

	if integrated && message == win.WM_NCHITTEST {
		point := win32_menu_point_from_lparam(lparam)
		result := win32_menu_frame_hit_test(state, i32(point.x), i32(point.y))
		return win32_integrated_frame_resolve_gesture_hit_test(result, state.gesture_owner, dwm_handled, dwm_result)
	}
	if dwm_handled { return dwm_result }

	if message == win.WM_COMMAND {
		command_id := u32(uintptr(wparam) & 0xffff)
		if command_id > 0 && int(command_id) < len(state.commands) {
			win32_menu_dispatch_native_id(state, command_id)
			return 0
		}
	}
	if message == win.WM_INITMENUPOPUP { win32_menu_refresh_state(state) }

	if integrated {
		if message == win.WM_LBUTTONUP && state.caption_pressed >= 0 {
			state.caption_pressed = -1
			native_menu_request_chrome_redraw(state.menu)
		} else if message == win.WM_LBUTTONDOWN {
			state.gesture_owner = .Alicorn
			point := win32_menu_point_from_lparam(lparam)
			if win32_menu_client_point_to_window(state, &point) {
				if index := win32_menu_label_at_window_point(state, i32(point.x), i32(point.y)); index >= 0 {
					state.gesture_owner = .Native_Menu
					win32_menu_cancel_app_pointer(state)
					if state.labels[index].direct_menu != nil {
						win32_menu_label_activate(state, index)
					} else {
						state.menu_mode = true
						state.active_menu = index
						win32_menu_open_popup(state, index)
					}
					state.gesture_owner = .None
					return 0
				}
			}
			if state.menu_mode {
				win32_menu_exit_mode(state, state.hovered)
			}
		} else if message == win.WM_MOUSEMOVE {
			if state.caption_hovered >= 0 {
				state.caption_hovered = -1
				native_menu_request_chrome_redraw(state.menu)
			}
			point := win32_menu_point_from_lparam(lparam)
			if win32_menu_client_point_to_window(state, &point) {
				index := win32_menu_label_at_window_point(state, i32(point.x), i32(point.y))
				if index >= 0 && state.gesture_owner != .Alicorn { win32_menu_cancel_app_pointer(state) }
				if index != state.hovered {
					state.hovered = index
					native_menu_request_chrome_redraw(state.menu)
				}
				track := win.TRACKMOUSEEVENT{cbSize=win.DWORD(size_of(win.TRACKMOUSEEVENT)), dwFlags=win.TME_LEAVE, hwndTrack=hwnd}
				_ = win.TrackMouseEvent(&track)
			}
		} else if message == win.WM_MOUSELEAVE {
			if state.hovered >= 0 {
				state.hovered = -1
				native_menu_request_chrome_redraw(state.menu)
			}
		} else if message == win.WM_SYSKEYDOWN {
			key := int(uintptr(wparam) & 0xff)
			alt_context := (uintptr(lparam) & (uintptr(1) << 29)) != 0
			if key == win.VK_MENU {
				if len(state.labels) > 0 {
					state.menu_mode = true
					state.active_menu = 0
					state.hovered = -1
					native_menu_request_chrome_redraw(state.menu)
					return 0
				}
			} else if key != WIN32_VK_SPACE && alt_context {
				for menu, index in state.menu.application.menus {
					if len(menu.label) > 0 {
						first := int(menu.label[0])
						if first >= 'a' && first <= 'z' { first -= ('a' - 'A') }
						if first == key {
							state.menu_mode = true
							state.active_menu = index
							state.hovered = -1
							native_menu_request_chrome_redraw(state.menu)
							win32_menu_label_activate(state, index)
							return 0
						}
					}
				}
			}
		}
	}

	result := win.DefSubclassProc(hwnd, message, wparam, lparam)
	if integrated && (message == win.WM_WINDOWPOSCHANGED || message == win.WM_ACTIVATE || message == win.WM_DPICHANGED) {
		position: ^win.WINDOWPOS
		if message == win.WM_WINDOWPOSCHANGED { position = cast(^win.WINDOWPOS)uintptr(lparam) }
		flags := position.flags if position != nil else win.UINT(0)
		win32_window_geometry_record(state, message, position, flags, false)
	}
	if message == win.WM_DWMCOMPOSITIONCHANGED && integrated {
		if !win32_menu_reapply_frame(state) { win32_menu_disable_frame(state) }
	} else if message == win.WM_NCACTIVATE {
		_ = win32_menu_set_active(state, wparam != 0)
	} else if message == win.WM_ACTIVATE {
		_ = win32_menu_set_active(state, (u16(uintptr(wparam)) & 0xffff) != 0)
	} else if message == win.WM_DPICHANGED && integrated {
		// SDL owns the HWND and processes the suggested RECT through the chained
		// procedure above. Observe the resulting DPI/size; do not SetWindowPos here.
		state.dpi = win.GetDpiForWindow(hwnd)
		if state.text_renderer != nil && state.menu.runtime != nil {
			_ = win32_menu_refresh_text(state, state.menu.runtime)
		}
		if !win32_menu_extend_frame(state) { win32_menu_disable_frame(state) }
		else { win32_menu_layout_labels(state) }
		if state.menu.runtime != nil {
			_ = win32_menu_sync_window_chrome_metrics(state, state.menu.runtime)
		}
		native_menu_request_chrome_redraw(state.menu)
	} else if (message == win.WM_WINDOWPOSCHANGED || message == win.WM_SIZE) && integrated {
		position := cast(^win.WINDOWPOS)uintptr(lparam)
		// DWM's bounds can be undefined while hidden. Showing the HWND must
		// replace the fallback even when the client dimensions have not changed.
		if message == win.WM_SIZE || (position != nil &&
			((position.flags & win.SWP_NOSIZE) == 0 || (position.flags & win.SWP_SHOWWINDOW) != 0)) {
			win32_menu_layout_labels(state)
			if state.menu.runtime != nil {
				_ = win32_menu_sync_window_chrome_metrics(state, state.menu.runtime)
			}
		}
		native_menu_request_chrome_redraw(state.menu)
	} else if (message == win.WM_THEMECHANGED || message == win.WM_SETTINGCHANGE || message == win.WM_SYSCOLORCHANGE) && integrated {
		win32_menu_layout_labels(state)
		native_menu_request_chrome_redraw(state.menu)
	} else if message == win.WM_KILLFOCUS && integrated {
		win32_menu_exit_mode(state, -1)
		state.caption_hovered = -1
		state.caption_pressed = -1
	}
	return result
}

native_menu_prepare :: proc(menu: ^Native_Menu_Runtime) -> bool {
	if menu == nil || menu.window == nil || menu.application == nil { return false }
	if len(menu.application.menus) == 0 {
		return menu.application.window_decorations == .System
	}
	if menu.application.window_decorations != .System && menu.application.window_decorations != .Integrated_Title_Bar { return false }
	props := sdl3.GetWindowProperties(menu.window)
	hwnd := cast(win.HWND)sdl3.GetPointerProperty(props, "SDL.window.win32.hwnd", nil)
	if hwnd == nil { return false }
	state := new(Win32_Menu_State)
	state.menu = menu
	state.hwnd = hwnd
	state.allocator = context.allocator
	state.hovered = -1
	state.active = true
	state.active_menu = -1
	state.caption_hovered = -1
	state.caption_pressed = -1
	state.high_contrast = false
	state.windows_11 = win32_caption_windows_11()
	state.frame_enabled = menu.application.window_decorations == .Integrated_Title_Bar
	menu.platform_data = rawptr(state)
	state.commands = make([dynamic]Application_Command_ID, 1, allocator=state.allocator)
	if state.commands == nil { return false }
	state.labels = make([]Win32_Menu_Label, len(menu.application.menus), allocator=state.allocator)
	if len(menu.application.menus) > 0 && state.labels == nil {
		return false
	}
	state.root = win.CreateMenu()
	if state.root == nil { return false }
	for &description, index in menu.application.menus {
		popup: win.HMENU
		flags := win.UINT(WIN32_MF_POPUP)
		native_id := win.UINT_PTR(0)
		if description.command != Application_Command_ID(0) {
			if len(state.commands) >= 0x10000 { return false }
			native_id = win.UINT_PTR(uintptr(len(state.commands)))
			append(&state.commands, description.command)
			flags = 0
			if !description.state.enabled { flags |= WIN32_MF_GRAYED }
			if description.state.checked { flags |= WIN32_MF_CHECKED }
		} else {
			popup = win.CreatePopupMenu()
			if popup == nil || !win32_menu_build_items(state, popup, description.items) {
				if popup != nil { win.DestroyMenu(popup) }
				return false
			}
			native_id = win.UINT_PTR(uintptr(popup))
		}
		// Native HMENU uses '&' to expose the first character as the Alt key.
		// The integrated caption is drawn from the untouched label below.
		wide := win32_menu_wide(state, fmt.tprintf("&%s", description.label))
		if wide == nil {
			if popup != nil { win.DestroyMenu(popup) }
			return false
		}
		if !win.AppendMenuW(state.root, flags, native_id, win.LPCWSTR(&wide[0])) {
			delete(wide, state.allocator)
			if popup != nil { win.DestroyMenu(popup) }
			return false
		}
		label_text := win32_menu_wide(state, description.label)
		delete(wide, state.allocator)
		if label_text == nil {
			return false
		}
		label_length := len(label_text)
		if label_length > 0 && label_text[label_length-1] == 0 { label_length -= 1 }
		state.labels[index] = Win32_Menu_Label{text=label_text, length=label_length, popup=popup}
		if description.command != Application_Command_ID(0) {
			state.labels[index].direct_menu = &description
			append(&state.bindings, Win32_Menu_Item_Binding{menu=state.root, position=win.UINT(index), top_menu=&description, is_command=true})
		}
	}
	win.SetWindowSubclass(hwnd, win32_menu_subclass, WIN32_MENU_SUBCLASS_ID, win.DWORD_PTR(uintptr(state)))
	state.installed = true
	if menu.application.window_decorations == .System {
		if !win.SetMenu(hwnd, state.root) { return false }
		state.menu_attached = true
		_ = DrawMenuBar(hwnd)
	} else if state.frame_enabled {
		if !win32_menu_reapply_frame(state) { return false }
	}
	return true
}

native_menu_accessibility_appearance_changed :: proc(
	menu: ^Native_Menu_Runtime,
	increased_contrast: bool,
	request_redraw := true,
) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Win32_Menu_State)menu.platform_data
	if state.high_contrast == increased_contrast { return }
	state.high_contrast = increased_contrast
	win32_menu_layout_labels(state)
	if request_redraw { native_menu_request_chrome_redraw(menu) }
}

native_menu_destroy :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Win32_Menu_State)menu.platform_data
	win32_caption_destroy_masks(state)
	if state.installed { _ = RemoveWindowSubclass(state.hwnd, win32_menu_subclass, WIN32_MENU_SUBCLASS_ID) }
	if state.root != nil {
		if state.menu_attached { _ = win.SetMenu(state.hwnd, nil) }
		_ = win.DestroyMenu(state.root)
	}
	for label in state.labels { if label.text != nil { delete(label.text, state.allocator) } }
	if state.title.text != nil { delete(state.title.text, state.allocator) }
	if state.labels != nil { delete(state.labels, state.allocator) }
	if state.commands != nil { delete(state.commands) }
	if state.bindings != nil { delete(state.bindings) }
	free(state, allocator=state.allocator)
	menu.platform_data = nil
	menu.content_inset_top = 0
	menu.chrome_redraw_pending = false
}

native_menu_take_pending :: proc(menu: ^Native_Menu_Runtime) -> (Application_Command_ID, bool) {
	if menu == nil || !menu.has_pending { return {}, false }
	command := menu.pending_command
	menu.pending_command = {}
	menu.has_pending = false
	return command, true
}

win32_menu_match_shortcut :: proc(items: []Application_Menu_Item, key: rune, actual: sdl3.Keymod) -> (Application_Command_ID, bool) {
	for item in items {
		if item.kind == .Submenu {
			if command, found := win32_menu_match_shortcut(item.items, key, actual); found { return command, true }
		} else if item.kind == .Command && item.state.enabled && item.shortcut.key != 0 {
			expected := item.shortcut.modifiers
			primary_down := native_text_modifier(actual, sdl3.KMOD_CTRL)
			shift_down := native_text_modifier(actual, sdl3.KMOD_SHIFT)
			alt_down := native_text_modifier(actual, sdl3.KMOD_ALT)
			super_down := native_text_modifier(actual, sdl3.KMOD_GUI)
			if (Application_Menu_Modifier.Primary in expected) != primary_down { continue }
			if (Application_Menu_Modifier.Shift in expected) != shift_down { continue }
			if (Application_Menu_Modifier.Alt in expected) != alt_down { continue }
			if (Application_Menu_Modifier.Super in expected) != super_down { continue }
			upper_key := key
			if upper_key >= 'a' && upper_key <= 'z' { upper_key -= ('a' - 'A') }
			item_key := item.shortcut.key
			if item_key >= 'a' && item_key <= 'z' { item_key -= ('a' - 'A') }
			if upper_key == item_key { return item.command, true }
		}
	}
	return {}, false
}

native_menu_try_shortcut :: proc(menu: ^Native_Menu_Runtime, keycode: int, modifiers: sdl3.Keymod) -> bool {
	if menu == nil || menu.application == nil || menu.application.on_menu_command == nil { return false }
	command: Application_Command_ID
	found := false
	for description in menu.application.menus {
		if description.command != Application_Command_ID(0) && description.state.enabled && description.shortcut.key != 0 {
			expected := description.shortcut.modifiers
			if (Application_Menu_Modifier.Primary in expected) == native_text_modifier(modifiers, sdl3.KMOD_CTRL) &&
			   (Application_Menu_Modifier.Shift in expected) == native_text_modifier(modifiers, sdl3.KMOD_SHIFT) &&
			   (Application_Menu_Modifier.Alt in expected) == native_text_modifier(modifiers, sdl3.KMOD_ALT) &&
			   (Application_Menu_Modifier.Super in expected) == native_text_modifier(modifiers, sdl3.KMOD_GUI) {
				key := rune(keycode)
				if key >= 'a' && key <= 'z' { key -= ('a'-'A') }
				expected_key := description.shortcut.key
				if expected_key >= 'a' && expected_key <= 'z' { expected_key -= ('a'-'A') }
				if key == expected_key {
					native_menu_dispatch_command(menu, description.command)
					return true
				}
			}
		}
		if candidate, matched := win32_menu_match_shortcut(description.items, rune(keycode), modifiers); matched {
			command = candidate
			found = true
			break
		}
	}
	if !found { return false }
	native_menu_dispatch_command(menu, command)
	return true
}
