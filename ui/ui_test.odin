package ui

import "core:testing"
import "core:strings"
import odin_runtime "base:runtime"
import alicorn "alicorn:runtime"

Run_Overlay_Test_App :: struct {
	main_text: Node_ID,
	modal: Node_ID,
	panel: Node_ID,
	overlay_text: Node_ID,
}

Run_Identity_Test_App :: struct {
	row: Node_ID,
}

run_identity_test_render :: proc(app: ^Run_Identity_Test_App, ctx: ^UI) {
	if row(ctx, key="stable-row", height=32) {
		app.row = ctx.runtime.stack[len(ctx.runtime.stack)-1]
		text(ctx, "Stable", key="stable-text")
		button(ctx, "Increment", key="increment")
	}
}

direct_identity_test_describe :: proc(app: ^Run_Identity_Test_App, ctx: ^alicorn.UI) -> Node_ID {
	root := alicorn.container_begin(
		ctx, .Root, label="ui-root", key="alicorn.ui.root",
		style=alicorn.layout_style(.Column, grow=1),
	)
	alicorn.container_begin(
		ctx, .Container, label="row", key="stable-row",
		style=alicorn.layout_style(.Row, height=32),
	)
	app.row = ctx.runtime.stack[len(ctx.runtime.stack)-1]
	alicorn.text(ctx, "Stable", key="stable-text")
	alicorn.button(ctx, "Increment", key="increment")
	alicorn.container_end(ctx)
	alicorn.container_end(ctx)
	return root
}

run_overlay_test_render :: proc(app: ^Run_Overlay_Test_App, ctx: ^UI) {
	app.main_text = text(ctx, "Workspace", key="workspace-label")
}

run_overlay_test_overlays :: proc(app: ^Run_Overlay_Test_App, ctx: ^UI) {
	app.modal = alicorn.modal_overlay_begin(ctx, key="help-overlay", style=alicorn.layout_style(.Column, grow=1))
	if app.modal == 0 { return }
	if panel(ctx, key="help-panel", width=160, padding=8, fill=rgb(0x303030)) {
		app.panel = ctx.runtime.stack[len(ctx.runtime.stack)-1]
		app.overlay_text = text(ctx, "Help", key="help-label")
	}
	alicorn.modal_overlay_end(ctx)
}

@(test)
test_scoped_layout_closes_and_keeps_caller_identity :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 200, 100})
	defer alicorn.destroy_runtime(&rt)
	ctx, should_build := alicorn.begin_frame(&rt)
	if !should_build { testing.expect(t, false, "scope fixture should describe the initial frame"); return }
	root := alicorn.container_begin(&ctx, .Root, key="ui-test-root", style=alicorn.layout_style(width=200, height=100))
	root_depth := len(rt.stack)
	row_id: Node_ID
	nested_row_id: Node_ID
	default_box_id: Node_ID
	if row(&ctx, key="swatches", gap=8) {
		row_id = rt.stack[len(rt.stack)-1]
		box(&ctx, key="red", size=32, fill=red)
		box(&ctx, key="green", size=32, fill=green)
		default_box_id = box(&ctx, key="default-size")
		if row(&ctx, key="nested-row", height=32, grow=1) {
			nested_row_id = rt.stack[len(rt.stack)-1]
			box(&ctx, key="nested-box", size=24)
		}
	}
	testing.expect(t, root != 0 && len(rt.stack) == root_depth,
		"a row written as an if scope should close automatically before the root does")
	container_depth := len(rt.identity_stack)
	leave_scope_early :: proc(ctx: ^UI) {
		if column(ctx, key="early-return") {
			return
		}
	}
	leave_scope_early(&ctx)
	testing.expect(t, len(rt.stack) == root_depth && len(rt.identity_stack) == container_depth,
		"scope cleanup should also run when ordinary control flow returns early")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)

	row_node, row_found := rt.nodes[row_id]
	testing.expect(t, row_found && row_node.bounds.w == 200 && row_node.bounds.h == 32,
		"row should use its allocated width and fit its 32-point square children")
	default_box, default_box_found := rt.nodes[default_box_id]
	testing.expect(t, default_box_found && default_box.bounds.w == 24 && default_box.bounds.h == 24,
		"a box without explicit dimensions should use the documented 24-point square size")
	nested_row, nested_row_found := rt.nodes[nested_row_id]
	testing.expect(t, nested_row_found && nested_row.bounds.w > 24 && nested_row.bounds.x+nested_row.bounds.w == row_node.bounds.x+row_node.bounds.w,
		"an explicit grow should use the parent's remaining width without changing the row's identity")
	if row_found {
		testing.expect(t, strings.contains(row_node.site.file, "ui_test.odin"),
			"the scoped helper should preserve the application call site for retained identity")
	}
}

