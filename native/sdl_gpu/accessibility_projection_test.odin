package alicorn_sdl_gpu

import "core:testing"
import "core:c"
import base_runtime "base:runtime"
import alicorn "../../runtime"
import ak "accesskit:accesskit"

@(test)
test_native_appearance_snapshot_merges_only_known_fields :: proc(t: ^testing.T) {
	previous := Native_Appearance_Snapshot{
		preferences=alicorn.Accessibility_Appearance_Preferences{
			increased_contrast=true,
			reduce_motion=true,
		},
		known=Native_Appearance_Known_Fields{.Increased_Contrast, .Reduce_Motion},
	}
	observed := Native_Appearance_Snapshot{
		preferences=alicorn.Accessibility_Appearance_Preferences{reduce_transparency=true},
		known=Native_Appearance_Known_Fields{.Reduce_Transparency},
	}
	merged, changed := native_appearance_snapshot_merge(previous, observed)
	testing.expect(t, changed && merged.preferences.increased_contrast && merged.preferences.reduce_motion &&
		merged.preferences.reduce_transparency && !merged.preferences.differentiate_without_color,
		"unsupported or failed preference reads must preserve known values while new supported fields update")
	testing.expect(t, Native_Appearance_Field.Increased_Contrast in merged.known &&
		Native_Appearance_Field.Reduce_Motion in merged.known &&
		Native_Appearance_Field.Reduce_Transparency in merged.known &&
		Native_Appearance_Field.Differentiate_Without_Color not_in merged.known,
		"the normalized snapshot must retain per-field support/query knowledge")

	merged_again, changed_again := native_appearance_snapshot_merge(merged, observed)
	testing.expect(t, !changed_again && merged_again.preferences == merged.preferences,
		"identical native preference notifications must not produce a normalized change")
	cleared := Native_Appearance_Snapshot{
		preferences=alicorn.Accessibility_Appearance_Preferences{},
		known=Native_Appearance_Known_Fields{.Increased_Contrast},
	}
	merged_cleared, changed_cleared := native_appearance_snapshot_merge(merged, cleared)
	testing.expect(t, changed_cleared && !merged_cleared.preferences.increased_contrast &&
		merged_cleared.preferences.reduce_motion && merged_cleared.preferences.reduce_transparency,
		"a known false preference must update without clearing unrelated known fields")

	scaled := Native_Appearance_Snapshot{text_scale=1.5, text_scale_known=true}
	merged_scaled, scale_changed := native_appearance_snapshot_merge(merged, scaled)
	unknown_scale, unknown_changed := native_appearance_snapshot_merge(
		merged_scaled,
		Native_Appearance_Snapshot{preferences=merged_scaled.preferences, known=merged_scaled.known},
	)
	unchanged_scale, unchanged_scale_changed := native_appearance_snapshot_merge(merged_scaled, scaled)
	testing.expect(t, scale_changed && merged_scaled.text_scale == 1.5 && merged_scaled.text_scale_known &&
		!unknown_changed && unknown_scale.text_scale == 1.5 && unknown_scale.text_scale_known &&
		!unchanged_scale_changed && unchanged_scale.text_scale == 1.5,
		"a supported text scale should update once and remain intact when a later native query cannot report it")
}

@(test)
test_native_text_scale_updates_root_once_and_preserves_unknown_reads :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 180})
	defer alicorn.destroy_runtime(&rt)
	monitor := Native_Appearance_Monitor{}
	observed := Native_Appearance_Snapshot{text_scale=1.75, text_scale_known=true}
	testing.expect(t, native_appearance_monitor_apply_snapshot(&monitor, &rt, observed),
		"a changed native text scale should update the persistent Alicorn root input")
	root := alicorn.style_root_accessibility_observation_get(&rt)
	testing.expect(t, root.text_scale == 1.75 && root.text_scale_known,
		"the host should pass the observed system scale through to Alicorn")

	rt.invalidated = false
	testing.expect(t, !native_appearance_monitor_apply_snapshot(&monitor, &rt, observed) && !rt.invalidated,
		"repeated identical text-scale notifications should not schedule UI work")
	unknown := Native_Appearance_Snapshot{}
	testing.expect(t, !native_appearance_monitor_apply_snapshot(&monitor, &rt, unknown) && !rt.invalidated,
		"a failed native scale query should preserve the prior value without scheduling work")
	root = alicorn.style_root_accessibility_observation_get(&rt)
	testing.expect(t, root.text_scale == 1.75 && root.text_scale_known,
		"unavailable native scale reads must preserve the last known system setting")
}
accessibility_projection_test_snapshot :: proc(
	revision: u64,
	nodes: []alicorn.Semantic_Node,
	focus := alicorn.Semantic_ID{},
) -> alicorn.Semantic_Snapshot {
	previous_allocator := context.allocator
	context.allocator = context.temp_allocator
	defer context.allocator = previous_allocator
	snapshot := alicorn.Semantic_Snapshot{
		revision=revision,
		keyboard_focus=focus,
		allocator=context.temp_allocator,
		nodes=make([dynamic]alicorn.Semantic_Node, 0, len(nodes), allocator=context.temp_allocator),
	}
	for node in nodes { append(&snapshot.nodes, node) }
	return snapshot
}

