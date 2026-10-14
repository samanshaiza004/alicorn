package main

import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"

App :: struct {}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build {
		return 0
	}
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="external-consumer-root",
		style=alicorn.layout_style(.Column, grow=1, padding=24, gap=12),
	)
	alicorn.text(&ui, "External Alicorn consumer")
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

main :: proc() {
	app := App{}
	host.Run(host.Application{
		state = rawptr(&app),
		title = "External Alicorn consumer",
		width = 640,
		height = 400,
		build = build_app,
	})
}
