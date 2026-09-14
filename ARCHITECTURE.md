# Implemented architecture

## Pipeline

Application code calls the small `runtime.UI` emission API during an invalidated
frame. Descriptions live only in `Runtime.pending`; `end_frame` reconciles them
into the retained `map[Node_ID]^Node`. Layout, retained paint commands and the
composition list are then updated from retained nodes.

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
plus the reason recorded for the latest invalidation. It also owns an ordered
`children` array. Reconciliation hashes pending parent/order membership and
rebuilds this adjacency only when that structure changes; layout never scans
the global retained order to discover children. Dirty layout is propagated
through ancestors so clean subtrees can be skipped. A changed description
does not automatically imply changed layout: the layout hash and paint hash
are compared independently. Region caches contain cloned descriptions, never
application-owned strings or pointers.

The current implementation is intentionally conservative about composition:
the display list is rebuilt when any composite product changes, while the
expensive description/layout/paint stages remain granular and counted.

## Ownership

Retained nodes contain runtime-owned identity metadata, interaction state,
geometry, cached descriptions, display commands and textual copies. Text-field
caret and selection offsets are byte positions normalized to Runa UAX #29
grapheme boundaries. They do not
contain `rawptr`, `^T` application pointers or closures. The application must
copy a text-edit result into its own ordinary state before the next frame.

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
rectangle compositor has been run on the verification Windows host; glyph
atlas rendering and cross-platform driver coverage remain unverified.
