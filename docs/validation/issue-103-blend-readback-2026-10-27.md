# Alicorn #103 — Native source-over blend readback

This record covers the GPU blending portion of #103 only. It does not establish
the physical input, accessibility, mixed-DPI, or secondary-window acceptance
gates.

## Candidate and method

- Base revision: `8f7450021901f083d444c689d21e63f5ed9318bc` (`master`).
- Validation changes: local, uncommitted work on `codex/issue-103-blend-parity`;
  a final candidate revision has not yet been assigned.
- Windows: Windows 10, build 19045, AMD64; Odin `dev-2026-09-nightly:a2fb372`;
  Direct3D 12 backend.
- GPU adapter model: not captured by this harness or available to this session;
  record it before treating this as final hardware evidence.
- Readback target: offscreen `R8G8B8A8_UNORM` texture. This is not a native
  swapchain or color-space test.
- Coverage: six renderer families, scales 1, 1.25, 1.5, and 2; destination
  alpha 0, 0.4, and 1; tolerance 2 RGBA8 values.
- Commands: `tools/validate_blending.ps1 -Odin <odin.exe>` and
  `tools/test.ps1 -Odin <odin.exe>`.

## Results

| Platform / backend | Result | Evidence |
| --- | --- | --- |
| Windows / Direct3D 12, corrected source-over state | PASS | 156/156 readback cases; all six families passed |
| Windows / legacy master factors | FAIL as expected | 108/156 cases failed; surface, geometry, text, and mixed failed; icon and image passed |
| macOS / Metal | BLOCKED | No macOS runner was available in this validation session; the foundation workflow now invokes the Metal probe |
| Full #103 physical acceptance | BLOCKED | Physical input/IME, Narrator or NVDA, VoiceOver, mixed-DPI movement, and secondary-window interaction remain unverified here |

The legacy-factor run used the exact existing pattern: `.SRC_ALPHA` for solid,
surface, and text output alpha, and `.ONE` for icon and image output alpha. Its
108 failures confirm that the probe detects the defect under investigation.

The full Windows `tools/test.ps1` suite passed, including the new non-GPU blend
factor assertion. A Darwin arm64 `odin check` of the probe entry point also
passed; that is a type-check only, not Metal compilation or execution.

## Limitation

The probe exercises Alicorn's production renderer pipelines and actual GPU
compositing, but only on an offscreen `R8G8B8A8_UNORM` target. It does not prove
swapchain-format, display color-space, or physical presentation parity. Keep
#103 open until a macOS Metal readback and the remaining physical acceptance
matrix are recorded against an identifiable candidate commit.
