# Tutorial: a small Alicorn UI

Alicorn UI code is ordinary Odin control flow. The application keeps its own
state and emits a description through `ui`.

```odin
text(ui, "Counter")

if button(ui, "Increment") {
	count += 1
}

text(ui, "The application owns count.")
```

`text(ui, ...)` emits text. `button(ui, ...)` emits a button and returns a
`bool`; a true result is the activation to handle in application code. The
runtime retains UI facts such as identity and interaction state, but it does
not become the owner of `count` or other application data.

## Give repeated UI a key

Use a `UI_Key` when a logical item must keep its identity while the data is
reordered or filtered:

```odin
row_key: UI_Key = key_u64(row.id)
value_key: UI_Key = key_pair(row.id, 1)
```

`key_string` is useful for a stable named part. `key_u64` is useful for a
numeric application identity without first formatting it as text. `key_pair`
combines two numeric identity values without first formatting them as text.

## Scope a reusable component

At the entry to a reusable component, establish its invocation identity before
emitting its contents:

```odin
component_begin(ui, key_string("settings"))
text(ui, "Settings")
if button(ui, "Dark mode") {
	dark_mode = !dark_mode
}
```

The component key keeps identical helper code distinct at different logical
call sites. Prefer keys that describe the logical item, not its current
position or its visible label.
