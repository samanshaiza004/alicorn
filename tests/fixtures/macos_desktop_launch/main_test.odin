package main

import "core:testing"

@(test)
test_desktop_validation_result_is_valid_json :: proc(t: ^testing.T) {
	expected := "{\"runId\":\"run-1\",\"pointerActivations\":1,\"keyboardActivations\":1}\n"
	got := desktop_validation_result_json("run-1", 1, 1)
	testing.expect(t, got == expected,
		"desktop fixture must write a parseable result with both activation counters")
}
