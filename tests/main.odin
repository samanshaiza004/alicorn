package main

import "core:fmt"
import "core:os"
import alicorn "../runtime"
import runa "../third_party/Runa"

S_ROOT :: alicorn.Source_Site{"tests/render.odin", 1, 1, "root"}
S_ROW :: alicorn.Source_Site{"tests/render.odin", 10, 1, "track_row"}
S_BUTTON :: alicorn.Source_Site{"tests/render.odin", 11, 5, "mute_button"}
S_EXTRA :: alicorn.Source_Site{"tests/render.odin", 20, 1, "conditional_sibling"}
S_WRAP :: alicorn.Source_Site{"tests/render.odin", 30, 1, "conditional_wrapper"}
S_REGION :: alicorn.Source_Site{"tests/render.odin", 40, 1, "region"}
S_VLIST :: alicorn.Source_Site{"tests/render.odin", 50, 1, "virtual_list"}
S_VROW :: alicorn.Source_Site{"tests/render.odin", 51, 1, "virtual_row"}
S_LAYOUT_A :: alicorn.Source_Site{"tests/layout.odin", 1, 1, "fixed"}
S_LAYOUT_B :: alicorn.Source_Site{"tests/layout.odin", 2, 1, "grow"}
S_REGION_STRESS :: alicorn.Source_Site{"tests/region_stress.odin", 1, 1, "region"}
S_REGION_STRESS_SCOPE :: alicorn.Source_Site{"tests/region_stress.odin", 2, 1, "scope"}
S_REGION_STRESS_NODE :: alicorn.Source_Site{"tests/region_stress.odin", 3, 1, "node"}
S_REGION_STRESS_SIBLING :: alicorn.Source_Site{"tests/region_stress.odin", 4, 1, "sibling"}
S_REGION_STRESS_NESTED :: alicorn.Source_Site{"tests/region_stress.odin", 5, 1, "nested"}

virtual_keys: []string

Test_State :: struct {
	failures: int,
}

expect :: proc(state: ^Test_State, condition: bool, message: string) {
	if !condition {
		state.failures += 1
		fmt.println("FAIL:", message)
	}
}

