package alicorn_sdl_gpu

import "core:c"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

Native_Text_Input_State :: struct {
	active: bool,
	owner: alicorn.Node_ID,
	composition_owner: alicorn.Node_ID,
	window_focused: bool,
	// A host overlay can own keyboard input while retaining the application's
	// focused node. Native text ownership resumes after its event queue drains.
	suspended: bool,
	last_area: alicorn.Text_Input_Area,
	last_area_valid: bool,
}

native_text_input_owner_is_valid :: proc(rt: ^alicorn.Runtime, id: alicorn.Node_ID) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || !node.focusable || node.disabled { return false }
	if alicorn.text_input_target_is_suspended(rt, id) { return false }
	return node.kind == .Text_Field || alicorn.text_input_target_is_active(rt, id)
}

native_current_text_input_owner :: proc(rt: ^alicorn.Runtime, state: ^Native_Text_Input_State = nil) -> alicorn.Node_ID {
	if state != nil {
		if state.suspended || !state.active || !state.window_focused || state.owner == 0 || state.owner != rt.focused { return 0 }
		return state.owner if native_text_input_owner_is_valid(rt, state.owner) else 0
	}
	return rt.focused if native_text_input_owner_is_valid(rt, rt.focused) else 0
}

native_text_input_area_update_required :: proc(
	state: ^Native_Text_Input_State,
	area: alicorn.Text_Input_Area,
	area_valid: bool,
) -> bool {
	if !area_valid { return state.last_area_valid }
	return !state.last_area_valid || state.last_area != area
}

native_application_text_input_event :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Input_Event,
	require_live_target := true,
) -> bool {
	if application == nil || application.on_text_input == nil || owner == 0 { return false }
	if require_live_target && !alicorn.text_input_target_is_active(rt, owner) { return false }
	application.on_text_input(application.state, rt, owner, event)
	reason := "application text input"
	#partial switch event.kind {
	case .Preedit: reason = "application text preedit"
	case .Cancel: reason = "application text composition canceled"
	}
	alicorn.invalidate_root(rt, reason)
	return true
}

native_dispatch_generic_text_input_event :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	event: Application_Text_Input_Event,
) -> bool {
	owner := native_current_text_input_owner(rt, state)
	if !alicorn.text_input_target_is_active(rt, owner) { return false }
	normalized_event := event
	if normalized_event.kind == .Preedit && len(normalized_event.text) == 0 { normalized_event.kind = .Cancel }
	delivered := native_application_text_input_event(application, rt, owner, normalized_event)
	if !delivered { return false }
	if state != nil {
		switch normalized_event.kind {
		case .Preedit: state.composition_owner = owner
		case .Commit, .Cancel: state.composition_owner = 0
		}
	}
	return true
}

native_application_text_key_event :: proc(
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> (event: Application_Text_Key_Event, mapped: bool) {
	word := native_text_word_modifier(mod)
	line := native_text_line_modifier(mod)
	document := native_text_document_modifier(mod)
	switch key {
	case sdl3.K_LEFT:
		if line { event.key = .Line_Start }
		else if word { event.key = .Word_Left }
		else { event.key = .Left }
	case sdl3.K_RIGHT:
		if line { event.key = .Line_End }
		else if word { event.key = .Word_Right }
		else { event.key = .Right }
	case sdl3.K_HOME: event.key = .Document_Start if document else .Home
	case sdl3.K_END: event.key = .Document_End if document else .End
	case sdl3.K_UP:
		when ODIN_OS == .Darwin {
			event.key = .Document_Start if document else .Up
		} else { event.key = .Up }
	case sdl3.K_DOWN:
		when ODIN_OS == .Darwin {
			event.key = .Document_End if document else .Down
		} else { event.key = .Down }
	case sdl3.K_PAGEUP: event.key = .Page_Up
	case sdl3.K_PAGEDOWN: event.key = .Page_Down
	case sdl3.K_BACKSPACE:
		if line { event.key = .Delete_Line_Backward }
		else if word { event.key = .Delete_Word_Backward }
		else { event.key = .Backspace }
	case sdl3.K_DELETE:
		if line { event.key = .Delete_Line_Forward }
		else if word { event.key = .Delete_Word_Forward }
		else { event.key = .Delete }
	case sdl3.K_TAB: event.key = .Tab
	case: return {}, false
	}
	event.shift = native_text_modifier(mod, sdl3.KMOD_SHIFT)
	event.control = native_text_modifier(mod, sdl3.KMOD_CTRL)
	event.alt = native_text_modifier(mod, sdl3.KMOD_ALT)
	event.super = native_text_modifier(mod, sdl3.KMOD_GUI)
	return event, true
}

native_dispatch_application_text_key :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> bool {
	if application == nil || application.on_text_key == nil || rt == nil { return false }
	event, mapped := native_application_text_key_event(key, mod)
	if !mapped { return false }
	owner := rt.focused
	node, ok := rt.nodes[owner]
	if !ok || !node.active || node.kind == .Text_Field || !alicorn.text_input_target_is_active(rt, owner) {
		return false
	}
	if !application.on_text_key(application.state, rt, owner, event) { return false }
	alicorn.invalidate_root(rt, "application handled focused text key")
	return true
}

// A generic focused text owner gets first refusal on Tab. If it declines the
// key, retain the host's normal forward/backward focus traversal behavior.
native_dispatch_application_text_key_or_focus_traverse :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
) -> bool {
	if native_dispatch_application_text_key(application, rt, key, mod) { return true }
	if key != sdl3.K_TAB || rt == nil { return false }
	direction: alicorn.Focus_Direction = .Next
	if native_text_modifier(mod, sdl3.KMOD_SHIFT) { direction = .Previous }
	return alicorn.focus_traverse(rt, direction) != 0
}

