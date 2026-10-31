package alicorn

import "core:fmt"
import "core:sync"

// Retained motion binds analytic responses to a live retained identity. The
// runtime owns only targets and sampled presentation values; application
// state and geometry negotiation remain authoritative outside this sidecar.

// The first native scheduler prototype deliberately exercises the runtime at
// 1, 100, and 1,000 simultaneously active retained records. Keep that capacity
// bounded, but large enough to cover the 1,000-record acceptance workload.
MOTION_RETAINED_MAX_OWNERS :: 1024
MOTION_F32_MAX :: f64(3.4028234663852886e38)
MOTION_DIAGNOSTIC_EVENT_CAPACITY :: 128
// Divide the representable GPU translation range across the maximum retained
// owner count so a fully nested path remains finite in f32 composition.
MOTION_TRANSLATION_COMPONENT_MAX :: MOTION_F32_MAX / f64(MOTION_RETAINED_MAX_OWNERS*2)

@(private)
motion_runtime_identity_sequence: u64

Motion_Owner_Handle :: struct {
	runtime_identity: u64,
	node: Node_ID,
	generation: u64,
}

Motion_Runtime_Status :: enum {
	Ok,
	Invalid_Runtime,
	Invalid_Owner,
	Owner_Not_Retained,
	Stale_Owner,
	Owner_Limit,
	Runtime_Identity_Limit,
	Invalid_Value,
	Invalid_Configuration,
	Time_Rewound,
	Clock_Unavailable,
	Interactive_Reveal_Unsupported,
	Description_Required,
	Owner_Not_Described,
	Numeric_Overflow,
}

// The host tags timestamps explicitly so diagnostics can distinguish injected
// replay time from the native monotonic clock. No predicted-frame clock exists
// in this scheduler yet; native samples are actual host timestamps.
Motion_Clock_Source :: enum { Unknown, Injected, Native_Monotonic }

Motion_Diagnostic_Kind :: enum {
	Target_Declared,
	Retarget,
	Mode_Change,
	Unchanged_Target,
	Reveal,
	Reduced_Motion_Rewrite,
	Release,
	Owner_Retired,
	Settled,
	Host_Suspended,
	Hidden_Gap_Fast_Forward,
	Opacity_Clamp,
	Bounded_Snap,
	Failure,
}

Motion_Diagnostic_Reason :: enum {
	None,
	Reduced_Opacity_Fade_Exceeded_Bound,
}

Motion_Property_Snapshot :: struct {
	has_value: bool,
	active: bool,
	deadline_established: bool,
	mode: Motion_Mode,
	config: Motion_Config,
	target: Motion_Vector2,
	presented: Motion_Vector2,
	residual: Motion_Vector2,
	velocity: Motion_Vector2,
	// sampled_at identifies the retained position sample shown above. Velocity
	// in the same snapshot is evaluated at this timestamp, not the runtime's
	// possibly newer clock-only value.
	sampled_at: Motion_Time,
	start_time: Motion_Time,
	settle_after_ns: u64,
}

// Motion_Diagnostic_Owner_Snapshot is a passive value copy. The inspector may
// format it without sampling the runtime, allocating retained records, or
// requesting a presentation frame.
Motion_Diagnostic_Owner_Snapshot :: struct {
	valid: bool,
	owner: Node_ID,
	generation: u64,
	intent: Motion_Intent,
	source: Source_Site,
	cause: Cause_Context,
	clock_source: Motion_Clock_Source,
	clock_time: Motion_Time,
	translation: Motion_Property_Snapshot,
	opacity: Motion_Property_Snapshot,
}

Motion_Diagnostic_Event :: struct {
	sequence: u64,
	time: Motion_Time,
	clock_source: Motion_Clock_Source,
	kind: Motion_Diagnostic_Kind,
	reason: Motion_Diagnostic_Reason,
	owner: Motion_Diagnostic_Owner_Snapshot,
	status: Motion_Runtime_Status,
	elapsed_ns: u64,
	detail_value: Motion_Vector2,
	repeat_count: u64,
}

Motion_Diagnostic_Stats :: struct {
	intent_declarations: u64,
	declarations_coalesced: u64,
	unchanged_target_noops: u64,
	retargets: u64,
	mode_changes: u64,
	reveals: u64,
	reduced_motion_rewrites: u64,
	releases: u64,
	owners_retired: u64,
	settlements: u64,
	host_suspends: u64,
	hidden_gap_fast_forwards: u64,
	opacity_clamps: u64,
	bounded_snaps: u64,
	failures: u64,
	sample_ticks: u64,
	owner_visits: u64,
	property_samples: u64,
	presentation_requests: u64,
	presentation_requests_coalesced: u64,
	presentation_submissions: u64,
	trace_evictions: u64,
}

Motion_Diagnostics :: struct {
	events: [MOTION_DIAGNOSTIC_EVENT_CAPACITY]Motion_Diagnostic_Event,
	next: int,
	count: int,
	sequence: u64,
	revision: u64,
	stats: Motion_Diagnostic_Stats,
}

// Motion_Presentation is the compositor-facing snapshot for a retained
// owner. Translation is in parent-local logical units. Hit testing,
// accessibility bounds and target layout continue to use target geometry.
Motion_Presentation :: struct {
	target_translation: Motion_Vector2,
	presented_translation: [2]f32,
	target_opacity: f64,
	presented_opacity: f32,
	has_translation: bool,
	has_opacity: bool,
	active: bool,
	deadline_established: bool,
	status: Motion_Runtime_Status,
}

Motion_Tick_Result :: struct {
	active_properties: int,
	active_owners: int,
	unestablished_deadlines: int,
	changed_owners: int,
	status: Motion_Runtime_Status,
}

// Motion_Activity is a read-only view used by the native host to decide
// whether a window needs another presentation opportunity. It does not sample
// responses or request work.
Motion_Activity :: struct {
	active_properties: int,
	active_owners: int,
	unestablished_deadlines: int,
}

Motion_Retained_Owner :: struct {
	generation: u64,
	intent: Motion_Intent,
	source: Source_Site,
	cause: Cause_Context,
	has_translation: bool,
	translation: Motion_Translation_Response,
	presented_translation: [2]f32,
	translation_sampled_at: Motion_Time,
	translation_active: bool,
	translation_deadline_established: bool,
	has_opacity: bool,
	opacity: Motion_Scalar_Response,
	presented_opacity: f32,
	opacity_sampled_at: Motion_Time,
	opacity_active: bool,
	opacity_deadline_established: bool,
	opacity_clamped: bool,
}

// Motion_Intent_Request keeps the ordinary UI wrapper declarative: a request
// made during description is applied after reconciliation, when the retained
// owner and its complete subtree have their current interaction/style state.
Motion_Intent_Request :: struct {
	owner: Node_ID,
	target: Motion_Target,
	intent: Motion_Intent,
	reveal_offset: Motion_Vector2,
	source: Source_Site,
	cause: Cause_Context,
}

Motion_Composition_Values :: struct {
	translation: [2]f32,
	opacity: f32,
}

