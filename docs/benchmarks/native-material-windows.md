# Native material flat-path benchmark: Windows

This focused benchmark compares CPU vertex expansion for a direct solid quad
and the canonical flat material path. It does not create an SDL window, submit
GPU work, measure the native frame loop, or include display-list traversal.
Both cases reuse preallocated vertex storage and should emit identical output.
Use it as a same-machine regression check, not a cross-machine performance
claim.

Run from the repository root:

```powershell
.\tools\bench_material.ps1
```

The script builds `benchmarks/native_material` with `-o:speed` and executes
three samples per process. This capture was taken 2026-10-06 with three fresh
processes (nine samples total).

| Item | Environment |
|---|---|
| OS | Microsoft Windows 10.0.19045 |
| CPU identifier | AMD64 Family 25 Model 97, 12 logical processors |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Build profile | `-o:speed` |
| Workload | 4,096 surfaces × 80 iterations per sample; 24,576 vertices per batch |
| Renderer | CPU-only vertex expansion; no SDL/GPU submission |

Across the nine samples, the direct-quad median was 8.436 ns per surface and
the flat-material median was 8.503 ns per surface, a 0.8% difference. The
sample ranges overlap substantially: 8.297–9.518 ns and 8.225–9.306 ns,
respectively. Every sample emitted 24,576 vertices at an unchanged capacity,
and the output checksum matched between paths. The observed difference is
within this small microbenchmark's noise; it does not indicate a material
runtime cost or a measurable speedup.

[Raw Windows stdout for all nine samples](raw/native-material-windows-2026-10-06.txt)
is committed alongside this summary.
