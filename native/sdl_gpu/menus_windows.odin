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

NATIVE_MENU_HOST_NODE_BASE :: alicorn.Node_ID(0xFFFF_FFFF_FFFF_F000)
NATIVE_MENU_HOST_SOLID_NODE :: alicorn.Node_ID(0xFFFF_FFFF_FFFF_E000)

Win32_Menu_Label :: struct {
	text:   []u16,
	length: int,
	bounds: win.RECT,
	popup:  win.HMENU,
	host_node: alicorn.Node_ID,
}

Win32_Caption_Control :: struct {
	bounds: win.RECT,
	hit_test: win.LRESULT,
	glyph_host_node: alicorn.Node_ID,
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
	title:      Win32_Menu_Label,
	title_text: string,
	active:     bool,
	hovered:    int,
	active_menu: int,
	menu_mode: bool,
	chrome_height: f32,
	caption_button_bounds: win.RECT,
	caption_button_bounds_valid: bool,
	caption_controls: [3]Win32_Caption_Control,
	caption_hovered: int,
	caption_pressed: int,
	dpi:        u32,
	installed:  bool,
	menu_attached: bool,
	frame_extended: bool,
	frame_enabled: bool,
	text_renderer: ^Native_Text_Renderer,
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

// Win32 sends screen coordinates even for nonclient hit testing. Convert using
// the client origin so this also works for maximized windows and monitors whose
// desktop coordinates are negative.
win32_screen_point_to_window_logical :: proc(screen_x, screen_y, client_origin_x, client_origin_y: i32, dpi: u32) -> (f32, f32) {
	effective_dpi := dpi if dpi != 0 else 96
	logical_per_pixel := 96.0/f32(effective_dpi)
	return f32(screen_x-client_origin_x)*logical_per_pixel, f32(screen_y-client_origin_y)*logical_per_pixel
}

win32_menu_screen_point_to_window :: proc(state: ^Win32_Menu_State, x, y: i32) -> (i32, i32, bool) {
	client_origin := win.POINT{}
	if !win.ClientToScreen(state.hwnd, &client_origin) { return 0, 0, false }
	dpi := win.GetDpiForWindow(state.hwnd)
	logical_x, logical_y := win32_screen_point_to_window_logical(x, y, i32(client_origin.x), i32(client_origin.y), dpi)
	return i32(logical_x), i32(logical_y), true
}

win32_menu_client_point_to_window :: proc(state: ^Win32_Menu_State, point: ^win.POINT) -> bool {
	if !win.ClientToScreen(state.hwnd, point) { return false }
	x, y, ok := win32_menu_screen_point_to_window(state, i32(point.x), i32(point.y))
	if !ok { return false }
	point.x = win.LONG(x)
	point.y = win.LONG(y)
	return true
}

win32_integrated_frame_hit_test :: proc(
	x, y, width, height: i32,
	chrome_height, resize_x, resize_y: i32,
	maximized: bool,
	caption_controls: []Win32_Caption_Control,
	labels: []win.RECT,
) -> win.LRESULT {
	for control in caption_controls {
		if x >= i32(control.bounds.left) && x < i32(control.bounds.right) &&
			y >= i32(control.bounds.top) && y < i32(control.bounds.bottom) {
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
		if x >= i32(label.left) && x < i32(label.right) && y >= i32(label.top) && y < i32(label.bottom) {
			return win.LRESULT(win.HTCLIENT)
		}
	}
	if y >= 0 && y < chrome_height { return win.LRESULT(win.HTCAPTION) }
	return win.LRESULT(win.HTCLIENT)
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

// DWM reports caption controls relative to the outer window in physical pixels.
// The compositor and label layout use client-relative logical coordinates.
win32_caption_bounds_to_client_logical :: proc(
	window_bounds, window_rect: win.RECT,
	client_origin_x, client_origin_y: i32,
	dpi: u32,
) -> win.RECT {
	logical_per_pixel := 96.0/f32(dpi if dpi != 0 else 96)
	return win.RECT{
		left=win.LONG(f32(i32(window_bounds.left)+i32(window_rect.left)-client_origin_x)*logical_per_pixel),
		top=win.LONG(f32(i32(window_bounds.top)+i32(window_rect.top)-client_origin_y)*logical_per_pixel),
		right=win.LONG(f32(i32(window_bounds.right)+i32(window_rect.left)-client_origin_x)*logical_per_pixel),
		bottom=win.LONG(f32(i32(window_bounds.bottom)+i32(window_rect.top)-client_origin_y)*logical_per_pixel),
	}
}

win32_menu_update_caption_button_bounds :: proc(state: ^Win32_Menu_State, logical_client_width: f32) -> bool {
	if state == nil || state.hwnd == nil { return false }
	state.caption_button_bounds_valid = false
	window_bounds: win.RECT
	if DwmGetWindowAttribute(state.hwnd, WIN32_DWMWA_CAPTION_BUTTON_BOUNDS, rawptr(&window_bounds), win.DWORD(size_of(window_bounds))) < 0 {
		return false
	}
	window_rect: win.RECT
	client_origin := win.POINT{}
	if !win.GetWindowRect(state.hwnd, &window_rect) || !win.ClientToScreen(state.hwnd, &client_origin) { return false }
	bounds := win32_caption_bounds_to_client_logical(
		window_bounds,
		window_rect,
		i32(client_origin.x),
		i32(client_origin.y),
		state.dpi,
	)
	button_width := f32(bounds.right-bounds.left)
	if bounds.right <= bounds.left || button_width > min(logical_client_width*0.5, 320) { return false }
	if bounds.left < 0 || f32(bounds.right) > logical_client_width+1 { return false }
	state.caption_button_bounds = bounds
	state.caption_button_bounds_valid = true
	return true
}

win32_menu_layout_caption_controls :: proc(state: ^Win32_Menu_State) {
	if state == nil { return }
	rects := win32_caption_control_rects(state.caption_button_bounds, state.caption_button_bounds_valid)
	hit_tests := [3]win.LRESULT{
		win.LRESULT(win.HTMINBUTTON),
		win.LRESULT(win.HTMAXBUTTON),
		win.LRESULT(win.HTCLOSE),
	}
	for index in 0..<len(state.caption_controls) {
		state.caption_controls[index].bounds = rects[index]
		state.caption_controls[index].hit_test = hit_tests[index]
	}
}

win32_menu_frame_hit_test :: proc(state: ^Win32_Menu_State, screen_x, screen_y: i32) -> win.LRESULT {
	if state == nil || !state.frame_enabled { return win.LRESULT(win.HTCLIENT) }
	client_rect: win.RECT
	if !win.GetClientRect(state.hwnd, &client_rect) { return win.LRESULT(win.HTCLIENT) }
	client_origin := win.POINT{}
	if !win.ClientToScreen(state.hwnd, &client_origin) { return win.LRESULT(win.HTCLIENT) }
	dpi := win.GetDpiForWindow(state.hwnd)
	if dpi == 0 { dpi = 96 }
	to_logical := 96.0/f32(dpi)
	logical_x, logical_y := win32_screen_point_to_window_logical(screen_x, screen_y, i32(client_origin.x), i32(client_origin.y), dpi)
	x, y := i32(logical_x), i32(logical_y)
	width := i32(f32(client_rect.right-client_rect.left)*to_logical)
	height := i32(f32(client_rect.bottom-client_rect.top)*to_logical)
	resize_x := i32(f32(win.GetSystemMetricsForDpi(win.SM_CXSIZEFRAME, dpi)+win.GetSystemMetricsForDpi(win.SM_CXPADDEDBORDER, dpi))*to_logical)
	resize_y := i32(f32(win.GetSystemMetricsForDpi(win.SM_CYSIZEFRAME, dpi)+win.GetSystemMetricsForDpi(win.SM_CXPADDEDBORDER, dpi))*to_logical)
	labels := make([]win.RECT, len(state.labels), allocator=context.temp_allocator)
	for label, i in state.labels { labels[i] = label.bounds }
	defer delete(labels, context.temp_allocator)
	return win32_integrated_frame_hit_test(x, y, width, height, i32(state.chrome_height), resize_x, resize_y,
		win.IsZoomed(state.hwnd) != false, state.caption_controls[:], labels)
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
			if state.menu != nil { state.menu.chrome_redraw_pending = true }
		}
		return
	}
	point := win32_menu_point_from_lparam(lparam)
	index := win32_menu_caption_control_at_screen(state, i32(point.x), i32(point.y))
	if message == win.WM_NCMOUSEMOVE {
		if state.caption_hovered != index {
			state.caption_hovered = index
			if state.menu != nil { state.menu.chrome_redraw_pending = true }
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
			if state.menu != nil { state.menu.chrome_redraw_pending = true }
		}
	} else if message == win.WM_NCLBUTTONUP {
		if state.caption_pressed >= 0 {
			state.caption_pressed = -1
			if state.menu != nil { state.menu.chrome_redraw_pending = true }
		}
	}
}

win32_menu_layout_labels :: proc(state: ^Win32_Menu_State) {
	if state == nil || state.menu == nil || state.menu.application == nil || !state.frame_enabled { return }
	state.dpi = win.GetDpiForWindow(state.hwnd)
	if state.dpi == 0 { state.dpi = 96 }
	scale := 96.0/f32(state.dpi)
	client: win.RECT
	if !win.GetClientRect(state.hwnd, &client) { return }
	client_width := f32(client.right-client.left)*scale
	caption_h := f32(win.GetSystemMetricsForDpi(win.SM_CYCAPTION, state.dpi))*scale
	frame_y := f32(win.GetSystemMetricsForDpi(win.SM_CYSIZEFRAME, state.dpi))*scale
	state.chrome_height = max(caption_h+frame_y, 28)
	state.menu.content_inset_top = state.chrome_height
	frame_x := f32(win.GetSystemMetricsForDpi(win.SM_CXSIZEFRAME, state.dpi))*scale
	button_w := f32(win.GetSystemMetricsForDpi(win.SM_CXSIZE, state.dpi))*scale
	usable_right := client_width-(button_w*3+frame_x+8)
	if win32_menu_update_caption_button_bounds(state, client_width) {
		usable_right = f32(state.caption_button_bounds.left)-8
	} else {
		// Keep a visible fallback on systems where DWM cannot report the bounds.
		state.caption_button_bounds = win.RECT{
			left=win.LONG(client_width-(button_w*3+frame_x+8)),
			top=0,
			right=win.LONG(client_width-frame_x),
			bottom=win.LONG(state.chrome_height),
		}
		state.caption_button_bounds_valid = true
	}
	win32_menu_layout_caption_controls(state)
	left := frame_x+8
	if title_run := native_text_host_run(state.text_renderer, state.title.host_node); title_run != nil {
		title_width := title_run.width+16
		state.title.bounds = win.RECT{left=win.LONG(left), top=0, right=win.LONG(min(left+title_width, usable_right)), bottom=win.LONG(state.chrome_height)}
		left += title_width
	} else {
		state.title.bounds = win.RECT{}
	}
	left += 8
	for i in 0..<len(state.labels) {
		label := &state.labels[i]
		label.bounds = win.RECT{}
		if left >= usable_right { continue }
		run := native_text_host_run(state.text_renderer, label.host_node)
		if run == nil { continue }
		width := run.width+24
		label.bounds = win.RECT{left=win.LONG(left), top=0, right=win.LONG(min(left+width, usable_right)), bottom=win.LONG(state.chrome_height)}
		left += width
	}
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
	if state.menu != nil { state.menu.chrome_redraw_pending = true }
	return true
}

win32_menu_disable_frame :: proc(state: ^Win32_Menu_State) {
	if state == nil { return }
	state.frame_enabled = false
	state.frame_extended = false
	state.chrome_height = 0
	if state.menu != nil {
		state.menu.content_inset_top = 0
		state.menu.chrome_redraw_pending = true
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
	state.title_text = title
	title_run, title_ok := alicorn.text_run_build(&rt.text_engine, title, 14, allocator=rt.persistent_allocator, scratch_allocator=rt.scratch_allocator)
	if !title_ok { return false }
	state.title.host_node = NATIVE_MENU_HOST_NODE_BASE
	if !native_text_register_host_run(renderer, state.title.host_node, title_run) {
		alicorn.text_run_destroy(&title_run)
		return false
	}
	for &label, i in state.labels {
		run, ok := alicorn.text_run_build(&rt.text_engine, menu.application.menus[i].label, 14,
			allocator=rt.persistent_allocator, scratch_allocator=rt.scratch_allocator)
		if !ok { return false }
		label.host_node = NATIVE_MENU_HOST_NODE_BASE+alicorn.Node_ID(i+1)
		if !native_text_register_host_run(renderer, label.host_node, run) {
			alicorn.text_run_destroy(&run)
			return false
		}
	}
	caption_glyphs := [?]string{"−", "□", "×"}
	for glyph, index in caption_glyphs {
		run, ok := alicorn.text_run_build(&rt.text_engine, glyph, 14,
			allocator=rt.persistent_allocator, scratch_allocator=rt.scratch_allocator)
		if !ok { return false }
		state.caption_controls[index].glyph_host_node = NATIVE_MENU_HOST_NODE_BASE+alicorn.Node_ID(len(state.labels)+index+1)
		if !native_text_register_host_run(renderer, state.caption_controls[index].glyph_host_node, run) {
			alicorn.text_run_destroy(&run)
			return false
		}
	}
	win32_menu_layout_labels(state)
	menu.chrome_redraw_pending = true
	return true
}

win32_color_ref :: proc(value: win.COLORREF) -> alicorn.Color {
	color := u32(value)
	return alicorn.Color{f32(color&0xff)/255, f32((color>>8)&0xff)/255, f32((color>>16)&0xff)/255, 1}
}

win32_menu_chrome_colors :: proc(state: ^Win32_Menu_State) -> (background, foreground: alicorn.Color) {
	background = win32_color_ref(win.GetSysColor(win.COLOR_ACTIVECAPTION if state.active else win.COLOR_INACTIVECAPTION))
	foreground = win32_color_ref(win.GetSysColor(win.COLOR_CAPTIONTEXT if state.active else win.COLOR_INACTIVECAPTIONTEXT))
	return
}

native_menu_overlay_commands :: proc(menu: ^Native_Menu_Runtime, width, height: f32, allocator: mem.Allocator) -> []alicorn.Display_Command {
	if menu == nil || menu.application == nil || menu.application.window_decorations != .Integrated_Title_Bar || menu.platform_data == nil { return nil }
	state := cast(^Win32_Menu_State)menu.platform_data
	if !state.frame_enabled || state.chrome_height <= 0 { return nil }
	commands := make([dynamic]alicorn.Display_Command, 0, len(state.labels)*2+10, allocator=allocator)
	background, foreground := win32_menu_chrome_colors(state)
	full := alicorn.Rect{0, 0, width, min(state.chrome_height, height)}
	append(&commands, alicorn.Display_Command{NATIVE_MENU_HOST_SOLID_NODE, .Root, full, full, "", background, nil})
	active_index := state.hovered
	if active_index < 0 && state.menu_mode { active_index = state.active_menu }
	if active_index >= 0 && active_index < len(state.labels) {
		bounds := state.labels[active_index].bounds
		if bounds.right > bounds.left {
			append(&commands, alicorn.Display_Command{
				NATIVE_MENU_HOST_SOLID_NODE+1, .Button,
				alicorn.Rect{f32(bounds.left), 2, f32(bounds.right-bounds.left), max(state.chrome_height-4, 0)},
				full, "", win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHT)), nil,
			})
			foreground = win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHTTEXT))
		}
	}
	for control, index in state.caption_controls {
		if control.bounds.right <= control.bounds.left || control.bounds.bottom <= control.bounds.top { continue }
		button_foreground := foreground
		if index == state.caption_hovered {
			hover_color := win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHT))
			if index == state.caption_pressed { hover_color = win32_color_ref(win.GetSysColor(win.COLOR_3DSHADOW)) }
			append(&commands, alicorn.Display_Command{
				NATIVE_MENU_HOST_SOLID_NODE+2+alicorn.Node_ID(index), .Button,
				alicorn.Rect{
					f32(control.bounds.left), f32(control.bounds.top),
					f32(control.bounds.right-control.bounds.left), f32(control.bounds.bottom-control.bounds.top),
				},
				full, "", hover_color, nil,
			})
			button_foreground = win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHTTEXT))
		}
		run := native_text_host_run(state.text_renderer, control.glyph_host_node)
		if run == nil { continue }
		x := f32(control.bounds.left)+(f32(control.bounds.right-control.bounds.left)-run.width)/2
		y := f32(control.bounds.top)+(f32(control.bounds.bottom-control.bounds.top)-run.height)/2
		append(&commands, alicorn.Display_Command{
			control.glyph_host_node, .Text, alicorn.Rect{x, y, run.width, run.height},
			full, "", button_foreground, nil,
		})
	}
	if title_run := native_text_host_run(state.text_renderer, state.title.host_node); title_run != nil {
		y := max((state.chrome_height-title_run.height)/2, 0)
		append(&commands, alicorn.Display_Command{
			state.title.host_node, .Text, alicorn.Rect{f32(state.title.bounds.left)+8, y, title_run.width, title_run.height},
			full, state.title_text, foreground, nil,
		})
	}
	for label, i in state.labels {
		run := native_text_host_run(state.text_renderer, label.host_node)
		if run == nil || label.bounds.right <= label.bounds.left { continue }
		y := max((state.chrome_height-run.height)/2, 0)
		label_color := foreground
		if i == active_index { label_color = win32_color_ref(win.GetSysColor(win.COLOR_HIGHLIGHTTEXT)) }
		append(&commands, alicorn.Display_Command{
			label.host_node, .Text, alicorn.Rect{f32(label.bounds.left)+12, y, run.width, run.height},
			full, menu.application.menus[i].label, label_color, nil,
		})
	}
	return commands[:]
}

