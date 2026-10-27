package main

import "core:testing"

@(test)
test_desktop_validation_result_is_valid_json :: proc(t: ^testing.T) {
	expected := "{\"runId\":\"run-1\",\"pointerActivations\":1,\"keyboardActivations\":1}\n"
	got := desktop_validation_result_json("run-1", 1, 1)
	testing.expect(
		t,
		got == expected,
		"desktop validation result must be parseable JSON without formatter diagnostics",
	)
}
