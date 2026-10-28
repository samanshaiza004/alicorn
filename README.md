# Alicorn

Alicorn is an experimental native GUI runtime for [Odin](https://odin-lang.org/).
Describe a UI with ordinary Odin code; Alicorn retains identity, interaction,
layout, text, and rendering products between updates.

The beginner path is deliberately direct:

```odin
import ui "alicorn:ui"

App :: struct { saved: bool }

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.column(ctx, padding=24, gap=12) {
		ui.text(ctx, "Hello, Alicorn")
		if ui.button(ctx, "Save") { app.saved = true }
	}
}

main :: proc() {
	app := App{}
	ui.run(&app, render, title="Alicorn", width=720, height=480)
}
```

<p align="center">
  <img src="assets/screenshots/scratchpad-on-alicorn.png" alt="Scratchpad running on Alicorn, with its file tree, Find panel, and source editor visible" width="800" />
</p>

<p align="center"><sub>Scratchpad running on Alicorn.</sub></p>

Application state stays in your code. `ui` lowers into the same retained
Runtime as the lower-level API; it adds no application state store or second
widget tree. The API is still evolving, and Alicorn is not production-ready.

**New to Alicorn?** Follow [Getting Started](docs/getting-started.md) to install
the prerequisites, build the project, and run an editable native example.
For this release's scope and limitations, see the
[v0.2.0 release notes](RELEASE_NOTES_v0.2.0.md).

For the reusable native distribution path, see
[Native application packaging](docs/packaging.md).

Then explore the [progressive application guide](docs/guide.md), [API reference](docs/reference.md),
[Choosing Alicorn](docs/choosing-alicorn.md), [examples](examples/README.md),
[typed themes](docs/themes.md),
[performance evidence](docs/performance.md), [architecture](docs/architecture.md),
or [contributor guide](docs/development.md). The current Linux evidence is
recorded in the [NixOS/Mango validation report](docs/validation/linux-nixos-mangowc-2026-10-23.md).

**Accessibility status:** Alicorn has an experimental AccessKit bridge for
Windows UI Automation and macOS accessibility. Maintainer-confirmed physical
checks include Narrator/NVDA and VoiceOver interaction, editable controls,
modal boundaries, and bounded virtualized content. Linux has no platform
adapter, and this is not comprehensive accessibility conformance; see the
[final acceptance matrix](docs/validation/issue-103-final.md) and the guide's
[accessibility status](docs/guide.md#accessibility-status).
The reusable Odin binding is in [`accesskit/`](accesskit/); it is separate from
Alicorn's semantic projection and SDL window integration.

For live debugging, the native host includes an opt-in
[visual inspector](docs/development.md#native-diagnostics): retained tree,
focus, work counters, and recent causes, rendered using Alicorn itself.

## Acknowledgements

Alicorn is its own experiment, but its design has been informed by ideas and
work from other GUI projects:

- [Shirei](https://github.com/hasenj/go-shirei) for direct application-facing
  UI authoring and practical GUI applications.
- [GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui) and
  [Fenestra](https://github.com/richer-richard/fenestra) for thoughtful
  explorations of desktop UI architecture and developer tooling.
- [Dear ImGui](https://github.com/ocornut/imgui) and
  [egui](https://github.com/emilk/egui) for the lesson that UI interaction can
  live beside application logic without a parallel application-owned widget
  state graph.
- [Xilem and Masonry](https://github.com/linebender/xilem) for work on
  incremental UI systems and retaining or pruning derived work.
- [Skald](https://github.com/BuLEEto/Skald) for advancing GUI development in
  Odin and as the project where the work that became Runa began.

The runtime is built with [Odin](https://odin-lang.org/) and its native host
uses [SDL3](https://www.libsdl.org/) / SDL_GPU. Text shaping and rasterization
are provided by [Runa](https://github.com/BuLEEto/Runa), vendored in
[`third_party/Runa`](third_party/Runa). These acknowledgements distinguish
design influences from technical foundations; they are not a complete
dependency or licensing inventory. See the relevant component directories
and notices for third-party terms.

## License

Project Alicorn is released under the [zlib License](LICENSE). Bundled fonts
and other third-party components keep their own notices; see
[`assets/fonts/README.md`](assets/fonts/README.md) and the relevant directories.
