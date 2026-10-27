package main

import "core:testing"
import alicorn "alicorn:runtime"

@(test)
test_accessibility_set_value_updates_app_owned_controlled_text :: proc(t: ^testing.T) {
	field_id := alicorn.Semantic_ID{namespace=0x4143434F4E545201, value=1}
	text, initialized := alicorn.text_field_buffer_init("Editable value", context.allocator)
	if !initialized {
		testing.expect(t, false, "the fixture text buffer should initialize")
		return
	}
	app := App{text=text, text_semantic_id=field_id}
	defer alicorn.text_field_buffer_destroy(&app.text)

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 180})
	defer alicorn.destroy_runtime(&rt)
	actions := alicorn.semantic_actions_add({}, .Set_Value)
	testing.expect(t, alicorn.semantic_node_set(&rt, alicorn.Semantic_Node_Description{
		id=field_id,
		role=.Text_Field,
		label="Contract text field",
		value=app.text.text,
		actions=actions,
	}), "the fixture field should publish its Set_Value action")
	_ = alicorn.semantic_commit(&rt)

	testing.expect(t, alicorn.semantic_action_request(&rt, field_id, .Set_Value, text_value="AX contract value"),
		"a native accessibility SetValue should become an application request")
	testing.expect(t, accessibility_contract_adopt_requests(&app, &rt),
		"the fixture should adopt the requested value into its owned buffer")
	testing.expect(t, app.text.text == "AX contract value",
		"the next application description should expose the adopted AX value")
	_ = alicorn.semantic_node_set(&rt, alicorn.Semantic_Node_Description{
		id=field_id,
		role=.Text_Field,
		label="Contract text field",
		value=app.text.text,
		actions=actions,
	})
	_ = alicorn.semantic_commit(&rt)
	updated, updated_found := alicorn.semantic_node_lookup(&rt, field_id)
	testing.expect(t, updated_found && updated.value == "AX contract value",
		"the refreshed semantic tree should publish the application-owned value")
	_, request_remains := alicorn.semantic_request_pop(&rt)
	testing.expect(t, !request_remains, "the fixture should destroy the consumed request")
}
