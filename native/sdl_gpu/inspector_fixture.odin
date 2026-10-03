package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

INSPECTOR_FIXTURE_ACTIVATE :: alicorn.Action_ID(1801)
INSPECTOR_FIXTURE_ROWS :: 64
INSPECTOR_FIXTURE_TEXT :: "Editable application text; inspector preserves its owner."

Inspector_Fixture_State :: struct {
	activations: u64,
	text: string,
	text_owned: bool,
	initialized: bool,
	identity_error: bool,
	smoke: bool,
	input_smoke: bool,
	initially_open: bool,
	input_step: int,
	input_complete: bool,
	scheduler: Application_Scheduler,
	settled_builds: u64,
	settled_submits: u64,
	runtime: ^alicorn.Runtime,
	list: alicorn.Node_ID,
	field: alicorn.Node_ID,
}

inspector_fixture_activate :: proc(app: ^Inspector_Fixture_State, rt: ^alicorn.Runtime) {
	app.activations += 1
	alicorn.trace_action(rt, INSPECTOR_FIXTURE_ACTIVATE, "Activate fixture control")
	alicorn.trace_mutation(rt, "inspector fixture activation counter changed")
	alicorn.invalidate_root(rt, "inspector fixture control activated")
}

inspector_fixture_row :: proc(ui: ^alicorn.UI, app: ^Inspector_Fixture_State, position: int) {
	if !alicorn.component_begin(ui, alicorn.key_u64(u64(position+1))) { return }
	alicorn.container_begin(ui, .Container, label="event-row", style=alicorn.layout_style(.Row, height=28, gap=6))
	if alicorn.button(ui, fmt.tprintf("Event %02d", position+1), style=alicorn.layout_style(.Row, width=160, height=28),
		state=alicorn.Button_State{selected=position == 2}) {
		inspector_fixture_activate(app, ui.runtime)
	}
	_ = alicorn.semantic_bind(ui, alicorn.Semantic_ID{namespace=18, value=u64(position+1)})
	alicorn.text(ui, fmt.tprintf("stable entity #%d", position+1), style=alicorn.layout_style(.Row, height=28))
	alicorn.container_end(ui)
	alicorn.component_end(ui)
}

inspector_fixture_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Inspector_Fixture_State)state
	app.runtime = rt
	_ = alicorn.action_update(rt,
		alicorn.Action_Descriptor{id=INSPECTOR_FIXTURE_ACTIVATE, name="fixture.activate", label="Activate fixture control"},
		alicorn.Action_State{enabled=true})
	_ = alicorn.action_update(rt,
		alicorn.Action_Descriptor{id=alicorn.Action_ID(1802), name="fixture.follow", label="Follow semantic event"},
		alicorn.Action_State{enabled=true, checked=true})
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(&ui, .Root, label="inspector-fixture-root", key=alicorn.key_string("fixture-root"),
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=10, clip=true),
		color=alicorn.Color{0.035, 0.045, 0.065, 1})
	alicorn.text(&ui, "Alicorn visual inspector fixture", style=alicorn.layout_style(height=28))
	alicorn.text(&ui, "F9 opens the inspector. Pick controls without activating them; inspect the retained tree and causes.",
		style=alicorn.layout_style(height=28))
	if alicorn.component_begin(&ui, alicorn.key_string("workspace")) {
		alicorn.container_begin(&ui, .Container, label="workspace", style=alicorn.layout_style(.Column, grow=1, gap=10, clip=true))
		alicorn.text(&ui, fmt.tprintf("Application activations: %d", app.activations), style=alicorn.layout_style(height=24))
		if alicorn.button(&ui, "Activate fixture control", key=alicorn.key_string("activate"), style=alicorn.layout_style(width=260, height=32)) {
			inspector_fixture_activate(app, rt)
		}
		app.field = alicorn.text_field(&ui, app.text, key=alicorn.key_string("editable"), style=alicorn.layout_style(height=34))
		alicorn.text(&ui, "Virtual list: 64 stable entities; semantic event #3 has its own durable owner.", style=alicorn.layout_style(height=24))
		list := alicorn.virtual_list_begin(&ui, INSPECTOR_FIXTURE_ROWS, 28, key=alicorn.key_string("events"),
			style=alicorn.layout_style(height=252, clip=true), label="fixture-events", focusable=true)
		app.list = list.scroll.id
		for position := list.first; position < list.last; position += 1 {
			inspector_fixture_row(&ui, app, position)
		}
		alicorn.virtual_list_end(&ui, list)
		if app.identity_error {
			// One call site and one repeated explicit key intentionally violate
			// the identity contract while leaving the rest of the tree inspectable.
			for index in 0..<2 {
				alicorn.text(&ui, fmt.tprintf("Duplicate identity %d", index), key=alicorn.key_string("duplicate-fixture-key"))
			}
		}
		alicorn.container_end(&ui)
		alicorn.component_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if !app.initialized {
		app.initialized = true
		_ = alicorn.semantic_focus_set(rt, alicorn.Semantic_ID{namespace=18, value=3}, app.list)
		_ = alicorn.focus(rt, app.list)
	}
	return root
}

