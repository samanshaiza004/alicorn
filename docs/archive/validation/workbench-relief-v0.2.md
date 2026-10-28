# Workbench Relief experiment — 2026-10-23

Candidate based on `d7e5441`. This implements the bounded recipe slice of #98;
it does not close the issue's remaining desktop acceptance gates.

The optional typed Button recipe uses the existing generic `Surface_Paint`.
Rest and pressed treatments have explicit presence: missing rest is flat,
missing pressed inherits rest, and explicitly defined flat overrides relief.
The material must be registered in the same Runtime before its theme. Height
is bounded to ±2. Existing themes, controls, geometry and JSON contract 0.2
remain compatible. JSON authors material definitions; the application connects
Runtime-local material IDs to typed recipes during setup.

Scratchpad's consumer branch adds Flat Workbench and Workbench Relief alongside
the existing Warm and Cool Light choices. Its application vocabulary maps
recessed/groove/flush/mounted/floating relationships to signed optical heights.
Semantic surfaces and Buttons keep their normal layout and interaction owners.
Relief themes are registered lazily, and each floating window keeps its own
Runtime-local theme/material handles. The editor remains a calm recessed well.

## Evidence

| Check | Result | Evidence / limit |
| --- | --- | --- |
| Runtime regression suite | PASS | 245 tests; includes pointer press/release, exactly one activation, explicit flat override, disabled state, invalid handles/heights, contrast/transparency, identity/focus, unchanged measurement/shaping/semantics and idle |
| Full foundation command | PASS | `tools/test.ps1`; runtime, theme, native-host suites, CLI/codegen, foundation executable, restart restoration, text-input contract |
| Examples | PASS | `tools/build_examples.ps1`; all 14 examples compile |
| Scratchpad integration | PASS | Go checks, 13 bridge tests, 161 frontend tests against the candidate API |
| Full-app optical transition | PASS | Flat → Relief → Warm with editor, syntax, modal and selected tab; same semantic nodes/bounds, preserved source-byte caret, zero new measurement/layout |
| Scale/clip coverage | PASS (structural) | Settings/text scale and native expansion at 1, 1.25, 1.5, 2; existing clip/finalization tests retained. These are not physical multi-monitor DPI tests |
| GPU image/clip readback | PASS | `tools/validate_images.ps1`: D3D12 SDR/SDR_LINEAR, midtone fidelity, clipped translation and source-over at all four scales; this checks the shared compositor, not four physical monitor captures |
| Same-scene GPU captures | PASS (Windows, 100%) | Scratchpad capture tool produces Flat, Relief, Increased Contrast snapshots from the real Editor Settings scene |
| Native idle | PASS (Windows scene) | Each 3-second D3D12 capture run: one submission, zero host wake events, publication/wake/ordered shutdown successful; no blinking text field in the scene |
| Shared Windows package | PASS | `tools/build_native_release.ps1 -SDLLinkage Shared`; dependency audit and empty-directory launch smoke |
| Static Windows package | BLOCKED locally | Build prerequisite `cmake.exe` unavailable; use packaging CI / prepared build environment |
| General native input fixture | BLOCKED in this session | `alicorn_sdl_gpu.exe --smoke` returned failure after it could not acquire foreground focus / activate SDL text input. This is not evidence of passing physical input acceptance |
| Physical fractional DPI / cross-monitor moves | BLOCKED | Requires desktop/display validation |
| macOS native chrome / appearance | BLOCKED locally | Requires macOS; foundation/package CI and real desktop validation remain required |

The source reports material/height and cache dependency domains in the existing
inspector. No shader, framebuffer, timer or material-specific input path was added.

## Cost

`tools/bench_material.ps1` / `.sh` preserve the original flat microbenchmark and
run a separate geometry-budget executable. A flat/zero-height surface emits
6 vertices, mounted/floating relief 66, recessed/groove relief 54, with one
surface draw slot at all four tested scales. These are measured CPU expansion
products, not GPU timings or a savings claim. Flat output matches the direct
quad byte-for-byte; the observed three-sample median was 8.80 ns/surface for
flat versus 8.65 ns/surface for the direct quad. Single runs do not establish a
timing regression or improvement.

## Release disposition

Keep #98 open until its Windows/macOS desktop appearance checks are recorded.
The implementation is opt-in and does not make the experiment a reason to
expand v0.2 architecture. Accessibility and release gates are recorded in
[release stabilization](release-stabilization-2026-10-23.md).
