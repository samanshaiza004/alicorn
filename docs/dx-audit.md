# Alicorn DX audit

Audit date: 2026-09-22.

This audit started from the current default-branch baselines (`origin/master`)
of Alicorn, Alicorn History, and Alicorn Monitor. The local checkouts also have
one unmerged native-dialog/scroll feature commit; that commit was inspected as
context but was not treated as baseline evidence. The baseline foundation,
History, and Monitor self-tests all pass.

## What repeats in real applications

### 1. Retained scrolling and virtualization — highest leverage

History assembles three independently scrolling collections: commits, changed
files, and patch lines. Each repeats the same composition:

1. begin a retained scroll region;
2. calculate content dimensions;
3. copy viewport and offset products into application fields;
4. call `virtual_list_metrics`;
5. emit a clipped `.Virtual_List` container with residual offsets;
6. iterate the visible range and add logical keys;
7. close the container and scroll region.

Monitor repeats the same mechanism for its process table. In the audited History
view this is three `scroll_region_begin` calls and three metric calls, plus two
more metric calculations in selection/navigation code. History carries roughly
twelve scroll, viewport, and scroll-node fields to bridge this seam.

This is Alicorn mechanism leaking into ordinary application code. The runtime
already owns retained offsets and wheel routing, but the application still has
to synchronize the same viewport geometry into a second virtualization model.
The high-level improvement should compose those two existing capabilities while
leaving the low-level APIs available.

### 2. Positional layout styles — frequent, low-risk ceremony

The audited History view contains about 35 `Layout_Style` literals; Monitor's
main view contains about 42. Most repeat the same min/max constraints,
alignment, and clipping defaults while changing only direction, dimensions,
padding, gap, or grow. The 12-field positional literal makes a row or panel's
intent visually difficult to find.

`DEFAULT_STYLE` already contains the right defaults. The missing affordance is a
small Odin-native way to override a few named values without reconstructing the
whole positional structure. A default-producing helper is preferable to a CSS
layer, a token system, or a fluent builder.

### 3. Latest-wins background results — real but not yet core-worthy

History has three independent request/result domains, each with generation
counters, bounded channels, stale-result checks, ownership transfer, cleanup,
and explicit wakeup. This is repetitive, but it is also tied to Git payload
lifetimes and three different domain state machines. Monitor samples on its
host tick and does not repeat this pattern.

The reusable host-facing piece (`application_wake`) already exists and preserves
true idle. There is not yet a second independent consumer that justifies an
Alicorn async or latest-result abstraction. This pass therefore keeps the
worker and latest-wins lanes in History.

### 4. Identity, filtering, and loading state — mostly justified application code

History's selected commit, filtered visible index, asynchronous detail state,
and loading/error/empty branches represent real domain state. Removing them
would hide ownership rather than remove framework ceremony. Stable commit keys
are correct; position keys in changed-file and patch rows are a correctness
risk if those collections can reorder, so migration should use logical file and
line keys where the domain provides them.

## Ranking

| Candidate | Frequency | App reduction | New runtime complexity | Decision |
| --- | ---: | ---: | ---: | --- |
| Integrated retained fixed-row list | High | High | Low | Implement |
| Defaulted/named layout-style helper | High | Medium | Very low | Implement |
| Generic async/latest-wins lane | Low across apps | Medium in History | Medium | Keep app-local |
| Generic loading/error/empty widgets | Medium | Low | Medium | Reject |
| Automatic identity or dependency tracking | Broad | Unclear | Very high | Reject |
| New inspector subsystem | Low evidence | Unclear | Medium | Document existing diagnostics first |

The selected slice is deliberately small: style construction plus a coherent
retained fixed-row virtual-list path, with tests and progressive-disclosure
documentation. It expresses application intent without changing ownership,
invalidation, or idle behavior.

## Design constraints carried forward

- ordinary Odin application state remains application-owned;
- stable logical keys remain explicit;
- visible work remains proportional to the viewport/frontier, not item count;
- fractional scroll offsets and horizontal scroll remain supported;
- no callback or application pointer is retained by runtime nodes;
- the current low-level scroll, metric, region, and diagnostic APIs remain
  available;
- no hidden polling, reactive dependency tracking, or framework-owned workers.

