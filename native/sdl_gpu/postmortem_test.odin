package alicorn_sdl_gpu

import "core:strings"
import "core:testing"

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
	testing.expect(t, strings.contains(line, `"timestamp_utc":"2026-10-29T12:00:00.000Z"`), "breadcrumb line should include UTC time")
	testing.expect(t, strings.contains(line, `"monotonic_ns":1234`), "breadcrumb line should include monotonic time")
	testing.expect(t, strings.contains(line, `"thread_id":77`), "breadcrumb line should include its thread")
	testing.expect(t, strings.contains(line, `"request_id":9`), "breadcrumb line should preserve request correlation")
	testing.expect(t, !strings.contains(line, "path"), "breadcrumb line should not include path or arbitrary payload fields")
	testing.expect(t, line[len(line)-1] == '\n', "each breadcrumb should be one JSONL record")
}
