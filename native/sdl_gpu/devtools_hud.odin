package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

// The devtools HUD is rendered by the native host after the application display
// list. It uses only transient solid quads and never enters Runtime.display,
// changes application nodes, or increments Runtime.Frame_Stats.
NATIVE_DEVTOOLS_HUD_REFRESH_INTERVAL_NS :: 1_000_000_000
NATIVE_DEVTOOLS_HUD_IDLE_AFTER_NS       :: 500_000_000
NATIVE_DEVTOOLS_HUD_MAX_RECENT_SAMPLES   :: 48

native_devtools_sample_has_activity :: proc(sample: Native_DevTools_Sample) -> bool {
	return sample.host_wakes > 0 || sample.app_builds > 0 || sample.presentation_updates > 0 ||
		sample.gpu_submissions > 0 || sample.surface_updates > 0 || sample.persistent_allocations > 0 || sample.reconcile_visits > 0 ||
		sample.layout_visits > 0 || sample.paint_visits > 0 || sample.composition_visits > 0
}

Native_DevTools_HUD :: struct {
	visible: bool,
}

Native_DevTools_HUD_Recent :: struct {
	app_builds:          u64,
	presentation_updates: u64,
	gpu_submissions:     u64,
	host_wakes:          u64,
	surface_updates:     u64,
	persistent_allocations: u64,
}

Native_DevTools_HUD_Line :: struct {
	bytes:  [128]u8,
	length: int,
}

native_devtools_hud_toggle :: proc(hud: ^Native_DevTools_HUD) {
	if hud == nil { return }
	hud.visible = !hud.visible
}

native_devtools_hud_recent :: proc(
	recorder: ^Native_Flight_Recorder,
	now_ns: u64,
	preview: Native_DevTools_Sample = {},
	preview_valid := false,
) -> (recent: Native_DevTools_HUD_Recent, last: Native_DevTools_Sample, has_last: bool) {
	count := native_flight_sample_count(recorder)
	cutoff := u64(0)
	if now_ns > 1_000_000_000 { cutoff = now_ns - 1_000_000_000 }
	for logical_index := 0; logical_index < count; logical_index += 1 {
		sample, ok := native_flight_sample_at(recorder, logical_index)
		if !ok { continue }
		last = sample
		has_last = true
		if sample.timestamp_ns < cutoff || sample.timestamp_ns > now_ns { continue }
		recent.app_builds += sample.app_builds
		recent.presentation_updates += sample.presentation_updates
		recent.gpu_submissions += sample.gpu_submissions
		recent.host_wakes += sample.host_wakes
		recent.surface_updates += sample.surface_updates
		recent.persistent_allocations += sample.persistent_allocations
	}
	if preview_valid && preview.timestamp_ns >= cutoff && preview.timestamp_ns <= now_ns {
		recent.app_builds += preview.app_builds
		recent.presentation_updates += preview.presentation_updates
		recent.gpu_submissions += preview.gpu_submissions
		recent.host_wakes += preview.host_wakes
		recent.surface_updates += preview.surface_updates
		recent.persistent_allocations += preview.persistent_allocations
		last = preview
		has_last = true
	}
	return
}

// The host can use this deadline to render the transition to IDLE and to age
// recent counters out of their one-second window without polling an idle app.
// New samples should request an immediate HUD presentation independently.
native_devtools_hud_next_wake_ns :: proc(recorder: ^Native_Flight_Recorder, now_ns: u64) -> u64 {
	count := native_flight_sample_count(recorder)
	if count <= 0 { return 0 }
	latest_activity_ns: u64 = 0
	oldest_recent_ns: u64 = 0
	for logical_index := 0; logical_index < count; logical_index += 1 {
		sample, ok := native_flight_sample_at(recorder, logical_index)
		if !ok { continue }
		if native_devtools_sample_has_activity(sample) && sample.timestamp_ns <= now_ns && sample.timestamp_ns > latest_activity_ns {
			latest_activity_ns = sample.timestamp_ns
		}
		has_recent_count := sample.app_builds+sample.presentation_updates+sample.gpu_submissions+
			sample.host_wakes+sample.surface_updates+sample.persistent_allocations > 0
		if has_recent_count && sample.timestamp_ns <= now_ns && now_ns-sample.timestamp_ns < 1_000_000_000 {
			if oldest_recent_ns == 0 || sample.timestamp_ns < oldest_recent_ns {
				oldest_recent_ns = sample.timestamp_ns
			}
		}
	}
	deadline: u64 = 0
	if latest_activity_ns != 0 && now_ns-latest_activity_ns < NATIVE_DEVTOOLS_HUD_IDLE_AFTER_NS {
		deadline = latest_activity_ns + NATIVE_DEVTOOLS_HUD_IDLE_AFTER_NS
	}
	if oldest_recent_ns != 0 {
		counter_deadline := oldest_recent_ns + 1_000_000_000
		if deadline == 0 || counter_deadline < deadline { deadline = counter_deadline }
	}
	if deadline <= now_ns { return 0 }
	return deadline
}

