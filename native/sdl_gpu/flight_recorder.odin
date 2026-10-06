package alicorn_sdl_gpu

import alicorn "../../runtime"

// Native_Flight_Recorder stores a short, fixed-size history of host/runtime
// work. Writes overwrite the oldest sample once the ring is full. The storage
// is inline so recording and reading never allocate or move existing samples.
NATIVE_FLIGHT_RECORDER_CAPACITY :: 256

Native_DevTools_Sample :: struct {
	timestamp_ns, cause_id: u64,
	build_ns, encode_ns, submit_ns, input_to_submit_ns: u64,
	app_builds, stabilization_rebuilds, host_wakes: u64,
	pointer_events, hover_target_transitions: u64,
	presentation_updates, gpu_submissions, surface_updates: u64,
	descriptions_emitted, descriptions_reused, regions_skipped, retained_subtrees_reused: u64,
	reconcile_visits, layout_visits, paint_visits, composition_visits: u64,
	nodes_created, nodes_retired: u64,
	semantic_descriptions_emitted, semantic_entities_resolved: u64,
	semantic_structure_changes, semantic_property_changes: u64,
	semantic_projection_nodes_added, semantic_projection_nodes_updated, semantic_projection_nodes_removed: u64,
	accessibility_activation_wakes, accessibility_action_wakes, accessibility_reveal_wakes, accessibility_updates_submitted: u64,
	accessibility_requests_received, accessibility_requests_dropped: u64,
	semantic_focus_search_visits, semantic_active_update_visits: u64,
	persistent_allocations, persistent_bytes_live, scratch_requested_bytes: u64,
	cause_kind: alicorn.Cause_Kind,
}

Native_DevTools_Activity_Class :: enum {
	Idle,
	Host,
	Present,
	App,
	Surface,
}

Native_Flight_Recorder :: struct {
	samples: [NATIVE_FLIGHT_RECORDER_CAPACITY]Native_DevTools_Sample,
	next_index: int,
	count: int,
	sequence: u64,
}

// Records one sample without allocation or shifting. Sequence is a recorder-
// wide count of all writes, including samples later overwritten by the ring.
native_flight_record :: proc(rec: ^Native_Flight_Recorder, sample: Native_DevTools_Sample) {
	if rec == nil { return }
	rec.samples[rec.next_index] = sample
	rec.next_index = (rec.next_index + 1) % NATIVE_FLIGHT_RECORDER_CAPACITY
	if rec.count < NATIVE_FLIGHT_RECORDER_CAPACITY { rec.count += 1 }
	rec.sequence += 1
}

// Returns the sample at a logical oldest-to-newest index. An index outside the
// retained history, or a nil recorder, returns a zero value and false.
native_flight_sample_at :: proc(rec: ^Native_Flight_Recorder, logical_index: int) -> (Native_DevTools_Sample, bool) {
	if rec == nil || logical_index < 0 || logical_index >= rec.count {
		return {}, false
	}
	oldest_index := (rec.next_index - rec.count + NATIVE_FLIGHT_RECORDER_CAPACITY) % NATIVE_FLIGHT_RECORDER_CAPACITY
	physical_index := (oldest_index + logical_index) % NATIVE_FLIGHT_RECORDER_CAPACITY
	return rec.samples[physical_index], true
}

native_flight_sample_count :: proc(rec: ^Native_Flight_Recorder) -> int {
	if rec == nil { return 0 }
	return rec.count
}

// Returns the total number of successful record calls, not just the retained
// sample count. It is useful as a monotonic change marker for UI/export code.
native_flight_sequence :: proc(rec: ^Native_Flight_Recorder) -> u64 {
	if rec == nil { return 0 }
	return rec.sequence
}
