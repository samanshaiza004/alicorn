package main

// 02 · Form shows ordinary fields and application-owned values using only
// Alicorn's beginner-facing UI package.

import "core:fmt"
import ui "alicorn:ui"

App :: struct {
	name:      ui.Text_Buffer,
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
	) {
		ui.text(ctx, "02 · A small form", size=24, color=ui.white)
		ui.text(ctx, "Edit the name, toggle an option, and adjust its value.")

		ui.text_field(ctx, "Name", &app.name, height=36)
		ui.checkbox(ctx, "Show grid", &app.show_grid, height=36)
		ui.slider_f32(ctx, "Gain", &app.gain, 0, 1, step=0.05, height=52)
		ui.text(ctx, fmt.tprintf("Gain: %.0f%%", app.gain*100))

		if ui.row(ctx, gap=8) {
			if ui.button(ctx, "Reset", width=100, height=34) {
				app.show_grid = true
				app.gain = 0.65
			}
			if ui.button(ctx, "Click", width=100, height=34) {
				app.clicks += 1
			}
		}

		ui.text(ctx, fmt.tprintf("Name: %s · grid: %v · button clicks: %d", app.name.text, app.show_grid, app.clicks))
	}
}

main :: proc() {
	name, ok := ui.text_buffer("Alicorn")
	if !ok { return }
	app := App{name=name, show_grid=true, gain=0.65}
	defer ui.text_buffer_destroy(&app.name)

	ui.run(&app, render, title="Alicorn Form", width=560, height=460)
}
