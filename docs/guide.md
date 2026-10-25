# Building Alicorn applications

An Alicorn application owns its data and describes its UI with ordinary Odin
control flow. The [native starter](../examples/01_hello/main.odin) uses the
typed `alicorn:ui` entry point; this guide shows how to grow from that path to
the lower-level runtime.

## Learn Alicorn progressively

Start with the `ui` package. It writes ordinary retained Alicorn nodes and
uses the same Runtime as the detailed API below.

1. **Text, buttons, and application state:** `ui.text`, `ui.button`, and
   `ui.run`; state remains in your struct.
2. **Containers and layout:** `ui.row`, `ui.column`, and `ui.panel` provide
   scoped layout, while `ui.box` describes a leaf surface.
3. **Repeated data:** pass stable keys for items that can move or be inserted.
4. **Scrolling and virtual collections:** use retained scroll regions and
   virtual-list APIs when a collection is larger than its viewport.
5. **Regions and reuse:** add explicit revisions when a subtree can be reused
   independently from the rest of the description.
6. **Async host wake:** use ordinary app-owned workers and the native host's
   waker service when background results need to wake an idle window.
7. **GPU and custom surfaces:** update retained geometry or versioned image
   surfaces for specialized visualizations.
8. **Runtime, allocator, and diagnostics:** use explicit invalidation,
   allocation configuration, tracing, and inspection when the application
   needs those controls.

The simple package does not own application state or retain a second widget
tree. `ui.run` is the routine single-window host path; applications that need
native callbacks such as custom wake handling can use `host.Run` and pass the
same `^alicorn.UI` description context to both convenience helpers and direct
runtime calls.

`ui.run` uses Alicorn's existing bounded correction policy after consumed UI
actions. The description can therefore run again after a click: keep file I/O,
worker submissions, and other external side effects behind consumed actions
or explicit application transitions. For custom async wake, initialization,
or native event callbacks, use `host.Run` instead. That path keeps explicit
invalidation and host-service ownership available.

Convenience sizing is local to `ui`: the application root fills the viewport;
rows and columns use their allocated width and fit their children's height;
text uses normal text measurement; buttons keep their existing intrinsic
control size; and a `ui.box` defaults to 24 by 24 logical units. Pass `grow=1`
when a row, column, or panel should take a share of its parent's remaining
main-axis space. Explicit box width or height overrides its square `size`;
explicit row or column dimensions and `grow` are passed to the existing layout
rules. The lower-level `Layout_Style` contract is unchanged.

For an exact layout escape route, import `alicorn:runtime` alongside `ui` and
use `if ui.layout(ctx, existing_style, label="Inspector") { ... }`. It scopes
one plain container with the supplied style, including constraints, without
changing defaults. Rows, columns, and panels also accept diagnostic labels.
`ui.text` forwards typed `style`, `font`, and `text_style`; a positive `size`
overrides only the font size. `ui.button` forwards typed styling, state, content
alignment, and variants; `width=96, height=28` can replace a layout constructor,
and nonnegative `grow` overrides that style field. Omitted sizing overrides
leave the supplied style intact. These helpers share the same context and
one-shot control behavior as direct runtime calls.

`ui.text` currently uses Alicorn's existing `DEFAULT_COLOR` unless a color is
passed explicitly; it does not yet resolve the active theme's semantic Text
role. The typed `ui.run` path also does not yet expose initialization, shutdown,
or native event callbacks. Use `host.Run` for runtime-specific setup/cleanup or
custom host services; theme-aware default text color and typed lifecycle hooks
are follow-up API work.

`ui.panel` is a column layout with a retained surface. An omitted fill uses
the active theme's Surface role; `fill`, `radius`, and `stroke` provide direct
appearance options. `ui.border(width, color)` places the stroke inside the
resolved bounds by default; pass `.Centered` or `.Outside` as its third
argument to change placement. Use `ui.row` and `ui.column` for arranging content,
`ui.box` for a colored leaf, and `ui.panel` when children need a surface.
Advanced materials and GPU surfaces remain in the runtime API.

Scoped layout calls are intended to appear directly in an `if` condition:

```odin
if ui.column(ctx, padding=12, gap=8) {
	ui.text(ctx, "Settings")
	if ui.row(ctx, gap=8) {
		// children
	}
}
```

