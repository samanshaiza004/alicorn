# Alicorn

Alicorn is an experimental native GUI runtime for [Odin](https://odin-lang.org/).
Describe a UI with ordinary Odin code; Alicorn retains identity, interaction,
layout, text, and rendering products between updates.

The programming model is deliberately direct:

```odin
alicorn.text(&ui, "Hello, Alicorn")
if alicorn.button(&ui, "Save") {
	app.saved = true
}
```

Application state stays in your code. Updates are explicit, and the API is
still evolving; Alicorn is not production-ready yet.

**New to Alicorn?** Follow [Getting Started](docs/getting-started.md) to install
the prerequisites, build the project, and run an editable native example.

Then explore the [application guide](docs/guide.md), [API reference](docs/reference.md),
[Choosing Alicorn](docs/choosing-alicorn.md), [examples](examples/README.md),
[performance evidence](docs/performance.md), [architecture](docs/architecture.md),
or [contributor guide](docs/development.md).

**Accessibility status:** Alicorn provides keyboard focus/navigation, keyboard
control behavior, and semantic action/focus identities, but it does not yet
expose its GPU-rendered UI as a platform accessibility tree for screen readers.
See the guide's [accessibility status](docs/guide.md#accessibility-status).

For live debugging, the native host includes an opt-in
[visual inspector](docs/development.md#native-diagnostics): retained tree,
focus, work counters, and recent causes, rendered using Alicorn itself.

## License

Project Alicorn is released under the [zlib License](LICENSE). Bundled fonts
and other third-party components keep their own notices; see
[`assets/fonts/README.md`](assets/fonts/README.md) and the relevant directories.
