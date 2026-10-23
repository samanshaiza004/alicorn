package alicorn

import "core:mem"
import "core:testing"
import odin "base:runtime"

text_input_target_suspension_test_render :: proc(rt: ^Runtime, include_target: bool) -> Node_ID {
	invalidate_root(rt, "text-input target suspension test")
	ui, should_build := begin_frame(rt)
	if !should_build { return 0 }
	container_begin(&ui, .Root, label="text-input-suspension-root", key=key_string("text-input-suspension-root"))
	owner := container_begin_ex(
		&ui,
		.Scroll_Region,
		site("runtime/text_input_test.odin", 1, 1, "suspension-owner"),
		label="editor input owner",
		key="suspension-owner",
		explicit_key=true,
		style=layout_style(width=240, height=64),
	)
	if include_target { _ = text_input_target(&ui, owner) }
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return owner
}

@(test)
test_text_input_target_suspend_resume_after_target_omitted :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)

	owner := text_input_target_suspension_test_render(&rt, true)
	testing.expect(t, owner != 0 && text_input_target_is_active(&rt, owner),
		"a described generic text target should begin eligible")
	if owner == 0 || !text_input_target_is_active(&rt, owner) { return }
	testing.expect(t, text_input_target_set_suspended(&rt, owner, true),
		"a live generic target should be suspendable")
	testing.expect(t, text_input_target_is_suspended(&rt, owner) && !text_input_target_is_active(&rt, owner),
		"suspension should immediately remove the target from native eligibility")
	testing.expect(t, !text_input_target_area_set(&rt, owner, Text_Input_Area{rect=Rect{0, 0, 4, 16}}),
		"suspended targets should not update native candidate geometry")

	owner_after_omission := text_input_target_suspension_test_render(&rt, false)
	testing.expect(t, owner_after_omission == owner && !text_input_target_is_active(&rt, owner),
		"omitting the marker on a later description should retain suspension without changing node identity")
	testing.expect(t, text_input_target_is_suspended(&rt, owner),
		"description reconciliation must not silently clear application suspension")
	testing.expect(t, text_input_target_set_suspended(&rt, owner, false),
		"the owner should be resumable after a description omitted its target marker")
	testing.expect(t, !text_input_target_is_suspended(&rt, owner),
		"resume should clear only the suspension flag")
	owner_again := text_input_target_suspension_test_render(&rt, true)
	testing.expect(t, owner_again == owner && text_input_target_is_active(&rt, owner),
		"re-describing a resumed target should restore native eligibility")

	text_input_target_set_suspended(&rt, owner, true)
	testing.expect(t, !text_input_target_set_suspended(&rt, owner, true),
		"repeating the same suspension should be an idempotent no-op")
	text_input_target_set_suspended(&rt, owner, false)
}

TEXT_INPUT_ALLOCATOR_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

Controlled_Text_Field_Test_State :: struct {
	value: Text_Field_Buffer,
	result: Text_Field_Response,
}

Controlled_Text_Field_Test_Mode :: enum { Controlled, Omitted, Text, Uncontrolled }

controlled_text_field_test_render :: proc(rt: ^Runtime, state: ^Controlled_Text_Field_Test_State, mode: Controlled_Text_Field_Test_Mode = .Controlled) -> Node_ID {
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("controlled-text-field-root"), style=layout_style(.Column, grow=1, gap=8))
	field_loc := odin.Source_Code_Location{"runtime/text_input_test.odin", 1, 1, "controlled_text_field_test_render"}
	field_key := key_string("controlled-text-field-input")
	field_style := layout_style(width=240, height=40)
	state.result = {}
	field: Node_ID
	switch mode {
	case .Controlled:
		state.result = text_field_controlled(&ui, &state.value, key=field_key, style=field_style, loc=field_loc)
		field = state.result.node
	case .Omitted:
	case .Text:
		// Use the same source and key to exercise a real kind change, rather
		// than retirement followed by an unrelated text node.
		field = emit_key(&ui, .Text,
			Source_Site{field_loc.file_path, int(field_loc.line), int(field_loc.column), "text_field"},
			text="replacement label", key=field_key, style=field_style)
	case .Uncontrolled:
		field = text_field(&ui, "uncontrolled", key=field_key, style=field_style, loc=field_loc)
	}
	text(&ui, state.value.text, key=key_string("controlled-text-field-echo"))
	container_end(&ui)
	end_frame(&ui)
	return field
}

