# Issue #157: current construction hot-path audit

Audit date: 2026-11-04. Current source: `fe8967f08fed8b29e7cd27d5989f52b7a85f405c`; historical comparison: `96461223cdbf43080acb957276c045ad704f4606`. This was a read-only source/history review of already-recorded local benchmark and profiler artifacts. No tests or benchmarks were run and no production, benchmark, or existing documentation files were changed.

## Finding

The construction slowdown is repeatable, but current evidence does not identify one exclusive CPU culprit. Most of the added CPU time is in `end_frame`; the current profile points to several interacting costs: reconciliation and allocator/map traffic, layout and measurement, geometry finalization, paint composition, and diagnostic formatting. The strongest avoidable-work hypothesis is the eagerly formatted invalidation trace emitted during per-node construction. Retained measurement and finalized geometry also add real per-node work, but are feature contracts whose individual costs have not been separated.

## Direct benchmark and profile evidence

The construction probe uses the same November Odin compiler (`dev-2026-11-nightly:9a69916`) for both revisions and five fresh-process samples per revision/profile. Values below are process-CPU medians in milliseconds; ranges are in `out/issue157/final-default/results.json` and `out/issue157/final-speed/results.json` (local generated artifacts).

| Workload | Default total, baseline → current | Default `end_frame` | `-o:speed` total, baseline → current | `-o:speed` `end_frame` |
| --- | ---: | ---: | ---: | ---: |
| 10k containers | 68.1 → 160.7 | 44.9 → 133.8 | 23.7 → 49.8 | 16.3 → 40.3 |
| 10k short text | 75.6 → 193.1 | 54.0 → 165.9 | 28.2 → 65.5 | 21.0 → 54.6 |
| 10k wrapped text | 94.1 → 203.2 | 71.9 → 175.4 | 36.5 → 68.6 | 29.2 → 57.9 |
| 100 panels | 4.0 → 15.3 | 3.1 → 13.8 | 1.5 → 4.2 | 1.1 → 3.7 |

`end_frame` is roughly 83–91% of current total CPU across these cases; description CPU rises by a smaller amount. The default short-text samples have a wide range, so the optimized profile and the repeated direction across workloads are more useful than any single ratio.

The five-second macOS `/usr/bin/sample` capture in `out/issue157/current-speed-cpu-sample.txt` shows frequent main-thread samples in `runtime::heap_allocator_proc`, `alicorn::reconcile`, `alicorn::layout_children` / `layout_measure_node`, `fmt::sbprintf`, `update_paint`, `layout_finalize_node_geometry_for_node`, `layout_finalize_rect`, and `resolve_main_sizes`. These are sampled stack buckets, not exclusive CPU percentages; they establish breadth, not a ranking by precise cost. The text workloads in `benchmarks/diagnostics/construction_cpu_probe.odin` use `new_runtime` without loading a font, so they do not measure native font loading or real application shaping/startup.

Two matched historical parent/commit pairs help narrow the source intervals, but neither isolates a single function:

| Git interval | Optimized 10k containers | Optimized 10k short text | Source boundary |
| --- | ---: | ---: | --- |
| `927e74a55e3d819c087e42d66f9324cff783dc16` → `ac0a420c17f1c83ef283fee38da2a37fe4bfaedd` | 27.283 → 32.655 ms | 33.359 → 46.204 ms | `ac0a420` adds retained leaf measurement, per-node `Measure_State`, finalized geometry, and the unsnapped/finalized display contract. The pair measures their combined cost, not measurement versus geometry separately. |
| `7e856892f16846ab2dbb15628d7c670db87efd33` → `3d1086318710969b2193c3047c3fa2d047396a72` | 38.012 → 49.087 ms | 52.400 → 63.179 ms | `3d10863` changes axis-aware layout invalidation and trace reasons, among other layout/style contract changes. This is an interval signal, not proof that its trace changes caused the delta. |

The historical pair values are from `out/issue157/history-pairs-speed/results.json`, five samples per side.

## Source-based attribution and safe candidates

1. **Eager invalidation diagnostics are the clearest avoidable candidate.** On every new node, `reconcile` calls `mark_layout_ancestors(rt, d.id)` (`runtime/reconcile.odin:886–896`). The current `mark_layout_ancestors` formats axis and ancestor explanations with `fmt.tprintf` while walking (`runtime/reconcile.odin:676–709`). Each `record_trace_with_cause` then copies the reason into the persistent allocator before replacing the bounded-ring slot (`runtime/runtime_state.odin:9–18`); a bounded ring therefore bounds retained entries, not per-event formatting/allocation. This fits the profile’s `fmt::sbprintf`, `fmt_bit_set`, allocator, and `mark_layout_ancestors` samples, but no profile stack proves those samples all come from this call site. A same-head allocation-only experiment replacing eligible immutable trace strings with `record_trace_literal` reduced `end_frame` allocation calls by 20,002 and requested bytes by about 530 KB for 10k containers; timing ranges overlapped, so it demonstrated less allocation churn, not a CPU win (`out/issue157/trace-experiments-alloc-fixed/results.json`). A behavior-preserving follow-up must retain trace event order and equivalent readable reasons—for example, inline/structured trace payloads formatted when inspected—not silently drop or gate events.

2. **Per-node measurement and geometry storage are measured costs, not yet safe to remove.** New nodes initialize `rt.measure_states` in `reconcile` (`runtime/reconcile.odin:886–890`); `layout_measure_node` performs cache-key/content-signature work and writes the state (`runtime/layout_measure.odin:584–604`); layout stores finalized bounds, hit bounds, and clips in `rt.finalized_geometry` (`runtime/layout_measure.odin:809–829`). The profile contains corresponding map-set and geometry-finalization samples. Compacting or co-locating these records may be worth an isolated experiment, but it must preserve measurement dependencies, retirement, pixel snapping, hit testing, and semantic bounds. The present evidence does not establish whether inline storage, map reservation, or another representation improves CPU time overall.

3. **Do not attribute this cold-build case to the fixed retained-locality regression.** `layout_measure_retained_dirty_nodes` scans all `rt.order` only after a font-generation change (`runtime/layout_measure.odin:725–741`); this probe creates an unloaded text engine and does not change its font generation. The current adaptive semantic sync visits pending descriptions rather than refreshing every retained node’s order (`runtime/adaptive.odin:428+`). The `cc88bfde3271f0f558894b5be1acdeb5ed8a64d5` locality repair and `b5455318605b23a19988f45e39641cc74477f5da` queue guard target reused/dirty work; a fresh 10k tree still must reconcile nodes, lay out children, and produce initial paint/geometry.

## Disposition

CPU attribution is now narrowed to source-backed candidates, but no behavior-preserving change has yet shown a reliable construction CPU improvement. Keep #157 open for a controlled CPU A/B of the invalidation trace path and a separate representation experiment for per-node measurement/geometry state. Treat the current 10k probe as synthetic evidence only; it does not settle real Scratchpad startup or construction-memory high-water behavior.
