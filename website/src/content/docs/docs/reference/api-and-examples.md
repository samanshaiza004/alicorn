---
title: API and examples
description: Find the right Alicorn package and follow the repository's progressive native examples.
---

Start with <code>alicorn:ui</code> for a routine single-window app. It provides
typed app state, layout scopes, text, common controls, and a native
<code>ui.run</code> lifecycle. Move to the lower-level runtime or host API only
when your application needs the additional control.

## Controls and layout

The convenience package covers rows, columns, panels, boxes, virtual lists,
text fields, checkboxes, sliders, icons, and buttons. It writes ordinary nodes
into the existing runtime. Your application keeps domain state and handles
the result of user actions.

The
[API reference](https://github.com/samanshaiza004/alicorn/blob/master/docs/reference.md)
lists the public surface and migration boundaries.

## Retained motion

Alicorn's retained motion API animates presentation values while keeping
target layout and hit geometry stable. Motion can be interrupted and retargeted;
the host schedules presentation-only work while a response is active.

Explore <code>examples/09_retained_motion</code> in the
[repository](https://github.com/samanshaiza004/alicorn/tree/master/examples/09_retained_motion).

## Large collections

Virtual lists let applications describe a bounded visible window instead of
creating a UI node for every logical item. Give rows stable keys so identity
survives changes in ordering and visibility.

See <code>examples/03_async_list</code> and the other numbered lessons in the
[examples directory](https://github.com/samanshaiza004/alicorn/tree/master/examples).

## Explore the source

- [Getting Started](https://github.com/samanshaiza004/alicorn/blob/master/docs/getting-started.md)
- [Progressive application guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/guide.md)
- [Typed themes](https://github.com/samanshaiza004/alicorn/blob/master/docs/themes.md)
- [Native packaging](https://github.com/samanshaiza004/alicorn/blob/master/docs/packaging.md)
- [Example index](https://github.com/samanshaiza004/alicorn/blob/master/examples/README.md)
