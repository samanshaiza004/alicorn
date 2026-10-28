# Retained layout v0.2 acceptance audit

Baseline: `22e8c23` (master), Windows, 2026-10-23. This audits #24 and the
implemented portion of #27. PASS means the named regression ran successfully;
it does not claim support for the deferred strategies below.

## Acceptance evidence

Regression names below are in the linked file. Existing coverage is retained;
this change adds the boundary matrix/replay fixture and corrects trace provenance.

| #24 criterion | Implementation | Regression evidence | Result |
|---|---|---|---|
| Width-dependent text height | [layout_measure.odin](../../../runtime/layout_measure.odin): `layout_measure_node`; Runa shaping through `prepare_text_run_node` | [layout_measure_test.odin](../../../runtime/layout_measure_test.odin): `test_content_height_row_uses_allocated_width_for_wrapped_children_and_tracks_resize`; [layout_grid_test.odin](../../../runtime/layout_grid_test.odin): `test_grid_resolves_width_before_wrapped_row_height_and_rtl_start` | PASS |
| Deterministic fixed/min/max sizing | [layout_allocate.odin](../../../runtime/layout_allocate.odin): `layout_allocate_axis`; inward maxima/outward minima in `layout_axis_constraint_normalize` | [layout_allocate_test.odin](../../../runtime/layout_allocate_test.odin): weighted expansion/compression, maxima redistribution, overflow, invalid constraints, aggregate extent and randomized invariants | PASS |
| Typed, populated measurement dependencies | [runtime.odin](../../../runtime/runtime.odin): `Measure_Dependencies`; `layout_measure_dependencies` | [layout_measure_test.odin](../../../runtime/layout_measure_test.odin): scoped text scale, density and font-generation cases | PASS (#75 / merged #85) |
| Dependency changes invalidate; paint-only changes do not | Metrics and typography generations from style resolution; font generation from Text_Engine; exact constraints and local input/content revisions in `Measure_Cache_Key` | Same file: `test_measure_cache_miss_with_equal_result_does_not_relayout_ancestors`, scoped text scale, density, font generation, writing direction and scale-finalization tests | PASS |
| Unrelated retained subtrees do not remeasure | `layout_measure_retained_dirty_nodes`, retained cache keys, queued local layout roots | Same file: `test_scoped_text_measure_reflows_inside_explicit_layout_boundary`; [layout_conformance_test.odin](../../../runtime/layout_conformance_test.odin): `test_width_boundary_wrapped_reflow_matches_fresh_runtime_and_stays_local`; Grid locality test | PASS |
| Horizontal, vertical and full boundary behavior | [reconcile.odin](../../../runtime/reconcile.odin): `mark_layout_ancestors`; `layout_boundary_stable_axes` | [layout_conformance_test.odin](../../../runtime/layout_conformance_test.odin): `test_layout_boundary_axis_conformance_matrix` (15 combinations, including partial containment of a two-axis change) | PASS |
| Fixed-width/content-height reflow escapes vertically | Input-axis dependencies and separate `Parent_Size_Dependencies`; content-height remeasurement | Same file: nested wrapped-text replay plus existing `test_axis_scoped_layout_boundary_allows_fit_content_height_to_escape` | PASS |
| Incremental result equals fresh Runtime | Retained measurement and canonical layout/finalization products | Same file: five mutations of width, text scale and content, comparing keyed identities, targets, snapped bounds/clips, measurement results and exact constraints at 125% presentation scale. Existing randomized Row/Column and Grid replay tests remain | PASS |
| Content sizing is a policy on shared measurement | `layout_measure_content_height` for Row/Column and Scroll_Region | [layout_measure_test.odin](../../../runtime/layout_measure_test.odin): empty Row, ordinary Row stretch, mixed fixed/content children, Row in Column, Column in Row, min/max and content-sized virtual scroll tests | PASS (#5 / #76) |
| Shared preferred-size/allocation semantics | [layout.odin](../../../runtime/layout.odin): `resolve_main_sizes`, Split allocation; [layout_grid.odin](../../../runtime/layout_grid.odin): track allocation | [layout_allocation_integration_test.odin](../../../runtime/layout_allocation_integration_test.odin), [layout_flow_test.odin](../../../runtime/layout_flow_test.odin), [layout_grid_test.odin](../../../runtime/layout_grid_test.odin) | PASS (#25 / #26) |
| Fixed-row virtualization stays bounded | [virtual_list.odin](../../../runtime/virtual_list.odin): visible-range emission | [semantic_virtualization_test.odin](../../../runtime/semantic_virtualization_test.odin): million-item bounded collection; Grid virtual-cell and content-sized scroll tests; retained benchmark retains 23 nodes for one million items | PASS |
| Representative baseline metadata | `Measure_Result.baseline`; Row and Grid baseline placement | [layout_flow_test.odin](../../../runtime/layout_flow_test.odin): mixed-size text/button/icon Row; [layout_grid_test.odin](../../../runtime/layout_grid_test.odin): UI/Monospace Grid; outer-top multiline baseline regression | PASS |
| RTL logical Start/End | `layout_effective_writing_direction`; Row/Column, Grid and Split placement | Flow logical order/remainders, Grid Start/End, Split RTL and measurement-vs-placement direction tests | PASS for logical placement |
| Remeasurement and propagation are explainable | `measure_cache_reason`, `layout_measure_propagate_parent_size_change`, `mark_layout_ancestors`; existing inspector Causes tab | New exact height/minimum/two-axis reason test and full typography → measured height → parent dependency → vertical propagation → fixed ancestor trace assertions | PASS after diagnostic correction |
| Existing allocation is unchanged unless opted in | Ordinary `-1` allocation remains separate from `LAYOUT_SIZE_FIT_CONTENT`; no allocator/placement changes in this PR | Full foundation suite, ordinary Row stretch regression, randomized replay, native compositor validation; all benchmark non-timing fields unchanged | PASS |
| Bounded phases; no hidden layout history | One deterministic axis allocator; Grid staged solve; two-branch adaptive selection from assigned width | Flow/Grid deterministic and randomized tests; [adaptive_test.odin](../../../runtime/adaptive_test.odin): assigned-width selection, hidden interaction/semantics, nested selection/focus, unchanged selection and clean replay | PASS |
| Canonical units and device finalization | `Layout_Unit` is i64-backed at 1/1024 logical units for measurement/allocation; public styles/Rects remain f32. Absolute edges finalize separately | Quantization/conservative maxima, shared absolute-edge snapping, scale-only semantic bounds and unsnapped Split drag tests; fractional-DPI replay | PASS; not a frozen numeric ABI |
| Zero-work idle | `begin_frame` skip and presentation scheduling | New reflow fixture's settled-frame assertion; semantic idle, adaptive idle and foundation retained-work tests | PASS |

## Boundary matrix and limits

| Declared boundary | Width change | Height change | Both axes |
|---|---|---|---|
| Fixed width/height, both axes contained | Stop locally | Stop locally | Stop locally |
| Fixed width/height, Width only | Stop locally | Escape | Width stops, height escapes |
| Fixed width/height, Height only | Escape | Stop locally | Height stops, width escapes |
| Fixed width/FIT_CONTENT height, Width only | Stop locally | Escape | Width stops, height escapes |
| Fixed width/FIT_CONTENT height, both requested | Stop locally | Escape | Width stops, height escapes |

The last case verifies that the content-dependent height cannot be declared
stable accidentally. Each transaction queues exactly one containing layout
root. The integration fixture separately proves real Runa reflow, cross-axis
dependencies, sibling movement, locality, fresh-runtime equivalence and idle.

FIT_CONTENT **width**, either alone or on both axes, is unsupported. No width
content-sizing implementation was added to fill matrix cells. Content-height
support is limited to the documented Row/Column Containers and Scroll_Region;
outer content-sized Grids remain unsupported. Boundary declarations are caller
promises about independently stable outer axes, not automatic containment of
arbitrary intrinsic relationships.

Locale-sensitive shaping and bidirectional paragraph layout are not implied by
RTL placement. Add dependencies when a supported shaping path consumes those
inputs. Physical DPI currently affects finalization, not intrinsic measurement.
Text scale affects metrics and typography, while density affects metrics.

Constraint interval certificates (including a reserved speculative field),
stable/balanced wrapping, hysteresis, generic anchor dependency graphs, docking,
layout animation and advanced virtual extent/scrollbar policies are deferred.
No certificate producer exists; exact canonical constraint keys are the fallback.
The already-present sparse variable-height list API is not a new deliverable of
this audit and does not establish those advanced policies.

## Checks and native evidence

All commands used Odin `dev-2026-09-nightly:a2fb372` in the isolated branch.

| Command | Result |
|---|---|
| `tools/check.ps1 -Odin <supported-sdk>` | PASS: all 14 examples, foundation executable, 241 runtime / 35 theme / 111 native tests, theme CLI/codegen, process restoration and native input contract |
| Focused conformance tests before correction | FAIL as intended: height-only constraints were called width changes; the child-to-parent trace edge was absent |
| Focused conformance tests after correction | PASS |
| `tools/bench.ps1` on baseline and candidate | PASS; raw logs below |
| `tools/bench_text_layout.ps1` on baseline and candidate | PASS; raw logs below |
| `tools/native_sdl_gpu.ps1 -SurfaceGeometryTest` | PASS |
| `tools/native_sdl_gpu.ps1 -SurfaceStress` | PASS on Direct3D12: 300 resize iterations, 1,203 submissions/retirements, 1,200 surface updates, max 3 frames in flight; zero ordinary descriptions/reconcile/layout/paint/composition visits |
| `tools/native_sdl_gpu.ps1 -InspectorOpen -Smoke -Diagnostics -CaptureAfter 0` | PASS on Direct3D12; diagnostics/capture emitted, 2 submissions/retirements, zero stabilization-cap hits |
| `git diff --check` | PASS |

Native runs use the SDK's shared SDL 3.4.2 and a 1x desktop. Fractional-DPI
finalization is tested headlessly at explicit scales. Physical cross-monitor
movement and native macOS execution were not performed on this Windows machine;
neither is claimed by these logs. This PR changes no native renderer or host API.

## Benchmark comparison

Single sequential runs on the same machine, baseline built before runtime edits.
Retained suite uses its documented default build; text-layout uses `-o:speed`.
All non-timing output fields match: allocations/bytes, stage work, shaping/cache
counts, retained counts and final geometry. Timing variation is observational,
not a claimed optimization or a statistical regression bound.

| Workload | Baseline ms | Candidate ms | Change |
|---|---:|---:|---:|
| 4,000 container-rich parent buckets | 186.1733 | 161.3909 | -13.31% |
| 1,200 retained surface updates | 4.7417 | 4.8058 | +1.35% |
| Million-item fixed list, 100 frames | 33.1567 | 26.9994 | -18.57% |
| Wrapped variable-height scroll, 120 frames | 360.2611 | 361.7270 | +0.41% |
| Wrapped width reflow, 40 frames | 135.2055 | 134.0381 | -0.86% |

Raw logs: [baseline retained](../../benchmarks/raw/layout-contract-windows-2026-10-23-baseline-retained.txt),
[candidate retained](../../benchmarks/raw/layout-contract-windows-2026-10-23-candidate-retained.txt),
[baseline text](../../benchmarks/raw/layout-contract-windows-2026-10-23-baseline-text-layout.txt),
[candidate text](../../benchmarks/raw/layout-contract-windows-2026-10-23-candidate-text-layout.txt).

## Tracker disposition

Recommend closing #24 when this acceptance PR is reviewed and merged, for the
supported v0.2 contract above. The new fixtures found no target-geometry or
locality failure; runtime edits correct only missing/misleading provenance.
Close #75 against its merged #85 implementation and independently passing input
domain regressions. Keep #27 open as a long-term architecture tracker, distinguish
adaptive v1 and shared measurement/allocation from its deferred research, and
remove #27 from the v0.2 milestone once #24 is accepted.
