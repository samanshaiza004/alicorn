package main

// Cross-window retained-motion lifecycle fixture for Alicorn #146. The
// primary and secondary SDL windows own independent Runtime instances and
// each animate one decorative marker. The runner minimizes or closes the
// secondary while both responses are active and inspects per-window evidence.

import "core:fmt"
import "core:os"
import alicorn "../../../runtime"
import host "../../../native/sdl_gpu"
import ui "alicorn:ui"

MOTION_START_DELAY_NS :: u64(250_000_000)
READY_CHECK_DELAY_NS  :: u64(300_000_000)
HIDDEN_CHECK_DELAY_NS :: u64(1_400_000_000)
IDLE_PROBE_DELAY_NS   :: u64(12_000_000_000)
POST_CLOSE_CHECK_DELAY_NS :: u64(500_000_000)
MOTION_TARGET_X        :: f64(220)

Validation_Mode :: enum { Restore_Secondary, Close_Secondary }
Validation_Phase :: enum { Retarget, Ready_Check, Hidden_Check, Done }

Shared_State :: struct {
	mode: Validation_Mode,
	secondary_opened: bool,
	open_failures: u64,
}

Window_State :: struct {
	shared: ^Shared_State,
	is_secondary: bool,
	services: host.Application_Services,
	phase: Validation_Phase,
	motion_theme: alicorn.Style_Theme_ID,
	target_x: f64,
}

window_role :: proc(app: ^Window_State) -> string {
	return "secondary" if app != nil && app.is_secondary else "primary"
}

record_checkpoint :: proc(app: ^Window_State, rt: ^alicorn.Runtime, stage: string) {
	if app == nil || app.shared == nil || rt == nil { return }
	activity := alicorn.motion_activity(rt)
	stats := alicorn.motion_diagnostics_stats(rt)
	role := window_role(app)
	fmt.println(
		"motion_secondary_validation",
		"stage", stage,
		"window", role,
		"active_owners", activity.active_owners,
		"sample_ticks", stats.sample_ticks,
		"mode", app.shared.mode,
	)
	base := fmt.tprintf("motion.validation.%s.%s", role, stage)
	host.application_diagnostic_event(
		app.services.diagnostics,
		fmt.tprintf("%s.owners", base),
		u64(max(activity.active_owners, 0)),
	)
	host.application_diagnostic_event(
		app.services.diagnostics,
		fmt.tprintf("%s.samples", base),
		stats.sample_ticks,
	)
}

build_window :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, _logical_height: int,
	_dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Window_State)state
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	role := window_role(app)
	title := "Primary window · active motion continues independently" if !app.is_secondary else "Secondary window · minimize or close me during motion"
	root := alicorn.container_begin(
		&ctx,
		.Root,
		label="motion-cross-window-root",
		style=ui.layout_style(grow=1),
		color=ui.rgb(0x111821),
	)
	if ui.column(&ctx, grow=1, padding=24, gap=14, clip=true, label="motion-cross-window-content") {
		ui.text(&ctx, fmt.tprintf("Alicorn #146 · %s", role), size=24)
		ui.text(&ctx, title)
		ui.text(&ctx, "The marker is decorative. This window has its own retained Runtime and motion scheduler.")
		track := alicorn.container_begin(
			&ctx,
			.Container,
			label="motion-validation-track",
			style=ui.layout_style(.Row, width=max(f32(logical_width-64), 240), height=28),
			color=ui.rgb(0x202A35),
		)
		motion_scope := alicorn.Style_Environment_Scope{}
		if app.motion_theme != 0 {
			motion_scope = alicorn.style_environment_push(
				&ctx,
				alicorn.Style_Environment{theme=app.motion_theme},
			)
		}
		marker := ui.box(
			&ctx,
			key=alicorn.key_string("cross-window-motion-marker"),
			size=16,
			fill=ui.rgb(0x6FA8FF),
			radius=8,
		)
		motion_status := ui.motion(
			&ctx,
			marker,
			ui.Motion_Target{
				translation=ui.Motion_Vector2{app.target_x, 0},
				has_translation=true,
			},
		)
		if motion_status != .Ok {
			ui.text(&ctx, fmt.tprintf("Motion declaration status: %v", motion_status))
		}
		if motion_scope.active { alicorn.style_environment_pop(&ctx, motion_scope) }
		alicorn.container_end(&ctx)
		ui.text(&ctx, fmt.tprintf("Target x: %.0f logical units", app.target_x))
		ui.text(&ctx, "Automated checkpoints report owner activity and retained sample counts to the diagnostic event trail.")
		if app.shared != nil && app.shared.open_failures > 0 {
			ui.text(&ctx, fmt.tprintf("Secondary window open failures: %d", app.shared.open_failures))
		}
	}
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

initialize_window :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	app := cast(^Window_State)state
	if app == nil || rt == nil { return }
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.motion_policy = alicorn.DEFAULT_MOTION_THEME_POLICY
	// Keep both responses active through the hidden checkpoint and restore.
	theme.motion_policy.translation = alicorn.Motion_Config{
		omega=1.2,
		position_tolerance=0.1,
		velocity_tolerance=0.5,
	}
	app.motion_theme = alicorn.style_theme_register(rt, theme)
}

services_window :: proc(state: rawptr, services: host.Application_Services) {
	app := cast(^Window_State)state
	if app != nil { app.services = services }
}