motion_runtime_status :: proc(status: Motion_Status) -> Motion_Runtime_Status {
	switch status {
	case .Ok: return .Ok
	case .Invalid_Response: return .Invalid_Owner
	case .Invalid_Configuration: return .Invalid_Configuration
	case .Invalid_Value: return .Invalid_Value
	case .Time_Rewound: return .Time_Rewound
	case .Numeric_Overflow: return .Numeric_Overflow
	}
	return .Invalid_Value
}

motion_diagnostics_ensure :: proc(rt: ^Runtime) -> ^Motion_Diagnostics {
	if rt == nil { return nil }
	if rt.motion_diagnostics == nil {
		rt.motion_diagnostics = new(Motion_Diagnostics, allocator=rt.persistent_allocator)
	}
	return rt.motion_diagnostics
}

motion_diagnostics_owner_snapshot :: proc(rt: ^Runtime, owner: Node_ID) -> Motion_Diagnostic_Owner_Snapshot {
	if rt == nil || rt.motion_owners == nil { return {} }
	state, found := rt.motion_owners[owner]
	if !found { return Motion_Diagnostic_Owner_Snapshot{owner=owner} }
	snapshot := Motion_Diagnostic_Owner_Snapshot{
		valid=true,
		owner=owner,
		generation=state.generation,
		intent=state.intent,
		source=state.source,
		cause=state.cause,
		clock_source=rt.motion_clock_source,
		clock_time=rt.motion_time,
	}
	if state.has_translation {
		sample := motion_translation_sample(state.translation, state.translation_sampled_at)
		target := Motion_Vector2{state.translation.x.target, state.translation.y.target}
		presented := Motion_Vector2{f64(state.presented_translation[0]), f64(state.presented_translation[1])}
		snapshot.translation = Motion_Property_Snapshot{
			has_value=true,
			active=state.translation_active,
			deadline_established=state.translation_deadline_established,
			mode=state.translation.x.mode,
			config=state.translation.x.config,
			target=target,
			presented=presented,
			residual=Motion_Vector2{presented.x-target.x, presented.y-target.y},
			velocity=sample.velocity,
			sampled_at=state.translation_sampled_at,
			start_time=state.translation.x.start_time,
			settle_after_ns=state.translation.x.settle_after_ns,
		}
	}
	if state.has_opacity {
		sample := motion_scalar_sample(state.opacity, state.opacity_sampled_at)
		target := Motion_Vector2{state.opacity.target, 0}
		presented := Motion_Vector2{f64(state.presented_opacity), 0}
		snapshot.opacity = Motion_Property_Snapshot{
			has_value=true,
			active=state.opacity_active,
			deadline_established=state.opacity_deadline_established,
			mode=state.opacity.mode,
			config=state.opacity.config,
			target=target,
			presented=presented,
			residual=Motion_Vector2{presented.x-target.x, 0},
			velocity=Motion_Vector2{sample.velocity, 0},
			sampled_at=state.opacity_sampled_at,
			start_time=state.opacity.start_time,
			settle_after_ns=state.opacity.settle_after_ns,
		}
	}
	return snapshot
}

motion_diagnostics_event_count :: proc(rt: ^Runtime) -> int {
	if rt == nil || rt.motion_diagnostics == nil { return 0 }
	return rt.motion_diagnostics.count
}

// newest_index is zero for the newest record. Returned values contain only
// stable scalar data and borrowed call-site strings; reading them is passive.
motion_diagnostics_event_recent :: proc(rt: ^Runtime, newest_index: int) -> (event: Motion_Diagnostic_Event, found: bool) {
	if rt == nil || rt.motion_diagnostics == nil || newest_index < 0 || newest_index >= rt.motion_diagnostics.count {
		return {}, false
	}
	diagnostics := rt.motion_diagnostics
	index := (diagnostics.next-1-newest_index+MOTION_DIAGNOSTIC_EVENT_CAPACITY) % MOTION_DIAGNOSTIC_EVENT_CAPACITY
	return diagnostics.events[index], true
}

motion_diagnostics_stats :: proc(rt: ^Runtime) -> Motion_Diagnostic_Stats {
	if rt == nil || rt.motion_diagnostics == nil { return {} }
	return rt.motion_diagnostics.stats
}

motion_diagnostic_failure :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	status: Motion_Runtime_Status,
	source: Source_Site = {},
	cause: Cause_Context = {},
	component: string = "motion",
	loc := #caller_location,
) -> Motion_Runtime_Status {
	if rt != nil {
		resolved_source := source
		if resolved_source.file == "" && resolved_source.line == 0 {
			resolved_source = Source_Site{loc.file_path, int(loc.line), int(loc.column), component}
		}
		motion_diagnostic_record(rt, .Failure, owner, status, resolved_source, cause, coalesce=true)
	}
	return status
}

motion_diagnostic_record :: proc(
	rt: ^Runtime,
	kind: Motion_Diagnostic_Kind,
	owner: Node_ID = 0,
	status: Motion_Runtime_Status = .Ok,
	source: Source_Site = {},
	cause: Cause_Context = {},
	elapsed_ns: u64 = 0,
	detail_value: Motion_Vector2 = {},
	reason: Motion_Diagnostic_Reason = .None,
	coalesce: bool = false,
	time_override: Motion_Time = Motion_Time(0),
	override_time := false,
) {
	diagnostics := motion_diagnostics_ensure(rt)
	if diagnostics == nil { return }
	diagnostics.revision += 1
	event := Motion_Diagnostic_Event{
		time=time_override if override_time else rt.motion_time,
		clock_source=rt.motion_clock_source,
		kind=kind,
		reason=reason,
		owner=motion_diagnostics_owner_snapshot(rt, owner),
		status=status,
		elapsed_ns=elapsed_ns,
		detail_value=detail_value,
		repeat_count=1,
	}
	if source.file != "" || source.line != 0 { event.owner.source = source }
	if source.file != "" || source.line != 0 || cause.id != 0 || cause.action_id != Action_ID(0) {
		event.owner.cause = cause
	}
	if coalesce && diagnostics.count > 0 {
		last_index := (diagnostics.next-1+MOTION_DIAGNOSTIC_EVENT_CAPACITY) % MOTION_DIAGNOSTIC_EVENT_CAPACITY
		last := &diagnostics.events[last_index]
		same_targets := last.owner.translation.has_value == event.owner.translation.has_value &&
			last.owner.translation.target == event.owner.translation.target &&
			last.owner.translation.mode == event.owner.translation.mode &&
			last.owner.translation.config == event.owner.translation.config &&
			last.owner.opacity.has_value == event.owner.opacity.has_value &&
			last.owner.opacity.target == event.owner.opacity.target &&
			last.owner.opacity.mode == event.owner.opacity.mode &&
			last.owner.opacity.config == event.owner.opacity.config
		if last.kind == event.kind && last.reason == event.reason && last.clock_source == event.clock_source &&
			last.owner.owner == event.owner.owner &&
			last.status == event.status && last.owner.cause == event.owner.cause &&
			last.owner.source.file == event.owner.source.file && last.owner.source.line == event.owner.source.line &&
			last.owner.source.column == event.owner.source.column && last.owner.intent == event.owner.intent &&
			same_targets {
			last.repeat_count += 1
			if kind == .Unchanged_Target { diagnostics.stats.unchanged_target_noops += 1 }
			if kind == .Failure { diagnostics.stats.failures += 1 }
			return
		}
	}
	diagnostics.sequence += 1
	event.sequence = diagnostics.sequence
	diagnostics.events[diagnostics.next] = event
	diagnostics.next = (diagnostics.next+1) % MOTION_DIAGNOSTIC_EVENT_CAPACITY
	if diagnostics.count < MOTION_DIAGNOSTIC_EVENT_CAPACITY { diagnostics.count += 1 }
	else { diagnostics.stats.trace_evictions += 1 }
	switch kind {
	case .Target_Declared: diagnostics.stats.intent_declarations += 1
	case .Retarget: diagnostics.stats.retargets += 1
	case .Mode_Change: diagnostics.stats.mode_changes += 1
	case .Unchanged_Target: diagnostics.stats.unchanged_target_noops += 1
	case .Reveal: diagnostics.stats.reveals += 1
	case .Reduced_Motion_Rewrite: diagnostics.stats.reduced_motion_rewrites += 1
	case .Release: diagnostics.stats.releases += 1
	case .Owner_Retired: diagnostics.stats.owners_retired += 1
	case .Settled: diagnostics.stats.settlements += 1
	case .Host_Suspended: diagnostics.stats.host_suspends += 1
	case .Hidden_Gap_Fast_Forward: diagnostics.stats.hidden_gap_fast_forwards += 1
	case .Opacity_Clamp: diagnostics.stats.opacity_clamps += 1
	case .Bounded_Snap: diagnostics.stats.bounded_snaps += 1
	case .Failure: diagnostics.stats.failures += 1
	}
}

