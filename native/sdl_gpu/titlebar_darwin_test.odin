#+build darwin

package alicorn_sdl_gpu

import "core:testing"
import NS "core:sys/darwin/Foundation"
import alicorn "../../runtime"
import "vendor:sdl3"

@(test)
test_darwin_titlebar_regions_follow_real_tabs_and_empty_space :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 900, 560})
	defer alicorn.destroy_runtime(&rt)
	app := Menu_Fixture_State{titlebar_fixture=true,
		titlebar_header_height=TITLEBAR_FIXTURE_HEADER_HEIGHT,
		titlebar_control_start_x=81, titlebar_tab_order={1, 2}, titlebar_selected_tab=1}
	application := Application{state=rawptr(&app), window_chrome_layout=menu_fixture_window_chrome_layout}
	native_state: Darwin_Menu_State
	native_state.titlebar.active = true
	native_state.titlebar.metrics = Window_Chrome_Metrics{header={0, 0, 900, 560}}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt, platform_data=rawptr(&native_state)}
	for remaining in 0..<3 {
		if remaining > 0 { app.titlebar_closed_tabs[remaining-1] = true }
		alicorn.invalidate_root(&rt, "fixture close test")
		_ = menu_fixture_titlebar_build(&app, &rt, 900, 560)
		_ = menu_fixture_titlebar_build(&app, &rt, 900, 560)
		native_darwin_titlebar_sync_layout(&menu)
		geometry := native_state.titlebar.geometry
		expected_width := f32(2-remaining)*180
		testing.expect(t, geometry.header.h == TITLEBAR_FIXTURE_HEADER_HEIGHT &&
			geometry.interactive_count == (1 if expected_width > 0 else 0) && app.titlebar_tab_width == expected_width,
			"only the actual bounded tab strip should be client-interactive, including after closing every tab")
		testing.expect(t, geometry.drag_region_count == 1 &&
			geometry.drag_regions[0] == alicorn.Rect{81+expected_width, 0, 819-expected_width, TITLEBAR_FIXTURE_HEADER_HEIGHT},
			"the explicit blank drag region should consume the actual remainder, not a fixed tail")
	}
}

@(test)
test_darwin_titlebar_narrow_width_keeps_selected_tab_visible :: proc(t: ^testing.T) {
	widths := [2]int{400, 320}
	for width in widths {
		rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(width), 560})
		defer alicorn.destroy_runtime(&rt)
		app := Menu_Fixture_State{titlebar_fixture=true,
			titlebar_header_height=TITLEBAR_FIXTURE_HEADER_HEIGHT,
			titlebar_control_start_x=81, titlebar_tab_order={1, 2}, titlebar_selected_tab=2}
		application := Application{state=rawptr(&app), window_chrome_layout=menu_fixture_window_chrome_layout}
		native_state: Darwin_Menu_State
		native_state.titlebar.active = true
		native_state.titlebar.metrics = Window_Chrome_Metrics{header={0, 0, f32(width), 560}}
		menu := Native_Menu_Runtime{application=&application, runtime=&rt, platform_data=rawptr(&native_state)}
		for _ in 0..<4 { _ = menu_fixture_titlebar_build(&app, &rt, width, 560) }
		native_darwin_titlebar_sync_layout(&menu)
		geometry := native_state.titlebar.geometry
		testing.expect(t, geometry.interactive_count == 1 &&
			geometry.interactive[0] == alicorn.Rect{81, 0, f32(width-81), TITLEBAR_FIXTURE_HEADER_HEIGHT},
			"narrow strips must report the width they actually give the tab component")
		selected, found := alicorn.node_by_key(&rt, alicorn.key_string("macos-titlebar-tab-two"), .Button)
		info, ok := alicorn.node_info(&rt, selected)
		testing.expect(t, found && ok && info.bounds.x >= 81 && info.bounds.x+info.bounds.w <= f32(width) && !rt.invalidated,
			"shrinking or overflowing tabs should keep the selected tab and close slot inside the window and settle")
		left, overflow := alicorn.node_by_key(&rt, alicorn.key_u64(2), .Button)
		_ = left
		testing.expect(t, overflow == (width == 320), "overflow controls should appear only after tabs reach their minimum width")
	}
}

