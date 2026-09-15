# Native observability

The native SDL/GPU host has a small diagnostics seam for investigating a
running application without attaching a console or changing the application
code. It is intentionally human-first and machine-readable: the same capture
can be inspected by a developer, a script, or an automated coding agent.

## Capture from the command line

Build or run a host with:

```powershell
.\tools\native_sdl_gpu.ps1 -Diagnostics -CaptureAfter 2 -CaptureDir out\diagnostics
```

Add `-DebugBounds` to start with the retained-node bounds overlay enabled.

For an application using the reusable native host, the equivalent command-line
arguments are:

```text
--diagnostics
--capture-after=2
--capture-dir=out/diagnostics
```

The capture directory contains:

```text
diagnostics.json   host timings, GPU counters, runtime counts, and notes
inspector.txt      retained tree, identity, bounds, dirty state, and focus
screenshot.ppm     dependency-free offscreen display-list capture
```

The screenshot is PPM rather than PNG so the host does not need an image
encoder dependency. Image tools and scripts can open or convert it directly.
The capture is a diagnostic artifact, not a golden-image compatibility claim.

## Capture while running

When diagnostics are enabled, press `F12` in the native window. The host
captures at the next safe presentation boundary. This keeps the application
responsible for its own state while the host records the retained runtime and
native submission state around it.

Press `F11` to toggle retained-node bounds. The bounds are drawn by the native
solid-quad diagnostic path and do not enter the application's retained display
list. The same mode can be enabled at startup with `--debug-bounds`.

## What the numbers mean

Timing values are host wall-clock measurements in nanoseconds. Frame samples
retain a bounded recent window and report p50, p95, p99, and maximum frame time.
The capture also separates application build/tick, event pumping, GPU encoding,
submission, and fence waits.

Runtime allocation telemetry, when present, describes Alicorn's requested
allocator bytes. It does not measure application allocations, GPU memory,
driver memory, allocator overhead, process working set, or OS-resident memory.

Solid-rectangle batches are counted only within contiguous display-list runs;
text and custom surfaces remain ordering boundaries.

## Current boundary

The current native seam provides capture artifacts, retained-tree inspection,
and a bounds overlay. An input replay format is intentionally separate follow-up
work. The artifacts are preferred for reproducible reports because they
preserve the measurements and identity data instead of relying only on a screen
recording.
