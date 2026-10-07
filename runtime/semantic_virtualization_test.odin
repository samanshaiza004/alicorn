package alicorn

import "core:testing"
import "core:fmt"

SEMANTIC_VIRTUAL_TEST_NAMESPACE :: u64(0x53454D5649525401)
SEMANTIC_VIRTUAL_TEST_COLLECTION_VALUE :: u64(1)
SEMANTIC_VIRTUAL_TEST_ITEM_BASE :: u64(0x100000000)
SEMANTIC_VIRTUAL_TEST_ITEM_COUNT :: 1_000_000
SEMANTIC_VIRTUAL_TEST_ROW_HEIGHT :: f32(24)

semantic_virtual_test_id :: proc(value: u64) -> Semantic_ID {
	return Semantic_ID{namespace=SEMANTIC_VIRTUAL_TEST_NAMESPACE, value=value}
}

semantic_virtual_test_item_id :: proc(logical_position: int) -> Semantic_ID {
	// This is the fixture record's durable model key. The loop's visible slot,
	// Node_ID, and current virtual-list first index are deliberately not used.
	return semantic_virtual_test_id(SEMANTIC_VIRTUAL_TEST_ITEM_BASE+u64(logical_position))
}

semantic_virtual_test_position :: proc(id: Semantic_ID) -> (position: int, found: bool) {
	if id.namespace != SEMANTIC_VIRTUAL_TEST_NAMESPACE || id.value < SEMANTIC_VIRTUAL_TEST_ITEM_BASE { return }
	position = int(id.value-SEMANTIC_VIRTUAL_TEST_ITEM_BASE)
	found = position < SEMANTIC_VIRTUAL_TEST_ITEM_COUNT
	return
}

semantic_virtual_test_has_id :: proc(ids: []Semantic_ID, target: Semantic_ID) -> bool {
	for id in ids {
		if id == target { return true }
	}
	return false
}

semantic_virtual_test_render :: proc(
	rt: ^Runtime,
	horizon: int = 0,
	current_id := Semantic_ID{},
	selected_id := Semantic_ID{},
) -> (owner: Node_ID, first, last: int) {
	invalidate_root(rt, "semantic million-row virtualization fixture")
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(
		&ui,
		.Root,
		label="semantic-million-root",
		key=key_string("semantic-million-root"),
		style=layout_style(.Column, width=360, height=216),
	)
	list := virtual_list_begin(
		&ui,
		SEMANTIC_VIRTUAL_TEST_ITEM_COUNT,
		SEMANTIC_VIRTUAL_TEST_ROW_HEIGHT,
		key=key_string("semantic-million-list"),
		style=layout_style(height=168),
		label="semantic-million-list",
		scrollbars=.Hidden,
	)
	owner, first, last = list.scroll.id, list.first, list.last
	collection := semantic_collection_begin(
		&ui,
		list.scroll.id,
		semantic_virtual_test_id(SEMANTIC_VIRTUAL_TEST_COLLECTION_VALUE),
		.List,
		"Million records",
		u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
		selected_id=selected_id,
		current_id=current_id,
		realized_first=u64(list.first),
		realized_last=u64(list.last),
	)
	for logical_position := list.first; logical_position < list.last; logical_position += 1 {
		item_id := semantic_virtual_test_item_id(logical_position)
		states := Semantic_States{}
		if item_id == selected_id { states = semantic_states_add(states, .Selected) }
		if item_id == current_id { states = semantic_states_add(states, .Current) }
		if !key_scope_begin_key(&ui, key_u64(item_id.value)) { continue }
		row_label := fmt.tprintf("Record %d", logical_position)
		container_begin_simple(
			&ui,
			.Virtual_Row,
			label=row_label,
			style=layout_style(.Row, height=SEMANTIC_VIRTUAL_TEST_ROW_HEIGHT),
		)
		_ = semantic_collection_item(
			&ui,
			collection,
			u64(logical_position),
			Semantic_Node_Description{
				id=item_id,
				role=.List_Item,
				label=row_label,
			states=states,
				actions=semantic_actions_add({}, .Focus),
			},
		)
		container_end(&ui)
		key_scope_end(&ui)
	}
	for logical_position := max(list.first-horizon, 0); logical_position < list.first; logical_position += 1 {
		item_id := semantic_virtual_test_item_id(logical_position)
		states := Semantic_States{}
		if item_id == selected_id { states = semantic_states_add(states, .Selected) }
		if item_id == current_id { states = semantic_states_add(states, .Current) }
		_ = semantic_collection_virtual_item(&ui, collection, u64(logical_position), Semantic_Node_Description{
			id=item_id,
			role=.List_Item,
			label=fmt.tprintf("Record %d", logical_position),
			states=states,
			actions=semantic_actions_add({}, .Focus),
		})
	}
	for logical_position := list.last; logical_position < min(list.last+horizon, SEMANTIC_VIRTUAL_TEST_ITEM_COUNT); logical_position += 1 {
		item_id := semantic_virtual_test_item_id(logical_position)
		states := Semantic_States{}
		if item_id == selected_id { states = semantic_states_add(states, .Selected) }
		if item_id == current_id { states = semantic_states_add(states, .Current) }
		_ = semantic_collection_virtual_item(&ui, collection, u64(logical_position), Semantic_Node_Description{
			id=item_id,
			role=.List_Item,
			label=fmt.tprintf("Record %d", logical_position),
			states=states,
			actions=semantic_actions_add({}, .Focus),
		})
	}
	working_first := max(list.first-horizon, 0)
	working_last := min(list.last+horizon, SEMANTIC_VIRTUAL_TEST_ITEM_COUNT)
	targets := [2]Semantic_ID{selected_id, current_id}
	for target in targets {
		position, found := semantic_virtual_test_position(target)
		if !found || (position >= working_first && position < working_last) { continue }
		states := Semantic_States{}
		if target == selected_id { states = semantic_states_add(states, .Selected) }
		if target == current_id { states = semantic_states_add(states, .Current) }
		_ = semantic_collection_virtual_item(&ui, collection, u64(position), Semantic_Node_Description{
			id=target,
			role=.List_Item,
			label=fmt.tprintf("Record %d", position),
			states=states,
			actions=semantic_actions_add({}, .Focus),
		})
	}
	virtual_list_end(&ui, list)
	container_end(&ui)
	end_frame(&ui)
	return
}

