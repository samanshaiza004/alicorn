# Real History projection experiment

Headless #50 research. This package has no Alicorn, SDL, window, or History application dependency. No production code imports it. It establishes real patch semantics before general tree mutation work.

```powershell
odin run experimental/history_patch_projection -thread-count:1
./experimental/history_patch_projection/capture.ps1
./experimental/history_patch_projection/verify_provenance.ps1 -HistoryRoot C:/path/to/alicorn-history
```

The correctness run uses seven fixtures. The capture builds once with `-o:speed -thread-count:1`, runs five sequential fresh processes, verifies equal backend checksums, and saves source hashes and raw measurements. It opens no native application and performs no GPU work. The 256-repeat scale case is only enabled by `--bench`.

## Source provenance

`history_parser.odin` snapshots History's existing parser, patch model, expanded-display builder, and destroy routines from `samanshaiza004/alicorn-history` at `ce3276cf2fb425013df013bcb49e211ca234473a`. Those routines are unchanged. The extraction excludes unrelated models and Git subprocess/native application functions. The only shim is `git_owned_error`, implemented as `strings.clone` for the parser's error messages. The snapshot permits a headless proof using the actual parser without compiling History's native host. `verify_provenance.ps1` compares every extracted source region and real fixture with the pinned Git objects; it does not edit History.

| Checked-in fixture | Actual Git source |
| --- | --- |
| `history-toolbar.patch` | `ce3276cf2fb425013df013bcb49e211ca234473a`, `history_view.odin` |
| `history-scroll.patch` | `3a22f387ef4003da82eea53aa27657471c71a899`, `history_view.odin` |
| `history-parser.patch` | `6ca8c476a8ef6cfb9e29d363e31f323fe8929870`, `git_parse_patch.odin` |

`edge-cases.patch` is a hand-authored valid patch for zero-count insertion/deletion, different old/new origins, omitted source gaps, blank lines, and no-newline metadata. Empty, binary, and complete-file deletion fixtures are inline. The amplified fixture repeats the real scroll patch's hunk bodies with renumbered source origins and reparses them. It is not evidence of an observed large History interaction.

## Application-owned references

Every backend copies the same 16-byte `Span_Ref {kind, source, first, count}`. A line span names a hunk and a contiguous same-kind line range. Text and coordinates are read from the immutable parsed `File_Patch`; there is no separate table of full projection records. Metadata and headers refer directly to parsed storage. A gap names the following hunk, so its old/new extents can be derived from neighboring parsed origins. The source axes start at line one; a zero-count unified-diff start denotes the preceding line.

The application freezes a separate catalog of fold plans before index construction. Each plan owns its stable ID, source references, original spans, and cached exact integer measures. Fold references name catalog slots, never a shared mutable sentinel. Independent folds therefore coexist and can expand in any order. The indexes implement ordered geometry; they do not choose folding policy.

The application must keep the `Patch_Store`, parsed patch, and frozen fold catalog alive and immutable until **all** referencing indexes have been destroyed. Source epochs scope logical anchors to one immutable patch. Replacing a patch means destroying its indexes first and creating a new epoch; array positions are not durable document identities. This research driver enforces construction/destruction order and tests rejection of anchors from another epoch. The package does not expose a general ownership API.

Source seeking follows the selected old/new measure through cached subtrees while accumulating display rows. Headers and additions/deletions with zero extent on the selected side are skipped. An omitted line returns `Gap`, a hidden line returns its own fold placeholder, and a coordinate outside the represented file extent returns `Missing`. Hunk seeking uses the header measure. Meta-line anchors start at their own hunk, since those records have zero old/new extent.

## Competing indexes

All backends use 32-reference leaves and identical adapter policies:

- `Block_Prefix`: flat prefix directory; local edits rebuild the affected suffix.
- `Block_Hierarchy`: fixed leaves and a binary summary directory; edits update ancestors without balancing.
- `Measured_Tree`: bottom-up fanout-16 directory, matching the earlier B+ prototype's local-edit model.

These are fixed-topology indexes. Splices must stay within one existing leaf and fit its capacity. Fold plans honor that restriction. Neither hierarchical backend provides arbitrary insertion, cross-leaf folding, split/merge, or allocation-failure rollback. Rejected ranges, overcapacity, invalid references, repeated folds, aliased input, and no-allocation queries/local folds are tested. Only a committed local edit increments the revision.

The oracle starts with History's actual `Patch_Display_Line` values and independently folds the expanded rows. Tests compare every viewport's text, kind, old/new gutter numbers, hunk identity, source line index, and borrowed string address. They exhaustively compare both source axes, test all simultaneous folds and non-LIFO expansion, recompute every cached directory summary, and resolve every hunk-line selection/scroll anchor before and after folding. This verifies logical projection behavior; native input, shaping, painting, and History's actual scroll/selection state have not been integrated or exercised.

## Measurement limits

Timed work reconstructs actual 100-row viewport descriptors and performs a fold/unfold pair, two viewport reconstructions, and two source seeks, while another fold remains active. Exact row/string checksums run outside the timing interval and must match all backends. Near the end of a small patch, fewer than 100 rows exist; the trace is identical for every backend.

`mem.Tracking_Allocator` measures live and peak **requested heap bytes** for each index, including temporary directory construction arrays and reserved leaf capacity. It excludes allocator headers, tracker bookkeeping, process overhead, stack buffers, and the shared parsed data. Parsed payload capacities, fold catalog bytes, construction-seed capacity, and the existing expanded display index are reported separately. The scale case also tracks common parser/adapter preparation peak. The expanded display index is released after the oracle proof; it is not counted as necessary backing storage for either alternative. The shared seed can likewise be released after building a chosen index. Local folds and queries allocate nothing, so their peak equals settled index storage; these figures make no claim about future growing splices.

See [the report](../../docs/benchmarks/history-real-patch-projection.md) for results and the remaining integration gates.
