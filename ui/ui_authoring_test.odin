package ui

import "core:testing"
import "core:math"
import "core:strings"
import alicorn "alicorn:runtime"

UI_Authoring_Test_App :: struct {
	name: ^Text_Buffer,
	enabled: bool,
	gain: f32,
	static_text: Node_ID,
	decorative_text: Node_ID,
	field: Node_ID,
	checkbox_changed: bool,
	slider_changed: bool,
}

ui_authoring_test_render :: proc(app: ^UI_Authoring_Test_App, ctx: ^UI) {
	if column(ctx, key="authoring-test-column", width=320, height=240, gap=4) {
		app.static_text = text(ctx, "Accessible status")
		app.decorative_text = text(ctx, "decorative", decorative=true)
	field := text_field(ctx, "Name", app.name, key="authoring-name", height=32)
		app.field = field.node
		app.checkbox_changed = checkbox(ctx, "Enabled", &app.enabled, key="authoring-enabled", height=32)
		app.slider_changed = slider_f32(ctx, "Gain", &app.gain, 0, 1, step=0.1, key="authoring-gain", height=32)
		_ = icon(ctx, .Search, key="authoring-search")
		_ = icon_button(ctx, "Search now", .Search, key="authoring-search-button")
	}
}

ui_authoring_test_frame :: proc(rt: ^alicorn.Runtime, app: ^UI_Authoring_Test_App) -> bool {
	ctx, build := alicorn.begin_frame(rt)
	if !build { return false }
	root := alicorn.container_begin(&ctx, .Root, key="authoring-root", style=alicorn.layout_style(.Column, width=360, height=280))
	ui_authoring_test_render(app, &ctx)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root != 0
}