open_secondary :: proc(primary: ^Window_State) -> bool {
	if primary == nil || primary.shared == nil || primary.services.windows.open == nil || primary.shared.secondary_opened {
		return false
	}
	secondary := new(Window_State, allocator=context.allocator)
	if secondary == nil { return false }
	secondary^ = Window_State{shared=primary.shared, is_secondary=true, phase=.Retarget}
	application := host.Application{
		state=rawptr(secondary),
		title="Alicorn #146 Secondary",
		width=720,
		height=360,
		interaction_update_policy=.Correct_After_Interaction,
		on_initialize=initialize_window,
		build=build_window,
		on_services=services_window,
		on_start=start_window,
		on_scheduled_wake=scheduled_wake_window,
		on_stop=stop_window,
	}
	accepted := host.application_open_window(
		primary.services.windows,
		host.Application_Window_Description{
			application=application,
			width=720,
			height=360,
			on_open_failed=secondary_open_failed,
		},
	)
	if !accepted {
		free(secondary, allocator=context.allocator)
		primary.shared.open_failures += 1
		return false
	}
	primary.shared.secondary_opened = true
	return true
}

secondary_open_failed :: proc(state: rawptr) {
	secondary := cast(^Window_State)state
	if secondary != nil && secondary.shared != nil {
		secondary.shared.open_failures += 1
		host.application_diagnostic_event(
			secondary.services.diagnostics,
			"motion.validation.secondary.open_failed",
		)
	}
	free(secondary, allocator=context.allocator)
}

start_window :: proc(state: rawptr, _waker: host.Application_Waker) {
	app := cast(^Window_State)state
	if app == nil || app.shared == nil { return }
	if !app.is_secondary {
		if !open_secondary(app) {
			app.shared.open_failures += 1
			fmt.eprintln("motion_secondary_validation secondary window open failed")
			return
		}
	}
	app.phase = .Retarget
	_ = host.application_schedule_after(app.services.scheduler, .Frequent, MOTION_START_DELAY_NS)
}

scheduled_wake_window :: proc(state: rawptr, rt: ^alicorn.Runtime, _class: host.Scheduled_Wake_Class) {
	app := cast(^Window_State)state
	if app == nil || app.shared == nil || rt == nil { return }
	switch app.phase {
	case .Retarget:
		app.target_x = MOTION_TARGET_X
		app.phase = .Ready_Check
		alicorn.invalidate_root(rt, "secondary motion validation target")
		host.application_diagnostic_event(
			app.services.diagnostics,
			fmt.tprintf("motion.validation.%s.target", window_role(app)),
		)
		_ = host.application_schedule_after(app.services.scheduler, .Frequent, READY_CHECK_DELAY_NS)
	case .Ready_Check:
		record_checkpoint(app, rt, "ready")
		app.phase = .Hidden_Check
		_ = host.application_schedule_after(app.services.scheduler, .Frequent, HIDDEN_CHECK_DELAY_NS)
	case .Hidden_Check:
		record_checkpoint(app, rt, "hidden")
		app.phase = .Done
		if !app.is_secondary && app.shared.mode == .Close_Secondary {
			_ = host.application_schedule_after(app.services.scheduler, .Frequent, POST_CLOSE_CHECK_DELAY_NS)
		} else if app.shared.mode == .Restore_Secondary {
			// Motion reports its idle transition on the next host-loop visit after
			// the final presentation. This one application-owned wake makes that
			// passive snapshot observable even when both windows are then quiet.
			_ = host.application_schedule_after(app.services.scheduler, .Frequent, IDLE_PROBE_DELAY_NS)
		}
	case .Done:
		// In close mode, these low-frequency checkpoints expose whether the
		// surviving primary response remains active after the child is destroyed.
		if !app.is_secondary && app.shared.mode == .Close_Secondary {
			record_checkpoint(app, rt, "post_close")
			if alicorn.motion_activity(rt).active_owners > 0 {
				_ = host.application_schedule_after(app.services.scheduler, .Frequent, POST_CLOSE_CHECK_DELAY_NS)
			}
		} else if app.shared.mode == .Restore_Secondary {
			record_checkpoint(app, rt, "idle_probe")
			if alicorn.motion_activity(rt).active_owners > 0 {
				_ = host.application_schedule_after(app.services.scheduler, .Frequent, POST_CLOSE_CHECK_DELAY_NS)
			}
		}
	}
}

stop_window :: proc(state: rawptr) {
	app := cast(^Window_State)state
	if app == nil { return }
	if app.is_secondary {
		host.application_diagnostic_event(app.services.diagnostics, "motion.validation.secondary.stopped")
		fmt.println("motion_secondary_validation", "secondary_window_stopped")
		free(app, allocator=context.allocator)
	} else {
		fmt.println("motion_secondary_validation", "primary_window_stopped")
	}
}

main :: proc() {
	mode := Validation_Mode.Restore_Secondary
	for argument in os.args {
		if argument == "--validation-mode=close" { mode = .Close_Secondary }
	}
	shared := Shared_State{mode=mode}
	primary := Window_State{shared=&shared, phase=.Retarget}
	host.Run(host.Application{
		state=rawptr(&primary),
		title="Alicorn #146 Primary",
		width=900,
		height=480,
		interaction_update_policy=.Correct_After_Interaction,
		on_initialize=initialize_window,
		build=build_window,
		on_services=services_window,
		on_start=start_window,
		on_scheduled_wake=scheduled_wake_window,
		on_stop=stop_window,
	})
}
