# Durable UI restoration

Applications own session schemas, persistence, migration, and missing-document
fallback. Alicorn retains UI products within one Runtime lifetime. Never save
Node_IDs, request tokens, virtual row realizations, shaped runs, or transient
pointer/menu/modal state.

## Snapshot and restore

1. Read a split's `preferred_position` with `split_state`, scroll offsets with
   `scroll_region_state`, and logical identity with `semantic_focus_state`.
   Save application meanings (document paths, record keys, pane names), not
   the current owner/realization handles. Style choices are already app-owned
   inputs to `style_environment_push`; persist those choices directly.
2. Create fresh `restore_token_next` tokens in the new Runtime. Pass a
   `Split_Restore_Request` or `Scroll_Restore_Request` when describing the
   intended target. Issue the request when delayed content becomes available;
   do not treat an empty loading placeholder as the final document extent.
3. Reuse the same token through corrective descriptions. A completed token
   never replays on ordinary rebuilds or overwrites subsequent user input.
   Supply a new token only for a new application restore intent.
4. Restore logical focus with `semantic_focus_restore_request` under the
   freshly acquired owner. It remains deferred while the matching entity is
   virtualized. The application decides whether to move keyboard focus to its
   owner using `focus`; semantic restoration itself cannot steal native focus.
5. Query `restore_state_query` for Requested/Deferred or terminal Applied,
   Clamped, Cancelled, and Superseded outcomes. Cancel unavailable application
   targets explicitly once their absence is known. Inspect/trace includes the
   requested, preferred, and resolved values and their resolution generation.

Coordinates are logical units. A split preserves its preferred extent through
temporary constraints. Scroll restoration clamps to the actual content and
viewport; if documents are editable, source-byte or item anchors can be a better
application schema than offsets. Neither API forces all logical rows to realize.
Pending semantic restoration does not poll or request idle descriptions.

## Reproduce an actual process restart

The public-API [fixture](../examples/durable_restoration/main.odin) uses a tiny
versioned application JSON schema containing a split ratio, scroll offset, and
logical record identity. Each invocation creates and destroys a fresh Runtime:

```powershell
.\tools\test_restoration.ps1
```

```sh
sh tools/test_restoration.sh
```

The checks write a session in one process, restore it in another, resize to a
constrained split, shrink 10,000 records to two, and reject missing, malformed,
non-finite, and unsupported-version state. Only a bounded visible range is
described. The restored semantic record must become realized, and the next
unchanged frame must skip description. These checks run in the normal suites.
The fixture's file is disposable test data; production applications should use
their existing atomic session write and recovery policies.

## Scratchpad consumer

Scratchpad's existing Go session owns active document, per-document selection
and scroll, sidebar extent, and recent workspaces. The frontend uses Alicorn's
split/scroll request hooks; its additive `ui` session fields describe the focus
area, tree path/type, and tree scroll position. Only a focused path's ancestors
are expanded. A new Runtime acquires a new tree owner and rebinds the path's
Semantic_ID, even if the first frame has no tree. Removed/hidden paths fall back
without transferring logical focus to another row. Restoring the tree remains
virtualized. A clean stop captures the current retained split and tree scroll
even if the last interaction did not rebuild the application.

Windows validation: the restart fixture and runtime regressions pass. Scratchpad
also tests serialization and reconstruction of a virtual tree in a fresh Runtime,
plus deletion/shrink fallback. macOS native restart interaction remains separate
platform validation; the process fixture is portable and runs in both CI suites.
