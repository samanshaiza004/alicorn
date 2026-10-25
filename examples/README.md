# Alicorn examples

Follow the numbered native applications in order. Every UI lesson imports
`alicorn:ui` for ordinary text, layout, and buttons. Lessons that demonstrate a
runtime capability use the runtime API beside it for that specific job; the
simple and advanced paths share the same UI context and retained Runtime.

Install Odin and the native prerequisites from
[Getting Started](../docs/getting-started.md) first.

| Step | Example | What it teaches |
|---|---|---|
| 1 | [Hello](01_hello/main.odin) | Typed `ui.run`, app-owned state, text, and a button |
| 2 | [Form](02_form/main.odin) | Scoped panels and rows, controlled text, checkbox and slider values |
| 3 | [Async List](03_async_list/main.odin) | Worker completion, stable keyed rows, fixed-height virtualization, and true idle |
| 4 | [Custom Surface](04_custom_surface/main.odin) | Retained GPU geometry inside a clipped UI panel; resize and DPI-aware updates |
| 5 | [Inspector](05_inspector/main.odin) | Retained tree, focus, semantic actions, and invalidation causes |
| 6 | [Secondary Windows](06_secondary_windows/main.odin) | Opening and closing a tool window with independent application state |
| 7 | [Appearance](07_simple_appearance/main.odin) | Direct colors, panels, borders, rounded surfaces, and fixed-size boxes |

Run a lesson from the repository root. The runner resolves Odin and native
linker dependencies, builds the selected program, and launches it:

```sh
./tools/run_example.sh 01_hello
./tools/run_example.sh 05_inspector --inspector
```

```powershell
.\tools\run_example.ps1 -Example 01_hello
.\tools\run_example.ps1 -Example 05_inspector -AppArgs @('--inspector')
```

Use `--odin PATH` on the shell runner or `-Odin PATH` on PowerShell to select
an Odin executable explicitly. Add `--speed` or `-Speed` for an optimized
build. Program arguments follow the example name on the shell runner and use
`-AppArgs` on PowerShell.

## Try each lesson

1. In `01_hello`, change the greeting or button label, then click **Increment**.
2. In `02_form`, edit the name, toggle the checkbox, adjust the slider, and
   compare the application-owned values shown at the bottom.
3. In `03_async_list`, wait for the worker result, scroll, and select rows. The
   list describes only visible records; after its completion wake, the host
   returns to event wait. Pass `--smoke` to the runner to run the bounded idle
   check (`./tools/run_example.sh 03_async_list --smoke`).
4. In `04_custom_surface`, change the waveform function or segment count. The
   application description stays idle while scheduled callbacks update the
   retained surface geometry.
5. In `05_inspector`, press **F9**, choose Tree, Focus, Work, and Causes, then
   press **P** and click an app control to pick it without activating it.
   **Escape** closes the inspector. To keep it open while triggering the
   intentional duplicate-key diagnostic, run:

   ```sh
   ./tools/run_example.sh 05_inspector --inspector-open --identity-error
   ```

6. In `06_secondary_windows`, open and close a child window, then compare its
   counter and lifecycle with the main window.
7. In `07_simple_appearance`, change panel fill, border, or swatch colors.

## Build and validation

`tools/build_examples.ps1` (Windows) and `tools/build_examples.sh` (macOS and
other Unix-like shells) compile the numbered application lessons. Both
foundation CI jobs run this check. `tools/check.ps1` and `tools/check.sh` also
compile internal validation fixtures, which live under `tests/fixtures` rather
than in the beginner-facing example list.

The starter and form also have older dedicated runners:

```powershell
.\tools\native_hello.ps1
.\tools\widget_gallery.ps1
```

```sh
./tools/native_hello.sh
./tools/widget_gallery.sh
```

The `widget_gallery` runner name is retained for compatibility; it launches
the focused form lesson. `tools/run_example` is the recommended path for any
numbered lesson because it supplies the `alicorn:ui` collection and platform
linker settings automatically.

For application-owned session files, see the headless
[durable restoration fixture](../tests/fixtures/durable_restoration/main.odin)
and its [restart checks](../docs/durable-ui-restoration.md). For the Runa text
integration probe, see [`tools/runa_text/main.odin`](../tools/runa_text/main.odin).