motion_diagnostic_host_event :: proc(
	rt: ^Runtime,
	kind: Motion_Diagnostic_Kind,
	at: Motion_Time,
	elapsed_ns: u64 = 0,
	source: Motion_Clock_Source = .Native_Monotonic,
) {
	if rt == nil { return }
	rt.motion_clock_source = source
	motion_diagnostic_record(rt, kind, elapsed_ns=elapsed_ns, time_override=at, override_time=true)
}

// Each runtime lifetime receives one process-unique identity, assigned lazily
// when it first creates a motion owner. Relaxed atomic ordering is sufficient:
// the counter only allocates distinct scalar IDs and publishes no other state.
motion_runtime_identity_next :: proc() -> (identity: u64, valid: bool) {
	current := sync.atomic_load_explicit(&motion_runtime_identity_sequence, .Relaxed)
	for {
		if current == u64(0xffffffffffffffff) { return 0, false }
		previous, exchanged := sync.atomic_compare_exchange_strong_explicit(
			&motion_runtime_identity_sequence,
			current,
			current+1,
			.Relaxed,
			.Relaxed,
		)
		if exchanged { return current+1, true }
		current = previous
	}
}

// motion_clock_set_time is the host bridge for intent-based authoring. It
// records a monotonic timestamp without sampling or requesting presentation;
// native hosts call it immediately before an application description, while
// deterministic tests may inject their own value.
motion_clock_set_time :: proc(
	rt: ^Runtime,
	at: Motion_Time,
	source: Motion_Clock_Source = .Injected,
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) { return .Time_Rewound }
	rt.motion_time = at
	rt.motion_clock_initialized = true
	rt.motion_clock_source = source
	return .Ok
}

// motion_intent_queue accepts one declarative motion request for a node emitted
// in the current description. A repeated request for the same node replaces
// the earlier request; intent application is deferred until end_frame has
// reconciled the current subtree.
motion_intent_queue :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	target: Motion_Target,
	intent: Motion_Intent = .Settle,
	reveal_offset: Motion_Vector2 = {},
	loc := #caller_location,
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	source := Source_Site{loc.file_path, int(loc.line), int(loc.column), "ui.motion"}
	cause := trace_current_cause(rt)
	if !rt.frame_open {
		motion_diagnostic_record(rt, .Failure, owner, .Description_Required, source, cause, coalesce=true)
		return .Description_Required
	}
	if owner == 0 {
		motion_diagnostic_record(rt, .Failure, owner, .Invalid_Owner, source, cause, coalesce=true)
		return .Invalid_Owner
	}
	if intent != .Settle && intent != .Direct && intent != .Snap && intent != .Reveal {
		motion_diagnostic_record(rt, .Failure, owner, .Invalid_Value, source, cause, coalesce=true)
		return .Invalid_Value
	}
	if !motion_finite(reveal_offset.x) || !motion_finite(reveal_offset.y) ||
		abs(reveal_offset.x) > MOTION_TRANSLATION_COMPONENT_MAX ||
		abs(reveal_offset.y) > MOTION_TRANSLATION_COMPONENT_MAX {
		motion_diagnostic_record(rt, .Failure, owner, .Invalid_Value, source, cause, coalesce=true)
		return .Invalid_Value
	}
	if target.has_opacity && (!motion_finite(target.opacity) || target.opacity < 0 || target.opacity > 1) {
		motion_diagnostic_record(rt, .Failure, owner, .Invalid_Value, source, cause, coalesce=true)
		return .Invalid_Value
	}
	if target.has_translation && (!motion_finite(target.translation.x) || !motion_finite(target.translation.y) ||
		abs(target.translation.x) > MOTION_TRANSLATION_COMPONENT_MAX ||
		abs(target.translation.y) > MOTION_TRANSLATION_COMPONENT_MAX) {
		motion_diagnostic_record(rt, .Failure, owner, .Invalid_Value, source, cause, coalesce=true)
		return .Invalid_Value
	}
	if !target.has_translation && !target.has_opacity { return .Ok }
	if _, described := rt.seen[owner]; !described {
		motion_diagnostic_record(rt, .Failure, owner, .Owner_Not_Described, source, cause, coalesce=true)
		return .Owner_Not_Described
	}
	if rt.motion_intent_request_indices == nil {
		rt.motion_intent_request_indices = make(map[Node_ID]int, allocator=rt.persistent_allocator)
	}
	request := Motion_Intent_Request{
		owner=owner,
		target=target,
		intent=intent,
		reveal_offset=reveal_offset,
		source=source,
		cause=cause,
	}
	if index, exists := rt.motion_intent_request_indices[owner]; exists {
		rt.motion_intent_requests[index] = request
		motion_diagnostics_ensure(rt).stats.declarations_coalesced += 1
	} else {
		append(&rt.motion_intent_requests, request)
		rt.motion_intent_request_indices[owner] = len(rt.motion_intent_requests)-1
	}
	return .Ok
}

motion_intent_requests_apply :: proc(rt: ^Runtime) {
	if rt == nil || len(rt.motion_intent_requests) == 0 { return }
	for request in rt.motion_intent_requests {
		status := motion_apply_intent(
			rt, request.owner, request.target, request.intent, request.reveal_offset,
			source=request.source, cause=request.cause,
		)
		if status != .Ok {
			file, line, column := request.source.file, request.source.line, request.source.column
			motion_diagnostic_record(rt, .Failure, request.owner, status, request.source, request.cause, coalesce=true)
			append_diagnostic(rt, fmt.tprintf(
				"motion intent for node %d declared at %s:%d:%d was not applied: %v",
				request.owner, file, line, column, status,
			))
		}
	}
	clear(&rt.motion_intent_requests)
	clear(&rt.motion_intent_request_indices)
}

