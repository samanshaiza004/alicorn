package alicorn_sdl_gpu

import alicorn "../../runtime"

// Native_Flight_Recorder stores a short, fixed-size history of host/runtime
// work. Writes overwrite the oldest sample once the ring is full. The storage
// is inline so recording and reading never allocate or move existing samples.
NATIVE_FLIGHT_RECORDER_CAPACITY :: 256
NATIVE_POINTER_EVENT_CAPACITY :: 256

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
	measure_requests, measure_cache_hits, measure_cache_misses, text_shape_requests: u64,
	persistent_allocations, persistent_bytes_live, scratch_requested_bytes: u64,
	cause_kind: alicorn.Cause_Kind,
}

// Native_Pointer_Event_Sample records the event-time details missing from
// wake-level work samples. It is fixed-size and allocation-free so diagnostics
// do not change the pointer path they are observing.
Native_Pointer_Event_Sample :: struct {
	sequence, timestamp_ns, cause_id: u64,
	kind: alicorn.Pointer_Kind,
	window_x, window_y, x, y: f32,
	inside_application: bool,
	button: int,
	target: alicorn.Node_ID,
	target_kind: alicorn.Node_Kind,
	target_valid: bool,
	captured_before, captured_after: alicorn.Node_ID,
	captured_before_kind, captured_after_kind: alicorn.Node_Kind,
	captured_before_valid, captured_after_valid: bool,
	split_owner: alicorn.Node_ID,
	split_position_before, split_position_after: f32,
	split_dragging_before, split_dragging_after: bool,
	split_state_valid: bool,
	callback_available, callback_called: bool,
	pointer_dispatched: bool,
	callback_blocked_by_context_menu, callback_blocked_by_drag: bool,
	invalidated, layout_pending, presentation_pending: bool,
	presentation_revision, submitted_revision: u64,
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
	pointer_events: [NATIVE_POINTER_EVENT_CAPACITY]Native_Pointer_Event_Sample,
	pointer_next_index: int,
	pointer_count: int,
	pointer_sequence: u64,
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

native_flight_pointer_record :: proc(rec: ^Native_Flight_Recorder, sample: Native_Pointer_Event_Sample) {
	if rec == nil { return }
	rec.pointer_sequence += 1
	recorded := sample
	recorded.sequence = rec.pointer_sequence
	rec.pointer_events[rec.pointer_next_index] = recorded
	rec.pointer_next_index = (rec.pointer_next_index + 1) % NATIVE_POINTER_EVENT_CAPACITY
	if rec.pointer_count < NATIVE_POINTER_EVENT_CAPACITY { rec.pointer_count += 1 }
}

native_flight_pointer_sample_at :: proc(rec: ^Native_Flight_Recorder, logical_index: int) -> (Native_Pointer_Event_Sample, bool) {
	if rec == nil || logical_index < 0 || logical_index >= rec.pointer_count { return {}, false }
	oldest_index := (rec.pointer_next_index - rec.pointer_count + NATIVE_POINTER_EVENT_CAPACITY) % NATIVE_POINTER_EVENT_CAPACITY
	physical_index := (oldest_index + logical_index) % NATIVE_POINTER_EVENT_CAPACITY
	return rec.pointer_events[physical_index], true
}

native_flight_pointer_sample_count :: proc(rec: ^Native_Flight_Recorder) -> int {
	if rec == nil { return 0 }
	return rec.pointer_count
}

native_flight_pointer_split_state :: proc(
	rt: ^alicorn.Runtime,
	id: alicorn.Node_ID,
) -> (owner_id: alicorn.Node_ID, position: f32, dragging, found: bool) {
	if rt == nil || id == 0 { return }
	node, node_ok := alicorn.node_info(rt, id)
	if !node_ok { return }
	if node.kind == .Split {
		return node.id, node.split_position, node.split_dragging, true
	}
	if node.kind != .Split_Handle || node.split_owner == 0 { return }
	owner, owner_ok := alicorn.node_info(rt, node.split_owner)
	if !owner_ok || owner.kind != .Split { return }
	return owner.id, owner.split_position, owner.split_dragging, true
}
