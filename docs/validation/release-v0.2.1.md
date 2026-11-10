# Alicorn v0.2.1 release validation — 2026-11-10

Validated source baseline: `974d74cde2c2e38f931c1cfb74280dfc5966f680`.
The final release includes the complete v0.2.0-to-v0.2.1 history documented in
[`CHANGELOG.md`](../../CHANGELOG.md). Toolchain: Odin `dev-2026-11:9a6991685`.
Local host: Apple Silicon, macOS 27.2 (build 26B123).

## Hosted checks

All five hosted checks passed on the validated source baseline:

| Check | Result | Evidence |
| --- | --- | --- |
| Windows foundation, including Direct3D 12 effect readback | PASS | [Windows foundation](https://github.com/samanshaiza004/alicorn/actions/runs/42905677375) |
| macOS foundation, including Metal effect readback | PASS | [macOS foundation](https://github.com/samanshaiza004/alicorn/actions/runs/42905677597) |
| Windows static-SDL package | PASS | [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/42905677704) |
| macOS SDL package | PASS | [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/42905677704) |
| Icon asset reproducibility | PASS | [Icon asset reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/42905677377) |

The release-preparation documentation commit `629efa0c46de19cd46bb07d3cae567b7cd6959f0`
also passed all five hosted checks. The final release documentation changes do
not alter executable sources; their exact commit checks are available from the
repository's [Actions page](https://github.com/samanshaiza004/alicorn/actions).
The foundation jobs include native unit/contract suites, example builds, and
GPU readback validation on their hosted backends. Package checks do not imply
physical desktop acceptance on every OS, driver, or device.

## Local checks

| Command | Result | Notes |
| --- | --- | --- |
| `CLANG_MODULE_CACHE_PATH=/private/tmp/alicorn-v021-release-20261110/out/clang-module-cache sh tools/check.sh` | PASS | AccessKit ABI/external-consumer checks, examples, theme CLI, and the foundation, UI, testui, and theme suites passed. |
| `CLANG_MODULE_CACHE_PATH=/private/tmp/alicorn-v021-release-20261110/out/clang-module-cache sh tools/test.sh` | PASS | Includes 169 native SDL/GPU tests, 6 scroll/capture tests, the text-input host contract, and restart/restoration checks. |
| `CLANG_MODULE_CACHE_PATH=/private/tmp/alicorn-v021-release-20261110/out/clang-module-cache sh tools/validate_effects.sh --odin /opt/homebrew/bin/odin --driver=metal` | BLOCKED | SDL reported `The video driver did not add any displays`; local Metal readback could not run. The hosted macOS Metal readback passed. |
| `git diff --check` | PASS | No whitespace errors in the release documentation. |

The first local `tools/test.sh` attempt used Clang's default module-cache
location under the user's home directory and could not write there in the
isolated checkout. Re-running with `CLANG_MODULE_CACHE_PATH` inside the
checkout passed. The local native-effects attempt compiled and passed its 169
unit tests before SDL initialization stopped at the unavailable display.

## Release scope and platform limits

Alicorn remains experimental and API-unstable. Hosted Windows D3D12 and macOS
Metal validation passed for this source baseline. Physical interactive checks
are limited to the evidence recorded in the linked validation reports; this
release does not certify every OS version, driver, display scale, assistive
technology, or GPU. Linux remains conditionally tested on one NixOS/Mango
environment and has no AccessKit adapter. macOS packages are ad-hoc signed,
not Developer ID signed or notarized. Distribution signing, installers,
updates, and notarization remain application-release responsibilities.