motion_owner_begin :: proc(rt: ^Runtime, owner: Node_ID, loc := #caller_location) -> (handle: Motion_Owner_Handle, status: Motion_Runtime_Status) {
	if rt == nil { return {}, .Invalid_Runtime }
	source := Source_Site{loc.file_path, int(loc.line), int(loc.column), "motion owner"}
	if owner == 0 {
		motion_diagnostic_record(rt, .Failure, owner, .Invalid_Owner, source, trace_current_cause(rt), coalesce=true)
		return {}, .Invalid_Owner
	}
	if node, found := rt.nodes[owner]; !found || node == nil || !node.active {
		motion_diagnostic_record(rt, .Failure, owner, .Owner_Not_Retained, source, trace_current_cause(rt), coalesce=true)
		return {}, .Owner_Not_Retained
	}
	if rt.motion_runtime_identity == 0 {
		identity, valid := motion_runtime_identity_next()
		if !valid {
			motion_diagnostic_record(rt, .Failure, owner, .Runtime_Identity_Limit, source, trace_current_cause(rt), coalesce=true)
			return {}, .Runtime_Identity_Limit
		}
		rt.motion_runtime_identity = identity
	}
	if rt.motion_owners == nil {
		rt.motion_owners = make(map[Node_ID]Motion_Retained_Owner, allocator=rt.persistent_allocator)
	}
	if current, found := rt.motion_owners[owner]; found {
		return Motion_Owner_Handle{rt.motion_runtime_identity, owner, current.generation}, .Ok
	}
	if len(rt.motion_owners) >= MOTION_RETAINED_MAX_OWNERS || rt.motion_generation_sequence == u64(0xffffffffffffffff) {
		motion_diagnostic_record(rt, .Failure, owner, .Owner_Limit, source, trace_current_cause(rt), coalesce=true)
		return {}, .Owner_Limit
	}
	rt.motion_generation_sequence += 1
	if rt.motion_generation_sequence == 0 {
		motion_diagnostic_record(rt, .Failure, owner, .Owner_Limit, source, trace_current_cause(rt), coalesce=true)
		return {}, .Owner_Limit
	}
	state := Motion_Retained_Owner{
		generation=rt.motion_generation_sequence,
		presented_opacity=1,
		opacity_deadline_established=true,
		translation_deadline_established=true,
	}
	rt.motion_owners[owner] = state
	return Motion_Owner_Handle{rt.motion_runtime_identity, owner, state.generation}, .Ok
}

@(private)
motion_reveal_subtree_is_noninteractive :: proc(rt: ^Runtime, owner: Node_ID) -> bool {
	if rt == nil { return false }
	MOTION_REVEAL_SUBTREE_SCAN_LIMIT :: 4096
	stack: [MOTION_REVEAL_SUBTREE_SCAN_LIMIT]Node_ID
	stack[0] = owner
	count := 1
	for count > 0 {
		count -= 1
		id := stack[count]
		node, found := rt.nodes[id]
		if !found || node == nil || !node.active { return false }
		if node.focusable || node.text_input_target || node.surface_interaction != .Inert ||
			node.drag_source_type != Drag_Type(0) || node.drop_target_type != Drag_Type(0) {
			return false
		}
		// Disabled controls and currently unfocusable navigation containers can
		// still become interactive while an opacity reveal is active. Restrict
		// Reveal to structurally passive node kinds, not just current focus flags.
		switch node.kind {
		case .Root, .Container, .Grid, .Text, .Image:
		case .Custom_Surface:
			if node.surface_interaction != .Inert { return false }
		case .Modal_Overlay, .Context_Menu_Overlay, .Context_Menu_Panel,
			.Button, .Tab, .Tab_Close, .Checkbox, .Slider, .Text_Field,
			.Text_Composition, .Virtual_List, .Virtual_Row, .Scroll_Region,
			.Split, .Split_Handle:
			return false
		}
		if len(node.children) > MOTION_REVEAL_SUBTREE_SCAN_LIMIT-count { return false }
		for child in node.children {
			stack[count] = child
			count += 1
		}
	}
	return true
}

@(private)
motion_intent_mode_resolve :: proc(
	intent: Motion_Intent,
	reduced_motion, disabled, opacity_property: bool,
	policy: Motion_Theme_Policy,
) -> (mode: Motion_Mode, config: Motion_Config) {
	config = policy.translation
	if opacity_property { config = policy.opacity }
	if disabled || intent == .Snap { return .Snap, config }
	if intent == .Direct { return .Direct, config }
	if reduced_motion {
		if opacity_property && policy.reduced_motion == .Opacity_Fade {
			return .Settle, policy.reduced_opacity
		}
		return .Snap, config
	}
	return .Settle, config
}

motion_owner_is_current :: proc(rt: ^Runtime, handle: Motion_Owner_Handle) -> bool {
	if rt == nil || rt.motion_owners == nil || rt.motion_runtime_identity == 0 ||
		handle.runtime_identity != rt.motion_runtime_identity || handle.node == 0 || handle.generation == 0 {
		return false
	}
	state, found := rt.motion_owners[handle.node]
	if !found || state.generation != handle.generation { return false }
	node, node_found := rt.nodes[handle.node]
	return node_found && node != nil && node.active
}

motion_request_presentation :: proc(rt: ^Runtime, reason: string) {
	diagnostics := motion_diagnostics_ensure(rt)
	if diagnostics != nil {
		diagnostics.stats.presentation_requests += 1
		if rt.presentation_pending { diagnostics.stats.presentation_requests_coalesced += 1 }
	}
	rt.presentation_pending = true
	rt.motion_frame_pending = true
	rt.composition_rebuild = true
	when APP_MUTATION_DIAGNOSTICS_ENABLED {
		application_mutation_note_request(rt, .Presentation)
	}
	record_trace_literal(rt, .Invalidation, 0, reason)
	note_pending_work_cause(rt, trace_current_cause(rt))
}

motion_clamp_opacity :: proc(value: f64) -> f32 {
	return f32(clamp(value, f64(0), f64(1)))
}

motion_value_to_f32 :: proc(value: f64) -> (result: f32, ok: bool) {
	if !motion_finite(value) || abs(value) > MOTION_F32_MAX { return 0, false }
	result = f32(value)
	return result, motion_finite(f64(result))
}

motion_mode_valid :: proc(mode: Motion_Mode) -> bool {
	return mode == .Settle || mode == .Direct || mode == .Snap
}

motion_composition_values :: proc(rt: ^Runtime, owner: Node_ID) -> Motion_Composition_Values {
	result := Motion_Composition_Values{opacity=1}
	if rt == nil || rt.motion_owners == nil { return result }
	state, found := rt.motion_owners[owner]
	if !found { return result }
	if state.has_translation { result.translation = state.presented_translation }
	if state.has_opacity { result.opacity = state.presented_opacity }
	return result
}