@(test)
test_controlled_text_field_adopts_commits_but_not_ime_preedit :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	state: Controlled_Text_Field_Test_State
	value, value_ok := text_field_buffer_init("seed", context.allocator)
	if !value_ok {
		testing.expect(t, false, "the app-owned field buffer should initialize")
		return
	}
	state.value = value
	defer text_field_buffer_destroy(&state.value)

	invalidate_root(&rt, "controlled text field initial description")
	field := controlled_text_field_test_render(&rt, &state)
	testing.expect(t, field != 0 && state.value.text == "seed", "the controlled field should start from the application value")
	if field == 0 { return }
	_ = focus(&rt, field)
	_ = set_text_caret(&rt, field, len(state.value.text))
	testing.expect(t, process_text_editing(&rt, field, "preedit", 0, 0), "the field should accept an IME preedit")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "seed" && !state.result.changed,
		"IME preedit must remain transient and must not mutate application-owned committed text")
	change := process_text_input(&rt, field, "!")
	if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "seed!" && state.result.changed,
		"a committed input event should be copied into the app-owned buffer on the next description")
	testing.expect(t, state.result.node == field, "controlled adoption must preserve the retained field identity")
	testing.expect(t, text_field_buffer_set(&state.value, "programmatic"), "the app should be able to replace controlled text explicitly")
	invalidate_root(&rt, "controlled text field programmatic replacement")
	_ = controlled_text_field_test_render(&rt, &state)
	retained, retained_found := rt.nodes[field]
	testing.expect(t, retained_found, "the controlled field should remain retained after a programmatic update")
	if retained_found {
		testing.expect(t, retained.text == "programmatic", "the retained field should adopt the new app-owned text")
	}
	testing.expect(t, !state.result.changed, "programmatic text replacement should not be reported as a user edit")
	text_field_buffer_destroy(&state.value)

	value, value_ok = text_field_buffer_init("submit", context.allocator)
	if !value_ok { return }
	state.value = value
	invalidate_root(&rt, "controlled text field programmatic update")
	field = controlled_text_field_test_render(&rt, &state)
	_ = focus(&rt, field)
	testing.expect(t, text_field_request_submit(&rt, field), "a focused controlled field should accept one submit request")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.result.submitted, "the next controlled description should consume the submit result once")
	invalidate_root(&rt, "controlled text field submit consumed")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, !state.result.submitted, "a consumed submit must not replay on later descriptions")
}

@(test)
test_controlled_text_field_programmatic_value_wins_over_unadopted_commit :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	state: Controlled_Text_Field_Test_State
	buffer_ok: bool
	state.value, buffer_ok = text_field_buffer_init("seed", context.allocator)
	testing.expect(t, buffer_ok, "the application buffer should initialize")
	if !buffer_ok { return }
	defer text_field_buffer_destroy(&state.value)

	field := controlled_text_field_test_render(&rt, &state)
	testing.expect(t, field != 0 && set_text_caret(&rt, field, 4), "the field should accept input after its initial value")
	change := process_text_input(&rt, field, "!")
	testing.expect(t, change.changed && change.text == "seed!" && state.value.text == "seed",
		"committed input should remain unadopted until the next controlled description")
	text_change_destroy(&rt, &change)

	testing.expect(t, text_field_buffer_set(&state.value, "reset"), "the application should replace its value before adoption")
	invalidate_root(&rt, "programmatic value before commit adoption")
	testing.expect(t, controlled_text_field_test_render(&rt, &state) == field, "a programmatic replacement should preserve field identity")
	retained, found := text_field_value(&rt, field)
	testing.expect(t, found && retained == "reset" && state.value.text == "reset" && !state.result.changed,
		"an application value differing from its last description should override the unadopted native edit")

	invalidate_root(&rt, "unadopted commit must not replay")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "reset" && !state.result.changed, "the overridden commit should not replay")
	_ = set_text_caret(&rt, field, 5)
	change = process_text_input(&rt, field, "?")
	text_change_destroy(&rt, &change)
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "reset?" && state.result.changed,
		"a subsequent native edit should still be adopted after the programmatic replacement")
}

