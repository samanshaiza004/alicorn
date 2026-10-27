# Alicorn #103 — Native source-over blend readback

This record covers the GPU blending portion of #103 only. It does not establish
the physical input, accessibility, mixed-DPI, or secondary-window acceptance
gates.

## Candidate and method

- Production blend-state fix: [`e02a59d`](https://github.com/samanshaiza004/alicorn/commit/e02a59d68076ae62c2a5bbf211c67c2002090622).
- Expected-case-count guard: [`0902c1d`](https://github.com/samanshaiza004/alicorn/commit/0902c1dadb7a989e572bf3115237facfa55cff87). This revision requires exactly 156 cases: 48 surface, 24 geometry, 24 icon, 24 image, 24 text, and 12 mixed.
- Local Windows run: Windows 10, build 19045, AMD64; Odin `dev-2026-09-nightly:a2fb372`;
  Direct3D 12 backend. The GPU adapter model was not captured; Windows device enumeration
  was unavailable in this session.
- Windows CI: [`Alicorn foundation`](https://github.com/samanshaiza004/alicorn/actions/runs/40521632257),
  runner image `windows-2025-vs2026`.
- macOS CI: [`Alicorn foundation (macOS)`](https://github.com/samanshaiza004/alicorn/actions/runs/40521632268),
  runner image `macos-26-arm64`. Metal readback passed on this hosted runner;
  this is not physical Apple Silicon desktop acceptance.
- Case-count guard CI: [`Alicorn foundation`](https://github.com/samanshaiza004/alicorn/actions/runs/40523352092)
  and [`Alicorn foundation (macOS)`](https://github.com/samanshaiza004/alicorn/actions/runs/40523352035),
  both for `0902c1d`; Windows passed and macOS remained queued at the time this
  record was updated.
- Follow-up native packaging CI: [`Native packaging`](https://github.com/samanshaiza004/alicorn/actions/runs/40523352096),
  also for `0902c1d`.
- Native packaging CI: [`Native packaging`](https://github.com/samanshaiza004/alicorn/actions/runs/40521632328),
  success.
- Readback target: offscreen `R8G8B8A8_UNORM` texture. This is not a native
  swapchain or color-space test.
- Coverage: six renderer families, scales 1, 1.25, 1.5, and 2; destination
  alpha 0, 0.4, and 1; tolerance 2 RGBA8 values.
- Commands: `tools/validate_blending.ps1 -Odin <odin.exe>` and
  `tools/test.ps1 -Odin <odin.exe>`.

## Results

| Platform / backend | Result | Evidence |
| --- | --- | --- |
| Windows local / Direct3D 12, corrected source-over state | PASS | 156/156 readback cases; all six families passed |
| Windows CI / Direct3D 12 | PASS | 156/156 readback cases on `windows-2025-vs2026` |
| macOS CI / Metal | PASS | 156/156 readback cases on hosted `macos-26-arm64` |
| `0902c1d` case-count guard / Windows local Direct3D 12 | PASS | 156 executed; 156 expected; per-family counts matched |
| `0902c1d` Windows foundation / native packaging / icon CI | PASS | Run `40523352092`, `40523352096`, and `40523352099` succeeded |
| `0902c1d` macOS foundation | QUEUED | Run `40523352035` had not started at the time of this record |
| Windows / legacy master factors | FAIL as expected | 108/156 cases failed; surface, geometry, text, and mixed failed; icon and image passed |
| Physical Apple Silicon desktop / Metal | BLOCKED | Hosted macOS CI is not a physical desktop interaction session |
| Full #103 physical acceptance | BLOCKED | Physical input/IME, Narrator or NVDA, VoiceOver, mixed-DPI movement, and secondary-window interaction remain unverified here |

The legacy-factor run used the exact existing pattern: `.SRC_ALPHA` for solid,
surface, and text output alpha, and `.ONE` for icon and image output alpha. Its
108 failures confirm that the probe detects the defect under investigation.

The full Windows `tools/test.ps1` suite passed on the blend-fix revision,
including the non-GPU blend-factor assertion. Both hosted GPU readback runs
passed on that revision. The follow-up `0902c1d` run also passed locally with
the exact total and per-family case-count checks enabled. Its hosted CI is
tracked separately above so the evidence identifies which revision each run
actually exercised.

## Limitation

The probe exercises Alicorn's production renderer pipelines and actual GPU
compositing, but only on an offscreen `R8G8B8A8_UNORM` target. It does not prove
swapchain-format, display color-space, or physical presentation parity. Keep
#103 open until the remaining physical acceptance matrix is recorded against
an identifiable candidate commit. The probe reports SDL's selected backend;
the GPU adapter model was not captured locally or in the cited hosted CI runs.
