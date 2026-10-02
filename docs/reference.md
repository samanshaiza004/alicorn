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
drag/drop transitions, scheduled wakes, dialogs, worker wakeups, and lifecycle
events.

`on_pointer` receives a platform-neutral `Pointer_Event` with the pointer kind,
logical window coordinates, button number, `Input_Modifiers`, and a native
`click_count`. The modifier flags describe the host's best event-time keyboard
state. SDL mouse-button events do not include a modifier snapshot, so the SDL
host tracks keyboard modifier events in queue order. `click_count` is the
platform-reported click sequence count (for example, 1 for a single click and 2
for a double-click); it is zero on non-button events or when the host cannot
provide a count. Application-level selection behavior should treat a zero
count on a button-down event as one click.

For periodic refreshes, read `Application_Services.scheduler` in
`on_services`. `application_schedule_after` and
`application_cancel_scheduled_wake` operate on one-shot `Frequent` and
`Opportunistic` deadlines; rearm explicitly from `on_scheduled_wake`. These
callbacks run on the UI thread. Opportunistic work is held until 150 ms after
the last keyboard or pointer event. `application_scheduler_stats` exposes
scheduled/coalesced counts, runs, deferrals, pending state, and maximum
lateness. Prefer this over display-cadence `on_tick` for live data refresh.

Use `Application.on_close_requested` to defer an OS/window close while an
application handles unsaved work. Return `.Allow` to close immediately or
`.Defer` to keep the window running. After the user resolves the application's
save/discard flow, call `application_request_quit` with
`Application_Services.quit`; this service is UI-thread-only and valid until
`Run` returns.

`Application_Services.clipboard` is the UI-thread-only OS text clipboard
service. `ClipboardGetText(service, allocator)` returns an owned UTF-8 string
that the caller must release with the same allocator; an empty clipboard is a
successful empty string, while `ok == false` reports an unavailable service or
host error. `ClipboardSetText(service, text)` copies UTF-8 text synchronously
and rejects embedded NUL bytes. Clipboard and dialog operations belong in the
native host boundary; application code decides selection and edit semantics.

## Frame and invalidation

| API | Use |
| --- | --- |
| `begin_frame` / `end_frame` | Open and complete an application description when invalidated. |
| `invalidate_root` | Request a new description after application state changes. |
| `invalidate_region` | Mark a revisioned region as changed. |
| `region_begin` / `region_end` | Reuse an unchanged described subtree using an application-owned revision. |

The runtime does not watch Odin memory. A revision is a promise from the
application: update it when the region's logical output changes. Revisions are
monotonic: `invalidate_region` accepts an equal or greater revision and forces
the matching live region instances to rebuild; a lower revision is rejected.
Invalidating an unknown key is also rejected. The key must match a region that
has already been described. If the same key is used in several component
instances, invalidation applies to each matching instance. `region_begin` also
rejects a revision lower than the retained high-water mark. These checks are
always enabled, including release builds; `inspect(runtime)` exposes the hard
error and its correction hint.

## Content and layout

| API | Use |
| --- | --- |
| `text` | Emit a text label. |
| `button` | Emit an interactive button; returns `bool` when activated. |
| `checkbox` | Emit a controlled checkbox; returns `{value, changed}`. |
| `slider_f32` | Emit a controlled horizontal `f32` slider; returns `{value, changed}`. |
| `text_field` | Emit an editable text field. The host reports committed edits through `on_text_change`. |
| `container_begin` / `container_end` | Group children and define their layout. |
| `layout_style` | Set direction, size constraints, growth, padding, gap, alignment, and clipping. |
| `button_content_style` | Set label alignment and padding inside a button. |
| `Text_Style` | Select weight, overflow behavior, and other text presentation options. |

The default layout direction is column. Use `.Row` for horizontal children;
`grow` shares available space. Layout is in logical window coordinates.

Checkboxes toggle by pointer or Space; Enter is reserved for button activation.
Sliders drag with the pointer, adjust down with Left/Down and up with Right/Up,
and jump to their exact minimum/maximum with Home/End. A slider's `step=0` means
continuous pointer input and one-percent-of-range keyboard steps; a positive
step snaps to the nearest increment from the minimum while keeping both
endpoints reachable. Both controls clamp values to their range and ignore
input while disabled. They do not own application state: store the returned
`value` when `changed` is true. Their default sizes are content-aware; set
`Layout_Style` when a specific size is desired.

## Identity and repeated UI

`UI_Key` forms:

- `key_string(name)` for a stable named item;
- `key_u64(id)` for a numeric item identity;
- `key_pair(first, second)` for a pair of numeric identity values.

Use `component_begin` / `component_end` to scope reusable UI for a data item.
Keys follow logical items through filtering, insertion, and reorder; indices
and labels are not durable identities. Duplicate keys in one scope are
diagnostics, not an implicit request to use position. A duplicate identity
diagnostic reports the first and conflicting declaration, their call sites,
keys, and enclosing scope path, with a suggested correction. These diagnostics
are always enabled in all build configurations; they do not fall back to
position-based identity.

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

### Context menus

`context_menu_open(runtime, anchor, restore_focus_to, width, item_height)` opens
one retained, single-level menu at a logical viewport rectangle. For a
pointer-anchored menu, pass `Rect{x, y, 0, 0}`; for keyboard invocation, pass the
focused control's bounds (or use `context_menu_open_for_focused`). The runtime
places the menu beside the anchor, flips it when space is short, and clamps it
to the viewport. Describe the ordinary root first, then, while the menu is
open, call `context_menu_begin`, add `context_menu_item` and
`context_menu_separator` entries, and finish with `context_menu_end`.