native_hud_cause_name :: proc(cause: alicorn.Cause_Kind) -> string {
	switch cause {
	case .Pointer:          return "POINTER"
	case .Keyboard:         return "KEYBOARD"
	case .Text_Input:       return "TEXT INPUT"
	case .Text_Composition: return "COMPOSITION"
	case .Scroll:           return "SCROLL"
	case .Native_Command:   return "COMMAND"
	case .Async_Wake:       return "ASYNC WAKE"
	case .Scheduled_Wake:   return "SCHEDULED"
	case .Application:      return "APPLICATION"
	case .Host_Event:       return "HOST EVENT"
	case .None:             return "NONE"
	}
	return "UNKNOWN"
}

native_hud_line_append :: proc(line: ^Native_DevTools_HUD_Line, value: string) {
	for ch in value {
		if line.length >= len(line.bytes) { return }
		line.bytes[line.length] = u8(ch)
		line.length += 1
	}
}

native_hud_line_append_u64 :: proc(line: ^Native_DevTools_HUD_Line, value: u64) {
	digits: [20]u8
	count := 0
	remaining := value
	if remaining == 0 {
		digits[0] = '0'
		count = 1
	} else {
		for remaining > 0 && count < len(digits) {
			digits[count] = u8('0' + remaining % 10)
			remaining /= 10
			count += 1
		}
	}
	for i := count-1; i >= 0; i -= 1 {
		if line.length >= len(line.bytes) { return }
		line.bytes[line.length] = digits[i]
		line.length += 1
	}
}

native_hud_line_string :: proc(line: ^Native_DevTools_HUD_Line) -> string {
	return string(line.bytes[:line.length])
}

native_hud_glyph_rows :: proc(character: u8) -> [7]u8 {
	ch := character
	if ch >= 'a' && ch <= 'z' { ch -= 'a' - 'A' }
	switch ch {
	case 'A': return {14,17,17,31,17,17,17}
	case 'B': return {30,17,17,30,17,17,30}
	case 'C': return {14,17,16,16,16,17,14}
	case 'D': return {30,17,17,17,17,17,30}
	case 'E': return {31,16,16,30,16,16,31}
	case 'F': return {31,16,16,30,16,16,16}
	case 'G': return {14,17,16,23,17,17,15}
	case 'H': return {17,17,17,31,17,17,17}
	case 'I': return {14,4,4,4,4,4,14}
	case 'J': return {7,2,2,2,18,18,12}
	case 'K': return {17,18,20,24,20,18,17}
	case 'L': return {16,16,16,16,16,16,31}
	case 'M': return {17,27,21,21,17,17,17}
	case 'N': return {17,25,21,19,17,17,17}
	case 'O': return {14,17,17,17,17,17,14}
	case 'P': return {30,17,17,30,16,16,16}
	case 'Q': return {14,17,17,17,21,18,13}
	case 'R': return {30,17,17,30,20,18,17}
	case 'S': return {15,16,16,14,1,1,30}
	case 'T': return {31,4,4,4,4,4,4}
	case 'U': return {17,17,17,17,17,17,14}
	case 'V': return {17,17,17,17,17,10,4}
	case 'W': return {17,17,17,21,21,21,10}
	case 'X': return {17,17,10,4,10,17,17}
	case 'Y': return {17,17,10,4,4,4,4}
	case 'Z': return {31,1,2,4,8,16,31}
	case '0': return {14,17,19,21,25,17,14}
	case '1': return {4,12,4,4,4,4,14}
	case '2': return {14,17,1,2,4,8,31}
	case '3': return {30,1,1,14,1,1,30}
	case '4': return {2,6,10,18,31,2,2}
	case '5': return {31,16,16,30,1,1,30}
	case '6': return {14,16,16,30,17,17,14}
	case '7': return {31,1,2,4,8,8,8}
	case '8': return {14,17,17,14,17,17,14}
	case '9': return {14,17,17,15,1,1,14}
	case ':': return {0,4,4,0,4,4,0}
	case '.': return {0,0,0,0,0,6,6}
	case ',': return {0,0,0,0,6,6,4}
	case '-': return {0,0,0,31,0,0,0}
	case '+': return {0,4,4,31,4,4,0}
	case '/': return {1,2,2,4,8,8,16}
	case '#': return {10,31,10,10,31,10,0}
	case '_': return {0,0,0,0,0,0,31}
	case ' ': return {}
	}
	return {}
}

