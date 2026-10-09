package alicorn

import "core:testing"

Adaptive_Test_Semantic_ID :: Semantic_ID{namespace=0x4144415054495645, value=1}
Adaptive_Test_Focus_ID :: Semantic_ID{namespace=0x4144415054495645, value=2}

Adaptive_Test_Nodes :: struct {
	owner: Node_ID,
	wide: Node_ID,
	compact: Node_ID,
	other: Node_ID,
	widest_button: Node_ID,
	compact_button: Node_ID,
	other_button: Node_ID,
}

adaptive_test_describe :: proc(rt: ^Runtime, viewport_width: f32) -> Adaptive_Test_Nodes {
	rt.viewport = Rect{0, 0, viewport_width, 180}
	invalidate_root(rt, "adaptive assigned-width test description")
	ui, build := begin_frame(rt)
	if !build { return {} }
	nodes := Adaptive_Test_Nodes{}
	container_begin(&ui, .Root, key=key_string("adaptive-test-root"), style=layout_style(.Row))
	nodes.owner = adaptive_begin(&ui, key_string("adaptive-test-owner"),
		style=layout_style(.Column, grow=1, height=120), label="Commit metadata")
	_ = semantic_describe_as(&ui, Adaptive_Test_Semantic_ID, .Group, "Commit metadata",
		actions=semantic_actions_add({}, .Expand))
	nodes.wide = adaptive_alternative_begin(&ui, key_string("adaptive-test-wide"), "Wide", minimum_width=380)
	nodes.widest_button, _ = button_begin(&ui, "Wide action", key_string("adaptive-test-wide-action"),
		style=layout_style(width=140, height=32))
	_ = semantic_bind(&ui, Adaptive_Test_Focus_ID)
	button_end(&ui)
	adaptive_alternative_end(&ui)
	nodes.compact = adaptive_alternative_begin(&ui, key_string("adaptive-test-compact"), "Compact")
	nodes.compact_button, _ = button_begin(&ui, "Compact action", key_string("adaptive-test-compact-action"),
		style=layout_style(width=140, height=32))
	_ = semantic_bind(&ui, Adaptive_Test_Focus_ID)
	button_end(&ui)
	adaptive_alternative_end(&ui)
	adaptive_end(&ui)
	nodes.other_button, _ = button_begin(&ui, "Outside", key_string("adaptive-test-outside"),
		style=layout_style(width=100, height=32))
	button_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return nodes
}

@(test)
test_adaptive_selection_uses_assigned_width_and_stays_idle :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&rt)
	nodes := adaptive_test_describe(&rt, 500)
	state := adaptive_selection_state(&rt, nodes.owner)
	owner, owner_ok := rt.nodes[nodes.owner]
	wide, wide_ok := rt.nodes[nodes.wide]
	compact, compact_ok := rt.nodes[nodes.compact]
	testing.expect(t, owner_ok && wide_ok && compact_ok && state.valid,
		"the adaptive owner and both ordered alternatives should be retained")
	testing.expect(t, state.selected_alternative == nodes.wide && state.selected_name == "Wide" &&
		state.available_width == 400 && state.reason == .Minimum_Fit && state.rejected_count == 1 &&
		state.rejected[0].node == nodes.compact,
		"selection should use the parent's assigned inner width and report the chosen and rejected candidates")
	testing.expect(t, wide.present && !compact.present && owner.adaptive_selected_alternative == nodes.wide,
		"only the selected realization should be present after the first bounded layout pass")
	frames_built := rt.stats.frames_built
	layout_visits := rt.stats.layout_nodes_visited
	ui, should_build := begin_frame(&rt)
	testing.expect(t, !should_build,
		"an unchanged adaptive component should not schedule an application description")
	if should_build { end_frame(&ui) }
	testing.expect(t, rt.stats.frames_built == frames_built && rt.stats.layout_nodes_visited == layout_visits &&
		!rt.invalidated && !presentation_needs_frame(&rt),
		"a settled adaptive decision should return the runtime to true idle")
}

