package alicorn

import "core:testing"

text_span_lifetime_describe_local :: proc(ui: ^UI) -> Node_ID {
	id := text(ui, "Local spans", key=key_string("text-span-lifetime"))
	paint := [1]Text_Paint_Span{{
		start=0,
		end=5,
		color=Color{0.8, 0.3, 0.2, 1},
		color_set=true,
	}}
	style := [1]Text_Style_Span{{
		start=0,
		end=5,
		font_weight=FONT_WEIGHT_BOLD,
		font_weight_set=true,
	}}
	_ = text_paint_spans(ui, id, paint[:])
	_ = text_style_spans(ui, id, style[:])
	// The pending descriptions must be independent of caller-local storage.
	paint[0] = {}
	style[0] = {}
	return id
}

@(test)
test_text_span_submission_copies_caller_local_storage :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 80})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	testing.expect(t, build, "the initial text span description must build")
	container_begin(&ui, .Root)
	id := text_span_lifetime_describe_local(&ui)
	container_end(&ui)
	end_frame(&ui)

	node, found := rt.nodes[id]
	testing.expect(t, found && len(node.text_paint_spans) == 1 && len(node.text_style_spans) == 1,
		"reconciliation must retain the spans submitted from caller-local arrays")
	if !found || len(node.text_paint_spans) != 1 || len(node.text_style_spans) != 1 { return }
	testing.expect(t,
		node.text_paint_spans[0].start == 0 && node.text_paint_spans[0].end == 5 &&
		node.text_paint_spans[0].color == Color{0.8, 0.3, 0.2, 1} && node.text_paint_spans[0].color_set,
		"paint spans must keep their submitted values through end_frame reconciliation")
	testing.expect(t,
		node.text_style_spans[0].start == 0 && node.text_style_spans[0].end == 5 &&
		node.text_style_spans[0].font_weight == FONT_WEIGHT_BOLD && node.text_style_spans[0].font_weight_set,
		"style spans must keep their submitted values through end_frame reconciliation")
}
