# Secondary native windows

The SDL host currently exposes a deliberately small secondary-window service:
one live secondary window per `Run` call. This proves the ownership and event
contracts without claiming arbitrary multi-window composition.

## Ownership

- The host owns SDL initialization, the shared `SDL_GPUDevice`, and every
  native `SDL_Window`.
- Each native window has an independent Alicorn `Runtime`, logical viewport,
  presentation scale, input/focus state, accessibility adapter, wake/scheduler
  state, and renderer resources.
- The shared GPU device claims each window separately, so every window has its
  own swapchain. The host creates, claims, presents, releases, and destroys
  windows on the SDL main thread.
- Application domain data remains application-owned. A secondary
  `Application.state` should point to a window context that explicitly refers
  to shared domain state; it should not blindly reuse the primary callback
  state when callbacks maintain per-window state.
- `on_open_failed` runs for setup failures before callbacks start. Once
  callbacks have started, `on_stop` owns cleanup, including partial startup.

Window creation is deferred until the next event-loop safe point. The service
rejects a second open while one is pending or live. Windows children can use an
independent integrated title bar, including direct top-level commands with
borrowed enabled/checked states and shortcuts. They share the primary caption
geometry, theme appearance policy, input transforms, and compositor. macOS
children use system chrome and leave application-global menus on the primary
window. A child close request uses its own `on_close_requested` callback and
Runtime. The title service copies replacement text and refreshes only chrome;
it does not re-enter application callbacks while a build is running.

## Events, DPI, and rendering

SDL's global event stream is routed by window ID. Child events and child-specific
wake events are placed in a bounded FIFO and replayed through that window's
normal semantic event dispatcher. Keyboard focus and text input are managed
against the child window, not inferred from the primary window. A display-scale
or drawable-size change refreshes that window's own metrics and Runtime scale.

The host submits child frames on the shared device and waits for the child
submission fence before recycling that window's renderer buffers. This first
implementation favors clear resource lifetime over overlapping submissions;
it can be made asynchronous after native validation establishes the required
per-window retirement contract.

## Shutdown

The host stops the child scheduler and wake sources, calls its application
`on_stop`, shuts down accessibility/dialog resources, waits for device work,
destroys its renderers and Runtime, releases the child swapchain claim, and then
destroys its SDL window. This happens before primary application state and the
shared GPU device are torn down.

## Native validation still required

The automated tests cover independent Runtime geometry/scales and focus,
window-ID/wake routing, deferred one-slot lifecycle, and bounded event ordering.
Before shipping, a native fixture should still be exercised on Windows and
macOS for moving the child across displays with different scales, resizing,
focus transfer, close/reopen, worker wakeups, and clean process shutdown.

## Diagnostic captures

A native host capture (F12 in either window) includes `windows.json` with primary and live secondary
SDL window IDs, focus/topmost state, size and scale, Runtime viewport, and frame
counters. On Windows, each window entry also contains platform geometry and
recent position-message history. When a child is live, the bundle includes
`secondary-inspector.txt`, `secondary-timeline.json` (the child's pointer-event
history), and `secondary-screenshot.ppm` rendered from that child Runtime and
its caption inset. These artifacts make a floating-window
issue inspectable even when the primary window remains focused.
The original `diagnostics.json`, `inspector.txt`, `timeline.json`, and
`screenshot.ppm` continue to describe the primary window; the JSON explicitly
labels that role.

Windows integrated frames preserve the HWND position during SDL's automatic
topmost promotion on mouse entry. SDL's standard-frame adjustment would otherwise
subtract a caption/resize inset from the custom full-client frame repeatedly.
The host recognizes that z-order promotion in `WM_WINDOWPOSCHANGING` and applies
`SWP_NOMOVE`; explicit moves, resizing, and DPI/frame changes retain their normal
geometry handling. A hidden native regression exercises repeated SDL mouse
entry/leave, topmost toggles, ordinary movement, and resizing without activating
or moving the user's cursor.
