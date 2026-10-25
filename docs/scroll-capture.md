# Native scroll capture

`native/sdl_gpu.Application.on_scroll_capture` optionally intercepts a wheel
event before Alicorn changes a retained scroll region's offset:

```odin
Application_Scroll_Capture_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	event: alicorn.Scroll_Event,
	target: alicorn.Node_ID,
) -> bool
```

The host calls it once per eligible wheel event, after inspector input blocking
and native content-coordinate translation. `target` is the nonzero retained
region returned by the public, modal-aware `alicorn.scroll_region_hit_test`.
Nested regions receive their own IDs; compare against the exact editor region
you retained from `scroll_region_begin(...).id` to scope an editor gesture:

```odin
capture_editor_scroll :: proc(
	state: rawptr, rt: ^alicorn.Runtime,
	event: alicorn.Scroll_Event, target: alicorn.Node_ID,
) -> bool {
	app := cast(^App)state
	if target != app.editor_region || !event.modifiers.control { return false }
	// Apply the application gesture using event.delta_x / event.delta_y.
	// Request the appropriate Alicorn invalidation if application state changes.
	return true
}
```

Returning `true` claims the event and skips both `alicorn.process_scroll` and
the existing `on_scroll` fallback. Returning `false`, or leaving the callback
unset, preserves retained scrolling and its existing fallback behavior. Events
outside every eligible region do not invoke capture. Modal backdrops continue
to block covered regions and fallback input.

The event preserves precise floating-point deltas, integer ticks, logical
content coordinates, and Shift/Control/Alt/Super modifiers. Use precise deltas
for continuous gestures; the host preserves SDL's chosen scroll direction.

Primary and secondary windows use their own application state and runtime.
Installing capture schedules no ticks, polling or automatic invalidation.

Focused headless regressions live in `native/scroll_capture_tests`; run
`odin test native/scroll_capture_tests` with the usual native linker flags.
That package serializes its SDL fixtures so Odin's parallel test runner cannot
interleave process-wide event queues or modifier state.
