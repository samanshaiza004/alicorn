#+build windows

package alicorn_sdl_gpu

import "core:testing"
import win "core:sys/windows"

@(test)
test_system_window_without_menus_needs_no_gpu_chrome_state :: proc(t: ^testing.T) {
	app := Application{window_decorations=.System}
	menu := Native_Menu_Runtime{application=&app}
	testing.expect(t, native_menu_prepare_gpu(&menu, nil, nil),
		"a system-decorated window without menus should skip GPU menu setup")
}

@(test)
test_integrated_frame_screen_conversion_handles_negative_monitor_coordinates :: proc(t: ^testing.T) {
	x, y := win32_screen_point_to_window_logical(-1500, -200, -1600, -300, 96)
	testing.expect(t, x == 100 && y == 100,
		"signed screen coordinates on a monitor left/above the primary display should map to positive window coordinates")

	x, y = win32_screen_point_to_window_logical(150, 300, 0, 0, 144)
	testing.expect(t, x == 100 && y == 200,
		"150 percent DPI should convert physical screen pixels to logical coordinates")

	x, y = win32_screen_point_to_window_logical(200, 400, 0, 0, 192)
	testing.expect(t, x == 100 && y == 200,
		"200 percent DPI should convert physical screen pixels to logical coordinates")
}

@(test)
test_integrated_frame_leaves_bare_f10_for_devtools :: proc(t: ^testing.T) {
	app := Application{window_decorations=.Integrated_Title_Bar}
	state := Win32_Menu_State{}
	menu := Native_Menu_Runtime{application=&app, platform_data=rawptr(&state)}
	handled := native_menu_handle_keydown(&menu, WIN32_VK_F10, {})
	testing.expect(t, !handled && !state.menu_mode,
		"bare F10 must continue to the Alicorn DevTools HUD instead of entering menu mode")
}

@(test)
test_integrated_frame_hit_test_resizing_and_menu_regions :: proc(t: ^testing.T) {
	labels := [?]win.RECT{{left=10, top=0, right=90, bottom=32}}
	testing.expect(
		t,
		win32_integrated_frame_hit_test(0, 0, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTTOPLEFT),
		"corner should keep resize priority",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(500, 2, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTTOP),
		"top edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(2, 300, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTLEFT),
		"left edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(998, 300, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTRIGHT),
		"right edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(500, 798, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTBOTTOM),
		"bottom edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(50, 16, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTCLIENT),
		"menu labels should stay client-hit targets",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(200, 16, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTCAPTION),
		"blank chrome should drag the window",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(200, 40, 1000, 800, 32, 8, 8, false, labels[:]) == win.LRESULT(win.HTCLIENT),
		"application area should remain client input",
	)
}

@(test)
test_integrated_frame_hit_test_maximized_does_not_expose_resize_edges :: proc(t: ^testing.T) {
	got := win32_integrated_frame_hit_test(1, 200, 1000, 800, 32, 8, 8, true, nil)
	testing.expect(t, got == win.LRESULT(win.HTCLIENT), "maximized frame should not report resize borders")
	got = win32_integrated_frame_hit_test(200, 12, 1000, 800, 32, 8, 8, true, nil)
	testing.expect(t, got == win.LRESULT(win.HTCAPTION), "maximized blank chrome should remain a drag region")
}
