package main

// 03 · Async List adds worker completion, retained scrolling, and fixed-row
// virtualization. The worker builds 10,000 records; after one completion wake,
// the host sleeps until input.

import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
import alicorn "alicorn:runtime"
import host "../../native/sdl_gpu"
import ui "alicorn:ui"

ASYNC_LIST_ITEM_COUNT :: 10_000
ASYNC_LIST_ROW_HEIGHT :: 30
ASYNC_LIST_ACTIVATE :: alicorn.Action_ID(301)

Item :: struct {
	id:    u64,
	score: int,
}

App :: struct {
	items:             []Item,
	worker:            ^thread.Thread,
	completion_mutex:  sync.Mutex,
	worker_complete:   bool,
	loaded:            bool,
	load_failed:       bool,
	waker:             host.Application_Waker,
	selected_id:       u64,
	build_calls:       u64,
	settled_builds:    u64,
	smoke:             bool,
}

load_items :: proc(data: rawptr) {
	app := cast(^App)data
	// A short delay makes the loading state visible without a polling loop.
	time.sleep(180 * time.Millisecond)
	for index in 0..<ASYNC_LIST_ITEM_COUNT {
		app.items[index] = Item{id=u64(index+1), score=(index*37+11)%1000}
	}
	sync.mutex_lock(&app.completion_mutex)
	app.worker_complete = true
	sync.mutex_unlock(&app.completion_mutex)
	host.application_wake(app.waker)
}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	_ = logical_width
	_ = logical_height
	_ = dpi_scale
	app := cast(^App)state
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	app.build_calls += 1

	_ = alicorn.action_update(rt,
		alicorn.Action_Descriptor{id=ASYNC_LIST_ACTIVATE, name="async-list.select", label="Select record"},
		alicorn.Action_State{enabled=app.loaded},
	)
	root := alicorn.container_begin(&ctx, .Root, label="async-list-root", style=alicorn.layout_style(grow=1))
	if ui.column(&ctx, grow=1, padding=20, gap=10, clip=true, label="async-list-content") {
		ui.text(&ctx, "03 · Async virtual list", size=24)
		if !app.loaded {
			message := "Loading 10,000 records on a worker…"
			if app.load_failed { message = "Worker could not be started. Close and rerun the example." }
			ui.text(&ctx, message)
		} else {
			ui.text(
				&ctx,
				fmt.tprintf("Loaded %d records · selected #%d · idle until input", len(app.items), app.selected_id),
				style=alicorn.layout_style(height=24),
			)
			list := alicorn.virtual_list_begin(
				&ctx,
				len(app.items),
				ASYNC_LIST_ROW_HEIGHT,
				key=alicorn.key_string("records"),
				style=alicorn.layout_style(grow=1, clip=true),
				label="10,000 stable records",
			)
			for position := list.first; position < list.last; position += 1 {
				item := app.items[position]
				if ui.row(&ctx, key=alicorn.key_u64(item.id), height=ASYNC_LIST_ROW_HEIGHT, gap=10, align=.Center, label="record-row") {
					ui.text(
						&ctx,
						fmt.tprintf("Record %05d · score %03d", item.id, item.score),
						style=alicorn.layout_style(.Row, grow=1),
					)
					if ui.button(&ctx, "Select", key=alicorn.key_string("select"), width=84, height=26,
						state=alicorn.Button_State{selected=item.id == app.selected_id}) {
						app.selected_id = item.id
						alicorn.trace_action(rt, ASYNC_LIST_ACTIVATE, "Select async-list record")
						alicorn.trace_mutation(rt, "selected async-list record")
						alicorn.invalidate_root(rt, "async-list selection changed")
					}
				}
			}
			alicorn.virtual_list_end(&ctx, list)
		}
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	app.settled_builds = app.build_calls
	return root
}

start_app :: proc(state: rawptr, waker: host.Application_Waker) {
	app := cast(^App)state
	app.waker = waker
	app.worker = thread.create_and_start_with_data(rawptr(app), load_items, name="alicorn-example-loader")
	app.load_failed = app.worker == nil
}

wake_app :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	app := cast(^App)state
	sync.mutex_lock(&app.completion_mutex)
	complete := app.worker_complete
	sync.mutex_unlock(&app.completion_mutex)
	if complete && !app.loaded {
		app.loaded = true
		alicorn.invalidate_root(rt, "async list worker completed")
	}
}

stop_app :: proc(state: rawptr) {
	app := cast(^App)state
	if app.worker != nil {
		thread.join(app.worker)
		thread.destroy(app.worker)
		app.worker = nil
	}
	if app.smoke {
		if !app.loaded || len(app.items) != ASYNC_LIST_ITEM_COUNT {
			fmt.eprintln("async-list smoke stopped before the worker result was presented")
			os.exit(1)
		}
		if app.build_calls != app.settled_builds {
			fmt.eprintln("async-list performed application builds after reaching idle")
			os.exit(1)
		}
		fmt.println("async_list_smoke", "items", len(app.items), "settled_builds", app.settled_builds, "idle", true)
	}
	delete(app.items)
}

main :: proc() {
	smoke := false
	for argument in os.args {
		if argument == "--smoke" { smoke = true }
	}
	app := App{items=make([]Item, ASYNC_LIST_ITEM_COUNT), smoke=smoke}
	host.Run(host.Application{
		state=rawptr(&app), title="Alicorn · Async List", width=860, height=680,
		build=build_app,
		on_start=start_app,
		on_wake=wake_app,
		on_stop=stop_app,
	}, smoke=smoke)
}
