# v0.2 adversarial follow-up — 2026-10-23

This follow-up starts from Alicorn `2063b03` and records verified work prompted
by the release-stabilization audit. It adds focused regressions and closes the
confirmed issues below; it does not certify v0.2.0 for release.

## Verified issues and changes

### Native surface paint extent

Rounded material surfaces were culled twice using different extents. The vertex
reservation pass expanded visibility for an outer shadow, while geometry
emission tested only the underlying rectangle. A surface outside the viewport
or parent clip could therefore reserve vertices and still lose a shadow that
crossed into the visible area.

Both passes now use one pixel-space paint footprint, including rounded
antialiasing, centered strokes, and outer shadows. Material meshes use the
resolved scissor, while flat rectangles keep the clipped-quad fast path. The
regression covers rounded and rectangular relief surfaces at a viewport edge
and a parent-clip edge, at scales 1, 1.25, 1.5, and 2; it also verifies fully
offscreen paint remains culled.

### Alpha compositing

The five native primitive pipelines used two source-alpha equations. An actual
Metal readback of the production display-list compositor confirmed the defect:
half-opacity content on transparent black returned alpha 64 instead of 128,
and two overlapping half-opacity layers returned alpha 96 instead of 191.

All five pipelines now share one straight-alpha source-over state: RGB uses
`SRC_ALPHA` / `ONE_MINUS_SRC_ALPHA`, while alpha uses `ONE` /
`ONE_MINUS_SRC_ALPHA`. The production-path readback runner compares rendered
RGBA values against CPU-derived mask coverage and expected compositing.

| Primitive family | Cases | Failed after fix |
| --- | ---: | ---: |
| Surfaces, including rounded interiors | 48 | 0 |
| Custom geometry | 24 | 0 |
| Icons | 24 | 0 |
| Images | 24 | 0 |
| Text | 24 | 0 |
| Mixed overlapping layers | 12 | 0 |
| **Total** | **156** | **0** |

The run used Metal and `R8G8B8A8_UNORM`, scales 1, 1.25, 1.5, and 2, and
destination alpha 0, 0.4, and 1. The separate image readback also passed SDR
and SDR-linear targets. Windows/D3D12 blending readback and other GPU target
formats remain unverified here.

### Secondary-window event overload

The old pump ignored a failed child-queue append and continued polling, so a
full 4096-event queue could silently lose a key release, focus loss, committed
text, or close request. The production pump now returns before waiting when the
queue is full and stops polling as soon as an enqueue fills it. The application
loop replays child input at its existing safe point before polling resumes.
Direct enqueue overload can discard motion samples first; it preserves other
queued transitions and FIFO order. Consumed queue storage is reused, and
partial text copies are released if allocation fails.

Four regressions cover full motion queues, pump backpressure with critical
events pending in SDL, interleaved replay staying within the capacity, and
payload cleanup on allocation failure. The queue capacity bounds event count,
not the total bytes of variable-length text. If payload allocation fails, the
event is logged and dropped; input-state recovery under OOM is not guaranteed.

### Invalidation and public identity

The new differential fixture compares settled incremental rendering with a
fresh Runtime after consumed keyboard actions, outside-description mutations,
all nonempty combinations of content/typography/material changes, keyed
reorder, keyed removal, and unrelated-region reuse. It verifies one-shot action
consumption, zero idle descriptions, and mutation diagnostics when enabled.
It also confirms the documented limit: forgetting invalidation can leave stale
output, and the advisory diagnostics cannot prove that the chosen region or
revision covers the actual mutation.

The public query test exposed a separate metadata omission: `region_begin`
used the established explicit-string identity for its node ID but did not
publish the local key to `node_info`, `node_identity_key`, or `node_by_key`.
`region_begin` now fills that metadata without changing the ID encoding. The
regression covers normal and empty keys, a parent identity scope, initial
description, retained reuse, and invalidation.

### Controlled text-field contract

