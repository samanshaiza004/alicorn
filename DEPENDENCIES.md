# Dependency and version notes

The verification environment used for this foundation snapshot is:

- Odin `dev-2026-09-nightly:a2fb372`;
- SDL3 package from the Odin SDK vendor collection, with `SDL3.lib` and
  `SDL3.dll` available on Windows;
- Runa: vendored under `third_party/Runa` at commit
  `4dd00c541c374938b192e23dc2efa983748a92ab` (the upstream 1.3.1 line:
  Thai word-break dictionary is opt-in). Alicorn uses the default
  `RUNA_THAI_DICT=false` configuration; the vendored corpus is present for
  reproducible opt-in builds, but Alicorn does not enable it by default.
  Enabling it requires retaining the upstream CC-BY-SA attribution and
  share-alike obligations. The adapter uses `font_load`, `layout_paragraph`,
  `line_destroy` and `cache_make/cache_size/cache_destroy`; the GUI does not
  expose Runa's atlas representation.

The headless runtime has no external dependency beyond Odin's core packages.
The native probe imports `vendor:sdl3`; its build is intentionally separate so
CI can run structural tests without a window system or GPU driver.

`runtime/text.odin` owns a cloned font byte buffer, parsed Runa font, bounded
shape cache and GUI-facing layout metrics. `examples/runa_text` is the
reproducible font/layout/cache proof. Do not make Runa's atlas representation
the GUI text abstraction.
