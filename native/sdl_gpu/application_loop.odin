package alicorn_sdl_gpu

import "core:fmt"
import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

// run_application_loop is the reusable native shell. Application state is
// borrowed only through callbacks; retained runtime nodes do not store the
// pointer. SDL, render-pass scheduling, and GPU resource retirement remain
// host responsibilities.
run_application_loop :: proc(
	window: ^sdl3.Window,
	device: ^sdl3.GPUDevice,
	rt: ^alicorn.Runtime,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	metrics: ^Window_Metrics,
	application: Application,
	smoke := false,
	manual_log := false,
	gpu_driver := "unknown",
	validation_timeout_seconds := 0,
	native_menu: ^Native_Menu_Runtime = nil,
) {
	application_instance := application
	if rt != nil && metrics != nil && metrics.logical_width > 0 && metrics.window_logical_height > 0 {
		_ = alicorn.set_presentation_scale(
			rt,
			f32(metrics.pixel_width)/f32(metrics.logical_width),
			f32(metrics.pixel_height)/f32(metrics.window_logical_height),
		)
	}
	if native_menu != nil {
		native_menu.runtime = rt
	}
	quit_requested := false
	logical_resize_events := 0
	pixel_resize_events := 0
	scale_events := 0
	text_input_events := 0
	composition_events := 0
	text_events := Native_Text_Event_Telemetry{}
	devtools_recorder: Native_Flight_Recorder
	devtools_hud := Native_DevTools_HUD{}
	devtools_hud_redraw_pending := false
	devtools_hud_deadline_ns: u64 = 0
	in_flight: [dynamic; 3]Native_In_Flight
	retired := 0
	max_in_flight := 0
	query_before_wait_true := 0
	query_after_wait_true := 0
	wait_count := 0
	submitted := 0
	timing := Native_Host_Timing{}
	diagnostics := native_parse_diagnostics_options()
	inspector: Native_Inspector_Overlay
	if !native_inspector_init(&inspector, device, sdl3.GetGPUSwapchainTextureFormat(device, window), rt.viewport) {
		fail("visual inspector initialization failed")
	}
	defer native_inspector_destroy(&inspector)
	if native_menu != nil { native_menu.inspector = &inspector }
	debug_bounds := diagnostics.debug_bounds
	host_scratch := native_host_scratch_make()
	defer native_host_scratch_destroy(&host_scratch)
	wake_event_id := sdl3.RegisterEvents(1)
	if wake_event_id == 0 { fail("SDL_RegisterEvents failed for application wakeups") }
	wake_state := Native_Application_Waker{event_type=sdl3.EventType(wake_event_id), active=true}
	application_waker := Application_Waker{data=rawptr(&wake_state), wake=native_application_wake}
	host_wake_event_id := sdl3.RegisterEvents(1)
	if host_wake_event_id == 0 { fail("SDL_RegisterEvents failed for host redraw wakeups") }
	host_wake_state := Native_Host_Event_Waker{event_type=sdl3.EventType(host_wake_event_id), active=true}
	appearance_monitor: Native_Appearance_Monitor
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		if !native_appearance_monitor_init(&appearance_monitor, window, &host_wake_state, rt) {
			fmt.println("appearance", "native preference notifications unavailable; using default appearance inputs")
		}
	}
	if native_menu != nil {
		native_menu_accessibility_appearance_changed(
			native_menu,
			appearance_monitor.snapshot.preferences.increased_contrast,
			request_redraw=false,
		)
	}
	accessibility_host: Native_Accessibility_Host
	accessibility_host_ready := false
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		accessibility_host_ready = native_accessibility_host_init(&accessibility_host, &host_wake_state)
		if !accessibility_host_ready { fmt.println("accessibility", "host queue initialization failed; native accessibility is unavailable") }
	}
	defer native_accessibility_host_destroy(&accessibility_host)
	if native_menu != nil { native_menu.host_waker = &host_wake_state }
	scheduler_state := Native_Scheduled_Wake_State{active=true}
	application_scheduler := Application_Scheduler{
		data=rawptr(&scheduler_state),
		schedule=native_application_schedule_after,
		cancel=native_application_cancel_scheduled,
		read_stats=native_application_scheduler_stats,
	}
	dialog_bridge := native_dialog_bridge_make(window, application_waker)
	defer native_dialog_bridge_release(dialog_bridge)
	if application_instance.on_services != nil {
		application_instance.on_services(application_instance.state, Application_Services{
			dialogs=Dialog_Service{handle=rawptr(dialog_bridge)},
			clipboard=native_clipboard_service(),
			scheduler=application_scheduler,
			quit=Application_Quit_Request{data=rawptr(&quit_requested), request=native_application_request_quit},
		})
	}
	if application_instance.on_start != nil {
		application_instance.on_start(application_instance.state, application_waker)
	}

	platform_text := ""
	start := time.now()
	window_flags := sdl3.GetWindowFlags(window)
	text_input_state := Native_Text_Input_State{window_focused=(window_flags & sdl3.WindowFlags{.INPUT_FOCUS}) != sdl3.WindowFlags{}}
	if native_menu != nil { text_input_state.content_inset_top = native_menu.content_inset_top }
	text_input_state.suspended = native_inspector_visible(&inspector)
	pointer_modifier_state := sdl3.GetModState()
	pointer_button_state := Native_Pointer_Button_State{}
	alicorn.invalidate_root(rt, "SDL application initial frame")
	_ = native_application_build_until_stable(&application_instance, rt, metrics, &timing, stop_on_hard_error=inspector.enabled)
	initial_summary := native_inspector_host_summary(&timing, rt, 0)
	native_inspector_update(&inspector, rt, rt.viewport, &initial_summary)
	devtools_cursor := native_devtools_cursor_init(rt, &timing, &text_events)
	sync_text_input_focus(window, rt, &text_input_state, &application_instance)
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		if accessibility_host_ready {
			if native_accessibility_adapter_init(&accessibility_host, window) {
				content_inset := f32(0)
				if native_menu != nil { content_inset = native_menu.content_inset_top }
				_ = native_accessibility_sync(&accessibility_host, rt, content_inset)
			} else {
				fmt.println("accessibility", "AccessKit native adapter initialization failed; continuing without platform semantics")
			}
		}
	}
	if !sdl3.ShowWindow(window) || !sdl3.RaiseWindow(window) { fail("SDL application window could not be shown after native host initialization") }
	live_resize_state := Native_Live_Resize_State{
		active=true,
		window=window,
		device=device,
		rt=rt,
		application=&application_instance,
		metrics=metrics,
		text_renderer=text_renderer,
		surface_renderer=surface_renderer,
		solid_renderer=solid_renderer,
		text_input_state=&text_input_state,
		timing=&timing,
		host_scratch=&host_scratch,
		in_flight=&in_flight,
		retired=&retired,
		max_in_flight=&max_in_flight,
		query_before_wait_true=&query_before_wait_true,
		query_after_wait_true=&query_after_wait_true,
		wait_count=&wait_count,
		submitted=&submitted,
		text_events=&text_events,
		devtools_recorder=&devtools_recorder,
		devtools_cursor=&devtools_cursor,
		devtools_hud=&devtools_hud,
		inspector=&inspector,
		debug_bounds=debug_bounds,
		native_menu=native_menu,
	}
	if !sdl3.AddEventWatch(native_live_resize_event_watch, rawptr(&live_resize_state)) {
		fail("SDL live-resize event watch registration failed")
	}

	last_tick := time.now()
	last_focus_log := start
	wait_for_event := false
	drag_autoscroll_deadline_ns: u64 = 0
	swapchain_retry_pending := false
	last_user_interaction_ns: u64 = 0
	devtools_last_cause: alicorn.Cause_Context
	event_waits: u64 = 0
	wake_events: u64 = 0
	for !quit_requested {
		native_host_scratch_reset(&host_scratch)
		frame_start := time.now()
		event_start := time.now()
		wait_timed_out := false
		validation_timeout_expired := false
		smoke_timeout := false
		wait_timeout_ms: sdl3.Sint32 = -1
		if wait_for_event {
			// A successful swapchain acquisition can still return no drawable while
			// the window is minimized or the swapchain is temporarily unavailable.
			// Keep the presentation revision pending, but sleep between retries and
			// let SDL events wake us as soon as the window can be presented again.
			if swapchain_retry_pending {
				wait_timeout_ms = native_event_wait_timeout_min(wait_timeout_ms, 100)
			}
			// Tick-driven applications still need their regular callback while a
			// drawable is unavailable. Wait only until the next tick rather than
			// turning the retry path into either a busy loop or an indefinite wait.
			if application_instance.on_tick != nil {
				elapsed_ns := time.duration_nanoseconds(time.since(last_tick))
				remaining_ns := i64(16_666_667) - elapsed_ns
				if remaining_ns < 0 { remaining_ns = 0 }
				tick_timeout_ms := sdl3.Sint32((remaining_ns + 999_999) / 1_000_000)
				wait_timeout_ms = sdl3.Sint32(native_event_wait_timeout_min(wait_timeout_ms, tick_timeout_ms))
			}
			current_ns := u64(sdl3.GetTicksNS())
			if drag_autoscroll_deadline_ns != 0 {
				drag_timeout_ms := sdl3.Sint32(scheduled_wake_timeout_ms(drag_autoscroll_deadline_ns, current_ns))
				wait_timeout_ms = sdl3.Sint32(native_event_wait_timeout_min(wait_timeout_ms, drag_timeout_ms))
			}
			if tooltip_deadline := alicorn.tooltip_next_deadline(rt); tooltip_deadline != 0 {
				tooltip_timeout_ms := sdl3.Sint32(scheduled_wake_timeout_ms(tooltip_deadline, current_ns))
				wait_timeout_ms = sdl3.Sint32(native_event_wait_timeout_min(wait_timeout_ms, tooltip_timeout_ms))
			}
			if next_deadline, found := scheduled_wake_next_deadline(&scheduler_state); found {
				scheduled_timeout_ms := sdl3.Sint32(scheduled_wake_timeout_ms(next_deadline, current_ns))
				wait_timeout_ms = sdl3.Sint32(native_event_wait_timeout_min(wait_timeout_ms, scheduled_timeout_ms))
			}
			if devtools_hud.visible && devtools_hud_deadline_ns != 0 {
				hud_timeout_ms := sdl3.Sint32(scheduled_wake_timeout_ms(devtools_hud_deadline_ns, current_ns))
				wait_timeout_ms = sdl3.Sint32(native_event_wait_timeout_min(wait_timeout_ms, hud_timeout_ms))
			}
			if smoke {
				elapsed := time.duration_nanoseconds(time.since(start))
				remaining := i64(3_000_000_000) - elapsed
				if remaining <= 0 {
					quit_requested = true
					continue
				}
				smoke_timeout_ms := u64((remaining + 999_999) / 1_000_000)
				if wait_timeout_ms < 0 || smoke_timeout_ms < u64(wait_timeout_ms) {
					wait_timeout_ms = sdl3.Sint32(min(smoke_timeout_ms, u64(0x7fff_ffff)))
					smoke_timeout = true
				}
			}
			if validation_timeout_seconds > 0 {
				elapsed := time.duration_nanoseconds(time.since(start))
				remaining := i64(validation_timeout_seconds)*1_000_000_000 - elapsed
				if remaining <= 0 {
					quit_requested = true
					continue
				}
				idle_timeout_ms := u64((remaining + 999_999) / 1_000_000)
				if wait_timeout_ms < 0 || idle_timeout_ms < u64(wait_timeout_ms) {
					wait_timeout_ms = sdl3.Sint32(min(idle_timeout_ms, u64(0x7fff_ffff)))
					validation_timeout_expired = true
					smoke_timeout = false
				}
			}
			swapchain_retry_pending = false
		}
		pump_events(
			window, rt, metrics, &quit_requested,
			&logical_resize_events, &pixel_resize_events, &scale_events,
			&text_input_events, &composition_events, &platform_text,
			manual_log=manual_log,
			application=&application_instance,
			diagnostics_capture_requested=&diagnostics.capture_requested,
			debug_bounds=&debug_bounds,
			telemetry=&text_events,
			wake_event=sdl3.EventType(wake_event_id),
			wake_event_enabled=true,
			host_wake_event=sdl3.EventType(host_wake_event_id),
			host_wake_event_enabled=true,
			wait_for_event=wait_for_event,
			event_waits=&event_waits,
			wake_events=&wake_events,
			native_host_wake_events=&timing.native_host_wake_events,
			wait_timeout_ms=wait_timeout_ms,
			wait_timed_out=&wait_timed_out,
			native_menu=native_menu,
			last_user_interaction_ns=&last_user_interaction_ns,
			text_input_state=&text_input_state,
			pointer_modifier_state=&pointer_modifier_state,
			pointer_button_state=&pointer_button_state,
			devtools_hud=&devtools_hud,
			devtools_hud_redraw_pending=&devtools_hud_redraw_pending,
			devtools_last_cause=&devtools_last_cause,
			inspector=&inspector,
			accessibility=&accessibility_host,
			appearance_monitor=&appearance_monitor,
		)
		_ = alicorn.tooltip_advance(rt, u64(sdl3.GetTicksNS()))
		native_drag_autoscroll_update(rt, &drag_autoscroll_deadline_ns, u64(sdl3.GetTicksNS()))
		if native_menu != nil {
			if command, ok := native_menu_take_pending(native_menu); ok {
				native_menu_dispatch_command(native_menu, command)
			}
		}
		native_dialog_dispatch(dialog_bridge, &application_instance, rt)
		wait_for_event = false
		if !quit_requested {
			native_dispatch_scheduled_wakes(&application_instance, rt, &scheduler_state, last_user_interaction_ns, &timing)
		}
		if wait_timed_out && (validation_timeout_expired || smoke_timeout) {
			quit_requested = true
			continue
		}
		native_timing_accumulate(&timing.event_pump_ns, &timing.event_pump_max_ns, u64(time.duration_nanoseconds(time.since(event_start))) )
		if quit_requested { break }

		now := time.now()
		when ODIN_OS == .Darwin {
			if manual_log && time.duration_nanoseconds(time.since(last_focus_log)) >= 1_000_000_000 {
				focus := darwin_focus_state(window)
				fmt.println(
					"darwin_focus",
					"app_active", focus.app_active,
					"key_window", focus.key_window,
					"sdl_input_focus", focus.input_focus,
				)
				last_focus_log = now
			}
		}
		if smoke && time.duration_nanoseconds(time.since(start)) >= 3_000_000_000 {
			quit_requested = true
			continue
		}
		if application_instance.on_tick != nil && time.duration_nanoseconds(time.since(last_tick)) >= 16_666_667 {
			tick_start := time.now()
			timing.application_tick_calls += 1
			tick_cause := alicorn.cause_begin(rt, .Application, "application tick")
			devtools_last_cause = tick_cause.cause
			application_instance.on_tick(application_instance.state, rt)
			alicorn.cause_end(rt, tick_cause)
			native_timing_accumulate(&timing.application_tick_ns, &timing.application_tick_max_ns, u64(time.duration_nanoseconds(time.since(tick_start))) )
			last_tick = now
		}

		if rt.invalidated && (!inspector.enabled || !rt.hard_error) {
			_ = native_application_build_until_stable(&application_instance, rt, metrics, &timing, stop_on_hard_error=inspector.enabled)
		}
		if alicorn.drag_is_active(rt) && !rt.invalidated && !native_inspector_visible(&inspector) {
			alicorn.drag_refresh_target(rt)
			_ = native_dispatch_drag_event(&application_instance, rt)
			if rt.invalidated {
				_ = native_application_build_until_stable(&application_instance, rt, metrics, &timing, stop_on_hard_error=inspector.enabled)
			}
		}
		// A focus or caret change can update the platform candidate anchor
		// without requiring a procedural description rebuild.
		sync_text_input_focus(window, rt, &text_input_state, &application_instance)

		// Interaction-only invalidation updates retained paint without asking the
		// application to rebuild its procedural description. Flush that retained
		// presentation before submitting the next GPU frame.
		if !rt.invalidated && (!inspector.enabled || !rt.hard_error) && alicorn.presentation_needs_frame(rt) {
			presentation_ui, ready := alicorn.begin_presentation_frame(rt)
			if ready {
				alicorn.end_presentation_frame(&presentation_ui)
			}
		}
		when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		if accessibility_host_ready {
			content_inset := f32(0)
			if native_menu != nil { content_inset = native_menu.content_inset_top }
			_ = native_accessibility_sync(&accessibility_host, rt, content_inset)
			accessibility_counters := native_accessibility_take_counters(&accessibility_host)
			rt.stats.accessibility_activation_wakes += accessibility_counters.activation_wakes
			rt.stats.accessibility_updates_submitted += accessibility_counters.updates_submitted
			rt.stats.accessibility_requests_received += accessibility_counters.actions_received
			rt.stats.accessibility_requests_dropped += accessibility_counters.actions_dropped
		}
		}

		inspector_summary := native_inspector_host_summary(&timing, rt, event_waits+wake_events)
		native_inspector_update(&inspector, rt, alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)}, &inspector_summary)
		// A toolbar Close can be consumed during this description, after the
		// native pump has already drained. Resume its preserved app owner now.
		native_inspector_finish_input_pump(&inspector, &text_input_state)
		sync_text_input_focus(window, rt, &text_input_state, &application_instance)
		application_submission_pending := alicorn.frame_needs_submission(rt)
		native_chrome_submission_pending := native_menu != nil && native_menu.chrome_redraw_pending
		inspector_submission_pending := native_inspector_submission_pending(&inspector)
		devtools_cause := devtools_last_cause
		if devtools_cause.kind == .None { devtools_cause = rt.frame_cause }
		if rt.pending_work_seen { devtools_cause = rt.pending_work_cause if !rt.pending_work_mixed else alicorn.Cause_Context{} }
		if rt.submission_cause_seen {
			devtools_cause = rt.submission_cause if !rt.submission_cause_mixed else alicorn.Cause_Context{}
		}
		if devtools_cause.kind == .None { devtools_cause = alicorn.Cause_Context{kind=.Host_Event} }
		devtools_sample_time_ns := u64(sdl3.GetTicksNS())
		devtools_preview := native_devtools_make_sample(
			&devtools_cursor, rt, &timing, &text_events, devtools_cause, devtools_sample_time_ns, host_wakes=0,
		)
		if application_submission_pending { devtools_preview.gpu_submissions += 1 }
		if text_events.pending_input_timestamp > 0 && devtools_sample_time_ns >= text_events.pending_input_timestamp {
			// While a presentation is still being encoded, the HUD's IN~ value is
			// the elapsed lower bound. The finalized recorder sample below replaces
			// it with the exact input-to-submit duration.
			devtools_preview.input_to_submit_ns = devtools_sample_time_ns-text_events.pending_input_timestamp
		}
		devtools_hud_deadline_wake := wait_timed_out && devtools_hud.visible && devtools_hud_deadline_ns != 0 &&
			devtools_sample_time_ns >= devtools_hud_deadline_ns
		devtools_wake_observed := native_devtools_observed_wake(&devtools_cursor, devtools_preview, &timing, &text_events)
		if devtools_wake_observed && !devtools_hud_deadline_wake { devtools_preview.host_wakes = 1 }
		if devtools_hud.visible && (devtools_wake_observed || devtools_hud_deadline_wake) {
			devtools_hud_redraw_pending = true
		}
		if native_frame_submission_requested(
			application_submission_pending,
			native_chrome_submission_pending,
			devtools_hud_redraw_pending,
			inspector_submission_pending,
		) {
			if len(in_flight) >= 2 {
				if !wait_and_retire_oldest(device, &in_flight, &query_before_wait_true, &query_after_wait_true, &wait_count, &timing) {
					fail("SDL application fence retirement failed")
				}
				retired += 1
			}
			encode_start := time.now()
			command := sdl3.AcquireGPUCommandBuffer(device)
			if command == nil { fail("SDL application command acquisition failed") }
			swapchain: ^sdl3.GPUTexture
			swap_w, swap_h: sdl3.Uint32
			if !sdl3.AcquireGPUSwapchainTexture(command, window, &swapchain, &swap_w, &swap_h) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL application swapchain acquisition failed")
			}
			if swapchain == nil || swap_w == 0 || swap_h == 0 {
				_ = sdl3.CancelGPUCommandBuffer(command)
				swapchain_retry_pending = true
				wait_for_event = true
				native_devtools_record_wake(&devtools_recorder, &devtools_cursor, rt, &timing, &text_events,
					devtools_cause, devtools_sample_time_ns, devtools_preview.host_wakes)
				devtools_last_cause = {}
				if devtools_hud.visible {
					devtools_hud_deadline_ns = native_devtools_hud_next_wake_ns(&devtools_recorder, u64(sdl3.GetTicksNS()))
				}
				continue
			}
			metrics.pixel_width = int(swap_w)
			metrics.pixel_height = int(swap_h)
			logical_to_pixel_x := f32(swap_w) / f32(metrics.logical_width)
			logical_to_pixel_y := f32(swap_h) / f32(metrics.window_logical_height)
			_ = alicorn.set_presentation_scale(rt, logical_to_pixel_x, logical_to_pixel_y)
			renderer_metrics_before := native_devtools_renderer_metrics_capture(text_renderer, surface_renderer, solid_renderer)
			hud_vertex_reserve := 0
			if devtools_hud.visible { hud_vertex_reserve = NATIVE_DEVTOOLS_HUD_RESERVE_VERTICES }
			content_inset_top := f32(0)
			if native_menu != nil { content_inset_top = native_menu.content_inset_top }
			if !draw_display_list(
				command, swapchain, swap_w, swap_h,
				text_renderer, surface_renderer, solid_renderer, rt.display[:],
				logical_to_pixel_x, logical_to_pixel_y,
				debug_bounds=debug_bounds,
				reserve_solid_vertices=hud_vertex_reserve,
				content_inset_top=content_inset_top,
				native_menu=native_menu,
				scratch_allocator=host_scratch.allocator,
			) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("SDL application display-list draw failed")
			}
			application_encode_elapsed := u64(time.duration_nanoseconds(time.since(encode_start)))
			if application_submission_pending {
				timing.application_gpu_encode_ns += application_encode_elapsed
			} else if inspector_submission_pending {
				timing.inspector_encode_ns += application_encode_elapsed
			} else if native_chrome_submission_pending {
				timing.native_chrome_encode_ns += application_encode_elapsed
			} else {
				// A HUD-only wake redraws the swapchain's base scene too; attribute
				// those host-forced draw costs to DevTools, not app interaction.
				timing.devtools_hud_encode_ns += application_encode_elapsed
			}
			hud_encode_start := time.now()
			if !native_devtools_hud_render(
				&devtools_hud, solid_renderer, command, swapchain, swap_w, swap_h,
				f32(swap_w)/f32(metrics.logical_width), f32(swap_h)/f32(metrics.logical_height),
				&devtools_recorder, u64(sdl3.GetTicksNS()), devtools_preview,
				preview_valid=devtools_hud.visible,
				last_invalidation=rt.last_invalidation_reason,
			) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("Alicorn DevTools HUD draw failed")
			}
			if !application_submission_pending {
				native_devtools_renderer_metrics_restore(text_renderer, surface_renderer, solid_renderer, renderer_metrics_before)
			}
			hud_encode_elapsed := u64(time.duration_nanoseconds(time.since(hud_encode_start)))
			if devtools_hud.visible { timing.devtools_hud_encode_ns += hud_encode_elapsed }
			inspector_encode_start := time.now()
			if !native_inspector_render(&inspector, surface_renderer, command, swapchain, swap_w, swap_h,
				logical_to_pixel_x, logical_to_pixel_y, scratch_allocator=host_scratch.allocator) {
				_ = sdl3.CancelGPUCommandBuffer(command)
				fail("Alicorn visual inspector draw failed")
			}
			if native_inspector_visible(&inspector) {
				timing.inspector_encode_ns += u64(time.duration_nanoseconds(time.since(inspector_encode_start)))
			}
			total_encode_elapsed := u64(time.duration_nanoseconds(time.since(encode_start)))
			native_timing_accumulate(&timing.gpu_encode_ns, &timing.gpu_encode_max_ns, total_encode_elapsed)
			submit_start := time.now()
			fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
			native_timing_accumulate(&timing.gpu_submit_ns, &timing.gpu_submit_max_ns, u64(time.duration_nanoseconds(time.since(submit_start))) )
			if fence == nil {
				fail("SDL application submission failed")
			}
			append(&in_flight, Native_In_Flight{fence})
			native_text_commit_submission(text_renderer)
			native_surface_commit_submission(surface_renderer)
			native_solid_commit_submission(solid_renderer)
			native_inspector_submission_succeeded(&inspector)
			if native_inspector_visible(&inspector) { timing.inspector_submissions += 1 }
			if application_submission_pending {
				alicorn.gpu_surface_frame_consumed(rt)
				// A retained frame remains pending until this successful submit
				// acknowledgement. A HUD-only redraw has no app revision to acknowledge.
				alicorn.frame_submission_succeeded(rt)
			}
			submitted += 1
			timing.gpu_submissions += 1
			if application_submission_pending {
				rt.stats.gpu_submits += 1
				native_note_input_submission(&text_events)
			}
			devtools_hud_redraw_pending = false
			if native_menu != nil { native_menu.chrome_redraw_pending = false }
			if len(in_flight) > max_in_flight { max_in_flight = len(in_flight) }
			// Refresh source submit/revision truth once after an app submit. The
			// resulting inspector-only submission never acknowledges the app,
			// so this follow-up converges and leaves an event-driven app asleep.
			if application_submission_pending {
				post_submit_summary := native_inspector_host_summary(&timing, rt, event_waits+wake_events)
				native_inspector_update(&inspector, rt, inspector.runtime.viewport, &post_submit_summary)
			}
		}
		if !native_application_has_pending_work(rt, suspend_hard_error=inspector.enabled) && !native_inspector_submission_pending(&inspector) && !devtools_hud_redraw_pending &&
			!(native_menu != nil && native_menu.chrome_redraw_pending) {
			if application_instance.on_tick == nil {
				// Event-driven apps wait for either input, a worker wake, or their
				// nearest scheduled deadline; there is no display-cadence tick.
				// A bounded smoke run adds its own final event-loop deadline.
				wait_for_event = true
			} else {
				sdl3.Delay(1)
			}
		}
		native_timing_add_frame(&timing, u64(time.duration_nanoseconds(time.since(frame_start))))
		scheduler_stats := scheduled_wake_read_stats(&scheduler_state)
		timing.frequent_wakes = scheduler_stats.frequent_wakes
		timing.opportunistic_wakes = scheduler_stats.opportunistic_wakes
		timing.scheduled_requests = scheduler_stats.scheduled
		timing.schedule_coalesces = scheduler_stats.coalesced
		timing.opportunistic_deferrals = scheduler_stats.opportunistic_deferrals
		timing.maximum_scheduled_lateness_ns = scheduler_stats.maximum_lateness_ns
		native_devtools_record_wake(&devtools_recorder, &devtools_cursor, rt, &timing, &text_events,
			devtools_cause, devtools_sample_time_ns, devtools_preview.host_wakes)
		devtools_last_cause = {}
		devtools_hud_deadline_ns = 0
		if devtools_hud.visible {
			devtools_hud_deadline_ns = native_devtools_hud_next_wake_ns(&devtools_recorder, u64(sdl3.GetTicksNS()))
		}
		if native_write_diagnostics(&diagnostics, start, gpu_driver, metrics^, rt, text_renderer, surface_renderer, solid_renderer, &timing, &text_events, &devtools_recorder) {
			screenshot_path := fmt.tprintf("%s/screenshot.ppm", diagnostics.last_capture_dir)
			if native_capture_display_ppm(
				device, text_renderer, surface_renderer, solid_renderer, rt.display[:],
				sdl3.Uint32(metrics.pixel_width), sdl3.Uint32(metrics.pixel_height),
				f32(metrics.pixel_width) / f32(metrics.logical_width),
				f32(metrics.pixel_height) / f32(metrics.logical_height),
				screenshot_path,
				debug_bounds=debug_bounds,
				inspector=&inspector,
			) {
				fmt.println("alicorn_diagnostics", "screenshot", screenshot_path)
			} else {
				fmt.println("alicorn_diagnostics", "screenshot_failed", screenshot_path)
			}
		}
	}

	live_resize_state.active = false
	sdl3.RemoveEventWatch(native_live_resize_event_watch, rawptr(&live_resize_state))
	native_accessibility_host_shutdown(&accessibility_host)
	if native_menu != nil { native_menu.inspector = nil }
	if !sdl3.WaitForGPUIdle(device) { fail("SDL application GPU idle wait failed") }
	native_dialog_bridge_shutdown(dialog_bridge)
	native_cancel_current_text_composition(&application_instance, rt, &text_input_state, "application shutdown")
	if text_input_state.active {
		_ = sdl3.ClearComposition(window)
		_ = sdl3.StopTextInput(window)
		text_input_state.active = false
		text_input_state.owner = 0
	}
	if application_instance.on_stop != nil {
		// Stop worker threads while the host-owned waker state is still alive.
		// This prevents a late worker completion from calling through a stack
		// address after run_application_loop returns.
		application_instance.on_stop(application_instance.state)
	}
	native_appearance_monitor_destroy(&appearance_monitor)
	scheduler_state.active = false
	for &pending in scheduler_state.pending { pending = false }
	wake_state.active = false
	host_wake_state.active = false
	if native_menu != nil { native_menu.host_waker = nil }
	for entry in in_flight {
		sdl3.ReleaseGPUFence(device, entry.fence)
		retired += 1
	}
	clear(&in_flight)
	elapsed_ns := time.duration_nanoseconds(time.since(start))
	fmt.println(
		"SDL application PASS",
		"submissions", submitted,
		"retired", retired,
		"max_frames_in_flight", max_in_flight,
		"wall_ns", elapsed_ns,
		"logical_resize_events", logical_resize_events,
		"pixel_resize_events", pixel_resize_events,
		"scale_events", scale_events,
		"text_input_events", text_input_events,
		"composition_events", composition_events,
		"text_change_dispatches", text_events.text_change_dispatches,
		"text_changes", text_events.text_changes,
		"text_edit_key_events", text_events.text_edit_key_events,
		"text_navigation_key_events", text_events.text_navigation_key_events,
		"text_selection_key_events", text_events.text_selection_key_events,
		"text_word_key_events", text_events.text_word_key_events,
		"events_per_pump_max", text_events.events_per_pump_max,
		"oldest_event_age_max_ns", text_events.oldest_event_age_max_ns,
		"input_to_submit_p95_ns", native_timing_percentile(text_events.input_to_submit_samples[:], 0.95),
		"input_to_submit_max_ns", text_events.input_to_submit_max_ns,
		"text_mesh_rebuilds", text_renderer.mesh_rebuilds,
		"text_mesh_cache_hits", text_renderer.mesh_cache_hits,
		"text_fingerprint_ns", text_renderer.fingerprint_ns,
		"text_fingerprint_bytes", text_renderer.fingerprint_bytes,
		"text_mesh_rebuild_ns", text_renderer.mesh_rebuild_ns,
		"text_vertex_uploads", text_renderer.vertex_uploads,
		"frame_p95_ns", native_timing_percentile(timing.frame_samples[:], 0.95),
		"gpu_encode_ns", timing.gpu_encode_ns,
		"inspector_encode_ns", timing.inspector_encode_ns,
		"inspector_submissions", timing.inspector_submissions,
		"gpu_submit_ns", timing.gpu_submit_ns,
		"fence_wait_ns", timing.fence_wait_ns,
		"application_tick_max_ns", timing.application_tick_max_ns,
		"application_build_max_ns", timing.application_build_max_ns,
		"application_stabilization_rebuilds", timing.application_stabilization_rebuilds,
		"application_stabilization_limit_hits", timing.application_stabilization_limit_hits,
		"event_waits", event_waits,
		"application_wake_events", wake_events,
		"native_host_wake_events", timing.native_host_wake_events,
		"native_chrome_encode_ns", timing.native_chrome_encode_ns,
		"gpu_encode_max_ns", timing.gpu_encode_max_ns,
		"fence_wait_max_ns", timing.fence_wait_max_ns,
	)
}
