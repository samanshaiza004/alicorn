---
title: Build and test
description: Run the native examples and repository checks while developing Alicorn applications.
---

From the repository root, run the headless checks:

~~~sh
./tools/check.sh
~~~

On Windows PowerShell:

~~~powershell
.\tools\check.ps1
~~~

These checks compile the examples and internal fixtures without opening a
window.

To build and run the native hello example:

~~~sh
./tools/native_hello.sh
~~~

~~~powershell
.\tools\native_hello.ps1
~~~

The repository's
[Getting Started guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/getting-started.md)
lists the full platform toolchain. The
[contributor guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/development.md)
covers focused suites, host fixtures, diagnostics, and packaging.

## Keep validation claims specific

A headless test establishes runtime behavior covered by that test. It does not
establish native window presentation, OS accessibility behavior, or GPU output.
Use the matching native fixture and physical platform checks for those claims.
