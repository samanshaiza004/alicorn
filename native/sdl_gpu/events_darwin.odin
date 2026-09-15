#+build darwin

package alicorn_sdl_gpu

import "core:c"
import NS "core:sys/darwin/Foundation"

foreign import CoreFoundation "system:CoreFoundation.framework"

foreign CoreFoundation {
	CFRunLoopRunInMode :: proc(mode: rawptr, seconds: f64, return_after_source_handled: bool) -> c.int ---
}

// SDL_PollEvent calls SDL_WaitEventTimeoutNS internally. On the affected
// macOS/SDL combinations that path can remain in Cocoa's
// nextEventMatchingMask:untilDate: call even though the requested timeout is
// zero. Even SDL_PumpEvents can reach that Cocoa wait on the affected host,
// so use the main Core Foundation run loop with a zero-second budget and
// drain SDL's already-translated queue separately.
//
// This keeps all Cocoa translation inside SDL and leaves the SDL queue to be
// drained separately. Unlike SDL_PollEvent, SDL_PeepEvents does not pump
// Cocoa again.

pump_platform_events :: proc() {
	// Run the main Core Foundation loop for zero seconds. This services the
	// AppKit/SDL event source without entering NSApplication's blocking
	// nextEventMatchingMask:untilDate: path.
	_ = CFRunLoopRunInMode(rawptr(NS.DefaultRunLoopMode), 0, false)
}
