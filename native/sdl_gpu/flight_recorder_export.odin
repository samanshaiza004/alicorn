package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
import alicorn "../../runtime"

// native_flight_cause_name returns stable schema values rather than Odin's
// source-level enum spelling, so captures remain useful across refactors.
native_flight_cause_name :: proc(kind: alicorn.Cause_Kind) -> string {
	switch kind {
	case .None:            return "none"
	case .Pointer:         return "pointer"
	case .Keyboard:        return "keyboard"
	case .Text_Input:      return "text_input"
	case .Text_Composition:return "text_composition"
	case .Scroll:          return "scroll"
	case .Native_Command:  return "native_command"
	case .Async_Wake:      return "async_wake"
	case .Scheduled_Wake:  return "scheduled_wake"
	case .Application:     return "application"
	case .Host_Event:      return "host_event"
	}
	return "unknown"
}

native_flight_pointer_kind_name :: proc(kind: alicorn.Pointer_Kind) -> string {
	switch kind {
	case .Move:   return "move"
	case .Down:   return "down"
	case .Up:     return "up"
	case .Cancel: return "cancel"
	}
	return "unknown"
}

native_flight_node_kind_name :: proc(kind: alicorn.Node_Kind, valid: bool) -> string {
	if !valid { return "none" }
	switch kind {
	case .Root:                 return "root"
	case .Modal_Overlay:        return "modal_overlay"
	case .Context_Menu_Overlay: return "context_menu_overlay"
	case .Context_Menu_Panel:   return "context_menu_panel"
	case .Container:            return "container"
	case .Grid:                 return "grid"
	case .Button:               return "button"
	case .Tab:                  return "tab"
	case .Tab_Close:            return "tab_close"
	case .Checkbox:             return "checkbox"
	case .Slider:               return "slider"
	case .Text:                 return "text"
	case .Text_Field:           return "text_field"
	case .Text_Composition:     return "text_composition"
	case .Virtual_List:         return "virtual_list"
	case .Virtual_Row:          return "virtual_row"
	case .Scroll_Region:        return "scroll_region"
	case .Split:                return "split"
	case .Split_Handle:         return "split_handle"
	case .Custom_Surface:       return "custom_surface"
	}
	return "unknown"
}

