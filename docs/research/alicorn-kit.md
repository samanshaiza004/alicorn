# AliKit: companion component library proposal

**Status:** Research and implementation proposal; no public component API selected yet.

## Decision

Proceed with an optional Alicorn companion library, but keep Alicorn itself as the UI runtime. AliKit should package reusable application behavior and composed controls that are awkward to rebuild. It should not create a second runtime, theme engine, retained tree, application-state system, or required component framework.

Start the first implementation with a generic Command Palette, dogfooded by Scratchpad. Build the Color Picker next, when Scratchpad has a user-facing theme editor. Do not add a basic split-pane implementation: Alicorn already provides retained split and tab primitives, and Scratchpad owns its workbench model.

Keep AliKit in a separate repository for its first public release. That keeps it optional and gives applications independent dependency choice. Before publishing a stable API, prove the package from a clean external Odin project pinned to a known Alicorn revision. Odin documents custom collections through the -collection flag and does not provide an official package manager, so the library must make its collection mapping and version pin explicit.

## What exists already

- Alicorn's architecture is direct procedural authoring over the retained runtime. Application code owns domain state; Alicorn owns retained interaction, geometry, text, paint, and native resources. Runtime fields are implementation details, not a supported component interface. See the [architecture guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/architecture.md).
- Alicorn already has a public third-party compound-control example. Mode Rail uses public UI/runtime calls, app-owned selected/disabled values, keyed identity, semantic augmentation, a typed vendor-role contract, adaptive layout, and retained motion. The [example guide](https://github.com/samanshaiza004/alicorn/blob/master/examples/11_third_party_component/README.md) is a strong starting template.
- The theme contract already supports namespaced extension roles and component-shipped default theme data. It advises validating required roles at setup/replacement and using visible errors or documented fallbacks. AliKit should follow that contract rather than invent a universal design system. See [typed themes](https://github.com/samanshaiza004/alicorn/blob/master/docs/themes.md).
- Alicorn's runtime already exposes split containers, resize handles, split-state snapshots, tab bars, virtual lists, semantic actions, and basic controls. A Kit wrapper is justified only when it adds useful composition or behavior; renaming a core primitive is not enough. See [split primitives](https://github.com/samanshaiza004/alicorn/blob/master/runtime/layout_widgets.odin) and [tab bars](https://github.com/samanshaiza004/alicorn/blob/master/runtime/tab_bar.odin).
- Scratchpad already has a substantial command palette: it gathers app commands and menu items, applies app-specific aliases and recency, filters and sorts results, routes Up/Down/Enter/Escape, restores focus, and reveals the selected result. Its file-oriented Quick Open and command dispatch are product behavior, not reusable palette behavior. See [Scratchpad's palette implementation](https://github.com/samanshaiza004/scratchpad/blob/main/frontends/alicorn/command_palette.odin).
- Scratchpad's current parity record says live theme replacement is development dogfood, not a general user-facing theme editor. A color picker is still a good planned component, but a claim that Scratchpad can immediately consume it in a theme editor would be premature. See [Scratchpad frontend coverage](https://github.com/samanshaiza004/scratchpad/blob/main/docs/frontends/alicorn/PARITY.md).
- Alicorn issue [#181](https://github.com/samanshaiza004/alicorn/issues/181) already owns the core control gallery and explicitly rejects a giant component catalog or a new design language. AliKit can have a separate gallery for its own components, while #181 remains the catalog of Alicorn core capabilities.

## Architecture

### Dependency direction

~~~text
Application (Scratchpad, Punks, future tools)
        ├── Alicorn UI/runtime
        └── AliKit components
                 └── Alicorn UI/runtime
~~~

AliKit depends on Alicorn; Alicorn never depends on AliKit. The first package should import the supported `alicorn:ui` interface and use documented `alicorn:runtime` APIs only where the higher-level UI package has no matching wrapper. If a component needs private runtime storage or a new host hook, stop and make that a focused Alicorn API proposal.

Do not create `alikit-base` yet. Alicorn already provides the primitive control behavior, focus, semantics, layout, and retained state. Split behavior from presentation inside a component only where the same hard interaction logic can serve materially different presentations.

### State and identity

- The application owns selected domain values, command registries, callbacks, persistence, and product policy.
- A component may expose a small caller-owned `State` value for ephemeral interaction that spans frames: query text, active item identity, visible month, or validation status. The application stores and passes it; Alicorn must not retain pointers to application values.
- Component calls return events or stable item IDs. AliKit does not keep callbacks into application modules or introduce a global command store.
- Use Alicorn's stable keyed component scopes and semantic APIs. Key repeated items by stable data identity, not their current row index. Use existing focus/semantic behavior rather than maintaining a parallel accessible tree.
- Every component documents which state is app-owned, which state is transient UI state, and what the caller must initialize/destroy.

### Presentation and theme contract

Components provide a small default style and accept explicit per-instance style overrides. Theme roles are namespaced, such as `vendor.alicorn_kit.command_palette.surface`; they do not extend Alicorn's core role enum. Ship default token data with the component package and provide a setup-time contract check for required roles. Avoid hard-coded product colors and avoid requiring one shared AliKit theme.

Use ordinary Alicorn controls for native hit testing, keyboard focus, semantics, and disabled behavior. Theme replacement remains a caller-controlled operation; components must not register a new theme on every description or retain token IDs across theme generations.

## First component: Command Palette

This is the best first package because Scratchpad already has a real implementation to extract and an immediate consumer. The extraction should be narrower than copying the current file.

**AliKit owns:** generic item identity, deterministic fuzzy matching, query/result state, selection movement, empty/disabled result handling, virtualized presentation, focus/selection continuity, and a result event.

**Scratchpad keeps:** command and menu discovery, labels/aliases for its features, recent-command policy, file Quick Open, keyboard shortcut registry, command execution, backend integration, and workspace policy.

An API sketch, not a committed signature:

~~~odin
Command_Item :: struct {
    id: string,
    label: string,
    keywords: string,
    category: string,
    shortcut: string,
    enabled: bool,
}

Palette_Event :: union {
    None,
    Activated: string, // stable item ID; the app dispatches it
    Dismissed,
}

palette :: proc(
    ctx: ^ui.UI,
    state: ^Palette_State,
    items: []Command_Item,
    key: ui.UI_Key,
) -> Palette_Event
~~~

The exact split between the draw call and a pure key-routing function must be proved against Alicorn's public application/test APIs before the signature is frozen. In particular, the palette must not bypass host input arbitration or inspect Runtime internals to capture Up/Down. If the public `ui.run` convenience layer cannot route the required keys, support the documented lower-level application callback first rather than expanding core for a single component.

Use stable item IDs so filtering, sorting, or source-list reordering does not move selection to a different command. The component reports the activated ID; Scratchpad executes the corresponding application action. The component must not claim to implement file search or command registration.

## Second component: Color Picker

Color Picker is a valuable second component, but it is not yet an immediate Scratchpad dogfood target because the current app has no user-facing custom-theme editor. Start with a controlled RGB/hex editor and color swatch using Alicorn's existing text-field and slider controls. Keep the selected `Color` application-owned; let a small caller-owned component state handle incomplete hex input and active editing.

Define color conversion and hex parsing as pure functions with explicit alpha and color-space semantics. Require labels, keyboard operation, semantic values, validation errors, and visible focus. Defer a 2D saturation/value surface and native eyedropper until the public pointer/semantic surface contract is clear and a real consumer needs them. The first component should be useful and accessible without platform-specific screen sampling.

Dogfood it in Scratchpad only when its theme editor is a real product surface. A development-only live-theme fixture is enough for early component visual iteration, but it does not establish user-facing product value.

## Split panes and specialized engines

Do not implement `Split_Pane` as a second split control. Core `split_begin`, `split_divider`, and `split_state` already own resize interaction and retained position. Scratchpad's pane/view registry, Git context, terminal sessions, document identity, and durable workbench arrangement are application architecture; putting those in AliKit would couple the library to one product's workspace model.

A later AliKit panel-group convenience is reasonable only if a second application needs the same composition and it can be built entirely on public split APIs. Docking, tab movement, workspace persistence, and task-oriented layouts need a separate product-level decision.

Keep a terminal emulator and rich editor as specialized packages with independently testable engines. The [zgui-terminal project](https://github.com/zortax/zgui-terminal) is a useful boundary example: its terminal widget accepts a transport rather than owning a shell, SSH connection, or process policy. Freya demonstrates that a broad ecosystem can be composed from separate packages and optional capabilities, while GPUI Kit documents a useful behavior-versus-presentation distinction. Neither architecture should be copied wholesale; Alicorn already has the runtime and public control foundation. See [Freya](https://github.com/marc2332/freya) and [GPUI Kit architecture](https://github.com/longbridge/gpui-kit/blob/main/docs/ARCHITECTURE.md).

## Repository and distribution

Create one optional repository named `alicorn-kit`; publish ordinary Odin packages, not an installer or registry. A likely first layout is:

~~~text
alicorn-kit/
  README.md
  CHANGELOG.md
  COMPATIBILITY.md
  command_palette/
  gallery/
  examples/
~~~

Use Odin's collection mapping, for example `-collection:alicorn_kit=/path/to/alicorn-kit`, with the application's existing Alicorn collection and native dependency setup. The public import would be `alicorn_kit:command_palette`. Pin each AliKit release to an explicitly tested Alicorn release/commit in `COMPATIBILITY.md`; do not promise compatibility with every historical Alicorn revision. Odin's [package and collection documentation](https://odin-lang.org/docs/overview/) supports custom collections and describes directory-based packages; the language does not provide an official package manager.

Before publishing the first release, build a separate consumer from outside both checkouts. That proves the import path, dependency mapping, licensing, and documentation rather than merely compiling AliKit from its own tree. Keep the package dependency-free beyond Alicorn and Odin.

## Implementation order and promotion gates

1. **Package boundary:** Create the separate repository, add collection setup and compatibility policy, and compile a tiny external consumer against a pinned Alicorn revision.
2. **Command Palette model:** Extract generic matching and stable selection state from Scratchpad. Keep it independent of Scratchpad command IDs, backend, Quick Open, and file-system services.
3. **Command Palette UI:** Compose public Alicorn fields, virtual lists, buttons, overlays, and semantics. Verify key handling through the same public host path a consumer uses; preserve focus and scroll reveal; return action IDs rather than invoking callbacks.
4. **Real consumer and gallery:** Adapt Scratchpad's command palette to the component without moving its command source or dispatch policy. Include a small AliKit gallery that demonstrates empty, filtered, disabled, keyboard, focus, and theme states. Alicorn #181 remains the core controls gallery.
5. **Color Picker:** Add pure color/hex helpers and a controlled, keyboard-accessible RGB/hex component. Dogfood when Scratchpad's user-facing theme editor exists.
6. **Panel convenience, if justified:** Revisit only after Scratchpad's workbench contract stabilizes and a second application demonstrates the same need. Reuse Alicorn split/tab primitives.

Use Alicorn's public `testui` for interaction/layout assertions and the exact consumer build, then use native checks for GPU visuals, OS accessibility integration, and actual keyboard/focus behavior. Headless tests do not prove native pixels or platform accessibility. For each component, require stable identities, an accessibility snapshot, a keyboard path, and a bounded idle state before calling it reusable.

## Research basis

- GPUI Kit's [architecture guide](https://github.com/longbridge/gpui-kit/blob/main/docs/ARCHITECTURE.md) separates reusable interaction behavior from product presentation and treats complex headless behavior as real implementation, not an empty wrapper. Useful principle; Alicorn should not add a second base layer where its runtime already provides that behavior.
- Freya's [repository and component overview](https://github.com/marc2332/freya) demonstrate breadth through separately organized components and optional specialized features. Useful ecosystem lesson; AliKit should earn each module through consumer use.
- The [Odin language overview](https://odin-lang.org/docs/overview/) documents package directories and custom collection paths. This makes a no-installer companion package practical, but puts exact dependency pins and external-consumer examples on AliKit.
- The [zgui-terminal README](https://github.com/zortax/zgui-terminal) describes a terminal UI separated from its transport. Specialized engines should keep their process/network boundary outside the component library.

## Recommendation

**GO for a small optional AliKit repository, beginning with Command Palette.** Do not start with a large styled catalog, duplicate split control, or a generic component lifecycle. Promote the library only after an external consumer builds cleanly and Scratchpad proves that the generic palette can reuse behavior without exporting application policy.

The Color Picker remains the next strong candidate, with Scratchpad theme editing as its intended dogfood path. Terminal and rich-editor engines remain separate.