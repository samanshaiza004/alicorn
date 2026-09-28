package alicorn_sdl_gpu

import "core:os"
import "core:testing"
import "core:time"

@(test)
test_diagnostics_capture_timestamp_is_utc_and_filename_safe :: proc(t: ^testing.T) {
	moment := time.unix(0, 123_456_789)
	stamp, iso, ok := native_diagnostics_timestamp(moment)
	testing.expect(t, ok, "a valid Unix timestamp should convert to UTC diagnostics metadata")
	testing.expect(t, stamp == "19700101T000000.123Z", "directory timestamp should be UTC and safe on Windows")
	testing.expect(t, iso == "1970-01-01T00:00:00.123Z", "JSON timestamp should use an unambiguous UTC ISO form")
}

@(test)
test_diagnostics_capture_bundles_do_not_overwrite_same_millisecond :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "alicorn-diagnostics-test-*", context.temp_allocator)
	if err != nil {
		testing.expect(t, false, "could not create a temporary diagnostics directory")
		return
	}
	defer _ = os.remove_all(root)
	first, first_sequence, first_ok := native_diagnostics_create_bundle(root, "20260928T123456.789Z", 1)
	second, second_sequence, second_ok := native_diagnostics_create_bundle(root, "20260928T123456.789Z", 1)
	testing.expect(t, first_ok && second_ok, "both repeated captures should allocate independent bundle directories")
	testing.expect(t, first_sequence == 1 && second_sequence == 2 && first != second,
		"a sequence suffix should resolve timestamp collisions without overwriting an earlier bundle")
}
