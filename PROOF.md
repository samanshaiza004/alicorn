# Retained-work avoidance gate

This is the proof report for the retained-work gate. It records mechanics and
measurements, not aspirations.

Starting SHA: `3a889d0308ed8b0fa3c61c1a288a315809cbcd15` (verified against
`origin/master` on 2026-09-14).

## Research findings

Xilem's `Memoize` is an explicit pruning boundary for a pure view subtree. The
outer reactive view may still be rebuilt, but the memoized subtree is not
constructed or rebuilt when its declared inputs are unchanged. Alicorn adopts
the pruning boundary, not Xilem's reactive application-state model: an Odin
application supplies an explicit region revision and Alicorn emits one
`Reuse_Subtree` marker.

GPUI tracks window dirtiness separately from a set of dirty retained view/entity
IDs. Invalidating an entity marks the window for work and inserts that entity
into the dirty frontier; retained identity and view-local state remain runtime
owned. Alicorn transfers the dirty-frontier/work-queue idea, not GPUI's entity
notification system or observer-driven application state.

Sources: [Xilem architecture and Memoize](https://github.com/linebender/xilem/blob/main/xilem/ARCHITECTURE.md),
[GPUI window invalidation](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/window.rs).

Rejected alternatives were: appending cloned cached descriptions (the old
representation, which was the gate failure), global generation/liveness scans
(which would retain a whole-tree walk), a persistent virtual-DOM/reactive graph
(which violates ordinary Odin state plus explicit invalidation), and hash-only
adjacency (which cannot express local retirement or explain visits).

## Claim: retained-subtree reuse is real

- Implementation: `Pending_Item{.Reuse_Subtree, subtree}` in
  `runtime/runtime.odin`; retained `Node.children` and `Runtime.top_level` are
  authoritative for a reused region.
- Test: `test_retained_subtree_reuse` in `tests/main.odin` preserves a focused
  descendant's Node_ID and local state, verifies no body reevaluation, changes
  parent constraints without description reevaluation, then removes the region
  and verifies full descendant retirement plus deterministic focus fallback.
- Benchmark: the large-region benchmark emits 3 direct descriptions when a
  10,000-descendant region is reused for an unrelated sibling change.
- Result: reuse does not copy or append cached descendant descriptions.
- Known limitations: the current display compositor still rebuilds its flat
  display list for structural order changes; reuse itself does not require
  that rebuild.
- Verdict: proven for explicit retained regions.

## Claim: small-region invalidation is local

- Implementation: reconciliation visits explicit pending descriptions and
  updates only direct child lists of explicitly described parents. Reuse markers
  skip descendant reconciliation. Paint uses a changed-node queue.
- Test: counters are asserted for subtree reuse; existing identity/stage tests
  remain green.
- Benchmark: the regional 10,102-node application has 100 regions of 100
  descendants. A one-region revision change emits/reconciles 202 descriptions
  (root, sibling, 100 changed-region descendants and region/frontier nodes),
  while 99 unchanged regions are represented by reuse markers.
- Result: description/reconciliation/paint work follows the changed region and
  necessary ancestors, not all 10,102 descendants.
- Known limitations: an explicit root wake with a flat non-region tree remains
  O(N), by contract. Layout may walk retained descendants when constraints
  change. Structural reorder rebuilds the flattened order and composition.
- Verdict: proven for the measured explicit-region model; broader arbitrary
  dependency inference is intentionally not provided.

## Claim: true idle is distinct from root wake

- Implementation: `begin_frame` returns without opening a frame when no explicit
  invalidation is pending.
- Benchmark: `true_idle_10k_tree_10000_frames` records zero emitted/reused
  descriptions, reconciliation visits, layout visits, paint visits,
  composition visits, adjacency rebuilds and GPU submissions across 10,000
  attempted frames.
- Verdict: proven for the headless scheduler path.

## Claim: typed keys remove the benchmark formatting artifact

- Implementation: `key_scope_u64` and `identity_hash_u64` consume numeric keys
  directly; string `key_scope` remains available and unchanged.
- Test: numeric keyed reorder preserves local state and inspector identity;
  duplicate numeric keys are a hard diagnostic.
- Benchmark: the formatted-string and typed-u64 10k initial paths are reported
  separately. The difference includes formatting/allocation and the remaining
  runtime effects; it is not presented as a pure allocator measurement.
- Verdict: proven as an allocation-free identity input path.

## Claim: identity remains stable under subtree skipping

- Implementation: reuse retains the existing child adjacency; retirement walks
  that adjacency rather than relying on descendants to be re-emitted.
- Test: existing 2,000-step keyed property sequence plus a 500-step retained
  region collection sequence covering keyed reorder, hide/show, revision
  changes, insertion, nested reuse, numeric-key reorder, focused-descendant
  reuse/removal and duplicate diagnostics.
- Verdict: proven for tested keyed and region structures; variable-height and
  offscreen virtualization identity remain outside this gate.

## Claim: allocation behavior is understood enough for this gate

- Implementation: the prior cloned `region_cache` was removed. The benchmark
  installs a benchmark-only allocator wrapper around Odin's current allocator
  and reports allocation calls and requested bytes per case. The retained
  reuse representation itself is one marker and has no per-descendant cache.
- Result: the 10,000-descendant reuse frame made 16 runtime allocation calls
  for 1,688 requested bytes, versus 100,176 calls and 25,582,032 bytes for its
  initial construction. The changed-region frame made 640 calls and 53,643
  bytes.
- Measurement limitation: the wrapper counts allocator requests and cumulative
  requested bytes, not a process-wide live heap profile; free sizes are not
  relied upon. It adds instrumentation overhead to benchmark timings.
- Verdict: reuse allocation behavior is proven bounded in this workload; total
  allocator behavior remains a scoped measurement.

## Benchmark taxonomy and raw results

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check.ps1
.\out\alicorn_benchmarks.exe
```

Environment: Windows host, Odin `dev-2026-09-nightly:a2fb372`, 2026-09-14.
Wall times are raw one-shot nanoseconds from `core:time`; no latency threshold
is used. Counters are per-row deltas unless noted.

| case | wall ns | emit | reuse | region skip | subtree reuse | reconcile | layout | paint visit | compose visit | adjacency | alloc | alloc bytes | created | retired | retained |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| true idle, 10k tree, 10k frames | 18,400 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 10,001 |
| 100 initial | 545,600 | 101 | 0 | 0 | 0 | 101 | 101 | 101 | 101 | 1 | 1,081 | 247,071 | 101 | 0 | 101 |
| 100 root wake unchanged | 134,100 | 101 | 101 | 0 | 0 | 101 | 1 | 0 | 0 | 0 | 123 | 23,252 | 0 | 0 | 101 |
| 1,000 initial | 2,730,100 | 1,001 | 0 | 0 | 0 | 1,001 | 1,001 | 1,001 | 1,001 | 1 | 10,114 | 2,166,075 | 1,001 | 0 | 1,001 |
| 1,000 root wake unchanged | 1,048,400 | 1,001 | 1,001 | 0 | 0 | 1,001 | 1 | 0 | 0 | 0 | 1,032 | 176,412 | 0 | 0 | 1,001 |
| 10,000 initial | 27,943,300 | 10,001 | 0 | 0 | 0 | 10,001 | 10,001 | 10,001 | 10,001 | 1 | 100,153 | 25,389,779 | 10,001 | 0 | 10,001 |
| 10,000 root wake unchanged | 10,614,500 | 10,001 | 10,001 | 0 | 0 | 10,001 | 1 | 0 | 0 | 0 | 10,042 | 1,559,788 | 0 | 0 | 10,001 |
| 10,000 root wake one value | 10,333,300 | 10,001 | 10,000 | 0 | 0 | 10,001 | 1 | 1 | 1 | 0 | 10,046 | 1,559,863 | 0 | 0 | 10,001 |
| 10,000 full keyed reorder | 12,724,000 | 10,001 | 10,000 | 0 | 0 | 10,001 | 1 | 1 | 10,001 | 1 | 10,046 | 1,559,883 | 0 | 0 | 10,001 |
| regional, unchanged root wake | 144,700 | 102 | 102 | 100 | 100 | 102 | 1 | 0 | 0 | 0 | 125 | 23,598 | 0 | 0 | 10,102 |
| regional, one 100-node region changed | 294,100 | 202 | 101 | 99 | 99 | 202 | 1 | 101 | 101 | 0 | 640 | 53,643 | 0 | 0 | 10,102 |
| large 10k region reused | 13,200 | 3 | 2 | 1 | 1 | 3 | 1 | 1 | 1 | 0 | 16 | 1,688 | 0 | 0 | 10,003 |

The regional initial build was `30,818,400 ns`, with 10,102 emitted,
reconciled, laid-out and painted nodes. The large-region initial build was
`32,224,400 ns`, with 10,003 retained nodes. The exact raw output is produced
by the benchmark executable; one-shot timings are illustrative, while the
visit-count locality is the primary evidence.

Structural churn on 10,000 keyed children measured swap, move-last-to-first,
reverse, 1% replacement, and 1,000 reorder-every-frame iterations. Reorders
created/retired zero nodes; each structural reorder rebuilt retained order and
the flat display composition. The 1% replacement created and retired 100 nodes.
Raw rows from this run were: swap `11,887,600 ns`, 10,001 reconciliation
visits, 10,001 composition visits, 1 adjacency rebuild; move
`12,075,900 ns` with the same counts; reverse `11,886,700 ns` with the same
counts; and 1% replacement `16,780,600 ns`, 10,001 reconciliation visits,
9,998 paint visits, 100 created and 100 retired. The 1,000-frame reorder loop
performed 1,000 adjacency rebuilds, 10,001,000 reconciliation visits, zero
creation/retirement, and retained 10,001 nodes. The benchmark prints all raw
counters and allocator requests.

Typed-key comparison from the same run:

```text
formatted_string_10k: 32,751,600 ns, 120,153 allocations, 25,508,687 bytes
typed_u64_10k:       27,950,500 ns, 100,153 allocations, 25,389,779 bytes
difference:           4,801,100 ns, 20,000 allocations, 118,908 bytes
```

The formatted path is a diagnostic comparison, not a claim that all of the
difference is string allocation.

## Existing regression evidence

`tools/check.ps1` builds and runs the foundation tests, benchmark executable,
identity torture executable, Crucible, and Runa text example. The headless
foundation tests pass after this gate. The fixed-height million-row benchmark
retains 23 nodes after 100 scroll frames (latest elapsed `6,512,000 ns`). The native SDL3/SDL_GPU fixture was
not redesigned; it must be rerun with the host's SDL3 DLL path after runtime
changes. Existing Windows and Apple Silicon macOS validation remains the
platform baseline, not new cross-platform proof from this gate.

## What was falsified or narrowed

- The old assumption that skipping a region body implied skipping retained
  subtree runtime work was false. Re-appending cached descendants was replaced
  by an explicit retained-subtree marker.
- “Unchanged” was not an idle benchmark. It was a forced root wake and is now
  named `root_invalidated_unchanged`.
- A full flat root wake remains proportional to the flat description size; the
  explicit-region contract is required for locality.
- Global flat composition is still necessary for structural order changes.
- Total process allocator bytes and native OS wakeups are not proven here.

## What was proven

The central retained-execution claim is proven for explicit retained regions:
an unrelated wake of a 10,000-descendant region emits a marker and visits no
descendant descriptions, while a one-region mutation in a 10k application
scales with the changed region and direct frontier. Identity, focus, layout
constraint crossing, deterministic retirement, typed keys and true-idle
short-circuiting remain intact in the current tests.

## Known limitations

No automatic domain mutation observation, variable-height virtualization,
offscreen selection, GPU glyph atlas, IME, semantic tree, reactive state graph,
or platform-idle telemetry was added. The native compositor remains rectangle
based and its structural composition path is conservative.

## Decision

`CONTINUE`

Retained work avoidance scales with changed explicit regions closely enough to
proceed to the real GPU text pipeline. The next task should begin with Runa
raster-to-glyph-atlas integration and must not silently broaden this gate.
