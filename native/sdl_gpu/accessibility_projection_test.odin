package alicorn_sdl_gpu

import "core:testing"
import base_runtime "base:runtime"
import alicorn "../../runtime"

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
test_accessibility_projection_keeps_virtual_collection_bounded_and_positions_absolute :: proc(t: ^testing.T) {
	collection_id := alicorn.Semantic_ID{namespace=23, value=1}
	item_id := alicorn.Semantic_ID{namespace=23, value=582_341}
	collection := alicorn.Semantic_Node{
		id=collection_id,
		role=.List,
		label="Results",
		is_collection=true,
		logical_count=1_000_000,
		selected_id=item_id,
		current_id=item_id,
		actions=transmute(alicorn.Semantic_Actions)(bit_set[alicorn.Semantic_Action; u32]{.Focus}),
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
	nodes := [2]alicorn.Semantic_Node{collection, item}
	snapshot := accessibility_projection_test_snapshot(12, nodes[:], item_id)
	projection, status := accessibility_projection_from_snapshot(snapshot, context.temp_allocator)
	testing.expect(t, status == .Success, "bounded virtual snapshot should project")
	defer accessibility_projection_destroy(&projection)
	testing.expect(t, len(projection.nodes) == 3,
		"logical collection size must not expand the already bounded semantic snapshot")
	collection_node, collection_found := accessibility_projection_node_by_semantic_id(projection, collection_id)
	item_node, item_found := accessibility_projection_node_by_semantic_id(projection, item_id)
	testing.expect(t, collection_found && collection_node.is_collection && collection_node.logical_count == 1_000_000,
		"collection should retain its full logical size")
	testing.expect(t, item_found && item_node.position_in_set == 582_341 && item_node.size_of_set == 1_000_000,
		"zero-based Alicorn index should map to one-based absolute platform position")
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
