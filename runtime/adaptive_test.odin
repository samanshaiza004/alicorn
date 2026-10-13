package alicorn

import "core:fmt"
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
	_ = tooltip(&ui, "Wide only help")
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
test_adaptive_hidden_branch_dismisses_pending_and_visible_tooltips :: proc(t: ^testing.T) {
	// Pending timers and already-composed overlays both belong to a specific
	// presentation. Hiding that branch must retire the tooltip immediately.
	rt := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&rt)
	nodes := adaptive_test_describe(&rt, 500)
	tooltip_pointer_update(&rt, nodes.widest_button, 100)
	testing.expect(t, rt.tooltip.target == nodes.widest_button, "hovering Wide should arm its tooltip")
	_ = adaptive_test_describe(&rt, 450)
	testing.expect(t, rt.tooltip.target == 0 && !tooltip_advance(&rt, 500_000_100),
		"selection change should cancel a pending tooltip owned by the now-hidden branch")

	visible := new_runtime(Rect{0, 0, 500, 180})
	defer destroy_runtime(&visible)
	_ = text_engine_load_font(&visible.text_engine, TOOLTIP_TEST_FONT)
	visible_nodes := adaptive_test_describe(&visible, 500)
	tooltip_pointer_update(&visible, visible_nodes.widest_button, 100)
	testing.expect(t, tooltip_advance(&visible, 500_000_100), "Wide tooltip should become visible after its delay")
	_ = adaptive_test_describe(&visible, 450)
	testing.expect(t, !visible.tooltip.visible && visible.tooltip.target == 0,
		"selection change should dismiss a visible tooltip owned by the hidden branch")
	for command in visible.display { testing.expect(t, command.owner != Node_ID(0), "hidden-branch tooltip commands must leave retained composition") }
}

Adaptive_Retained_Semantic_ID :: Semantic_ID{namespace=0x4144415054495645, value=91}
Adaptive_Retained_Run_ID :: Semantic_ID{namespace=0x4144415054495645, value=93}
Adaptive_Retained_Area_ID :: Semantic_ID{namespace=0x4144415054495645, value=94}
Adaptive_Retained_Compact_Area_ID :: Semantic_ID{namespace=0x4144415054495645, value=95}

adaptive_retained_split_describe :: proc(
	rt: ^Runtime,
	semantic_id := Adaptive_Retained_Semantic_ID,
	omit_semantic_role := false,
) -> (handle: Node_ID, wide_button, compact_button: Node_ID) {
	invalidate_root(rt, "adaptive retained semantic fixture description")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("adaptive-retained-root"), style=layout_style(.Column, width=500, height=200))
	split := split_begin(&ui, key_string("adaptive-retained-split"), .Horizontal, 100,
		style=layout_style(.Row, grow=1, height=200, clip=true))
	_ = split_first_begin(&ui, split, style=layout_style(width=100, grow=0))
	split_first_end(&ui, split)
	handle = split_divider(&ui, split, thickness=2, hit_size=10)
	_ = split_second_begin(&ui, split)
	_ = adaptive_begin(&ui, key_string("adaptive-retained-owner"), style=layout_style(.Column, grow=1, height=80))
	_ = adaptive_alternative_begin(&ui, key_string("adaptive-retained-wide"), "Wide", minimum_width=380)
	wide_button, _ = button_begin(&ui, "Wide action", key_string("adaptive-retained-wide-action"), style=layout_style(width=120, height=32))
	if omit_semantic_role {
		_ = semantic_bind(&ui, semantic_id)
		ui.runtime.pending[len(ui.runtime.pending)-1].semantic = Semantic_Descriptor{}
	} else {
		_ = semantic_describe_as(&ui, semantic_id, .Button, "Wide custom name", actions=semantic_actions_add({}, .Press))
	}
	button_end(&ui)
	adaptive_retained_run_describe(&ui, "Wide", Adaptive_Retained_Area_ID)
	adaptive_alternative_end(&ui)
	_ = adaptive_alternative_begin(&ui, key_string("adaptive-retained-compact"), "Compact")
	compact_button, _ = button_begin(&ui, "Compact action", key_string("adaptive-retained-compact-action"), style=layout_style(width=120, height=32))
	if omit_semantic_role {
		_ = semantic_bind(&ui, semantic_id)
		ui.runtime.pending[len(ui.runtime.pending)-1].semantic = Semantic_Descriptor{}
	} else {
		_ = semantic_describe_as(&ui, semantic_id, .Button, "Compact custom name", actions=semantic_actions_add({}, .Press))
	}
	button_end(&ui)
	adaptive_retained_run_describe(&ui, "Compact", Adaptive_Retained_Compact_Area_ID)
	adaptive_alternative_end(&ui)
	adaptive_end(&ui)
	split_second_end(&ui, split)
	split_end(&ui, split)
	container_end(&ui)
	end_frame(&ui)
	return
}