@(test)
test_darwin_titlebar_regions_refresh_after_retained_only_split_layout :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 900, 560})
	defer alicorn.destroy_runtime(&rt)
	app: Menu_Fixture_State
	app.titlebar_fixture = true
	application := Application{state=rawptr(&app), window_chrome_layout=menu_fixture_window_chrome_layout}
	native_state: Darwin_Menu_State
	native_state.titlebar.active = true
	native_state.titlebar.metrics = Window_Chrome_Metrics{header={0, 0, 900, 560}}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt, platform_data=rawptr(&native_state)}
	divider_id: alicorn.Node_ID
	for _ in 0..<2 {
		ui, ready := alicorn.begin_frame(&rt)
		testing.expect(t, ready)
		split := alicorn.split_begin(&ui, alicorn.key_string("titlebar-layout-split"), .Horizontal, 400, 200, 200)
		_ = alicorn.split_first_begin(&ui, split)
		app.titlebar_header_node = alicorn.container_begin(&ui, .Container,
			style=alicorn.layout_style(.Row, height=32, gap=0, clip=true))
		items := [1]alicorn.Tab_Bar_Item{{key=alicorn.key_u64(1), label="Tab", selected=true}}
		options := alicorn.DEFAULT_TAB_BAR_OPTIONS
		options.presentation = .Compact
		options.height = 32
		app.titlebar_tabs_region_node = alicorn.container_begin(&ui, .Container,
			style=alicorn.layout_style(.Row, width=180, height=32, clip=true))
		_ = alicorn.tab_bar(&ui, alicorn.key_string("macos-titlebar-tabs"), items[:], options,
			alicorn.layout_style(.Row, width=180, height=32))
		alicorn.container_end(&ui)
		app.titlebar_blank_node = alicorn.container_begin(&ui, .Container, style=alicorn.layout_style(.Row, grow=1))
		alicorn.container_end(&ui)
		alicorn.container_end(&ui)
		alicorn.split_first_end(&ui, split)
		divider_id = alicorn.split_divider(&ui, split)
		_ = alicorn.split_second_begin(&ui, split)
		alicorn.split_second_end(&ui, split)
		alicorn.split_end(&ui, split)
		alicorn.end_frame(&ui)
	}
	native_darwin_titlebar_sync_layout(&menu)
	before := native_state.titlebar.geometry
	stats := rt.stats
	divider, found := alicorn.node_info(&rt, divider_id)
	testing.expect(t, found && before.header.w == 400 && before.drag_regions[0].w == 220)
	x, y := divider.bounds.x+divider.bounds.w*0.5, divider.bounds.y+40
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Down, x=x, y=y, button=1})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Move, x=x+100, y=y})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Up, x=x+100, y=y, button=1})
	_ = alicorn.set_presentation_scale(&rt, 1.25, 1.25)
	presentation, pending := alicorn.begin_presentation_frame(&rt)
	testing.expect(t, pending, "split resizing should request retained layout without an application build")
	if pending { alicorn.end_presentation_frame(&presentation) }
	native_darwin_titlebar_sync_layout(&menu)
	after := native_state.titlebar.geometry
	testing.expect(t, after.header.w == 500 && after.drag_regions[0].w == 320 &&
		after.interactive[0] == before.interactive[0],
		"retained split layout should move the blank drag boundary with the pointer stationary, including fractional scaling")
	testing.expect(t, rt.stats.descriptions_emitted == stats.descriptions_emitted && rt.stats.frames_built == stats.frames_built,
		"publishing host hit regions must not request or emit an application description")
}

@(test)
test_darwin_titlebar_metrics_delivery_does_not_inspect_ordinary_application_state :: proc(t: ^testing.T) {
	sentinel := u64(42)
	application := Application{state=rawptr(&sentinel)}
	native_state: Darwin_Menu_State
	native_state.titlebar.metrics_valid = true
	menu := Native_Menu_Runtime{application=&application, platform_data=rawptr(&native_state)}
	native_darwin_titlebar_deliver_metrics(&menu)
	testing.expect(t, sentinel == 42 && !native_darwin_titlebar_exit_fullscreen(&menu),
		"native chrome callbacks must not cast or mutate an ordinary app's state when the opt-in is inactive")
}

@(test)
test_darwin_titlebar_layout_does_not_depend_on_fullscreen_control_coordinates :: proc(t: ^testing.T) {
	controls := [3]alicorn.Rect{{9, 877, 14, 14}, {32, 877, 14, 14}, {55, 877, 14, 14}}
	geometry, start_x := darwin_titlebar_resolve_geometry(
		alicorn.Rect{0, 0, 1440, 900}, alicorn.Rect{0, 0, 1440, 900}, 44, controls[:])
	testing.expect(t, geometry.header.h == 44 && geometry.native_control_count == 0 && start_x == 0,
		"off-header fullscreen toolbar controls must not enlarge the application header or reserve tab space")
	controls[0] = alicorn.Rect{9, 41, 14, 14}
	geometry, start_x = darwin_titlebar_resolve_geometry(
		alicorn.Rect{0, 0, 1440, 900}, alicorn.Rect{0, 32, 1440, 868}, 44, controls[:])
	testing.expect(t, geometry.header.y == 32 && geometry.header.h == 44 &&
		geometry.native_control_count == 1 && start_x == 35,
		"the native safe area offsets the independently sized header, while only actual control intersections reserve space")
}

