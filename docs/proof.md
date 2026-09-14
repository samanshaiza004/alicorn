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
| 100 initial | 322,400 | 101 | 0 | 0 | 0 | 101 | 101 | 101 | 101 | 1 | 1,081 | 282,919 | 101 | 0 | 101 |
| 100 root wake unchanged | 114,800 | 101 | 101 | 0 | 0 | 101 | 1 | 0 | 0 | 0 | 123 | 23,252 | 0 | 0 | 101 |
| 1,000 initial | 3,096,200 | 1,001 | 0 | 0 | 0 | 1,001 | 1,001 | 1,001 | 1,001 | 1 | 10,114 | 2,511,331 | 1,001 | 0 | 1,001 |
| 1,000 root wake unchanged | 1,108,400 | 1,001 | 1,001 | 0 | 0 | 1,001 | 1 | 0 | 0 | 0 | 1,032 | 176,412 | 0 | 0 | 1,001 |
| 10,000 initial | 35,701,800 | 10,001 | 0 | 0 | 0 | 10,001 | 10,001 | 10,001 | 10,001 | 1 | 100,153 | 29,136,315 | 10,001 | 0 | 10,001 |
| 10,000 root wake unchanged | 12,772,400 | 10,001 | 10,001 | 0 | 0 | 10,001 | 1 | 0 | 0 | 0 | 10,042 | 1,559,788 | 0 | 0 | 10,001 |
| 10,000 root wake one value | 12,873,500 | 10,001 | 10,000 | 0 | 0 | 10,001 | 1 | 1 | 1 | 0 | 10,046 | 1,559,863 | 0 | 0 | 10,001 |
| 10,000 full keyed reorder | 14,643,100 | 10,001 | 10,000 | 0 | 0 | 10,001 | 1 | 1 | 10,001 | 1 | 10,046 | 1,559,883 | 0 | 0 | 10,001 |
| regional, unchanged root wake | 197,100 | 102 | 102 | 100 | 100 | 102 | 1 | 0 | 0 | 0 | 225 | 29,098 | 0 | 0 | 10,102 |
| regional, one 100-node region changed | 353,200 | 202 | 101 | 99 | 99 | 202 | 1 | 101 | 101 | 0 | 739 | 59,088 | 0 | 0 | 10,102 |
| large 10k region reused | 30,400 | 3 | 2 | 1 | 1 | 3 | 1 | 1 | 1 | 0 | 17 | 1,743 | 0 | 0 | 10,003 |

The regional initial build was `38,975,700 ns`, with 10,102 emitted,
reconciled, laid-out and painted nodes. The large-region initial build was
`37,004,200 ns`, with 10,003 retained nodes. The exact raw output is produced
by the benchmark executable; one-shot timings are illustrative, while the
visit-count locality is the primary evidence.

Structural churn on 10,000 keyed children measured swap, move-last-to-first,
reverse, 1% replacement, and 1,000 reorder-every-frame iterations. Reorders
created/retired zero nodes; each structural reorder rebuilt retained order and
the flat display composition. The 1% replacement created and retired 100 nodes.
Raw rows from this run were: swap `15,248,100 ns`, 10,001 reconciliation
visits, 10,001 composition visits, 1 adjacency rebuild; move
`15,534,900 ns` with the same counts; reverse `14,557,500 ns` with the same
counts; and 1% replacement `20,994,400 ns`, 10,001 reconciliation visits,
9,998 paint visits, 100 created and 100 retired. The 1,000-frame reorder loop
performed 1,000 adjacency rebuilds, 10,001,000 reconciliation visits, zero
creation/retirement, and retained 10,001 nodes. The benchmark prints all raw
counters and allocator requests.

Typed-key comparison from the same run:

```text
formatted_string_10k: 41,177,500 ns, 120,153 allocations, 29,255,223 bytes
typed_u64_10k:       34,449,900 ns, 100,153 allocations, 29,136,315 bytes
difference:           6,727,600 ns, 20,000 allocations, 118,908 bytes
```

The formatted path is a diagnostic comparison, not a claim that all of the
difference is string allocation.

## Existing regression evidence