@(test)
test_simple_text_appearance_lowers_to_regular_text_node :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 100})
	defer alicorn.destroy_runtime(&rt)
	ctx, should_build := alicorn.begin_frame(&rt)
	if !should_build { testing.expect(t, false, "text fixture should describe the initial frame"); return }
	alicorn.container_begin(&ctx, .Root, key="ui-text-root", style=alicorn.layout_style(width=240, height=100))
	id := text(&ctx, "Hello", key="hello", size=20, color=white)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	node, found := rt.nodes[id]
	testing.expect(t, found && node.kind == .Text && node.text_style.font_size == 20 && node.color == white,
		"size and color options should lower to the existing retained text description")
}

@(test)
test_panel_is_one_container_surface_and_box_is_a_leaf :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 200, 120})
	defer alicorn.destroy_runtime(&rt)
	ctx, should_build := alicorn.begin_frame(&rt)
	if !should_build { testing.expect(t, false, "panel fixture should describe the initial frame"); return }
	root_id := alicorn.container_begin(&ctx, .Root, key="ui-panel-root", style=alicorn.layout_style(width=200, height=120))
	panel_id: Node_ID
	if panel(&ctx, key="card", width=160, padding=8, fill=rgb(0x505050), radius=6, stroke=border(1, blue)) {
		panel_id = rt.stack[len(rt.stack)-1]
		text(&ctx, "Card", key="card-label")
	}
	box_id := box(&ctx, key="swatch", size=32, fill=red)
	bad_panel_opened := panel(&ctx, key="bad-panel", radius=-1)
	testing.expect(t, !bad_panel_opened && len(rt.stack) == 1,
		"invalid rounded-panel geometry should fail without popping the parent or leaving a scope open")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	panel_node, panel_found := rt.nodes[panel_id]
	box_node, box_found := rt.nodes[box_id]
	panel_paint_ok := false
	if panel_found && len(panel_node.paint) == 1 {
		paint, ok := panel_node.paint[0].payload.(alicorn.Surface_Paint)
		panel_paint_ok = ok && paint.fill == rgb(0x505050) && paint.stroke == alicorn.Paint_Stroke{color=blue, width=1} &&
			panel_node.paint[0].stroke_placement == .Inside &&
			paint.shape == alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=6}
	}
	panel_style, panel_style_found := rt.semantic_surfaces[panel_id]
	panel_paint_ok = panel_paint_ok && panel_style_found && panel_style.stroke_placement == .Inside
	testing.expect(t, panel_found && panel_node.kind == .Container && panel_paint_ok,
		"panel should lower to one ordinary container with a fill, border, and rounded corners")
	testing.expect(t, box_found && box_node.parent == root_id && box_node.bounds.w == 32 && box_node.bounds.h == 32,
		"box should be one square leaf node beside the panel, with explicit sizing preserved")
}

@(test)
test_typed_runner_closes_main_root_before_describing_modal_overlay :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 140})
	defer alicorn.destroy_runtime(&rt)
	app := Run_Overlay_Test_App{}
	run_state := Run_State(Run_Overlay_Test_App){
		app=&app,
		render=run_overlay_test_render,
		render_overlays=run_overlay_test_overlays,
	}
	ctx, should_build := alicorn.begin_frame(&rt)
	if !should_build { testing.expect(t, false, "typed runner fixture should describe the initial frame"); return }
	root := run_describe(&run_state, &ctx)
	testing.expect(t, root != 0 && len(rt.stack) == 0 && len(rt.identity_stack) == 0,
		"the typed runner should close its ordinary root and overlay before ending the description")
	alicorn.end_frame(&ctx)
	modal, modal_found := rt.nodes[app.modal]
	root_node, root_found := rt.nodes[root]
	main_node, main_found := rt.nodes[app.main_text]
	panel_node, panel_found := rt.nodes[app.panel]
	overlay_node, overlay_found := rt.nodes[app.overlay_text]
	testing.expect(t, modal_found && modal.kind == .Modal_Overlay && modal.parent == 0 &&
		main_found && main_node.parent == root && panel_found && panel_node.parent == app.modal &&
		overlay_found && overlay_node.parent == app.panel,
		"the optional typed overlay callback should emit a top-level modal after the workspace with ordinary retained children")
	testing.expect(t, root_found && root_node.bounds == alicorn.Rect{0, 0, 240, 140},
		"the typed runner's ordinary root should fill the native viewport")
	root_order, modal_order := -1, -1
	for id, index in rt.order {
		if id == root { root_order = index }
		if id == app.modal { modal_order = index }
	}
	testing.expect(t, root_order >= 0 && modal_order > root_order,
		"the modal overlay should follow the main application root in retained composition order")
}

