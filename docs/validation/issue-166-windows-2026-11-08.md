# Issue #166 — live theme editing Windows prototype

Validated on Windows on 2026-11-08 in a native SDL3/D3D12 process with the
project-pinned Odin `dev-2026-11-nightly:9a69916`. SDL reported version 3.4.2.
The machine's WMI CPU/GPU details were unavailable to this process, so they
are not recorded.

## Prototype

`examples/10_live_theme` is an opt-in development example. The ordinary
runtime does not start a file watcher. When launched with `--live-theme`, a
worker polls file metadata every 80 ms, waits for a 240 ms quiet period,
compiles through the existing strict theme compiler, validates that the file
did not change during compilation, and publishes one owned candidate to the
UI thread. A 1 MiB source limit is enforced before reading. Invalid candidates
show a source-located diagnostic and leave the last-good runtime theme intact.

Runtime replacement keeps the theme ID stable and stages owned storage before
releasing the previous snapshot. Paint-only changes request presentation
without rebuilding the application description; metric and motion-policy
changes invalidate the root because application-authored layout and motion
requests may depend on them. Identical runtime values are a no-op. Material
definitions are validated by the compiler but are not applied by this first
slice because the runtime has no stable named-material replacement registry.

## Windows native smoke

The example was built and launched with its SDL3 runtime DLL. The process
created an SDL window and selected the D3D12 GPU backend. The following file
sequence was exercised against the running process:

1. A valid initial theme was adopted.
2. A valid accent-color edit was adopted while the process remained open.
3. Invalid JSON was rejected with a source location; the last-good theme
   remained installed.
4. A subsequent valid edit was adopted, proving recovery.
5. Two saves 35 ms apart produced one adoption of the final persisted file,
   consistent with the debounce/coalescing policy.

Accepted-candidate process logs measured compile times of about 0.13–0.24 ms,
compile-to-UI-adoption delays of about 0.08–0.11 ms, and change-detection-to-
adoption delays of about 242–243 ms. The latter includes the configured 240 ms
debounce. These measurements stop at UI-thread adoption; no screenshot or
frame-presentation instrumentation was available, so they do not establish
edit-to-visible latency or quantify improvement over a controlled restart
baseline. The UI automation service could not enumerate the SDL window for
pixel inspection.

## Checks

- `tools/test.ps1 -Odin <project-pinned Odin>` — passed all configured suites,
  including AccessKit ABI/UIA, runtime, theme, UI, and native host checks.
- `tools/check.ps1 -Odin <project-pinned Odin>` — passed all configured builds
  and checks.
- `odin test runtime` — 326 tests passed, including theme replacement,
  invalid-candidate retention, stable identity, style-domain invalidation,
  interaction-state retention, and per-Runtime isolation.
- `odin test theme` — 35 tests passed.
- `odin check examples/10_live_theme` and `odin build examples/10_live_theme` —
  passed and linked; the native smoke required the SDL3 DLL beside the
  executable.
- `git diff --check` — passed.
- The compiler emitted existing large-stack warnings for the native test
  helper `Native_Secondary_Window`; no check failed.

## Remaining acceptance evidence

This is a successful Windows implementation prototype, not a complete GO
decision for #166. Actual visual output and edit-to-visible latency still need
an instrumented or manually captured run. macOS validation, a two-window
watcher/consumer scenario, and a controlled comparison with the normal
restart-based theme-edit loop were not performed. The example intentionally
supports one watched window, and must remain explicitly opted in; no watcher
was added to release runtime paths.
