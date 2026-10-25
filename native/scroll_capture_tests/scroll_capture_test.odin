package scroll_capture_tests

import "core:sync"
import "core:testing"
import alicorn "../../runtime"
import host "../sdl_gpu"
import "vendor:sdl3"

// SDL event queues and modifier state are process-wide. Keep these fixtures in
// a separate test package and serialize their SDL lifetime even with Odin's
// default parallel test runner.
scroll_capture_test_sdl_mutex: sync.Mutex

scroll_capture_test_start :: proc(t: ^testing.T) -> bool {
	sync.mutex_lock(&scroll_capture_test_sdl_mutex)
	if !sdl3.Init(sdl3.INIT_EVENTS) {
		testing.expect(t, false, "SDL events should initialize")
		sync.mutex_unlock(&scroll_capture_test_sdl_mutex)
		return false
	}
	return true
}

scroll_capture_test_stop :: proc() {
	sdl3.Quit()
	sync.mutex_unlock(&scroll_capture_test_sdl_mutex)
}

Scroll_Capture_Test_State :: struct {
	claim_target: alicorn.Node_ID,
	captures, fallbacks: int,
	target: alicorn.Node_ID,
	runtime: ^alicorn.Runtime,
	event, fallback_event: alicorn.Scroll_Event,
	offset_x_before, offset_y_before: f32,
}

scroll_capture_test_capture :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Scroll_Event, target: alicorn.Node_ID) -> bool {
	probe := cast(^Scroll_Capture_Test_State)state
	probe.captures += 1
	probe.runtime, probe.target, probe.event = rt, target, event
	probe.offset_x_before = alicorn.scroll_region_offset_x(rt, target)
	probe.offset_y_before = alicorn.scroll_region_offset(rt, target)
	return target == probe.claim_target
}

scroll_capture_test_fallback :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Scroll_Event) {
	probe := cast(^Scroll_Capture_Test_State)state
	probe.fallbacks += 1
	probe.fallback_event = event
}

scroll_capture_test_describe :: proc(rt: ^alicorn.Runtime, nested := false, modal := false) -> (editor, inner, modal_region: alicorn.Node_ID) {
	ui, ready := alicorn.begin_frame(rt)
	if !ready { return }
	alicorn.container_begin(&ui, .Root, style=alicorn.layout_style(.Column))
	region := alicorn.scroll_region_begin(
		&ui, key=alicorn.key_string("editor"),
		viewport_width=240, viewport_height=180, content_width=600, content_height=600,
		line_width=10, line_height=20, axes=.Both, axis_behavior=.Free,
		style=alicorn.layout_style(.Column, width=240, height=180, clip=true),
	)
	editor = region.id
	if nested {
		child := alicorn.scroll_region_begin(
			&ui, key=alicorn.key_string("nested"),
			viewport_width=100, viewport_height=60, content_width=400, content_height=400,
			line_width=10, line_height=20, axes=.Both, axis_behavior=.Free,
			style=alicorn.layout_style(.Column, width=100, height=60, clip=true),
		)
		inner = child.id
		alicorn.scroll_region_end(&ui)
	}
	alicorn.scroll_region_end(&ui)
	alicorn.container_end(&ui)
	if modal {
		_ = alicorn.modal_overlay_begin(&ui, alicorn.key_string("modal"), style=alicorn.layout_style(.Column, clip=true))
		child := alicorn.scroll_region_begin(
			&ui, key=alicorn.key_string("modal-scroll"),
			viewport_width=100, viewport_height=60, content_height=400,
			line_height=20, axes=.Vertical,
			style=alicorn.layout_style(.Column, width=100, height=60, clip=true),
		)
		modal_region = child.id
		alicorn.scroll_region_end(&ui)
		alicorn.modal_overlay_end(&ui)
	}
	alicorn.end_frame(&ui)
	return
}

scroll_capture_test_wheel :: proc(x, y: f32) -> sdl3.Event {
	event := sdl3.Event{type=.MOUSE_WHEEL}
	event.wheel.mouse_x, event.wheel.mouse_y = x, y
	event.wheel.x, event.wheel.y = -0.375, -0.625
	event.wheel.integer_x, event.wheel.integer_y = -7, -9
	event.wheel.direction = .FLIPPED
	return event
}

