# Roadmap

## Foundation

- identity, reconciliation, invalidation, layout, input/focus;
- retained-subtree reuse proof: unchanged region bodies emit one reuse marker,
  local reconciliation visits only explicit frontier nodes, and subtree
  removal retires retained adjacency deterministically;
- retained display products and headless proof tests;
- SDL3/SDL_GPU boundary smoke and safe headless resource retirement;
- Runa-backed text loading, grapheme-safe editing, multiline metrics and
  wrapping, logical text runs, caret/selection geometry, and cluster hit testing;
- inspector, structural tracing, virtualized list and the eight-track Crucible.

## Scale

- logical item-key virtualization and fixed-height retained-work locality are
  now in foundation; variable-height rows,
  fractional scroll anchoring and offscreen selection storage remain here;
- [GPU text gate](gpu-text-gate.md): Runa rasterization → persistent alpha
  glyph atlas → SDL_GPU text is implemented and the Windows monochrome path is
  proven with a fence-signaled offscreen readback. Text Geometry Stage 2 now
  separates logical layout from DPI-specific residency and supplies basic
  caret/selection/hit-testing products; native committed editing, IME, color
  glyphs, broader screenshot proof and one shader-backed custom surface remain
  separately gated;
- broader native coverage on Windows, macOS and Linux;
- accessibility integration through a separate semantic adapter.

## Observability

- richer causality and performance timelines;
- semantic inspector and AccessKit projection.

## Experimental

- semantic LOD policies, QoS scheduling and richer custom surfaces.

## Research

- domain transactions, persistence/history, collaboration, AI interfaces,
  content-addressed runtime data and GPU-compute layout.

Research items are not silently promoted into foundation scope.
