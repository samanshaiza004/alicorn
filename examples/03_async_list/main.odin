package main

// 03 · Async List adds worker completion, retained scrolling, and fixed-row
// virtualization. The worker builds 10,000 records; after one completion wake,
// the host sleeps until input.
// render_record uses one key scope for the whole component. Its children keep
// their call-site identities when records move or leave the visible window.

import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
import ui "alicorn:ui"

ASYNC_LIST_ITEM_COUNT :: 10_000
ASYNC_LIST_ROW_HEIGHT :: 30

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
	waker:             ui.Application_Waker,
	selected_id:       u64,
	build_calls:       u64,
	loaded_builds:     u64,
	wake_calls:        u64,
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
	// The mutex publishes the data; the borrowed waker only requests an event.
	ui.wake(app.waker)
}

render_record :: proc(ctx: ^ui.UI, item: Item, selected: bool) -> bool {
	if ui.key_scope(ctx, item.id) {
		if ui.row(ctx, height=ASYNC_LIST_ROW_HEIGHT, gap=10, align=.Center) {
			ui.text(ctx, fmt.tprintf("Record %05d · score %03d", item.id, item.score),
				style=ui.layout_style(.Row, grow=1))
			return ui.button(ctx, "Select", width=84, height=26,
				state=ui.Button_State{selected=selected})
		}
	}
	return false
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	app.build_calls += 1
	if app.loaded { app.loaded_builds += 1 }
	if ui.column(ctx, grow=1, padding=20, gap=10, clip=true, label="async-list-content") {
		ui.text(ctx, "03 · Async virtual list", size=24)
		if !app.loaded {
			message := "Loading 10,000 records on a worker…"
			if app.load_failed { message = "Worker could not be started. Close and rerun the example." }
			ui.text(ctx, message)
		} else {
			ui.text(
				ctx,
				fmt.tprintf("Loaded %d records · selected #%d · idle until input", len(app.items), app.selected_id),
				style=ui.layout_style(height=24),
			)
			// Virtualization requires every emitted row to use this fixed height.
			if list, ok := ui.virtual_list(
				ctx,
				len(app.items),
				ASYNC_LIST_ROW_HEIGHT,
				key="records",
				label="10,000 stable records",
			); ok {
				for position in list.first..<list.last {
					item := app.items[position]
					if render_record(ctx, item, item.id == app.selected_id) {
						app.selected_id = item.id
					}
				}
			}
		}
	}
}

start_app :: proc(app: ^App, waker: ui.Application_Waker) {
	app.waker = waker
	app.worker = thread.create_and_start_with_data(rawptr(app), load_items, name="alicorn-example-loader")
	app.load_failed = app.worker == nil
}

wake_app :: proc(app: ^App, ctx: ui.Application_Context) {
	app.wake_calls += 1
	sync.mutex_lock(&app.completion_mutex)
	complete := app.worker_complete
	sync.mutex_unlock(&app.completion_mutex)
	if complete && !app.loaded {
		app.loaded = true
		ui.invalidate(ctx, "async list worker completed")
	}
}

stop_app :: proc(app: ^App) {
	if app.worker != nil {
		// Join before releasing data or returning the borrowed waker to the host.
		thread.join(app.worker)
		thread.destroy(app.worker)
		app.worker = nil
	}
	if app.smoke {
		if !app.loaded || len(app.items) != ASYNC_LIST_ITEM_COUNT {
			fmt.eprintln("async-list smoke stopped before the worker result was presented")
			os.exit(1)
		}
		// The initial loaded description may require one retained-layout pass.
		// Further descriptions without input would violate the idle contract.
		if app.wake_calls != 1 || app.loaded_builds < 1 || app.loaded_builds > 2 {
			fmt.eprintln("async-list performed application builds after reaching idle")
			os.exit(1)
		}
		fmt.println("async_list_smoke", "items", len(app.items), "builds", app.build_calls,
			"loaded_builds", app.loaded_builds, "completion_wakes", app.wake_calls, "idle", true)
	}
}

main :: proc() {
	smoke := false
	for argument in os.args {
		if argument == "--smoke" { smoke = true }
	}
	app := App{items=make([]Item, ASYNC_LIST_ITEM_COUNT), smoke=smoke}
	// Result storage outlives the worker; run returns after on_stop joins it.
	defer delete(app.items)
	ui.run(&app, render, title="Alicorn · Async List", width=860, height=680,
		on_start=start_app,
		on_wake=wake_app,
		on_stop=stop_app,
		smoke=smoke,
	)
}