accessibility_projection_test_collision_hash :: proc(id: alicorn.Semantic_ID) -> u64 {
	_ = id
	return 0xCAFE
}

accessibility_projection_test_find_node :: proc(nodes: []Accessibility_Projection_Node, id: alicorn.Semantic_ID) -> (node: Accessibility_Projection_Node, found: bool) {
	for candidate in nodes {
		if candidate.semantic_id == id { return candidate, true }
	}
	return {}, false
}

@(test)
test_accessibility_projection_maps_static_text_to_label_value :: proc(t: ^testing.T) {
	id := alicorn.Semantic_ID{namespace=25, value=1}
	nodes := [1]alicorn.Semantic_Node{{id=id, role=.Static_Text, value="Build completed"}}
	snapshot := accessibility_projection_test_snapshot(1, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	projected, found := accessibility_projection_node_by_semantic_id(projection, id)
	testing.expect(t, status == .Success && found && projected.role == .Static_Text &&
		projected.label == "" && projected.value == "Build completed",
		"Static_Text should preserve content as value and must not synthesize an accessible label")
	testing.expect(t, native_accessibility_accesskit_role(projected.role) == ACCESSKIT_ROLE_LABEL,
		"the AccessKit adapter should expose Static_Text as Label")
}

@(test)
test_accessibility_projection_preserves_live_regions_and_select_roles :: proc(t: ^testing.T) {
	status_id := alicorn.Semantic_ID{namespace=26, value=1}
	alert_id := alicorn.Semantic_ID{namespace=26, value=2}
	combo_id := alicorn.Semantic_ID{namespace=26, value=3}
	list_id := alicorn.Semantic_ID{namespace=26, value=4}
	option_id := alicorn.Semantic_ID{namespace=26, value=5}
	nodes := [5]alicorn.Semantic_Node{
		{id=status_id, role=.Status, value="Saved", live=.Polite, live_atomic=true, tree_order=1},
		{id=alert_id, role=.Alert, value="Save failed", live=.Assertive, live_atomic=true, tree_order=2},
		{id=combo_id, role=.Combo_Box, label="Theme", value="Warm", tree_order=3},
		{id=list_id, role=.List_Box, label="Themes", is_collection=true, logical_count=1, tree_order=4},
		{id=option_id, role=.List_Box_Option, label="Warm", parent=list_id, states=alicorn.semantic_states_add({}, .Selected), tree_order=5},
	}
	snapshot := accessibility_projection_test_snapshot(10, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	status_node, status_found := accessibility_projection_node_by_semantic_id(projection, status_id)
	alert_node, alert_found := accessibility_projection_node_by_semantic_id(projection, alert_id)
	combo_node, combo_found := accessibility_projection_node_by_semantic_id(projection, combo_id)
	list_node, list_found := accessibility_projection_node_by_semantic_id(projection, list_id)
	option_node, option_found := accessibility_projection_node_by_semantic_id(projection, option_id)
	selected := accessibility_projection_state_has(option_node.states, .Selected)
	checking := status == .Success && status_found && alert_found && combo_found && list_found && option_found && selected &&
		status_node.live == .Polite && status_node.live_atomic && alert_node.live == .Assertive && alert_node.live_atomic &&
		combo_node.role == .Combo_Box && list_node.role == .List_Box && option_node.role == .List_Box_Option &&
		native_accessibility_accesskit_role(status_node.role) == ACCESSKIT_ROLE_STATUS &&
		native_accessibility_accesskit_role(alert_node.role) == ACCESSKIT_ROLE_ALERT &&
		native_accessibility_accesskit_role(combo_node.role) == ACCESSKIT_ROLE_COMBO_BOX &&
		native_accessibility_accesskit_role(list_node.role) == ACCESSKIT_ROLE_LIST_BOX &&
		native_accessibility_accesskit_role(option_node.role) == ACCESSKIT_ROLE_LIST_BOX_OPTION
	testing.expect(t, checking,
		"live status/alert attributes and Select roles should survive projection to the native accessibility contract")
}

@(test)
test_accessibility_projection_maps_text_runs_and_area_selection :: proc(t: ^testing.T) {
	area_id := alicorn.Semantic_ID{namespace=25, value=20}
	first_run_id := alicorn.Semantic_ID{namespace=25, value=21}
	second_run_id := alicorn.Semantic_ID{namespace=25, value=22}
	first_lengths := [2]u8{1, 4}
	second_lengths := [2]u8{1, 2}
	actions := alicorn.semantic_actions_add({}, .Set_Value)
	actions = alicorn.semantic_actions_add(actions, .Set_Text_Selection)
	actions = alicorn.semantic_actions_add(actions, .Replace_Selected_Text)
	selection := alicorn.Semantic_Text_Selection{
		anchor={run_id=first_run_id, character_index=1},
		focus={run_id=second_run_id, character_index=2},
		valid=true,
	}
	nodes := [3]alicorn.Semantic_Node{
		{id=area_id, role=.Text_Area, actions=actions, text_selection=selection, tree_order=1},
		{id=first_run_id, role=.Text_Run, parent=area_id, value="a🙂", text_run_character_lengths=first_lengths[:], tree_order=2},
		{id=second_run_id, role=.Text_Run, parent=area_id, value="b\r\n", text_run_character_lengths=second_lengths[:], tree_order=3},
	}
	snapshot := accessibility_projection_test_snapshot(8, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	area, area_found := accessibility_projection_node_by_semantic_id(projection, area_id)
	first, first_found := accessibility_projection_node_by_semantic_id(projection, first_run_id)
	second, second_found := accessibility_projection_node_by_semantic_id(projection, second_run_id)
	decoded, decoded_ok := accessibility_projection_text_selection_decode(
		projection, area_id, first.id, 1, second.id, 2,
	)
	_, invalid_run_ok := accessibility_projection_text_selection_decode(
		projection, area_id, first.id, 3, second.id, 0,
	)
	testing.expect(t, status == .Success && area_found && area.role == .Text_Area && area.text_selection.valid &&
		area.text_selection.anchor.node_id == first.id && area.text_selection.anchor.character_index == 1 &&
		area.text_selection.focus.node_id == second.id && area.text_selection.focus.character_index == 2,
		"Text_Area selection should be published using stable AccessKit Text_Run node IDs")
	testing.expect(t, first_found && second_found && first.role == .Text_Run && first.value == "a🙂" &&
		first.text_run_character_lengths[0] == 1 && first.text_run_character_lengths[1] == 4 &&
		second.text_run_character_lengths[1] == 2,
		"Text_Run projection should preserve text and UTF-8 selectable-unit lengths")
	testing.expect(t, decoded_ok && decoded.anchor.run_id == first_run_id && decoded.anchor.character_index == 1 &&
		decoded.focus.run_id == second_run_id && decoded.focus.character_index == 2 && !invalid_run_ok,
		"AccessKit text positions should map back to semantic run positions and reject invalid indices")
	testing.expect(t, native_accessibility_accesskit_role(first.role) == ACCESSKIT_ROLE_TEXT_RUN,
		"Text_Run must map to AccessKit's TextRun role")
	selection_action, _, selection_supported := native_accessibility_action_to_semantic(
		ACCESSKIT_ACTION_SET_TEXT_SELECTION, area,
	)
	replacement_action, _, replacement_supported := native_accessibility_action_to_semantic(
		ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT, area,
	)
	selection_data := ak.Action_Data_ABI{
		tag=c.int(ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION),
		value=[4]u64{first.id, 1, second.id, 2},
	}
	decoded_action, action_data_ok := native_accessibility_selection_from_action_data(
		projection, area_id, selection_data,
	)
	testing.expect(t, selection_supported && selection_action == .Set_Text_Selection &&
		replacement_supported && replacement_action == .Replace_Selected_Text,
		"SetTextSelection and ReplaceSelectedText should only translate when advertised by the area")
	testing.expect(t, action_data_ok && decoded_action.anchor.run_id == first_run_id &&
		decoded_action.focus.run_id == second_run_id && decoded_action.anchor.character_index == 1 &&
		decoded_action.focus.character_index == 2,
		"the AccessKit 32-byte action-data union arm should decode in anchor/focus order")
}

@(test)
test_accessibility_projection_maps_builtin_text_field_selection :: proc(t: ^testing.T) {
	field_id := alicorn.Semantic_ID{namespace=26, value=40}
	run_id := alicorn.Semantic_ID{namespace=27, value=40}
	lengths := [4]u8{1, 3, 3, 4}
	actions := alicorn.semantic_actions_add({}, .Focus)
	actions = alicorn.semantic_actions_add(actions, .Set_Value)
	actions = alicorn.semantic_actions_add(actions, .Set_Text_Selection)
	selection := alicorn.Semantic_Text_Selection{
		anchor={run_id=run_id, character_index=2},
		focus={run_id=run_id, character_index=3},
		valid=true,
	}
	nodes := [2]alicorn.Semantic_Node{
		{id=field_id, role=.Text_Field, value="A日本🙂", actions=actions, text_selection=selection, tree_order=1},
		{id=run_id, role=.Text_Run, parent=field_id, value="A日本🙂", text_run_character_lengths=lengths[:], tree_order=2},
	}
	snapshot := accessibility_projection_test_snapshot(9, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	field, field_found := accessibility_projection_node_by_semantic_id(projection, field_id)
	run, run_found := accessibility_projection_node_by_semantic_id(projection, run_id)
	decoded, decoded_ok := accessibility_projection_text_selection_decode(
		projection, field_id, run.id, 1, run.id, 4,
	)
	selection_action, _, selection_supported := native_accessibility_action_to_semantic(
		ACCESSKIT_ACTION_SET_TEXT_SELECTION, field,
	)
	testing.expect(t, status == .Success && field_found && field.role == .Text_Input && field.text_selection.valid &&
		field.text_selection.anchor.node_id == run.id && field.text_selection.anchor.character_index == 2 &&
		field.text_selection.focus.character_index == 3,
		"built-in text fields must project a text run and selection on the AccessKit text-input node")
	testing.expect(t, run_found && run.role == .Text_Run && run.value == "A日本🙂" &&
		len(run.text_run_character_lengths) == len(lengths) &&
		run.text_run_character_lengths[0] == 1 && run.text_run_character_lengths[1] == 3 &&
		run.text_run_character_lengths[2] == 3 && run.text_run_character_lengths[3] == 4 && decoded_ok &&
		decoded.anchor.character_index == 1 && decoded.focus.character_index == 4,
		"field text selection decoding must preserve Unicode grapheme indexes")
	testing.expect(t, selection_supported && selection_action == .Set_Text_Selection,
		"editable text fields must expose the native SetTextSelection action")
}

@(test)
test_accessibility_projection_rejects_invalid_text_selection_tree :: proc(t: ^testing.T) {
	area_id := alicorn.Semantic_ID{namespace=25, value=30}
	run_id := alicorn.Semantic_ID{namespace=25, value=31}
	lengths := [1]u8{1}
	nodes := [2]alicorn.Semantic_Node{
		{
			id=area_id,
			role=.Text_Area,
			text_selection=alicorn.Semantic_Text_Selection{
				anchor={run_id=run_id, character_index=2},
				focus={run_id=run_id, character_index=0},
				valid=true,
			},
		},
		{id=run_id, role=.Text_Run, parent=area_id, value="x", text_run_character_lengths=lengths[:]},
	}
	snapshot := accessibility_projection_test_snapshot(9, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	testing.expect(t, status == .Invalid_Text_Model,
		"the native projection must reject text selections outside the selectable-unit range")
}

@(test)
test_accessibility_projection_preserves_formatted_slider_value_and_numeric_range :: proc(t: ^testing.T) {
	id := alicorn.Semantic_ID{namespace=25, value=2}
	nodes := [1]alicorn.Semantic_Node{{
		id=id,
		role=.Slider,
		label="Gain",
		value="65%",
		numeric_value=0.65,
		numeric_minimum=0,
		numeric_maximum=1,
		numeric_step=0.05,
		has_numeric_value=true,
	}}
	snapshot := accessibility_projection_test_snapshot(2, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	projected, found := accessibility_projection_node_by_semantic_id(projection, id)
	testing.expect(t, status == .Success && found && projected.role == .Slider &&
		projected.label == "Gain" && projected.value == "65%" && projected.has_numeric_value &&
		projected.numeric_value == 0.65 && projected.numeric_minimum == 0 &&
		projected.numeric_maximum == 1 && projected.numeric_step == 0.05,
		"the native projection should preserve the formatted value alongside numeric range properties")
}

@(test)
test_accessibility_action_translation_keeps_reveal_separate_from_perform :: proc(t: ^testing.T) {
	button := Accessibility_Projection_Node{
		role=.Button,
		actions=transmute(Accessibility_Projection_Actions)(bit_set[Accessibility_Projection_Action; u32]{.Press, .Focus}),
	}
	action, reveal, supported := native_accessibility_action_to_semantic(ACCESSKIT_ACTION_CLICK, button)
	testing.expect(t, supported && action == .Press && !reveal,
		"AccessKit click on a button should route to semantic Press")
	action, reveal, supported = native_accessibility_action_to_semantic(ACCESSKIT_ACTION_FOCUS, button)
	testing.expect(t, supported && action == .Focus && !reveal,
		"AccessKit focus should route through Alicorn semantic focus")
	virtual_item := Accessibility_Projection_Node{
		role=.List_Item,
		actions=transmute(Accessibility_Projection_Actions)(bit_set[Accessibility_Projection_Action; u32]{.Scroll_Into_View}),
	}
	action, reveal, supported = native_accessibility_action_to_semantic(ACCESSKIT_ACTION_SCROLL_INTO_VIEW, virtual_item)
	testing.expect(t, supported && action == .Scroll_Into_View && reveal,
		"ScrollIntoView must remain a reveal request, not a perform/click action")
	action, reveal, supported = native_accessibility_action_to_semantic(ACCESSKIT_ACTION_CLICK, virtual_item)
	testing.expect(t, !supported && action == .None && !reveal,
		"unadvertised AccessKit actions must not be synthesized")
	scrollable_collection := Accessibility_Projection_Node{
		role=.List,
		actions=transmute(Accessibility_Projection_Actions)(bit_set[Accessibility_Projection_Action; u32]{.Scroll_Forward, .Scroll_Backward}),
	}
	action, reveal, supported = native_accessibility_action_to_semantic(ACCESSKIT_ACTION_SCROLL_DOWN, scrollable_collection)
	testing.expect(t, supported && action == .Scroll_Forward && !reveal,
		"AccessKit scroll-down should route to the collection's forward semantic action")
	action, reveal, supported = native_accessibility_action_to_semantic(ACCESSKIT_ACTION_SCROLL_UP, scrollable_collection)
	testing.expect(t, supported && action == .Scroll_Backward && !reveal,
		"AccessKit scroll-up should route to the collection's backward semantic action")
}

@(test)
test_accessibility_action_translation_supports_slider_adjustment :: proc(t: ^testing.T) {
	slider := Accessibility_Projection_Node{
		role=.Slider,
		actions=transmute(Accessibility_Projection_Actions)(bit_set[Accessibility_Projection_Action; u32]{
			.Set_Value, .Increment, .Decrement,
		}),
	}
	action, reveal, supported := native_accessibility_action_to_semantic(ACCESSKIT_ACTION_INCREMENT, slider)
	testing.expect(t, supported && action == .Increment && !reveal,
		"AccessKit slider increment should route as an application-owned action")
	action, reveal, supported = native_accessibility_action_to_semantic(ACCESSKIT_ACTION_DECREMENT, slider)
	testing.expect(t, supported && action == .Decrement && !reveal,
		"AccessKit slider decrement should route as an application-owned action")
}

@(test)
test_accessibility_projection_exports_stable_reversible_semantic_ids :: proc(t: ^testing.T) {
	first_id := alicorn.Semantic_ID{namespace=17, value=99}
	second_id := alicorn.Semantic_ID{namespace=18, value=99}
	first_node_id, first_ok := accessibility_semantic_to_node_id(first_id)
	second_node_id, second_ok := accessibility_semantic_to_node_id(second_id)
	_, zero_ok := accessibility_semantic_to_node_id({})
	testing.expect(t, first_ok && second_ok && first_node_id != second_node_id,
		"stable node IDs must incorporate both namespace and value")
	testing.expect(t, !zero_ok, "zero semantic identity must not map to a platform node")

	nodes := [2]alicorn.Semantic_Node{
		{id=first_id, role=.Button, label="Save", tree_order=1},
		{id=second_id, role=.Text_Field, label="Name", tree_order=2},
	}
	first_snapshot := accessibility_projection_test_snapshot(4, nodes[:])
	projection, status := accessibility_projection_from_snapshot(first_snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "semantic snapshot should project")
	defer accessibility_projection_destroy(&projection)
	projected_first, found_first := accessibility_projection_node_by_semantic_id(projection, first_id)
	projected_second, found_second := accessibility_projection_node_by_id(projection, second_node_id)
	testing.expect(t, found_first && projected_first.id == first_node_id,
		"semantic lookup should return its deterministic platform ID")
	testing.expect(t, found_second && projected_second.semantic_id == second_id,
		"platform lookup should preserve the full reverse semantic identity")
	testing.expect(t, len(projection.nodes) == 3 && projection.nodes[0].id == projection.root_id,
		"projection nodes should enumerate the synthetic root and bounded snapshot entities")
	reversed_nodes := [2]alicorn.Semantic_Node{nodes[1], nodes[0]}
	reversed_snapshot := accessibility_projection_test_snapshot(4, reversed_nodes[:])
	reversed_projection, reversed_status := accessibility_projection_from_snapshot(reversed_snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&reversed_projection)
	reversed_first, reversed_found := accessibility_projection_node_by_semantic_id(reversed_projection, first_id)
	testing.expect(t, reversed_status == .Success && reversed_found && reversed_first.id == first_node_id,
		"semantic-to-platform identity must not depend on snapshot enumeration order")
	no_op := alicorn.Semantic_Update_View{from_revision=4, to_revision=4}
	empty_delta, no_op_result := accessibility_projection_apply_update(&projection, no_op, first_snapshot, context.temp_allocator)
	defer accessibility_projection_delta_destroy(&empty_delta)
	testing.expect(t, no_op_result == .Applied && len(empty_delta.changed_nodes) == 0 &&
		len(empty_delta.removed_ids) == 0 && empty_delta.keyboard_focus == projection.root_id,
		"an unchanged semantic revision should produce an empty, allocation-bounded transition")
}

@(test)
test_accessibility_projection_focus_only_update_reuses_tree_and_advances_revision :: proc(t: ^testing.T) {
	first_id := alicorn.Semantic_ID{namespace=27, value=1}
	second_id := alicorn.Semantic_ID{namespace=27, value=2}
	nodes := [2]alicorn.Semantic_Node{
		{id=first_id, role=.Button, label="First", tree_order=1},
		{id=second_id, role=.Text_Field, label="Second", tree_order=2},
	}
	initial_snapshot := accessibility_projection_test_snapshot(40, nodes[:], first_id)
	projection, status := accessibility_projection_from_snapshot(initial_snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "the focus-only fixture should build an initial projection")
	defer accessibility_projection_destroy(&projection)
	second_platform_id, second_id_ok := accessibility_semantic_to_node_id(second_id)
	testing.expect(t, second_id_ok && projection.keyboard_focus_semantic_id == first_id,
		"initial keyboard focus should be represented in the projection")

	next_snapshot := accessibility_projection_test_snapshot(41, nodes[:], second_id)
	update := alicorn.Semantic_Update_View{
		from_revision=40,
		to_revision=41,
		keyboard_focus=second_id,
	}
	nodes_storage := raw_data(projection.nodes)
	delta, result := accessibility_projection_apply_update(&projection, update, next_snapshot, context.temp_allocator)
	defer accessibility_projection_delta_destroy(&delta)
	testing.expect(t, result == .Applied && !delta.requires_snapshot &&
		len(delta.changed_nodes) == 0 && len(delta.removed_ids) == 0,
		"a focus-only semantic revision should update focus without producing node changes")
	testing.expect(t, projection.revision == 41 && projection.keyboard_focus == second_platform_id &&
		projection.keyboard_focus_semantic_id == second_id && delta.keyboard_focus == second_platform_id,
		"the focus-only transition should advance revision and publish the new platform focus ID")
	testing.expect(t, raw_data(projection.nodes) == nodes_storage,
		"focus-only transitions must preserve the retained node storage instead of cloning the full tree")

	stale_update := alicorn.Semantic_Update_View{
		from_revision=41,
		to_revision=42,
		keyboard_focus=first_id,
	}
	stale_snapshot := accessibility_projection_test_snapshot(42, nodes[:], second_id)
	stale_delta, stale_result := accessibility_projection_apply_update(&projection, stale_update, stale_snapshot, context.temp_allocator)
	defer accessibility_projection_delta_destroy(&stale_delta)
	testing.expect(t, stale_result == .Requires_Snapshot && projection.revision == 41 &&
		projection.keyboard_focus_semantic_id == second_id && raw_data(projection.nodes) == nodes_storage,
		"focus disagreement must keep the exact-base projection unchanged and request a fresh snapshot")

	incomplete_nodes := [1]alicorn.Semantic_Node{nodes[0]}
	incomplete_snapshot := accessibility_projection_test_snapshot(42, incomplete_nodes[:], second_id)
	incomplete_update := alicorn.Semantic_Update_View{
		from_revision=41,
		to_revision=42,
		keyboard_focus=second_id,
	}
	incomplete_delta, incomplete_result := accessibility_projection_apply_update(
		&projection, incomplete_update, incomplete_snapshot, context.temp_allocator,
	)
	defer accessibility_projection_delta_destroy(&incomplete_delta)
	testing.expect(t, incomplete_result == .Requires_Snapshot && projection.revision == 41 &&
			projection.keyboard_focus_semantic_id == second_id && raw_data(projection.nodes) == nodes_storage,
		"an empty delta cannot advance across a snapshot with missing entities")
}

@(test)
test_accessibility_projection_destroy_with_persistent_allocator :: proc(t: ^testing.T) {
	id := alicorn.Semantic_ID{namespace=19, value=1}
	nodes := [1]alicorn.Semantic_Node{{id=id, role=.Button, label="Open"}}
	snapshot := accessibility_projection_test_snapshot(1, nodes[:])
	projection, status := accessibility_projection_from_snapshot(
		snapshot,
		base_runtime.default_context().allocator,
	)
	defer accessibility_projection_destroy(&projection)
	testing.expect(t, status == .Success && projection.nodes[0].label == "Alicorn",
		"persistent projection ownership should include the synthetic root label")
}

@(test)
test_accessibility_projection_rejects_current_id_collisions :: proc(t: ^testing.T) {
	nodes := [2]alicorn.Semantic_Node{
		{id={namespace=20, value=1}, role=.Button, label="One"},
		{id={namespace=20, value=2}, role=.Button, label="Two"},
	}
	snapshot := accessibility_projection_test_snapshot(1, nodes[:])
	projection, status := accessibility_projection_from_snapshot_with_hash(
		snapshot,
		context.temp_allocator,
		accessibility_projection_test_collision_hash,
	)
	testing.expect(t, status == .ID_Collision,
		"colliding IDs in the current projection must fail instead of aliasing semantic entities")
	accessibility_projection_destroy(&projection)
}

@(test)
test_accessibility_projection_delta_includes_parent_after_child_removal :: proc(t: ^testing.T) {
	parent_id := alicorn.Semantic_ID{namespace=21, value=1}
	child_id := alicorn.Semantic_ID{namespace=21, value=2}
	initial_nodes := [2]alicorn.Semantic_Node{
		{id=parent_id, role=.Group, label="Toolbar", tree_order=1},
		{id=child_id, role=.Button, label="Save", parent=parent_id, tree_order=2},
	}
	initial_snapshot := accessibility_projection_test_snapshot(40, initial_nodes[:])
	projection, status := accessibility_projection_from_snapshot(initial_snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "initial semantic tree should project")
	defer accessibility_projection_destroy(&projection)

	updated_nodes := [1]alicorn.Semantic_Node{
		{id=parent_id, role=.Group, label="Toolbar", tree_order=1},
	}
	updated_snapshot := accessibility_projection_test_snapshot(41, updated_nodes[:])
	removed := [1]alicorn.Semantic_ID{child_id}
	update := alicorn.Semantic_Update_View{
		from_revision=40,
		to_revision=41,
		removed_ids=removed[:],
	}
	delta, applied := accessibility_projection_apply_update(&projection, update, updated_snapshot, context.temp_allocator)
	testing.expect(t, applied == .Applied && !delta.requires_snapshot,
		"an exact-base removal delta should apply")
	defer accessibility_projection_delta_destroy(&delta)
	testing.expect(t, len(delta.removed_ids) == 1,
		"removed semantic items should become platform removal IDs")
	parent_update, parent_in_delta := accessibility_projection_test_find_node(delta.changed_nodes[:], parent_id)
	testing.expect(t, parent_in_delta && len(parent_update.children) == 0,
		"the old parent must be included when its child list changes")
	parent_after, parent_found := accessibility_projection_node_by_semantic_id(projection, parent_id)
	testing.expect(t, parent_found && len(parent_after.children) == 0 && projection.revision == 41,
		"successful delta application should atomically advance the stored projection")
}

@(test)
test_accessibility_projection_attaches_parentless_and_orphan_nodes_to_synthetic_root :: proc(t: ^testing.T) {
	parentless_id := alicorn.Semantic_ID{namespace=24, value=1}
	orphan_id := alicorn.Semantic_ID{namespace=24, value=2}
	nodes := [2]alicorn.Semantic_Node{
		{id=parentless_id, role=.Group, label="Detached", tree_order=1},
		{id=orphan_id, role=.Button, label="Orphan", parent={namespace=24, value=999}, tree_order=2},
	}
	snapshot := accessibility_projection_test_snapshot(2, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "parentless and orphaned nodes should remain projectable")
	defer accessibility_projection_destroy(&projection)
	testing.expect(t, len(projection.nodes[0].children) == 2,
		"synthetic root should retain both parentless and missing-parent entities")
}

@(test)
test_accessibility_projection_unknown_base_requests_snapshot_without_mutation :: proc(t: ^testing.T) {
	id := alicorn.Semantic_ID{namespace=22, value=1}
	nodes := [1]alicorn.Semantic_Node{{id=id, role=.Button, label="Open"}}
	snapshot := accessibility_projection_test_snapshot(8, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "initial semantic tree should project")
	defer accessibility_projection_destroy(&projection)
	update := alicorn.Semantic_Update_View{from_revision=6, to_revision=9}
	next_snapshot := accessibility_projection_test_snapshot(9, nodes[:])
	delta, result := accessibility_projection_apply_update(&projection, update, next_snapshot, context.temp_allocator)
	defer accessibility_projection_delta_destroy(&delta)
	testing.expect(t, result == .Requires_Snapshot && delta.requires_snapshot,
		"a nonmatching base revision must request a full snapshot")
	testing.expect(t, projection.revision == 8,
		"failed delta application must leave the current projection untouched")
}

@(test)
test_accessibility_projection_keeps_virtual_collection_bounded_and_zero_based_positions :: proc(t: ^testing.T) {
	collection_id := alicorn.Semantic_ID{namespace=23, value=1}
	item_id := alicorn.Semantic_ID{namespace=23, value=582_341}
	first_item_id := alicorn.Semantic_ID{namespace=23, value=2}
	collection := alicorn.Semantic_Node{
		id=collection_id,
		role=.List,
		label="Results",
		is_collection=true,
		logical_count=1_000_000,
		selected_id=item_id,
		current_id=item_id,
		actions=transmute(alicorn.Semantic_Actions)(bit_set[alicorn.Semantic_Action; u32]{.Focus, .Scroll_Forward, .Scroll_Backward}),
		tree_order=1,
	}
	item := alicorn.Semantic_Node{
		id=item_id,
		role=.List_Item,
		label="Result 582341",
		value="current result",
		description="Virtual result in the filtered collection",
		parent=collection_id,
		collection_id=collection_id,
		position_in_set=582_340,
		size_of_set=1_000_000,
		is_virtual_item=true,
		states=transmute(alicorn.Semantic_States)(bit_set[alicorn.Semantic_State; u32]{.Modified}),
		actions=transmute(alicorn.Semantic_Actions)(bit_set[alicorn.Semantic_Action; u32]{.Press, .Scroll_Into_View}),
		has_bounds=true,
		bounds=alicorn.Rect{20, 30, 200, 24},
		tree_order=2,
	}
	first_item := alicorn.Semantic_Node{
		id=first_item_id,
		role=.List_Item,
		label="Result 1",
		parent=collection_id,
		collection_id=collection_id,
		position_in_set=0,
		size_of_set=1_000_000,
		is_virtual_item=true,
		tree_order=3,
	}
	nodes := [3]alicorn.Semantic_Node{collection, item, first_item}
	snapshot := accessibility_projection_test_snapshot(12, nodes[:], item_id)
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "bounded virtual snapshot should project")
	defer accessibility_projection_destroy(&projection)
	testing.expect(t, len(projection.nodes) == 4,
		"logical collection size must not expand the already bounded semantic snapshot")
	collection_node, collection_found := accessibility_projection_node_by_semantic_id(projection, collection_id)
	item_node, item_found := accessibility_projection_node_by_semantic_id(projection, item_id)
	first_item_node, first_item_found := accessibility_projection_node_by_semantic_id(projection, first_item_id)
	testing.expect(t, collection_found && collection_node.is_collection && collection_node.logical_count == 1_000_000,
		"collection should retain its full logical size")
	testing.expect(t, accessibility_projection_action_has(collection_node.actions, .Scroll_Forward) &&
		accessibility_projection_action_has(collection_node.actions, .Scroll_Backward),
		"advertised collection scroll actions should survive the AccessKit projection")
	testing.expect(t, collection_node.size_of_set == 1_000_000 && item_found && item_node.has_position_in_set &&
		item_node.position_in_set == 582_340 && item_node.size_of_set == 0,
		"the collection should own total size and item positions should remain zero-based")
	testing.expect(t, first_item_found && first_item_node.has_position_in_set && first_item_node.position_in_set == 0 &&
		first_item_node.size_of_set == 0,
		"the first collection item must export its present zero-based position")
	testing.expect(t, item_node.role == .List_Item && item_node.label == "Result 582341" &&
		item_node.value == "current result" && item_node.description == "Virtual result in the filtered collection",
		"semantic role, label, description, and value should be preserved")
	testing.expect(t, accessibility_projection_state_has(item_node.states, .Selected) &&
		accessibility_projection_state_has(item_node.states, .Current) &&
		accessibility_projection_state_has(item_node.states, .Modified),
		"collection selection/current and authored item states should all survive projection")
	testing.expect(t, item_node.has_bounds && item_node.bounds == (alicorn.Rect{20, 30, 200, 24}) &&
		accessibility_projection_action_has(item_node.actions, .Press) &&
		accessibility_projection_action_has(item_node.actions, .Scroll_Into_View),
		"bounds and supported semantic actions should be preserved")
}

@(test)
test_accessibility_projection_orders_realized_and_virtual_collection_items_logically :: proc(t: ^testing.T) {
	collection_id := alicorn.Semantic_ID{namespace=24, value=1}
	first_id := alicorn.Semantic_ID{namespace=24, value=10}
	second_id := alicorn.Semantic_ID{namespace=24, value=11}
	third_id := alicorn.Semantic_ID{namespace=24, value=12}
	nodes := [4]alicorn.Semantic_Node{
		{id=collection_id, role=.List, label="Records", is_collection=true, logical_count=1_000_000, tree_order=1},
		// The rows around the realized range have no visual traversal order.
		// Their stable IDs sort around, rather than among, the realized row.
		{id=first_id, role=.List_Item, label="Record 10", parent=collection_id,
			collection_id=collection_id, position_in_set=9, size_of_set=1_000_000,
			is_virtual_item=true, tree_order=0},
		{id=second_id, role=.List_Item, label="Record 11", parent=collection_id,
			collection_id=collection_id, position_in_set=10, size_of_set=1_000_000,
			tree_order=100},
		{id=third_id, role=.List_Item, label="Record 12", parent=collection_id,
			collection_id=collection_id, position_in_set=11, size_of_set=1_000_000,
			is_virtual_item=true, tree_order=0},
	}
	snapshot := accessibility_projection_test_snapshot(13, nodes[:])
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	defer accessibility_projection_destroy(&projection)
	collection_node, found := accessibility_projection_node_by_semantic_id(projection, collection_id)
	ordered := [3]alicorn.Semantic_ID{}
	if found && len(collection_node.children) == len(ordered) {
		for child_id, index in collection_node.children {
			child, child_found := accessibility_projection_node_by_id(projection, child_id)
			if child_found { ordered[index] = child.semantic_id }
		}
	}
	testing.expect(t, status == .Success && found && len(collection_node.children) == 3 &&
		ordered[0] == first_id && ordered[1] == second_id && ordered[2] == third_id,
		"assistive technology must receive realized and virtual rows in logical collection order")
}
