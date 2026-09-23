package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import alicorn "../runtime"
import runa "../third_party/Runa"

TEST_UI_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
TEST_MONO_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")

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

virtual_geometry_row :: proc(ui: ^alicorn.UI, index: int) {
	style := alicorn.Layout_Style{.Column, -1, 20, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}
	_, _ = alicorn.button_ex(ui, fmt.tprintf("row-%d", index), S_VROW, style=style)
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

render_virtual_geometry :: proc(rt: ^alicorn.Runtime, scroll: f32) -> map[string]alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test virtual geometry")
	ui, build := alicorn.begin_frame(rt)
	ids := make(map[string]alicorn.Node_ID)
	if !build { return ids }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="virtual-geometry-root")
	alicorn.virtual_list_ex(&ui, 100, scroll, 200, 20, S_VLIST, virtual_item_key, virtual_geometry_row)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Button && node.identity_key != "" {
			ids[node.identity_key] = id
		}
	}
	return ids
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

render_weighted_text :: proc(rt: ^alicorn.Runtime, weight: f32) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test retained font weight")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="weighted-text-root")
	id := alicorn.text(&ui, "Alicorn typography", text_style=alicorn.Text_Style{font_weight=weight})
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

render_keyboard_focus_order :: proc(rt: ^alicorn.Runtime) -> map[string]alicorn.Node_ID {
	ids := make(map[string]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "test keyboard focus order")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, label="keyboard-focus-root")
	ids["filter"] = alicorn.text_field(&ui, "", key=alicorn.key_string("filter"))
	alicorn.button(&ui, "Sort CPU", key=alicorn.key_string("sort-cpu"))
	alicorn.button(&ui, "Disabled", key=alicorn.key_string("disabled"), state=alicorn.Button_State{disabled=true})
	alicorn.button(&ui, "Pause", key=alicorn.key_string("pause"))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok {
			if node.kind == .Button { ids[node.label] = id }
		}
	}
	return ids
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

test_keyboard_focus_and_activation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 240})
	ids := render_keyboard_focus_order(&rt)
	expect(state, alicorn.focus_traverse(&rt, .Next) == ids["filter"], "Tab traversal must focus the first focusable node")
	expect(state, alicorn.focus_traverse(&rt, .Next) == ids["Sort CPU"], "Tab traversal must move to the next focusable node")
	expect(state, alicorn.focus_traverse(&rt, .Next) == ids["Pause"], "Tab traversal must skip disabled nodes")
	expect(state, alicorn.focus_traverse(&rt, .Next) == ids["filter"], "Tab traversal must wrap to the first focusable node")
	expect(state, alicorn.focus_traverse(&rt, .Previous) == ids["Pause"], "Shift-Tab traversal must wrap backward")
	expect(state, !alicorn.focus(&rt, ids["Disabled"]), "disabled nodes must not receive keyboard focus")

	rt.focused = 0
	button_id, _ := render_canonical_button(&rt)
	unfocused_color := rt.nodes[button_id].paint[0].color
	expect(state, alicorn.focus(&rt, button_id), "button must accept keyboard focus")
	expect(state, alicorn.activate_focused(&rt), "focused button must accept keyboard activation")
	_, clicked := render_canonical_button(&rt)
	expect(state, clicked, "focused button activation must reach the public button API")
	_, clicked = render_canonical_button(&rt)
	expect(state, !clicked, "focused button activation must be consumed exactly once")
	expect(state, rt.nodes[button_id].paint[0].color != unfocused_color, "focused button must have a visible paint state")
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

test_text_commands :: proc(state: ^Test_State) {
	value := "hello, world 42"
	word_left := alicorn.text_move_word(value, alicorn.Text_Position{len(value), .Trailing}, -1)
	expect(state, word_left.byte == len("hello, world "), "word-left must use Runa boundaries and skip separators")
	word_left = alicorn.text_move_word(value, word_left, -1)
	expect(state, word_left.byte == len("hello, "), "repeated word-left must reach the prior word start")
	word_right := alicorn.text_move_word(value, alicorn.Text_Position{0, .Leading}, 1)
	expect(state, word_right.byte == len("hello, "), "word-right must reach the next word start")
	word_right = alicorn.text_move_word(value, word_right, 1)
	expect(state, word_right.byte == len("hello, world "), "repeated word-right must skip punctuation and whitespace")
	preserved := alicorn.text_move_word("A👨‍👩‍👧", alicorn.Text_Position{2, .Trailing}, 0)
	expect(state, preserved.byte == 1 && preserved.affinity == .Trailing, "word movement must normalize to a grapheme boundary without losing affinity")

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	runtime_value := "hello, world"
	id := render_text_field(&rt, runtime_value)
	rt.invalidated = false
	expect(state, alicorn.set_text_caret(&rt, id, len(runtime_value)), "caret command target must be editable")
	expect(state, !rt.invalidated, "caret-only changes must not invalidate the application root")
	expect(state, alicorn.process_text_command(&rt, id, .Move_Word_Left).changed == false && rt.nodes[id].caret.byte == len("hello, "), "word-left command must move the retained caret")
	expect(state, alicorn.set_text_caret(&rt, id, len("hello, world")), "caret must move to a word end")
	change := alicorn.process_text_command(&rt, id, .Delete_Word_Backward)
	expect(state, change.changed && change.text == "hello, ", "word-backward deletion must remove one Runa word unit")
	if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
	render_text_field(&rt, "hello, ")
	expect(state, alicorn.set_text_caret(&rt, id, len("hello, ")), "caret must remain usable after a mutation")
	change = alicorn.process_text_command(&rt, id, .Delete_Word_Backward)
	expect(state, change.changed && change.text == "", "word-backward deletion must remove the prior word and separators")
	if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
	rt.invalidated = false
	expect(state, alicorn.set_text_selection(&rt, id, 0, 0), "selection setter must accept an empty range")
	expect(state, !rt.invalidated, "selection-only changes must not invalidate the application root")
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
	ready: bool
	ui, ready = alicorn.begin_presentation_frame(&rt)
	if ready { alicorn.end_presentation_frame(&ui) }
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

test_structure_layout_invalidation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 200})
	empty_values := []int{}
	first := render_keyed(&rt, []string{"a", "b", "c"}, empty_values, false, false)
	expect(state, rt.nodes[first["a"]].bounds.y == 0 && rt.nodes[first["b"]].bounds.y == 24 && rt.nodes[first["c"]].bounds.y == 48, "initial keyed rows must be laid out in declaration order")

	reordered := render_keyed(&rt, []string{"c", "a", "b"}, empty_values, false, false)
	expect(state, rt.nodes[reordered["c"]].bounds.y == 0 && rt.nodes[reordered["a"]].bounds.y == 24 && rt.nodes[reordered["b"]].bounds.y == 48, "reordering children must recompute retained geometry")
	hit := alicorn.hit_test(&rt, rt.nodes[reordered["c"]].bounds.x+4, rt.nodes[reordered["c"]].bounds.y+12)
	expect(state, hit == reordered["c"], "hit testing must follow reordered child geometry")

	removed := render_keyed(&rt, []string{"c", "b"}, empty_values, false, false)
	expect(state, rt.nodes[removed["c"]].bounds.y == 0 && rt.nodes[removed["b"]].bounds.y == 24, "removing a child must close the retained layout gap")
	expect(state, alicorn.hit_test(&rt, rt.nodes[removed["b"]].bounds.x+4, rt.nodes[removed["b"]].bounds.y+12) == removed["b"], "hit testing must follow removal-adjusted geometry")
	expect(state, alicorn.hit_test(&rt, 4, 60) == 0, "removed child must not remain hit-testable at its old position")
	alicorn.destroy_runtime(&rt)
}

test_virtualization_and_gpu :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 600})
	metrics := alicorn.virtual_list_metrics(100, 12.5, 100, 20)
	expect(state, metrics.first == 0 && metrics.last == 6, "virtual metrics include the partially visible leading row")
	expect(state, metrics.offset_y == 12.5 && metrics.max_scroll_y == 1900, "virtual metrics preserve fractional scroll and use the real viewport")
	expect(state, metrics.leading_offset_y == 12.5, "virtual metrics expose the residual leading offset")
	clamped_metrics := alicorn.virtual_list_metrics(100, 9999, 100, 20)
	expect(state, clamped_metrics.offset_y == clamped_metrics.max_scroll_y && clamped_metrics.first == 95 && clamped_metrics.leading_offset_y == 0, "virtual metrics clamp to the content end")
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
	geometry_scrolls := []f32{0, 12, 24, 240, 1800}
	for scroll in geometry_scrolls {
		geometry_ids := render_virtual_geometry(&rt, scroll)
		geometry := alicorn.virtual_list_metrics(100, scroll, 200, 20)
		list_id := alicorn.Node_ID(0)
		for id in rt.order {
			if node, ok := rt.nodes[id]; ok && node.kind == .Virtual_List {
				list_id = id
				break
			}
		}
		list := rt.nodes[list_id]
		first_id := geometry_ids[fmt.tprintf("item-%d", geometry.first)]
		expect(state, rt.nodes[first_id].bounds.y == list.bounds.y-geometry.leading_offset_y, fmt.tprintf("virtual first row position at scroll %.1f", scroll))
		hit_index := geometry.first+1
		hit_id := geometry_ids[fmt.tprintf("item-%d", hit_index)]
		hit_y := rt.nodes[hit_id].bounds.y + 10
		expect(state, alicorn.hit_test(&rt, list.bounds.x+4, hit_y) == hit_id, fmt.tprintf("virtual hit testing at scroll %.1f", scroll))
	}
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

