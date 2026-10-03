# Retained-work benchmark: macOS

Captured on 2026-10-02 CDT from Alicorn
`96461223cdbf43080acb957276c045ad704f4606`, on macOS 27.0 (26A428), MacBook
Air 10,1 / Apple M1 arm64, 8 logical CPUs, 8 GiB RAM. Odin was
`dev-2026-09-nightly:a2fb372`. The suite is headless and uses the build
profile selected by `tools/bench.sh` (no explicit `-o` option).

Run from the repository root:

```sh
./tools/bench.sh
```

The checked-in raw output below records a single run. It is useful as a
reproducible point-in-time baseline, not a distribution or latency target.
Timer results include benchmark fixture and runtime work, and do not include
SDL, GPU presentation, application startup, or OS scheduling.

## Selected results

| Workload | Observed result | What it demonstrates |
|---|---:|---|
| One initial 10,000-node tree | 86.198 ms | Full description/reconcile/layout/paint baseline for this fixture |
| 10,000-node unchanged root invalidation | 35.409 ms | Description/reconciliation still visits the emitted tree; no layout, paint, or composition work |
| 10,000-node one-value change | 35.817 ms | One paint visit and one composite in the fixture's work counters |
| 10,000-node full keyed reorder | 61.415 ms | Identity reuse under reorder; layout and paint revisit the reordered tree |
| 100-node unchanged region inside a 10,102-node app | 0.773 ms | 100 region bodies skipped on an unrelated root wake |
| 10,000-descendant region reused for sibling change | 0.356 ms | One region body call; the retained descendants are not enumerated for reuse |
| 1,000,000 logical virtual items over 100 frames | 17.501 ms total; 23 retained nodes | Logical size remains large while realized retained nodes stay viewport-bounded |
| 1,200 custom-surface updates | 8.299 ms total; zero ordinary stage visits/allocations | Surface-only updates remain local in the headless runtime path |
| Typed `u64` versus formatted-string keys, 10,000 items | 84.626 ms vs. 91.142 ms; 20,000 fewer allocations | One-run allocation/work comparison; not a cross-machine or statistical performance claim |

The `true_idle_10k_tree_10000_frames` fixture recorded zero retained-stage
work and zero GPU submissions across 10,000 idle frames. Its reported 59,000
ns total is below a useful per-frame timing scale and must not be interpreted
as active runtime cost or host wake behavior; this is a headless counter proof.

The suite also records 100/1,000-node cases, churn patterns, container-rich
frames, and complete stage/allocation counters. Those values are preserved
without selecting only the fastest cases in the raw output.

## Scope and remaining evidence

This Mac run complements the same focused wrapped-text workload measured on
Windows and macOS in the [text-layout report](text-layout.md). The Mac-only
[native hello sample](native-hello-macos.md) measures one idle host session,
RSS/process CPU observations, binary size, and qualified startup markers.
These results were produced by the project author and are not independent
validation or a cross-framework comparison.

There is not yet a matching Windows run of this retained-work suite, a Windows
native-hello idle/startup result, or fixed-fixture native measurements for
Monitor, History, and Scope. The v0.1.0 performance issue remains open until
those release-gate gaps are resolved or deliberately descoped.

[Raw Mac output](raw/retained-work-macos-m1-2026-10-02.txt) is committed
alongside this summary.
