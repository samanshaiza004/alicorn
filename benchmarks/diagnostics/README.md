# Construction diagnostics

This standalone headless probe separates flat container, short text, and
wrapped text construction. `short-reserve` pre-reserves exactly 10,001 pending
items for the synthetic short-text fixture. It is a diagnostic experiment;
runtime applications should not reserve this capacity unconditionally.

From the repository root, build and run one fresh process per workload:

```powershell
odin build benchmarks\diagnostics\perf_construction_probe.odin -file -out:out\perf_construction_probe.exe
out\perf_construction_probe.exe containers
out\perf_construction_probe.exe short
out\perf_construction_probe.exe short-reserve
out\perf_construction_probe.exe wrapped
```

The `memory_requested` values are the probe allocator's requested-live-byte
high-water mark, not process RSS, allocator overhead, or GPU residency. Work
counters accompany wall times to show which stages ran. The workload is a
synthetic flat root with 10,000 children and does not represent application
startup on its own.