semantic_action_test_render :: proc(rt: ^Runtime) -> (node: Node_ID, activated: bool) {
	invalidate_root(rt, "semantic action routing fixture")
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(&ui, .Root, label="semantic-action-root", key=key_string("semantic-action-root"), style=layout_style(.Column, width=280, height=100))
	activated = button(&ui, "Apply", key_string("semantic-action-apply"), style=layout_style(width=120, height=32))
	if len(ui.runtime.pending) > 0 { node = ui.runtime.pending[len(ui.runtime.pending)-1].description.id }
	container_end(&ui)
	end_frame(&ui)
	return node, activated
}

@(test)
test_semantic_revisioned_latest_delta_and_snapshot_fallback :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)

	first_id := semantic_virtual_test_id(100)
	removed_id := semantic_virtual_test_id(200)
	added_id := semantic_virtual_test_id(300)
	first := Semantic_Node_Description{id=first_id, role=.Button, label="Save", value="ready"}
	removed := Semantic_Node_Description{id=removed_id, role=.List_Item, label="Old entry"}
	testing.expect(t, semantic_node_set(&rt, first), "valid semantic descriptions should be retained")
	testing.expect(t, semantic_node_set(&rt, removed), "a second entity should be retained")
	testing.expect(t, semantic_commit(&rt), "one commit should publish the pending entity set")
	base_revision := semantic_revision(&rt)
	testing.expect(t, base_revision == 1, "the initial semantic publication should create revision one")
	testing.expect(t, rt.stats.semantic_projection_nodes_added == 2 && rt.stats.semantic_projection_nodes_updated == 0 &&
		rt.stats.semantic_projection_nodes_removed == 0,
		"the first semantic revision should instrument its two bounded additions")

	initial := semantic_update_since(&rt, 0)
	testing.expect(t, !initial.requires_snapshot && initial.from_revision == 0 && initial.to_revision == base_revision,
		"a consumer at the exact base revision should receive the latest ordered delta")
	testing.expect(t, semantic_virtual_test_has_id(initial.changed_ids, first_id) &&
		semantic_virtual_test_has_id(initial.changed_ids, removed_id),
		"the latest delta should identify all changed semantic entities")

	first.label = "Save document"
	first.value = "saved"
	testing.expect(t, semantic_node_set(&rt, first), "changed content should replace the retained description")
	testing.expect(t, semantic_node_remove(&rt, removed_id), "removed entities should be recorded for the next delta")
	testing.expect(t, semantic_node_set(&rt, Semantic_Node_Description{id=added_id, role=.Checkbox, label="Keep open"}),
		"new entities should join the same pending revision")
	testing.expect(t, semantic_commit(&rt), "all changes since the prior commit should publish atomically")
	testing.expect(t, rt.stats.semantic_projection_nodes_added == 3 && rt.stats.semantic_projection_nodes_updated == 1 &&
		rt.stats.semantic_projection_nodes_removed == 1,
		"semantic revision counters should distinguish add, update, and removal operations")

	latest := semantic_update_since(&rt, base_revision)
	testing.expect(t, !latest.requires_snapshot && latest.from_revision == base_revision && latest.to_revision == base_revision+1,
		"a consumer with the latest base should receive exactly the next revision")
	testing.expect(t, semantic_virtual_test_has_id(latest.changed_ids, first_id) &&
		semantic_virtual_test_has_id(latest.changed_ids, added_id) &&
		semantic_virtual_test_has_id(latest.removed_ids, removed_id),
		"the latest delta should include changed, added, and removed identities")

	missed := semantic_update_since(&rt, 0)
	testing.expect(t, missed.requires_snapshot,
		"a consumer that missed a base-dependent revision must request a complete snapshot")

	snapshot := semantic_snapshot(&rt)
	defer semantic_snapshot_destroy(&snapshot)
	testing.expect(t, snapshot.revision == semantic_revision(&rt) && len(snapshot.nodes) == 2,
		"a full snapshot should describe the current revision without removed entities")
	first_found, added_found := false, false
	for node in snapshot.nodes {
		if node.id == first_id {
			first_found = node.label == "Save document" && node.value == "saved"
		}
		if node.id == added_id { added_found = node.label == "Keep open" && node.role == .Checkbox }
	}
	testing.expect(t, first_found && added_found,
		"snapshots should preserve stable semantic IDs and owned current label/value content")
	_, removed_still_found := semantic_node_lookup(&rt, removed_id)
	testing.expect(t, !removed_still_found, "removed semantic IDs should not reappear in full snapshots")
}