`tools/check.ps1` builds and runs the foundation tests, benchmark executable,
identity torture executable, Crucible, and Runa text example. The headless
foundation tests pass after this gate. The fixed-height million-row benchmark
retains 23 nodes after 100 scroll frames (latest elapsed `6,732,800 ns`). The
native SDL3/SDL_GPU fixture was rerun after this closure on Windows
Direct3D12; existing Apple Silicon macOS validation remains the platform
baseline, not new cross-platform GPU-text proof from this gate.

## GPU text gate — stage 1

### Claim: Runa glyphs become retained GPU display data

- Implementation: `Runtime.text_engine` owns cloned font bytes, the parsed Runa
  font, a generation-keyed glyph-resource cache, a CPU atlas and copied logical
  `Text_Run` placements. Each retained text node owns its platform-neutral
  `Text_Run`; the SDL adapter resolves physical residency and owns the GPU
  transfer buffers, vertex buffer, shader pipeline and sampler.
- Test: `test_gpu_text_resource_boundary` verifies key separation and
  generation-safe Runa dirty snapshot/ack behavior. `examples/runa_text`
  verifies a shaped run rasterizes its unique glyphs once and reuses them on a
  second run.
- Native validation: the Windows SDL3/SDL_GPU fixture ran 303 submissions with
  three frames in flight and no SDL error. The text path issued 26 glyph quads
  from one persistent atlas page and the offscreen readback found 969 pixels
  differing from the clear color inside the expected text bounds.
- Result: the Runa-to-SDL_GPU path executes with real shader, copy-pass,
  render-pass, atlas texture, ordered display composition and fence-backed
  compositor resources.
- Known limitations: no color-glyph shader policy, no caret/selection
  geometry, no IME, and this native visual proof is currently Windows
  Direct3D12-only.
- Verdict: proven for the measured monochrome native path.

### Claim: unchanged native text avoids shaping and rasterization

- Implementation: node-owned `Text_Run` products are rebuilt only for dirty
  text nodes or a changed font generation. Glyph slots are cached by font
  generation, glyph ID, raster size, subpixel bucket, hint mode and color-page
  policy. The SDL adapter has no historical run cache, so virtualized node
  retirement bounds text-product retention.
- Benchmark command:

  ```powershell
  .\tools\native_sdl_gpu.ps1
  ```

  The Windows runner resolves Odin, validates the Odin distribution's
  `vendor\sdl3\SDL3.dll`, copies it beside the executable as
  `out\SDL3.dll`, and then launches the fixture. No SDL DLL `PATH` setup is
  required.

- Environment: Windows host, Odin `dev-2026-09-nightly:a2fb372`, SDL 3.4.14,
  Direct3D12, 2026-09-14. The fixture also performs 300 resize iterations.

| case | submissions | shape calls | glyph misses | glyph hits | rasterizations | atlas pages | quads | full-page uploads | upload bytes | readback pixels |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| native retained text + 300-frame resize stress | 303 | 2 | 16 | 44 | 16 | 1 | 27 | 2 | 8,388,608 | 969 |

This row is the historical Stage 1 fixture, before Stage 2 made the focused
field's width constraint part of the retained logical text product. The
current constraint-driven native result is recorded in the Stage 2 section.

- Result: after the initial base string and one deliberate `Z` mutation in the
  three-frame burst, subsequent unchanged text caused no additional shaping or
  glyph rasterization. The runtime-owned run is reused through the complete
  resize stress; the mesh fingerprint is rechecked but does not rebuild for an
  unchanged display.
- Verdict: proven for the measured retained native fixture.

### Claim: atlas updates preserve old glyph pixels when textures are cycled

- Implementation: every dirty atlas write uses a cycling transfer buffer but
  rewrites the complete page before cycling the destination texture. This
  avoids SDL's rule that the rest of a cycled texture is undefined until
  rewritten.
- Test: the headless boundary test writes a second glyph after the first dirty
  snapshot and verifies that acknowledging the first generation leaves the
  later write pending. The native readback uses a fence-signaled download from
  the rendered target.
- Result: partial dirty rectangles are retained as invalidation metadata, but
  the native upload policy is a conservative 1024×1024×4-byte page upload. The
  initial three-frame native burst changes the text after its first submission,
  producing two full-page uploads and one additional glyph rasterization before
  the burst is drained. The stress run completed without atlas corruption or
  resource-use failures.
