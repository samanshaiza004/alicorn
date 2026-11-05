# v0.2.1 candidate performance scorecard — Windows

Date: 2026-11-04

## Decision

At the measured `736277f` candidate, synthetic construction time improved across all four workloads in both compiler profiles. Large-tree end-frame allocation traffic also fell after the Issue #157 trace change. The retained locality counters stayed stable, the 20,000-row text workload was slightly faster, and closed-inspector motion sampling remained allocation-free with a small steady-state timing delta.

This is a positive performance result for the measured workloads, not complete v0.2.1 release signoff. The native runs below are lifecycle observations rather than a paired v0.2.0 comparison. A matched Windows Scratchpad workload, continuous resize/input responsiveness, DPI coverage, and native frame p99 are still outstanding.

## Compared revisions and environment

| Item | Value |
| --- | --- |
| v0.2.0 baseline | Tag `v0.2.0`, `24a881590b249c5c166c7864482886fb5aa41653` |
| v0.2.1 candidate | `736277f899b7777d0cf907a1b7c962370d7217b0`, `master` at capture time; v0.2.1 was not tagged |
| Host | Windows 10 Home 22H2, build 19045; Ryzen 5 7600X, 12 logical processors; 16 GiB RAM |
| GPU | NVIDIA GeForce RTX 2080 SUPER, driver 595.97 |
| Native backend | SDL 3.4.18, Direct3D 12 |
| Odin | `dev-2026-11-nightly:9a69916`; SDK binary SHA-256 `F2143C351575AF8D9D5757B38E52FA5E17922159556DA9D9CA01FF8E3F345115` |

Both source revisions used the same compiler. The historical v0.2.0 archive needed one isolated Odin-November compatibility substitution in the unused headless image decoder (`decoded.pixels.buf` → `decoded.pixels`). No measured benchmark path uses that decoder. The candidate source was not adapted.

## Construction

The headless probe measured elapsed time for 10,000 containers, 10,000 short-text nodes, 10,000 requested wrapped-text nodes, and a 100-panel tree (601 retained nodes). Each cell is the median of five alternating fresh-process runs, in milliseconds. `-o:speed` was measured separately. `total` is the per-run description plus `end_frame` elapsed time; its median need not equal the sum of the displayed phase medians. These are monotonic elapsed measurements, not process CPU time; Windows process CPU time is not exposed by this probe. Raw min/max ranges are preserved in the JSON captures.

The 10k text cases are construction/retained-measurement requests, not glyph-shaping timing: the probe has no loaded font and records no shape requests. The separate text-layout fixture below is the shaping and virtualized-row measurement.

| Workload | Default: v0.2.0 → candidate | `-o:speed`: v0.2.0 → candidate |
| --- | ---: | ---: |
| 10k containers | 101.817 → 81.643 (−19.8%) | 41.127 → 33.888 (−17.6%) |
| 10k short text | 117.838 → 94.638 (−19.7%) | 52.978 → 49.417 (−6.7%) |
| 10k requested wrapped text | 124.291 → 102.986 (−17.1%) | 66.217 → 58.570 (−11.5%) |
| 100-panel form | 8.752 → 5.970 (−31.8%) | 4.773 → 3.452 (−27.7%) |

Most of the reduction is in `end_frame`. One exception is the optimized short-text description phase: its median rose from 9.838 ms to 12.046 ms (+22.4%), while `end_frame` fell from 42.374 ms to 37.978 ms and total elapsed time improved 6.7%. This is a phase-level tradeoff to retain in future comparisons.

The separate three-process allocator capture measured end-frame persistent allocation traffic:

| Workload | Allocation calls: v0.2.0 → candidate | Requested bytes: v0.2.0 → candidate |
| --- | ---: | ---: |
| 10k containers | 100,111 → 70,107 (−30,004) | 37.087 → 34.563 MB (−2.524 MB) |
| 10k short text | 130,133 → 100,129 (−30,004) | 56.352 → 53.827 MB (−2.524 MB) |
| 10k wrapped text | 130,133 → 100,129 (−30,004) | 57.862 → 55.337 MB (−2.524 MB) |
| 100-panel form | 9,423 → 6,119 (−3,304) | 4.315 → 4.027 MB (−0.288 MB) |

These are requested allocator bytes, not process working set. End-frame allocation capture is instrumented and is intentionally separate from timing runs. The retained node counts match. The structured trace record grew from 72 to 104 bytes; the measured allocator high-water increased by 1,184 bytes for these default trace configurations.

The uninstrumented timing runs also read each short-lived benchmark process's OS peak working set every 1 ms. Candidate medians were 2.8–6.0% lower across these workloads (about 0.29–3.51 MiB). This is synthetic process memory evidence; it excludes GPU allocations and does not predict a full application's working set.

