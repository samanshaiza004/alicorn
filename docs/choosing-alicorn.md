# Choosing Alicorn

Alicorn is an experimental, Odin-native runtime for small-to-medium native
desktop tools. Its central trade-off is unusual: you write the interface with
ordinary procedural Odin code, while the runtime retains UI identity,
interaction, layout, text, and rendering products between descriptions. This
is not a promise that Alicorn is the best GUI approach in general.

## The mental model: direct to write, retained to run

```text
application-owned data
        │ logical change / input command
        ▼
explicit invalidation or scheduled wake
        │ only when description is needed
        ▼
ordinary Odin UI description
        │ stable call sites + keys
        ▼
retained identity, focus, geometry, text and paint products
        │ dirty stages only
        ▼
native host presents; when idle, it waits for input or a deadline
```

The application owns domain state. Alicorn does not inspect arbitrary Odin
memory or infer that a field changed. It retains the UI state and derived
products needed to preserve focus, scroll, geometry, shaping, paint, and
bounded GPU resources. The native SDL3 host owns the window, input pump,
platform services, GPU submission, and event-driven loop.

### State and description

**Problem:** Keep application logic ordinary without reconstructing all UI
execution work on every host iteration.

**Use it when:** State changes should produce a new description, while idle
frames or small interactions should reuse unchanged runtime work.

```odin
if alicorn.button(&ui, "Save") {
    app.saved = true
}
```

The app changes `app.saved` and explicitly invalidates the root or affected
region. A button result is an event, not storage owned by the button. A common
mistake is changing app memory and expecting the retained tree to notice.