- Known limitation: the native fixture does not inspect the first in-flight
  target after the second upload; it proves the submitted sequence and safe
  retirement, not a full pixel-by-pixel old/new atlas comparison.
- Verdict: proven for the selected full-page policy and exercised mutation
  sequence; visual preservation under every backend remains partial.

### Claim: mesh and compositor state do not retain stale text

- Implementation: the mesh fingerprint includes ordered display index, node ID,
  text, color, bounds, clip and DPI scale. Text is emitted at its display-list
  position, not in a final global text pass. Each text pass uses a load
  operation and a per-command scissor. Destination blits do not cycle the
  retained target, so later display items cannot erase earlier text.
- Test: native offscreen readback checks the text region after interleaved
  rectangle/text/rectangle composition. The fingerprint changes on the source
  fields listed above, including removal and reorder by construction.
- Result: the native fixture reports nonzero glyph coverage after ordered
  composition and no stale adapter-side run entries exist after node removal.
- Verdict: proven for the exercised ordered monochrome fixture; broad visual
  screenshot tolerance tests remain future work.

### GPU text allocation observations

The native adapter creates one atlas transfer buffer, one vertex transfer
buffer and one persistent vertex buffer. Atlas pages are created only when a
new Runa page appears. SDL transfer buffers are mapped with `cycle=true`, and
the handles remain alive through shutdown after a device-idle wait; no per-frame
transfer buffer or atlas texture is created in the 300-frame stress run. The
native readback additionally creates and fence-retires one offscreen target and
download buffer. Process-wide GPU allocator telemetry remains uncertain.

## GPU text gate — stage 2: text geometry and editing foundation

### Claim: logical text geometry can be retained independently of physical glyph residency

- Implementation: `Text_Run` now retains copied logical glyph IDs, cluster
  start/end byte ranges, line records, cumulative line Y positions, advances,
  offsets, embedding levels, and constraint metadata. It no longer stores a
  Runa atlas slot. The native SDL adapter resolves each glyph at the current
  DPI and raster size when it builds the physical mesh.
- Test: `test_text_geometry` exercises line-local caret coordinates, wrapped
  hit testing, multi-line selection rectangles, logical grapheme movement, and
  visual movement. `examples/runa_text` checks real Runa multiline and wrapped
  runs have increasing cumulative line positions.
- Result: logical layout survives physical residency changes as a separate
  retained product. A DPI change can select a new raster resource without
  changing the retained logical run.
- Known limitations: physical DPI changes have only been exercised through the
  native scale boundary; Retina/HiDPI GPU text execution remains unproven on
  this host, and internal caret placement inside a multi-grapheme ligature is
  deterministic interpolation rather than font-provided caret data.
- Verdict: partially proven.

### Claim: text layout can honor parent constraints without re-executing the application description

- Implementation: the layout pass derives an auto-width text constraint from
  the parent's cross-axis size before measuring the child's main axis. A new
  width rebuilds only the retained logical text product; unchanged root wakes
  do not rebuild a valid auto-width run.
- Test: the Runa example verifies constrained wrapping and cumulative metrics.
  The native focused-field fixture alternates logical window widths through 300
  resize iterations while retaining the same field identity and GPU resources.
- Native result: Windows Direct3D12 completed 303 submissions with 303 fence
  retirements, 16 glyph rasterizations, 16 glyph-cache misses, 9,344 glyph
  cache hits, one atlas page, and two full-page uploads. Shape/layout calls are
  expected to rise when the resize changes the text width constraint; this is
  not an unchanged-text reuse claim.
- Known limitations: the flex subset still uses a deliberately small two-pass
  model. Text in a row with an auto main-axis width does not yet participate in
  sophisticated shrink negotiation.
- Verdict: proven for the current constraint model.

### Claim: a retained text field can expose deterministic caret and selection geometry

- Implementation: `text_run_caret_geometry`, `text_run_selection_rects`,
  `text_run_hit_test`, logical grapheme movement, and line-based visual movement
  operate on the retained run. Runtime wrappers expose field geometry without
  retaining an application buffer pointer. Focused fields emit selection and
  caret display commands in retained paint order; pointer-down maps to the
  nearest visual boundary. Retained fields store `Text_Position` affinity and
  selection anchor/focus rather than only a sorted byte interval. Interaction
  changes explicitly queue the affected node's paint product.