adaptive_retained_run_describe :: proc(ui: ^UI, prefix: string, run_area_id: Semantic_ID) {
	text(ui, "Accessible run", key=key_string("adaptive-retained-run"), style=layout_style(.Row, height=20))
	rt := ui.runtime
	area_label := fmt.aprintf("%s area", prefix, allocator=rt.scratch_allocator)
	area_description := fmt.aprintf("%s area description", prefix, allocator=rt.scratch_allocator)
	area_value := fmt.aprintf("%s area value", prefix, allocator=rt.scratch_allocator)
	_ = semantic_describe_as(ui, run_area_id, .Text_Area, area_label, area_description, area_value)
	text(ui, "Accessible run", key=key_string("adaptive-retained-text-run"), style=layout_style(.Row, height=20))
	label := fmt.aprintf("%s label", prefix, allocator=rt.scratch_allocator)
	description := fmt.aprintf("%s description", prefix, allocator=rt.scratch_allocator)
	value := fmt.aprintf("%s %s", prefix, "a🙂", allocator=rt.scratch_allocator)
	lengths := make([]u8, 4, allocator=rt.scratch_allocator)
	lengths[0] = u8(len(prefix))
	lengths[1] = 1
	lengths[2] = 1
	lengths[3] = 4
	_ = semantic_describe_as(ui, Adaptive_Retained_Run_ID, .Text_Run, label, description, value)
	run := &rt.pending[len(rt.pending)-1].semantic
	run.parent = run_area_id
	run.text_run_character_lengths = lengths
}

adaptive_retained_split_drag :: proc(rt: ^Runtime, handle_id: Node_ID, delta: f32) {
	handle := rt.nodes[handle_id]
	x := handle.bounds.x + handle.bounds.w*0.5
	y := handle.bounds.y + handle.bounds.h*0.5
	_ = process_pointer(rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(rt, Pointer_Event{kind=.Move, x=x+delta, y=y, timestamp_ns=1})
	_ = process_pointer(rt, Pointer_Event{kind=.Up, x=x+delta, y=y, button=POINTER_BUTTON_PRIMARY})
}

@(test)
test_retained_split_drag_rebinds_adaptive_semantics_without_description :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 500, 200})
	defer destroy_runtime(&rt)
	handle, wide_button, compact_button := adaptive_retained_split_describe(&rt)
	initial_revision := semantic_revision(&rt)
	initial, initial_found := semantic_node_lookup(&rt, Adaptive_Retained_Semantic_ID)
	testing.expect(t, initial_found && initial.visual_node == wide_button && initial.label == "Wide custom name",
		"initial Wide selection should publish its custom descriptor")
	frames_built := rt.stats.frames_built
	adaptive_retained_split_drag(&rt, handle, 50)
	testing.expect(t, !rt.invalidated && rt.presentation_pending && rt.focused == 0,
		"divider movement should schedule a retained presentation without invalidating description or taking focus")
	ui, ready := begin_presentation_frame(&rt)
	testing.expect(t, ready, "split drag should open a retained presentation frame")
	if ready { end_presentation_frame(&ui) }
	compact, compact_found := semantic_node_lookup(&rt, Adaptive_Retained_Semantic_ID)
	compact_run, compact_run_found := semantic_node_lookup(&rt, Adaptive_Retained_Run_ID)
	update := semantic_update_since(&rt, initial_revision)
	testing.expect(t, rt.stats.frames_built == frames_built && rt.focused == 0,
		"adaptive semantic rebinding should not ask the application to describe again or change focus")
	testing.expect(t, compact_found && compact.visual_node == compact_button && compact.label == "Compact custom name" &&
		compact.has_bounds && compact.bounds.w > 0,
		"retained width selection should publish the selected branch descriptor and finalized bounds")
	testing.expect(t, compact_run_found && compact_run.label == "Compact label" &&
		compact_run.description == "Compact description" && compact_run.value == "Compact a🙂" &&
		compact_run.parent == Adaptive_Retained_Compact_Area_ID &&
		len(compact_run.text_run_character_lengths) == 4 && compact_run.text_run_character_lengths[0] == 7 &&
		compact_run.text_run_character_lengths[1] == 1 && compact_run.text_run_character_lengths[2] == 1 &&
		compact_run.text_run_character_lengths[3] == 4,
		"scratch-backed semantic strings and Text_Run byte lengths should survive the presentation-frame scratch reset")
	testing.expect(t, semantic_revision(&rt) != initial_revision && !update.requires_snapshot &&
		update.to_revision == semantic_revision(&rt) && len(update.changed_ids) > 0,
		"the retained presentation should publish a semantic delta for the branch replacement")
	adaptive_retained_split_drag(&rt, handle, -50)
	ui, ready = begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	wide, wide_found := semantic_node_lookup(&rt, Adaptive_Retained_Semantic_ID)
	wide_run, wide_run_found := semantic_node_lookup(&rt, Adaptive_Retained_Run_ID)
	testing.expect(t, wide_found && wide.visual_node == wide_button && wide.label == "Wide custom name" && wide.has_bounds,
		"dragging back across the threshold should rebind the same semantic ID to Wide again")
	testing.expect(t, wide_run_found && wide_run.label == "Wide label" && wide_run.description == "Wide description" &&
		wide_run.value == "Wide a🙂" && wide_run.parent == Adaptive_Retained_Area_ID && len(wide_run.text_run_character_lengths) == 4 &&
		wide_run.text_run_character_lengths[0] == 4 && wide_run.text_run_character_lengths[3] == 4,
		"returning to Wide should restore its independently owned custom Text_Run descriptor")
	testing.expect(t, semantic_action_request(&rt, Adaptive_Retained_Semantic_ID, .Press),
		"Press should route to the active Wide visual node after the return transition")
}

