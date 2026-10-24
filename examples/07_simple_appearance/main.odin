package main

// Common layout, text, and surface decoration lower to the same retained
// runtime nodes used by advanced applications.

import ui "alicorn:ui"

App :: struct {}

render :: proc(_app: ^App, ctx: ^ui.UI) {
	if ui.column(ctx, padding=24, align=.Center, gap=12) {
		if ui.panel(ctx, width=500, height=500, padding=1, fill=ui.blue) {
			if ui.panel(ctx, height=498, padding=12, gap=12, fill=ui.rgb(0x505050), radius=8) {
				ui.text(ctx, "Hello, Alicorn", size=20, color=ui.white)
				if ui.row(ctx, height=32, gap=8, justify=.Center, align=.Center) {
					colors: [6]ui.Color = {ui.red, ui.green, ui.blue, ui.yellow, ui.black, ui.white}
					for color, i in colors {
						ui.box(ctx, key=u64(i+1), size=32, fill=color)
					}
				}
			}
		}
	}
}

main :: proc() {
	app := App{}
	ui.run(&app, render, title="Alicorn appearance", width=720, height=640)
}
