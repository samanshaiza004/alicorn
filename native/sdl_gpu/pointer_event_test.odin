package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

@(test)
test_pointer_event_carries_native_selection_metadata :: proc(t: ^testing.T) {
	event := sdl3.Event{}
	event.type = .MOUSE_MOTION
	event.motion.x = 123.25
	event.motion.y = 234.75
	pointer, ok := pointer_from_sdl_with_modifiers(event, sdl3.KMOD_SHIFT)
	testing.expect(t, ok && pointer.kind == .Move, "mouse motion should convert to a runtime move event")
	testing.expect(t, pointer.x == 123.25 && pointer.y == 234.75,
		"mouse coordinates should remain in SDL window-logical units")
	testing.expect(t, pointer.modifiers.shift && !pointer.modifiers.control &&
		!pointer.modifiers.alt && !pointer.modifiers.super,
		"motion events should carry platform-neutral modifier state")
	testing.expect(t, pointer.click_count == 0 && pointer.button == 0,
		"motion events should not invent button or click data")

	event = sdl3.Event{}
	event.type = .MOUSE_BUTTON_DOWN
	event.button.button = 1
	event.button.clicks = 2
	event.button.x = 17.5
	event.button.y = 22.25
	pointer, ok = pointer_from_sdl_with_modifiers(event, sdl3.KMOD_SHIFT | sdl3.KMOD_CTRL)
	testing.expect(t, ok && pointer.kind == .Down && pointer.button == 1,
		"button-down should preserve the pointer kind and button identity")
	testing.expect(t, pointer.click_count == 2,
		"SDL double-click count should reach the runtime unchanged")
	testing.expect(t, pointer.x == 17.5 && pointer.y == 22.25,
		"button coordinates should remain in window-logical units")
	testing.expect(t, pointer.modifiers.shift && pointer.modifiers.control &&
		!pointer.modifiers.alt && !pointer.modifiers.super,
		"Shift-click should expose Shift and preserve other modifier state")

	event.button.clicks = 3
	pointer, ok = pointer_from_sdl_with_modifiers(event,
		sdl3.KMOD_SHIFT | sdl3.KMOD_CTRL | sdl3.KMOD_ALT | sdl3.KMOD_GUI)
	testing.expect(t, ok && pointer.click_count == 3,
		"SDL triple-click count should reach the runtime unchanged")
	testing.expect(t, pointer.modifiers.shift && pointer.modifiers.control &&
		pointer.modifiers.alt && pointer.modifiers.super,
		"all SDL keyboard modifiers should map to the neutral runtime flags")

	event.type = .MOUSE_BUTTON_UP
	pointer, ok = pointer_from_sdl_with_modifiers(event, {})
	testing.expect(t, ok && pointer.kind == .Up && pointer.click_count == 3 &&
		!pointer.modifiers.shift && !pointer.modifiers.control && !pointer.modifiers.alt && !pointer.modifiers.super,
		"button-up should preserve click count and modifiers too")

	mod_state := sdl3.Keymod{}
	event = sdl3.Event{}
	event.type = .KEY_DOWN
	event.key.mod = sdl3.KMOD_SHIFT
	pointer_modifier_state_update(&mod_state, event)
	event.type = .MOUSE_BUTTON_DOWN
	event.button.clicks = 1
	pointer, ok = pointer_from_sdl_with_modifiers(event, mod_state)
	testing.expect(t, ok && pointer.modifiers.shift,
		"button-down should use the most recent ordered keyboard modifier snapshot")
	event.type = .KEY_UP
	event.key.mod = {}
	pointer_modifier_state_update(&mod_state, event)
	event.type = .MOUSE_BUTTON_DOWN
	pointer, ok = pointer_from_sdl_with_modifiers(event, mod_state)
	testing.expect(t, ok && !pointer.modifiers.shift,
		"a queued Shift release should clear Shift for subsequent pointer events")
	mod_state = sdl3.KMOD_SHIFT | sdl3.KMOD_CTRL
	event.type = .WINDOW_FOCUS_LOST
	pointer_modifier_state_update(&mod_state, event)
	testing.expect(t, mod_state == sdl3.Keymod{},
		"focus loss should clear cached modifiers when SDL may omit key-up events")

	event.type = .KEY_DOWN
	_, ok = pointer_from_sdl_with_modifiers(event, {})
	testing.expect(t, !ok,
		"non-pointer SDL events should not be converted to runtime pointer events")
}
