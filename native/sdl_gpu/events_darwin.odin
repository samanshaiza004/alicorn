#+build darwin

package alicorn_sdl_gpu

import "vendor:sdl3"
import NS "core:sys/darwin/Foundation"

Darwin_Focus_State :: struct {
	app_active:  bool,
	key_window:  bool,
	input_focus: bool,
}

// SDL_PollEvent implicitly pumps Cocoa while draining the queue. Keep the
// operations explicit on Darwin: SDL_PumpEvents performs SDL's complete
// AppKit dispatch, including activation and delivery through NSApplication,
// and SDL_PeepEvents then drains the translated queue without re-entering the
// Cocoa path.

pump_platform_events :: proc() {
	sdl3.PumpEvents()
}

darwin_focus_state :: proc(window: ^sdl3.Window) -> Darwin_Focus_State {
	state := Darwin_Focus_State{}
	if window == nil { return state }
	flags := sdl3.GetWindowFlags(window)
	state.input_focus = (flags & sdl3.WindowFlags{.INPUT_FOCUS}) != sdl3.WindowFlags{}
	app := NS.Application_sharedApplication()
	if app == nil { return state }
	state.app_active = NS.Application_active(app)
	key_window := NS.Application_keyWindow(app)
	state.key_window = key_window != nil && NS.Window_keyWindow(key_window)
	return state
}