@(test)
test_typed_runner_keeps_keyed_identity_and_warm_description_allocations_stable :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	direct_rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&direct_rt)
	app := Run_Identity_Test_App{}
	direct_app := Run_Identity_Test_App{}
	run_state := Run_State(Run_Identity_Test_App){app=&app, render=run_identity_test_render}
	ctx, should_build := alicorn.begin_frame(&rt)
	if !should_build { testing.expect(t, false, "identity fixture should describe its first frame"); return }
	root := run_describe(&run_state, &ctx)
	alicorn.end_frame(&ctx)
	first_row := app.row
	direct_ctx, direct_should_build := alicorn.begin_frame(&direct_rt)
	if !direct_should_build { testing.expect(t, false, "direct API fixture should describe its first frame"); return }
	direct_root := direct_identity_test_describe(&direct_app, &direct_ctx)
	alicorn.end_frame(&direct_ctx)
	direct_first_row := direct_app.row
	ui_allocations_before_repeat := rt.allocation_stats.persistent_alloc_calls
	direct_allocations_before_repeat := direct_rt.allocation_stats.persistent_alloc_calls

	ctx, should_build = alicorn.begin_frame(&rt)
	testing.expect(t, !should_build, "typed runner's underlying Runtime should settle to true idle")
	if !should_build {
		invalidate(&ctx, "identity regression second description")
		ctx, should_build = alicorn.begin_frame(&rt)
	}
	direct_ctx, direct_should_build = alicorn.begin_frame(&direct_rt)
	testing.expect(t, !direct_should_build, "direct API fixture should settle to true idle")
	if !direct_should_build {
		alicorn.invalidate_root(&direct_rt, "direct API identity regression second description")
		direct_ctx, direct_should_build = alicorn.begin_frame(&direct_rt)
	}
	if should_build {
		_ = run_describe(&run_state, &ctx)
		alicorn.end_frame(&ctx)
	}
	if direct_should_build {
		_ = direct_identity_test_describe(&direct_app, &direct_ctx)
		alicorn.end_frame(&direct_ctx)
	}
	row_node, row_found := rt.nodes[app.row]
	testing.expect(t, should_build && root != 0 && app.row == first_row && row_found && row_node.parent == root,
		"an identical typed description should preserve its explicit keyed node identity")
	direct_row_node, direct_row_found := direct_rt.nodes[direct_app.row]
	testing.expect(t, direct_should_build && direct_root != 0 && direct_app.row == direct_first_row &&
		direct_row_found && direct_row_node.parent == direct_root,
		"the equivalent direct description should preserve its explicit keyed identity")
	ui_allocations := rt.allocation_stats.persistent_alloc_calls-ui_allocations_before_repeat
	direct_allocations := direct_rt.allocation_stats.persistent_alloc_calls-direct_allocations_before_repeat
	testing.expect(t, ui_allocations == direct_allocations,
		"warm convenience descriptions should add no persistent allocations beyond equivalent direct runtime calls")

	_, idle_build := alicorn.begin_frame(&rt)
	testing.expect(t, !idle_build, "after the corrective invalidation description, the Runtime should return to idle")
	_, direct_idle_build := alicorn.begin_frame(&direct_rt)
	testing.expect(t, !direct_idle_build, "the equivalent direct Runtime should also return to idle")
}