// native_flight_timeline_json creates a bounded, versioned export of the
// recorder's oldest-to-newest sample window. It is called only during capture;
// the recorder itself remains allocation-free on the event path.
native_flight_timeline_json :: proc(recorder: ^Native_Flight_Recorder) -> string {
	builder, builder_err := strings.builder_make()
	if builder_err != nil { return "" }
	defer strings.builder_destroy(&builder)

	count := 0
	pointer_count := native_flight_pointer_sample_count(recorder)
	if recorder != nil {
		// Bound enumeration independently of ring metadata so even a corrupted
		// count can never turn a diagnostic capture into unbounded work/output.
		for index := 0; index < NATIVE_FLIGHT_RECORDER_CAPACITY; index += 1 {
			_, ok := native_flight_sample_at(recorder, index)
			if !ok { break }
			count += 1
		}
	}

	fmt.sbprintf(&builder, `{{
  "schema": 1,
  "kind": "alicorn-flight-recorder",
  "timestamp_clock": "monotonic",
  "sample_order": "oldest_to_newest",
  "sample_count": %d,
    "samples": [
`, count)

	for index := 0; index < count; index += 1 {
		sample, ok := native_flight_sample_at(recorder, index)
		if !ok { break }
		comma := ","
		if index == count-1 { comma = "" }
		fmt.sbprintf(&builder, `    {{
      "sample_index": %d,
      "timestamp_ns": %d,
      "cause": {{
        "id": %d,
        "kind": "%s"
      }},
      "activity_class": "%s",
      "work": {{
        "app_builds": %d,
        "stabilization_rebuilds": %d,
        "host_wakes": %d,
        "pointer_events": %d,
        "hover_target_transitions": %d,
        "presentation_updates": %d,
        "gpu_submissions": %d,
        "surface_updates": %d,
        "descriptions_emitted": %d,
        "descriptions_reused": %d,
        "regions_skipped": %d,
        "retained_subtrees_reused": %d,
        "reconcile_visits": %d,
        "layout_visits": %d,
        "paint_visits": %d,
        "composition_visits": %d,
        "nodes_created": %d,
        "nodes_retired": %d,
        "semantic_descriptions_emitted": %d,
        "semantic_entities_resolved": %d,
        "semantic_structure_changes": %d,
        "semantic_property_changes": %d,
        "semantic_projection_nodes_added": %d,
        "semantic_projection_nodes_updated": %d,
        "semantic_projection_nodes_removed": %d,
        "accessibility_activation_wakes": %d,
        "accessibility_action_wakes": %d,
        "accessibility_reveal_wakes": %d,
        "accessibility_updates_submitted": %d,
        "accessibility_requests_received": %d,
        "accessibility_requests_dropped": %d,
        "semantic_focus_search_visits": %d,
        "semantic_active_update_visits": %d,
        "measure_requests": %d,
        "measure_cache_hits": %d,
        "measure_cache_misses": %d,
        "text_shape_requests": %d,
        "persistent_allocations": %d,
        "persistent_bytes_live": %d,
        "scratch_requested_bytes": %d
      }},
      "timing_ns": {{
        "application_build": %d,
        "gpu_encode": %d,
        "gpu_submit": %d,
        "input_to_submit": %d
      }}
    }}%s
`, index, sample.timestamp_ns, sample.cause_id, native_flight_cause_name(sample.cause_kind),
			native_devtools_activity_class_name(native_devtools_activity_class(sample)),
			sample.app_builds, sample.stabilization_rebuilds, sample.host_wakes,
			sample.pointer_events, sample.hover_target_transitions,
			sample.presentation_updates, sample.gpu_submissions, sample.surface_updates,
			sample.descriptions_emitted, sample.descriptions_reused, sample.regions_skipped,
			sample.retained_subtrees_reused,
			sample.reconcile_visits, sample.layout_visits, sample.paint_visits,
			sample.composition_visits, sample.nodes_created, sample.nodes_retired,
			sample.semantic_descriptions_emitted, sample.semantic_entities_resolved,
			sample.semantic_structure_changes, sample.semantic_property_changes,
			sample.semantic_projection_nodes_added, sample.semantic_projection_nodes_updated,
			sample.semantic_projection_nodes_removed, sample.accessibility_activation_wakes,
			sample.accessibility_action_wakes, sample.accessibility_reveal_wakes, sample.accessibility_updates_submitted,
			sample.accessibility_requests_received, sample.accessibility_requests_dropped,
			sample.semantic_focus_search_visits, sample.semantic_active_update_visits,
			sample.measure_requests, sample.measure_cache_hits, sample.measure_cache_misses, sample.text_shape_requests,
			sample.persistent_allocations, sample.persistent_bytes_live, sample.scratch_requested_bytes,
			sample.build_ns, sample.encode_ns, sample.submit_ns, sample.input_to_submit_ns, comma)
	}

	strings.write_string(&builder, `  ],
  "pointer_event_count": `)
	fmt.sbprintf(&builder, "%d,\n  \"pointer_events\": [\n", pointer_count)
	for index := 0; index < pointer_count; index += 1 {
		event, ok := native_flight_pointer_sample_at(recorder, index)
		if !ok { break }
		comma := ","
		if index == pointer_count-1 { comma = "" }
		fmt.sbprintf(&builder, `    {{
      "sequence": %d,
      "timestamp_ns": %d,
      "cause_id": %d,
      "kind": "%s",
      "window_point": {{"x": %.3f, "y": %.3f}},
      "application_point": {{"x": %.3f, "y": %.3f, "inside": %t, "dispatched": %t}},
      "button": %d,
      "target": {{"id": %d, "kind": "%s"}},
      "captured_before": {{"id": %d, "kind": "%s"}},
      "captured_after": {{"id": %d, "kind": "%s"}},
      "split": {{"valid": %t, "owner": %d, "position_before": %.3f, "position_after": %.3f, "dragging_before": %t, "dragging_after": %t}},
      "application_callback": {{"available": %t, "called": %t, "blocked_by_context_menu": %t, "blocked_by_drag": %t}},
      "pending_after": {{"invalidated": %t, "layout": %t, "presentation": %t, "presentation_revision": %d, "submitted_revision": %d}}
    }}%s
`, event.sequence, event.timestamp_ns, event.cause_id, native_flight_pointer_kind_name(event.kind),
			event.window_x, event.window_y, event.x, event.y, event.inside_application, event.pointer_dispatched,
			event.button, event.target, native_flight_node_kind_name(event.target_kind, event.target_valid),
			event.captured_before, native_flight_node_kind_name(event.captured_before_kind, event.captured_before_valid),
			event.captured_after, native_flight_node_kind_name(event.captured_after_kind, event.captured_after_valid),
			event.split_state_valid, event.split_owner, event.split_position_before, event.split_position_after,
			event.split_dragging_before, event.split_dragging_after,
			event.callback_available, event.callback_called, event.callback_blocked_by_context_menu, event.callback_blocked_by_drag,
			event.invalidated, event.layout_pending, event.presentation_pending, event.presentation_revision, event.submitted_revision, comma)
	}
	strings.write_string(&builder, `  ]
}
`)
	// Builder strings alias the builder's buffer, so return an owned copy before
	// the deferred builder_destroy releases that buffer.
	json, clone_err := strings.clone(strings.to_string(builder))
	if clone_err != nil { return "" }
	return json
}

// native_write_flight_timeline writes a capture-local timeline JSON file.
// The caller chooses the bundle path and handles capture naming/metadata.
native_write_flight_timeline :: proc(path: string, recorder: ^Native_Flight_Recorder) -> bool {
	json := native_flight_timeline_json(recorder)
	defer delete(json)
	if len(json) == 0 { return false }
	if err := os.write_entire_file(path, json); err != nil { return false }
	return true
}
