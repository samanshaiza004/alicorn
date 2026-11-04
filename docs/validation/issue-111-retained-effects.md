# Issue #111: bounded retained-effects experiment

Research: 2026-11-03; native validation: 2026-11-04.
Sources: [primary-source review](../research/retained-effects-issue-111.md).

## Scope and decision

This implements an isolated experiment, gated by
`ALICORN_RETAINED_EFFECTS_EXPERIMENT=true`. Ordinary applications exclude the
experiment at compile time. `Runtime`, `Paint_Command`, layout, semantics,
the application loop, scheduling, and `draw_display_list` are unchanged.

The decision is **NO-GO for a supported application effects API at this stage**.
The probe establishes a bounded implementation and a reproducible comparison;
it does not establish the issue's two real consumer interactions or full backend
acceptance. Backdrop blur remains an experiment. Existing analytic materials
remain the component-shadow implementation.

The two candidate needs are Scratchpad's Quick Open/command palette background
and localized component separation in History/Scope. These fixtures approximate
those surfaces using the actual generic paint stream; they are not changes to
the dogfood applications or evidence of user preference.

## Run

```sh
sh tools/validate_effects.sh --odin /path/to/odin
# Where SDL supports Vulkan:
sh tools/validate_effects.sh --odin /path/to/odin --driver=vulkan
```

```powershell
./tools/validate_effects.ps1 -Odin odin
./tools/validate_effects.ps1 -Odin odin -Driver vulkan
```

The runners enable the experiment, run native unit tests, then execute device-only
GPU readbacks. Requested-device failure is a failure, never a silent pass or a
switch to a different renderer. Captures are written to
`out/retained-effects/{flat,analytic-shadow,blur-cold,blur-retained}.ppm`.
Foundation CI includes Metal and D3D12 runs; adding a step does not constitute
a completed hosted result.

## Boundary and rendering contract

`Native_Effect_Request` contains one stable key, authoritative source generation,
resolved output rectangle/ancestor clip, uniform DPI scale, finite kernel spacing,
and depth. A source generation must include every contributing paint, glyph,
image, geometry, background, and resource change. The fixture advances it
explicitly. There is no automatic observation of arbitrary paint resources and
no persistent node-based effect state.

The effect captures the specified paint prefix before foreground commands. It
replays it through `draw_display_list`, translated into the input rectangle,
with the original per-command clips preserved. It never samples a swapchain.
The palette comparison replays a **known opaque background** with the prefix;
the filtered alpha-one result replaces the original backdrop at composition.
Replaying a transparent prefix over itself would double-composite it and is
not a valid general backdrop capture. Transparent isolated layers are tested
separately by the readback cases.
The input includes the complete two-tap halo on each side and rounds outward
in physical pixels. The output is scissored to the resolved region/ancestor
intersection. Nested effects are rejected; nested ordinary clips are retained.

The blur is a fixed separable five-tap binomial filter, `[1,4,6,4,1]/16` per
axis, not a configurable Gaussian or an effect graph. Five weighted quads per
axis reuse Alicorn's compiled image shader. The shader needs no new artifact,
runtime compilation, or backend-specific effect implementation. Input, horizontal,
and vertical stages use distinct RGBA8 textures. Two filter passes accumulate
premultiplied RGBA additively; composition uses `ONE, ONE_MINUS_SRC_ALPHA` so
alpha is not multiplied twice. The final palette and foreground retain painter
order. All passes end before the next pass begins.

The color contract is **encoded SDR RGBA8**, matching the existing ordinary
UNORM renderer. This is deliberately not a linear-light blur. HDR, sRGB render
targets, wide-gamut/native display color management, and rounded effect-output
masks are unimplemented. A supported effects API needs an explicit decision on
those cases; changing the whole renderer's color contract is outside this probe.

## Bounded retention and failure behavior

- One slot, three textures, maximum 2048 physical pixels on either axis,
  spacing at most eight logical pixels, depth exactly one. There is no
  unbounded cache or hidden full-window target.
- The fixture uses a 16 MiB budget for requested texture and fixed vertex/transfer
  buffer bytes. Existing source-renderer buffers, final target/readback buffers,
  pipeline/sampler objects, and driver allocation overhead are excluded. This
  is not a measurement of total frame memory or hardware texture residency.
- Textures and buffers do not cycle. A changed source generation repaints the
  complete bounded input; unchanged generations reuse the filtered result.
  There is no partial-damage algorithm.
- Resize/replacement/deactivation uses conservative device-idle retirement in
  this isolated probe. That prevents a resize storm from retaining unlimited
  old storage, but it can stall other work. It is a reason to defer production
  adoption until a fence-tracked, nonblocking resource policy is measured.
- Unsupported format, budget, or allocation failure chooses direct drawing.
  Canceled/submission-failed work is not published as a valid output generation.
  Reset retires the slot; a fresh cache recreates resources lazily.
- Device loss is not transparently recovered. A failed device requires the
  host's device teardown/recreation; old cache handles must never migrate to a
  new device. Actual device removal and injected submit failure remain untested.
- Initially inactive scenes create zero effect resources. Static cached planning
  performs no filter pass, allocation, submission, timer, or wake. The probe
  itself owns no event loop; existing native-host idle behavior is unchanged.

## Validation and measurement boundaries

The CPU reference independently performs both quantized RGBA8 filter passes
over the generic renderer's downloaded source pixels, then computes
premultiplied source-over and foreground ordering. This validates the filter
and composition; the source renderer's correctness remains covered separately
by the existing blend/readback suite. Source and destination never alias.

