package testui

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:math"
import alicorn "alicorn:runtime"

Harness_Test_App :: struct {
	name: string,
	activations: int,
}

harness_test_render :: proc(app: ^Harness_Test_App, ui: ^alicorn.UI) {
	_ = alicorn.text_field(ui, app.name, key=alicorn.key_string("name"), style=alicorn.layout_style(height=32))
	_ = alicorn.semantic_text_field_label(ui, "Name")
	if alicorn.button(ui, "Save", key=alicorn.key_string("save"), style=alicorn.layout_style(height=32)) {
		app.activations += 1
	}
}

harness_test_text_changed :: proc(state: rawptr, _rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	if !change.changed { return }
	app := cast(^Harness_Test_App)state
	copy, err := strings.clone(change.text)
	if err != nil { return }
	if len(app.name) > 0 { delete(app.name) }
	app.name = copy
}

@(test)
test_public_harness_drives_focus_text_and_physical_button_input :: proc(t: ^testing.T) {
	app := Harness_Test_App{}
	defer if len(app.name) > 0 { delete(app.name) }
	h, status := open(&app, harness_test_render, width=240, height=120, on_text_change=harness_test_text_changed)
	if !testing.expect(t, status == .Ok, "headless application should open without a native window") { return }
	defer close(&h)
	testing.expect(t, strings.contains(last_turn_diagnostic(&h), "input=initialization"),
		"the initial application description should not be reported as a synthetic Tab input")
	testing.expect(t, strings.contains(last_turn_diagnostic(&h), "key=none"),
		"initialization should not report a key that the application never received")
	testing.expect(t, step(&h, Input{kind=.Initial_Description}) == .Unsupported_Input,
		"the internal initialization turn should not be accepted as user input")

	field := find(&h, Query{role=.Text_Field, name="Name", match_role=true, match_name=true})
	if !testing.expect(t, field.match == .Unique && field.element.has_bounds,
		"a semantic name should resolve to one element with finalized layout") {
		destroy_find_result(&field)
		return
	}
	if !testing.expect(t, click(&h, &field.element) == .Ok, "element click should use its current physical bounds") {
		destroy_find_result(&field)
		return
	}
	testing.expect(t, last_turn(&h).pointer_target == field.element.visual_node,
		"the pointer hit target should survive the corrective application description")
	testing.expect(t, step(&h, Input{kind=.Text_Commit, text="Ada"}) == .Ok,
		"committed synthetic text should run through the retained text input state")
	destroy_find_result(&field)

	field = find(&h, Query{role=.Text_Field, name="Name", match_role=true, match_name=true})
	testing.expect(t, field.match == .Unique && field.element.value == "Ada" && app.name == "Ada",
		"the application callback and semantic snapshot should observe the committed value")
	destroy_find_result(&field)
	testing.expect(t, step(&h, Input{kind=.Key, key=.Backspace}) == .Ok && app.name == "Ad",
		"Backspace should edit a built-in field through the shared text-key route")
	testing.expect(t, step(&h, Input{kind=.Key, key=.Home}) == .Ok &&
		step(&h, Input{kind=.Key, key=.Delete}) == .Ok && app.name == "d",
		"Home and Delete should update the caret and source value through the same route")

	testing.expect(t, step(&h, Input{kind=.Key, key=.Tab}) == .Ok,
		"Tab should use the same logical focus traversal as the native host")
	save := find(&h, Query{
		role=.Button,
		name="Save",
		key=alicorn.key_string("save"),
		match_role=true,
		match_name=true,
		match_key=true,
	})
	testing.expect(t, save.match == .Unique && save.element.focused,
		"a stable key should resolve the button and the snapshot should report focus")
	testing.expect(t, step(&h, Input{kind=.Key, key=.Return}) == .Ok && app.activations == 1,
		"Return should activate the focused button through the retained interaction path")
	destroy_find_result(&save)
	save = find(&h, Query{role=.Button, name="Save", match_role=true, match_name=true})
	if testing.expect(t, save.match == .Unique, "Save should remain queryable for a physical button click") {
		testing.expect(t, click(&h, &save.element) == .Ok && app.activations == 2,
			"a coordinate click should activate the button through normal pointer routing")
		testing.expect(t, last_turn(&h).pointer_target == save.element.visual_node,
			"the button hit target should survive the resulting application description")
	}
	destroy_find_result(&save)
	close(&h)
}

Harness_Ambiguous_App :: struct {
	activations: int,
}

harness_ambiguous_render :: proc(app: ^Harness_Ambiguous_App, ui: ^alicorn.UI) {
	if alicorn.button(ui, "Open", key=alicorn.key_string("first"), style=alicorn.layout_style(height=30)) {
		app.activations += 1
	}
	if alicorn.button(ui, "Open", key=alicorn.key_string("second"), style=alicorn.layout_style(height=30)) {
		app.activations += 1
	}
}