test_presentation_submission_lifecycle :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	render_single_button(&rt)
	first_revision := rt.presentation_revision
	expect(state, first_revision != rt.submitted_revision, "a reconciled display must remain pending until native submission succeeds")
	expect(state, alicorn.frame_needs_submission(&rt), "a reconciled display must request its first submission")

	// Simulate a swapchain acquisition that returns no drawable texture. The
	// host must leave the revision pending so its next loop iteration retries.
	expect(state, alicorn.frame_needs_submission(&rt), "an unavailable initial swapchain must leave the surface-less display pending")
	alicorn.frame_submission_succeeded(&rt)
	expect(state, !alicorn.frame_needs_submission(&rt), "successful submission must consume the retained display revision")
	alicorn.invalidate_root(&rt, "submission retry test")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="retry-root")
		alicorn.text_ex(&ui, "updated", S_EXTRA)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	second_revision := rt.presentation_revision
	expect(state, second_revision != first_revision, "a later retained rebuild must advance the presentation revision")
	expect(state, alicorn.frame_needs_submission(&rt), "a later retained rebuild must remain pending")
	expect(state, alicorn.frame_needs_submission(&rt), "an unavailable swapchain must not consume pending work")
	alicorn.frame_submission_succeeded(&rt)
	expect(state, !alicorn.frame_needs_submission(&rt), "the retry must clear pending work only after submission")

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

test_multiline_text_controls :: proc(state: ^Test_State) {
	engine := alicorn.new_text_engine("multiline-test", allocator=context.allocator)
	defer alicorn.text_engine_destroy(&engine)
	expect(state, alicorn.text_engine_load_font(&engine, TEST_UI_FONT_DATA), "bundled UI font must load for multiline regression")
	run, ok := alicorn.text_run_build(
		&engine,
		"first\nsecond",
		16,
		allocator=context.allocator,
		scratch_allocator=context.temp_allocator,
	)
	if !ok {
		expect(state, false, "multiline text must shape successfully")
		return
	}
	defer alicorn.text_run_destroy(&run)
	expect(state, len(run.lines) >= 2, "newline must advance to a second text line")
	newline_glyph := false
	for glyph in run.glyphs {
		if glyph.cluster_start == 5 { newline_glyph = true; break }
	}
	expect(state, !newline_glyph, "newline must not produce a visible missing-glyph box")
	if len(run.lines) >= 2 {
		expect(state, run.lines[1].y > run.lines[0].y, "newline line geometry must advance vertically")
	}

	tab_run, tab_ok := alicorn.text_run_build(
		&engine,
		"A\tB",
		16,
		allocator=context.allocator,
		scratch_allocator=context.temp_allocator,
	)
	if !tab_ok {
		expect(state, false, "tab text must shape successfully")
		return
	}
	defer alicorn.text_run_destroy(&tab_run)
	expect(state, tab_run.value == "A\tB", "control normalization must preserve the original source bytes")
	tab_index := -1
	a_index := -1
	b_index := -1
	for glyph, i in tab_run.glyphs {
		if glyph.cluster_start == 0 { a_index = i }
		if glyph.cluster_start == 1 && glyph.cluster_end == 2 {
			tab_index = i
			expect(state, glyph.control_advance, "tab must be retained as non-rendering advance geometry")
		}
		if glyph.cluster_start == 2 { b_index = i }
	}
	expect(state, a_index >= 0 && tab_index >= 0 && b_index >= 0, "tab and surrounding glyphs must map to their original UTF-8 byte positions")
	if a_index >= 0 && tab_index >= 0 && b_index >= 0 {
		tab := tab_run.glyphs[tab_index]
		b := tab_run.glyphs[b_index]
		expect(state, tab.x == tab_run.glyphs[a_index].x+tab_run.glyphs[a_index].x_advance, "tab begins at the preceding text advance")
		expect(state, b.x == tab.x+tab.x_advance, "following text begins after the tab-stop advance")
		expect(state, b.x > tab.x, "tab must advance to the next four-space stop")
		caret_before := alicorn.text_run_caret_geometry(&tab_run, alicorn.Text_Position{1, .Leading})
		caret_after := alicorn.text_run_caret_geometry(&tab_run, alicorn.Text_Position{2, .Leading})
		expect(state, caret_before.valid && caret_after.valid && caret_after.rect.x == b.x, "tab source-byte caret positions must span the tab advance")
		tab_selection := alicorn.text_run_selection_rects(&tab_run, alicorn.Text_Position{1, .Leading}, alicorn.Text_Position{2, .Trailing})
		if len(tab_selection) == 1 {
			selection_delta := tab_selection[0].rect.w-tab.x_advance
			if selection_delta < 0 { selection_delta = -selection_delta }
			expect(state, selection_delta < 0.01, "tab selection geometry must cover the tab advance")
		} else {
			expect(state, false, "selecting a tab must produce its visible advance rectangle")
		}
		delete(tab_selection)
		hit := alicorn.text_run_hit_test(&tab_run, tab.x+tab.x_advance*0.75, 0)
		expect(state, hit.byte == 2, "hit testing inside the tab advance must resolve to its trailing source boundary")
	}
	space_stop_width: f32 = 0
	space_run, space_ok := alicorn.text_run_build(&engine, " ", 16, allocator=context.allocator)
	if space_ok {
		defer alicorn.text_run_destroy(&space_run)
		if a_index >= 0 && b_index >= 0 && len(space_run.glyphs) == 1 {
			space_stop := space_run.glyphs[0].x_advance * f32(alicorn.TEXT_TAB_WIDTH_SPACES)
			space_stop_width = space_stop
			line_x := tab_run.glyphs[a_index].x_advance
			next_stop := f32(int(line_x/space_stop)+1) * space_stop
			delta := tab_run.glyphs[b_index].x-next_stop
			if delta < 0 { delta = -delta }
			expect(state, delta < 0.01, "tab must place following text at the next four-space tab stop")
		}
	} else {
		expect(state, false, "space metrics must shape for tab-stop verification")
	}
	metric_width, _, _, metrics_ok := alicorn.text_layout(&engine, "A\tB", 16)
	if metrics_ok {
		delta := metric_width-tab_run.width
		if delta < 0 { delta = -delta }
		expect(state, delta < 0.01, "measurement-only layout must use the same tab stops as retained text runs")
	} else {
		expect(state, false, "tab text metrics must shape successfully")
	}

	repeated_tabs := "foo\t\tbar"
	repeated_run, repeated_ok := alicorn.text_run_build(&engine, repeated_tabs, 16, allocator=context.allocator)
	if repeated_ok {
		defer alicorn.text_run_destroy(&repeated_run)
		expect(state, repeated_run.value == repeated_tabs, "repeated tabs must preserve source bytes")
		tab_advances := 0
		second_tab_advance: f32 = 0
		for glyph in repeated_run.glyphs {
			if glyph.control_advance {
				tab_advances += 1
				if tab_advances == 2 { second_tab_advance = glyph.x_advance }
			}
		}
		expect(state, tab_advances == 2, "each repeated tab must produce non-rendering geometry")
		if space_stop_width > 0 {
			delta := second_tab_advance-space_stop_width
			if delta < 0 { delta = -delta }
			expect(state, delta < 0.01, "a tab beginning on a stop must advance to the following stop")
		}
	} else {
		expect(state, false, "repeated tabs must shape successfully")
	}

	mixed_breaks := "a\r\nb\rc\nd"
	break_run, breaks_ok := alicorn.text_run_build(
		&engine,
		mixed_breaks,
		16,
		allocator=context.allocator,
		scratch_allocator=context.temp_allocator,
	)
	if !breaks_ok {
		expect(state, false, "CR, CRLF, and LF text must shape successfully")
		return
	}
	defer alicorn.text_run_destroy(&break_run)
	expect(state, break_run.value == mixed_breaks, "line-break normalization must preserve the original CR and LF bytes")
	expect(state, len(break_run.lines) == 4, "CR, CRLF, and LF must each produce one line break")
	if len(break_run.lines) == 4 {
		expect(state, break_run.lines[1].byte_start == 3, "CRLF must map the second line to its original byte offset")
		expect(state, break_run.lines[2].byte_start == 5, "CR must map the third line to its original byte offset")
		expect(state, break_run.lines[3].byte_start == 7, "LF must map the fourth line to its original byte offset")
	}

	controls := "A\x01B\x7fC"
	control_run, controls_ok := alicorn.text_run_build(
		&engine,
		controls,
		16,
		allocator=context.allocator,
		scratch_allocator=context.temp_allocator,
	)
	if !controls_ok {
		expect(state, false, "unsupported C0 controls must be normalized before shaping")
		return
	}
	defer alicorn.text_run_destroy(&control_run)
	expect(state, control_run.value == controls, "C0 control handling must preserve application text")
	control_advances := 0
	for glyph in control_run.glyphs {
		if glyph.control_advance { control_advances += 1 }
	}
	expect(state, control_advances == 2, "unsupported C0 controls must become non-rendering advances")
	for glyph in control_run.glyphs {
		if glyph.cluster_start == 1 || glyph.cluster_start == 3 {
			expect(state, glyph.control_advance, "C0 source positions must map to the non-rendering advances")
		}
	}
	c1_bytes := make([]u8, 4, context.allocator)
	c1_bytes[0], c1_bytes[1], c1_bytes[2], c1_bytes[3] = 'A', 0xc2, 0x85, 'B'
	c1_controls := string(c1_bytes)
	defer delete(c1_bytes, context.allocator)
	c1_run, c1_ok := alicorn.text_run_build(&engine, c1_controls, 16, allocator=context.allocator)
	if c1_ok {
		defer alicorn.text_run_destroy(&c1_run)
		expect(state, c1_run.value == c1_controls, "C1 control normalization must preserve source bytes")
		c1_advance := false
		for glyph in c1_run.glyphs {
			if glyph.cluster_start == 1 && glyph.cluster_end == 3 { c1_advance = glyph.control_advance }
		}
		expect(state, c1_advance, "C1 controls must become non-rendering advances")
	} else {
		expect(state, false, "C1 controls must normalize before shaping")
	}
}