motion_presentation :: proc(rt: ^Runtime, handle: Motion_Owner_Handle) -> Motion_Presentation {
	if rt == nil { return Motion_Presentation{status=.Invalid_Runtime} }
	if !motion_owner_is_current(rt, handle) { return Motion_Presentation{status=.Stale_Owner} }
	state := rt.motion_owners[handle.node]
	active := state.translation_active || state.opacity_active
	deadline_established := (!state.translation_active || state.translation_deadline_established) &&
		(!state.opacity_active || state.opacity_deadline_established)
	return Motion_Presentation{
		target_translation=Motion_Vector2{
			state.translation.x.target if state.has_translation else 0,
			state.translation.y.target if state.has_translation else 0,
		},
		presented_translation=state.presented_translation,
		target_opacity=state.opacity.target if state.has_opacity else 1,
		presented_opacity=state.presented_opacity if state.has_opacity else 1,
		has_translation=state.has_translation,
		has_opacity=state.has_opacity,
		active=active,
		deadline_established=deadline_established,
		status=.Ok,
	}
}

motion_scalar_set_target :: proc(
	response: Motion_Scalar_Response,
	initialized: bool,
	base, target: f64,
	config: Motion_Config,
	mode: Motion_Mode,
	at: Motion_Time,
) -> (next: Motion_Scalar_Response, status: Motion_Status) {
	if !motion_finite(target) { return response, .Invalid_Value }
	if !motion_config_valid(config) { return response, .Invalid_Configuration }
	if !motion_mode_valid(mode) { return response, .Invalid_Value }
	if !initialized {
		next, status = motion_scalar_create(base, target, 0, config, at)
		if status != .Ok { return response, status }
		switch mode {
		case .Settle:
			return next, .Ok
		case .Direct:
			return motion_scalar_direct(next, target, at)
		case .Snap:
			return motion_scalar_snap(next, target, at)
		}
	}
	if response.config != config {
		// A configuration change is a response replacement. Preserve the
		// currently presented position and velocity under the new policy.
		current := motion_scalar_sample(response, at)
		if current.status != .Ok { return response, current.status }
		next, status = motion_scalar_create(current.value, target, current.velocity, config, at)
		if status != .Ok { return response, status }
		switch mode {
		case .Settle: return next, .Ok
		case .Direct: return motion_scalar_direct(next, target, at)
		case .Snap: return motion_scalar_snap(next, target, at)
		}
	}
	switch mode {
	case .Settle: return motion_scalar_settle(response, target, at)
	case .Direct: return motion_scalar_direct(response, target, at)
	case .Snap: return motion_scalar_snap(response, target, at)
	}
	return response, .Invalid_Value
}

motion_translation_set_target :: proc(
	response: Motion_Translation_Response,
	initialized: bool,
	base, target: Motion_Vector2,
	config: Motion_Config,
	mode: Motion_Mode,
	at: Motion_Time,
) -> (next: Motion_Translation_Response, status: Motion_Status) {
	if !motion_finite(target.x) || !motion_finite(target.y) { return response, .Invalid_Value }
	if !motion_config_valid(config) { return response, .Invalid_Configuration }
	if !motion_mode_valid(mode) { return response, .Invalid_Value }
	if !initialized {
		next, status = motion_translation_create(base, target, {}, config, at)
		if status != .Ok { return response, status }
		switch mode {
		case .Settle: return next, .Ok
		case .Direct: return motion_translation_direct(next, target, at)
		case .Snap: return motion_translation_snap(next, target, at)
		}
	}
	if response.x.config != config {
		current := motion_translation_sample(response, at)
		if current.status != .Ok { return response, current.status }
		next, status = motion_translation_create(current.value, target, current.velocity, config, at)
		if status != .Ok { return response, status }
		switch mode {
		case .Settle: return next, .Ok
		case .Direct: return motion_translation_direct(next, target, at)
		case .Snap: return motion_translation_snap(next, target, at)
		}
	}
	switch mode {
	case .Settle: return motion_translation_settle(response, target, at)
	case .Direct: return motion_translation_direct(response, target, at)
	case .Snap: return motion_translation_snap(response, target, at)
	}
	return response, .Invalid_Value
}

motion_target_opacity :: proc(
	rt: ^Runtime,
	handle: Motion_Owner_Handle,
	target: f64,
	config: Motion_Config,
	mode: Motion_Mode,
	at: Motion_Time,
	source: Source_Site = {},
	cause: Cause_Context = {},
	record_diagnostics := true,
	loc := #caller_location,
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	event_source := source
	if event_source.file == "" { event_source = Source_Site{loc.file_path, int(loc.line), int(loc.column), "motion opacity"} }
	if target < 0 || target > 1 || !motion_finite(target) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Invalid_Value, event_source, cause, "motion opacity") }
		return .Invalid_Value
	}
	if !motion_config_valid(config) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Invalid_Configuration, event_source, cause, "motion opacity") }
		return .Invalid_Configuration
	}
	if !motion_mode_valid(mode) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Invalid_Value, event_source, cause, "motion opacity") }
		return .Invalid_Value
	}
	if !motion_owner_is_current(rt, handle) {
		if record_diagnostics { motion_diagnostic_record(rt, .Failure, handle.node, .Stale_Owner, event_source, cause, coalesce=true) }
		return .Stale_Owner
	}
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Time_Rewound, event_source, cause, "motion opacity") }
		return .Time_Rewound
	}
	preflight := motion_tick(rt, at)
	if preflight.status != .Ok {
		if record_diagnostics && preflight.status == .Time_Rewound {
			return motion_diagnostic_failure(rt, handle.node, preflight.status, event_source, cause, "motion opacity")
		}
		return preflight.status
	}
	state := rt.motion_owners[handle.node]
	before := state
	next, kernel_status := motion_scalar_set_target(
		state.opacity, state.has_opacity, 1, target, config, mode, at,
	)
	if kernel_status != .Ok {
		status := motion_runtime_status(kernel_status)
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, status, event_source, cause, "motion opacity") }
		return status
	}
	changed := !state.has_opacity || state.opacity != next
	if !changed {
		if record_diagnostics { motion_diagnostic_record(rt, .Unchanged_Target, handle.node, source=event_source, cause=cause, coalesce=true) }
		return .Ok
	}
	sample := motion_scalar_sample(next, at)
	if sample.status != .Ok {
		status := motion_runtime_status(sample.status)
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, status, event_source, cause, "motion opacity") }
		return status
	}
	state.opacity = next
	state.has_opacity = true
	state.presented_opacity = motion_clamp_opacity(sample.value)
	state.opacity_sampled_at = at
	state.opacity_active = sample.active
	state.opacity_deadline_established = sample.deadline_established
	if record_diagnostics {
		state.intent = .Settle if mode == .Settle else (.Direct if mode == .Direct else .Snap)
		state.source = event_source
		state.cause = cause
	}
	rt.motion_owners[handle.node] = state
	motion_request_presentation(rt, "retained motion opacity target changed")
	if record_diagnostics {
		kind: Motion_Diagnostic_Kind = .Target_Declared
		if before.has_opacity { kind = .Retarget }
		if before.has_opacity && before.opacity.mode != state.opacity.mode { kind = .Mode_Change }
		motion_diagnostic_record(rt, kind, handle.node, source=event_source, cause=cause)
	}
	return .Ok
}

