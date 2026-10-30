# Getting Started

This gets a small native Alicorn application on screen. You will build the
project, run the starter app, change its UI, and run it again.

## 1. Install the prerequisites

Install Git and a **complete Odin distribution** from the
[official Odin installation guide](https://odin-lang.org/docs/install/). Keep
the compiler beside its `base`, `core`, and `vendor` directories; copying only
`odin.exe` or `odin` is not enough. Alicorn was checked with Odin
`dev-2026-09-nightly:a2fb372`.

Also install the native platform tools:

- **Windows:** Visual Studio or Build Tools with **Desktop development with
  C++**, including MSVC and a Windows SDK. Use an Odin distribution with its
  `vendor/sdl3` package and `SDL3.dll`.
- **macOS:** Xcode Command Line Tools (`xcode-select --install`) and SDL3
  `3.4.18` (`brew install sdl3`). Keep the SDL3 version at `3.4.18`; the host
  checks it when it starts.
- **Linux:** a Wayland session, Vulkan-capable SDL3 development and library
  outputs, Fontconfig, `pkg-config`, and a C compiler. `vulkan-tools` and
  `wayland-utils` are recommended for host inventory. On NixOS, the
  [Linux acceptance matrix](validation/linux-native-acceptance.md) uses a
  temporary shell so the system profile is not changed.

Native build helpers check out [odin-accesskit](https://github.com/samanshaiza004/odin-accesskit)
at the exact commit in [`dependencies/odin-accesskit.json`](../dependencies/odin-accesskit.json)
into the ignored `.deps/odin-accesskit/` directory. They invoke its native
bootstrap with Alicorn's existing `.deps/accesskit/` cache, preserving the
AccessKit C `0.23.1` release archive and checksum verification. Network access
is needed on first use, after removing a cache, or when the pin changes. The
helpers pass the binding collection to Odin and do not modify the Odin
installation. The native AccessKit adapter is currently Windows/macOS only.
See [dependency and external consumer usage](../dependencies/README.md) for
manual builds.

Put the directory containing `odin` on `PATH`. In a new terminal, verify it:

```text
odin version
```

For matching the tested toolchain, the output should identify
`dev-2026-09-nightly:a2fb372`.

## 2. Clone and check the project

```text
git clone https://github.com/samanshaiza004/alicorn.git
cd alicorn
```

Build the headless examples and run Alicorn's tests:

```powershell
.\tools\check.ps1
```

```sh
./tools/check.sh
```

The check is headless; it does not open a window.

## 3. Run the native starter app

The starter has an **Increment** button and displays its count. Run the command
for your platform:

```powershell
.\tools\native_hello.ps1
```

```sh
./tools/native_hello.sh
```

Close the window to return to the terminal. The Windows runner copies the
matching `SDL3.dll` from the Odin distribution into `out/` before launch. The
macOS runner links against the SDL3 installation from step 1.

For an unsigned distributable folder or `.app`, including the static-SDL release
path and dependency audit, see [Native application packaging](packaging.md).

## 4. Make a change

Open [`examples/01_hello/main.odin`](../examples/01_hello/main.odin).
Try changing `"Hello, Alicorn"` or the button label, save, and rerun the same
native command. The runner rebuilds before launching.

The app keeps its count in an ordinary Odin struct. Its render procedure
describes text and a button; when the button activates, the app updates that
struct. `ui.run` supplies the routine single-window host and frame lifecycle.
That is enough to start building your own UI.

## Explore the form example

The form uses only `alicorn:ui` for layout, text, a managed controlled text
field, and pointer-bound checkbox and slider. Informational text and standard
controls expose their accessibility semantics by default; use
`decorative=true` for text that should remain visual-only:

```powershell
.\tools\run_example.ps1 -Example 02_form
```

```sh
./tools/run_example.sh 02_form
```

The app source is [`examples/02_form/main.odin`](../examples/02_form/main.odin).
Browse icons and named icon buttons in the
[Control Gallery](../examples/08_control_gallery/main.odin).
Continue through the [numbered example progression](../examples/README.md) for
worker-backed virtualization, custom GPU surfaces, and the built-in inspector.
Step 3 keeps the same typed render procedure and `alicorn:ui` import, adding
app-owned workers through `ui.run` lifecycle hooks and a scoped virtual list.

## If Odin is not on `PATH`

You can point a single command at the compiler instead:

```powershell
.\tools\check.ps1 -Odin 'C:\dev\Odin\odin.exe'
```

```sh
./tools/check.sh --odin /opt/odin/odin
```

Or set `ALICORN_ODIN` for the current shell. Install the full Odin
distribution before using a custom compiler path.

## Platform status

The native path is exercised on Windows and macOS. Linux has a conditional
validation record from one NixOS 26.11/Mango 0.16.2 machine, but this is not
broad Linux support; the native app remains experimental. See the
[Linux validation record](validation/linux-nixos-mangowc-2026-10-23.md) and the
[repeatable acceptance matrix](validation/linux-native-acceptance.md).

If a build fails, check `odin version`, the platform prerequisites above, and
the compiler's complete `base`, `core`, and `vendor` installation. The
[application guide](guide.md) is the next step after the window appears.