@(test)
test_controlled_text_field_equal_programmatic_value_adopts_unadopted_commit :: proc(t: ^testing.T) {
	cases := []bool{false, true}
	for round_trip in cases {
		rt := new_runtime(Rect{0, 0, 320, 120})
		defer destroy_runtime(&rt)
		state: Controlled_Text_Field_Test_State
		buffer_ok: bool
		state.value, buffer_ok = text_field_buffer_init("seed", context.allocator)
		testing.expect(t, buffer_ok, "the application buffer should initialize")
		if !buffer_ok { return }
		defer text_field_buffer_destroy(&state.value)
		field := controlled_text_field_test_render(&rt, &state)
		_ = set_text_caret(&rt, field, 4)
		change := process_text_input(&rt, field, "!")
		testing.expect(t, change.changed && change.text == "seed!", "the field should have an unadopted native edit")
		text_change_destroy(&rt, &change)
		if round_trip {
			testing.expect(t, text_field_buffer_set(&state.value, "temporary"), "the application should be able to replace its value")
		}
		testing.expect(t, text_field_buffer_set(&state.value, "seed"), "the application should set the last described value")
		invalidate_root(&rt, "same value before native edit adoption")
		_ = controlled_text_field_test_render(&rt, &state)
		retained, found := text_field_value(&rt, field)
		testing.expect(t, found && retained == "seed!" && state.value.text == "seed!" && state.result.changed,
			"an equal app value should adopt the pending edit even after an undescribed round trip through a different value")
	}
}

@(test)
test_controlled_text_field_programmatic_reset_cancels_active_ime :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	rt := new_runtime(Rect{0, 0, 320, 120}, Runtime_Config{persistent_allocator=mem.tracking_allocator(&tracking)})
	defer {
		destroy_runtime(&rt)
		testing.expect(t, len(tracking.allocation_map) == 0 && len(tracking.bad_free_array) == 0,
			"reset and destruction should release the IME projection and runtime snapshots through their allocator")
	}
	font_ok := font_load_bytes(&rt, .UI, TEXT_INPUT_ALLOCATOR_TEST_FONT)
	testing.expect(t, font_ok, "the fixture should load a font to exercise retained IME presentation")
	if !font_ok { return }
	state: Controlled_Text_Field_Test_State
	buffer_ok: bool
	state.value, buffer_ok = text_field_buffer_init("seed", context.allocator)
	testing.expect(t, buffer_ok, "the application buffer should initialize")
	if !buffer_ok { return }
	defer text_field_buffer_destroy(&state.value)

	field := controlled_text_field_test_render(&rt, &state)
	testing.expect(t, field != 0 && set_text_selection(&rt, field, 1, 3), "IME should replace the selected committed text")
	testing.expect(t, process_text_editing(&rt, field, "preedit", 2, 1), "the field should begin composition")
	_ = controlled_text_field_test_render(&rt, &state)
	interaction, found := text_field_interaction(&rt, field)
	testing.expect(t, found && interaction.composition_active && state.value.text == "seed" && !state.result.changed,
		"the application should keep committed text while IME owns the preedit")
	testing.expect(t, !text_field_request_submit(&rt, field), "Return during IME should not submit the field")

	testing.expect(t, text_field_buffer_set(&state.value, ""), "the application should reset committed text during composition")
	invalidate_root(&rt, "programmatic reset during IME")
	testing.expect(t, controlled_text_field_test_render(&rt, &state) == field, "reset should preserve field identity")
	retained, value_found := text_field_value(&rt, field)
	interaction, found = text_field_interaction(&rt, field)
	testing.expect(t, value_found && retained == "" && !state.result.changed && !state.result.submitted,
		"a reset should replace the retained value without reporting a native edit or submit")
	testing.expect(t, found && interaction.focused && !interaction.composition_active &&
		interaction.caret == 0 && !interaction.has_selection,
		"reset should cancel IME and clamp the selection to the new empty value while preserving focus")
	testing.expect(t, !cancel_text_composition(&rt, field), "the reset should have already released the active composition")

	change := process_text_input(&rt, field, "new")
	testing.expect(t, change.changed && change.text == "new", "input after reset should use the new value and selection")
	text_change_destroy(&rt, &change)
	testing.expect(t, text_field_request_submit(&rt, field), "reset should release IME's ownership of Return")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "new" && state.result.changed && state.result.submitted,
		"subsequent committed input and submit should reach the application normally")
}

@(test)
test_controlled_text_field_removal_discards_pending_commit_and_submit :: proc(t: ^testing.T) {
	controlled_text_field_test_pending_lifecycle(t, .Omitted)
}

@(test)
test_controlled_text_field_retyping_discards_pending_commit_and_submit :: proc(t: ^testing.T) {
	controlled_text_field_test_pending_lifecycle(t, .Text)
}

