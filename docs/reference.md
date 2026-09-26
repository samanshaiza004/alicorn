# API reference

This is a map of Alicorn's public programming surface. The compiler's package
definitions in [`runtime/runtime.odin`](../runtime/runtime.odin) are the source
of truth for exact parameter types and defaults.

## Native application host

Import `native/sdl_gpu` as a host package and pass an `Application` to `Run`.
The application state pointer is borrowed for the duration of `Run`; keep the
state alive until it returns. See the complete
[native starter](../examples/native_hello/main.odin).

The required callback is `build(state, runtime, logical_width,
logical_height, dpi_scale) -> Node_ID`. A typical callback calls
`begin_frame`, emits a `.Root` container and its children, then calls
`end_frame`. Return early if `begin_frame` says there is no application build
to do. Optional callbacks handle text changes, keys, pointer/scroll input,
ticks, dialogs, worker wakeups, and lifecycle events.

## Frame and invalidation

| API | Use |
| --- | --- |
| `begin_frame` / `end_frame` | Open and complete an application description when invalidated. |
| `invalidate_root` | Request a new description after application state changes. |
| `invalidate_region` | Mark a revisioned region as changed. |
| `region_begin` / `region_end` | Reuse an unchanged described subtree using an application-owned revision. |

The runtime does not watch Odin memory. A revision is a promise from the
application: update it when the region's logical output changes.

## Content and layout

| API | Use |
| --- | --- |
| `text` | Emit a text label. |
| `button` | Emit an interactive button; returns `bool` when activated. |
| `text_field` | Emit an editable text field. The host reports committed edits through `on_text_change`. |
| `container_begin` / `container_end` | Group children and define their layout. |
| `layout_style` | Set direction, size constraints, growth, padding, gap, alignment, and clipping. |
| `button_content_style` | Set label alignment and padding inside a button. |
| `Text_Style` | Select weight, overflow behavior, and other text presentation options. |

The default layout direction is column. Use `.Row` for horizontal children;
`grow` shares available space. Layout is in logical window coordinates.

## Identity and repeated UI

`UI_Key` forms:

- `key_string(name)` for a stable named item;
- `key_u64(id)` for a numeric item identity;
- `key_pair(first, second)` for a pair of numeric identity values.

Use `component_begin` / `component_end` to scope reusable UI for a data item.
Keys follow logical items through filtering, insertion, and reorder; indices
and labels are not durable identities. Duplicate keys in one scope are
diagnostics, not an implicit request to use position.

## Collections and panes

- `virtual_list_begin` / `virtual_list_end` return the visible row range for a
  fixed-height list. Emit only those rows, and key each row by its data identity.
- `virtual_list_ensure_visible` scrolls a fixed-row item into view.
- `scroll_region_begin/end` and `virtual_list_metrics` are lower-level tools
  for custom or variable-height scrolling layouts.
- `split_begin`, `split_first_begin/end`, `split_divider`,
  `split_second_begin/end`, and `split_end` compose a retained two-pane split.
  Nest splits for additional panes; nesting direction determines how resizing
  propagates.

### Semantic focus in virtualized views

Keyboard focus, application selection, and the logical entity being operated
on are separate state. Use `Semantic_ID{namespace, value}` to identify an
entity without tying it to a retained node. Set it with
`semantic_focus_set(runtime, id, owner)`, then call `semantic_bind(ui, id)`
immediately after describing a node that currently presents it. Use a stable,
focusable ancestor as owner, such as a virtual list (`focusable=true`).

When the bound row is virtualized away, the runtime retains the semantic ID,
clears its realized node, and keeps keyboard focus at the list owner if focus was
on that row. A later matching `semantic_bind` reconnects the presentation.
`semantic_focus_clear` clears the logical identity; this does not change the
application's selected item. `semantic_focus_state` and `inspect(runtime)` show
the identity, owner, and current realization.

## Transient modal surfaces

`modal_overlay_begin(ui, key, style, backdrop_color)` and
`modal_overlay_end(ui)` describe a viewport-sized modal root after the normal
workspace root has been closed. Its subtree paints above the workspace and
owns hit testing, wheel input, and focus traversal while present. The app must
handle dismissal and restore the focus owner it saved before opening the
overlay. Use a stable key so retained input state survives rebuilds. The
overlay fills the viewport, but generic child containers do not auto-size to
their descendants; transient panels need an explicit or application-computed
height.

## Text, runtime, and presentation

- `Text_Style` and `Font_Role` choose text weight, overflow, and UI/monospace
  roles. The native host bundles Atkinson Hyperlegible Next and Mono; font
  notices and file details are in [`assets/fonts/README.md`](../assets/fonts/README.md).
- `Runtime_Config` optionally configures persistent and scratch backing
  allocators when calling `new_runtime`.
- `inspect(runtime)` and `trace_snapshot(runtime)` expose retained state and
  recent invalidation/stage events for diagnostics.
- `cause_begin` / `cause_end` bracket an input, async completion, or other
  external action. Use `cause_resume` only to continue a saved cause across a
  genuinely dependent asynchronous step; unrelated completions need new IDs.
  `pointer_cause_begin` keeps pointer press, captured motion, and release
  together while leaving uncaptured hover motion ungrouped.
- `Action_ID`, `Action_Descriptor`, and `Action_State` describe an
  application-owned operation without moving its handler into Alicorn.
  `action_update` explicitly publishes its stable machine name, readable label,
  and current enabled/checked state; `action_lookup` reads that state without
  polling or hidden reactivity. `trace_action` and `trace_mutation` attach the
  action identity and readable state-change reasons. `Trace_Event` carries the
  cause, origin, and action through runtime stages and successful host
  submission. IDs are monotonic; trace history remains bounded by
  `Runtime_Config.trace_capacity`.
  If distinct causes coalesce into one frame, its stage records are left
  unattributed rather than assigned to the most recent input.
- `gpu_surface` / `gpu_surface_update` provide the current bounded custom
  surface path. Keep GPU handles and rendering callbacks inside the host; the
  application supplies typed data, not SDL command buffers.

For the ownership and lifecycle model behind these calls, see
[Architecture](architecture.md).