## Retained locality

Seven alternating `-o:speed` runs compared the v0.2.0 tag with the candidate. The 10k unchanged-root update was 13.150 ms → 13.182 ms (+0.24%). Initial construction of the 10k-node tree was 58.376 ms → 50.969 ms (−12.7%).

The locality counters matched in all seven runs per revision:

- Waking an unchanged 100-node retained region under an unrelated root wake performed zero layout, paint, composition, measurement, and display-finalization work.
- Changing one value in that 100-node region performed zero layout work and visited 101 paint/composition nodes.
- An unchanged 10k-node root update performed zero layout, paint, composition, and display-finalization work.

The unrelated-sibling reuse probe was 33.7 µs → 36.5 µs (+8.3%, +2.8 µs). This small absolute delta did not approach the benchmark's gross-regression failure threshold; keep it as a monitored result rather than interpreting seven samples as a performance guarantee.

## Text shaping and virtualization

The headless text fixture used 20,000 logical rows with variable-height text, 11 initially visible rows, 120 scroll frames, and 40 width-reflow frames. Five alternating fresh-process `-o:speed` runs per revision gave:

| Operation | v0.2.0 median | Candidate median | Change |
| --- | ---: | ---: | ---: |
| Variable-height scroll, 120 frames | 297.061 ms (2.476 ms/frame) | 292.847 ms (2.440 ms/frame) | −1.4% |
| Wrapped-width reflow, 40 frames | 128.839 ms (3.221 ms/frame) | 123.693 ms (3.092 ms/frame) | −4.0% |

Work counts were identical: scroll used 246 shape calls and 3,460 layout visits; width reflow used 362 shape calls and 924 layout visits. The fixture exercises shaping and virtualized visible-row work, but does not measure native GPU presentation or a live application scroll session.

## Motion diagnostics and scheduler cost

The closed-inspector headless comparison used five alternating fresh processes under `-o:speed`: pre-#144 motion authoring at `9690333` versus candidate `736277f`, with no inspector runtime constructed. It sampled 1, 100, and 1,000 active owners and 1,000 successive target changes. Since the two source revisions span more than a single diagnostic-only patch, this is an end-to-end revision comparison, not a perfectly isolated attribution of inspector instrumentation.

| Active owners | Tick p50: before → candidate | Tick p95: before → candidate | Tick p99: before → candidate |
| ---: | ---: | ---: | ---: |
| 1 | 0.4 → 0.4 µs | 0.5 → 0.4 µs | 0.7 → 0.542 µs |
| 100 | 31.0 → 31.2 µs | 39.205 → 39.415 µs | 57.144 → 48.252 µs |
| 1,000 | 313.4 → 315.55 µs | 418.23 → 419.57 µs | 503.232 → 516.107 µs |

At 1,000 owners, tick p50/p95 rose about 0.7%/0.3%; process CPU cycles rose 0.5%. Retarget p50/p95 for 1,000 changes rose 2.5%/4.8% (4.0/4.2 µs → 4.1/4.4 µs). Tick and retarget paths each recorded zero allocations. Frame-submission acknowledgements allocated 180 times / 5,940 bytes per 180-sample batch in both revisions; those allocations are not motion sampling.

Diagnostics have a visible setup-memory cost. Candidate versus pre-#144 motion owner setup requested an additional 59,216 bytes at 1 owner, 91,600 bytes at 100 owners, and 321,360 bytes at 1,000 owners. This is a setup allocation, not per-frame work. The inspector was closed and no inspector UI was created during this benchmark.

## Native two-window lifecycle observations

The native fixture ran on SDL 3.4.18 / Direct3D 12. It is a candidate-only behavior validation, not an A/B performance run. Each scenario ended with a five-second quiet interval after its terminal idle checkpoint; the event count did not change during that interval, and the host exited cleanly.

| Scenario | Motion and presentation observations | Timing observations |
| --- | --- | --- |
| Minimize and restore secondary window | Secondary scheduler held at 18 samples while minimized, then took one restore sample. Primary continued. At terminal idle: primary 472 samples / 478 submissions; secondary 397 / 399. | Frame p95 17.991 ms; motion max lateness 77.927 ms; cumulative GPU encode/submit/fence times 25.543 / 67.614 / 4.094 ms. |
| Close minimized secondary during motion | Secondary closed with one active owner; close checkpoint recorded 20 samples and 22 submissions. Primary continued. At terminal idle: primary 450 samples / 455 submissions. | Frame p95 18.079 ms; motion max lateness 121.487 ms; cumulative GPU encode/submit/fence times 28.249 / 73.719 / 11.567 ms. |

