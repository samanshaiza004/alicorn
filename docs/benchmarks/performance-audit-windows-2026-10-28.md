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
| Candidate | `3d2c89e55ba3f34a2fb741926521f482ee57a17e` (current audited master) |

The measurements use the repository's headless retained-work benchmarks. The
dirty-reason comparison used three alternating fresh-process samples of
`3e31c74` and `b545531` in each profile. A five-sample comparison checked the
later hash/style changes (`9f4a985` versus exact current head `3d2c89e`); each
revision was also run in duplicate buckets to expose same-build timing spread.
A separate five-sample construction probe compared flat containers, short
text, wrapped text, and an exact pending-array reserve. No native-host profiler
was attached. Historical and current allocation counters come from the
retained-work fixture, not RSS or peak heap measurements.

| Profile | Workload | `9f4a985` median (range) | `3d2c89e` median (range) |
| --- | --- | ---: | ---: |
| Default | Initial 10k tree | 128.677 ms (125.932–130.219) | 130.280 ms (128.044–133.397) |
| Default | Unchanged 10k root | 29.261 ms (28.999–37.392) | 30.751 ms (30.148–30.997) |
| `-o:speed` | Initial 10k tree | 56.744 ms (54.817–63.379) | 59.979 ms (56.019–74.212) |
| `-o:speed` | Unchanged 10k root | 14.484 ms (13.486–15.387) | 14.409 ms (13.512–17.195) |

The ranges overlap. These samples do not establish a latency improvement or
regression from the hash/style changes. Matched raw logs
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
latency regression. In the exact-head full-suite sample, initial construction
took 129.362 ms, with 130,183 allocation calls and 111,649,298 cumulatively
requested bytes. Compared with the older `9646122` benchmark, this remains
about 2.5× slower in the default profile and about 2× slower with `-o:speed`.
The five-sample comparison against `9f4a985` has overlapping ranges, so the
hash/style deduplication does not establish an additional timing change.

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
does it identify a safe complete-description fast path. The experiments below
separate likely costs without justifying a representation rewrite.

### Record-size and construction experiments

The record-size probe compared the old runtime and exact current source with
the same Odin compiler:

| Record | `9646122` | `3d2c89e` | Change |
| --- | ---: | ---: | ---: |
| `Pending_Item` | 720 B | 1,272 B | +552 B (+76.7%) |
| `Description` | 704 B | 768 B | +64 B (+9.1%) |
| `Node` | 1,792 B | 2,048 B | +256 B (+14.3%) |

The old `Display_Command` (96 B) and current `Paint_Command` (128 B) have
different contracts and are not a like-for-like size comparison. See the
[type-size capture](raw/performance-audit-windows-2026-10-28-type-sizes.txt).

Five fresh-process samples per mode compared the same 10,001-node flat tree:

| Workload | Total median (range) | Description median | `end_frame` median | Requested-live high-water |
| --- | ---: | ---: | ---: | ---: |
| Plain containers | 113.730 ms (112.332–119.438) | 19.366 ms | 94.364 ms | 57.06 MB |
| Short text leaves | 133.350 ms (132.116–148.461) | 18.635 ms | 114.212 ms | 70.88 MB |
| Short text, exact reserve | 133.585 ms (132.050–144.976) | 17.414 ms | 116.164 ms | 62.76 MB |
| Wrapped text leaves | 146.942 ms (143.820–153.820) | 19.762 ms | 126.536 ms | 72.61 MB |

Plain containers did no leaf measurement and composed only the root; text
workloads measured 10,000 leaves and composed all nodes. Every mode performed
20,001 layout visits. The wrapped-text median was higher, but the short and
wrapped ranges overlap. This synthetic probe used low-level text descriptions
with no semantic descriptions, so it does not measure semantic-publication
cost or predict application startup by itself.

Pre-reserving exactly 10,001 pending entries reduced cumulative requested
bytes from 112.06 MB to 83.11 MB (25.8%) and requested-live high-water by
8.12 MB. It kept pending capacity at 10,001 instead of geometric growth to
16,384. Median total time was effectively unchanged (133.350 ms without
reserve, 133.585 ms with it; ranges overlap). This supports avoiding repeated
growth when demand is already known, but does not justify unconditional
reservation in Alicorn. These requested-byte figures are not RSS or committed
memory measurements. The [probe source and instructions](../../benchmarks/diagnostics/README.md)
and [five-sample raw capture](raw/performance-audit-windows-2026-10-28-construction-probes.txt)
are preserved for follow-up.

