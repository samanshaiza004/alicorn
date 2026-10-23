package alicorn_sdl_gpu

import "core:fmt"
import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

Controlled_Text_Update_Test_State :: struct {
	value: alicorn.Text_Field_Buffer,
	field: alicorn.Node_ID,
	changed_events: int,
	submissions: int,
}

controlled_text_update_test_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	test_state := cast(^Controlled_Text_Update_Test_State)state
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="controlled-text-update-root",
		style=alicorn.layout_style(.Column, width=f32(logical_width), height=f32(logical_height), gap=8),
	)
	alicorn.text(&ui, fmt.tprintf("query %s", test_state.value.text), key=alicorn.key_string("controlled-text-update-echo"))
	result := alicorn.text_field_controlled(
		&ui,
		&test_state.value,
		key=alicorn.key_string("controlled-text-update-field"),
		style=alicorn.layout_style(width=220, height=32),
	)
	test_state.field = result.node
	if result.changed { test_state.changed_events += 1 }
	if result.submitted { test_state.submissions += 1 }
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

@(test)
test_native_host_corrects_controlled_text_and_consumes_submit_once :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	state: Controlled_Text_Update_Test_State
	value, value_ok := alicorn.text_field_buffer_init("find", context.allocator)
	if !value_ok {
		testing.expect(t, false, "the app-owned search buffer should initialize")
		return
	}
	state.value = value
	defer alicorn.text_field_buffer_destroy(&state.value)
	application := Application{
		state=rawptr(&state),
		build=controlled_text_update_test_build,
		interaction_update_policy=.Correct_After_Interaction,
	}
	metrics := Window_Metrics{logical_width=320, logical_height=200, display_scale=1}
	timing: Native_Host_Timing

	alicorn.invalidate_root(&rt, "controlled text host test initial description")
	_ = native_application_build_until_stable(&application, &rt, &metrics, &timing)
	field := state.field
	_ = alicorn.focus(&rt, field)
	_ = alicorn.set_text_caret(&rt, field, len(state.value.text))
	change := alicorn.process_text_input(&rt, field, "!")
	if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
	result := native_application_build_until_stable(&application, &rt, &metrics, &timing)
	visible_latest_query := false
	for id in rt.order {
		if node, found := rt.nodes[id]; found && node.text == "query find!" { visible_latest_query = true }
	}
	testing.expect(t, result.stable && result.passes == 2 && state.value.text == "find!" &&
		state.changed_events == 1 && visible_latest_query,
		"committed input should update app state and the final display before presentation")
	testing.expect(t, native_text_field_submit_on_key(&rt, sdl3.K_RETURN, true, false, false) == false &&
		native_text_field_submit_on_key(&rt, sdl3.K_RETURN, false, true, false) == false,
		"key repeat and modified Return should not generate a controlled-field submit")
	testing.expect(t, native_text_field_submit_on_key(&rt, sdl3.K_RETURN, false, false, true) == false,
		"IME composition must retain Return instead of submitting the controlled field")
	testing.expect(t, native_text_field_submit_on_key(&rt, sdl3.K_RETURN, false, false, false),
		"an unmodified Return should queue one submit after the app declines the key")
	result = native_application_build_until_stable(&application, &rt, &metrics, &timing)
	testing.expect(t, result.stable && result.passes == 2 && state.submissions == 1,
		"the submit response should be delivered once, then stabilized before presentation")
	alicorn.invalidate_root(&rt, "controlled text submit one-shot test")
	_ = native_application_build_until_stable(&application, &rt, &metrics, &timing)
	testing.expect(t, state.submissions == 1, "later descriptions must not replay a consumed submit")
}