motion_target_translation :: proc(
	rt: ^Runtime,
	handle: Motion_Owner_Handle,
	target: Motion_Vector2,
	config: Motion_Config,
	mode: Motion_Mode,
	at: Motion_Time,
	source: Source_Site = {},
	cause: Cause_Context = {},
	record_diagnostics := true,
	loc := #caller_location,
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	event_source := source
	if event_source.file == "" { event_source = Source_Site{loc.file_path, int(loc.line), int(loc.column), "motion translation"} }
	if !motion_finite(target.x) || !motion_finite(target.y) ||
		abs(target.x) > MOTION_TRANSLATION_COMPONENT_MAX || abs(target.y) > MOTION_TRANSLATION_COMPONENT_MAX {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Invalid_Value, event_source, cause, "motion translation") }
		return .Invalid_Value
	}
	if !motion_config_valid(config) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Invalid_Configuration, event_source, cause, "motion translation") }
		return .Invalid_Configuration
	}
	if !motion_mode_valid(mode) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Invalid_Value, event_source, cause, "motion translation") }
		return .Invalid_Value
	}
	if !motion_owner_is_current(rt, handle) {
		if record_diagnostics { motion_diagnostic_record(rt, .Failure, handle.node, .Stale_Owner, event_source, cause, coalesce=true) }
		return .Stale_Owner
	}
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Time_Rewound, event_source, cause, "motion translation") }
		return .Time_Rewound
	}
	preflight := motion_tick(rt, at)
	if preflight.status != .Ok {
		if record_diagnostics && preflight.status == .Time_Rewound {
			return motion_diagnostic_failure(rt, handle.node, preflight.status, event_source, cause, "motion translation")
		}
		return preflight.status
	}
	state := rt.motion_owners[handle.node]
	before := state
	next, kernel_status := motion_translation_set_target(
		state.translation, state.has_translation, {}, target, config, mode, at,
	)
	if kernel_status != .Ok {
		status := motion_runtime_status(kernel_status)
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, status, event_source, cause, "motion translation") }
		return status
	}
	if state.has_translation && state.translation == next {
		if record_diagnostics { motion_diagnostic_record(rt, .Unchanged_Target, handle.node, source=event_source, cause=cause, coalesce=true) }
		return .Ok
	}
	sample := motion_translation_sample(next, at)
	if sample.status != .Ok {
		status := motion_runtime_status(sample.status)
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, status, event_source, cause, "motion translation") }
		return status
	}
	x, x_ok := motion_value_to_f32(sample.value.x)
	y, y_ok := motion_value_to_f32(sample.value.y)
	if !x_ok || !y_ok {
		if record_diagnostics { return motion_diagnostic_failure(rt, handle.node, .Numeric_Overflow, event_source, cause, "motion translation") }
		return .Numeric_Overflow
	}
	state.translation = next
	state.has_translation = true
	state.presented_translation = [2]f32{x, y}
	state.translation_sampled_at = at
	state.translation_active = sample.active
	state.translation_deadline_established = sample.deadline_established
	if record_diagnostics {
		state.intent = .Settle if mode == .Settle else (.Direct if mode == .Direct else .Snap)
		state.source = event_source
		state.cause = cause
	}
	rt.motion_owners[handle.node] = state
	motion_request_presentation(rt, "retained motion translation target changed")
	if record_diagnostics {
		kind: Motion_Diagnostic_Kind = .Target_Declared
		if before.has_translation { kind = .Retarget }
		if before.has_translation && before.translation.x.mode != state.translation.x.mode { kind = .Mode_Change }
		motion_diagnostic_record(rt, kind, handle.node, source=event_source, cause=cause)
	}
	return .Ok
}

