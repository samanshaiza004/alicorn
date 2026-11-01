# Issue #106 — Incremental-vs-fresh-runtime invalidation oracle

Status: initial bounded oracle implemented. Issue #106 remains open for
expanding the action corpus and deciding whether its added coverage remains
worth the maintenance cost.

## Purpose and boundary

`runtime/invalidation_coherence_test.odin` compares a retained runtime after
declared app-model mutations with a fresh runtime described from the same model.
It is a deterministic test fixture, not production instrumentation. It does not
observe arbitrary Odin memory, infer missing revisions, or add per-frame
full-tree scans to applications.

The current fixture has three keyed regions and one unrelated peer. It exercises
content changes, typography scale, analytic surface material, combined changes,
root/parent/child invalidation, keyed reorder/removal, focus and semantic state,
text-field interaction and line geometry, and settled idle behavior. The
comparison uses public node/key queries, `Node_Info`, semantic snapshots,
text-field queries, text-line geometry, and stable resolved style/paint summaries
from the public inspector. Runtime-private node maps, display lists, and text-run
tables are not read. The inspector projection is not a GPU pixel comparison.

## Seeded failure and replay

The test `test_seeded_invalidation_oracle_replays_and_shrinks_wrong_region_failure`
uses fixed seed `0x106A11CE` to create eight deterministic mutations. At the
seed-derived fault step, it mutates one row but invalidates the unrelated peer.
That request schedules a description and does not trigger the advisory mutation
diagnostic, yet the retained row diverges from a fresh description. The test
checks the first failing prefix and deletes irrelevant actions until the minimal
reproduction contains only the wrong-region mutation.

The diagnostic text includes the seed, minimal action sequence, first divergence,
keyed path, changed domain, invalidation scope, and advisory-diagnostic count.
The same seeded mutations with a correct parent invalidation must match a fresh
runtime after every step and settle with no description, layout, or presentation
work pending.

This demonstrates a case ordinary advisory diagnostics cannot prove: a caller
can request work while invalidating a valid but unrelated region. The fresh
runtime comparison detects stale output without claiming that Alicorn can infer
which application-owned value changed.

## Bounds and current limits

The generated case count is fixed at one seed and eight actions over three rows;
prefix replay and action deletion are bounded by that short sequence. The fixture
is covered by the ordinary `odin test runtime` suite. It does not yet fuzz or
cover the full issue corpus, including virtualized-range changes, text selection
and composition mutation sequences, delayed corrective descriptions, DPI/theme
transitions, or broad insertion/removal action generation. Those remain possible
follow-ups only if the current oracle's signal justifies the extra test surface.

## Reproduction

From the repository root, run:

```powershell
odin test runtime
```

The repository-wide Windows suite is available with:

```powershell
.\tools\test.ps1 -Odin 'C:\path\to\odin.exe'
```

## Verification

The local Windows repository suite passed with Odin
`C:\Users\saman\Documents\odin\dist\odin.exe`: 308 runtime tests, 39 UI
tests, 35 theme tests, 168 native SDL tests, 8 AccessKit ABI tests, and 6 scroll
capture tests, plus the foundation, restoration, accessibility-contract, and
text-input smoke checks. `odin test runtime` passed independently as well.

This report records fixture scope, not a claim that every client invalidation
pattern is verified. Consumer-specific tests remain necessary for application
state and layouts not represented by the fixture.
