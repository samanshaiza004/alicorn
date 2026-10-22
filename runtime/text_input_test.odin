package alicorn

import "core:mem"
import "core:testing"

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