test_text_ellipsis :: proc(state: ^Test_State) {
	engine := alicorn.new_text_engine("ellipsis-test", allocator=context.allocator)
	defer alicorn.text_engine_destroy(&engine)
	expect(state, alicorn.text_engine_load_font(&engine, TEST_UI_FONT_DATA), "bundled UI font must load for ellipsis regression")
	source := "origin/port/macos-history-6ca8c47"
	full, full_ok := alicorn.text_run_build(&engine, source, 16, overflow=.Clip, allocator=context.allocator)
	if !full_ok {
		expect(state, false, "single-line source text must shape")
		return
	}
	width := full.width * 0.62
	alicorn.text_run_destroy(&full)
	run, ok := alicorn.text_run_build_with_overflow(
		&engine, source, 16, width,
		context.allocator, context.temp_allocator,
		.UI, alicorn.FONT_WEIGHT_REGULAR, .Ellipsis,
	)
	if !ok {
		expect(state, false, "ellipsized text must shape successfully")
		return
	}
	defer alicorn.text_run_destroy(&run)
	expect(state, len(run.lines) == 1, "ellipsis overflow must remain single-line")
	expect(state, run.value != source && strings.has_suffix(run.value, "…"), "overflowed text must end with an ellipsis")
	expect(state, run.source_value_override && run.source_value == source, "ellipsized run must retain the original source value for invalidation")
	expect(state, run.width <= width, "ellipsized text width must fit its assigned logical width")

	unicode_source := "feature/👩‍💻-implementation-with-a-long-name"
	unicode_full, unicode_full_ok := alicorn.text_run_build(&engine, unicode_source, 16, overflow=.Clip, allocator=context.allocator)
	if !unicode_full_ok {
		expect(state, false, "Unicode source text must shape")
		return
	}
	unicode_width := unicode_full.width * 0.56
	alicorn.text_run_destroy(&unicode_full)
	unicode_run, unicode_ok := alicorn.text_run_build_with_overflow(
		&engine, unicode_source, 16, unicode_width,
		context.allocator, context.temp_allocator,
		.UI, alicorn.FONT_WEIGHT_REGULAR, .Ellipsis,
	)
	if !unicode_ok {
		expect(state, false, "Unicode ellipsis must shape successfully")
		return
	}
	defer alicorn.text_run_destroy(&unicode_run)
	if strings.has_suffix(unicode_run.value, "…") {
		prefix_length := len(unicode_run.value)-len("…")
		expect(state, alicorn.grapheme_floor_boundary(unicode_source, prefix_length) == prefix_length, "ellipsis must not split an extended grapheme cluster")
	} else {
		expect(state, false, "Unicode ellipsis must retain the terminal ellipsis")
	}
}

test_monospace_font_role :: proc(state: ^Test_State) {
	engine := alicorn.new_text_engine("font-role-test", allocator=context.allocator)
	defer alicorn.text_engine_destroy(&engine)
	expect(state, alicorn.text_engine_load_font(&engine, TEST_UI_FONT_DATA), "bundled UI font role must load")
	mono_loaded := alicorn.text_engine_load_font_role(&engine, .Monospace, TEST_MONO_FONT_DATA)
	expect(state, mono_loaded, "bundled monospace font role must load")
	ui_axes := runa.font_axes(&engine.font)
	mono_axes := runa.font_axes(&engine.monospace_font)
	expect(state, len(ui_axes) > 0, "bundled UI font must expose its variable axes")
	expect(state, len(mono_axes) > 0, "bundled monospace font must expose its variable axes")
	weight_axis_found := false
	for axis in ui_axes {
		if axis.tag == runa.Axis_Tag(0x77676874) {
			weight_axis_found = true
			expect(state, axis.min_value <= alicorn.FONT_WEIGHT_REGULAR && axis.max_value >= alicorn.FONT_WEIGHT_SEMIBOLD, "UI wght axis must cover regular through semibold")
		}
	}
	expect(state, weight_axis_found, "bundled UI face must expose the OpenType wght axis")
	ui_run, ui_ok := alicorn.text_run_build(&engine, "iW", 16, allocator=context.allocator, font_role=.UI)
	mono_run, mono_ok := alicorn.text_run_build(&engine, "iW", 16, allocator=context.allocator, font_role=.Monospace)
	defer {
		if ui_ok { alicorn.text_run_destroy(&ui_run) }
		if mono_ok { alicorn.text_run_destroy(&mono_run) }
	}
	expect(state, ui_ok && mono_ok, "both font roles must shape text")
	if ui_ok && mono_ok && len(ui_run.glyphs) == 2 && len(mono_run.glyphs) == 2 {
		ui_delta := ui_run.glyphs[0].x_advance-ui_run.glyphs[1].x_advance
		mono_delta := mono_run.glyphs[0].x_advance-mono_run.glyphs[1].x_advance
		if ui_delta < 0 { ui_delta = -ui_delta }
		if mono_delta < 0 { mono_delta = -mono_delta }
		expect(state, ui_run.font == .UI && mono_run.font == .Monospace, "text runs must retain the selected font role")
		expect(state, ui_delta > 0.1, "UI font should retain proportional glyph advances")
		expect(state, mono_delta < 0.1, "bundled monospace role should use equal advances for i and W")
	}
	regular_run, regular_ok := alicorn.text_run_build(&engine, "Alicorn", 18, allocator=context.allocator, font_weight=alicorn.FONT_WEIGHT_REGULAR)
	semibold_run, semibold_ok := alicorn.text_run_build(&engine, "Alicorn", 18, allocator=context.allocator, font_weight=alicorn.FONT_WEIGHT_SEMIBOLD)
	defer {
		if regular_ok { alicorn.text_run_destroy(&regular_run) }
		if semibold_ok { alicorn.text_run_destroy(&semibold_run) }
	}
	expect(state, regular_ok && semibold_ok, "regular and semibold text runs must shape")
	if regular_ok && semibold_ok {
		expect(state, regular_run.font_weight == alicorn.FONT_WEIGHT_REGULAR, "regular run must retain its selected weight")
		expect(state, semibold_run.font_weight == alicorn.FONT_WEIGHT_SEMIBOLD, "semibold run must retain its selected weight")
	}
	font_weight_glyph := runa.font_lookup_glyph(&engine.font, 'A')
	runa.font_reset_variations(&engine.font)
	regular_outline: runa.Outline
	semibold_outline: runa.Outline
	defer runa.outline_destroy(&regular_outline)
	defer runa.outline_destroy(&semibold_outline)
	regular_axis_err := runa.font_set_variation(&engine.font, runa.Axis_Tag(0x77676874), alicorn.FONT_WEIGHT_REGULAR)
	regular_outline_err := runa.font_glyph_outline(&engine.font, font_weight_glyph, &regular_outline)
	runa.font_reset_variations(&engine.font)
	semibold_axis_err := runa.font_set_variation(&engine.font, runa.Axis_Tag(0x77676874), alicorn.FONT_WEIGHT_SEMIBOLD)
	semibold_outline_err := runa.font_glyph_outline(&engine.font, font_weight_glyph, &semibold_outline)
	runa.font_reset_variations(&engine.font)
	outline_weight_differs := false
	if regular_outline_err == .None && semibold_outline_err == .None && len(regular_outline.points) == len(semibold_outline.points) {
		for point, i in regular_outline.points {
			if point != semibold_outline.points[i] { outline_weight_differs = true; break }
		}
	}
	expect(state, regular_axis_err == .None && semibold_axis_err == .None && outline_weight_differs, "wght axis must produce a distinct semibold outline")
	glyph_cache_before := engine.glyph_cache_misses
	_, _, regular_glyph_ok := alicorn.text_engine_glyph(&engine, font_weight_glyph, 18, font_weight=alicorn.FONT_WEIGHT_REGULAR)
	_, _, semibold_glyph_ok := alicorn.text_engine_glyph(&engine, font_weight_glyph, 18, font_weight=alicorn.FONT_WEIGHT_SEMIBOLD)
	expect(state, regular_glyph_ok && semibold_glyph_ok, "regular and semibold glyphs must rasterize")
	expect(state, engine.glyph_cache_misses >= glyph_cache_before+2, "glyph cache identity must distinguish font weights")
	fallback_generation := engine.font_generation
	fallback_loaded := alicorn.text_engine_load_fallback_font_role(&engine, .UI, TEST_MONO_FONT_DATA)
	expect(state, fallback_loaded && engine.fallback_font_loaded, "optional UI fallback face must load and remain independently owned")
	expect(state, engine.font_generation > fallback_generation, "loading a fallback face must invalidate retained font resources")
}

test_public_monospace_font_role :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="font-role-root")
		id := alicorn.text(&ui, "source", font=.Monospace)
		field_id := alicorn.text_field(&ui, "editable source", font=.Monospace)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		node, found := rt.nodes[id]
		expect(state, found && node != nil && node.font == .Monospace, "public text API must retain the requested monospace role")
		field, field_found := rt.nodes[field_id]
		expect(state, field_found && field != nil && field.font == .Monospace, "public text-field API must retain the requested monospace role")
	} else {
		expect(state, false, "font-role description frame must build")
	}
	alicorn.destroy_runtime(&rt)
}

test_retained_text_weight :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	expect(state, alicorn.text_engine_load_font(&rt.text_engine, TEST_UI_FONT_DATA), "retained-weight test font must load")
	regular_id := render_weighted_text(&rt, alicorn.FONT_WEIGHT_REGULAR)
	regular_node, regular_found := rt.nodes[regular_id]
	expect(state, regular_found && regular_node != nil && regular_node.text_run_valid, "regular text style must create a retained text product")
	regular_layout_hash := regular_node.layout_hash if regular_found && regular_node != nil else 0
	regular_run_generation := regular_node.text_run_generation if regular_found && regular_node != nil else 0
	semibold_id := render_weighted_text(&rt, alicorn.FONT_WEIGHT_SEMIBOLD)
	semibold_node, semibold_found := rt.nodes[semibold_id]
	expect(state, semibold_id == regular_id, "changing weight must preserve retained text identity")
	expect(state, semibold_found && semibold_node != nil && semibold_node.text_style.font_weight == alicorn.FONT_WEIGHT_SEMIBOLD, "retained node must adopt its new typography style")
	if semibold_found && semibold_node != nil {
		expect(state, semibold_node.text_run_valid && semibold_node.text_run.font_weight == alicorn.FONT_WEIGHT_SEMIBOLD, "weight changes must rebuild the text product with the selected instance")
		expect(state, semibold_node.layout_hash != regular_layout_hash, "weight changes must invalidate intrinsic layout")
		expect(state, semibold_node.text_run_generation > regular_run_generation, "weight changes must advance retained text generation")
	}
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