ui_percent_test_describe_root_children :: proc(rt: ^alicorn.Runtime, viewport_width, fraction: f32) -> (root, first, second: alicorn.Node_ID) {
	rt.viewport = alicorn.Rect{0, 0, viewport_width, 200}
	alicorn.invalidate_root(rt, "percentage sizing fixture")
	ctx, build := alicorn.begin_frame(rt)
	if !build { return }
	root = alicorn.container_begin(&ctx, .Root, key="percent-root", style=alicorn.layout_style(.Row, padding=20, gap=10))
	if root == 0 { return }
	if layout_sized(&ctx, alicorn.layout_style(.Column, height=30), sizing(width=percent(fraction)), key="percent-first", label="first percent") {
		first = ctx.runtime.pending[len(ctx.runtime.pending)-1].description.id
	}
	if layout_sized(&ctx, alicorn.layout_style(.Column, height=30), sizing(width=percent(fraction)), key="percent-second", label="second percent") {
		second = ctx.runtime.pending[len(ctx.runtime.pending)-1].description.id
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return
}

ui_percent_test_describe_content_parent :: proc(rt: ^alicorn.Runtime) {
	alicorn.invalidate_root(rt, "percentage cycle rejection fixture")
	ctx, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ctx, .Root, key="percent-cycle-root", style=alicorn.layout_style(.Column, width=400, height=160))
	if layout(&ctx, alicorn.layout_style(.Column, max_width=520, height=80), key="percent-content-parent", label="bounded content parent") {
		_ = layout_sized(&ctx, alicorn.layout_style(.Column, height=24), sizing(width=percent(0.5)), key="percent-cycle-child", label="cyclic percent")
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
}

ui_percent_test_describe_fixed_parent :: proc(rt: ^alicorn.Runtime) -> (parent, first, capped: alicorn.Node_ID) {
	rt.viewport = alicorn.Rect{0, 0, 600, 200}
	alicorn.invalidate_root(rt, "fixed-parent percentage fixture")
	ctx, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ctx, .Root, key="fixed-percent-root", style=alicorn.layout_style(.Column, width=600, height=180))
	if layout(&ctx, alicorn.layout_style(.Row, width=400, height=80, padding=20, gap=10), key="fixed-percent-parent", label="fixed parent") {
		parent = ctx.runtime.pending[len(ctx.runtime.pending)-1].description.id
		if layout_sized(&ctx, alicorn.layout_style(.Column, height=30), sizing(width=percent(0.75)), key="fixed-percent-first", label="first fixed percent") {
			first = ctx.runtime.pending[len(ctx.runtime.pending)-1].description.id
		}
		if layout_sized(&ctx, alicorn.layout_style(.Column, height=30), sizing(width=percent(0.75), max_width=logical(250)), key="fixed-percent-capped", label="capped fixed percent") {
			capped = ctx.runtime.pending[len(ctx.runtime.pending)-1].description.id
		}
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return
}

@(test)
test_typed_sizing_lowers_to_legacy_layout_style_and_rejects_ambiguity :: proc(t: ^testing.T) {
	declaration := sizing(
		width=logical(240),
		height=fit_content(),
		min_width=logical(100),
		max_width=logical(300),
		min_height=logical(24),
		grow=expand(1.5),
	)
	base := layout_style(.Row, padding=8, gap=6, align=.Center, clip=true)
	lowered, valid := resolve_sizing(base, declaration)
	expected := alicorn.layout_style(.Row, width=240, height=alicorn.LAYOUT_SIZE_FIT_CONTENT,
		min_width=100, max_width=300, min_height=24, grow=1.5, padding=8, gap=6, align=.Center, clip=true)
	testing.expect(t, valid && lowered == expected,
		"typed fixed, fit, expand, and bound declarations should normalize to the existing style representation")

	invalid_fit_bound := sizing(min_width=fit_content())
	_, valid = resolve_sizing(base, invalid_fit_bound)
	testing.expect(t, !valid, "fit-content is not a valid minimum bound")
	invalid_fit_width := sizing(width=fit_content())
	_, valid = resolve_sizing(base, invalid_fit_width)
	testing.expect(t, !valid, "fit-content width is not part of the existing bounded contract")
	invalid_nan := sizing(width=logical(math.nan_f32()))
	_, valid = resolve_sizing(base, invalid_nan)
	testing.expect(t, !valid, "non-finite logical extents should be rejected")
	_, valid = resolve_sizing(base, sizing(width=percent(0.5)))
	testing.expect(t, !valid, "the context-free normalizer must reject percentages that need a parent")
	invalid_bounds := sizing(min_width=logical(300), max_width=logical(100))
	_, valid = resolve_sizing(base, invalid_bounds)
	testing.expect(t, !valid, "minimum greater than maximum should be rejected instead of normalized silently")
	conflicting_base := alicorn.layout_style(.Row, width=200)
	_, valid = resolve_sizing(conflicting_base, sizing(width=logical(240)))
	testing.expect(t, !valid, "conflicting legacy and typed declarations should be rejected")
	invalid_expand := sizing(grow=expand(0))
	_, valid = resolve_sizing(base, invalid_expand)
	testing.expect(t, !valid, "expansion weights must be finite and positive")
}

@(test)
test_percentage_width_resolves_from_definite_parent_and_matches_fresh_layout :: proc(t: ^testing.T) {
	incremental := alicorn.new_runtime(alicorn.Rect{0, 0, 600, 200})
	defer alicorn.destroy_runtime(&incremental)
	root, first, second := ui_percent_test_describe_root_children(&incremental, 600, 0.75)
	if root == 0 || first == 0 || second == 0 { testing.expect(t, false, "percentage children should be described"); return }
	testing.expect(t, incremental.nodes[first].bounds.w == 420 && incremental.nodes[second].bounds.w == 420,
		"75% widths should use the root inner width after padding")
	testing.expect(t, incremental.nodes[second].bounds.x == 450 && incremental.nodes[second].bounds.x+incremental.nodes[second].bounds.w > 600,
		"percentages totaling over 100% should retain their preferred sizes and overflow through the ordinary Row allocator")
	first_id, second_id := first, second
	first_description_hash := incremental.nodes[first].description_hash
	first_layout_hash := incremental.nodes[first].layout_hash

	root, first, second = ui_percent_test_describe_root_children(&incremental, 800, 0.75)
	testing.expect(t, root != 0 && first == first_id && second == second_id,
		"resizing the viewport must preserve percentage child identities")
	testing.expect(t, incremental.nodes[first].bounds.w == 570 && incremental.nodes[second].bounds.w == 570,
		"the next description must resolve percentages from the new viewport without using prior geometry")
	testing.expect(t, incremental.nodes[first].description_hash == first_description_hash &&
		incremental.nodes[first].layout_hash != first_layout_hash,
		"viewport-relative sizing must change retained layout inputs without changing paint/description inputs")

	previous_layout_hash := incremental.nodes[first].layout_hash
	root, first, second = ui_percent_test_describe_root_children(&incremental, 800, 0.5)
	testing.expect(t, root != 0 && first == first_id && second == second_id &&
		incremental.nodes[first].bounds.w == 380 && incremental.nodes[second].bounds.w == 380,
		"changing a percentage must update layout while retaining the same Node_IDs")
	testing.expect(t, incremental.nodes[first].description_hash == first_description_hash &&
		incremental.nodes[first].layout_hash != previous_layout_hash,
		"changing the percentage must advance only the retained layout input")

	fresh := alicorn.new_runtime(alicorn.Rect{0, 0, 800, 200})
	defer alicorn.destroy_runtime(&fresh)
	_, fresh_first, fresh_second := ui_percent_test_describe_root_children(&fresh, 800, 0.5)
	testing.expect(t, fresh_first == first_id && fresh_second == second_id &&
		incremental.nodes[first].bounds == fresh.nodes[fresh_first].bounds &&
		incremental.nodes[second].bounds == fresh.nodes[fresh_second].bounds,
		"incremental and fresh runtimes must produce identical geometry for the same sizing inputs")
}

@(test)
test_percentage_width_uses_fixed_parent_inner_width_and_existing_bounds :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 600, 200})
	defer alicorn.destroy_runtime(&rt)
	parent, first, capped := ui_percent_test_describe_fixed_parent(&rt)
	if parent == 0 || first == 0 || capped == 0 { testing.expect(t, false, "fixed-parent percentage fixture should build"); return }
	testing.expect(t, rt.nodes[parent].bounds.w == 400 && rt.nodes[first].bounds.w == 270,
		"a fixed nested parent should resolve percentages against its 360-unit inner width")
	testing.expect(t, rt.nodes[first].bounds.x == 20 && rt.nodes[capped].bounds.x == 300 && rt.nodes[capped].bounds.w == 250,
		"parent padding, sibling gap, and child max-width should retain their existing independent allocator semantics")
}