native_hud_draw_quad :: proc(renderer: ^Native_Solid_Renderer, x, y, width, height: f32, color: [4]f32) {
	if width <= 0 || height <= 0 || len(renderer.vertices)+6 > MAX_SOLID_VERTICES { return }
	native_solid_append_quad(&renderer.vertices, x, y, x+width, y+height, color)
}

native_hud_draw_text :: proc(renderer: ^Native_Solid_Renderer, value: string, x, y, pixel_scale: int, color: [4]f32, clip_right: int) {
	if pixel_scale <= 0 { return }
	cursor_x := x
	for character in value {
		if cursor_x + 5*pixel_scale > clip_right { break }
		rows := native_hud_glyph_rows(u8(character))
		for row in 0..<7 {
			bits := rows[row]
			for column in 0..<5 {
				mask := u8(1 << u32(4-column))
				if bits & mask != 0 {
					native_hud_draw_quad(renderer, f32(cursor_x+column*pixel_scale), f32(y+row*pixel_scale), f32(pixel_scale), f32(pixel_scale), color)
				}
			}
		}
		cursor_x += 6*pixel_scale
	}
}

native_hud_build_line :: proc(renderer: ^Native_Solid_Renderer, line: ^Native_DevTools_HUD_Line, x, y, pixel_scale, clip_right: int, color: [4]f32) {
	native_hud_draw_text(renderer, native_hud_line_string(line), x, y, pixel_scale, color, clip_right)
}

native_hud_line_number :: proc(prefix: string, value: u64) -> Native_DevTools_HUD_Line {
	line: Native_DevTools_HUD_Line
	native_hud_line_append(&line, prefix)
	native_hud_line_append_u64(&line, value)
	return line
}

