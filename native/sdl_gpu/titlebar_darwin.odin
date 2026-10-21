#+build darwin

package alicorn_sdl_gpu

import "base:runtime"
import "base:intrinsics"
import "core:c"
import "core:fmt"
import "core:math"
import NS "core:sys/darwin/Foundation"
import alicorn "../../runtime"
import "vendor:sdl3"

Darwin_Titlebar_Gesture_Owner :: enum u8 {
	None,
	Client,
	Alicorn,
	Native_Control,
	Window,
}

DARWIN_TITLEBAR_POINTER_SAMPLE_CAPACITY :: 64

Darwin_Titlebar_Pointer_Samples :: struct {
	points:  [DARWIN_TITLEBAR_POINTER_SAMPLE_CAPACITY]sdl3.Point,
	buttons: [DARWIN_TITLEBAR_POINTER_SAMPLE_CAPACITY]sdl3.MouseButtonFlags,
	head:    int,
	count:   int,
}

Darwin_Titlebar_Geometry :: struct {
	header:                 alicorn.Rect,
	native_controls:        [3]alicorn.Rect,
	native_control_count:   int,
	interactive:            [2]alicorn.Rect,
	interactive_count:     int,
	drag_regions:           [1]alicorn.Rect,
	drag_region_count:      int,
}

Darwin_Titlebar_Fixture_State :: struct {
	active:                     bool,
	geometry:                   Darwin_Titlebar_Geometry,
	gesture_owner:              Darwin_Titlebar_Gesture_Owner,
	hit_test_calls:              u64,
	draggable_hit_test_calls:    u64,
	consumed_window_events:      u64,
	window_style_reapplies:      u64,
	pointer_samples:            Darwin_Titlebar_Pointer_Samples,
	last_sdl_pointer_point:      sdl3.Point,
	last_sdl_pointer_valid:     bool,
}

darwin_titlebar_pointer_sample_push :: proc(
	samples: ^Darwin_Titlebar_Pointer_Samples,
	point: sdl3.Point,
	buttons: sdl3.MouseButtonFlags,
) {
	if samples == nil || samples.count >= len(samples.points) { return }
	index := (samples.head+samples.count) % len(samples.points)
	samples.points[index] = point
	samples.buttons[index] = buttons
	samples.count += 1
}

darwin_titlebar_pointer_sample_pop :: proc(samples: ^Darwin_Titlebar_Pointer_Samples) -> (point: sdl3.Point, ok: bool) {
	if samples == nil || samples.count <= 0 { return }
	point = samples.points[samples.head]
	samples.head = (samples.head+1) % len(samples.points)
	samples.count -= 1
	ok = true
	return
}

// SDL queues the corresponding pointer event after invoking Cocoa's hit-test
// callback, but an initial hover callback can have no SDL event. For press,
// drag, and release events, match by the native left-button snapshot and drop
// any earlier unpaired hover samples. This preserves the actual drag distance.
darwin_titlebar_pointer_sample_pop_matching :: proc(
	samples: ^Darwin_Titlebar_Pointer_Samples,
	left_down: bool,
) -> (point: sdl3.Point, ok: bool) {
	if samples == nil { return }
	for samples.count > 0 {
		index := samples.head
		point = samples.points[index]
		buttons := sdl3.MouseButtonFlag.LEFT in samples.buttons[index]
		samples.head = (samples.head+1) % len(samples.points)
		samples.count -= 1
		if buttons == left_down {
			ok = true
			return
		}
	}
	return
}

// AppKit frames are measured in points, in the view's coordinate direction.
// SDL uses top-left window-logical points. Expand fractional edges outward so
// a native control's exclusion cannot miss a pointer pixel at either edge.
darwin_titlebar_rect_to_window_logical :: proc(rect, content_bounds: NS.Rect, content_is_flipped: bool) -> alicorn.Rect {
	left := f32(rect.origin.x-content_bounds.origin.x)
	bottom_from_top := f32(content_bounds.origin.y+content_bounds.size.height-(rect.origin.y+rect.size.height))
	top := bottom_from_top
	if content_is_flipped {
		top = f32(rect.origin.y-content_bounds.origin.y)
	}
	right := left+f32(rect.size.width)
	bottom := top+f32(rect.size.height)
	left = f32(math.floor(f64(left)))
	top = f32(math.floor(f64(top)))
	right = f32(math.ceil(f64(right)))
	bottom = f32(math.ceil(f64(bottom)))
	return alicorn.Rect{left, top, max(right-left, 0), max(bottom-top, 0)}
}