The app owns the context entity and command handler. Menu items use the same
`Action_ID` registry as native menus and return the selected ID from
`context_menu_end`; Alicorn never invokes application callbacks. A registered
disabled action is not focusable or activatable. Up/Down, Home/End, Enter/Space,
Escape, outside-click dismissal, focus restoration, and the full-viewport input
blocker are runtime behavior. If the app omits the menu on the next description,
the runtime closes it. The host exposes `POINTER_BUTTON_SECONDARY` for secondary
click and maps Shift+F10 to `Application_Key.Context_Menu`; the app should open
the menu from its focused/semantic target and call `context_menu_open`.

The popup is a top-level transient layer, so it is not clipped by its invoking
pane. This first primitive is single-level and has no submenu, checkmark, or
embedded-widget model.

### Local drag and drop

`drag_source(ui, drag_type, semantic_id)` and
`drop_target(ui, drag_type, semantic_id, mode)` annotate the most recently
described node. The application chooses a nonzero `Drag_Type`, supplies stable
`Semantic_ID`s, and interprets the event payload; Alicorn never stores an
application pointer or decides whether a drop means move, copy, or reorder.
Use `.On` for a destination surface and `.Between_Horizontal` or
`.Between_Vertical` for Before/After insertion targets. Hit testing resolves a
child control to its nearest accepting retained ancestor. During an active
drag, an annotated background surface can also receive drops in its blank
space.

The host recognizes a drag after the pointer moves at least five logical
pixels from a primary-button press on a declared source. Below that threshold,
ordinary click activation is unchanged. `Application.on_drag` receives
`.Started`, `.Target_Changed`, `.Dropped`, and `.Cancelled` events, identified
by semantic source/target IDs. Target-change events are emitted only when the
semantic target or Before/After side changes; same-target pointer motion stays
in retained runtime presentation and does not rebuild the application. A
virtualized source may disappear after `.Started`; the semantic source ID
remains valid for the rest of the session. Escape, native pointer cancellation,
and focus loss cancel and release the drag.

While a local drag is held inside the 24-logical-pixel edge zone of a
scrollable viewport, the native host schedules bounded 16 ms autoscroll ticks.
The runtime changes only the retained scroll offset; the application rebuilds
the virtualized viewport only when that offset advances. Releasing, canceling,
or reaching the scroll limit stops the timer.

Dragging also presents a small runtime-owned preview: Alicorn captures a
bounded shaped copy of the source label (falling back to its text), offsets it
from the pointer, and dims the realized source to 55% opacity. The preview is
presentation-only and hit-test-transparent. Its label remains available if
virtualization retires the source node; pointer motion updates the preview
position without rebuilding application descriptions.

This is an in-window, single-source primitive. It does not transport operating
system file drops or arbitrary MIME payloads.

## Text, runtime, and presentation

- `Text_Style` and `Font_Role` choose text weight, overflow, and UI/monospace
  roles. The native host bundles Atkinson Hyperlegible Next and Mono; font
  notices and file details are in [`assets/fonts/README.md`](../assets/fonts/README.md).
- `text_style_spans(ui, id, spans)` applies shaping-aware typography to the
  just-described `.Text` node. Each `Text_Style_Span` uses a half-open UTF-8
  byte range. Weight and italic are independently optional; later spans that
  set an attribute win. These styles participate in shaping and can change
  glyph advances or line metrics, so they invalidate text layout and editor
  geometry. The bundled faces use real variable weights and separate italic
  fonts. Keep color, backgrounds, underline, and strikethrough in
  `Text_Paint_Span` when geometry must remain unchanged.
- `text_paint_spans(ui, id, spans)` decorates the just-described `.Text` node.
  Each `Text_Paint_Span` uses a half-open UTF-8 byte range (`start`, `end`) in
  the displayed `Text_Run.value`. Set `color_set` to use `color`; set
  `background_set` to use `background`; `underline` and `strikethrough` add
  those decorations. Empty spans clear all span paint on the node. The runtime
  copies the supplied slice during reconciliation, so its source can be
  temporary. Span edits repaint the retained run but do not reshape it or
  change its caret, hit-test, or layout geometry.
- Overlapping foreground spans use the last matching span in input order.
  Backgrounds draw in input order, so later backgrounds cover earlier ones;
  underline and strike are additive. Foreground color applies to a complete
  shaped glyph cluster when the range touches it. This preserves ligatures and
  cluster shaping; a span inside a ligature colors that whole glyph. Background
  and decoration bounds expand to intersecting grapheme geometry and use the
  text command's clip.
- `visual_row_background(ui, row, text, position, color)` paints the complete
  shaped visual row behind an editor row container. `row` may be the source
  lane or a separate gutter; `text` supplies the retained shaped geometry and
  `position` chooses the wrapped visual row. The background spans the row
  container's width and uses the text row's Y and height, so it does not stop
  at the last glyph. This is row geometry, not a text paint span, and therefore
  remains correct when a wrapped row is active.
- Example, immediately after emitting a Text node:

  ```odin
  id := alicorn.text(&ui, "Save draft")
  spans := []alicorn.Text_Paint_Span{{
      start=0, end=4,
      color=alicorn.Color{0.35, 0.78, 1, 1}, color_set=true,
      underline=true,
  }}
  _ = alicorn.text_paint_spans(&ui, id, spans)
  ```
- A generic `text_input_target` receives `Application_Text_Key_Event` values
  whose key is a normalized editing intent (`Word_Left`, `Line_Start`,
  `Document_End`, and so on), not an SDL keycode/modifier combination. The SDL
  host applies platform conventions (Ctrl/Option word movement, Command line
  movement, and platform document-edge keys). A focused generic text owner gets
  first refusal on Tab; declining it preserves normal focus traversal. Global
  menu shortcuts are checked before generic text keys.
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
