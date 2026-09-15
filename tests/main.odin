package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
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
S_TEXT_A :: alicorn.Source_Site{"tests/text_input.odin", 1, 1, "field_a"}
S_TEXT_B :: alicorn.Source_Site{"tests/text_input.odin", 2, 1, "field_b"}
S_SURFACE :: alicorn.Source_Site{"tests/gpu_surface.odin", 1, 1, "surface"}

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
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="root", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	if extra {
		alicorn.text_ex(&ui, "extra", S_EXTRA)
	}
	if wrapper {
		alicorn.transparent_container_begin(&ui, .Container, S_WRAP, label="wrapper")
	}
	for i := 0; i < len(keys); i += 1 {
		if alicorn.key_scope_begin_ex(&ui, keys[i], S_ROW) {
			id, _ := alicorn.button_ex(&ui, keys[i], S_BUTTON, style=alicorn.Layout_Style{.Column, -1, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}, paint_value=u64(values[i] if i < len(values) else 0))
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
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="numeric-root")
	for key, i in keys {
		if alicorn.key_scope_u64(&ui, key, S_ROW) {
			id, _ := alicorn.button_ex(&ui, fmt.tprintf("n%d", key), S_BUTTON, style=alicorn.Layout_Style{.Column, -1, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}, paint_value=u64(values[i] if i < len(values) else 0))
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
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="root")
	id, reused := alicorn.region_begin(&ui, "static", revision, S_REGION)
	if id != 0 && !reused {
		start := len(rt.pending)
		body_counter^ += 1
		alicorn.text_ex(&ui, "cached body", alicorn.site("tests/render.odin", 41, 1, "cached_body"))
		alicorn.region_end(&ui, id, false, start)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_stress_region :: proc(rt: ^alicorn.Runtime, revision: u64, include_region: bool, body_counter: ^int) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test retained subtree stress")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="stress-root")
	sibling, _ := alicorn.button_ex(&ui, "fallback", S_REGION_STRESS_SIBLING, style=alicorn.Layout_Style{.Column, 160, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	if include_region && alicorn.key_scope_begin_ex(&ui, "retained", S_REGION_STRESS_SCOPE) {
		id, reused := alicorn.region_begin(&ui, "body", revision, S_REGION_STRESS)
		if id != 0 && !reused {
			body_counter^ += 1
			start := len(rt.pending)
			if alicorn.key_scope_u64(&ui, 0, S_REGION_STRESS_NODE) {
				alicorn.button_ex(&ui, "focused descendant", S_REGION_STRESS_NODE, style=alicorn.Layout_Style{.Column, 180, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
				alicorn.key_scope_end(&ui)
			}
			for i := 1; i < 256; i += 1 {
				if alicorn.key_scope_u64(&ui, u64(i), S_REGION_STRESS_NODE) {
					alicorn.text_ex(&ui, "retained descendant", S_REGION_STRESS_NODE)
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
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="region-collection")
	for key in order {
		if key >= u64(len(enabled)) || !enabled[key] { continue }
		if !alicorn.key_scope_u64(&ui, key, S_REGION_STRESS_SCOPE) { continue }
		id, reused := alicorn.region_begin(&ui, "item", revisions[key], S_REGION_STRESS)
		roots[key] = id
		if id != 0 && !reused {
			body_counter^ += 1
			start := len(rt.pending)
			if alicorn.key_scope_u64(&ui, 0, S_REGION_STRESS_NODE) {
				alicorn.button_ex(&ui, "region-state", S_REGION_STRESS_NODE, style=alicorn.Layout_Style{.Column, 120, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}, paint_value=key)
				alicorn.key_scope_end(&ui)
			}
			if nested && key == 0 {
				nested_id, nested_reused := alicorn.region_begin(&ui, "nested", revisions[key], S_REGION_STRESS_NESTED)
				if nested_id != 0 && !nested_reused {
					nested_start := len(rt.pending)
					alicorn.text_ex(&ui, "nested-state", S_REGION_STRESS_NODE)
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
	alicorn.text_ex(ui, fmt.tprintf("row %d", index), S_VROW)
}

virtual_item_key :: proc(index: int) -> string {
	return fmt.tprintf("item-%d", index)
}

virtual_data_key :: proc(index: int) -> string {
	return virtual_keys[index]
}

virtual_data_row :: proc(ui: ^alicorn.UI, index: int) {
	alicorn.text_ex(ui, virtual_keys[index], S_VROW)
}

render_virtual :: proc(rt: ^alicorn.Runtime, scroll: f32) {
	alicorn.invalidate_root(rt, "test virtual scroll")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="root")
	alicorn.virtual_list_ex(&ui, 1_000_000, scroll, 200, 20, S_VLIST, virtual_item_key, virtual_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

render_virtual_data :: proc(rt: ^alicorn.Runtime, keys: []string, scroll: f32) -> map[string]alicorn.Node_ID {
	virtual_keys = keys
	alicorn.invalidate_root(rt, "test logical virtual data")
	ui, build := alicorn.begin_frame(rt)
	ids := make(map[string]alicorn.Node_ID)
	if !build { return ids }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="virtual-data-root")
	alicorn.virtual_list_ex(&ui, len(keys), scroll, 200, 20, S_VLIST, virtual_data_key, virtual_data_row)
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
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="button-root")
	id, clicked = alicorn.button_ex(&ui, "button", S_BUTTON, style=alicorn.Layout_Style{.Column, 100, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

render_text_field :: proc(rt: ^alicorn.Runtime, value: string) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test text field frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="text-field-root")
	id := alicorn.text_field_ex(&ui, value, alicorn.site("tests/edit.odin", 2, 1, "query"))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return id
}

render_two_text_fields :: proc(rt: ^alicorn.Runtime) -> (first, second: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "test two text fields")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="two-text-fields")
	first = alicorn.text_field_ex(&ui, "first", S_TEXT_A)
	second = alicorn.text_field_ex(&ui, "second", S_TEXT_B)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

render_optional_text_field :: proc(rt: ^alicorn.Runtime, include: bool) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test optional composition field")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="optional-text-field")
	id: alicorn.Node_ID
	if include { id = alicorn.text_field_ex(&ui, "retained", S_TEXT_A) }
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return id
}

make_geometry_run :: proc() -> alicorn.Text_Run {
	value, err := strings.clone("abcd")
	if err != nil { return alicorn.Text_Run{} }
	run := alicorn.Text_Run{
		value=value,
		glyphs=make([dynamic]alicorn.Text_Glyph, 0, 4),
		lines=make([dynamic]alicorn.Text_Line, 0, 2),
		width=20,
		height=20,
		size=16,
	}
	append(&run.glyphs,
		alicorn.Text_Glyph{glyph_id=0, cluster_start=0, cluster_end=1, x=0, x_advance=10, line_index=0},
		alicorn.Text_Glyph{glyph_id=0, cluster_start=1, cluster_end=2, x=10, x_advance=10, line_index=0},
		alicorn.Text_Glyph{glyph_id=0, cluster_start=2, cluster_end=3, x=0, y=10, x_advance=10, line_index=1},
		alicorn.Text_Glyph{glyph_id=0, cluster_start=3, cluster_end=4, x=10, y=10, x_advance=10, line_index=1},
	)
	append(&run.lines,
		alicorn.Text_Line{glyph_start=0, glyph_end=2, byte_start=0, byte_end=2, x=0, y=0, width=20, height=10, baseline=8},
		alicorn.Text_Line{glyph_start=2, glyph_end=4, byte_start=2, byte_end=4, x=0, y=10, width=20, height=10, baseline=8},
	)
	return run
}

render_focus_ancestor :: proc(rt: ^alicorn.Runtime, include_child: bool) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test focus ancestor")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="focus-root")
	parent := alicorn.container_begin_ex(&ui, .Container, S_WRAP, label="focus-parent", focusable=true, style=alicorn.Layout_Style{.Column, 120, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	if include_child {
		child, _ := alicorn.button_ex(&ui, "child", S_BUTTON, style=alicorn.Layout_Style{.Column, 100, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
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
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="clip-root")
	alicorn.container_begin_ex(&ui, .Container, S_WRAP, label="clip-parent", style=alicorn.Layout_Style{.Column, 50, 50, 0, -1, 0, -1, 0, 0, 0, .Stretch, true})
	child, _ := alicorn.button_ex(&ui, "oversized", S_BUTTON, style=alicorn.Layout_Style{.Column, 100, 100, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return child
}

ergonomic_row :: proc(ui: ^alicorn.UI, label: string) -> alicorn.Node_ID {
	id, _ := alicorn.button_ex(ui, label, key=label, explicit_key=true, style=alicorn.Layout_Style{.Column, 100, 24, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	return id
}

render_ergonomic :: proc(rt: ^alicorn.Runtime, keys: []string) -> map[string]alicorn.Node_ID {
	ids := make(map[string]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "test ergonomic API")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, label="ergonomic-root")
	for key in keys {
		if alicorn.component_begin(&ui, alicorn.key_string(key)) {
			ids[key] = ergonomic_row(&ui, key)
			alicorn.component_end(&ui)
		}
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

emit_canonical_key :: proc(ui: ^alicorn.UI, key: alicorn.UI_Key) -> alicorn.Node_ID {
	return alicorn.text(ui, "same structural site", key=key)
}

render_key_variants :: proc(rt: ^alicorn.Runtime, keys: []alicorn.UI_Key) -> []alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test typed key variants")
	ui, build := alicorn.begin_frame(rt)
	ids := make([]alicorn.Node_ID, len(keys))
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, label="typed-key-root")
	for key, i in keys { ids[i] = emit_canonical_key(&ui, key) }
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

render_canonical_button :: proc(rt: ^alicorn.Runtime, state := alicorn.Button_State{}) -> (id: alicorn.Node_ID, clicked: bool) {
	alicorn.invalidate_root(rt, "test canonical button")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="canonical-button-root")
	clicked = alicorn.button(&ui, "canonical", state=state)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for candidate in rt.order {
		if node, ok := rt.nodes[candidate]; ok && node.kind == .Button { id = candidate; break }
	}
	return
}

render_text_growth_pair :: proc(rt: ^alicorn.Runtime, first, second: string) -> (first_id, second_id: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "test text intrinsic growth")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	row_style := alicorn.Layout_Style{.Row, -1, 40, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, style=row_style)
	first_id = alicorn.text_ex(&ui, first, S_TEXT_A)
	second_id = alicorn.text_ex(&ui, second, S_TEXT_B)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
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
		alicorn.container_begin_ex(&ui, .Root, S_ROOT)
		alicorn.button_ex(&ui, "one", S_BUTTON)
		alicorn.button_ex(&ui, "two", S_BUTTON)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, rt.hard_error, "unkeyed repeated siblings must be a hard diagnostic")
	alicorn.destroy_runtime(&rt)
	rt = alicorn.new_runtime(alicorn.Rect{0, 0, 100, 100})
	alicorn.invalidate_root(&rt, "duplicate key test")
	ui, build = alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, S_ROOT)
		if alicorn.key_scope_begin_ex(&ui, "same", S_ROW) { alicorn.text_ex(&ui, "one", S_BUTTON); alicorn.key_scope_end(&ui) }
		if alicorn.key_scope_begin_ex(&ui, "same", S_ROW) { alicorn.text_ex(&ui, "two", S_BUTTON); alicorn.key_scope_end(&ui) }
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
		alicorn.container_begin_ex(&ui, .Root, S_ROOT)
		if alicorn.key_scope_u64(&ui, 7, S_ROW) { alicorn.text_ex(&ui, "one", S_BUTTON); alicorn.key_scope_end(&ui) }
		if alicorn.key_scope_u64(&ui, 7, S_ROW) { alicorn.text_ex(&ui, "two", S_BUTTON); alicorn.key_scope_end(&ui) }
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, rt.hard_error, "duplicate numeric keys must be a hard diagnostic")
	alicorn.destroy_runtime(&rt)
}

test_typed_key_variants :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	keys := []alicorn.UI_Key{
		alicorn.UI_Unkeyed{},
		alicorn.key_string(""),
		alicorn.key_u64(0),
		alicorn.key_pair(0, 0),
		alicorn.key_string("same"),
		alicorn.key_u64(1),
		alicorn.key_pair(0, 1),
	}
	ids := render_key_variants(&rt, keys)
	for i := 0; i < len(ids); i += 1 {
		expect(state, ids[i] != 0, fmt.tprintf("typed key variant %d must emit a node", i))
		for j := i+1; j < len(ids); j += 1 {
			expect(state, ids[i] != ids[j], fmt.tprintf("typed key variants %d and %d must remain distinct", i, j))
		}
	}
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
	expect(state, rt.stats.stage_visits[.Description] > 0, "description stage visits must be counted")
	expect(state, rt.stats.stage_visits[.Reconcile] > 0, "reconcile stage visits must be counted")
	expect(state, rt.stats.stage_visits[.Layout] > 0, "layout stage visits must be counted")
	expect(state, rt.stats.stage_visits[.Paint] > 0, "paint stage visits must be counted")
	expect(state, rt.stats.stage_visits[.Composite] > 0, "composite stage visits must be counted")
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
		alicorn.container_begin_ex(&ui, .Root, S_ROOT)
		field := alicorn.text_field_ex(&ui, "abc", alicorn.site("tests/edit.odin", 1, 1, "query"))
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
	expect(state, rt.nodes[id].selection_anchor.byte == 5 && rt.nodes[id].selection_anchor.affinity == .Trailing, "reverse selection must retain its anchor affinity")
	expect(state, rt.nodes[id].selection_focus.byte == 0 && rt.nodes[id].selection_focus.affinity == .Leading, "reverse selection must retain its active-end affinity")
	change = alicorn.process_text_edit(&rt, id, alicorn.Text_Edit{.Backspace, ""})
	expect(state, change.changed && change.text == "😀", "selection deletion must expand to grapheme boundaries")
	if len(change.text) > 0 { delete(change.text) }
	expect(state, rt.nodes[id].caret.byte == 0 && rt.nodes[id].caret.affinity == .Leading, "selection deletion must collapse caret to range start")
	alicorn.destroy_runtime(&rt)
}

test_text_input_composition :: proc(state: ^Test_State) {
	expect(state, alicorn.utf8_character_index_to_byte_offset("é世😀", 0) == 0, "SDL character index zero maps to byte zero")
	expect(state, alicorn.utf8_character_index_to_byte_offset("é世😀", 1) == 2, "UTF-8 character index maps past a two-byte code point")
	expect(state, alicorn.utf8_character_index_to_byte_offset("é世😀", 2) == 5, "UTF-8 character index maps past a three-byte code point")
	expect(state, alicorn.utf8_character_index_to_byte_offset("é世😀", 3) == 9, "UTF-8 character index maps past a four-byte code point")
	expect(state, alicorn.utf8_character_index_to_byte_offset("é世😀", 99) == 9, "out-of-range SDL character indexes clamp to the string end")

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	id := render_text_field(&rt, "hello world")
	alicorn.set_text_selection(&rt, id, 11, 6)
	paint_before := rt.stats.paint_updates
	expect(state, alicorn.process_text_editing(&rt, id, "日本", 0, 2), "TEXT_EDITING must be accepted by a focused text field")
	expect(state, rt.nodes[id].text == "hello world", "preedit must not mutate committed application text")
	expect(state, rt.nodes[id].composition.active, "preedit must become retained transient composition state")
	expect(state, rt.nodes[id].composition.replace_anchor.byte == 11 && rt.nodes[id].composition.replace_focus.byte == 6, "composition must retain the original selection direction")
	expect(state, rt.nodes[id].composition.selection_start == 0 && rt.nodes[id].composition.selection_end == 6, "SDL character indexes must convert to composition byte offsets")
	render_text_field(&rt, "hello world")
	expect(state, rt.stats.paint_updates > paint_before, "preedit updates must repaint the focused field")

	expect(state, alicorn.process_text_editing(&rt, id, "にほ", 1, 1), "composition updates must replace the copied preedit")
	expect(state, rt.nodes[id].composition.selection_start == 3 && rt.nodes[id].composition.selection_end == 6, "composition cursor selection must track later UTF-8 updates")
	change := alicorn.process_text_input(&rt, id, "世界")
	expect(state, change.changed && change.text == "hello 世界", "committed TEXT_INPUT must replace the captured selection exactly once")
	expect(state, !rt.nodes[id].composition.active, "committed input must clear transient composition state")
	if len(change.text) > 0 { delete(change.text) }
	render_text_field(&rt, "hello 世界")

	expect(state, alicorn.process_text_editing(&rt, id, "かな", -1, -1), "composition with unset SDL cursor metadata must be accepted")
	expect(state, rt.nodes[id].composition.selection_start == len("かな") && rt.nodes[id].composition.selection_end == len("かな"), "unset SDL cursor metadata must place the preedit cursor at its end")
	expect(state, alicorn.cancel_text_composition(&rt, id, "test explicit composition cancel"), "explicit composition cancellation must clear an active preedit")
	expect(state, !rt.nodes[id].composition.active && rt.nodes[id].text == "hello 世界", "explicit cancellation must not change committed text")
	alicorn.process_text_editing(&rt, id, "かな", 0, 2)
	alicorn.process_text_editing(&rt, id, "", 0, 0)
	expect(state, !rt.nodes[id].composition.active && rt.nodes[id].text == "hello 世界", "empty TEXT_EDITING must cancel without changing committed text")

	first, second := render_two_text_fields(&rt)
	alicorn.process_text_editing(&rt, first, "候", 0, 1)
	expect(state, rt.nodes[first].composition.active, "first field should own its active composition")
	expect(state, alicorn.focus(&rt, second), "focus transfer to another text field must succeed")
	expect(state, !rt.nodes[first].composition.active, "focus loss must cancel the old field composition")

	retained := render_optional_text_field(&rt, true)
	alicorn.process_text_editing(&rt, retained, "消", 0, 1)
	render_optional_text_field(&rt, false)
	expect(state, rt.focused == 0, "retiring a composing field must clear keyboard focus")
	expect(state, len(rt.nodes) == 1, "retiring a composing field must remove its retained node")
	alicorn.destroy_runtime(&rt)
}

test_interaction_paint_invalidation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	id := render_text_field(&rt, "caret")
	expect(state, len(rt.nodes[id].paint) == 1, "unfocused text field starts with only its text command")
	paint_before_focus := rt.stats.paint_updates
	expect(state, alicorn.focus(&rt, id), "text field must accept focus")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, S_ROOT)
		field := alicorn.text_field_ex(&ui, "caret", alicorn.site("tests/edit.odin", 2, 1, "query"))
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		expect(state, field == id, "focus repaint frame must preserve field identity")
	}
	expect(state, rt.stats.paint_updates > paint_before_focus, "focus change must queue an interaction repaint")
	paint_before_focus = rt.stats.paint_updates
	alicorn.set_text_selection(&rt, id, 5, 1)
	ui, build = alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, S_ROOT)
		alicorn.text_field_ex(&ui, "caret", alicorn.site("tests/edit.odin", 2, 1, "query"))
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, rt.stats.paint_updates > paint_before_focus, "selection change must queue an interaction repaint")
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

test_disabled_button_semantics :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	id, _ := render_canonical_button(&rt)
	node := rt.nodes[id]
	enabled_color := node.paint[0].color
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, node.bounds.x+2, node.bounds.y+2, 1})
	expect(state, rt.captured_node == id, "enabled button must capture pointer down")
	_, _ = render_canonical_button(&rt, alicorn.Button_State{disabled=true})
	expect(state, rt.captured_node == 0 && !rt.nodes[id].pressed, "disabling a captured button must clear press state")
	expect(state, rt.nodes[id].paint[0].color != enabled_color, "disabled button must change its paint state")
	expect(state, alicorn.hit_test(&rt, node.bounds.x+2, node.bounds.y+2) == 0, "disabled button must not hit-test")
	expect(state, !alicorn.focus(&rt, id), "disabled button must not receive focus")
	_, clicked := render_canonical_button(&rt, alicorn.Button_State{disabled=true})
	expect(state, !clicked, "disabled button must not activate from keyboard or pointer state")
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
		alicorn.container_begin_ex(&ui, .Root, S_ROOT, style=row_style)
		fixed := alicorn.Layout_Style{.Column, 30, 20, 0, -1, 0, -1, 0, 0, 0, .Stretch, false}
		grow := alicorn.Layout_Style{.Column, -1, 20, 0, -1, 0, -1, 1, 0, 0, .Stretch, false}
		fixed_id, _ := alicorn.button_ex(&ui, "fixed", S_LAYOUT_A, style=fixed)
		grow_id := alicorn.text_ex(&ui, "grow", S_LAYOUT_B, style=grow)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		expect(state, rt.nodes[fixed_id].bounds.w == 30, "fixed row child width")
		expect(state, rt.nodes[grow_id].bounds.w == 70, "grow row child consumes remaining width")
		expect(state, rt.nodes[grow_id].bounds.x == 30, "row child placement")
		expect(state, rt.stats.layout_updates >= 2, "layout changes must be counted")
	}
	alicorn.destroy_runtime(&rt)
}

test_text_intrinsic_layout_invalidation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 80})
	first, second := render_text_growth_pair(&rt, "CPU 0.0%", "System memory 0 MB")
	first_layout_hash := rt.nodes[first].layout_hash
	before_updates := rt.stats.layout_updates
	first, second = render_text_growth_pair(&rt, "CPU 100.0%", "System memory 12.7 GB / 32.0 GB")
	expect(state, rt.nodes[first].layout_hash != first_layout_hash, "text growth must change the retained layout product")
	expect(state, rt.stats.layout_updates > before_updates, "text growth must revisit layout rather than only repainting")
	expect(state, rt.nodes[second].bounds.x >= rt.nodes[first].bounds.x+rt.nodes[first].bounds.w, "text siblings must remain laid out after a dynamic value grows")
	alicorn.destroy_runtime(&rt)
}

test_container_paint_defaults :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	alicorn.invalidate_root(&rt, "test container paint defaults")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="root")
		layout_only := alicorn.container_begin_ex(&ui, .Container, S_WRAP, label="layout-only")
		alicorn.container_end(&ui)
		colored := alicorn.container_begin_ex(&ui, .Container, S_EXTRA, label="colored", color=alicorn.Color{0.1, 0.2, 0.3, 1})
		alicorn.container_end(&ui)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		expect(state, len(rt.nodes[rt.top_level[0]].paint) == 1, "root must retain its default background paint")
		expect(state, len(rt.nodes[layout_only].paint) == 0, "layout-only containers must not emit a background paint command")
		expect(state, len(rt.nodes[colored].paint) == 1, "explicitly colored containers must retain a background paint command")
	}
	alicorn.destroy_runtime(&rt)
}

