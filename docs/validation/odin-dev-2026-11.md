# Odin `dev-2026-11` migration validation

Captured 2026-11-03 on Windows x86-64. This record covers the compiler-baseline
migration; it does not replace the platform acceptance reports for native UI
behavior.

## Toolchain

- Official release: [Odin `dev-2026-11`](https://github.com/odin-lang/Odin/releases/tag/dev-2026-11), signed source tag `e28f5d1`.
- Windows archive compiler: `dev-2026-11-nightly:9a69916`.
- Windows archive SHA-256: `259effedf2997293c8fa4a5e497496f8ebce9f826652d9dd353a9dd2113c31fd` (verified before extraction).
- Installed only under this worktree's ignored `out/toolchains/odin-dev-2026-11/`; the September SDK remains installed for rollback.
- Default atomic-order analysis was enabled for all ordinary checks. No compiler analysis was disabled.

## Results

| Check | Result |
| --- | --- |
| `tools/check.ps1 -Odin <November odin.exe>` | PASS |
| Runtime tests | 317 passed |
| Accessibility contract fixture tests | 1 passed |
| UI tests | 39 passed |
| Theme tests | 35 passed |
| Native SDL GPU tests | 168 passed |
| Scroll/capture tests | 6 passed |
| AccessKit C ABI and external-consumer smoke | PASS |
| Windows UI Automation accessibility fixture | PASS |
| Windows shared-SDL release package and empty-directory launch smoke | PASS |
| Packaged Windows executable with a UTF-8 diagnostic path argument | PASS |
| Darwin ARM64 native-host type-check from Windows | PASS |
| `-vet-atomic-access` on runtime | 317 passed |
| `-vet-atomic-access` on native SDL GPU host | 168 passed |
| `git diff --check` | PASS |

The Darwin check type-checks the updated AppKit/Foundation bindings; it does not
link or execute a macOS application. The Windows UI Automation fixture passed
on rerun after one initial transient `Accessible Button missing` result.

## Migration changes

- CI now selects `dev-2026-11` instead of an unpinned nightly.
- The macOS SDK bootstrap verifies the November Apple Silicon archive and has
  an explicit Intel source-build path pinned to the release tag. The Intel
  branch was not executable on this Windows machine.
- Alicorn now uses the November AppKit/Foundation binding names and ownership
  operations while retaining the existing native menu, titlebar, and
  appearance-monitor behavior.
- Image decoding reads `core:image.Image.pixels` as the new dynamic byte array.
- Text paint/style span submission copies caller slices into frame scratch
  before retaining them through reconciliation. A regression test covers
  caller-local span arrays.
- Native inspector and host-waker storage now lives in the caller-owned native
  menu bridge for the full application-loop lifetime. A test helper also clears
  borrowed virtual keys when its callback returns.

## Not established here

- Physical macOS or Linux behavior, including menus, integrated titlebars,
  accessibility, window lifecycle, and native linking.
- A real Intel macOS source build or execution of the macOS bootstrap script.
- A Windows static-SDL release-package build: the local static package command
  stopped before compilation because `cmake.exe` is not installed or on `PATH`.
  The shared-SDL package did build and pass its empty-directory launch smoke.
- Compiler-time/memory comparison against September, or a performance claim
  about the November compiler.

Those checks remain platform-specific validation work; the November SDK is
type-checked and test-validated on this Windows host without turning off its
new default analysis.
