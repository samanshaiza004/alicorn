# Issue #110: shape primitives and shape-aware input

**Status:** bounded prototype implemented; issue remains open for native visual, interaction, and performance acceptance.

## Research and decision

Issue [#110](https://github.com/samanshaiza004/alicorn/issues/110) asks for a small renderer-neutral visual vocabulary that lowers into Alicorn's existing retained paint stream, plus explicitly opted-in nonrectangular pointer targeting. It rules out a mandatory SDF renderer, a canvas or SVG editor, arbitrary shader graphs, and duplicating the backend comparison in [#104](https://github.com/samanshaiza004/alicorn/issues/104).

PanGui's [September 2026 update](https://pangui.io/blog/07-progress-update-september/) describes both shape drawing and SVG meshes, and uses shapes in instrument-cluster gauges. That is useful evidence that compact controls and gauges benefit from richer geometry. Alicorn's narrower prototype keeps its single semantic/layout tree and uses its existing `Geometry_Paint` path as the escape hatch for arbitrary geometry.

The chosen prototype is **Circle, Arc, and Cubic Bezier**. Circles cover concentric knobs and meter endpoints; open arcs cover gauges; cubic Bezier strokes cover curved connections. There is no new widget kind or second display tree. Shape metadata is retained with the existing semantic-surface style, while paint commands continue to carry only compact shape identifiers and owner IDs.

## Implemented contract

- `surface_shape_circle`, `surface_shape_arc`, and `surface_shape_cubic_bezier` describe normalized geometry through the semantic-surface API.
- Circle surfaces support fill and stroke placement. Arcs and Beziers are open centered strokes; their fill is ignored. Curved shapes require flat material, no gradient, and no backdrop effect.
- The SDL_GPU renderer expands these shapes into the existing solid-surface batch. Tessellation is derived from pixel extent and capped at 96 segments, with a 16 segment minimum for visible curves and a transparent subpixel fringe. Rectangles keep their existing flat six-vertex route.
- `button_begin(pointer_hit_shape=.Circle)` optionally restricts pointer hits to the inscribed circle of that Button's bounds. The ordinary rectangle remains the default. Child hit testing, keyboard interaction, focus, and accessibility bounds retain their existing behavior.
- Theme roles resolve shape fills through the normal semantic-surface path. Core roles use Alicorn's contrast adaptations; extension-role palettes remain the component author's responsibility in increased-contrast mode. Reduced-transparency makes role-derived fills opaque. Explicit stroke colors retain their authored alpha. These primitives do not animate, so reduced-motion mode adds no shape work. Components should draw a theme-resolved focus cue.
- Clipping and source-over blending use the existing solid renderer and parent clip. Stroke and antialias outsets are included in visibility bounds. No additional texture, shader, render pass, or idle scheduler was added.

The [Shape Primitives example](../../examples/14_shape_primitives/README.md) demonstrates a concentric Gain control with circular pointer targeting, an output-meter arc, and a curved signal cable.

## Validation recorded

On macOS with Odin `dev-2026-11:9a6991685` and the repository-pinned AccessKit dependency:

- `odin check runtime -no-entry-point -collection:alicorn=.` — passed.
- `odin check native/sdl_gpu -no-entry-point` with the pinned `accesskit` and `accesskit_c` collections — passed. Odin emitted existing large-stack warnings from `secondary_window_host_test.odin`.
- Built `examples/14_shape_primitives` with the repository's AccessKit linker flags — passed; the linker reported a duplicate `-lobjc` warning.

These are compile checks, not GPU visual-readback or performance results. No automated tests were run for this prototype.

## Acceptance still required before closing #110

The issue's GO decision requires evidence beyond successful compilation. Still needed:

1. Run the example and compare the knob, arc, and Bezier readbacks with their prior/custom-geometry equivalents at 1×, 1.25×, 1.5×, and 2× scales, including partial clipping and overlapping translucent strokes.
2. Confirm pointer pass-through outside the knob circle, plus keyboard activation and accessible rectangular focus bounds on macOS and Windows.
3. Record authored LOC, generated vertex/upload counts, draw calls, CPU and GPU latency distributions, binary-size change, and idle work on representative integrated and stronger GPUs.
4. Compare the prototype against `Geometry_Paint`; do not repeat #104's SDF backend benchmark here.

The feature is therefore a usable API/rendering prototype, not a claim that the full performance and physical-acceptance gate has passed.
