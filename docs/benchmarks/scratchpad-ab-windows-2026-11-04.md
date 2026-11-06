# Matched Scratchpad A/B — Windows

Date: 2026-11-04

## Finding

On the same Scratchpad source and generated workspace, the v0.2.1 candidate reduced cumulative application-build callback time by a paired median **6.19%** versus v0.2.0. First successful application submission was effectively flat: paired median **+1.82%** (about 0.18 ms at a roughly 10 ms median). Process CPU and peak working set were also effectively unchanged at this sample size. Both revisions made 23 primary GPU submissions in each measured process.

This is a positive but modest application-level result for one Windows host and one automated workload. It does not establish interactive resize pacing, native input latency, displayed-frame latency, or a general performance improvement across Scratchpad workloads.

## Revisions and environment

| Item | Value |
| --- | --- |
| Baseline | Alicorn v0.2.0, `24a881590b249c5c166c7864482886fb5aa41653` |
| Candidate | `736277f899b7777d0cf907a1b7c962370d7217b0` (v0.2.1 candidate; untagged at capture time) |
| Scratchpad | `751f949c24c0ad3108c201358f7a65b740cd951a`, identical for both Alicorn builds |
| Caliber | `197cd964cc7265bc60df599a6b8562eac7c75f3a` |
| Host | Windows 10 Home 22H2, build 19045; Ryzen 5 7600X, 12 logical processors; 16 GiB RAM |
| GPU | NVIDIA GeForce RTX 2080 SUPER, driver 595.97 |
| Native backend | SDL 3.4.18 / Direct3D 12 |
| Toolchain | Odin `dev-2026-11-nightly:9a69916`; Go `1.27.1` |
| Build profile | Release, Odin `-o:speed` |

The Scratchpad revision is a compatibility revision, not the current `main`: current Scratchpad uses Alicorn APIs unavailable in the v0.2.0 baseline. Using one older revision keeps the comparison focused on the Alicorn change. It limits how directly this result describes current Scratchpad.

## Workload and method

A generated workspace contained eight directories, 192 small files, a README, and a 5,002-line `application/sample_00.go` file (193 files total). Each fresh process ran the same nine actions:

1. Open `README.md`.
2. Open `application/sample_00.go`.
3. Switch back to `README.md`.
4. Open Quick Open.
5. Wait until Quick Open's index is ready, then close it.
6. Open Settings.
7. Close Settings.
8. Close `README.md`.
9. Close the remaining Go document.

A benchmark-only, environment-gated scheduled hook exercised Scratchpad's existing application/backend command paths. It did not synthesize native keyboard or pointer input. Each process also passed the existing smoke publication, worker-wake, and ordered-shutdown checks.

There was one unmeasured warmup per revision and seven measured fresh-process pairs. The warmup ran baseline then candidate; measured pair order alternated each round. All 16 processes passed the smoke and nine-action sequence checks. The application process ran for approximately three seconds because the smoke harness has a fixed exit window.

The metrics mean:

- **First application submission:** elapsed time from the native application-loop timing origin to the first successful GPU submission that consumed an application frame. This is startup-to-submit timing; it is neither input latency nor display-delivery latency.
- **Cumulative app build:** sum of measured application `build` callback durations during the process.
- **Largest app build:** maximum single application `build` callback duration.
- **Process CPU:** `Process.TotalProcessorTime` collected after exit. It includes the fixed smoke interval, not just active interaction.
- **Peak working set:** Windows process peak working set. The runner sampled the process every 10 ms while active.
- **Paired change:** median of the seven per-pair percentage changes, candidate relative to baseline. Positive means higher/slower.

## Results

Times are milliseconds. Each revision column shows median and observed min–max across seven measured processes.

