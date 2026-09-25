#+build darwin

package alicorn_sdl_gpu

import "base:runtime"
import "base:intrinsics"
import "core:strings"
import "core:unicode/utf8"
import NS "core:sys/darwin/Foundation"
import sdl3 "vendor:sdl3"

Darwin_Menu_State :: struct {
	application:           ^NS.Application,
	window:                ^NS.Window,
	main_menu:             ^NS.Menu,
	previous_main_menu:    ^NS.Menu,
	previous_windows_menu: ^NS.Menu,
	previous_services_menu: ^NS.Menu,
	selector:              NS.SEL,
	update_selector:       NS.SEL,
	bindings:              [dynamic]Darwin_Menu_Binding,
}

Darwin_Menu_Binding :: struct {
	menu:        ^NS.Menu,
	items:       []Application_Menu_Item,
	start_index: int,
	item_count:  int,
}

darwin_active_menu: ^Native_Menu_Runtime

darwin_menu_string :: proc(value: string) -> ^NS.String {
	utf8, err := strings.clone_to_cstring(value, context.temp_allocator)
	if err != nil { return nil }
	defer delete(utf8, context.temp_allocator)
	return NS.String_initWithCString(NS.String_alloc(), utf8, .UTF8)
}

darwin_menu_selector :: proc(value: string) -> NS.SEL {
	name := darwin_menu_string(value)
	if name == nil { return nil }
	defer NS.release(cast(^NS.Object)name)
	return NS.SelectorFromString(name)
}

darwin_menu_item_set_state :: proc(item: ^NS.MenuItem, state: NS.Integer) {
	intrinsics.objc_send(nil, item, "setState:", state)
}

darwin_menu_refresh_state :: proc(state: ^Darwin_Menu_State, menu: ^NS.Menu) {
	if state == nil || menu == nil { return }
	for binding in state.bindings {
		if binding.menu != menu { continue }
		count := min(binding.item_count, len(binding.items))
	for i in 0..<count {
		description := &binding.items[i]
		if description.kind == .Separator { continue }
		native_index := NS.Integer(binding.start_index+i)
		native_item := NS.Menu_itemAtIndex(menu, native_index)
		if native_item == nil { continue }
		NS.MenuItem_setEnabled(native_item, description.state.enabled)
		if description.kind == .Command {
			value := NS.Integer(0)
			if description.state.checked { value = 1 }
			darwin_menu_item_set_state(native_item, value)
		}
	}
	return
	}
}

darwin_menu_update_callback :: proc "c" (unused: rawptr, selector: NS.SEL, sender: ^NS.Object) {
	context = runtime.default_context()
	menu_runtime := darwin_active_menu
	if menu_runtime == nil || menu_runtime.platform_data == nil || sender == nil { return }
	state := cast(^Darwin_Menu_State)menu_runtime.platform_data
	darwin_menu_refresh_state(state, cast(^NS.Menu)sender)
}

darwin_menu_retain_if_present :: proc(menu: ^NS.Menu) {
	if menu != nil { NS.retain(cast(^NS.Object)menu) }
}

darwin_menu_key_string :: proc(key: rune) -> string {
	if key == 0 { return "" }
	normalized := key
	if normalized >= 'A' && normalized <= 'Z' { normalized += 'a' - 'A' }
	bytes, length := utf8.encode_rune(normalized)
	return string(bytes[:length])
}

darwin_menu_shortcut_mask :: proc(modifiers: Application_Menu_Modifiers) -> NS.EventModifierFlags {
	mask: NS.EventModifierFlags
	if Application_Menu_Modifier.Primary in modifiers { mask += {.Command} }
	if Application_Menu_Modifier.Shift in modifiers { mask += {.Shift} }
	if Application_Menu_Modifier.Alt in modifiers { mask += {.Option} }
	if Application_Menu_Modifier.Super in modifiers { mask += {.Control} }
	return mask
}

darwin_menu_callback :: proc "c" (unused: rawptr, selector: NS.SEL, sender: ^NS.Object) {
	context = runtime.default_context()
	menu := darwin_active_menu
	if menu == nil || menu.application == nil || menu.runtime == nil || sender == nil { return }
	item := cast(^NS.MenuItem)sender
	command := Application_Command_ID(u32(NS.MenuItem_tag(item)))
	menu.pending_command = command
	menu.has_pending = true
}

