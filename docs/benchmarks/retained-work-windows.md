# Retained-work benchmark: Windows

Captured 2026-10-03 on Alicorn `7c5e812`, Windows 10 Home 22H2
(10.0.19045.6466), AMD Ryzen 5 7600X / 12 logical processors. Odin was
`dev-2026-09-nightly:a2fb372`. This is the headless suite and uses the default
profile from `tools/bench.ps1` (no explicit optimization option); there is no
SDL host or GPU in this measurement.

From a fresh checkout with the documented Odin toolchain, run three fresh
processes:

```powershell
1..3 | ForEach-Object { .\tools\bench.ps1 }
```

The script builds `benchmarks/` and reports wall-clock nanoseconds plus
allocation, retained-node, reconciliation, layout, paint, and composition
counters. Results below are medians of three sequential processes, rounded to
the nearest 0.1 ms where useful. They are a point-in-time author-run baseline,
not a latency target.

| Workload | Median | Work counters / interpretation |
|---|---:|---|
| Initial 10,000-node tree | 53.4 ms | 10,001 retained nodes; 70.5 MB allocated by the benchmark allocator |
| Unchanged root invalidation, 10,000 nodes | 21.2 ms | 10,001 reconciled; one layout visit; zero paint visits/composites |
| True-idle headless loop, 10,000 frames | 25.9 µs total | Zero allocations and retained-stage visits; zero GPU submissions |
| 1,000,000 logical virtual items, 100 frames | 9.37 ms total | 23 retained nodes |
| 1,200 custom-surface updates | 4.79 ms total | Zero ordinary emit/reconcile/layout/paint/composition work or allocations; 2 retained nodes |

The idle fixture is an invariant/counter test in the headless runtime. Its
total time is too small to interpret as host CPU cost or wake behavior. The
native idle observation is measured separately in the
[Windows native-host report](native-dogfood-windows.md).

[Raw output from all three processes](raw/retained-work-windows-2026-10-03.txt)
is committed beside this report. It includes the other tree sizes, keyed
churn/reorder, regional invalidation, and typed-key allocation cases. The
matching [macOS retained-work report](retained-work-macos.md) is a separate
machine baseline; do not compare its timings as if the systems were identical.
