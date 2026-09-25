# Building Alicorn applications

An Alicorn application owns its data and describes its UI with ordinary Odin
control flow. The [native starter](../examples/native_hello/main.odin) is a
small complete example; this guide explains the patterns to grow it.

## Keep state in your application

Use normal structs, slices, maps, and procedures for domain state. A button
returns `true` when activated, so ordinary control flow updates that state:

```odin
if alicorn.button(&ui, "Pause") {
	app.paused = !app.paused
}
```

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
alicorn.button(&ui, "Open", style=alicorn.layout_style(.Row, width=100, height=32))
alicorn.button(&ui, "Save", style=alicorn.layout_style(.Row, width=100, height=32))
alicorn.container_end(&ui)
```

`layout_style` is a small constructor, not a stylesheet. Button label alignment
and inner padding use `button_content_style`; parent layout padding controls
space around the button.

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

## When something looks wrong

Use the runtime inspector and trace to see identity, focus, bounds, invalidation
reasons, and visited work. The native host also has diagnostic captures; see
[Development](development.md#native-diagnostics). For the design boundaries,
see [Architecture](architecture.md).
