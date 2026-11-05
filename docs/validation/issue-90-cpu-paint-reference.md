# Issue #90 — CPU paint reference prototype

Captured 2026-11-05. This records the bounded prototype and its first Windows
validation. It does not propose a production software renderer.

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
128×128, then compares every channel of every pixel. The per-channel tolerance
remains 2/255. On this Windows D3D12 run:

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
counts were not measured. Hosted CI duration has not yet been collected.

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
that the existing point probes did not detect, so the prototype has shown
additional detection value on D3D12.

## Current decision and remaining validation

**GO for retaining this narrow test-only reference.** Keep the generated corpus
bounded and extend supported paint operations only when a real test need
justifies it. The mismatch seed and reduced command are replayable from this
report and the fixed generator.

Metal validation and hosted CI cost remain open. Run the existing
`tools/validate_blending.sh` workflow on macOS and record its result and elapsed
time before closing Issue #90. Fractional geometry, non-unit DPI, antialiasing,
rounded surfaces, text, icons, images, and materials remain unsupported.