@(test)
test_adaptive_full_description_removes_previous_semantic_identity_and_role :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 500, 200})
	defer destroy_runtime(&rt)
	_, _, _ = adaptive_retained_split_describe(&rt)
	changed_id := Semantic_ID{namespace=Adaptive_Retained_Semantic_ID.namespace, value=92}
	_, _, _ = adaptive_retained_split_describe(&rt, changed_id)
	_, previous_still_found := semantic_node_lookup(&rt, Adaptive_Retained_Semantic_ID)
	changed, changed_found := semantic_node_lookup(&rt, changed_id)
	testing.expect(t, !previous_still_found && changed_found && changed.label == "Wide custom name",
		"full adaptive reconciliation should retire an old semantic ID when its active node is rebound")
	_, _, _ = adaptive_retained_split_describe(&rt, changed_id, true)
	_, role_still_found := semantic_node_lookup(&rt, changed_id)
	testing.expect(t, !role_still_found,
		"removing the active adaptive node's semantic role should retire its prior logical entity")
}

@(test)
test_adaptive_semantic_sidecars_free_on_retirement_and_destroy :: proc(t: ^testing.T) {
	stats := Runtime_Allocation_Stats{}
	rt := new_runtime(Rect{0, 0, 500, 200}, Runtime_Config{allocation_stats=&stats})
	_, _, _ = adaptive_retained_split_describe(&rt)
	frees_before_retire := stats.persistent_free_calls
	invalidate_root(&rt, "retire adaptive semantic fixture")
	ui, build := begin_frame(&rt)
	if build {
		container_begin(&ui, .Root, key=key_string("adaptive-retained-root"), style=layout_style(.Column, width=500, height=200))
		text(&ui, "replacement", key=key_string("replacement"))
		container_end(&ui)
		end_frame(&ui)
	}
	testing.expect(t, len(rt.adaptive_semantic_descriptors) == 0 && len(rt.semantic_tree_orders) == 0 &&
		stats.persistent_free_calls > frees_before_retire,
		"retiring adaptive alternatives should release their owned descriptors and per-node order entries")
	destroy_runtime(&rt)
	testing.expect(t, stats.persistent_requested_bytes_live == 0 && stats.persistent_free_calls > frees_before_retire,
		"runtime destruction should release tracked persistent adaptive sidecar allocations")
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

