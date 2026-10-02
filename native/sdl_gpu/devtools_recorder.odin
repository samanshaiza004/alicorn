package alicorn_sdl_gpu

import alicorn "../../runtime"

Native_DevTools_Renderer_Metrics :: struct {
	text_atlas_uploads, text_atlas_upload_bytes, text_mesh_rebuilds, text_mesh_cache_hits, text_vertex_uploads: u64,
	// Mirrors the cumulative Native_Text_Renderer fields fingerprint_ns,
	// fingerprint_bytes, and mesh_rebuild_ns; the renderer owns their updates.
	text_fingerprint_ns, text_fingerprint_bytes, text_mesh_rebuild_ns: u64,
	surface_resource_creations, surface_vertex_uploads, surface_encodes: u64,
	solid_batches, solid_vertices_uploaded: u64,
}

native_devtools_renderer_metrics_capture :: proc(
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
) -> Native_DevTools_Renderer_Metrics {
	if text_renderer == nil || surface_renderer == nil || solid_renderer == nil { return {} }
	return Native_DevTools_Renderer_Metrics{
		text_atlas_uploads=text_renderer.atlas_uploads,
		text_atlas_upload_bytes=text_renderer.atlas_upload_bytes,
		text_mesh_rebuilds=text_renderer.mesh_rebuilds,
		text_mesh_cache_hits=text_renderer.mesh_cache_hits,
		text_fingerprint_ns=text_renderer.fingerprint_ns,
		text_fingerprint_bytes=text_renderer.fingerprint_bytes,
		text_mesh_rebuild_ns=text_renderer.mesh_rebuild_ns,
		text_vertex_uploads=text_renderer.vertex_uploads,
		surface_resource_creations=surface_renderer.resource_creations,
		surface_vertex_uploads=surface_renderer.vertex_uploads,
		surface_encodes=surface_renderer.encodes,
		solid_batches=solid_renderer.batches,
		solid_vertices_uploaded=solid_renderer.vertices_uploaded,
	}
}

native_devtools_renderer_metrics_restore :: proc(
	text_renderer: ^Native_Text_Renderer,
	surface_renderer: ^Native_Surface_Renderer,
	solid_renderer: ^Native_Solid_Renderer,
	metrics: Native_DevTools_Renderer_Metrics,
) {
	if text_renderer == nil || surface_renderer == nil || solid_renderer == nil { return }
	text_renderer.atlas_uploads = metrics.text_atlas_uploads
	text_renderer.atlas_upload_bytes = metrics.text_atlas_upload_bytes
	text_renderer.mesh_rebuilds = metrics.text_mesh_rebuilds
	text_renderer.mesh_cache_hits = metrics.text_mesh_cache_hits
	text_renderer.fingerprint_ns = metrics.text_fingerprint_ns
	text_renderer.fingerprint_bytes = metrics.text_fingerprint_bytes
	text_renderer.mesh_rebuild_ns = metrics.text_mesh_rebuild_ns
	text_renderer.vertex_uploads = metrics.text_vertex_uploads
	surface_renderer.resource_creations = metrics.surface_resource_creations
	surface_renderer.vertex_uploads = metrics.surface_vertex_uploads
	surface_renderer.encodes = metrics.surface_encodes
	solid_renderer.batches = metrics.solid_batches
	solid_renderer.vertices_uploaded = metrics.solid_vertices_uploaded
}

// Native_DevTools_Cursor captures the cumulative counters at the last recorder
// boundary. Samples therefore describe only work since the previous host wake.
Native_DevTools_Cursor :: struct {
	stats: alicorn.Frame_Stats,
	presentation_revision: u64,
	application_build_ns: u64,
	application_gpu_encode_ns: u64,
	gpu_submit_ns: u64,
	stabilization_rebuilds: u64,
	persistent_allocations: u64,
	input_to_submit_sequence: u64,
	events_received_sequence: u64,
	application_tick_calls: u64,
	scheduled_wakes: u64,
}

native_devtools_cursor_init :: proc(
	rt: ^alicorn.Runtime,
	timing: ^Native_Host_Timing,
	text_events: ^Native_Text_Event_Telemetry,
) -> Native_DevTools_Cursor {
	if rt == nil || timing == nil || text_events == nil { return {} }
	return Native_DevTools_Cursor{
		stats=rt.stats,
		presentation_revision=rt.presentation_revision,
		application_build_ns=timing.application_build_ns,
		application_gpu_encode_ns=timing.application_gpu_encode_ns,
		gpu_submit_ns=timing.gpu_submit_ns,
		stabilization_rebuilds=timing.application_stabilization_rebuilds,
		persistent_allocations=rt.allocation_stats.persistent_alloc_calls if rt.allocation_stats != nil else 0,
		input_to_submit_sequence=text_events.input_to_submit_sequence,
		events_received_sequence=text_events.events_received_sequence,
		application_tick_calls=timing.application_tick_calls,
		scheduled_wakes=timing.scheduled_wakes,
	}
}

