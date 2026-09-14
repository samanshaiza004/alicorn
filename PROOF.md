# Foundation proof report

This report is deliberately conservative. A claim is only marked proven when
the repository contains a repeatable test or measurement for it.

## Claim: procedural descriptions can reconcile into stable retained identity

- Implementation: `runtime/runtime.odin`, hierarchical FNV identity and
  explicit `key_scope`.
- Test: `tests/main.odin`, including insertion, deletion, reorder,
  filter, wrapper/conditional changes and deterministic randomized sequences.
- Benchmark: `benchmarks/main.odin` keyed reorder.
- Result: the test checks `logical_key -> retained state` after each operation.
- Known limitations: tests use explicit sites for deterministic fixtures;
  `caller_site` is available for Odin `#caller_location` source ingredients.
- Verdict: proven for the tested identity contract.

## Claim: explicit invalidation enables retained regions

- Implementation: `begin_frame`, `invalidate_root`, `region` and region
  description caches.
- Test: region reuse tests assert the body execution counter and stage counters.
- Result: unchanged regions are not reevaluated after an unrelated root wake-up.
- Known limitations: the application must provide truthful revisions; the
  runtime cannot detect arbitrary Odin memory mutation.
- Verdict: proven for explicit revisions.

## Claim: stage work is granular and inspectable

- Implementation: independent description/layout/paint/composite hashes,
  counters, inspector and trace ring.
- Test: changing one keyed meter changes that node's paint stage while sibling
  descriptions and layouts are reused.
- Verdict: partially proven; composition currently rebuilds conservatively.

## Claim: input and focus are deterministic

- Implementation: one `focused` Node_ID, retained hit testing and fallback.
- Test: focus through reorder, removal, filtering and representation changes.
- Verdict: proven by headless tests for the defined fallback policy.

## Claim: a million-row list has bounded retained state

- Implementation: fixed-height `virtual_list` emits only the visible range.
- Test/benchmark: `tests/main.odin` and `benchmarks/main.odin`.
- Result: retained rows are viewport-scale, not logical-item-scale.
- Known limitations: the current helper proves range virtualization and hit
  testing is covered for ordinary controls, but virtual-row selection routing is
  not yet implemented.
- Verdict: proven for fixed-height rows.

## Claim: Runa-backed text rendering and editing works

- Implementation: text-node/editing abstraction exists, but the installed Odin
  SDK has no Runa package. Upstream Runa v1.2.3 exposes the expected facade and
  segmentation/raster APIs, but has not been vendored or wired into this tree.
- Result: basic retained text editing is headlessly testable; shaping, bidi,
  segmentation, rasterization and cluster mapping are not.
- Verdict: not proven.

## Claim: SDL3/SDL_GPU and custom-surface lifetime behavior is safe

- Implementation: platform-neutral command/fence retirement model and SDL3
  vendor availability notes.
- Result: the lifetime model has stress tests; native driver execution has not
  been run in this environment.
- Verdict: partially proven; native compositor remains unverified.

## Claim: idle UI performs effectively no unnecessary work

- Implementation: invalidated-frame gate.
- Measurement: benchmark records skipped frames, description execution and
  headless GPU-submit count. It does not yet capture allocator telemetry,
  process CPU utilization or OS wakeups.
- Verdict: partially proven for the headless scheduler; native OS/GPU wakeups
  and allocation behavior remain unverified.

## Gate recommendation

`REVISE`: the identity, invalidation, input and fixed-height scale mechanisms are
credible, and the SDL3/SDL_GPU fence smoke path runs on this host. Runa-backed
text and full retained display-list rendering remain unproven, and composition
reuse is conservative. The next layer should not expand until those gaps are
closed on a native fixture.

## Raw benchmark sample

Environment: Windows 10.0.19045, Odin `dev-2026-09-nightly:a2fb372`,
2026-09-13. The host CPU query was denied by the managed environment, so no CPU
model is claimed. Command: `powershell -ExecutionPolicy Bypass -File
tools/bench.ps1`.

| workload | first ns | unchanged ns | one change ns | keyed reorder ns | retained nodes | cumulative layout updates |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 nodes | 559200 | 356000 | 361000 | 383600 | 101 | 200 |
| 1,000 nodes | 23403900 | 21722500 | 21881800 | 22470400 | 1001 | 2000 |
| 10,000 nodes | 2804309400 | 2792453000 | 2796636600 | 2792247700 | 10001 | 20000 |

Virtual list: 1,000,000 logical rows, 100 scroll frames, elapsed `6197800 ns`,
retained nodes `23`. Idle: 10,000 attempted frames, elapsed `18400 ns`,
`idle_count=10000`, headless GPU submits `0`.

Native command: build `native/sdl_gpu`, put the SDK's SDL3 directory on
`PATH`, run the executable. On this host it submitted and fence-waited three
SDL_GPU command buffers successfully and enabled the SDL mouse/window event
adapter. It is a lifetime smoke test, not yet a full retained display-list
renderer.
