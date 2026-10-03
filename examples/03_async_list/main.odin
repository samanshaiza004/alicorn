package main

// 03 · Async List teaches worker-to-UI notification and fixed-row
// virtualization. Run with `odin run examples/03_async_list`; the worker
// builds 10,000 records, then Alicorn sleeps until input. Change the row or
// dataset generation below.

import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

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
	// A short deterministic delay makes the asynchronous loading state visible
	// without introducing any network, timer loop, or external dependency.
	time.sleep(180 * time.Millisecond)
	for index in 0..<ASYNC_LIST_ITEM_COUNT {
		app.items[index] = Item{
			id=u64(index+1),
			score=(index*37+11)%1000,
		}
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
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	app.build_calls += 1

	_ = alicorn.action_update(rt,
		alicorn.Action_Descriptor{id=ASYNC_LIST_ACTIVATE, name="async-list.select", label="Select record"},
		alicorn.Action_State{enabled=app.loaded},
	)
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="async-list-root",
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=10, clip=true),
		color=alicorn.Color{0.035, 0.045, 0.065, 1},
	)
	alicorn.text(&ui, "03 · Async virtual list", style=alicorn.layout_style(height=30), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_BOLD})
	if !app.loaded {
		message := "Loading 10,000 records on a worker…"
		if app.load_failed { message = "Worker could not be started. Close and rerun the example." }
		alicorn.text(&ui, message)
		alicorn.container_end(&ui)
		alicorn.end_frame(&ui)
		return root
	}
	status := fmt.tprintf("Loaded %d records · selected #%d · idle until input", len(app.items), app.selected_id)
	alicorn.text(&ui, status, style=alicorn.layout_style(height=24))
	list := alicorn.virtual_list_begin(
		&ui,
		len(app.items),
		ASYNC_LIST_ROW_HEIGHT,
		key=alicorn.key_string("records"),
		style=alicorn.layout_style(grow=1, clip=true),
		label="10,000 stable records",
	)
	for position := list.first; position < list.last; position += 1 {
		item := app.items[position]
		if alicorn.component_begin(&ui, alicorn.key_u64(item.id)) {
			alicorn.container_begin(&ui, .Container, label="record-row", style=alicorn.layout_style(.Row, height=ASYNC_LIST_ROW_HEIGHT, gap=10, align=.Center))
			alicorn.text(&ui, fmt.tprintf("Record %05d · score %03d", item.id, item.score), style=alicorn.layout_style(.Row, grow=1))
			if alicorn.button(
				&ui,
				"Select",
				key=alicorn.key_string("select"),
				style=alicorn.layout_style(.Row, width=84, height=26),
				state=alicorn.Button_State{selected=item.id == app.selected_id},
			) {
				app.selected_id = item.id
				alicorn.trace_action(rt, ASYNC_LIST_ACTIVATE, "Select async-list record")
				alicorn.trace_mutation(rt, "selected async-list record")
				alicorn.invalidate_root(rt, "async-list selection changed")
			}
			alicorn.container_end(&ui)
			alicorn.component_end(&ui)
		}
	}
	alicorn.virtual_list_end(&ui, list)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
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
