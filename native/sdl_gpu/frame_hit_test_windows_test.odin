#+build windows

package alicorn_sdl_gpu

import "core:testing"
import win "core:sys/windows"
import alicorn "../../runtime"

@(test)
test_native_chrome_feedback_uses_distinct_derived_states :: proc(t: ^testing.T) {
	background := alicorn.Color{1, 1, 1, 1}
	foreground := alicorn.Color{0, 0, 0, 1}
	hover, open, pressed := win32_menu_feedback_colors(background, foreground)
	ordered := hover.r < background.r && open.r < hover.r && pressed.r < open.r
	strengths := hover.r > 0.89 && hover.r < 0.91 &&
		open.r > 0.85 && open.r < 0.87 && pressed.r > 0.79 && pressed.r < 0.81
	alpha_preserved := hover.a == 1 && open.a == 1 && pressed.a == 1
	testing.expect(t, ordered && strengths && alpha_preserved,
		"normal caption hover, open-menu, and pressed fills should be visibly distinct foreground mixes")
}

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
test_caption_button_bounds_convert_to_client_logical_coordinates :: proc(t: ^testing.T) {
	window_bounds := win.RECT{left=1380, top=0, right=1515, bottom=40}
	window_rect := win.RECT{left=-1500, top=400, right=300, bottom=1400}
	got := win32_caption_bounds_to_client_logical(window_bounds, window_rect, -1500, 400, 144)
	testing.expect(t, got.left == 920 && got.top == 0 && got.right == 1010 && got.bottom == 26,
		"DWM window-relative bounds should map to client logical coordinates at 150 percent DPI")
}

@(test)
test_caption_control_geometry_is_shared_by_draw_and_hit_testing :: proc(t: ^testing.T) {
	caption_bounds := win.RECT{left=900, top=0, right=1200, bottom=40}
	rects := win32_caption_control_rects(caption_bounds, true)
	controls := [3]Win32_Caption_Control{
		{bounds=rects[0], hit_test=win.LRESULT(win.HTMINBUTTON)},
		{bounds=rects[1], hit_test=win.LRESULT(win.HTMAXBUTTON)},
		{bounds=rects[2], hit_test=win.LRESULT(win.HTCLOSE)},
	}
	testing.expect(t, rects[0].left == 900 && rects[0].right == 1000, "minimize drawing bounds should use the first third of DWM's cluster")
	testing.expect(t, rects[1].left == 1000 && rects[1].right == 1100, "maximize drawing bounds should use the second third of DWM's cluster")
	testing.expect(t, rects[2].left == 1100 && rects[2].right == 1200, "close drawing bounds should use the last third of DWM's cluster")
	testing.expect(t,
		win32_integrated_frame_hit_test(950, 20, 1200, 800, 40, 8, 8, false, controls[:], nil) == win.LRESULT(win.HTMINBUTTON),
		"the minimize hit target should use the same rectangle as its glyph")
	testing.expect(t,
		win32_integrated_frame_hit_test(1050, 20, 1200, 800, 40, 8, 8, false, controls[:], nil) == win.LRESULT(win.HTMAXBUTTON),
		"the maximize hit target should use the same rectangle as its glyph")
	testing.expect(t,
		win32_integrated_frame_hit_test(1150, 20, 1200, 800, 40, 8, 8, false, controls[:], nil) == win.LRESULT(win.HTCLOSE),
		"the close hit target should use the same rectangle as its glyph")
}

@(test)
test_integrated_frame_hit_test_resizing_and_menu_regions :: proc(t: ^testing.T) {
	labels := [?]win.RECT{{left=10, top=0, right=90, bottom=32}}
	testing.expect(
		t,
		win32_integrated_frame_hit_test(0, 0, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTTOPLEFT),
		"corner should keep resize priority",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(500, 2, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTTOP),
		"top edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(2, 300, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTLEFT),
		"left edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(998, 300, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTRIGHT),
		"right edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(500, 798, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTBOTTOM),
		"bottom edge should resize",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(50, 16, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTCLIENT),
		"menu labels should stay client-hit targets",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(200, 16, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTCAPTION),
		"blank chrome should drag the window",
	)
	testing.expect(
		t,
		win32_integrated_frame_hit_test(200, 40, 1000, 800, 32, 8, 8, false, nil, labels[:]) == win.LRESULT(win.HTCLIENT),
		"application area should remain client input",
	)
}

@(test)
test_integrated_frame_hit_test_maximized_does_not_expose_resize_edges :: proc(t: ^testing.T) {
	got := win32_integrated_frame_hit_test(1, 200, 1000, 800, 32, 8, 8, true, nil, nil)
	testing.expect(t, got == win.LRESULT(win.HTCLIENT), "maximized frame should not report resize borders")
	got = win32_integrated_frame_hit_test(200, 12, 1000, 800, 32, 8, 8, true, nil, nil)
	testing.expect(t, got == win.LRESULT(win.HTCAPTION), "maximized blank chrome should remain a drag region")
}
