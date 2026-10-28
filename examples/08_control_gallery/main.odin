package main

// 08 · Control Gallery keeps reusable icon examples separate from the
// beginner form while using only Alicorn's application-facing UI package.

import "core:fmt"
import ui "alicorn:ui"

App :: struct {
	searches: int,
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.panel(ctx, grow=1, padding=24, gap=16) {
		ui.text(ctx, "08 · Control Gallery", size=24)
		ui.text(ctx, "Font-independent icons and named icon buttons.")

		if ui.row(ctx, gap=20) {
			if ui.column(ctx, gap=8) {
				ui.icon(ctx, .Folder_Closed, size=24)
				ui.text(ctx, "Folder")
			}
			if ui.column(ctx, gap=8) {
				ui.icon(ctx, .Folder_Open, size=24)
				ui.text(ctx, "Open folder")
			}
			if ui.column(ctx, gap=8) {
				ui.icon(ctx, .Search, size=24)
				ui.text(ctx, "Search")
			}
		}

		if ui.row(ctx, gap=8) {
			if ui.icon_button(ctx, "Search", .Search) {
				app.searches += 1
			}
			ui.text(ctx, fmt.tprintf("Search activations: %d", app.searches))
		}
	}
}

main :: proc() {
	app := App{}
	ui.run(&app, render, title="Alicorn Control Gallery", width=560, height=360)
}
