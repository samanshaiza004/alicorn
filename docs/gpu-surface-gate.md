# GPU surface gate

## Question

Can a high-frequency, shader-backed application surface update inside Alicorn
while ordinary retained UI around it stays asleep?

This gate is intentionally smaller than a graphics framework. It proves one
specialized surface primitive, not arbitrary application command recording,
compute, or a general scene graph.

## Research

Xilem's `Memoize` is a pruning boundary: when declared inputs are unchanged,
the memoized view subtree is not constructed or rebuilt. The useful lesson for
Alicorn is subtree pruning. Xilem's reactive dependency model is deliberately
not transferred; Alicorn keeps explicit revisions and ordinary Odin state.
See [Xilem's architecture](https://github.com/linebender/xilem/blob/main/xilem/ARCHITECTURE.md).

GPUI tracks dirty views in a separate set and wakes the window when a view is
invalidated. That is a useful precedent for an explicit dirty frontier and
specialized GPU element. Alicorn does not adopt GPUI's entity/observer model:
the application must explicitly update a surface handle. See [GPUI window
invalidation](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/window.rs).

SDL_GPU makes the backend boundary concrete. Graphics pipelines are bound
inside render passes, copy and compute passes cannot overlap a render pass, and
a command buffer is no longer usable after submission. See [SDL render
passes](https://wiki.libsdl.org/SDL3/SDL_BeginGPURenderPass), [SDL copy
passes](https://wiki.libsdl.org/SDL3/SDL_BeginGPUCopyPass), and [SDL command
buffers](https://wiki.libsdl.org/SDL3/SDL_AcquireGPUCommandBuffer).

The transferable conclusion is simple: applications describe surface data;
the Alicorn compositor decides when and where GPU work is encoded.

## Contract

The public runtime contract is split into two operations:

```odin
surface := ui.gpu_surface(
    "cpu-history", revision,
    logical_bounds, pixel_width, pixel_height, dpi_scale,
)

alicorn.gpu_surface_update(&rt, surface, next_revision, samples)
```

The description call creates or updates the retained placement. It carries
logical bounds, physical extent, DPI, stable identity, and the initial
revision. The explicit update call copies sample data into runtime-owned
storage and marks only the compositor frame pending. It does not invalidate
the procedural root and does not retain the caller's slice or any application
pointer.

`gpu_surface_context` exposes the backend-neutral context:

```text
logical bounds, pixel width/height, DPI scale, effective clip, revision
```

`gpu_surface_needs_frame` and `gpu_surface_frame_consumed` make scheduling
observable without introducing a QoS or reactive system.

### Retained typed geometry

The waveform API above remains unchanged. A second constructor provides a
layout-resolved surface for small retained 2D geometry:

```odin
surface := alicorn.gpu_geometry_surface(
    &ui,
    "commit-dag",
    revision,
    alicorn.layout_style(grow=1, clip=true),
    dpi_scale,
)

segments := [1]alicorn.GPU_Surface_Line_Segment{{
	start={4, 8}, end={28, 20}, thickness=2, color={0.3, 0.8, 1, 1},
}}
circles := [1]alicorn.GPU_Surface_Filled_Circle{{
	center={28, 20}, radius=4, color={1, 0.7, 0.2, 1},
}}
alicorn.gpu_surface_update_geometry(&rt, surface, next_revision, segments[:], circles[:])
```

`Layout_Style` determines the surface's retained bounds and clipping through
ordinary Alicorn layout; applications do not supply viewport coordinates.
Points, thicknesses, and radii are logical units local to those resolved
bounds. `gpu_surface_context` reports those bounds and derives physical pixel
extent from layout size and DPI for geometry surfaces. Geometry surfaces are
transparent by default: the renderer emits no backing quad, making the surface
suitable as an overlay/gutter alongside ordinary UI. The original waveform
surface retains its dark background.

The runtime copies both typed slices with its persistent allocator. The update
is atomic and revisioned: invalid geometry, a repeated revision, or geometry
that would exceed the shared `GPU_SURFACE_MAX_VERTICES` limit (8,192 vertices)
returns `false` and leaves the previous payload intact. Geometry surfaces are
transparent and consume no background vertices; the waveform background quad
remains within the same backend buffer budget.
Segments use six vertices; circles use deterministic 16-triangle fans. Colors
are normalized RGBA, and thickness/radius must be positive. The SDL_GPU backend
draws these triangles through the existing surface pipeline, display ordering,
effective scissor, and frame scheduling; application code receives no GPU
callback or command buffer.

## Chosen implementation

The first backend surface is a 512-sample waveform. The retained node owns
the copied samples and revision. The native adapter owns a dedicated graphics
pipeline, 1×1 white texture, sampler, vertex buffer and transfer buffer.

The surface reuses the proven text shader artifact format because that shader
already accepts position, color, UV, and a projection uniform. A white texture
turns that textured-color pipeline into a small colored-triangle surface
without adding a shader compiler or a second artifact toolchain to the
foundation gate. The surface still owns a separate pipeline and buffers, so
its residency and upload counters are independent of text.

The geometry payload shares this pipeline and buffer budget while retaining
its own typed runtime-owned segments/circles. It does not alter waveform
updates or introduce a general-purpose scene graph.

The compositor keeps display order. A surface is encoded at its display-list
position in a load-preserving render pass with an effective scissor. The
runtime never gives application code a raw `SDL_GPURenderPass *` or command
buffer.

## Invariants

- A surface update is explicit and revisioned.
- Sample slices are copied before the update returns.
- Geometry slices are copied before the update returns and released when the
  retained node is retired or the runtime is destroyed.
- Geometry overflow rejects the complete revision without truncation or a
  partially rendered primitive.
- A surface-only update does not execute `begin_frame`'s application
  description, reconciliation, layout, paint, or display-list rebuild.
- A later root wake with the same surface description does not roll back a
  newer explicit surface revision.
- Removing the retained surface retires its copied samples with the node.
- The native renderer creates its pipeline, sampler, white texture, vertex
  buffer, and transfer buffer once per renderer. It updates vertex contents
  with a cycling transfer/upload path, never by destroying an in-flight
  buffer.
- The surface render pass clamps its scissor to the effective retained clip.
- Submission remains bounded by SDL's three allowed frames in flight.

## Proof commands

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\check.ps1
powershell -ExecutionPolicy Bypass -File .\tools\bench.ps1
powershell -ExecutionPolicy Bypass -File .\tools\native_sdl_gpu.ps1
powershell -ExecutionPolicy Bypass -File .\tools\native_sdl_gpu.ps1 -SurfaceStress
powershell -ExecutionPolicy Bypass -File .\tools\native_sdl_gpu.ps1 -SurfaceGeometryTest
```

`-SurfaceStress` runs 1,200 surface revisions (120 Hz for ten seconds at the
fixture's pacing), pre-fills three in-flight submissions from the already
retained display list, and prints ordinary runtime visits separately from
surface encoding/upload counters.

## Measured result

Environment: Windows host, Odin `dev-2026-09-nightly:a2fb372`, SDL 3.4.14,
Direct3D12, 2026-09-14. The warmed headless update loop reported:

```text
surface_locality_1200_updates
wall_ns 5152600
surface_updates 1200
surface_frames_consumed 1200
ordinary_emit 0
ordinary_reconcile 0
ordinary_layout 0
ordinary_paint 0
ordinary_compose 0
alloc 0
alloc_bytes 0
retained 2
```

The native stress reported:

```text
surface_stress frames 1200
wall_ns 11606128600
surface_updates 1200
surface_frames_consumed 1200
surface_encodes 1203
surface_vertex_uploads 1200
surface_resource_creations 5
ordinary_descriptions 0
ordinary_reconcile_visits 0
ordinary_layout_visits 0
ordinary_paint_visits 0
ordinary_composition_visits 0
max_frames_in_flight 3
```

The three extra surface encodes are the in-flight prefill; vertex uploads match
the 1,200 changed revisions. The one-time readback upload is excluded from
these deltas. Resource creation stayed at five. The ordinary counters are
measured after the initial input probe and one-time retained UI settle.
The regular native validation also completed 303 submissions with 303 fence
retirements and no SDL error.

## What this proves

For the measured single-surface Windows Direct3D12 path, a high-frequency
surface can update and submit without re-running surrounding application
description, reconciliation, layout, paint, or composition work. Surface
vertex data is uploaded per revision while surface GPU resources remain
persistent and frames in flight remain bounded.

## What it does not prove

- Metal or Vulkan execution of the new surface path.
- General application-provided shader callbacks or arbitrary GPU resources.
- Compute, uploads requested by an application surface, or multi-surface
  scheduling.
- Non-waveform geometry or variable-size resource growth.
- A full screenshot/readback proof of waveform geometry; the existing native
  readback still proves text coverage, while the surface stress proves the
  actual shader render path through successful native submissions.
- A sophisticated scheduler. The update API is explicit and single-threaded.

## Decision

**CONTINUE** — the explicit retained surface direction provides the required
locality for the measured high-frequency waveform without introducing a
mandatory reactive application model. The next feature gate may investigate
real shader-backed domain drawing, but this proof should stop here rather than
turning into a graphics framework.