- Test: headless geometry tests cover ASCII and wrapped lines; editing tests
  cover UTF-8, combining/extended grapheme deletion, insertion, selection
  direction and interaction repaint propagation. The native fixture composes a
  focused field and reports five display commands, including its caret
  decoration. `examples/runa_text` runs a real-font `ffiABC` regression; when
  the font forms the discretionary ligature, the editable policy disables it
  and verifies the byte boundary before `A` remains present.
- Result: the platform-neutral geometry and native decoration seam exists and
  passes the current deterministic tests.
- Known limitations: pointer drag selection, clipboard, full bidi caret
  movement/selection behavior and SDL committed text input/IME are not
  implemented.
  Internal ligature caret placement remains interpolation rather than
  font-provided component data. The current visual readback proves glyph
  coverage, not a golden caret/selection image.
- Verdict: partially proven.

## GPU text gate — stage 3: committed input and transient IME composition

### Claim: platform text input can be integrated without making preedit application state

- Implementation: `Text_Composition` is owned by the retained text-field node.
  The native adapter copies SDL `TEXT_EDITING` and `TEXT_INPUT` strings at
  event processing time. Editing events update a temporary projected
  `Text_Run`; committed events use the ordinary text-edit path and return an
  owned `Text_Change` for the application to copy.
- Test: `test_text_input_composition` covers UTF-8 character-index conversion,
  preedit non-mutation, repeated updates, reverse selection replacement,
  empty-preedit cancellation, focus transfer and composing-node retirement.
  The native SDL fixture pushes one `TEXT_EDITING` event followed by one
  `TEXT_INPUT` event through SDL's actual event queue and verifies the
  composition display command, committed application value and cleared state.
- Result: the runtime and native SDL adapter preserve the distinction between
  committed text and transient composition. SDL text input starts only while a
  focused text field owns keyboard focus, the input area follows retained caret
  geometry, and focus loss/shutdown clears and stops the platform composition.
- Known limitations: the SDL queue probe is deterministic adapter coverage,
  not proof that a real Windows/macOS IME emits the expected events. The
  manual Windows fixture can now hold an interactive window and logs raw
  platform events, but a reproducible recorded Japanese or Chinese IME result
  with candidate-window observation is still required. Clipboard, drag
  selection, rich candidate rendering and full bidi composition selection
  remain out of scope.
- Verdict: partially proven; continue to native OS IME validation.

### Stage 3 measurements

| validation | result |
| --- | --- |
| headless foundation tests | PASS |
| native SDL/D3D12 event-queue probe | 1 `TEXT_EDITING`, 1 `TEXT_INPUT` |
| preedit committed text mutation | none before commit |
| composition display command | present before commit |
| commit result | `NATIVE_TEXT_BASE + 世界` |
| focus-owned SDL lifecycle | start on focused field, caret-area update, clear/stop on shutdown |
| existing GPU stress | 303 submissions, 303 fence retirements, 3 frames in flight |

The native run remains a Windows Direct3D12 proof. Hosted macOS foundation CI
continues to compile and run the headless/native baseline, but this gate does
not claim a Metal IME or GPU-text execution result.

## GPU surface gate — retained high-frequency custom surface

### Research conclusions

Xilem's `Memoize` confirms the value of an explicit subtree-pruning boundary,
but its reactive dependency model does not fit Alicorn's ordinary Odin state
and explicit revision contract. GPUI's dirty-view set confirms that a separate
dirty frontier can wake a window without treating every retained view as dirty;
Alicorn transfers that work-queue idea without adopting GPUI entities or
observer notifications. SDL_GPU requires graphics pipelines to be bound inside
render passes, does not permit overlapping render/copy/compute passes, and
invalidates command-buffer use after submission. Those rules justify keeping
pass scheduling and submission in the Alicorn compositor while exposing no raw
SDL pass to application code.

