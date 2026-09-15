# Odin for Alicorn

Alicorn fits Odin's direct style: keep state in ordinary Odin values, use
control flow to describe the UI, and make identity explicit when structure is
dynamic.

## Emit from ordinary state

```odin
text(ui, "Tracks")

track_key: UI_Key = key_u64(track.id)
component_begin(ui, track_key)
text(ui, track.name)

if button(ui, "Mute") {
	track.muted = !track.muted
}
```

The `button(ui, ...)` result is a `bool`, so application code can update its
own state with normal Odin control flow. `text(ui, ...)` describes content; it
does not transfer ownership of `track.name` to the runtime.

## Choose the key form that matches the data

- `key_string` names a stable textual part.
- `key_u64` carries a numeric logical identity directly.
- `key_pair` composes a parent key and a child key.

For example:

```odin
track_key: UI_Key = key_u64(track.id)
	label_key: UI_Key = key_pair(track.id, 1)
```

Keys are for logical identity, not presentation. A visible label may change;
an index may move. Neither is automatically a durable identity.

## Advanced: runtime-owned allocator configuration

Allocator configuration belongs at the runtime boundary, not in individual
`text` or `button` calls. Configure the runtime's allocator according to the
embedding configuration in the Odin-Native API plan, then let the runtime use
that allocator for its retained data and products.

Keep application state and short-lived description inputs under application
ownership. Do not rely on the runtime observing arbitrary Odin memory, and do
not give it a temporary application allocation with the expectation that it
will own the allocation after the description returns. The allocator is a
runtime lifetime decision; the emission API remains the small set of calls
shown above.
