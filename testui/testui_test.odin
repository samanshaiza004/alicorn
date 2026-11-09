package testui

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:math"
import "core:time"
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

Harness_Full_Build_App :: struct {
	descriptions: int,
	activations: int,
	width, height: int,
	scale: f32,
}

harness_test_full_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Harness_Full_Build_App)state
	app.descriptions += 1
	app.width = logical_width
	app.height = logical_height
	app.scale = dpi_scale
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(&ui, .Root, label="full-application-root",
		style=alicorn.layout_style(.Column, grow=1))
	if alicorn.button(&ui, "Save", key=alicorn.key_string("full-build-save"),
		style=alicorn.layout_style(height=32)) {
		app.activations += 1
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

@(test)
test_public_harness_runs_full_application_build_callback :: proc(t: ^testing.T) {
	app := Harness_Full_Build_App{}
	_, empty_status := open(&app, width=240, height=120)
	testing.expect(t, empty_status == .Invalid_Application,
		"open should reject an application with no render or full-build callback")

	h, status := open(&app, width=240, height=120, scale=2,
		build_application=harness_test_full_build)
	if !testing.expect(t, status == .Ok, last_turn_diagnostic(&h)) { return }
	defer close(&h)
	testing.expect(t, app.descriptions == 1 && app.width == 240 && app.height == 120 && app.scale == 2,
		"the full application callback should receive the configured viewport and scale")

	save := find(&h, Query{role=.Button, name="Save", match_role=true, match_name=true})
	defer destroy_find_result(&save)
	if !testing.expect(t, save.match == .Unique && save.element.has_bounds,
		"full application semantics should be queryable after its normal frame lifecycle") {
		return
	}
	if !testing.expect(t, click(&h, &save.element) == .Ok,
		"physical input should drive controls from the full application build") {
		return
	}
	testing.expect(t, app.activations == 1 && app.descriptions > 1,
		"input should reach the application and rerun its production-style build callback")
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

Harness_Visual_Transition_App :: struct {
	descriptions: int,
	theme: alicorn.Style_Theme_ID,
}

harness_visual_transition_render :: proc(app: ^Harness_Visual_Transition_App, ui: ^alicorn.UI) {
	app.descriptions += 1
	root := alicorn.container_begin(ui, .Root, key=alicorn.key_string("transition-root"),
		style=alicorn.layout_style(.Column, grow=1))
	if root != 0 {
		if app.theme == 0 {
			theme := alicorn.DEFAULT_STYLE_THEME
			recipe := theme.button_recipes.recipes[int(alicorn.Button_Variant.Default)]
			recipe.hover_fill_transition = alicorn.Style_Transition{
				duration=300*time.Millisecond,
				easing=.Ease,
			}
			theme.button_recipes.recipes[int(alicorn.Button_Variant.Default)] = recipe
			app.theme = alicorn.style_theme_register(ui.runtime, theme)
		}
		scope := alicorn.style_environment_push(ui, alicorn.Style_Environment{theme=app.theme})
		_ = alicorn.button(ui, "Transition target", key=alicorn.key_string("transition-button"),
			style=alicorn.layout_style(width=200, height=40))
		alicorn.style_environment_pop(ui, scope)
		alicorn.container_end(ui)
	}
}

harness_visual_transition_fill :: proc(rt: ^alicorn.Runtime, owner: alicorn.Node_ID) -> (fill: alicorn.Color, found: bool) {
	node, ok := rt.nodes[owner]
	if !ok || node == nil { return }
	for command in node.paint {
		if command.bounds != node.bounds { continue }
		if surface, is_surface := command.payload.(alicorn.Surface_Paint); is_surface {
			return surface.fill, true
		}
	}
	return {}, false
}

harness_visual_transition_color_near :: proc(a, b: alicorn.Color, epsilon: f32) -> bool {
	return math.abs(a.r-b.r) <= epsilon && math.abs(a.g-b.g) <= epsilon &&
		math.abs(a.b-b.b) <= epsilon && math.abs(a.a-b.a) <= epsilon
}

@(test)
test_button_hover_fill_transition_is_retained_reversible_and_inspector_independent :: proc(t: ^testing.T) {
	app := Harness_Visual_Transition_App{}
	h, status := open(&app, harness_visual_transition_render, width=320, height=120)
	if !testing.expect(t, status == .Ok, last_turn_diagnostic(&h)) { return }
	defer close(&h)
	result := find(&h, Query{
		role=.Button,
		name="Transition target",
		key=alicorn.key_string("transition-button"),
		match_role=true,
		match_name=true,
		match_key=true,
	})
	defer destroy_find_result(&result)
	if !testing.expect(t, result.match == .Unique && result.element.has_bounds,
		"the transition fixture should expose one physically clickable button") { return }
	owner := result.element.visual_node
	initial_fill, initial_found := harness_visual_transition_fill(h.runtime, owner)
	track, track_found := h.runtime.style_transition_owners[owner]
	if !testing.expect(t, initial_found && track_found && !track.active && track.presented_mix == 0,
		"the first resting frame should establish the independent style-transition baseline") { return }

	// Inspector resolution may populate the ordinary computed-style cache. It
	// must not become the transition system's adopted hover target.
	_ = alicorn.style_button_resolve_retained(h.runtime, h.runtime.nodes[owner],
		alicorn.Button_Visual_State{hovered=true})
	bounds := result.element.bounds
	if !testing.expect(t, step(&h, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{
		kind=.Move, x=bounds.x+bounds.w*0.5, y=bounds.y+bounds.h*0.5,
	}}) == .Ok, "physical pointer motion should enter the button") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found := harness_visual_transition_fill(h.runtime, owner)
	activity := alicorn.motion_activity(h.runtime)
	if !testing.expect(t, fill_found && fill == track.pair.rest.surface && track.active &&
		activity.active_owners == 1 && activity.active_properties == 1,
		"hover should begin at the resting fill and schedule a retained transition") { return }
	transition_event, transition_event_found := alicorn.motion_diagnostics_event_recent(h.runtime, 0)
	if !testing.expect(t, transition_event_found &&
		transition_event.kind == .Style_Transition_Retarget &&
		transition_event.style_transition_sample && transition_event.owner.valid &&
		transition_event.style_transition_duration_ns == 300_000_000,
		"the bounded motion diagnostics should identify the owner, target and duration") { return }
	if !testing.expect(t, app.descriptions == 1 && last_turn(&h).descriptions == 0,
		"hover and transition setup should not rerun the application description") { return }

	if !testing.expect(t, advance_time(&h, 90_000_000) == .Ok,
		"virtual time should advance the hover transition without pointer input") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found = harness_visual_transition_fill(h.runtime, owner)
	if !testing.expect(t, fill_found && track.presented_mix > 0.50 && track.presented_mix < 0.53 &&
		last_turn(&h).work.descriptions_emitted == 0 && last_turn(&h).work.layout_nodes_visited == 0 &&
		last_turn(&h).work.text_shape_requests == 0,
		"the eased sample should visibly interpolate without descriptions, layout, or reshaping") { return }
	first_sample := track.presented_mix

	if !testing.expect(t, step(&h, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Move, x=310, y=110}}) == .Ok,
		"moving off the button should reverse the same hover transition") { return }
	track = h.runtime.style_transition_owners[owner]
	if !testing.expect(t, track.active && track.segment.target_mix == 0 &&
		math.abs(track.segment.start_mix-first_sample) < 0.001 &&
		track.segment.duration_ns >= 153_000_000 && track.segment.duration_ns <= 155_000_000,
		"exit should start from the eased visual sample and shorten by remaining visual distance") { return }

	if !testing.expect(t, advance_time(&h, 50_000_000) == .Ok,
		"the reversed segment should continue on explicit virtual time") { return }
	track = h.runtime.style_transition_owners[owner]
	before_reversal := track.presented_mix
	if !testing.expect(t, before_reversal > 0 && before_reversal < first_sample,
		"the exit sample should move continuously back toward the original resting endpoint") { return }
	if !testing.expect(t, step(&h, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{
		kind=.Move, x=bounds.x+bounds.w*0.5, y=bounds.y+bounds.h*0.5,
	}}) == .Ok, "re-entering should reverse without replacing the original endpoint pair") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found = harness_visual_transition_fill(h.runtime, owner)
	if !testing.expect(t, track.active && track.segment.target_mix == 1 &&
		math.abs(track.segment.start_mix-before_reversal) < 0.001 && fill_found &&
		harness_visual_transition_color_near(fill,
			style_transition_test_color_mix(track.pair.rest.surface, track.pair.hover.surface, f32(before_reversal)), 0.0001),
		"re-entering should preserve the current sample and both original style endpoints") { return }

	final_duration := track.segment.duration_ns
	if !testing.expect(t, advance_time(&h, final_duration+1) == .Ok,
		"the latest target should complete without further pointer movement") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found = harness_visual_transition_fill(h.runtime, owner)
	activity = alicorn.motion_activity(h.runtime)
	if !testing.expect(t, fill_found && fill == track.pair.hover.surface && !track.active &&
		activity.active_owners == 0 && !alicorn.presentation_needs_frame(h.runtime),
		"the exact hover endpoint should be painted before the scheduler returns to true idle") { return }
	settled_event, settled_event_found := alicorn.motion_diagnostics_event_recent(h.runtime, 0)
	if !testing.expect(t, settled_event_found && settled_event.kind == .Style_Transition_Settled &&
		settled_event.style_transition_mix == 1 && settled_event.style_transition_target_hovered,
		"transition settlement should be reported without impersonating an explicit spring owner") { return }
	work := last_turn(&h).work
	testing.expect(t, work.descriptions_emitted == 0 && work.layout_nodes_visited == 0 &&
		work.text_shape_requests == 0,
		"all transition-only turns should preserve application state without layout or shaping work")

	if !testing.expect(t, step(&h, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Move, x=310, y=110}}) == .Ok,
		"hover exit should begin another transition before the accessibility snap test") { return }
	track = h.runtime.style_transition_owners[owner]
	if !testing.expect(t, track.active &&
		alicorn.style_root_accessibility_set(h.runtime, alicorn.Accessibility_Appearance_Preferences{reduce_motion=true}),
		"Reduced Motion should be accepted as a root appearance change while the fill is moving") { return }
	if !testing.expect(t, advance_time(&h, 0) == .Ok,
		"the accessibility update should be applied at the next deterministic turn") { return }
	fill, fill_found = harness_visual_transition_fill(h.runtime, owner)
	_, track_found = h.runtime.style_transition_owners[owner]
	snap_event, snap_event_found := alicorn.motion_diagnostics_event_recent(h.runtime, 0)
	activity = alicorn.motion_activity(h.runtime)
	if !testing.expect(t, fill_found && fill == track.pair.rest.surface && !track_found &&
		activity.active_owners == 0 && snap_event_found &&
		snap_event.kind == .Style_Transition_Snap &&
		snap_event.reason == .Style_Transition_Accessibility_Preference,
		"Reduced Motion should snap to the current resolved target, cancel the track and report why") { return }
}