darwin_menu_add_item :: proc(menu: ^NS.Menu, item: ^NS.MenuItem) -> bool {
	if menu == nil || item == nil { return false }
	NS.Menu_addItem(menu, item)
	NS.release(cast(^NS.Object)item)
	return true
}

darwin_menu_make_command_item :: proc(
	state: ^Darwin_Menu_State,
	label: string,
	action: NS.SEL,
	key: string,
	modifiers: NS.EventModifierFlags,
) -> ^NS.MenuItem {
	title := darwin_menu_string(label)
	key_string := darwin_menu_string(key)
	if title == nil || key_string == nil {
		if title != nil { NS.release(cast(^NS.Object)title) }
		if key_string != nil { NS.release(cast(^NS.Object)key_string) }
		return nil
	}
	defer NS.release(cast(^NS.Object)title)
	defer NS.release(cast(^NS.Object)key_string)
	item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), title, action, key_string)
	if item == nil { return nil }
	NS.MenuItem_setTarget(item, cast(NS.id)state.application)
	NS.MenuItem_setKeyEquivalentModifierMask(item, modifiers)
	return item
}

darwin_menu_add_native_action :: proc(menu: ^NS.Menu, state: ^Darwin_Menu_State, label, selector_name, key: string, modifiers: NS.EventModifierFlags, target_application := true) -> bool {
	item := darwin_menu_make_command_item(state, label, darwin_menu_selector(selector_name), key, modifiers)
	if item != nil && !target_application { NS.MenuItem_setTarget(item, nil) }
	return darwin_menu_add_item(menu, item)
}

darwin_menu_build_items :: proc(state: ^Darwin_Menu_State, menu: ^NS.Menu, items: []Application_Menu_Item) -> bool {
	start_index := int(NS.Menu_numberOfItems(menu))
	append(&state.bindings, Darwin_Menu_Binding{menu=menu, items=items, start_index=start_index, item_count=len(items)})
	NS.Menu_setDelegate(menu, cast(^NS.MenuDelegate)state.application)
	for description in items {
		switch description.kind {
		case .Separator:
			NS.Menu_addItem(menu, NS.MenuItem_separatorItem())
		case .Submenu:
			title := darwin_menu_string(description.label)
			if title == nil { return false }
			submenu := NS.Menu_initWithTitle(NS.Menu_alloc(), title)
			NS.release(cast(^NS.Object)title)
			if submenu == nil { return false }
			if !darwin_menu_build_items(state, submenu, description.items) {
				NS.release(cast(^NS.Object)submenu)
				return false
			}
			empty := darwin_menu_string("")
			if empty == nil { NS.release(cast(^NS.Object)submenu); return false }
			item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), NS.Menu_title(submenu), nil, empty)
			NS.release(cast(^NS.Object)empty)
			if item == nil { NS.release(cast(^NS.Object)submenu); return false }
			NS.MenuItem_setSubmenu(item, submenu)
			NS.release(cast(^NS.Object)submenu)
			NS.MenuItem_setEnabled(item, description.state.enabled)
			if !darwin_menu_add_item(menu, item) { return false }
		case .Command:
			key := darwin_menu_key_string(description.shortcut.key)
			item := darwin_menu_make_command_item(
				state,
				description.label,
				state.selector,
				key,
				darwin_menu_shortcut_mask(description.shortcut.modifiers),
			)
			if item == nil { return false }
			NS.MenuItem_setTag(item, NS.Integer(u32(description.command)))
			NS.MenuItem_setEnabled(item, description.state.enabled)
			if description.state.checked { darwin_menu_item_set_state(item, 1) }
			if !darwin_menu_add_item(menu, item) { return false }
		}
	}
	return true
}

darwin_menu_make_titled :: proc(title: string) -> ^NS.Menu {
	value := darwin_menu_string(title)
	if value == nil { return nil }
	defer NS.release(cast(^NS.Object)value)
	menu := NS.Menu_initWithTitle(NS.Menu_alloc(), value)
	if menu != nil { NS.Menu_setAutoenablesItems(menu, false) }
	return menu
}

