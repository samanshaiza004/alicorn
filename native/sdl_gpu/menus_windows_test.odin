#+build windows

package alicorn_sdl_gpu

import "core:testing"
import win "core:sys/windows"
import alicorn "../../runtime"
import "vendor:sdl3"

WIN32_MENU_TEST_DRAG_TYPE :: alicorn.Drag_Type(141)
WIN32_MENU_TEST_DRAG_SOURCE :: alicorn.Semantic_ID{namespace=901, value=1}

@(test)
test_hidden_menu_labels_release_chrome_but_keep_command_metadata :: proc(t: ^testing.T) {
	items := [?]Application_Menu_Item{{kind=.Command, command=Application_Command_ID(81), label="Open", state={enabled=true}, shortcut={'O', {.Primary}}}}
	menus := [?]Application_Menu{{label="File", items=items[:]}}
	app := Application{menus=menus[:], window_decorations=.Integrated_Title_Bar, menu_presentation=.Hidden}
	menu := Native_Menu_Runtime{application=&app}
	labels := [?]Win32_Menu_Label{{bounds={8, 0, 64, 32}}}
	state := Win32_Menu_State{menu=&menu, labels=labels[:], dpi=96, chrome_height_pixels=32}
	state.caption_controls[0].bounds.left = 800
	win32_menu_layout_label_bounds(&state)
	testing.expect(t, state.labels[0].bounds == win.RECT{} && win32_menu_label_at_window_point(&state, 20, 16) == -1,
		"hidden menu labels must have no visual or pointer exclusion over retained tabs and drag areas")
	command, found := native_menu_match_shortcut(&app, int(sdl3.K_O), sdl3.KMOD_CTRL)
	testing.expect(t, found && command == Application_Command_ID(81),
		"hiding labels must retain the borrowed native command and shortcut registry")
	app.window_decorations = .System
	testing.expect(t, !win32_menu_labels_hidden(&state), "system menu presentation must retain the platform menu bar")
}

@(test)
test_hidden_menu_alt_route_preserves_system_menu_and_devtools :: proc(t: ^testing.T) {
	menus := [?]Application_Menu{{label="File"}}
	app := Application{menus=menus[:], window_decorations=.Integrated_Title_Bar, menu_presentation=.Hidden}
	labels := [?]Win32_Menu_Label{{popup=cast(win.HMENU)uintptr(1)}}
	state := Win32_Menu_State{labels=labels[:]}
	menu := Native_Menu_Runtime{application=&app, platform_data=&state}
	state.menu = &menu
	testing.expect(t, native_menu_handle_keydown(&menu, int(sdl3.K_LALT), {}) && !state.menu_mode,
		"bare Alt must wait for release before opening the first hidden native popup")
	testing.expect(t, win32_menu_take_alt_popup(&state) == 0 && win32_menu_take_alt_popup(&state) == -1,
		"Alt release must consume exactly one native menu opening")
	_ = native_menu_handle_keydown(&menu, int(sdl3.K_LALT), {})
	testing.expect(t, !native_menu_handle_keydown(&menu, int(sdl3.K_SPACE), sdl3.KMOD_ALT) && win32_menu_take_alt_popup(&state) == -1,
		"Alt+Space must stay with the Windows system menu and cancel the pending app popup")
	testing.expect(t, !native_menu_handle_keydown(&menu, WIN32_VK_F10, {}) && !state.menu_mode,
		"F10 must remain available to DevTools with hidden menus")
	state.alt_menu_pending = true
	win32_menu_exit_mode_state(&state, -1)
	testing.expect(t, win32_menu_take_alt_popup(&state) == -1, "focus loss/menu cancellation must cancel a pending Alt opening")
	state.alt_menu_pending = true
	state.gesture_owner = .Alicorn
	win32_menu_cancel_input(&state)
	testing.expect(t, win32_menu_take_alt_popup(&state) == -1 && state.gesture_owner == .None,
		"capture loss and cancel mode must discard pending native menu intent along with gesture ownership")
}

@(test)
test_hidden_bare_alt_never_activates_a_direct_top_level_command :: proc(t: ^testing.T) {
	menus := [?]Application_Menu{{label="Save", command=Application_Command_ID(44), state={enabled=true}}, {label="File"}}
	app := Application{menus=menus[:], window_decorations=.Integrated_Title_Bar, menu_presentation=.Hidden}
	menu := Native_Menu_Runtime{application=&app}
	labels := [?]Win32_Menu_Label{{direct_menu=&menus[0]}, {popup=cast(win.HMENU)uintptr(1)}}
	state := Win32_Menu_State{menu=&menu, labels=labels[:], alt_menu_pending=true}
	testing.expect(t, win32_menu_take_alt_popup(&state) == 1 && !menu.has_pending,
		"bare Alt must choose the first popup without executing an enabled direct command")
	state.labels = labels[:1]
	state.alt_menu_pending = true
	testing.expect(t, win32_menu_take_alt_popup(&state) == -1 && !menu.has_pending,
		"a direct-command-only caption must not execute a command when Alt is released")
}

