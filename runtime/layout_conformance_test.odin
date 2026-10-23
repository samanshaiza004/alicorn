package alicorn

import "core:fmt"
import "core:strings"
import "core:testing"

// Test both isolated axes and their union; underclaiming a boundary is legal.
// FIT_CONTENT width is deliberately absent: v0.2 supports content height only.
@(test)
test_layout_boundary_axis_conformance_matrix :: proc(t: ^testing.T) {
	Case :: struct { axes, stable: Layout_Axes, content_height: bool }
	cases := []Case{
		{{.Width, .Height}, {.Width, .Height}, false},
		{{.Width}, {.Width}, false},
		{{.Height}, {.Height}, false},
		{{.Width}, {.Width}, true},
		{{.Width, .Height}, {.Width}, true},
	}
	changes := []Layout_Axes{{.Width}, {.Height}, {.Width, .Height}}
	for entry in cases {
		for change in changes {
			rt := new_runtime(Rect{0, 0, 300, 300}, Runtime_Config{trace_capacity=32})
			root := new(Node, allocator=rt.persistent_allocator)
			root^ = Node{id=9001, kind=.Root, active=true, style=layout_style(width=300, height=300), layout_boundary_axes={.Width, .Height}}
			boundary := new(Node, allocator=rt.persistent_allocator)
			boundary^ = Node{id=9002, parent=root.id, kind=.Container, active=true, style=layout_style(width=160, height=120), layout_boundary_axes=entry.axes}
			if entry.content_height { boundary.style.height = LAYOUT_SIZE_FIT_CONTENT }
			child := new(Node, allocator=rt.persistent_allocator)
			child^ = Node{id=9003, parent=boundary.id, kind=.Text, active=true}
			rt.nodes[root.id], rt.nodes[boundary.id], rt.nodes[child.id] = root, boundary, child
			mark_layout_ancestors(&rt, child.id, change)
			escaped := layout_axes_difference(change, entry.stable)
			label := fmt.tprintf("axes=%v content-height=%t changed=%v", entry.axes, entry.content_height, change)
			testing.expect(t, dirty_has(child.dirty, .Layout) && dirty_has(boundary.dirty, .Layout), label)
			testing.expect(t, dirty_has(root.dirty, .Layout) == (escaped != {}), label)
			testing.expect(t, len(rt.layout_roots) == 1, "one bounded layout root must own the transaction")
			if len(rt.layout_roots) == 1 {
				expected := boundary.id if escaped == {} else root.id
				testing.expect(t, rt.layout_roots[0] == expected, label)
			}
			destroy_runtime(&rt)
		}
	}
}

Layout_Conformance_Nodes :: struct { outer, content, boundary, text, sibling, peer: Node_ID }

layout_conformance_describe :: proc(rt: ^Runtime, width, scale: f32, value: string) -> Layout_Conformance_Nodes {
	invalidate_root(rt, "layout conformance inputs changed")
	ui, build := begin_frame(rt)
	if !build { return {} }
	nodes: Layout_Conformance_Nodes
	container_begin(&ui, .Root, key=key_string("conformance-root"), style=layout_style(.Row, grow=1))
	nodes.outer = container_begin(&ui, .Container, key=key_string("fixed-ancestor"), style=layout_style(.Column, width=440, height=500), layout_boundary=true)
	nodes.content = container_begin(&ui, .Container, key=key_string("content-parent"), style=layout_style(.Column, width=width, height=LAYOUT_SIZE_FIT_CONTENT, gap=7))
	nodes.boundary = container_begin(&ui, .Container, key=key_string("width-boundary"), style=layout_style(.Column, width=width, height=LAYOUT_SIZE_FIT_CONTENT), layout_boundary_axes={.Width})
	scope := style_environment_push(&ui, Style_Environment{text_scale=scale})
	nodes.text = text(&ui, value, key=key_string("wrapped-text"), style=layout_style(width=-1), text_style=Text_Style{overflow=.Wrap})
	style_environment_pop(&ui, scope)
	container_end(&ui)
	nodes.sibling = text(&ui, "Sibling after wrapped content", key=key_string("following-sibling"), style=layout_style(width=120, height=24))
	container_end(&ui)
	container_end(&ui)
	nodes.peer = text(&ui, "Unaffected panel", key=key_string("unaffected-peer"), style=layout_style(width=200, height=100))
	container_end(&ui)
	end_frame(&ui)
	return nodes
}

LAYOUT_CONFORMANCE_PARAGRAPH :: "The width boundary keeps its assigned width while wrapped text changes height. The surrounding content parent and following sibling must use the newly measured height."

layout_conformance_trace :: proc(rt: ^Runtime, after: u64, kind: Trace_Kind, node: Node_ID, fragment: string) -> bool {
	for event in rt.trace.events {
		if event.sequence > after && event.kind == kind && event.node == node && strings.contains(event.reason, fragment) { return true }
	}
	return false
}