darwin_menu_build_application_menu :: proc(state: ^Darwin_Menu_State, title: string) -> ^NS.Menu {
	menu := darwin_menu_make_titled(title)
	if menu == nil { return nil }
	if !darwin_menu_add_native_action(menu, state, "About Alicorn", "orderFrontStandardAboutPanel:", "", {}) { return nil }
	NS.Menu_addItem(menu, NS.MenuItem_separatorItem())
	services_menu := darwin_menu_make_titled("Services")
	services_title := darwin_menu_string("Services")
	empty := darwin_menu_string("")
	if services_menu == nil || services_title == nil || empty == nil { return nil }
	services_item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), services_title, nil, empty)
	NS.release(cast(^NS.Object)services_title)
	NS.release(cast(^NS.Object)empty)
	if services_item == nil { return nil }
	NS.MenuItem_setSubmenu(services_item, services_menu)
	NS.Application_setServicesMenu(state.application, services_menu)
	NS.release(cast(^NS.Object)services_menu)
	if !darwin_menu_add_item(menu, services_item) { return nil }
	NS.Menu_addItem(menu, NS.MenuItem_separatorItem())
	if !darwin_menu_add_native_action(menu, state, "Hide Alicorn", "hide:", "h", NS.EventModifierFlags{.Command}) { return nil }
	if !darwin_menu_add_native_action(menu, state, "Hide Others", "hideOtherApplications:", "h", NS.EventModifierFlags{.Command, .Option}) { return nil }
	if !darwin_menu_add_native_action(menu, state, "Show All", "unhideAllApplications:", "", {}) { return nil }
	NS.Menu_addItem(menu, NS.MenuItem_separatorItem())
	if !darwin_menu_add_native_action(menu, state, "Quit Alicorn", "terminate:", "q", NS.EventModifierFlags{.Command}) { return nil }
	return menu
}

darwin_menu_build_window_menu :: proc(state: ^Darwin_Menu_State) -> ^NS.Menu {
	menu := darwin_menu_make_titled("Window")
	if menu == nil { return nil }
	if !darwin_menu_add_native_action(menu, state, "Minimize", "performMiniaturize:", "m", NS.EventModifierFlags{.Command}, target_application=false) { return nil }
	if !darwin_menu_add_native_action(menu, state, "Zoom", "performZoom:", "", {}, target_application=false) { return nil }
	NS.Menu_addItem(menu, NS.MenuItem_separatorItem())
	if !darwin_menu_add_native_action(menu, state, "Bring All to Front", "arrangeInFront:", "", {}) { return nil }
	return menu
}