@(test)
test_invalidate_requests_existing_runtime_description :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 100, 80})
	defer alicorn.destroy_runtime(&rt)
	ctx, should_build := alicorn.begin_frame(&rt)
	if !should_build { testing.expect(t, false, "invalidation fixture should describe the initial frame"); return }
	alicorn.container_begin(&ctx, .Root, key="ui-invalidate-root", style=alicorn.layout_style())
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	ctx, should_build = alicorn.begin_frame(&rt)
	testing.expect(t, !should_build, "settled runtime should skip an unchanged description")
	invalidate(&ctx, "UI facade explicit invalidation")
	ctx, should_build = alicorn.begin_frame(&rt)
	testing.expect(t, should_build, "the convenience invalidation helper should use the runtime's existing root contract")
	if should_build { alicorn.container_begin(&ctx, .Root, key="ui-invalidate-root", style=alicorn.layout_style()); alicorn.container_end(&ctx); alicorn.end_frame(&ctx) }
}

UI_COMPAT_TEST_LOCATION :: odin_runtime.Source_Code_Location{file_path="app/compatibility.odin", line=42, column=7, procedure="render"}
UI_COMPAT_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
UI_COMPAT_TEST_MONO_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")

@(test)
test_scope_labels_preserve_diagnostics_and_old_positional_locations :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	ctx, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false); return }
	alicorn.container_begin(&ctx, .Root, key="labels-root", style=alicorn.layout_style(width=240, height=120))
	ids: [3]Node_ID
	if row(&ctx, "toolbar", 120, 24, 0, 0, 0, .Start, .Start, false, UI_COMPAT_TEST_LOCATION, label="Editor toolbar") {
		ids[0] = rt.stack[len(rt.stack)-1]
	}
	if column(&ctx, "content", 120, 24, 0, 0, 0, .Start, .Start, false, UI_COMPAT_TEST_LOCATION, label="Editor content") {
		ids[1] = rt.stack[len(rt.stack)-1]
	}
	if panel(&ctx, "inspector", 120, 24, 0, 0, 0, .Start, .Start, false, blue, 0, Border{}, UI_COMPAT_TEST_LOCATION, label="Inspector") {
		ids[2] = rt.stack[len(rt.stack)-1]
	}
	default_ids: [3]Node_ID
	if row(&ctx, key="default-row") { default_ids[0] = rt.stack[len(rt.stack)-1] }
	if column(&ctx, key="default-column") { default_ids[1] = rt.stack[len(rt.stack)-1] }
	if panel(&ctx, key="default-panel") { default_ids[2] = rt.stack[len(rt.stack)-1] }
	testing.expect(t, len(rt.stack) == 1 && len(rt.identity_stack) == 1, "all named scopes must close before their parent")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	labels := [?]string{"Editor toolbar", "Editor content", "Inspector"}
	defaults := [?]string{"row", "column", "panel"}
	for id, i in ids {
		node, found := rt.nodes[id]
		testing.expect(t, found && node.label == labels[i] && node.site.file == UI_COMPAT_TEST_LOCATION.file_path &&
			node.site.line == int(UI_COMPAT_TEST_LOCATION.line) && node.site.column == int(UI_COMPAT_TEST_LOCATION.column),
			"diagnostics must retain the supplied label and the old positional caller-location argument")
		default_node, default_found := rt.nodes[default_ids[i]]
		testing.expect(t, default_found && default_node.label == defaults[i] && strings.contains(default_node.site.file, "ui_test.odin"),
			"omitting label and loc must preserve the original diagnostic name and application call site")
	}
}

