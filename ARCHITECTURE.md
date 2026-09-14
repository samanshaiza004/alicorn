# Implemented architecture

## Pipeline

Application code calls the small `runtime.UI` emission API during an invalidated
frame. Descriptions live only in `Runtime.pending`; `end_frame` reconciles them
into the retained `map[Node_ID]^Node`. Pending data contains either an explicit
description or a `Reuse_Subtree(Node_ID)` marker. Layout, retained paint
commands and the composition list are then updated from retained nodes.

An idle frame does not enter description execution at all. A root invalidation
is explicit. A region invalidation currently uses the same wake-up mechanism,
but its revision controls whether the region body is executed.

## Identity

An ID is the FNV-1a hash of the parent identity scope, source site and optional
explicit key. `key_scope` contributes a scope component without creating a
widget node. Emitted containers contribute a retained node component and also
become the retained hierarchy parent. See `IDENTITY.md`.

Source-site strings remain available for deterministic tests and low-level
adapters, but public emission calls can omit them. Omitted sites are
constructed from Odin `#caller_location`; reusable helpers use
`component_begin/end` to add an invocation scope at the actual call site.
Source location alone is still not enough to identify repeated data.

## Reconciliation and invalidation

Each retained node tracks description, layout, paint and composite dirtiness,
plus the reason recorded for the latest invalidation. It owns an ordered
`children` array, and the runtime owns a retained `top_level` list. Reconcile
updates only the direct child list of explicitly described parents. A reuse
marker makes its region root an atomic reconciliation unit; descendants remain
present through retained adjacency and are not copied into pending data.

When structure changes, `order` is rebuilt by traversing retained adjacency.
When structure does not change, the flattened order is retained. Removing a
parent calls `retire_subtree` and deterministically releases its descendants,
interaction state and display resources; descendants do not need to fail a
global frame-wide `seen` scan.

Description, layout, paint and composition are separate stages. A changed
description compares layout and paint hashes independently. A reused
description can still be laid out again when incoming constraints change.
Paint and composition use queues for changed nodes; a structural display-list
rebuild remains necessary for order changes in the current flat compositor.
The counters `reconcile_nodes_visited`, `layout_nodes_visited`,
`paint_nodes_visited` and `composition_nodes_visited` make these boundaries
inspectable.

## Ownership

Retained nodes contain runtime-owned identity metadata, interaction state,
geometry, display commands and textual copies. Text-field
caret and selection offsets are byte positions normalized to Runa UAX #29
grapheme boundaries. They do not
contain `rawptr`, `^T` application pointers or closures. The application must
copy a text-edit result into its own ordinary state before the next frame.

`Runtime.text_engine` owns cloned font bytes, the parsed Runa font, a shape
cache, an atlas and a glyph cache. Each retained text node owns one
platform-neutral `Text_Run`; it is rebuilt only when the node's text/layout
inputs or the font generation require it. `Text_Run` copies glyph IDs,
clusters, advances, offsets and atlas slots out of Runa's temporary paragraph
lines; it never retains Runa's non-owning font pointer. `Glyph_Resource_Key`
contains font generation, raster size, subpixel bucket, hinting and color-page
policy. CPU atlas page identity is separate from GPU texture residency. The
SDL adapter consumes node-owned runs and has no historical run cache of its
own, so virtualized node retirement also bounds text-product retention.

## Regions and explicit invalidation

`region(key, revision)` is an explicit trust boundary. If the same retained
region identity is emitted with the same revision, the body is not called and
the pending stream receives one `Reuse_Subtree` marker. The application must
increment the revision when the region's logical contents change; if it lies,
stale content may be reused. Alicorn does not observe arbitrary Odin memory.

Region reuse preserves the retained subtree's Node_IDs, interaction state,
layout/paint caches, GPU references and inspector identity. It does not promise
that layout is skipped: changed parent constraints may walk retained
descendants without rerunning the application description. Region removal is
structural and retires the complete retained subtree.

## Input and focus

Hit testing walks the retained order backwards and requires both bounds and the
effective retained clip rectangle. Pointer down captures one retained node,
assigns the single `Runtime.focused` owner when focusable, and sets its pressed
state. Pointer up activates only when it hits the captured node; releasing
outside cancels. Activation carries a monotonic event sequence and is consumed
by the matching button exactly once; hover, capture and pressed state are
interaction state, separate from frame presence.
When the focused node disappears, the nearest active focusable ancestor is
chosen, otherwise the first active focusable node in retained order is chosen.

Virtual lists require an item-key callback. The visible range is fixed-height
and bounded to the viewport; row identity follows the callback's logical key,
not the row's viewport index. Fractional scroll offset and persistent offscreen
selection storage remain future scale work.

## GPU boundary

`runtime.GPU_Backend` is a platform-neutral lifetime model: command buffers
cannot be used after submit, and submitted resource references retire only after
an observed fence. `native/sdl_gpu` documents the SDL3 mapping. The native
adapter keeps one GPU texture per Runa atlas page and rewrites a complete page
when cycling a texture; this is conservative but preserves old glyph pixels
when new glyphs arrive. SDL transfer buffers are cycled for staging, while
dirty-page acknowledgement happens only after command submission. Text meshes
are rebuilt from an ordered display fingerprint that includes node identity,
text, color, bounds, clip, ordering and DPI scale, so removal/reorder/color
changes cannot leave stale vertices. Text is rendered at its display-list
position in a load-preserving pass with a per-command scissor, preserving basic
z-order and clipping. Atlas/vertex resources are released after the final
device-idle wait. The shader artifacts are checked-in DXIL, MSL and SPIR-V
outputs derived from SDL_ttf's GPU-text example. A native offscreen download
probe verifies glyph coverage in the expected bounds.
