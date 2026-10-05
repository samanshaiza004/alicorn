package alicorn

import "core:fmt"
import "core:testing"

PAINT_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

@(test)
test_paint_command_storage_budget_and_retained_bytes :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "paint command storage measurement")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "paint command size fixture should build"); return }
	container_begin(&ui, .Root, label="paint-storage-root")
	button(&ui, "surface", key="surface", style=layout_style(width=120, height=32))
	text(&ui, "text", style=layout_style(width=80, height=24))
	container_end(&ui)
	end_frame(&ui)
	retained_bytes := paint_retained_command_capacity_bytes(&rt)
	fmt.println("Alicorn retained paint commands: Paint_Command=", PAINT_COMMAND_SIZE_BYTES,
		" bytes, node+display capacity=", retained_bytes, " bytes")
	testing.expect(t, PAINT_COMMAND_SIZE_BYTES <= PAINT_COMMAND_SIZE_TRIPWIRE_BYTES,
		"Paint_Command exceeded its compact renderer-boundary budget")
	testing.expect(t, retained_bytes >= len(rt.display)*PAINT_COMMAND_SIZE_BYTES,
		"retained paint storage measurement should include the composed display capacity")
}

@(test)
test_geometry_payload_handles_reject_stale_generations :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	invalidate_root(&rt, "geometry resource handle test")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "geometry handle fixture should build"); return }
	container_begin(&ui, .Root, label="geometry-handle-root")
	owner := gpu_geometry_surface(&ui, "geometry-handle", layout_style(width=40, height=30), 1)
	container_end(&ui)
	end_frame(&ui)
	node := rt.nodes[owner]
	handle := paint_geometry_handle_for_node(node)
	_, current_ok := gpu_surface_payload_resolve(&rt, handle)
	_, stale_ok := gpu_surface_payload_resolve(&rt, Geometry_Handle{handle.resource, handle.generation+1})
	testing.expect(t, current_ok, "the current payload handle should resolve")
	testing.expect(t, !stale_ok, "a stale generation must be rejected without resolving a replacement resource")
}

paint_handle_test_render :: proc(rt: ^Runtime, value: string) -> Node_ID {
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin_simple(&ui, .Root, label="paint-handle-root", key=key_string("paint-handle-root"))
	id := text(&ui, value, key=key_string("paint-handle-text"), style=layout_style(width=120, height=28))
	container_end(&ui)
	end_frame(&ui)
	return id
}

@(test)
test_text_payload_handles_reject_replaced_runs :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 100})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, PAINT_TEST_FONT), "text handle fixture font should load")

	id := paint_handle_test_render(&rt, "before")
	old_handle := paint_text_handle_for_node(rt.nodes[id])
	_, old_ok := paint_text_run_resolve(&rt, old_handle)
	testing.expect(t, old_ok, "the current shaped text resource should resolve")

	invalidate_root(&rt, "replace text resource generation")
	replacement_id := paint_handle_test_render(&rt, "after")
	new_handle := paint_text_handle_for_node(rt.nodes[replacement_id])
	new_run, new_ok := paint_text_run_resolve(&rt, new_handle)
	_, stale_ok := paint_text_run_resolve(&rt, old_handle)
	testing.expect(t, replacement_id == id && new_handle.generation != old_handle.generation,
		"reused retained identity must issue a fresh generation when its shaped run changes")
	testing.expect(t, new_ok && new_run.value == "after", "the new text handle should resolve the replacement payload")
	testing.expect(t, !stale_ok, "a stale text generation must not resolve the replacement shaped run")
}

@(test)
test_waveform_background_is_a_generic_surface_before_geometry :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 100})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "waveform paint fixture should build"); return }
	container_begin_simple(&ui, .Root, label="waveform-paint-root", key=key_string("waveform-paint-root"))
	id := gpu_surface(&ui, "waveform-paint", Rect{0, 0, 120, 48}, 120, 48, 1)
	container_end(&ui)
	end_frame(&ui)

	owner := rt.nodes[id]
	testing.expect(t, len(owner.paint) == 2 && paint_command_is_surface(owner.paint[0]) && paint_command_is_geometry(owner.paint[1]),
		"waveform presentation should be an ordinary backing surface followed by a geometry payload command")
	if len(owner.paint) == 2 {
		color, color_ok := paint_surface_color(owner.paint[0])
		testing.expect(t, color_ok && color == Color{0.08, 0.14, 0.24, 1}, "waveform backing color should be resolved by the paint producer")
		geometry, geometry_ok := owner.paint[1].payload.(Geometry_Paint)
		_, payload_ok := gpu_surface_payload_resolve(&rt, geometry.geometry)
		testing.expect(t, geometry_ok && payload_ok, "the geometry command should resolve only the retained waveform payload")
	}
}
