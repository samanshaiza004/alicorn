# Initial v0.2.1 release-candidate validation — 2026-11-06

Initial candidate baseline: `072aaf5a29e97f5dad6296dff84835f9f707fcbf` (`origin/master`,
2026-11-06). The release range starts at tag `v0.2.0` and contains 60
first-parent commits. The complete commit and merged-PR inventory is in the
[consolidated changelog](../../../CHANGELOG.md).

## Validation evidence

| Area | Result | Evidence |
| --- | --- | --- |
| Odin `dev-2026-11` Windows migration | PASS | [Migration record](../../validation/odin-dev-2026-11.md): runtime, UI, theme, native SDL GPU, scroll/capture, and accessibility contract suites; examples, ABI, package smoke, and atomic-access checks. |
| Connected-tab close refinement | PASS | [PR #176](https://github.com/samanshaiza004/alicorn/pull/176), head `8137bc3fa3a3aacc6856ce5d6dae5a1427b8f33c`: headless, Windows static SDL, macOS SDL, and icon regeneration jobs succeeded. |
| CPU paint reference | PASS | [PR #161](https://github.com/samanshaiza004/alicorn/pull/161), head `875e189f870cdf0246811101920ffedf64cc58c9`: Windows/macOS foundation and packaging plus icon reproducibility checks succeeded. |
| Construction attribution | PASS | [PR #160](https://github.com/samanshaiza004/alicorn/pull/160), head `fb5b060d96dbb830454b4fabfeca16165a5f6453`: Windows/macOS foundation, packaging, and icon jobs succeeded. |
| Deferred layout-trace formatting | PASS | [PR #159](https://github.com/samanshaiza004/alicorn/pull/159), head `c0ba666e1646abcbce8ba2b5934547267fdc989c`: final Windows/macOS and icon jobs succeeded; the earlier headless attempt was cancelled and a later headless run passed. |
| CPU/GPU paint differential | PASS | PR #161 records 156 targeted cases, 32 generated scenes, and a minimized clipping regression on Windows D3D12 and macOS Metal at 2/255 per-channel tolerance. |
| Performance | PASS with limits | [Windows scorecard](../../benchmarks/performance-scorecard-v0.2.1-windows-2026-11-04.md) and [macOS Issue #157 report](../../benchmarks/issue-157-construction-cpu-macos-2026-11-04.md) record measured results and accepted remaining construction cost. They do not establish cross-platform frame-latency guarantees. |
| Documentation integrity | PASS | `git diff --check` and local-link verification passed for the release documentation changes. |

## Local validation boundary

The local Windows PATH compiler is Odin `dev-2026-09-nightly:a2fb372`, while
this release baseline migrated to `dev-2026-11`. The November toolchain is not
installed in this checkout, so the full current-source suite was not rerun
locally with the older compiler. The exact toolchain's Windows validation is
recorded above; the release changes themselves only edit documentation and
consolidate existing release notes.

The November migration record does not establish physical macOS or Linux
behavior, an Intel macOS build/run, or a local Windows static-SDL package build
without CMake. Existing platform acceptance reports retain those limits. Linux
remains conditionally tested on one NixOS/Mango environment and has no AccessKit
adapter.

## Layout sizing scope

The release includes the sizing behavior already merged on master, including
the corrected typed helper defaults and definite-parent percentage-width
retention. It adds no new layout-resizing work. Percentage height, intrinsic fit
width, arbitrary relative constraints, aspect-ratio solving, and a general
constraint solver remain deferred to future research.
