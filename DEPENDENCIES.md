# Dependency and version notes

The verification environment used for this foundation snapshot is:

- Odin `dev-2026-09-nightly:a2fb372`;
- SDL3 package from the Odin SDK vendor collection, with `SDL3.lib` and
  `SDL3.dll` available on Windows;
- Runa: not installed or discoverable in the Odin SDK.

The headless runtime has no external dependency beyond Odin's core packages.
The native probe imports `vendor:sdl3`; its build is intentionally separate so
CI can run structural tests without a window system or GPU driver.

When adding Runa, record the exact repository revision and API surface here,
then replace `Text_Engine`'s unconfigured provider with a small adapter. Do not
make Runa's atlas representation the GUI text abstraction.