native_cancel_application_text_composition :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
) {
	if state.composition_owner == 0 { return }
	owner := state.composition_owner
	state.composition_owner = 0
	_ = native_application_text_input_event(
		application,
		rt,
		owner,
		Application_Text_Input_Event{kind=.Cancel},
		require_live_target=false,
	)
}

native_cancel_current_text_composition :: proc(
	application: ^Application,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	reason := "text composition canceled by text-input lifecycle",
) {
	if state.composition_owner != 0 {
		native_cancel_application_text_composition(application, rt, state)
		return
	}
	if node, ok := rt.nodes[state.owner]; ok && node.active && node.kind == .Text_Field && node.composition.active {
		_ = alicorn.cancel_text_composition(rt, state.owner, reason)
	}
}

sync_text_input_focus :: proc(
	window: ^sdl3.Window,
	rt: ^alicorn.Runtime,
	state: ^Native_Text_Input_State,
	application: ^Application = nil,
) {
	desired := rt.focused
	if state.suspended || !state.window_focused || !native_text_input_owner_is_valid(rt, desired) { desired = 0 }
	if desired != 0 {
		if node, ok := rt.nodes[desired]; ok && node.kind != .Text_Field && (application == nil || application.on_text_input == nil) {
			desired = 0
		}
	}
	if desired != state.owner {
		native_cancel_current_text_composition(application, rt, state)
		if state.active {
			// Clear platform preedit before changing the Alicorn owner; otherwise
			// a late platform event could be applied to the wrong target.
			if !sdl3.ClearComposition(window) { fail("SDL_ClearComposition failed during text-input focus transfer") }
			if !sdl3.StopTextInput(window) { fail("SDL_StopTextInput failed during text-input focus transfer") }
			state.active = false
		}
		state.owner = 0
		state.last_area_valid = false
		if desired != 0 {
			if !sdl3.StartTextInput(window) { fail("SDL_StartTextInput failed for focused text-input target") }
			state.active = true
			state.owner = desired
		}
	}
	if state.active && state.owner != 0 {
		area, ok := alicorn.text_input_area(rt, state.owner)
		if !ok {
			if native_text_input_area_update_required(state, {}, false) {
				if !sdl3.SetTextInputArea(window, nil, 0) {
					fail("SDL_SetTextInputArea failed while clearing stale candidate-window geometry")
				}
				state.last_area = alicorn.Text_Input_Area{}
				state.last_area_valid = false
			}
			return
		}
		width := int(area.rect.w)
		height := int(area.rect.h)
		if width < 1 { width = 1 }
		if height < 1 { height = 1 }
		input_area := sdl3.Rect{
			x=c.int(area.rect.x), y=c.int(area.rect.y), w=c.int(width), h=c.int(height),
		}
		if native_text_input_area_update_required(state, area, true) {
			if !sdl3.SetTextInputArea(window, &input_area, c.int(area.cursor_x)) {
				fail("SDL_SetTextInputArea failed for focused text-input target")
			}
			state.last_area = area
			state.last_area_valid = true
		}
	}
}

adopt_text_change :: proc(app_text: ^string, rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	// Text_Change.text is a runtime-owned product. Copy it into the host's
	// ordinary application state before releasing it through the allocator that
	// created it; never transfer the runtime allocation across this boundary.
	if change.changed {
		copy, err := strings.clone(change.text)
		if err == nil {
			if len(app_text^) > 0 { delete(app_text^) }
			app_text^ = copy
		}
	}
	if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
}

native_dispatch_text_change :: proc(
	app_text: ^string,
	application: ^Application,
	rt: ^alicorn.Runtime,
	change: alicorn.Text_Change,
	telemetry: ^Native_Text_Event_Telemetry = nil,
) {
	if telemetry != nil {
		telemetry.text_change_dispatches += 1
		if change.changed { telemetry.text_changes += 1 }
	}
	if application != nil {
		if application.on_text_change != nil {
			// The callback borrows the runtime-owned text for the duration of the
			// call. It must clone any value it keeps; the host releases the product
			// through rt.persistent_allocator after the callback returns.
			application.on_text_change(application.state, rt, change)
		}
		if len(change.text) > 0 { delete(change.text, rt.persistent_allocator) }
	} else {
		adopt_text_change(app_text, rt, change)
	}
}