@(test)
test_semantic_virtual_collection_is_bounded_for_million_items :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 216})
	defer destroy_runtime(&rt)

	owner, first, last := semantic_virtual_test_render(&rt)
	testing.expect(t, owner != 0 && first >= 0 && last > first,
		"the fixture should realize a nonempty visible range through virtual_list")
	if owner == 0 || last <= first { return }

	collection_id := semantic_virtual_test_id(SEMANTIC_VIRTUAL_TEST_COLLECTION_VALUE)
	collection, collection_found := semantic_node_lookup(&rt, collection_id)
	visible_count := last-first
	testing.expect(t, collection_found && collection.is_collection && collection.role == .List &&
		collection.logical_count == u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
		"one retained collection should describe the full logical million-item count")
	testing.expect(t, len(rt.semantic_entities) == visible_count+1,
		"semantic retention should scale with visible rows plus one collection, not logical item count")

	initial_ids := make([dynamic]Semantic_ID, 0, visible_count)
	defer delete(initial_ids)
	for logical_position := first; logical_position < last; logical_position += 1 {
		item_id := semantic_virtual_test_item_id(logical_position)
		append(&initial_ids, item_id)
		item, found := semantic_node_lookup(&rt, item_id)
		testing.expect(t, found && item.role == .List_Item && item.is_virtual_item == false &&
			item.collection_id == collection_id && item.parent == collection_id &&
			item.position_in_set == u64(logical_position) &&
			item.size_of_set == u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
			"realized semantics should use durable record IDs and report logical set position/size")
	}
	// A retained-region reuse can omit this collection from the just-described
	// work. Omission is not an empty collection and must not erase its semantics.
	clear(&rt.semantic_collection_touched)
	semantic_prune_touched_collections(&rt)
	_, collection_survived_reuse := semantic_node_lookup(&rt, collection_id)
	_, first_item_survived_reuse := semantic_node_lookup(&rt, semantic_virtual_test_item_id(first))
	testing.expect(t, collection_survived_reuse && first_item_survived_reuse && len(rt.semantic_entities) == visible_count+1,
		"reusing an unchanged visual subtree should preserve its collection and semantic rows")

	far_offset := f32(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT/2)*SEMANTIC_VIRTUAL_TEST_ROW_HEIGHT
	testing.expect(t, scroll_region_set_offset(&rt, owner, far_offset, "move million-row semantic fixture"),
		"the virtual list should scroll to a distant logical range without realizing intervening rows")
	owner_after_scroll, far_first, far_last := semantic_virtual_test_render(&rt)
	testing.expect(t, owner_after_scroll == owner && far_first > last && far_last > far_first,
		"scrolling should preserve the collection owner and realize only the distant visible range")
	if far_last <= far_first { return }
	collection_after_scroll, collection_still_found := semantic_node_lookup(&rt, collection_id)
	testing.expect(t, collection_still_found && collection_after_scroll.logical_count == u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
		"the same collection identity and logical count should survive virtual scrolling")
	testing.expect(t, len(rt.semantic_entities) == far_last-far_first+1,
		"the working set should replace old rows rather than accumulate semantics while scrolling")
	for logical_position := far_first; logical_position < far_last; logical_position += 1 {
		item_id := semantic_virtual_test_item_id(logical_position)
		item, found := semantic_node_lookup(&rt, item_id)
		testing.expect(t, found && item.position_in_set == u64(logical_position) &&
			item.collection_id == collection_id && item.size_of_set == u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
			"newly visible rows should be identified by their data records, not reused visual slots")
	}
	for old_id in initial_ids {
		_, still_retained := semantic_node_lookup(&rt, old_id)
		testing.expect(t, !still_retained,
			"rows outside the bounded visible working set should be released when not focused or current")
	}
}

