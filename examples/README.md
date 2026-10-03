# Alicorn examples

Follow the numbered examples in order. Each one is a small native application
and uses the same public runtime/host APIs available to an application.
Install the Odin and SDL3 prerequisites from [Getting Started](../docs/getting-started.md)
first. The same `odin run` commands work in Windows PowerShell and macOS
Terminal.

## Learning progression

| Step | Example | What it teaches | Run |
|---|---|---|---|
| 1 | [01 · Hello](01_hello/main.odin) | Native window/event loop, text, a button, app-owned counter state, row/column layout | `odin run examples/01_hello` |
| 2 | [02 · Form](02_form/main.odin) | Text field, checkbox, sliders, controlled state, per-widget color/style | `odin run examples/02_form` |
| 3 | [03 · Async List](03_async_list/main.odin) | Worker completion through `Application_Waker`, a 10,000-item fixed-row virtual list, stable keys, and event-driven idle | `odin run examples/03_async_list` |
| 4 | [04 · Custom Surface](04_custom_surface/main.odin) | Bounded retained GPU geometry in clipped layout, resize and DPI-aware updates | `odin run examples/04_custom_surface` |
| 5 | [05 · Inspector](05_inspector/main.odin) | Retained tree, focus, semantic action and causal work inspection | `odin run examples/05_inspector -- --inspector` |

The native starter and form also have convenience runners:

```powershell
.\tools\native_hello.ps1
.\tools\widget_gallery.ps1
```

```sh
./tools/native_hello.sh
./tools/widget_gallery.sh
```

The `widget_gallery` runner name is retained for compatibility; it launches
the numbered form lesson.

## Try each lesson

1. In `01_hello`, change the greeting or button label, then click **Increment**.
2. In `02_form`, edit the name, toggle a checkbox, adjust a slider, and change
   the panel colors in the source.
3. In `03_async_list`, scroll and select rows. Only visible rows are described;
   after the worker's single completion wake, the host returns to event wait.
   Add `-- --smoke` to run its bounded startup/idle check where a native window
   can be opened.
4. In `04_custom_surface`, change the waveform function or segment count. The
   application description remains idle while scheduled callbacks update only
   the retained surface geometry.
5. In `05_inspector`, press **F9** to open/close the inspector, choose Tree,
   Focus, Work, and Causes, then press **P** and click an app control to pick it
   without activating it. **Escape** closes the overlay. To intentionally
   produce a duplicate-key diagnostic while keeping the inspector open, run:

   ```text
   odin run examples/05_inspector -- --inspector-open --identity-error
   ```

   The negative mode is opt-in; ordinary startup has valid identities.
   The inspector and diagnostic name the `first declaration` and
   `duplicate declaration` plus the repeated key and suggested correction.

## Build and validation

`tools/build_examples.ps1` (Windows) and `tools/build_examples.sh` (macOS and
other Unix-like shells) compile every immediate `examples/*/main.odin`
package. Both foundation CI jobs run this check. The Windows/macOS runners use
the platform's Odin/SDL3 installation described in Getting Started. Native
manual-run instructions and the Windows inspector smoke evidence are in
[`docs/validation/visual-inspector-windows.md`](../docs/validation/visual-inspector-windows.md)
and the native starter's platform notes.

## Focused examples and validation fixtures

These are subsystem references and headless tests, not extra steps in the
beginner progression:

- [`hello`](hello/main.odin), [`counter`](counter/main.odin),
  [`text_input`](text_input/main.odin): compact headless runtime examples.
- [`keyed_list`](keyed_list/main.odin): minimal keyed virtual-list API sample.
- [`runa_text`](runa_text/main.odin): text shaping and geometry proof.
- [`advanced_identity`](advanced_identity/main.odin),
  [`identity_torture`](identity_torture/main.odin): identity diagnostics and
  stress coverage.
- [`crucible`](crucible/main.odin): retained-runtime fixture for keyed state,
  regions, compact presentation, and custom-surface payloads.

For design trade-offs, see [Choosing Alicorn](../docs/choosing-alicorn.md).