@(test)
test_find_reports_ambiguous_names_and_resolves_stable_key :: proc(t: ^testing.T) {
	app := Harness_Ambiguous_App{}
	h, status := open(&app, harness_ambiguous_render, width=240, height=120)
	if !testing.expect(t, status == .Ok) { return }
	defer close(&h)

	ambiguous := find(&h, Query{role=.Button, name="Open", match_role=true, match_name=true})
	testing.expect(t, ambiguous.match == .Ambiguous,
		"a repeated accessible name should not silently select an arbitrary button")
	destroy_find_result(&ambiguous)

	unique := find(&h, Query{key=alicorn.key_string("second"), match_key=true})
	testing.expect(t, unique.match == .Unique && unique.element.bounds.y > 0,
		"stable UI identity should resolve the second button and its layout")
	if unique.match != .Unique { destroy_find_result(&unique); return }
	testing.expect(t, step(&h, Input{kind=.Key, key=.Tab}) == .Ok,
		"a subsequent input should reconcile a fresh description")
	testing.expect(t, click(&h, &unique.element) == .Stale_Snapshot,
		"physical interaction must reject bounds captured before the last description")
	destroy_find_result(&unique)
	unique = find(&h, Query{key=alicorn.key_string("second"), match_key=true})
	defer destroy_find_result(&unique)
	testing.expect(t, unique.match == .Unique && step(&h, Input{
		kind=.Semantic_Action,
		semantic_id=unique.element.semantic_id,
		semantic_action=.Press,
	}) == .Ok && app.activations == 1,
		"an advertised semantic Press should activate the requested control independently of coordinates")
}

Harness_Modal_App :: struct {
	background_activations: int,
	modal_activations: int,
}

harness_modal_render :: proc(app: ^Harness_Modal_App, ui: ^alicorn.UI) {
	alicorn.container_begin(ui, .Root, label="modal-workspace", key=alicorn.key_string("modal-workspace"),
		style=alicorn.layout_style(.Column, grow=1))
	if alicorn.button(ui, "Background action", key=alicorn.key_string("modal-background"),
		style=alicorn.layout_style(width=220, height=48)) {
		app.background_activations += 1
	}
	alicorn.container_end(ui)
}

harness_modal_render_overlay :: proc(app: ^Harness_Modal_App, ui: ^alicorn.UI) {
	alicorn.modal_overlay_begin(ui, alicorn.key_string("test-modal"),
		style=alicorn.layout_style(.Column, align=.Center, justify=.Center))
	if alicorn.button(ui, "Modal action", key=alicorn.key_string("modal-action"),
		style=alicorn.layout_style(width=220, height=48)) {
		app.modal_activations += 1
	}
	alicorn.modal_overlay_end(ui)
}

@(test)
test_modal_overlay_blocks_background_pointer_and_keyboard_actions :: proc(t: ^testing.T) {
	app := Harness_Modal_App{}
	h, status := open(
		&app,
		harness_modal_render,
		width=320,
		height=180,
		render_overlays=harness_modal_render_overlay,
	)
	if !testing.expect(t, status == .Ok) { return }
	defer close(&h)

	background := find(&h, Query{role=.Button, name="Background action", match_role=true, match_name=true})
	defer destroy_find_result(&background)
	modal := find(&h, Query{role=.Button, name="Modal action", match_role=true, match_name=true})
	defer destroy_find_result(&modal)
	if !testing.expect(t, background.match == .Unique && modal.match == .Unique,
		"the workspace and modal actions should both remain semantically queryable") {
		return
	}
	if !testing.expect(t, alicorn.semantic_actions_has(background.element.actions, .Press),
		"the background action must advertise Press so the modal-scope check is meaningful") {
		return
	}

	background_point := background.element.bounds
	status = click_at(&h, background_point.x+background_point.w/2, background_point.y+background_point.h/2)
	testing.expect(t, status == .Ok && app.background_activations == 0 &&
		last_turn(&h).pointer_target != background.element.visual_node,
		"a modal backdrop should consume a physical click before it reaches the background action")

	testing.expect(t, step(&h, Input{
		kind=.Semantic_Action,
		semantic_id=background.element.semantic_id,
		semantic_action=.Press,
	}) == .Unsupported_Input,
		"a semantic Press must not activate a covered workspace action")
	testing.expect(t, step(&h, Input{kind=.Key, key=.Tab}) == .Ok,
		"Tab should traverse focus within the modal scope")
	destroy_find_result(&modal)
	modal = find(&h, Query{role=.Button, name="Modal action", match_role=true, match_name=true})
	testing.expect(t, modal.match == .Unique && modal.element.focused,
		"focus traversal should choose the modal action while the workspace is covered")
	return_status := step(&h, Input{kind=.Key, key=.Return})
	testing.expect(t, return_status == .Ok && app.modal_activations == 1 && app.background_activations == 0,
		fmt.tprintf("Return should activate only the modal action: status=%v modal=%d background=%d focus=%d",
			return_status, app.modal_activations, app.background_activations, last_turn(&h).focus))
}

Harness_Time_App :: struct {
	last_pointer_timestamp: u64,
}

harness_time_render :: proc(_app: ^Harness_Time_App, ui: ^alicorn.UI) {
	_ = alicorn.button(ui, "Target", key=alicorn.key_string("time-target"), style=alicorn.layout_style(height=30))
}

