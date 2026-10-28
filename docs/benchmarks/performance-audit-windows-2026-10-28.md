# Windows runtime performance audit — 2026-10-28

This audit investigates the unchanged-root and initial-construction costs in
the retained-work benchmarks. It records measured changes and remaining work;
it is not a cross-platform guarantee or a native frame-latency measurement.

## Environment and method

| Item | Value |
| --- | --- |
| OS | Windows 10 Home 22H2, build 19045 |
| CPU | AMD Ryzen 5 7600X, 12 logical processors |
| GPU | NVIDIA GeForce RTX 2080 SUPER |
| Memory | 16 GiB installed |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Candidate | `0ebff430ba89` (hash and style-environment duplicate-work reductions) |

The measurements use the repository's headless retained-work benchmarks. The
dirty-reason comparison used three alternating fresh-process samples of
`3e31c74` and `b545531` in each profile. A second five-sample comparison
checked the later hash/style changes (`9f4a985` versus `0ebff43`); each revision
was also run in duplicate buckets to expose same-build timing spread. No
native-host profiler was attached. Historical and current allocation counters
come from the retained-work fixture, not RSS or peak heap measurements.

| Profile | Workload | `9f4a985` median (range) | `0ebff43` median (range) |
| --- | --- | ---: | ---: |
| Default | Initial 10k tree | 132.728 ms (129.969–136.140) | 137.698 ms (131.747–141.662) |
| Default | Unchanged 10k root | 30.287 ms (29.746–33.287) | 30.984 ms (30.619–33.439) |
| `-o:speed` | Initial 10k tree | 65.294 ms (57.686–66.641) | 65.098 ms (63.533–66.152) |
| `-o:speed` | Unchanged 10k root | 16.154 ms (14.750–19.221) | 14.472 ms (13.580–18.538) |

The ranges overlap. The small median movements vary by profile and do not
establish a latency improvement from the hash/style changes. Matched raw logs
and machine-readable summaries: [default text](raw/performance-audit-windows-2026-10-28-locality-default.txt),
[default JSON](raw/performance-audit-windows-2026-10-28-locality-default.json),
[`-o:speed` text](raw/performance-audit-windows-2026-10-28-locality-speed.txt),
and [`-o:speed` JSON](raw/performance-audit-windows-2026-10-28-locality-speed.json).

## Unchanged-root optimization

`mark_dirty` previously replaced the owned diagnostic reason even when an
unchanged description left an already-clean node clean. It now updates that
reason only when the description creates new dirty work, and avoids replacing
an identical reason. The dirty flags, trace behavior, and reason for actual
changes remain intact. A changed → unchanged → changed regression test checks
that a meaningful cause is retained.

| Profile | Revision | Unchanged 10k root median | Allocations | Cumulative allocation bytes |
| --- | --- | ---: | ---: | ---: |
| Default | `3e31c74` | 37.397 ms | 10,023 | 1,532,352 |
| Default | `b545531` | 30.899 ms | 22 | 1,352,334 |
| `-o:speed` | `3e31c74` | 19.424 ms | 10,023 | 1,532,352 |
| `-o:speed` | `b545531` | 14.731 ms | 22 | 1,352,334 |

The three-sample medians improved by 17% and 24%, respectively. This is useful
same-machine evidence, while the small sample count still limits confidence in
the precise latency percentage. The allocation reduction is deterministic:
the no-op path no longer creates one reason string per retained node. Full raw
captures: [default](raw/performance-audit-windows-2026-10-28-dirty-reason-default.txt)
and [`-o:speed`](raw/performance-audit-windows-2026-10-28-dirty-reason-speed.txt).

## Initial construction and attribution

New nodes are still marked measure-dirty, but are no longer inserted into the
pre-layout remeasurement queue until a valid prior constraint key exists.
Their first measurement remains part of parent layout. The initial 10k fixture
therefore examines zero entries in the premature queue while still executing
10,000 required measurements and 20,001 layout visits. Runtime tests cover
later constraint availability and insertion paths.

This change removes redundant queue work; it does not solve the initial-build
latency regression. One full current-candidate run measured 132.606 ms, 130,183
allocation calls, and 111,649,298 cumulatively requested bytes for initial
construction. The earlier Windows locality comparison measured roughly
2.5× the `9646122` baseline in the default profile and 2× with `-o:speed`.
The newer five-sample comparison shows that the hash/style deduplication did
not produce a robust additional timing change: its median differences were
inside the same-revision run-to-run spread.

