package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

paint_stream_test_same_rect :: proc(a, b: alicorn.Rect) -> bool {
	return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h
}

@(test)
test_paint_stream_keeps_heterogeneous_order_and_only_batches_neighbors :: proc(t: ^testing.T) {
	overlap := alicorn.Rect{4, 6, 32, 24}
	clip := alicorn.Rect{0, 0, 80, 60}
	host_text := alicorn.Text_Run_Handle{source=.Host, resource=7, generation=11}
	geometry := alicorn.Geometry_Handle{resource=9, generation=13}
	display := [5]alicorn.Paint_Command{
		alicorn.paint_surface_command(1, overlap, clip, alicorn.Color{1, 0, 0, 1}),
		alicorn.paint_text_command(2, overlap, clip, host_text, alicorn.Color{1, 1, 1, 1}),
		alicorn.paint_surface_command(3, overlap, clip, alicorn.Color{0, 1, 0, 1}),
		alicorn.paint_geometry_command(4, overlap, clip, geometry),
		alicorn.paint_text_command(5, overlap, clip, host_text, alicorn.Color{0, 0, 1, 1}),
	}
	expected := [5]Native_Paint_Run_Kind{.Surface, .Text, .Surface, .Geometry, .Text}
	index := 0
	for run_index in 0..<len(expected) {
		kind, end := native_paint_run(display[:], index)
		testing.expect(t, kind == expected[run_index], "renderer run dispatch must follow retained payload order")
		testing.expect(t, end == index+1, "incompatible or overlapping payloads must remain separate ordering barriers")
		testing.expect(t, paint_stream_test_same_rect(display[index].bounds, overlap), "fixture commands should overlap so reordering would change visible compositing")
		index = end
	}
	testing.expect(t, index == len(display), "the compositor must visit each retained paint command exactly once")

	batched := [3]alicorn.Paint_Command{
		alicorn.paint_surface_command(1, overlap, clip, alicorn.Color{1, 0, 0, 1}),
		alicorn.paint_surface_command(2, overlap, clip, alicorn.Color{0, 1, 0, 1}),
		alicorn.paint_text_command(3, overlap, clip, host_text, alicorn.Color{1, 1, 1, 1}),
	}
	kind, end := native_paint_run(batched[:], 0)
	testing.expect(t, kind == .Surface && end == 2, "only adjacent compatible surface primitives may share a renderer batch")
}