native_devtools_hud_render :: proc(
	hud: ^Native_DevTools_HUD,
	renderer: ^Native_Solid_Renderer,
	command: ^sdl3.GPUCommandBuffer,
	target: ^sdl3.GPUTexture,
	target_w, target_h: sdl3.Uint32,
	scale_x, scale_y: f32,
	recorder: ^Native_Flight_Recorder,
	now_ns: u64,
	preview: Native_DevTools_Sample = {},
	preview_valid := false,
	last_invalidation: string = "",
) -> bool {
	if hud == nil || !hud.visible || renderer == nil || command == nil || target == nil || target_w == 0 || target_h == 0 {
		return true
	}
	font_scale := int(max(scale_x, scale_y) + 0.5)
	if font_scale < 1 { font_scale = 1 }
	if font_scale > 3 { font_scale = 3 }
	margin := 12 * font_scale
	panel_w := min(int(target_w)-2*margin, 410*font_scale)
	if panel_w < 150*font_scale { return true }
	panel_h := 116 * font_scale
	if int(target_h) < panel_h+2*margin { return true }
	panel_x := int(target_w)-panel_w-margin
	panel_y := margin

	// Preserve renderer aggregates: host-only HUD geometry must not appear as
	// application solid batches or uploads in the regular diagnostics report.
	previous_batches := renderer.batches
	previous_vertices_uploaded := renderer.vertices_uploaded
	defer {
		renderer.batches = previous_batches
		renderer.vertices_uploaded = previous_vertices_uploaded
	}

	vertex_start := len(renderer.vertices)
	draw_start := len(renderer.draws)
	native_hud_draw_quad(renderer, f32(panel_x), f32(panel_y), f32(panel_w), f32(panel_h), [4]f32{0.025, 0.035, 0.055, 0.96})
	native_hud_draw_quad(renderer, f32(panel_x), f32(panel_y), f32(panel_w), f32(3*font_scale), [4]f32{0.20, 0.68, 0.86, 1})

	recent, last, has_last := native_devtools_hud_recent(recorder, now_ns, preview, preview_valid)
	last_activity_ns: u64 = 0
	for logical_index := 0; logical_index < native_flight_sample_count(recorder); logical_index += 1 {
		sample, ok := native_flight_sample_at(recorder, logical_index)
		if ok && native_devtools_sample_has_activity(sample) && sample.timestamp_ns <= now_ns && sample.timestamp_ns > last_activity_ns {
			last_activity_ns = sample.timestamp_ns
		}
	}
	if preview_valid && native_devtools_sample_has_activity(preview) && preview.timestamp_ns <= now_ns && preview.timestamp_ns > last_activity_ns {
		last_activity_ns = preview.timestamp_ns
	}
	idle := last_activity_ns == 0 || now_ns-last_activity_ns >= NATIVE_DEVTOOLS_HUD_IDLE_AFTER_NS
	content_x := panel_x + 10*font_scale
	clip_right := panel_x + panel_w - 8*font_scale
	line_y := panel_y + 8*font_scale
	line_height := 10*font_scale
	white := [4]f32{0.82, 0.89, 0.96, 1}
	muted := [4]f32{0.52, 0.62, 0.72, 1}
	green := [4]f32{0.32, 0.88, 0.58, 1}
	cyan := [4]f32{0.38, 0.78, 0.96, 1}

	line: Native_DevTools_HUD_Line
	native_hud_line_append(&line, "ALICORN DEVTOOLS")
	native_hud_line_append(&line, "  IDLE" if idle else "  ACTIVE")
	native_hud_build_line(renderer, &line, content_x, line_y, font_scale, clip_right, green if idle else cyan)

	line = {}
	native_hud_line_append(&line, "1S BLD ")
	native_hud_line_append_u64(&line, recent.app_builds)
	native_hud_line_append(&line, " PRES ")
	native_hud_line_append_u64(&line, recent.presentation_updates)
	native_hud_line_append(&line, " GPU ")
	native_hud_line_append_u64(&line, recent.gpu_submissions)
	native_hud_build_line(renderer, &line, content_x, line_y+line_height, font_scale, clip_right, white)

	line = {}
	native_hud_line_append(&line, "WAKE ")
	native_hud_line_append_u64(&line, recent.host_wakes)
	native_hud_line_append(&line, " SURF ")
	native_hud_line_append_u64(&line, recent.surface_updates)
	native_hud_line_append(&line, " ALLOC ")
	native_hud_line_append_u64(&line, recent.persistent_allocations)
	native_hud_build_line(renderer, &line, content_x, line_y+2*line_height, font_scale, clip_right, muted)

	last_work := last
	if has_last {
		count := native_flight_sample_count(recorder)
		for logical_index := count-1; logical_index >= 0; logical_index -= 1 {
			sample, ok := native_flight_sample_at(recorder, logical_index)
			if !ok { continue }
			if sample.host_wakes > 0 || sample.app_builds+sample.presentation_updates+sample.gpu_submissions+sample.surface_updates > 0 {
				last_work = sample
				break
			}
		}
	}
	if preview_valid && (preview.host_wakes > 0 || preview.app_builds+preview.presentation_updates+preview.gpu_submissions+preview.surface_updates > 0) {
		last_work = preview
	}
	line = {}
	native_hud_line_append(&line, "LAST ")
	native_hud_line_append(&line, native_hud_cause_name(last_work.cause_kind))
	if last_work.cause_id != 0 {
		native_hud_line_append(&line, " #")
		native_hud_line_append_u64(&line, last_work.cause_id)
	}
	native_hud_build_line(renderer, &line, content_x, line_y+3*line_height, font_scale, clip_right, white)

	line = {}
	native_hud_line_append(&line, "WORK B")
	native_hud_line_append_u64(&line, last_work.app_builds)
	native_hud_line_append(&line, " D")
	native_hud_line_append_u64(&line, last_work.descriptions_emitted)
	native_hud_line_append(&line, " R")
	native_hud_line_append_u64(&line, last_work.reconcile_visits)
	native_hud_line_append(&line, " L")
	native_hud_line_append_u64(&line, last_work.layout_visits)
	native_hud_build_line(renderer, &line, content_x, line_y+4*line_height, font_scale, clip_right, cyan)

	line = {}
	native_hud_line_append(&line, "P")
	native_hud_line_append_u64(&line, last_work.paint_visits)
	native_hud_line_append(&line, " C")
	native_hud_line_append_u64(&line, last_work.composition_visits)
	native_hud_line_append(&line, " N+")
	native_hud_line_append_u64(&line, last_work.nodes_created)
	native_hud_line_append(&line, " -")
	native_hud_line_append_u64(&line, last_work.nodes_retired)
	native_hud_line_append(&line, " SK")
	native_hud_line_append_u64(&line, last_work.regions_skipped)
	native_hud_line_append(&line, " RE")
	native_hud_line_append_u64(&line, last_work.retained_subtrees_reused)
	native_hud_line_append(&line, " A")
	native_hud_line_append_u64(&line, last_work.persistent_allocations)
	native_hud_build_line(renderer, &line, content_x, line_y+5*line_height, font_scale, clip_right, muted)

	line = {}
	native_hud_line_append(&line, "BUILD ")
	native_hud_line_append_u64(&line, last_work.build_ns/1000)
	native_hud_line_append(&line, "US ENC ")
	native_hud_line_append_u64(&line, last_work.encode_ns/1000)
	native_hud_line_append(&line, "US IN~ ")
	native_hud_line_append_u64(&line, last_work.input_to_submit_ns/1000)
	native_hud_line_append(&line, "US SCR ")
	native_hud_line_append_u64(&line, last_work.scratch_requested_bytes)
	native_hud_build_line(renderer, &line, content_x, line_y+6*line_height, font_scale, clip_right, white)

	line = {}
	native_hud_line_append(&line, "INV ")
	native_hud_line_append(&line, last_invalidation)
	native_hud_build_line(renderer, &line, content_x, line_y+7*line_height, font_scale, clip_right, muted)

	// Draw a bounded oldest-to-newest activity strip. Colors distinguish app
	// work, submission, and host-only wakes without implying a fixed frame rate.
	strip_y := panel_y + panel_h - 17*font_scale
	strip_x := content_x
	strip_w := max(panel_w-20*font_scale, 0)
	bar_count := min(native_flight_sample_count(recorder), NATIVE_DEVTOOLS_HUD_MAX_RECENT_SAMPLES)
	bar_gap := font_scale
	bar_width := max((strip_w-(bar_count-1)*bar_gap)/max(bar_count,1), font_scale)
	max_work: u64 = 1
	for logical_index := max(native_flight_sample_count(recorder)-bar_count, 0); logical_index < native_flight_sample_count(recorder); logical_index += 1 {
		sample, ok := native_flight_sample_at(recorder, logical_index)
		if !ok { continue }
		work := sample.app_builds + sample.presentation_updates + sample.gpu_submissions + sample.host_wakes
		if work > max_work { max_work = work }
	}
	for bar_index := 0; bar_index < bar_count; bar_index += 1 {
		logical_index := native_flight_sample_count(recorder)-bar_count+bar_index
		sample, ok := native_flight_sample_at(recorder, logical_index)
		if !ok { continue }
		work := sample.app_builds + sample.presentation_updates + sample.gpu_submissions + sample.host_wakes
		bar_h := font_scale + int(u64(10*font_scale)*work/max_work)
		bar_color := [4]f32{0.23, 0.34, 0.44, 1}
		if sample.host_wakes > 0 { bar_color = [4]f32{0.48, 0.55, 0.62, 1} }
		if sample.app_builds+sample.presentation_updates > 0 { bar_color = [4]f32{0.28, 0.70, 0.88, 1} }
		if sample.gpu_submissions > 0 { bar_color = [4]f32{0.34, 0.84, 0.62, 1} }
		x := strip_x + bar_index*(bar_width+bar_gap)
		if x+bar_width > strip_x+strip_w { bar_width = max(strip_x+strip_w-x, 0) }
		bar_top := strip_y + 12*font_scale - bar_h
		native_hud_draw_quad(renderer, f32(x), f32(bar_top), f32(bar_width), f32(bar_h), bar_color)
	}

	if len(renderer.vertices)-vertex_start == 0 { return true }
	append(&renderer.draws, Native_Solid_Draw{first_vertex=sdl3.Uint32(vertex_start), vertex_count=sdl3.Uint32(len(renderer.vertices)-vertex_start)})
	renderer.upload_pending = true
	if !native_solid_prepare_white_texture(renderer, command) { return false }
	if !native_solid_upload(renderer, command) { return false }
	if !native_solid_render_batch(renderer, command, target, target_w, target_h, renderer.draws[draw_start:]) { return false }
	return true
}
