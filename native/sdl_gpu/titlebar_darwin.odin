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
DARWIN_TITLEBAR_REGION_CAPACITY :: WINDOW_CHROME_REGION_CAPACITY

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
	interactive:            [DARWIN_TITLEBAR_REGION_CAPACITY]alicorn.Rect,
	interactive_count:     int,
	drag_regions:           [DARWIN_TITLEBAR_REGION_CAPACITY]alicorn.Rect,
	drag_region_count:      int,
}

Darwin_Titlebar_State :: struct {
	active:                     bool,
	header_height:              f32,
	geometry:                   Darwin_Titlebar_Geometry,
	metrics:                    Window_Chrome_Metrics,
	metrics_valid:              bool,
	metrics_delivered:          bool,
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
	point, _, ok = darwin_titlebar_pointer_sample_pop_with_buttons(samples)
	return
}

darwin_titlebar_pointer_sample_pop_with_buttons :: proc(
	samples: ^Darwin_Titlebar_Pointer_Samples,
) -> (point: sdl3.Point, buttons: sdl3.MouseButtonFlags, ok: bool) {
	if samples == nil || samples.count <= 0 { return }
	point = samples.points[samples.head]
	buttons = samples.buttons[samples.head]
	samples.head = (samples.head+1) % len(samples.points)
	samples.count -= 1
	ok = true
	return
}