An opt-in `--allocation-attribution` diagnostic aggregates allocator calls by
source location and phase for the 10k short-text fixture. It observed:

| Phase | Calls | Cumulative requested bytes |
| --- | ---: | ---: |
| Runtime initialization | 11 | 40,188 |
| Description emission | 46 | 55,310,156 |
| Reconciliation/layout/paint | 130,137 | 56,339,142 |

The largest individual sites were growth of the pending-description storage
(12 requests totaling 41.7 MB across superseded backing buffers), 10,001
retained `Node` allocations (20.5 MB), and 10,000 first paint-command storage
allocations (10.2 MB). These are cumulative allocation requests, not retained
memory or RSS. The fixture's source-location attribution is diagnostic and
adds overhead; it is not used for timing claims. The raw output is
[preserved here](raw/performance-audit-windows-2026-10-28-allocation-sites.txt).

The evidence does not justify skipping retained semantics or paint setup, nor
does it identify a safe complete-description fast path. A future construction
optimization should first compare plain containers, short text leaves, and
wrapped text on representative application startup workloads. In particular,
the first text measurement and final geometry assignment are distinct required
passes; removing one wholesale would violate layout ordering.

## Current full-suite sample

One full current-candidate `tools/bench.ps1` run produced:

| Workload | Result | Work counters |
| --- | ---: | --- |
| 10k-node unchanged root | 30.424 ms | 22 allocations; 0 layout/paint/composition visits |
| 10k-node initial tree | 132.606 ms | 130,183 allocations; 111.65 MB cumulative requests; 0 queue examinations; 10,000 measurements |
| 10k-node true idle, 10k frames | 25.9 µs total | 0 allocations, 0 retained work, 0 GPU submissions |
| Reuse 10k-node region on unrelated wake | 56.4 µs | 3 reconciled; 0 measurement; one display command finalized |
| Change one 100-node region | 738.4 µs | 99 subtree items reused; 101 paint visits |
| 1M-item virtual list, 100 frames | 27.57 ms | 23 retained nodes |
| 1,200 custom-surface updates | 5.94 ms | 0 ordinary UI work and 0 allocations |

The complete output is in
[the full-suite raw capture](raw/performance-audit-windows-2026-10-28-full.txt).
The one-run values are a current-machine snapshot, not medians.

The text-layout and material suites passed. Variable-height scrolling measured
3.092 ms/frame (246 shape calls, 3,460 layout visits, 15 retained nodes);
wrapped-width reflow measured 3.475 ms/frame (362 shape calls, 924 layout
visits, 13 retained nodes). Direct-quad and flat-material expansion both
passed output and vertex-budget checks; three direct samples were 8.11–9.53
ns/surface and flat samples 7.92–8.09 ns/surface, too close to claim a material
speedup. See the raw full-suite captures and the existing material report.

## Validation run

- `odin test runtime`: 266 tests passed.
- `odin build benchmarks -out:out\\alicorn_benchmarks.exe`: passed.
- `out\\alicorn_benchmarks.exe --allocation-attribution`: completed; 45 source
  sites, no site overflow.
- `tools/bench.ps1`: completed; full output preserved.
- `tools/bench_text_layout.ps1`: completed successfully.
- `tools/bench_material.ps1`: completed; checksums and vertex budgets passed.
- `python tools/bench_retained_locality.py ... --runs 3`: default and
  `-o:speed` matched comparisons passed.
- Five-sample `9f4a985`/`0ebff43` matched comparisons passed in both profiles.
- `python -m py_compile tools\\bench_retained_locality.py`: passed.
- `git diff --check`: passed before final report edits; rerun before commit.

The standard benchmark, text-layout, material, and locality tools are headless.
This audit did not measure current native startup, process high-water memory,
GPU residency, or a Scratchpad editing session. No macOS benchmark was run on
this Windows machine; use the saved report as the Windows side of the next
cross-platform comparison.

## Conclusion

The unchanged-root path now avoids essentially all per-node diagnostic-string
allocation and is measurably faster in the three-sample comparison. The
pre-layout measurement queue also stops examining new nodes whose constraints
are not yet available. The initial 10k construction regression remains: the
allocation attribution points to pending-array growth and expected per-node
retained storage, but does not yet prove which change accounts for the
historical delta. Keep `-o:speed`; do not trade correctness or retained
behavior for an unverified fast path. The next useful step is representative
text/container allocation comparison and a Scratchpad high-water run, not a
broader reconciliation rewrite.
