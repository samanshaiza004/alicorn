# Issue #90 — CPU paint reference validation

Updated 2026-11-05. The implementation results below were measured for PR #161
at `2af693e489e6abf7eafbd35ac42f7349d7711030`, based on `master` at
`c6eb8fe6fd0c6229cafb2f2d2592876ca786a6cc`; this follow-up only records the
evidence. It documents the bounded test-only reference, not a production
software renderer.

## Implemented contract

The headless reference consumes `[]Paint_Command` and writes into a caller-owned
RGBA8 buffer. Its package has no SDL, GPU, window, or host-font imports. It
prevalidates the complete command list before modifying the output buffer.

The current raster contract is deliberately narrow:

- Target size is 1–128 pixels per dimension, with scale 1.
- Bounds after translation and clip edges are integer-aligned, and rectangles
  use half-open `[x0, x1) × [y0, y1)` pixel coverage.
- Translation moves bounds. The clip is already resolved and remains in its
  original coordinate space.
- Only flat rectangular surfaces without stroke or optical decoration are
  supported. Other payloads, shapes, materials, decorations, fractional edges,
  invalid colors, and non-finite values return a typed error with the command
  index and owner.
- Source RGB is straight-alpha input. Source alpha is `fill.a * opacity`; RGB
  uses `Cs * As + Cd * (1 - As)` and alpha uses `As + Ad * (1 - As)`. Each
  operation is quantized to nearest RGBA8 before the next command. No sRGB
  transfer is applied.
- Clear is transparent black or any opaque RGBA8 color.

The CPU implementation has its own raster and blend code. It does not call the
GPU bounds or blend helpers. The GPU comparison reuses the existing
`blend_validation_readback` path and its `R8G8B8A8_UNORM` offscreen target.

## Test evidence

Headless tests cover the hand-calculated red/blue source-over result, reversed
paint order, opaque clear, stationary clipping after translation, transparent
surface insertion, scene-plus-clip translation, transactional rejection,
fractional-edge rejection, and deterministic seeded replay.

The GPU fixture renders 32 deterministic scenes of eight rectangles each at
128×128, plus a fixed one-command regression reduced from the mutation failure.
It compares every channel of every pixel at a per-channel tolerance of 2/255.
The fixed case is outside the 32-scene timing totals. On the initial local
Windows D3D12 run, before adding the fixed fixture:

| Check | Result |
| --- | ---: |
| Existing targeted GPU cases | 156/156 passed |
| Generated full-frame scenes | 32/32 passed |
| CPU reference time, 32 scenes | 24.39 ms total; 0.762 ms mean per scene |
| GPU readback path, 32 scenes | 4.80 ms total; 0.150 ms mean per scene |
| CPU reference allocations per scene | 0 by construction; caller-owned buffers are reused |
| Validation script wall time | 1.43 s with an incremental build |

These timings are one local measurement, not a performance distribution. The
GPU timing covers the existing offscreen draw/readback path; GPU-host allocation
counts were not measured. They are retained as the original local baseline and
are not directly comparable to the hosted measurements below.

### Exact PR-head D3D12 and Metal results

Both native backends ran the existing 156 targeted cases, all 32 generated
scenes, and the fixed regression on the exact PR head `2af693e`:

| Backend | Existing GPU cases | Generated full-frame scenes | Fixed clip regression | CPU reference for 32 scenes | GPU render/readback for 32 scenes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Windows D3D12 | 156/156 passed | 32/32 passed | Passed | 46.78 ms total; 1.462 ms/scene | 11.40 ms total; 0.356 ms/scene |
| macOS Metal | 156/156 passed | 32/32 passed | Passed | 53.19 ms total; 1.662 ms/scene | 58.71 ms total; 1.835 ms/scene |

The per-scene measurements are from the validation log's 32-seed corpus. They
exclude the extra one-command regression render/readback. CPU rendering uses no
per-scene heap allocation; the GPU column measures the offscreen production
draw/readback path, not just the CPU reference. These are single hosted-run
measurements rather than performance distributions. The Windows run used the
`windows-2025-vs2026` runner image; Metal ran on the `macos-26-arm64` image
(macOS 26.6.2).

### Hosted CI duration

All four PR-triggered workflows passed on the exact head. The table separates
the workflow's GitHub elapsed time from runner job execution. Workflow elapsed
time includes inter-job waiting/serialization; job times are runner wall-clock
durations and overlap where the workflow runs jobs in parallel.

| PR workflow | Result | Workflow elapsed | Runner job time |
| --- | --- | ---: | ---: |
| [Windows foundation](https://github.com/samanshaiza004/alicorn/actions/runs/42087953123) | Passed | 3m 23s | 3m 19s |
| [Icon reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/42087952999) | Passed | 16s | 12s |
| [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/42087952608) | Passed | 9m 07s | 7m 43s across Windows and macOS jobs |
| [macOS foundation / Metal](https://github.com/samanshaiza004/alicorn/actions/runs/42087952983) | Passed | 9m 50s | 4m 44s |

The four workflow elapsed durations sum to 22m 36s of workflow time, while
their observed event-to-final-completion wall-clock span was 9m 50s because
they ran concurrently. Their runner job durations sum to 15m 58s; that sum is
also not end-to-end CI wall time. A duplicate push-triggered macOS foundation
run for the same SHA also passed ([run 42087943642](https://github.com/samanshaiza004/alicorn/actions/runs/42087943642)); it took 15m 09s from workflow start to completion, including its wait before the 5m 01s runner job began.

These durations describe the full hosted workflows, including setup, build,
packaging where applicable, and other tests. They are not the incremental cost
of the CPU reference. The best available isolated cost is the per-scene CPU
and offscreen GPU timing above; the one-command regression adds one additional
draw/readback but is not separately timed. Hosted CI timings are a single run,
not a stable latency benchmark.

## Mutation experiment

A temporary renderer mutation translated the clip along with the command
bounds. The existing 156 targeted cases still passed. The full-frame comparison
failed on seed 2 with 27 mismatching pixels and a maximum channel error of 24
bytes. The reducer only removed commands when the mismatch reproduced and
reduced the eight-command scene to this one-command case:

```text
owner=7
bounds=(112,76,36,42)
clip=(113,101,2,9)
translation=(2,-3)
opacity=0.2509804
fill=(0.85882354,0.92941177,0.49019608,0.5019608)
```

The mutation was reverted. This demonstrates a clip/translation fault class
that the existing point probes did not detect. The reduced command is now a
named, permanent CPU assertion and is rendered through the production GPU
readback path independently of the seeded corpus. It expects coverage in
exactly one pixel column by nine rows at `(114, 101)` through `(114, 109)`, so
changes to the random generator cannot erase this fault-class regression. The
fixed case passed on both D3D12 and Metal within the same 2/255 tolerance.

## Decision

**GO for retaining this narrow test-only reference.** Keep the generated corpus
bounded and extend supported paint operations only when a real test need
justifies it. The random seed remains useful for replaying the discovery; the
fixed regression now provides stable independent coverage.

The exact PR-head D3D12, Metal, hosted workflow, and fixed-regression checks
passed. Issue #90's research and adoption gate is satisfied. Fractional
geometry, non-unit DPI, antialiasing, rounded surfaces, text, icons, images,
and materials remain outside this reference's contract.
