package alicorn

import "core:testing"

@(test)
test_text_field_interaction_is_a_normalized_public_snapshot :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 160})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "the initial frame should build"); return }
	container_begin(&ui, .Root, key=key_string("text-interaction-root"), style=layout_style())
	field := text_field(&ui, "a🙂bc", key=key_string("text-interaction-field"))
	container_end(&ui)
	end_frame(&ui)
	testing.expect(t, field != 0 && focus(&rt, field), "the text field should accept focus")
	_ = set_text_selection(&rt, field, 6, 1)
	state, ok := text_field_interaction(&rt, field)
	testing.expect(t, ok && state.focused && state.can_edit && state.has_selection,
		"the public query should report focused editable selection state")
	testing.expect(t, state.selection_start == 1 && state.selection_end == 6 && state.caret == 1,
		"selection offsets should be normalized while caret direction is preserved")
	testing.expect(t, process_text_editing(&rt, field, "preedit", 0, 0), "the field should accept transient composition")
	state, ok = text_field_interaction(&rt, field)
	testing.expect(t, ok && state.composition_active, "the public query should report active IME composition")
	state, ok = text_field_interaction(&rt, 0)
	testing.expect(t, !ok, "the query should reject an absent node ID")
}

@(test)
test_text_change_destroy_preserves_ownership_when_runtime_is_nil :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 160})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "the initial frame should build"); return }
	container_begin(&ui, .Root, key=key_string("text-change-destroy-root"), style=layout_style())
	field := text_field(&ui, "seed", key=key_string("text-change-destroy-field"))
	container_end(&ui)
	end_frame(&ui)
	change := process_text_input(&rt, field, "!")
	testing.expect(t, len(change.text) > 0, "committed text input should return an owned result")
	text_change_destroy(nil, &change)
	testing.expect(t, len(change.text) > 0 && change.node == field,
		"a nil Runtime must leave an owned text result intact so its owner can still release it")
	text_change_destroy(&rt, &change)
	testing.expect(t, len(change.text) == 0 && change.node == 0 && !change.changed,
		"a valid Runtime should release and clear the owned result")
}

@(test)
test_node_identity_key_returns_local_string_key_inside_scope :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 160})
	defer destroy_runtime(&rt)

	ui, should_build := begin_frame(&rt)
	if !should_build {
		testing.expect(t, false, "the initial frame should describe the test tree")
		return
	}
	container_begin(&ui, .Root, label="query-test-root", key=key_string("root"), style=layout_style())
	if !key_scope_begin(&ui, key_string("parent-scope")) {
		testing.expect(t, false, "the distinct parent identity scope should open")
		return
	}
	_ = button(&ui, "Workspace row", key=key_string("src/nested/first.txt"))
	key_scope_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	row: Node_ID
	for id in rt.order {
		if node, found := rt.nodes[id]; found && node.active && node.kind == .Button && node.label == "Workspace row" {
			row = id
			break
		}
	}
	testing.expect(t, row != 0, "the described workspace row should be retained")
	if row == 0 { return }

	key, key_found := node_identity_key(&rt, row)
	key_path := ""
	if value, is_string := key.(string); is_string {
		key_path = value
	}
	testing.expect(t, key_found && key_path == "src/nested/first.txt",
		"the public identity query should return a string-keyed node's own key, not its parent scope")
	info, info_found := node_info(&rt, row)
	info_path := ""
	if value, is_string := info.key.(string); is_string {
		info_path = value
	}
	testing.expect(t, info_found && info_path == "src/nested/first.txt",
		"node_info should expose the same local string key as node_identity_key")
	resolved, resolved_found := node_by_key(&rt, key_string("src/nested/first.txt"), .Button)
	testing.expect(t, resolved_found && resolved == row,
		"node_by_key should resolve a string-keyed node independently of its parent scope")
}

public_query_test_region :: proc(t: ^testing.T, rt: ^Runtime, key: string, revision: u64, legacy_container := false) -> (id: Node_ID, reused: bool) {
	ui, build := begin_frame(rt)
	if !build { testing.expect(t, false, "the region query fixture must describe a frame"); return }
	container_begin(&ui, .Root, key=key_string("region-query-root"), style=layout_style())
	if !key_scope_begin(&ui, key_string("region-query-parent-scope")) {
		testing.expect(t, false, "the containing identity scope must open")
		return
	}
	source := site("tests/public-region-query.odin", 10, 1, "region-query")
	if legacy_container {
		// The public legacy string-key API defines the region's existing ID
		// encoding at this same source, scope and explicit key.
		id = container_begin_ex(&ui, .Container, source, key=key, explicit_key=true)
		container_end(&ui)
	} else {
		id, reused = region_begin(&ui, key, revision, source)
		region_end(&ui, id, reused, 0)
	}
	key_scope_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_region_string_key_is_queryable_with_legacy_identity :: proc(t: ^testing.T) {
	// Empty strings are explicit string keys too, not unkeyed declarations.
	keys := []string{"queryable-region", ""}
	for key in keys {
		legacy := new_runtime(Rect{0, 0, 240, 120})
		expected_id, _ := public_query_test_region(t, &legacy, key, 1, legacy_container=true)
		destroy_runtime(&legacy)
		rt := new_runtime(Rect{0, 0, 240, 120})
		for frame in 0..<3 {
			revision := u64(1)
			if frame == 1 { invalidate_root(&rt, "query a reused region") }
			if frame == 2 {
				revision = 2
				invalidate_region(&rt, key, revision, "query an invalidated region")
			}
			id, reused := public_query_test_region(t, &rt, key, revision)
			testing.expect(t, id != 0 && id == expected_id,
				"region IDs must retain the legacy explicit-string encoding across reuse and invalidation")
			testing.expect(t, reused == (frame == 1), "the fixture must exercise initial, reused and invalidated descriptions")
			resolved, found := node_by_key(&rt, key_string(key), .Container)
			testing.expect(t, found && resolved == id, "node_by_key must resolve the region's explicit string key")
			identity_key, identity_found := node_identity_key(&rt, id)
			identity_string, is_string := identity_key.(string)
			testing.expect(t, identity_found && is_string && identity_string == key,
				"node_identity_key must return the region's local key rather than its containing scope")
			info, info_found := node_info(&rt, id)
			info_string, info_is_string := info.key.(string)
			testing.expect(t, info_found && info.active && info.kind == .Container && info_is_string && info_string == key,
				"node_info must expose the live region's explicit string key")
		}
		destroy_runtime(&rt)
	}
}