@(test)
test_hidden_native_popup_anchors_below_the_caption_at_fractional_dpi :: proc(t: ^testing.T) {
	app := Application{window_decorations=.Integrated_Title_Bar, menu_presentation=.Hidden}
	menu := Native_Menu_Runtime{application=&app}
	labels := [?]Win32_Menu_Label{{bounds={40, 0, 80, 32}}}
	state := Win32_Menu_State{menu=&menu, labels=labels[:]}
	for dpi in ([4]u32{96, 120, 144, 192}) {
		state.dpi = dpi
		state.chrome_height_pixels = i32(native_pixel_edge(32, f32(dpi)/96))
		anchor := win32_menu_popup_anchor(&state, 0)
		testing.expect(t, anchor.x == win.LONG(native_pixel_edge(8, f32(dpi)/96)) && anchor.y == state.chrome_height_pixels,
			"hidden menus must open below the header using physical caption coordinates")
	}
	app.menu_presentation = .Labels
	testing.expect(t, win32_menu_popup_anchor(&state, 0) == win.POINT{40, 32},
		"the default native popup must continue to anchor to its visible label")
}

Win32_Menu_Drag_Cancel_Probe :: struct {
	calls: int,
	last:  alicorn.Drag_Event,
}

win32_menu_test_on_drag :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Drag_Event) {
	probe := cast(^Win32_Menu_Drag_Cancel_Probe)state
	probe.calls += 1
	probe.last = event
}

@(test)
test_win32_chrome_uses_theme_colors_and_respects_high_contrast :: proc(t: ^testing.T) {
	appearance := Window_Chrome_Appearance{
		defined=true,
		background=alicorn.Color{0.18, 0.22, 0.28, 1},
		foreground=alicorn.Color{0.9, 0.92, 0.96, 1},
	}
	menu := Native_Menu_Runtime{chrome_appearance=appearance}
	state := Win32_Menu_State{menu=&menu, active=true}
	background, foreground := win32_menu_chrome_colors(&state)
	testing.expect(t, background == appearance.background && foreground == appearance.foreground,
		"normal integrated chrome should use the app's resolved theme appearance")

	state.active = false
	background, foreground = win32_menu_chrome_colors(&state)
	testing.expect(t, background == appearance.background &&
		foreground == win32_color_mix(appearance.background, appearance.foreground, 0.72),
		"inactive themed chrome should retain its surface with softer foreground contrast")

	state.high_contrast = true
	background, foreground = win32_menu_chrome_colors(&state)
	testing.expect(t,
		background == win32_color_ref(win.GetSysColor(win.COLOR_MENU)) &&
		foreground == win32_color_ref(win.GetSysColor(win.COLOR_MENUTEXT)),
		"high contrast should use the Windows system menu palette instead of app colors")
}

@(test)
test_win32_menu_capture_cancel_delivers_active_drag_cancellation :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160})
	defer alicorn.destroy_runtime(&rt)
	source_id: alicorn.Node_ID
	ui, should_build := alicorn.begin_frame(&rt)
	if should_build {
		alicorn.container_begin_simple(&ui, .Root, key="menu-drag-root",
			style=alicorn.layout_style(.Column, width=320, height=160))
		source_id, _ = alicorn.button_ex(&ui, "Drag", style=alicorn.layout_style(width=100, height=40))
		_ = alicorn.semantic_bind(&ui, WIN32_MENU_TEST_DRAG_SOURCE)
		_ = alicorn.drag_source(&ui, WIN32_MENU_TEST_DRAG_TYPE, WIN32_MENU_TEST_DRAG_SOURCE)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		if source_id == 0 {
			testing.expect(t, false, "the drag source should be retained")
			return
		}
	}

	if source_id == 0 {
		testing.expect(t, false, "the drag source should be retained")
		return
	}
	source := rt.nodes[source_id]
	x, y := source.bounds.x+source.bounds.w*0.5, source.bounds.y+source.bounds.h*0.5
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Down, x=x, y=y, button=1})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Move, x=x+32, y=y})
	_, started := alicorn.drag_event_take(&rt)
	if !started || !alicorn.drag_is_active(&rt) {
		testing.expect(t, false, "moving beyond the drag threshold should start the runtime drag")
		return
	}

	probe := Win32_Menu_Drag_Cancel_Probe{}
	application := Application{state=&probe, on_drag=win32_menu_test_on_drag}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt}
	state := Win32_Menu_State{menu=&menu}
	win32_menu_cancel_app_pointer(&state)

	testing.expect(t, probe.calls == 1 && probe.last.kind == .Cancelled &&
		probe.last.source == WIN32_MENU_TEST_DRAG_SOURCE,
		"menu capture cancellation should deliver exactly one Cancelled event to the app")
	_, pending := alicorn.drag_event_take(&rt)
	testing.expect(t, !pending && !alicorn.drag_is_active(&rt),
		"delivering menu cancellation should consume the terminal event and end the drag")
}
