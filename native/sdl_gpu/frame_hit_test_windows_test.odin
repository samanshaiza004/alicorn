#+build windows

package alicorn_sdl_gpu

import "core:testing"
import "core:encoding/json"
import win "core:sys/windows"
import alicorn "../../runtime"
import "vendor:sdl3"

@(test)
test_integrated_topmost_window_mouse_entry_preserves_native_rectangle :: proc(t: ^testing.T) {
	if !sdl3.Init(sdl3.INIT_VIDEO) { testing.expect(t, false, "SDL video initialization failed"); return }
	defer sdl3.Quit()
	window := sdl3.CreateWindow("Alicorn topmost entry regression", 480, 320, {.HIDDEN, .RESIZABLE})
	if window == nil { testing.expect(t, false, "hidden SDL window creation failed"); return }
	defer sdl3.DestroyWindow(window)
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 480, 320})
	defer alicorn.destroy_runtime(&rt)
	menus := [1]Application_Menu{{label="Tool"}}
	app := Application{title="Alicorn topmost entry regression", menus=menus[:], window_decorations=.Integrated_Title_Bar}
	menu := Native_Menu_Runtime{window=window, application=&app, runtime=&rt}
	defer native_menu_destroy(&menu)
	if !native_menu_prepare(&menu) { testing.expect(t, false, "integrated frame initialization failed"); return }
	state := cast(^Win32_Menu_State)menu.platform_data
	if !sdl3.SetWindowAlwaysOnTop(window, true) { testing.expect(t, false, "topmost transition failed"); return }
	_ = win.SendMessageW(state.hwnd, win.WM_MOUSELEAVE, 0, 0)
	before: win.RECT
	if !win.GetWindowRect(state.hwnd, &before) { testing.expect(t, false, "native window rectangle unavailable"); return }
	keyboard_focus := sdl3.GetKeyboardFocus()
	for i in 0..<8 {
		point := win.LPARAM(uintptr(120+i) | uintptr(120)<<16)
		_ = win.SendMessageW(state.hwnd, win.WM_MOUSEMOVE, 0, point)
		testing.expect(t, sdl3.GetMouseFocus() == window, "the real SDL mouse-entry path must be exercised")
		after: win.RECT
		_ = win.GetWindowRect(state.hwnd, &after)
		testing.expect_value(t, after, before)
		testing.expect(t, sdl3.GetKeyboardFocus() == keyboard_focus, "mouse entry must not activate the window")
		_ = win.SendMessageW(state.hwnd, win.WM_MOUSELEAVE, 0, 0)
	}
	testing.expect_value(t, state.window_geometry.topmost_promotions_preserved, u64(8))
	// Native caption dragging and explicit placement use ordinary move requests.
	move_flags := win.UINT(win.SWP_NOSIZE | win.SWP_NOACTIVATE | win.SWP_NOZORDER)
	testing.expect(t, win.SetWindowPos(state.hwnd, nil, before.left+40, before.top+20, 0, 0, move_flags) != false)
	before.left += 40; before.right += 40; before.top += 20; before.bottom += 20
	moved: win.RECT
	_ = win.GetWindowRect(state.hwnd, &moved)
	testing.expect_value(t, moved, before)
	resize_flags := win.UINT(win.SWP_NOMOVE | win.SWP_NOACTIVATE | win.SWP_NOZORDER)
	testing.expect(t, win.SetWindowPos(state.hwnd, nil, 0, 0, before.right-before.left+40, before.bottom-before.top+30, resize_flags) != false)
	before.right += 40; before.bottom += 30
	resized: win.RECT
	_ = win.GetWindowRect(state.hwnd, &resized)
	testing.expect_value(t, resized, before)
	topmost_states := [2]bool{false, true}
	for topmost in topmost_states {
		testing.expect(t, sdl3.SetWindowAlwaysOnTop(window, topmost))
		for i in 0..<8 {
			_ = win.SendMessageW(state.hwnd, win.WM_MOUSEMOVE, 0, win.LPARAM(uintptr(140+i) | uintptr(140)<<16))
			after: win.RECT
			_ = win.GetWindowRect(state.hwnd, &after)
			testing.expect_value(t, after, before)
			_ = win.SendMessageW(state.hwnd, win.WM_MOUSELEAVE, 0, 0)
		}
	}
	testing.expect_value(t, state.window_geometry.topmost_promotions_preserved, u64(16))
	// The same capture exports two independent native identities and viewports,
	// plus the child HWND history that was absent from the original capture.
	primary_window := sdl3.CreateWindow("Primary diagnostics fixture", 800, 600, {.HIDDEN})
	if primary_window == nil { testing.expect(t, false, "primary fixture creation failed"); return }
	defer sdl3.DestroyWindow(primary_window)
	primary_rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 600})
	defer alicorn.destroy_runtime(&primary_rt)
	primary_metrics, child_metrics: Window_Metrics
	_ = read_window_metrics(primary_window, &primary_metrics)
	_ = read_window_metrics(window, &child_metrics, menu.content_inset_top)
	child := Native_Secondary_Window{active=true, window=window, runtime=&rt, metrics=child_metrics, native_menu=menu}
	manager := Native_Secondary_Window_Manager{child=&child}
	serialized := native_window_diagnostics_json(primary_window, primary_metrics, &primary_rt, nil, &manager)
	defer delete(serialized)
	value, err := json.parse_string(serialized)
	if err != .None { testing.expect(t, false, "window inventory must be valid JSON"); return }
	defer json.destroy_value(value)
	root := value.(json.Object)
	primary := root["primary"].(json.Object)
	secondary := root["secondary"].(json.Object)
	testing.expect(t, primary["sdl_window_id"].(json.Float) != secondary["sdl_window_id"].(json.Float))
	primary_runtime := primary["runtime"].(json.Object)
	secondary_runtime := secondary["runtime"].(json.Object)
	primary_viewport := primary_runtime["viewport"].(json.Object)
	secondary_viewport := secondary_runtime["viewport"].(json.Object)
	testing.expect_value(t, primary_viewport["width"].(json.Float), json.Float(800))
	testing.expect_value(t, secondary_viewport["width"].(json.Float), json.Float(480))
	native := secondary["win32"].(json.Object)
	testing.expect_value(t, native["topmost_promotions_preserved"].(json.Float), json.Float(16))
	testing.expect(t, len(native["position_history"].(json.Array)) > 0)
}

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
test_cancelled_native_menu_popup_exits_mode_and_uses_current_hover :: proc(t: ^testing.T) {
	state := Win32_Menu_State{menu_mode=true, active_menu=1, hovered=1}
	win32_menu_finish_popup(&state, 0, -1)
	closed := !state.menu_mode && state.active_menu == -1 && state.hovered == -1

	state = Win32_Menu_State{menu_mode=true, active_menu=1, hovered=1}
	win32_menu_finish_popup(&state, 0, 2)
	hover_restored := !state.menu_mode && state.active_menu == -1 && state.hovered == 2
	testing.expect(t, closed && hover_restored,
		"canceling a native popup should leave menu mode immediately and keep only the actual pointer hover")
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
	x, y := win32_screen_point_to_client_pixels(-1500, -200, -1600, -300)
	testing.expect(t, x == 100 && y == 100,
		"signed screen coordinates on a monitor left/above the primary display should map to positive window coordinates")

	x, y = win32_screen_point_to_client_pixels(150, 301, 0, 300)
	testing.expect(t, x == 150 && y == 1,
		"physical hit coordinates must preserve one-pixel resize boundaries at fractional DPI")
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
test_caption_button_bounds_convert_to_client_physical_coordinates :: proc(t: ^testing.T) {
	window_bounds := win.RECT{left=1380, top=0, right=1515, bottom=40}
	window_rect := win.RECT{left=-1500, top=400, right=300, bottom=1400}
	got := win32_caption_bounds_to_client_pixels(window_bounds, window_rect, -1492, 408)
	testing.expect(t, got.left == 1372 && got.top == -8 && got.right == 1507 && got.bottom == 32,
		"DWM outer-frame offsets should translate to physical client pixels without DPI rounding")
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
test_caption_band_normalizes_maximized_dwm_offsets_and_shares_hit_bounds :: proc(t: ^testing.T) {
	dpis := [4]u32{96,120,144,192}
	states := [2]bool{false,true}
	densities := [2]f32{1,2}
	for dpi in dpis {
		scale := f32(dpi)/96
		width := i32(native_pixel_edge(1200, scale))
		height := i32(native_pixel_edge(32, scale))
		edge := i32(native_pixel_edge(8, scale))
		raw := win.RECT{win.LONG(width-i32(native_pixel_edge(138,scale))-edge), -win.LONG(edge), win.LONG(width-edge), win.LONG(height-edge)}
		for maximized in states {
			controls := win32_caption_layout_controls(raw, true, width, height, dpi, maximized)
			for control, i in controls {
				testing.expect(t, control.bounds.top == (0 if maximized else 1) && control.bounds.bottom == win.LONG(height),
					"all caption controls must share the visible band even when DWM reports negative Y")
				x := i32((control.bounds.left+control.bounds.right)/2)
				y := i32((control.bounds.top+control.bounds.bottom)/2)
				testing.expect_value(t, win32_integrated_frame_hit_test(x,y,width,800,height,edge,edge,maximized,controls[:],nil), control.hit_test)
				for density in densities {
					visual := win32_chrome_rect_to_window(control.bounds,density)
					x0,y0,x1,y1 := logical_to_pixel_bounds(visual,density,density)
					testing.expect(t, x0 == int(control.bounds.left) && y0 == int(control.bounds.top) && x1 == int(control.bounds.right) && y1 == int(control.bounds.bottom),
						"paint must round-trip to canonical physical hit geometry independently of SDL density")
				}
				if i == 2 && maximized {
					testing.expect_value(t, win32_integrated_frame_hit_test(width-1,0,width,800,height,edge,edge,true,controls[:],nil), win.LRESULT(win.HTCLOSE))
				}
			}
			if !maximized {
				testing.expect_value(t, win32_integrated_frame_hit_test(width-1,height/2,width,800,height,edge,edge,false,controls[:],nil), win.LRESULT(win.HTRIGHT))
				testing.expect_value(t, win32_integrated_frame_hit_test(width-edge-20,0,width,800,height,edge,edge,false,controls[:],nil), win.LRESULT(win.HTTOP))
			}
		}
	}
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
test_integrated_frame_hit_test_routes_windows_app_tabs_and_drag_gaps :: proc(t: ^testing.T) {
	labels := [?]win.RECT{{left=8, top=0, right=230, bottom=48}}
	regions := [?]Win32_Chrome_Hit_Region{
		{bounds=win.RECT{left=250, top=0, right=650, bottom=48}, kind=.Interactive},
		{bounds=win.RECT{left=650, top=0, right=960, bottom=48}, kind=.Window_Drag},
	}
	caption := [1]Win32_Caption_Control{{
		bounds=win.RECT{left=960, top=0, right=1000, bottom=48},
		hit_test=win.LRESULT(win.HTCLOSE),
	}}
	testing.expect_value(t, win32_integrated_frame_hit_test(80, 20, 1000, 700, 48, 8, 8, false, caption[:], labels[:], regions[:], true), win.LRESULT(win.HTCLIENT))
	testing.expect_value(t, win32_integrated_frame_hit_test(400, 20, 1000, 700, 48, 8, 8, false, caption[:], labels[:], regions[:], true), win.LRESULT(win.HTCLIENT))
	testing.expect_value(t, win32_integrated_frame_hit_test(800, 20, 1000, 700, 48, 8, 8, false, caption[:], labels[:], regions[:], true), win.LRESULT(win.HTCAPTION))
	testing.expect_value(t, win32_integrated_frame_hit_test(980, 20, 1000, 700, 48, 8, 8, false, caption[:], labels[:], regions[:], true), win.LRESULT(win.HTCLOSE))
	testing.expect(t,
		win32_integrated_frame_hit_test(240, 20, 1000, 700, 48, 8, 8, false, caption[:], labels[:], regions[:], true) == win.LRESULT(win.HTCLIENT),
		"unregistered pixels in an app-owned header must remain ordinary client input")
	testing.expect(t,
		win32_integrated_frame_hit_test(500, 80, 1000, 700, 48, 8, 8, false, caption[:], labels[:], regions[:], true) == win.LRESULT(win.HTCLIENT),
		"the editor below the integrated band must remain client input")
}

@(test)
test_integrated_frame_gesture_owner_survives_titlebar_boundary_crossing :: proc(t: ^testing.T) {
	labels := [?]win.RECT{{left=8, top=0, right=230, bottom=48}}
	regions := [?]Win32_Chrome_Hit_Region{
		{bounds=win.RECT{left=250, top=0, right=650, bottom=48}, kind=.Interactive},
		{bounds=win.RECT{left=650, top=0, right=960, bottom=48}, kind=.Window_Drag},
	}
	controls := [1]Win32_Caption_Control{{bounds=win.RECT{left=960, top=0, right=1000, bottom=48}, hit_test=win.LRESULT(win.HTMAXBUTTON)}}
	app_owner := win32_integrated_frame_hit_test(
		800, 20, 1000, 700, 48, 8, 8, false, controls[:], labels[:], regions[:], true, .Alicorn)
	window_owner := win32_integrated_frame_hit_test(
		400, 20, 1000, 700, 48, 8, 8, false, controls[:], labels[:], regions[:], true, .Window)
	menu_owner := win32_integrated_frame_hit_test(
		800, 20, 1000, 700, 48, 8, 8, false, controls[:], labels[:], regions[:], true, .Native_Menu)
	testing.expect(t, app_owner == win.LRESULT(win.HTCLIENT),
		"a tab gesture must never turn into a window drag when it crosses blank header space")
	testing.expect(t, window_owner == win.LRESULT(win.HTCAPTION),
		"a window drag remains caption-owned while crossing interactive tab geometry")
	testing.expect(t, menu_owner == win.LRESULT(win.HTCLIENT),
		"native-menu routing must keep the pointer in the client until the popup finishes")
	testing.expect(t,
		win32_integrated_frame_resolve_gesture_hit_test(app_owner, .Alicorn, true, win.LRESULT(win.HTCLOSE)) == win.LRESULT(win.HTCLIENT),
		"DWM must not steal a latched tab drag when it crosses the caption controls")
	testing.expect(t,
		win32_integrated_frame_resolve_gesture_hit_test(window_owner, .Window, true, win.LRESULT(win.HTMAXBUTTON)) == win.LRESULT(win.HTCAPTION),
		"the window manager must retain the initial blank-header drag owner")
	testing.expect(t,
		win32_integrated_frame_resolve_gesture_hit_test(win.LRESULT(win.HTCLIENT), .None, true, win.LRESULT(win.HTMAXBUTTON)) == win.LRESULT(win.HTMAXBUTTON),
		"Windows Snap Layout hover must retain DWM's native maximize classification")
}

@(test)
test_integrated_frame_hit_test_keeps_editor_client_owned_when_dwm_handles :: proc(t: ^testing.T) {
	client := win.LRESULT(win.HTCLIENT)
	caption := win.LRESULT(win.HTCAPTION)
	resize := win.LRESULT(win.HTTOPLEFT)
	close_button := win.LRESULT(win.HTCLOSE)

	testing.expect(t,
		win32_integrated_frame_resolve_hit_test(client, true, caption) == client,
		"DWM must not turn editor client pixels into a caption drag region")
	testing.expect(t,
		win32_integrated_frame_resolve_hit_test(client, true, resize) == client,
		"DWM must not turn editor client pixels into a resize edge")
	testing.expect(t,
		win32_integrated_frame_resolve_hit_test(caption, true, resize) == caption,
		"Alicorn's caption drag geometry must remain authoritative outside system buttons")
	testing.expect(t,
		win32_integrated_frame_resolve_hit_test(resize, true, caption) == resize,
		"Alicorn's resize geometry must remain authoritative")
	testing.expect(t,
		win32_integrated_frame_resolve_hit_test(client, true, close_button) == close_button,
		"DWM may still supply a standard caption-button target when local geometry is unavailable")
}

@(test)
test_integrated_frame_hit_test_maximized_does_not_expose_resize_edges :: proc(t: ^testing.T) {
	got := win32_integrated_frame_hit_test(1, 200, 1000, 800, 32, 8, 8, true, nil, nil)
	testing.expect(t, got == win.LRESULT(win.HTCLIENT), "maximized frame should not report resize borders")
	got = win32_integrated_frame_hit_test(200, 12, 1000, 800, 32, 8, 8, true, nil, nil)
	testing.expect(t, got == win.LRESULT(win.HTCAPTION), "maximized blank chrome should remain a drag region")
}
