#+build darwin

package alicorn_sdl_gpu

import "vendor:sdl3"

// SDL_PollEvent implicitly pumps Cocoa while draining the queue. Keep the
// operations explicit on Darwin: SDL_PumpEvents performs SDL's complete
// AppKit dispatch, including activation and delivery through NSApplication,
// and SDL_PeepEvents then drains the translated queue without re-entering the
// Cocoa path.

pump_platform_events :: proc() {
	sdl3.PumpEvents()
}
