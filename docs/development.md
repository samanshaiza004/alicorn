# Development

This page is for working on Alicorn itself. For a fresh installation and the
native starter app, use [Getting Started](getting-started.md).

## Repository map

```text
runtime/          retained runtime and public UI API
native/sdl_gpu/   SDL3 / SDL_GPU host and compositor
examples/         headless examples and the native starter app
tests/            deterministic foundation tests
benchmarks/       retained-work benchmark workloads
third_party/      vendored dependencies and their notices
```

## Build and test

The standard checks build examples and run the headless suite:

```powershell
.\tools\check.ps1
```

```sh
./tools/check.sh
```

`test.ps1` / `test.sh` also compile the native SDL/GPU entry point before
running tests. The native compile and smoke runner requires the platform setup
from [Getting Started](getting-started.md).

For focused work:

```powershell
.\tools\test.ps1
.\tools\bench.ps1
.\tools\bench_text_layout.ps1
.\tools\native_sdl_gpu.ps1 -SurfaceStress
```

```sh
./tools/test.sh
./tools/bench.sh
./tools/bench_text_layout.sh
./tools/native_sdl_gpu.sh
```

The scripts accept `-Odin PATH` on PowerShell and `--odin PATH` on Unix-like
shells. They otherwise use `ALICORN_ODIN`, then `odin` on `PATH`.

## Native diagnostics

The reusable native `Run` host provides a visual inspector when started with
`--inspector`. Press `F9` to open or close it; `--inspector-open` enables it and
opens it at startup. `Escape` or the inspector's Close button also closes it.
The inspector is disabled by default.

The Tree tab shows a collapsible retained hierarchy. Select a row for node
identity, source location, component/key scope, bounds, and interaction state.
Use Pick (or `P`) and click an application node to inspect it without activating it.
The Focus tab shows keyboard focus, semantic identity, its durable owner, and
its currently realized node. Work shows retained stage counters, presentation
and submission revisions, and host timings. Causes shows bounded recent
transactions with actions, invalidations, stage work, and submissions.

The inspector is an Alicorn UI in its own retained runtime, composited above
the application. Inspector interactions consume input while it is open; the
application's focus and semantic focus stay intact. Async application work and
window lifecycle events continue. It refreshes when inspected state changes
or the developer interacts, and adds no periodic tick or idle polling. An
application identity error remains visible in the inspector. With inspector
opt-in, the host suspends further descriptions of the failed application for
the remainder of that run, allowing the independent inspector to stay usable
and return to idle.

Run the inspector fixture for a bounded native check and screenshot:

```powershell
.\tools\native_sdl_gpu.ps1 -InspectorOpen -Smoke -Diagnostics -CaptureAfter 0
```

```sh
./tools/native_sdl_gpu.sh --inspector-open --smoke --diagnostics --capture-after=0
```

The fixture has nested components, semantic focus, a virtual list, and actions.
Its `--inspector-input-smoke` mode injects SDL input through the production host
to check picking, text-input blocking, composition cancellation, focus, and
settled application work. Add `--inspector-identity-error` to inspect an
intentional duplicate-key error. These two switches belong to the fixture;
`--inspector` and `--inspector-open` work with any app using the reusable host,
without application diagnostics code.

```powershell
.\out\alicorn_sdl_gpu.exe --inspector-fixture --inspector-input-smoke
.\out\alicorn_sdl_gpu.exe --inspector-fixture --inspector-input-smoke --inspector-identity-error
```

Use `--capture-after=0` for a static startup capture, or press `F12` during an
interactive run. A settled event-driven app sleeps rather than waking solely
for the automatic capture timer.

The native window supports `F10` to toggle the host-owned runtime HUD, `F11` to
toggle retained bounds, and `F12` for a diagnostic capture (including repeated
captures during one run). The HUD reports recent application builds,
presentation updates, app-driven GPU submissions, host wakes, surface updates,
runtime allocations, retained-region reuse, last-interaction stage visits, and
input-to-submit latency. Its status classifies the latest work as `IDLE`,
`HOST` (input/wake only), `PRESENT` (retained presentation), `APP` (application
description/build), or `SURFACE` (custom-surface-only). Recent pointer-event
and hover-target-transition counts help distinguish ordinary mouse motion from
retained hover changes. It starts hidden and
does not add retained nodes or change application `Frame_Stats`. When visible,
the host redraws the current scene to composite the overlay; those HUD-only
submissions and encode costs are reported separately in the capture.

The fixed 256-sample flight recorder stores host wake/work counter deltas in a
rolling buffer. Event-driven idle time produces no synthetic frame samples;
zero application work while asleep is expected behavior, not a zero-FPS error.
The HUD uses one-shot idle/counter-expiry waits and returns to sleeping until
the next app or OS event. Timeline samples include an activity class and raw
pointer-event/hover-target-transition counts alongside application builds,
retained stage visits, surface updates, and app-driven GPU submissions.

F12 captures separate application build/tick, event handling, GPU encoding,
submission, and fence-wait timings, alongside retained-tree identity, layout
information, and the recent flight-recorder history.

```powershell
.\tools\native_sdl_gpu.ps1 -Diagnostics -CaptureAfter 2 -CaptureDir out\diagnostics
```

Each capture is written as a bundle under `out/diagnostics/`, for example
`20260928T165642.317Z-0001/diagnostics.json`, `inspector.txt`, `timeline.json`,
and `screenshot.ppm`. The timeline uses a versioned JSON schema and contains at
most the 256 most recent samples in oldest-to-newest order. The UTC timestamp
and sequence make repeated captures
distinct, and the JSON records the capture ID and frame. Treat these as
investigation artifacts, not golden-image compatibility promises.

## Change boundaries

- Keep app state in the app; do not make retained nodes own arbitrary pointers.
- Preserve explicit invalidation and stable logical keys.
- Keep SDL and GPU handles inside the native host.
- Run the headless checks for runtime/API changes; run a native smoke on the
  target platform for host, input, text, or rendering changes.
- Use benchmarks to compare a named workload, not as cross-machine promises.
- The [performance evidence index](performance.md) links the published
  cross-platform text-layout runs, Mac retained-work suite, and native-hello
  sample. These are workload-specific observations, not cross-machine
  promises; the native report includes raw evidence and qualified startup
  markers.
