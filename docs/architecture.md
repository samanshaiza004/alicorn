# Architecture

Alicorn is **direct to write, retained to run**. Application code describes
the interface procedurally; the runtime retains only the UI facts and products
that need to survive between descriptions.

```text
application-owned Odin state
              │
              ▼
       UI description
              │
              ▼
identity → reconcile → layout → paint → presentation
              │
              ▼
      native host / SDL_GPU
```

## Ownership

The application owns its model and decides when it changes. Alicorn owns
retained node identity, interaction state, geometry, text products, paint
products, and GPU-facing runtime resources. It does not observe arbitrary Odin
memory or keep application pointers in retained nodes.

The native host owns the window, input pump, application loop, GPU submission,
and resource lifetime. The app supplies ordinary callbacks and typed UI
descriptions; it never receives an SDL command buffer or render-pass pointer.

## Identity

A source location identifies a structural call site. A `UI_Key` distinguishes
repeated logical items at that site. Reusable components add a keyed identity
scope. Identity therefore remains stable when a keyed item moves, while a
duplicate key is reported rather than guessed from its current position.

Runtime node IDs are implementation identity, not persistent IDs for saving
data across program versions.

## Work and invalidation

`begin_frame` skips application description when the root is not invalidated.
After a logical mutation, the app explicitly invalidates the root or a region.
A region's revision lets Alicorn reuse an unchanged subtree; the application
must advance that revision when its output changes.

Description, reconciliation, layout, paint, and presentation have distinct
dirty state. An input-only change can update retained presentation without
asking the application to describe the whole UI again. Changed constraints
can require layout even when the description itself is reused.

This is explicit reuse, not automatic dependency tracking. A stale region
revision can produce stale content.

Runtime trace records can share a monotonic cause ID from input or another
external cause through semantic action, invalidation, retained work, and GPU submit.
The ring stays bounded. When separate causes collapse into one pending frame,
the frame's stage records are deliberately unassigned; the runtime does not
guess which input was responsible. An idle runtime creates no causes.

Applications publish stable action identity and explicit enabled/checked state
to their Alicorn runtime. The application still owns dispatch and behavior;
menus, shortcuts, direct controls, and palettes can share the same `Action_ID`
without introducing a global command registry or reactive state system.

## Native and text boundaries

The runtime is platform-neutral Odin code. `native/sdl_gpu` adapts SDL3 input,
window metrics, native text input, and SDL_GPU composition. Text shaping and
layout products are kept separate from DPI-specific GPU glyph residency.
Bundled fonts and their licenses are documented in
[`assets/fonts/README.md`](../assets/fonts/README.md).

The host waits for events when idle. Worker completions can wake it through an
opaque `Application_Waker`; the UI remains on the window thread. The runtime
does not create application threads or observe external state.

Applications that need delayed refreshes can use the host's two-slot
`Application_Scheduler`. A slot is either `Frequent` or `Opportunistic`; each
class owns one replaceable deadline, and callbacks run on the UI thread with a
`Scheduled_Wake` cause. Opportunistic deadlines wait until 150 ms after the
last keyboard or pointer input. The host sleeps until the next deadline or
native event, and no callback rearms itself automatically, so canceling both
slots returns the application to true idle. This is for bounded refresh
cadences, not animations or general-purpose task queues.

## Boundaries and current scope

The current surface API supports typed retained presentation data; it is not
an application shader API. Accessibility integration, broader platform
validation, and additional advanced text behavior remain future work. The
project is experimental, and its API may change.
