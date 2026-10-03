# Examples and validation fixtures

The examples directory currently mixes small applications with headless
runtime proofs. This guide identifies which files are intended as a first
learning path and which are diagnostic fixtures; it is not yet the complete
five-step curriculum described by release issue #19.

## Learn Alicorn in order

### 1. `native_hello`: a window, button, and app-owned state

Start with the native starter. It opens an SDL3 window, displays text and an
Increment button, and stores the count in an ordinary app struct.

```powershell
.\tools\native_hello.ps1
```

```sh
./tools/native_hello.sh
```

Try changing the text or button label in
[`native_hello/main.odin`](native_hello/main.odin), then rerun the command.

### 2. `widget_gallery`: controlled form controls

Run the native gallery with `./tools/widget_gallery.sh` on macOS or
`./tools/widget_gallery.ps1` on Windows. It demonstrates buttons, checkboxes,
continuous and stepped sliders, keyboard focus, disabled state, and app-owned
values. Try Tab/Shift+Tab, Space, arrow keys, Home, and End.

Source: [`widget_gallery/main.odin`](widget_gallery/main.odin).

### 3. `keyed_list`: stable identity and a virtual-list API

This small headless example shows the shape of a fixed-height virtual list and
keyed rows. It uses only three sample items, so it teaches the API shape rather
than large-data performance or asynchronous loading.

```sh
odin run examples/keyed_list
```

Source: [`keyed_list/main.odin`](keyed_list/main.odin).

## Focused examples and validation fixtures

These are useful when investigating a specific subsystem, but are not a
beginner sequence and should not all be treated as public-API application
templates:

- [`hello`](hello/main.odin) and [`counter`](counter/main.odin): minimal
  headless runtime examples.
- [`text_input`](text_input/main.odin) and [`runa_text`](runa_text/main.odin):
  headless text/input and shaping-oriented demonstrations.
- [`advanced_identity`](advanced_identity/main.odin) and
  [`identity_torture`](identity_torture/main.odin): identity diagnostics and
  stress coverage.
- [`crucible`](crucible/main.odin): a headless retained-runtime validation
  fixture for keyed state, regions, compact presentation, and custom-surface
  payloads. It does not open a native window or prove GPU presentation.

## Curriculum gaps

The current tree does not yet contain the proposed beginner-friendly async
10,000-item list, a small native custom-surface application, or a visual
inspector example. The built-in visual inspector overlay itself is not yet
shipped. Those remain release-roadmap work; the headless fixtures above are
not substitutes for them.

For the runtime model and fit trade-offs, see [Choosing Alicorn](../docs/choosing-alicorn.md).
For prerequisites and the first native launch, see [Getting Started](../docs/getting-started.md).
