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

## macOS capture

Captured 2026-10-02 CDT at Alicorn
`f35c2a02e5359d5346a05dad6cc5e11965c2c812`. The benchmark code was unchanged
from `b486dcf`, which introduced the Windows capture above.

| Item | Environment |
|---|---|
| OS | macOS 27.0, build 26A428 |
| Mac model | MacBookAir10,1 |
| CPU / architecture | Apple M1 / arm64 |
| Logical processors / physical memory | 8 / 8 GiB |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Build profile | `-o:speed` |
| Runtime | Headless Alicorn runtime; no native host or GPU |

Three sequential fresh processes used the same optimized binary. The first
was launched by `tools/bench_text_layout.sh --odin <compiler>`; the next two
invoked `out/alicorn_text_layout_benchmark` directly.

| Phase | Frames | Median total | Median per frame | Per-frame range |
|---|---:|---:|---:|---:|
| Variable-height scroll | 120 | 838.331 ms | 6.986 ms | 6.772–7.234 ms |
| Wrapped-width reflow | 40 | 429.800 ms | 10.745 ms | 10.602–10.972 ms |

All three runs reproduced the Windows phase work counters: scroll had 492
fresh shape calls, 0 cache hits, 1,787 layout visits, and 15 retained nodes;
reflow had 444 fresh shape calls, 0 cache hits, 482 layout visits, and 13
retained nodes. The sparse index ended with 317 measured rows, spanning 62.4
to approximately 187.2 logical pixels. The Mac shaping cache reported 319
entries; the Windows summary reported 317. No cache leak or performance
conclusion follows from that two-entry difference in a single workload.

[Raw Mac stdout for all three runs](raw/text-layout-macos-m1-2026-10-02.txt)
is retained alongside this report. The original Windows per-run stdout was
not available in the repository; its supplied summary above is preserved
without reconstructing raw results.

These are separate machine baselines. Matching compiler revisions and phase
work counters help establish workload consistency, but the CPUs and operating
systems differ. Neither capture measures native scrolling latency or GPU
presentation. See the separate [native-hello Mac sample](native-hello-macos.md)
for limited native-host evidence.
