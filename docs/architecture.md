# Architecture

Alicorn is **direct to write, retained to run**. Application code describes
the interface procedurally; the runtime retains only the UI facts and products
that need to survive between descriptions.

```text
application-owned Odin state
              │
              ▼
       UI description
              │
              ▼
identity → reconcile → layout → paint → presentation
              │
              ▼
      native host / SDL_GPU
```

## Ownership

The application owns its model and decides when it changes. Alicorn owns
retained node identity, interaction state, geometry, text products, paint
products, and GPU-facing runtime resources. It does not observe arbitrary Odin
memory or keep application pointers in retained nodes.

The native host owns the window, input pump, application loop, GPU submission,
and resource lifetime. The app supplies ordinary callbacks and typed UI
descriptions; it never receives an SDL command buffer or render-pass pointer.

## Identity

A source location identifies a structural call site. A `UI_Key` distinguishes
repeated logical items at that site. Reusable components add a keyed identity
scope. Identity therefore remains stable when a keyed item moves, while a
duplicate key is reported rather than guessed from its current position.

Runtime node IDs are implementation identity, not persistent IDs for saving
data across program versions.

`Runtime` remains a public Odin struct for now, so its fields are technically
reachable by importing applications. They are implementation details, not a
supported compatibility surface. Applications should use documented runtime
queries and commands; the package exposes read-only node snapshots and text
geometry queries rather than retained node or shaping storage.

## Work and invalidation

`begin_frame` skips application description when the root is not invalidated.
After a logical mutation, the app explicitly invalidates the root or a region.
A region's revision lets Alicorn reuse an unchanged subtree; the application
must advance that revision when its output changes.

Description, reconciliation, layout, paint, and presentation have distinct
dirty state. An input-only change can update retained presentation without
asking the application to describe the whole UI again. Changed constraints
can require layout even when the description itself is reused.

