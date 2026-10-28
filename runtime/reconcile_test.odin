package alicorn

import "core:testing"

@(test)
test_mark_dirty_preserves_reason_when_description_is_reused :: proc(t: ^testing.T) {
	allocator := context.allocator
	node := Node{last_reason=owned("description changed", allocator)}
	defer delete(node.last_reason, allocator)

	mark_dirty(&node, "description reused", false, false, false, false, allocator)
	testing.expect(t, node.last_reason == "description changed",
		"reusing a clean description must preserve the last meaningful work reason")
	testing.expect(t, !dirty_has(node.dirty, .Paint),
		"reusing a clean description must not make the node paint-dirty")

	mark_dirty(&node, "new description change", true, false, true, false, allocator)
	testing.expect(t, node.last_reason == "new description change",
		"a later description change must replace the preserved reason")
}