No runtime logic defect was reproduced in the ownership and lifecycle audit.
Seven public-API regressions now cover programmatic-value precedence over an
unadopted edit, unchanged-value adoption, IME reset, removal/retyping and
uncontrolled-field transitions, and releasing/replacing the app buffer between
descriptions. The reference now documents single ownership, allocator lifetime,
borrowed pointer/text lifetime, update precedence, IME behavior, and one-shot
submit delivery. The lower-level uncontrolled text-field path remains
available.

## Rounded-surface workload

The material budget benchmark now also exercises 500 described surfaces in a
fully visible controls/tabs/cards arrangement and a scrolling-list arrangement
where only 27 flat/rounded surfaces or 28 relief surfaces emit geometry. It
warms the renderer and checks that the next 20 rebuilds allocate no new vertex
or draw storage.

| Scene and treatment | Emitted vertices | Active vertex bytes | Warm allocations |
| --- | ---: | ---: | ---: |
| 500 visible flat surfaces | 3,000 | 108,000 | 0 |
| 500 visible rounded-flat surfaces | 157,500 | 5,670,000 | 0 |
| 500 visible rounded-relief surfaces | 682,500 | 24,570,000 | 0 |
| 27 visible rounded-flat rows | 8,505 | 306,180 | 0 |
| 28 visible rounded-relief rows | 38,220 | 1,375,920 | 0 |

On this Apple Silicon host, the measured 500-surface rounded-relief rebuilds
were roughly 8–13 ms across the four tested scales in the recorded run. An
earlier local run varied more, so these timings are workload evidence, not a
portable frame-time claim. They measure CPU mesh expansion only, not GPU time.
The vertex and byte counts are the stable evidence: rounded relief remains an
opt-in visual treatment with a substantial geometry cost for hundreds of
simultaneously visible surfaces.

## Validation run

| Check | Result |
| --- | --- |
| `sh tools/check.sh` | PASS: examples, 257 runtime tests, 35 theme tests, theme CLI/codegen |
| `sh tools/test.sh` | PASS: foundation, 257 runtime tests, 35 theme tests, 109 native tests, text-input host contract, restoration |
| `sh tools/bench.sh` | PASS: retained-work benchmarks, including 10,000 idle frames with zero app work and 1,000,000-item virtualization retaining 23 nodes |
| `sh tools/bench_text_layout.sh` | PASS: 20,000-row workload retained 13–15 nodes through scrolling and width reflow |
| `sh tools/bench_material.sh` | PASS: flat output matched direct quad; workload geometry and zero-warm-allocation checks passed |
| `sh tools/validate_blending.sh` | PASS: 156 Metal readback cases, zero failures |
| `sh tools/validate_images.sh` | PASS: Metal SDR/SDR-linear, clipped translation, source-over and midtone checks |
| `odin check native/sdl_gpu -target:windows_amd64 -no-entry-point` | PASS: Windows cross-platform compile check |
| `odin check native/blend_validation_entry -target:windows_amd64 -no-entry-point` | PASS: Windows blend-probe entry-point compile check |
| `python3 tools/test_package_macos.py` | PASS: 8 packaging tests |
| `git diff --check` | PASS |

Both full `tools/build_native_release.sh` invocations (static and shared) built
their bundles but failed their direct-executable idle smoke with `SIGABRT` in
`NSApplication` initialization during SDL's Cocoa video initialization. The
crash report identifies AppKit `RegisterApplication` as the abort site; the
bundle executable and `CFBundleExecutable` entry were present. Launch Services
also returned `kLSNoExecutableErr` when asked to open the generated bundle.
The same static and shared bundles passed packaging, dependency relocation, and
signing when generated with `--skip-smoke-test`; this does not count as a
successful desktop launch. The macOS GUI packaging smoke therefore remains a
release gate requiring a working interactive desktop session.

## Release gates still open

- Run at least one real Narrator/NVDA and VoiceOver session.
- Repeat native foreground input and IME testing on macOS and Windows.
- Verify DPI transitions while physically moving windows between displays.
- Obtain a successful static and shared macOS package launch in a desktop
  session, plus the remaining platform lifecycle checks.
- Run the new compositing readback on Windows/D3D12.

This follow-up does not establish v0.2.0 release readiness.
