# Focused text-layout benchmark

This workload measures Alicorn's headless retained text and layout path. It
does not include SDL/GPU presentation, file I/O, Caliber, or Scratchpad startup.
It is a comparison point for future changes on the same machine, not a
cross-machine performance promise.

Run it from the repository root:

```powershell
.\tools\bench_text_layout.ps1
```

```sh
./tools/bench_text_layout.sh
```

The script builds `benchmarks/text_layout` with Odin's `-o:speed` profile and
runs one process. Each invocation constructs 20,000 logical rows with varied
paragraph lengths. Visible rows wrap in an 1180 × 860 logical viewport and use
the bundled Atkinson Hyperlegible Next regular and italic faces. Every paragraph
has two typography spans and three paint spans, representing emphasis, italic,
link, inline-code, and search-like decoration. The app records measured row
heights into Alicorn's sparse variable-height list index after each frame.

Eight untimed frames warm the initial geometry. The timed phases are:

| Phase | Work |
|---|---|
| `variable_height_scroll` | 120 frames, scrolling by 160 logical pixels per frame at 1180 px width |
| `wrapped_width_reflow` | 40 frames alternating 940 px and 680 px widths while continuing to scroll |

The benchmark reports phase wall time, average time per frame, fresh text shape
calls, shaping-cache hits, layout-node visits, and retained-node count. The
height range and sparse measured-entry count are reported to confirm that the
fixture exercises variable-height wrapping.

## Windows capture

Captured 2026-10-02 at 20:06 local time on the following environment:

| Item | Environment |
|---|---|
| OS | Windows 10 Home 22H2, build 19045.6466 |
| CPU | AMD Ryzen 5 7600X 6-Core Processor |
| Logical processors | 12 |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Build profile | `-o:speed` |
| Runtime | Headless Alicorn runtime; no native host or GPU |

Three fresh process invocations produced these per-phase times. The reported
value is the median of the three runs; the range shows run-to-run variation.

| Phase | Frames | Median total | Median per frame | Per-frame range |
|---|---:|---:|---:|---:|
| Variable-height scroll | 120 | 395.319 ms | 3.294 ms | 3.260–3.424 ms |
| Wrapped-width reflow | 40 | 144.535 ms | 3.613 ms | 3.558–3.624 ms |

The measured work was stable across all three processes:

| Phase | Shape calls | Shape-cache hits | Layout visits | Retained nodes at phase end |
|---|---:|---:|---:|---:|
| Variable-height scroll | 492 | 0 | 1,787 | 15 |
| Wrapped-width reflow | 444 | 0 | 482 | 13 |

The initial 1180 px pass measured row heights from 62.4 to 104 logical pixels.
After scrolling and narrow-width reflow, the sparse index held 317 measured
rows spanning 62.4 to 187.2 logical pixels; the shaping cache held 317 entries.

This capture is a baseline, not a latency target. Timing includes retained
description/reconciliation, shaping, layout, paint preparation, and per-frame
application work. Compare like-for-like builds and environments, and inspect
the work counters alongside elapsed time.