inspector_fixture_text_change :: proc(state: rawptr, rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	if !change.changed { return }
	app := cast(^Inspector_Fixture_State)state
	copy, err := strings.clone(change.text)
	if err != nil { return }
	if app.text_owned { delete(app.text) }
	app.text, app.text_owned = copy, true
	alicorn.invalidate_root(rt, "inspector fixture text changed")
}

inspector_fixture_push_event :: proc(event: sdl3.Event) {
	queued := event
	queued.common.timestamp = sdl3.GetTicksNS()
	if !sdl3.PushEvent(&queued) { fail("inspector fixture could not enqueue SDL input") }
}

inspector_fixture_push_key :: proc(key: sdl3.Keycode, scancode: sdl3.Scancode) {
	event := sdl3.Event{type=.KEY_DOWN}
	event.key.key, event.key.scancode, event.key.down = key, scancode, true
	inspector_fixture_push_event(event)
	event.type, event.key.down = .KEY_UP, false
	inspector_fixture_push_event(event)
}

inspector_fixture_activation_bounds :: proc(rt: ^alicorn.Runtime) -> alicorn.Rect {
	for id in rt.order {
		node := rt.nodes[id]
		if node.kind == .Button && node.label == "Activate fixture control" { return node.bounds }
	}
	fail("inspector fixture activation target was not retained")
}

inspector_fixture_push_button :: proc(rt: ^alicorn.Runtime, kind: sdl3.EventType) {
	bounds := inspector_fixture_activation_bounds(rt)
	event := sdl3.Event{type=kind}
	event.button.button, event.button.clicks = 1, 1
	event.button.down = kind == .MOUSE_BUTTON_DOWN
	event.button.x, event.button.y = bounds.x+bounds.w/2, bounds.y+bounds.h/2
	inspector_fixture_push_event(event)
}

inspector_fixture_services :: proc(state: rawptr, services: Application_Services) {
	app := cast(^Inspector_Fixture_State)state
	app.scheduler = services.scheduler
	if app.input_smoke {
		_ = application_schedule_after(app.scheduler, .Frequent, 150_000_000)
	}
}

