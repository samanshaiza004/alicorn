package main

// 06 · Secondary Windows is a public-API acceptance fixture for one native
// tool window. Run with `tools/secondary_windows_acceptance.ps1`. The primary
// and tool window own independent Runtime/UI state and explicitly share only
// the small acceptance model below.

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"
import ui "alicorn:ui"

SURFACE_PERIOD_NS :: u64(33_000_000)
WORKER_PERIOD     :: 250 * time.Millisecond
SMOKE_LIFETIME    :: u64(60)
SMOKE_CLOSE_AFTER :: u64(24)
GPU_STRESS_SEGMENTS :: 560
GPU_STRESS_CIRCLES  :: 100

Shared_State :: struct {
	primary_waker:           host.Application_Waker,
	smoke:                   bool,
	gpu_stress:              bool,
	tool_live_or_pending:    bool,
	reopen_after_first_close: bool,
	open_requests:           u64,
	open_failures:           u64,
	tool_starts:             u64,
	tool_stops:              u64,
	primary_worker_wakes:    u64,
	tool_worker_wakes:       u64,
	text_changes:            u64,
	composition_events:     u64,
	menu_commands:           u64,
	geometry_updates:        u64,
}

Window_State :: struct {
	shared:             ^Shared_State,
	is_tool:            bool,
	cycle:              u64,
	services:           host.Application_Services,
	waker:              host.Application_Waker,
	worker:             ^thread.Thread,
	worker_stop:        u32,
	worker_enabled:     u32,
	text:               string,
	text_owned:         bool,
	preedit:            string,
	build_count:        u64,
	worker_wake_count:  u64,
	surface:            alicorn.Node_ID,
	phase:              f32,
	animation_enabled:  bool,
	always_on_top:      bool,
	surface_updates:    u64,
	close_for_smoke:    bool,
	menus:              [2]host.Application_Menu,
	file_items:         [2]host.Application_Menu_Item,
	view_items:         [2]host.Application_Menu_Item,
}

