package alicorn

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