@(test)
test_controlled_text_field_uncontrolled_description_discards_pending_commit_and_submit :: proc(t: ^testing.T) {
	controlled_text_field_test_pending_lifecycle(t, .Uncontrolled)
}

controlled_text_field_test_pending_lifecycle :: proc(t: ^testing.T, mode: Controlled_Text_Field_Test_Mode) {
	runtime_tracking, app_tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&runtime_tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&runtime_tracking)
	mem.tracking_allocator_init(&app_tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&app_tracking)
	rt := new_runtime(Rect{0, 0, 320, 120}, Runtime_Config{persistent_allocator=mem.tracking_allocator(&runtime_tracking)})
	defer {
		destroy_runtime(&rt)
		testing.expect(t, len(runtime_tracking.allocation_map) == 0 && len(runtime_tracking.bad_free_array) == 0,
			"field lifecycle changes and destruction should release all runtime-owned text and snapshots")
	}
	state: Controlled_Text_Field_Test_State
	buffer_ok: bool
	state.value, buffer_ok = text_field_buffer_init("seed", mem.tracking_allocator(&app_tracking))
	testing.expect(t, buffer_ok, "the application buffer should initialize with its own allocator")
	if !buffer_ok { return }
	defer {
		text_field_buffer_destroy(&state.value)
		testing.expect(t, len(app_tracking.allocation_map) == 0 && len(app_tracking.bad_free_array) == 0,
			"the application should release its buffer independently of the runtime")
	}

	field := controlled_text_field_test_render(&rt, &state)
	testing.expect(t, field != 0 && set_text_caret(&rt, field, 4), "the field should be ready for native input")
	change := process_text_input(&rt, field, "!")
	testing.expect(t, change.changed && change.text == "seed!", "the field should have a committed edit awaiting adoption")
	text_change_destroy(&rt, &change)
	testing.expect(t, text_field_request_submit(&rt, field), "the edited field should also have a pending submit")
	testing.expect(t, !text_field_request_submit(&rt, field), "a pending submit should not queue twice")
	testing.expect(t, state.value.text == "seed", "the application should not yet have adopted the native edit")

	replacement := controlled_text_field_test_render(&rt, &state, mode)
	if mode == .Omitted {
		_, found := node_info(&rt, field)
		testing.expect(t, replacement == 0 && !found, "omission should retire the field before pending events are consumed")
	} else {
		testing.expect(t, replacement == field, "replacement should reuse the actual retained field identity")
	}
	if mode == .Uncontrolled {
		value, found := text_field_value(&rt, field)
		testing.expect(t, found && value == "uncontrolled", "the low-level field should use its explicitly described value")
	} else {
		_, found := text_field_value(&rt, field)
		testing.expect(t, !found, "the old identity should no longer expose a text field")
		change = process_text_input(&rt, field, "stale")
		testing.expect(t, !change.changed, "a removed or retyped field should reject stale committed input")
		text_change_destroy(&rt, &change)
		testing.expect(t, !process_text_editing(&rt, field, "stale preedit", 0, 0), "a removed or retyped field should reject stale IME input")
	}
	testing.expect(t, !text_field_request_submit(&rt, field), "the old field should no longer accept a controlled submit")
	testing.expect(t, state.value.text == "seed", "retiring the controlled binding must not mutate app-owned text")

	invalidate_root(&rt, "restore controlled description after pending events were discarded")
	testing.expect(t, controlled_text_field_test_render(&rt, &state) == field, "the same source and key should restore the field identity")
	value, found := text_field_value(&rt, field)
	testing.expect(t, found && value == "seed" && state.value.text == "seed" && !state.result.changed && !state.result.submitted,
		"restoring a controlled field must use app text without replaying the old edit or submit")
	_ = set_text_caret(&rt, field, 4)
	change = process_text_input(&rt, field, "?")
	text_change_destroy(&rt, &change)
	testing.expect(t, text_field_request_submit(&rt, field), "the restored controlled field should accept a fresh submit")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "seed?" && state.result.changed && state.result.submitted,
		"fresh native edits and submits should work after restoring the controlled field")
	invalidate_root(&rt, "fresh controlled events consumed")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, !state.result.changed && !state.result.submitted, "fresh events should also be consumed only once")
}

