package main

import "core:fmt"
import "core:os"
import alicorn "../runtime"

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

virtual_row :: proc(ui: ^alicorn.UI, index: int) {
	alicorn.text(ui, fmt.tprintf("row %d", index), S_VROW)
}

render_virtual :: proc(rt: ^alicorn.Runtime, scroll: f32) {
	alicorn.invalidate_root(rt, "test virtual scroll")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, S_ROOT, label="root")
	alicorn.virtual_list(&ui, 1_000_000, scroll, 200, 20, S_VLIST, virtual_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
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
	report := alicorn.inspect(&rt)
	expect(state, len(report) > 100 && len(alicorn.trace_snapshot(&rt)) > 0, "inspector and bounded trace must expose structural work")
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

test_virtualization_and_gpu :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 600})
	render_virtual(&rt, 0)
	expect(state, len(rt.nodes) <= 14, "million logical rows must retain only viewport-scale nodes")
	first_count := len(rt.nodes)
	render_virtual(&rt, 500000)
	expect(state, len(rt.nodes) == first_count, "scrolling fixed-height virtual list keeps bounded node count")
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

main :: proc() {
	state: Test_State
	test_identity_and_ambiguity(&state)
	test_property_sequences(&state)
	test_regions_and_stages(&state)
	test_focus_and_editing(&state)
	test_virtualization_and_gpu(&state)
	test_layout_geometry(&state)
	if state.failures == 0 {
		fmt.println("Alicorn foundation tests: PASS")
		return
	}
	fmt.println("Alicorn foundation tests: FAILURES", state.failures)
	os.exit(1)
}