win32_menu_dispatch_native_id :: proc(state: ^Win32_Menu_State, native_id: u32) {
	if state == nil || state.menu == nil || native_id == 0 || int(native_id) >= len(state.commands) || native_inspector_visible(state.menu.inspector) { return }
	state.menu.pending_command = state.commands[native_id]
	state.menu.has_pending = true
	state.menu_mode = false
	state.active_menu = -1
	state.hovered = -1
	state.menu.chrome_redraw_pending = true
}

win32_menu_open_popup :: proc(state: ^Win32_Menu_State, index: int) {
	if state == nil || index < 0 || index >= len(state.labels) { return }
	label := state.labels[index]
	if label.popup == nil { return }
	win32_menu_refresh_state(state)
	client_origin := win.POINT{}
	if !win.ClientToScreen(state.hwnd, &client_origin) { return }
	dpi := win.GetDpiForWindow(state.hwnd)
	if dpi == 0 { dpi = 96 }
	to_pixels := f32(dpi)/96.0
	flags := win.UINT(win.TPM_RETURNCMD | win.TPM_NONOTIFY | win.TPM_LEFTALIGN | win.TPM_TOPALIGN)
	command := win.TrackPopupMenu(label.popup, flags,
		win.INT(i32(client_origin.x)+i32(f32(label.bounds.left)*to_pixels)),
		win.INT(i32(client_origin.y)+i32(f32(label.bounds.bottom)*to_pixels)),
		0, state.hwnd, nil)
	win32_menu_dispatch_native_id(state, u32(command))
	if command == 0 && state.menu != nil { state.menu.chrome_redraw_pending = true }
	_ = win.PostMessageW(state.hwnd, win.WM_NULL, 0, 0)
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
		menu.chrome_redraw_pending = true
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
					win32_menu_open_popup(state, i)
					return true
				}
			}
		}
	}
	if !state.menu_mode { return false }
	if keycode == int(sdl3.K_ESCAPE) {
		state.menu_mode = false
		state.active_menu = -1
		state.hovered = -1
		menu.chrome_redraw_pending = true
		return true
	}
	if keycode == int(sdl3.K_LEFT) || keycode == int(sdl3.K_RIGHT) {
		count := len(state.labels)
		if count == 0 { return true }
		delta := 1
		if keycode == int(sdl3.K_LEFT) { delta = count-1 }
		state.active_menu = (state.active_menu+delta)%count
		menu.chrome_redraw_pending = true
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
					win32_menu_open_popup(state, i)
					return true
				}
			}
		}
	}
	if keycode == int(sdl3.K_RETURN) || keycode == int(sdl3.K_KP_ENTER) || keycode == int(sdl3.K_SPACE) {
		win32_menu_open_popup(state, state.active_menu)
		return true
	}
	return false
}