Sources: [Xilem architecture](https://github.com/linebender/xilem/blob/main/xilem/ARCHITECTURE.md),
[GPUI window invalidation](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/window.rs),
[SDL render passes](https://wiki.libsdl.org/SDL3/SDL_BeginGPURenderPass),
[SDL copy passes](https://wiki.libsdl.org/SDL3/SDL_BeginGPUCopyPass), and
[SDL command buffers](https://wiki.libsdl.org/SDL3/SDL_AcquireGPUCommandBuffer).

### Claim: a high-frequency surface can update independently

- Implementation: `GPU_Surface_Context` records retained logical bounds,
  physical extent, DPI, effective clip and revision. `gpu_surface_update`
  copies samples into the retained `.Custom_Surface` node and sets a
  compositor-frame-pending bit without invalidating the procedural root.
  `native/sdl_gpu/surface.odin` owns a dedicated pipeline, sampler, 1×1 white
  texture, vertex buffer and transfer buffer, and encodes a scissored waveform
  render pass at the display-command position.
- Test: `test_gpu_surface_contract` verifies the context, copied data,
  surface-only frame wake, zero ordinary frame work, preservation across a
  later root wake, and rejection after surface retirement.
- Benchmark: the warmed headless loop performs 1,200 explicit updates with
  zero ordinary descriptions, reconciliation, layout, paint or composition
  visits and zero measured allocations. The Windows native surface stress runs
  1,200 revisions at 120 Hz pacing beside the retained text/button fixture.
- Result: the surface updates and uploads every revision while the surrounding
  procedural UI remains asleep; its five GPU resources are created once and
  three frames in flight remain bounded.
- Known limitations: native surface execution is proven on Windows Direct3D12
  only. The current API accepts copied waveform samples, not arbitrary shader
  callbacks, compute, multiple independent surfaces, variable-size resources,
  or a full visual readback assertion for waveform geometry.
- Verdict: proven for the measured explicit waveform surface; continue.

### GPU surface measurements

Starting SHA for this gate: `9af95f2301e8a9977a2dfad4dd972f25cbd3b06e`.
Ending SHA is recorded when the gate commits.

Environment: Windows host, Odin `dev-2026-09-nightly:a2fb372`, SDL 3.4.14,
Direct3D12, 2026-09-14.

| case | updates/frames | wall ns | encodes | vertex uploads | resources created | ordinary descriptions | reconcile | layout | paint | compose | allocations | max in flight |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| headless warmed surface locality | 1,200 / 1,200 | 5,152,600 | n/a | n/a | n/a | 0 | 0 | 0 | 0 | 0 | 0 | n/a |
| native Windows surface stress | 1,200 / 1,200 | 11,606,128,600 | 1,203 | 1,200 | 5 | 0 | 0 | 0 | 0 | 0 | n/a | 3 |

Native baseline after the change: 303 submissions, 303 retirements, no SDL
error, and the existing text readback remained positive. Reproducible
commands are `.\tools\check.ps1`, `.\tools\bench.ps1`,
`.\tools\native_sdl_gpu.ps1`, and
`.\tools\native_sdl_gpu.ps1 -SurfaceStress`.

### Allocation observations

The first implementation recorded one allocated trace string per surface
update. That was instrumentation overhead, not surface data ownership, so
high-frequency literal trace reasons now use the bounded trace ring without a
heap copy. After warming the retained sample capacity, the 1,200-update
headless loop reports zero allocator requests. The native path still performs
the expected per-frame transfer-buffer map/upload, while its pipeline, sampler,
texture, vertex buffer and transfer buffer are persistent.

## What was falsified or narrowed

- The old assumption that skipping a region body implied skipping retained
  subtree runtime work was false. Re-appending cached descendants was replaced
  by an explicit retained-subtree marker.
- “Unchanged” was not an idle benchmark. It was a forced root wake and is now
  named `root_invalidated_unchanged`.
- A full flat root wake remains proportional to the flat description size; the
  explicit-region contract is required for locality.
- Global flat composition is still necessary for structural order changes;
  text now preserves ordering within that list, but the renderer is not yet a
  batched retained display graph.
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
offscreen selection, semantic tree, reactive state graph, color glyph policy,
real OS IME telemetry, or platform-idle telemetry was added. The surface gate
also does not prove Metal/Vulkan execution or a general arbitrary-GPU API. The
visual check is a bounded offscreen readback rather than a full screenshot
corpus, and the native compositor remains a conservative per-item
rectangle/text/surface path.

## Decision

`CONTINUE`

The explicit retained surface path now demonstrates the central locality claim
for a high-frequency shader-backed waveform without a mandatory reactive
application model. The next gate may investigate broader shader-backed domain
drawing, but this foundation gate is complete for its stated scope.
