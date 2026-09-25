#+build windows

package alicorn_sdl_gpu

import "core:mem"
import "base:runtime"
import win "core:sys/windows"
import "core:c"
import "core:fmt"
import sdl3 "vendor:sdl3"

foreign import dwmapi "system:Dwmapi.lib"
foreign dwmapi {
	DwmDefWindowProc :: proc "system" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, result: ^win.LRESULT) -> win.BOOL ---
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

Win32_Menu_Label :: struct {
	text:   []u16,
	length: int,
	bounds: win.RECT,
	popup:  win.HMENU,
}

Win32_Menu_Item_Binding :: struct {
	menu:       win.HMENU,
	position:   win.UINT,
	item:       ^Application_Menu_Item,
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
	active:     bool,
	hovered:    int,
	dpi:        u32,
	installed:  bool,
	menu_attached: bool,
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
		if !binding.item.state.enabled { flags |= WIN32_MF_GRAYED }
		_ = win.EnableMenuItem(binding.menu, binding.position, flags)
		if binding.is_command {
			check := WIN32_MF_BYPOSITION
			if binding.item.state.checked { check |= WIN32_MF_CHECKED }
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

win32_menu_screen_point_to_window :: proc(state: ^Win32_Menu_State, x, y: i32) -> (i32, i32, bool) {
	window_rect: win.RECT
	if !win.GetWindowRect(state.hwnd, &window_rect) { return 0, 0, false }
	return x-window_rect.left, y-window_rect.top, true
}

win32_menu_client_point_to_window :: proc(state: ^Win32_Menu_State, point: ^win.POINT) -> bool {
	if !win.ClientToScreen(state.hwnd, point) { return false }
	x, y, ok := win32_menu_screen_point_to_window(state, i32(point.x), i32(point.y))
	if !ok { return false }
	point.x = win.LONG(x)
	point.y = win.LONG(y)
	return true
}

win32_menu_draw_caption_labels :: proc(state: ^Win32_Menu_State) {
	if state == nil || state.menu == nil || state.menu.application == nil || state.menu.application.window_decorations != .Integrated_Title_Bar { return }
	hdc := win.GetWindowDC(state.hwnd)
	if hdc == nil { return }
	defer win.ReleaseDC(state.hwnd, hdc)
	old_font := win.SelectObject(hdc, win.GetStockObject(win.DEFAULT_GUI_FONT))
	defer win.SelectObject(hdc, old_font)
	_ = win.SetBkMode(hdc, .TRANSPARENT)

	state.dpi = win.GetDpiForWindow(state.hwnd)
	if state.dpi == 0 { state.dpi = 96 }
	caption_h := win.GetSystemMetricsForDpi(win.SM_CYCAPTION, state.dpi)
	frame_y := win.GetSystemMetricsForDpi(win.SM_CYSIZEFRAME, state.dpi)
	frame_x := win.GetSystemMetricsForDpi(win.SM_CXSIZEFRAME, state.dpi)
	button_w := win.GetSystemMetricsForDpi(win.SM_CXSIZE, state.dpi)
	caption_buttons_reserve := button_w*3 + frame_x + 6
	window_rect: win.RECT
	if !win.GetWindowRect(state.hwnd, &window_rect) { return }
	usable_right := i32(window_rect.right-window_rect.left) - caption_buttons_reserve

	text_metrics: win.TEXTMETRICW
	_ = win.GetTextMetricsW(hdc, &text_metrics)
	text_height := i32(text_metrics.tmHeight)
	left := frame_x + win.GetSystemMetricsForDpi(win.SM_CXSIZE, state.dpi) + (8*win.INT(state.dpi))/96
	// Keep the native window title visible and place the menu labels after it.
	title: [256]u16
	title_len := win.GetWindowTextW(state.hwnd, win.LPWSTR(&title[0]), c.int(len(title)))
	if title_len > 0 {
		title_size: win.SIZE
		if win.GetTextExtentPoint32W(hdc, win.LPCWSTR(&title[0]), title_len, &title_size) {
			left += i32(title_size.cx) + (8*win.INT(state.dpi))/96
		}
	}
	base_top := frame_y + (caption_h-text_height)/2
	for i in 0..<len(state.labels) {
		label := &state.labels[i]
		label.bounds = win.RECT{}
		if left >= usable_right { continue }
		label_size: win.SIZE
		if !win.GetTextExtentPoint32W(hdc, win.LPCWSTR(&label.text[0]), c.int(label.length), &label_size) { continue }
		padding := (12*win.INT(state.dpi))/96
		width := i32(label_size.cx) + padding*2
		label.bounds = win.RECT{
			left=win.LONG(left), top=win.LONG(base_top-((4*win.INT(state.dpi))/96)),
			right=win.LONG(min(left+width, usable_right)), bottom=win.LONG(base_top+text_height+((4*win.INT(state.dpi))/96)),
		}
		if state.hovered == i {
			_ = win.FillRect(hdc, &label.bounds, win.GetSysColorBrush(win.COLOR_HIGHLIGHT))
			_ = win.SetTextColor(hdc, win.GetSysColor(win.COLOR_HIGHLIGHTTEXT))
		} else if state.active {
			_ = win.SetTextColor(hdc, win.GetSysColor(win.COLOR_CAPTIONTEXT))
		} else {
			_ = win.SetTextColor(hdc, win.GetSysColor(win.COLOR_INACTIVECAPTIONTEXT))
		}
		text_x := i32(label.bounds.left) + padding
		text_y := base_top
		_ = win.TextOutW(hdc, win.INT(text_x), win.INT(text_y), win.LPCWSTR(&label.text[0]), c.int(label.length))
		left += width
	}
}

win32_menu_dispatch_native_id :: proc(state: ^Win32_Menu_State, native_id: u32) {
	if state == nil || state.menu == nil || native_id == 0 || int(native_id) >= len(state.commands) { return }
	state.menu.pending_command = state.commands[native_id]
	state.menu.has_pending = true
}

win32_menu_open_popup :: proc(state: ^Win32_Menu_State, index: int) {
	if state == nil || index < 0 || index >= len(state.labels) { return }
	label := state.labels[index]
	if label.popup == nil { return }
	win32_menu_refresh_state(state)
	window_rect: win.RECT
	if !win.GetWindowRect(state.hwnd, &window_rect) { return }
	flags := win.UINT(win.TPM_RETURNCMD | win.TPM_NONOTIFY | win.TPM_LEFTALIGN | win.TPM_TOPALIGN)
	command := win.TrackPopupMenu(label.popup, flags, win.INT(window_rect.left+label.bounds.left), win.INT(window_rect.top+label.bounds.bottom), 0, state.hwnd, nil)
	win32_menu_dispatch_native_id(state, u32(command))
	_ = win.PostMessageW(state.hwnd, win.WM_NULL, 0, 0)
}

win32_menu_subclass :: proc "system" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, subclass_id: win.UINT_PTR, ref_data: win.DWORD_PTR) -> win.LRESULT {
	context = runtime.default_context()
	state := win32_menu_state(ref_data)
	if state == nil { return win.DefSubclassProc(hwnd, message, wparam, lparam) }
	state.hwnd = hwnd

	if message == win.WM_NCHITTEST || message == win.WM_NCMOUSEMOVE || message == win.WM_NCLBUTTONDOWN || message == win.WM_NCLBUTTONUP || message == win.WM_NCLBUTTONDBLCLK {
		dwm_result: win.LRESULT
		if DwmDefWindowProc(hwnd, message, wparam, lparam, &dwm_result) { return dwm_result }
	}

	if message == win.WM_NCHITTEST && state.menu != nil && state.menu.application != nil && state.menu.application.window_decorations == .Integrated_Title_Bar {
		point := win32_menu_point_from_lparam(lparam)
		if index_x, index_y, ok := win32_menu_screen_point_to_window(state, i32(point.x), i32(point.y)); ok {
			if win32_menu_label_at_window_point(state, index_x, index_y) >= 0 { return win.LRESULT(win.HTCLIENT) }
		}
		return win.DefSubclassProc(hwnd, message, wparam, lparam)
	}

	if message == win.WM_COMMAND {
		command_id := u32(uintptr(wparam) & 0xffff)
		if command_id > 0 && int(command_id) < len(state.commands) {
			win32_menu_dispatch_native_id(state, command_id)
			return 0
		}
	}
	if message == win.WM_INITMENUPOPUP { win32_menu_refresh_state(state) }

	if state.menu != nil && state.menu.application != nil && state.menu.application.window_decorations == .Integrated_Title_Bar {
		if message == win.WM_LBUTTONDOWN {
			point := win32_menu_point_from_lparam(lparam)
			if win32_menu_client_point_to_window(state, &point) {
				if index := win32_menu_label_at_window_point(state, i32(point.x), i32(point.y)); index >= 0 {
					win32_menu_open_popup(state, index)
					return 0
				}
			}
		} else if message == win.WM_MOUSEMOVE {
			point := win32_menu_point_from_lparam(lparam)
			if win32_menu_client_point_to_window(state, &point) {
				index := win32_menu_label_at_window_point(state, i32(point.x), i32(point.y))
				if index != state.hovered {
					state.hovered = index
					_ = win.RedrawWindow(hwnd, nil, nil, win.RedrawWindowFlags(0x0401))
				}
				track := win.TRACKMOUSEEVENT{cbSize=win.DWORD(size_of(win.TRACKMOUSEEVENT)), dwFlags=win.TME_LEAVE, hwndTrack=hwnd}
				_ = win.TrackMouseEvent(&track)
			}
		} else if message == win.WM_MOUSELEAVE {
			if state.hovered >= 0 {
				state.hovered = -1
				_ = win.RedrawWindow(hwnd, nil, nil, win.RedrawWindowFlags(0x0401))
			}
		} else if message == win.WM_SYSKEYDOWN {
			key := int(uintptr(wparam) & 0xff)
			alt_context := (uintptr(lparam) & (uintptr(1) << 29)) != 0
			if key != WIN32_VK_SPACE && alt_context {
				for menu, index in state.menu.application.menus {
					if len(menu.label) > 0 {
						first := int(menu.label[0])
						if first >= 'a' && first <= 'z' { first -= ('a' - 'A') }
						if first == key {
							win32_menu_open_popup(state, index)
							return 0
						}
					}
				}
			}
		}
	}

	result := win.DefSubclassProc(hwnd, message, wparam, lparam)
	if message == win.WM_NCPAINT || message == win.WM_NCACTIVATE || message == win.WM_THEMECHANGED || message == win.WM_SETTINGCHANGE {
		if message == win.WM_NCACTIVATE { state.active = wparam != 0 }
		win32_menu_draw_caption_labels(state)
	} else if message == win.WM_ACTIVATE {
		state.active = (u16(uintptr(wparam)) & 0xffff) != 0
		win32_menu_draw_caption_labels(state)
	} else if message == win.WM_DPICHANGED {
		state.dpi = win.GetDpiForWindow(hwnd)
		win32_menu_draw_caption_labels(state)
		_ = win.RedrawWindow(hwnd, nil, nil, win.RedrawWindowFlags(0x0401))
	} else if message == win.WM_WINDOWPOSCHANGED {
		position := cast(^win.WINDOWPOS)uintptr(lparam)
		if position != nil && (position.flags & win.SWP_NOSIZE) == 0 {
			win32_menu_draw_caption_labels(state)
		}
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
	menu.platform_data = rawptr(state)
	state.commands = make([dynamic]Application_Command_ID, 1, allocator=state.allocator)
	if state.commands == nil { return false }
	state.labels = make([]Win32_Menu_Label, len(menu.application.menus), allocator=state.allocator)
	if len(menu.application.menus) > 0 && state.labels == nil {
		return false
	}
	state.root = win.CreateMenu()
	if state.root == nil { return false }
	for description, index in menu.application.menus {
		popup := win.CreatePopupMenu()
		if popup == nil || !win32_menu_build_items(state, popup, description.items) {
			if popup != nil { win.DestroyMenu(popup) }
			return false
		}
		// Native HMENU uses '&' to expose the first character as the Alt key.
		// The integrated caption is drawn from the untouched label below.
		wide := win32_menu_wide(state, fmt.tprintf("&%s", description.label))
		if wide == nil {
			win.DestroyMenu(popup)
			return false
		}
		if !win.AppendMenuW(state.root, WIN32_MF_POPUP, win.UINT_PTR(uintptr(popup)), win.LPCWSTR(&wide[0])) {
			delete(wide, state.allocator)
			win.DestroyMenu(popup)
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
	}
	win.SetWindowSubclass(hwnd, win32_menu_subclass, WIN32_MENU_SUBCLASS_ID, win.DWORD_PTR(uintptr(state)))
	state.installed = true
	if menu.application.window_decorations == .System {
		if !win.SetMenu(hwnd, state.root) { return false }
		state.menu_attached = true
		_ = DrawMenuBar(hwnd)
	}
	win32_menu_draw_caption_labels(state)
	_ = win.RedrawWindow(hwnd, nil, nil, win.RedrawWindowFlags(0x0401))
	return true
}

native_menu_destroy :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Win32_Menu_State)menu.platform_data
	if state.installed { _ = RemoveWindowSubclass(state.hwnd, win32_menu_subclass, WIN32_MENU_SUBCLASS_ID) }
	if state.root != nil {
		if state.menu_attached { _ = win.SetMenu(state.hwnd, nil) }
		_ = win.DestroyMenu(state.root)
	}
	for label in state.labels { if label.text != nil { delete(label.text, state.allocator) } }
	if state.labels != nil { delete(state.labels, state.allocator) }
	if state.commands != nil { delete(state.commands) }
	if state.bindings != nil { delete(state.bindings) }
	free(state, allocator=state.allocator)
	menu.platform_data = nil
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
