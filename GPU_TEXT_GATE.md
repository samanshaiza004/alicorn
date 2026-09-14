# GPU text gate

This document is the researched implementation and proof plan for Alicorn's
next foundation gate. It is deliberately a plan, not a claim that GPU glyph
rendering is already implemented.

Research checked against the vendored Runa sources and the current SDL3 wiki
on 2026-09-14. The gate must use the versions recorded in
[`DEPENDENCIES.md`](DEPENDENCIES.md) and re-verify them at implementation
time.

## Gate question

Can a shaped Runa glyph become a persistent Alicorn-owned GPU resource and a
retained text display command without rebuilding, reshaping or uploading
unrelated UI?

The first proof path is:

```text
Runa shaped glyph
    ↓ cache lookup
Runa raster_glyph on a miss
    ↓ atlas slot and dirty page
GPU atlas page allocation
    ↓ transfer buffer + copy pass
SDL_GPU texture upload
    ↓ retained glyph-run display command
text shader/pipeline
    ↓ render pass
swapchain
```

The gate then extends that path to a real editable field, SDL text input/IME,
and one shader-backed custom surface. The sequence is intentionally narrow:
it proves the resource seam before adding editor behavior or a generalized
graphics API.

## Current repository seams and constraints

The current code already provides useful boundaries:

- `runtime/text.odin` owns cloned font bytes, parsed Runa fonts, a bounded
  shape cache, GUI-facing layout metrics and grapheme boundary helpers;
- the native SDL3 path owns command-buffer/render-pass lifetime, swapchain
  composition and deferred retirement, but currently draws retained rectangles;
- the retained runtime can preserve paint/display products independently of
  application description execution;
- the current Runa vendor commit is
  `4dd00c541c374938b192e23dc2efa983748a92ab`, recorded as the 1.3.1 line in
  [`DEPENDENCIES.md`](DEPENDENCIES.md).

Runa's public facade exposes `raster_glyph`, `Atlas`, `Atlas_Slot`, dirty-page
tracking and `atlas_flush_dirty`. The current vendored atlas implementation
stores page pixels, page format and slot fields in package-private fields,
however. Alicorn must not reach into those private fields by accident. Before
GPU integration, choose one of these narrow seams:

1. Preferred: add Runa facade accessors returning an immutable page/slot view
   and dirty-page pixel span, preserving Runa's atlas ownership and allowing
   incremental dirty-rectangle uploads.
2. Alternative: add a Runa API that rasterizes into an Alicorn-provided
   bitmap/slot sink, keeping the GUI independent of the Runa atlas allocator.

Do not duplicate the rasterizer or expose the entire internal atlas structure
as Alicorn's text API. The adapter should translate Runa output into
Alicorn-owned `Glyph_Atlas_Page`, `Glyph_Slot` and `Glyph_Run` data.

## Research findings

### Runa

The vendored Runa API provides:

- `shape_text`/paragraph layout with positioned glyph IDs, advances, offsets
  and source clusters;
- UAX #29 grapheme iterators returning UTF-8 byte ranges;
- `raster_glyph(font, gid, size, subpx_x, atlas, ...)`, which packs monochrome
  glyphs into alpha pages and color glyphs into RGBA pages;
- dirty bounding boxes per atlas page so a consumer can upload only changed
  regions.

