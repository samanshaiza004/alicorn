package main

import "core:fmt"
import alicorn "../../runtime"

App :: struct {
	query: string,
}

main :: proc() {
	app := App{query="Type here"}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 360})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "text input example")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, label="text-input-root")
		alicorn.text(&ui, "Search")
		alicorn.text_field(&ui, app.query)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	fmt.println("Text input example", app.query)
}
