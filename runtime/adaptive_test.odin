package alicorn

import "core:testing"

Adaptive_Test_Semantic_ID :: Semantic_ID{namespace=0x4144415054495645, value=1}
Adaptive_Test_Focus_ID :: Semantic_ID{namespace=0x4144415054495645, value=2}
Adaptive_Test_Nested_Action_ID :: Semantic_ID{namespace=0x4144415054495645, value=3}

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
	for i in 0..<48 {
		text(&ui, "Wide branch detail", key=key_u64(u64(i)), style=layout_style(.Row, height=16))
	}
	adaptive_alternative_end(&ui)
	nodes.compact = adaptive_alternative_begin(&ui, key_string("adaptive-test-compact"), "Compact")
	nodes.compact_button, _ = button_begin(&ui, "Compact action", key_string("adaptive-test-compact-action"),
		style=layout_style(width=140, height=32))
	_ = semantic_bind(&ui, Adaptive_Test_Focus_ID)
	button_end(&ui)
	for i in 0..<48 {
		text(&ui, "Compact branch detail", key=key_u64(u64(i)), style=layout_style(.Row, height=16))
	}
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
	branch_walks_after_initial := rt.stats.adaptive_presentation_nodes_visited
	testing.expect(t, branch_walks_after_initial == 50,
		"the initial selection should visit the inactive 50-node branch exactly once")
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
	branch_walks_after_switch := rt.stats.adaptive_presentation_nodes_visited
	testing.expect(t, branch_walks_after_switch-branch_walks_after_initial == 100,
		"switching selection should visit both 50-node subtrees once, recording 100 visits")
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
	branch_walks_before_steady := rt.stats.adaptive_presentation_nodes_visited
	steady := adaptive_test_describe(&rt, 460)
	steady_state := adaptive_selection_state(&rt, steady.owner)
	testing.expect(t, steady_state.selected_alternative == steady.compact &&
		rt.stats.nodes_created == created_before && rt.stats.nodes_retired == retired_before,
		"resizing without crossing the selection threshold should not reconstruct either alternative")
	testing.expect(t, rt.stats.adaptive_presentation_nodes_visited == branch_walks_before_steady,
		"resizing within an unchanged selection should skip both retained alternative subtrees")

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

@(test)
test_adaptive_invalid_alternative_end_preserves_owner_scope :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "the first adaptive scope fixture should build"); return }
	root := container_begin(&ui, .Root, key=key_string("adaptive-scope-root"), style=layout_style(.Column))
	owner := adaptive_begin(&ui, key_string("adaptive-scope-owner"), style=layout_style(.Column, width=420, height=120))
	_ = adaptive_alternative_begin(&ui, key_string("adaptive-scope-wide"), "Wide", minimum_width=380)
	adaptive_alternative_end(&ui)
	_ = adaptive_alternative_begin(&ui, key_string("adaptive-scope-compact"), "Compact")
	adaptive_alternative_end(&ui)
	invalid := adaptive_alternative_begin(&ui, key_string("adaptive-scope-third"), "Third", minimum_width=100)
	testing.expect(t, invalid == 0, "a third alternative should be rejected without opening a retained container")
	adaptive_alternative_end(&ui)
	testing.expect(t, current_node_parent(&ui) == owner && len(rt.stack) == 2,
		"ending an invalid alternative must leave the enclosing adaptive owner on the container stack")
	adaptive_end(&ui)
	testing.expect(t, current_node_parent(&ui) == root && len(rt.stack) == 1,
		"adaptive_end should close its own owner after the invalid alternative marker is consumed")
	container_end(&ui)
	end_frame(&ui)
	testing.expect(t, len(rt.stack) == 0 && len(rt.adaptive_description_scopes) == 0,
		"the malformed alternative fixture should finish with balanced container and adaptive scopes")
	testing.expect(t, rt.hard_error && rt.diagnostic == "adaptive regions support exactly two ordered alternatives in v1",
		"the rejected alternative should retain its useful validation diagnostic without a scope-corruption error")
}

Adaptive_Nested_Test_Nodes :: struct {
	outer_owner: Node_ID,
	outer_wide: Node_ID,
	outer_compact: Node_ID,
	nested_owner: Node_ID,
	nested_wide: Node_ID,
	nested_compact: Node_ID,
	nested_wide_button: Node_ID,
	nested_compact_button: Node_ID,
	outer_compact_button: Node_ID,
}

