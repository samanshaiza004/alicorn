# Alicorn v0.1.0

Alicorn is an experimental native GUI runtime for Odin. This first release
provides a small retained UI runtime and an SDL3/SDL_GPU native host, with
application state kept in ordinary Odin code.

## What’s included

- Procedural UI descriptions with retained identity, layout, focus, and
  interaction state.
- Common controls and text input, plus native-host keyboard, pointer, window,
  and menu integration.
- Keyed virtual lists, retained regions, and bounded custom GPU surfaces for
  larger collections and visualization workloads.
- An opt-in visual inspector for the retained tree, focus, runtime work, and
  recent causes; the host also provides a runtime HUD and diagnostic captures.
- A five-step example progression from a native window and controls through
  asynchronous virtual lists, custom surfaces, and the inspector.

Start with [Getting Started](docs/getting-started.md), then see the
[application guide](docs/guide.md), [API reference](docs/reference.md),
[examples](examples/README.md), and [native diagnostics guide](docs/development.md#native-diagnostics).

## Platform validation

The native path has been exercised on Windows and macOS. Checked-in validation
records include Windows 10 22H2 and macOS 27.0 on Apple silicon. This is focused
project testing, not certification across all OS versions, hardware, or GPU
drivers. Linux native support has not been validated; the headless checks may
still be useful there, but native use remains experimental.

## Experimental status and limitations

This release is **not production-ready**. Alicorn is experimental, its public
API is not frozen and may change, and the available widget set is intentionally
small. v0.1.0 does not promise a full-featured toolkit or long-term production
API stability.

Keyboard focus and operation, semantic focus identities, and native text-input
composition are supported. They are not a platform accessibility bridge:
Alicorn does not expose its GPU-rendered controls as Windows UI Automation or
macOS Accessibility/NSAccessibility elements, so screen readers cannot inspect
or operate that control tree.

The native starter scripts are development workflows, not a general app
packager. Windows development currently stages SDL3 beside the executable;
macOS development links the installed SDL3 library. v0.1.0 does not provide a
first-party self-contained app bundle, installer, signing, or notarization
pipeline. Those deployment responsibilities remain with each application for
now; reusable SDL/runtime packaging belongs with Alicorn's native-host tools,
not Caliber's frontend-neutral ABI layer.

## Performance evidence

The published measurements are author-run, workload-specific observations,
not cross-framework comparisons or general performance guarantees. They cover
focused text-layout workloads and retained-work tests on Windows and macOS,
plus bounded native-host samples. See the [performance evidence index](docs/performance.md)
for methodology, platform reports, raw captures, and limitations.
