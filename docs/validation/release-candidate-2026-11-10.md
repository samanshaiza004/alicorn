# Release candidate validation — 2026-11-10

Code baseline validated: `974d74cde2c2e38f931c1cfb74280dfc5966f680`
(`master` before release documentation updates). Toolchain: Odin
`dev-2026-11:9a6991685`. Local host: Apple Silicon, macOS 27.2 (build
26B123).

## Hosted checks

All five check runs for the candidate revision passed:

| Check | Result | Evidence |
| --- | --- | --- |
| Windows foundation, including Direct3D 12 effect readback | PASS | [Alicorn foundation](https://github.com/samanshaiza004/alicorn/actions/runs/42905677375) |
| macOS foundation, including Metal effect readback | PASS | [Alicorn foundation (macOS)](https://github.com/samanshaiza004/alicorn/actions/runs/42905677597) |
| Windows static-SDL package | PASS | [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/42905677704) |
| macOS SDL package | PASS | [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/42905677704) |
| Icon asset reproducibility | PASS | [Icon asset reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/42905677377) |

The foundation jobs include native unit/contract suites, example builds, and
GPU readback validation on their hosted backends. Package checks do not imply
physical desktop acceptance on every supported OS, driver, or device.

## Local checks

| Command | Result | Notes |
| --- | --- | --- |
| `CLANG_MODULE_CACHE_PATH=/private/tmp/alicorn-v021-release-20261110/out/clang-module-cache sh tools/check.sh` | PASS | AccessKit ABI/external-consumer checks, examples, theme CLI, and the foundation, UI, testui, and theme suites passed. |
| `CLANG_MODULE_CACHE_PATH=/private/tmp/alicorn-v021-release-20261110/out/clang-module-cache sh tools/test.sh` | PASS | Includes 169 native SDL/GPU tests, 6 scroll/capture tests, the text-input host contract, and restart/restoration checks. |
| `CLANG_MODULE_CACHE_PATH=/private/tmp/alicorn-v021-release-20261110/out/clang-module-cache sh tools/validate_effects.sh --odin /opt/homebrew/bin/odin --driver=metal` | BLOCKED | The local SDL environment reports `The video driver did not add any displays`; no local Metal readback ran. The hosted macOS Metal readback passed above. |
| `git diff --check` | PASS | No whitespace errors in the candidate documentation changes. |

The first `tools/test.sh` attempt used Clang's default module-cache location
under the user's home directory and could not write there in the isolated
workspace. Re-running with `CLANG_MODULE_CACHE_PATH` inside the temporary clone
completed successfully. The native-effects attempt compiled and passed its 169
unit tests before SDL initialization stopped at the unavailable display.

## Existing version tag

The remote already contains an annotated `v0.2.1` tag at
`44a7b84d3c87a687e718162e7235412782e97c8e`, while this candidate is 41 commits
ahead of that tag (32 non-merge commits). The GitHub Releases API returns 404
for `v0.2.1`, so there is no release object attached to the tag. Reusing this
version for the candidate would require moving the existing public tag; this
record does not do so.