@(test)
test_percentage_width_rejects_content_dependent_parent_with_source_diagnostic :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 600, 200})
	defer alicorn.destroy_runtime(&rt)
	ui_percent_test_describe_content_parent(&rt)
	testing.expect(t, rt.hard_error && strings.contains(rt.diagnostic, "definite parent width") &&
		strings.contains(rt.diagnostic, "maximum width alone does not make it definite") &&
		strings.contains(rt.diagnostic, "ui_authoring_test.odin:"),
		"a percentage under a content-sized parent with finite max width must be rejected with its source location")
	cycle_child_retained := false
	for _, node in rt.nodes { if node.label == "cyclic percent" { cycle_child_retained = true } }
	testing.expect(t, !cycle_child_retained,
		"a rejected percentage must not silently emit a child with an unrelated width")
}

UI_Bound_Control_Test_App :: struct {
	enabled: bool,
	gain: f32,
	checkbox_changed: bool,
	slider_changed: bool,
}

ui_bound_control_test_render :: proc(app: ^UI_Bound_Control_Test_App, ctx: ^UI) {
	if column(ctx, key="bound-control-column", width=320, height=120, gap=4) {
		app.checkbox_changed = checkbox(ctx, "Enabled", &app.enabled, key="bound-enabled", height=32)
		app.slider_changed = slider_f32(ctx, "Gain", &app.gain, 0, 1, step=0.1, key="bound-gain", height=32)
	}
}

ui_bound_control_test_frame :: proc(rt: ^alicorn.Runtime, app: ^UI_Bound_Control_Test_App) -> bool {
	ctx, build := alicorn.begin_frame(rt)
	if !build { return false }
	alicorn.container_begin(&ctx, .Root, key="bound-controls-root", style=alicorn.layout_style(.Column, width=360, height=140))
	ui_bound_control_test_render(app, &ctx)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return true
}

ui_repeated_checkbox :: proc(ctx: ^UI, label: string, value: ^bool, key: string) -> bool {
	return checkbox(ctx, label, value, key=key)
}