adaptive_nested_test_describe :: proc(rt: ^Runtime, viewport_width: f32) -> Adaptive_Nested_Test_Nodes {
	rt.viewport = Rect{0, 0, viewport_width, 180}
	invalidate_root(rt, "nested adaptive assigned-width test description")
	ui, build := begin_frame(rt)
	if !build { return {} }
	nodes := Adaptive_Nested_Test_Nodes{}
	container_begin(&ui, .Root, key=key_string("adaptive-nested-root"), style=layout_style(.Row))
	nodes.outer_owner = adaptive_begin(&ui, key_string("adaptive-nested-outer-owner"),
		style=layout_style(.Column, grow=1, height=140), label="Outer adaptive region")
	nodes.outer_wide = adaptive_alternative_begin(&ui, key_string("adaptive-nested-outer-wide"), "Wide", minimum_width=380,
		style=layout_style(.Column))
	nodes.nested_owner = adaptive_begin(&ui, key_string("adaptive-nested-inner-owner"),
		style=layout_style(.Column, grow=1, height=64), label="Nested adaptive region")
	nodes.nested_wide = adaptive_alternative_begin(&ui, key_string("adaptive-nested-inner-wide"), "Nested Wide", minimum_width=390)
	nodes.nested_wide_button, _ = button_begin(&ui, "Nested action", key_string("adaptive-nested-inner-wide-action"),
		style=layout_style(width=140, height=32))
	_ = semantic_bind(&ui, Adaptive_Test_Nested_Action_ID)
	button_end(&ui)
	adaptive_alternative_end(&ui)
	nodes.nested_compact = adaptive_alternative_begin(&ui, key_string("adaptive-nested-inner-compact"), "Nested Compact")
	nodes.nested_compact_button, _ = button_begin(&ui, "Nested action", key_string("adaptive-nested-inner-compact-action"),
		style=layout_style(width=140, height=32))
	_ = semantic_bind(&ui, Adaptive_Test_Nested_Action_ID)
	button_end(&ui)
	adaptive_alternative_end(&ui)
	adaptive_end(&ui)
	adaptive_alternative_end(&ui)
	nodes.outer_compact = adaptive_alternative_begin(&ui, key_string("adaptive-nested-outer-compact"), "Compact")
	nodes.outer_compact_button, _ = button_begin(&ui, "Nested action", key_string("adaptive-nested-outer-compact-action"),
		style=layout_style(width=140, height=32))
	_ = semantic_bind(&ui, Adaptive_Test_Nested_Action_ID)
	button_end(&ui)
	adaptive_alternative_end(&ui)
	adaptive_end(&ui)
	_ = button(&ui, "Fixed sibling", key=key_string("adaptive-nested-fixed-sibling"),
		style=layout_style(width=100, height=32))
	container_end(&ui)
	end_frame(&ui)
	return nodes
}

@(test)
test_nested_adaptive_visibility_and_focus_survive_outer_switches :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&rt)
	wide := adaptive_nested_test_describe(&rt, 500)
	outer_wide_state := adaptive_selection_state(&rt, wide.outer_owner)
	nested_wide_state := adaptive_selection_state(&rt, wide.nested_owner)
	testing.expect(t, outer_wide_state.valid && outer_wide_state.selected_alternative == wide.outer_wide &&
		nested_wide_state.valid && nested_wide_state.selected_alternative == wide.nested_wide &&
		rt.nodes[wide.nested_wide].present && !rt.nodes[wide.nested_compact].present,
		"the initial outer and nested widths should select the Wide presentation at both levels")
	testing.expect(t, focus(&rt, wide.nested_wide_button), "the selected nested action should accept keyboard focus")

	nested_compact := adaptive_nested_test_describe(&rt, 480)
	outer_still_wide := adaptive_selection_state(&rt, nested_compact.outer_owner)
	nested_now_compact := adaptive_selection_state(&rt, nested_compact.nested_owner)
	testing.expect(t, outer_still_wide.selected_alternative == nested_compact.outer_wide &&
		nested_now_compact.selected_alternative == nested_compact.nested_compact &&
		rt.nodes[nested_compact.nested_compact].present && !rt.nodes[nested_compact.nested_wide].present,
		"a nested width transition should update only the nested adaptive presentation")
	testing.expect(t, rt.focused == nested_compact.nested_compact_button,
		"focus should transfer to the semantic peer when the nested presentation changes")

	outer_compact := adaptive_nested_test_describe(&rt, 450)
	outer_now_compact := adaptive_selection_state(&rt, outer_compact.outer_owner)
	testing.expect(t, outer_now_compact.selected_alternative == outer_compact.outer_compact &&
		!rt.nodes[outer_compact.outer_wide].present && !rt.nodes[outer_compact.nested_owner].present &&
		!rt.nodes[outer_compact.nested_wide].present && !rt.nodes[outer_compact.nested_compact].present &&
		rt.nodes[outer_compact.outer_compact].present,
		"hiding the outer Wide branch should hide the nested owner and all of its presentations")
	testing.expect(t, rt.focused == outer_compact.outer_compact_button,
		"focus should leave the hidden nested subtree for the equivalent outer Compact action")

	restored := adaptive_nested_test_describe(&rt, 500)
	restored_outer := adaptive_selection_state(&rt, restored.outer_owner)
	restored_nested := adaptive_selection_state(&rt, restored.nested_owner)
	testing.expect(t, restored_outer.selected_alternative == restored.outer_wide &&
		restored_nested.selected_alternative == restored.nested_wide &&
		rt.nodes[restored.nested_wide].present && !rt.nodes[restored.nested_compact].present,
		"restoring the outer branch should recompute and restore the nested selection")
	testing.expect(t, rt.focused == restored.nested_wide_button && node_is_presentation_active(&rt, rt.focused),
		"focus should return to the matching nested action without remaining in a hidden presentation")
}

