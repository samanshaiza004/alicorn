package main

import "core:fmt"
import alicorn "../../runtime"

App :: struct {
	count: int,
}

view :: proc(ui: ^alicorn.UI, app: ^App) {
	alicorn.text(ui, "Counter")
	if alicorn.button(ui, "Increment") {
		app.count += 1
	}
	alicorn.text(ui, fmt.tprintf("Count: %d", app.count))
}

main :: proc() {
	app := App{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 360})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "counter example")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		view(&ui, &app)
		alicorn.end_frame(&ui)
	}
	fmt.println("Counter example", app.count)
}