@(test)
test_semantic_virtual_collection_horizon_and_pinned_entities :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 216})
	defer destroy_runtime(&rt)
	collection_id := semantic_virtual_test_id(SEMANTIC_VIRTUAL_TEST_COLLECTION_VALUE)

	// Policy B: visible plus a deliberately small two-item leading/trailing horizon.
	_, first, last := semantic_virtual_test_render(&rt, 2)
	initial_count := len(rt.semantic_entities)
	initial_expected := last-first + 1 + (min(2, SEMANTIC_VIRTUAL_TEST_ITEM_COUNT-last))
	testing.expect(t, initial_count == initial_expected,
		"the semantic horizon should add only the explicitly described nearby records")
	if last > first {
		trailing, trailing_found := semantic_node_lookup(&rt, semantic_virtual_test_item_id(last))
		testing.expect(t, trailing_found && trailing.is_virtual_item && trailing.visual_node == 0,
			"horizon records should be semantic entities without realized visual rows")
	}
	far_offset := f32(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT/2)*SEMANTIC_VIRTUAL_TEST_ROW_HEIGHT
	list_owner, _ := node_by_key(&rt, key_string("semantic-million-list"), .Scroll_Region)
	_ = scroll_region_set_offset(&rt, list_owner, far_offset, "move semantic horizon fixture")
	_, far_first, far_last := semantic_virtual_test_render(&rt, 2)
	far_expected := far_last-far_first + 1 + 4
	testing.expect(t, len(rt.semantic_entities) == far_expected,
		"visible-plus-horizon export should remain bounded after a distant scroll")

	// Policy C: keep a logical current item and a separate semantically focused
	// item pinned after their visual rows leave the viewport and horizon.
	current_rt := new_runtime(Rect{0, 0, 360, 216})
	defer destroy_runtime(&current_rt)
	current_id := semantic_virtual_test_item_id(0)
	focused_id := semantic_virtual_test_item_id(1)
	owner, current_first, current_last := semantic_virtual_test_render(&current_rt, 2, current_id)
	testing.expect(t, current_first == 0 && current_last > 2,
		"the first build should expose current and focused entities as realized rows")
	_ = semantic_focus_set(&current_rt, focused_id, owner)
	current_owner, _ := node_by_key(&current_rt, key_string("semantic-million-list"), .Scroll_Region)
	_ = scroll_region_set_offset(&current_rt, current_owner, far_offset, "move pinned semantic fixture")
	_, pinned_first, pinned_last := semantic_virtual_test_render(&current_rt, 2, current_id)
	current, current_found := semantic_node_lookup(&current_rt, current_id)
	focused, focused_found := semantic_node_lookup(&current_rt, focused_id)
	testing.expect(t, current_found && current.visual_node == 0 && focused_found && focused.visual_node == 0,
		"selected/current and semantic-focus identities should remain available after visual unrealization")
	testing.expect(t, current.collection_id == collection_id && current.position_in_set == 0 &&
		focused.collection_id == collection_id && focused.position_in_set == 1,
		"pinned entities must retain their durable collection positions")
	testing.expect(t, len(current_rt.semantic_entities) == pinned_last-pinned_first+1+4+2,
		"the pinned policy should add only the visible range, horizon, collection, and pinned entities")
}

