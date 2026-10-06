# API reference

This is a map of Alicorn's public programming surface. The compiler's package
definitions in [`runtime/runtime.odin`](../runtime/runtime.odin) are the source
of truth for exact parameter types and defaults.

## Native application host

Import `native/sdl_gpu` as a host package and pass an `Application` to `Run`.
The application state pointer is borrowed for the duration of `Run`; keep the
state alive until it returns. See the complete
[native starter](../examples/01_hello/main.odin).

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
Native hosts also populate `Pointer_Event.target_key` from the hit or captured
node when it has an explicit key. Direct callers of `process_pointer` receive
the target `Node_ID` and can query `node_identity_key` themselves.

`Runtime`'s fields are exported for Odin interoperability, but are internal
implementation details and are not a supported application API. Use
`node_info`, `text_field_value`, `focused_node`, `captured_node`,
`viewport_bounds`, `runtime_scratch_allocator`, and retained text geometry
procedures for read access. Borrowed strings remain valid until the next
mutation of the referenced value, application description, or runtime
destruction. Scratch allocations must not outlive the next runtime scratch
reset.

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
| `text_field_value` | Read the borrowed current value of an active retained text field. |
| `node_info` / `node_identity_key` / `node_by_key` | Read a node's geometry, interaction state, scroll metrics, and explicit identity. |
| `text_node_line_geometry` / `text_node_hit_test_line` | Query retained visual-line geometry and hit-test without exposing its shaped run. |
| `runtime_text_run_build` | Shape temporary application text through Alicorn's retained text engine without exposing the engine. |
| `container_begin` / `container_end` | Group children and define their layout. |
| `layout_style` | Set direction, size constraints, growth, padding, gap, alignment, and clipping. |
| `button_content_style` | Set label alignment and padding inside a button. |
| `Text_Style` | Select weight, overflow behavior, and other text presentation options. |
| `Style_Theme` / `style_theme_register` | Register an immutable typed color palette for one runtime. |
| `style_color` / `style_metric` | Resolve a semantic color or scale an app-owned metric in the active environment. |
| `Style_Color_Token_ID` / `Style_Length_Token_ID` | Address theme-local typed token arrays without string lookup. |
| `style_token_color` / `style_token_length` | Resolve a typed token against its registered theme ID. |
| `Style_Extension_*_Role_ID` / `style_extension_*` | Resolve namespaced app/vendor roles during setup, then retain the typed token ID. |
| `Button_Variant` / `Button_Recipe` | Select an explicit button recipe such as `.Toolbar`, `.Primary`, `.Quiet`, or `.Tab`. |

The default layout direction is column. Use `.Row` for horizontal children;
`grow` shares available space. Layout is in logical window coordinates.

### Scoped style environment

`Style_Environment` carries a compact theme ID, density, text scale, and packed
accent override (`style_accent` quantizes RGB to 8 bits per channel). Register an immutable `Style_Theme` with `style_theme_register`; its
typed `Style_Color_Role` entries provide semantic colors. `style_color` resolves
a role in the current scope, and `style_metric` scales a logical metric by the
active density. The application still chooses which app-authored dimensions and
paint surfaces use those values.

Place `style_environment_push` immediately after beginning a container, describe
the subtree, then pair it with `style_environment_pop` before ending that
container. Zero-valued fields in the pushed value inherit from the enclosing
scope, so focused overrides such as `Style_Environment{text_scale=1.25}` remain
composable. Density must be in `[0.5, 3]`; text scale must be positive and below
100; theme colors use normalized RGBA channels with nonzero alpha. Accent
overrides are opaque and quantized to 8-bit RGB.

Text scale invalidates typography and metrics. Density invalidates metrics.
Theme and accent changes invalidate paint only. These changes are retained and
scoped: unrelated siblings are not laid out or repainted. Text products shape at
`DEFAULT_TEXT_SIZE * text_scale`. The scope container must keep parent-assigned
bounds stable while its contents reflow. Theme IDs are immutable and local to a
runtime; do not reuse IDs across runtimes.

The separate [`theme` compiler contract](themes.md) compiles typed color and
logical-length tokens, aliases, core roles, and namespaced extension roles.
This is not a general selector/cascade system. Button, Text Field, and
Scrollbar recipes currently describe semantic color treatment; only Button
has a retained `Computed_Style` cache. Rectangular semantic surfaces can use
registered flat or analytic-relief materials. General property resolution,
metric-token dependencies, and richer native surface shapes remain outside the
current contract.

