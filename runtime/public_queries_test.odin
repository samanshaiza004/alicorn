package alicorn

import "core:testing"

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
