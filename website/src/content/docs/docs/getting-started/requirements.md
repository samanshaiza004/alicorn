---
title: System requirements
description: Toolchain and platform prerequisites for building Alicorn's native examples.
---

Alicorn is a source project for applications written in Odin. It does not have
a separate runtime installer for end users.

## Odin

Install the complete Odin distribution from the
[official Odin installation guide](https://odin-lang.org/docs/install/).
Keep the compiler together with its <code>base</code>, <code>core</code>, and
<code>vendor</code> directories. The project documents its current tested
compiler baseline in the
[repository getting-started guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/getting-started.md).

Check the compiler from a new terminal:

~~~sh
odin version
~~~

## Native build tools

The exact packages vary by operating system. The source guide is the current
reference; the short outline is:

- **Windows:** Visual Studio or Build Tools with Desktop development with C++,
  MSVC, and a Windows SDK. Use an Odin distribution with its SDL3 vendor
  package and runtime.
- **macOS:** Xcode Command Line Tools and the SDL3 development package pinned
  by the Alicorn host.
- **Linux:** a graphical session, Vulkan-capable SDL3 development files,
  Fontconfig, <code>pkg-config</code>, and a C compiler. Linux validation is
  currently narrower than Windows/macOS validation.

The native AccessKit integration is currently Windows/macOS only. See
[Accessibility status](/docs/guides/accessibility) for the boundary.

## Verify the setup

Clone the project and run the headless checks:

~~~sh
git clone https://github.com/samanshaiza004/alicorn.git
cd alicorn
./tools/check.sh
~~~

On Windows, use <code>.\tools\check.ps1</code>. The check compiles examples
and exercises the runtime without opening a native window.

Next: [run your first app](/docs/getting-started/first-app).
