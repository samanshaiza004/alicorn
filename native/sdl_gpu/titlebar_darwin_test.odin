#+build darwin

package alicorn_sdl_gpu

import "core:testing"
import NS "core:sys/darwin/Foundation"
import alicorn "../../runtime"
import "vendor:sdl3"

@(test)
test_darwin_titlebar_fixture_callbacks_ignore_ordinary_application_state :: proc(t: ^testing.T) {
	sentinel := u64(42)
	application := Application{state=rawptr(&sentinel)}
	native_state: Darwin_Menu_State
	menu := Native_Menu_Runtime{application=&application, platform_data=rawptr(&native_state)}
	native_darwin_titlebar_fixture_note_fullscreen(&menu, .WINDOW_ENTER_FULLSCREEN)
	testing.expect(t, sentinel == 42 && !native_darwin_titlebar_fixture_exit_fullscreen(&menu),
		"fixture-only callbacks must not cast or mutate an ordinary app's state during native fullscreen events")
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
		interactive=[2]alicorn.Rect{{94, 0, 500, 48}, {20, 64, 280, 32}},
		interactive_count=2,
		drag_regions=[1]alicorn.Rect{{594, 0, 160, 48}},
		drag_region_count=1,
	}
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
