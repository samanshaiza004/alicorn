package main

// 06 · Secondary Windows opens a small independent native tool window. The
// host API is used only for per-window lifecycle and the open/close service.

import "core:fmt"
import alicorn "alicorn:runtime"
import host "../../native/sdl_gpu"
import ui "alicorn:ui"

Window_State :: struct {
	is_tool:  bool,
	count:    int,
	services: host.Application_Services,
}

build_window :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	_ = logical_width
	_ = logical_height
	_ = dpi_scale
	app := cast(^Window_State)state
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }

	root := alicorn.container_begin(&ctx, .Root, label="secondary-window-example-root", style=alicorn.layout_style(grow=1))
	if ui.column(&ctx, grow=1, padding=24, gap=12, clip=true, label="secondary-window-example") {
		if app.is_tool {
			ui.text(&ctx, "A separate tool window", size=24)
			ui.text(&ctx, "This window has its own application state and Runtime.")
			if ui.button(&ctx, "Increment tool counter", key=alicorn.key_string("tool-increment")) {
				app.count += 1
			}
			ui.text(&ctx, fmt.tprintf("Tool counter: %d", app.count))
			if ui.button(&ctx, "Close tool window", key=alicorn.key_string("tool-close")) {
				host.application_close_window(app.services.windows)
			}
		} else {
			ui.text(&ctx, "Main window", size=24)
			ui.text(&ctx, "Open a companion window and compare its independent counter.")
			if ui.button(&ctx, "Increment main counter", key=alicorn.key_string("main-increment")) {
				app.count += 1
			}
			ui.text(&ctx, fmt.tprintf("Main counter: %d", app.count))
			if ui.button(&ctx, "Open tool window", key=alicorn.key_string("open-tool")) {
				_ = open_tool_window(app)
			}
			ui.text(&ctx, "Only one tool window can be open at a time; close it before opening another.")
		}
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

open_tool_window :: proc(primary: ^Window_State) -> bool {
	tool := new(Window_State, allocator=context.allocator)
	if tool == nil { return false }
	tool^ = Window_State{is_tool=true}
	application := host.Application{
		state=rawptr(tool),
		title="Alicorn Tool Window",
		width=480,
		height=320,
		interaction_update_policy=.Correct_After_Interaction,
		build=build_window,
		on_services=window_services,
		on_stop=tool_window_stop,
	}
	accepted := host.application_open_window(
		primary.services.windows,
		host.Application_Window_Description{
			application=application,
			width=480,
			height=320,
			on_open_failed=tool_window_open_failed,
		},
	)
	if !accepted { free(tool, allocator=context.allocator) }
	return accepted
}

window_services :: proc(state: rawptr, services: host.Application_Services) {
	app := cast(^Window_State)state
	app.services = services
}

tool_window_open_failed :: proc(state: rawptr) {
	free(cast(^Window_State)state, allocator=context.allocator)
}

tool_window_stop :: proc(state: rawptr) {
	free(cast(^Window_State)state, allocator=context.allocator)
}

main :: proc() {
	primary := Window_State{}
	host.Run(host.Application{
		state=rawptr(&primary),
		title="Alicorn · Secondary Windows",
		width=720,
		height=480,
		interaction_update_policy=.Correct_After_Interaction,
		build=build_window,
		on_services=window_services,
	})
}