darwin_titlebar_consume_hit_test_sample :: proc(
	samples: ^Darwin_Titlebar_Pointer_Samples,
	owner: ^Darwin_Titlebar_Gesture_Owner,
) -> bool {
	_, buttons, ok := darwin_titlebar_pointer_sample_pop_with_buttons(samples)
	if ok && !(sdl3.MouseButtonFlag.LEFT in buttons) {
		// Cocoa can consume mouse-up while performing its window drag. The app
		// must still release its latched gesture owner even without SDL's up event.
		darwin_titlebar_gesture_cancel(owner)
	}
	return ok
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

// The app chooses its row height. Native controls only exclude overlapping
// header space; hidden/reparented fullscreen toolbar controls cannot grow it.
darwin_titlebar_resolve_geometry :: proc(
	viewport, safe_area: alicorn.Rect,
	header_height: f32,
	visible_controls: []alicorn.Rect,
) -> (geometry: Darwin_Titlebar_Geometry, content_start_x: f32) {
	top := clamp(safe_area.y, 0, viewport.h)
	geometry.header = alicorn.Rect{0, top, viewport.w, min(max(header_height, 0), max(viewport.h-top, 0))}
	content_start_x = max(safe_area.x, 0)
	for bounds in visible_controls {
		if bounds.w <= 0 || bounds.h <= 0 || bounds.x >= viewport.w || bounds.x+bounds.w <= 0 ||
			bounds.y >= top+geometry.header.h || bounds.y+bounds.h <= top { continue }
		if geometry.native_control_count < len(geometry.native_controls) {
			geometry.native_controls[geometry.native_control_count] = bounds
			geometry.native_control_count += 1
		}
		content_start_x = max(content_start_x, bounds.x+bounds.w+12)
	}
	return
}

darwin_titlebar_should_add_full_size_content_view :: proc(
	has_full_size_content_view, fullscreen, allow_style_mask_change: bool,
) -> bool {
	// Mutating NSWindow's style mask while AppKit is entering/leaving fullscreen
	// can cancel the transition. Skip it for transition callbacks even if the
	// style-mask snapshot has not reported FullScreen yet.
	return allow_style_mask_change && !has_full_size_content_view && !fullscreen
}

darwin_titlebar_set_window_style_mask :: proc(window: ^NS.Window, style_mask: NS.WindowStyleMask, preserve_frame: bool) {
	if window == nil { return }
	frame := NS.Window_frame(window)
	content_view := NS.Window_contentView(window)
	if content_view == nil {
		NS.Window_setStyleMask(window, style_mask)
		if preserve_frame { NS.Window_setFrame(window, frame, false) }
		return
	}

	// SDL's Cocoa backend installs its listener as the content view's next
	// responder. NSWindow.setStyleMask can detach that link, so preserve and
	// restore the existing responder without depending on SDL-private objects.
	view_responder := cast(^NS.Responder)content_view
	previous_responder := intrinsics.objc_send(^NS.Responder, view_responder, "nextResponder")
	if previous_responder != nil {
		intrinsics.objc_send(nil, view_responder, "setNextResponder:", cast(^NS.Responder)nil)
	}
	NS.Window_setStyleMask(window, style_mask)
	current_responder := intrinsics.objc_send(^NS.Responder, view_responder, "nextResponder")
	if previous_responder != nil && previous_responder != current_responder {
		intrinsics.objc_send(nil, view_responder, "setNextResponder:", previous_responder)
	}
	// AppKit keeps the old content size when FullSizeContentView is added and
	// subtracts the titlebar from the frame. On fullscreen exit SDL has already
	// restored the desired outer frame; preserve that frame when restoring our
	// content extension, so every transition does not shorten the window again.
	if preserve_frame { NS.Window_setFrame(window, frame, false) }
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
) -> (bounds: alicorn.Rect, ok, visible: bool) {
	button := intrinsics.objc_send(^NS.View, window, "standardWindowButton:", button_kind)
	if button == nil { return }
	parent := intrinsics.objc_send(^NS.View, button, "superview")
	if parent == nil { return }
	frame := intrinsics.objc_send(NS.Rect, button, "frame")
	content_frame := intrinsics.objc_send(NS.Rect, content_view, "convertRect:fromView:", frame, parent)
	bounds = darwin_titlebar_rect_to_window_logical(content_frame, content_bounds, content_is_flipped)
	ok = bounds.w > 0 && bounds.h > 0
	visible = intrinsics.objc_send(^NS.Window, button, "window") == window &&
		!intrinsics.objc_send(NS.BOOL, button, "isHiddenOrHasHiddenAncestor")
	return
}

darwin_titlebar_intersection :: proc(a, b: alicorn.Rect) -> alicorn.Rect {
	x := max(a.x, b.x)
	y := max(a.y, b.y)
	return alicorn.Rect{x, y, max(min(a.x+a.w, b.x+b.w)-x, 0), max(min(a.y+a.h, b.y+b.h)-y, 0)}
}

// Copy finalized retained products after either a description or a retained
// presentation/layout pass. The hit-test callback consumes only this snapshot.
native_darwin_titlebar_sync_layout :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil || menu.runtime == nil || menu.application == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar.active || menu.application.window_chrome_layout == nil { return }
	layout := menu.application.window_chrome_layout(menu.application.state, menu.runtime)
	header, header_ok := alicorn.node_info(menu.runtime, layout.header)
	geometry := &state.titlebar.geometry
	geometry.interactive_count = 0
	geometry.drag_region_count = 0
	if !header_ok || !header.active {
		geometry.header = {}
		return
	}
	geometry.header = darwin_titlebar_intersection(header.bounds, state.titlebar.metrics.header)
	for region in layout.regions {
		if region.node == 0 { continue }
		node, ok := alicorn.node_info(menu.runtime, region.node)
		if !ok || !node.active { continue }
		region_bounds := node.bounds
		// The divider's retained grab target is wider than its painted rule.
		// Keep that target client-owned in the titlebar, just as in the body.
		if region.kind == .Interactive && node.kind == .Split_Handle { region_bounds = node.hit_bounds }
		bounds := darwin_titlebar_intersection(region_bounds, geometry.header)
		if bounds.w <= 0 || bounds.h <= 0 { continue }
		if region.kind == .Interactive {
			if geometry.interactive_count < len(geometry.interactive) {
				geometry.interactive[geometry.interactive_count] = bounds
				geometry.interactive_count += 1
			}
		} else if region.kind == .Window_Drag {
			if geometry.drag_region_count < len(geometry.drag_regions) {
				geometry.drag_regions[geometry.drag_region_count] = bounds
				geometry.drag_region_count += 1
			}
		}
	}
}

darwin_titlebar_apply_mobility :: proc(window: ^NS.Window, result: sdl3.HitTestResult) {
	if window == nil { return }
	desired := result == .DRAGGABLE
	if intrinsics.objc_send(NS.BOOL, window, "isMovable") != desired {
		NS.Window_setMovable(window, desired)
	}
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
	if !state.titlebar.active { return .NORMAL }
	state.titlebar.hit_test_calls += 1
	buttons := sdl3.GetGlobalMouseState(nil, nil)
	state.titlebar.last_sdl_pointer_point = area^
	state.titlebar.last_sdl_pointer_valid = true
	darwin_titlebar_pointer_sample_push(&state.titlebar.pointer_samples, area^, buttons)
	previous_owner := state.titlebar.gesture_owner
	result := darwin_titlebar_hit_test(state.titlebar.geometry, area^, buttons, &state.titlebar.gesture_owner)
	// SDL toggles movableByWindowBackground for its drag regions, but that
	// does not disable AppKit's ordinary titled-window drag path. Gate that
	// path too, including on hover before AppKit sees the initial mouse-down.
	darwin_titlebar_apply_mobility(state.window, result)
	if previous_owner == .None && state.titlebar.gesture_owner != .None {
		fmt.println("macos_titlebar_gesture", "point", area^,
			"owner", state.titlebar.gesture_owner, "hit", result)
	}
	if result == .DRAGGABLE { state.titlebar.draggable_hit_test_calls += 1 }
	return result
}