test_presentation_invalidation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	id, _ := render_single_button(&rt)
	frames_before := rt.stats.frames_built
	rt.invalidated = false
	node := rt.nodes[id]
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, node.bounds.x+2, node.bounds.y+2, 0})
	expect(state, !rt.invalidated, "hover must not invalidate the application description")
	expect(state, alicorn.presentation_needs_frame(&rt), "hover must request a retained presentation frame")
	_, build := alicorn.begin_frame(&rt)
	expect(state, !build && rt.stats.frames_built == frames_before, "presentation-only wake must not rebuild the application description")
	presentation_ui, ready := alicorn.begin_presentation_frame(&rt)
	expect(state, ready, "presentation-only wake must open a retained frame")
	if ready { alicorn.end_presentation_frame(&presentation_ui) }
	expect(state, !alicorn.presentation_needs_frame(&rt), "flushing presentation work must consume its pending wake")
	alicorn.destroy_runtime(&rt)
}

test_text_geometry :: proc(state: ^Test_State) {
	run := make_geometry_run()
	defer alicorn.text_run_destroy(&run)

	caret := alicorn.text_run_caret_geometry(&run, alicorn.Text_Position{1, .Leading})
	expect(state, caret.valid && caret.line_index == 0 && caret.rect.x == 10 && caret.rect.y == 0, "caret geometry must map a logical boundary to line coordinates")
	hit := alicorn.text_run_hit_test(&run, 19, 2)
	expect(state, hit.byte == 2, "text hit testing must choose the nearest visual cluster boundary")
	hit = alicorn.text_run_hit_test(&run, 1, 12)
	expect(state, hit.byte == 2, "text hit testing must select the correct wrapped line")

	selection := alicorn.text_run_selection_rects(&run, alicorn.Text_Position{1, .Leading}, alicorn.Text_Position{3, .Trailing})
	expect(state, len(selection) == 2, "selection across wrapped lines must produce one rectangle per line")
	if len(selection) == 2 {
		expect(state, selection[0].rect.x == 10 && selection[0].rect.w == 10, "first selection line must begin at the selected boundary")
		expect(state, selection[1].rect.x == 0 && selection[1].rect.w == 10, "second selection line must end at the selected boundary")
	}
	delete(selection)

	ligature_value, ligature_err := strings.clone("ffi")
	ligature := alicorn.Text_Run{
		value=ligature_value,
		glyphs=make([dynamic]alicorn.Text_Glyph, 0, 1),
		lines=make([dynamic]alicorn.Text_Line, 0, 1),
		width=30,
		height=10,
	}
	if ligature_err == nil {
		append(&ligature.glyphs, alicorn.Text_Glyph{cluster_start=0, cluster_end=3, x=0, x_advance=30, line_index=0})
		append(&ligature.lines, alicorn.Text_Line{glyph_start=0, glyph_end=1, byte_start=0, byte_end=3, width=30, height=10})
		ligature_caret := alicorn.text_run_caret_geometry(&ligature, alicorn.Text_Position{1, .Leading})
		expect(state, ligature_caret.valid && ligature_caret.rect.x == 10, "ligature caret must expose internal grapheme boundaries")
	}
	alicorn.text_run_destroy(&ligature)

	rtl_value, rtl_err := strings.clone("אב")
	rtl := alicorn.Text_Run{
		value=rtl_value,
		glyphs=make([dynamic]alicorn.Text_Glyph, 0, 2),
		lines=make([dynamic]alicorn.Text_Line, 0, 1),
		width=20,
		height=10,
	}
	if rtl_err == nil {
		// Runa gives the visual line order to consumers. The logical first
		// Hebrew cluster is therefore on the right-hand side here.
		append(&rtl.glyphs,
			alicorn.Text_Glyph{cluster_start=2, cluster_end=4, x=0, x_advance=10, line_index=0, level=1},
			alicorn.Text_Glyph{cluster_start=0, cluster_end=2, x=10, x_advance=10, line_index=0, level=1},
		)
		append(&rtl.lines, alicorn.Text_Line{glyph_start=0, glyph_end=2, byte_start=0, byte_end=4, width=20, height=10})
		rtl_caret := alicorn.text_run_caret_geometry(&rtl, alicorn.Text_Position{0, .Leading})
		expect(state, rtl_caret.valid && rtl_caret.rect.x == 20, "RTL caret leading edge must use visual glyph direction")
	}
	alicorn.text_run_destroy(&rtl)

	logical := alicorn.text_move_logical("Aé世😀", alicorn.Text_Position{len("Aé世😀"), .Leading}, -1)
	expect(state, logical.byte == len("Aé世"), "logical movement must step by grapheme rather than byte")
	visual := alicorn.text_run_move_visual(&run, alicorn.Text_Position{1, .Leading}, 1)
	expect(state, visual.byte == 2, "visual movement must advance to the next boundary on the line")
	visual = alicorn.text_run_move_visual(&run, alicorn.Text_Position{2, .Trailing}, 1)
	expect(state, visual.byte == 2, "visual movement at a wrapped line end must enter the next line deterministically")
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

test_runtime_edit_invalidates_text_product :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	id := render_text_field(&rt, "hello")
	node, found := rt.nodes[id]
	if found && node != nil {
		// Model the run that a configured text provider would have built. This
		// test deliberately does not depend on a host font being installed in
		// headless CI.
		node.text_run.value, _ = strings.clone("hello")
		node.text_run_valid = true
		old_generation := node.text_run_generation
		alicorn.set_text_caret(&rt, id, 3)
		change := alicorn.process_text_edit(&rt, id, alicorn.Text_Edit{.Backspace, ""})
		expect(state, change.changed && change.text == "helo", "runtime backspace must return the edited application value")
		expect(state, !node.text_run_valid, "runtime text mutation must invalidate the retained text run immediately")
		expect(state, node.text_run_generation > old_generation, "runtime text mutation must advance text-run generation")
		// Simulate the direct-style application echoing Text_Change.text on the
		// next frame. The retained identity survives, but the old run must not.
		render_text_field(&rt, change.text)
		expect(state, rt.nodes[id].text == "helo", "application echo must preserve the edited retained value")
		expect(state, !rt.nodes[id].text_run_valid, "application echo must not resurrect the previous text run")
		if len(change.text) > 0 { delete(change.text) }
	}
	alicorn.destroy_runtime(&rt)
}

