#+build linux

package alicorn_sdl_gpu

import sdl3 "vendor:sdl3"

// Linux keeps system decorations and uses menu descriptions only as semantic
// accelerator metadata. It does not create a native application menu.
native_menu_prepare :: proc(menu: ^Native_Menu_Runtime) -> bool {
	return menu != nil && menu.application != nil &&
		menu.application.window_decorations == .System
}

native_menu_destroy :: proc(menu: ^Native_Menu_Runtime) {}

native_menu_take_pending :: proc(menu: ^Native_Menu_Runtime) -> (Application_Command_ID, bool) {
	return {}, false
}

native_menu_try_shortcut :: proc(
	menu: ^Native_Menu_Runtime,
	keycode: int,
	modifiers: sdl3.Keymod,
	repeat: bool,
) -> bool {
	if menu == nil || menu.application == nil || menu.application.on_menu_command == nil { return false }
	command, found := native_menu_match_shortcut(menu.application, keycode, modifiers)
	if !found { return false }
	if !repeat { native_menu_dispatch_command(menu, command) }
	return true
}

native_menu_accessibility_appearance_changed :: proc(
	menu: ^Native_Menu_Runtime,
	increased_contrast: bool,
	request_redraw := true,
) {
	_ = menu
	_ = increased_contrast
	_ = request_redraw
}