native_devtools_make_sample :: proc(
	cursor: ^Native_DevTools_Cursor,
	rt: ^alicorn.Runtime,
	timing: ^Native_Host_Timing,
	text_events: ^Native_Text_Event_Telemetry,
	cause: alicorn.Cause_Context,
	timestamp_ns: u64,
	host_wakes: u64 = 0,
) -> Native_DevTools_Sample {
	if cursor == nil || rt == nil || timing == nil || text_events == nil { return {} }
	current := rt.stats
	previous := cursor.stats
	sample := Native_DevTools_Sample{
		timestamp_ns=timestamp_ns,
		cause_id=cause.id,
		cause_kind=cause.kind,
		build_ns=timing.application_build_ns-cursor.application_build_ns,
		encode_ns=timing.application_gpu_encode_ns-cursor.application_gpu_encode_ns,
		host_wakes=host_wakes,
		pointer_events=current.pointer_events-previous.pointer_events,
		hover_target_transitions=current.hover_target_transitions-previous.hover_target_transitions,
		app_builds=current.frames_built-previous.frames_built,
		stabilization_rebuilds=timing.application_stabilization_rebuilds-cursor.stabilization_rebuilds,
		presentation_updates=rt.presentation_revision-cursor.presentation_revision,
		surface_updates=current.surface_updates-previous.surface_updates,
		descriptions_emitted=current.descriptions_emitted-previous.descriptions_emitted,
		descriptions_reused=current.descriptions_reused-previous.descriptions_reused,
		regions_skipped=current.regions_skipped-previous.regions_skipped,
		retained_subtrees_reused=current.retained_subtrees_reused-previous.retained_subtrees_reused,
		reconcile_visits=current.reconcile_nodes_visited-previous.reconcile_nodes_visited,
		layout_visits=current.layout_nodes_visited-previous.layout_nodes_visited,
		paint_visits=current.paint_nodes_visited-previous.paint_nodes_visited,
		composition_visits=current.composition_nodes_visited-previous.composition_nodes_visited,
		nodes_created=current.nodes_created-previous.nodes_created,
		nodes_retired=current.nodes_retired-previous.nodes_retired,
	}
	if rt.allocation_stats != nil {
		sample.persistent_allocations = rt.allocation_stats.persistent_alloc_calls-cursor.persistent_allocations
		if rt.allocation_stats.persistent_requested_bytes_live > 0 {
			sample.persistent_bytes_live = u64(rt.allocation_stats.persistent_requested_bytes_live)
		}
		sample.scratch_requested_bytes = rt.allocation_stats.scratch_requested_bytes_epoch
	}
	return sample
}

native_devtools_observed_wake :: proc(
	cursor: ^Native_DevTools_Cursor,
	sample: Native_DevTools_Sample,
	timing: ^Native_Host_Timing,
	text_events: ^Native_Text_Event_Telemetry,
) -> bool {
	if cursor == nil || timing == nil || text_events == nil { return false }
	return sample.app_builds > 0 || sample.presentation_updates > 0 || sample.gpu_submissions > 0 ||
		sample.surface_updates > 0 || sample.reconcile_visits > 0 || sample.layout_visits > 0 ||
		sample.paint_visits > 0 || sample.composition_visits > 0 || sample.nodes_created > 0 ||
		sample.nodes_retired > 0 || sample.pointer_events > 0 || sample.hover_target_transitions > 0 ||
		sample.persistent_allocations > 0 || timing.application_tick_calls != cursor.application_tick_calls ||
		timing.scheduled_wakes != cursor.scheduled_wakes ||
		text_events.events_received_sequence != cursor.events_received_sequence
}

// native_devtools_record_wake appends counter deltas at a host-loop boundary.
// It does not inspect or mutate the retained tree; recording itself is a fixed
// struct copy into the host-owned ring.
native_devtools_record_wake :: proc(
	recorder: ^Native_Flight_Recorder,
	cursor: ^Native_DevTools_Cursor,
	rt: ^alicorn.Runtime,
	timing: ^Native_Host_Timing,
	text_events: ^Native_Text_Event_Telemetry,
	cause: alicorn.Cause_Context,
	timestamp_ns: u64,
	host_wakes: u64 = 0,
) {
	if recorder == nil || cursor == nil || rt == nil || timing == nil || text_events == nil { return }
	sample := native_devtools_make_sample(cursor, rt, timing, text_events, cause, timestamp_ns, host_wakes)
	sample.gpu_submissions = rt.stats.gpu_submits-cursor.stats.gpu_submits
	if sample.gpu_submissions > 0 {
		// SDL submits the command buffer as a whole. With the optional HUD shown,
		// this host call also includes its tiny overlay draw, while the reported
		// GPU-submission count and application render encoding remain app-only.
		sample.submit_ns = timing.gpu_submit_ns-cursor.gpu_submit_ns
	}
	if text_events.input_to_submit_sequence > cursor.input_to_submit_sequence && len(text_events.input_to_submit_samples) > 0 {
		sample.input_to_submit_ns = text_events.input_to_submit_samples[len(text_events.input_to_submit_samples)-1]
	}
	write_sample := sample.host_wakes > 0 || sample.pointer_events > 0 || sample.hover_target_transitions > 0 ||
		sample.app_builds > 0 || sample.presentation_updates > 0 ||
		sample.gpu_submissions > 0 || sample.surface_updates > 0 || sample.reconcile_visits > 0 ||
		sample.layout_visits > 0 || sample.paint_visits > 0 || sample.composition_visits > 0 ||
		sample.nodes_created > 0 || sample.nodes_retired > 0 || sample.persistent_allocations > 0
	if write_sample { native_flight_record(recorder, sample) }
	cursor^ = native_devtools_cursor_init(rt, timing, text_events)
}
