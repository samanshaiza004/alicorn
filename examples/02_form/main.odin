package main

// 02 · Form shows ordinary fields and application-owned values. Layout and
// presentation use alicorn:ui; controls not yet wrapped by that package use
// the same UI context through alicorn:runtime.

import "core:fmt"
import alicorn "alicorn:runtime"
import ui "alicorn:ui"

App :: struct {
	name:      alicorn.Text_Field_Buffer,
	show_grid: bool,
	gain:      f32,
	clicks:    int,
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.panel(
		ctx,
		grow=1,
		padding=24,
		gap=14,
		fill=ui.rgb(0x111827),
		label="preferences-form",
	) {
		ui.text(ctx, "02 · A small form", size=24, color=ui.white)
		ui.text(ctx, "Edit the name, toggle an option, and adjust its value.")

		ui.text(ctx, "Name")
		_ = alicorn.text_field_controlled(
			ctx,
			&app.name,
			key=alicorn.key_string("name"),
			style=alicorn.layout_style(height=36),
		)
		_ = alicorn.semantic_description(ctx, .Text_Field, "Name")

		show_grid := alicorn.checkbox(
			ctx,
			"Show grid",
			app.show_grid,
			key=alicorn.key_string("show-grid"),
			style=alicorn.layout_style(.Row, height=36),
		)
		if show_grid.changed { app.show_grid = show_grid.value }

		gain := alicorn.slider_f32(
			ctx,
			"Gain",
			app.gain,
			0,
			1,
			0.05,
			key=alicorn.key_string("gain"),
			style=alicorn.layout_style(height=52),
		)
		if gain.changed { app.gain = gain.value }
		ui.text(ctx, fmt.tprintf("Gain: %.0f%%", app.gain*100))
		ui.text(ctx, "Atlas-backed icons")
		if ui.row(ctx, height=28, gap=8, align=.Center, label="form-icons") {
			_ = alicorn.icon(ctx, .Folder_Closed, key=alicorn.key_string("folder-closed"), size=18)
			ui.text(ctx, "Files")
			_ = alicorn.icon(ctx, .Folder_Open, key=alicorn.key_string("folder-open"), size=18)
			ui.text(ctx, "Open")
			_ = alicorn.icon(ctx, .Search, key=alicorn.key_string("search"), size=18)
			ui.text(ctx, "Search")
		}

		if ui.row(ctx, gap=8, label="form-actions") {
			if ui.button(ctx, "Reset", key=alicorn.key_string("reset"), width=100, height=34) {
				app.show_grid = true
				app.gain = 0.65
			}
			if ui.button(ctx, "Click", key=alicorn.key_string("click"), width=100, height=34) {
				app.clicks += 1
			}
		}

		ui.text(ctx, fmt.tprintf("Name: %s · grid: %v · button clicks: %d", app.name.text, app.show_grid, app.clicks))
	}
}

main :: proc() {
	name, ok := alicorn.text_field_buffer_init("Alicorn", context.allocator)
	if !ok { return }
	app := App{name=name, show_grid=true, gain=0.65}
	defer alicorn.text_field_buffer_destroy(&app.name)

	ui.run(&app, render, title="Alicorn Form", width=560, height=460)
}
