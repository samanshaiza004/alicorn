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