render_geometry_surface :: proc(rt: ^alicorn.Runtime, show: bool, revision: u64) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "test retained geometry surface description")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin_ex(&ui, .Root, S_ROOT, label="geometry-root")
	id: alicorn.Node_ID = 0
	if show {
		id = alicorn.gpu_geometry_surface(
			&ui,
			"dag",
			revision,
			alicorn.layout_style(grow=1, clip=true),
			2,
		)
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
	alicorn.frame_submission_succeeded(&rt)
	expect(state, !alicorn.frame_needs_submission(&rt), "initial surface description must be acknowledged only after a successful submission")
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
	alicorn.frame_submission_succeeded(&rt)
	expect(state, !alicorn.frame_needs_submission(&rt), "successful surface submission must acknowledge the presentation revision")
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

test_gpu_geometry_surface_contract :: proc(state: ^Test_State) {
	stats := alicorn.Runtime_Allocation_Stats{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160}, alicorn.Runtime_Config{
		persistent_allocator = context.allocator,
		scratch_backing_allocator = context.allocator,
		trace_capacity = 32,
		allocation_stats = &stats,
	})
	id := render_geometry_surface(&rt, true, 0)
	ctx, ok := alicorn.gpu_surface_context(&rt, id)
	expect(state, ok && ctx.logical_bounds.w == 320 && ctx.logical_bounds.h == 160, "geometry surface bounds must come from flex layout")
	expect(state, ok && ctx.pixel_width == 640 && ctx.pixel_height == 320 && ctx.dpi_scale == 2, "geometry surface pixel extent must derive from resolved layout bounds and DPI")
	expect(state, ok && ctx.clip.w == 320 && ctx.clip.h == 160, "geometry surface must expose Alicorn's effective layout clip")

	segments := [1]alicorn.GPU_Surface_Line_Segment{{
		start={4, 6}, end={44, 26}, thickness=2, color={0.2, 0.8, 1, 1},
	}}
	circles := [1]alicorn.GPU_Surface_Filled_Circle{{center={44, 26}, radius=5, color={1, 0.4, 0.1, 1}}}
	expect(state, alicorn.gpu_surface_update_geometry(&rt, id, 1, segments[:], circles[:]), "revisioned retained geometry update must succeed")
	node := rt.nodes[id]
	expect(state, node.surface_geometry_active && node.surface_revision == 1, "geometry update must switch the retained payload and revision")
	expect(state, len(node.surface_segments) == 1 && len(node.surface_circles) == 1, "typed segments and circles must be retained")
	segments[0].start.x = 999
	circles[0].radius = 999
	expect(state, node.surface_segments[0].start.x == 4 && node.surface_circles[0].radius == 5, "runtime must copy geometry instead of retaining application slices")
	expect(state, !alicorn.gpu_surface_update_geometry(&rt, id, 1, segments[:], circles[:]), "equal geometry revisions must be rejected")
	expect(state, alicorn.gpu_surface_needs_frame(&rt), "geometry update must request presentation")
	updates_before := rt.stats.surface_geometry_updates
	too_many: [1366]alicorn.GPU_Surface_Line_Segment
	expect(state, !alicorn.gpu_surface_update_geometry(&rt, id, 2, too_many[:], nil), "geometry exceeding the shared 8192-vertex budget must be rejected")
	expect(state, rt.stats.surface_geometry_overflow_rejections == 1 && rt.stats.surface_geometry_updates == updates_before, "overflow rejection must be observable without counting as an update")
	expect(state, node.surface_revision == 1 && len(node.surface_segments) == 1 && len(node.surface_circles) == 1, "overflow rejection must preserve the prior complete geometry revision")
	invalid := [1]alicorn.GPU_Surface_Line_Segment{{start={0, 0}, end={1, 1}, thickness=0, color={1, 1, 1, 1}}}
	expect(state, !alicorn.gpu_surface_update_geometry(&rt, id, 2, invalid[:], nil), "non-positive segment thickness must be rejected")
	expect(state, node.surface_revision == 1, "invalid geometry must not advance or replace the retained revision")

	max_segments: [1365]alicorn.GPU_Surface_Line_Segment
	for &segment, i in max_segments {
		segment = alicorn.GPU_Surface_Line_Segment{start={f32(i), 0}, end={f32(i), 1}, thickness=1, color={0.5, 0.5, 0.5, 1}}
	}
	expect(state, alicorn.gpu_surface_update_geometry(&rt, id, 2, max_segments[:], nil), "geometry fitting the exact public primitive budget must be accepted")
	expect(state, len(node.surface_segments) == 1365 && len(node.surface_circles) == 0, "accepted capacity-boundary geometry must remain complete")
	expect(state, !alicorn.gpu_surface_update_geometry(&rt, id, 3, max_segments[:], circles[:]), "circle tessellation vertices must be included in overflow checks")
	expect(state, rt.stats.surface_geometry_overflow_rejections == 2 && node.surface_revision == 2 && len(node.surface_segments) == 1365, "circle overflow must preserve the complete prior geometry")
	live_with_geometry := stats.persistent_requested_bytes_live

	// The original description revision is unchanged, so a procedural root wake
	// must not erase the explicit geometry update.
	render_geometry_surface(&rt, true, 0)
	expect(state, node.surface_geometry_active && node.surface_revision == 2 && len(node.surface_segments) == 1365, "same description revision must preserve explicit geometry data")
	// A new description revision is an authoritative replacement and clears old
	// direct-update payloads while keeping the retained geometry surface kind.
	render_geometry_surface(&rt, true, 2)
	expect(state, node.surface_revision == 2 && node.surface_geometry_active && len(node.surface_segments) == 0, "new surface description revision must clear stale geometry payload")
	render_geometry_surface(&rt, false, 0)
	expect(state, !alicorn.gpu_surface_update_geometry(&rt, id, 3, nil, nil), "retired geometry handles must reject updates")
	expect(state, len(rt.nodes) == 1, "geometry removal must retire the retained node and its arrays")
	expect(state, stats.persistent_requested_bytes_live < live_with_geometry, "retiring the surface must release retained segment/circle storage")
	alicorn.destroy_runtime(&rt)
	expect(state, stats.persistent_requested_bytes_live == 0, "runtime destruction must release all retained geometry storage")
}

test_retained_scroll_region :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "scroll region test")
	ui, build := alicorn.begin_frame(&rt)
	expect(state, build, "scroll region test builds an initial description")
	if build {
		alicorn.container_begin(&ui, .Root, label="scroll-root")
		region := alicorn.scroll_region_begin(&ui, key=alicorn.key_string("items"), viewport_height=60, content_height=400, line_height=20, style=alicorn.Layout_Style{.Column, -1, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, true})
		metrics := alicorn.virtual_list_metrics(20, region.offset_y, region.viewport_height, 20)
		alicorn.container_begin(&ui, .Virtual_List, label="items", style=alicorn.Layout_Style{.Column, -1, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}, scroll_offset_y=metrics.offset_y, layout_scroll_offset_y=metrics.leading_offset_y)
		for i := metrics.first; i < metrics.last; i += 1 {
			_ = alicorn.button(&ui, fmt.tprintf("item %d", i), key=alicorn.key_u64(u64(i)), style=alicorn.Layout_Style{.Row, -1, 20, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
		}
		alicorn.container_end(&ui)
		alicorn.scroll_region_end(&ui)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	region_id: alicorn.Node_ID = 0
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region { region_id = id; break }
	}
	expect(state, region_id != 0, "scroll region retains a stable node")
	if region_id != 0 {
		node := rt.nodes[region_id]
		handled_precise := alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_y=-0.1, ticks_y=-1, x=node.bounds.x+4, y=node.bounds.y+4})
		expect(state, handled_precise, "precise wheel input is claimed by the retained region")
		expect(state, alicorn.scroll_region_offset(&rt, region_id) == 2, "precise delta remains authoritative over accumulated ticks")
		_ = alicorn.scroll_region_set_offset(&rt, region_id, 0)
		handled := alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_y=-1, x=node.bounds.x+4, y=node.bounds.y+4})
		expect(state, handled, "wheel input is claimed by the retained region under the pointer")
		expect(state, alicorn.scroll_region_offset(&rt, region_id) == 20, "wheel input advances the region by its line height")
	}
}

render_high_level_virtual_list :: proc(rt: ^alicorn.Runtime, keys: []u64) -> (list_id: alicorn.Node_ID, ids: map[u64]alicorn.Node_ID) {
	ids = make(map[u64]alicorn.Node_ID)
	alicorn.invalidate_root(rt, "high-level virtual list test")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="high-level-list-root", style=alicorn.layout_style(clip=true))
	list := alicorn.virtual_list_begin(
		&ui,
		len(keys),
		20,
		key=alicorn.key_string("items"),
		style=alicorn.layout_style(height=60),
	)
	list_id = list.scroll.id
	for position := list.first; position < list.last; position += 1 {
		key := keys[position]
		if alicorn.component_begin(&ui, alicorn.key_u64(key)) {
			ids[key] = alicorn.text(&ui, fmt.tprintf("item %d", key), style=alicorn.layout_style(height=20))
			alicorn.component_end(&ui)
		}
	}
	alicorn.virtual_list_end(&ui, list)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