render_gpu_surface :: proc(rt: ^alicorn.Runtime, show: bool, revision: u64) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test GPU surface description")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="surface-root")
	id: alicorn.Node_ID = 0
	if show {
		id = alicorn.gpu_surface_ex(&ui, "waveform", revision, alicorn.Rect{10, 12, 240, 80}, 480, 160, 2, S_SURFACE)
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return id
}

test_gpu_surface_contract :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160})
	id := render_gpu_surface(&rt, true, 0)
	ctx, ok := alicorn.gpu_surface_context(&rt, id)
	expect(state, ok, "GPU surface handle must resolve to an active retained node")
	expect(state, ok && ctx.logical_bounds.w == 240 && ctx.logical_bounds.h == 80, "surface context must retain laid-out logical bounds")
	expect(state, ok && ctx.pixel_width == 480 && ctx.pixel_height == 160 && ctx.dpi_scale == 2, "surface context must retain physical extent and DPI")
	expect(state, ok && ctx.clip.w == 240 && ctx.clip.h == 80, "surface context must expose an effective clip bounded to the surface")
	samples := []f32{0.1, 0.4, 0.8, 0.2}
	before := rt.stats
	expect(state, alicorn.gpu_surface_update(&rt, id, 1, samples[:]), "explicit surface revision update must succeed")
	expect(state, !rt.invalidated && alicorn.gpu_surface_needs_frame(&rt), "surface update must wake composition without invalidating the procedural root")
	expect(state, rt.nodes[id].surface_revision == 1 && len(rt.nodes[id].surface_samples) == 4 && rt.nodes[id].surface_samples[2] == 0.8, "surface samples must be copied into retained runtime storage")
	_, build := alicorn.begin_frame(&rt)
	expect(state, !build, "surface-only update must not execute the application description")
	expect(state, rt.stats.frames_built == before.frames_built && rt.stats.reconcile_nodes_visited == before.reconcile_nodes_visited && rt.stats.layout_nodes_visited == before.layout_nodes_visited && rt.stats.paint_nodes_visited == before.paint_nodes_visited, "surface-only update must leave ordinary frame work untouched")
	alicorn.gpu_surface_frame_consumed(&rt)
	expect(state, !alicorn.gpu_surface_needs_frame(&rt), "successful surface submission must consume the pending frame")
	// A later root wake with the same description must not roll back the
	// independently updated retained surface revision or its copied samples.
	render_gpu_surface(&rt, true, 0)
	expect(state, rt.nodes[id].surface_revision == 1 && len(rt.nodes[id].surface_samples) == 4, "root wake must preserve a newer explicit surface update")
	render_gpu_surface(&rt, true, 2)
	expect(state, rt.nodes[id].surface_revision == 2, "a changed surface description revision must replace a direct update")
	render_gpu_surface(&rt, false, 0)
	expect(state, !alicorn.gpu_surface_update(&rt, id, 2, samples[:]), "retired surface handles must reject updates")
	expect(state, rt.focused == 0 && len(rt.nodes) == 1, "surface removal must retire its retained node")
	alicorn.destroy_runtime(&rt)
}

