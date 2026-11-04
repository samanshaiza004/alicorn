package alicorn

import "core:testing"

Layout_Invalidation_Trace_Test_Nodes :: struct {
	root: Node_ID,
	middle: Node_ID,
	leaf: Node_ID,
}

layout_invalidation_trace_test_nodes :: proc(rt: ^Runtime, middle_axes: Layout_Axes, fit_height := false) -> Layout_Invalidation_Trace_Test_Nodes {
	root := new(Node, allocator=rt.persistent_allocator)
	root^ = Node{
		id=7901,
		kind=.Root,
		active=true,
		style=layout_style(width=200, height=200),
		layout_boundary_axes={.Width, .Height},
		layout_root_queued=true,
	}
	middle := new(Node, allocator=rt.persistent_allocator)
	middle^ = Node{
		id=7902,
		parent=root.id,
		kind=.Container,
		active=true,
		style=layout_style(width=100, height=100),
		layout_boundary_axes=middle_axes,
	}
	if fit_height { middle.style.height = LAYOUT_SIZE_FIT_CONTENT }
	leaf := new(Node, allocator=rt.persistent_allocator)
	leaf^ = Node{id=7903, parent=middle.id, kind=.Text, active=true}
	rt.nodes[root.id], rt.nodes[middle.id], rt.nodes[leaf.id] = root, middle, leaf
	return {root.id, middle.id, leaf.id}
}

@(test)
test_layout_invalidation_trace_reasons_materialize_lazily_and_exactly :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 160}, Runtime_Config{trace_capacity=32})
	defer destroy_runtime(&rt)
	nodes := layout_invalidation_trace_test_nodes(&rt, {.Width})

	expected_reasons := [5]string{
		"layout invalidation starts on axes Layout_Axes{Width, Height}",
		"layout invalidation propagated from node 7903 on axes Layout_Axes{Width, Height}",
		"layout boundary contains axes Layout_Axes{Width}; axes Layout_Axes{Height} escape to ancestors",
		"layout invalidation propagated from node 7903 on axes Layout_Axes{Height}",
		"layout boundary stops axes Layout_Axes{Height}; its requested outer dimensions are stable",
	}
	expected_nodes := [5]Node_ID{nodes.leaf, nodes.middle, nodes.middle, nodes.root, nodes.root}

	cause := cause_begin(&rt, .Keyboard, "layout invalidation trace test")
	first_sequence := rt.trace.sequence
	allocations_before := rt.allocation_stats.persistent_alloc_calls
	mark_layout_ancestors(&rt, nodes.leaf, {.Width, .Height})
	cause_end(&rt, cause)
	testing.expect(t, rt.allocation_stats.persistent_alloc_calls == allocations_before,
		"initial invalidation recording must not allocate owned diagnostic strings")
	unmaterialized := 0
	for event in rt.trace.events {
		if event.sequence <= first_sequence || event.kind != .Invalidation { continue }
		unmaterialized += 1
		testing.expect(t, len(event.reason) == 0,
			"detailed invalidation reasons must remain unformatted until requested")
	}
	testing.expect(t, unmaterialized == len(expected_reasons), "the boundary traversal should keep all five invalidation events")

	sequence_before_snapshot := rt.trace.sequence
	layout_roots_before_snapshot := len(rt.layout_roots)
	events := trace_snapshot(&rt)
	defer delete(events)
	testing.expect(t, rt.trace.sequence == sequence_before_snapshot && len(rt.layout_roots) == layout_roots_before_snapshot,
		"materializing trace reasons must not emit trace events or change retained layout work")
	found := 0
	for event in events {
		if event.sequence <= first_sequence || event.kind != .Invalidation { continue }
		if found < len(expected_reasons) {
			testing.expect(t, event.reason == expected_reasons[found], "snapshot should preserve the exact historical invalidation explanation")
			testing.expect(t, event.node == expected_nodes[found], "snapshot should preserve invalidation node ordering")
			testing.expect(t, event.cause_id == cause.cause.id && event.cause_kind == .Keyboard,
				"deferred invalidation reasons must retain their original cause metadata")
		}
		found += 1
	}
	testing.expect(t, found == len(expected_reasons), "snapshot should expose each invalidation event exactly once")

	allocations_before_repeat_snapshot := rt.allocation_stats.persistent_alloc_calls
	repeated_snapshot := trace_snapshot(&rt)
	defer delete(repeated_snapshot)
	testing.expect(t, rt.allocation_stats.persistent_alloc_calls == allocations_before_repeat_snapshot,
		"re-reading a materialized trace snapshot must reuse its cached reasons")
	for event_index in 0..<len(events) {
		testing.expect(t, repeated_snapshot[event_index].sequence == events[event_index].sequence &&
			repeated_snapshot[event_index].reason == events[event_index].reason,
			"repeated snapshots should keep the same event sequence and reason")
	}

	second_sequence := rt.trace.sequence
	allocations_before_repeat_invalidation := rt.allocation_stats.persistent_alloc_calls
	mark_layout_ancestors(&rt, nodes.leaf, {.Width, .Height})
	testing.expect(t, rt.allocation_stats.persistent_alloc_calls == allocations_before_repeat_invalidation,
		"repeated invalidation must not allocate diagnostic strings before inspection")
	new_unmaterialized := 0
	for event in rt.trace.events {
		if event.sequence <= second_sequence || event.kind != .Invalidation { continue }
		new_unmaterialized += 1
		testing.expect(t, len(event.reason) == 0, "repeated invalidation should defer its reasons too")
	}
	testing.expect(t, new_unmaterialized == len(expected_reasons), "repeated invalidation should record the same five events")

	all_events := trace_snapshot(&rt)
	defer delete(all_events)
	new_found := 0
	for event in all_events {
		if event.sequence <= second_sequence || event.kind != .Invalidation { continue }
		if new_found < len(expected_reasons) {
			testing.expect(t, event.reason == expected_reasons[new_found], "repeated invalidation should materialize the same exact explanations")
			testing.expect(t, event.node == expected_nodes[new_found], "repeated invalidation should preserve node ordering")
		}
		new_found += 1
	}
	testing.expect(t, new_found == len(expected_reasons), "repeated invalidation snapshot should expose all events")
}

