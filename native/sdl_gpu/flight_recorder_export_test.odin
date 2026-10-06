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
		semantic_descriptions_emitted = 5,
		semantic_entities_resolved = 3,
		semantic_structure_changes = 1,
		semantic_property_changes = 2,
		semantic_projection_nodes_added = 1,
		semantic_projection_nodes_updated = 2,
		semantic_projection_nodes_removed = 1,
		accessibility_action_wakes = 1,
		accessibility_reveal_wakes = 2,
		accessibility_requests_received = 3,
		accessibility_requests_dropped = 1,
		semantic_focus_search_visits = 4,
		semantic_active_update_visits = 9,
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
	testing.expect(t, strings.contains(json, `"semantic_descriptions_emitted": 5`) &&
		strings.contains(json, `"semantic_entities_resolved": 3`) &&
		strings.contains(json, `"semantic_structure_changes": 1`) &&
		strings.contains(json, `"semantic_property_changes": 2`),
		"timeline exports backend-neutral semantic description and delta counters")
	testing.expect(t, strings.contains(json, `"semantic_projection_nodes_added": 1`) &&
		strings.contains(json, `"semantic_projection_nodes_updated": 2`) &&
		strings.contains(json, `"semantic_projection_nodes_removed": 1`) &&
		strings.contains(json, `"accessibility_action_wakes": 1`) &&
		strings.contains(json, `"accessibility_reveal_wakes": 2`) &&
		strings.contains(json, `"accessibility_requests_received": 3`) &&
		strings.contains(json, `"accessibility_requests_dropped": 1`),
		"timeline exports semantic working-set projection and assistive-action telemetry")
	testing.expect(t, strings.contains(json, `"semantic_focus_search_visits": 4`) &&
		strings.contains(json, `"semantic_active_update_visits": 9`),
		"timeline exports the two independently instrumented semantic-focus scans")
}
