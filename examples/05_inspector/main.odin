package main

// 05 · Inspector teaches retained identity, focus, semantic actions, and
// causality. Run with `tools/run_example.sh 05_inspector --inspector`, then
// press F9 to open/close the built-in inspector. For the intentional identity
// diagnostic, also pass `--identity-error`; normal startup never triggers it.

import "core:fmt"
import "core:os"
import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"
import ui "alicorn:ui"

INSPECTOR_DEMO_ACTIVATE :: alicorn.Action_ID(501)
INSPECTOR_DEMO_ROWS     :: 48

App :: struct {
	activations:   u64,
	identity_error: bool,
	smoke:          bool,
}

emit_intentional_duplicate :: proc(ctx: ^ui.UI, value: string) {
	ui.text(ctx, value, key="intentional-duplicate")
}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	_logical_width, _logical_height: int,
	_dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^App)state
	alicorn.action_update(rt,
		alicorn.Action_Descriptor{id=INSPECTOR_DEMO_ACTIVATE, name="example.activate", label="Activate example action"},
		alicorn.Action_State{enabled=true},
	)
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ctx,
		.Root,
		label="inspector-example-root",
		key="inspector-example",
		style=ui.layout_style(grow=1),
	)
	if ui.column(&ctx, grow=1, padding=20, gap=10, clip=true, label="inspector-example-content") {
		ui.text(&ctx, "05 · Inspect a retained application", size=24)
		ui.text(&ctx, "Launch with --inspector, Tab to focus controls, then press F9 and explore Tree / Focus / Work / Causes. P enables safe picking; Escape closes.")
		ui.text(&ctx, fmt.tprintf("Application action count: %d", app.activations), style=ui.layout_style(height=26))
		if ui.button(
			&ctx,
			"Activate and record a cause",
			width=260,
			height=34,
		) {
			app.activations += 1
			alicorn.trace_action(rt, INSPECTOR_DEMO_ACTIVATE, "Activate example action")
			alicorn.trace_mutation(rt, "inspector example counter changed")
			alicorn.invalidate_root(rt, "inspector example action activated")
		}
		ui.text(&ctx, "Stable keyed rows (only visible rows are realized):", style=ui.layout_style(height=24))
		list := alicorn.virtual_list_begin(
			&ctx,
			INSPECTOR_DEMO_ROWS,
			30,
			key="inspector-rows",
			style=ui.layout_style(grow=1, clip=true),
			label="48 stable inspector rows",
			focusable=true,
		)
		for position := list.first; position < list.last; position += 1 {
			row_id := u64(position+1)
			if ui.row(&ctx, key=row_id, height=30, align=.Center) {
				ui.text(&ctx, fmt.tprintf("Retained row %02d", row_id))
				alicorn.semantic_bind(&ctx, alicorn.Semantic_ID{namespace=5, value=row_id})
			}
		}
		alicorn.virtual_list_end(&ctx, list)
		if app.identity_error {
			ui.text(&ctx, "Debug mode: the following duplicate key is intentional.")
			emit_intentional_duplicate(&ctx, "first declaration")
			emit_intentional_duplicate(&ctx, "duplicate declaration")
		}
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

main :: proc() {
	app := App{}
	for argument in os.args {
		if argument == "--identity-error" { app.identity_error = true }
		if argument == "--smoke" { app.smoke = true }
	}
	host.Run(host.Application{
		state=rawptr(&app), title="Alicorn · Inspector example", width=920, height=700,
		build=build_app,
	}, smoke=app.smoke)
}