@(test)
test_darwin_titlebar_does_not_mutate_style_mask_during_fullscreen :: proc(t: ^testing.T) {
	testing.expect(t,
		darwin_titlebar_should_add_full_size_content_view(false, false, true),
		"the titlebar style should be installed while the window is in its normal state")
	testing.expect(t,
		!darwin_titlebar_should_add_full_size_content_view(false, true, true),
		"AppKit's style mask must not be changed during a fullscreen transition")
	testing.expect(t,
		!darwin_titlebar_should_add_full_size_content_view(false, false, false),
		"fullscreen transition callbacks must defer style-mask changes even before AppKit sets its fullscreen bit")
	testing.expect(t,
		!darwin_titlebar_should_add_full_size_content_view(true, false, true),
		"an already configured window should not need another style-mask mutation")
}

@(test)
test_darwin_titlebar_button_bounds_convert_to_window_logical_points :: proc(t: ^testing.T) {
	content_bounds := NS.Rect{origin={0, 0}, size={900, 600}}
	appkit_button := NS.Rect{origin={18.25, 570}, size={14, 14}}
	logical := darwin_titlebar_rect_to_window_logical(appkit_button, content_bounds, false)
	testing.expect(t, logical.x == 18 && logical.y == 16 && logical.w == 15 && logical.h == 14,
		"AppKit fractional button bounds should convert outward to unscaled SDL top-left logical points")

	flipped_bounds := NS.Rect{origin={4, 8}, size={900, 600}}
	flipped_button := NS.Rect{origin={24, 20}, size={14, 14}}
	flipped_logical := darwin_titlebar_rect_to_window_logical(flipped_button, flipped_bounds, true)
	testing.expect(t, flipped_logical.x == 20 && flipped_logical.y == 12,
		"flipped content views should preserve their top-left logical button coordinates")
}

@(test)
test_darwin_titlebar_pointer_prefers_the_native_event_coordinate :: proc(t: ^testing.T) {
	pointer := alicorn.Pointer_Event{kind=.Down, x=0, y=0}
	native_point := sdl3.Point{400, 19}
	translated := darwin_titlebar_pointer_use_hit_test_point(pointer, native_point, true)
	testing.expect(t,
		translated.x == 400 && translated.y == 19 && translated.kind == .Down,
		"titlebar pointer routing should use the exact AppKit point when SDL's queued coordinates are stale")

	unchanged := darwin_titlebar_pointer_use_hit_test_point(pointer, native_point, false)
	testing.expect(t,
		unchanged.x == 0 && unchanged.y == 0,
		"events without a native hit-test point should preserve the SDL coordinates")
}

@(test)
test_darwin_titlebar_pointer_samples_pair_native_points_with_sdl_events :: proc(t: ^testing.T) {
	samples: Darwin_Titlebar_Pointer_Samples
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{29, 321}, {})
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{400, 19}, {})
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{400, 19}, sdl3.BUTTON_LMASK)
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{400, 19}, {})
	_, move_ok := darwin_titlebar_pointer_sample_pop_matching(&samples, false)
	press, press_ok := darwin_titlebar_pointer_sample_pop_matching(&samples, true)
	release, release_ok := darwin_titlebar_pointer_sample_pop_matching(&samples, false)
	_, empty_ok := darwin_titlebar_pointer_sample_pop_matching(&samples, false)
	testing.expect(t,
		move_ok && press_ok && release_ok && !empty_ok &&
			press == sdl3.Point{400, 19} && release == sdl3.Point{400, 19},
		"pointer press should skip an unpaired initial hover sample and keep the native coordinates aligned with button state")
}