acceptance_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Window_State)state
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	app.build_count += 1
	app.surface = 0

	root := alicorn.container_begin(&ctx, .Root, label="secondary-window-acceptance-root", style=alicorn.layout_style(grow=1))
	if ui.column(&ctx, grow=1, padding=20, gap=8, clip=true, label="secondary-window-content") {
		role := "Primary window" if !app.is_tool else fmt.tprintf("Tool window · cycle %d", app.cycle)
		ui.text(&ctx, role, size=22)
		ui.text(&ctx,
			fmt.tprintf("Assigned client: %d × %d logical · scale %.2f · focus %v", logical_width, logical_height, dpi_scale, alicorn.focused_node(rt) != 0),
		)

		if app.is_tool {
			if ui.button(&ctx, "Close tool window", key=alicorn.key_string("secondary-close"), width=190, height=36) {
				host.application_close_window(app.services.windows)
			}
		} else {
			if ui.button(
				&ctx,
				"Open tool window",
				key=alicorn.key_string("secondary-open"),
				width=190,
				height=36,
				state=alicorn.Button_State{disabled=app.shared.tool_live_or_pending},
			) {
				acceptance_open_tool(app)
			}
			if ui.button(
				&ctx,
				"Quit while tool and GPU are active",
				key=alicorn.key_string("secondary-quit-active"),
				width=300,
				height=36,
				state=alicorn.Button_State{disabled=!app.shared.tool_live_or_pending},
			) {
				host.application_request_quit(app.services.quit)
			}
		}

		worker_is_enabled := sync.atomic_load(&app.worker_enabled) != 0
		worker_label := "Start worker wakeups" if !worker_is_enabled else "Stop worker wakeups"
		if ui.button(&ctx, worker_label, key=alicorn.key_string("secondary-worker-toggle"), width=220, height=34) {
			if worker_is_enabled {
				acceptance_worker_stop(app)
			} else if !acceptance_worker_start(app) {
				fmt.eprintln("secondary-window worker could not be started")
			}
		}
		animation_label := "Start GPU animation" if !app.animation_enabled else "Stop GPU animation"
		if ui.button(&ctx, animation_label, key=alicorn.key_string("secondary-animation-toggle"), width=220, height=34) {
			app.animation_enabled = !app.animation_enabled
			if app.animation_enabled {
				_ = host.application_schedule_after(app.services.scheduler, .Frequent, SURFACE_PERIOD_NS)
			} else {
				_ = host.application_cancel_scheduled_wake(app.services.scheduler, .Frequent)
			}
		}

		ui.text(&ctx, "Independent text input (IME composition is counted below)")
		field_key := alicorn.key_string("secondary-tool-text") if app.is_tool else alicorn.key_string("secondary-primary-text")
		field := alicorn.text_field(&ctx, app.text, key=field_key, style=alicorn.layout_style(.Row, height=40))
		field_focused := alicorn.focused_node(rt) == field
		ui.text(&ctx, fmt.tprintf("This window's field focus: %v · text bytes: %d · composition: %q", field_focused, len(app.text), app.preedit))

		ui.text(
			&ctx,
			fmt.tprintf(
				"Shared: open requests %d · starts/stops %d/%d · failures %d · text changes %d · IME events %d · menu commands %d",
				app.shared.open_requests,
				app.shared.tool_starts,
				app.shared.tool_stops,
				app.shared.open_failures,
				app.shared.text_changes,
				app.shared.composition_events,
				app.shared.menu_commands,
			),
		)
		ui.text(
			&ctx,
			fmt.tprintf("Local: builds %d · worker wakes %d · shared GPU geometry updates %d", app.build_count, app.worker_wake_count, app.shared.geometry_updates),
		)

		if ui.panel(&ctx, grow=1, padding=8, clip=true, fill=ui.rgb(0x131822), label="secondary-window-animated-surface-panel") {
			app.surface = alicorn.gpu_geometry_surface(
				&ctx,
				"secondary-window-animated-surface",
				alicorn.layout_style(.Row, grow=1, width=-1, height=-1),
				dpi_scale,
			)
		}
		ui.text(&ctx, "Move/resize this window, transfer focus, type into both fields, and inspect each window's independent scale and state.")
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

acceptance_open_tool :: proc(primary: ^Window_State) -> bool {
	if primary == nil || primary.shared == nil || primary.shared.tool_live_or_pending { return false }
	tool := new(Window_State, allocator=context.allocator)
	if tool == nil {
		primary.shared.open_failures += 1
		return false
	}
	tool^ = Window_State{
		shared=primary.shared,
		is_tool=true,
		cycle=primary.shared.tool_starts+1,
		text="Tool window text",
		animation_enabled=true,
	}
	tool.file_items = [2]host.Application_Menu_Item{
		{kind=.Command, command=host.Application_Command_ID(1), label="Close Tool Window", state=alicorn.Action_State{enabled=true}},
		{kind=.Command, command=host.Application_Command_ID(2), label="Change Tool Title", state=alicorn.Action_State{enabled=true}},
	}
	tool.view_items = [2]host.Application_Menu_Item{
		{kind=.Command, command=host.Application_Command_ID(3), label="Toggle Always on Top", state=alicorn.Action_State{enabled=true}},
		{kind=.Command, command=host.Application_Command_ID(4), label="Toggle Animation", state=alicorn.Action_State{enabled=true}},
	}
	tool.menus = [2]host.Application_Menu{
		{label="File", items=tool.file_items[:]},
		{label="View", items=tool.view_items[:]},
	}
	tool_app := host.Application{
		state=rawptr(tool),
		title="Alicorn Secondary Tool",
		width=680,
		height=620,
		menus=tool.menus[:],
		window_decorations=.Integrated_Title_Bar,
		build=acceptance_build,
		on_text_change=acceptance_text_change,
		on_text_input=acceptance_text_input,
		on_services=acceptance_services,
		on_start=acceptance_start,
		on_wake=acceptance_wake,
		on_scheduled_wake=acceptance_scheduled_wake,
		on_stop=acceptance_stop,
		on_menu_command=acceptance_menu_command,
	}
	description := host.Application_Window_Description{
		application=tool_app,
		width=680,
		height=620,
		on_open_failed=acceptance_open_failed,
	}
	if !host.application_open_window(primary.services.windows, description) {
		acceptance_free_window(tool)
		primary.shared.open_failures += 1
		return false
	}
	primary.shared.tool_live_or_pending = true
	primary.shared.open_requests += 1
	return true
}

acceptance_free_window :: proc(app: ^Window_State) {
	if app == nil { return }
	if app.text_owned { delete(app.text, context.allocator) }
	if len(app.preedit) > 0 { delete(app.preedit, context.allocator) }
	free(app, allocator=context.allocator)
}

acceptance_open_failed :: proc(state: rawptr) {
	tool := cast(^Window_State)state
	if tool != nil && tool.shared != nil {
		tool.shared.open_failures += 1
		tool.shared.tool_live_or_pending = false
	}
	acceptance_free_window(tool)
}

acceptance_services :: proc(state: rawptr, services: host.Application_Services) {
	app := cast(^Window_State)state
	app.services = services
}

acceptance_start :: proc(state: rawptr, waker: host.Application_Waker) {
	app := cast(^Window_State)state
	app.waker = waker
	if !app.is_tool { app.shared.primary_waker = waker }
	if app.is_tool {
		app.shared.tool_starts += 1
		app.shared.tool_live_or_pending = true
	}
	if app.animation_enabled {
		_ = host.application_schedule_after(app.services.scheduler, .Frequent, SURFACE_PERIOD_NS)
	}
	if app.is_tool || app.shared.smoke {
		if !acceptance_worker_start(app) { fmt.eprintln("secondary-window worker could not be started") }
	}
	if !app.is_tool && app.shared.smoke { _ = acceptance_open_tool(app) }
}

acceptance_worker_start :: proc(app: ^Window_State) -> bool {
	if app == nil { return false }
	if app.worker != nil {
		sync.atomic_store(&app.worker_enabled, 1)
		return true
	}
	sync.atomic_store(&app.worker_stop, 0)
	sync.atomic_store(&app.worker_enabled, 1)
	app.worker = thread.create_and_start_with_data(rawptr(app), acceptance_worker, name="alicorn-secondary-window-waker")
	if app.worker == nil {
		sync.atomic_store(&app.worker_enabled, 0)
		return false
	}
	return true
}

acceptance_worker_stop :: proc(app: ^Window_State) {
	if app == nil || app.worker == nil { return }
	sync.atomic_store(&app.worker_enabled, 0)
	sync.atomic_store(&app.worker_stop, 1)
	thread.join(app.worker)
	thread.destroy(app.worker)
	app.worker = nil
}

acceptance_worker :: proc(data: rawptr) {
	app := cast(^Window_State)data
	for sync.atomic_load(&app.worker_stop) == 0 {
		if sync.atomic_load(&app.worker_enabled) != 0 {
			time.sleep(WORKER_PERIOD)
			if sync.atomic_load(&app.worker_enabled) != 0 && sync.atomic_load(&app.worker_stop) == 0 {
				host.application_wake(app.waker)
			}
		} else {
			time.sleep(50 * time.Millisecond)
		}
	}
}

acceptance_wake :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	app := cast(^Window_State)state
	app.worker_wake_count += 1
	if app.is_tool {
		app.shared.tool_worker_wakes += 1
	} else {
		app.shared.primary_worker_wakes += 1
	}
	alicorn.invalidate_root(rt, "secondary acceptance worker wake")
	if !app.is_tool && app.shared.reopen_after_first_close {
		app.shared.reopen_after_first_close = false
		_ = acceptance_open_tool(app)
	}
}

