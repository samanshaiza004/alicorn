package main

import "core:testing"
import alicorn "alicorn:runtime"

@(test)
test_hello_uses_standard_accessible_ui_controls :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 720, 480})
	defer alicorn.destroy_runtime(&rt)
	app := App{}
	ctx, build := alicorn.begin_frame(&rt)
	if !build { testing.expect(t, false, "Hello should describe its first frame"); return }
	alicorn.container_begin(&ctx, .Root, key="hello-test-root", style=alicorn.layout_style(.Column, width=720, height=480))
	render(&app, &ctx)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)

	button_found := false
	text_semantic_found := false
	for id in rt.order {
		node := rt.nodes[id]
		if node.kind == .Button && node.label == "Increment" { button_found = true }
		if node.kind == .Text && node.text == "Hello, Alicorn" {
			if semantic, found := rt.semantic_entities[alicorn.semantic_visual_id(id)]; found {
				text_semantic_found = semantic.node.role == .Static_Text && semantic.node.value == "Hello, Alicorn"
			}
		}
	}
	testing.expect(t, button_found && text_semantic_found && app.count == 0,
		"the starter should use ordinary button identity and expose its informational text without runtime-only calls")
}