// Exercise the shared event pump via either SDL's primary queue or the bounded
// secondary replay queue. Zero window IDs let both paths run without a window/GPU.
scroll_capture_test_pump :: proc(
	t: ^testing.T, rt: ^alicorn.Runtime, application: ^host.Application,
	events: []sdl3.Event, replay := true,
	inspector: ^host.Native_Inspector_Overlay = nil, menu: ^host.Native_Menu_Runtime = nil,
) {
	child := host.Native_Secondary_Window{active=true}
	child.event_queue = make([dynamic]host.Native_Secondary_Window_Queued_Event, 0, allocator=context.allocator)
	defer delete(child.event_queue)
	manager := host.Native_Secondary_Window_Manager{child=&child}
	for event in events {
		queued := event
		ok := host.native_secondary_window_enqueue_event(&manager, event) if replay else sdl3.PushEvent(&queued)
		testing.expect(t, ok, "the wheel event should enter the selected host queue")
	}
	metrics := host.Window_Metrics{logical_width=320, logical_height=240, window_logical_height=240, display_scale=1}
	quit := false
	logical_resizes, pixel_resizes, scales, text_events, compositions: int
	text := ""
	host.pump_events(
		nil, rt, &metrics, &quit, &logical_resizes, &pixel_resizes, &scales,
		&text_events, &compositions, &text,
		application=application, inspector=inspector, native_menu=menu,
		secondary_child=&child if replay else nil, replay_secondary_events=replay,
	)
}

@(test)
test_scroll_capture_claim_and_decline_preserve_precise_input :: proc(t: ^testing.T) {
	if !scroll_capture_test_start(t) { return }
	defer scroll_capture_test_stop()
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&rt)
	editor, _, _ := scroll_capture_test_describe(&rt)
	testing.expect(t, editor != 0, "the editor region should be retained")
	probe := Scroll_Capture_Test_State{claim_target=editor}
	app := host.Application{state=&probe, on_scroll_capture=scroll_capture_test_capture, on_scroll=scroll_capture_test_fallback}
	events := [?]sdl3.Event{scroll_capture_test_wheel(23.25, 37.75)}
	modifiers := sdl3.KMOD_SHIFT | sdl3.KMOD_CTRL | sdl3.KMOD_ALT | sdl3.KMOD_GUI
	sdl3.SetModState(modifiers)
	defer sdl3.SetModState({})
	scroll_capture_test_pump(t, &rt, &app, events[:], replay=false)
	expected := alicorn.Scroll_Event{
		x=23.25, y=37.75, delta_x=-0.375, delta_y=-0.625, ticks_x=-7, ticks_y=-9,
		modifiers={shift=true, control=true, alt=true, super=true},
	}
	testing.expect(t, probe.captures == 1 && probe.runtime == &rt && probe.target == editor && probe.event == expected,
		"capture should receive the app state, runtime, exact target, precise deltas, whole ticks and all modifiers unchanged")
	testing.expect(t, probe.offset_x_before == 0 && probe.offset_y_before == 0 &&
		alicorn.scroll_region_offset_x(&rt, editor) == 0 && alicorn.scroll_region_offset(&rt, editor) == 0 && probe.fallbacks == 0,
		"claiming must run before mutation and skip both retained axes and fallback")
	probe.claim_target = 0
	scroll_capture_test_pump(t, &rt, &app, events[:], replay=false)
	testing.expect(t, probe.captures == 2 && probe.event == expected && probe.offset_y_before == 0 &&
		alicorn.scroll_region_offset_x(&rt, editor) == 3.75 && alicorn.scroll_region_offset(&rt, editor) == 12.5 && probe.fallbacks == 0,
		"declining should preserve precise retained scrolling rather than substitute integer ticks or flip SDL direction")
	app.on_scroll_capture = nil
	scroll_capture_test_pump(t, &rt, &app, events[:], replay=false)
	testing.expect(t, probe.captures == 2 && alicorn.scroll_region_offset(&rt, editor) == 25 && probe.fallbacks == 0,
		"an absent capture callback should preserve existing retained scrolling")
	app.on_scroll_capture = scroll_capture_test_capture
	events[0] = scroll_capture_test_wheel(300.25, 220.75)
	scroll_capture_test_pump(t, &rt, &app, events[:], replay=false)
	expected.x, expected.y = 300.25, 220.75
	testing.expect(t, probe.captures == 2 && probe.fallbacks == 1 && probe.fallback_event == expected,
		"outside every retained region, only the existing fallback should receive the unchanged event")
}

