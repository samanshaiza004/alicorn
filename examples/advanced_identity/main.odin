package main

import "core:fmt"
import alicorn "../../runtime"

ADVANCED_BUTTON_SITE :: alicorn.Source_Site{"examples/advanced_identity/main.odin", 1, 1, "diagnostic_button"}

main :: proc() {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 360})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "advanced identity example")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin_ex(&ui, .Root, label="advanced-root")
		_, _ = alicorn.button_ex(&ui, "Explicit diagnostic identity", ADVANCED_BUTTON_SITE)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	fmt.println("Advanced identity example")
}