win32_menu_cancel_app_pointer :: proc(state: ^Win32_Menu_State) {
	if state == nil || state.menu == nil || state.menu.runtime == nil { return }
	menu := state.menu
	rt := menu.runtime
	captured := rt.captured_node
	if captured == 0 && !alicorn.drag_is_active(rt) { return }
	cancel_cause := alicorn.pointer_cause_begin(rt, .Cancel)
	_ = alicorn.cancel_pointer_capture(rt)
	if alicorn.drag_is_active(rt) {
		_ = alicorn.drag_cancel(rt)
		_ = native_dispatch_drag_event(menu.application, rt)
	}
	if menu.application != nil && menu.application.on_pointer != nil {
		cancelled := alicorn.Pointer_Event{kind=.Cancel}
		if key, ok := alicorn.node_identity_key(rt, captured); ok { cancelled.target_key = key }
		menu.application.on_pointer(menu.application.state, rt, cancelled, captured)
	}
	alicorn.cause_end(rt, cancel_cause)
}

win32_menu_subclass :: proc "system" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, subclass_id: win.UINT_PTR, ref_data: win.DWORD_PTR) -> win.LRESULT {
	context = runtime.default_context()
	state := win32_menu_state(ref_data)
	if state == nil { return win.DefSubclassProc(hwnd, message, wparam, lparam) }
	state.hwnd = hwnd
	integrated := state.frame_enabled

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
		if result == win.LRESULT(win.HTMINBUTTON) || result == win.LRESULT(win.HTMAXBUTTON) || result == win.LRESULT(win.HTCLOSE) {
			return result
		}
		if dwm_handled { return dwm_result }
		return result
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
			if state.menu != nil { state.menu.chrome_redraw_pending = true }
		} else if message == win.WM_LBUTTONDOWN {
			point := win32_menu_point_from_lparam(lparam)
			if win32_menu_client_point_to_window(state, &point) {
				if index := win32_menu_label_at_window_point(state, i32(point.x), i32(point.y)); index >= 0 {
					win32_menu_cancel_app_pointer(state)
					state.menu_mode = true
					state.active_menu = index
					win32_menu_open_popup(state, index)
					return 0
				}
			}
			if state.menu_mode {
				state.menu_mode = false
				state.active_menu = -1
				state.menu.chrome_redraw_pending = true
			}
		} else if message == win.WM_MOUSEMOVE {
			if state.caption_hovered >= 0 {
				state.caption_hovered = -1
				state.menu.chrome_redraw_pending = true
			}
			point := win32_menu_point_from_lparam(lparam)
			if win32_menu_client_point_to_window(state, &point) {
				index := win32_menu_label_at_window_point(state, i32(point.x), i32(point.y))
				if index >= 0 { win32_menu_cancel_app_pointer(state) }
				if index != state.hovered {
					state.hovered = index
					state.menu.chrome_redraw_pending = true
				}
				track := win.TRACKMOUSEEVENT{cbSize=win.DWORD(size_of(win.TRACKMOUSEEVENT)), dwFlags=win.TME_LEAVE, hwndTrack=hwnd}
				_ = win.TrackMouseEvent(&track)
			}
		} else if message == win.WM_MOUSELEAVE {
			if state.hovered >= 0 {
				state.hovered = -1
				state.menu.chrome_redraw_pending = true
			}
		} else if message == win.WM_SYSKEYDOWN {
			key := int(uintptr(wparam) & 0xff)
			alt_context := (uintptr(lparam) & (uintptr(1) << 29)) != 0
			if key == win.VK_MENU {
				if len(state.labels) > 0 {
					state.menu_mode = true
					state.active_menu = 0
					state.hovered = -1
					state.menu.chrome_redraw_pending = true
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
							state.menu.chrome_redraw_pending = true
							win32_menu_open_popup(state, index)
							return 0
						}
					}
				}
			}
		}
	}

	result := win.DefSubclassProc(hwnd, message, wparam, lparam)
	if message == win.WM_DWMCOMPOSITIONCHANGED && integrated {
		if !win32_menu_reapply_frame(state) { win32_menu_disable_frame(state) }
	} else if message == win.WM_NCACTIVATE {
		state.active = wparam != 0
		state.caption_hovered = -1
		state.caption_pressed = -1
		if state.menu != nil { state.menu.chrome_redraw_pending = true }
	} else if message == win.WM_ACTIVATE {
		state.active = (u16(uintptr(wparam)) & 0xffff) != 0
		if !state.active {
			state.caption_hovered = -1
			state.caption_pressed = -1
		}
		if state.menu != nil { state.menu.chrome_redraw_pending = true }
	} else if message == win.WM_DPICHANGED && integrated {
		// SDL owns the HWND and processes the suggested RECT through the chained
		// procedure above. Observe the resulting DPI/size; do not SetWindowPos here.
		state.dpi = win.GetDpiForWindow(hwnd)
		if !win32_menu_extend_frame(state) { win32_menu_disable_frame(state) }
		else { win32_menu_layout_labels(state) }
		if state.menu != nil { state.menu.chrome_redraw_pending = true }
	} else if (message == win.WM_WINDOWPOSCHANGED || message == win.WM_SIZE) && integrated {
		position := cast(^win.WINDOWPOS)uintptr(lparam)
		if message == win.WM_SIZE || (position != nil && (position.flags & win.SWP_NOSIZE) == 0) { win32_menu_layout_labels(state) }
		if state.menu != nil { state.menu.chrome_redraw_pending = true }
	} else if (message == win.WM_THEMECHANGED || message == win.WM_SETTINGCHANGE) && integrated {
		win32_menu_layout_labels(state)
		if state.menu != nil { state.menu.chrome_redraw_pending = true }
	} else if message == win.WM_KILLFOCUS && integrated {
		state.menu_mode = false
		state.active_menu = -1
		state.hovered = -1
		state.caption_hovered = -1
		state.caption_pressed = -1
		if state.menu != nil { state.menu.chrome_redraw_pending = true }
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
	} else if state.frame_enabled {
		if !win32_menu_reapply_frame(state) { return false }
	}
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
