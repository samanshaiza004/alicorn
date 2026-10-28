# SDL 3.4.18 Upgrade Validation

> Historical report from 2026-10-20. Its Windows validation-pending note was
> resolved by the later Windows/macOS candidate and packaging checks recorded
> in the [final #103 acceptance matrix](../../validation/issue-103-final.md).

Date: 2026-10-20  
Candidate: `chore/sdl-3.4.18`, based on Alicorn `0b52d7ee`  
Host: macOS 27, Apple Silicon (`arm64`), Odin `dev-2026-09-nightly+2026-09-01`

This is a local validation record, not a release approval. The candidate changes
were uncommitted when tested.

## Result

The macOS regression and package checks passed against SDL 3.4.18. The exact
version guard remains enabled. SDL was built from its official 3.4.18 source
archive (`9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3`)
for both the Alicorn static-package test and Scratchpad's shared macOS package.

## Alicorn checks

Passed:

- `sh tools/check.sh` and `sh tools/test.sh` (including 215 runtime tests,
  35 theme tests, and 82 native-host tests).
- `python3 tools/test_package_macos.py` (7 tests).
- `sh tools/validate_icons.sh` on Metal (twice) and
  `sh tools/validate_images.sh` on Metal.
- `sh tools/native_sdl_gpu.sh --menu-fixture --menu-fixture-smoke` on Metal.
- `sh tools/native_hello.sh --idle-validation-seconds=3` reported SDL 3.4.18,
  Metal, one submitted/retired frame, two event waits, zero input events, zero
  application ticks, and zero wake events.
- Static native package build from pinned SDL source, followed by package
  verification and a clean-directory Metal launch smoke. The package manifest
  records SDL 3.4.18, static linkage, and the source URL/checksum. The resulting
  Alicorn starter package was approximately 9 MiB and has no dynamic SDL
  dependency.

The SDL source provenance is now included in macOS package manifests for both
shared and static linkage: macOS packaging builds the pinned source in either
case. The static link path also uses an explicit archive force-load, and the
package audit verified that the executable does not retain an SDL dylib
dependency.

## Scratchpad consumer checks

In isolated worktree `/private/tmp/scratchpad-sdl-3.4.18`, the SDL pin and test
fixtures were updated to 3.4.18.

Passed:

- `go test ./...`.
- `sh tools/alicorn.sh test ...`: Go tests and all 152 Alicorn frontend tests,
  including the native text-input and layout fixtures.
- Built a Scratchpad `v0.2.0` arm64 package from the pinned SDL source, then
  verified the ZIP checksum, ad-hoc code signature, and clean-directory
  extracted-app launch smoke.
- The app and bundled SDL link only to system frameworks/libraries or
  bundle-relative `@rpath` dependencies. `otool -L` shows no Homebrew path.
- The selected linker input is recorded in `native-link-input.json` and the
  actual link trace names the SDL library under the temporary 3.4.18 build
  prefix. The embedded app manifest now records the SDL source URL and
  checksum, not only the runtime version.
- Go/cgo, Rust, and native link inputs use the same macOS 13.0 minimum; the
  package `Info.plist` also declares 13.0.

The temporary candidate is at
`/private/tmp/scratchpad-sdl-3.4.18/out/packages/sdl-3.4.18-candidate-provenance`;
the app is about 35 MiB and its ZIP about 19 MiB. The prior 3.4.16 test bundle
was also about 35 MiB / 19 MiB at this rounded size.

## 3.4.16 comparison and limits

The existing 3.4.16 idle smoke and the fresh 3.4.18 idle smoke both showed the
same expected idle behavior: one initial submission/retirement, event-driven
waiting, no ongoing application ticks, and no wakeups. Their one-shot
`frame_p95_ns` values were 44.7 ms (3.4.16) and 206.0 ms (3.4.18). These are
short startup/idle probes with very few frames, not a controlled performance
comparison; they provide no evidence of a meaningful performance change. No
SDL-level throughput regression was observed in the GPU validation suite.

Windows validation remains required: this host has no PowerShell runner, so
the pinned Windows SDL build, D3D12 native suite, and Windows package job were
not run. Run the normal Windows CI/native/package matrix before promoting the
pin. The repository also has no integrated-titlebar acceptance fixture yet;
the menu fixture does not validate integrated titlebar behavior. Manual IME,
secondary-window interaction, and cross-display resizing should be repeated
against the new pin if they are part of the v0.2.0 acceptance gate.