render_keyed :: proc(rt: ^alicorn.Runtime, keys: []string, values: []int, extra, wrapper: bool) -> map[string]alicorn.Node_ID {
	ids := make(map[string]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "test structural render")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="root", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	if extra {
		alicorn.text(&ui, "extra", S_EXTRA)
	}
	if wrapper {
		alicorn.transparent_container_begin(&ui, .Container, S_WRAP, label="wrapper")
	}
	for i := 0; i < len(keys); i += 1 {
		if alicorn.key_scope_begin(&ui, keys[i], S_ROW) {
			id, _ := alicorn.button(&ui, keys[i], S_BUTTON, style=alicorn.Layout_Style{.Column, -1, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}, paint_value=u64(values[i] if i < len(values) else 0))
			ids[keys[i]] = id
			alicorn.key_scope_end(&ui)
		}
	}
	if wrapper {
		alicorn.transparent_container_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

render_numeric_keyed :: proc(rt: ^alicorn.Runtime, keys: []u64, values: []int) -> map[u64]alicorn.Node_ID {
	ids := make(map[u64]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "test numeric keyed render")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="numeric-root")
	for key, i in keys {
		if alicorn.key_scope_u64(&ui, key, S_ROW) {
			id, _ := alicorn.button(&ui, fmt.tprintf("n%d", key), S_BUTTON, style=alicorn.Layout_Style{.Column, -1, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}, paint_value=u64(values[i] if i < len(values) else 0))
			ids[key] = id
			alicorn.key_scope_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

render_region :: proc(rt: ^alicorn.Runtime, revision: u64, body_counter: ^int) {
	alicorn.invalidate_root(rt, "test region render")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="root")
	id, reused := alicorn.region_begin(&ui, "static", revision, S_REGION)
	if id != 0 && !reused {
		start := len(rt.pending)
		body_counter^ += 1
		alicorn.text(&ui, "cached body", alicorn.site("tests/render.odin", 41, 1, "cached_body"))
		alicorn.region_end(&ui, id, false, start)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_stress_region :: proc(rt: ^alicorn.Runtime, revision: u64, include_region: bool, body_counter: ^int) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test retained subtree stress")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="stress-root")
	sibling, _ := alicorn.button(&ui, "fallback", S_REGION_STRESS_SIBLING, style=alicorn.Layout_Style{.Column, 160, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	if include_region && alicorn.key_scope_begin(&ui, "retained", S_REGION_STRESS_SCOPE) {
		id, reused := alicorn.region_begin(&ui, "body", revision, S_REGION_STRESS)
		if id != 0 && !reused {
			body_counter^ += 1
			start := len(rt.pending)
			if alicorn.key_scope_u64(&ui, 0, S_REGION_STRESS_NODE) {
				alicorn.button(&ui, "focused descendant", S_REGION_STRESS_NODE, style=alicorn.Layout_Style{.Column, 180, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
				alicorn.key_scope_end(&ui)
			}
			for i := 1; i < 256; i += 1 {
				if alicorn.key_scope_u64(&ui, u64(i), S_REGION_STRESS_NODE) {
					alicorn.text(&ui, "retained descendant", S_REGION_STRESS_NODE)
					alicorn.key_scope_end(&ui)
				}
			}
			alicorn.region_end(&ui, id, false, start)
		}
		alicorn.key_scope_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return sibling
}

render_region_collection :: proc(rt: ^alicorn.Runtime, order: []u64, enabled: []bool, revisions: []u64, nested: bool, body_counter: ^int) -> map[u64]alicorn.Node_ID {
	roots := make(map[u64]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "test region collection")
	ui, build := alicorn.begin_frame(rt)
	if !build { return roots }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="region-collection")
	for key in order {
		if key >= u64(len(enabled)) || !enabled[key] { continue }
		if !alicorn.key_scope_u64(&ui, key, S_REGION_STRESS_SCOPE) { continue }
		id, reused := alicorn.region_begin(&ui, "item", revisions[key], S_REGION_STRESS)
		roots[key] = id
		if id != 0 && !reused {
			body_counter^ += 1
			start := len(rt.pending)
			if alicorn.key_scope_u64(&ui, 0, S_REGION_STRESS_NODE) {
				alicorn.button(&ui, "region-state", S_REGION_STRESS_NODE, style=alicorn.Layout_Style{.Column, 120, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}, paint_value=key)
				alicorn.key_scope_end(&ui)
			}
			if nested && key == 0 {
				nested_id, nested_reused := alicorn.region_begin(&ui, "nested", revisions[key], S_REGION_STRESS_NESTED)
				if nested_id != 0 && !nested_reused {
					nested_start := len(rt.pending)
					alicorn.text(&ui, "nested-state", S_REGION_STRESS_NODE)
					alicorn.region_end(&ui, nested_id, false, nested_start)
				}
			}
			alicorn.region_end(&ui, id, false, start)
		}
		alicorn.key_scope_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return roots
}

virtual_row :: proc(ui: ^alicorn.UI, index: int) {
	alicorn.text(ui, fmt.tprintf("row %d", index), S_VROW)
}

virtual_item_key :: proc(index: int) -> string {
	return fmt.tprintf("item-%d", index)
}

virtual_data_key :: proc(index: int) -> string {
	return virtual_keys[index]
}

virtual_data_row :: proc(ui: ^alicorn.UI, index: int) {
	alicorn.text(ui, virtual_keys[index], S_VROW)
}

render_virtual :: proc(rt: ^alicorn.Runtime, scroll: f32) {
	alicorn.invalidate_root(rt, "test virtual scroll")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="root")
	alicorn.virtual_list(&ui, 1_000_000, scroll, 200, 20, S_VLIST, virtual_item_key, virtual_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_virtual_data :: proc(rt: ^alicorn.Runtime, keys: []string, scroll: f32) -> map[string]alicorn.Node_ID {
	virtual_keys = keys
	alicorn.invalidate_root(rt, "test logical virtual data")
	ui, build := alicorn.begin_frame(rt)
	ids := make(map[string]alicorn.Node_ID)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="virtual-data-root")
	alicorn.virtual_list(&ui, len(keys), scroll, 200, 20, S_VLIST, virtual_data_key, virtual_data_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Text && node.identity_key != "" {
			ids[node.identity_key] = id
		}
	}
	return ids
}

render_single_button :: proc(rt: ^alicorn.Runtime) -> (id: alicorn.Node_ID, clicked: bool) {
	alicorn.invalidate_root(rt, "test button frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="button-root")
	id, clicked = alicorn.button(&ui, "button", S_BUTTON, style=alicorn.Layout_Style{.Column, 100, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

render_text_field :: proc(rt: ^alicorn.Runtime, value: string) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test text field frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="text-field-root")
	id := alicorn.text_field(&ui, value, alicorn.site("tests/edit.odin", 2, 1, "query"))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return id
}

render_focus_ancestor :: proc(rt: ^alicorn.Runtime, include_child: bool) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test focus ancestor")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="focus-root")
	parent := alicorn.container_begin(&ui, .Container, S_WRAP, label="focus-parent", focusable=true, style=alicorn.Layout_Style{.Column, 120, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	if include_child {
		child, _ := alicorn.button(&ui, "child", S_BUTTON, style=alicorn.Layout_Style{.Column, 100, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
		parent = child
	}
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return parent
}

render_clipped :: proc(rt: ^alicorn.Runtime) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test clipping")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="clip-root")
	alicorn.container_begin(&ui, .Container, S_WRAP, label="clip-parent", style=alicorn.Layout_Style{.Column, 50, 50, 0, -1, 0, -1, 0, 0, 0, .Stretch, true})
	child, _ := alicorn.button(&ui, "oversized", S_BUTTON, style=alicorn.Layout_Style{.Column, 100, 100, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return child
}

ergonomic_row :: proc(ui: ^alicorn.UI, label: string) -> alicorn.Node_ID {
	id, _ := alicorn.button(ui, label, key=label, explicit_key=true, style=alicorn.Layout_Style{.Column, 100, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	return id
}

render_ergonomic :: proc(rt: ^alicorn.Runtime, keys: []string) -> map[string]alicorn.Node_ID {
	ids := make(map[string]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "test ergonomic API")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, label="ergonomic-root")
	for key in keys {
		if alicorn.component_begin(&ui, key) {
			ids[key] = ergonomic_row(&ui, key)
			alicorn.component_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

test_identity_and_ambiguity :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 500})
	keys := []string{"a", "b", "c", "d"}
	values := []int{1, 2, 3, 4}
	ids := render_keyed(&rt, keys, values, false, false)
	for key, id in ids {
		if node, ok := rt.nodes[id]; ok { node.local_counter = len(key) * 10 }
	}
	keys = []string{"d", "b", "a", "c"}
	ids = render_keyed(&rt, keys, values, true, false)
	for key, id in ids {
		expect(state, rt.nodes[id].local_counter == len(key)*10, fmt.tprintf("retained counter moved for %s", key))
	}
	keys = []string{"d", "a", "c"}
	render_keyed(&rt, keys, values, false, true)
	for key, id in render_keyed(&rt, keys, values, false, true) {
		expect(state, rt.nodes[id].local_counter == len(key)*10, fmt.tprintf("transparent wrapper moved state for %s", key))
	}
	// An unkeyed repeated source is a hard diagnostic, not positional magic.
	alicorn.invalidate_root(&rt, "test ambiguity")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, S_ROOT)
		alicorn.button(&ui, "one", S_BUTTON)
		alicorn.button(&ui, "two", S_BUTTON)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, rt.hard_error, "unkeyed repeated siblings must be a hard diagnostic")
	alicorn.destroy_runtime(&rt)
	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 100, 100})
	alicorn.invalidate_root(&rt, "duplicate key test")
	ui, build = alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, S_ROOT)
		if alicorn.key_scope_begin(&ui, "same", S_ROW) { alicorn.text(&ui, "one", S_BUTTON); alicorn.key_scope_end(&ui) }
		if alicorn.key_scope_begin(&ui, "same", S_ROW) { alicorn.text(&ui, "two", S_BUTTON); alicorn.key_scope_end(&ui) }
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, rt.hard_error, "duplicate explicit keys must be a hard diagnostic")
	alicorn.destroy_runtime(&rt)
	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 800, 500})
	numeric_keys := []u64{11, 22, 33, 44}
	numeric_values := []int{1, 2, 3, 4}
	numeric_ids := render_numeric_keyed(&rt, numeric_keys, numeric_values)
	for key, id in numeric_ids { rt.nodes[id].local_counter = int(key) }
	numeric_keys = []u64{44, 22, 11, 33}
	numeric_ids = render_numeric_keyed(&rt, numeric_keys, numeric_values)
	for key, id in numeric_ids {
		expect(state, rt.nodes[id].local_counter == int(key), fmt.tprintf("typed key retained counter moved for %d", key))
		expect(state, rt.nodes[id].identity_key_numeric && rt.nodes[id].identity_key_u64 == key, fmt.tprintf("typed key retained inspector identity for %d", key))
	}
	alicorn.destroy_runtime(&rt)
	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 100, 100})
	alicorn.invalidate_root(&rt, "duplicate numeric key test")
	ui, build = alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, S_ROOT)
		if alicorn.key_scope_u64(&ui, 7, S_ROW) { alicorn.text(&ui, "one", S_BUTTON); alicorn.key_scope_end(&ui) }
		if alicorn.key_scope_u64(&ui, 7, S_ROW) { alicorn.text(&ui, "two", S_BUTTON); alicorn.key_scope_end(&ui) }
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, rt.hard_error, "duplicate numeric keys must be a hard diagnostic")
	alicorn.destroy_runtime(&rt)
}

test_property_sequences :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 480})
	keys := make([dynamic]string, 0)
	for i := 0; i < 8; i += 1 { append(&keys, fmt.aprintf("k%d", i)) }
	values := make([]int, 8)
	for i := 0; i < len(values); i += 1 { values[i] = i }
	expected := make(map[string]int)
	for key in keys { expected[key] = 100 + len(expected) }
	ids := render_keyed(&rt, keys[:], values, false, false)
	for key, id in ids { rt.nodes[id].local_counter = expected[key] }
	seed: u64 = 0xA11C0DE
	for step := 0; step < 2000; step += 1 {
		seed = seed*6364136223846793005 + 1442695040888963407
		op := int(seed % 5)
		if op == 0 || len(keys) < 2 {
			key := fmt.aprintf("new%d", step)
			at := int(seed % u64(len(keys)+1))
			append(&keys, "")
			for j := len(keys)-1; j > at; j -= 1 { keys[j] = keys[j-1] }
			keys[at] = key
			// New retained nodes begin with a runtime default state. The important
			// invariant is that this default never comes from another logical key.
			expected[key] = 0
		} else if op == 1 && len(keys) > 1 {
			at := int(seed % u64(len(keys)))
			delete_key(&expected, keys[at])
			for j := at; j < len(keys)-1; j += 1 { keys[j] = keys[j+1] }
			pop(&keys)
		} else if op == 2 {
			at := int(seed % u64(len(keys)))
			key := keys[at]
			for j := at; j < len(keys)-1; j += 1 { keys[j] = keys[j+1] }
			pop(&keys)
			to := int((seed >> 8) % u64(len(keys)+1))
			append(&keys, "")
			for j := len(keys)-1; j > to; j -= 1 { keys[j] = keys[j-1] }
			keys[to] = key
		} else if op == 3 {
			for i, j := 0, len(keys)-1; i < j; i, j = i+1, j-1 { keys[i], keys[j] = keys[j], keys[i] }
		} else {
			for i := len(keys)-1; i >= 0; i -= 1 {
				if (seed+u64(i)) % 3 == 0 && len(keys) > 1 {
					delete_key(&expected, keys[i])
					for j := i; j < len(keys)-1; j += 1 { keys[j] = keys[j+1] }
					pop(&keys)
				}
			}
		}
		values = make([]int, len(keys))
		ids = render_keyed(&rt, keys[:], values, step%7 == 0, step%11 == 0)
		for key, id in ids {
			if _, exists := expected[key]; !exists { expected[key] = 2000 + step }
			expect(state, rt.nodes[id].local_counter == expected[key], fmt.tprintf("property state transfer at step %d key %s", step, key))
		}
	}
	expect(state, len(rt.nodes) <= len(keys)+2, "retained nodes should track live keyed structure")
	alicorn.destroy_runtime(&rt)
}

test_regions_and_stages :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 480})
	body_calls: int = 0
	rt.invalidated = true
	render_region(&rt, 1, &body_calls)
	render_region(&rt, 1, &body_calls)
	expect(state, body_calls == 1, "unchanged retained region body must be skipped")
	expect(state, rt.stats.regions_skipped >= 1, "inspector counters must record skipped regions")
	render_region(&rt, 2, &body_calls)
	expect(state, body_calls == 2, "changed region revision must reevaluate the region body")
	before_paint := rt.stats.paint_updates
	render_keyed(&rt, []string{"a", "b", "c"}, []int{0, 7, 0}, false, false)
	after_paint := rt.stats.paint_updates
	expect(state, after_paint-before_paint == 3, "first keyed tree creates three paints")
	rt.invalidated = true
	render_keyed(&rt, []string{"a", "b", "c"}, []int{0, 8, 0}, false, false)
	expect(state, rt.stats.paint_updates-after_paint == 1, "one paint input should repaint one keyed node")
	adjacency_before := rt.stats.adjacency_rebuilds
	render_keyed(&rt, []string{"a", "b", "c"}, []int{0, 8, 0}, false, false)
	expect(state, rt.stats.adjacency_rebuilds == adjacency_before, "unchanged structure must reuse retained adjacency")
	report := alicorn.inspect(&rt)
	expect(state, len(report) > 100 && len(alicorn.trace_snapshot(&rt)) > 0, "inspector and bounded trace must expose structural work")
	alicorn.destroy_runtime(&rt)
}