darwin_titlebar_rect_contains :: proc(rect: alicorn.Rect, point: sdl3.Point) -> bool {
	x := f32(point[0])
	y := f32(point[1])
	return rect.w > 0 && rect.h > 0 &&
		x >= rect.x && y >= rect.y &&
		x < rect.x+rect.w && y < rect.y+rect.h
}

darwin_titlebar_should_add_full_size_content_view :: proc(
	has_full_size_content_view, fullscreen, allow_style_mask_change: bool,
) -> bool {
	// Mutating NSWindow's style mask while AppKit is entering/leaving fullscreen
	// can cancel the transition. Skip it for transition callbacks even if the
	// style-mask snapshot has not reported FullScreen yet.
	return allow_style_mask_change && !has_full_size_content_view && !fullscreen
}

// SDL's Cocoa backend asks on mouse-down, mouse-up, and pointer motion. Latch
// the first left-button owner so neither a tab drag nor a window move can be
// stolen by a later pointer crossing. The callback clears the owner on release;
// focus loss and teardown clear it explicitly as a fallback.
darwin_titlebar_hit_test :: proc(
	geometry: Darwin_Titlebar_Geometry,
	point: sdl3.Point,
	buttons: sdl3.MouseButtonFlags,
	owner: ^Darwin_Titlebar_Gesture_Owner,
) -> sdl3.HitTestResult {
	if owner == nil { return .NORMAL }
	left_down := sdl3.MouseButtonFlag.LEFT in buttons
	if owner^ != .None {
		if !left_down {
			owner^ = .None
			return .NORMAL
		}
		return .DRAGGABLE if owner^ == .Window else .NORMAL
	}
	if left_down {
		for i in 0..<min(max(geometry.native_control_count, 0), len(geometry.native_controls)) {
			if darwin_titlebar_rect_contains(geometry.native_controls[i], point) {
				owner^ = .Native_Control
				return .NORMAL
			}
		}
		for i in 0..<min(max(geometry.interactive_count, 0), len(geometry.interactive)) {
			if darwin_titlebar_rect_contains(geometry.interactive[i], point) {
				owner^ = .Alicorn
				return .NORMAL
			}
		}
		for i in 0..<min(max(geometry.drag_region_count, 0), len(geometry.drag_regions)) {
			if darwin_titlebar_rect_contains(geometry.drag_regions[i], point) {
				owner^ = .Window
				return .DRAGGABLE
			}
		}
		owner^ = .Client
		return .NORMAL
	}
	if !darwin_titlebar_rect_contains(geometry.header, point) { return .NORMAL }
	for i in 0..<min(max(geometry.native_control_count, 0), len(geometry.native_controls)) {
		if darwin_titlebar_rect_contains(geometry.native_controls[i], point) { return .NORMAL }
	}
	for i in 0..<min(max(geometry.interactive_count, 0), len(geometry.interactive)) {
		if darwin_titlebar_rect_contains(geometry.interactive[i], point) { return .NORMAL }
	}
	for i in 0..<min(max(geometry.drag_region_count, 0), len(geometry.drag_regions)) {
		if darwin_titlebar_rect_contains(geometry.drag_regions[i], point) { return .DRAGGABLE }
	}
	return .NORMAL
}

darwin_titlebar_gesture_cancel :: proc(owner: ^Darwin_Titlebar_Gesture_Owner) {
	if owner != nil { owner^ = .None }
}

darwin_titlebar_pointer_use_hit_test_point :: proc(
	pointer: alicorn.Pointer_Event,
	point: sdl3.Point,
	point_valid: bool,
) -> alicorn.Pointer_Event {
	result := pointer
	if point_valid {
		result.x = f32(point[0])
		result.y = f32(point[1])
	}
	return result
}