@(test)
test_virtual_selection_churn_does_not_pin_stale_selected_rows :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 360, 216})
	defer destroy_runtime(&rt)
	selected_id := semantic_virtual_test_item_id(0)
	owner, _, _ := semantic_virtual_test_render(&rt, 1, selected_id=selected_id)
	far_offset := f32(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT/2)*SEMANTIC_VIRTUAL_TEST_ROW_HEIGHT
	_ = scroll_region_set_offset(&rt, owner, far_offset, "move selected semantic row out of view")
	_, first, last := semantic_virtual_test_render(&rt, 1, selected_id=selected_id)
	selected_item, selected_found := semantic_node_lookup(&rt, selected_id)
	testing.expect(t, selected_found && selected_item.visual_node == 0 && semantic_states_has(selected_item.states, .Selected),
		"the collection's current selected item should remain pinned beyond the visible horizon")
	previous_selected_id := selected_id
	for index := 1; index <= 8; index += 1 {
		selected_id = semantic_virtual_test_item_id(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT/4+index*500)
		_, first, last = semantic_virtual_test_render(&rt, 1, selected_id=selected_id)
		selected_item, selected_found = semantic_node_lookup(&rt, selected_id)
		_, stale_selected_found := semantic_node_lookup(&rt, previous_selected_id)
		expected_count := (last-first) + 2 + 1 + 1 // visible + horizon + collection + one selected item
		testing.expect(t, selected_found && selected_item.visual_node == 0 && semantic_states_has(selected_item.states, .Selected) &&
			!stale_selected_found && len(rt.semantic_entities) == expected_count,
			"changing selection must release the former selected item instead of accumulating navigation history")
		previous_selected_id = selected_id
	}
}

