# Issue #157: retained-tree construction history

Research snapshot: 2026-11-03. Scope: tracked Alicorn documentation and local git
history at `fe8967f08fed8b29e7cd27d5989f52b7a85f405c`, compared with historical
`96461223cdbf43080acb957276c045ad704f4606` and audited runtime
`3d2c89e55ba3f34a2fb741926521f482ee57a17e`. The exact-head report and construction
probe were committed in `37f6322180d12a048c834a5c4ab35672cf0fc2e5`.

This sidecar ran no benchmarks, tests, or profiler and changed no production
code. All timings and sizes below are previously recorded results. Feature
boundaries come from `git show` / `git diff`; they are candidates for attribution,
not measured CPU hot paths. Existing untracked research files were left alone.

## Findings

The historical construction increase is established, including on both Windows
and macOS, but neither the responsible commit intervals nor CPU attribution are
established. The most useful specific source boundaries to test are retained
measurement/geometry (`ac0a420`), elastic flow allocation (`ec2e081`), and
axis-aware invalidation with additional formatted traces (`3d10863`). Earlier
paint, style, and semantic changes also change the work and record contracts.
This prioritization reflects construction-reachable source changes, not measured
dominance. The separate retained-region locality regression is already fixed.
Sources and bounded bisection intervals follow.

## Recorded construction evidence and limits

| Evidence | What the existing record supports |
| --- | --- |
| Windows matched historical comparison, three alternating processes per revision/profile | At `d8b011a`, initial 10k-tree medians were 52.852 / 129.312 / 132.902 ms for `9646122` / `3e31c74` / candidate in default, and 30.001 / 57.435 / 58.969 ms with `-o:speed`. The substantial increase predates the locality repair. [Report at `37f6322`, L11–48][windows-history] |
| macOS matched historical comparison | The rebased locality candidate `f5e7888` recorded default initial medians 58.593 / 149.522 / 152.636 ms, and optimized 25.093 / 60.781 / 58.110 ms. Three alternating processes per revision/profile; M1, macOS 27.2, September compiler. [Report at `37f6322`, L72–105][mac-history] |
| Exact audited runtime `3d2c89e`, Windows full-suite snapshot | 129.3623 ms initial total: description 17.0804 ms and `end_frame` 112.2817 ms; 130,183 allocator calls, 111,649,298 cumulative requested bytes; 10,000 measure executions, 20,001 layout visits, 10,001 finalized display commands. This is one sample, not a median or CPU profile. [Raw capture at `37f6322`, L19–21][exact-raw] |
| Five-process default construction probes at audited source | Container / short-text / wrapped-text total medians 113.730 / 133.350 / 146.942 ms. Containers execute no leaf measurement and compose only the root. Much cost therefore exists without leaf text measurement, but the remaining components are not individually timed. [Report at `37f6322`, L118–143][probe-report] |
| Pending-array reserve experiment | Short text: 133.350 ms unreserved versus 133.585 ms reserved, overlapping ranges. Cumulative requested bytes fall 25.8%, requested-live high-water falls 8.12 MB. This supports an allocation-volume reduction, not a CPU benefit or an unconditional runtime reserve. [Same report, L134–143][probe-report] |
| Allocation attribution | Runtime init: 11 calls / 40,188 B; description: 46 / 55,310,156 B; `end_frame`: 130,137 / 56,339,142 B. Biggest byte sites include pending growth, 10,001 Nodes, and 10,000 first paint-array allocations. The instrumentation adds overhead and its counters do not establish CPU cost. [Raw at `37f6322`, L1–27][allocations] |

Two fixture limitations matter for the next loop:

- The diagnostic probes report `semantic_descriptions=0`, `semantic_resolved=0`,
  and `shape_requests=0`, including the wrapped-text mode. Ten thousand measure
  executions do not mean ten thousand font-shaping calls. The fixture imports
  only the runtime and never loads fonts; `prepare_text_run_node` returns when
  the role has no loaded font. These results cannot attribute native shaping,
  AccessKit, or actual semantic publication cost. [Raw L5–39][probe-raw],
  [probe at `37f6322`, L60–82, L98–131][probe-source],
  [`3d2c89e:runtime/text.odin`, L1149–1174][font-guard]
