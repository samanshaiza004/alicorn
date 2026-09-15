#+build darwin

package alicorn_sdl_gpu

import NS "core:sys/darwin/Foundation"

// SDL_PollEvent calls SDL_WaitEventTimeoutNS internally. On the affected
// macOS/SDL combinations that path can remain in Cocoa's
// nextEventMatchingMask:untilDate: call even though the requested timeout is
// zero. Since event polling and SDL video operations are main-thread-only,
// keep the workaround in this host boundary and use AppKit's public
// non-blocking event query directly.
//
// Events are still sent through NSApplication.sendEvent:, which is the route
// SDL's Cocoa application subclass uses to translate AppKit events into SDL
// events. The SDL queue is drained separately with SDL_PeepEvents; unlike
// SDL_PollEvent, that function does not pump Cocoa again.
DARWIN_NATIVE_EVENT_BUDGET :: 512

pump_platform_events :: proc() {
	application := NS.Application_sharedApplication()
	if application == nil { return }

	for i := 0; i < DARWIN_NATIVE_EVENT_BUDGET; i += 1 {
		// A date equal to now gives AppKit a genuinely non-blocking deadline.
		// Do not use NSDate.distantFuture or an SDL wait API here.
		expiration := NS.Date_dateWithTimeIntervalSinceNow(0)
		event := NS.Application_nextEventMatchingMask(
			application,
			NS.EventMaskAny,
			expiration,
			NS.DefaultRunLoopMode,
			true,
		)
		if event == nil { break }
		NS.Application_sendEvent(application, event)
	}
}
