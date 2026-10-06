# Building Alicorn applications

An Alicorn application owns its data and describes its UI with ordinary Odin
control flow. The [native starter](../examples/01_hello/main.odin) is a
small complete example; this guide explains the patterns to grow it.

## Keep state in your application

Use normal structs, slices, maps, and procedures for domain state. A button
returns `true` when activated, so ordinary control flow updates that state:

```odin
if alicorn.button(&ui, "Pause") {
	app.paused = !app.paused
}

enabled := alicorn.checkbox(&ui, "Show grid", app.show_grid)
if enabled.changed {
	app.show_grid = enabled.value
}

gain := alicorn.slider_f32(&ui, "Gain", app.gain, 0, 1, 0.05)
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
has no idle fill, and `.Tab` provides a selection treatment. Recipes define
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
- `text_field` and the host text-change callback for editable text;
- a custom GPU surface for a bounded, high-frequency visualization.

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
requires a snapshot. This API is currently an internal, backend-neutral
runtime API and is not connected to a native adapter.

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

These features are **not** a platform accessibility bridge. Alicorn does not
currently expose its retained controls as UI Automation elements on Windows
or an Accessibility/NSAccessibility tree on macOS. Consequently, VoiceOver,
Narrator, and other screen readers cannot inspect or operate the ordinary
GPU-rendered Alicorn control tree through native accessibility APIs. A
`Semantic_ID` identifies an app entity for Alicorn; it is not an accessible
role, label, value, or platform element. Native application menus and dialogs
use OS facilities; that does not make Alicorn-rendered context menus or
controls accessible to assistive technology.

Semantic updates are dirty-driven; they do not poll while idle. A future
activation path may request a bounded initial projection, but activation and
platform adapter work belong to #51 and are not implemented. For now, treat
keyboard reachability and screen-reader accessibility as separate
capabilities. See the [reference](reference.md#semantic-model-and-collections)
for the API boundary and limitations.

## When something looks wrong

Launch a native app with `--inspector` and press `F9` for the built-in visual
inspector, or use `--inspector-open` to show it at startup. Its tree, focus,
work, and causality tabs read retained runtime truth; Pick selects an app node
without activating it. Close returns input to the application's existing
focus. The native host also has diagnostic captures; see
[Development](development.md#native-diagnostics). For the design boundaries,
see [Architecture](architecture.md).
