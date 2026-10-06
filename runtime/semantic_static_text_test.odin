package alicorn

import "core:testing"

semantic_static_text_test_render :: proc(rt: ^Runtime, value: string, annotate: bool) -> (
	text_node: Node_ID,
	control_node: Node_ID,
	annotation_ok: bool,
	control_annotation_ok: bool,
) {
	invalidate_root(rt, "semantic static text test")
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin(&ui, .Root, key=key_string("semantic-static-root"), style=layout_style(.Column, gap=4))
	text(&ui, "Visual-only ornament", key=key_string("visual-only"))
	text_node = text(&ui, value, key=key_string("standalone-copy"))
	if annotate { annotation_ok = semantic_static_text(&ui) }
	control_node, _ = button_ex(&ui, "Save", key="save", explicit_key=true)
	control_annotation_ok = semantic_static_text(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_semantic_static_text_is_explicit_and_uses_value :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)

	text_node, control_node, annotation_ok, control_annotation_ok := semantic_static_text_test_render(&rt, "Status: ready", false)
	static_id := semantic_visual_id(text_node)
	_, static_found := rt.semantic_entities[static_id]
	_, button_found := rt.semantic_entities[semantic_visual_id(control_node)]
	testing.expect(t, text_node != 0 && !annotation_ok && !control_annotation_ok &&
		!static_found && button_found && len(rt.semantic_entities) == 1,
		"ordinary Text must remain absent, and the opt-in must reject non-Text controls")

	text_node, control_node, annotation_ok, control_annotation_ok = semantic_static_text_test_render(&rt, "Status: ready", true)
	static_entity, static_entity_found := rt.semantic_entities[semantic_visual_id(text_node)]
	static_node := static_entity.node
	_, button_found = rt.semantic_entities[semantic_visual_id(control_node)]
	testing.expect(t, annotation_ok && !control_annotation_ok && static_entity_found &&
		static_node.role == .Static_Text && static_node.label == "" && static_node.value == "Status: ready" &&
		static_node.actions == {} && static_node.visual_node == text_node && button_found &&
		len(rt.semantic_entities) == 2,
		"an explicit static text entity should carry its spoken content as value without inventing an action or label")

	text_node_after, control_node_after, annotation_ok_after, control_annotation_ok_after := semantic_static_text_test_render(&rt, "Status: updated", true)
	updated, updated_found := rt.semantic_entities[semantic_visual_id(text_node_after)]
	updated_control, updated_control_found := rt.semantic_entities[semantic_visual_id(control_node_after)]
	testing.expect(t, text_node_after == text_node && annotation_ok_after && !control_annotation_ok_after && updated_found &&
		updated.node.value == "Status: updated" && updated_control_found && updated_control.node.role == .Button &&
		len(rt.semantic_entities) == 2,
		"annotated dynamic Text should update in place while visual-only Text remains omitted")
}