@(test)
test_button_hover_transition_uses_current_time_after_idle_gap :: proc(t: ^testing.T) {
	app := Harness_Visual_Transition_App{}
	h, status := open(&app, harness_visual_transition_render, width=320, height=120)
	if !testing.expect(t, status == .Ok, last_turn_diagnostic(&h)) { return }
	defer close(&h)
	result := find(&h, Query{
		role=.Button,
		name="Transition target",
		key=alicorn.key_string("transition-button"),
		match_role=true,
		match_name=true,
		match_key=true,
	})
	defer destroy_find_result(&result)
	if !testing.expect(t, result.match == .Unique && result.element.has_bounds,
		"the transition fixture should expose one physically clickable button") { return }
	owner := result.element.visual_node
	initial_fill, initial_found := harness_visual_transition_fill(h.runtime, owner)
	track, track_found := h.runtime.style_transition_owners[owner]
	if !testing.expect(t, initial_found && track_found && !track.active,
		"the initial frame should establish the resting button style") { return }

	// Model native idle: host time advances, but no application description or
	// motion wake runs to refresh the runtime's injected clock.
	h.now_ns = 5_000_000_000
	bounds := result.element.bounds
	if !testing.expect(t, step(&h, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{
		kind=.Move, x=bounds.x+bounds.w*0.5, y=bounds.y+bounds.h*0.5,
	}}) == .Ok, "pointer entry after idle should flush retained hover paint") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found := harness_visual_transition_fill(h.runtime, owner)
	if !testing.expect(t, fill_found && fill == track.pair.rest.surface && track.active,
		"the first retained hover frame should still show the resting fill") { return }

	if !testing.expect(t, advance_time(&h, 90_000_000) == .Ok,
		"the transition should make progress after an idle gap") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found = harness_visual_transition_fill(h.runtime, owner)
	if !testing.expect(t, track.active && track.segment.start_time == alicorn.Motion_Time(5_000_000_000) &&
		track.presented_mix > 0.50 && track.presented_mix < 0.53 && fill_found &&
		app.descriptions == 1 && last_turn(&h).descriptions == 0,
		"hover should progress from the current monotonic time without rebuilding the app") { return }

	if !testing.expect(t, advance_time(&h, 199_999_999) == .Ok,
		"the transition should remain active until its full duration elapses") { return }
	track = h.runtime.style_transition_owners[owner]
	if !testing.expect(t, track.active && track.presented_mix < 1,
		"the hover transition should not settle before 300 ms of active time") { return }
	if !testing.expect(t, advance_time(&h, 10_000_001) == .Ok,
		"the transition should settle at its 300 ms endpoint") { return }
	track = h.runtime.style_transition_owners[owner]
	fill, fill_found = harness_visual_transition_fill(h.runtime, owner)
	testing.expect(t, fill_found && fill == track.pair.hover.surface && !track.active,
		"the final hover color should appear exactly when the full duration elapses")
}

style_transition_test_color_mix :: proc(from, to: alicorn.Color, amount: f32) -> alicorn.Color {
	return alicorn.Color{
		from.r+(to.r-from.r)*amount,
		from.g+(to.g-from.g)*amount,
		from.b+(to.b-from.b)*amount,
		from.a+(to.a-from.a)*amount,
	}
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