test_retained_subtree_reuse :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 500})
	body_calls: int = 0
	sibling := render_stress_region(&rt, 1, true, &body_calls)
	expect(state, body_calls == 1, "stress region body executes initially")
	region_nodes := len(rt.nodes)
	child: alicorn.Node_ID = 0
	for id, node in rt.nodes {
		if node.kind == .Button && node.label == "focused descendant" { child = id; break }
	}
	expect(state, child != 0, "stress region retains a focusable descendant")
	if child != 0 {
		rt.nodes[child].local_counter = 4242
		expect(state, alicorn.focus(&rt, child), "stress descendant can own focus")
	}
	before := rt.stats
	render_stress_region(&rt, 1, true, &body_calls)
	expect(state, body_calls == 1, "reused stress region body is not reevaluated")
	expect(state, len(rt.nodes) == region_nodes, "reused stress subtree remains retained")
	expect(state, rt.stats.reconcile_nodes_visited-before.reconcile_nodes_visited <= 3, "subtree reuse does not visit cached descendants")
	expect(state, rt.stats.retained_subtrees_reused-before.retained_subtrees_reused == 1, "reuse marker is observable")
	if child != 0 {
		expect(state, rt.nodes[child].local_counter == 4242, "reused subtree preserves descendant state")
		expect(state, rt.focused == child, "reused subtree preserves focus")
	}
	rt.viewport.w = 900
	before = rt.stats
	render_stress_region(&rt, 1, true, &body_calls)
	expect(state, body_calls == 1, "constraint-only wake does not reevaluate reused description")
	expect(state, rt.stats.reconcile_nodes_visited-before.reconcile_nodes_visited <= 3, "constraint-only wake remains description-local")
	expect(state, rt.stats.layout_nodes_visited-before.layout_nodes_visited > 0, "constraint change can lay out retained descendants")
	before = rt.stats
	new_sibling := render_stress_region(&rt, 1, false, &body_calls)
	expect(state, body_calls == 1, "hidden region does not execute its body")
	expect(state, rt.stats.nodes_retired-before.nodes_retired >= 257, "removing a region retires its full retained subtree")
	expect(state, len(rt.nodes) == 2, "removed region descendants are no longer retained")
	expect(state, new_sibling == sibling && rt.focused == sibling, "focus falls back to surviving sibling deterministically")
	_, child_present := rt.nodes[child]
	expect(state, child == 0 || !child_present, "removed subtree child is unreachable")
	alicorn.destroy_runtime(&rt)
}

