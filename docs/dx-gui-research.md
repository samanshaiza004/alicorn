# GUI API comparison for Alicorn DX

This is a focused comparison of primary-source APIs relevant to the audit. The
goal is to borrow small interaction ideas, not to import another framework's
ownership model.

## Useful ideas

Dear ImGui's [`ImGuiListClipper`](https://github.com/ocornut/imgui/blob/master/imgui.h)
and child-window APIs compute a visible range while the application still emits
the visible items. That is the right shape for Alicorn's fixed-row fast path,
provided Alicorn keeps logical item keys and fractional offsets. ImGui's
[metrics/debug windows](https://github.com/ocornut/imgui/blob/master/imgui_demo.cpp)
also reinforce the value of an inspectable retained/runtime boundary.

egui's [`ScrollArea::show_rows`](https://github.com/emilk/egui/blob/master/crates/egui/src/containers/scroll_area.rs)
is the closest ergonomic precedent: row height and count go in, and only the
visible range is evaluated. Its explicit
[`request_repaint`](https://github.com/emilk/egui/blob/master/crates/egui/src/context.rs)
and delayed repaint callback are also a good precedent for a sleeping host.
Alicorn already has the corresponding explicit host waker, so this pass does
not add a scheduler or reactive repaint graph.

GPUI's [`uniform_list`](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/elements/uniform_list.rs)
and inspector show the benefit of a visible-range list plus source-aware
diagnostics. GPUI's entity graph, observable context, and executor are not a
fit: they would add ownership and lifecycle concepts Alicorn explicitly avoids.

Xilem/Masonry's
[`VirtualScroll`](https://github.com/linebender/xilem/blob/main/masonry/src/widgets/virtual_scroll.rs)
confirms that virtualization quickly grows policy around active children,
focus, and variable extents. Alicorn should keep the simpler fixed-row path and
leave application state outside recycled/realized rows.

Flutter's [`ListView.builder`](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/scroll_view.dart)
and constraint model show the usefulness of a builder/visible-range boundary
and parent-owned geometry. The Widget/Element/RenderObject lifecycle and
mandatory `setState` model are not being adopted.

Slint's [ListView](https://github.com/slint-ui/slint/blob/master/docs/astro/src/content/docs/reference/std-widgets/views/listview.mdx)
and Qt Quick's [ListView](https://doc.qt.io/qt-6/qml-qtquick-listview.html)
both make the same important point: virtualized delegates are transient, so
durable selection and domain state must not live in a delegate instance. Their
model/property-binding graphs, pooling semantics, and event-loop ownership are
larger than Alicorn needs.

Qt Quick Layouts' warning against having both the layout and children control
geometry is directly applicable. Alicorn should keep one authoritative resolved
viewport/clip product. The new list API composes with the existing layout and
retained scroll node instead of reconstructing viewport geometry in the app.

## Decisions for this pass

| Idea | Application ceremony removed | Hidden cost | Alicorn decision |
| --- | --- | --- | --- |
| Visible-range fixed-row list | viewport math, content extent, fractional offset plumbing | uniform-row assumption | Adopt as `virtual_list_begin/end`; keep low-level APIs |
| Defaulted layout construction | repeated min/max/alignment fields | helper proliferation | Adopt one named constructor, not a style DSL |
| Repaint/wake callback | host-specific wake plumbing | scheduler ownership if expanded | Existing `application_wake` is sufficient for now |
| Automatic model/property dependencies | explicit invalidation | hidden ownership and idle work | Reject |
| Recycled delegate-owned state | convenient row-local state | incorrect state transfer | Reject; keep app-owned state and explicit keys |
| Full inspector/debug object tree | ad-hoc diagnosis | public snapshot/ownership surface | Defer; document existing inspect/trace products |

The common thread is explicit intent with runtime-owned products: layout may
become smarter, but ordinary Odin code should not need to learn a new ownership
model.

