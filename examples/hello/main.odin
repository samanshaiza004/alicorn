package main

import "core:fmt"
import alicorn "../../runtime"

main :: proc() {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 360})
	defer alicorn.destroy_runtime(&rt)

	alicorn.invalidate_root(&rt, "hello example")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, label="hello-root")
		alicorn.text(&ui, "Hello, Alicorn")
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	fmt.println("Hello example built", rt.stats.frames_built, "frame")
}
