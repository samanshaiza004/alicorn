package alicorn

import "core:testing"

semantic_range_value_test_render :: proc(rt: ^Runtime, value_text: string) -> (
	id: Semantic_ID,
	annotated: bool,
	invalid_annotation: bool,
	expected_numeric_value: f64,
) {
	invalidate_root(rt, "semantic range value test")
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin(&ui, .Root, key=key_string("semantic-range-root"), style=layout_style(.Column, gap=4))
	text(&ui, "Not a slider", key=key_string("ordinary-text"))
	invalid_annotation = semantic_range_value_text(&ui, "ignored")
	slider := slider_f32(&ui, "Gain", 0.65, 0, 1, 0.05, key=key_string("gain"))
	expected_numeric_value = f64(slider.value)
	description := &rt.pending[len(rt.pending)-1].description
	id = semantic_visual_id(description.id)
	annotated = semantic_range_value_text(&ui, value_text)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_semantic_range_value_text_preserves_numeric_value :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)

	id, annotated, invalid_annotation, expected_numeric_value := semantic_range_value_test_render(&rt, "65%")
	entity, found := rt.semantic_entities[id]
	node := entity.node
	testing.expect(t, annotated && !invalid_annotation, "only the immediately preceding slider should accept range value text")
	testing.expect(t, found && node.role == .Slider && node.label == "Gain" && node.value == "65%",
		"the semantic slider should retain its label and formatted value")
	testing.expect(t, node.has_numeric_value, "slider should retain its numeric-value marker")
	testing.expect(t, node.numeric_value == expected_numeric_value, "formatted text should preserve the current numeric value")
	testing.expect(t, node.numeric_minimum == 0 && node.numeric_maximum == 1, "formatted text should preserve numeric bounds")
	testing.expect(t, node.numeric_step == f64(f32(0.05)), "formatted text should preserve the configured numeric step")

	updated_id, updated_annotated, updated_invalid, updated_numeric_value := semantic_range_value_test_render(&rt, "70%")
	updated, updated_found := rt.semantic_entities[updated_id]
	testing.expect(t, updated_annotated && !updated_invalid && updated_id == id && updated_found &&
		updated.node.value == "70%",
		"changing formatted text should update the same semantic slider")
	testing.expect(t, updated.node.numeric_value == updated_numeric_value, "formatted text updates must preserve numeric value")
	testing.expect(t, updated.node.numeric_minimum == 0 && updated.node.numeric_maximum == 1,
		"formatted text updates must preserve numeric bounds")
	testing.expect(t, updated.node.numeric_step == f64(f32(0.05)), "formatted text updates must preserve numeric step")
}