| Metric | v0.2.0 median (min–max) | Candidate median (min–max) | Paired median change |
| --- | ---: | ---: | ---: |
| First application submission | 10.053 (9.585–29.764) | 10.322 (9.816–29.649) | +1.82% |
| Cumulative app build callbacks | 21.496 (20.599–22.382) | 19.792 (18.627–22.326) | −6.19% |
| Largest single app build callback | 5.773 (5.600–6.967) | 5.547 (5.077–7.122) | −0.94% |
| Process CPU | 671.875 (562.500–765.625) | 656.250 (593.750–796.875) | −2.33% |
| Process wall time | 3,428.619 (3,405.284–3,447.604) | 3,410.250 (3,403.103–3,474.488) | −0.65% |
| Native application-loop wall time | 3,043.322 (3,016.612–3,053.099) | 3,018.353 (3,008.605–3,081.403) | −0.89% |
| Peak working set | 172.430 (171.895–173.496) MiB | 171.930 (170.934–173.059) MiB | −0.52% |
| Primary GPU submissions | 23 (23–23) | 23 (23–23) | 0.00% |

The raw per-process values and application log captures are available in [`raw/scratchpad-ab-windows-2026-11-04/`](raw/scratchpad-ab-windows-2026-11-04/manifest.json).

## Interpretation

The lower cumulative build time is the clearest result. First submission medians differ by 0.27 ms, and the paired percentage result is +1.82%; the observed ranges include similar roughly 30 ms outliers on both revisions. I would treat startup submission as flat in this run rather than claim a regression or improvement.

Process CPU differs by 2.33% and peak working set by 0.52%. Both are small compared with the run-to-run ranges; the fixed smoke interval also makes total CPU a coarse active-work measure. Process and host wall times are dominated by the three-second smoke window. GPU submission count is identical.

The baseline executable required a temporary Odin dev-2026-11 compatibility substitution in the unused image decoder (`decoded.pixels.buf` to `decoded.pixels`). The measured path does not use that decoder. The copied Scratchpad build driver also received temporary AccessKit collection arguments so the same source could build against both Alicorn revisions. The baseline received a measurement-only host-summary overlay for cumulative app-build time, first application submission, and primary GPU submission count; the candidate already emitted these fields. The Scratchpad sequence hook and all build accommodations were confined to the isolated benchmark copy.

## Performance acceptance status

| Criterion | Status | Evidence |
| --- | --- | --- |
| No retained-locality counter regression | **Pass for measured probes** | The seven-run retained-locality comparison in the [Windows scorecard](performance-scorecard-v0.2.1-windows-2026-11-04.md) preserved its zero-work and locality counters. |
| No persistent blank regions during resize | **Not measured** | Needs a continuous horizontal, vertical, and diagonal resize fixture. |
| No stale-size frame after resize settles | **Not measured** | Requires frame-size agreement capture during resize and after the final size. |
| No unexplained major increase in active-frame p99 | **Not measured** | This event-driven smoke workload has no sustained active presentation sequence and does not provide a comparable p99 distribution. |
| Zero unnecessary application submissions after settling | **Not established by this A/B** | The A/B sequence exits shortly after its actions. The separate candidate-only native lifecycle capture is not a matched post-settlement submission comparison. |

This benchmark closes the matched Windows Scratchpad comparison. It leaves the resize/input responsiveness and active native frame-pacing work as the next release-validation items. It does not measure input-to-display latency, PresentMon display delivery, DPI transitions, or another operating system/backend.

## Reproduction artifacts

- [Per-process CSV](raw/scratchpad-ab-windows-2026-11-04/samples.csv)
- [Capture manifest and SHA-256 hashes](raw/scratchpad-ab-windows-2026-11-04/manifest.json)
- [PowerShell runner](raw/scratchpad-ab-windows-2026-11-04/run_windows_ab.ps1)
- [Temporary Scratchpad sequence/build-driver patch](raw/scratchpad-ab-windows-2026-11-04/scratchpad-benchmark-harness.patch)
- [Baseline Alicorn compatibility and measurement patch](raw/scratchpad-ab-windows-2026-11-04/alicorn-v020-measurement-compatibility.patch)
- [All 16 raw process logs](raw/scratchpad-ab-windows-2026-11-04/logs/)

