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
  `3.4.16` (`brew install sdl3`). Keep the SDL3 version at `3.4.16`; the host
  checks it when it starts.

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

## 4. Make a change

Open [`examples/native_hello/main.odin`](../examples/native_hello/main.odin).
Try changing `"Hello, Alicorn"` or the button label, save, and rerun the same
native command. The runner rebuilds before launching.

The app keeps its count in an ordinary Odin struct. Its build procedure emits
text and a button; when the button activates, the app updates that struct and
emits the new count. That is enough to start building your own UI.

## Explore the widget gallery

The gallery is a runnable reference for Alicorn's checkbox and slider controls.
It includes disabled states, stepped and continuous input, keyboard operation,
and a negative slider range:

```powershell
.\tools\widget_gallery.ps1
```

```sh
./tools/widget_gallery.sh
```

The app source is [`examples/widget_gallery/main.odin`](../examples/widget_gallery/main.odin).

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

The native path is exercised on Windows and macOS. Linux support is not yet
validated by this project; the headless checks can still be useful there, but
the native app should be considered experimental.

If a build fails, check `odin version`, the platform prerequisites above, and
the compiler's complete `base`, `core`, and `vendor` installation. The
[application guide](guide.md) is the next step after the window appears.