@(test)
test_exact_layout_preserves_style_constraints_and_plain_hierarchy :: proc(t: ^testing.T) {
	styles := [?]alicorn.Layout_Style{
		alicorn.layout_style(.Row, width=400, height=50, min_width=80, max_width=180, min_height=20, max_height=40,
			padding=5, gap=3, align=.Center, clip=true, compress_weight=7, writing_direction=.Right_To_Left),
		{}, // Zero-valued styles must not acquire convenience defaults.
		alicorn.layout_style(.Row, height=alicorn.LAYOUT_SIZE_FIT_CONTENT),
		alicorn.DEFAULT_STYLE,
	}
	for style, i in styles {
		rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 100})
		defer alicorn.destroy_runtime(&rt)
		ctx, build := alicorn.begin_frame(&rt)
		if !build { testing.expect(t, false); return }
		root := alicorn.container_begin(&ctx, .Root, key="exact-root", style=alicorn.layout_style(width=300, height=100))
		id, first, second: Node_ID
		if layout(&ctx, style, key="exact-layout") {
			id = rt.stack[len(rt.stack)-1]
			first = box(&ctx, key="first", size=18)
			second = box(&ctx, key="second", size=18)
		}
		alicorn.container_end(&ctx)
		alicorn.end_frame(&ctx)
		node, found := rt.nodes[id]
		testing.expect(t, found && node.kind == .Container && node.parent == root && node.style == style &&
			node.label == "layout" && len(node.paint) == 0 && rt.nodes[first].parent == id && rt.nodes[second].parent == id && len(rt.order) == 4,
			"exact layout must forward every style field through one non-painting Container without adding hierarchy")
		testing.expect(t, strings.contains(node.site.file, "ui_test.odin"), "exact layout must keep its caller's source location")
		switch i {
		case 0:
			testing.expect(t, node.bounds.w == 180 && node.bounds.h == 40 && rt.nodes[first].bounds.x > rt.nodes[second].bounds.x,
				"the existing solver must enforce the exact constraints and RTL flow")
		case 1:
			testing.expect(t, node.bounds.w == 0 && node.bounds.h == 0, "an exact zero-sized style must stay zero-sized")
		case 2:
			testing.expect(t, node.bounds.w == 300 && node.bounds.h == 18, "explicit fit-content height must measure the existing child layout")
		case 3:
			direct_rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 100})
			defer alicorn.destroy_runtime(&direct_rt)
			direct_ctx, direct_build := alicorn.begin_frame(&direct_rt)
			if !direct_build { testing.expect(t, false); return }
			alicorn.container_begin(&direct_ctx, .Root, key="exact-root", style=alicorn.layout_style(width=300, height=100))
			direct_id := alicorn.container_begin(&direct_ctx, .Container, key="exact-layout", style=alicorn.DEFAULT_STYLE)
			box(&direct_ctx, key="first", size=18)
			box(&direct_ctx, key="second", size=18)
			alicorn.container_end(&direct_ctx)
			alicorn.container_end(&direct_ctx)
			alicorn.end_frame(&direct_ctx)
			testing.expect(t, node.bounds == direct_rt.nodes[direct_id].bounds,
				"ordinary runtime dimensions must resolve exactly as a direct Container, without convenience fit-content sizing")
		}
	}
}

@(test)
test_exact_layout_balances_empty_top_level_and_control_flow_scopes :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 200, 100})
	defer alicorn.destroy_runtime(&rt)
	ctx, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false); return }
	empty: Node_ID
	if layout(&ctx, alicorn.DEFAULT_STYLE, key="empty-top-level", label="Empty") { empty = rt.stack[len(rt.stack)-1] }
	testing.expect(t, empty != 0 && len(rt.stack) == 0 && len(rt.identity_stack) == 0,
		"an empty top-level exact scope must close both stacks without needing a hidden Root")
	root := alicorn.container_begin(&ctx, .Root, key="flow-root", style=alicorn.layout_style())
	leave_early :: proc(ctx: ^UI) {
		if layout(ctx, alicorn.DEFAULT_STYLE, key="return-outer") {
			if layout(ctx, alicorn.DEFAULT_STYLE, key="return-inner") { return }
		}
	}
	leave_early(&ctx)
	testing.expect(t, len(rt.stack) == 1 && len(rt.identity_stack) == 1, "return must close nested exact scopes exactly once")
	opened := 0
	for i in 0..<3 {
		if layout(&ctx, alicorn.DEFAULT_STYLE, key=alicorn.key_pair(100, u64(i))) {
			opened += 1
			if i == 0 { continue }
			break
		}
	}
	testing.expect(t, opened == 2 && len(rt.stack) == 1 && len(rt.identity_stack) == 1,
		"continue and break must close their exact scopes while preserving the parent")
	sibling := text(&ctx, "After scopes", key="sibling")
	alicorn.container_end(&ctx)
	testing.expect(t, len(rt.stack) == 0 && len(rt.identity_stack) == 0, "the ordinary root must remain balanced after every exit path")
	alicorn.end_frame(&ctx)
	testing.expect(t, rt.nodes[sibling].parent == root && rt.nodes[empty].parent == 0 && rt.nodes[empty].kind == .Container && len(rt.order) == 7,
		"scope exits must leave the following sibling in its intended parent without extra containers")
}

