#+build linux

package alicorn_sdl_gpu

import sdl3 "vendor:sdl3"

// Other SDL hosts keep the existing system decorations. Menu support is
// currently implemented only by the Windows and macOS native adapters.
native_menu_prepare :: proc(menu: ^Native_Menu_Runtime) -> bool {
	return menu != nil && menu.application != nil && len(menu.application.menus) == 0 &&
		menu.application.window_decorations == .System
}

native_menu_destroy :: proc(menu: ^Native_Menu_Runtime) {}

native_menu_take_pending :: proc(menu: ^Native_Menu_Runtime) -> (Application_Command_ID, bool) {
	return {}, false
}

native_menu_try_shortcut :: proc(menu: ^Native_Menu_Runtime, keycode: int, modifiers: sdl3.Keymod) -> bool {
	return false
}
