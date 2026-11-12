# Per-corner surface validation

Validation for [issue #118](https://github.com/samanshaiza004/alicorn/issues/118)
after dogfooding the public surface-shape API in Scratchpad and the custom
segmented-control example.

## Results

| Check | Result |
|---|---|
| Scratchpad retained Find/editor/status geometry at 1×, 1.25×, 1.5×, and 2× | Pass; the three surfaces share aligned edges and retain only the exposed corner radii |
| Scratchpad full frontend suite | Pass; `./tools/alicorn.sh test`, 254 tests |
| Segmented-control public-API example | Pass; 6 tests, including both instances and both orientations |
| Alicorn full test script | Pass; `./tools/test.sh --odin /opt/homebrew/bin/odin` |
| Native Metal pixel readback | Pass; 348 cases, including all 16 corner masks at four scales and three destination alpha values |

The Metal readback checks all four outer pixels and the center of each surface,
with a two-byte RGBA tolerance. It exercises the compositor, upload, render,
and readback path rather than only inspecting generated geometry.

## CPU geometry benchmark

Captured on 2026-11-12 with an Apple M1 (8 cores), macOS 27.2 (build 26B123),
and Odin `dev-2026-11:9a6991685`. The benchmark builds 256 surfaces per batch,
warms the geometry, then reports p50 and p95 across 101 samples. Timings cover
CPU vertex expansion only; they exclude layout, display-list composition,
GPU upload, and presentation.

| Shape | Vertices per surface | p50 batch | p95 batch | p50 per surface | p95 per surface |
|---|---:|---:|---:|---:|---:|
| Rectangle | 6 | 4.000 µs | 4.000 µs | 15.625 ns | 15.625 ns |
| Uniform rounded | 324 | 1.034 ms | 1.045 ms | 4.039 µs | 4.082 µs |
| Per-corner rounded | 324 | 1.033 ms | 1.054 ms | 4.035 µs | 4.117 µs |

The rounded paths have the same vertex count. Their p50 difference is below
0.1% in this run; the p95 values are close and do not establish a performance
advantage for either path. The result indicates no material CPU geometry
regression for this workload, not a complete application-frame comparison.

[Raw benchmark output](../benchmarks/raw/issue-118-per-corner-macos-2026-11-12.txt)
and reproduction command: `./tools/bench_material.sh /opt/homebrew/bin/odin`.

## Scope

The Scratchpad test exercises its retained layout and semantic shape sidecars;
the Alicorn readback exercises the native Metal renderer with synthetic corner
patterns. This run did not capture a live Scratchpad window or validate another
GPU backend. D3D12 and Vulkan still require their respective platform runs.