test_region_identity_sequences :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 500})
	order := make([dynamic]u64, 0)
	enabled := make([dynamic]bool, 0)
	revisions := make([dynamic]u64, 0)
	for key := 0; key < 6; key += 1 {
		append(&order, u64(key))
		append(&enabled, true)
		append(&revisions, 0)
	}
	nested := true
	body_calls: int = 0
	roots := render_region_collection(&rt, order[:], enabled[:], revisions[:], nested, &body_calls)
	expected := make(map[u64]int)
	for key, id in roots { expected[key] = int(key)+1000; rt.nodes[id].local_counter = expected[key] }
	seed: u64 = 0xA11C0DE
	for step := 0; step < 500; step += 1 {
		seed = seed*6364136223846793005 + 1442695040888963407
		op := int(seed % 6)
		if op == 0 {
			at := int(seed % u64(len(order)))
			to := int((seed >> 8) % u64(len(order)))
			key := order[at]
			for i := at; i < len(order)-1; i += 1 { order[i] = order[i+1] }
			pop(&order)
			append(&order, 0)
			for i := len(order)-1; i > to; i -= 1 { order[i] = order[i-1] }
			order[to] = key
		} else if op == 1 {
			key := u64(seed % u64(len(enabled)))
			enabled[key] = !enabled[key]
			if enabled[key] { expected[key] = 0 } else { delete_key(&expected, key) }
		} else if op == 2 {
			key := u64(seed % u64(len(revisions)))
			revisions[key] += 1
		} else if op == 3 {
			nested = !nested
			revisions[0] += 1
		} else if op == 4 && len(enabled) < 8 {
			key := u64(len(enabled))
			append(&enabled, true)
			append(&revisions, 0)
			append(&order, key)
			expected[key] = 0
		} else {
			key := u64(seed % u64(len(enabled)))
			enabled[key] = true
			if _, exists := expected[key]; !exists { expected[key] = 0 }
		}
		before_body := body_calls
		roots = render_region_collection(&rt, order[:], enabled[:], revisions[:], nested, &body_calls)
		for key, id in roots {
			expect(state, rt.nodes[id].local_counter == expected[key], fmt.tprintf("region state followed key at step %d key %d", step, key))
		}
		expect(state, body_calls >= before_body, "region body count is monotonic")
	}
	for _, id in roots { expect(state, rt.nodes[id].region, "region collection root remains a region") }
	expect(state, len(rt.nodes) < 80, "region collection retains only enabled live structure")
	alicorn.destroy_runtime(&rt)
}

