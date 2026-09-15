# Odin-native API and memory ownership

This pass keeps Alicorn's normal application surface small while making the
runtime's stronger controls available to Odin programmers who need them.

## One canonical surface

The normal calls derive their source identity from `#caller_location`:

```odin
alicorn.text(ui, "Processes")

if alicorn.button(ui, "Pause", state=alicorn.Button_State{selected=app.paused}) {
	app.paused = !app.paused
}

for process in app.processes {
	if alicorn.component_begin(ui, alicorn.key_pair(u64(process.pid), process.start_time)) {
		alicorn.text(ui, process.name)
		alicorn.component_end(ui)
	}
}
```

The call site identifies the structural program site. The key identifies the
logical repeated data instance. This is the central identity lesson exposed to
newcomers; the hash and retained-node machinery stay in the runtime.

`button` returns only its activation `bool`. `button_ex` and the other `*_ex`
procedures remain for tests, diagnostics, explicit source identity, and other
advanced integrations that genuinely need a `Node_ID` or a controlled source.

`Button_State.disabled` is semantic, not cosmetic: a disabled button cannot be
hit, focused, captured, pressed, or activated. `selected` participates in its
visual retained state.

## Typed identity

`UI_Key` is a non-nil tagged union with unkeyed, string, numeric, and two-part
numeric variants. The variant is hashed as well as the value, so an unkeyed
emission, empty string, zero integer, and zero pair remain distinct. Numeric
keys avoid formatting and temporary string allocation in large keyed trees.

`Source_Site` is still exported as an advanced/testing escape hatch. It is not
part of the ordinary API contract.

## Allocator lifetime

`Runtime_Config` captures persistent and scratch backing allocators at runtime
construction. Alicorn wraps the persistent allocator for retained products and
creates an internal `mem.Dynamic_Arena` for frame/reconciliation scratch. The
runtime resets and destroys that arena itself; it never resets or frees an
application-owned temporary allocator.

All retained node data, child adjacency, display commands, text products,
composition strings, diagnostics, trace reasons, surface samples, and Runa
state are routed through the captured persistent allocator. The caller may
change ambient `context.allocator` after construction without changing these
ownership rules.

Runtime text caret, hit-test, selection, word-navigation, and paragraph-layout
work receives the runtime scratch allocator at its internal call sites. Public
text helpers retain an optional scratch-allocator parameter for callers that
need the same bounded lifetime. Native hosts likewise use a host-owned scratch
arena for renderer snapshots and reset it once per host iteration; neither
boundary resets the application's ambient temporary allocator.

`Runtime_Allocation_Stats` reports requested allocation calls and requested
bytes for these runtime-owned wrappers. It does not report RSS, committed
pages, allocator metadata, GPU memory, driver residency, or application-side
sampler allocations.

## Deliberate non-goals

This pass does not introduce a signal graph, mutation observation,
application-owned widget objects, an SOA node store, or a mandatory allocator
configuration path. Those would change the programming model rather than make
the existing model clearer.
