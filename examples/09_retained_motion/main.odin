package main

// 09 · Retained Motion demonstrates a decorative selection marker. Selecting
// another tab changes the retained translation target once; the native host
// samples the analytic response at display-like intervals without rebuilding
// this application description.

import "core:fmt"
import "core:os"
import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"
import ui "alicorn:ui"

TAB_COUNT :: 3
MOTION_CONFIG :: ui.Motion_Config{
	omega=18,
	position_tolerance=0.001,
	velocity_tolerance=0.01,
}

App :: struct {
	selected: int,
	logical_width: int,
	clock: host.Application_Motion_Clock,
	scheduler: host.Application_Scheduler,
	diagnostics: host.Application_Diagnostics,
	services_ready: bool,
	validation_mode: bool,
	validation_phase: Motion_Validation_Phase,
}

Motion_Validation_Phase :: enum { None, Retarget, Settled_Check, Idle_Check, Done }

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, _logical_height: int,
	_dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^App)state
	app.logical_width = logical_width
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(&ctx, .Root, key="motion-root", style=ui.layout_style(grow=1))
	if ui.column(&ctx, padding=24, gap=18, grow=1, label="motion-content") {
		ui.text(&ctx, "09 · Retained Motion", size=24)
		ui.text(&ctx, "Click a tab. Only the decorative marker moves; the application description and layout stay idle.")
		tab_width := max(f32(logical_width-48-16)/f32(TAB_COUNT), 120)
		tab_labels := [3]string{"Library", "Editor", "Settings"}
		if ui.row(&ctx, height=36, gap=8, label="motion-tabs") {
			for index in 0..<TAB_COUNT {
				if ui.button(
					&ctx, tab_labels[index],
					key=ui.key_u64(u64(index+1)),
					width=tab_width,
					height=36,
					state=ui.Button_State{selected=app.selected == index},
				) {
					app.selected = index
				}
			}
		}
		if ui.row(&ctx, height=4, label="motion-indicator-track") {
			indicator := alicorn.container_begin(
				&ctx,
				.Container,
				label="decorative-motion-indicator",
				key="motion-indicator",
				style=ui.layout_style(.Row, width=tab_width, height=4),
				color=alicorn.Color{0.30, 0.62, 0.98, 1},
			)
			if app.services_ready {
				handle, owner_status := ui.motion_owner_begin(&ctx, indicator)
				if owner_status == .Ok {
					at := host.application_motion_time_now(app.clock)
					target_x := f64(app.selected)*f64(tab_width+8)
					current := ui.motion_presentation(&ctx, handle)
					if current.status == .Ok && current.target_translation.x != target_x {
						status := ui.motion_translation(
							&ctx,
							handle,
							ui.Motion_Vector2{target_x, 0},
							MOTION_CONFIG,
							.Settle,
							at,
						)
						if status != .Ok {
							ui.text(&ctx, fmt.tprintf("Motion target rejected: %v", status))
						}
					}
				}
			}
			alicorn.container_end(&ctx)
		}
		ui.text(&ctx, fmt.tprintf("Selected tab: %s", tab_labels[app.selected]))
		ui.text(&ctx, "The native scheduler coalesces all active motion records into one per-window presentation demand.")
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

services_app :: proc(state: rawptr, services: host.Application_Services) {
	app := cast(^App)state
	app.clock = services.motion_clock
	app.scheduler = services.scheduler
	app.diagnostics = services.diagnostics
	app.services_ready = app.clock.now != nil
	if app.validation_mode {
		app.validation_phase = .Retarget
		_ = host.application_schedule_after(app.scheduler, .Frequent, 100_000_000)
		host.application_diagnostic_event(app.diagnostics, "motion.validation.ready")
	}
}

scheduled_wake_app :: proc(state: rawptr, rt: ^alicorn.Runtime, _class: host.Scheduled_Wake_Class) {
	app := cast(^App)state
	switch app.validation_phase {
	case .Retarget:
		app.selected = 2
		app.validation_phase = .Settled_Check
		alicorn.invalidate_root(rt, "motion validation retarget")
		host.application_diagnostic_event(app.diagnostics, "motion.validation.retargeted")
		_ = host.application_schedule_after(app.scheduler, .Frequent, 1_500_000_000)
	case .Settled_Check:
		activity := alicorn.motion_activity(rt)
		fmt.println("motion_validation", "settled_checkpoint", "active_owners", activity.active_owners,
			"active_properties", activity.active_properties, "unestablished_deadlines", activity.unestablished_deadlines)
		host.application_diagnostic_event(app.diagnostics, "motion.validation.settled_checkpoint")
		if activity.active_owners == 0 {
			app.validation_phase = .Idle_Check
			_ = host.application_schedule_after(app.scheduler, .Frequent, 1_000_000_000)
		} else {
			_ = host.application_schedule_after(app.scheduler, .Frequent, 250_000_000)
		}
	case .Idle_Check:
		activity := alicorn.motion_activity(rt)
		fmt.println("motion_validation", "idle_checkpoint", "active_owners", activity.active_owners,
			"active_properties", activity.active_properties, "unestablished_deadlines", activity.unestablished_deadlines)
		host.application_diagnostic_event(app.diagnostics, "motion.validation.idle_checkpoint")
		app.validation_phase = .Done
	case .None, .Done:
		// Ordinary applications don't install this callback. In validation mode,
		// it only advances the bounded retarget/settlement/idle checkpoints.
	}
}

main :: proc() {
	app := App{}
	validation_smoke := false
	for argument in os.args {
		if argument == "--motion-validation" {
			// Make one delayed logical selection change, then observe the retained
			// response settle and leave an idle interval before bounded shutdown.
			// Run with --diagnostics to capture native scheduler counters.
			app.validation_mode = true
			validation_smoke = true
		}
	}
	host.Run(host.Application{
		state=rawptr(&app),
		title="Alicorn · Retained Motion",
		width=720,
		height=360,
		interaction_update_policy=.Correct_After_Interaction,
		build=build_app,
		on_services=services_app,
		on_scheduled_wake=scheduled_wake_app,
	}, smoke=validation_smoke)
}
