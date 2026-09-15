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
become the retained hierarchy parent. See [`identity.md`](identity.md).

Source-site strings remain available for deterministic tests and low-level
adapters, but public emission calls can omit them. Omitted sites are
constructed from Odin `#caller_location`; reusable helpers use
`component_begin/end` to add an invocation scope at the actual call site.
Source location alone is still not enough to identify repeated data.

## Reconciliation and invalidation

Each retained node tracks description, layout, paint and composite dirtiness in
an Odin `bit_set`,
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
caret and selection positions use byte offsets normalized to Runa UAX #29
grapheme boundaries plus affinity. The node retains a caret and an
anchor/focus pair, so selection direction is not lost. They do not
contain `rawptr`, `^T` application pointers or closures. The application must
copy a text-edit result into its own ordinary state before the next frame.

Interaction changes are separate from application description changes. Focus,
hover, press, selection and caret updates mark the affected retained node's
paint product and queue it for the next invalidated frame; they do not require
the application description to change.

`Runtime.text_engine` owns cloned font bytes, the parsed Runa font, a shape
cache, CPU atlas residency and a glyph-resource cache. Each retained text node
owns one platform-neutral `Text_Run`; it is rebuilt only when the node's
text/layout inputs or the font generation require it. `Text_Run` copies glyph
IDs, cluster ranges, advances, offsets, line records and caret-relevant
geometry out of Runa's temporary paragraph lines; it never retains Runa's
non-owning font pointer or a physical atlas slot. The native adapter resolves
each logical glyph at the current DPI into a `Glyph_Resource_Key` and a
physical atlas slot. This keeps logical text geometry separate from rendering
residency and lets a window change DPI without stretching a low-resolution
slot. The SDL adapter has no historical run cache of its own, so virtualized
node retirement also bounds text-product retention.

Editable text runs disable Runa's discretionary `liga`, `clig` and `calt`
features. This is a narrow mitigation for the vendored Runa cluster-index bug
after ligation; static labels retain the normal feature set. Mandatory shaping
features remain enabled.

Runtime-owned allocation is split into a persistent allocator wrapper and a
scratch arena. `Runtime_Config` chooses the backing allocators at construction;
the runtime captures those values and does not consult a later ambient
`context.allocator` for retained destruction. Frame and reconciliation scratch
is reset by Alicorn at its own frame boundary. `Runtime_Allocation_Stats`
counts requested bytes and calls for these runtime-owned wrappers only; it is
not a process-memory or GPU-memory measurement.

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
not the row's viewport index. The shared metrics calculation clamps against
the actual viewport and preserves the fractional leading offset, so realized
rows move continuously while the retained list clip protects surrounding UI.
Scroll physics, pointer-drag scrollbar interaction, and persistent offscreen
selection storage remain outside this small primitive.

## Committed text input and composition

`Text_Composition` is transient interaction state attached to the focused text
field. It owns a copied UTF-8 preedit string, the platform's selected range
converted to byte offsets, and the committed anchor/focus range that the
composition will replace. `SDL_EVENT_TEXT_EDITING` updates this state and
invalidates only the field's interaction paint. It never changes `Node.text`.

`SDL_EVENT_TEXT_INPUT` is the commit boundary. The runtime sends the committed
string through the ordinary insertion/editing path, replacing the captured
selection once, then clears the composition. The application callback borrows
the runtime-owned `Text_Change.text` for the duration of the call, clones it
into ordinary Odin state if needed, and lets the host release the runtime
product through the runtime's captured persistent allocator before the next
description. Empty editing text cancels; focus loss, pointer placement and
node retirement also cancel deterministically.

SDL reports composition selection positions as UTF-8 character indexes, so the
native adapter passes them through an explicit character-to-byte conversion.
The retained `Text_Position` model remains byte-based with grapheme-boundary
normalization and affinity. The native adapter starts text input only while a
focused text field exists, stops it on focus loss, and updates
`SDL_SetTextInputArea` from the field bounds and actual retained caret
geometry. Platform candidate-window behavior remains SDL/OS-owned; Alicorn
currently renders a simple inline preedit projection and underline.

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

## Custom GPU surfaces

`gpu_surface` creates a retained `.Custom_Surface` placement with a stable
identity, logical bounds, physical extent, DPI scale and initial revision.
`gpu_surface_update` is the explicit high-frequency path: it copies caller
samples into node-owned storage, records a bounded structural trace event and
sets a compositor-frame-pending bit. It does not invalidate the root or queue
ordinary description/layout/paint work. `gpu_surface_frame_consumed` clears
that bit after a successful native submission. Retained display products also
carry a monotonic `presentation_revision`; native hosts acknowledge the latest
revision only after a successful GPU submission, so a missing swapchain
drawable leaves the frame pending for a later retry.

The first native implementation is a 512-sample waveform. Its SDL adapter
owns a dedicated pipeline, sampler, white texture, vertex buffer and transfer
buffer. It encodes a scissored render pass at the retained display-command
position and cycles buffer uploads safely while three frames may be in flight.
The application never receives an SDL command buffer or render-pass pointer.
Surface samples are copied; arbitrary application pointers and closures are not
retained. Surface resource destruction occurs after the adapter's final device
idle wait. The measured surface-only path has zero ordinary runtime visits and
zero warmed-loop allocations; the native stress path performs 1,200 waveform
uploads with five resources created once.
