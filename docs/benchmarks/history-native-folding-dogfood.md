# History binary block native dogfood — Alicorn #50

The next application experiment is implemented on History branch `codex/folding-projection`, based on History master `e0eb3d4`. The isolated working checkout is `out/history-folding-dogfood/` in this Alicorn workspace; History owns and tracks that checkout's code. Enable it with History's `--folding` argument or Windows `tools/run.ps1 -Folding`.

The public projection API uses distinct old/new line, display row, hunk, source-index, byte, pixel and count types over one private dimensional query engine. The UI owns a binary block directory borrowing immutable parsed hunks. Whole-hunk folding changes only the display measure, preserving old/new source extents and one placeholder. It supports multiple folds and hunks spanning blocks without structural splices. Stale worker results remain rejected before adoption.

Native selection is by source row through the gutter control. Its identity survives hiding and virtual-node retirement. The top source target and fractional scroll offset survive folding; later scrolling and explicit hunk navigation supersede pending restoration. Header and placeholder controls stay visible while code is horizontally scrolled. Projection preparation and numeric aggregation reject invalid data, overflow, and allocation failure before replacing a live index.

History's full self-test, four negative type-compilation contracts, and six bounded native processes passed. Windows 10, Direct3D 12, 1200 × 800 at 100% scale, Odin `dev-2026-09-nightly:a2fb372`, optimized build, one compiler thread and one native process at a time. The native fixture is the actual 128-row, nine-hunk History scroll patch at `3a22f38`. The finite script verifies simultaneous folds, hidden targets, selection, fractional/horizontal restoration, and later user-originated scroll intent; controls are separately exercised through semantic Press actions.

| Median of three process-level measurements | Expanded display array | Binary directory dogfood |
| --- | ---: | ---: |
| Ordinary native build p95 | 1.346 ms | 1.291 ms |
| Ordinary active CPU-stage p95 | 2.713 ms | 2.231 ms |
| Index + viewport staging capacity | 7,224 B | 4,392 B |

The active-stage figure sums build, native GPU encoding and submission for 29 ordinary presentations per process. It excludes GPU execution, fence/event waits and input latency. The host's global frame percentile contains idle-loop samples and is not an active-frame measurement. The compact build clears the 5% regression guardrail on this small fixture; three processes and overlapping build-time ranges do not prove a general speedup. Memory counts include the extra viewport staging but exclude shared parsed data, renderer storage, allocator overhead and preparation peak.

Detailed source hashes, raw stdout, per-presentation stage JSON, screenshot, methodology and remaining gates live in History's `research/folding-projection.md` and adjacent artifacts. The native fixture uses actual render/shape/submit work driven by scheduled application commands; it is not a captured human input session. Larger real-world traces and cross-platform/DPI validation remain necessary before default adoption. General B+ tree mutation, concurrency and package extraction remain deferred; Alicorn's sparse height index is unchanged.
