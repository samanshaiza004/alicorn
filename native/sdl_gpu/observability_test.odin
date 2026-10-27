package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
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
test_diagnostics_path_join_preserves_existing_trailing_separator :: proc(t: ^testing.T) {
	testing.expect(
		t,
		native_diagnostics_path_join("/Users/test/Alicorn Diagnostics/", "capture") ==
			"/Users/test/Alicorn Diagnostics/capture",
		"SDL preference paths that already end in a separator must not produce a doubled slash",
	)
	testing.expect(t, native_diagnostics_path_join("/", "capture") == "/capture",
		"joining below the filesystem root should preserve its single separator")
	testing.expect(t, native_diagnostics_path_join("C:\\Users\\test\\", "capture") == "C:\\Users\\test\\capture",
		"Windows paths with a trailing backslash should not gain a second separator")
}

@(test)
test_diagnostics_capture_bundles_do_not_overwrite_same_millisecond :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "alicorn-diagnostics-test-*", context.temp_allocator)
	if err != nil {
		testing.expect(t, false, "could not create a temporary diagnostics directory")
		return
	}
	defer _ = os.remove_all(root)
	first, first_sequence, first_ok, first_failure := native_diagnostics_create_bundle(root, "20260928T123456.789Z", 1)
	second, second_sequence, second_ok, second_failure := native_diagnostics_create_bundle(root, "20260928T123456.789Z", 1)
	testing.expect(t, first_ok && second_ok, "both repeated captures should allocate independent bundle directories")
	testing.expect(t, first_failure == "" && second_failure == "", "successful bundle creation should not report an error")
	testing.expect(t, first_sequence == 1 && second_sequence == 2 && first != second,
		"a sequence suffix should resolve timestamp collisions without overwriting an earlier bundle")
}

@(test)
test_diagnostics_default_capture_dir_is_app_specific_and_absolute :: proc(t: ^testing.T) {
	directory, failure := native_diagnostics_default_capture_dir()
	if directory != "" { defer delete(directory) }
	testing.expect(t, directory != "", "default diagnostics location should resolve")
	testing.expect(t, failure == "", "SDL's preferred diagnostics location should resolve without a fallback")
	testing.expect(t, os.is_absolute_path(directory), "default diagnostics location must not depend on the working directory")
	testing.expect(t, strings.contains(directory, NATIVE_DIAGNOSTICS_APPLICATION),
		"default diagnostics output should use the dedicated app-specific SDL preference directory")
	testing.expect(t, directory != "out/diagnostics", "default diagnostics output must not use a repository-relative path")
}

@(test)
test_diagnostics_capture_dir_override_is_preserved :: proc(t: ^testing.T) {
	args := [2]string{"alicorn", "--capture-dir=/tmp/alicorn-diagnostics-explicit"}
	directory, overridden := native_diagnostics_capture_dir_override(args[:], "/user/data/Alicorn/diagnostics")
	testing.expect(t, overridden, "--capture-dir should select the caller-provided output directory")
	testing.expect(t, directory == "/tmp/alicorn-diagnostics-explicit", "the explicit capture directory should be preserved verbatim")
}

@(test)
test_diagnostics_capture_failure_reports_cause_and_consumes_request :: proc(t: ^testing.T) {
	root, err := os.make_directory_temp("", "alicorn-diagnostics-failure-test-*", context.temp_allocator)
	if err != nil {
		testing.expect(t, false, "could not create a temporary diagnostics directory")
		return
	}
	defer _ = os.remove_all(root)
	blocked_path := fmt.tprintf("%s/capture-root-file", root)
	if write_err := os.write_entire_file(blocked_path, "not a directory"); write_err != nil {
		testing.expect(t, false, "could not create the file used to block capture directory creation")
		return
	}
	_, _, created, failure := native_diagnostics_create_bundle(blocked_path, "20260928T123456.789Z", 1)
	testing.expect(t, !created, "a regular file cannot be used as a capture directory")
	testing.expect(t, failure != "", "bundle creation failure should preserve the underlying filesystem error")

	options := Native_Diagnostics_Options{
		enabled=true,
		capture_requested=true,
		capture_dir=blocked_path,
	}
	native_diagnostics_capture_failed(&options, blocked_path, failure, automatic_due=true)
	testing.expect(t, !options.capture_requested, "failed manual capture request should be consumed rather than retried every loop")
	testing.expect(t, options.automatic_capture_done, "failed automatic capture should be latched")
	should_retry_automatically := options.enabled && !options.automatic_capture_done
	testing.expect(t, !should_retry_automatically, "automatic failure must not produce an endless retry loop")
}
