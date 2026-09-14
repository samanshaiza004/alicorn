# Retained-work research notes

This gate uses external frameworks as precedents for pruning and invalidation,
not as dependencies or architectural authorities.

## Xilem `Memoize`

Xilem still evaluates its outer reactive view function and diffs a retained
element tree, but `Memoize` defers construction of a pure subtree until its
declared data dependencies change. When those dependencies are unchanged, the
subtree is neither constructed nor rebuilt. This is the closest precedent for
Alicorn's explicit region revision: a region marker can preserve a retained
subtree without restating its descendants. Xilem's dependency model is
reactive and Rust-owned, so Alicorn adopts only the pruning boundary and keeps
revision ownership in ordinary Odin application state.

Reference: <https://github.com/linebender/xilem/blob/main/xilem/ARCHITECTURE.md>

## GPUI

GPUI tracks window dirtiness separately from a set of dirty entity/view IDs.
Invalidating an entity records that entity, marks the window dirty and wakes
the run loop; the frame can then process the affected views instead of treating
every invalidation as an undifferentiated whole-window update. GPUI also has a
retained entity/view identity model and explicit pointer/event phases.

The transferable lesson is to retain a dirty frontier and make worklists
observable. The non-transferable assumption is GPUI's entity store and
notification/observer system: Alicorn must not require application objects to
be observable, so its frontier is produced by explicit root/region revisions.

Reference: <https://github.com/zed-industries/zed/blob/main/crates/gpui/src/window.rs>

## Process-monitor precedents

The first dogfood deliberately follows the shape of established monitoring
tools without copying their application architecture. [bottom](https://github.com/ClementTsang/bottom)
combines process sorting/search with live system graphs, which makes it a
useful product-level precedent for choosing this app as the first integration
test. The Alicorn version stays smaller: one CPU history surface, one process
table, and no termination or tree-management features.

Windows' process APIs also make this a useful identity test. A PID is not a
durable logical identity because the operating system may reuse it. Alicorn
therefore pairs the PID with the process creation `FILETIME` and uses that
pair for row identity. CPU is sampled from `GetProcessTimes` deltas rather
than inferred from the row's position, so sorting can change without making
selection positional.

## Alicorn decision

Alicorn will use explicit pending subtree reuse markers, retained child
adjacency, local retirement and stage-specific queues. It will not add a
signal graph, automatic dependency discovery, compiler instrumentation or
application-owned widget objects. Global root wake-up and structural reorder
remain intentionally more expensive paths and will be measured separately.

## GPU surface gate

The same precedents support a second boundary. Xilem's pruning idea explains
why a retained surface should not force an ordinary subtree rebuild. GPUI's
dirty-view set explains why a high-frequency surface needs its own explicit
wake bit. SDL_GPU's pass rules explain why the surface cannot own a raw command
buffer: graphics, copy, and compute work must be scheduled in compatible pass
lifetimes, and submitted command buffers cannot be reused. Alicorn therefore
uses an explicit `gpu_surface_update` handle with copied samples; the runtime
owns placement and wakeup, while the native surface adapter owns only its
specialized pipeline and buffers.

## Dogfood decision

The process monitor is intentionally a separate repository at
`samanshaiza004/alicorn-monitor`. Alicorn now exposes a reusable
`alicorn_sdl_gpu.Application`/`Run` host boundary, so the app can pin Alicorn
as a Git submodule without importing the foundation proof entrypoint or
reaching into retained node/display-list internals.
