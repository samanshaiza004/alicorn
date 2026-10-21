#+build darwin

package alicorn_sdl_gpu

import "base:intrinsics"
import "core:fmt"
import NS "core:sys/darwin/Foundation"
import alicorn "../../runtime"
import "vendor:sdl3"

// Opt-in desktop regression: exercise the same native geometry adapter and
// ordinary fixture builder without requiring GPU presentation or a human click.
// Its bounded event pumping belongs only to --geometry-check, never normal idle.
native_darwin_titlebar_geometry_check :: proc() -> bool {
	configure_platform_activation()
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("titlebar check SDL initialization failed") }
	defer sdl3.Quit()
	window := sdl3.CreateWindow("Alicorn titlebar geometry check", 900, 560, {.HIDDEN, .RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil { fail("titlebar check window creation failed") }
	defer sdl3.DestroyWindow(window)
	app := Menu_Fixture_State{titlebar_fixture=true, titlebar_header_height=TITLEBAR_FIXTURE_HEADER_HEIGHT, titlebar_tab_order={1, 2}, titlebar_selected_tab=1}
	menus := [1]Application_Menu{{label="View"}}
	application := Application{state=rawptr(&app), menus=menus[:]}
	menu := Native_Menu_Runtime{window=window, application=&application}
	if !native_menu_prepare(&menu) { fail("titlebar check native setup failed") }
	defer native_menu_destroy(&menu)
	if !native_darwin_titlebar_fixture_prepare(&menu) { fail("titlebar check style setup failed") }
	metrics: Window_Metrics
	if !read_window_metrics(window, &metrics) { fail("titlebar check window metrics unavailable") }
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)})
	defer alicorn.destroy_runtime(&rt)
	if !native_load_default_fonts(&rt) { fail("titlebar check fonts unavailable") }
	menu.runtime = &rt
	state := cast(^Darwin_Menu_State)menu.platform_data
	_ = sdl3.ShowWindow(window)
	native_darwin_titlebar_check_pump(&menu, 250)
	initial := native_darwin_titlebar_check_snapshot(&menu, &rt, &app, "windowed-before")
	passed := initial.header.h == TITLEBAR_FIXTURE_HEADER_HEIGHT && initial.body.h > 100

	for cycle in 0..<2 {
		if cycle == 0 {
			button := intrinsics.objc_send(^NS.View, state.window, "standardWindowButton:", NS.UInteger(2))
			intrinsics.objc_send(nil, button, "performClick:", state.window)
		} else {
			// Public AppKit menu action: exercise a second entry/exit without
			// recreating the native window or the retained runtime.
			intrinsics.objc_send(nil, state.window, "toggleFullScreen:", state.window)
		}
		native_darwin_titlebar_check_pump(&menu, 1800)
		fullscreen := native_darwin_titlebar_check_snapshot(&menu, &rt, &app, "fullscreen")
		fullscreen_ok := fullscreen.fullscreen && fullscreen.header.h == TITLEBAR_FIXTURE_HEADER_HEIGHT && fullscreen.body.h > 100
		if !fullscreen_ok { fmt.println("titlebar_geometry_check FAIL fullscreen header/body", fullscreen) }
		passed = passed && fullscreen_ok

		_ = native_darwin_titlebar_fixture_exit_fullscreen(&menu)
		native_darwin_titlebar_check_pump(&menu, 1800)
		restored := native_darwin_titlebar_check_snapshot(&menu, &rt, &app, "windowed-after")
		restore_ok := !restored.fullscreen && restored.root.w == initial.root.w && restored.root.h == initial.root.h
		if !restore_ok { fmt.println("titlebar_geometry_check FAIL restore size", "before", initial.root, "after", restored) }
		passed = passed && restore_ok
	}
	_ = sdl3.SetWindowSize(window, 720, 480)
	_ = sdl3.SyncWindow(window)
	native_darwin_titlebar_check_pump(&menu, 100)
	resized := native_darwin_titlebar_check_snapshot(&menu, &rt, &app, "resized")
	resize_ok := resized.root.w == 720 && resized.root.h == 480 && resized.header.h == TITLEBAR_FIXTURE_HEADER_HEIGHT && resized.body.h > 100
	passed = passed && resize_ok
	if !resize_ok { fmt.println("titlebar_geometry_check FAIL resize", resized) }
	if passed { fmt.println("titlebar_geometry_check PASS") }
	return passed
}

native_darwin_titlebar_check_pump :: proc(menu: ^Native_Menu_Runtime, duration_ms: u64) {
	deadline := sdl3.GetTicks()+duration_ms
	for sdl3.GetTicks() < deadline {
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .WINDOW_ENTER_FULLSCREEN, .WINDOW_LEAVE_FULLSCREEN:
				native_darwin_titlebar_fixture_note_fullscreen(menu, event.type)
				fmt.println("titlebar_geometry_check event", event.type)
			case:
			}
		}
		sdl3.Delay(10)
	}
}

Darwin_Titlebar_Check_Layout :: struct {root, header, body: alicorn.Rect, fullscreen: bool}

native_darwin_titlebar_check_snapshot :: proc(
	menu: ^Native_Menu_Runtime, rt: ^alicorn.Runtime, app: ^Menu_Fixture_State, phase: string,
) -> Darwin_Titlebar_Check_Layout {
	_ = native_darwin_titlebar_fixture_refresh(menu)
	metrics: Window_Metrics
	if !read_window_metrics(menu.window, &metrics) { fail("titlebar check snapshot metrics unavailable") }
	rt.viewport = alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)}
	alicorn.invalidate_root(rt, "native titlebar geometry check phase")
	_ = menu_fixture_titlebar_build(app, rt, metrics.logical_width, metrics.logical_height)
	root, _ := alicorn.node_info(rt, app.titlebar_root_node)
	header, _ := alicorn.node_info(rt, app.titlebar_header_node)
	body, _ := alicorn.node_info(rt, app.titlebar_body_node)
	state := cast(^Darwin_Menu_State)menu.platform_data
	content_view := NS.Window_contentView(state.window)
	style_mask := intrinsics.objc_send(NS.WindowStyleMask, state.window, "styleMask")
	safe_area: sdl3.Rect
	_ = sdl3.GetWindowSafeArea(menu.window, &safe_area)
	fmt.println("titlebar_geometry_check snapshot", phase,
		"style", style_mask, "window-frame", NS.Window_frame(state.window),
		"content-bounds", NS.View_bounds(content_view), "content-frame", intrinsics.objc_send(NS.Rect, content_view, "frame"),
		"SDL-logical", metrics.logical_width, metrics.logical_height, "SDL-pixels", metrics.pixel_width, metrics.pixel_height,
		"safe-area", safe_area, "controls", app.titlebar_control_bounds, "header-height", app.titlebar_header_height,
		"root", root.bounds, "header", header.bounds, "body", body.bounds)
	return Darwin_Titlebar_Check_Layout{root.bounds, header.bounds, body.bounds, NS.WindowStyleFlag.FullScreen in style_mask}
}