harness_time_pointer :: proc(state: rawptr, _rt: ^alicorn.Runtime, event: alicorn.Pointer_Event, _target: alicorn.Node_ID) {
	app := cast(^Harness_Time_App)state
	app.last_pointer_timestamp = event.timestamp_ns
}

@(test)
test_virtual_time_is_explicit_and_shared_with_synthetic_pointer_events :: proc(t: ^testing.T) {
	app := Harness_Time_App{}
	h, status := open(&app, harness_time_render, width=160, height=80, on_pointer=harness_time_pointer)
	if !testing.expect(t, status == .Ok) { return }
	defer close(&h)
	testing.expect(t, step(&h, Input{kind=.Time_Advance, delta_ns=50_000_000}) == .Ok,
		"one time-advance input should tick at the explicitly requested monotonic timestamp")
	testing.expect(t, last_turn(&h).input == .Time_Advance && h.now_ns == 50_000_000,
		"the turn report and harness clock should expose the same virtual time advance")
	testing.expect(t, click_at(&h, 20, 15) == .Ok && app.last_pointer_timestamp == 50_000_000,
		"synthetic pointer events should use virtual time rather than wall-clock time")
}

Harness_Generic_Text_App :: struct {
	last_event: alicorn.Application_Text_Input_Event,
	last_key_event: alicorn.Application_Text_Key_Event,
	last_owner: alicorn.Node_ID,
	event_count: int,
	key_event_count: int,
}

harness_generic_text_render :: proc(_app: ^Harness_Generic_Text_App, ui: ^alicorn.UI) {
	owner := alicorn.container_begin(
		ui,
		.Scroll_Region,
		label="Source editor",
		key=alicorn.key_string("generic-text-owner"),
		style=alicorn.layout_style(width=220, height=80),
	)
	_ = alicorn.text_input_target(ui, owner)
	alicorn.container_end(ui)
}

harness_generic_text_input :: proc(
	state: rawptr,
	_rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: alicorn.Application_Text_Input_Event,
) {
	app := cast(^Harness_Generic_Text_App)state
	app.last_event = event
	app.last_owner = owner
	app.event_count += 1
}

harness_generic_text_key :: proc(
	state: rawptr,
	_rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: alicorn.Application_Text_Key_Event,
) -> bool {
	app := cast(^Harness_Generic_Text_App)state
	app.last_key_event = event
	app.last_owner = owner
	app.key_event_count += 1
	return true
}

@(test)
test_generic_text_target_receives_commit_preedit_and_escape_cancel :: proc(t: ^testing.T) {
	app := Harness_Generic_Text_App{}
	h, status := open(
		&app,
		harness_generic_text_render,
		width=240,
		height=100,
		on_text_key=harness_generic_text_key,
		on_text_input=harness_generic_text_input,
	)
	if !testing.expect(t, status == .Ok) { return }
	defer close(&h)
	testing.expect(t, step(&h, Input{kind=.Key, key=.Tab}) == .Ok,
		"Tab should focus an application-owned text-input target")
	owner := alicorn.focused_node(h.runtime)
	testing.expect(t, alicorn.text_input_target_is_active(h.runtime, owner),
		"the focused owner should be active for generic application text input")
	testing.expect(t, step(&h, Input{kind=.Text_Commit, text="hello"}) == .Ok &&
		app.last_event.kind == .Commit && app.last_event.text == "hello" && app.last_owner == owner,
		"committed text should reach the application's generic text-input callback")
	testing.expect(t, step(&h, Input{
		kind=.Text_Preedit,
		text="かな",
		selection_start_byte=3,
		selection_end_byte=6,
	}) == .Ok && app.last_event.kind == .Preedit && app.last_event.selection_start_byte == 3 &&
		app.last_event.selection_end_byte == 6,
		"preedit should preserve UTF-8 byte selection offsets for an application-owned editor")
	testing.expect(t, step(&h, Input{kind=.Key, key=.Backspace}) == .Ok &&
		app.last_key_event.key == .Backspace && app.last_owner == owner,
		"Backspace should reach the editor callback as a logical text-editing key")
	testing.expect(t, step(&h, Input{kind=.Key, key=.Word_Left, modifiers={control=true, shift=true}}) == .Ok &&
		app.last_key_event.key == .Word_Left && app.last_key_event.control && app.last_key_event.shift,
		"word navigation and modifiers should be directly simulatable without OS scancodes")
	testing.expect(t, step(&h, Input{kind=.Key, key=.Escape}) == .Ok &&
		app.last_event.kind == .Cancel && app.last_owner == owner && app.event_count == 3 &&
		app.key_event_count == 2,
		"Escape should cancel active generic text composition through the app callback")
}

@(test)
test_open_rejects_non_finite_viewport_scale :: proc(t: ^testing.T) {
	app := Harness_Ambiguous_App{}
	_, status := open(&app, harness_ambiguous_render, scale=math.nan_f32())
	testing.expect(t, status == .Invalid_Viewport,
		"NaN scale should be rejected before runtime initialization")
}
