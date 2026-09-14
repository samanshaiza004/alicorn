# Process monitor dogfood

The implementation now lives in the separate
[Alicorn Monitor repository](https://github.com/samanshaiza004/alicorn-monitor).
This document remains the Alicorn-side record of the application boundary; the
monitor repository contains its source, build script, and pinned dependency.

## Purpose

The process monitor is the first application-sized test of Alicorn. It is
small enough to understand, but it combines the parts that were previously
tested in isolation:

```text
Windows process sampling
        + keyed sorting/filtering
        + virtualized interaction
        + Runa text
        + retained GPU surface
        + resize and focus
```

The point is not to make a complete task manager. The point is to find out
whether using Alicorn to build a useful tool feels direct while its runtime
keeps expensive work local.

## Screen and behavior

The current screen contains a CPU and memory summary, a 512-sample CPU graph,
a filter field, sort controls, pause/resume, and a fixed-height process table.
Rows are emitted only for the visible range. The current input map is:

| Input | Behavior |
| --- | --- |
| Mouse click | Focus or select a control/row |
| Mouse wheel | Scroll visible process rows |
| Up/Down | Move selection when a non-text control owns focus |
| Page Up/Page Down | Move by eight visible rows |
| `1`, `2`, `3` | Sort by CPU, memory, or name |
| Space | Pause or resume sampling when the filter is not focused |

The filter remains an ordinary application string. SDL committed text events
are applied through Alicorn's existing text-field path; Alicorn's retained
runtime state is not the application's process database.

## Identity choice

Windows can recycle a PID. A row therefore uses:

```text
Process_Key = { pid, creation_time }
```

The string identity used by the current runtime API is `pid=...;created=...`.
This is intentionally more conservative than using the visible table position
or PID alone. CPU sorting can reorder rows every sample without transferring
selection to a different process.

The sampler uses `CreateToolhelp32Snapshot` with `Process32FirstW` and
`Process32NextW` to enumerate processes. It obtains cumulative kernel/user
time with `GetProcessTimes` and working-set memory with
`GetProcessMemoryInfo`. CPU percentages are computed from deltas over a QPC
wall-clock interval and normalized by the logical processor count. Processes
that deny `PROCESS_QUERY_LIMITED_INFORMATION` are skipped and counted as query
failures instead of stopping the application.

These choices follow the Windows API contracts documented by Microsoft:

- [CreateToolhelp32Snapshot](https://learn.microsoft.com/en-us/windows/win32/api/tlhelp32/nf-tlhelp32-createtoolhelp32snapshot)
- [Process32FirstW](https://learn.microsoft.com/en-us/windows/win32/api/tlhelp32/nf-tlhelp32-process32firstw)
- [Process32NextW](https://learn.microsoft.com/en-us/windows/win32/api/tlhelp32/nf-tlhelp32-process32nextw)
- [GetProcessTimes](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes)
- [GetProcessMemoryInfo](https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-getprocessmemoryinfo)
- [PROCESS_MEMORY_COUNTERS_EX](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex)

## Cadence and ownership

Process enumeration runs at roughly 4 Hz. The graph history and
`gpu_surface_update` advance only when a fresh sample arrives; the host may
tick at display cadence, but the monitor does not submit duplicate graph
points between samples. A surface update copies its samples into runtime-owned
storage and does not invalidate or rebuild the ordinary procedural description.

The table reports working set (`WS`) and private committed memory
(`PRIVATE`) separately. Working set includes resident shared pages, while the
private value comes from `PROCESS_MEMORY_COUNTERS_EX.PrivateUsage`. This makes
the monitor's own footprint diagnosable instead of presenting working set as
an unexplained generic memory number.

The process monitor runs from its separate repository and calls the reusable
`alicorn_sdl_gpu.Application` / `Run` host through the `vendor/alicorn`
submodule. The app package does not call the renderer, retain SDL pointers, or
reach into retained node maps. The host borrows the application state only
while invoking callbacks; it owns the SDL window, event loop, compositor, and
GPU resource retirement.

## Smoke evidence

On the development Windows host, the bounded smoke command is run from the
separate repository with `tools/run.ps1 -Smoke`. A representative three-second
run reported:

```text
samples 11
rows 92
surface_updates 11
surface_frames 11
submissions 11
retired 11
max_frames_in_flight 3
query_failures 781
```

The query failures are expected on a live Windows machine because some
processes are protected or otherwise inaccessible. They are observable rather
than hidden. The smoke test proves the sampler, graph update path, swapchain,
and bounded fence retirement coexist; it is not yet a cross-platform process
monitor proof.

## Known limits

- Windows is the only implemented sampler. Other hosts render an empty but
  buildable app boundary until a platform sampler is added.
- The visible-row viewport is fixed-height and uses whole-row scroll steps.
- The reusable host is intentionally small and experimental; it is not a
  complete cross-platform application shell.
- CPU and memory values are sampled data, not a system-wide accounting proof.
- No process termination, tree view, icons, GPU metrics, settings, or
  accessibility projection has been added.
- The app has no dedicated dogfood performance report yet; runtime counters
  and the native smoke summary are the first evidence surface.

## Next application-driven work

Do not generalize the graphics API yet. The next useful work is to run the
interactive app, exercise sort/reorder/filter/selection under real process
churn, and extract only the missing host or widget primitives that the app
actually needs.
