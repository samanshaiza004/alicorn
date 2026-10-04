package alicorn

import "core:testing"

TOOLTIP_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

tooltip_test_build :: proc(rt: ^Runtime) -> (source, neighbor: Node_ID) {
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(&ui, .Root, label="tooltip-test-root", key=key_string("root"), style=layout_style(.Column, gap=0))
	source, _ = button_ex(&ui, "Match case", key="tooltip-source", style=layout_style(width=120, height=32))
	_ = tooltip(&ui, "Match case", delay_ms=500)
	neighbor, _ = button_ex(&ui, "Neighbor", key="tooltip-neighbor", style=layout_style(width=120, height=32))
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_tooltip_hover_delay_presentation_and_true_idle :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 220, 120})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, TOOLTIP_TEST_FONT), "tooltip should use Alicorn's loaded UI text role")
	source, neighbor := tooltip_test_build(&rt)
	if source == 0 || neighbor == 0 { testing.expect(t, false, "tooltip test controls should be retained"); return }
	original_focus := rt.focused
	point := Rect{rt.nodes[source].bounds.x+10, rt.nodes[source].bounds.y+10, 0, 0}
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=point.x, y=point.y, timestamp_ns=1_000_000})
	testing.expect(t, rt.tooltip.target == source && rt.tooltip.deadline_ns == 501_000_000,
		"hover should arm one delay from the host's monotonic timestamp")
	testing.expect(t, tooltip_next_deadline(&rt) == 501_000_000, "the native host should be able to wait until the one-shot deadline")
	testing.expect(t, !tooltip_advance(&rt, 500_999_999) && !rt.tooltip.visible,
		"the tooltip must remain hidden until its full delay elapses")
	testing.expect(t, tooltip_advance(&rt, 501_000_000) && rt.tooltip.visible,
		"the tooltip should become visible when the timer expires")
	testing.expect(t, rt.focused == original_focus, "showing a tooltip must not take keyboard focus")
	testing.expect(t, tooltip_next_deadline(&rt) == 0, "a visible tooltip must leave no recurring deadline armed")

	ui, ready := begin_presentation_frame(&rt)
	testing.expect(t, ready, "showing a tooltip should request one retained presentation")
	if ready { end_presentation_frame(&ui) }
	background_found := false
	background_bounds := Rect{}
	text_found := false
	for command in rt.display {
		if command.kind == .Tooltip_Background { background_found = true; background_bounds = command.bounds; break }
	}
	for command in rt.display { if command.kind == .Tooltip_Text && command.text == "Match case" { text_found = true } }
	testing.expect(t, background_found && text_found, "the top-level tooltip layer should retain a background and shaped label")
	if background_found {
		bounds := background_bounds
		testing.expect(t, bounds.x >= rt.viewport.x && bounds.y >= rt.viewport.y &&
			bounds.x+bounds.w <= rt.viewport.x+rt.viewport.w && bounds.y+bounds.h <= rt.viewport.y+rt.viewport.h,
			"tooltip bounds should remain clamped to the viewport")
		hit := hit_test(&rt, bounds.x+bounds.w/2, bounds.y+bounds.h/2)
		testing.expect(t, hit == neighbor, "tooltip presentation must be hit-test transparent so the underlying control remains reachable")
	}
	testing.expect(t, rt.focused == original_focus && !rt.invalidated && !presentation_needs_frame(&rt),
		"settling the shown tooltip must preserve focus and return presentation to idle")

	tooltip_dismiss(&rt)
	ui, ready = begin_presentation_frame(&rt)
	testing.expect(t, ready, "dismissing a visible tooltip should request one retained repaint")
	if ready { end_presentation_frame(&ui) }
	for command in rt.display { testing.expect(t, command.node != Node_ID(0), "dismissed tooltip commands must be removed before releasing their shaped text") }
	testing.expect(t, rt.tooltip.target == 0 && tooltip_next_deadline(&rt) == 0 &&
		!rt.invalidated && !presentation_needs_frame(&rt),
		"after dismissal Alicorn should return to true idle with no timer or whole-tree invalidation")
}

@(test)
test_tooltip_anchor_flips_and_clamps_to_viewport :: proc(t: ^testing.T) {
	viewport := Rect{10, 20, 200, 100}
	anchor := Rect{185, 108, 15, 10}
	placed := tooltip_placement(viewport, anchor, 90, 55)
	testing.expect(t, placed.x == 110 && placed.y == 53,
		"a tooltip near the lower-right edge should flip above and clamp horizontally")
	oversized := tooltip_placement(viewport, Rect{0, 20, 0, 0}, 400, 300)
	testing.expect(t, oversized.x >= viewport.x && oversized.y >= viewport.y &&
		oversized.x+oversized.w <= viewport.x+viewport.w && oversized.y+oversized.h <= viewport.y+viewport.h,
		"even oversized tooltip dimensions should be bounded by the viewport")
}

@(test)
test_tooltip_is_dismissed_by_pointer_exit_and_focus_change :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 220, 120})
	defer destroy_runtime(&rt)
	_ = text_engine_load_font(&rt.text_engine, TOOLTIP_TEST_FONT)
	source, neighbor := tooltip_test_build(&rt)
	if source == 0 || neighbor == 0 { testing.expect(t, false, "tooltip test controls should be retained"); return }
	source_bounds := rt.nodes[source].bounds
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=source_bounds.x+10, y=source_bounds.y+10, timestamp_ns=10})
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=rt.nodes[neighbor].bounds.x+10, y=rt.nodes[neighbor].bounds.y+10, timestamp_ns=20})
	testing.expect(t, rt.tooltip.target == 0 && tooltip_next_deadline(&rt) == 0,
		"leaving the annotated control should cancel its pending hover timer")
	_ = process_pointer(&rt, Pointer_Event{kind=.Move, x=source_bounds.x+10, y=source_bounds.y+10, timestamp_ns=30})
	testing.expect(t, rt.tooltip.target == source, "re-entering the control should arm a fresh timer")
	_ = focus(&rt, neighbor)
	testing.expect(t, rt.tooltip.target == 0 && tooltip_next_deadline(&rt) == 0,
		"keyboard focus movement should dismiss a pending tooltip")
}

@(test)
test_tooltip_zero_delay_with_synthetic_zero_timestamp_keeps_deadline_armed :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 220, 120})
	defer destroy_runtime(&rt)
	source, _ := tooltip_test_build(&rt)
	if source == 0 { testing.expect(t, false, "tooltip source should be retained"); return }
	rt.nodes[source].tooltip_delay_ms = 0
	tooltip_pointer_update(&rt, source, 0)
	testing.expect(t, tooltip_next_deadline(&rt) == 1,
		"zero is reserved as the no-deadline sentinel, so zero-time immediate tooltips must remain armed")
}
