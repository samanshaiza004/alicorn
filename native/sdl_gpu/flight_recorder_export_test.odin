package alicorn_sdl_gpu

import "core:testing"
import "core:strings"
import alicorn "../../runtime"

@(test)
test_native_flight_timeline_is_versioned_and_oldest_first :: proc(t: ^testing.T) {
	recorder: Native_Flight_Recorder
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns = 100,
		cause_id = 7,
		cause_kind = .Keyboard,
		app_builds = 1,
		pointer_events = 3,
		hover_target_transitions = 2,
		layout_visits = 4,
		retained_subtrees_reused = 3,
		persistent_allocations = 2,
		persistent_bytes_live = 640,
		scratch_requested_bytes = 128,
		build_ns = 900,
		input_to_submit_ns = 1_200,
	})
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns = 200,
		cause_id = 8,
		cause_kind = .Async_Wake,
		gpu_submissions = 1,
		submit_ns = 300,
	})
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns = 300,
		cause_id = 9,
		cause_kind = .Host_Event,
		host_wakes = 1,
		pointer_events = 7,
	})

	json := native_flight_timeline_json(&recorder)
	defer delete(json)
	first := strings.index(json, `"timestamp_ns": 100`)
	second := strings.index(json, `"timestamp_ns": 200`)
	third := strings.index(json, `"timestamp_ns": 300`)
	testing.expect(t, !strings.contains(json, "%!") && json[0] == '{' && json[len(json)-2] == '}',
		"timeline JSON should contain no formatter diagnostics and have valid outer braces")
	testing.expect(t, strings.contains(json, `"schema": 1`) && strings.contains(json, `"kind": "alicorn-flight-recorder"`),
		"timeline export identifies its versioned schema")
	testing.expect(t, strings.contains(json, `"timestamp_clock": "monotonic"`) && strings.contains(json, `"sample_count": 3`),
		"timeline export declares monotonic time and includes the bounded sample count")
	testing.expect(t, first >= 0 && second > first && third > second,
		"timeline samples preserve the recorder's oldest-to-newest ordering")
	testing.expect(t, strings.contains(json, `"activity_class": "app"`) && strings.contains(json, `"activity_class": "host"`),
		"timeline exports a machine-readable activity classification per sample")
	testing.expect(t, strings.contains(json, `"pointer_events": 3`) && strings.contains(json, `"hover_target_transitions": 2`),
		"timeline preserves raw pointer and hover-transition evidence")
	testing.expect(t, strings.contains(json, `"kind": "keyboard"`) && strings.contains(json, `"input_to_submit": 1200`),
		"timeline exports semantic causes and responsiveness timing")
	testing.expect(t, strings.contains(json, `"gpu_submissions": 1`) && strings.contains(json, `"gpu_submit": 300`),
		"timeline exports work counters and stage timings")
	testing.expect(t, strings.contains(json, `"retained_subtrees_reused": 3`) && strings.contains(json, `"persistent_allocations": 2`),
		"timeline exports retained reuse and allocator deltas")
	testing.expect(t, strings.contains(json, `"persistent_bytes_live": 640`) && strings.contains(json, `"scratch_requested_bytes": 128`),
		"timeline exports allocator live and scratch byte telemetry")
}