acceptance_scheduled_wake :: proc(state: rawptr, rt: ^alicorn.Runtime, class: host.Scheduled_Wake_Class) {
	_ = class
	app := cast(^Window_State)state
	if app.animation_enabled && app.surface != 0 {
		segments: [GPU_STRESS_SEGMENTS]alicorn.GPU_Surface_Line_Segment
		circles: [GPU_STRESS_CIRCLES]alicorn.GPU_Surface_Filled_Circle
		segment_count := 72
		circle_count := 1
		if app.shared.gpu_stress {
			segment_count = GPU_STRESS_SEGMENTS
			circle_count = GPU_STRESS_CIRCLES
		}
		bounds, ok := alicorn.gpu_surface_context(rt, app.surface)
		if ok && bounds.logical_bounds.w > 0 && bounds.logical_bounds.h > 0 {
			width, height := bounds.logical_bounds.w, bounds.logical_bounds.h
			for index in 0..<segment_count {
				x0 := width*f32(index)/f32(segment_count)
				x1 := width*f32(index+1)/f32(segment_count)
				t := f32(index)/f32(segment_count)
				y0 := height*(0.5-0.34*math.sin(t*12.5663706+app.phase))
				t1 := f32(index+1)/f32(segment_count)
				y1 := height*(0.5-0.34*math.sin(t1*12.5663706+app.phase))
				segments[index] = alicorn.GPU_Surface_Line_Segment{
					start={x0, y0}, end={x1, y1}, thickness=1.5,
					color=alicorn.Color{0.30, 0.78, 0.96, 0.86},
				}
			}
			for index in 0..<circle_count {
				t := f32(index)/f32(max(circle_count, 1))
				circles[index] = alicorn.GPU_Surface_Filled_Circle{
					center={width*t, height*(0.5+0.28*math.sin(t*6.2831853+app.phase))},
					radius=3.5,
					color=alicorn.Color{1, 0.70, 0.25, 0.95},
				}
			}
			if alicorn.gpu_surface_update_geometry(rt, app.surface, segments[:segment_count], circles[:circle_count]) {
				app.phase += 0.14
				app.shared.geometry_updates += 1
				app.surface_updates += 1
			}
		}
		_ = host.application_schedule_after(app.services.scheduler, .Frequent, SURFACE_PERIOD_NS)
		if app.shared.smoke && app.is_tool && app.cycle == 1 && app.worker_wake_count > 0 {
			// Keep the first child alive long enough to receive worker wakeups and
			// submit many GPU frames, then close it through the public service.
			if app.surface_updates >= SMOKE_CLOSE_AFTER {
				app.close_for_smoke = true
				host.application_close_window(app.services.windows)
			}
		}
	}
	if !app.is_tool && app.shared.smoke {
		if app.shared.geometry_updates >= SMOKE_LIFETIME {
			host.application_request_quit(app.services.quit)
		}
	}
}

