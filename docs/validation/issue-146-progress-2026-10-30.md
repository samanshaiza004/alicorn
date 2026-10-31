# Issue #146 progress: motion diagnostics and Punks dogfood

**Status:** Evidence update only. Issue [#146](https://github.com/samanshaiza004/alicorn/issues/146) remains open.

Date: 2026-10-30 (local time)

## Candidate and environment

- Alicorn candidate: `e93ac0d58ed3ccfbc4617691a8c3bc9b0073279a`
- Benchmark baseline: `9690333ea5dbe335737d59a1c0bfb331edd3ee44`
- Punks dogfood: `1e66e093b45d88dd4b0e0f21658885dedd07fdf0`, with Alicorn pinned at `9690333`
- OS: Windows 10, build 19045
- CPU: AMD Ryzen 5 7600X, 6 cores / 12 logical processors
- Odin: `dev-2026-09-nightly:a2fb372`
- Build profile: `-o:speed`

The benchmark compares archived source snapshots in alternating fresh processes, five runs per revision. It does not create or open the visual inspector. Diagnostics remain enabled in the candidate, so this measures the closed-inspector runtime path while transition recording and counters are active. Each run samples 1, 100, and 1,000 retained owners for 180 ticks, then performs 1,000 target changes on one owner. Per-run p50/p95/p99 values are computed from operation timings; the report uses the median of those five per-run quantiles.

Reproduce it with:

```powershell
python tools/bench_motion_diagnostics.py `
  --odin 'C:\Users\saman\Documents\odin\dist\odin.exe' `
  --baseline 9690333ea5dbe335737d59a1c0bfb331edd3ee44 `
  --candidate e93ac0d58ed3ccfbc4617691a8c3bc9b0073279a `
  --runs 5
```

The script writes machine-readable results and raw runs under the ignored `out/motion-diagnostics-comparison/` directory.

## Closed-inspector overhead

Active sampling time per tick:

| Active owners | Baseline p50 / p95 / p99 | Candidate p50 / p95 / p99 | Candidate p95 delta |
| ---: | ---: | ---: | ---: |
| 1 | 0.400 / 0.500 / 0.684 µs | 0.400 / 0.500 / 0.721 µs | 0% |
| 100 | 32.600 / 35.105 / 57.162 µs | 32.800 / 34.900 / 55.499 µs | -0.6% |
| 1,000 | 325.100 / 369.370 / 408.548 µs | 328.600 / 377.340 / 410.861 µs | +2.2% |

The 1,000-change retarget workload measured 4.200 / 4.405 / 4.803 µs p50/p95/p99 on the baseline and 4.300 / 4.500 / 4.700 µs on the candidate. Candidate p95 was 2.2% higher.

Owner creation and first target assignment include the one-time diagnostic sidecar allocation:

| Owners | Baseline setup | Candidate setup | Baseline allocations / bytes | Candidate allocations / bytes |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 9.95 µs | 21.95 µs | 1 / 4,032 | 2 / 63,248 |
| 100 | 513.1 µs | 563.0 µs | 6 / 206,592 | 7 / 298,192 |
| 1,000 | 19.272 ms | 21.290 ms | 9 / 1,642,688 | 10 / 1,964,048 |

The 1,000-owner setup was 10.5% slower and made one extra allocation, with 321,360 more measured bytes. This is setup cost, not per-frame allocation. Across the active sampling loops, `motion_tick` made zero allocations on both revisions. The benchmark's simulated submit acknowledgement made 180 allocations for 180 samples on both revisions; those allocations are in the acknowledgement/trace path, not in motion sampling. The 1,000 retarget calls themselves also made zero allocations on both revisions.

The median whole-process CPU-cycle count was 466,958,441 on the baseline and 481,072,025 on the candidate (+3.0%). Whole-process wall time was 101.34 ms and 104.89 ms (+3.5%). These broad totals include setup, all workloads, and identical captured console output; the per-operation timings above are the more useful estimate of runtime diagnostic overhead.

For 1,000 active owners, the candidate recorded 180 sample ticks, 180,000 owner visits, and 180,000 property samples. It retained 128 transition events. The separate 1,000-change churn run recorded 1,000 retargets, 2,000 presentation requests (2,000 coalesced requests), 1,000 submission acknowledgements, and 873 trace evictions at the fixed 128-event capacity.

Every active-sampling workload reported zero application frame builds, reconciliation visits, measurement requests, text shaping, layout visits, paint visits, and composition visits. A final virtual-time advance settled all owners; the headless fixture then made no further motion sample call. This confirms runtime-stage isolation and settled state, but does not measure native timer wakes or GPU submissions.

## Punks dogfood

Punks commit `1e66e09` adds a reduced-motion regression for the fixed-space playback-status indicator. Together with the existing presentation-only/idle regression, it checks that playback status can retarget without changing the reserved geometry, motion sampling does not rebuild the application, reduced motion snaps the decorative opacity to its target, and settled motion returns to idle.

`tools/build.ps1 -TestUi -Odin 'C:\Users\saman\Documents\odin\dist\odin.exe'` passed all 9 Punks UI tests and produced:

`target/windows-x86_64/debug/punks.exe`

The folder also contains `SDL3.dll` and `punks_caliber.dll` for running the executable.

## Local verification

On Alicorn `e93ac0d`, `tools/test.ps1` passed: 302 runtime tests, 39 UI tests, 35 theme tests, 164 native SDL tests, 8 AccessKit contract tests, and 6 scroll-capture tests. Theme checks, generated-theme compilation, and the restoration restart harness also passed.

The connected combined-status query returned no entries when this report was first prepared. GitHub check-run queries now independently confirm all five hosted checks passed for `e93ac0d`, `d9e3c88`, and the native-fixture source revision `772ac45` (regeneration, macOS SDL, Windows static SDL, and both headless jobs). The earlier local test pass remains separate from this hosted CI evidence.

At the time of the October 30 evidence, native zero-work acceptance had not been measured. The Windows run below adds a first bounded native sample.

## Windows native validation (2026-10-31)

**Source revision:** `772ac45` (`test(motion): cover native interrupted settling`). The executable was built from this source tree using Odin `dev-2026-09-nightly:a2fb372`, `-o:speed`, and the bundled SDL 3.4.2. SDL selected Direct3D 12. The host is Windows 10 Home, build 19045, on the same AMD Ryzen 5 7600X system recorded above. The run used a 720 × 360 logical window at 1.0 display scale. The GPU adapter name was not exposed by the captured diagnostics.

The validation mode in Example 09 now applies three scheduled target changes, 80 ms apart after the first 100 ms delay, interrupting the decorative response twice. It then checks motion activity after 1.5 seconds and again after a one-second quiet interval. The sequence is headless with respect to user input, but it exercises the real Windows window, SDL event loop, D3D12 swapchain, motion scheduler, and diagnostics capture.

Reproduce from the Alicorn repository root:

```powershell
.\tools\run_example.ps1 -Example 09_retained_motion `
  -Odin 'C:\Users\saman\Documents\odin\dist\odin.exe' `
  -Speed -AppArgs @('--motion-validation','--diagnostics',
    '--capture-dir=out/issue-146/windows-interrupted-2026-10-31')

.\tools\run_example.ps1 -Example 09_retained_motion `
  -Odin 'C:\Users\saman\Documents\odin\dist\odin.exe' `
  -Speed -AppArgs @('--idle-validation-seconds=3','--diagnostics',
    '--capture-after=1',
    '--capture-dir=out/issue-146/windows-idle-captured-2026-10-31')
```

The first run completed with `SDL application PASS`, 52 total GPU submissions, 50 motion samples/timer wakes, a maximum of two active owners, zero application tick callbacks, and zero native host-only wake events. Its first settled checkpoint reported 0 active owners, 0 active properties, and 0 unestablished deadlines. The second checkpoint, about one second later, reported the same. The flight-recorder timeline ends with a no-op sample (0 presentation updates and 0 GPU submissions) after settlement; there are no later motion samples or GPU submissions before the idle checkpoint. Application builds and text shaping occur only during initial/target descriptions, not during the motion samples. The run's aggregate frame p95 was 2.1 µs; this is dominated by no-op/event-loop samples and is not a presentation-latency figure.

The separate idle-only run completed after 3.12 seconds with one initial GPU submission, one event wait, zero application tick calls, and zero native host-only wake events. The requested automatic capture did not fire because the idle event loop remained blocked until its validation timeout; this is why the run's final host counters are recorded from its `SDL application PASS` line rather than a diagnostic bundle.

### Follow-up: Windows event-wait diagnosis and correction (2026-10-31)

**Source revision:** `5f7913b` (`fix(native): avoid tight SDL timeout retries on Windows`). This change adds diagnostic-only event-wait attribution and duration counters, plus a Windows-only 1 ms timeout margin. It does not change the motion kernel or sampling cadence. The margin compensates for SDL's Windows backend converting nanosecond remainders to integer milliseconds by truncation; `WIN_WaitEventTimeout` uses `SDL_NS_TO_MS(timeoutNS)` before calling the Win32 wait in both [SDL 3.4.2](https://github.com/libsdl-org/SDL/blob/release-3.4.2/src/video/windows/SDL_windowsevents.c#L2277-L2288) and [SDL 3.4.18](https://github.com/libsdl-org/SDL/blob/release-3.4.18/src/video/windows/SDL_windowsevents.c#L2315-L2326). The public wait API documents millisecond timeouts in [SDL_WaitEventTimeout](https://wiki.libsdl.org/SDL3/SDL_WaitEventTimeout).

The instrumented pre-fix interrupted-motion run recorded **7,085** `WaitEventTimeout` calls over about 3.03 seconds. Of these, 7,014 requested 1 ms and 7,022 returned in under 100 µs. Deadline attribution identified 6,443 as primary-motion deadlines, 641 as application-scheduled deadlines, and one as the smoke-exit deadline. Motion samples themselves remained near the normal 16.7 ms cadence; the excess calls were rapid retries near SDL's truncated sub-millisecond wait boundary.

After applying the one-millisecond Windows margin, the same fixture completed in about 3.03 seconds with **55** event-wait calls: 55 timed out, none returned an event, none requested zero or one millisecond, and none returned in under 100 µs. The 55 waits accounted for 2.768 seconds total and a maximum wait of about 1.000 seconds; their selected deadline sources were 49 primary-motion, five application-scheduled, and one smoke-exit. The change removes the measured short-wait retry loop in this run while allowing up to roughly one additional millisecond of deadline lateness.

The padded run used Windows 10 Home build 19045, Ryzen 5 7600X, Odin `dev-2026-09-nightly:a2fb372`, `-o:speed`, SDL 3.4.2 and D3D12, at 720 × 360 logical units and 1.0 scale. It produced 51 GPU submissions and 49 motion samples/timer wakes. At both the settled checkpoint (~2.27 s) and the idle checkpoint (~3.31 s), there were zero active owners, properties, or unestablished deadlines. `application_tick_calls` remained zero; motion sampling did not invoke application description, reconciliation, shaping, layout, or paint. The aggregate frame p95 includes blocked event-wait time and is not a presentation-latency measure.

Reproduce the post-fix run from the Alicorn repository root:

```powershell
.\tools\run_example.ps1 -Example 09_retained_motion `
  -Odin 'C:\Users\saman\Documents\odin\dist\odin.exe' `
  -Speed -AppArgs @('--motion-validation','--diagnostics',
    '--capture-dir=out/issue-146/windows-interrupted-padded-2026-10-31')
```

The resulting event log is valid JSONL and records session start, target changes, settled and idle checkpoints, and shutdown without file paths. The diagnostic event-wait duration and source counters are only collected when diagnostics are enabled; the 1 ms Windows wait margin is the production behavior under test.

This is a bounded native fixture result, not a count of every Windows kernel wake. `native_host_wake_events` counts Alicorn's dedicated host-only wake event, and `event_waits` counts calls into SDL; neither independently counts all OS wakeups. It also does not show zero wakes while motion is active: timed waits and motion timer wakes are expected during presentation.

The complete local `tools/test.ps1` suite passed on this source: 302 runtime tests, 39 UI tests, 35 theme tests, 165 native SDL tests, 8 AccessKit ABI tests, and 6 scroll-capture tests; theme validation/code generation, the restart restoration harness, and native text-input/ownership contracts passed as well. GitHub's connected status query returned no statuses for `5f7913b` at the time of this report update, so hosted CI is not claimed here.

### Remaining limits and follow-up

- No physical minimize/restore, mixed-DPI, secondary-window, accessibility, or shutdown-during-motion session was performed. These remain release-gate items.
- The 1x D3D12 smoke is not evidence for macOS/Metal or Linux/Vulkan, alternate DPI scales, nor GPU-adapter coverage. The Punks physical playback-state pass remains as previously recorded; it did not exercise the new #144 snapshot on its older pinned Alicorn revision.
- All five hosted checks passed for the earlier native fixture source revision `772ac45`: [Windows/macOS SDL](https://github.com/samanshaiza004/alicorn/actions/runs/41228759044), [headless job 1](https://github.com/samanshaiza004/alicorn/actions/runs/41228758919), [headless job 2](https://github.com/samanshaiza004/alicorn/actions/runs/41228758951), and [regeneration](https://github.com/samanshaiza004/alicorn/actions/runs/41228758921). GitHub also reports all five checks passed for `e93ac0d` and `d9e3c88`.

Captured artifacts are in the ignored local `out/issue-146/windows-interrupted-2026-10-31/` directory, including `diagnostics.json`, `timeline.json`, `windows.json`, `inspector.txt`, `screenshot.ppm`, and valid `events.jsonl`. The idle-only run's bundle directory is empty because automatic capture was not reached.

## Still outstanding for #146

The Windows run supports retained stage isolation and shows that D3D12 submissions stop after settlement in this fixture. The event-wait attribution isolated and corrected a Windows SDL timeout retry loop, but it does not count every OS-level wake. Manual minimize/restore and secondary-window acceptance, alternate DPI configurations, cross-platform native evidence, and agreed accessibility sessions remain release-gate work. Keep the issue open.
