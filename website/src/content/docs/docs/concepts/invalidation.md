---
title: Invalidation and stable identity
description: Tell Alicorn what changed and keep repeated UI attached to stable logical keys.
---

Alicorn retains UI products, but it does not watch application memory. Input
events already trigger the normal description cycle. Explicit invalidation is
for application changes adopted outside that cycle, such as a worker result:

~~~odin
on_wake :: proc(app: ^App, ctx: ui.Application_Context) {
    if app.result_ready {
        app.result_ready = false
        ui.invalidate(ctx, "worker result adopted")
    }
}
~~~

Adopt synchronized worker data before invalidating. The native host then
describes the updated application state. See the
[Async List example](https://github.com/samanshaiza004/alicorn/blob/master/examples/03_async_list/main.odin)
for a complete worker and wake lifecycle.

## Give repeated items stable keys

For rows or controls that can move, insert, or disappear, use an identity based
on the item—not its current position. Alicorn can then associate the retained
state with the same logical item after the description changes.

A duplicated key is an identity error. It is not a request for the runtime to
guess by falling back to row position.

## Reuse a costly region

A region can retain a subtree under an application-owned key and revision.
Advance the revision when the output described by that region changes. Keeping
a stale revision intentionally keeps stale output, so the revision must reflect
the data that determines the region's description.

The complete contracts and examples are in
[the application guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/guide.md)
and [the architecture overview](https://github.com/samanshaiza004/alicorn/blob/master/docs/architecture.md).
