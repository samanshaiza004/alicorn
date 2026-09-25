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
[architecture](docs/architecture.md), or [contributor guide](docs/development.md).

## License

Project Alicorn is released under the [zlib License](LICENSE). Bundled fonts
and other third-party components keep their own notices; see
[`assets/fonts/README.md`](assets/fonts/README.md) and the relevant directories.