The frame p95 values and cumulative host timings describe these individual fixture runs, not a cross-revision distribution. The native summary does not expose frame p99 or per-stage GPU p95/p99. It also does not measure input-event latency; no input was generated by the fixture. The quiet interval plus zero active owners establishes the fixture's settled state and stable diagnostic event count, but not zero operating-system wakeups in general.

The Windows dual-window titlebar-drag behavior was physically observed after the host-wide move-loop change: both visible windows continued to animate while one was dragged. That observation establishes behavior, not frame latency; it was not included as a timed benchmark run here.

## Real Scratchpad workload

The existing [Issue #157 macOS A/B report](issue-157-construction-cpu-macos-2026-11-04.md) provides the real-application complement: opening and closing a 5,002-line document reduced cumulative application-build callback time by a paired median 8%, while total process CPU and peak RSS stayed flat. It is an Apple M1 comparison of the structured-trace change, not a matched Windows v0.2.0-versus-`736277f` comparison. No Windows Scratchpad A/B is claimed in this scorecard.

## Scorecard and remaining release evidence

| Question | Finding |
| --- | --- |
| Established performance invariants regressed? | No measured regression in unchanged-root locality or visible-row work counts. Construction, end-frame allocation traffic, and synthetic working set improved. The small sibling-reuse timing increase remains monitored. |
| New capabilities add measurable cost? | The motion sampler's closed-inspector steady-state delta was small in this run and remained allocation-free. Diagnostic owner setup adds 59–321 KiB across tested owner counts. |
| What changed for application users? | The retained trace fix lowered construction time and allocator traffic in these probes. The Mac Scratchpad A/B shows an 8% callback-time improvement on a large-document interaction; a Windows app-level comparison is still needed. |

Still outstanding for a full release-level comparison: a matched Windows Scratchpad workload; repeated native runs with per-frame p50/p95/p99; continuous resize and input responsiveness; DPI/refresh transitions; and a comparable native run on another supported OS/GPU backend. Preserve the October Windows benchmark reports as historical baselines; their compiler and workloads differ and they are not regression thresholds for this November-toolchain comparison.

## Raw captures and reproduction

Redacted raw per-process results and the capture manifest are in [`raw/v0.2.1-windows-2026-11-04/`](raw/v0.2.1-windows-2026-11-04/manifest.json). Absolute local paths were replaced with `$ALICORN` in JSON captures; timing samples and event ordering are otherwise preserved.

Construction reproduction from the repository root:

```powershell
$Odin = "out\toolchains\odin-dev-2026-11\dist\odin.exe"
python tools\bench_construction.py --odin $Odin --ref v020=v0.2.0 --ref v021=736277f899b7777d0cf907a1b7c962370d7217b0 --runs 5 --windows-process-metrics --workloads containers:10000,short:10000,wrapped:10000,panel:100 --output out\release-v0.2.1-windows-2026-11-04\construction-default
python tools\bench_construction.py --odin $Odin --ref v020=v0.2.0 --ref v021=736277f899b7777d0cf907a1b7c962370d7217b0 --runs 5 --speed --windows-process-metrics --workloads containers:10000,short:10000,wrapped:10000,panel:100 --output out\release-v0.2.1-windows-2026-11-04\construction-speed
python tools\bench_construction.py --odin $Odin --ref v020=v0.2.0 --ref v021=736277f899b7777d0cf907a1b7c962370d7217b0 --runs 3 --allocations --workloads containers:10000,short:10000,wrapped:10000,panel:100 --output out\release-v0.2.1-windows-2026-11-04\construction-allocations
```

Retained locality, motion diagnostics, and native lifecycle captures:

```powershell
python tools\bench_retained_locality.py --odin $Odin --baseline v0.2.0 --candidate 736277f899b7777d0cf907a1b7c962370d7217b0 --runs 7 --speed
python tools\bench_motion_diagnostics.py --odin $Odin --baseline 9690333ea5dbe335737d59a1c0bfb331edd3ee44 --candidate 736277f899b7777d0cf907a1b7c962370d7217b0 --runs 5
.\tools\secondary_motion_validation.ps1 -Odin (Resolve-Path $Odin).Path -QuietSeconds 5
```

The text-layout capture builds `benchmarks/text_layout` from each archived construction snapshot with `-o:speed`, then alternates five fresh-process runs per executable. The snapshots created by the commands above can be built with:

```powershell
& $Odin build out\release-v0.2.1-windows-2026-11-04\construction-speed\v020-24a881590b24\benchmarks\text_layout -o:speed -out:out\release-v0.2.1-windows-2026-11-04\text-layout\v020.exe
& $Odin build out\release-v0.2.1-windows-2026-11-04\construction-speed\v021-736277f899b7\benchmarks\text_layout -o:speed -out:out\release-v0.2.1-windows-2026-11-04\text-layout\v021.exe
```

Its raw per-process output is preserved with the scorecard artifacts.