UI_Compat_Test_App :: struct {
	layout, text, sized_text, button: Node_ID,
	clicked: bool,
}

ui_compat_test_fonts :: proc(rt: ^alicorn.Runtime) -> bool {
	return alicorn.text_engine_load_font(&rt.text_engine, UI_COMPAT_TEST_FONT) &&
		alicorn.text_engine_load_font_role(&rt.text_engine, .Monospace, UI_COMPAT_TEST_MONO_FONT)
}

ui_compat_test_controls :: proc(ctx: ^UI, app: ^UI_Compat_Test_App, direct, disabled: bool) {
	text_layout := alicorn.layout_style(.Row, width=180, height=28, min_width=80, max_width=200)
	text_appearance := alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD, font_size=18, overflow=.Clip}
	button_layout := alicorn.layout_style(.Row, width=180, height=44, min_width=40, max_width=200, min_height=24, max_height=60,
		grow=1, padding=2, gap=3, align=.End, clip=true, compress_weight=2)
	button_appearance := alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_BOLD, font_size=16, overflow=.Ellipsis}
	content := alicorn.button_content_style(.Start, .End, padding_x=11, padding_y=3)
	state := alicorn.Button_State{selected=true, disabled=disabled}
	if direct {
		app.text = alicorn.text(ctx, "Styled source", "styled-text", style=text_layout, loc=UI_COMPAT_TEST_LOCATION,
			font=.Monospace, text_style=text_appearance, color=blue)
		app.sized_text = alicorn.text(ctx, "Sized source", "sized-text", style=text_layout, loc=UI_COMPAT_TEST_LOCATION,
			font=.Monospace, text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD, font_size=12, overflow=.Clip}, color=blue)
		app.clicked = alicorn.button(ctx, "Apply", "styled-action", loc=UI_COMPAT_TEST_LOCATION,
			style=alicorn.layout_style(.Row, width=120, height=36, min_width=40, max_width=200, min_height=24, max_height=60,
				padding=2, gap=3, align=.End, clip=true, compress_weight=2),
			state=state, text_style=button_appearance, content_style=content, variant=.Toolbar)
	} else {
		app.text = text(ctx, "Styled source", "styled-text", -3, blue, UI_COMPAT_TEST_LOCATION,
			style=text_layout, font=.Monospace, text_style=text_appearance)
		app.sized_text = text(ctx, "Sized source", "sized-text", 12, blue, UI_COMPAT_TEST_LOCATION,
			style=text_layout, font=.Monospace, text_style=text_appearance)
		app.clicked = button(ctx, "Apply", "styled-action", UI_COMPAT_TEST_LOCATION,
			style=button_layout, state=state, text_style=button_appearance, content_style=content, variant=.Toolbar,
			width=120, height=36, grow=0)
	}
}