test_high_level_virtual_list_and_style_defaults :: proc(state: ^Test_State) {
	style := alicorn.layout_style(.Row, width=100, height=30, grow=1, padding=4, gap=8, clip=true)
	expect(state, style.direction == .Row && style.width == 100 && style.height == 30, "layout_style names the ordinary row dimensions")
	expect(state, style.min_width == 0 && style.max_width == -1 && style.min_height == 0 && style.max_height == -1, "layout_style preserves default constraints")
	expect(state, style.grow == 1 && style.padding == 4 && style.gap == 8 && style.align == .Stretch && style.clip, "layout_style preserves named layout behavior")

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	keys_a := []u64{10, 20, 30, 40, 50, 60, 70, 80}
	_, ids_a := render_high_level_virtual_list(&rt, keys_a)
	list_id := alicorn.Node_ID(0)
	for id, node in rt.nodes {
		if node.kind == .Scroll_Region && node.label == "virtual-list" { list_id = id; break }
	}
	expect(state, list_id != 0, "high-level virtual list retains a scroll region")
	expect(state, len(ids_a) <= 4, "high-level virtual list realizes only the visible row frontier")
	if list_id != 0 {
		node := rt.nodes[list_id]
		expect(state, node.scroll_content_height == 160 && node.scroll_viewport_height == 60, "high-level virtual list owns content and viewport geometry")
		content_id := alicorn.Node_ID(0)
		for id, child in rt.nodes {
			if child.parent == list_id && child.kind == .Virtual_List { content_id = id; break }
		}
		expect(state, content_id != 0, "high-level virtual list retains its content viewport")
		if content_id != 0 {
			content := rt.nodes[content_id]
			expect(state, content.bounds.h == node.scroll_viewport_height, "virtual content height matches the resolved viewport")
			expect(state, content.clip.h == node.scroll_viewport_height, "virtual content clip covers the resolved viewport")
		}
		if text_id, ok := ids_a[u64(10)]; ok {
			row := rt.nodes[text_id]
			expect(state, row.bounds.h == 20, "fixed-height virtual row keeps its requested height")
			expect(state, row.clip.h == node.scroll_viewport_height, "virtual row clip is not reduced to the intrinsic fallback height")
		}
		expect(state, alicorn.virtual_list_ensure_visible(&rt, list_id, 6), "high-level virtual list can ensure a logical row is visible")
		expect(state, alicorn.scroll_region_offset(&rt, list_id) == 80, "ensure-visible uses retained row geometry")
	}
	keys_b := []u64{40, 30, 20, 10, 50, 60, 70, 80}
	_, ids_b := render_high_level_virtual_list(&rt, keys_b)
	for key, id in ids_b {
		if old, ok := ids_a[key]; ok {
			expect(state, old == id, "logical keys preserve retained row identity under reorder")
		}
	}
}

render_both_scroll :: proc(rt: ^alicorn.Runtime) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "both-axis scroll test")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, label="both-axis-scroll-root", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	region := alicorn.scroll_region_begin(&ui, key=alicorn.key_string("both-axis"), viewport_width=100, content_width=500, line_width=10, viewport_height=60, content_height=400, line_height=20, style=alicorn.Layout_Style{.Column, 100, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}, axes=.Both, axis_behavior=.Auto_Lock)
	alicorn.container_begin(&ui, .Virtual_List, label="both-axis-content", style=alicorn.Layout_Style{.Column, 500, 400, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}, layout_scroll_offset_y=region.offset_y, layout_scroll_offset_x=region.offset_x)
	alicorn.text(&ui, "two dimensional content", style=alicorn.Layout_Style{.Row, 500, 400, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.container_end(&ui)
	alicorn.scroll_region_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return region.id
}

render_scroll_pair :: proc(rt: ^alicorn.Runtime, viewport_height: f32) -> [2]alicorn.Node_ID {
	ids: [2]alicorn.Node_ID
	alicorn.invalidate_root(rt, "scroll pair test")
	ui, build := alicorn.begin_frame(rt)
	if !build { return ids }
	alicorn.container_begin(&ui, .Root, label="scroll-pair-root", style=alicorn.Layout_Style{.Row, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	left := alicorn.scroll_region_begin(&ui, key=alicorn.key_string("left"), viewport_height=viewport_height, content_height=400, line_height=20, style=alicorn.Layout_Style{.Column, 100, viewport_height, 0, -1, 0, -1, 0, 0, 0, .Stretch, true})
	ids[0] = left.id
	alicorn.scroll_region_end(&ui)
	right := alicorn.scroll_region_begin(&ui, key=alicorn.key_string("right"), viewport_height=viewport_height, content_height=400, line_height=20, style=alicorn.Layout_Style{.Column, 100, viewport_height, 0, -1, 0, -1, 0, 0, 0, .Stretch, true})
	ids[1] = right.id
	alicorn.scroll_region_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return ids
}

render_horizontal_scroll :: proc(rt: ^alicorn.Runtime, viewport_width: f32) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "horizontal scroll test")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, label="horizontal-scroll-root", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	region := alicorn.scroll_region_begin(
		&ui,
		key=alicorn.key_string("horizontal"),
		viewport_width=viewport_width,
		content_width=500,
		line_width=10,
		viewport_height=60,
		content_height=60,
		style=alicorn.Layout_Style{.Column, viewport_width, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, true},
		axes=.Horizontal,
	)
	id := region.id
	alicorn.container_begin(&ui, .Virtual_List, label="horizontal-content", style=alicorn.Layout_Style{.Column, 500, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}, layout_scroll_offset_x=region.offset_x)
	alicorn.text(&ui, "a very long line that must remain wider than the viewport", style=alicorn.Layout_Style{.Row, 500, 60, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.container_end(&ui)
	alicorn.scroll_region_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return id
}

test_scroll_region_routing_and_clamp :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	ids := render_scroll_pair(&rt, 60)
	left := rt.nodes[ids[0]]
	right := rt.nodes[ids[1]]
	left_before := alicorn.scroll_region_offset(&rt, ids[0])
	right_before := alicorn.scroll_region_offset(&rt, ids[1])
	expect(state, alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_y=-1, x=left.bounds.x+4, y=left.bounds.y+4}), "left region claims wheel input")
	expect(state, alicorn.scroll_region_offset(&rt, ids[0]) == left_before+20 && alicorn.scroll_region_offset(&rt, ids[1]) == right_before, "wheel over left changes only left offset")
	expect(state, alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_y=-1, x=right.bounds.x+4, y=right.bounds.y+4}), "right region claims wheel input")
	expect(state, alicorn.scroll_region_offset(&rt, ids[1]) == right_before+20, "wheel over right changes only right offset")
	expect(state, !alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_y=-1, x=280, y=20}), "wheel outside regions remains available to the application")
	expect(state, alicorn.scroll_region_set_offset(&rt, ids[0], 999), "scroll region accepts a changed programmatic offset")
	expect(state, alicorn.scroll_region_offset(&rt, ids[0]) == 340, "scroll region clamps to content minus viewport")
	_ = alicorn.scroll_region_set_offset(&rt, ids[0], -1)
	expect(state, alicorn.scroll_region_offset(&rt, ids[0]) == 0, "scroll region clamps negative offsets")
	ids = render_scroll_pair(&rt, 100)
	expect(state, alicorn.scroll_region_set_offset(&rt, ids[0], 999), "resized scroll region accepts a new offset")
	expect(state, alicorn.scroll_region_offset(&rt, ids[0]) == 300, "resized viewport recomputes the maximum offset")
	horizontal := render_horizontal_scroll(&rt, 100)
	horizontal_node := rt.nodes[horizontal]
	expect(state, alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_x=-1, x=horizontal_node.bounds.x+4, y=horizontal_node.bounds.y+4}), "horizontal region claims horizontal wheel input")
	expect(state, alicorn.scroll_region_offset_x(&rt, horizontal) == 10, "horizontal wheel changes the retained x offset")
	expect(state, alicorn.scroll_region_set_offset_x(&rt, horizontal, 999), "horizontal region accepts a changed programmatic offset")
	expect(state, alicorn.scroll_region_offset_x(&rt, horizontal) == 400, "horizontal region clamps to content minus viewport")
	_ = render_horizontal_scroll(&rt, 100)
	expect(state, alicorn.scroll_region_offset_x(&rt, horizontal) == 400, "horizontal offset survives the rebuild triggered by scrolling")
	both := render_both_scroll(&rt)
	both_node := rt.nodes[both]
	expect(state, alicorn.process_scroll(&rt, alicorn.Scroll_Event{delta_x=-1, delta_y=-1, x=both_node.bounds.x+4, y=both_node.bounds.y+4}), "two-axis region claims diagonal wheel input")
	expect(state, alicorn.scroll_region_offset(&rt, both) == 20 && alicorn.scroll_region_offset_x(&rt, both) == 0, "auto-lock keeps an equal diagonal gesture on one axis")
}

render_scrollbar_fixture :: proc(
	rt: ^alicorn.Runtime,
	content_width, content_height: f32,
	axes: alicorn.Scroll_Axes,
	policy := alicorn.Scrollbar_Policy.Auto,
	outer_width: f32 = 100,
	outer_height: f32 = 60,
) -> (id: alicorn.Node_ID, handle: alicorn.Scroll_Region_Handle) {
	alicorn.invalidate_root(rt, "scrollbar fixture")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="scrollbar-root", style=alicorn.layout_style())
	handle = alicorn.scroll_region_begin(
		&ui,
		key=alicorn.key_string("scrollbar-region"),
		viewport_width=outer_width,
		viewport_height=outer_height,
		content_width=content_width,
		content_height=content_height,
		style=alicorn.layout_style(width=outer_width, height=outer_height, clip=true),
		axes=axes,
		scrollbars=policy,
	)
	id = handle.id
	alicorn.container_begin(&ui, .Virtual_List, label="scrollbar-content", style=alicorn.layout_style(width=content_width, height=content_height, clip=true))
	alicorn.text(&ui, "retained scroll content", style=alicorn.layout_style(width=content_width, height=24))
	alicorn.container_end(&ui)
	alicorn.scroll_region_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