native_menu_prepare :: proc(menu: ^Native_Menu_Runtime) -> bool {
	if menu == nil || menu.window == nil || menu.application == nil { return false }
	if len(menu.application.menus) == 0 { return menu.application.window_decorations == .System }
	props := sdl3.GetWindowProperties(menu.window)
	window := cast(^NS.Window)sdl3.GetPointerProperty(props, "SDL.window.cocoa.window", nil)
	if window == nil { return false }
	state := new(Darwin_Menu_State)
	menu.platform_data = rawptr(state)
	state.window = window
	state.application = NS.Application_sharedApplication()
	if state.application == nil { return false }
	state.previous_main_menu = NS.Application_mainMenu(state.application)
	state.previous_windows_menu = NS.Application_windowsMenu(state.application)
	state.previous_services_menu = NS.Application_servicesMenu(state.application)
	darwin_menu_retain_if_present(state.previous_main_menu)
	darwin_menu_retain_if_present(state.previous_windows_menu)
	darwin_menu_retain_if_present(state.previous_services_menu)
	state.selector = NS.MenuItem_registerActionCallback("alicornApplicationMenuCommand", darwin_menu_callback)
	state.update_selector = NS.MenuItem_registerActionCallback("menuNeedsUpdate", darwin_menu_update_callback)
	state.main_menu = darwin_menu_make_titled("")
	if state.main_menu == nil { return false }
	NS.Menu_setAutoenablesItems(state.main_menu, false)

	app_title := "Alicorn"
	app_menu := darwin_menu_build_application_menu(state, app_title)
	if app_menu == nil { return false }
	app_title_string := darwin_menu_string(app_title)
	empty := darwin_menu_string("")
	if app_title_string == nil || empty == nil { return false }
	app_item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), app_title_string, nil, empty)
	NS.release(cast(^NS.Object)app_title_string)
	NS.release(cast(^NS.Object)empty)
	if app_item == nil { return false }
	NS.MenuItem_setSubmenu(app_item, app_menu)
	NS.release(cast(^NS.Object)app_menu)
	if !darwin_menu_add_item(state.main_menu, app_item) { return false }

	window_menu := darwin_menu_build_window_menu(state)
	if window_menu == nil { return false }
	for description in menu.application.menus {
		if description.label == "Window" && !darwin_menu_build_items(state, window_menu, description.items) { return false }
	}
	help_menu_index := -1
	for description, index in menu.application.menus {
		if description.label == "Help" { help_menu_index = index; continue }
		if description.label == "Window" { continue }
		title := darwin_menu_string(description.label)
		if title == nil { return false }
		submenu := NS.Menu_initWithTitle(NS.Menu_alloc(), title)
		NS.release(cast(^NS.Object)title)
		if submenu == nil { return false }
		if !darwin_menu_build_items(state, submenu, description.items) { return false }
		empty_key := darwin_menu_string("")
		if empty_key == nil { return false }
		item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), NS.Menu_title(submenu), nil, empty_key)
		NS.release(cast(^NS.Object)empty_key)
		if item == nil { return false }
		NS.MenuItem_setSubmenu(item, submenu)
		NS.release(cast(^NS.Object)submenu)
		if !darwin_menu_add_item(state.main_menu, item) { return false }
	}
	window_title := darwin_menu_string("Window")
	empty_key := darwin_menu_string("")
	if window_title == nil || empty_key == nil { return false }
	window_item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), window_title, nil, empty_key)
	NS.release(cast(^NS.Object)window_title)
	NS.release(cast(^NS.Object)empty_key)
	if window_item == nil { return false }
	NS.MenuItem_setSubmenu(window_item, window_menu)
	NS.Application_setWindowsMenu(state.application, window_menu)
	NS.release(cast(^NS.Object)window_menu)
	if !darwin_menu_add_item(state.main_menu, window_item) { return false }
	if help_menu_index >= 0 {
		help := menu.application.menus[help_menu_index]
		title := darwin_menu_string(help.label)
		if title == nil { return false }
		submenu := NS.Menu_initWithTitle(NS.Menu_alloc(), title)
		NS.release(cast(^NS.Object)title)
		if submenu == nil || !darwin_menu_build_items(state, submenu, help.items) { return false }
		empty_key = darwin_menu_string("")
		if empty_key == nil { return false }
		help_item := NS.MenuItem_initWithTitle(NS.MenuItem_alloc(), NS.Menu_title(submenu), nil, empty_key)
		NS.release(cast(^NS.Object)empty_key)
		if help_item == nil { return false }
		NS.MenuItem_setSubmenu(help_item, submenu)
		NS.release(cast(^NS.Object)submenu)
		if !darwin_menu_add_item(state.main_menu, help_item) { return false }
	}
	NS.Application_setMainMenu(state.application, state.main_menu)
	darwin_active_menu = menu
	return true
}

native_menu_destroy :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if darwin_active_menu == menu { darwin_active_menu = nil }
	if state.application != nil {
		NS.Application_setMainMenu(state.application, state.previous_main_menu)
		NS.Application_setWindowsMenu(state.application, state.previous_windows_menu)
		NS.Application_setServicesMenu(state.application, state.previous_services_menu)
	}
	if state.main_menu != nil { NS.release(cast(^NS.Object)state.main_menu) }
	if len(state.bindings) > 0 { delete(state.bindings) }
	if state.previous_main_menu != nil { NS.release(cast(^NS.Object)state.previous_main_menu) }
	if state.previous_windows_menu != nil { NS.release(cast(^NS.Object)state.previous_windows_menu) }
	if state.previous_services_menu != nil { NS.release(cast(^NS.Object)state.previous_services_menu) }
	free(state)
	menu.platform_data = nil
}

native_menu_take_pending :: proc(menu: ^Native_Menu_Runtime) -> (Application_Command_ID, bool) {
	if menu == nil || !menu.has_pending { return {}, false }
	command := menu.pending_command
	menu.pending_command = {}
	menu.has_pending = false
	return command, true
}

native_menu_try_shortcut :: proc(menu: ^Native_Menu_Runtime, keycode: int, modifiers: sdl3.Keymod) -> bool {
	return false
}