Odin's [deferred procedure attributes](https://odin-lang.org/docs/attributes/)
close the scope at the end of the surrounding lexical scope. An early `return`,
`break`, or `continue` still closes it. Keep a scoped call as the direct
condition: assigning its result defers cleanup to the containing scope, and
short-circuit expressions can prevent a deferred call from being registered.

## Keep state in your application

Use normal structs, slices, maps, and procedures for domain state. A button
returns `true` when activated, so ordinary control flow updates that state:

```odin
if ui.button(ctx, "Pause") {
	app.paused = !app.paused
}
```

The broader runtime API exposes controls that are not duplicated in the small
facade. Import `alicorn:runtime` alongside `alicorn:ui` to use those controls
with the same context:

```odin
enabled := alicorn.checkbox(ctx, "Show grid", app.show_grid)
if enabled.changed {
	app.show_grid = enabled.value
}

gain := alicorn.slider_f32(ctx, "Gain", app.gain, 0, 1, 0.05)
if gain.changed {
	app.gain = gain.value
}
```

Both controls report a proposed value; the application stores it. A slider's
optional step is `0` for continuous input or a positive snapping increment.

The runtime retains UI identity and interaction state, but does not observe
arbitrary application memory. When a logical change needs a new description,
invalidate the root or the affected region. The native host handles ordinary
pointer and window input and schedules the next build.

For a form or search field, `Text_Field_Buffer` gives committed text explicit
application ownership without retaining a pointer into app state. Initialize
it once with an allocator and destroy it with the app; describe it with
`text_field_controlled` and use the returned `changed` flag to update dependent
state. IME preedit remains transient runtime state. Programmatic replacements
use `text_field_buffer_set` and the application's normal invalidation path.
The lower-level `text_field` and host edit callback remain available when that
fits the application better.

## Load application fonts and images

Load app-owned fonts in `Application.on_initialize`. It runs after Alicorn
creates the Runtime and before the native host installs its default faces or
creates renderer resources. Font loading copies the input, replaces the
selected face only after validation succeeds, and invalidates shaped text and
glyph resources. The callback runs on the application thread:

```odin
Demo_App :: struct {
	logo: alicorn.Image_Handle,
}

APP_UI_FONT :: #load("assets/StudioSans.ttf")
APP_LOGO_PNG :: #load("assets/studio-logo.png")

initialize :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	app := cast(^Demo_App)state
	if !alicorn.font_load_bytes(rt, .UI, APP_UI_FONT) {
		// Keep the host default face if the app asset is invalid.
	}
	logo, err := alicorn.image_load_bytes(rt, APP_LOGO_PNG)
	if err == .None { app.logo = logo }
}
```

Use `.Monospace` for code-oriented text. Optional italic and fallback faces
can be installed with `font_load_italic_bytes` and
`font_load_fallback_bytes`. The app supplies the font license and distribution
rights. Call these APIs on the application thread; loading a face invalidates
text shaping and paint so retained content is rebuilt with the new font.

When an application does not supply a fallback, the Linux native host resolves
an optional symbol fallback through Fontconfig and verifies its glyph coverage
before loading it. It does not assume a distribution-specific path such as
`/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`. If Fontconfig, `fc-match`,
or the selected font is unavailable or unusable, the fallback remains optional
and the host continues with the bundled primary face.

`image_load_bytes` currently decodes PNG and QOI into Runtime-owned RGBA8
pixels. It copies decoded pixels, so a disk buffer can be released as soon as
the call returns. The image widget is a regular retained paint node, with
intrinsic pixel dimensions when no size is specified and an aspect ratio
preserved when only width or height is set:

```odin
// In build, among the other retained children:
alicorn.image(&ui, app.logo, alt_text="Studio logo", key=alicorn.key_string("logo"))
```

The `initialize` procedure is assigned to `host.Application.on_initialize`.
For a file loaded from disk, pass its bytes to the same APIs and release that
temporary buffer after the call; Alicorn retains its own copy.

Image handles belong to one Runtime and are never reused. Release them with
`image_release` after removing ordinary image widgets and custom-surface image
layers from the app's next presentation. The native renderer creates a texture
the first time an image is visible, retains it for the GPU-device lifetime,
and recreates it after device recreation. DPI changes scale retained bounds
through the ordinary layout and compositor path. A custom surface can retain a
bounded set of image layers with `gpu_surface_update_images`; each layer uses
surface-local logical bounds and paints above its background and below its
app-authored geometry.

