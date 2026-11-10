# Documentation

Start with [Getting Started](getting-started.md) to install the toolchain, build
Alicorn, and run the native starter.

The current release is [Alicorn v0.2.1](../CHANGELOG.md); the same changelog
contains the v0.1.0 and v0.2.0 release history.

## Use Alicorn

- [Progressive application guide](guide.md) — build interfaces from basic
  controls through native integration and accessibility.
- [API reference](reference.md) — public Odin API and runtime contracts.
- [Choosing Alicorn](choosing-alicorn.md) — workload fit and architectural
  tradeoffs.
- [Typed themes](themes.md) — author, validate, and apply themes.

## Understand the runtime

- [Architecture](architecture.md) — ownership boundaries, retained execution,
  invalidation, semantics, and scheduling.
- [Durable UI restoration](durable-ui-restoration.md) — persistent identity and
  restoration behavior.
- [Application mutation diagnostics](application-mutation-diagnostics.md) —
  diagnosing application-state changes and invalidation.
- [Native menus and integrated titlebars](native-menus-and-integrated-titlebar.md).
- [Secondary native windows](secondary-native-windows.md).
- [Scroll capture](scroll-capture.md).
- [Icon assets](icon-assets.md).
- [Unicode font fallback prototype](unicode-font-fallback.md) — current
  face-registry stage and remaining shaping/platform gates.

## Develop and distribute

- [Contributor guide](development.md) — repository map, checks, fixtures, and
  diagnostics.
- [Native linking recipe](native-link-recipe.md).
- [Native application packaging](packaging.md).
- [Performance evidence](performance.md) and the [benchmark index](benchmarks/README.md).

## Active research

- [#109 typed sizing research](research/issue-109-completion-plan.md) —
  v0.3.0 follow-up research. v0.2.1 includes only the already merged fixed,
  fit-height, and definite-parent percentage-width work; broader layout
  resizing remains deferred and is not a v0.2.1 release gate.

## Platform status and validation

- [Current validation records and runbooks](validation/README.md).
- [Final Windows/macOS acceptance matrix](validation/issue-103-final.md).
- [Linux NixOS/Mango validation](validation/linux-nixos-mangowc-2026-10-23.md).

Older research notes and point-in-time validation reports are preserved under
[the documentation archive](archive/README.md). They provide provenance; use
the current guides and acceptance matrix for present project status.