darwin_titlebar_native_button_bounds :: proc(
	window: ^NS.Window,
	content_view: ^NS.View,
	content_bounds: NS.Rect,
	content_is_flipped: bool,
	button_kind: NS.UInteger,
) -> (bounds: alicorn.Rect, ok: bool) {
	button := intrinsics.objc_send(^NS.View, window, "standardWindowButton:", button_kind)
	if button == nil { return }
	parent := intrinsics.objc_send(^NS.View, button, "superview")
	if parent == nil { return }
	frame := intrinsics.objc_send(NS.Rect, button, "frame")
	content_frame := intrinsics.objc_send(NS.Rect, content_view, "convertRect:fromView:", frame, parent)
	bounds = darwin_titlebar_rect_to_window_logical(content_frame, content_bounds, content_is_flipped)
	ok = bounds.w > 0 && bounds.h > 0
	return
}

darwin_titlebar_sdl_hit_test :: proc "c" (
	window: ^sdl3.Window,
	area: ^sdl3.Point,
	data: rawptr,
) -> sdl3.HitTestResult {
	context = runtime.default_context()
	if area == nil || data == nil { return .NORMAL }
	menu := cast(^Native_Menu_Runtime)data
	if menu.platform_data == nil { return .NORMAL }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar_fixture.active { return .NORMAL }
	state.titlebar_fixture.hit_test_calls += 1
	geometry := state.titlebar_fixture.geometry
	app: ^Menu_Fixture_State = nil
	if menu.application != nil && menu.application.state != nil {
		app = cast(^Menu_Fixture_State)menu.application.state
		geometry.header.w = app.titlebar_window_width
		geometry.header.h = app.titlebar_header_height
		geometry.interactive[0] = alicorn.Rect{
			app.titlebar_tab_start_x,
			0,
			app.titlebar_tab_width,
			app.titlebar_header_height,
		}
		geometry.interactive_count = 1
		geometry.drag_regions[0] = app.titlebar_drag_region
		geometry.drag_region_count = 1 if app.titlebar_drag_region.w > 0 else 0
	}
	buttons := sdl3.GetGlobalMouseState(nil, nil)
	state.titlebar_fixture.last_sdl_pointer_point = area^
	state.titlebar_fixture.last_sdl_pointer_valid = true
	darwin_titlebar_pointer_sample_push(&state.titlebar_fixture.pointer_samples, area^, buttons)
	result := darwin_titlebar_hit_test(geometry, area^, buttons, &state.titlebar_fixture.gesture_owner)
	if app != nil {
		app.titlebar_hit_test_count += 1
		app.titlebar_hit_x = int(area[0])
		app.titlebar_hit_y = int(area[1])
		app.titlebar_hit_result = result
	}
	if result == .DRAGGABLE { state.titlebar_fixture.draggable_hit_test_calls += 1 }
	return result
}

native_darwin_titlebar_fixture_translate_pointer :: proc(
	menu: ^Native_Menu_Runtime,
	pointer: alicorn.Pointer_Event,
	event: sdl3.Event,
) -> alicorn.Pointer_Event {
	if menu == nil || menu.platform_data == nil { return pointer }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar_fixture.active { return pointer }
	left_down := false
	match_buttons := true
	if event.type == .MOUSE_MOTION {
		left_down = sdl3.MouseButtonFlag.LEFT in event.motion.state
	} else if event.type == .MOUSE_BUTTON_DOWN {
		left_down = event.button.button == sdl3.BUTTON_LEFT
	} else if event.type != .MOUSE_BUTTON_UP {
		match_buttons = false
	}
	point, found := darwin_titlebar_pointer_sample_pop_matching(&state.titlebar_fixture.pointer_samples, left_down)
	if !match_buttons { point, found = darwin_titlebar_pointer_sample_pop(&state.titlebar_fixture.pointer_samples) }
	if !found {
		point = state.titlebar_fixture.last_sdl_pointer_point
		found = state.titlebar_fixture.last_sdl_pointer_valid
	}
	return darwin_titlebar_pointer_use_hit_test_point(
		pointer,
		point,
		found,
	)
}