test_scrollbar_layout_projection :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)

	id, handle := render_scrollbar_fixture(&rt, 100, 200, .Vertical)
	node := rt.nodes[id]
	expect(state, handle.vertical_bar_visible && !handle.horizontal_bar_visible, "Auto shows only the overflowing enabled axis")
	expect(state, handle.viewport_width == 88 && handle.viewport_height == 60, "vertical solid bar reserves width in the handle before virtualizing")
	expect(state, node.scroll_viewport_bounds.w == 88 && node.scroll_viewport_bounds.h == 60, "resolved viewport excludes reserved vertical bar")
	expect(state, node.scrollbar_vertical_track.h == 60 && node.scrollbar_vertical_thumb.h >= alicorn.SCROLLBAR_MIN_THUMB, "vertical bar has a persistent usable thumb")
	content_id := node.children[0]
	content := rt.nodes[content_id]
	expect(state, content.clip.w == node.scroll_viewport_bounds.w && content.clip.h == node.scroll_viewport_bounds.h, "scroll content clip matches effective viewport")

	// Horizontal overflow reserves the bottom strip, which makes the height
	// overflow and therefore requires the vertical strip too.
	id, handle = render_scrollbar_fixture(&rt, 101, 55, .Both)
	node = rt.nodes[id]
	expect(state, handle.horizontal_bar_visible && handle.vertical_bar_visible, "cross-axis overflow is solved to a stable two-bar layout")
	expect(state, handle.viewport_width == 88 && handle.viewport_height == 48, "both bars reserve their solid corner from the effective viewport")
	expect(state, node.scrollbar_vertical_track.h == 48 && node.scrollbar_horizontal_track.w == 88, "both scrollbar tracks stop before the shared corner")
	corner_found := false
	for command in rt.display {
		if command.kind == .Scrollbar_Corner && command.bounds.x == node.scrollbar_vertical_track.x && command.bounds.y == node.scrollbar_horizontal_track.y {
			corner_found = command.bounds.w == alicorn.SCROLLBAR_THICKNESS && command.bounds.h == alicorn.SCROLLBAR_THICKNESS
		}
	}
	expect(state, corner_found, "two-axis bars retain an explicitly painted shared corner")
	expect(state, node.scrollbar_vertical_thumb.h >= alicorn.SCROLLBAR_MIN_THUMB && node.scrollbar_horizontal_thumb.w >= alicorn.SCROLLBAR_MIN_THUMB, "both axes enforce the minimum usable thumb")
	expect(state, node.scrollbar_vertical_thumb.h <= node.scrollbar_vertical_track.h && node.scrollbar_horizontal_thumb.w <= node.scrollbar_horizontal_track.w, "minimum thumb never exceeds a short track")

	text_index, bar_index := -1, -1
	for command, i in rt.display {
		if command.kind == .Text && command.node != id { text_index = i }
		if (command.kind == .Scrollbar_Track || command.kind == .Scrollbar_Thumb) && bar_index < 0 { bar_index = i }
	}
	expect(state, text_index >= 0 && bar_index > text_index, "scrollbar display commands are composed after content and remain visible")

	id, handle = render_scrollbar_fixture(&rt, 99, 59, .Both)
	node = rt.nodes[id]
	expect(state, !handle.horizontal_bar_visible && !handle.vertical_bar_visible, "Auto hides bars when content fits the base viewport")
	for command in rt.display {
		expect(state, command.kind != .Scrollbar_Track && command.kind != .Scrollbar_Thumb && command.kind != .Scrollbar_Corner, "hidden Auto bars emit no geometry")
	}

	id, handle = render_scrollbar_fixture(&rt, 10, 10, .Both, .Always)
	expect(state, handle.horizontal_bar_visible && handle.vertical_bar_visible, "Always displays enabled bars even when content fits")
	expect(state, handle.max_scroll_x == 0 && handle.max_scroll_y == 0, "Always bars with fitting content remain non-scrollable")

	// The high-level virtual list must use the reserved content viewport while
	// it chooses its realized row interval, including the cross-axis case.
	alicorn.invalidate_root(&rt, "scrollbar virtual list projection")
	ui, build := alicorn.begin_frame(&rt)
	list: alicorn.Virtual_List_Handle
	if build {
		alicorn.container_begin(&ui, .Root, label="scrollbar-vlist-root")
		list = alicorn.virtual_list_begin(
			&ui, 100, 2,
			key=alicorn.key_string("scrollbar-vlist"),
			style=alicorn.layout_style(width=100, height=60),
			content_width=101,
			axes=.Both,
		)
		alicorn.virtual_list_end(&ui, list)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	expect(state, list.scroll.viewport_width == 88 && list.scroll.viewport_height == 48, "virtual_list_begin returns the effective reserved viewport")
	expect(state, list.last-list.first <= 25, "virtual list realization is bounded by its effective content viewport")

	id, handle = render_scrollbar_fixture(&rt, 80, 45, .Both, .Auto, 70, 40)
	expect(state, handle.horizontal_bar_visible && handle.vertical_bar_visible, "small viewport activates both auto bars")
	_ = alicorn.scroll_region_set_offset(&rt, id, 999)
	_ = alicorn.scroll_region_set_offset_x(&rt, id, 999)
	id, handle = render_scrollbar_fixture(&rt, 80, 45, .Both, .Auto, 100, 60)
	node = rt.nodes[id]
	expect(state, !handle.horizontal_bar_visible && !handle.vertical_bar_visible, "resizing larger removes bars once content fits")
	expect(state, alicorn.scroll_region_offset(&rt, id) == 0 && alicorn.scroll_region_offset_x(&rt, id) == 0, "resize reclamps both retained offsets to the new maxima")
	expect(state, node.scroll_viewport_bounds.w == 100 && node.scroll_viewport_bounds.h == 60, "resized effective viewport returns all formerly reserved space")
	id, handle = render_scrollbar_fixture(&rt, 100, 100, .Both, .Auto, 8, 8)
	node = rt.nodes[id]
	expect(state, handle.viewport_width == 0 && handle.viewport_height == 0, "tiny two-axis viewport retains zero effective dimensions without negative geometry")
	_ = alicorn.scroll_region_set_offset(&rt, id, 999)
	expect(state, alicorn.scroll_region_offset(&rt, id) == 100, "zero-sized resolved viewport still clamps against its true maximum")
}

test_scrollbar_interaction :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	id, _ := render_scrollbar_fixture(&rt, 100, 600, .Vertical)
	node := rt.nodes[id]
	track := node.scrollbar_vertical_track
	thumb := node.scrollbar_vertical_thumb
	expect(state, alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, track.x+track.w/2, track.y+track.h-1, 1}) == id, "vertical track click is claimed by the scroll region")
	expect(state, alicorn.scroll_region_offset(&rt, id) == node.scroll_viewport_height, "vertical track click pages by one effective viewport")

	// Build a fresh geometry at the top before testing pointer capture.
	_, _ = render_scrollbar_fixture(&rt, 100, 600, .Vertical)
	node = rt.nodes[id]
	thumb = node.scrollbar_vertical_thumb
	start_x, start_y := thumb.x+thumb.w/2, thumb.y+thumb.h/2
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, start_x, start_y, 1})
	expect(state, rt.scrollbar_drag_node == id && rt.captured_node == id, "thumb down captures the retained scroll region")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, start_x, 500, 0})
	expect(state, alicorn.scroll_region_offset(&rt, id) == node.scroll_content_height-node.scroll_viewport_height, "captured vertical drag outside the track clamps to the end")
	expect(state, alicorn.process_pointer(&rt, alicorn.Pointer_Event{kind=.Cancel}) == 0, "pointer cancellation is handled without a target")
	expect(state, rt.scrollbar_drag_node == 0 && rt.captured_node == 0, "focus-loss cancellation clears both retained capture states")
	before := alicorn.scroll_region_offset(&rt, id)
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, start_x, 0, 0})
	expect(state, alicorn.scroll_region_offset(&rt, id) == before, "motion after focus-loss cancellation cannot continue dragging")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, start_x, 500, 1})
	expect(state, rt.scrollbar_drag_node == 0 && rt.captured_node == 0, "pointer release outside the bar ends capture")
	before = alicorn.scroll_region_offset(&rt, id)
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, start_x, 0, 0})
	expect(state, alicorn.scroll_region_offset(&rt, id) == before, "moves after outside release do not continue the drag")
	_ = alicorn.scroll_region_set_offset(&rt, id, 0)
	_, _ = render_scrollbar_fixture(&rt, 100, 600, .Vertical)
	node = rt.nodes[id]
	thumb = node.scrollbar_vertical_thumb
	start_x, start_y = thumb.x+thumb.w/2, thumb.y+thumb.h/2
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, start_x, start_y, 1})
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, start_x, 500, 0})
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, start_x, 500, 1})
	expect(state, rt.scrollbar_drag_node == 0 && rt.captured_node == 0, "outside pointer-up releases an active drag capture")
	expect(state, alicorn.scroll_region_offset(&rt, id) == node.scroll_content_height-node.scroll_viewport_height, "drag position remains clamped after outside release")

	id, _ = render_scrollbar_fixture(&rt, 500, 55, .Both)
	node = rt.nodes[id]
	track_x, thumb_x := node.scrollbar_horizontal_track, node.scrollbar_horizontal_thumb
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, track_x.x+track_x.w-1, track_x.y+track_x.h/2, 1})
	expect(state, alicorn.scroll_region_offset_x(&rt, id) == node.scroll_viewport_width, "horizontal track click pages by one effective viewport")
	_, _ = render_scrollbar_fixture(&rt, 500, 55, .Both)
	node = rt.nodes[id]
	thumb_x = node.scrollbar_horizontal_thumb
	start_x, start_y = thumb_x.x+thumb_x.w/2, thumb_x.y+thumb_x.h/2
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, start_x, start_y, 1})
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, 500, start_y, 0})
	expect(state, alicorn.scroll_region_offset_x(&rt, id) == node.scroll_content_width-node.scroll_viewport_width, "captured horizontal drag clamps to the end")
	alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, 500, start_y, 1})
	expect(state, rt.scrollbar_drag_node == 0, "horizontal drag capture releases outside the window")
}

