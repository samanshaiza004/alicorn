# Final Windows performance refresh — 2026-10-28

This final pre-release refresh reruns Alicorn's documented headless benchmarks
on the Windows release-candidate source tree. It compares matched optimized
retained-work runs with the post-merge baseline from October 27. The results
are specific to this machine and workload; they are not cross-framework claims
or general latency guarantees.

## Environment and method

| Item | Value |
|---|---|
| OS | Windows 10 Home 22H2, build 19045.6466 |
| CPU | AMD Ryzen 5 7600X, 12 logical processors |
| GPU | NVIDIA GeForce RTX 2080 SUPER |
| Memory | 16 GiB installed |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Source | `master` at `3e31c743`; measured checkout `67417bb`, identical Git tree `e2850cc` |

Each workload used three fresh processes. `tools/bench.ps1` was also rerun in
its default build profile; its timings are intentionally excluded from the
optimized comparison below. The matched retained-work comparison uses
`odin build benchmarks -o:speed`; `tools/bench_text_layout.ps1` and
`tools/bench_material.ps1` also build with `-o:speed`. The material script ran
all geometry checksum and vertex-budget cases at scales 1, 1.25, 1.5, and 2.
The raw outputs are in
[`raw/performance-final-windows-2026-10-28.txt`](raw/performance-final-windows-2026-10-28.txt).

The reference is the three-process post-#103-merge run on source `4a96793`,
reported in the [October 27 audit](performance-audit-windows-2026-10-27.md).
The benchmarked runtime and benchmark sources are unchanged between that
reference and this release-candidate tree, so the comparison isolates run-to-
run variation on the same machine rather than a new runtime optimization.

## Retained-work comparison

Times are per benchmark operation. Percentages compare the medians; negative
values are lower times.

| Workload | Oct 27 median (range) | Oct 28 median (range) | Median change |
|---|---:|---:|---:|
| 10,000-node unchanged root invalidation | 18.547 ms (16.705–20.081) | 16.393 ms (16.328–17.260) | −11.6% |
| 10,000-node root invalidation, one value changed | 17.958 ms (17.828–18.409) | 15.499 ms (15.480–16.465) | −13.7% |
| 100-node region changed | 2.307 ms (2.263–3.563) | 2.190 ms (2.138–2.220) | −5.1% |
| Reuse a retained 10,000-node subtree | 2.755 ms (2.696–3.307) | 2.427 ms (2.323–2.470) | −11.9% |
| 1,000,000-item virtual list, 100 frames | 8.481 ms (8.387–8.888) | 8.325 ms (8.276–8.445) | −1.8% |

The medians are lower in all five rows. The unchanged-root ranges overlap, and
the million-item result is effectively unchanged at this sample size. The
one-value, changed-region, and retained-subtree samples were all faster in
this rerun, with non-overlapping three-run ranges; treat that as encouraging
same-machine evidence, not a statistical guarantee. The runtime source did not
change between the compared captures, so these lower times should not be
credited to a new code change.

The work counters remained structurally stable: an untouched 10,000-node tree
completed 10,000 idle frames with zero allocations, reconciliation, layout,
paint/composition visits, or GPU submissions. The million-item fixture kept
23 retained visual nodes. The 1,200 custom-surface updates still caused zero
ordinary UI work and zero allocations. Their measured wall time varied between
runs and is not evidence of a performance change.

## Text layout and material paths

| Workload | Oct 27 median (range) | Oct 28 median (range) | Interpretation |
|---|---:|---:|---|
| 20,000-row variable-height scroll, 120 frames | 2.986 ms/frame (2.950–2.996) | 2.939 ms/frame (2.938–2.957) | Slightly lower median; ranges overlap |
| Wrapped-width reflow, 40 frames | 3.244 ms/frame (3.216–3.409) | 3.307 ms/frame (3.299–3.382) | Slightly higher median; ranges overlap |
| Direct solid-quad expansion | 8.338 ns/surface (8.055–9.617) | 8.801 ns/surface (8.277–10.420) | Ranges overlap; no material change established |
| Flat-material expansion | 8.318 ns/surface (7.950–10.073) | 8.661 ns/surface (8.264–8.947) | Ranges overlap; no material change established |

Text workload counters matched the previous run: 246 shape calls and 3,460
layout visits for variable-height scrolling; 362 shape calls and 924 layout
visits for wrapped reflow. Material output checksums matched, capacities were
unchanged, and every vertex-budget case passed at all four tested scales.

## Conclusion and limits

On this Windows machine, the optimized retained-work medians improved in the
final rerun, most visibly for changed root reconciliation, localized region
work, and retained-subtree reuse. Idle behavior and the million-item list
remain effectively unchanged. Text and material measurements moved slightly
in both directions within overlapping ranges. Since the source did not change
from the comparison revision and only three fresh processes were measured,
these results record repeatability and machine variation rather than a new
performance enhancement.

This is headless CPU benchmark evidence. It does not measure native startup,
interactive frame latency, process RSS, GPU residency, long-term memory
retention, or macOS performance. See the October 27 audit for the separate
release-size and initial-buffer experiments. A macOS rerun remains separate
validation to be performed on that host.