ui_compat_test_frame :: proc(rt: ^alicorn.Runtime, app: ^UI_Compat_Test_App, direct := false, disabled := false) -> bool {
	ctx, build := alicorn.begin_frame(rt)
	if !build { return false }
	alicorn.container_begin(&ctx, .Root, label="compat-root", key="compat-root", style=alicorn.layout_style(width=320, height=200))
	style := alicorn.layout_style(.Column, width=240, height=120, padding=4, gap=3, align=.Start, clip=true)
	if direct {
		app.layout = alicorn.container_begin(&ctx, .Container, label="Control group", key="control-group", style=style, loc=UI_COMPAT_TEST_LOCATION)
		ui_compat_test_controls(&ctx, app, true, disabled)
		alicorn.container_end(&ctx)
	} else if layout(&ctx, style, "control-group", "Control group", UI_COMPAT_TEST_LOCATION) {
		app.layout = rt.stack[len(rt.stack)-1]
		ui_compat_test_controls(&ctx, app, false, disabled)
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	app.button, _ = alicorn.node_by_key(rt, alicorn.key_string("styled-action"), .Button)
	return true
}

@(test)
test_typed_text_and_button_match_direct_runtime_and_consume_activation_once :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	direct_rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&direct_rt)
	if !ui_compat_test_fonts(&rt) || !ui_compat_test_fonts(&direct_rt) { testing.expect(t, false, "conformance needs real shaped fonts"); return }
	app, direct_app: UI_Compat_Test_App
	testing.expect(t, ui_compat_test_frame(&rt, &app) && ui_compat_test_frame(&direct_rt, &direct_app, true))
	node := rt.nodes[app.text]
	sized := rt.nodes[app.sized_text]
	control := rt.nodes[app.button]
	testing.expect(t, node.font == .Monospace && node.text_style.font_size == 18 && node.text_style.font_weight == alicorn.FONT_WEIGHT_SEMIBOLD &&
		node.text_style.overflow == .Clip && node.color == blue && node.text_run_valid && node.text_run.size == 18 &&
		sized.text_style.font_size == 12 && sized.text_style.font_weight == node.text_style.font_weight && sized.text_style.overflow == .Clip && sized.text_run.size == 12,
		"typed typography must reach shaping; only a positive size shorthand may override its font size")
	testing.expect(t, control.bounds.w == 120 && control.bounds.h == 36 && control.style.grow == 0 && control.selected && control.focusable &&
		control.button_variant == .Toolbar && control.text_style.font_size == 16 && control.text_style.font_weight == alicorn.FONT_WEIGHT_BOLD &&
		control.button_content_style == alicorn.button_content_style(.Start, .End, padding_x=11, padding_y=3),
		"button options must control its layout, typography, state, content alignment and existing variant")
	ids := [?]Node_ID{app.layout, app.text, app.sized_text, app.button}
	direct_ids := [?]Node_ID{direct_app.layout, direct_app.text, direct_app.sized_text, direct_app.button}
	for id, i in ids {
		a, b := rt.nodes[id], direct_rt.nodes[direct_ids[i]]
		testing.expect(t, id == direct_ids[i] && a.parent == b.parent && a.bounds == b.bounds && a.style == b.style &&
			a.font == b.font && a.text_style == b.text_style && a.site == b.site && a.site.file == UI_COMPAT_TEST_LOCATION.file_path,
			"typed helpers must preserve keyed identity, hierarchy, layout and source diagnostics from equivalent direct calls")
	}
	testing.expect(t, alicorn.focus(&rt, app.button) && alicorn.activate_focused(&rt, .Enter), "the styled button must accept ordinary keyboard activation")
	for pass in 0..<2 {
		alicorn.invalidate_root(&rt, "consume styled activation")
		_ = ui_compat_test_frame(&rt, &app)
		testing.expect(t, app.button == ids[3] && app.clicked == (pass == 0), "a styled keyed button must consume activation once across repeated descriptions")
	}
	alicorn.invalidate_root(&rt, "disable styled action")
	_ = ui_compat_test_frame(&rt, &app, disabled=true)
	testing.expect(t, rt.nodes[app.button].disabled && !rt.nodes[app.button].focusable && !app.clicked && !alicorn.focus(&rt, app.button),
		"forwarded disabled state must prevent ordinary focus and activation")
}