@(test)
test_scroll_capture_exact_nested_target :: proc(t: ^testing.T) {
	if !scroll_capture_test_start(t) { return }
	defer scroll_capture_test_stop()
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&rt)
	editor, inner, _ := scroll_capture_test_describe(&rt, nested=true)
	testing.expect(t, editor != 0 && inner != 0 && alicorn.scroll_region_hit_test(&rt, 20, 20) == inner &&
		alicorn.scroll_region_hit_test(&rt, 200, 140) == editor, "the public query should resolve the deepest hit region")
	probe := Scroll_Capture_Test_State{claim_target=editor}
	app := host.Application{state=&probe, on_scroll_capture=scroll_capture_test_capture, on_scroll=scroll_capture_test_fallback}
	events := [?]sdl3.Event{scroll_capture_test_wheel(20, 20)}
	scroll_capture_test_pump(t, &rt, &app, events[:])
	testing.expect(t, probe.captures == 1 && probe.target == inner && alicorn.scroll_region_offset(&rt, inner) == 12.5 &&
		alicorn.scroll_region_offset(&rt, editor) == 0 && probe.fallbacks == 0,
		"an editor-only claim should decline a nested region and let that exact region scroll")
	events[0] = scroll_capture_test_wheel(200, 140)
	scroll_capture_test_pump(t, &rt, &app, events[:])
	testing.expect(t, probe.captures == 2 && probe.target == editor && alicorn.scroll_region_offset(&rt, editor) == 0 && probe.fallbacks == 0,
		"the same callback should claim the outer editor away from its nested region")
}

@(test)
test_scroll_capture_respects_modal_targets_and_backdrop :: proc(t: ^testing.T) {
	if !scroll_capture_test_start(t) { return }
	defer scroll_capture_test_stop()
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&rt)
	editor, _, modal := scroll_capture_test_describe(&rt, modal=true)
	testing.expect(t, editor != 0 && modal != 0 && alicorn.scroll_region_hit_test(&rt, 200, 140) == 0 &&
		alicorn.scroll_region_hit_test(&rt, 20, 20) == modal, "the public query should exclude covered background regions")
	probe := Scroll_Capture_Test_State{claim_target=modal}
	app := host.Application{state=&probe, on_scroll_capture=scroll_capture_test_capture, on_scroll=scroll_capture_test_fallback}
	events := [?]sdl3.Event{scroll_capture_test_wheel(200, 140), scroll_capture_test_wheel(300, 220)}
	scroll_capture_test_pump(t, &rt, &app, events[:])
	testing.expect(t, probe.captures == 0 && probe.fallbacks == 0 && alicorn.scroll_region_offset(&rt, editor) == 0,
		"modal backdrop input should reach neither capture, covered scrolling nor fallback")
	events[0] = scroll_capture_test_wheel(20, 20)
	scroll_capture_test_pump(t, &rt, &app, events[:1])
	testing.expect(t, probe.captures == 1 && probe.target == modal && alicorn.scroll_region_offset(&rt, modal) == 0 && probe.fallbacks == 0,
		"capture should receive and claim an actual region inside the active modal")
	probe.claim_target = 0
	scroll_capture_test_pump(t, &rt, &app, events[:1])
	testing.expect(t, probe.captures == 2 && alicorn.scroll_region_offset(&rt, modal) == 12.5 &&
		alicorn.scroll_region_offset(&rt, editor) == 0 && probe.fallbacks == 0,
		"declining modal capture should scroll only the modal region")
}

