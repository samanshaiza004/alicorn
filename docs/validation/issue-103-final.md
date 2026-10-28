# Alicorn #103 — Acceptance matrix

**Status: ACCEPTED — maintainer-confirmed physical validation complete (2026-10-27).** This closeout records the physical checks performed after the Windows acceptance and VoiceOver virtualization changes were integrated. The outcomes below are confirmed by the maintainer; detailed per-session traces and exact device/version metadata were not included in the closeout confirmation.

## Candidate and evidence boundary

- Integrated code candidate: [`6fb430a`](https://github.com/samanshaiza004/alicorn/commit/6fb430a11b9ced75dca13650554429a6a212f041), the merge of PR #150 onto PR #151's Windows acceptance work. The final matrix documentation was subsequently merged in PR #152; it did not change the tested code.
- The updated PR #150 head [`af0e8ff`](https://github.com/samanshaiza004/alicorn/commit/af0e8ff8ae34151a3b259999bd94aa7918bcc0a5) has the same source tree as `6fb430a`. Its Windows, macOS, packaging, and icon workflows passed.
- The maintainer confirmed the final physical checklist on the integrated candidate, including the packaged Windows build using SDL 3.4.18. The exact executable/build identifier for each physical session was not supplied.
- Detailed platform records: [Windows acceptance](issue-103-windows-2026-10-27.md) and [macOS acceptance](issue-103-macos-2026-10-27.md). Earlier machine and OS details remain in those records; this closeout does not retroactively infer missing scale factors, reader versions, or trace values.

## Final results

| Gate | Status | Evidence and limits |
| --- | --- | --- |
| D3D12 / Metal source-over parity | **PASS — automated** | On updated PR #150 candidate `af0e8ff`, [Windows foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40628541521) and [macOS foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40628541508) each passed 156/156 cases. Readbacks use offscreen `R8G8B8A8_UNORM`; native swapchain/color-space parity is outside this probe. |
| Windows foundation, native packaging, icons | **PASS — CI** | [Foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40628541521), [native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/40628541592), and [icon reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/40628541498) passed on `af0e8ff`. |
| Combined accessibility projection regressions | **PASS — local and CI** | Windows `tools/test.ps1` passed on `af0e8ff`; 254 runtime tests and the AccessKit/native contract checks passed. Windows and macOS foundation workflows also passed. |
| Windows foreground input and lifecycle | **PASS — maintainer-confirmed physical** | Confirmed on the packaged Windows application with SDL 3.4.18, including foreground interaction and window lifecycle. |
| Windows non-Latin IME | **PASS — maintainer-confirmed physical** | Composition/editing behavior was confirmed. The closeout confirmation did not include the IME name or individual composition/commit/cancel trace. |
| Narrator / NVDA | **PASS — maintainer-confirmed physical** | The final accessibility checklist was confirmed. Earlier records describe real reader use; exact reader versions and per-action traces were not included in the closeout confirmation. |
| Windows mixed-DPI movement | **PASS — maintainer-confirmed physical** | Cross-display DPI behavior was confirmed for the available test setup. Exact scale factors and display-by-display geometry notes were not supplied. |
| macOS foreground input, IME, and window lifecycle | **PASS — maintainer-confirmed physical** | Confirmed, including native titlebar/window interaction. Earlier record identifies Japanese IME, Cocoa, SDL 3.4.18, and Metal; the closeout did not include a per-action trace. |
| VoiceOver editable controls, including slider adjustment | **PASS — maintainer-confirmed physical** | The previously outstanding slider operation and editable-control checks were confirmed. Exact VoiceOver version and action trace were not supplied. |
| VoiceOver modal containment | **PASS — maintainer-confirmed physical** | Modal boundary behavior was confirmed. |
| VoiceOver virtualized million-row collection | **PASS — maintainer-confirmed physical** | Bounded traversal across virtualized working-set boundaries was confirmed after the projection changes. Full traversal to row 1,000,000 is not required. The closeout confirmation did not include the trace artifact or last announced row. |
| macOS mixed-DPI and display movement | **PASS — maintainer-confirmed physical** | Cross-display behavior was confirmed for the available setup. Exact display scales and movement trace were not supplied. |
| Appearance preferences and return to idle | **PASS — maintainer-confirmed physical** | The supported appearance-preference checks, update behavior, and return-to-idle behavior were confirmed. Exact per-preference counters or captures were not supplied. |
| GPU adapter and display formats | **LIMITATION RECORDED** | Adapter identity was not captured in the automated readback record. Blend tests use offscreen RGBA8 and do not verify every native swapchain format or display color-management path. These limits do not block the scoped #103 acceptance. |

## Close decision

The maintainer has confirmed the remaining physical input, accessibility, DPI, and appearance checks as passing on the integrated implementation. Together with the completed automated D3D12/Metal parity and CI evidence, this satisfies the acceptance scope of #103.

Some session metadata (exact scale factors, screen-reader/IME versions, and detailed physical traces) was not supplied with the final confirmation. It is identified above as a record limitation; no result or hardware configuration has been fabricated.

**Decision: close #103 as completed.**
