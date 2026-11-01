package alicorn_sdl_gpu

import "core:strings"
import "core:testing"
import "vendor:sdl3"
import alicorn "../../runtime"

@(test)
test_postmortem_event_names_are_bounded_and_path_free :: proc(t: ^testing.T) {
	testing.expect(t, native_breadcrumb_event_name_valid("directory.open.requested"), "application event names should accept dotted identifiers")
	testing.expect(t, native_breadcrumb_event_name_valid("dialog.callback_queued-1"), "event names should accept supported separators")
	testing.expect(t, !native_breadcrumb_event_name_valid("C:\\Users\\secret"), "event names must reject path separators")
	testing.expect(t, !native_breadcrumb_event_name_valid("event\"injection"), "event names must reject JSON syntax")
	too_long, too_long_error := strings.repeat("a", 97)
	if too_long_error == nil {
		testing.expect(t, !native_breadcrumb_event_name_valid(too_long), "event names must have a bounded length")
		delete(too_long)
	} else {
		testing.expect(t, false, "long identifier test input should allocate")
	}
}

@(test)
test_postmortem_event_line_has_correlation_and_no_payload_fields :: proc(t: ^testing.T) {
	line := native_breadcrumb_json_line("2026-10-29T12:00:00.000Z", 1234, 77, "application", "directory.open.requested", 9)
	testing.expect(t, strings.has_prefix(line, `{"schema":1,`), "breadcrumb line should be valid JSON without formatter diagnostics")
	testing.expect(t, strings.has_suffix(line, "}\n"), "breadcrumb line should end with one complete JSON object")
	testing.expect(t, !strings.contains(line, "%!("), "breadcrumb line should not contain formatter diagnostics")
	testing.expect(t, strings.contains(line, `"timestamp_utc":"2026-10-29T12:00:00.000Z"`), "breadcrumb line should include UTC time")
	testing.expect(t, strings.contains(line, `"monotonic_ns":1234`), "breadcrumb line should include monotonic time")
	testing.expect(t, strings.contains(line, `"thread_id":77`), "breadcrumb line should include its thread")
	testing.expect(t, strings.contains(line, `"request_id":9`), "breadcrumb line should preserve request correlation")
	testing.expect(t, !strings.contains(line, "path"), "breadcrumb line should not include path or arbitrary payload fields")
	testing.expect(t, line[len(line)-1] == '\n', "each breadcrumb should be one JSONL record")
}

@(test)
test_postmortem_motion_visibility_snapshot_captures_runtime_and_scheduler_state :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 120})
	defer alicorn.destroy_runtime(&rt)
	scheduler := Native_Motion_Scheduler_State{
		active=true,
		suspended=true,
		suspended_since_ns=500,
		next_deadline_ns=0,
		stats=Native_Motion_Scheduler_Stats{
			samples=7,
			timer_wakes=6,
			hidden_active_observations=2,
		},
	}
	activity := alicorn.Motion_Activity{active_owners=1, active_properties=1}
	line := native_breadcrumb_motion_window_json_line(
		"2026-10-31T12:00:00.000Z", 900, 77, "motion.window.suspended", 3,
		sdl3.WindowFlags{}, false, true, 12, &scheduler, &rt, activity,
	)
	testing.expect(t, strings.has_prefix(line, `{"schema":1,`), "motion visibility breadcrumb should be valid bounded JSONL")
	testing.expect(t, strings.contains(line, `"window":{"id":3,"renderable":false,"hidden":false,"minimized":false,"native_minimized":true`),
		"the event should distinguish native minimization from SDL's cached flags")
	testing.expect(t, strings.contains(line, `"runtime":{"active_owners":1,"active_properties":1`),
		"the event should record active runtime responses at suspension")
	testing.expect(t, strings.contains(line, `"scheduler":{"active":true,"suspended":true,"suspended_since_ns":500,"next_deadline_ns":0,"samples":7,"timer_wakes":6`),
		"the event should record suspension, the dropped deadline, and the motion sample counter")
	testing.expect(t, strings.contains(line, `"hidden_active_observations":2`),
		"the event should show hidden checks that observed active motion without sampling")
	testing.expect(t, strings.contains(line, `"host_gpu_submissions":12`),
		"the event should record the host submission counter for hidden-interval comparison")
	testing.expect(t, strings.has_suffix(line, "}\n") && !strings.contains(line, "%!("),
		"the motion snapshot should be one complete JSONL record without format errors")
}
