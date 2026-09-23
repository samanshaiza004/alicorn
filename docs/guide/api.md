# Canonical API

This is the small API most applications should use. The runtime derives the
source site from Odin's `#caller_location`; application code normally does not
construct `Source_Site` values.

```odin
alicorn.text(ui, "Processes")

if alicorn.button(ui, "Pause", state=alicorn.Button_State{disabled=false}) {
	app.paused = !app.paused
}

alicorn.text_field(ui, app.filter)
```

`button` returns a `bool`. A true result is one activation. `text` and
`text_field` return a `Node_ID` when the application needs to focus or inspect
the emitted node; most applications can ignore that result.

Text weight is separate from layout geometry and uses a `Text_Style` value.
The default is regular (400); use the named constants for common hierarchy:

```odin
alicorn.text(&ui, "Changed files (6)", text_style=alicorn.Text_Style{
	font_weight = alicorn.FONT_WEIGHT_SEMIBOLD,
})
```

The bundled variable UI and monospace faces apply the requested OpenType
`wght` axis. Text products and intrinsic layout are rebuilt when weight
changes. A loaded static font without a `wght` axis stays at its native weight.

## Layout defaults

`layout_style` is a small named-field constructor for the common case. It
starts with Alicorn's normal defaults (`-1` for unconstrained dimensions,
stretch alignment, zero spacing, and no clip) so an application names only the
layout intent it needs:

```odin
alicorn.button(ui, "Refresh", style=alicorn.layout_style(.Row, width=100, height=30))
alicorn.container_begin(ui, .Container, style=alicorn.layout_style(grow=1, padding=8, clip=true))
```

`Layout_Style{...}` remains available for unusual or fully explicit layouts.
The constructor is not a stylesheet or a token system.

## Repeated data

Call `component_begin` around a reusable component and give it a stable key:

```odin
for process in app.processes {
	if alicorn.component_begin(ui, alicorn.key_pair(u64(process.pid), process.start_time)) {
		alicorn.text(ui, process.name)
		alicorn.component_end(ui)
	}
}
```

The caller location identifies the structural program site. The key identifies
the repeated runtime data instance. Do not use a viewport index as a logical
key when rows can reorder.

## State

`Button_State{selected=..., disabled=...}` is the normal way to express those
semantic states. Disabled controls do not receive hit tests, focus, capture, or
activation. `selected` changes the control's presentation and retained
interaction projection.

`region`, `virtual_list`, and `gpu_surface` are also canonical APIs. Use them
when the application has a real explicit revision, bounded fixed-height rows,
or a high-frequency domain surface. They are not required for a first window.

## Fixed-row virtual lists

For a retained scrollable collection with uniform row height, use
`virtual_list_begin/end`. The runtime owns the scroll offset, resolved
viewport, clipping, fractional leading offset, and visible range. The
application still owns the collection, stable logical key, selection, and row
contents:

```odin
list := alicorn.virtual_list_begin(
	ui,
	len(app.files),
	24,
	key=alicorn.key_string("files"),
	style=alicorn.layout_style(grow=1, clip=true),
	scrollbars=.Auto,
)
for position := list.first; position < list.last; position += 1 {
	file := app.files[position]
	if alicorn.component_begin(ui, alicorn.key_string(file.path)) {
		alicorn.text(ui, file.name)
		alicorn.component_end(ui)
	}
}
alicorn.virtual_list_end(ui, list)
```

This does not evaluate every logical item and does not retain a row callback or
application pointer. Auto scrollbars are solid and reserve space from the
effective viewport; both axes, thumb dragging, and track-click paging are
runtime-owned. Use `.Hidden` or `.Always` only when the application needs a
different visibility policy. For a custom canvas, variable-height collection,
or unusual two-dimensional layout, keep using
`scroll_region_begin`, `virtual_list_metrics`, and `container_begin` directly.
`virtual_list_ensure_visible` is the explicit navigation helper for fixed-row
selection.

## Resizable panes

A split owns its divider position under its key. Applications provide two
panes and minimum sizes; pointer capture, drag clamping, and the wider hit
target belong to the runtime. Nest splits to make three or more panes. Nesting
direction determines how each divider redistributes space. For three adjacent
panes `A | B | C`, use `[A | B] | C` when each divider should resize only its
immediate neighbors:

```text
[ A | B ] | C
  ^       ^
  A/B     B/C
```

With absolute split positions, `A | [B | C]` instead makes the `A/B`
divider resize `A` against the whole right-hand group; the nested `B/C` split
keeps its own position as that group changes size. Choose the nesting to match
the intended resize behavior.

For example, the adjacent-neighbor form is:

```odin
outer := alicorn.split_begin(
	ui,
	key=alicorn.key_string("workspace-detail"),
	axis=.Horizontal,
	initial=740, // A + B
	min_first=452,
	min_second=280,
	style=alicorn.layout_style(grow=1, clip=true),
)
alicorn.split_first_begin(ui, outer)
inner := alicorn.split_begin(
	ui,
	key=alicorn.key_string("sidebar-content"),
	axis=.Horizontal,
	initial=240,
	min_first=150,
	min_second=300,
	style=alicorn.layout_style(grow=1, clip=true),
)
alicorn.split_first_begin(ui, inner)
render_sidebar(ui) // A
alicorn.split_first_end(ui, inner)
alicorn.split_divider(ui, inner)
alicorn.split_second_begin(ui, inner)
render_content(ui) // B
alicorn.split_second_end(ui, inner)
alicorn.split_end(ui, inner)
alicorn.split_first_end(ui, outer)
alicorn.split_divider(ui, outer)
alicorn.split_second_begin(ui, outer)
render_inspector(ui) // C
alicorn.split_second_end(ui, outer)
alicorn.split_end(ui, outer)
```

Use `.Vertical` to stack panes. Drag state stays in Alicorn; it is not an
application model value or a foreign-backend command.

## Progressive disclosure

Most applications can learn Alicorn in this order:

1. `text`, `button`, and ordinary Odin state;
2. containers and `layout_style`;
3. `component_begin` plus stable keys for repeated data;
4. `virtual_list_begin/end` for fixed-row scrolling;
5. `region` and explicit revisions when a subtree is expensive;
6. host wake integration for application-owned background work;
7. GPU/custom surfaces;
8. runtime, allocator, and diagnostic depth.

The later levels are opt-in. A counter does not need regions, scroll routing,
allocator configuration, or an async model.