@(test)
test_darwin_titlebar_consumed_hit_test_samples_are_drained_and_release_owner :: proc(t: ^testing.T) {
	samples: Darwin_Titlebar_Pointer_Samples
	owner := Darwin_Titlebar_Gesture_Owner.Window
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{620, 22}, sdl3.BUTTON_LMASK)
	consumed_drag := darwin_titlebar_consume_hit_test_sample(&samples, &owner)
	owner_retained := owner == .Window
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{180, 22}, {})
	consumed_release := darwin_titlebar_consume_hit_test_sample(&samples, &owner)
	_, _, empty := darwin_titlebar_pointer_sample_pop_with_buttons(&samples)
	testing.expect(t,
		consumed_drag && owner_retained && consumed_release && owner == .None && !empty,
		"Cocoa-consumed pointer samples must be drained and a consumed release must clear gesture ownership")

	// A later ordinary client event must not consume coordinates left behind by
	// a mouse transition that Cocoa handled itself.
	darwin_titlebar_pointer_sample_push(&samples, sdl3.Point{400, 19}, {})
	point, found := darwin_titlebar_pointer_sample_pop_matching(&samples, false)
	testing.expect(t,
		found && point == sdl3.Point{400, 19} && samples.count == 0,
		"client pointer events must see the next unconsumed sample, not Cocoa's stale point")
}

@(test)
test_darwin_titlebar_hit_test_keeps_native_and_alicorn_gestures_in_the_client :: proc(t: ^testing.T) {
	geometry := Darwin_Titlebar_Geometry{
		header={0, 0, 900, 48},
		native_controls=[3]alicorn.Rect{{12, 10, 14, 14}, {34, 10, 14, 14}, {56, 10, 14, 14}},
		native_control_count=3,
		interactive_count=2,
		drag_region_count=1,
	}
	geometry.interactive[0] = alicorn.Rect{94, 0, 500, 48}
	geometry.interactive[1] = alicorn.Rect{20, 64, 280, 32}
	geometry.drag_regions[0] = alicorn.Rect{594, 0, 160, 48}
	owner := Darwin_Titlebar_Gesture_Owner.None

	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{40, 16}, sdl3.BUTTON_LMASK, &owner) == .NORMAL &&
			owner == .Native_Control,
		"native traffic-light bounds must remain AppKit-owned")
	_ = darwin_titlebar_hit_test(geometry, sdl3.Point{40, 16}, {}, &owner)
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{180, 22}, sdl3.BUTTON_LMASK, &owner) == .NORMAL &&
			owner == .Alicorn,
		"Alicorn tab and close controls must receive ordinary SDL input")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{620, 22}, sdl3.BUTTON_LMASK, &owner) == .NORMAL &&
			owner == .Alicorn,
		"an Alicorn tab drag must remain client-owned across the blank titlebar region")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{620, 22}, {}, &owner) == .NORMAL &&
			owner == .None,
		"the app gesture owner should clear on release")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{620, 22}, sdl3.BUTTON_LMASK, &owner) == .DRAGGABLE &&
			owner == .Window,
		"a press that begins in the explicitly blank titlebar region should be owned by the window")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{180, 22}, sdl3.BUTTON_LMASK, &owner) == .DRAGGABLE &&
			owner == .Window,
		"a window drag must remain native-owned when crossing an Alicorn tab")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{180, 70}, sdl3.BUTTON_LMASK, &owner) == .DRAGGABLE &&
			owner == .Window,
		"a window drag must stay owned outside the header until release")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{180, 22}, {}, &owner) == .NORMAL &&
			owner == .None,
		"releasing a window drag should clear the latched owner without starting another gesture")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{180, 70}, sdl3.BUTTON_LMASK, &owner) == .NORMAL &&
			owner == .Alicorn,
		"a text-field gesture outside the header must remain Alicorn-owned")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{620, 22}, sdl3.BUTTON_LMASK, &owner) == .NORMAL &&
			owner == .Alicorn,
		"an app gesture must keep Alicorn ownership when crossing into blank titlebar space")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{620, 22}, {}, &owner) == .NORMAL &&
			owner == .None,
		"the app gesture owner should clear on release")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{70, 22}, {}, &owner) == .NORMAL,
		"unregistered header gaps must not become implicit window-drag regions")
	testing.expect(t,
		darwin_titlebar_hit_test(geometry, sdl3.Point{620, 22}, {}, &owner) == .DRAGGABLE,
		"the explicit blank titlebar region should permit a native window drag")
	owner = .Window
	darwin_titlebar_gesture_cancel(&owner)
	testing.expect(t,
		owner == .None && darwin_titlebar_hit_test(geometry, sdl3.Point{180, 22}, sdl3.BUTTON_LMASK, &owner) == .NORMAL &&
			owner == .Alicorn,
		"cancellation must release the prior drag owner before another gesture can start")
}