### Button variants and recipes

Buttons use one recipe family with explicit intent rather than inferring their
appearance from their parent container. The default and `.Toolbar` variants
use neutral surfaces; `.Primary` uses the theme accent; `.Quiet` has no idle
surface; and `.Tab` keeps an idle tab quiet, then marks the selected tab with
both a surface treatment and an underline.
Select them at the call site:

```odin
alicorn.button(&ui, "Open", variant=.Toolbar)
alicorn.button(&ui, "Save", variant=.Primary)
alicorn.button(&ui, "Dismiss", variant=.Quiet)
alicorn.button(&ui, "Files", state=alicorn.Button_State{selected=true}, variant=.Tab)
```

Each `Button_Recipe` names semantic surface/text roles and defines transforms
for selection, hover, press, and disabled state. Transforms blend semantic
roles in a fixed order: selected, hovered, pressed, then disabled. Later states
therefore take precedence while still composing with the earlier result.
Focus and semantic-active outlines are independent overlays and remain visible
alongside those fills. The inspector reports the selected variant, base recipe,
active state transforms, and focus overlay roles.

An immutable `Style_Theme` may override any variant in its
`button_recipes.recipes` array; an undefined variant uses Alicorn's built-in
recipe for that intent, resolved against the active palette. Theme registration
validates transform roles and blend amounts. `Button_State.quiet` remains as a
compatibility spelling for `.Quiet`; new call sites should use `variant`.

For example, copy a built-in toolbar recipe, adjust its hover transform, then
register the containing immutable theme:

```odin
theme := alicorn.DEFAULT_STYLE_THEME
toolbar := theme.button_recipes.recipes[int(alicorn.Button_Variant.Toolbar)]
toolbar.hovered = alicorn.Style_Transform{surface_role=.Accent, surface_mix=0.08}
theme.button_recipes.recipes[int(alicorn.Button_Variant.Toolbar)] = toolbar
theme_id := alicorn.style_theme_register(&rt, theme)
```

Checkboxes toggle by pointer or Space; Enter is reserved for button activation.
Sliders drag with the pointer, adjust down with Left/Down and up with Right/Up,
and jump to their exact minimum/maximum with Home/End. A slider's `step=0` means
continuous pointer input and one-percent-of-range keyboard steps; a positive
step snaps to the nearest increment from the minimum while keeping both
endpoints reachable. Both controls clamp values to their range and ignore
input while disabled. They do not own application state: store the returned
`value` when `changed` is true. Their default sizes are content-aware; set
`Layout_Style` when a specific size is desired.

### Tab bars

`tab_bar(ui, key, items, options, style)` describes a complete tab bar as one
composite control and returns a `Tab_Bar_Result`. Internally, the retained
tree uses a `Scroll_Region` labelled `tab-bar`, a `Virtual_List` row, semantic
`Tab` controls, a content row, and an internal `Tab_Close` action. The selected
underline and dirty marker are composed with semantic surface nodes; their
bounds and clipping come from normal layout, and the renderer sees only the
resulting generic surface/text commands. This is the first built-in consumer
of Alicorn's high-level visual-part composition path. The separate `.Tab`
`Button_Variant` remains available for simple selectable buttons.

Each `Tab_Bar_Item` contains:

| Field | Meaning |
| --- | --- |
| `key: UI_Key` | Required, unique, stable identity for this item across descriptions and reordering. |
| `label: string` | Display label for the tab. |
| `selected: bool` | Application-provided selected state. |
| `closable: bool` | Whether the tab presents its internal close action. |
| `dirty: bool` | Whether the tab presents its dirty-state indicator. |
| `semantic_id: Semantic_ID` | Stable logical identity used by the existing semantic drag/drop events. |

`Tab_Bar_Options` supplies `min_tab_width`, `max_tab_width`, `height`, `gap`,
`close_policy`, and `drag_type`. Width, height, and gap are in logical window
units. Tabs shrink by equal amounts from the maximum width toward the minimum
width as space becomes constrained. If the bar is still too narrow when tabs
reach their minimum width, it uses horizontal overflow; the selected tab is
kept visible. Accessible Scroll tabs left/right controls appear while the bar
overflows, and the bar also accepts horizontal wheel/trackpad scrolling. The
close affordance is internal to the tab surface, retains a 24×24 logical hit
target, and its hover visibility does not change tab layout or width. Inactive
tabs show a distinct rounded close-action surface on hover; dirty state uses
the same reserved trailing slot, so switching between its marker and close
action does not shift the title. For dirty tabs, the marker remains visible
while hovering the tab body; it is replaced by the close glyph only when the
pointer enters the close action itself (or while that action is pressed).
Moving into a hidden close slot reveals it, but clicking the invisible slot
without first hovering does not activate Close. `Always` explicitly shows the
close glyph even for dirty tabs. Selection remains visible independently of
the keyboard-focus ring; pointer focus does not add a second focus outline.

