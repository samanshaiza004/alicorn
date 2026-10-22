# Alicorn v0.1.1

Alicorn v0.1.1 is a maintenance release based on v0.1.0. It contains two
focused macOS pointer-input fixes and no public API changes.

## Fixes

- Map macOS Control-primary-click to Alicorn's secondary-button context-click
  behavior while preserving the Control modifier for applications.
- Keep the logical button selected on pointer-down through the matching
  pointer-up, even if the Control modifier changes during the gesture. Clear
  held button mappings when the window loses focus.

These changes leave pointer behavior on Windows and other platforms unchanged.

## Compatibility

Applications using v0.1.0 can adopt v0.1.1 without source changes. Rebuild the
application with the v0.1.1 Alicorn source to receive the native-host fixes.

## Validation

The Windows release snapshot passed `tools/check.ps1` using Odin
`dev-2026-09-nightly:a2fb372`. This builds the examples and runs the runtime,
native-host, and text-input contract tests. The macOS foundation workflow is
used for the corresponding cross-platform check.