The #25 axis allocator is a deterministic primitive over `Layout_Unit`
participants and now owns Row/Column main-axis distribution. Fixed and natural
children enter as measured extents; a grow child starts at its hard minimum and
maps `grow` to a normalized expansion weight. Maxima saturate and release their
share for redistribution; hard minima remain intact, and any unresolved
overflow or unused surplus stays explicit. Text shaping remains in the measure
stage and is never initiated by allocation. Cross-axis alignment and the
specialized Split sizing path are unchanged. This is not content-sized
container measurement (#5), Grid (#26), or a new compression policy: current
Row/Column children do not compress below their ideal/minimum.

`Style_Environment` is the inherited dependency surface for a compact theme ID,
density, normalized text scale, accent override, and backend-neutral
`Accessibility_Appearance_Preferences`. Applications can provide increased
contrast, reduced motion/transparency, and non-color state differentiation.
These preferences alter only resolved paint/material; they never add or rewrite
semantic roles, names, values, actions, or states. Immutable typed palettes
resolve semantic color roles without copying them into every retained node.
Environment changes map to retained domains: density to metrics, text scale to
metrics and typography, theme/accent and contrast/non-color preferences to
paint, and preference-aware analytic materials to material. A style scope and a
layout boundary are separate: style scopes supply inherited inputs, while a
container opts into local layout invalidation with `layout_boundary=true` when
its parent-assigned bounds can remain stable. Measurement invalidation alone
does not propagate layout; the runtime compares retained measure results and
propagates changed output axes through the parent's placement dependencies.
The current `layout_boundary=true` contract is full containment: the boundary
keeps its parent-assigned outer geometry stable while its contents relayout.
`Parent_Size_Dependencies` records the child-output-to-parent-output mapping,
but current Row/Column containers do not derive external preferred size from
their children. #5 owns content-sized container policy and the future per-axis
propagation this enables; a width-definite/height-content container is not yet
an axis-specific layout boundary.
`style_metric` leaves the meaning and use of each dimension with the
application. This is explicit dependency tracking, not a general cascade or
implicit observation of app state. The
button component has an explicit recipe family for default, primary, toolbar,
quiet, and tab intent. Checkbox and Slider resolve semantic recipes over their
distinct visual parts. Selected/checked, hover, press, and disabled transforms
compose in a fixed order; focus remains a separate overlay.
Typed color and logical-length tokens now have a small compiler/runtime path,
including namespaced application/vendor roles. Retained nodes keep compact
per-domain style generations; scope updates advance only affected nodes.
Button, Checkbox, Slider, Text Field, Scrollbar, and Semantic Surface
`Computed_Style` entries live in Runtime side storage keyed by `Node_ID`,
keeping the retained `Node` under its byte budget. Each entry records its
recipe family, semantic inputs, dependency domains, and only the matching
generation snapshots. Buttons, Checkboxes, Sliders, Text Fields, and
Scrollbars depend on Paint; Semantic Surfaces depend on Paint
for role color and Material for shape/material/height/group. Inspector
provenance reports these retained results, including optional compiled token
names and alias chains. Node retirement and runtime destruction release
sidecar entries. Token aliases are flattened in runtime values; readable names
and immediate alias edges are optional runtime diagnostic metadata while
source locations remain compiler-only. Rectangular semantic surfaces can use
registered flat or analytic-relief materials; a general cascade and richer
native shapes remain outside this slice.

Product-specific presentation composes over retained owners. `button_begin` /
`button_end` let an application describe ordinary layout children under a
Button; `visual_part_attach` records a typed core or namespaced extension
identity, owner, and optional owner-state visibility rule in Runtime side
storage. Any retained owner can own always-visible parts; state-dependent
visibility is validated against the owner control's supported states, and
Button recipe inheritance remains Button-specific. The runtime validates
that each part is retained beneath its owner. The sidecar is available to the
inspector and is deleted when the retained node retires. It does not add a
second event model or geometry language: layout remains responsible for order,
bounds, and clipping, while interactive owners remain responsible for
activation and state. TabBar is the first built-in consumer; its close child
is independently actionable and its paint uses the same generic primitive
stream as other controls.

Theme/accent changes are Paint-only today because current recipes consume color
roles only. No theme length token drives recipe metrics, typography, or material
selection. A text-scale scope advances Metrics and Typography only for its
subtree and triggers layout there, while the color-only computed-style cache
remains valid. Material-only surface description changes advance Material,
preserve Paint and leave layout/hit geometry untouched. Themes/materials are
immutable after registration, and semantic recipe or surface description
inputs participate in cache signatures. Optional authored token names,
immediate alias edges, and qualified extension-role names flow into the runtime
inspector; source spans remain compiler-only. Runtime work counters expose
computed-style resolutions and retained cache hits, and inspector reads do not
alter those counts.

This is explicit reuse, not automatic dependency tracking. A stale region
revision can produce stale content.

Runtime trace records can share a monotonic cause ID from input or another
external cause through semantic action, invalidation, retained work, and GPU submit.
The ring stays bounded. When separate causes collapse into one pending frame,
the frame's stage records are deliberately unassigned; the runtime does not
guess which input was responsible. An idle runtime creates no causes.

Applications publish stable action identity and explicit enabled/checked state
to their Alicorn runtime. The application still owns dispatch and behavior;
menus, shortcuts, direct controls, and palettes can share the same `Action_ID`
without introducing a global command registry or reactive state system.

## Backend-neutral semantics and bounded collections

Semantic entities are retained independently from visual nodes; they are not a
platform accessibility tree. Ordinary controls can contribute roles, names,
values, state, actions, and relationships. The composite Tab Bar illustrates
the boundary: a TabList contains Tab entities and close actions, while
underlines, dirty markers, and hover/selection paint remain presentation only.

Large virtual collections retain collection metadata and only the item
descriptions in the application's semantic working set. Applications may
describe realized rows and logical-only items; they should submit a bounded
visible range plus any useful navigation horizon. Items that leave that set
are pruned unless they are current, selected, or the logical semantic-focus
target. This keeps semantic identity independent of visual realization without
allocating one retained descriptor per logical row. The million-item fixture
tests visible-only, horizon, and pinned-item policies; it does not demonstrate
screen-reader traversal across a native tree's unexported gaps.

The internal runtime API can return an owned `semantic_snapshot` or the single
newest `semantic_update_since` transition. Deltas carry `from_revision` and
`to_revision`; a caller already at the current revision gets an empty update,
while any other base must match the retained transition or request a snapshot.
The backend-neutral snapshot/delta API feeds a Windows/macOS AccessKit adapter;
platform nodes are derived and never become Alicorn's semantic source of
truth. `semantic_action_request` routes
supported realized Press/Select/Focus actions through Alicorn's existing
interaction path; logical-only and other domain actions queue app-owned Perform
events. `semantic_reveal_request` separately queues an app-owned Reveal event.
Apps drain queued events with `semantic_request_pop` and decide how to perform
the domain action or reveal an item; Reveal is not a synthetic click. The
AccessKit bridge requests a bounded full snapshot on activation and applies
revision-exact deltas, falling back to a full snapshot when the base differs.
Semantic state is dirty-driven and introduces no idle polling; activation can
request one bounded host wake. Real platform assistive-technology navigation
remains an explicit validation gate.

## Native and text boundaries

The runtime is platform-neutral Odin code. `native/sdl_gpu` adapts SDL3 input,
window metrics, native text input, and SDL_GPU composition. Text shaping and
layout products are kept separate from DPI-specific GPU glyph residency.
Bundled fonts and their licenses are documented in
[`assets/fonts/README.md`](../assets/fonts/README.md).

Paint producers include runtime widgets, retained overlays, and native host
chrome. They resolve their presentation decisions into a small generic paint
stream: `Surface_Paint`, `Text_Paint`, and `Geometry_Paint`. Every command carries
its bounds, clip, opacity, and translation; `owner` identifies the producer
for diagnostics and transient cleanup, and does not select renderer behavior.
Translation and opacity affect composition only, never layout or hit testing.

Text and geometry handles are generation-checked references to payloads. Their
resolvers return shaped text or surface geometry data only; placement, clipping,
and other presentation state stay on the command. Stale handles are skipped.
The retained stream order is authoritative: the SDL compositor batches adjacent
surface primitives and treats text and geometry as ordering barriers. It does
not sort by primitive family or inspect `Node_Kind` to decide how to draw.

Semantic surfaces carry a registered material ID, optical height, and group in
their generic paint command. The native renderer expands flat or analytic
rectangular relief into bounded ordinary vertices; optical height never affects
layout or stacking order. Analytic relief uses a fixed upper-left light and
scales/reverses edge shading with signed physical height. Flat materials and
zero-height surfaces emit the same single quad as ordinary solid paint; they
need no auxiliary buffer, blur, compute pass, or continuing redraw. Image paint
is deferred until Alicorn defines its image resource lifetime and upload
contract. Applications author semantic widgets and host integrations; the
generic paint payload union is an internal renderer boundary, not a replacement
UI authoring API.

The host waits for events when idle. Worker completions can wake it through an
opaque `Application_Waker`; the UI remains on the window thread. The runtime
does not create application threads or observe external state.

Applications that need delayed refreshes can use the host's two-slot
`Application_Scheduler`. A slot is either `Frequent` or `Opportunistic`; each
class owns one replaceable deadline, and callbacks run on the UI thread with a
`Scheduled_Wake` cause. Opportunistic deadlines wait until 150 ms after the
last keyboard or pointer input. The host sleeps until the next deadline or
native event, and no callback rearms itself automatically, so canceling both
slots returns the application to true idle. This is for bounded refresh
cadences, not animations or general-purpose task queues.

## Boundaries and current scope

The current surface API supports typed retained presentation data; it is not
an application shader API. The runtime's keyboard focus, semantic focus, and
action IDs are exported through an experimental Windows/macOS AccessKit bridge;
real screen-reader behavior remains unvalidated. See the
[accessibility status](guide.md#accessibility-status).
Broader platform validation and additional advanced text behavior remain
future work. The project is experimental, and its API may change.