```odin
layers := [1]alicorn.GPU_Surface_Image{
	alicorn.gpu_surface_image(app.logo, alicorn.Rect{8, 6, 32, 24}, opacity=0.9),
}
_ = alicorn.gpu_surface_update_images(rt, app.preview_surface, layers[:])
```

The surface must already be retained. The update copies its descriptors,
allows at most 256 layers, and schedules paint/presentation work without
re-describing application layout. Call it on the Runtime's owning thread.

The built-in decoder is intentionally small: PNG and QOI only, bounded to
128 MiB encoded input and 64 MiB decoded RGBA8 data. Alicorn does not search OS
font locations or infer licenses. Keep third-party attribution with the
application's distributed assets.

## Select a value

Use `select_control` when the user chooses one value from a fixed set. Keep the
selected key in application state and apply the returned change:

```odin
theme_options := [2]alicorn.Select_Option{
	{key=1, label="Warm"},
	{key=2, label="Cool Light"},
}
theme := alicorn.select_control(
	&ui,
	"settings-theme",
	"Theme",
	theme_options[:],
	app.theme_key,
)
if theme.changed {
	app.theme_key = theme.selected_key
}
```

The control supplies an anchored, scrollable listbox, keyboard navigation,
type-ahead, focus restoration, and Combo_Box/List_Box accessibility semantics.
Keep keys stable when the option order changes. The popup is an Alicorn overlay
and is added automatically when `end_frame` describes the retained frame.

## Describe layout with containers

Calls are nested in the same order as the layout. Choose `.Row` for horizontal
children and `.Column` for vertical children; name only the constraints you
need with `layout_style`:

```odin
alicorn.container_begin(
	&ui,
	.Container,
	label="toolbar",
	style=alicorn.layout_style(.Row, padding=8, gap=6, align=.Center),
)
alicorn.button(&ui, "Open", style=alicorn.layout_style(.Row, width=100, height=32), variant=.Toolbar)
alicorn.button(&ui, "Save", style=alicorn.layout_style(.Row, width=100, height=32), variant=.Primary)
alicorn.button(&ui, "Dismiss", style=alicorn.layout_style(.Row, width=100, height=32), variant=.Quiet)
alicorn.container_end(&ui)
```

`layout_style` is a small constructor, not a stylesheet. Button label alignment
and inner padding use `button_content_style`; parent layout padding controls
space around the button. Button variants express intent explicitly: the
default and `.Toolbar` are neutral, `.Primary` uses the theme accent, `.Quiet`
has no idle fill, `.Tab` provides a selection treatment, and `.Danger` marks
destructive actions. Recipes define
their semantic colors and state transforms; selected, hovered, pressed, then
disabled transforms apply in that order. Focus remains a separate outline.

For a product-specific visual control, keep the existing Button as the
interaction owner and describe its retained pieces as ordinary children:

```odin
owner, activated := alicorn.button_begin(
	&ui,
	"",
	key=alicorn.key_string("commit-row"),
	style=alicorn.layout_style(.Row, height=32),
)
label_id := alicorn.text(&ui, "4f19c2a  Fix editor layout", key=alicorn.key_string("label"))
_ = alicorn.visual_part_attach(
	&ui,
	label_id,
	owner,
	alicorn.visual_part_extension_id("app.history", "commit.subject"),
)
alicorn.button_end(&ui)
if activated { app.selected_commit = commit.id }
```

