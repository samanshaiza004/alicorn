#+build windows

package alicorn_sdl_gpu

import "core:testing"
import win "core:sys/windows"
import alicorn "../../runtime"

WIN32_MENU_TEST_DRAG_TYPE :: alicorn.Drag_Type(141)
WIN32_MENU_TEST_DRAG_SOURCE :: alicorn.Semantic_ID{namespace=901, value=1}

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
	ui, should_build := alicorn.begin_frame(&rt)
	if should_build {
		alicorn.container_begin_simple(&ui, .Root, key="menu-drag-root",
			style=alicorn.layout_style(.Column, width=320, height=160))
		source, _ := alicorn.button_ex(&ui, "Drag", key="menu-drag-source",
			style=alicorn.layout_style(width=100, height=40))
		_ = alicorn.semantic_bind(&ui, WIN32_MENU_TEST_DRAG_SOURCE)
		_ = alicorn.drag_source(&ui, WIN32_MENU_TEST_DRAG_TYPE, WIN32_MENU_TEST_DRAG_SOURCE)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		if source == 0 {
			testing.expect(t, false, "the drag source should be retained")
			return
		}
	}

	source_id, found := alicorn.node_by_key(&rt, "menu-drag-source", .Button)
	if !found {
		testing.expect(t, false, "the drag source should be available by its key")
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