test_focus_and_editing :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	ids := render_keyed(&rt, []string{"a", "b", "c"}, []int{0, 0, 0}, false, false)
	b := rt.nodes[ids["b"]]
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, b.bounds.x+2, b.bounds.y+2, 1})
	render_keyed(&rt, []string{"a", "b", "c"}, []int{0, 0, 0}, false, false)
	expect(state, rt.focused == ids["b"], "pointer focus must target the retained node")
	ids = render_keyed(&rt, []string{"c", "b", "a"}, []int{0, 0, 0}, false, false)
	expect(state, rt.focused == ids["b"], "focus must survive keyed reorder")
	render_keyed(&rt, []string{"a", "c"}, []int{0, 0}, false, false)
	expect(state, rt.focused == ids["a"], "removed focus must fall back to first active focusable")
	alicorn.invalidate_root(&rt, "test text field")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, S_ROOT)
		field := alicorn.text_field(&ui, "abc", alicorn.site("tests/edit.odin", 1, 1, "query"))
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		change := alicorn.process_text_edit(&rt, field, alicorn.Text_Edit{.Backspace, ""})
		expect(state, change.changed && change.text == "ab", "basic retained text editing must produce an explicit app-state change")
	}
	alicorn.destroy_runtime(&rt)
}

test_unicode_editing :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	id := render_text_field(&rt, "Aé世😀👨‍👩‍👧")
	change := alicorn.process_text_edit(&rt, id, alicorn.Text_Edit{.Backspace, ""})
	expect(state, change.changed && change.text == "Aé世😀", "backspace must remove one complete family grapheme")
	if len(change.text) > 0 { delete(change.text) }
	render_text_field(&rt, "Aé世😀")
	change = alicorn.process_text_edit(&rt, id, alicorn.Text_Edit{.Backspace, ""})
	expect(state, change.changed && change.text == "Aé世", "backspace must remove one complete emoji grapheme")
	if len(change.text) > 0 { delete(change.text) }
	render_text_field(&rt, "é世😀")
	expect(state, alicorn.set_text_caret(&rt, id, 1), "caret setter must accept a text field")
	change = alicorn.process_text_edit(&rt, id, alicorn.Text_Edit{.Delete, ""})
	expect(state, change.changed && change.text == "世😀", "delete must remove a complete UTF-8 grapheme")
	if len(change.text) > 0 { delete(change.text) }
	render_text_field(&rt, "é世😀")
	expect(state, alicorn.set_text_selection(&rt, id, 5, 1), "selection setter must accept reversed byte offsets")
	change = alicorn.process_text_edit(&rt, id, alicorn.Text_Edit{.Backspace, ""})
	expect(state, change.changed && change.text == "😀", "selection deletion must expand to grapheme boundaries")
	if len(change.text) > 0 { delete(change.text) }
	expect(state, rt.nodes[id].caret_byte == 0, "selection deletion must collapse caret to range start")
	alicorn.destroy_runtime(&rt)
}