native_darwin_titlebar_translate_pointer :: proc(
	menu: ^Native_Menu_Runtime,
	pointer: alicorn.Pointer_Event,
	event: sdl3.Event,
) -> alicorn.Pointer_Event {
	if menu == nil || menu.platform_data == nil { return pointer }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar.active { return pointer }
	left_down := false
	match_buttons := true
	if event.type == .MOUSE_MOTION {
		left_down = sdl3.MouseButtonFlag.LEFT in event.motion.state
	} else if event.type == .MOUSE_BUTTON_DOWN {
		left_down = event.button.button == sdl3.BUTTON_LEFT
	} else if event.type != .MOUSE_BUTTON_UP {
		match_buttons = false
	}
	point, found := darwin_titlebar_pointer_sample_pop_matching(&state.titlebar.pointer_samples, left_down)
	if !match_buttons { point, found = darwin_titlebar_pointer_sample_pop(&state.titlebar.pointer_samples) }
	if !found {
		point = state.titlebar.last_sdl_pointer_point
		found = state.titlebar.last_sdl_pointer_valid
	}
	return darwin_titlebar_pointer_use_hit_test_point(
		pointer,
		point,
		found,
	)
}

native_darwin_titlebar_apply_style :: proc(
	window: ^NS.Window,
	force := false,
	allow_style_mask_change := true,
	preserve_frame := true,
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
		darwin_titlebar_set_window_style_mask(window, style_mask, preserve_frame)
	}
	if force || style_changed {
		NS.Window_setTitlebarAppearsTransparent(window, true)
		NS.Window_setTitleVisibility(window, .Hidden)
	}
	return style_changed
}

native_darwin_titlebar_prepare :: proc(menu: ^Native_Menu_Runtime, header_height: f32) -> bool {
	if menu == nil || menu.window == nil || menu.platform_data == nil || menu.application == nil { return false }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if state.window == nil || state.application == nil { return false }
	if menu.application.window_decorations != .Content_Title_Bar { return false }
	state.titlebar.header_height = max(header_height, 0)
	_ = native_darwin_titlebar_apply_style(state.window, force=true, preserve_frame=false)
	NS.Window_setMovableByWindowBackground(state.window, false)
	menu.content_inset_top = 0
	state.titlebar.active = true
	if !sdl3.SetWindowHitTest(menu.window, darwin_titlebar_sdl_hit_test, rawptr(menu)) { return false }
	return native_darwin_titlebar_refresh(menu)
}

native_darwin_titlebar_refresh :: proc(
	menu: ^Native_Menu_Runtime,
	force_style := false,
	allow_style_mask_change := true,
) -> bool {
	if menu == nil || menu.platform_data == nil || menu.application == nil { return false }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar.active || state.window == nil { return true }
	style_changed := native_darwin_titlebar_apply_style(
		state.window,
		force=force_style,
		allow_style_mask_change=allow_style_mask_change,
	)
	if style_changed || force_style {
		state.titlebar.window_style_reapplies += 1
		fmt.println("macos_titlebar_style_reapplied", "count", state.titlebar.window_style_reapplies)
	}
	style_mask := intrinsics.objc_send(NS.WindowStyleMask, state.window, "styleMask")
	fullscreen := NS.WindowStyleFlag.FullScreen in style_mask
	content_view := NS.Window_contentView(state.window)
	if content_view == nil { return false }
	content_bounds := NS.View_bounds(content_view)
	content_is_flipped := NS.View_isFlipped(content_view)
	button_kinds := [3]NS.UInteger{0, 1, 2}
	measured_controls: [3]alicorn.Rect
	visible_controls: [3]alicorn.Rect
	visible_count := 0
	for button_kind, index in button_kinds {
		bounds, ok, visible := darwin_titlebar_native_button_bounds(
			state.window,
			content_view,
			content_bounds,
			content_is_flipped,
			button_kind,
		)
		if !ok { continue }
		measured_controls[index] = bounds
		if visible {
			visible_controls[visible_count] = bounds
			visible_count += 1
		}
	}
	window_width, window_height: c.int
	if !sdl3.GetWindowSize(menu.window, &window_width, &window_height) { return false }
	safe_area: sdl3.Rect
	if !sdl3.GetWindowSafeArea(menu.window, &safe_area) { return false }
	next, content_start_x := darwin_titlebar_resolve_geometry(
		alicorn.Rect{0, 0, f32(window_width), f32(window_height)},
		alicorn.Rect{f32(safe_area.x), f32(safe_area.y), f32(safe_area.w), f32(safe_area.h)},
		state.titlebar.header_height,
		visible_controls[:visible_count],
	)
	metrics := Window_Chrome_Metrics{
		header=next.header,
		native_controls=next.native_controls,
		native_control_count=next.native_control_count,
		content_start_x=content_start_x,
		content_end_x=f32(window_width),
		display_scale=sdl3.GetWindowDisplayScale(menu.window),
		fullscreen=fullscreen,
	}
	metrics_changed := !state.titlebar.metrics_valid || !darwin_titlebar_metrics_equal(state.titlebar.metrics, metrics)
	// Keep the last resolved regions until the pending layout publishes new
	// products. Native resize/style measurements are not a substitute for layout.
	next.interactive = state.titlebar.geometry.interactive
	next.interactive_count = state.titlebar.geometry.interactive_count
	next.drag_regions = state.titlebar.geometry.drag_regions
	next.drag_region_count = state.titlebar.geometry.drag_region_count
	state.titlebar.geometry = next
	if metrics_changed {
		state.titlebar.metrics = metrics
		state.titlebar.metrics_valid = true
		state.titlebar.metrics_delivered = false
		if menu.runtime != nil {
			native_darwin_titlebar_deliver_metrics(menu)
			alicorn.invalidate_root(menu.runtime, "measured macOS titlebar geometry changed")
		}
		fmt.println("macos_titlebar_geometry", "logical", window_width, window_height,
			"header", next.header, "measured_controls", measured_controls,
			"active_controls", next.native_control_count, "display_scale", metrics.display_scale)
	}
	return true
}