@(test)
test_button_defaults_explicit_styles_and_nonnegative_sizing_overrides :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	ctx, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false); return }
	alicorn.container_begin(&ctx, .Root, key="button-sizing-root", style=alicorn.layout_style(width=320, height=200))
	button(&ctx, "Default", "default-button", UI_COMPAT_TEST_LOCATION)
	provided := alicorn.layout_style(.Row, width=80, height=26, grow=2, padding=3, gap=4)
	button(&ctx, "Exact style", key="provided-button", style=provided, width=-3, height=-2, grow=-4)
	button(&ctx, "Zero", key="zero-button", style=provided, width=0, height=0, grow=0)
	if row(&ctx, key="grow-row", width=200, height=40, align=.Start) {
		button(&ctx, "Fixed", key="fixed-button", width=40, height=24, grow=0)
		button(&ctx, "Grow", key="grow-button", width=40, height=24, grow=1)
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	default_id, _ := alicorn.node_by_key(&rt, alicorn.key_string("default-button"), .Button)
	provided_id, _ := alicorn.node_by_key(&rt, alicorn.key_string("provided-button"), .Button)
	zero_id, _ := alicorn.node_by_key(&rt, alicorn.key_string("zero-button"), .Button)
	fixed_id, _ := alicorn.node_by_key(&rt, alicorn.key_string("fixed-button"), .Button)
	grow_id, _ := alicorn.node_by_key(&rt, alicorn.key_string("grow-button"), .Button)
	default_node := rt.nodes[default_id]
	testing.expect(t, default_node.style == alicorn.DEFAULT_STYLE && default_node.text_style == alicorn.DEFAULT_BUTTON_TEXT_STYLE &&
		default_node.button_content_style == alicorn.DEFAULT_BUTTON_CONTENT_STYLE && default_node.focusable && !default_node.selected && !default_node.disabled,
		"omitted options must preserve existing button sizing, typography, content and enabled state")
	testing.expect(t, rt.nodes[provided_id].style == provided, "negative shorthand values must leave every supplied style field unchanged")
	zero_style := rt.nodes[zero_id].style
	testing.expect(t, zero_style.width == 0 && zero_style.height == 0 && zero_style.grow == 0 && zero_style.direction == provided.direction &&
		zero_style.padding == provided.padding && zero_style.gap == provided.gap,
		"zero sizing overrides must apply explicitly without reconstructing the rest of the style")
	testing.expect(t, rt.nodes[fixed_id].bounds.w == 40 && rt.nodes[fixed_id].bounds.h == 24 &&
		rt.nodes[grow_id].bounds.w == 160 && rt.nodes[grow_id].bounds.h == 24 && rt.nodes[grow_id].style.direction == alicorn.DEFAULT_STYLE.direction,
		"shorthand sizing must use the existing grow allocator while retaining the default layout direction")
}

@(test)
test_extended_helpers_keep_warm_allocation_parity_and_true_idle :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	direct_rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&direct_rt)
	if !ui_compat_test_fonts(&rt) || !ui_compat_test_fonts(&direct_rt) { testing.expect(t, false); return }
	app, direct_app: UI_Compat_Test_App
	for _ in 0..<3 {
		alicorn.invalidate_root(&rt, "warm compatibility description")
		alicorn.invalidate_root(&direct_rt, "warm compatibility description")
		_ = ui_compat_test_frame(&rt, &app)
		_ = ui_compat_test_frame(&direct_rt, &direct_app, true)
	}
	first_text, first_button := app.text, app.button
	before, direct_before := rt.allocation_stats^, direct_rt.allocation_stats^
	for _ in 0..<4 {
		alicorn.invalidate_root(&rt, "repeat compatibility description")
		alicorn.invalidate_root(&direct_rt, "repeat compatibility description")
		_ = ui_compat_test_frame(&rt, &app)
		_ = ui_compat_test_frame(&direct_rt, &direct_app, true)
	}
	persistent_allocations := rt.allocation_stats.persistent_alloc_calls-before.persistent_alloc_calls
	direct_persistent_allocations := direct_rt.allocation_stats.persistent_alloc_calls-direct_before.persistent_alloc_calls
	scratch_allocations := rt.allocation_stats.scratch_alloc_calls-before.scratch_alloc_calls
	direct_scratch_allocations := direct_rt.allocation_stats.scratch_alloc_calls-direct_before.scratch_alloc_calls
	testing.expect(t, app.text == first_text && app.button == first_button &&
		persistent_allocations == direct_persistent_allocations && scratch_allocations == direct_scratch_allocations,
		"warm exact layout and typed controls must preserve keyed identity and add no allocations beyond direct runtime descriptions")
	idle_allocations := rt.allocation_stats^
	builds, shapes := rt.stats.frames_built, rt.text_engine.shape_calls
	for _ in 0..<12 { testing.expect(t, !ui_compat_test_frame(&rt, &app), "settled extended helpers must skip application description") }
	idle_persistent_allocations := rt.allocation_stats.persistent_alloc_calls-idle_allocations.persistent_alloc_calls
	idle_scratch_allocations := rt.allocation_stats.scratch_alloc_calls-idle_allocations.scratch_alloc_calls
	testing.expect(t, rt.stats.frames_built == builds && rt.text_engine.shape_calls == shapes &&
		idle_persistent_allocations == 0 && idle_scratch_allocations == 0,
		"idle helpers must perform zero builds, shaping calls or runtime allocations")
}