// motion_apply_intent is the ordinary application path: logical selection or
// visibility changes once, and the runtime owns the retained record, clock,
// retargeting and presentation policy. Reveal initializes only fresh retained
// properties. Target layout, hit testing and accessibility remain authoritative
// immediately; therefore interactive descendants are rejected for Reveal.
motion_apply_intent :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	target: Motion_Target,
	intent: Motion_Intent = .Settle,
	reveal_offset: Motion_Vector2 = {},
	source: Source_Site = {},
	cause: Cause_Context = {},
	loc := #caller_location,
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if intent != .Settle && intent != .Direct && intent != .Snap && intent != .Reveal {
		return .Invalid_Value
	}
	if !motion_finite(reveal_offset.x) || !motion_finite(reveal_offset.y) ||
		abs(reveal_offset.x) > MOTION_TRANSLATION_COMPONENT_MAX ||
		abs(reveal_offset.y) > MOTION_TRANSLATION_COMPONENT_MAX {
		return .Invalid_Value
	}
	if target.has_opacity && (!motion_finite(target.opacity) || target.opacity < 0 || target.opacity > 1) {
		return .Invalid_Value
	}
	if target.has_translation && (!motion_finite(target.translation.x) || !motion_finite(target.translation.y) ||
		abs(target.translation.x) > MOTION_TRANSLATION_COMPONENT_MAX ||
		abs(target.translation.y) > MOTION_TRANSLATION_COMPONENT_MAX) {
		return .Invalid_Value
	}
	if !target.has_translation && !target.has_opacity { return .Ok }
	if !rt.motion_clock_initialized { return .Clock_Unavailable }
	event_source := source
	node, found := rt.nodes[owner]
	if !found || node == nil || !node.active { return .Owner_Not_Retained }
	if intent == .Reveal && !motion_reveal_subtree_is_noninteractive(rt, owner) {
		return .Interactive_Reveal_Unsupported
	}
	if event_source.file == "" {
		event_source = Source_Site{loc.file_path, int(loc.line), int(loc.column), "motion intent"}
	}
	policy := style_theme_motion_policy(rt, node.style_environment.theme)
	if !motion_theme_policy_valid(policy) { return .Invalid_Configuration }
	handle, owner_status := motion_owner_begin(rt, owner)
	if owner_status != .Ok { return owner_status }
	before := rt.motion_owners[owner]
	current := motion_presentation(rt, handle)
	if current.status != .Ok { return current.status }
	reduced := node.style_environment.accessibility.reduce_motion
	translation_mode, translation_config := motion_intent_mode_resolve(
		intent, reduced, node.disabled, false, policy,
	)
	opacity_mode, opacity_config := motion_intent_mode_resolve(
		intent, reduced, node.disabled, true, policy,
	)
	if intent == .Reveal {
		// The fresh frame is paint-only hidden/offset before the response starts.
		// Reduced motion skips spatial displacement; an opted-in opacity fade may
		// still begin at zero and converge under its shorter theme policy.
		if target.has_translation && !current.has_translation && !reduced && !node.disabled {
			initial := Motion_Vector2{
				target.translation.x+reveal_offset.x,
				target.translation.y+reveal_offset.y,
			}
			if status := motion_target_translation(rt, handle, initial, policy.translation, .Snap, rt.motion_time,
				source=event_source, cause=cause, record_diagnostics=false); status != .Ok {
				return status
			}
		}
		if target.has_opacity && !current.has_opacity && !node.disabled &&
			(!reduced || policy.reduced_motion == .Opacity_Fade) {
			if status := motion_target_opacity(rt, handle, 0, policy.opacity, .Snap, rt.motion_time,
				source=event_source, cause=cause, record_diagnostics=false); status != .Ok {
				return status
			}
		}
	}
	if target.has_translation {
		if status := motion_target_translation(rt, handle, target.translation, translation_config, translation_mode, rt.motion_time,
			source=event_source, cause=cause, record_diagnostics=false); status != .Ok {
			return status
		}
	}
	if target.has_opacity {
		if status := motion_target_opacity(rt, handle, target.opacity, opacity_config, opacity_mode, rt.motion_time,
			source=event_source, cause=cause, record_diagnostics=false); status != .Ok {
			return status
		}
	}
	reduced_opacity_bounded_snap := false
	if reduced && policy.reduced_motion == .Opacity_Fade && target.has_opacity && opacity_mode == .Settle {
		candidate := rt.motion_owners[owner].opacity
		if !candidate.deadline_established || candidate.settle_after_ns > MOTION_REDUCED_OPACITY_MAX_NS {
			// The initial settle request has not been submitted yet. Replace its
			// response at the same injected time so no intermediate fade is shown.
			snapped, snap_status := motion_scalar_snap(candidate, target.opacity, rt.motion_time)
			if snap_status != .Ok { return motion_runtime_status(snap_status) }
			state := rt.motion_owners[owner]
			state.opacity = snapped
			state.has_opacity = true
			state.presented_opacity = motion_clamp_opacity(target.opacity)
			state.opacity_sampled_at = rt.motion_time
			state.opacity_active = false
			state.opacity_deadline_established = true
			rt.motion_owners[owner] = state
			opacity_mode = .Snap
			reduced_opacity_bounded_snap = true
		}
	}
	state := rt.motion_owners[owner]
	translation_changed := target.has_translation &&
		(!before.has_translation || before.translation != state.translation)
	opacity_changed := target.has_opacity &&
		(!before.has_opacity || before.opacity != state.opacity)
	translation_mode_changed := before.has_translation && target.has_translation &&
		before.translation.x.mode != state.translation.x.mode
	opacity_mode_changed := before.has_opacity && target.has_opacity && before.opacity.mode != state.opacity.mode
	if translation_changed || opacity_changed {
		state.intent = intent
		state.source = event_source
		state.cause = cause
		rt.motion_owners[owner] = state
	}
	diagnostics := motion_diagnostics_ensure(rt)
	diagnostics.stats.intent_declarations += 1
	if translation_changed || opacity_changed {
		if translation_mode_changed || opacity_mode_changed {
			motion_diagnostic_record(rt, .Mode_Change, owner, source=event_source, cause=cause)
		} else if before.has_translation || before.has_opacity {
			motion_diagnostic_record(rt, .Retarget, owner, source=event_source, cause=cause)
		} else {
			motion_diagnostic_record(rt, .Target_Declared, owner, source=event_source, cause=cause)
		}
	} else {
		motion_diagnostic_record(rt, .Unchanged_Target, owner, source=event_source, cause=cause, coalesce=true)
	}
	if intent == .Reveal && ((!before.has_translation && target.has_translation) || (!before.has_opacity && target.has_opacity)) {
		motion_diagnostic_record(rt, .Reveal, owner, source=event_source, cause=cause, coalesce=true)
	}
	if reduced && intent != .Direct && intent != .Snap &&
		((target.has_translation && translation_mode == .Snap) || (target.has_opacity && opacity_mode == .Snap)) {
		reason := Motion_Diagnostic_Reason(.None)
		if reduced_opacity_bounded_snap { reason = .Reduced_Opacity_Fade_Exceeded_Bound }
		motion_diagnostic_record(rt, .Reduced_Motion_Rewrite, owner, source=event_source, cause=cause, reason=reason, coalesce=true)
	}
	return .Ok
}

motion_sample_validate :: proc(state: Motion_Retained_Owner, at: Motion_Time) -> Motion_Runtime_Status {
	if state.has_opacity {
		sample := motion_scalar_sample(state.opacity, at)
		if sample.status != .Ok { return motion_runtime_status(sample.status) }
	}
	if state.has_translation {
		sample := motion_translation_sample(state.translation, at)
		if sample.status != .Ok { return motion_runtime_status(sample.status) }
		_, x_ok := motion_value_to_f32(sample.value.x)
		_, y_ok := motion_value_to_f32(sample.value.y)
		if !x_ok || !y_ok { return .Numeric_Overflow }
	}
	return .Ok
}

// motion_tick samples every active retained response at one injected time.
// It is all-or-nothing on errors, schedules a presentation-only frame when a
// visible value changes, and reports active responses without certified
// deadlines so a future scheduler can apply an explicit bounded policy.
motion_tick :: proc(rt: ^Runtime, at: Motion_Time) -> Motion_Tick_Result {
	if rt == nil { return Motion_Tick_Result{status=.Invalid_Runtime} }
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) {
		return Motion_Tick_Result{status=.Time_Rewound}
	}
	if rt.motion_owners == nil {
		rt.motion_time = at
		rt.motion_clock_initialized = true
		return Motion_Tick_Result{status=.Ok}
	}
	if rt.motion_diagnostics != nil {
		rt.motion_diagnostics.stats.sample_ticks += 1
		rt.motion_diagnostics.stats.owner_visits += u64(len(rt.motion_owners))
		for _, state in rt.motion_owners {
			if state.has_translation { rt.motion_diagnostics.stats.property_samples += 1 }
			if state.has_opacity { rt.motion_diagnostics.stats.property_samples += 1 }
		}
	}
	for owner, state in rt.motion_owners {
		status := motion_sample_validate(state, at)
		if status != .Ok {
			motion_diagnostic_record(rt, .Failure, owner, status, coalesce=true)
			return Motion_Tick_Result{status=status}
		}
	}
	result := Motion_Tick_Result{status=.Ok}
	rt.motion_time = at
	rt.motion_clock_initialized = true
	for owner, &state in rt.motion_owners {
		changed := false
		owner_active := false
		settled := false
		clamped_now := false
		if state.has_opacity {
			sample := motion_scalar_sample(state.opacity, at)
			clamped_now = sample.value < 0 || sample.value > 1
			if state.opacity_active && !sample.active { settled = true }
			newly_clamped := clamped_now && !state.opacity_clamped
			state.opacity_clamped = clamped_now
			presented := motion_clamp_opacity(sample.value)
			if presented != state.presented_opacity { changed = true }
			state.presented_opacity = presented
			state.opacity_sampled_at = at
			state.opacity_active = sample.active
			state.opacity_deadline_established = sample.deadline_established
			if sample.active {
				result.active_properties += 1
				owner_active = true
				if !sample.deadline_established { result.unestablished_deadlines += 1 }
			}
			if newly_clamped {
				motion_diagnostic_record(rt, .Opacity_Clamp, owner, detail_value=Motion_Vector2{sample.value, 0})
			}
		}
		if state.has_translation {
			sample := motion_translation_sample(state.translation, at)
			if state.translation_active && !sample.active { settled = true }
			x, _ := motion_value_to_f32(sample.value.x)
			y, _ := motion_value_to_f32(sample.value.y)
			presented := [2]f32{x, y}
			if presented != state.presented_translation { changed = true }
			state.presented_translation = presented
			state.translation_sampled_at = at
			state.translation_active = sample.active
			state.translation_deadline_established = sample.deadline_established
			if sample.active {
				result.active_properties += 1
				owner_active = true
				if !sample.deadline_established { result.unestablished_deadlines += 1 }
			}
		}
		if owner_active { result.active_owners += 1 }
		if changed { result.changed_owners += 1 }
		if settled { motion_diagnostic_record(rt, .Settled, owner) }
	}
	if result.changed_owners > 0 {
		motion_request_presentation(rt, "retained motion presentation sampled")
	}
	return result
}

