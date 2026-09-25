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

The native window supports `F12` for a diagnostic capture when started with
diagnostics enabled, and `F11` to toggle retained bounds. Captures separate
application build/tick, event handling, GPU encoding, submission, and fence
wait timings, alongside retained-tree identity and layout information.

```powershell
.\tools\native_sdl_gpu.ps1 -Diagnostics -CaptureAfter 2 -CaptureDir out\diagnostics
```

See `out/diagnostics/` for the generated files. Treat these as investigation
artifacts, not golden-image compatibility promises.

## Change boundaries

- Keep app state in the app; do not make retained nodes own arbitrary pointers.
- Preserve explicit invalidation and stable logical keys.
- Keep SDL and GPU handles inside the native host.
- Run the headless checks for runtime/API changes; run a native smoke on the
  target platform for host, input, text, or rendering changes.
- Use benchmarks to compare a named workload, not as cross-machine promises.