Split_Test_Nodes :: struct {
	split: alicorn.Split_Handle,
	first: alicorn.Node_ID,
	divider: alicorn.Node_ID,
	second: alicorn.Node_ID,
}

render_split_test :: proc(rt: ^alicorn.Runtime, axis: alicorn.Split_Axis, initial, min_first, min_second: f32) -> Split_Test_Nodes {
	result: Split_Test_Nodes
	alicorn.invalidate_root(rt, "split test render")
	ui, build := alicorn.begin_frame(rt)
	if !build { return result }
	alicorn.container_begin(&ui, .Root, label="split-root", style=alicorn.layout_style(direction=.Column, grow=1, clip=true))
	result.split = alicorn.split_begin(&ui, key=alicorn.key_string("main-split"), axis=axis, initial=initial, min_first=min_first, min_second=min_second)
	result.first = alicorn.split_first_begin(&ui, result.split)
	alicorn.text(&ui, "first pane")
	alicorn.split_first_end(&ui, result.split)
	result.divider = alicorn.split_divider(&ui, result.split)
	result.second = alicorn.split_second_begin(&ui, result.split)
	alicorn.text(&ui, "second pane")
	alicorn.split_second_end(&ui, result.split)
	alicorn.split_end(&ui, result.split)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return result
}

render_nested_split_test :: proc(rt: ^alicorn.Runtime) -> (outer, inner: alicorn.Split_Handle, outer_divider, inner_divider: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "nested split test render")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="nested-split-root", style=alicorn.layout_style(direction=.Column, grow=1, clip=true))
	outer = alicorn.split_begin(&ui, key=alicorn.key_string("outer"), axis=.Horizontal, initial=210, min_first=100, min_second=180)
	_ = alicorn.split_first_begin(&ui, outer)
	alicorn.text(&ui, "left")
	alicorn.split_first_end(&ui, outer)
	outer_divider = alicorn.split_divider(&ui, outer)
	_ = alicorn.split_second_begin(&ui, outer)
	inner = alicorn.split_begin(&ui, key=alicorn.key_string("inner"), axis=.Vertical, initial=90, min_first=40, min_second=40, style=alicorn.layout_style(grow=1, clip=true))
	_ = alicorn.split_first_begin(&ui, inner)
	alicorn.text(&ui, "top")
	alicorn.split_first_end(&ui, inner)
	inner_divider = alicorn.split_divider(&ui, inner)
	_ = alicorn.split_second_begin(&ui, inner)
	alicorn.text(&ui, "bottom")
	alicorn.split_second_end(&ui, inner)
	alicorn.split_end(&ui, inner)
	alicorn.split_second_end(&ui, outer)
	alicorn.split_end(&ui, outer)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return outer, inner, outer_divider, inner_divider
}

Adjacent_Three_Pane_Test_Nodes :: struct {
	outer:         alicorn.Split_Handle,
	inner:         alicorn.Split_Handle,
	outer_divider: alicorn.Node_ID,
	inner_divider: alicorn.Node_ID,
	pane_a:        alicorn.Node_ID,
	pane_b:        alicorn.Node_ID,
	pane_c:        alicorn.Node_ID,
}

render_adjacent_three_pane_test :: proc(rt: ^alicorn.Runtime) -> Adjacent_Three_Pane_Test_Nodes {
	result: Adjacent_Three_Pane_Test_Nodes
	alicorn.invalidate_root(rt, "adjacent three pane split test render")
	ui, build := alicorn.begin_frame(rt)
	if !build { return result }
	alicorn.container_begin(&ui, .Root, label="three-pane-root", style=alicorn.layout_style(direction=.Column, grow=1, clip=true))
	result.outer = alicorn.split_begin(&ui, key=alicorn.key_string("workspace-detail"), axis=.Horizontal, initial=702, min_first=452, min_second=250, style=alicorn.layout_style(.Row, grow=1, clip=true))
	_ = alicorn.split_first_begin(&ui, result.outer)
	result.inner = alicorn.split_begin(&ui, key=alicorn.key_string("sidebar-content"), axis=.Horizontal, initial=300, min_first=150, min_second=200, style=alicorn.layout_style(.Row, grow=1, clip=true))
	result.pane_a = alicorn.split_first_begin(&ui, result.inner)
	alicorn.text(&ui, "pane A")
	alicorn.split_first_end(&ui, result.inner)
	result.inner_divider = alicorn.split_divider(&ui, result.inner)
	result.pane_b = alicorn.split_second_begin(&ui, result.inner)
	alicorn.text(&ui, "pane B")
	alicorn.split_second_end(&ui, result.inner)
	alicorn.split_end(&ui, result.inner)
	alicorn.split_first_end(&ui, result.outer)
	result.outer_divider = alicorn.split_divider(&ui, result.outer)
	result.pane_c = alicorn.split_second_begin(&ui, result.outer)
	alicorn.text(&ui, "pane C")
	alicorn.split_second_end(&ui, result.outer)
	alicorn.split_end(&ui, result.outer)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return result
}

test_adjacent_three_pane_split_redistribution :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1000, 320})
	defer alicorn.destroy_runtime(&rt)
	nodes := render_adjacent_three_pane_test(&rt)
	a := rt.nodes[nodes.pane_a].bounds.w
	b := rt.nodes[nodes.pane_b].bounds.w
	c := rt.nodes[nodes.pane_c].bounds.w
	expect(state, a == 300 && b == 400 && c == 296, "three-pane adjacent split begins at the expected pane widths")

	inner_handle := rt.nodes[nodes.inner_divider]
	start_x := inner_handle.bounds.x + inner_handle.bounds.w/2
	start_y := inner_handle.bounds.y + 20
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, start_x, start_y, 1})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, start_x+50, start_y, 0})
	ui, ready := alicorn.begin_presentation_frame(&rt)
	if ready { alicorn.end_presentation_frame(&ui) }
	a_after_inner := rt.nodes[nodes.pane_a].bounds.w
	b_after_inner := rt.nodes[nodes.pane_b].bounds.w
	c_after_inner := rt.nodes[nodes.pane_c].bounds.w
	expect(state, a_after_inner == a+50 && b_after_inner == b-50 && c_after_inner == c, "first divider redistributes only pane A and B")
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, start_x+50, start_y, 1})

	outer_handle := rt.nodes[nodes.outer_divider]
	start_x = outer_handle.bounds.x + outer_handle.bounds.w/2
	start_y = outer_handle.bounds.y + 20
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, start_x, start_y, 1})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, start_x+40, start_y, 0})
	ui, ready = alicorn.begin_presentation_frame(&rt)
	if ready { alicorn.end_presentation_frame(&ui) }
	a_after_outer := rt.nodes[nodes.pane_a].bounds.w
	b_after_outer := rt.nodes[nodes.pane_b].bounds.w
	c_after_outer := rt.nodes[nodes.pane_c].bounds.w
	expect(state, a_after_outer == a_after_inner && b_after_outer == b_after_inner+40 && c_after_outer == c_after_inner-40, "second divider redistributes only pane B and C")
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, start_x+40, start_y, 1})
}

test_retained_split_drag_and_clamp :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 600, 320})
	defer alicorn.destroy_runtime(&rt)
	nodes := render_split_test(&rt, .Horizontal, 200, 150, 200)
	parent := rt.nodes[nodes.split.id]
	handle := rt.nodes[nodes.divider]
	first := rt.nodes[nodes.first]
	second := rt.nodes[nodes.second]
	expect(state, first.bounds.w == 200 && second.bounds.w == 398, "horizontal split allocates preferred first size and remaining second pane")
	expect(state, handle.bounds.w == 2 && handle.hit_bounds.w == 10, "visible split divider stays thin and hit target is expanded")
	// The pointer is just outside the visible two-pixel divider, inside the
	// expanded hit region.
	start_x := handle.bounds.x - 3
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, start_x, 80, 1})
	expect(state, rt.captured_node == nodes.divider && parent.split_dragging, "pointer down captures the retained split divider")
	expect(state, !rt.invalidated, "split pointer down does not invalidate the application description")
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, 999, 80, 0})
	expect(state, parent.split_position == 398, "dragging beyond the window clamps to the second-pane minimum")
	expect(state, !rt.invalidated, "split drag moves remain retained presentation work")
	ui, ready := alicorn.begin_presentation_frame(&rt)
	if ready { alicorn.end_presentation_frame(&ui) }
	expect(state, first.bounds.w == 398 && second.bounds.w == 200, "retained-only presentation lays out panes during a drag")
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, 999, 500, 1})
	expect(state, rt.captured_node == 0 && !parent.split_dragging, "pointer release outside the window ends the captured drag")
	expect(state, !handle.hovered && rt.last_hovered == 0, "release outside clears the divider hover state")
	expect(state, !rt.invalidated, "split release outside does not trigger app-level pointer handling")
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, first.bounds.x+first.bounds.w-3, 40, 1})
	rt.viewport.w = 400
	nodes = render_split_test(&rt, .Horizontal, 40, 150, 200)
	parent = rt.nodes[nodes.split.id]
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, 500, 40, 0})
	expect(state, parent.split_position == 198 && rt.captured_node == nodes.divider, "resize during capture reclamps drag and preserves capture")
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Up, 500, 40, 1})

	rt.viewport.w = 400
	nodes = render_split_test(&rt, .Horizontal, 40, 150, 200)
	parent = rt.nodes[nodes.split.id]
	first = rt.nodes[nodes.first]
	second = rt.nodes[nodes.second]
	expect(state, parent.split_position == 198 && first.bounds.w == 198 && second.bounds.w == 200, "window resize reclamps retained position to pane minima")
	rt.viewport.w = 60
	nodes = render_split_test(&rt, .Horizontal, 40, 150, 200)
	first = rt.nodes[nodes.first]
	second = rt.nodes[nodes.second]
	expect(state, first.bounds.w >= 0 && second.bounds.w >= 0 && first.bounds.w+second.bounds.w+rt.nodes[nodes.divider].bounds.w == 60, "tiny window keeps split geometry nonnegative and inside bounds")
}

