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

## Still outstanding for #146

This report does not claim native zero-work acceptance. It does not measure host timer wakes, native presentation visits, D3D12/Metal submissions, minimized-window suspension/restore, DPI changes, secondary-window lifecycle, or shutdown during motion. The Punks UI fixture is headless; the produced Windows executable is available for physical interaction checks, but this report does not claim a new physical UI session. Cross-platform native evidence and any agreed accessibility sessions remain separate release-gate work.
