package main

import "core:fmt"
import alicorn "../../runtime"

Item :: struct {
	id:   u64,
	name: string,
}

render_item :: proc(ui: ^alicorn.UI, item: Item) {
	alicorn.text(ui, item.name)
	if alicorn.button(ui, "Select") {
		fmt.println("selected", item.id)
	}
}

main :: proc() {
	items: []Item = []Item{{10, "Alpha"}, {20, "Beta"}, {30, "Gamma"}}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 360})
	defer alicorn.destroy_runtime(&rt)
	alicorn.invalidate_root(&rt, "keyed list example")
	ui, build := alicorn.begin_frame(&rt)
	if build {
		alicorn.container_begin(&ui, .Root, label="keyed-list-root")
		for item in items {
			if alicorn.component_begin(&ui, alicorn.key_u64(item.id)) {
				render_item(&ui, item)
				alicorn.component_end(&ui)
			}
		}
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
	}
	fmt.println("Keyed list example", len(items), "items")
}
