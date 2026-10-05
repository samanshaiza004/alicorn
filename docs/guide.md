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
explicit.

These features are **not** a platform accessibility bridge. Alicorn does not
currently expose its retained controls as UI Automation elements on Windows
or an Accessibility/NSAccessibility tree on macOS. Consequently, VoiceOver,
Narrator, and other screen readers cannot inspect or operate the ordinary
GPU-rendered Alicorn control tree through native accessibility APIs. A
`Semantic_ID` identifies an app entity for Alicorn; it is not an accessible
role, label, value, or platform element. Native application menus and dialogs
use OS facilities; that does not make Alicorn-rendered context menus or
controls accessible to assistive technology.

For v0.1, treat keyboard reachability and screen-reader accessibility as
separate capabilities. The intended direction is to build any future platform
bridge from the existing control, action, focus, and semantic state rather
than infer accessibility from paint output or add a parallel application
command model. See the [reference](reference.md#accessibility-boundary) for
the API boundary and limitations.

## When something looks wrong

Launch a native app with `--inspector` and press `F9` for the built-in visual
inspector, or use `--inspector-open` to show it at startup. Its tree, focus,
work, and causality tabs read retained runtime truth; Pick selects an app node
without activating it. Close returns input to the application's existing
focus. The native host also has diagnostic captures; see
[Development](development.md#native-diagnostics). For the design boundaries,
see [Architecture](architecture.md).