native_darwin_titlebar_fixture_apply_style :: proc(
	window: ^NS.Window,
	force := false,
	allow_style_mask_change := true,
) -> bool {
	if window == nil { return false }
	style_mask := intrinsics.objc_send(NS.WindowStyleMask, window, "styleMask")
	fullscreen := NS.WindowStyleFlag.FullScreen in style_mask
	has_full_size_content_view := NS.WindowStyleFlag.FullSizeContentView in style_mask
	style_changed := darwin_titlebar_should_add_full_size_content_view(
		has_full_size_content_view,
		fullscreen,
		allow_style_mask_change,
	)
	if style_changed {
		style_mask += {.FullSizeContentView}
		NS.Window_setStyleMask(window, style_mask)
	}
	if force || style_changed {
		NS.Window_setTitlebarAppearsTransparent(window, true)
		NS.Window_setTitleVisibility(window, .Hidden)
	}
	return style_changed
}

native_darwin_titlebar_fixture_prepare :: proc(menu: ^Native_Menu_Runtime) -> bool {
	if menu == nil || menu.window == nil || menu.platform_data == nil || menu.application == nil { return false }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if state.window == nil || state.application == nil { return false }
	_ = native_darwin_titlebar_fixture_apply_style(state.window, force=true)
	NS.Window_setMovableByWindowBackground(state.window, false)
	menu.content_inset_top = 0
	state.titlebar_fixture.active = true
	if !sdl3.SetWindowHitTest(menu.window, darwin_titlebar_sdl_hit_test, rawptr(menu)) { return false }
	return native_darwin_titlebar_fixture_refresh(menu)
}

native_darwin_titlebar_fixture_refresh :: proc(
	menu: ^Native_Menu_Runtime,
	force_style := false,
	allow_style_mask_change := true,
) -> bool {
	if menu == nil || menu.platform_data == nil || menu.application == nil || menu.application.state == nil { return false }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar_fixture.active || state.window == nil { return true }
	style_changed := native_darwin_titlebar_fixture_apply_style(
		state.window,
		force=force_style,
		allow_style_mask_change=allow_style_mask_change,
	)
	if style_changed || force_style {
		state.titlebar_fixture.window_style_reapplies += 1
		app := cast(^Menu_Fixture_State)menu.application.state
		app.titlebar_style_resets += 1
		fmt.println("macos_titlebar_style_reapplied", "count", state.titlebar_fixture.window_style_reapplies)
	}
	app := cast(^Menu_Fixture_State)menu.application.state
	style_mask := intrinsics.objc_send(NS.WindowStyleMask, state.window, "styleMask")
	app.titlebar_fullscreen_active = NS.WindowStyleFlag.FullScreen in style_mask
	window_frame := NS.Window_frame(state.window)
	app.titlebar_window_origin_x = f32(window_frame.origin.x)
	app.titlebar_window_origin_y = f32(window_frame.origin.y)
	content_view := NS.Window_contentView(state.window)
	if content_view == nil { return false }
	content_bounds := NS.View_bounds(content_view)
	content_is_flipped := NS.View_isFlipped(content_view)
	button_kinds := [3]NS.UInteger{0, 1, 2}
	next := Darwin_Titlebar_Geometry{}
	for button_kind, index in button_kinds {
		bounds, ok := darwin_titlebar_native_button_bounds(
			state.window,
			content_view,
			content_bounds,
			content_is_flipped,
			button_kind,
		)
		if !ok { return false }
		next.native_controls[index] = bounds
		next.native_control_count += 1
	}
	window_width, window_height: c.int
	if !sdl3.GetWindowSize(menu.window, &window_width, &window_height) { return false }
	button_bottom: f32 = 0
	controls_right: f32 = 0
	for bounds in next.native_controls[:next.native_control_count] {
		button_bottom = max(button_bottom, bounds.y+bounds.h)
		controls_right = max(controls_right, bounds.x+bounds.w)
	}
	next_header_height := max(44, f32(math.ceil(f64(button_bottom+12))))
	old_app := cast(^Menu_Fixture_State)menu.application.state
	changed := old_app.titlebar_header_height != next_header_height ||
		old_app.titlebar_control_start_x != controls_right+12 ||
		old_app.titlebar_window_width != f32(window_width) ||
		old_app.titlebar_logical_height != f32(window_height)
	old_app.titlebar_control_bounds = next.native_controls
	old_app.titlebar_header_height = next_header_height
	old_app.titlebar_control_start_x = controls_right+12
	old_app.titlebar_window_width = f32(window_width)
	old_app.titlebar_logical_height = f32(window_height)
	old_app.titlebar_tab_start_x = old_app.titlebar_control_start_x
	old_app.titlebar_tab_width = max(f32(window_width)-old_app.titlebar_tab_start_x-160, 0)
	old_app.titlebar_drag_region = alicorn.Rect{
		old_app.titlebar_tab_start_x+old_app.titlebar_tab_width,
		0,
		max(f32(window_width)-old_app.titlebar_tab_start_x-old_app.titlebar_tab_width, 0),
		next_header_height,
	}
	next.header = alicorn.Rect{0, 0, f32(window_width), next_header_height}
	next.drag_regions[0] = old_app.titlebar_drag_region
	if next.drag_regions[0].w > 0 { next.drag_region_count = 1 }
	state.titlebar_fixture.geometry = next
	if changed && menu.runtime != nil { alicorn.invalidate_root(menu.runtime, "measured macOS titlebar geometry changed") }
	fmt.println(
		"macos_titlebar_geometry",
		"logical", window_width, window_height,
		"header", next_header_height,
		"controls", next.native_controls[0], next.native_controls[1], next.native_controls[2],
		"display_scale", sdl3.GetWindowDisplayScale(menu.window),
	)
	return true
}

