---
title: Direct to write. Retained to run.
description: Why Alicorn keeps application state ordinary and retains the UI products that benefit from identity.
date: 2026-11-13
tags:
  - Runtime model
  - Design
---

Alicorn starts with a simple split: the application owns its data, and the
runtime retains the interface work that benefits from identity.

A render procedure describes controls with ordinary Odin code. A button result
is an event the application handles; it is not a hidden store for the
application's state. When the app changes a value that affects the interface,
it explicitly invalidates the root or the region whose output changed.

That boundary keeps state changes legible. The runtime does not need to inspect
arbitrary Odin memory, infer dependencies from pointers, or guess whether a
value is safe to reuse.

## Retain products, not application state

Alicorn retains the identity and derived products needed to make an interface
behave like a continuing interface: focus, selection, scroll, geometry, shaped
text, semantics, and paint. Stable call sites identify one-off structure;
stable keys identify repeated logical items.

When a new description arrives, Alicorn reconciles it with that identity.
Changed data marks dependent products dirty. Unchanged products can remain
available to the next frame. If no input, scheduled work, or animation needs
attention, the native host can wait for the next event.

The boundary is intentionally explicit. A developer can see what changed,
which region needs a new description, and which runtime stage must respond.

## Keep the host native

The application describes meaning and intent. The native host owns the window,
input pump, platform services, GPU submission, and in-flight resource
lifecycle. Applications do not receive renderer command buffers or store
platform handles in retained nodes.

That gives the runtime a useful division of responsibility: an application
can describe a specialized control, while Alicorn provides stable interaction,
focus, semantics, layout, text, and presentation machinery.

## Still an experiment

Alicorn's API and platform integration are evolving. The goal is not to hide
those boundaries behind a universal widget framework. It is to make the
important ones explicit, testable, and useful to applications written in Odin.

Start with the
[first native example](/docs/getting-started/first-app), then use the
[project status](/docs/project/status) to understand what is and is not
validated.