test_runtime_allocator_ownership :: proc(state: ^Test_State) {
	base_allocator := context.allocator
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, base_allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	stats := alicorn.Runtime_Allocation_Stats{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120}, alicorn.Runtime_Config{
		persistent_allocator = base_allocator,
		scratch_backing_allocator = base_allocator,
		trace_capacity = 32,
		allocation_stats = &stats,
	})
	// Deliberately change the ambient allocator after construction. Runtime
	// allocations and destruction must continue through their captured owners.
	context.allocator = mem.tracking_allocator(&tracking)
	alicorn.invalidate_root(&rt, "allocator ownership test")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, label="allocator-root")
		alicorn.text(&ui, "retained allocation")
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, len(tracking.allocation_map) == 0, "runtime must not allocate through a later ambient allocator")
	expect(state, stats.persistent_alloc_calls > 0 && stats.persistent_requested_bytes_peak > 0, "persistent requested-byte telemetry must record retained work")
	expect(state, stats.scratch_alloc_calls > 0 && stats.scratch_requested_bytes_peak > 0, "scratch requested-byte telemetry must record frame work")
	expect(state, stats.scratch_resets > 0 && stats.scratch_requested_bytes_epoch > 0, "runtime-owned scratch arena must reset at the frame boundary")
	// Keep the changed ambient allocator active while destroying the runtime.
	alicorn.destroy_runtime(&rt)
	expect(state, len(tracking.allocation_map) == 0, "runtime destruction must release through the original allocator")
	expect(state, stats.persistent_requested_bytes_live == 0, "persistent requested-byte live total must return to zero")
	context.allocator = base_allocator
}

main :: proc() {
	state: Test_State
	test_identity_and_ambiguity(&state)
	test_typed_key_variants(&state)
	test_property_sequences(&state)
	test_regions_and_stages(&state)
	test_retained_subtree_reuse(&state)
	test_region_identity_sequences(&state)
	test_focus_and_editing(&state)
	test_unicode_editing(&state)
	test_text_input_composition(&state)
	test_interaction_paint_invalidation(&state)
	test_interaction_regressions(&state)
	test_disabled_button_semantics(&state)
	test_ergonomic_identity(&state)
	test_virtualization_and_gpu(&state)
	test_layout_geometry(&state)
	test_text_intrinsic_layout_invalidation(&state)
	test_container_paint_defaults(&state)
	test_presentation_invalidation(&state)
	test_text_geometry(&state)
	test_gpu_text_resource_boundary(&state)
	test_retained_text_product_lifetime(&state)
	test_runtime_edit_invalidates_text_product(&state)
	test_gpu_surface_contract(&state)
	test_runtime_allocator_ownership(&state)
	if state.failures == 0 {
		fmt.println("Alicorn foundation tests: PASS")
		return
	}
	fmt.println("Alicorn foundation tests: FAILURES", state.failures)
	os.exit(1)
}
