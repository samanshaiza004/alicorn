package alicorn_sdl_gpu

import "core:fmt"
import alicorn "../../runtime"
import "vendor:sdl3"

native_drag_autoscroll_update :: proc(rt: ^alicorn.Runtime, deadline_ns: ^u64, now_ns: u64) {
	if deadline_ns == nil { return }
	if rt == nil || !alicorn.drag_autoscroll_can_step(rt) {
		deadline_ns^ = 0
		return
	}
	if deadline_ns^ == 0 {
		deadline_ns^ = now_ns+NATIVE_DRAG_AUTOSCROLL_INTERVAL_NS
		return
	}
	if now_ns < deadline_ns^ { return }
	_ = alicorn.drag_autoscroll_step(rt, NATIVE_DRAG_AUTOSCROLL_INTERVAL_NS)
	if alicorn.drag_autoscroll_can_step(rt) {
		deadline_ns^ = now_ns+NATIVE_DRAG_AUTOSCROLL_INTERVAL_NS
	} else {
		deadline_ns^ = 0
	}
}

pump_events :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	metrics: ^Window_Metrics,
	quit_requested: ^bool,
	logical_resize_events, pixel_resize_events, scale_events: ^int,
	text_input_events, composition_events: ^int,
	app_text: ^string,
	manual_log := false,
	application: ^Application = nil,
	diagnostics_capture_requested: ^bool = nil,
	debug_bounds: ^bool = nil,
	telemetry: ^Native_Text_Event_Telemetry = nil,
	wake_event: sdl3.EventType = .FIRST,
	wake_event_enabled := false,
	wait_for_event := false,
	event_waits: ^u64 = nil,
	wake_events: ^u64 = nil,
	wait_timeout_ms: sdl3.Sint32 = -1,
	wait_timed_out: ^bool = nil,
	native_menu: ^Native_Menu_Runtime = nil,
	last_user_interaction_ns: ^u64 = nil,
	text_input_state: ^Native_Text_Input_State = nil,
	pointer_modifier_state: ^sdl3.Keymod = nil,
	pointer_button_state: ^Native_Pointer_Button_State = nil,
	devtools_hud: ^Native_DevTools_HUD = nil,
	devtools_hud_redraw_pending: ^bool = nil,
	devtools_last_cause: ^alicorn.Cause_Context = nil,
	inspector: ^Native_Inspector_Overlay = nil,
) {
	if telemetry != nil { telemetry.events_this_pump = 0 }
	mod_state := sdl3.GetModState()
	if pointer_modifier_state != nil { mod_state = pointer_modifier_state^ }
	event: sdl3.Event
	when ODIN_OS == .Darwin {
		pump_platform_events()
	}
	has_event := false
	if wait_for_event {
		if event_waits != nil { event_waits^ += 1 }
		if wait_timeout_ms >= 0 {
			has_event = sdl3.WaitEventTimeout(&event, wait_timeout_ms)
		} else {
			has_event = sdl3.WaitEvent(&event)
		}
		if !has_event && wait_timed_out != nil { wait_timed_out^ = true }
	} else {
		has_event = poll_sdl_event(&event)
	}
	for has_event {
		// SDL mouse-button events carry no modifier snapshot. Track keyboard
		// snapshots in queue order; GetModState seeds the pump and focus gain.
		pointer_modifier_state_update(pointer_modifier_state, event)
		if event.type == .KEY_DOWN || event.type == .KEY_UP ||
			event.type == .WINDOW_FOCUS_LOST || event.type == .WINDOW_FOCUS_GAINED {
			if pointer_modifier_state != nil { mod_state = pointer_modifier_state^ }
		}
		pointer, pointer_ok := pointer_from_sdl_with_modifiers(event, mod_state, pointer_button_state)
		if telemetry != nil { telemetry.events_received_sequence += 1 }
		if last_user_interaction_ns != nil && native_event_is_user_interaction(event.type) {
			last_user_interaction_ns^ = u64(sdl3.GetTicksNS())
		}
		if native_inspector_route_event(
			inspector, rt, event, mod_state, application, text_input_state, window,
			translated_pointer=pointer, translated_pointer_ok=pointer_ok,
		) {
			// Host diagnostics are available while the inspector owns input. Do
			// not pass these keys through app shortcut or text routing first.
			if event.type == .KEY_DOWN && event.key.down && !event.key.repeat {
				if event.key.key == sdl3.K_F12 && diagnostics_capture_requested != nil { diagnostics_capture_requested^ = true }
				if event.key.key == sdl3.K_F11 && debug_bounds != nil {
					debug_bounds^ = !debug_bounds^
					if inspector != nil { inspector.redraw_pending = true }
				}
				if event.key.key == sdl3.K_F10 && !native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) && devtools_hud != nil {
					native_devtools_hud_toggle(devtools_hud)
					if devtools_hud_redraw_pending != nil { devtools_hud_redraw_pending^ = true }
				}
			}
			has_event = poll_sdl_event(&event)
			continue
		}
		if telemetry != nil {
			event_timestamp: u64 = 0
			#partial switch event.type {
			case .KEY_DOWN, .KEY_UP: event_timestamp = u64(event.key.timestamp)
			case .TEXT_INPUT: event_timestamp = u64(event.text.timestamp)
			case .TEXT_EDITING: event_timestamp = u64(event.edit.timestamp)
			case .MOUSE_MOTION: event_timestamp = u64(event.motion.timestamp)
			case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP: event_timestamp = u64(event.button.timestamp)
			case .MOUSE_WHEEL: event_timestamp = u64(event.wheel.timestamp)
			}
			if event_timestamp != 0 { native_note_input_event(telemetry, event_timestamp) }
		}
		if manual_log {
			if event.type == .WINDOW_FOCUS_GAINED {
				fmt.println("sdl_event", "WINDOW_FOCUS_GAINED")
			} else if event.type == .WINDOW_FOCUS_LOST {
				fmt.println("sdl_event", "WINDOW_FOCUS_LOST")
			} else if event.type == .MOUSE_BUTTON_DOWN || event.type == .MOUSE_BUTTON_UP {
				fmt.println("sdl_event", "MOUSE_BUTTON", "x", event.button.x, "y", event.button.y, "button", event.button.button, "down", event.button.down)
			}
		}
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			close_result := Application_Close_Result.Allow
			if application != nil && application.on_close_requested != nil {
				close_result = application.on_close_requested(application.state, rt)
			}
			if close_result == .Allow { quit_requested^ = true }
		}
		if event.type == .WINDOW_FOCUS_LOST {
			alicorn.context_menu_close(rt)
			alicorn.tooltip_dismiss(rt)
			if text_input_state != nil {
				text_input_state.window_focused = false
				native_cancel_current_text_composition(application, rt, text_input_state, "window focus lost")
			}
			// SDL releases its automatic mouse capture when focus leaves the
			// window. Drop the matching retained press/drag state as well so a
			// later motion cannot resume an abandoned scrollbar or split drag.
			captured := rt.captured_node
			cancel_cause := alicorn.pointer_cause_begin(rt, .Cancel)
			if devtools_last_cause != nil { devtools_last_cause^ = cancel_cause.cause }
			_ = alicorn.cancel_pointer_capture(rt)
			_ = native_dispatch_drag_event(application, rt)
			if application != nil && application.on_pointer != nil {
				cancelled_pointer := alicorn.Pointer_Event{kind=.Cancel}
				if key, key_ok := alicorn.node_identity_key(rt, captured); key_ok {
					cancelled_pointer.target_key = key
				}
				application.on_pointer(application.state, rt, cancelled_pointer, captured)
			}
			alicorn.cause_end(rt, cancel_cause)
		}
		if event.type == .WINDOW_MOUSE_LEAVE {
			alicorn.tooltip_dismiss(rt)
		}
		if event.type == .WINDOW_FOCUS_GAINED && text_input_state != nil {
			text_input_state.window_focused = true
		}
		if application != nil && application.on_wake != nil && wake_event_enabled && event.type == wake_event {
			if wake_events != nil { wake_events^ += 1 }
			wake_cause := alicorn.cause_begin(rt, .Async_Wake, "application wake event")
			if devtools_last_cause != nil { devtools_last_cause^ = wake_cause.cause }
			application.on_wake(application.state, rt)
			alicorn.cause_end(rt, wake_cause)
		}
		if pointer_ok {
			pointer.timestamp_ns = u64(sdl3.GetTicksNS())
			pointer_cause := alicorn.pointer_cause_begin(rt, pointer.kind)
			if devtools_last_cause != nil { devtools_last_cause^ = pointer_cause.cause }
			target := alicorn.process_pointer(rt, pointer)
			if key, key_ok := alicorn.node_identity_key(rt, target); key_ok {
				pointer.target_key = key
			}
			drag_event_dispatched := native_dispatch_drag_event(application, rt)
			drag_consumed := drag_event_dispatched || alicorn.drag_is_active(rt)
			if application != nil && application.on_pointer != nil && !alicorn.context_menu_pointer_consumed(rt) && !drag_consumed {
				application.on_pointer(application.state, rt, pointer, target)
				// App-level pointer handlers can mutate their own state even when
				// the hit test intentionally returns no retained target. Preserve
				// the historical description refresh for those explicit handlers;
				// otherwise an inert surface/background click stays presentation-only.
				if pointer.kind == .Down || pointer.kind == .Up {
					alicorn.invalidate_root(rt, "application pointer callback")
				}
			}
			alicorn.cause_end(rt, pointer_cause)
		}
		if application != nil && event.type == .MOUSE_WHEEL {
			alicorn.tooltip_dismiss(rt)
			scroll_cause := alicorn.cause_begin(rt, .Scroll, "mouse wheel")
			if devtools_last_cause != nil { devtools_last_cause^ = scroll_cause.cause }
			delta_x := event.wheel.x
			delta_y := event.wheel.y
			ticks_x := int(event.wheel.integer_x)
			ticks_y := int(event.wheel.integer_y)
			mod := sdl3.GetModState()
			modifiers := alicorn.Input_Modifiers{
				shift=native_text_modifier(mod, sdl3.KMOD_SHIFT),
				control=native_text_modifier(mod, sdl3.KMOD_CTRL),
				alt=native_text_modifier(mod, sdl3.KMOD_ALT),
				super=native_text_modifier(mod, sdl3.KMOD_GUI),
			}
			// SDL already reports the platform's chosen scroll direction. Keep
			// precise deltas and the native natural-scroll preference intact;
			// retained regions apply their own logical offset convention.
			dispatched_to_scroll_region := alicorn.process_scroll(rt, alicorn.Scroll_Event{
				delta_x=delta_x,
				delta_y=delta_y,
				ticks_x=ticks_x,
				ticks_y=ticks_y,
				x=event.wheel.mouse_x,
				y=event.wheel.mouse_y,
				modifiers=modifiers,
			})
			if !dispatched_to_scroll_region && application.on_scroll != nil {
				application.on_scroll(application.state, rt, alicorn.Scroll_Event{
					delta_x=delta_x,
					delta_y=delta_y,
					ticks_x=ticks_x,
					ticks_y=ticks_y,
					x=event.wheel.mouse_x,
					y=event.wheel.mouse_y,
					modifiers=modifiers,
				})
			}
			alicorn.cause_end(rt, scroll_cause)
		}
		if event.type == .KEY_DOWN && event.key.down {
			alicorn.tooltip_dismiss(rt)
			key_cause := alicorn.cause_begin(rt, .Keyboard, "SDL key down")
			if devtools_last_cause != nil { devtools_last_cause^ = key_cause.cause }
			context_menu_handled := alicorn.context_menu_handle_key(rt, native_context_menu_key_from_sdl(event.key.key))
			drag_cancelled := false
			if !context_menu_handled && event.key.key == sdl3.K_ESCAPE && alicorn.drag_is_active(rt) {
				_ = alicorn.drag_cancel(rt)
				_ = native_dispatch_drag_event(application, rt)
				drag_cancelled = true
			}
			menu_shortcut_handled := !context_menu_handled && !drag_cancelled && native_menu_try_shortcut(native_menu, int(event.key.key), event.key.mod)
			devtools_hotkey_handled := false
			if !menu_shortcut_handled && event.key.key == sdl3.K_F10 &&
				!native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) && !event.key.repeat && devtools_hud != nil {
				native_devtools_hud_toggle(devtools_hud)
				if devtools_hud_redraw_pending != nil { devtools_hud_redraw_pending^ = true }
				devtools_hotkey_handled = true
			}
			runtime_key_handled := context_menu_handled || drag_cancelled || menu_shortcut_handled || devtools_hotkey_handled
			if !runtime_key_handled && event.key.key == sdl3.K_F10 &&
				native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) && !event.key.repeat &&
				application != nil && application.on_key != nil {
				runtime_key_handled = application.on_key(application.state, rt, .Context_Menu)
				if runtime_key_handled { alicorn.invalidate_root(rt, "application opened context menu from keyboard") }
			}
			// Let transient application UI intercept navigation and dismissal
			// while a text-input owner has focus. Returning false preserves the
			// normal caret/composition behavior below.
			if !runtime_key_handled && application != nil && application.on_key != nil {
				text_input_focused := native_current_text_input_owner(rt, text_input_state) != 0
				composition_active := false
				if node, ok := rt.nodes[rt.focused]; ok {
					composition_active = node.composition.active
				}
				if text_input_state != nil && text_input_state.composition_owner == rt.focused {
					composition_active = true
				}
				if text_input_focused {
					application_key: Application_Key
					mapped := true
					switch event.key.key {
					case sdl3.K_UP: application_key = .Up
					case sdl3.K_DOWN: application_key = .Down
					case sdl3.K_PAGEUP: application_key = .Page_Up
					case sdl3.K_PAGEDOWN: application_key = .Page_Down
					case sdl3.K_ESCAPE: application_key = .Escape
					case sdl3.K_RETURN, sdl3.K_KP_ENTER:
						application_key = native_text_field_return_key(native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT))
					case sdl3.K_O:
						if len(application.menus) == 0 && native_text_primary_modifier(event.key.mod) { application_key = .Open_Repository }
						else { mapped = false }
					case sdl3.K_P:
						if len(application.menus) == 0 && native_text_primary_modifier(event.key.mod) && native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) {
							application_key = .Open_Command_Palette
						} else { mapped = false }
					case sdl3.K_F:
						if native_text_primary_modifier(event.key.mod) {
							application_key = .Workspace_Search if native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) else .Find
						} else { mapped = false }
					case sdl3.K_F2: application_key = .Workspace_Rename
					case sdl3.K_F3:
						application_key = .Find_Previous if native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) else .Find_Next
					case sdl3.K_EQUALS, sdl3.K_PLUS, sdl3.K_KP_PLUS:
						if native_text_primary_modifier(event.key.mod) { application_key = .Zoom_In }
						else { mapped = false }
					case sdl3.K_MINUS, sdl3.K_KP_MINUS:
						if native_text_primary_modifier(event.key.mod) { application_key = .Zoom_Out }
						else { mapped = false }
					case sdl3.K_0, sdl3.K_KP_0:
						if native_text_primary_modifier(event.key.mod) { application_key = .Zoom_Reset }
						else { mapped = false }
					case: mapped = false
					}
					if mapped && application_key_can_preempt_text_field(application_key, composition_active) &&
						application.on_key(application.state, rt, application_key) {
						runtime_key_handled = true
						alicorn.invalidate_root(rt, "application handled focused text-field key")
					}
				}
			}
			if !runtime_key_handled {
				runtime_key_handled = native_dispatch_application_text_key_or_focus_traverse(
					application,
					rt,
					event.key.key,
					event.key.mod,
				)
			}
			if event.key.key == sdl3.K_F12 && diagnostics_capture_requested != nil {
				diagnostics_capture_requested^ = true
				fmt.println("alicorn_diagnostics", "capture_requested", "F12")
			}
			if event.key.key == sdl3.K_F11 && debug_bounds != nil {
				debug_bounds^ = !debug_bounds^
				alicorn.request_presentation(rt)
				fmt.println("alicorn_diagnostics", "debug_bounds", debug_bounds^)
			}
			modifier_key := false
			switch event.key.key {
			case sdl3.K_LCTRL, sdl3.K_LSHIFT, sdl3.K_LALT, sdl3.K_LGUI,
				sdl3.K_RCTRL, sdl3.K_RSHIFT, sdl3.K_RALT, sdl3.K_RGUI:
				modifier_key = true
			}
			if manual_log && (!event.key.repeat || !modifier_key) {
				composition_active := false
				if node, ok := rt.nodes[rt.focused]; ok {
					composition_active = node.composition.active
				}
				fmt.println("sdl_event", "KEY_DOWN", "key", event.key.key, "repeat", event.key.repeat, "composition_active", composition_active)
			}
			if !runtime_key_handled {
				runtime_key_handled = native_route_focused_control_key(rt, event.key.key)
			}
			if !runtime_key_handled && event.key.key == sdl3.K_ESCAPE {
				if alicorn.cancel_text_composition(rt, rt.focused, "Escape canceled text composition") {
					if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed for Escape") }
					runtime_key_handled = true
				} else if text_input_state != nil && text_input_state.composition_owner == rt.focused {
					native_cancel_application_text_composition(application, rt, text_input_state)
					if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed for Escape") }
					runtime_key_handled = true
				}
			} else if !runtime_key_handled {
				if node, ok := rt.nodes[rt.focused]; ok && node.active && node.kind == .Text_Field && !node.composition.active {
					handled := true
					word_modifier := native_text_word_modifier(event.key.mod)
					switch event.key.key {
					case sdl3.K_BACKSPACE:
						native_text_apply_key_edit(rt, rt.focused, .Backspace, word_modifier, app_text, application, telemetry)
					case sdl3.K_DELETE:
						native_text_apply_key_edit(rt, rt.focused, .Delete, word_modifier, app_text, application, telemetry)
					case:
						handled = native_text_apply_key_navigation(rt, rt.focused, event.key.key, event.key.mod, telemetry)
					}
					if manual_log && handled {
						fmt.println("alicorn_key_handled", "key", event.key.key, "text", app_text^)
					}
				}
			}
			if application != nil && !runtime_key_handled {
				text_input_focused := native_current_text_input_owner(rt, text_input_state) != 0
				if !text_input_focused {
					application_key: Application_Key
					handled := true
					switch event.key.key {
					case sdl3.K_LEFT: application_key = .Left
					case sdl3.K_RIGHT: application_key = .Right
					case sdl3.K_UP: application_key = .Up
					case sdl3.K_DOWN: application_key = .Down
					case sdl3.K_PAGEUP: application_key = .Page_Up
					case sdl3.K_PAGEDOWN: application_key = .Page_Down
					case sdl3.K_HOME: application_key = .Home
					case sdl3.K_END: application_key = .End
					case sdl3.K_1: application_key = .Command_1
					case sdl3.K_2: application_key = .Command_2
					case sdl3.K_3: application_key = .Command_3
					case sdl3.K_SPACE: application_key = .Toggle
					case sdl3.K_ESCAPE: application_key = .Escape
					case sdl3.K_RETURN, sdl3.K_KP_ENTER: application_key = .Return
					case sdl3.K_P:
						if len(application.menus) == 0 && native_text_primary_modifier(event.key.mod) && native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) {
							application_key = .Open_Command_Palette
						} else { handled = false }
					case sdl3.K_F:
						if native_text_primary_modifier(event.key.mod) {
							application_key = .Workspace_Search if native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) else .Find
						} else {
							application_key = .Fit_Selection
						}
					case sdl3.K_F3:
						application_key = .Find_Previous if native_text_modifier(event.key.mod, sdl3.KMOD_SHIFT) else .Find_Next
					case sdl3.K_EQUALS, sdl3.K_PLUS, sdl3.K_KP_PLUS:
						if native_text_primary_modifier(event.key.mod) { application_key = .Zoom_In }
						else { handled = false }
					case sdl3.K_MINUS, sdl3.K_KP_MINUS:
						if native_text_primary_modifier(event.key.mod) { application_key = .Zoom_Out }
						else { handled = false }
					case sdl3.K_0, sdl3.K_KP_0:
						if native_text_primary_modifier(event.key.mod) { application_key = .Zoom_Reset }
						else { handled = false }
					case sdl3.K_F2: application_key = .Workspace_Rename
					case sdl3.K_O:
						if len(application.menus) == 0 && native_text_primary_modifier(event.key.mod) {
							application_key = .Open_Repository
						} else {
							handled = false
						}
					case: handled = false
					}
					if handled && application.on_key != nil && application.on_key(application.state, rt, application_key) {
						alicorn.invalidate_root(rt, "application keyboard command")
					}
				}
			}
			alicorn.cause_end(rt, key_cause)
		}

		#partial switch event.type {
		case .WINDOW_RESIZED:
			host_cause := alicorn.cause_begin(rt, .Host_Event, "window resized")
			if devtools_last_cause != nil { devtools_last_cause^ = host_cause.cause }
			// data1/data2 are logical window coordinates for this event.
			metrics.logical_width = int(event.window.data1)
			metrics.logical_height = int(event.window.data2)
			logical_resize_events^ += 1
			rt.viewport.w = f32(metrics.logical_width)
			rt.viewport.h = f32(metrics.logical_height)
			alicorn.invalidate_root(rt, "SDL logical window size changed")
			alicorn.cause_end(rt, host_cause)
		case .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_METAL_VIEW_RESIZED:
			host_cause := alicorn.cause_begin(rt, .Host_Event, "drawable size changed")
			if devtools_last_cause != nil { devtools_last_cause^ = host_cause.cause }
			// data1/data2 are physical drawable pixels for these events. Do not
			// feed them into the logical layout viewport.
			metrics.pixel_width = int(event.window.data1)
			metrics.pixel_height = int(event.window.data2)
			pixel_resize_events^ += 1
			alicorn.invalidate_root(rt, "SDL drawable size changed")
			alicorn.cause_end(rt, host_cause)
		case .WINDOW_DISPLAY_SCALE_CHANGED:
			host_cause := alicorn.cause_begin(rt, .Host_Event, "display scale changed")
			if devtools_last_cause != nil { devtools_last_cause^ = host_cause.cause }
			scale_events^ += 1
			metrics.pixel_density = sdl3.GetWindowPixelDensity(window)
			metrics.display_scale = sdl3.GetWindowDisplayScale(window)
			alicorn.invalidate_root(rt, "SDL display scale changed")
			alicorn.cause_end(rt, host_cause)
		case .TEXT_INPUT:
			text_cause := alicorn.cause_begin(rt, .Text_Input, "SDL text input")
			if devtools_last_cause != nil { devtools_last_cause^ = text_cause.cause }
			text_input_events^ += 1
			if manual_log {
				raw_text := ""
				if event.text.text != nil { raw_text = string(event.text.text) }
				fmt.println("sdl_event", "TEXT_INPUT", "text", raw_text)
			}
			if event.text.text != nil {
				owner := native_current_text_input_owner(rt, text_input_state)
				if node, ok := rt.nodes[owner]; ok && node.active && node.kind == .Text_Field {
					change := alicorn.process_text_input(rt, owner, string(event.text.text))
					native_dispatch_text_change(app_text, application, rt, change, telemetry)
					if manual_log && application == nil { fmt.println("alicorn_after_TEXT_INPUT", "text", app_text^) }
				} else if alicorn.text_input_target_is_active(rt, owner) {
					_ = native_dispatch_generic_text_input_event(application, rt, text_input_state,
						Application_Text_Input_Event{kind=.Commit, text=string(event.text.text)})
				}
			}
			alicorn.cause_end(rt, text_cause)
		case .TEXT_EDITING:
			composition_cause := alicorn.cause_begin(rt, .Text_Composition, "SDL text composition")
			if devtools_last_cause != nil { devtools_last_cause^ = composition_cause.cause }
			composition_events^ += 1
			if manual_log {
				raw_text := ""
				if event.edit.text != nil { raw_text = string(event.edit.text) }
				fmt.println("sdl_event", "TEXT_EDITING", "text", raw_text, "start_chars", event.edit.start, "length_chars", event.edit.length)
			}
			if event.edit.text != nil {
				owner := native_current_text_input_owner(rt, text_input_state)
				preedit := string(event.edit.text)
				if node, ok := rt.nodes[owner]; ok && node.active && node.kind == .Text_Field {
					alicorn.process_text_editing(rt, owner, preedit, int(event.edit.start), int(event.edit.length))
					if manual_log {
						if field, found := rt.nodes[owner]; found {
							fmt.println(
								"alicorn_after_TEXT_EDITING",
								"preedit", field.composition.text,
								"selection_bytes", field.composition.selection_start, field.composition.selection_end,
							)
						}
					}
				} else if alicorn.text_input_target_is_active(rt, owner) {
					if len(preedit) == 0 {
						_ = native_dispatch_generic_text_input_event(application, rt, text_input_state,
							Application_Text_Input_Event{kind=.Cancel})
					} else {
						start_byte := alicorn.utf8_character_index_to_byte_offset(preedit, int(event.edit.start))
						end_byte := start_byte
						if event.edit.start < 0 {
							start_byte, end_byte = len(preedit), len(preedit)
						} else if event.edit.length >= 0 {
							start_char, length_char := int(event.edit.start), int(event.edit.length)
							end_byte = alicorn.utf8_character_index_to_byte_offset(preedit, start_char+length_char)
						}
						_ = native_dispatch_generic_text_input_event(application, rt, text_input_state, Application_Text_Input_Event{
							kind=.Preedit, text=preedit,
							selection_start_byte=start_byte, selection_end_byte=end_byte,
						})
					}
				}
			}
			alicorn.cause_end(rt, composition_cause)
		}

		if event.type == .WINDOW_RESIZED ||
			event.type == .WINDOW_PIXEL_SIZE_CHANGED ||
			event.type == .WINDOW_METAL_VIEW_RESIZED ||
			event.type == .WINDOW_DISPLAY_SCALE_CHANGED {
			if !read_window_metrics(window, metrics) {
				fail("window metrics became unavailable after a window event")
			}
		}
		if text_input_state != nil {
			sync_text_input_focus(window, rt, text_input_state, application)
		}
		has_event = poll_sdl_event(&event)
	}
	native_inspector_finish_input_pump(inspector, text_input_state)
	if telemetry != nil { native_finish_input_pump(telemetry) }
}