@(test)
test_layout_invalidation_fit_content_trace_reason_is_deferred_exactly :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 160}, Runtime_Config{trace_capacity=16})
	defer destroy_runtime(&rt)
	nodes := layout_invalidation_trace_test_nodes(&rt, {.Height}, fit_height=true)
	allocations_before := rt.allocation_stats.persistent_alloc_calls
	mark_layout_ancestors(&rt, nodes.leaf, {.Height})
	testing.expect(t, rt.allocation_stats.persistent_alloc_calls == allocations_before,
		"FIT_CONTENT invalidation tracing must not allocate its formatted explanation eagerly")

	expected_reasons := [5]string{
		"layout invalidation starts on axes Layout_Axes{Height}",
		"layout invalidation propagated from node 7903 on axes Layout_Axes{Height}",
		"layout boundary cannot contain Height because that outer dimension uses FIT_CONTENT",
		"layout invalidation propagated from node 7903 on axes Layout_Axes{Height}",
		"layout boundary stops axes Layout_Axes{Height}; its requested outer dimensions are stable",
	}
	expected_nodes := [5]Node_ID{nodes.leaf, nodes.middle, nodes.middle, nodes.root, nodes.root}
	// The reason must describe the boundary when invalidation happened, even if
	// the node's style changes before anyone inspects the trace.
	rt.nodes[nodes.middle].style.height = 100
	events := trace_snapshot(&rt)
	defer delete(events)
	found := 0
	for event in events {
		if event.kind != .Invalidation { continue }
		if found < len(expected_reasons) {
			testing.expect(t, event.reason == expected_reasons[found], "FIT_CONTENT trace should preserve the exact rejected-axis explanation")
			testing.expect(t, event.node == expected_nodes[found], "FIT_CONTENT trace should preserve event node order")
		}
		found += 1
	}
	testing.expect(t, found == len(expected_reasons), "FIT_CONTENT traversal should expose all expected invalidation events")
}

@(test)
test_layout_invalidation_trace_ring_wrap_keeps_deferred_reasons :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 160}, Runtime_Config{trace_capacity=4})
	defer destroy_runtime(&rt)
	nodes := layout_invalidation_trace_test_nodes(&rt, {.Width})
	allocations_before := rt.allocation_stats.persistent_alloc_calls
	mark_layout_ancestors(&rt, nodes.leaf, {.Width, .Height})
	testing.expect(t, rt.trace.count == 4, "the trace ring should retain only its newest four events")
	testing.expect(t, rt.allocation_stats.persistent_alloc_calls == allocations_before,
		"overwritten deferred reasons should never be formatted or allocated")

	expected_reasons := [4]string{
		"layout invalidation propagated from node 7903 on axes Layout_Axes{Width, Height}",
		"layout boundary contains axes Layout_Axes{Width}; axes Layout_Axes{Height} escape to ancestors",
		"layout invalidation propagated from node 7903 on axes Layout_Axes{Height}",
		"layout boundary stops axes Layout_Axes{Height}; its requested outer dimensions are stable",
	}
	events := trace_snapshot(&rt)
	defer delete(events)
	testing.expect(t, len(events) == len(expected_reasons), "snapshot should expose the bounded trace window")
	for index in 0..<min(len(events), len(expected_reasons)) {
		testing.expect(t, events[index].reason == expected_reasons[index],
			"ring wrap should retain the full historical detail for every surviving structured event")
	}
}

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