@(test)
test_beginner_ui_controls_expose_accessible_names_and_preserve_field_semantics :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 360, 280})
	defer alicorn.destroy_runtime(&rt)
	buffer, buffer_ok := text_buffer("Alicorn")
	if !buffer_ok { testing.expect(t, false, "managed UI text buffer should initialize"); return }
	defer text_buffer_destroy(&buffer)
	app := UI_Authoring_Test_App{name=&buffer, gain=0.5}
	testing.expect(t, ui_authoring_test_frame(&rt, &app), "the authoring example should describe its initial frame")

	static_id := app.static_text
	decorative_id := app.decorative_text
	static_found := static_id != 0
	decorative_found := decorative_id != 0
	checkbox_id, checkbox_found := alicorn.node_by_key(&rt, "authoring-enabled", .Checkbox)
	slider_id, slider_found := alicorn.node_by_key(&rt, "authoring-gain", .Slider)
	button_id, button_found := alicorn.node_by_key(&rt, "authoring-search-button", .Button)
	static, static_semantic_found := rt.semantic_entities[alicorn.semantic_visual_id(static_id)]
	_, decorative_semantic_found := rt.semantic_entities[alicorn.semantic_visual_id(decorative_id)]
	field, field_found := rt.semantic_entities[alicorn.semantic_visual_id(app.field)]
	checkbox_semantic, checkbox_semantic_found := rt.semantic_entities[alicorn.semantic_visual_id(checkbox_id)]
	slider_semantic, slider_semantic_found := rt.semantic_entities[alicorn.semantic_visual_id(slider_id)]
	button_semantic, button_semantic_found := rt.semantic_entities[alicorn.semantic_visual_id(button_id)]
	field_actions := field.node.actions
	static_node := static.node
	checkbox_node := checkbox_semantic.node
	slider_node := slider_semantic.node
	button_node := button_semantic.node
	_ = checkbox_found
	_ = slider_found
	_ = button_found
	testing.expect(t, static_found && static_semantic_found && static_node.role == .Static_Text && static_node.value == "Accessible status",
		"ordinary ui.text should expose informational text as a static-text semantic")
	testing.expect(t, decorative_found && !decorative_semantic_found,
		"decorative text should remain visual-only when explicitly requested")
	testing.expect(t, field_found && field.node.role == .Text_Field && field.node.label == "Name" && field.node.value == "Alicorn" &&
		alicorn.semantic_actions_has(field_actions, .Focus) &&
		alicorn.semantic_actions_has(field_actions, .Set_Value) &&
		alicorn.semantic_actions_has(field_actions, .Set_Text_Selection),
		"ui.text_field should name the control while preserving its value and editing actions")
	testing.expect(t, checkbox_semantic_found && checkbox_node.role == .Checkbox && checkbox_node.label == "Enabled" &&
		!app.checkbox_changed,
		"a normal checkbox description should expose checked-control semantics without adopting a value")
	testing.expect(t, slider_semantic_found && slider_node.role == .Slider && slider_node.label == "Gain" &&
		slider_node.has_numeric_value && slider_node.numeric_value == 0.5 && !app.slider_changed,
		"a normal slider description should expose its numeric semantics without reporting an interaction")
	testing.expect(t, button_semantic_found && button_node.role == .Button && button_node.label == "Search now",
		"icon_button should keep its accessible name while drawing a decorative icon")

	change := alicorn.process_text_edit(&rt, app.field, alicorn.Text_Edit{.Insert, "!"})
	testing.expect(t, change.changed, "the named UI text field should accept committed text edits")
	alicorn.text_change_destroy(&rt, &change)
	alicorn.invalidate_root(&rt, "synchronize UI-owned text buffer")
	testing.expect(t, ui_authoring_test_frame(&rt, &app), "the controlled field should describe the committed edit")
	updated_field, updated_field_found := rt.semantic_entities[alicorn.semantic_visual_id(app.field)]
	testing.expect(t, updated_field_found && app.name^.text == "Alicorn!" &&
		updated_field.node.label == "Name" && updated_field.node.value == "Alicorn!" &&
		alicorn.semantic_actions_has(updated_field.node.actions, .Set_Text_Selection),
		"the wrapper should synchronize committed text while retaining the field's accessible name and selection action")
}