// These injected SDL events belong to this internal native fixture. Every
// event still travels through the production pump and input ownership route.
inspector_fixture_scheduled :: proc(state: rawptr, rt: ^alicorn.Runtime, class: Scheduled_Wake_Class) {
	app := cast(^Inspector_Fixture_State)state
	if !app.input_smoke || class != .Frequent || app.input_complete { return }
	switch app.input_step {
	case 0:
		if app.initially_open { inspector_fixture_push_key(sdl3.K_F9, .F9) }
		_ = alicorn.focus(rt, app.field)
	case 1:
		event := sdl3.Event{type=.TEXT_EDITING}
		event.edit.text, event.edit.start, event.edit.length = "pending composition", 0, 7
		inspector_fixture_push_event(event)
	case 2:
		inspector_fixture_push_key(sdl3.K_F9, .F9)
		event := sdl3.Event{type=.TEXT_INPUT}
		event.text.text = "must not enter app while inspecting"
		inspector_fixture_push_event(event)
	case 3:
		inspector_fixture_push_key(sdl3.K_P, .P)
	case 4:
		inspector_fixture_push_button(rt, .MOUSE_BUTTON_DOWN)
		inspector_fixture_push_button(rt, .MOUSE_BUTTON_UP)
	case 5:
		inspector_fixture_push_key(sdl3.K_ESCAPE, .ESCAPE)
		// Closing must consume queued input from the old ownership epoch.
		event := sdl3.Event{type=.TEXT_INPUT}
		event.text.text = "must not enter app after inspector closes"
		inspector_fixture_push_event(event)
		inspector_fixture_push_button(rt, .MOUSE_BUTTON_UP)
	case 6:
		if rt.focused != app.field { fail("inspector input smoke did not restore application text focus") }
		if node, ok := rt.nodes[app.field]; !ok || node.composition.active {
			fail("inspector input smoke left stale application composition")
		}
		app.input_complete = true
		app.settled_builds, app.settled_submits = rt.stats.frames_built, rt.stats.gpu_submits
	}
	app.input_step += 1
	if !app.input_complete { _ = application_schedule_after(app.scheduler, .Frequent, 150_000_000) }
}

inspector_fixture_stop :: proc(state: rawptr) {
	app := cast(^Inspector_Fixture_State)state
	fmt.println("inspector_fixture", "activations", app.activations, "hard_error", app.runtime.hard_error,
		"focus", app.runtime.focused, "semantic_owner", app.runtime.semantic_focus.owner,
		"input_complete", app.input_complete, "text_unchanged", app.text == INSPECTOR_FIXTURE_TEXT)
	if app.smoke {
		if app.activations != 0 { fail("inspector fixture smoke accidentally activated application controls") }
		if app.runtime.hard_error != app.identity_error { fail("inspector fixture identity error did not match requested mode") }
		if app.runtime.semantic_focus.id != (alicorn.Semantic_ID{namespace=18, value=3}) {
			fail("inspector fixture lost durable semantic focus")
		}
		if app.input_smoke {
			if !app.input_complete || app.text != INSPECTOR_FIXTURE_TEXT {
				fail("inspector input smoke failed to consume overlay text input")
			}
			if app.runtime.stats.frames_built != app.settled_builds || app.runtime.stats.gpu_submits != app.settled_submits {
				fail("inspector input smoke performed application work after settling")
			}
		}
	}
	if app.text_owned { delete(app.text) }
}

// RunInspectorFixture exercises the reusable Run host with retained hierarchy,
// explicit identity scopes, editable text, virtual rows, actions, and semantic
// focus. With no tick callback, a settled inspector can demonstrate true idle.
RunInspectorFixture :: proc() {
	state := Inspector_Fixture_State{text=INSPECTOR_FIXTURE_TEXT}
	for argument in os.args {
		if argument == "--inspector-identity-error" { state.identity_error = true }
		if argument == "--inspector-fixture-smoke" || argument == "--smoke" { state.smoke = true }
		if argument == "--inspector-input-smoke" { state.input_smoke, state.smoke = true, true }
		if argument == "--inspector-open" { state.initially_open = true }
	}
	Run(Application{
		state=rawptr(&state), title="Alicorn Inspector Fixture", width=1280, height=760,
		build=inspector_fixture_build,
		on_text_change=inspector_fixture_text_change,
		on_services=inspector_fixture_services,
		on_scheduled_wake=inspector_fixture_scheduled,
		on_stop=inspector_fixture_stop,
	}, smoke=state.smoke)
}
