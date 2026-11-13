---
title: Themes and custom components
description: Use typed semantic roles and compose application-owned controls over Alicorn's retained interaction primitives.
---

Alicorn's theme system is a small typed design-token compiler, not a
stylesheet cascade. Themes bind semantic color roles and control recipes to
values. Applications and component packages can add namespaced extension
roles without changing Alicorn's core role enum.

## Keep appearance separate from meaning

A theme can change how a selected, hovered, pressed, or disabled control
looks. The control's semantic role, label, value, actions, and state remain
owned by the UI description.

For a quick start, see
[the typed theme guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/themes.md)
and the theme compiler under <code>theme/</code>.

## Compose a custom control

An application can build a compound control from existing public primitives:
ordinary layout scopes, semantic surfaces, visual parts, extension roles, and
retained motion. The component owns its recipe and per-instance design choices;
Alicorn continues to own retained identity, hit testing, focus, and the native
input lifecycle.

The repository's custom-control examples and tests are the best guide to the
current API. Start at
[examples](https://github.com/samanshaiza004/alicorn/tree/master/examples)
and read the
[API reference](https://github.com/samanshaiza004/alicorn/blob/master/docs/reference.md)
before depending on a lower-level contract.

## Keep theme requirements visible

Extension roles are namespaced and typed. A component that depends on one
should document the role name and provide a deliberate fallback or clear
configuration diagnostic. Do not assume a valid role ID proves that the active
theme has bound it.

For reusable application components that build on Alicorn rather than changing
its runtime, see the companion [AliKit component catalog](/alikit).