## Current full-suite sample

One full `tools/bench.ps1` run from exact current head `3d2c89e` produced:

| Workload | Result | Work counters |
| --- | ---: | --- |
| 10k-node unchanged root | 33.263 ms | 22 allocations; 0 layout/paint/composition visits |
| 10k-node initial tree | 129.362 ms | 130,183 allocations; 111.65 MB cumulative requests; 0 queue examinations; 10,000 measurements |
| 10k-node true idle, 10k frames | 30.2 µs total | 0 allocations, 0 retained work, 0 GPU submissions |
| Reuse 10k-node region on unrelated wake | 56.4 µs | 3 reconciled; 0 measurement; one display command finalized |
| Change one 100-node region | 738.4 µs | 99 subtree items reused; 101 paint visits |
| 1M-item virtual list, 100 frames | 26.73 ms | 23 retained nodes |
| 1,200 custom-surface updates | 5.89 ms | 0 ordinary UI work and 0 allocations |

The complete output is in
[the exact-head full-suite raw capture](raw/performance-audit-windows-2026-10-28-master-3d2c89e.txt).
The one-run values are a current-machine snapshot, not medians.

The current text-layout run measured 2.896 ms/frame for variable-height
scrolling (246 shape calls, 3,460 layout visits, 15 retained nodes) and
3.362 ms/frame for wrapped-width reflow (362 shape calls, 924 layout visits,
13 retained nodes). These single runs are within ordinary timing variability
of the prior samples and do not establish a speedup. Direct-quad and
flat-material expansion passed output and vertex-budget checks. In the
three-sample CPU-only capture, direct quads measured 8.200–8.741 ns/surface
and flat materials 7.951–8.094 ns/surface, with identical output. This is a
small microbenchmark difference; it does not establish an end-to-end rendering
gain. The [current text and material capture](raw/performance-audit-windows-2026-10-28-text-material.txt)
contains the outputs.

## Validation run

- `odin test runtime`: 266 tests passed.
- `odin build benchmarks -out:out\\alicorn_benchmarks.exe`: passed.
- `out\\alicorn_benchmarks.exe --allocation-attribution`: completed; 45 source
  sites, no site overflow.
- `tools/bench.ps1`: completed; full output preserved.
- `tools/bench_text_layout.ps1`: completed successfully.
- `tools/bench_material.ps1`: completed; checksums and vertex budgets passed.
- Five-sample `9f4a985`/`3d2c89e` matched comparisons passed in default and
  `-o:speed` profiles.
- Five-sample construction probes completed for containers, short text,
  reserved short text, and wrapped text; record sizes were measured on both
  `9646122` and `3d2c89e`.
- `odin build benchmarks\diagnostics\perf_construction_probe.odin -file`:
  passed.
- `python -m py_compile tools\\bench_retained_locality.py`: passed.
- `git diff --check`: passed after the report and capture updates.

The standard benchmark, text-layout, material, and locality tools are headless.
This audit did not measure current native startup, process high-water memory,
GPU residency, or a Scratchpad editing session. No macOS benchmark was run on
this Windows machine; use the saved report as the Windows side of the next
cross-platform comparison.

## Conclusion

The unchanged-root path avoids essentially all per-node diagnostic-string
allocation and was faster in the earlier three-sample A/B. Exact-head
five-sample comparisons show no separate, reproducible timing effect from the
subsequent hash/style changes. The pre-layout queue no longer examines new
nodes whose constraints are unavailable. Initial 10k construction remains
slower than the historical baseline. Pending-array reserve lowers synthetic
requested allocation volume but not elapsed time, and the workload comparison
shows text measurement and composition add work over flat containers. No
runtime capacity or data-layout change is justified yet. Keep `-o:speed`; do
not trade correctness or retained behavior for an unverified fast path.
Current Scratchpad startup and high-water memory, native GPU residency, and
macOS measurements remain untested on this machine.