native_darwin_titlebar_fixture_cancel_gesture :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if state.titlebar_fixture.active {
		darwin_titlebar_gesture_cancel(&state.titlebar_fixture.gesture_owner)
	}
}

native_darwin_titlebar_fixture_note_consumed_event :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if state.titlebar_fixture.active {
		state.titlebar_fixture.consumed_window_events += 1
		if menu.application != nil && menu.application.state != nil {
			app := cast(^Menu_Fixture_State)menu.application.state
			if state.window != nil {
				window_frame := NS.Window_frame(state.window)
				app.titlebar_window_origin_x = f32(window_frame.origin.x)
				app.titlebar_window_origin_y = f32(window_frame.origin.y)
			}
			app.titlebar_consumed_count += 1
			if menu.runtime != nil { alicorn.invalidate_root(menu.runtime, "Cocoa consumed a native titlebar input event") }
		}
	}
}

native_darwin_titlebar_fixture_note_sdl_pointer :: proc(menu: ^Native_Menu_Runtime, event: sdl3.Event) {
	if menu == nil || menu.platform_data == nil || menu.application == nil || menu.application.state == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar_fixture.active { return }
	app := cast(^Menu_Fixture_State)menu.application.state
	app.titlebar_raw_pointer_count += 1
	if event.type == .MOUSE_MOTION {
		app.titlebar_raw_motion_x = event.motion.x
		app.titlebar_raw_motion_y = event.motion.y
	} else if event.type == .MOUSE_BUTTON_DOWN {
		app.titlebar_raw_down_x = event.button.x
		app.titlebar_raw_down_y = event.button.y
	} else if event.type == .MOUSE_BUTTON_UP {
		app.titlebar_raw_up_x = event.button.x
		app.titlebar_raw_up_y = event.button.y
	}
}

native_darwin_titlebar_fixture_destroy :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar_fixture.active { return }
	_ = sdl3.SetWindowHitTest(menu.window, nil, nil)
	if state.window != nil { NS.Window_setMovableByWindowBackground(state.window, false) }
	darwin_titlebar_gesture_cancel(&state.titlebar_fixture.gesture_owner)
	fmt.println(
		"macos_titlebar_input_summary",
		"hit_tests", state.titlebar_fixture.hit_test_calls,
		"draggable_decisions", state.titlebar_fixture.draggable_hit_test_calls,
		"SDL_WINDOW_HIT_TEST_events", state.titlebar_fixture.consumed_window_events,
	)
	state.titlebar_fixture.active = false
}