@(test)
test_controlled_text_field_buffer_is_borrowed_only_during_description :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	state: Controlled_Text_Field_Test_State
	buffer_ok: bool
	state.value, buffer_ok = text_field_buffer_init("seed", mem.tracking_allocator(&tracking))
	testing.expect(t, buffer_ok, "the application should initialize the owning buffer")
	if !buffer_ok { return }
	defer text_field_buffer_destroy(&state.value)
	field := controlled_text_field_test_render(&rt, &state)
	testing.expect(t, field != 0, "the runtime should copy the described value")

	text_field_buffer_destroy(&state.value)
	testing.expect(t, len(tracking.allocation_map) == 0 && len(tracking.bad_free_array) == 0,
		"the application may release its buffer after description")
	retained, found := text_field_value(&rt, field)
	testing.expect(t, found && retained == "seed", "retained text must remain valid independently of the application allocation")
	_ = set_text_caret(&rt, field, 4)
	change := process_text_input(&rt, field, "!")
	testing.expect(t, change.changed && change.text == "seed!", "native input should operate on the runtime's copy")
	text_change_destroy(&rt, &change)
	testing.expect(t, !state.value.initialized && len(tracking.allocation_map) == 0,
		"native input between descriptions must not access or allocate through the former buffer")

	state.value, buffer_ok = text_field_buffer_init("seed", mem.tracking_allocator(&tracking))
	testing.expect(t, buffer_ok, "the application may supply a freshly initialized owner on the next description")
	if !buffer_ok { return }
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, state.value.text == "seed!" && state.result.changed,
		"a new buffer with the last described value should adopt the pending commit")
	text_field_buffer_destroy(&state.value)
	testing.expect(t, len(tracking.allocation_map) == 0 && len(tracking.bad_free_array) == 0,
		"destroying the new owner should release both its initial and adopted text allocations")
}

@(test)
test_controlled_text_field_runtime_snapshot_released_on_destroy :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	rt := new_runtime(
		Rect{0, 0, 320, 120},
		Runtime_Config{persistent_allocator=mem.tracking_allocator(&tracking)},
	)
	runtime_alive := true
	defer { if runtime_alive { destroy_runtime(&rt) } }
	state: Controlled_Text_Field_Test_State
	value, value_ok := text_field_buffer_init("owned", context.allocator)
	if !value_ok {
		testing.expect(t, false, "the app-owned field buffer should initialize")
		return
	}
	state.value = value
	defer text_field_buffer_destroy(&state.value)

	invalidate_root(&rt, "controlled field allocator lifecycle test")
	_ = controlled_text_field_test_render(&rt, &state)
	testing.expect(t, len(rt.controlled_text_fields) == 1,
		"the runtime should retain only its own committed-value snapshot for the active controlled field")
	if len(tracking.allocation_map) == 0 {
		testing.expect(t, false, "the runtime fixture should have tracked retained allocations before destruction")
		return
	}
	destroy_runtime(&rt)
	runtime_alive = false
	testing.expect(t, len(tracking.allocation_map) == 0,
		"runtime destruction should release the controlled-field snapshot and its sidecar storage")
}

text_input_allocator_test_render :: proc(rt: ^Runtime) -> Node_ID {
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("text-input-allocator-root"), style=layout_style(.Column, grow=1))
	id := text_field(
		&ui,
		"seed",
		key=key_string("text-input-allocator-field"),
		style=layout_style(width=240, height=40),
	)
	container_end(&ui)
	end_frame(&ui)
	return id
}

@(test)
test_text_composition_projection_uses_runtime_allocator :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	rt := new_runtime(
		Rect{0, 0, 320, 120},
		Runtime_Config{persistent_allocator=mem.tracking_allocator(&tracking)},
	)
	runtime_alive := true
	defer { if runtime_alive { destroy_runtime(&rt) } }
	if !text_engine_load_font(&rt.text_engine, TEXT_INPUT_ALLOCATOR_TEST_FONT) {
		testing.expect(t, false, "the composition allocator fixture should load its UI font")
		return
	}
	field := text_input_allocator_test_render(&rt)
	if field == 0 {
		testing.expect(t, false, "the composition allocator fixture should retain its text field")
		return
	}
	testing.expect(t, process_text_editing(&rt, field, "preedit", 0, 0),
		"a focused text field should accept a preedit update")
	updated_field := text_input_allocator_test_render(&rt)
	node, found := rt.nodes[updated_field]
	testing.expect(t, found && node.composition_run_valid && node.composition_run.value == "seedpreedit",
		"rendering IME preedit with a distinct runtime allocator should retain the projected run")

	destroy_runtime(&rt)
	runtime_alive = false
	testing.expect(t, len(tracking.allocation_map) == 0,
		"the runtime should release all preedit projection and retained allocations through their owners")
}