`button_begin` / `button_end` preserve Button focus and activation. Visual-part
identity adds inspectable owner/state metadata; ordinary retained layout still
controls ordering, bounds, and clipping. Use visual parts to describe
presentation, not to create another interaction system. A retained container
or semantic surface can own always-visible parts; hover/selection visibility
and Button recipe inheritance remain tied to owners that expose those states.
See [Visual parts under an existing control](reference.md#visual-parts-under-an-existing-control)
for attachment validation, core roles, namespaced identities, and owner-state
visibility policies.

For document-style tabs, use the composite `tab_bar` contract rather than
assembling a tab button beside a separate close button. Each item has a stable
`UI_Key`; the application still owns the selected item, document lifecycle,
and item order. See the [Tab Bar reference](reference.md#tab-bars) for sizing,
close policies, navigation semantics, and drag/drop behavior. The `.Tab`
button variant remains appropriate for a standalone selectable button.

The Tab Bar reports selection and close requests by item index. Apply those
requests to application state and describe the updated items on the next build:

```odin
result := alicorn.tab_bar(
	&ui,
	alicorn.key_string("document-tabs"),
	items,
	options,
	style,
)
if result.action == .Select {
	app.active_tab_key = items[result.item_index].key
} else if result.action == .Close {
	request_close(items[result.item_index].key)
}
```

`items` supplies each tab's selected, closable, and dirty state. Use
`tab_bar_navigate(item_count, selected_index, navigation)` from the
application's command handling to share the component's
Next/Previous/index/Last navigation semantics. It returns `(index, found)`;
apply `index` only when `found` is true. Choose Ctrl/Cmd bindings in the
application rather than assuming the runtime installs them.

For reordering, consume the existing drag/drop events and update the
application-owned order. `Semantic_ID` is also used by Alicorn's backend-neutral
semantic model; it is not a native screen-reader accessibility interface.

## Give repeated data stable identity

For a repeated item, its logical key—not its current row number or visible
label—lets focus and other retained state follow it through reordering:

```odin
for item in app.items {
	if alicorn.component_begin(&ui, alicorn.key_u64(item.id)) {
		if alicorn.button(&ui, item.name) {
			app.selected_id = item.id
		}
		alicorn.component_end(&ui)
	}
}
```

Use `key_string`, `key_u64`, or `key_pair` to match the identity you already
have. The call site identifies the kind of UI; the key identifies the data
item.

If keyboard operation must stay with a logical item while its row is
virtualized or replaced by another presentation, use semantic focus; the
[reference](reference.md#semantic-focus-in-virtualized-views) explains the
small identity/binding API.

## Grow only when the app needs it

Start with the root description. Add more specialized mechanisms for a real
need:

- `virtual_list_begin/end` for a large, fixed-height collection;
- `region_begin/end` with an application-owned revision when an unchanged
  subtree is expensive to describe;
- `split_begin/end` for retained, draggable panes;
- `text_field` and the host text-change callback for editable text. Text
  fields also own normal mouse selection: click-drag selects graphemes,
  double-click selects a word, triple-click selects a logical line, and
  Shift-click extends the current selection;
- `Text_Field_Buffer` and `text_field_controlled` when an app-owned form or
  search string should adopt committed input through one explicit allocator
  contract. The host never retains the application's buffer pointer;
- `.Correct_After_Interaction` on a native `Application` for a small app whose
  controls update ordinary app state during the UI description. A consumed
  activation or controlled-value result requests a corrective description
  before presentation, so labels can appear before or after their controls.
  The default `.Explicit` policy is unchanged; regions still require their
  own revision updates, and no application memory is observed or polled;
- a custom GPU surface for a bounded, high-frequency visualization.

This policy is opt-in. State remains application-owned, and the policy uses
the existing bounded host stabilization loop; it does not create a reactive
model or change the explicit invalidation contract for advanced applications.

During development, [application mutation diagnostics](application-mutation-diagnostics.md)
can check that selected app-owned revisions schedule the corresponding
description or presentation work.

For aligned label/value layouts, use the small retained Grid rather than
nesting Rows to reproduce the same columns:

```odin
columns := [2]alicorn.Grid_Track{alicorn.grid_fixed(88), alicorn.grid_fraction(1)}
rows := [3]alicorn.Grid_Track{alicorn.grid_auto(), alicorn.grid_auto(), alicorn.grid_auto()}
alicorn.grid_begin(&ui, alicorn.key_string("commit-details"), columns[:], rows[:],
	style=alicorn.layout_style(width=480, height=120), gap_x=8, gap_y=4)
author_label := alicorn.text(&ui, "Author")
_ = alicorn.grid_cell(&ui, author_label, 0, 0)
author_value := alicorn.text(&ui, commit.author)
_ = alicorn.grid_cell(&ui, author_value, 0, 1)
// Emit and place each remaining label/value pair in its own row.
alicorn.grid_end(&ui)
```

Every Grid child has an explicit cell. The supported track and span behavior,
and the fixed width-before-height solve order, are described in the
[layout reference](reference.md#shared-track-grid).
For fixed parent-assigned Grid bounds whose cell content may reflow locally,
pass `layout_boundary=true` to contain both axes, or `layout_boundary_axes`
to contain only stable dimensions. FIT_CONTENT dimensions always propagate
to the Grid's parent.

These APIs do not replace application state. In particular, Alicorn does not
infer that a region changed: increment its revision when its logical content
changes. See the [reference](reference.md) for the relevant APIs and details.

For a transient modal surface such as a command picker, describe the normal
workspace first, close its root, then add `modal_overlay_begin/end` as a second
top-level root. It paints above the workspace and confines pointer, wheel, and
tab-focus handling until omitted from a later description. The application
still owns dismissal and focus restoration. The overlay fills the viewport, but
its child panels follow normal layout rules: generic containers do not size
themselves to their descendants, so give transient panels an explicit or
application-computed height. See the API
[reference](reference.md#transient-modal-surfaces).

Attach delayed help to a just-described control with `tooltip(&ui, text)`. The
native host waits for the hover deadline; the popup remains pointer-transparent
and does not change focus. See the
[tooltip reference](reference.md#tooltips) for dismissal and placement behavior.

For a single-level context menu, handle secondary-click (or the host's
Shift+F10 `Application_Key.Context_Menu`) in the application and open it with
`context_menu_open`. Keep the semantic context target in application state.
After describing the ordinary root, add the menu with
`context_menu_begin/item/separator/end`; dispatch the `Action_ID` returned by
`context_menu_end` through the app's existing command handler. The popup owns
navigation, placement, outside-click dismissal, and focus restoration. See the
[context-menu reference](reference.md#context-menus).

## Report an application notice

Choose a notice presentation based on what the user needs to do. A brief
success message can expire automatically; a failed save or retryable workspace
operation should remain until the application resolves or dismisses it. A
blocking decision still belongs in a modal dialog. For example:

```odin
retry_action := [1]alicorn.Notice_Action{{id=RETRY_SCAN, label="Retry"}}
_ = alicorn.notice_post(rt, alicorn.Notice{
	id="workspace-scan-failure",
	title="Couldn't refresh folder",
	message="The folder's contents may be out of date.",
	details=original_error,
	severity=.Warning,
	lifetime=.Persistent,
	placement=.Toast,
	actions=retry_action[:],
}, monotonic_now_ns)

if event, ok := alicorn.notice_take_action(rt); ok {
	if event.action == RETRY_SCAN {
		start_workspace_scan(app)
	}
}
```

Alicorn keeps notice text and action storage bounded, deduplicates by stable
ID, draws notices in an independent overlay, and schedules a one-shot wake for
transient expiry. The app owns severity, lifetime, retry behavior, and
dismissal. Notices do not take editor focus or move the main layout. See the
[Notice reference](reference.md#notices) for queue limits and accessibility
announcements.

## Accessibility status

Alicorn has keyboard-level interaction support: Tab and Shift+Tab traverse
focusable controls, buttons activate from the keyboard, checkboxes toggle with
Space, sliders respond to their documented keys, and text fields use the
native text-input path, including composition events. Focus has a visible
runtime presentation. Applications can also publish stable `Action_ID`s for
commands and use `Semantic_ID` to keep logical focus attached to an item whose
visual row may be virtualized; these APIs keep app behavior and identity
explicit. The runtime can retain semantic entities separately from visual
nodes, publish a full `semantic_snapshot`, or expose the newest
`semantic_update_since` delta. Deltas describe one `from_revision` →
`to_revision` transition; only the latest transition is retained. If a consumer
asks from a different base revision, it must obtain a new snapshot rather than
apply a discontinuous delta. A caller already at the current revision gets an
empty update; any other base must match the single retained transition or
requires a snapshot. The native Windows/macOS host projects these snapshots
and deltas through AccessKit; the semantic runtime remains the source of truth.
Select controls expose Combo_Box, List_Box, and List_Box_Option semantics.
Notices expose polite Status or assertive Alert live regions and never steal
keyboard focus. This is bridge coverage; native Narrator/NVDA/VoiceOver behavior
still needs platform testing.

Ordinary visual `Text` is intentionally not exported automatically. For
standalone informational copy, call `semantic_static_text` immediately after
`text`; it exposes that text as a `Static_Text` entity (mapped to AccessKit's
Label role, whose text content is carried as its value). Text that already
names a control should remain part of that control's semantic name rather than
being annotated a second time. Rich editor/document text uses a specialized
semantic model: a `Text_Area` with logical `Text_Run` children. Alicorn's
native AccessKit projection publishes selectable-unit byte lengths, text
selection, `SetTextSelection`, and `ReplaceSelectedText`. Application code must
still publish a complete, revision-consistent text projection and apply queued
requests through its normal editor mutation path. AccessKit stores each
selectable unit's UTF-8 length in an 8-bit field, so a single unit longer than
255 bytes cannot be represented directly.

Sliders retain their numeric value, range, and step for assistive technology.
If the normalized number is not meaningful to users, call
`semantic_range_value_text(&ui, "65%")` immediately after `slider_f32` to add
an optional human-readable value such as a percentage, decibels, or a formatted
frequency without replacing the numeric range. The application owns formatting
and locale; `02_form` demonstrates this for its sliders.

Virtual collections use `semantic_collection_begin` with
`semantic_collection_item` for realized rows and `semantic_collection_virtual_item`
for logical items that need description without visual realization. The
application supplies only its semantic working set; Alicorn retains collection
metadata rather than eagerly constructing one semantic record for every
logical item. Items described for a collection are pruned as its working set
moves, except items pinned as current, selected, or semantic-focus targets.
Collection item records carry their logical position and total set size. The
application remains responsible for describing useful items and for handling
requests: `semantic_action_request` can route supported realized actions
through Alicorn's normal activation/focus paths or queue a logical Perform
event; `semantic_reveal_request` queues a distinct Reveal event. During the
resulting application wake, the app drains queued events with
`semantic_request_pop` and releases transferred event data with
`semantic_request_event_destroy`.

Tests exercise a million-item collection while retaining a small working set,
including visible-only, horizon, and current/selected/focused-pinned cases.
This is an implementation and bounded-memory proof, not evidence that an
assistive-technology client can navigate gaps in a platform accessibility
tree.

The native host currently links AccessKit 0.23.1 on Windows and macOS and
projects common controls, text fields, text areas/runs, tabs, and the bounded
semantic collection working set. AccessKit activation requests a full bounded
snapshot; later updates are applied only from the adapter's exact revision,
otherwise a full snapshot is sent. Native actions route through Alicorn's
semantic action/reveal APIs on the UI thread, not synthetic pointer events.
Text-run action payloads are validated against the current semantic projection
before they enter the application queue. The bridge has no Linux platform
adapter, and real Narrator/NVDA/VoiceOver behavior still requires manual
validation.

`Style_Environment` can separately carry normalized accessibility appearance
preferences such as increased contrast, reduced transparency, reduced motion,
and non-color state cues. These inputs affect visual recipes/materials only;
they do not create, rename, or modify semantic entities. The application or
host supplies these values; Alicorn does not yet query OS accessibility
preferences automatically.

This is an **experimental integration, not yet a validated screen-reader
experience**. Windows and macOS builds compile and link, but real Narrator,
NVDA, and VoiceOver traversal/action behavior has not yet been certified. In
particular, the million-item test proves bounded semantic storage, not that a
screen reader can cross gaps in the bounded exported tree. The Alicorn runtime
and native bridge now support a Text_Area/Text_Run projection and queued text
selection/replacement actions; applications still need to supply a complete
text model and handle those requests. Alicorn-rendered context menus and other
custom controls may also have incomplete platform semantics. Native menus and
dialogs continue to use OS facilities.

Semantic updates are dirty-driven and do not start an idle polling loop.
Accessibility activation may cause a one-shot host wake to build a bounded
initial projection; it does not start a timer. For now, treat keyboard
reachability and screen-reader support as separate capabilities, and verify
assistive-technology behavior on each target platform before relying on it.
See the [reference](reference.md#semantic-model-and-collections) for the API
boundary and virtualization limitations.

## When something looks wrong

Launch a native app with `--inspector` and press `F9` for the built-in visual
inspector, or use `--inspector-open` to show it at startup. Its tree, focus,
work, and causality tabs read retained runtime truth; Pick selects an app node
without activating it. While the inspector is open, clicks and scrolling
outside its panel still reach the app. The app keeps keyboard and IME input
until you click inside the inspector; clicking the app returns that input to
it, except that Pick temporarily intercepts app clicks for selection. Close
returns input to the application's existing focus. The native host also has
diagnostic captures; see
[Development](development.md#native-diagnostics). For the design boundaries,
see [Architecture](architecture.md).
