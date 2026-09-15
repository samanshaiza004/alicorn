package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:time"
import alicorn "../../runtime"

NATIVE_DIAGNOSTIC_FRAME_SAMPLES :: 240

Native_Diagnostics_Options :: struct {
	enabled:             bool,
	capture_requested:   bool,
	capture_after_ns:    u64,
	capture_dir:         string,
	captured:            bool,
}

Native_Host_Timing :: struct {
	frames:              u64,
	event_pump_ns:       u64,
	application_build_ns: u64,
	application_tick_ns: u64,
	gpu_encode_ns:       u64,
	gpu_submit_ns:       u64,
	fence_wait_ns:       u64,
	frame_ns_total:      u64,
	frame_ns_max:        u64,
	gpu_submissions:     u64,
	fence_waits:         u64,
	frame_samples:       [dynamic; NATIVE_DIAGNOSTIC_FRAME_SAMPLES]u64,
}

native_timing_add_frame :: proc(timing: ^Native_Host_Timing, frame_ns: u64) {
	timing.frames += 1
	timing.frame_ns_total += frame_ns
	if frame_ns > timing.frame_ns_max { timing.frame_ns_max = frame_ns }
	if len(timing.frame_samples) >= NATIVE_DIAGNOSTIC_FRAME_SAMPLES {
		for i := 1; i < len(timing.frame_samples); i += 1 {
			timing.frame_samples[i-1] = timing.frame_samples[i]
		}
		pop(&timing.frame_samples)
	}
	append(&timing.frame_samples, frame_ns)
}

native_timing_percentile :: proc(samples: []u64, fraction: f64) -> u64 {
	if len(samples) == 0 { return 0 }
	ordered := make([]u64, len(samples))
	defer delete(ordered)
	copy(ordered, samples)
	sort.quick_sort(ordered)
	index := int(fraction * f64(len(ordered)-1))
	return ordered[index]
}

native_parse_diagnostics_options :: proc() -> Native_Diagnostics_Options {
	options := Native_Diagnostics_Options{
		capture_after_ns = 2_000_000_000,
		capture_dir = "out/diagnostics",
	}
	for argument in os.args {
		if argument == "--diagnostics" {
			options.enabled = true
			continue
		}
		capture_after_prefix := "--capture-after="
		if len(argument) > len(capture_after_prefix) && argument[:len(capture_after_prefix)] == capture_after_prefix {
			seconds, ok := strconv.parse_int(argument[len(capture_after_prefix):])
			if ok && seconds >= 0 {
				options.enabled = true
				options.capture_after_ns = u64(seconds) * 1_000_000_000
			}
			continue
		}
		capture_dir_prefix := "--capture-dir="
		if len(argument) > len(capture_dir_prefix) && argument[:len(capture_dir_prefix)] == capture_dir_prefix {
			options.enabled = true
			options.capture_dir = argument[len(capture_dir_prefix):]
		}
	}
	return options
}

native_write_diagnostics :: proc(
	options: ^Native_Diagnostics_Options,
	started: time.Time,
	gpu_driver: string,
	metrics: Window_Metrics,
	rt: ^alicorn.Runtime,
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	timing: ^Native_Host_Timing,
) -> bool {
	if (!options.enabled && !options.capture_requested) || options.captured { return false }
	if !options.capture_requested && time.duration_nanoseconds(time.since(started)) < i64(options.capture_after_ns) { return false }
	if err := os.make_directory_all(options.capture_dir); err != nil { return false }

	p50 := native_timing_percentile(timing.frame_samples[:], 0.50)
	p95 := native_timing_percentile(timing.frame_samples[:], 0.95)
	p99 := native_timing_percentile(timing.frame_samples[:], 0.99)
	average := u64(0)
	if timing.frames > 0 { average = timing.frame_ns_total / timing.frames }
	builder, builder_err := strings.builder_make()
	if builder_err != nil { return false }
	defer strings.builder_destroy(&builder)
	fmt.sbprintf(&builder, `{{
  "schema": 1,
  "kind": "alicorn-native-diagnostics",
  "gpu_driver": "%s",
  "window": {{
    "logical_width": %d,
    "logical_height": %d,
    "pixel_width": %d,
    "pixel_height": %d,
    "pixel_density": %.4f,
    "display_scale": %.4f
  }},
`, gpu_driver,
		metrics.logical_width, metrics.logical_height, metrics.pixel_width, metrics.pixel_height,
		metrics.pixel_density, metrics.display_scale)
	fmt.sbprintf(&builder, `  "timing_ns": {{
    "frames": %d,
    "event_pump": %d,
    "application_build": %d,
    "application_tick": %d,
    "gpu_encode": %d,
    "gpu_submit": %d,
    "fence_wait": %d,
    "frame_average": %d,
    "frame_p50": %d,
    "frame_p95": %d,
    "frame_p99": %d,
    "frame_max": %d
  }},
`, timing.frames, timing.event_pump_ns, timing.application_build_ns, timing.application_tick_ns,
		timing.gpu_encode_ns, timing.gpu_submit_ns, timing.fence_wait_ns, average,
		p50, p95, p99, timing.frame_ns_max)
	fmt.sbprintf(&builder, `  "gpu": {{
    "submissions": %d,
    "fence_waits": %d,
    "text_shape_calls": %d,
    "text_glyph_cache_hits": %d,
    "text_glyph_cache_misses": %d,
    "text_rasterizations": %d,
    "text_atlas_pages": %d,
    "surface_encodes": %d,
    "surface_vertex_uploads": %d,
    "solid_batches": %d,
    "solid_vertices_uploaded": %d
  }},
`, timing.gpu_submissions, timing.fence_waits,
		rt.text_engine.shape_calls, rt.text_engine.glyph_cache_hits, rt.text_engine.glyph_cache_misses,
		rt.text_engine.glyph_rasterizations,
		len(text_renderer.pages), surface_renderer.encodes, surface_renderer.vertex_uploads,
		solid_renderer.batches, solid_renderer.vertices_uploaded)
	fmt.sbprintf(&builder, `  "runtime": {{
    "retained_nodes": %d,
    "display_commands": %d,
    "focused_node": %d,
    "gpu_surface_updates": %d,
    "gpu_surface_frames_consumed": %d
  }},
`, len(rt.nodes), len(rt.display), u64(rt.focused), rt.stats.surface_updates, rt.stats.surface_frames_consumed)
	strings.write_string(&builder, `  "notes": [
    "timing values are host wall-clock measurements in nanoseconds",
    "runtime allocation telemetry excludes application allocations, GPU memory, driver memory, and OS working set",
    "solid rectangles are batched only within contiguous display-list runs; text and custom surfaces remain ordering boundaries"
  ]
}
`)
	json := strings.to_string(builder)
	path := fmt.tprintf("%s/diagnostics.json", options.capture_dir)
	if err := os.write_entire_file(path, json); err != nil { return false }
	// Keep the full retained-tree explanation beside the compact JSON. The
	// human-readable inspector already contains node identity, bounds, dirty
	// stages, focus/hover state, and invalidation reasons without requiring a
	// JSON escaping layer in the runtime.
	inspection := alicorn.inspect(rt)
	inspection_path := fmt.tprintf("%s/inspector.txt", options.capture_dir)
	if err := os.write_entire_file(inspection_path, inspection); err != nil {
		delete(inspection)
		return false
	}
	delete(inspection)
	options.captured = true
	fmt.println("alicorn_diagnostics", "path", path, "inspector", inspection_path, "frame_p95_ns", p95, "gpu_encode_ns", timing.gpu_encode_ns)
	return true
}
