package alicorn_sdl_gpu

import "core:fmt"
import "core:c"
import "core:os"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

// A primary capture is accompanied by a compact inventory of every native
// window owned by this host. The secondary entry intentionally describes the
// live child Runtime, rather than the primary Runtime or shared app model.
native_append_window_diagnostic :: proc(
	builder: ^strings.Builder,
	window: ^sdl3.Window,
	metrics: Window_Metrics,
	rt: ^alicorn.Runtime,
	menu: ^Native_Menu_Runtime,
) {
	flags := sdl3.GetWindowFlags(window)
	focused := (flags & sdl3.WindowFlags{.INPUT_FOCUS}) != sdl3.WindowFlags{}
	mouse_focused := sdl3.GetMouseFocus() == window
	topmost := (flags & sdl3.WindowFlags{.ALWAYS_ON_TOP}) != sdl3.WindowFlags{}
	position_x, position_y: c.int
	_ = sdl3.GetWindowPosition(window, &position_x, &position_y)
	fmt.sbprintf(builder, `{{
	  "sdl_window_id": %d,
	  "sdl_position_x": %d,
	  "sdl_position_y": %d,
	  "focused": %t,
	  "mouse_focused": %t,
	  "always_on_top": %t,
	  "logical_width": %d,
	  "logical_height": %d,
	  "window_logical_height": %d,
	  "pixel_width": %d,
	  "pixel_height": %d,
	  "pixel_density": %.4f,
	  "display_scale": %.4f,
	  "runtime": {{
	    "viewport": {{"x": %.3f, "y": %.3f, "width": %.3f, "height": %.3f}},
	    "retained_nodes": %d,
	    "display_commands": %d,
	    "focused_node": %d,
	    "gpu_submissions": %d,
	    "frame_needs_submission": %t,
	    "presentation_revision": %d,
	    "submitted_revision": %d
	  }}`, sdl3.GetWindowID(window), position_x, position_y, focused, mouse_focused, topmost,
		metrics.logical_width, metrics.logical_height, metrics.window_logical_height,
		metrics.pixel_width, metrics.pixel_height, metrics.pixel_density, metrics.display_scale,
		rt.viewport.x, rt.viewport.y, rt.viewport.w, rt.viewport.h,
		len(rt.nodes), len(rt.display), u64(rt.focused), rt.stats.gpu_submits,
		alicorn.frame_needs_submission(rt), rt.presentation_revision, rt.submitted_revision)
	when ODIN_OS == .Windows {
		native_window_append_platform_diagnostics(builder, menu)
	}
	strings.write_string(builder, "}")
}

native_window_diagnostics_json :: proc(
	primary_window: ^sdl3.Window,
	primary_metrics: Window_Metrics,
	primary_runtime: ^alicorn.Runtime,
	primary_menu: ^Native_Menu_Runtime,
	secondary: ^Native_Secondary_Window_Manager,
) -> string {
	if primary_window == nil || primary_runtime == nil { return "" }
	builder, err := strings.builder_make()
	if err != nil { return "" }
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, `{
  "schema": 1,
  "kind": "alicorn-native-window-diagnostics",
  "primary": `)
	native_append_window_diagnostic(&builder, primary_window, primary_metrics, primary_runtime, primary_menu)
	strings.write_string(&builder, `,
  "secondary": `)
	if secondary != nil && secondary.child != nil && secondary.child.active &&
	   secondary.child.window != nil && secondary.child.runtime != nil {
		child := secondary.child
		native_append_window_diagnostic(&builder, child.window, child.metrics, child.runtime, &child.native_menu)
	} else {
		strings.write_string(&builder, "null")
	}
	strings.write_string(&builder, "\n}\n")
	result, clone_err := strings.clone(strings.to_string(builder))
	if clone_err != nil { return "" }
	return result
}

native_write_window_diagnostics :: proc(
	path: string,
	primary_window: ^sdl3.Window,
	primary_metrics: Window_Metrics,
	primary_runtime: ^alicorn.Runtime,
	primary_menu: ^Native_Menu_Runtime,
	secondary: ^Native_Secondary_Window_Manager,
) -> bool {
	json := native_window_diagnostics_json(primary_window, primary_metrics, primary_runtime, primary_menu, secondary)
	if json == "" { return false }
	defer delete(json)
	return os.write_entire_file(path, json) == nil
}

native_capture_secondary_diagnostics :: proc(
	bundle_dir: string,
	device: ^sdl3.GPUDevice,
	secondary: ^Native_Secondary_Window_Manager,
	debug_bounds := false,
) -> bool {
	if secondary == nil || secondary.child == nil || !secondary.child.active { return true }
	child := secondary.child
	if child.window == nil || child.runtime == nil { return false }

	inspection := alicorn.inspect(child.runtime)
	inspection_path := fmt.tprintf("%s/secondary-inspector.txt", bundle_dir)
	inspection_ok := os.write_entire_file(inspection_path, inspection) == nil
	delete(inspection)
	if !inspection_ok { return false }
	if !native_write_flight_timeline(fmt.tprintf("%s/secondary-timeline.json", bundle_dir), &child.flight_recorder) { return false }

	screenshot_path := fmt.tprintf("%s/secondary-screenshot.ppm", bundle_dir)
	if !native_capture_display_ppm(
		device, &child.text_renderer, &child.surface_renderer, &child.solid_renderer,
		child.runtime.display[:],
		sdl3.Uint32(max(child.metrics.pixel_width, 0)),
		sdl3.Uint32(max(child.metrics.pixel_height, 0)),
		f32(child.metrics.pixel_width)/f32(max(child.metrics.logical_width, 1)),
		f32(child.metrics.pixel_height)/f32(max(child.metrics.window_logical_height, 1)),
		screenshot_path,
		debug_bounds=debug_bounds,
		content_inset_top=child.native_menu.content_inset_top,
		native_menu=&child.native_menu,
		scratch_allocator=child.host_scratch.allocator,
	) {
		fmt.println("alicorn_diagnostics", "secondary_screenshot_failed", screenshot_path)
		return false
	}
	fmt.println("alicorn_diagnostics", "secondary_screenshot", screenshot_path)
	return true
}
