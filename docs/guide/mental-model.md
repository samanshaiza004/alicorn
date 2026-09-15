# Alicorn's mental model

Alicorn separates two concerns:

1. Application code owns ordinary Odin state and describes the interface.
2. The runtime owns retained UI facts needed between descriptions.

The description is procedural. A call to `text(ui, ...)` contributes text, and
`button(ui, ...)` contributes an interactive button whose result is a `bool`.
There is no application-owned widget object required for either operation.

## Identity is hierarchical

Labels are content, not identity. A `UI_Key` supplies the logical identity
that a repeated or reusable part needs:

```odin
screen_key: UI_Key = key_string("settings")
row_key: UI_Key = key_u64(row.id)
cell_key: UI_Key = key_pair(row.id, 1)
```

Use `key_string` for stable named parts, `key_u64` for numeric identities, and
`key_pair` when two numeric values form one identity. A key should follow the
logical item through insertion, removal, filtering, and reordering. It should
not be manufactured from a transient list position merely because that
position is convenient.

Reusable components add an invocation scope with:

```odin
component_begin(ui, screen_key)
```

The component's internal `text` and `button` calls then participate in that
keyed scope. This lets the same helper be used for different logical
components without making their retained identities collide.

## Ownership stays visible

Keep application state in application-owned Odin values. The runtime may retain
identity, interaction state, layout products, and other runtime products, but
the emission API does not turn an application buffer into runtime-owned state.
Update application state when a button returns true, then describe the next
frame from that state.

This boundary is the reason the API stays small: text and interaction are
emissions, keys express identity, and the runtime retains only what it owns.
