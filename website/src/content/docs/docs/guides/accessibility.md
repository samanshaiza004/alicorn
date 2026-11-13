---
title: Accessibility
description: Alicorn's semantic model, native adapters, and current validation limits.
---

Alicorn keeps accessibility semantics separate from paint. Applications
describe meaningful roles, names, values, states, and actions; the native
adapter projects that information to the platform.

## Current boundary

The repository has an experimental AccessKit integration for Windows UI
Automation and macOS Accessibility. Maintainer-run physical checks have covered
representative VoiceOver and Windows screen-reader interactions, including
editable controls and bounded virtualized content.

Linux currently has no native platform accessibility adapter. These checks
are not a claim of comprehensive conformance or support for every application
pattern.

## Build semantic UI

Use the built-in controls when their behavior fits. They provide expected
semantics for standard controls. For a custom presentation, preserve the
interaction owner's accessible name and state, and make keyboard focus
visually perceivable. Do not rely on color alone to convey selection,
availability, or focus.

Reduced motion, increased contrast, text scale, and non-color differentiation
are inputs that application authors should include in their visual review.
The platform matrix and detailed caveats are recorded in the
[repository acceptance report](https://github.com/samanshaiza004/alicorn/blob/master/docs/validation/issue-103-final.md).

## Report gaps

Alicorn is experimental. If a control's semantics or platform behavior is
unclear, compare it with the
[semantic API documentation](https://github.com/samanshaiza004/alicorn/blob/master/docs/guide.md)
and file a reproducible report in
[GitHub Issues](https://github.com/samanshaiza004/alicorn/issues).