Those are the right primitives for Alicorn. The GUI must still own the cache
key policy, GPU texture resources, display-command lifetime, caret geometry,
selection geometry and input routing. Runa's API reference and source are the
authoritative details: [Runa API](https://github.com/BuLEEto/Runa/blob/main/API.md),
[Runa facade](https://github.com/BuLEEto/Runa/blob/main/runa.odin), and
[Runa atlas implementation](https://github.com/BuLEEto/Runa/blob/main/raster/atlas.odin).

Close these adapter hazards before relying on the API:

- `atlas_flush_dirty` currently returns dirty rectangles and clears the page's
  dirty bit in the same call. Prefer a peek/ack split, or retain a pending
  upload until transfer encoding and submission have succeeded, so a failed
  upload is retryable.
- Empty glyphs such as spaces may have advances but no drawable bitmap. The
  retained run must preserve their metrics without inventing a zero-size GPU
  slot.
- `Paragraph_Glyph.font` is a non-owning pointer into the caller's font stack.
  Retained glyph runs must copy a stable Alicorn font/resource identity rather
  than retain that pointer.
- `text_engine_load_font` destroys the old parsed font and shape cache. A glyph
  cache must be invalidated or generation-tagged at the same boundary.
- The current GUI text path uses a fixed size of 16. Stage 1 must explicitly
  choose logical-size versus physical-pixel rasterization and include the
  resulting size/DPI policy in the resource key.
- Verify language/script inputs against the exact vendored Runa cache behavior
  before treating language-sensitive shaping as a cache-safe feature.

### SDL_GPU upload and lifetime

SDL_GPU's intended upload path matches the required ownership model:

- create/map a transfer buffer, copy CPU pixels into it, then unmap before
  encoding upload commands;
- begin one copy pass, call `SDL_UploadToGPUTexture` for a texture region, and
  end the copy pass;
- the upload executes on the GPU timeline. Alicorn must not reuse upload memory
  unsafely; it may explicitly retain a transfer buffer, use SDL's cycling
  behavior, or release the SDL handle after encoding and rely on SDL's
  documented safe-release semantics;
- submitting with `SDL_SubmitGPUCommandBufferAndAcquireFence` makes the command
  buffer unusable and returns a fence that must eventually be released.

Relevant primary references are [SDL_CreateGPUTransferBuffer](https://wiki.libsdl.org/SDL3/SDL_CreateGPUTransferBuffer),
[SDL_MapGPUTransferBuffer](https://wiki.libsdl.org/SDL3/SDL_MapGPUTransferBuffer),
[SDL_BeginGPUCopyPass](https://wiki.libsdl.org/SDL3/SDL_BeginGPUCopyPass),
[SDL_UploadToGPUTexture](https://wiki.libsdl.org/SDL3/SDL_UploadToGPUTexture),
[SDL_CreateGPUTexture](https://wiki.libsdl.org/SDL3/SDL_CreateGPUTexture),
[SDL_SubmitGPUCommandBufferAndAcquireFence](https://wiki.libsdl.org/SDL3/SDL_SubmitGPUCommandBufferAndAcquireFence),
and [SDL_QueryGPUFence](https://wiki.libsdl.org/SDL3/SDL_QueryGPUFence).

Start with an alpha coverage texture for monochrome glyphs. Check
`SDL_GPUTextureSupportsFormat` for `R8_UNORM` with sampler usage at device
startup; keep an `R8G8B8A8_UNORM` fallback only if a target actually requires
it. Color glyphs are a separate later case because they need an RGBA page and
a color sampling path. SDL documents the format query at
[SDL_GPUTextureSupportsFormat](https://wiki.libsdl.org/SDL3/SDL_GPUTextureSupportsFormat)
and the texture format set in the [SDL GPU header](https://github.com/libsdl-org/SDL/blob/main/include/SDL3/SDL_gpu.h).

### SDL_GPU shaders

SDL_GPU does not imply one portable shader binary. A device reports supported
shader formats through `SDL_GetGPUShaderFormats`; the current SDL formats
include SPIR-V, DXBC/DXIL, MSL and Metallib. `SDL_CreateGPUShader` also
requires resource bindings to follow backend-specific conventions.

The gate must therefore make shader artifacts reproducible rather than hiding
that problem in runtime string compilation. The first implementation should
select a checked-in or deterministically generated shader artifact matching the
device format, and fail with an actionable diagnostic if no supported artifact
exists. Record the compiler/tool versions and the vertex/fragment resource
layout in the repository.

References: [SDL_GetGPUShaderFormats](https://wiki.libsdl.org/SDL3/SDL_GetGPUShaderFormats),
[SDL_GPUShaderFormat](https://wiki.libsdl.org/SDL3/SDL_GPUShaderFormat),
[SDL_CreateGPUShader](https://wiki.libsdl.org/SDL3/SDL_CreateGPUShader), and
[SDL_CreateGPUGraphicsPipeline](https://wiki.libsdl.org/SDL3/SDL_CreateGPUGraphicsPipeline).

SDL's [SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross) is a
candidate build-time translator for a small HLSL source pair. It should be
adopted only with a pinned tool revision and recorded output formats; runtime
shader-source compilation is not a substitute for reproducible artifacts.

### SDL text input and IME

SDL3 text input is window-specific and is not enabled by default. The native
adapter should call `SDL_StartTextInput` only while a field owns focus, consume
`SDL_EVENT_TEXT_INPUT` for committed UTF-8 text, and keep
`SDL_EVENT_TEXT_EDITING` as transient composition state. The caret's window
coordinate is supplied through `SDL_SetTextInputArea`, allowing native
candidate UI to appear near the active insertion point.

References: [SDL_StartTextInput](https://wiki.libsdl.org/SDL3/SDL_StartTextInput),
[SDL_SetTextInputArea](https://wiki.libsdl.org/SDL3/SDL_SetTextInputArea),
[SDL_Event](https://wiki.libsdl.org/SDL3/SDL_Event), and
[SDL Best Keyboard Practices](https://wiki.libsdl.org/SDL3/BestKeyboardPractices).

## Chosen architecture

### 0. Lock the measurement and ownership interfaces

Before changing rendering, add explicit counters and debug records for:

```text
shape_calls
shape_cache_hits
raster_calls
glyph_cache_hits
atlas_pages_created
atlas_dirty_rects_uploaded
transfer_bytes_uploaded
text_display_commands
text_quads_submitted
text_nodes_painted
text_nodes_composited
staging_buffers_created/retired
atlas_textures_created/retired
```

All counters are per-frame and cumulative where useful. The inspector should
be able to answer which text node caused a glyph miss and which atlas page it
uses. No counter may claim that domain data changed; only runtime events and
explicit invalidations are traced.

Define GUI-facing types conceptually like:

```text
Font_Handle
Glyph_Resource_Key = font face + variation state + pixel size + glyph ID
                    + subpixel bucket + raster flags
Glyph_Slot = atlas page + UV rectangle + pixel size + bearing + color flag
Glyph_Run = retained placements + cluster map + atlas slot references
```

The key must include every parameter that changes raster output. A font handle
must identify runtime-owned font bytes/face state, not an application pointer.

Keep CPU atlas identity separate from GPU residency identity:

```text
Glyph_Atlas_Page_ID
    ↓
CPU/Runa page state
    ↓
GPU residency record
    texture handle
    uploaded generation
    dirty generation
```

The first useful invariant is `cpu_generation == gpu_generation` after the
upload for a page. A later device recreation, page replacement or cache policy
can then invalidate GPU residency without changing the logical glyph resource
identity. A Runa page number must never be treated as an `SDL_GPUTexture *`.

### 1. Runa rasterization to a persistent GPU atlas

Implement this first and stop for a proof review before adding IME.

1. Add the narrow Runa page/slot view seam described above.
2. Create an Alicorn glyph cache keyed by `Glyph_Resource_Key`.
3. On a miss, call Runa's `raster_glyph`; record the returned slot and page
   format. On a hit, do not call the rasterizer.
4. Create persistent SDL_GPU atlas textures per page. Do not recreate them per
   frame. Page dimensions are fixed for the first gate; use page growth rather
   than eviction so lifetime behavior is easy to prove.
5. Stage uploads as three proofs: (A) upload a persistent page and draw one
   glyph correctly, (B) upload only the dirty rectangle, and (C) batch multiple
   dirty rectangles/pages where measurement justifies it. Do not make batching
   a prerequisite for the first visible-glyph proof. Account for backend
   alignment and measure whether SDL inserts an internal copy for a tightly
   packed dirty rectangle.
6. After unmapping, do not access the mapped transfer pointer. Choose staging
   lifetime explicitly: retain the SDL handle behind the existing fence, or
   release it after encoding and rely on SDL's safe-release/cycling semantics.
   The invariant is that upload memory is never reused unsafely; manual fence
   retention is not mandatory. Keep atlas textures alive while any retained
   glyph display command may reference them. Replace or retire pages only
   through the existing deferred-retirement mechanism.
7. Add a minimal glyph vertex format containing destination position, UV,
   color and page/type selection. Retained text paint stores glyph placements
   and page references; composition binds the atlas texture and samples it in a
   shader pipeline.
8. Preserve the existing rectangle compositor and custom-surface seam. Text is
   an additional retained display command, not a replacement platform layer.

The first monochrome pipeline should use alpha coverage multiplied by the
requested text color. RGBA color glyphs can be admitted only after the alpha
path's proof is green; they should use a distinct atlas page type and shader
sampling rule.

### 2. Native editable field

Once glyphs are visible, make the existing field genuinely usable:

- retain a caret and selection as grapheme-boundary byte offsets;
- derive caret x/y and selection rectangles from shaped line/cluster data;
- map pointer coordinates to the nearest visual caret boundary;
- implement logical movement by grapheme boundaries and visual movement by
  line geometry;
- support insertion, deletion, selection replacement and clipboard through a
  runtime-owned edit operation/result;
- invalidate only the field's text/caret/selection paint products, not the
  surrounding application;
- keep the application buffer ordinary Odin state and never retain its pointer
  in a node.

Tests must cover ASCII, combining marks, emoji ZWJ sequences, CJK, RTL text,
ligatures and wrapped/multiline fields. A field that merely avoids splitting
UTF-8 bytes is not enough; caret and selection behavior must be defined at
grapheme/cluster boundaries.

### 3. SDL text input and IME

Add a platform adapter around the canonical focused text field:

1. Start SDL text input when the field gains native focus; stop it when focus
   leaves or the window closes.
2. Convert committed `SDL_EVENT_TEXT_INPUT` UTF-8 into a text edit operation at
   the current selection.
3. Store `SDL_EVENT_TEXT_EDITING` text, composition cursor and selection as
   transient retained field state. Do not commit it to application state until
   SDL sends committed text.
4. Recompute the caret rectangle after layout and call
   `SDL_SetTextInputArea` on the main thread with window coordinates.
5. Define deterministic behavior when the field is hidden, its region is
   reused, focus changes, or its subtree is retired: stop input and clear
   composition before routing to the next owner.

The headless input model should be testable without an IME. Native smoke tests
must verify committed text, composition replacement, focus loss and caret-area
updates where the host platform exposes them.

### 4. One shader-backed custom surface

Only after the text path is stable, add one real custom surface such as an
animated process graph or waveform. It receives the existing surface contract:

```text
logical bounds
pixel bounds
DPI scale
clip
frame information
```

The runtime schedules its command recording and owns pipeline/buffer lifetime.
The surface updates continuously while unchanged controls keep their retained
text/layout/paint products. This proves that a custom pipeline and a glyph
pipeline can coexist without turning the whole window into one application
rebuild.

## Proof matrix

### Glyph/resource reuse

| scenario | expected evidence |
| --- | --- |
| unchanged text, repeated frames | no new shaping, rasterization, atlas upload or text paint |
| changed color/position, same text | no rasterization/upload; only the necessary paint/composition work |
| changed text using existing glyphs | shape/layout as required; glyph cache hits; zero new raster/upload for existing glyphs |
| one new glyph | one glyph miss/raster result and one affected dirty upload, subject to page creation |
| same text, changed font size | shape/layout as required; new size-specific glyph keys miss; old slots remain valid until policy retirement |
| same text, changed variable-font axis | shape/layout and glyph keys change with the variation generation; no stale pixels from the prior instance |
| repeated new glyphs in one frame | raster misses equal unique resource keys; uploads are bounded by dirty pages/rectangles |
| atlas survives many frames | same page/slot identity and no re-upload when content is unchanged |
| page replacement or shutdown | no use-after-free; resource retirement waits for a signaled fence |

### Retained-work locality

Run a 10,000-node application with one text node in one explicit region:

- changing an unrelated region must not shape, rasterize, paint or upload the
  text node;
- changing the text region must not rebuild unrelated regions;
- a root wake with unchanged text is measured separately and may remain O(N);
- counters must identify the changed node and the exact cache decision.

### Editable field

Use deterministic headless snapshots for:

- caret and selection geometry on single-line and wrapped text;
- mouse hit testing at cluster boundaries;
- grapheme-safe Backspace/Delete and logical/visual movement;
- focus insertion/removal/reorder and region reuse/removal;
- committed input versus transient composition.

### Native/GPU stress

Run the existing Windows and macOS native fixtures, then stress:

- repeated text changes and atlas misses;
- window resize and DPI changes;
- hide/show and region retirement;
- rapid field focus changes;
- custom-surface animation beside unchanged text;
- enough frames to exercise three in-flight submissions and delayed fences.

No command buffer may be used after submission. No transfer buffer, atlas page
or pipeline may be destroyed while in-flight. Resource counts must plateau in a
bounded workload.

## Benchmark commands and raw reporting

Add a dedicated headless text benchmark rather than folding it into the old
retained-work rows. It should print:

```text
environment and compiler
font identity and size
text case and UTF-8 byte length
shape calls / cache hits
raster calls / glyph cache hits
atlas pages and dirty rectangles
uploaded bytes and transfer-buffer allocations
text paint/composition visits
wall time
```

The native fixture should print the same counters plus GPU submissions, fences,
pages created/retired and peak in-flight resources. Publish raw values in
`PROOF.md`; do not convert one machine's timing into a universal threshold.

Reproducible commands should be:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check.ps1
powershell -ExecutionPolicy Bypass -File tools/bench.ps1
ALICORN_NATIVE_GPU=1 powershell -ExecutionPolicy Bypass -File tools/native_sdl_gpu.ps1
```

If the last command does not exist yet, add the smallest platform-specific
wrapper that matches the current native fixture rather than hiding native work
inside headless tests.

## Failure conditions

The gate is not green if any of these occur:

- unchanged text reshapes, rerasterizes or reuploads without a relevant
  invalidation;
- a new glyph forces all text nodes or the whole window to repaint;
- a glyph key omits a raster parameter and displays stale pixels;
- the runtime retains an application buffer pointer to make editing work;
- a reused region loses glyph-run, caret, focus or selection state;
- atlas or pipeline resources are freed before their fence, or a transfer
  buffer is released/reused in a way that violates SDL's safe-release and
  cycling semantics;
- page growth or replacement leaks resources over repeated stress cycles;
- cluster mapping cannot support deterministic caret/selection behavior;
- the shader artifact path is not reproducible on a supported SDL_GPU backend;
- the custom surface forces unrelated text/layout work;
- native behavior passes only because a headless fake bypasses the SDL path.

If Runa's current public surface cannot provide safe page pixel/slot access,
record a minimal upstream API issue/reproduction and either add the narrow
accessor or revise the adapter. Do not copy Runa's Unicode/rasterization
implementation into Alicorn to conceal an API mismatch.

## Alternatives rejected

### Re-rasterize every frame

Rejected because it destroys the retained GPU resource thesis and makes text
cost scale with visible text even when nothing changed.

### Store Runa's atlas as Alicorn's public text model

Rejected because it couples GUI lifetime and display commands to an internal
third-party atlas representation. Runa is the text engine; Alicorn owns GUI
resource policy.

### Upload one texture per glyph

Rejected for the first path because it multiplies bindings and resource
lifetime. Persistent pages with dirty-region uploads match Runa's existing
allocator and the expected GPU workload.

### Runtime shader source compilation as the only path

Rejected as a hidden portability dependency. SDL_GPU reports backend-specific
formats and requires binding conventions; artifacts and tool versions must be
explicit.

### Make text editing a separate widget-object subsystem

Rejected because editing is an interaction capability of a retained node, not
an excuse to move application state into a second ownership model.

## Gate review and decision

At completion, update `PROOF.md` with:

- the exact starting and ending SHAs;
- the Runa API seam chosen and why;
- headless and native test commands;
- benchmark tables and raw environment information;
- allocation and resource-retirement observations;
- known limitations and any falsified assumptions.

Choose exactly one:

```text
CONTINUE — the persistent glyph path and native editing prerequisites are
credible enough to proceed to broader text/IME work.

REVISE — the direction is credible, but the resource, cluster, shader or
platform seam needs architectural changes.

STOP — the required GPU text behavior cannot be achieved without violating
ordinary Odin state, explicit invalidation or safe retained ownership.
```

If the first stage passes, stop and review the evidence before beginning the
next stage. The recommended order remains:

```text
Runa raster → GPU glyph atlas → SDL_GPU text
native caret/selection field
SDL text input and IME
one shader-backed custom surface
```
