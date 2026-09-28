package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_devtools_sample_reports_runtime_work_since_cursor :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200})
	defer alicorn.destroy_runtime(&rt)
	timing := Native_Host_Timing{}
	text_events := Native_Text_Event_Telemetry{}
	cursor := native_devtools_cursor_init(&rt, &timing, &text_events)

	rt.stats.frames_built = 2
	rt.stats.layout_nodes_visited = 7
	rt.stats.nodes_created = 3
	rt.stats.descriptions_emitted = 9
	rt.stats.regions_skipped = 2
	rt.stats.retained_subtrees_reused = 2
	rt.presentation_revision = 4
	rt.allocation_stats.persistent_alloc_calls += 5
	rt.allocation_stats.persistent_requested_bytes_live = 640
	rt.allocation_stats.scratch_requested_bytes_epoch = 128
	timing.application_build_ns = 850
	timing.application_stabilization_rebuilds = 1
	events := alicorn.Cause_Context{id=19, kind=.Keyboard}
	sample := native_devtools_make_sample(&cursor, &rt, &timing, &text_events, events, 1234)
	testing.expect(t, sample.timestamp_ns == 1234 && sample.cause_id == 19 && sample.cause_kind == .Keyboard,
		"sample should retain its timestamp and semantic cause")
	testing.expect(t, sample.app_builds == 2 && sample.build_ns == 850 && sample.stabilization_rebuilds == 1,
		"sample should contain cumulative-counter deltas since the cursor")
	testing.expect(t, sample.layout_visits == 7 && sample.nodes_created == 3 && sample.presentation_updates == 4,
		"sample should preserve stage, node, and presentation work counts")
	testing.expect(t, sample.descriptions_emitted == 9 && sample.regions_skipped == 2 && sample.retained_subtrees_reused == 2,
		"sample should preserve description and retained-region work")
	testing.expect(t, sample.persistent_allocations == 5 && sample.persistent_bytes_live == 640 && sample.scratch_requested_bytes == 128,
		"sample should preserve bounded allocator telemetry")
	testing.expect(t, native_devtools_observed_wake(&cursor, sample, &timing, &text_events),
		"new retained work should be recognized as an observed wake")
}

@(test)
test_devtools_recorder_skips_internal_idle_refreshes :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 100, 100})
	defer alicorn.destroy_runtime(&rt)
	timing := Native_Host_Timing{}
	text_events := Native_Text_Event_Telemetry{}
	cursor := native_devtools_cursor_init(&rt, &timing, &text_events)
	recorder: Native_Flight_Recorder

	native_devtools_record_wake(&recorder, &cursor, &rt, &timing, &text_events,
		alicorn.Cause_Context{kind=.Host_Event}, 100, host_wakes=0)
	testing.expect(t, native_flight_sample_count(&recorder) == 0,
		"HUD idle/counter-expiry timer wakes should not become fake application flight samples")

	text_events.events_received_sequence = 1
	testing.expect(t, native_devtools_observed_wake(&cursor, {}, &timing, &text_events),
		"a real SDL event must be distinguishable from a HUD-only timer wake")
}