- Fresh executable processes in the old comparisons are not isolated first-tree
  processes. The locality driver calls `measure_regions`, then `measure_tree`,
  then a separate phase probe. The ordinary full suite also constructs an idle
  tree and smaller trees before the timed 10k case. Both timed cases exclude
  `new_runtime` initialization. Use the new matched construction-only entrypoint
  to resolve that distinction. [`3d2c89e:tools/bench_retained_locality.py`,
  L52–90, L117–140][old-driver], [`benchmarks/main.odin`, L364–375][old-timing],
  [L588–607][old-main]

Keep the Windows and Mac observations, the two optimization profiles, and
single-suite snapshots versus process medians separate. In particular, the
later five-sample `9f4a985` versus `3d2c89e` table is not a five-sample historical
`9646122` versus current-head A/B. `9f4a985` already contains description-hash
reuse; that table cannot isolate the introduction of that optimization.
[Report at `37f6322`, L18–40][near-head], [hash-reuse diff][hash-diff]

## Feature and commit map

All rows below describe source evidence. Their latency contributions remain
hypotheses until a matched construction-only comparison or profile measures them.

| Commit / feature | Construction-relevant source change | Applicability to the flat fixture |
| --- | --- | --- |
| `0d63037`, scoped text-scale environment; later `323bea8`, theme/density environment | Adds inherited environment fields, environment comparisons and typography invalidation to node copying, and scoped layout roots. [`0d63037:runtime/reconcile.odin`, L248–304][environment] | Common copying/hash paths change even when the fixture does not opt into scoped styling. This is earlier than the retained computed-style cache. |
| `175611e`, renderer-neutral paint commands (#57) | Replaces `Display_Command` with a payload union, owner, opacity, translation, and generation-checked resource handles. Paint no longer owns a separate copied text string per command. [`runtime/paint_types.odin`, L1–19][paint-types], [`runtime/reconcile.odin`, L519–524, L600–608][paint-node], [diff][paint-diff] | Changes command storage and ownership. It both adds capability and removes old string ownership; larger command size alone cannot establish a slowdown. |
| `6f4e34f`, semantic surfaces/style generations; `900b88e`, retained computed styles; `f20f844`, visual parts | Adds inline pending surface/visual-part inputs and per-node style-generation work. `900b88e` moves computed recipe values out of Node into runtime map storage and adds per-family cache validation. [`6f4e34f:runtime/runtime.odin`, L824–829][surface-pending], [`f20f844:runtime/runtime.odin`, L919–925][visual-pending], [`900b88e:runtime/style_resolution.odin`, L84–145][computed-style] | Recipe-cache population is conditional on control/surface use. Generic description copying still performs style/surface comparisons and map maintenance; do not attribute the short-text fixture to button-recipe resolution. [`3d2c89e:runtime/reconcile.odin`, L415–445, L510–525][style-copy] |
| `22b3ef2`, semantic accessibility core; `80ae4ba`, accessibility appearance; `61641eb`, semantic text runs | Adds `Semantic_Descriptor` to every pending entry, semantic defaults and synchronization during description copying, bounds/order synchronization, and publication. Text-run byte-length slices and text-selection data later enlarge the descriptor. [`22b3ef2:runtime/reconcile.odin`, L411–415, L814–824][semantic-integration], [`61641eb:runtime/semantics.odin`, L80–124][semantic-text] | Ordinary low-level text/container descriptions have no semantic role. The audited path returns early for `.None`, and commit returns early with no pending semantic changes. Descriptor footprint and generic checks remain; entity publication is not exercised by the existing probes. [`3d2c89e:runtime/semantics.odin`, L815–838, L1180–1187][semantic-guards] |
| `ac0a420`, retained leaf measurement and geometry finalization | Every new node gains a `Measure_State` entry/input hash. Reconciliation switches from `prepare_text_runs` to retained measurement; parent layout supplies leaf constraints. Adds finalized geometry storage and unsnapped `display_target` followed by a snapped display pass. [`runtime/reconcile.odin`, L759–774, L910–918][measurement-integration], [`runtime/layout_measure.odin`, L354–388][geometry] | New work is reachable on first construction, including containers' retained state/geometry. Text preparation already existed at the historical baseline: this commit introduces a retained measurement contract, not text processing from scratch. [`9646122:runtime/reconcile.odin`, L705–707][baseline-stages] |
| `8520419` through `ec2e081`, elastic Row/Column allocation | Integrates fixed-point allocation, compression, distribution, baseline and direction policies. By `ec2e081`, ordinary flow layout allocates `main_sizes` and calls `resolve_main_sizes` for all children rather than only the old grow path. [`ec2e081:runtime/layout.odin`, L723–747][elastic-call]; audited scratch arrays at [`3d2c89e:runtime/layout.odin`, L269–309][elastic-arrays] | Applies to a plain flat Column too. The allocator call and scratch storage are concrete differences; their CPU fraction is unmeasured. |
| `5f7d2a9`, Grid; `e3f5ece` / `5927f09`, adaptive layout; later content-height and text-field geometry | Grid adds track slices to Pending and retained track/item fields to Node. Audited Node also includes adaptive selection/environment fields. [`5f7d2a9:runtime/runtime.odin`, L1109–1155][grid-records], [`3d2c89e:runtime/runtime.odin`, L1266–1289][adaptive-records] | Grid/adaptive behavior needs an opted-in tree. Their generic record/copying footprint can still affect an ordinary fixture. Do not treat all feature-specific solvers as executed. |
| `3d10863`, theme/layout/asset contracts | Makes boundaries axis-aware. Adds formatted trace reasons at the start of `mark_layout_ancestors` and when propagating to an ancestor; every newly retained node calls that function. [`runtime/reconcile.odin`, L646–686][axis-traces], audited creation at [`3d2c89e:runtime/reconcile.odin`, L850–880][creation] | A specific additional diagnostic path reachable per new node, independently of leaf shaping or semantic publication. Compare its parent with this commit; formatting/string-copy CPU is not measured in the old report. |
| `dcec257`, typed measurement dependencies | Refines dependency hashing/reason reporting; removes unused locale/direction generations from the measure dependency record. [`runtime/layout_measure.odin`, L108–120, L303–320][typed-measure], [`runtime/runtime.odin`, L315–329][typed-record] | Changes the measure-key contract but is not the introduction of retained measurement. No isolated construction result is recorded. |
| `1902add`, redundant semantic scans | Adds an early collection-pruning guard. Earlier semantic-focus changes also avoid clearing every node when no focus is realized. [`runtime/semantics.odin`, L1352–1361][semantic-prune]; [October 27 report at `37f6322`, L36–54][semantic-scan-report] | Existing work reduction; the report's timing comparisons cover updates, not an isolated initial-construction improvement. |
| `cc88bfd`, locality repair (#156), then `b545531` | Introduces a deduplicated measurement queue and single-command finalization; `b545531` keeps first-time nodes out of that queue until prior constraints exist and avoids redundant diagnostic-reason replacement on unchanged nodes. [Locality diff][locality-diff], [`b545531:runtime/layout_measure.odin`, L6–20][queue-guard], [`runtime/reconcile.odin`, L308–324][dirty-reason] | Initial construction still does its required first measures and a full display build. Preserved-region locality is an existing invariant to retain, not an unfinished construction fix. |
| `9f4a985`, hash reuse; `0ebff43`, resolved environment reuse | Reuses the already-computed description hash for paint checks and passes resolved environment/domain changes into node copying. [Hash diff][hash-diff], [environment diff][resolved-env-diff] | Removes redundant source operations. The saved near-head timings overlap and do not demonstrate a separate construction benefit. [Recorded comparison][near-head] |

### Retained strings and diagnostics

Owned strings and trace ownership are not new since `9646122`. The baseline
already copies source-site strings, keys, labels/text, identity strings, dirty
reasons, and reconciliation trace reasons. It also already provides
`record_trace_literal`. The ordinary trace routine clones its reason; the literal
routine borrows process-lifetime text, with both respecting eviction ownership.
[`9646122:runtime/reconcile.odin`, L195–220, L241–261, L556–575][baseline-owned],
[`9646122:runtime/runtime_state.odin`, L9–39][baseline-trace],
[`3d2c89e:runtime/runtime_state.odin`, L9–39][audited-trace]

Changes that can add construction diagnostic work are more specific: the
measurement cache-miss formatting introduced in `ac0a420` and the axis-propagation
formatting introduced in `3d10863`. Both use ordinary owned trace recording.
[`ac0a420:runtime/layout_measure.odin`, L210–250][measure-trace], [axis traces][axis-traces]
The allocation report aggregates 70,009 calls at `owned_with_allocator` and
40,004 at `owned`; it does not split those helpers' CPU time or all callers.
[Raw at `37f6322`, L14–19][allocations]

`7b9a1ad` application-mutation diagnostics are explicitly scoped/compile-time
guarded; they are not evidence of per-node mutation-scope creation in this
fixture. [`runtime/application_mutation_diagnostics.odin`, L16–43][mutation]
The `b545531` unchanged-root allocation improvement is deterministic, but its
saved timing A/B spans `3e31c74` to `b545531`, including the locality repair.
It is not an isolated CPU A/B of dirty-reason replacement or of construction.
[Report at `37f6322`, L42–78][dirty-report]

### Record sizes

The same September compiler measured these sizes; no intermediate-commit or
`fe8967f` sizes were measured by this sidecar.

| Record | `9646122` | `3d2c89e` | Recorded delta |
| --- | ---: | ---: | ---: |
| Pending_Item | 720 B | 1,272 B | +552 B |
| Description | 704 B | 768 B | +64 B |
| Node | 1,792 B | 2,048 B | +256 B |

Source: [`37f6322:docs/benchmarks/raw/performance-audit-windows-2026-10-28-type-sizes.txt`,
L1–17][sizes]. `Display_Command` 96 B versus `Paint_Command` 128 B is a change
of contract, not a like-for-like representation comparison.

The baseline Pending contains only kind, Description and subtree; audited Pending
also carries semantic-surface style, visual-part style, semantic descriptor,
accessibility preferences and Grid inputs inline. The introduction commits in
the feature table explain structural growth even when those capabilities are
unused. They do not assign measured byte or latency deltas to each commit.
[`9646122:runtime/runtime.odin`, L559–563][baseline-pending],
[`3d2c89e:runtime/runtime.odin`, L1236–1247][audited-pending]
Conversely, `900b88e` removes the inline computed-style payload from Node.
[Diff][computed-diff] Net record growth does not mean every intermediate feature
only enlarged Node, or justify pooling/SoA without CPU evidence.

## Construction-only bisection candidates

These are endpoint pairs to compare, then subdivide only intervals with a
repeatable construction difference. They are not good/bad classifications.
Use the identical deterministic tree, timer boundaries, compiler, allocation
instrumentation policy, and process entrypoint throughout; run default and
`-o:speed` independently. Prefer the main agent's new construction loop over
using region-reuse latency as the bisection predicate.

| Interval | Why it is a useful boundary; first narrow pairs if a jump appears |
| --- | --- |
| `9646122..175611e` | Scoped environment, early theme/recipe work, renderer-neutral paint. Isolate `0d63037^..0d63037` and `175611e^..175611e`. |
| `175611e..927e74a` | Retained style/surface/visual-part inputs, semantics/appearance, semantic text runs. Isolate `900b88e^..900b88e`, `22b3ef2^..22b3ef2`, `61641eb^..61641eb`. |
| `927e74a..ac0a420` | Direct parent/child pair for retained measurement, geometry side storage and display finalization. A high-information first pair because several construction stages change together. |
| `ac0a420..0d86719` | Elastic flow, content sizing, Grid and adaptive layout integration. Split first at `28250e7..ec2e081` (direct pair for completed elastic flow), then Grid/adaptive changes if needed. |
| `0d86719..3e31c74` | Layout/asset contracts, typed measurement, text/restore/input capabilities and later semantic fixes. Check `7e85689..3d10863` directly for axis-aware propagation/traces; `f223bab..dcec257` for typed measurement. Both are verified parent/child pairs. |
| `3e31c74..3d2c89e` | Locality repair and small audit optimizations. Direct checks: `f2d6678..cc88bfd`, `b545531^..b545531`, `9f4a985^..9f4a985`, `0ebff43^..0ebff43`. Saved results already show no restoration of historical construction time, but do not assign its cause. |
| `3d2c89e..fe8967f` | Separate audit-to-current interval; do not silently treat audited runtime as HEAD. Typed control metrics/percentage sizing, motion, scroll-focus presentation, text selection and the compiler migration occur here. |

The feature-table citations identify the changes behind these boundaries. Use
topology/ancestry, rather than dates alone, when subdividing merged branches;
record exact tested SHAs and skip source-incompatible snapshots explicitly.

For the final interval, `075e517` retains percentage dependencies in a sparse
sidecar; `9690333` adds post-reconcile motion-intent application; `0349be5` adds
scroll-focus policy; `1fde82b` adopts November Odin and copies submitted nonempty
text spans into frame scratch. Percentage/motion paths have early empty-state
guards, so feature existence alone does not prove significant flat-tree cost.
[`fe8967f:runtime/percent_width.odin`, L103–105][percent-guard],
[`runtime/motion_retained.odin`, L541–558][motion-guard],
[`runtime/reconcile.odin`, L934–947, L1051–1062][head-stages],
[`1fde82b:runtime/layout_widgets.odin`, L523–561][span-copy]
Do not mix the compiler transition into a source-only performance attribution:
the November migration record makes no compiler performance claim.
[`1fde82b:docs/validation/odin-dev-2026-11.md`, L7–13, L39–65][compiler]

## Issue #157 criteria: supported versus missing

The [open issue's goals and checklist][issue] require understanding/acceptance,
not a rewrite or mandatory return to historical latency. The status below is
the state of existing evidence, not certification of the main agent's new work.

| Requirement | Already supported | Still missing |
| --- | --- | --- |
| Reproducible same-workload historical/current A/B | Pinned September compiler, raw historical/current comparisons on Windows and M1, reproducible fixtures. | At least five alternating isolated construction processes per revision/profile for `9646122` versus current HEAD; controlled host/compiler metadata and distributions for that exact comparison. Existing historical comparisons use three processes, later five-sample comparisons use near-head revisions. [Windows method][windows-history], [near-head method][near-head] |
| CPU attribution by construction phase | Description versus `end_frame` wall timing; allocator phase/site attribution. | CPU sampling or low-overhead subdivisions inside `end_frame`: creation/copying, strings/trace, semantic publication, measurement, layout, style, paint and finalization. Separate profiling/instrumentation runs from latency runs. [Audit L65–101][audit-core] |
| Identify historical commits/features | Source boundaries mapped above. | Measured construction bisection and a decision separating necessary capability cost from avoidable work; no source boundary here is a proven latency jump. |
| Memory/workload characterization | Container/short/wrapped fixtures; calls, requested bytes and requested-live high-water; record sizes and a reserve counterexample. | Peak process RSS/working set separately; representative realistic UI including real semantic/font work; current-head figures. [Probe results][probe-report] |
| Measured low-risk improvements | Existing locality/queue guards and unchanged-root reason reduction; reserve is documented as no demonstrated CPU win. | Isolated construction CPU/allocation benefit for any #157 candidate, then deliberate accepted tradeoffs. Hash/environment deduplication alone has no demonstrated latency benefit in the saved comparison. [Dirty report][dirty-report], [near-head comparison][near-head] |
| Correctness/locality | Prior runtime suite: 266 tests; deterministic retained-region tests, DPI/finalization fallbacks; idle and bounded virtualization evidence. | Candidate-specific runtime/accessibility/layout/disposal checks and native checks after implementation; historical passes do not validate a future change. [Audit L149–198][validation], [locality contract L1–7][locality-contract] |
| Representative native Scratchpad startup | Launch/publication and package smoke evidence exists. | First presentation, startup responsiveness and process high-water across startup/open/close/settings; distinguish runtime CPU from app/backend and SDL/GPU. Details below. |
| Publish results / budget | Existing historical audits and raw captures are preserved. | Accepted #157 results/tradeoffs in `docs/benchmarks/`; a latency CI budget only after representative workload/tolerance evidence. The current locality driver's failure threshold checks region reuse, not construction. [`3d2c89e:tools/bench_retained_locality.py`, L170–190][old-driver] |

## Existing native startup evidence

No quantified native Scratchpad startup or process high-water series was found
in the tracked Alicorn docs at `fe8967f`. This is a repository-scope finding;
it does not assert that no measurements exist in Scratchpad's repository or
maintainers' local output. The October audit explicitly leaves Scratchpad
startup/high-water unmeasured. [Report at `37f6322`, L194–213][audit-limits]

| Existing record | Measurements or observations | What it does not establish |
| --- | --- | --- |
| Native hello, macOS, Oct 2; runtime `f35c2a0`, M1, Metal | Two launches: GPU driver selected at 1.049 / 0.228 s; post-submit first-frame diagnostics log at 1.730 / 0.668 s. Idle RSS was separately sampled at 5.066 / 20.006 s: 89,520 / 84,016 KiB. [`fe8967f:docs/benchmarks/native-hello-macos.md`, L3–10, L61–92][hello-mac] | Scratchpad startup, first visible pixel, controlled cold start, median startup, or process high-water. Diagnostics marker includes serialization/output. |
| Native hello, Windows, Oct 3; Alicorn `7c5e812`, D3D12 | Launch to post-submit diagnostics marker 0.416 / 0.379 / 0.363 s; median 0.379 s. Separate bounded idle working-set/private-byte samples exist. [`fe8967f:docs/benchmarks/native-dogfood-windows.md`, L17–25, L56–80][hello-windows] | Scratchpad, cold-start distribution or first-visible/interactive latency. Other apps in this report are Monitor, History and Scope, each with a separate Alicorn pin. [L82–104][dogfood-windows] |
| Scratchpad macOS sync/package, Oct 20 | Scratchpad `eae8c9b`; native smoke shows publication rendered, wake observed, ordered shutdown, one Metal submission/retirement; package/extracted launch passed. [`fe8967f:docs/archive/validation/macos-sync-2026-10-20.md`, L12–13, L55–65][scratchpad-mac] | No launch-to-presentation time, responsiveness distribution or RSS/high-water is reported. |
| Scratchpad SDL 3.4.18 package validation | arm64 package, signature/link audit and extracted-app launch smoke passed. [`fe8967f:docs/archive/validation/sdl-3.4.18.md`, L46–70][scratchpad-package] | Package/app disk sizes are not runtime memory or startup timings. |
| Scratchpad Windows stabilization, Oct 23 | Native tests/build and three D3D12 appearance smokes: publication/wake/shutdown passed. [`fe8967f:docs/archive/validation/release-stabilization-2026-10-23.md`, L28–39][scratchpad-windows] | No quantified startup, real interaction sequence, or high-water series. |

## Source links

Each code link pins the SHA named in its label/text; line anchors refer to that
snapshot, not the moving working tree. Commit links refer to the corresponding
primary git diff.

[issue]: https://github.com/samanshaiza004/alicorn/issues/157
[windows-history]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-locality-windows-2026-10-28.md#L11-L48
[mac-history]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/retained-locality.md#L72-L105
[exact-raw]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/raw/performance-audit-windows-2026-10-28-master-3d2c89e.txt#L19-L21
[probe-report]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-28.md#L118-L143
[allocations]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/raw/performance-audit-windows-2026-10-28-allocation-sites.txt#L1-L27
[probe-raw]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/raw/performance-audit-windows-2026-10-28-construction-probes.txt#L5-L39
[probe-source]: https://github.com/samanshaiza004/alicorn/blob/37f6322/benchmarks/diagnostics/perf_construction_probe.odin#L60-L131
[font-guard]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/text.odin#L1149-L1174
[old-driver]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/tools/bench_retained_locality.py#L52-L190
[old-timing]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/benchmarks/main.odin#L364-L375
[old-main]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/benchmarks/main.odin#L588-L607
[near-head]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-28.md#L18-L40
[environment]: https://github.com/samanshaiza004/alicorn/blob/0d63037/runtime/reconcile.odin#L248-L304
[paint-types]: https://github.com/samanshaiza004/alicorn/blob/175611e/runtime/paint_types.odin#L1-L19
[paint-node]: https://github.com/samanshaiza004/alicorn/blob/175611e/runtime/reconcile.odin#L519-L608
[paint-diff]: https://github.com/samanshaiza004/alicorn/commit/175611e
[surface-pending]: https://github.com/samanshaiza004/alicorn/blob/6f4e34f/runtime/runtime.odin#L824-L829
[visual-pending]: https://github.com/samanshaiza004/alicorn/blob/f20f844/runtime/runtime.odin#L919-L925
[computed-style]: https://github.com/samanshaiza004/alicorn/blob/900b88e/runtime/style_resolution.odin#L84-L145
[style-copy]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/reconcile.odin#L415-L525
[semantic-integration]: https://github.com/samanshaiza004/alicorn/blob/22b3ef2/runtime/reconcile.odin#L411-L824
[semantic-text]: https://github.com/samanshaiza004/alicorn/blob/61641eb/runtime/semantics.odin#L80-L124
[semantic-guards]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/semantics.odin#L815-L1187
[measurement-integration]: https://github.com/samanshaiza004/alicorn/blob/ac0a420/runtime/reconcile.odin#L759-L918
[geometry]: https://github.com/samanshaiza004/alicorn/blob/ac0a420/runtime/layout_measure.odin#L354-L388
[baseline-stages]: https://github.com/samanshaiza004/alicorn/blob/9646122/runtime/reconcile.odin#L705-L707
[elastic-call]: https://github.com/samanshaiza004/alicorn/blob/ec2e081/runtime/layout.odin#L723-L747
[elastic-arrays]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/layout.odin#L269-L309
[grid-records]: https://github.com/samanshaiza004/alicorn/blob/5f7d2a9/runtime/runtime.odin#L1109-L1155
[adaptive-records]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/runtime.odin#L1266-L1289
[axis-traces]: https://github.com/samanshaiza004/alicorn/blob/3d10863/runtime/reconcile.odin#L646-L686
[creation]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/reconcile.odin#L850-L880
[typed-measure]: https://github.com/samanshaiza004/alicorn/blob/dcec257/runtime/layout_measure.odin#L108-L320
[typed-record]: https://github.com/samanshaiza004/alicorn/blob/dcec257/runtime/runtime.odin#L315-L329
[semantic-prune]: https://github.com/samanshaiza004/alicorn/blob/1902add/runtime/semantics.odin#L1352-L1361
[semantic-scan-report]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-27.md#L36-L54
[locality-diff]: https://github.com/samanshaiza004/alicorn/commit/cc88bfd
[queue-guard]: https://github.com/samanshaiza004/alicorn/blob/b545531/runtime/layout_measure.odin#L6-L20
[dirty-reason]: https://github.com/samanshaiza004/alicorn/blob/b545531/runtime/reconcile.odin#L308-L324
[hash-diff]: https://github.com/samanshaiza004/alicorn/commit/9f4a985
[resolved-env-diff]: https://github.com/samanshaiza004/alicorn/commit/0ebff43
[baseline-owned]: https://github.com/samanshaiza004/alicorn/blob/9646122/runtime/reconcile.odin#L195-L575
[baseline-trace]: https://github.com/samanshaiza004/alicorn/blob/9646122/runtime/runtime_state.odin#L9-L39
[audited-trace]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/runtime_state.odin#L9-L39
[measure-trace]: https://github.com/samanshaiza004/alicorn/blob/ac0a420/runtime/layout_measure.odin#L210-L250
[mutation]: https://github.com/samanshaiza004/alicorn/blob/7b9a1ad/runtime/application_mutation_diagnostics.odin#L16-L43
[dirty-report]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-28.md#L42-L78
[sizes]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/raw/performance-audit-windows-2026-10-28-type-sizes.txt#L1-L17
[baseline-pending]: https://github.com/samanshaiza004/alicorn/blob/9646122/runtime/runtime.odin#L559-L563
[audited-pending]: https://github.com/samanshaiza004/alicorn/blob/3d2c89e/runtime/runtime.odin#L1236-L1247
[computed-diff]: https://github.com/samanshaiza004/alicorn/commit/900b88e
[percent-guard]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/percent_width.odin#L103-L105
[motion-guard]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/motion_retained.odin#L541-L558
[head-stages]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/reconcile.odin#L934-L1062
[span-copy]: https://github.com/samanshaiza004/alicorn/blob/1fde82b/runtime/layout_widgets.odin#L523-L561
[compiler]: https://github.com/samanshaiza004/alicorn/blob/1fde82b/docs/validation/odin-dev-2026-11.md#L7-L65
[audit-core]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-28.md#L65-L101
[validation]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-28.md#L149-L198
[locality-contract]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/retained-locality.md#L1-L7
[audit-limits]: https://github.com/samanshaiza004/alicorn/blob/37f6322/docs/benchmarks/performance-audit-windows-2026-10-28.md#L194-L213
[hello-mac]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/docs/benchmarks/native-hello-macos.md#L3-L92
[hello-windows]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/docs/benchmarks/native-dogfood-windows.md#L17-L80
[dogfood-windows]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/docs/benchmarks/native-dogfood-windows.md#L82-L104
[scratchpad-mac]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/docs/archive/validation/macos-sync-2026-10-20.md#L12-L65
[scratchpad-package]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/docs/archive/validation/sdl-3.4.18.md#L46-L70
[scratchpad-windows]: https://github.com/samanshaiza004/alicorn/blob/fe8967f/docs/archive/validation/release-stabilization-2026-10-23.md#L28-L39
