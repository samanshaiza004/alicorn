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

## Alicorn decision

Alicorn will use explicit pending subtree reuse markers, retained child
adjacency, local retirement and stage-specific queues. It will not add a
signal graph, automatic dependency discovery, compiler instrumentation or
application-owned widget objects. Global root wake-up and structural reorder
remain intentionally more expensive paths and will be measured separately.
