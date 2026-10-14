package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

// native_route_focused_control_key is kept separate from the event loop so the
// platform key convention for retained controls can be verified headlessly.
native_route_focused_control_key :: proc(rt: ^alicorn.Runtime, key: sdl3.Keycode) -> bool {
	switch key {
	case sdl3.K_SPACE:
		return alicorn.activate_focused(rt, .Space)
	case sdl3.K_RETURN, sdl3.K_KP_ENTER:
		return alicorn.activate_focused(rt, .Enter)
	case sdl3.K_LEFT, sdl3.K_DOWN:
		return alicorn.adjust_focused_slider(rt, -1)
	case sdl3.K_RIGHT, sdl3.K_UP:
		return alicorn.adjust_focused_slider(rt, 1)
	case sdl3.K_HOME:
		return alicorn.set_focused_slider_bound(rt, .Minimum)
	case sdl3.K_END:
		return alicorn.set_focused_slider_bound(rt, .Maximum)
	case:
		return false
	}
}

pointer_modifiers_from_sdl :: proc(mod: sdl3.Keymod) -> alicorn.Input_Modifiers {
	return alicorn.Input_Modifiers{
		shift=native_text_modifier(mod, sdl3.KMOD_SHIFT),
		control=native_text_modifier(mod, sdl3.KMOD_CTRL),
		alt=native_text_modifier(mod, sdl3.KMOD_ALT),
		super=native_text_modifier(mod, sdl3.KMOD_GUI),
	}
}

Native_Pointer_Button_State :: struct {
	// SDL button numbers are small positive integers. Zero means there is no
	// active press mapping for that physical button.
	logical_by_physical: [8]int,
}

native_pointer_button_state_clear :: proc(state: ^Native_Pointer_Button_State) {
	if state != nil { state^ = {} }
}

native_pointer_button_from_sdl :: proc(button: int, modifiers: alicorn.Input_Modifiers) -> int {
	when ODIN_OS == .Darwin {
		// Cocoa's conventional context-click gesture is Control + primary click.
		// Preserve the modifier snapshot, but expose the gesture as secondary so
		// applications can use one portable context-menu path.
		if button == alicorn.POINTER_BUTTON_PRIMARY && modifiers.control {
			return alicorn.POINTER_BUTTON_SECONDARY
		}
	}
	return button
}

pointer_from_sdl_with_modifiers :: proc(
	event: sdl3.Event,
	mod: sdl3.Keymod,
	button_state: ^Native_Pointer_Button_State = nil,
) -> (value: alicorn.Pointer_Event, ok: bool) {
	// SDL mouse coordinates are window-logical coordinates. They are passed
	// through unchanged; only the compositor converts logical geometry to pixels.
	modifiers := pointer_modifiers_from_sdl(mod)
	if event.type == .WINDOW_FOCUS_LOST {
		// SDL may not deliver the matching button-up after focus/capture is lost.
		native_pointer_button_state_clear(button_state)
	}
	if event.type == .MOUSE_MOTION {
		return alicorn.Pointer_Event{
			kind=.Move,
			x=event.motion.x,
			y=event.motion.y,
			modifiers=modifiers,
		}, true
	}
	if event.type == .MOUSE_BUTTON_DOWN {
		physical_button := int(event.button.button)
		button := native_pointer_button_from_sdl(physical_button, modifiers)
		if button_state != nil && physical_button > 0 && physical_button < len(button_state.logical_by_physical) {
			button_state.logical_by_physical[physical_button] = button
		}
		return alicorn.Pointer_Event{
			kind=.Down,
			x=event.button.x,
			y=event.button.y,
			button=button,
			modifiers=modifiers,
			click_count=event.button.clicks,
		}, true
	}
	if event.type == .MOUSE_BUTTON_UP {
		physical_button := int(event.button.button)
		button := native_pointer_button_from_sdl(physical_button, modifiers)
		if button_state != nil && physical_button > 0 && physical_button < len(button_state.logical_by_physical) {
			if logical_button := button_state.logical_by_physical[physical_button]; logical_button != 0 {
				button = logical_button
			}
			button_state.logical_by_physical[physical_button] = 0
		}
		return alicorn.Pointer_Event{
			kind=.Up,
			x=event.button.x,
			y=event.button.y,
			button=button,
			modifiers=modifiers,
			click_count=event.button.clicks,
		}, true
	}
	return alicorn.Pointer_Event{}, false
}

native_dispatch_drag_event :: proc(application: ^Application, rt: ^alicorn.Runtime) -> bool {
	event, pending := alicorn.drag_event_take(rt)
	if !pending { return false }
	if application != nil && application.on_drag != nil {
		application.on_drag(application.state, rt, event)
	}
	return true
}

pointer_modifier_state_update :: proc(mod_state: ^sdl3.Keymod, event: sdl3.Event) {
	if mod_state == nil { return }
	if event.type == .KEY_DOWN || event.type == .KEY_UP {
		mod_state^ = event.key.mod
	} else if event.type == .WINDOW_FOCUS_LOST {
		mod_state^ = {}
	} else if event.type == .WINDOW_FOCUS_GAINED {
		mod_state^ = sdl3.GetModState()
	}
}

poll_sdl_event :: proc(event: ^sdl3.Event) -> bool {
	when ODIN_OS == .Darwin {
		// The Darwin host pumps AppKit explicitly above. PeepEvents retrieves
		// only what SDL has already translated, so it cannot re-enter the
		// blocking SDL_PollEvent -> Cocoa path.
		return sdl3.PeepEvents(event, 1, .GETEVENT, sdl3.EventType.FIRST, sdl3.EventType.LAST) > 0
	} else {
		return sdl3.PollEvent(event)
	}
}

// native_event_window_id extracts the owner of the SDL event variants that
// participate in a secondary window's independent input/focus/scale stream.
// Device-level and process-level events intentionally return zero and remain
// with the primary host loop.
native_event_window_id :: proc(event: sdl3.Event) -> sdl3.WindowID {
	#partial switch event.type {
	case .WINDOW_SHOWN, .WINDOW_HIDDEN, .WINDOW_EXPOSED, .WINDOW_MOVED,
	     .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_METAL_VIEW_RESIZED,
	     .WINDOW_MINIMIZED, .WINDOW_MAXIMIZED, .WINDOW_RESTORED,
	     .WINDOW_MOUSE_ENTER, .WINDOW_MOUSE_LEAVE, .WINDOW_FOCUS_GAINED,
	     .WINDOW_FOCUS_LOST, .WINDOW_CLOSE_REQUESTED, .WINDOW_DISPLAY_CHANGED,
	     .WINDOW_DISPLAY_SCALE_CHANGED, .WINDOW_SAFE_AREA_CHANGED,
	     .WINDOW_ENTER_FULLSCREEN, .WINDOW_LEAVE_FULLSCREEN, .WINDOW_DESTROYED:
		return event.window.windowID
	case .KEY_DOWN, .KEY_UP:
		return event.key.windowID
	case .TEXT_INPUT:
		return event.text.windowID
	case .TEXT_EDITING:
		return event.edit.windowID
	case .TEXT_EDITING_CANDIDATES:
		return event.edit_candidates.windowID
	case .MOUSE_MOTION:
		return event.motion.windowID
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		return event.button.windowID
	case .MOUSE_WHEEL:
		return event.wheel.windowID
	case:
		return 0
	}
}

native_event_next :: proc(event: ^sdl3.Event, child: ^Native_Secondary_Window, replay_secondary_events: bool) -> bool {
	if event == nil { return false }
	if replay_secondary_events { return native_secondary_window_pop_event(child, event) }
	return poll_sdl_event(event)
}