test_split_axis_nested_identity_and_cancel :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 520, 360})
	defer alicorn.destroy_runtime(&rt)
	vertical := render_split_test(&rt, .Vertical, 120, 80, 100)
	expect(state, rt.nodes[vertical.first].bounds.h == 120 && rt.nodes[vertical.second].bounds.h == 238, "vertical split allocates along the y axis")
	outer, inner, outer_divider, inner_divider := render_nested_split_test(&rt)
	expect(state, outer.id != inner.id && outer_divider != inner_divider, "nested split keys retain distinct parent and divider identities")
	rt.nodes[outer.id].split_position = 275
	rt.nodes[inner.id].split_position = 155
	outer2, inner2, outer_divider2, inner_divider2 := render_nested_split_test(&rt)
	expect(state, outer.id == outer2.id && inner.id == inner2.id && outer_divider == outer_divider2 && inner_divider == inner_divider2, "nested split identities survive description rebuild")
	expect(state, rt.nodes[outer.id].split_position == 275 && rt.nodes[inner.id].split_position == 155, "nested split positions persist independently")
	handle := rt.nodes[inner_divider]
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, handle.bounds.x+3, handle.bounds.y+1, 1})
	owner := rt.nodes[inner.id]
	expect(state, owner.split_dragging && rt.captured_node == inner_divider, "nested divider begins its own retained drag")
	alicorn.cancel_pointer_capture(&rt)
	expect(state, rt.captured_node == 0 && !owner.split_dragging && !rt.nodes[inner_divider].pressed, "host capture cancellation clears the active split drag")
}

render_split_virtual_test :: proc(rt: ^alicorn.Runtime, axis := alicorn.Split_Axis.Vertical) -> (divider: alicorn.Node_ID, last: int) {
	alicorn.invalidate_root(rt, "vertical split virtual-list test")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="virtual-split-root", style=alicorn.layout_style(direction=.Column, grow=1, clip=true))
	split := alicorn.split_begin(&ui, key=alicorn.key_string("virtual-split"), axis=axis, initial=120, min_first=60, min_second=60)
	_ = alicorn.split_first_begin(&ui, split)
	list := alicorn.virtual_list_begin(&ui, 100, 20, key=alicorn.key_string("virtual-split-list"), style=alicorn.layout_style(grow=1, clip=true))
	last = list.last
	alicorn.virtual_list_end(&ui, list)
	alicorn.split_first_end(&ui, split)
	divider = alicorn.split_divider(&ui, split)
	_ = alicorn.split_second_begin(&ui, split)
	alicorn.text(&ui, "second pane")
	alicorn.split_second_end(&ui, split)
	alicorn.split_end(&ui, split)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

render_split_geometry_test :: proc(rt: ^alicorn.Runtime) -> (divider, surface: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "split geometry surface test")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="split-geometry-root", style=alicorn.layout_style(.Row, grow=1, clip=true))
	split := alicorn.split_begin(&ui, key=alicorn.key_string("split-geometry"), axis=.Horizontal, initial=120, min_first=60, min_second=60, style=alicorn.layout_style(grow=1, clip=true))
	alicorn.split_first_begin(&ui, split)
	alicorn.text(&ui, "sidebar")
	alicorn.split_first_end(&ui, split)
	divider = alicorn.split_divider(&ui, split)
	alicorn.split_second_begin(&ui, split)
	surface = alicorn.gpu_geometry_surface(&ui, "resizable-geometry", 0, alicorn.layout_style(grow=1, clip=true))
	alicorn.split_second_end(&ui, split)
	alicorn.split_end(&ui, split)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

test_geometry_surface_resize_invalidation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 200})
	defer alicorn.destroy_runtime(&rt)
	divider, surface := render_split_geometry_test(&rt)
	before, before_ok := alicorn.gpu_surface_context(&rt, surface)
	expect(state, before_ok && before.logical_bounds.w == 278, "initial split geometry surface resolves its app-authored width")
	rt.viewport.w = 500
	divider, surface = render_split_geometry_test(&rt)
	window_resized, window_resize_ok := alicorn.gpu_surface_context(&rt, surface)
	expect(state, window_resize_ok && window_resized.logical_bounds.w == 378, "window resize rebuilds geometry at the new resolved width")
	handle := rt.nodes[divider]
	x, y := handle.bounds.x+handle.bounds.w/2, handle.bounds.y+handle.bounds.h/2
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, x, y, 1})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, x+40, y, 0})
	ui, ready := alicorn.begin_presentation_frame(&rt)
	if ready { alicorn.end_presentation_frame(&ui) }
	after, after_ok := alicorn.gpu_surface_context(&rt, surface)
	expect(state, after_ok && after.logical_bounds.w == 338, "retained splitter drag updates the geometry surface bounds")
	expect(state, rt.invalidated, "geometry surface extent change requests one app description rebuild")
	frames_before_rebuild := rt.stats.frames_built
	_, rebuilt_surface := render_split_geometry_test(&rt)
	expect(state, rt.stats.frames_built == frames_before_rebuild+1, "host can immediately rebuild the app-authored geometry projection after resize")
	rebuilt, rebuilt_ok := alicorn.gpu_surface_context(&rt, rebuilt_surface)
	expect(state, rebuilt_ok && rebuilt.logical_bounds.w == after.logical_bounds.w, "rebuilt geometry surface preserves the resized coordinate space")
	expect(state, !rt.invalidated, "geometry surface resize invalidation is consumed by the rebuilt description")
}

test_split_virtual_viewport_followup :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 400})
	defer alicorn.destroy_runtime(&rt)
	divider: alicorn.Node_ID
	before: int
	for _ in 0..<4 {
		divider, before = render_split_virtual_test(&rt)
		if !rt.invalidated { break }
	}
	handle := rt.nodes[divider]
	x, y := handle.bounds.x+10, handle.bounds.y+handle.bounds.h/2
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, x, y, 1})
	_ = alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Move, x, y+100, 0})
	expect(state, !rt.invalidated, "vertical split drag remains presentation-local until retained layout resolves")
	ui, ready := alicorn.begin_presentation_frame(&rt)
	if ready { alicorn.end_presentation_frame(&ui) }
	expect(state, rt.invalidated, "changed virtual-list viewport requests one follow-up description")
	_, after := render_split_virtual_test(&rt)
	expect(state, after > before, "follow-up description realizes rows exposed by the taller split pane")

	horizontal_rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 400})
	defer alicorn.destroy_runtime(&horizontal_rt)
	horizontal_divider: alicorn.Node_ID
	for _ in 0..<4 {
		horizontal_divider, _ = render_split_virtual_test(&horizontal_rt, .Horizontal)
		if !horizontal_rt.invalidated { break }
	}
	horizontal_handle := horizontal_rt.nodes[horizontal_divider]
	hx, hy := horizontal_handle.bounds.x+horizontal_handle.bounds.w/2, horizontal_handle.bounds.y+10
	_ = alicorn.process_pointer(&horizontal_rt, alicorn.Pointer_Event{.Down, hx, hy, 1})
	_ = alicorn.process_pointer(&horizontal_rt, alicorn.Pointer_Event{.Move, hx+50, hy, 0})
	horizontal_ui, horizontal_ready := alicorn.begin_presentation_frame(&horizontal_rt)
	if horizontal_ready { alicorn.end_presentation_frame(&horizontal_ui) }
	expect(state, !horizontal_rt.invalidated, "width-only split drag keeps fixed-row virtualization presentation-local")

	test_geometry_surface_resize_invalidation(state)
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
		geometry := alicorn.gpu_geometry_surface(&ui, "allocator-surface", 0, alicorn.layout_style(height=24))
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		segment := [1]alicorn.GPU_Surface_Line_Segment{{start={0, 0}, end={10, 10}, thickness=1, color={1, 1, 1, 1}}}
		expect(state, alicorn.gpu_surface_update_geometry(&rt, geometry, 1, segment[:], nil), "geometry backing storage must allocate through the runtime-owned persistent allocator")
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
	test_keyboard_focus_and_activation(&state)
	test_unicode_editing(&state)
	test_text_commands(&state)
	test_text_input_composition(&state)
	test_interaction_paint_invalidation(&state)
	test_interaction_regressions(&state)
	test_disabled_button_semantics(&state)
	test_ergonomic_identity(&state)
	test_structure_layout_invalidation(&state)
	test_virtualization_and_gpu(&state)
	test_layout_geometry(&state)
	test_text_intrinsic_layout_invalidation(&state)
	test_container_paint_defaults(&state)
	test_presentation_invalidation(&state)
	test_presentation_submission_lifecycle(&state)
	test_text_geometry(&state)
	test_gpu_text_resource_boundary(&state)
	test_multiline_text_controls(&state)
	test_text_ellipsis(&state)
	test_monospace_font_role(&state)
	test_public_monospace_font_role(&state)
	test_retained_text_weight(&state)
	test_retained_text_product_lifetime(&state)
	test_runtime_edit_invalidates_text_product(&state)
	test_gpu_surface_contract(&state)
	test_gpu_geometry_surface_contract(&state)
	test_retained_scroll_region(&state)
	test_high_level_virtual_list_and_style_defaults(&state)
	test_scroll_region_routing_and_clamp(&state)
	test_scrollbar_layout_projection(&state)
	test_scrollbar_interaction(&state)
	test_retained_split_drag_and_clamp(&state)
	test_adjacent_three_pane_split_redistribution(&state)
	test_split_axis_nested_identity_and_cancel(&state)
	test_split_virtual_viewport_followup(&state)
	test_runtime_allocator_ownership(&state)
	if state.failures == 0 {
		fmt.println("Alicorn foundation tests: PASS")
		return
	}
	fmt.println("Alicorn foundation tests: FAILURES", state.failures)
	os.exit(1)
}
