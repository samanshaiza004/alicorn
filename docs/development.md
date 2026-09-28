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
.\tools\native_sdl_gpu.ps1 -SurfaceStress
```

```sh
./tools/test.sh
./tools/bench.sh
./tools/native_sdl_gpu.sh
```

The scripts accept `-Odin PATH` on PowerShell and `--odin PATH` on Unix-like
shells. They otherwise use `ALICORN_ODIN`, then `odin` on `PATH`.

## Native diagnostics

The native window supports `F10` to toggle the host-owned runtime HUD, `F11` to
toggle retained bounds, and `F12` for a diagnostic capture (including repeated
captures during one run). The HUD reports recent application builds,
presentation updates, app-driven GPU submissions, host wakes, surface updates,
runtime allocations, retained-region reuse, last-interaction stage visits, and
input-to-submit latency. It starts hidden and
does not add retained nodes or change application `Frame_Stats`. When visible,
the host redraws the current scene to composite the overlay; those HUD-only
submissions and encode costs are reported separately in the capture.

The fixed 256-sample flight recorder stores host wake/work counter deltas in a
rolling buffer. Event-driven idle time produces no synthetic frame samples;
zero application work while asleep is expected behavior, not a zero-FPS error.
The HUD uses one-shot idle/counter-expiry waits and returns to sleeping until
the next app or OS event.

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