@(test)
test_semantic_controls_actions_and_tab_composition :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 360})
	defer destroy_runtime(&rt)
	button_node, first_activation := semantic_action_test_render(&rt)
	button_entity, button_found := semantic_node_lookup(&rt, semantic_visual_id(button_node))
	_ = first_activation
	testing.expect(t, button_found && button_entity.role == .Button && button_entity.label == "Apply" &&
		semantic_actions_has(button_entity.actions, .Press) && button_entity.has_bounds,
		"ordinary controls should publish an accessible role, label, action, and post-layout bounds")
	testing.expect(t, semantic_action_request(&rt, button_entity.id, .Press),
		"Press on a realized button should enter Alicorn's normal activation path")
	_, activated := semantic_action_test_render(&rt)
	testing.expect(t, activated, "semantic Press should be observed by the same button call as keyboard activation")

	readme_id := semantic_virtual_test_id(0xA001)
	license_id := semantic_virtual_test_id(0xA002)
	descriptions_before_tabs := rt.stats.semantic_descriptions_emitted
	items := [2]Tab_Bar_Item{
		{key=key_string("tab-readme"), label="README.md", selected=true, closable=true, dirty=true, semantic_id=readme_id},
		{key=key_string("tab-license"), label="LICENSE", closable=true, semantic_id=license_id},
	}
	invalidate_root(&rt, "semantic tab list fixture")
	ui, should_build := begin_frame(&rt)
	if should_build {
		container_begin_simple(&ui, .Root, label="semantic-tab-root", key=key_string("semantic-tab-root"), style=layout_style(.Column, width=640, height=360))
		_ = tab_bar(&ui, key_string("semantic-tab-bar"), items[:])
		container_end(&ui)
		end_frame(&ui)
	}
	tab_bar_owner, tab_bar_owner_found := node_by_key(&rt, key_string("semantic-tab-bar"), .Container)
	tab_bar_semantic_id := semantic_visual_id(tab_bar_owner)
	snapshot := semantic_snapshot(&rt)
	defer semantic_snapshot_destroy(&snapshot)
	tab_list_found, selected_found, dirty_found, close_found, license_found := false, false, false, false, false
	readme_entity, license_entity: Semantic_Node
	for entity in snapshot.nodes {
		if entity.role == .Tab_List {
			tab_list_found = entity.label == "Open documents" && entity.logical_count == 2 &&
				entity.selected_id == readme_id && entity.current_id == (Semantic_ID{})
		}
		if entity.id == readme_id {
			readme_entity = entity
			selected_found = tab_bar_owner_found && entity.role == .Tab && entity.parent == tab_bar_semantic_id &&
				semantic_states_has(entity.states, .Selected)
			dirty_found = semantic_states_has(entity.states, .Modified)
		}
		if entity.id == license_id { license_entity = entity; license_found = true }
		if entity.role == .Button && entity.label == "Close README.md" && entity.parent == readme_id {
			close_found = semantic_actions_has(entity.actions, .Press)
		}
	}
	testing.expect(t, tab_list_found && selected_found && dirty_found && close_found && license_found &&
		readme_entity.position_in_set == 0 && license_entity.position_in_set == 1 &&
		!semantic_states_has(readme_entity.states, .Current) && !semantic_states_has(license_entity.states, .Current) &&
		readme_entity.tree_order < license_entity.tree_order,
		"TabList selection should not duplicate selected state as current; decorative parts stay non-semantic")
	testing.expect(t, rt.stats.semantic_descriptions_emitted-descriptions_before_tabs == 5,
		"description telemetry should count TabList, two Tabs, and two close actions once each")
	base_revision := snapshot.revision
	semantic_snapshot_destroy(&snapshot)
	reordered_items := [2]Tab_Bar_Item{
		{key=key_string("tab-license"), label="LICENSE", selected=true, closable=true, semantic_id=license_id},
		{key=key_string("tab-readme"), label="README.md", closable=true, dirty=true, semantic_id=readme_id},
	}
	invalidate_root(&rt, "semantic tab reorder fixture")
	ui, should_build = begin_frame(&rt)
	if should_build {
		container_begin_simple(&ui, .Root, label="semantic-tab-root", key=key_string("semantic-tab-root"), style=layout_style(.Column, width=640, height=360))
		_ = tab_bar(&ui, key_string("semantic-tab-bar"), reordered_items[:])
		container_end(&ui)
		end_frame(&ui)
	}
	readme_after_reorder, readme_after_found := semantic_node_lookup(&rt, readme_id)
	license_after_reorder, license_after_found := semantic_node_lookup(&rt, license_id)
	delta := semantic_update_since(&rt, base_revision)
	testing.expect(t, readme_after_found && license_after_found && readme_after_reorder.position_in_set == 1 &&
		license_after_reorder.position_in_set == 0 && license_after_reorder.tree_order < readme_after_reorder.tree_order &&
		semantic_states_has(license_after_reorder.states, .Selected) && !semantic_states_has(readme_after_reorder.states, .Selected) &&
		!semantic_states_has(license_after_reorder.states, .Current) && !semantic_states_has(readme_after_reorder.states, .Current),
		"reordering tabs should preserve IDs while updating semantic order and selection")
	testing.expect(t, !delta.requires_snapshot && delta.from_revision == base_revision &&
		semantic_virtual_test_has_id(delta.changed_ids, readme_id) && semantic_virtual_test_has_id(delta.changed_ids, license_id),
		"a tab reorder should publish revisioned changes for the affected semantic entities")
}

