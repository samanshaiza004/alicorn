package main

import "core:fmt"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

App :: struct {
	count: int,
}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^App)state
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build {
		return 0
	}

	root := alicorn.container_begin(
		&ui,
		.Root,
		label="starter-root",
		style=alicorn.layout_style(.Column, grow=1, padding=24, gap=12, clip=true),
		color=alicorn.Color{0.04, 0.05, 0.08, 1},
	)
	alicorn.text(&ui, "Hello, Alicorn")
	if alicorn.button(&ui, "Increment", style=alicorn.layout_style(.Row, width=180, height=36)) {
		app.count += 1
	}
	alicorn.text(&ui, fmt.tprintf("Count: %d", app.count))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

main :: proc() {
	app := App{}
	host.Run(host.Application{
		state = rawptr(&app),
		title = "Alicorn starter",
		width = 720,
		height = 480,
		build = build_app,
	})
}