test_interaction_regressions :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	id, _ := render_single_button(&rt)
	node := rt.nodes[id]
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, node.bounds.x+2, node.bounds.y+2, 0})
	render_single_button(&rt)
	expect(state, rt.nodes[id].hovered, "hover state must survive reconciliation")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, node.bounds.x+2, node.bounds.y+2, 1})
	_, clicked := render_single_button(&rt)
	expect(state, !clicked && rt.nodes[id].pressed, "pointer down must capture and retain pressed state without activating")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, 400, 180, 0})
	render_single_button(&rt)
	expect(state, rt.nodes[id].pressed, "captured button remains pressed while pointer leaves its bounds")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, 400, 180, 1})
	_, clicked = render_single_button(&rt)
	expect(state, !clicked && !rt.nodes[id].pressed, "pointer up outside target must cancel activation")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, node.bounds.x+2, node.bounds.y+2, 1})
	render_single_button(&rt)
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, node.bounds.x+2, node.bounds.y+2, 1})
	_, clicked = render_single_button(&rt)
	expect(state, clicked && !rt.nodes[id].pressed, "pointer down/up on target must activate exactly once")
	for _ in 0..<100 {
		_, clicked = render_single_button(&rt)
		expect(state, !clicked, "button activation must be consumed exactly once")
	}

	child := render_focus_ancestor(&rt, true)
	child_node := rt.nodes[child]
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, child_node.bounds.x+2, child_node.bounds.y+2, 1})
	render_focus_ancestor(&rt, true)
	expect(state, rt.focused == child, "child should own focus before removal")
	parent := render_focus_ancestor(&rt, false)
	expect(state, rt.focused == parent, "removed focus must fall back to nearest active focusable ancestor")

	clipped := render_clipped(&rt)
	clipped_node := rt.nodes[clipped]
	expect(state, alicorn.hit_test(&rt, clipped_node.bounds.x+10, clipped_node.bounds.y+10) == clipped, "visible clipped child should hit")
	expect(state, alicorn.hit_test(&rt, clipped_node.bounds.x+75, clipped_node.bounds.y+10) == 0, "clipped child must not hit outside effective clip")
	alicorn.destroy_runtime(&rt)
}