@(test)
test_builtin_control_semantic_roles_values_and_actions :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 480, 240})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "built-in semantic controls fixture")
	ui, should_build := begin_frame(&rt)
	checkbox_node, slider_node, text_field_node: Node_ID
	if should_build {
		container_begin_simple(&ui, .Root, label="semantic-controls-root", key=key_string("semantic-controls-root"), style=layout_style(.Column, width=480, height=240))
		_ = checkbox(&ui, "Enabled", true, key_string("semantic-controls-enabled"), style=layout_style(width=180, height=32))
		checkbox_node = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
		_ = slider_f32(&ui, "Gain", 0.5, 0, 1, 0.1, key_string("semantic-controls-gain"), style=layout_style(width=180, height=32))
		slider_node = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
		text_field_node = text_field(&ui, "notes", key_string("semantic-controls-notes"), style=layout_style(width=180, height=32))
		container_end(&ui)
		end_frame(&ui)
	}
	checkbox_semantic, checkbox_found := semantic_node_lookup(&rt, semantic_visual_id(checkbox_node))
	slider_semantic, slider_found := semantic_node_lookup(&rt, semantic_visual_id(slider_node))
	field_semantic, field_found := semantic_node_lookup(&rt, semantic_visual_id(text_field_node))
	testing.expect(t, checkbox_found && checkbox_semantic.role == .Checkbox &&
		semantic_states_has(checkbox_semantic.states, .Checked) && semantic_actions_has(checkbox_semantic.actions, .Press),
		"checkbox state and activation should be represented semantically")
	testing.expect(t, slider_found && slider_semantic.role == .Slider && slider_semantic.has_numeric_value,
		"sliders should publish their role and a numeric value")
	testing.expect(t, slider_semantic.numeric_value == 0.5, "slider semantic value should match the authoritative application value")
	testing.expect(t, slider_semantic.numeric_minimum == 0 && slider_semantic.numeric_maximum == 1,
		"slider semantics should include its authoritative range")
	testing.expect(t, slider_semantic.numeric_step == f64(f32(0.1)), "slider semantics should include its configured step")
	testing.expect(t, semantic_actions_has(slider_semantic.actions, .Set_Value) && semantic_actions_has(slider_semantic.actions, .Increment),
		"enabled sliders should advertise set and increment actions")
	testing.expect(t, field_found && field_semantic.role == .Text_Field && field_semantic.value == "notes" &&
		semantic_actions_has(field_semantic.actions, .Focus) && semantic_actions_has(field_semantic.actions, .Set_Value),
		"text fields should expose current value and supported semantic actions")
	testing.expect(t, semantic_action_request(&rt, slider_semantic.id, .Set_Value, numeric_value=0.8, has_numeric_value=true),
		"semantic slider value changes should be queued as domain operations")
	request, found := semantic_request_pop(&rt)
	testing.expect(t, found && request.kind == .Perform && request.action == .Set_Value && request.numeric_value == 0.8 &&
		request.has_numeric_value && request.id == slider_semantic.id,
		"the app should receive the requested stable slider identity and numeric value")
	semantic_request_event_destroy(&rt, &request)
}

@(test)
test_semantic_idle_does_not_resolve_or_publish :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "semantic idle fixture")
	ui, should_build := begin_frame(&rt)
	if should_build {
		container_begin_simple(&ui, .Root, label="semantic-idle-root", key=key_string("semantic-idle-root"), style=layout_style(.Column, width=320, height=180))
		_ = button(&ui, "Save", key_string("semantic-idle-save"), style=layout_style(width=100, height=32))
		container_end(&ui)
		end_frame(&ui)
	}
	before := rt.stats
	revision := semantic_revision(&rt)
	idle_ui, idle_build := begin_frame(&rt)
	_ = idle_ui
	testing.expect(t, !idle_build, "an unchanged runtime should remain asleep with no accessibility adapter polling it")
	testing.expect(t, semantic_revision(&rt) == revision &&
		rt.stats.semantic_descriptions_emitted == before.semantic_descriptions_emitted &&
		rt.stats.semantic_entities_resolved == before.semantic_entities_resolved &&
		rt.stats.semantic_structure_changes == before.semantic_structure_changes &&
		rt.stats.semantic_property_changes == before.semantic_property_changes,
		"an untouched idle interval should perform no semantic resolution or publication")
}