@(test)
test_adaptive_switch_hides_input_and_semantics_and_replays :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&rt)
	first := adaptive_test_describe(&rt, 500)
	wide_bounds := rt.nodes[first.widest_button].bounds
	owner_semantic, owner_semantic_found := semantic_node_lookup(&rt, Adaptive_Test_Semantic_ID)
	wide_semantic_id := Adaptive_Test_Focus_ID
	_, wide_semantic_found := semantic_node_lookup(&rt, wide_semantic_id)
	testing.expect(t, owner_semantic_found, "adaptive owner semantic should be published")
	testing.expect(t, wide_semantic_found, "selected branch semantic should be published")
	testing.expect(t, owner_semantic.has_bounds, "adaptive owner semantic should receive finalized bounds")
	testing.expect(t, semantic_actions_has(owner_semantic.actions, .Expand), "adaptive owner semantic action should be retained")
	wide_displayed, compact_displayed := false, false
	for command in rt.display {
		if command.owner == first.widest_button { wide_displayed = true }
		if command.owner == first.compact_button { compact_displayed = true }
	}
	testing.expect(t, wide_displayed && !compact_displayed,
		"only the selected branch should contribute retained paint commands")
	testing.expect(t, focus(&rt, first.widest_button), "the selected Wide control should accept keyboard focus")

	compact := adaptive_test_describe(&rt, 450)
	state := adaptive_selection_state(&rt, compact.owner)
	wide_node, wide_ok := rt.nodes[compact.wide]
	compact_node, compact_ok := rt.nodes[compact.compact]
	owner_after, owner_after_found := semantic_node_lookup(&rt, Adaptive_Test_Semantic_ID)
	focused_semantic_after, wide_semantic_after_found := semantic_node_lookup(&rt, wide_semantic_id)
	_, wide_visual_semantic_found := semantic_node_lookup(&rt, semantic_visual_id(compact.widest_button))
	wide_displayed, compact_displayed = false, false
	for command in rt.display {
		if command.owner == compact.widest_button { wide_displayed = true }
		if command.owner == compact.compact_button { compact_displayed = true }
	}
	testing.expect(t, state.valid && state.available_width == 350 && state.selected_alternative == compact.compact &&
		state.reason == .Fallback && state.rejected_count == 1 && state.rejected[0].reason == .Minimum_Width_Not_Met,
		"a narrower actual parent assignment should select the fallback and explain why Wide was rejected")
	testing.expect(t, wide_ok && compact_ok && !wide_node.present && compact_node.present,
		"the hidden alternative should not be present in the normal retained presentation")
	testing.expect(t, !wide_displayed && compact_displayed,
		"switching alternatives should remove old branch paint and compose only the selected branch")
	testing.expect(t, wide_semantic_after_found && focused_semantic_after.visual_node == compact.compact_button &&
		!wide_visual_semantic_found,
		"the shared semantic identity should move to the selected alternative without exposing the hidden visual node")
	testing.expect(t, owner_after_found && owner_after.id == Adaptive_Test_Semantic_ID && owner_after.has_bounds &&
		semantic_actions_has(owner_after.actions, .Expand),
		"the logical semantic identity and actions should survive presentation replacement")
	focused_semantic, focused_semantic_found := semantic_node_lookup(&rt, Adaptive_Test_Focus_ID)
	testing.expect(t, rt.focused == compact.compact_button && focused_semantic_found &&
		focused_semantic.visual_node == compact.compact_button && semantic_actions_has(focused_semantic.actions, .Press),
		"focus and its stable application semantic action should move to the equivalent node in the selected presentation")
	hit := hit_test(&rt, rt.nodes[compact.compact_button].bounds.x+10, rt.nodes[compact.compact_button].bounds.y+10)
	testing.expect(t, hit == compact.compact_button,
		"pointer hit testing should resolve the selected alternative at the overlapping branch bounds")

	created_before := rt.stats.nodes_created
	retired_before := rt.stats.nodes_retired
	steady := adaptive_test_describe(&rt, 460)
	steady_state := adaptive_selection_state(&rt, steady.owner)
	testing.expect(t, steady_state.selected_alternative == steady.compact &&
		rt.stats.nodes_created == created_before && rt.stats.nodes_retired == retired_before,
		"resizing without crossing the selection threshold should not reconstruct either alternative")

	wide_again := adaptive_test_describe(&rt, 500)
	wide_again_state := adaptive_selection_state(&rt, wide_again.owner)
	testing.expect(t, wide_again_state.selected_alternative == wide_again.wide &&
		same_rect(rt.nodes[wide_again.widest_button].bounds, wide_bounds),
		"Compact to Wide replay should restore the same selected branch geometry")

	clean := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&clean)
	clean_nodes := adaptive_test_describe(&clean, 500)
	testing.expect(t, same_rect(rt.nodes[wide_again.owner].bounds, clean.nodes[clean_nodes.owner].bounds) &&
		same_rect(rt.nodes[wide_again.widest_button].bounds, clean.nodes[clean_nodes.widest_button].bounds),
		"retained replay should match a clean solve for identical final constraints")
}

