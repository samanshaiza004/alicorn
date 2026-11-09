# 10 · Live Theme

This is an opt-in development dogfood for editing a JSON theme while the
native window is running. It uses the same strict parser, compiler, and runtime
adapter as `tools/theme`; a successful candidate is adopted on the application
thread. A syntax or compiler error is displayed with its source location, and
the last good runtime theme stays active.

From the repository root:

```powershell
odin build examples/10_live_theme `
  -collection:alicorn=. `
  -out:out/examples/10_live_theme.exe
out/examples/10_live_theme.exe --live-theme examples/10_live_theme/theme.json
```

Without `--live-theme`, the app starts no watcher or worker. With the option,
the worker checks file metadata every 80 ms, waits for a 240 ms quiet period,
then reads and compiles off the UI thread. The candidate is accepted only if
the file metadata still matches after the read. Editor saves that replace the
file atomically are therefore picked up on the next check. Inputs above 1 MiB
are rejected before reading. The console reports source bytes, compile time,
file-change-detection-to-UI-adoption delay, and compile-to-UI-adoption delay
for accepted candidates; measure actual edit-to-visible latency separately
with a screen recording or stopwatch. The detection interval is bounded by
the 80 ms poll period; the change-to-adoption metric includes the debounce.

Try a valid save, an invalid JSON save, then another valid save. The preview
must keep its last-good colors through the invalid version and apply the next
valid one. Paint-only reloads request presentation without rebuilding the
application description; only the initial theme registration, metric/motion
changes, or diagnostic text changes need root invalidation.

The first slice demonstrates colors and button recipes. Named material
definitions are validated by the compiler but are not registered or replaced
by this example; the runtime does not yet expose stable named material slots.
The example uses one window. Each window owns a separate Runtime and theme
registry; per-window file watching/publication is not included in this slice.
The runtime test suite checks that replacing a theme in one Runtime does not
mutate another Runtime with the same local theme ID.
