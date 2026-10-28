# Windows performance audit — 2026-10-27

This is an author-run performance audit on one Windows machine. It records a
small runtime optimization and experiments that were measured but not adopted.
It is not a cross-framework comparison or a performance guarantee.

## Environment

| Item | Value |
|---|---|
| OS | Windows 10 Home 22H2, build 19045.6466 |
| CPU | AMD Ryzen 5 7600X, 12 logical processors |
| GPU | NVIDIA GeForce RTX 2080 SUPER |
| Memory | 16 GiB installed |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Native host | SDL 3.4.2, Direct3D 12 |
| Baseline source | `550e0c230a4a5cff235205983f077d6b1368cc6f` |

## Retained runtime: matched baseline and candidate

The baseline executable was built from an archive of the exact baseline
revision. The candidate used the same source plus the semantic-focus and
collection-pruning changes recorded with this report. Both were built with
Odin `-o:speed` and run in five fresh processes each, alternating baseline and
candidate order. The benchmark is headless; each timing is a measured phase
inside the retained-work suite, not startup or native frame latency.

| Workload | Baseline median (range) | Candidate median (range) | Median change |
|---|---:|---:|---:|
| 10,000-node unchanged root invalidation | 18.074 ms (17.233–21.494) | 16.972 ms (16.226–21.134) | −6.1% |
| 10,000-node root invalidation, one value changed | 20.058 ms (16.682–23.289) | 16.393 ms (15.824–23.803) | −18.3% |
| 100-node region changed | 2.480 ms (2.300–4.330) | 2.209 ms (2.176–2.274) | −10.9% |
| Reuse a retained 10,000-node subtree | 2.644 ms (2.377–3.102) | 2.519 ms (2.385–2.710) | −4.7% |
| 1,000,000-item virtual list, 100 frames | 8.452 ms (8.352–10.626) | 8.385 ms (8.318–8.803) | Effectively unchanged |

The largest deterministic improvement is work reduction in
`refresh_semantic_focus_realization`. Before this change, each no-focus refresh
visited every retained node just to clear a flag that was already false. A
10,001-node tree therefore recorded 20,002 `semantic_active_update_visits`
across the two refreshes of one reconciliation. The candidate visits zero
nodes when there is no realized semantic focus and at most the previous and
next realized nodes when realization changes. Existing focus tests verify
that the old active presentation is cleared and that a stable focus remains
correct.

`semantic_prune_touched_collections` also now skips its entity scan when no
collection was touched and no removed collection needs orphan cleanup. A
removed collection schedules one cleanup pass; a regression test verifies
that orphaned virtual items are still removed. The retained timing table does
not isolate this optimization, so no wall-time gain is attributed to it.

The timing ranges overlap, and the one-value-change case has a noisy candidate
outlier. Treat the median reductions as encouraging same-machine evidence,
not as a guaranteed latency improvement. The virtual-list result is unchanged
within measurement noise.

## Other documented headless benchmarks

Three fresh processes were run with each documented script after the changes.

| Workload | Median | Range | Stable work counters |
|---|---:|---:|---|
| 20,000-row variable-height scroll, 120 frames | 2.986 ms/frame | 2.950–2.996 | 246 shape calls; 0 shape-cache hits; 3,460 layout visits; 15 retained nodes |
| Wrapped-width reflow, 40 frames | 3.244 ms/frame | 3.216–3.409 | 362 shape calls; 0 shape-cache hits; 924 layout visits; 13 retained nodes |
| Direct solid quad expansion | 8.338 ns/surface | 8.055–9.617 | 4,096 surfaces × 80 iterations; output checksums match |
| Flat material expansion | 8.318 ns/surface | 7.950–10.073 | Same vertices and capacity as direct path |

The material-path distributions overlap; there is no measured reason to
change the flat material implementation. The text benchmark counters differ
from the older October 3 capture, so this report does not attribute a timing
change to that historical baseline.

## Release build and GPU buffer experiments

Seven native `01_hello` runs per profile compared Odin `-o:speed` with
`-o:size`. The size profile reduced the executable from 6,586,368 bytes to
6,180,864 bytes (405,504 bytes, or 6.2%). With the same 2,790,400-byte SDL3
DLL, the measured first-frame medians favored `-o:speed`:

| First-frame metric | `-o:speed` median | `-o:size` median | `-o:size` change |
|---|---:|---:|---:|
| Frame p95 | 3.410 ms | 3.592 ms | +5.3% |
| Application build max | 2.436 ms | 2.961 ms | +21.5% |
| GPU encode | 2.668 ms | 2.915 ms | +9.2% |

The frame-p95 ranges overlap, but application-build samples separated in
these runs. The project should keep `-o:speed` as its release default unless
a future representative workload supports a different tradeoff.

A temporary 8,192-vertex initial-capacity build launched and rendered the
`01_hello`, `02_form`, and `05_inspector` examples. This is only a smoke test;
it does not establish that text-heavy Scratchpad frames avoid GPU-buffer
growth. The source defaults remain unchanged. At 36 bytes per vertex, changing
both text and solid renderer capacities from 65,536 to 8,192 would lower the
four vertex/upload buffer allocations from 9 MiB to 1.125 MiB of requested
capacity, before the separate 4 MiB atlas transfer buffer. Whether that
reduces actual resident memory or harms first-frame latency depends on the
application and graphics driver. Measure Scratchpad and a larger gallery
before adopting this tradeoff.

## Checks and limitations

- `tools/bench.ps1`: three candidate runs; all completed successfully.
- `tools/bench_text_layout.ps1`: three candidate runs; all completed
  successfully.
- `tools/bench_material.ps1`: three candidate runs and all material-budget
  cases at scales 1, 1.25, 1.5, and 2 passed.
- `odin test runtime`: 255 tests passed.
- `git diff --check`: passed.
- Native package/profile and 8,192-capacity runs were short Windows smoke
  captures, not prolonged interactive or Scratchpad stress sessions.
- No current high-water-memory comparison was made. A process working set is
  not a direct measure of GPU residency or leaked allocations.
- The measurements are specific to this Windows 10 / Ryzen 5 7600X / RTX
  2080 SUPER machine and Odin revision. Repeat on macOS and on a representative
  Scratchpad workload before drawing platform-wide conclusions.

[Raw retained-suite, text-layout, material, profile, and capacity captures](raw/performance-audit-windows-2026-10-27.txt)
are committed beside this report.