@(test)
test_scroll_capture_follows_inspector_and_content_blocking :: proc(t: ^testing.T) {
	if !scroll_capture_test_start(t) { return }
	defer scroll_capture_test_stop()
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&rt)
	editor, _, _ := scroll_capture_test_describe(&rt)
	probe := Scroll_Capture_Test_State{claim_target=editor}
	app := host.Application{state=&probe, on_scroll_capture=scroll_capture_test_capture, on_scroll=scroll_capture_test_fallback}
	overlay: host.Native_Inspector_Overlay
	host.native_inspector_runtime_init(&overlay, {enabled=true, start_visible=true}, rt.viewport)
	defer host.native_inspector_destroy(&overlay)
	overlay.state.panel_bounds = {0, 0, 80, 80}
	events := [?]sdl3.Event{scroll_capture_test_wheel(20, 20)}
	scroll_capture_test_pump(t, &rt, &app, events[:], inspector=&overlay)
	testing.expect(t, probe.captures == 0 && probe.fallbacks == 0 && alicorn.scroll_region_offset(&rt, editor) == 0,
		"inspector-owned wheel input must be blocked before application capture")
	events[0] = scroll_capture_test_wheel(200, 140)
	scroll_capture_test_pump(t, &rt, &app, events[:], inspector=&overlay)
	testing.expect(t, probe.captures == 1 && probe.target == editor, "input outside the inspector should still reach capture")
	menu := host.Native_Menu_Runtime{content_inset_top=30}
	events[0] = scroll_capture_test_wheel(20, 10)
	scroll_capture_test_pump(t, &rt, &app, events[:], menu=&menu)
	testing.expect(t, probe.captures == 1 && probe.fallbacks == 0, "native chrome above application content should not enter capture or fallback")
	events[0] = scroll_capture_test_wheel(20, 50)
	scroll_capture_test_pump(t, &rt, &app, events[:], menu=&menu)
	testing.expect(t, probe.captures == 2 && probe.event.x == 20 && probe.event.y == 20 && probe.target == editor,
		"capture hit testing and callback coordinates should share the existing content inset transform")
}

@(test)
test_scroll_capture_secondary_isolation_and_idle :: proc(t: ^testing.T) {
	if !scroll_capture_test_start(t) { return }
	defer scroll_capture_test_stop()
	primary := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&primary)
	secondary := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 240})
	defer alicorn.destroy_runtime(&secondary)
	primary_editor, _, _ := scroll_capture_test_describe(&primary)
	secondary_editor, _, _ := scroll_capture_test_describe(&secondary)
	primary_probe := Scroll_Capture_Test_State{claim_target=primary_editor}
	secondary_probe := Scroll_Capture_Test_State{claim_target=secondary_editor}
	primary_app := host.Application{state=&primary_probe, on_scroll_capture=scroll_capture_test_capture}
	secondary_app := host.Application{state=&secondary_probe, on_scroll_capture=scroll_capture_test_capture}
	// Initial retained scrollbar geometry can request a corrective description,
	// just as in the host's bounded stabilization pass before it enters idle.
	for _ in 0..<host.NATIVE_DESCRIPTION_STABILIZATION_LIMIT {
		if !primary.invalidated && !secondary.invalidated { break }
		if primary.invalidated { _, _, _ = scroll_capture_test_describe(&primary) }
		if secondary.invalidated { _, _, _ = scroll_capture_test_describe(&secondary) }
	}
	alicorn.frame_submission_succeeded(&primary)
	alicorn.frame_submission_succeeded(&secondary)
	testing.expect(t, !host.native_application_has_pending_work(&primary) && !host.native_application_has_pending_work(&secondary),
		"both initial window descriptions should settle before testing idle capture")
	primary_builds, secondary_builds := primary.stats.frames_built, secondary.stats.frames_built
	events := [?]sdl3.Event{scroll_capture_test_wheel(20, 20)}
	scroll_capture_test_pump(t, &primary, &primary_app, events[:], replay=false)
	scroll_capture_test_pump(t, &secondary, &secondary_app, events[:])
	testing.expect(t, primary_probe.captures == 1 && primary_probe.runtime == &primary && primary_probe.target == primary_editor &&
		secondary_probe.captures == 1 && secondary_probe.runtime == &secondary && secondary_probe.target == secondary_editor,
		"primary dispatch and secondary replay should use each window's own callback state, runtime and target")
	for _ in 0..<3 {
		scroll_capture_test_pump(t, &primary, &primary_app, nil, replay=false)
		scroll_capture_test_pump(t, &secondary, &secondary_app, nil)
	}
	child := host.Native_Secondary_Window{active=true, runtime=&secondary, application=secondary_app}
	manager := host.Native_Secondary_Window_Manager{child=&child}
	testing.expect(t, primary_probe.captures == 1 && secondary_probe.captures == 1 && primary_app.on_tick == nil && secondary_app.on_tick == nil &&
		primary.stats.frames_built == primary_builds && secondary.stats.frames_built == secondary_builds &&
		!host.native_application_has_pending_work(&primary) && !alicorn.presentation_needs_frame(&primary) &&
		!host.native_secondary_window_has_work(&manager),
		"a passive capture callback should introduce no callbacks, descriptions, presentations or pending work on idle pumps")
}
