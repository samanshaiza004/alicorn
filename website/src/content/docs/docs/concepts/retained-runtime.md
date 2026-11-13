---
title: The retained runtime
description: How application-owned Odin state meets Alicorn's retained UI identity and derived work.
---

Alicorn's shorthand is **direct to write, retained to run**.

Your application describes the UI with ordinary control flow. Alicorn keeps
the runtime identity and derived products needed to preserve interaction and
avoid repeating work that has not become dirty.

## Ownership stays explicit

Your application owns its data and decisions. Alicorn does not inspect
arbitrary Odin memory or infer that one of your fields changed. The native host
owns the window, input pump, event loop, GPU submission, and platform services.

~~~text
application state
      │ logical change or user action
      ▼
explicit invalidation
      │
      ▼
Odin UI description
      │ stable call sites and keys
      ▼
retained identity, interaction, geometry, text, paint
      │ dirty stages only
      ▼
native host presents
~~~

The high-level <code>alicorn:ui</code> package writes into the same retained
runtime as the lower-level API. It does not create a second widget tree or an
application state store.

## What Alicorn retains

Stable node identity allows the runtime to associate focus, selection, scroll,
layout, text products, semantic information, and paint with logical controls
across descriptions. A description may run after an interaction or state
change; retained identity keeps the control from becoming a new object each
time.

The application still decides what changed. See
[Invalidation and identity](/docs/concepts/invalidation) for that contract.

## The host is a separate boundary

The native host translates platform input, manages the event loop, and submits
GPU work. Application code receives typed capabilities and UI context; it does
not receive SDL command buffers or render-pass pointers. That separation keeps
UI intent portable across Alicorn's lower-level runtime and native host.