acceptance_text_change :: proc(state: rawptr, rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	_ = rt
	if !change.changed { return }
	app := cast(^Window_State)state
	value, err := strings.clone(change.text, context.allocator)
	if err != nil { return }
	if app.text_owned { delete(app.text, context.allocator) }
	app.text = value
	app.text_owned = true
	app.shared.text_changes += 1
}

acceptance_text_input :: proc(state: rawptr, rt: ^alicorn.Runtime, owner: alicorn.Node_ID, event: host.Application_Text_Input_Event) {
	_ = rt
	_ = owner
	app := cast(^Window_State)state
	app.shared.composition_events += 1
	if len(app.preedit) > 0 { delete(app.preedit, context.allocator) }
	if event.kind == .Preedit {
		value, err := strings.clone(event.text, context.allocator)
		if err == nil { app.preedit = value }
	}
}

acceptance_menu_command :: proc(state: rawptr, rt: ^alicorn.Runtime, command: host.Application_Command_ID) {
	app := cast(^Window_State)state
	app.shared.menu_commands += 1
	switch command {
	case host.Application_Command_ID(1):
		host.application_close_window(app.services.windows)
	case host.Application_Command_ID(2):
		_ = host.application_window_set_title(app.services.windows, "Alicorn Secondary Tool · menu verified")
	case host.Application_Command_ID(3):
		app.always_on_top = !app.always_on_top
		_ = host.application_window_set_always_on_top(app.services.windows, app.always_on_top)
	case host.Application_Command_ID(4):
		app.animation_enabled = !app.animation_enabled
		if app.animation_enabled {
			_ = host.application_schedule_after(app.services.scheduler, .Frequent, SURFACE_PERIOD_NS)
		} else {
			_ = host.application_cancel_scheduled_wake(app.services.scheduler, .Frequent)
		}
	case:
	}
	alicorn.invalidate_root(rt, "secondary acceptance menu command")
}

acceptance_stop :: proc(state: rawptr) {
	app := cast(^Window_State)state
	acceptance_worker_stop(app)
	if app.is_tool {
		app.shared.tool_stops += 1
		app.shared.tool_live_or_pending = false
		if app.close_for_smoke {
			app.shared.reopen_after_first_close = true
			host.application_wake(app.shared.primary_waker)
		}
		acceptance_free_window(app)
	} else if app.shared.smoke {
		passed := app.shared.open_failures == 0 &&
			app.shared.tool_starts == 2 && app.shared.tool_stops == 2 &&
			app.shared.geometry_updates >= SMOKE_LIFETIME &&
			app.shared.tool_worker_wakes > 0
		fmt.println(
			"secondary_window_lifecycle_smoke",
			"result", "PASS" if passed else "FAIL",
			"opens", app.shared.open_requests,
			"starts", app.shared.tool_starts,
			"stops", app.shared.tool_stops,
			"failures", app.shared.open_failures,
			"worker_wakes", app.shared.tool_worker_wakes,
			"geometry_updates", app.shared.geometry_updates,
		)
		if !passed { os.exit(1) }
	}
	if !app.is_tool && app.text_owned { delete(app.text, context.allocator) }
}

run_acceptance :: proc(smoke, gpu_stress: bool) {
	shared := Shared_State{smoke=smoke, gpu_stress=gpu_stress}
	primary := Window_State{
		shared=&shared,
		text="Primary window text",
		animation_enabled=smoke,
	}
	application := host.Application{
		state=rawptr(&primary),
		title="Alicorn Secondary Window Acceptance",
		width=920,
		height=720,
		build=acceptance_build,
		on_text_change=acceptance_text_change,
		on_text_input=acceptance_text_input,
		on_services=acceptance_services,
		on_start=acceptance_start,
		on_wake=acceptance_wake,
		on_scheduled_wake=acceptance_scheduled_wake,
		on_stop=acceptance_stop,
	}
	host.Run(application)
}

main :: proc() {
	smoke, gpu_stress := false, false
	for argument in os.args {
		if argument == "--lifecycle-smoke" { smoke = true }
		if argument == "--gpu-stress" { gpu_stress = true }
	}
	run_acceptance(smoke, gpu_stress)
}