motion_activity :: proc(rt: ^Runtime) -> Motion_Activity {
	result := Motion_Activity{}
	if rt == nil || rt.motion_owners == nil { return result }
	for _, state in rt.motion_owners {
		owner_active := false
		if state.opacity_active {
			result.active_properties += 1
			owner_active = true
			if !state.opacity_deadline_established { result.unestablished_deadlines += 1 }
		}
		if state.translation_active {
			result.active_properties += 1
			owner_active = true
			if !state.translation_deadline_established { result.unestablished_deadlines += 1 }
		}
		if owner_active { result.active_owners += 1 }
	}
	return result
}

// motion_snap_unestablished applies the host's bounded policy to active
// responses whose conservative settlement deadline could not be certified.
// Certified responses are untouched. The operation preflights all affected
// values before mutation and requests at most one presentation update.
motion_snap_unestablished :: proc(rt: ^Runtime, at: Motion_Time) -> Motion_Tick_Result {
	if rt == nil { return Motion_Tick_Result{status=.Invalid_Runtime} }
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) {
		return Motion_Tick_Result{status=.Time_Rewound}
	}
	if rt.motion_owners == nil {
		rt.motion_time = at
		rt.motion_clock_initialized = true
		return Motion_Tick_Result{status=.Ok}
	}
	for owner, state in rt.motion_owners {
		if state.opacity_active && !state.opacity_deadline_established {
			if status := motion_sample_validate(state, at); status != .Ok {
				motion_diagnostic_record(rt, .Failure, owner, status, coalesce=true)
				return Motion_Tick_Result{status=status}
			}
		}
		if state.translation_active && !state.translation_deadline_established {
			if status := motion_sample_validate(state, at); status != .Ok {
				motion_diagnostic_record(rt, .Failure, owner, status, coalesce=true)
				return Motion_Tick_Result{status=status}
			}
		}
	}
	result := Motion_Tick_Result{status=.Ok}
	rt.motion_time = at
	rt.motion_clock_initialized = true
	for owner, &state in rt.motion_owners {
		changed := false
		snapped := false
		if state.opacity_active && !state.opacity_deadline_established {
			next, status := motion_scalar_snap(state.opacity, state.opacity.target, at)
			if status != .Ok { return Motion_Tick_Result{status=motion_runtime_status(status)} }
			presented := motion_clamp_opacity(next.target)
			changed = changed || presented != state.presented_opacity
			state.opacity = next
			state.presented_opacity = presented
			state.opacity_sampled_at = at
			state.opacity_active = false
			state.opacity_deadline_established = true
			snapped = true
		}
		if state.translation_active && !state.translation_deadline_established {
			target := Motion_Vector2{state.translation.x.target, state.translation.y.target}
			next, status := motion_translation_snap(state.translation, target, at)
			if status != .Ok { return Motion_Tick_Result{status=motion_runtime_status(status)} }
			x, x_ok := motion_value_to_f32(target.x)
			y, y_ok := motion_value_to_f32(target.y)
			if !x_ok || !y_ok { return Motion_Tick_Result{status=.Numeric_Overflow} }
			presented := [2]f32{x, y}
			changed = changed || presented != state.presented_translation
			state.translation = next
			state.presented_translation = presented
			state.translation_sampled_at = at
			state.translation_active = false
			state.translation_deadline_established = true
			snapped = true
		}
		if changed { result.changed_owners += 1 }
		if snapped { motion_diagnostic_record(rt, .Bounded_Snap, owner) }
	}
	if result.changed_owners > 0 {
		motion_request_presentation(rt, "uncertified retained motion reached host duration limit")
	}
	activity := motion_activity(rt)
	result.active_properties = activity.active_properties
	result.active_owners = activity.active_owners
	result.unestablished_deadlines = activity.unestablished_deadlines
	return result
}

motion_retire_owner :: proc(rt: ^Runtime, owner: Node_ID) {
	if rt == nil || rt.motion_owners == nil { return }
	if state, found := rt.motion_owners[owner]; found {
		source := Source_Site{}
		if node, node_found := rt.nodes[owner]; node_found && node != nil { source = node.site }
		motion_diagnostic_record(rt, .Owner_Retired, owner, source=source, cause=trace_current_cause(rt))
		_ = state
	}
	delete_key(&rt.motion_owners, owner)
}

// motion_owner_release cancels an owner's current motion, removes its sidecar
// record, and leaves the retained node alive. Releasing resets its presentation
// to the neutral transform and opacity on the next composition; callers that
// need another resting presentation should commit that state before releasing.
motion_owner_release :: proc(rt: ^Runtime, handle: Motion_Owner_Handle, loc := #caller_location) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	source := Source_Site{loc.file_path, int(loc.line), int(loc.column), "motion release"}
	if !motion_owner_is_current(rt, handle) {
		motion_diagnostic_record(rt, .Failure, handle.node, .Stale_Owner, source, trace_current_cause(rt), coalesce=true)
		return .Stale_Owner
	}
	state := rt.motion_owners[handle.node]
	visible_change := state.presented_translation != [2]f32{} ||
		(state.has_opacity && state.presented_opacity != 1)
	motion_diagnostic_record(rt, .Release, handle.node, source=source, cause=trace_current_cause(rt))
	delete_key(&rt.motion_owners, handle.node)
	if visible_change { motion_request_presentation(rt, "retained motion owner released") }
	return .Ok
}

// Motion geometry is paint-only. Ancestor translation is accumulated through
// retained hierarchy; clips, hit regions and accessibility target bounds stay
// at their logical target geometry by design in this first integration.
motion_compose_subtree :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	inherited_translation: [2]f32,
	inherited_opacity: f32,
) -> Motion_Composition_Values {
	local := motion_composition_values(rt, owner)
	return Motion_Composition_Values{
		translation=[2]f32{
			inherited_translation[0]+local.translation[0],
			inherited_translation[1]+local.translation[1],
		},
		opacity=clamp(inherited_opacity*local.opacity, f32(0), f32(1)),
	}
}