@(test)
test_bound_controls_write_only_after_real_user_interaction :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 360, 280})
	defer alicorn.destroy_runtime(&rt)
	app := UI_Bound_Control_Test_App{gain=1.5}
	testing.expect(t, ui_bound_control_test_frame(&rt, &app), "the first bound-control frame should build")
	checkbox_id, _ := alicorn.node_by_key(&rt, "bound-enabled", .Checkbox)
	slider_id, _ := alicorn.node_by_key(&rt, "bound-gain", .Slider)
	testing.expect(t, !app.enabled && app.gain == 1.5 && !app.checkbox_changed && !app.slider_changed,
		"initial rendering must not mutate bound values, including when the slider range normalizes its display value")

	testing.expect(t, alicorn.focus(&rt, checkbox_id) && alicorn.activate_focused(&rt, .Space),
		"the retained checkbox should accept ordinary keyboard activation")
	alicorn.invalidate_root(&rt, "reconcile bound checkbox interaction")
	testing.expect(t, ui_bound_control_test_frame(&rt, &app), "an accepted checkbox activation should request a corrective description")
	testing.expect(t, rt.activation_node == 0,
		"the bound checkbox description should consume its retained one-shot activation")
	consumed_by_checkbox := false
	checkbox_node, checkbox_node_found := rt.nodes[checkbox_id]
	if checkbox_node_found { consumed_by_checkbox = checkbox_node.last_consumed_activation == rt.activation_sequence }
	testing.expect(t, consumed_by_checkbox && app.enabled && app.checkbox_changed,
		"the bound checkbox should consume its one-shot activation and adopt the new application value")

	slider := rt.nodes[slider_id]
	slider.control_pending = true
	slider.control_pending_value = 0.7
	rt.nodes[slider_id] = slider
	alicorn.invalidate_root(&rt, "reconcile bound slider interaction")
	testing.expect(t, ui_bound_control_test_frame(&rt, &app), "a pending slider value should request a corrective description")
	testing.expect(t, app.gain == 0.7 && app.slider_changed,
		"a real pending slider interaction should be adopted by the bound wrapper")
}

@(test)
test_unkeyed_controls_keep_application_callsite_identity :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	first := false
	second := true
	ctx, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false); return }
	alicorn.container_begin(&ctx, .Root, key="callsite-identity-root", style=alicorn.layout_style(.Column, width=240, height=120))
	_ = checkbox(&ctx, "First", &first)
	_ = checkbox(&ctx, "Second", &second)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	first_id, second_id: Node_ID
	for id in rt.order {
		if node, found := rt.nodes[id]; found && node.kind == .Checkbox {
			if node.label == "First" { first_id = id }
			if node.label == "Second" { second_id = id }
		}
	}
	first_found, second_found := first_id != 0, second_id != 0
	testing.expect(t, first_found && second_found && first_id != second_id,
		"static controls at distinct application call sites should not require explicit keys")
}

@(test)
test_explicit_keys_preserve_identity_through_a_shared_wrapper_and_reorder :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	first, second := false, true
	for pass in 0..<2 {
		if pass > 0 { alicorn.invalidate_root(&rt, "reorder repeated keyed controls") }
		ctx, build := alicorn.begin_frame(&rt)
		if !build { testing.expect(t, false, "reordered repeated controls should be described"); return }
		alicorn.container_begin(&ctx, .Root, key="repeated-checkbox-root", style=alicorn.layout_style(.Column, width=240, height=120))
		if pass == 0 {
			_ = ui_repeated_checkbox(&ctx, "First", &first, "record-1")
			_ = ui_repeated_checkbox(&ctx, "Second", &second, "record-2")
		} else {
			_ = ui_repeated_checkbox(&ctx, "Second", &second, "record-2")
			_ = ui_repeated_checkbox(&ctx, "First", &first, "record-1")
		}
		alicorn.container_end(&ctx)
		alicorn.end_frame(&ctx)
	}
	first_id, first_found := alicorn.node_by_key(&rt, "record-1", .Checkbox)
	second_id, second_found := alicorn.node_by_key(&rt, "record-2", .Checkbox)
	testing.expect(t, first_found && second_found && first_id != second_id &&
		rt.nodes[first_id].label == "First" && rt.nodes[first_id].paint_value == 0 &&
		rt.nodes[second_id].label == "Second" && rt.nodes[second_id].paint_value == 1,
		"explicit data keys must survive the same helper call site being reordered")
}
