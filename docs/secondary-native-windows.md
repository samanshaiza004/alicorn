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

## Native validation limits

The automated tests cover independent Runtime geometry/scales and focus,
window-ID/wake routing, deferred one-slot lifecycle, and bounded event ordering.
The Windows D3D12 lifecycle and packaging results are recorded below. Physical
focus transfer, OS text composition, native menu interaction, and movement
between displays still require interactive verification. macOS has a separate
native platform-validation requirement.

## Windows acceptance fixture

The [numbered secondary-window lesson](../examples/06_secondary_windows/main.odin)
demonstrates opening and closing a small tool window with independent state.
The larger
[acceptance fixture](../tests/fixtures/secondary_windows/main.odin) exercises
integrated title bars, text input, workers, animation, native menus, and
shutdown under load.

Build and launch the interactive fixture from the repository root:

```powershell
.\tools\secondary_windows_acceptance.ps1 -Odin odin
```

Open the tool window, resize it, move it to another display, transfer focus
between both text fields, enter text (including an IME composition when
available), invoke its File and View menus, close it, and reopen it. The
window status reports its assigned logical size and scale. Stop the worker and
animation controls to return the application to idle. The primary window's
“Quit while tool and GPU are active” button exercises process shutdown while
the child is live.

The native lifecycle smoke opens, closes, and reopens a real child window,
keeps worker wakeups and GPU geometry updates active, then requests process
shutdown with the second child live:

```powershell
.\tools\secondary_windows_acceptance.ps1 -Odin odin -LifecycleSmoke
```

Add `-GpuStress` to fill most of Alicorn's bounded geometry payload for each
animated frame. The smoke exits nonzero unless two child instances start and
stop, at least one child worker wake is delivered, geometry updates run, and
there are no open failures. The recorded run had the child live and two
unretired primary GPU fences at shutdown; the host then waited for the shared
device to become idle before releasing child resources. Child rendering waits
on each child's submission fence, so the test does not claim an in-flight
child command at the exact shutdown boundary.

### Windows validation record

| Check | Result | Notes |
| --- | --- | --- |
| Headless runtime and native SDL GPU tests | PASS | 234 runtime, 35 theme, 104 native tests; text-input host contract passed. |
| Every example builds | PASS | At the captured revision, all 14 examples compiled. |
| Caption DPI capture matrix | PASS | 144 D3D12 captures at 96, 120, 144, and 192 DPI. |
| Icon and image validation | PASS | D3D12 pixel, blending, atlas, and scale checks passed. |
| GPU geometry unit validation | PASS | `--surface-geometry-test`. |
| D3D12 surface stress | PASS | 1,200 frames/updates; zero ordinary description, reconcile, layout, paint, or composition visits. Synthetic SDL text composition passed; physical focus is not covered by this run. |
| Secondary-window lifecycle and GPU-drain smoke | PASS | Direct3D 12; two child starts/stops, zero open failures, 3 child worker wakes, 60 geometry updates; child live and 2 primary fences unretired at shutdown. |
| Integrated native-menu D3D12 smoke | PASS | Host startup, presentation, and idle smoke passed; this did not invoke a menu item. |
| Shared-SDL native package and clean-directory smoke | PASS | Acceptance fixture package launched from an empty working directory. |
| Static-SDL package build | BLOCKED | CMake is not installed in this Windows environment; the shared-SDL package smoke passed. |
| Focus transfer and separate physical text input | BLOCKED | Native desktop automation is unavailable in this session. |
| Child native menu commands | BLOCKED | The automated smoke did not select menu items. |
| Resize and cross-display DPI movement | BLOCKED | Two displays are attached, but interactive movement and scale transition were not exercised. |
| Physical IME candidate/composition behavior | BLOCKED | Synthetic SDL composition passed; no physical IME session was available. |

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