native_text_modifier :: proc(mod: sdl3.Keymod, mask: sdl3.Keymod) -> bool {
	return (mod & mask) != sdl3.Keymod{}
}

native_text_primary_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_modifier(mod, sdl3.KMOD_GUI)
	} else {
		return native_text_modifier(mod, sdl3.KMOD_CTRL)
	}
}

native_text_word_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_modifier(mod, sdl3.KMOD_ALT)
	} else {
		return native_text_modifier(mod, sdl3.KMOD_CTRL)
	}
}

native_text_line_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_modifier(mod, sdl3.KMOD_GUI)
	} else {
		return false
	}
}

native_text_document_modifier :: proc(mod: sdl3.Keymod) -> bool {
	when ODIN_OS == .Darwin {
		return native_text_primary_modifier(mod)
	} else {
		return native_text_modifier(mod, sdl3.KMOD_CTRL)
	}
}

native_text_apply_key_edit :: proc(
	rt: ^alicorn.Runtime,
	node: alicorn.Node_ID,
	kind: alicorn.Text_Edit_Kind,
	word: bool,
	app_text: ^string,
	application: ^Application,
	telemetry: ^Native_Text_Event_Telemetry = nil,
) -> bool {
	field, ok := rt.nodes[node]
	if !ok || !field.active || field.kind != .Text_Field || field.composition.active { return false }
	if telemetry != nil { telemetry.text_edit_key_events += 1 }
	command: alicorn.Text_Command = .Delete_Backward if kind == .Backspace else .Delete_Forward
	if word {
		command = .Delete_Word_Backward if kind == .Backspace else .Delete_Word_Forward
	}
	change := alicorn.process_text_command(rt, node, command)
	native_dispatch_text_change(app_text, application, rt, change, telemetry)
	return true
}

native_text_apply_key_navigation :: proc(
	rt: ^alicorn.Runtime,
	node: alicorn.Node_ID,
	key: sdl3.Keycode,
	mod: sdl3.Keymod,
	telemetry: ^Native_Text_Event_Telemetry = nil,
) -> bool {
	field, ok := rt.nodes[node]
	if !ok || !field.active || field.kind != .Text_Field || field.composition.active { return false }
	shift := native_text_modifier(mod, sdl3.KMOD_SHIFT)
	primary := native_text_primary_modifier(mod)
	word := native_text_word_modifier(mod)
	line := native_text_line_modifier(mod)
	selection_nonempty := field.selection_anchor.byte != field.selection_focus.byte
	target := field.caret.byte
	handled := true
	switch key {
	case sdl3.K_LEFT, sdl3.K_RIGHT:
		direction := -1 if key == sdl3.K_LEFT else 1
		if !shift && selection_nonempty {
			target = field.selection_anchor.byte if direction < 0 else field.selection_focus.byte
			if field.selection_anchor.byte > field.selection_focus.byte {
				target = field.selection_focus.byte if direction < 0 else field.selection_anchor.byte
			}
		} else if line {
			target = 0 if direction < 0 else len(field.text)
			_ = alicorn.set_text_caret(rt, node, target)
			if telemetry != nil { telemetry.text_navigation_key_events += 1 }
			return true
		} else if !shift {
			command: alicorn.Text_Command = .Move_Left if direction < 0 else .Move_Right
			if word { command = .Move_Word_Left if direction < 0 else .Move_Word_Right }
			_ = alicorn.process_text_command(rt, node, command)
			if telemetry != nil {
				telemetry.text_navigation_key_events += 1
				if word { telemetry.text_word_key_events += 1 }
			}
			return true
		} else if line {
			target = 0 if direction < 0 else len(field.text)
		} else if word {
			position := alicorn.text_move_word(field.text, alicorn.Text_Position{target, .Leading}, direction, rt.scratch_allocator)
			target = position.byte
		} else {
			position := alicorn.text_move_logical(field.text, alicorn.Text_Position{target, .Leading}, direction)
			target = position.byte
		}
	case sdl3.K_HOME:
		target = 0
	case sdl3.K_END:
		target = len(field.text)
	case sdl3.K_A:
		if !primary { handled = false }
		if handled {
			_ = alicorn.set_text_selection(rt, node, 0, len(field.text))
			if telemetry != nil { telemetry.text_selection_key_events += 1 }
			return true
		}
	case:
		handled = false
	}
	if !handled { return false }
	if shift {
		_ = alicorn.set_text_selection(rt, node, field.selection_anchor.byte, target)
		if telemetry != nil { telemetry.text_selection_key_events += 1 }
	} else {
		_ = alicorn.set_text_caret(rt, node, target)
	}
	if telemetry != nil {
		telemetry.text_navigation_key_events += 1
		if word { telemetry.text_word_key_events += 1 }
	}
	return true
}
