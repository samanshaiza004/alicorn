package main

// 05 · Inspector teaches retained identity, focus, semantic actions, and
// causality. Run with `odin run examples/05_inspector -- --inspector`, then
// press F9 to open/close the built-in inspector. For the intentional identity
// diagnostic, also pass `--identity-error`; normal startup never triggers it.

import "core:fmt"
import "core:os"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

INSPECTOR_DEMO_ACTIVATE :: alicorn.Action_ID(501)
INSPECTOR_DEMO_ROWS     :: 48

App :: struct {
	activations:   u64,
	identity_error: bool,
	smoke:          bool,
}

emit_intentional_duplicate :: proc(ui: ^alicorn.UI, value: string) {
	alicorn.text(ui, value, key=alicorn.key_string("intentional-duplicate"))
}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	_ = logical_width
	_ = logical_height
	_ = dpi_scale
	app := cast(^App)state
	_ = alicorn.action_update(rt,
		alicorn.Action_Descriptor{id=INSPECTOR_DEMO_ACTIVATE, name="example.activate", label="Activate example action"},
		alicorn.Action_State{enabled=true},
	)
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="inspector-example-root",
		key=alicorn.key_string("inspector-example"),
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=10, clip=true),
		color=alicorn.Color{0.035, 0.045, 0.065, 1},
	)
	alicorn.text(&ui, "05 · Inspect a retained application", style=alicorn.layout_style(height=30), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_BOLD})
	alicorn.text(&ui, "Launch with --inspector, Tab to focus controls, then press F9 and explore Tree / Focus / Work / Causes. P enables safe picking; Escape closes.", style=alicorn.layout_style(height=44))
	alicorn.text(&ui, fmt.tprintf("Application action count: %d", app.activations), style=alicorn.layout_style(height=26))
	if alicorn.button(
		&ui,
		"Activate and record a cause",
		key=alicorn.key_string("activate"),
		style=alicorn.layout_style(width=260, height=34),
	) {
		app.activations += 1
		alicorn.trace_action(rt, INSPECTOR_DEMO_ACTIVATE, "Activate example action")
		alicorn.trace_mutation(rt, "inspector example counter changed")
		alicorn.invalidate_root(rt, "inspector example action activated")
	}
	alicorn.text(&ui, "Stable keyed rows (only visible rows are realized):", style=alicorn.layout_style(height=24))
	list := alicorn.virtual_list_begin(
		&ui,
		INSPECTOR_DEMO_ROWS,
		30,
		key=alicorn.key_string("inspector-rows"),
		style=alicorn.layout_style(grow=1, clip=true),
		label="48 stable inspector rows",
		focusable=true,
	)
	for position := list.first; position < list.last; position += 1 {
		row_id := u64(position+1)
		if alicorn.component_begin(&ui, alicorn.key_u64(row_id)) {
			alicorn.container_begin(&ui, .Container, label="stable-row", style=alicorn.layout_style(.Row, height=30, align=.Center))
			alicorn.text(&ui, fmt.tprintf("Retained row %02d", row_id))
			_ = alicorn.semantic_bind(&ui, alicorn.Semantic_ID{namespace=5, value=row_id})
			alicorn.container_end(&ui)
			alicorn.component_end(&ui)
		}
	}
	alicorn.virtual_list_end(&ui, list)
	if app.identity_error {
		alicorn.text(&ui, "Debug mode: the following duplicate key is intentional.", key=alicorn.key_string("identity-error-explanation"))
		emit_intentional_duplicate(&ui, "first declaration")
		emit_intentional_duplicate(&ui, "duplicate declaration")
	}
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
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