@(test)
test_width_boundary_wrapped_reflow_matches_fresh_runtime_and_stays_local :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600}, Runtime_Config{trace_capacity=512})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, LAYOUT_MEASURE_TEST_FONT), "conformance font must load")
	_ = set_presentation_scale(&rt, 1.25, 1.25)
	nodes := layout_conformance_describe(&rt, 320, 1, LAYOUT_CONFORMANCE_PARAGRAPH)
	Mutation :: struct { width, scale: f32, value: string }
	mutations := []Mutation{
		{320, 1.5, LAYOUT_CONFORMANCE_PARAGRAPH},
		{180, 1.5, LAYOUT_CONFORMANCE_PARAGRAPH},
		{180, 1, "Short text"},
		{320, 1, LAYOUT_CONFORMANCE_PARAGRAPH},
		{240, 1.25, LAYOUT_CONFORMANCE_PARAGRAPH},
	}
	for mutation, index in mutations {
		peer_measure := rt.measure_states[nodes.peer]
		rt.layout_visit_probe[nodes.peer] = 0
		trace_start := rt.trace.sequence
		previous_height := rt.nodes[nodes.boundary].bounds.h
		previous_y := rt.nodes[nodes.sibling].bounds.y
		next := layout_conformance_describe(&rt, mutation.width, mutation.scale, mutation.value)
		testing.expect(t, next == nodes, "all keyed identities survive reflow and resize")
		if index == 0 {
			testing.expect(t, rt.nodes[nodes.boundary].bounds.h > previous_height && rt.nodes[nodes.sibling].bounds.y > previous_y,
				"height must escape a width-only boundary and move the following sibling")
			testing.expect(t, rt.layout_visit_probe[nodes.peer] == 0 && rt.measure_states[nodes.peer].cache_key == peer_measure.cache_key,
				"the fixed ancestor must contain reflow without visiting or remeasuring the unrelated peer")
			testing.expect(t, layout_conformance_trace(&rt, trace_start, .Measure, nodes.text, "metrics and typography dependency generations changed"), "trace must identify the changed typography input")
			testing.expect(t, layout_conformance_trace(&rt, trace_start, .Measure, nodes.text, fmt.tprintf("measured output changed on axes %v", Layout_Axes{.Height})), "trace must identify the measured height change")
			testing.expect(t, layout_conformance_trace(&rt, trace_start, .Measure, nodes.boundary, "parent size depends on child"), "trace must name the child-to-parent output dependency")
			testing.expect(t, layout_conformance_trace(&rt, trace_start, .Measure, nodes.content, "parent size depends on child") &&
				layout_conformance_trace(&rt, trace_start, .Invalidation, nodes.content, fmt.tprintf("on axes %v", Layout_Axes{.Height})),
				"trace must follow the height dependency and invalidation through the content parent")
			testing.expect(t, layout_conformance_trace(&rt, trace_start, .Invalidation, nodes.outer, fmt.tprintf("layout boundary stops axes %v", Layout_Axes{.Height})), "trace must identify the fixed ancestor that contains the height change")
		}
		testing.expect(t, .Width_To_Height in rt.measure_states[nodes.text].result.input_axis_dependencies &&
			.Width_To_Height in rt.measure_states[nodes.boundary].result.input_axis_dependencies,
			"the wrapped leaf and content boundary must retain their cross-axis width-to-height dependency")
		fresh := new_runtime(Rect{0, 0, 800, 600})
		testing.expect(t, text_engine_load_font(&fresh.text_engine, LAYOUT_MEASURE_TEST_FONT), "fresh comparison font must load")
		_ = set_presentation_scale(&fresh, 1.25, 1.25)
		clean_nodes := layout_conformance_describe(&fresh, mutation.width, mutation.scale, mutation.value)
		testing.expect(t, clean_nodes == nodes && layout_allocation_test_geometry_matches(&rt, &fresh),
			fmt.tprintf("mutation %d must have identical targets, snapped bounds, clips, measure results and exact constraints to a fresh Runtime", index))
		destroy_runtime(&fresh)
	}
	before := rt.stats
	_, rebuild := begin_frame(&rt)
	testing.expect(t, !rebuild && rt.stats.measure_requests == before.measure_requests && rt.stats.layout_nodes_visited == before.layout_nodes_visited,
		"settled reflow must return to zero measurement/layout work")
}

@(test)
test_measure_constraint_provenance_names_changed_axes_and_minima :: proc(t: ^testing.T) {
	old := Measure_Cache_Key{valid=true, constraints=Layout_Constraints{
		width=layout_axis_constraint_normalize(10, 100), height=layout_axis_constraint_normalize(20, 200),
	}}
	next := old
	next.constraints.height = layout_axis_constraint_normalize(30, 200)
	reason := measure_cache_reason(old, next)
	testing.expect(t, strings.contains(reason, "height constraint") && !strings.contains(reason, "width constraint") && strings.contains(reason, "30.000"),
		"a height-minimum-only cache miss must not claim the unchanged width caused remeasurement")
	next.constraints.width = layout_axis_constraint_normalize(15, 100)
	reason = measure_cache_reason(old, next)
	testing.expect(t, strings.contains(reason, "height constraint") && strings.contains(reason, "width constraint") && strings.contains(reason, "15.000"),
		"a two-axis miss must explain both changed exact constraints, including minima")
}