test_ergonomic_identity :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	first := render_ergonomic(&rt, []string{"a", "b", "c"})
	for key, id in first { rt.nodes[id].local_counter = 700 + len(key) }
	second := render_ergonomic(&rt, []string{"c", "a", "b"})
	for key, id in second {
		expect(state, rt.nodes[id].local_counter == 700+len(key), fmt.tprintf("caller-location component identity moved for %s", key))
	}
	for _, id in second {
		expect(state, len(rt.nodes[id].site.file) > 0 && rt.nodes[id].site.component == "button", "auto widget API must retain caller source site")
	}
	alicorn.destroy_runtime(&rt)
}

test_virtualization_and_gpu :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 600})
	render_virtual(&rt, 0)
	expect(state, len(rt.nodes) <= 14, "million logical rows must retain only viewport-scale nodes")
	first_count := len(rt.nodes)
	render_virtual(&rt, 500000)
	expect(state, len(rt.nodes) == first_count, "scrolling fixed-height virtual list keeps bounded node count")
	logical_keys := []string{"k0", "k1", "k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9", "k10", "k11"}
	ids := render_virtual_data(&rt, logical_keys, 0)
	for key, id in ids { rt.nodes[id].local_counter = 900 + len(key) }
	expect(state, alicorn.select(&rt, ids["k3"]), "visible virtual row can be selected explicitly")
	logical_keys = []string{"k5", "k0", "k1", "k2", "k3", "k4", "k6", "k7", "k8", "k9", "k10", "k11"}
	ids = render_virtual_data(&rt, logical_keys, 0)
	for key, id in ids {
		expect(state, rt.nodes[id].local_counter == 900+len(key), fmt.tprintf("virtual row identity moved for %s", key))
	}
	expect(state, rt.selected == ids["k3"] && rt.nodes[ids["k3"]].selected, "virtual selection follows logical row identity")
	gpu := alicorn.new_gpu_backend()
	for i := 0; i < 10000; i += 1 {
		command := alicorn.gpu_begin_commands(&gpu)
		fence := alicorn.gpu_submit(&gpu, command)
		alicorn.gpu_replace_resource(&gpu, fence)
		if i%3 == 0 { alicorn.gpu_retire_completed(&gpu, fence) }
	}
	alicorn.gpu_retire_completed(&gpu, gpu.next_fence)
	expect(state, !gpu.command_open && gpu.resource_retirements > 0, "submitted GPU work must retire through fences")
	expect(state, gpu.resource_retirements <= u64(gpu.next_fence), "GPU retirement bookkeeping must remain bounded")
	expect(state, len(gpu.retirement_queue) == 0, "retired GPU queue must be compacted")
	alicorn.destroy_runtime(&rt)
}

test_layout_geometry :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 100, 40})
	alicorn.invalidate_root(&rt, "layout test")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		row_style := alicorn.Layout_Style{.Row, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}
		alicorn.container_begin(&ui, .Root, S_ROOT, style=row_style)
		fixed := alicorn.Layout_Style{.Column, 30, 20, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}
		grow := alicorn.Layout_Style{.Column, -1, 20, 0, -1, 0, -1, 1, 0, 0, .Stretch, false}
		fixed_id, _ := alicorn.button(&ui, "fixed", S_LAYOUT_A, style=fixed)
		grow_id := alicorn.text(&ui, "grow", S_LAYOUT_B, style=grow)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		expect(state, rt.nodes[fixed_id].bounds.w == 30, "fixed row child width")
		expect(state, rt.nodes[grow_id].bounds.w == 70, "grow row child consumes remaining width")
		expect(state, rt.nodes[grow_id].bounds.x == 30, "row child placement")
		expect(state, rt.stats.layout_updates >= 2, "layout changes must be counted")
	}
	alicorn.destroy_runtime(&rt)
}

