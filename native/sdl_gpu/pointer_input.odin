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

pointer_from_sdl_with_modifiers :: proc(event: sdl3.Event, mod: sdl3.Keymod) -> (value: alicorn.Pointer_Event, ok: bool) {
	// SDL mouse coordinates are window-logical coordinates. They are passed
	// through unchanged; only the compositor converts logical geometry to pixels.
	modifiers := pointer_modifiers_from_sdl(mod)
	if event.type == .MOUSE_MOTION {
		return alicorn.Pointer_Event{
			kind=.Move,
			x=event.motion.x,
			y=event.motion.y,
			modifiers=modifiers,
		}, true
	}
	if event.type == .MOUSE_BUTTON_DOWN {
		button := native_pointer_button_from_sdl(int(event.button.button), modifiers)
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
		button := native_pointer_button_from_sdl(int(event.button.button), modifiers)
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