Read [the application guide](guide.md#keep-state-in-your-application) and
[frame/invalidation reference](reference.md#frame-and-invalidation).

### Stable identity

**Problem:** Row positions and labels change; focus and retained state should
still belong to the same logical item.

**Use it when:** Emitting repeated items that may be inserted, removed,
filtered, or reordered.

```odin
for item in app.items {
    if alicorn.component_begin(&ui, alicorn.key_u64(item.id)) {
        alicorn.text(&ui, item.name)
        alicorn.component_end(&ui)
    }
}
```

Use the item's durable key, not its current index. Duplicate keys are a
diagnostic, not a request for positional fallback. See
[identity and repeated UI](guide.md#give-repeated-data-stable-identity).

### Explicit invalidation and regions

**Problem:** The runtime cannot safely watch application variables for
changes, and rebuilding a costly subtree may be unnecessary.

**Use it when:** App state changes, or an expensive subtree has a clear
application-owned revision.

After changing app state, call `invalidate_root(rt, "reason")`:

```odin
app.filter = next_filter
alicorn.invalidate_root(rt, "filter changed")
```

For a costly subtree, use `region_begin/end` (or its convenience form) with a
stable key and increment its revision whenever its described output changes.
A stale revision deliberately means stale content; do not use time or pointer
identity as a substitute for a real revision. The common mistake is to change
app memory without invalidation, or to change region output while leaving its
revision unchanged.

See [regions and revisions](reference.md#frame-and-invalidation) and the
[architecture overview](architecture.md#work-and-invalidation).

### Retained focus, scroll, and layout

**Problem:** Keyboard focus and scroll position should not disappear just
because a description is rebuilt.

**Use it when:** Building forms, split panes, virtualized views, or transient
modal/context UI. For example, reveal a selected fixed-row item with
`virtual_list_ensure_visible(rt, list_id, selected_index)`.

Focusable nodes retain keyboard focus; stable semantic focus can keep a
logical item focused while its row is temporarily virtualized away. Ordinary
layout is described in logical window coordinates. The host separately handles
physical drawable pixels and DPI. A common mistake is to use a current row
index as the identity for focus or selection.

Do not identify a row by its visible position, or assume keyboard focus,
application selection, and logical semantic focus are the same state. See
[layout and virtualization](guide.md#grow-only-when-the-app-needs-it),
[semantic focus](reference.md#semantic-focus-in-virtualized-views), and
[modal/context-menu APIs](reference.md#transient-modal-surfaces).

### Idle and scheduled work

**Problem:** A display-rate loop wastes work for tools that have no continuous
animation.

**Use it when:** The UI mostly changes on input or on a bounded refresh
deadline.

The native host waits for events when there is no work. Apps may request
one-shot frequent or opportunistic deadlines through
`application_schedule_after(scheduler, .Frequent, delay_ns)`; callbacks run on
the UI thread and are not automatically rearmed. Do not use this scheduler as
an animation clock or a general task system. A worker may compute an owned
result and wake the UI through `Application_Waker`; it must not mutate the
runtime from the worker.

See [scheduler and native lifecycle](reference.md#native-application-host) and
[architecture](architecture.md#native-and-text-boundaries).

### Virtual lists and custom surfaces

**Problem:** Large logical data sets and high-frequency visualizations should
not require one retained node or ordinary description per item/sample.

**Use it when:** Showing a bounded visible window of rows, or embedding a
bounded graph/spectrum-like surface beside normal controls.

`virtual_list_begin/end` asks the app to emit only the visible fixed-height
rows, each with a stable data key. A waveform surface declaration has the
shape `gpu_surface(&ui, key, logical_bounds, pixel_width, pixel_height,
dpi_scale)`, while layout-sized geometry uses
`gpu_geometry_surface(&ui, key, style, dpi_scale)`. Declarations have no
payload revision: call `gpu_surface_update` or
`gpu_surface_update_geometry` to atomically publish new retained data, and use
the explicitly versioned variants only when an asynchronous producer needs
latest-wins ordering. Surfaces are inert to pointer input by default; opt in to
`.Pointer` interaction only for a surface that behaves as a control/canvas.
The surface API carries typed, bounded presentation data; it does not expose
SDL command buffers or an application shader API. Keep platform/GPU handles
in the host boundary. Do not emit every logical row or move GPU sizing into
application-private renderer code.

See the [collections reference](reference.md#collections-and-panes), the
[surface reference](reference.md#text-runtime-and-presentation), and the
[Crucible validation fixture](../examples/crucible/main.odin). Crucible is a
headless runtime fixture, not proof of native GPU presentation.

### Actions, semantic focus, and causality

`action_update` publishes an `Action_ID`'s current label/enabled state;
`Semantic_ID` names a logical app entity independently of its current retained
node. For example, publish command state after it changes:

```odin
_ = alicorn.action_update(rt,
    alicorn.Action_Descriptor{id=alicorn.Action_ID(1), name="file.open", label="Open"},
    alicorn.Action_State{enabled=true},
)
```

Cause IDs can connect an input or external event through the resulting
invalidation, runtime work, and successful GPU submit. These are explicit
runtime contracts, not hidden application-state observation or a screen-reader
accessibility tree. Do not treat a semantic identity as an accessibility role
or export it as if it were a complete platform element.

See [actions and trace](reference.md#native-application-host),
[semantic focus](reference.md#semantic-focus-in-virtualized-views), and
[the accessibility boundary](guide.md#accessibility-status).

## When Alicorn is a reasonable fit

Alicorn may fit well when:

- the application is written in Odin and is a native desktop tool;
- you want app-owned data and procedural descriptions, with the runtime
  retaining interaction and derived UI products;
- most frames can be event-driven, with explicit bounded refreshes;
- you need a small set of controls, retained virtualization, editable text,
  menus/dialogs, or bounded custom GPU surfaces;
- you are comfortable working with an experimental API and helping discover
  missing capabilities.

Alicorn is probably not the right fit yet when:

- you require a mature, broad widget ecosystem or stable long-term API;
- screen-reader/platform accessibility-tree support is a release requirement;
- you need a web UI, mobile UI, or a large set of native platform widgets;
- a production application depends on complete native text/editor behavior,
  extensive accessibility, or established third-party tooling;
- your team does not want to own Odin or participate in early-stage runtime
  integration.

## Trade-offs by approach

These are differences in default model and ecosystem, not a scorecard. Qt
Widgets, Dear ImGui, and Electron each support many architectures and can be
customized beyond these summaries.

| Dimension | Alicorn | Dear ImGui | Qt Widgets | Electron |
|---|---|---|---|---|
| Authoring | Procedural Odin description; retained runtime execution | Immediate-mode API designed to reduce user-managed UI state duplication | Usually a hierarchy of `QWidget` objects; Qt also provides model/view abstractions | Web UI in Chromium renderer processes, with a Node.js main process |
| State | App owns domain state; Alicorn retains UI identity and derived products | Application owns values; the API recomputes UI declarations for frames | Objects/signals and model/view can own or present longer-lived state | Web application state plus main/renderer process messaging |
| Idle | Host can wait for native events and explicit one-shot deadlines | Commonly embedded in an application's own frame/render loop; integration determines scheduling | Event-loop driven; timers and updates are available | Event-loop and process model inherited from Chromium/Electron |
| Native/GPU seam | SDL3 host, OS services, typed retained surface path | Renderer backends and application-owned integration | Broad Qt platform/widget facilities | Chromium web platform and Electron OS APIs |
| Accessibility | Keyboard/focus exists; no platform accessibility tree yet | Depends on the chosen application/backend integration; verify the exact setup | Built-in widgets expose Qt accessibility interfaces; custom UI still needs correct metadata/interfaces | Chromium accessibility is available to Electron apps; verify the rendered structure and app behavior |
| Ecosystem | Small and experimental; Odin-specific | Established C++ ecosystem, including embedded debug UI | Broad desktop toolkit and commercial/open-source ecosystem | JavaScript/web ecosystem with Chromium renderer and Node.js main-process model |

For primary descriptions of those projects' models, see the
[Dear ImGui overview](https://github.com/ocornut/imgui#how-it-works),
[Qt Widgets tutorial](https://doc.qt.io/qt-6/widgets-tutorial.html),
[Qt's model/view overview](https://doc.qt.io/qt-6/model-view-programming.html),
and [Qt accessibility](https://doc.qt.io/qt-6/accessible.html), plus
[Electron's process model](https://www.electronjs.org/docs/latest/tutorial/process-model)
and [Electron accessibility](https://www.electronjs.org/docs/latest/tutorial/accessibility).
These links explain project architecture; they are not comparative
performance claims or certification of a particular application.

## Translating a familiar mental model

| Coming from | Familiar assumption | Alicorn translation |
|---|---|---|
| Dear ImGui | Call widgets while building each frame; keep values in app state | Keep values in app state, describe on invalidation, and let retained Alicorn state reuse identity and derived work |
| Qt Widgets | Create widget objects, connect signals, and update them over time | Keep domain data in Odin structs, emit controls from procedures, and use stable keys/revisions for retained state |
| React/Electron | Components describe a tree from application state; browser owns DOM/rendering and process boundaries | Describe with Odin control flow; Alicorn retains its own node/runtime products, while SDL host owns native services and GPU presentation |

These are translations, not automatic porting recipes. Keep application
behavior and domain models in the application. Let Alicorn own only the
retained interaction and presentation state described by its public API.

## Maturity and evidence

Alicorn is experimental; public APIs may change and the widget set is
intentionally small. Windows and macOS native paths are exercised, while
Linux native support is not validated. Accessibility limitations are
documented in the [guide](guide.md#accessibility-status). The opt-in visual
inspector is available to native apps launched with `--inspector`; follow
[example 05](../examples/05_inspector/main.odin) and the
[Development diagnostics guide](development.md#native-diagnostics).

Performance numbers are machine- and workload-specific. The published
[text-layout benchmark](benchmarks/text-layout.md) separates Windows and Mac
headless measurements; the [Mac native hello sample](benchmarks/native-hello-macos.md)
is a limited single-machine host observation. Neither is a cross-framework
claim or a guarantee for an application workload.

Start with [Getting Started](getting-started.md), then follow the currently
available [example progression](../examples/README.md). The more detailed
[application guide](guide.md) and [API reference](reference.md) remain the
source for how to use individual capabilities.
