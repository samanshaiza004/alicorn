# Odin AccessKit bindings

This package binds the pinned AccessKit C API 0.23.1. It has no Alicorn or SDL
imports. The shared node, tree-update, ABI-payload, and action-request APIs are
available to Odin consumers; native subclassing adapters are explicitly
conditional on Windows and macOS.

`Role`, `Action`, and `Node_ID` are typed AccessKit identifiers. Named role and
action constants cover common controls; other values from the pinned C header
can be converted explicitly. In particular, `ROLE_LIST_BOX` is 87 and
`ROLE_LIST_BOX_OPTION` is 10 and `ROLE_STATUS` is 116 in AccessKit 0.23.1.
`Rect` uses top-left-origin, y-down coordinates.
`Text_Position.character_index` uses AccessKit character indices.

## Typed node setters

The owning `Node` wrapper includes typed setters for the semantic fields used
by Alicorn's AccessKit projection: character lengths, text selection, live and
live-atomic state, required, read-only, invalid, busy, current, toggled,
position/size in set, and numeric value/minimum/maximum/step. The wrapper also
retains direct public `accesskit_node_set_*` C bindings for less common fields.

`node_set_character_lengths` accepts a `[]u8` and forwards its pointer and
length to AccessKit; the Odin wrapper does not adopt or free the caller's
slice. `node_set_text_selection` takes the public `Text_Selection` value by
value. Live, invalid, current, and toggled values use distinct types rather
than unvalidated bytes. Their named constants match the pinned header:
`LIVE_OFF`, `LIVE_POLITE`, `LIVE_ASSERTIVE`, `TOGGLED_FALSE`, and
`TOGGLED_TRUE` (with `TOGGLED_MIXED` also available). Tests pin the role and
enum discriminants to AccessKit 0.23.1.

## Native subclassing adapters

The package accepts raw native handles and does not discover or own the window:

- Windows: `windows_subclassing_adapter_create(hwnd, ...)` accepts an `HWND`
  represented as `rawptr`. Create it on the owning window thread before the
  window is shown or focused. The caller keeps ownership of the HWND.
- macOS: `macos_subclassing_adapter_create_for_window(window, ...)` accepts a
  valid `NSWindow` pointer as `rawptr`. Its content view must exist. The caller
  keeps ownership of the native window.

Both create calls accept C-callable activation and action callbacks. Activation
callbacks and the `Update_Factory` later supplied to `*_update_if_active`
return a newly owned, non-nil `Tree_Update` C pointer, normally produced with
`tree_update_take`. Action callbacks receive an AccessKit request whose
ownership was transferred to the callback. They must release it exactly once;
use `action_request_snapshot_and_destroy` to safely copy its payload and free
the request, or pair `action_request_take` with `action_request_destroy`.

Use `*_subclassing_adapter_update_if_active` after changing the semantic tree.
The returned queued-events wrapper can be nil when the adapter is inactive. A
non-nil queue must be passed once to `*_queued_events_raise`; this delivers and
frees the C queue, and clears the Odin handle. macOS and Windows also expose
their platform-specific focus-state update procedure. Its returned queue has
the same ownership rule. Destroy the adapter before releasing its native
window.

On Windows, adapter creation must happen before the HWND is visible/focused,
and create/update/focus/destroy operations should be performed on the window's
owning thread. The action callback may run on a different thread; application
state must be synchronized accordingly. On macOS,
`macos_add_focus_forwarder_to_window_class`
installs a permanent method on an NSWindow subclass. The AccessKit library
must remain loaded for the process lifetime when using it, so static linking
is recommended. The helper accepts a NUL-terminated class name.

The low-level `accesskit_*` C declarations remain public for cases where a
consumer needs an AccessKit 0.23.1 operation not yet covered by a typed helper.
They use opaque `rawptr` handles and preserve the C ownership contract. The
public `Action_Data_ABI`, `Optional_Action_Data_ABI`, `Action_Request_ABI`,
`Text_Position`, and `Text_Selection` types mirror the pinned C layouts; their
layout is guarded by Odin compile-time assertions. `accesskit_node_set_*`
bindings include live state, text selection and character lengths, numeric
values, and set position/size setters used by Alicorn's semantic adapter.

## Ownership

- `Node`, `Tree_Info`, and `Tree_Update` are owning handles. Do not copy them.
- Destroy an untransferred handle with its matching `*_destroy` procedure.
- `tree_update_push_node` transfers the node to the update and clears the Odin
  handle; this transfer is documented by AccessKit's C header.
- `tree_update_set_tree_info` clears the Odin handle after handing the pointer
  to AccessKit. The 0.23.1 header does not explicitly describe this setter's
  ownership transfer; this wrapper follows the existing native integration.
- `tree_update_take` transfers the opaque C update to a platform adapter or C
  caller. It is not an Odin allocation.
- Text setters borrow the supplied Odin string only for the call; AccessKit
  stores its own copy. AccessKit label results must be freed with
  `accesskit_string_free`.
- `Action_Request` owns the request transferred to an action callback.
  `action_request_borrow` returns a view valid only until the request is freed.
  `action_request_copy` clones text into caller-selected allocator storage,
  while retaining the request owner. `action_request_snapshot_and_destroy`
  clones text and always frees the transferred request, including when cloning
  fails. Destroy its `Owned_Action_Request` with
  `owned_action_request_destroy`; do not copy the owned value.
- A C queued-events pointer is delivered and freed by its platform-specific
  `*_queued_events_raise` function. The safe wrapper clears the handle after
  raising; do not copy or raise the same queue twice.

## Boundaries and limitations

This is an intentionally small binding, not a platform-windowing framework.
It does not discover native handles, create windows, implement event loops,
translate Alicorn semantics, synchronize application state, or route
accessibility actions into an application. Those remain the toolkit or
consumer's responsibility. There is no native adapter on Linux in this
version. The platform adapters and native assistive-technology behavior still
require Windows/macOS host validation; package tests alone do not establish
UIA/AX or screen-reader compatibility.

## Local checks

From the repository root, after the pinned dependency has been bootstrapped:

```sh
odin check accesskit -no-entry-point
REPO_ROOT=$PWD
. tools/accesskit.sh
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
ABI_PROBE_LINK_FLAGS=$(sh tools/build_accesskit_abi_probe.sh out/accesskit_abi_probe)
odin test accesskit "-extra-linker-flags:$ACCESSKIT_LINK_FLAGS $ABI_PROBE_LINK_FLAGS"
odin run accesskit/consumer \
  -collection:accesskit=. \
  -extra-linker-flags:"-L.deps/accesskit/accesskit-c-0.23.1/lib/macos/arm64/static -framework AppKit -framework Foundation -framework CoreFoundation -lobjc -lc++"
```

Use the matching AccessKit 0.23.1 library for the target platform and
architecture. The consumer fixture imports only `accesskit:accesskit`; it
does not link Alicorn or SDL.
