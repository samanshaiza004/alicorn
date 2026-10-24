package ui

import "core:testing"
import "core:strings"
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
		panel_paint_ok = ok && paint.fill == rgb(0x505050) && paint.stroke == border(1, blue) && paint.stroke.placement == .Inside &&
			paint.shape == alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=6}
	}
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