darwin_titlebar_metrics_equal :: proc(a, b: Window_Chrome_Metrics) -> bool {
	if a.header != b.header || a.native_control_count != b.native_control_count ||
		a.content_start_x != b.content_start_x || a.content_end_x != b.content_end_x ||
		a.display_scale != b.display_scale || a.fullscreen != b.fullscreen { return false }
	for i in 0..<min(max(a.native_control_count, 0), len(a.native_controls)) {
		if a.native_controls[i] != b.native_controls[i] { return false }
	}
	return true
}

native_darwin_titlebar_deliver_metrics :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil || menu.runtime == nil || menu.application == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar.active || !state.titlebar.metrics_valid || state.titlebar.metrics_delivered { return }
	if menu.application.window_chrome_metrics != nil {
		menu.application.window_chrome_metrics(menu.application.state, menu.runtime, state.titlebar.metrics)
	}
	state.titlebar.metrics_delivered = true
}

native_darwin_titlebar_cancel_gesture :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if state.titlebar.active {
		darwin_titlebar_gesture_cancel(&state.titlebar.gesture_owner)
		darwin_titlebar_apply_mobility(state.window, .NORMAL)
	}
}

native_darwin_titlebar_exit_fullscreen :: proc(menu: ^Native_Menu_Runtime) -> bool {
	if menu == nil || menu.platform_data == nil || menu.window == nil { return false }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar.active || state.window == nil { return false }
	style_mask := intrinsics.objc_send(NS.WindowStyleMask, state.window, "styleMask")
	if !(NS.WindowStyleFlag.FullScreen in style_mask) { return false }
	return sdl3.SetWindowFullscreen(menu.window, false)
}

native_darwin_titlebar_note_consumed_event :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if state.titlebar.active {
		state.titlebar.consumed_window_events += 1
		darwin_titlebar_consume_hit_test_sample(
			&state.titlebar.pointer_samples,
			&state.titlebar.gesture_owner,
		)
		state.titlebar.last_sdl_pointer_valid = false
	}
}

native_darwin_titlebar_destroy :: proc(menu: ^Native_Menu_Runtime) {
	if menu == nil || menu.platform_data == nil { return }
	state := cast(^Darwin_Menu_State)menu.platform_data
	if !state.titlebar.active { return }
	_ = sdl3.SetWindowHitTest(menu.window, nil, nil)
	if state.window != nil {
		NS.Window_setMovableByWindowBackground(state.window, false)
		NS.Window_setMovable(state.window, true)
	}
	darwin_titlebar_gesture_cancel(&state.titlebar.gesture_owner)
	fmt.println(
		"macos_titlebar_input_summary",
		"hit_tests", state.titlebar.hit_test_calls,
		"draggable_decisions", state.titlebar.draggable_hit_test_calls,
		"SDL_WINDOW_HIT_TEST_events", state.titlebar.consumed_window_events,
	)
	state.titlebar.active = false
}
