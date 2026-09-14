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
  counters, retained child adjacency, inspector and trace ring.
- Test: changing one keyed meter changes that node's paint stage while sibling
  descriptions and layouts are reused.
- Result: the 10,000-node unchanged benchmark is now approximately linear after
  replacing global child scans with retained adjacency; composition remains
  conservative.
- Verdict: partially proven.

## Claim: input and focus are deterministic

- Implementation: one `focused` Node_ID, retained hit testing and fallback.
- Test: focus through reorder, removal, filtering and representation changes;
  activation consumption, retained hover/pressed state, ancestor fallback and
  nested clipping regressions.
- Verdict: proven by headless tests for the defined fallback policy.

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
  out `office — Alicorn` twice. On the verification host it reported
  `169.86328 x 31.921875`, `16` glyphs, and cache size `1 -> 1`.
- Result: real Runa font loading and paragraph layout work; the existing basic
  text-field editing test remains byte-oriented and does not prove grapheme
  caret mapping, IME or atlas upload.
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

| workload | first ns | unchanged ns | one change ns | keyed reorder ns | retained nodes | cumulative layout updates |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 nodes | 457700 | 137100 | 207500 | 206200 | 101 | 100 |
| 1,000 nodes | 3896900 | 1170700 | 1196700 | 1158200 | 1001 | 1000 |
| 10,000 nodes | 33177200 | 14446700 | 15090700 | 15833100 | 10001 | 10000 |

Virtual list: 1,000,000 logical rows, 100 scroll frames, elapsed `5852100 ns`,
retained nodes `23`. Idle: 10,000 attempted frames, elapsed `18700 ns`,
`idle_count=10000`, headless GPU submits `0`.

Native command: build `native/sdl_gpu`, put the SDK's SDL3 directory on
`PATH`, run the executable. On this host it submitted six SDL_GPU frames,
composed four retained display commands per frame, maintained three frames in
flight, and retired six temporary textures behind queried/waited fences.