@(test)
test_semantic_virtual_action_is_delivered_as_domain_event :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)
	id := semantic_virtual_test_item_id(77)
	item := Semantic_Node_Description{
		id=id,
		role=.List_Item,
		label="Build log",
		actions=semantic_actions_add({}, .Press),
		is_virtual_item=true,
	}
	testing.expect(t, semantic_node_set(&rt, item), "a logical-only item can be described without a visual node")
	_ = semantic_commit(&rt)
	testing.expect(t, semantic_action_request(&rt, id, .Press, text_value="open"),
		"actions on virtual entities should queue a domain event, not fake pointer activation")
	event, found := semantic_request_pop(&rt)
	testing.expect(t, found && event.kind == .Perform && event.id == id && event.action == .Press && event.text_value == "open",
		"the application should receive the stable logical ID and action payload on the requested build")
	semantic_request_event_destroy(&rt, &event)
	_, empty := semantic_request_pop(&rt)
	stats := rt.stats
	testing.expect(t, !empty && stats.accessibility_action_wakes == 1,
		"action delivery should drain cleanly and record its bounded wake")
}

@(test)
test_detached_collection_keeps_logical_selection_and_drops_incidental_rows :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)
	collection_id := semantic_virtual_test_id(0xB001)
	selected_id := semantic_virtual_test_item_id(900_001)
	incidental_id := semantic_virtual_test_item_id(900_002)
	_ = semantic_node_set(&rt, Semantic_Node_Description{
		id=collection_id,
		role=.List,
		label="Nested results",
		visual_node=77,
		is_collection=true,
		logical_count=10,
		selected_id=selected_id,
	})
	_ = semantic_node_set(&rt, Semantic_Node_Description{
		id=selected_id,
		role=.List_Item,
		label="Selected result",
		states=semantic_states_add({}, .Selected),
		parent=collection_id,
		collection_id=collection_id,
		position_in_set=8,
		size_of_set=10,
		is_virtual_item=true,
	})
	_ = semantic_node_set(&rt, Semantic_Node_Description{
		id=incidental_id,
		role=.List_Item,
		label="Nearby result",
		parent=collection_id,
		collection_id=collection_id,
		position_in_set=9,
		size_of_set=10,
		is_virtual_item=true,
	})
	_ = semantic_commit(&rt)
	owner := Node{id=77, semantic_id=collection_id}
	semantic_retire_node(&rt, &owner)
	semantic_prune_touched_collections(&rt)
	collection, collection_found := semantic_node_lookup(&rt, collection_id)
	selected, selected_found := semantic_node_lookup(&rt, selected_id)
	_, incidental_found := semantic_node_lookup(&rt, incidental_id)
	testing.expect(t, collection_found && collection.is_collection && collection.visual_node == 0 &&
		selected_found && selected.visual_node == 0 && collection.selected_id == selected_id,
		"a detached collection should retain identity and its selected logical item without visual nodes")
	testing.expect(t, !incidental_found,
		"detaching a collection should discard incidental rows instead of retaining old visible work")
	testing.expect(t, len(rt.semantic_entities) == 2,
		"a detached selected collection should retain only itself and its pinned selected item")
}

@(test)
test_semantic_reveal_is_not_a_perform_action :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 200})
	defer destroy_runtime(&rt)
	collection_id := semantic_virtual_test_id(SEMANTIC_VIRTUAL_TEST_COLLECTION_VALUE)
	item_id := semantic_virtual_test_item_id(42)
	_ = semantic_node_set(&rt, Semantic_Node_Description{
		id=collection_id,
		role=.List,
		label="Builds",
		is_collection=true,
		logical_count=u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
	})
	_ = semantic_node_set(&rt, Semantic_Node_Description{
		id=item_id,
		role=.List_Item,
		label="Build log",
		parent=collection_id,
		collection_id=collection_id,
		position_in_set=42,
		size_of_set=u64(SEMANTIC_VIRTUAL_TEST_ITEM_COUNT),
		is_virtual_item=true,
	})
	_ = semantic_commit(&rt)
	testing.expect(t, semantic_reveal_request(&rt, item_id),
		"a logical collection item should accept a separate reveal request")
	event, found := semantic_request_pop(&rt)
	testing.expect(t, found && event.kind == .Reveal && event.id == item_id && event.action == .None,
		"reveal delivery must be distinguishable from semantic action dispatch")
	semantic_request_event_destroy(&rt, &event)
	testing.expect(t, rt.stats.accessibility_reveal_wakes == 1 && rt.stats.accessibility_action_wakes == 0,
		"reveal wakes should be counted independently from performed actions")
}