Readbacks cover transparent colored edges, text, ancestor clipping, input halo,
foreground overlap, scales 1/1.25/1.5/2, source-generation changes, cache reuse,
fresh rebuild equality, cancellation, reset/recreation, and direct fallback.
Transfer rows are padded to the D3D12-compatible 256-byte alignment. The unit
tests reject invalid numeric values, oversized regions, excess nesting, and
missing source identity before allocation.

The fixture is built with `-o:speed`. Timing prints first-frame encoding and
submission-to-fence wall time, followed by
40 warm samples' p95 for flat, direct analytic shadow, changed-source blur,
and retained blur during a forced ordinary repaint. The first sample's artifact
readback is excluded from warm samples. These first frames occur in a warmed
process after correctness probes; they are not cold application/driver startup
measurements. Encoding wall time includes preparation and the conservative
device-idle wait. Submission-to-fence wall time includes
driver/queue/wait costs and is **not hardware GPU timestamp duration**. SDL_GPU
does not expose a portable timestamp query used by this fixture. Captures,
correctness readbacks, and device-idle resize stalls are not described as frame
presentation latency.

Remaining adoption gates include two app-level interaction reviews,
hardware GPU p95/residency, native idle tracing with enabled effects, failure
injection/device removal, more than one outstanding command, and backend parity.

## Native results: Apple M1, macOS 27.2, Metal

Odin `dev-2026-11-nightly:9a69916`, SDL 3.4.18; baseline commit `fe8967f` plus
this working-tree experiment. Metal API validation was enabled. One run, 40
warm samples per mode, 384×256 final target. The effect's resolved output is
192×144 at 1×; its padded input is 208×160. These are small fixture results,
not a product benchmark or a cross-framework comparison.

| Mode | First encode / submit-wait (ms) | Warm encode p95 (ms) | Warm submit-wait p95 (ms) | Warm render passes | Effect bytes live/peak |
| --- | --- | --- | --- | --- | --- |
| Flat palette | 2.562 / 1.650 | 1.514 | 2.154 | 15 | 0 |
| Existing analytic shadow | 1.546 / 1.273 | 1.626 | 2.656 | 16 | 0 |
| Blur, source changed every frame | 3.804 / 2.204 | 2.880 | 4.107 | 29 | 404,112 |
| Retained blur, forced ordinary repaint | 3.210 / 2.101 | 1.586 | 2.259 | 16 | 404,112 |

The changing-source mode replayed the prefix and filtered each time (82 filter
passes over 41 frames). The retained mode filtered once (two filter passes),
then reused that texture for 40 repaints. Each effect mode created eight SDL
objects initially and uploaded 2,376 effect vertex bytes total; source-only
changes did not reupload the filter mesh. Repeated inactive/unchanged requests
created no additional effect resources or submissions. Reset returned charged
live bytes to zero. The reported 404,112 bytes are about 0.39 MiB, below the
16 MiB requested-storage budget.

Readbacks passed five independent CPU-reference cases with maximum error
three RGBA8 values, plus cached-versus-fresh equality and pixel-identical direct
fallback. Five overlapping weighted quads accumulate into RGBA8 per axis, so
rounding is not identical to one unquantized convolution write; the fixed
tolerance accounts for those intermediate blend writes. No new shader binaries
were added. The optimized standalone validation executable is 3,353,368 bytes;
that is its whole size, not the incremental cost of effects in an application.
The default host executable contains no `native_effect_*` symbols.

| Check | Result |
| --- | --- |
| Runtime suite, default build | PASS, 317 tests; retained record sizes unchanged |
| Complete `tools/test.sh`, default build | PASS, including 152 native tests, AccessKit contracts, UI/theme, text input, restoration |
| Opt-in native suite | PASS, 156 tests (four new experiment tests) |
| Metal effects readback | PASS, clipping/DPI/alpha/order/cache/invalidation/cancel/reset/fallback |
| Existing Metal blend suite | PASS, 156/156 cases plus motion clip checks |
| Default native-hello idle smoke | PASS, three seconds; one submission/retirement, two event waits, zero application wake events/ticks or motion timers |
| Vulkan availability on this Mac | UNAVAILABLE: `SDL_HINT_GPU_DRIVER vulkan unsupported!` |
| D3D12 and hosted workflow executions | UNVERIFIED locally; reproducible runner and CI step added |
| Actual device loss / hardware GPU timestamps / real dogfood interaction comparison | UNVERIFIED |

The sandbox cannot enumerate this Mac's displays. The successful Metal runs
used the normal desktop session with elevated execution; this limitation was
not bypassed using a dummy video driver.

Raw measurement output: [Metal fixture run](raw/issue-111-metal-2026-11-04.txt).

## Visual comparison

These deterministic captures show the same static palette/content scene, not
live dogfood screenshots. They were inspected locally after the opaque-prefix
capture correction. The blurred background reduces competing text detail in
this example; that alone does not establish a second useful application need.

| Flat palette | Direct analytic shadow | Retained backdrop blur |
| --- | --- | --- |
| ![Flat palette](assets/issue111-flat.png) | ![Analytic shadow](assets/issue111-analytic-shadow.png) | ![Retained blur](assets/issue111-blur-retained.png) |

For now the useful result is an opt-in, tested probe and an explicit adoption
boundary: keep direct shadows, retain the blur experiment, and require real
consumer evidence plus a nonblocking lifetime/color policy before promoting
the layer into Alicorn's supported application API.