test_gpu_text_resource_boundary :: proc(state: ^Test_State) {
	// The key is CPU-resource identity, not GPU residency. Every raster
	// parameter that can change pixels must participate in the key.
	size_16: f32 = 16
	size_18: f32 = 18
	base := alicorn.Glyph_Resource_Key{font_generation=1, size_bits=transmute(u32)size_16, subpixel_bucket=0, hint=true, is_color=false}
	other_size := base
	other_size.size_bits = transmute(u32)size_18
	other_subpixel := base
	other_subpixel.subpixel_bucket = 1
	other_font := base
	other_font.font_generation = 2
	expect(state, base != other_size, "glyph key must include pixel size")
	expect(state, base != other_subpixel, "glyph key must include subpixel bucket")
	expect(state, base != other_font, "glyph key must include font generation")

	atlas := runa.atlas_make(16, 16)
	defer runa.atlas_destroy(&atlas)
	pixels := [4]u8{255, 128, 64, 32}
	_, pack_err := runa.atlas_pack_alpha(&atlas, pixels[:], 2, 2, [2]f32{})
	expect(state, pack_err == .None, "synthetic glyph must pack into the CPU atlas")
	snapshot := runa.atlas_dirty_snapshot(&atlas)
	expect(state, len(snapshot) == 1, "dirty snapshot must expose the page without clearing it")
	if len(snapshot) == 1 {
		view, view_ok := runa.atlas_page_view(&atlas, snapshot[0].Page_Index, snapshot[0].Is_Color)
		expect(state, view_ok && len(view.Pixels) == 16*16, "atlas page view must expose stable page pixels")
	}
	// A second write after the snapshot must survive acknowledgement of the
	// first upload generation. This is the retry/lost-update invariant.
	second_pixel := [1]u8{7}
	_, second_err := runa.atlas_pack_alpha(&atlas, second_pixel[:], 1, 1, [2]f32{})
	expect(state, second_err == .None, "second synthetic glyph must pack")
	runa.atlas_dirty_ack(&atlas, snapshot)
	delete(snapshot)
	remaining := runa.atlas_dirty_snapshot(&atlas)
	expect(state, len(remaining) == 1, "dirty writes after a snapshot must remain pending")
	if len(remaining) > 0 { runa.atlas_dirty_ack(&atlas, remaining) }
	delete(remaining)
	final_snapshot := runa.atlas_dirty_snapshot(&atlas)
	expect(state, len(final_snapshot) == 0, "acknowledged atlas page must become clean")
	delete(final_snapshot)
}

test_retained_text_product_lifetime :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	id := render_text_field(&rt, "retained")
	node, found := rt.nodes[id]
	expect(state, found && node != nil, "text field must create a retained node")
	if found && node != nil {
		// A real GPU/native run is populated only when a font provider is
		// configured. This sentinel exercises the ownership boundary: changing
		// the retained text must invalidate and destroy the node-owned product.
		node.text_run_valid = true
	}
	changed_id := render_text_field(&rt, "changed")
	expect(state, changed_id == id, "text changes must preserve text-field identity")
	if node, ok := rt.nodes[id]; ok {
		expect(state, !node.text_run_valid, "changed text must invalidate the retained text product")
	}
	alicorn.destroy_runtime(&rt)
}

main :: proc() {
	state: Test_State
	test_identity_and_ambiguity(&state)
	test_property_sequences(&state)
	test_regions_and_stages(&state)
	test_retained_subtree_reuse(&state)
	test_region_identity_sequences(&state)
	test_focus_and_editing(&state)
	test_unicode_editing(&state)
	test_interaction_regressions(&state)
	test_ergonomic_identity(&state)
	test_virtualization_and_gpu(&state)
	test_layout_geometry(&state)
	test_gpu_text_resource_boundary(&state)
	test_retained_text_product_lifetime(&state)
	if state.failures == 0 {
		fmt.println("Alicorn foundation tests: PASS")
		return
	}
	fmt.println("Alicorn foundation tests: FAILURES", state.failures)
	os.exit(1)
}
