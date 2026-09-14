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
  counters, retained child adjacency, inspector and trace ring. Adjacency is
  guarded by a hash of pending parent/order membership and is rebuilt only on
  structural change.
- Test: changing one keyed meter changes that node's paint stage while sibling
  descriptions and layouts are reused; an unchanged invalidation leaves the
  adjacency rebuild counter unchanged.
- Result: the 10,000-node unchanged benchmark is now approximately linear and
  unchanged invalidations avoid adjacency reconstruction; composition remains
  conservative.
- Verdict: partially proven.

## Claim: input and focus are deterministic

- Implementation: one `focused` Node_ID, retained hit testing and fallback,
  plus one pointer capture owner. Down captures and presses; Up activates only
  when it returns to the captured node.
- Test: focus through reorder, removal, filtering and representation changes;
  activation consumption, retained hover/pressed state, outside-release
  cancellation, click-on-release, ancestor fallback and nested clipping.
- Verdict: proven by headless tests for the defined fallback and activation
  policy.

## Claim: a million-row list has bounded retained state

- Implementation: fixed-height `virtual_list` emits only the visible range.
- Test/benchmark: `tests/main.odin` and `benchmarks/main.odin`.
- Result: retained rows are viewport-scale, not logical-item-scale.
- Known limitations: fixed-height rows only; fractional scroll offset and
  offscreen selection storage are not implemented.
- Verdict: proven for fixed-height rows.

## Claim: Runa-backed text rendering and editing works

- Implementation: `runtime/text.odin` owns a cloned font buffer, parsed Runa
  font, bounded Runa shape cache and GUI-facing layout metrics. The GUI does not
  retain Runa's atlas representation.
- Test/measurement: `examples/runa_text` loads a caller-provided font and lays
  out `office — Alicorn` twice, a three-line paragraph, and a width-constrained
  paragraph. The headless runtime test exercises deletion and selection through
  Runa UAX #29 grapheme boundaries for multi-byte and extended emoji clusters.
- Result: real Runa font loading, cache reuse, multiline metrics, wrapping and
  grapheme-safe text editing work. Caret hit testing, IME and atlas upload are
  not implemented.
- Verdict: partially proven.

## Claim: SDL3/SDL_GPU and custom-surface lifetime behavior is safe

- Implementation: platform-neutral command/fence retirement model plus a native
  SDL3 adapter that acquires swapchain textures, runs render passes, composes
  retained rectangle commands with GPU blits, and retires temporary textures
  behind submission fences.
- Result: the native proof submitted `6` frames with `3` frames in flight and
  retired `6` concrete offscreen textures on this host.
- Known limitations: the compositor is rectangle-based; shader pipelines,
  glyph-atlas upload and cross-platform driver coverage remain unverified.
- Verdict: partially proven.

## Claim: idle UI performs effectively no unnecessary work

- Implementation: invalidated-frame gate.
- Measurement: benchmark records skipped frames, description execution and
  headless GPU-submit count. It does not yet capture allocator telemetry,
  process CPU utilization or OS wakeups.
- Verdict: partially proven for the headless scheduler; native OS/GPU wakeups
  and allocation behavior remain unverified.

## Gate recommendation

`REVISE`: the identity, invalidation, input, fixed-height scale, Runa layout and
native rectangle-composition mechanisms are now credible. Full glyph atlas
rendering, IME/cluster editing, cross-platform native coverage and conservative
composition reuse remain open. The next layer should not expand until those
gaps are closed.

## Raw benchmark sample

Environment: Windows 10.0.19045, Odin `dev-2026-09-nightly:a2fb372`,
2026-09-13. The host CPU query was denied by the managed environment, so no CPU
model is claimed. Command: `powershell -ExecutionPolicy Bypass -File
tools/bench.ps1`.

| workload | first ns | unchanged ns | one change ns | keyed reorder ns | retained nodes | cumulative layout updates | adjacency rebuilds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 nodes | 360100 | 101300 | 106800 | 109500 | 101 | 100 | 2 |
| 1,000 nodes | 3835600 | 1123000 | 1079000 | 1124600 | 1001 | 1000 | 2 |
| 10,000 nodes | 33057700 | 14397800 | 15431000 | 15199900 | 10001 | 10000 | 2 |

Virtual list: 1,000,000 logical rows, 100 scroll frames, elapsed `5733400 ns`,
retained nodes `23`. Idle: 10,000 attempted frames, elapsed `18600 ns`,
`idle_count=10000`, headless GPU submits `0`.

Runa text command: with `C:\Windows\Fonts\segoeui.ttf`, it reported single-line
height `31.921875`, multiline height `95.765625`, wrapped height `159.60938`,
multiline glyph count `13`, wrapped glyph count `23`, and cache size `4 -> 4`
on the verification host.

Native command: build `native/sdl_gpu`, put the SDK's SDL3 directory on
`PATH`, run the executable. On this host it submitted six SDL_GPU frames,
composed four retained display commands per frame, maintained three frames in
flight, and retired six temporary textures behind queried/waited fences.
