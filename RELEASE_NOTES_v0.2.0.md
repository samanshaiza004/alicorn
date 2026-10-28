# Alicorn v0.2.0

Alicorn is an experimental native GUI runtime for Odin. It lets applications
describe interfaces with ordinary Odin code while retaining identity,
interaction, layout, text, semantics, and rendering products between updates.
This release strengthens the direct authoring API and adds real Windows/macOS
accessibility validation to the retained runtime.

## Highlights

- **Direct Odin UI authoring.** The `alicorn:ui` package provides a concise
  procedural entry point while using the same retained runtime and leaving
  application state in ordinary structs.
- **Richer retained controls and layout.** Tabs, text editing, adaptive
  presentations, multi-window hosting, integrated native title bars, and
  typed theme recipes build on retained layout and invalidation.
- **International text input.** Text editing includes selection, clipboard,
  IME composition, and font fallback across the validated native paths.
- **Experimental native accessibility.** An Odin AccessKit binding and native
  bridge expose common controls and text interactions to Windows UI Automation
  and macOS Accessibility. The final acceptance record includes physical
  Narrator/NVDA and VoiceOver checks, modal containment, and bounded virtualized
  content traversal. See the [#103 acceptance matrix](docs/validation/issue-103-final.md)
  for its evidence and limits.
- **Native application packaging tools.** Alicorn includes Windows and macOS
  packaging and dependency-audit tooling for applications using its SDL3 host.
- **Performance and diagnostics evidence.** Retained-work, text-layout,
  native-host, and material benchmarks document workload counters and their
  machine-specific limits.

## Tested platforms

The release candidate has physical validation on **Windows 10 22H2 x64** with
Direct3D 12 and **macOS 27.0 on Apple M1** with Metal. Validation includes
foreground input, IME, lifecycle, mixed-DPI movement, OS appearance changes,
and real screen-reader interaction. The tested native stack uses Odin
`dev-2026-09-nightly:a2fb372`, SDL 3.4.18, and AccessKit 0.23.1. The exact
per-session reader/IME versions, display scales, and some test traces were not
recorded; the linked validation matrix preserves those evidence limits.

Windows and macOS foundation, native packaging, and icon reproducibility
workflows passed on the integrated #103 acceptance candidate. The performance
and documentation changes in this release branch are being validated on the
combined tree separately; do not treat those earlier workflow runs as CI for
the final release SHA.

Linux has one conditional NixOS/Mango native validation record, not broad
platform support. The Linux native host has no AccessKit screen-reader adapter.

## Experimental status and limitations

This release is **not production-ready**. Alicorn's public API remains
experimental and may change; the widget and platform surface is still growing.
The accessibility integration is not a claim of comprehensive WCAG or native
accessibility conformance. Linux accessibility is unsupported, and custom
context menus and some less common widget patterns may have incomplete native
semantics. The blend readback suite uses offscreen RGBA8 targets; it does not
validate every native swapchain format or display color-management path.

macOS packages produced by the helper are locally ad-hoc signed. They are not
Developer ID signed or notarized. Signing, notarization, installers, update
channels, and distribution remain application release responsibilities.

## Release artifacts

v0.2.0 is a **source/toolkit release**. The GitHub Release does not include
prebuilt example applications. Build the examples and package your own
application using the [Getting Started guide](docs/getting-started.md) and
[native packaging guide](docs/packaging.md). Release commit, final workflow
links, and artifact metadata will be recorded when the tag is cut.

## Validation and performance records

- [Final Windows/macOS acceptance matrix](docs/validation/issue-103-final.md)
- [Windows performance audit](docs/benchmarks/performance-audit-windows-2026-10-27.md)
- [Performance evidence index](docs/performance.md)
- [Native application packaging](docs/packaging.md)
