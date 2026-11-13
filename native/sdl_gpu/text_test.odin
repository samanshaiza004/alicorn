package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_native_text_quad_clip_intersection :: proc(t: ^testing.T) {
	clip := alicorn.Rect{10, 20, 100, 40}
	testing.expect(t, native_text_quad_visible(20, 30, 25, 35, clip, 1, 1), "quad fully inside clip should render")
	testing.expect(t, native_text_quad_visible(8, 30, 12, 35, clip, 1, 1), "quad crossing clip edge should render")
	testing.expect(t, !native_text_quad_visible(0, 30, 9, 35, clip, 1, 1), "quad outside horizontal clip should be culled")
	testing.expect(t, !native_text_quad_visible(20, 61, 25, 70, clip, 1, 1), "quad outside vertical clip should be culled")
	testing.expect(t, native_text_quad_visible(40, 50, 50, 60, clip, 2, 2), "clip should use the same physical scale as glyph geometry")
}

@(test)
test_native_text_color_glyph_preserves_embedded_rgb :: proc(t: ^testing.T) {
	paint := alicorn.Color{r=0.2, g=0.4, b=0.8, a=0.6}
	monochrome := native_text_vertex_color(paint, 0.5, false)
	color_glyph := native_text_vertex_color(paint, 0.5, true)
	testing.expect(t, monochrome == [4]f32{0.2, 0.4, 0.8, 0.3},
		"monochrome glyphs should retain syntax tint and multiply alpha by command opacity")
	testing.expect(t, color_glyph == [4]f32{1, 1, 1, 0.3},
		"color glyph RGB should remain from the atlas while paint alpha and opacity still apply")
}

@(test)
test_native_text_mesh_fingerprint_ignores_non_text_command_positions :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	renderer := Native_Text_Renderer{
		runtime=&rt,
		host_runs=make([dynamic]Native_Host_Text_Run, 0, 2, allocator=context.temp_allocator),
	}
	defer delete(renderer.host_runs)
	handle := alicorn.Text_Run_Handle{.Host, 41, 1}
	append(&renderer.host_runs, Native_Host_Text_Run{
		host_id=alicorn.Node_ID(41),
		handle=handle,
		run=alicorn.Text_Run{value="unchanged retained text", size=14},
	})
	text := alicorn.paint_text_command(
		alicorn.Node_ID(41), alicorn.Rect{8, 12, 180, 20}, alicorn.Rect{0, 0, 320, 200},
		handle, alicorn.Color{0.9, 0.9, 0.9, 1},
	)
	selection := alicorn.paint_surface_command(
		alicorn.Node_ID(41), alicorn.Rect{28, 12, 34, 20}, alicorn.Rect{0, 0, 320, 200},
		alicorn.Color{0.2, 0.4, 0.8, 0.5},
	)
	caret := alicorn.paint_surface_command(
		alicorn.Node_ID(41), alicorn.Rect{62, 12, 1, 20}, alicorn.Rect{0, 0, 320, 200},
		alicorn.Color{0.9, 0.9, 0.9, 1},
	)
	before := [1]alicorn.Paint_Command{text}
	selection_before_text := [2]alicorn.Paint_Command{selection, text}
	caret_after_text := [2]alicorn.Paint_Command{text, caret}
	fingerprint, _ := native_text_mesh_fingerprint(&renderer, before[:], 1, 1)
	selection_fingerprint, _ := native_text_mesh_fingerprint(&renderer, selection_before_text[:], 1, 1)
	caret_fingerprint, _ := native_text_mesh_fingerprint(&renderer, caret_after_text[:], 1, 1)
	testing.expect(t, fingerprint == selection_fingerprint && fingerprint == caret_fingerprint,
		"selection and caret surfaces should not invalidate an unchanged ordered text mesh")
	mesh_renderer := Native_Text_Renderer{
		runtime=&rt,
		host_runs=renderer.host_runs,
	}
	defer delete(mesh_renderer.vertices)
	defer delete(mesh_renderer.draws)
	testing.expect(t, native_text_rebuild_mesh(&mesh_renderer, before[:], 1, 1),
		"the baseline text display should build a mesh")
	testing.expect(t, native_text_rebuild_mesh(&mesh_renderer, selection_before_text[:], 1, 1),
		"adding a selection surface should keep the text mesh usable")
	testing.expect(t, mesh_renderer.mesh_rebuilds == 1 && mesh_renderer.mesh_cache_hits == 1,
		"selection-only changes should reuse the retained text mesh")
}

@(test)
test_native_text_mesh_fingerprint_preserves_text_order_and_generation :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	renderer := Native_Text_Renderer{
		runtime=&rt,
		host_runs=make([dynamic]Native_Host_Text_Run, 0, 2, allocator=context.temp_allocator),
	}
	defer delete(renderer.host_runs)
	first_handle := alicorn.Text_Run_Handle{.Host, 41, 1}
	second_handle := alicorn.Text_Run_Handle{.Host, 42, 1}
	append(&renderer.host_runs,
		Native_Host_Text_Run{alicorn.Node_ID(41), first_handle, alicorn.Text_Run{value="first", size=14}},
		Native_Host_Text_Run{alicorn.Node_ID(42), second_handle, alicorn.Text_Run{value="second", size=14}},
	)
	first := alicorn.paint_text_command(
		alicorn.Node_ID(41), alicorn.Rect{8, 12, 100, 20}, alicorn.Rect{0, 0, 320, 200},
		first_handle, alicorn.Color{1, 1, 1, 1},
	)
	second := alicorn.paint_text_command(
		alicorn.Node_ID(42), alicorn.Rect{8, 32, 100, 20}, alicorn.Rect{0, 0, 320, 200},
		second_handle, alicorn.Color{1, 1, 1, 1},
	)
	forward := [2]alicorn.Paint_Command{first, second}
	reverse := [2]alicorn.Paint_Command{second, first}
	forward_fingerprint, _ := native_text_mesh_fingerprint(&renderer, forward[:], 1, 1)
	reverse_fingerprint, _ := native_text_mesh_fingerprint(&renderer, reverse[:], 1, 1)
	new_generation_handle := first_handle
	new_generation_handle.generation += 1
	new_generation := alicorn.paint_text_command(
		alicorn.Node_ID(41), alicorn.Rect{8, 12, 100, 20}, alicorn.Rect{0, 0, 320, 200},
		new_generation_handle, alicorn.Color{1, 1, 1, 1},
	)
	changed_generation := [1]alicorn.Paint_Command{new_generation}
	new_generation_fingerprint, _ := native_text_mesh_fingerprint(&renderer, changed_generation[:], 1, 1)
	testing.expect(t, forward_fingerprint != reverse_fingerprint,
		"reordering text commands must invalidate their ordered mesh")
	testing.expect(t, forward_fingerprint != new_generation_fingerprint,
		"changing a retained text-run generation must invalidate the mesh")
	draw0 := Native_Text_Draw{text_command_index=0, run_handle=first_handle}
	draw1 := Native_Text_Draw{text_command_index=1, run_handle=first_handle}
	testing.expect(t, native_text_draw_matches_command(draw0, 0, first_handle) &&
		!native_text_draw_matches_command(draw0, 1, first_handle) &&
		native_text_draw_matches_command(draw1, 1, first_handle),
		"text-only ordinals should keep repeated run handles attached to the right display command")
}