The close policies are `Always`, `Hover`, `Selected_Or_Hover`, and `Auto`.
`Auto` delegates close-affordance visibility to the component's responsive
policy; applications should not depend on a particular width breakpoint.
`Tab_Bar_Result.action` is `None`, `Select`, or `Close`; for `Select` and
`Close`, `item_index` identifies the corresponding item in the input `items`
slice. The result is a request: the application updates its own selected state
or performs its own close workflow, then describes the resulting state on the
next build.

Provide a nonzero `drag_type` and stable item `semantic_id`s to participate in
Alicorn's existing drag/drop events. The bar identifies semantic sources and
reorder targets, paints a clear insertion marker, and edge-autoscrolls while a
drag is held near an overflowing edge; the application handles the events and
changes its own item order. The widget does not mutate the supplied slice or
own application data.

`tab_bar_navigate(item_count, selected_index, navigation) -> (index, found)`
computes a navigation target using `Next`, `Previous`, `Index_1` through
`Index_8`, or `Last`. When `found` is true, `index` identifies the target in
the item sequence; otherwise there is no navigation target. Applications
apply a found index to their own state. This helper does not install global
key bindings: Ctrl/Cmd shortcuts and their platform policy remain application
commands.

The retained node kinds distinguish tabs and their close actions internally,
but Alicorn does not yet expose a native platform accessibility tree. This
component therefore does not make tabs available to VoiceOver, Narrator, or
other screen readers.

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

### Accessibility boundary

These semantic IDs and focus states are runtime interaction data, not a
platform accessibility tree. `Action_ID` names an application command; it does
not automatically expose a control's accessible role, name, value, or actions
to UI Automation, NSAccessibility, or a screen reader. The current runtime has
no bridge that publishes its GPU-rendered node tree to those platform APIs.
Native host menus and dialogs are OS-owned services, but custom Alicorn
controls and context menus remain outside that accessibility tree. See the
[guide's accessibility status](guide.md#accessibility-status).

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

### Tooltips

Call `tooltip(ui, text, delay_ms)` immediately after describing the control that
owns the help text. The default delay is 500 ms; Alicorn retains the label with
that node and anchors a small popup to its bounds. The native event loop waits
for the one-shot hover deadline instead of polling. The popup flips and clamps
to the viewport, remains hit-test transparent, and never takes keyboard focus.
Pointer exit, a press, keyboard input, focus loss, or a modal/context menu
dismisses it. Once shown or dismissed, no recurring timer remains armed.

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
- The native `Run` host accepts `--inspector` (enable `F9`) and
  `--inspector-open` (enable and show immediately). Its built-in visual
  inspector uses a separate Alicorn runtime above the application, preserving
  app focus and keeping inspector work out of application stage counters.
  `Escape` closes it. Tree selection and Pick inspect retained nodes without
  invoking app controls. No app-private data or callback is required. See
  [Native diagnostics](development.md#native-diagnostics) for usage and capture.
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
  surface path. Waveform updates accept at most
  `GPU_SURFACE_MAX_WAVEFORM_SAMPLES` (1,365) samples; larger updates return
  `false` without changing the current payload. Declarations do not take a
  revision; ordinary waveform and geometry updates advance the retained
  payload revision internally. `gpu_surface_update_versioned` and
  `gpu_surface_update_geometry_versioned` are for callers that need strict
  latest-wins ordering, and reject equal or stale revisions. Update APIs must
  run on the runtime's owning/UI thread. `gpu_surface_clear` explicitly
  removes the payload while retaining the surface node. Surfaces do not
  participate in retained hit testing, focus, or pointer capture unless their
  declaration opts in with `GPU_Surface_Interaction.Pointer`. The sample limit
  accounts for the background quad and six vertices per adjacent sample pair
  within `GPU_SURFACE_MAX_VERTICES`. Keep GPU handles and rendering callbacks
  inside the host; the application supplies typed data, not SDL command
  buffers.

For the ownership and lifecycle model behind these calls, see
[Architecture](architecture.md).
