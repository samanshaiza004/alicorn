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
	has_translation: bool,
	translation: Motion_Translation_Response,
	presented_translation: [2]f32,
	translation_active: bool,
	translation_deadline_established: bool,
	has_opacity: bool,
	opacity: Motion_Scalar_Response,
	presented_opacity: f32,
	opacity_active: bool,
	opacity_deadline_established: bool,
}

// Motion_Intent_Request keeps the ordinary UI wrapper declarative: a request
// made during description is applied after reconciliation, when the retained
// owner and its complete subtree have their current interaction/style state.
Motion_Intent_Request :: struct {
	owner: Node_ID,
	target: Motion_Target,
	intent: Motion_Intent,
	reveal_offset: Motion_Vector2,
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
motion_clock_set_time :: proc(rt: ^Runtime, at: Motion_Time) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) { return .Time_Rewound }
	rt.motion_time = at
	rt.motion_clock_initialized = true
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
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if !rt.frame_open { return .Description_Required }
	if owner == 0 { return .Invalid_Owner }
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
	if _, described := rt.seen[owner]; !described { return .Owner_Not_Described }
	if rt.motion_intent_request_indices == nil {
		rt.motion_intent_request_indices = make(map[Node_ID]int, allocator=rt.persistent_allocator)
	}
	request := Motion_Intent_Request{owner, target, intent, reveal_offset}
	if index, exists := rt.motion_intent_request_indices[owner]; exists {
		rt.motion_intent_requests[index] = request
	} else {
		append(&rt.motion_intent_requests, request)
		rt.motion_intent_request_indices[owner] = len(rt.motion_intent_requests)-1
	}
	return .Ok
}

motion_intent_requests_apply :: proc(rt: ^Runtime) {
	if rt == nil || len(rt.motion_intent_requests) == 0 { return }
	for request in rt.motion_intent_requests {
		status := motion_apply_intent(rt, request.owner, request.target, request.intent, request.reveal_offset)
		if status != .Ok {
			file, line, column := "", 0, 0
			if node, found := rt.nodes[request.owner]; found && node != nil {
				file, line, column = node.site.file, node.site.line, node.site.column
			}
			append_diagnostic(rt, fmt.tprintf(
				"motion intent for node %d declared at %s:%d:%d was not applied: %v",
				request.owner, file, line, column, status,
			))
		}
	}
	clear(&rt.motion_intent_requests)
	clear(&rt.motion_intent_request_indices)
}

motion_owner_begin :: proc(rt: ^Runtime, owner: Node_ID) -> (handle: Motion_Owner_Handle, status: Motion_Runtime_Status) {
	if rt == nil { return {}, .Invalid_Runtime }
	if owner == 0 { return {}, .Invalid_Owner }
	if node, found := rt.nodes[owner]; !found || node == nil || !node.active {
		return {}, .Owner_Not_Retained
	}
	if rt.motion_runtime_identity == 0 {
		identity, valid := motion_runtime_identity_next()
		if !valid { return {}, .Runtime_Identity_Limit }
		rt.motion_runtime_identity = identity
	}
	if rt.motion_owners == nil {
		rt.motion_owners = make(map[Node_ID]Motion_Retained_Owner, allocator=rt.persistent_allocator)
	}
	if current, found := rt.motion_owners[owner]; found {
		return Motion_Owner_Handle{rt.motion_runtime_identity, owner, current.generation}, .Ok
	}
	if len(rt.motion_owners) >= MOTION_RETAINED_MAX_OWNERS || rt.motion_generation_sequence == u64(0xffffffffffffffff) {
		return {}, .Owner_Limit
	}
	rt.motion_generation_sequence += 1
	if rt.motion_generation_sequence == 0 { return {}, .Owner_Limit }
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
	rt.presentation_pending = true
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
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if target < 0 || target > 1 || !motion_finite(target) { return .Invalid_Value }
	if !motion_config_valid(config) { return .Invalid_Configuration }
	if !motion_mode_valid(mode) { return .Invalid_Value }
	if !motion_owner_is_current(rt, handle) { return .Stale_Owner }
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) { return .Time_Rewound }
	preflight := motion_tick(rt, at)
	if preflight.status != .Ok { return preflight.status }
	state := rt.motion_owners[handle.node]
	next, kernel_status := motion_scalar_set_target(
		state.opacity, state.has_opacity, 1, target, config, mode, at,
	)
	if kernel_status != .Ok { return motion_runtime_status(kernel_status) }
	changed := !state.has_opacity || state.opacity != next
	if !changed { return .Ok }
	sample := motion_scalar_sample(next, at)
	if sample.status != .Ok { return motion_runtime_status(sample.status) }
	state.opacity = next
	state.has_opacity = true
	state.presented_opacity = motion_clamp_opacity(sample.value)
	state.opacity_active = sample.active
	state.opacity_deadline_established = sample.deadline_established
	rt.motion_owners[handle.node] = state
	motion_request_presentation(rt, "retained motion opacity target changed")
	return .Ok
}

motion_target_translation :: proc(
	rt: ^Runtime,
	handle: Motion_Owner_Handle,
	target: Motion_Vector2,
	config: Motion_Config,
	mode: Motion_Mode,
	at: Motion_Time,
) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if !motion_finite(target.x) || !motion_finite(target.y) { return .Invalid_Value }
	if abs(target.x) > MOTION_TRANSLATION_COMPONENT_MAX || abs(target.y) > MOTION_TRANSLATION_COMPONENT_MAX { return .Invalid_Value }
	if !motion_config_valid(config) { return .Invalid_Configuration }
	if !motion_mode_valid(mode) { return .Invalid_Value }
	if !motion_owner_is_current(rt, handle) { return .Stale_Owner }
	if rt.motion_clock_initialized && i64(at) < i64(rt.motion_time) { return .Time_Rewound }
	preflight := motion_tick(rt, at)
	if preflight.status != .Ok { return preflight.status }
	state := rt.motion_owners[handle.node]
	next, kernel_status := motion_translation_set_target(
		state.translation, state.has_translation, {}, target, config, mode, at,
	)
	if kernel_status != .Ok { return motion_runtime_status(kernel_status) }
	if state.has_translation && state.translation == next { return .Ok }
	sample := motion_translation_sample(next, at)
	if sample.status != .Ok { return motion_runtime_status(sample.status) }
	x, x_ok := motion_value_to_f32(sample.value.x)
	y, y_ok := motion_value_to_f32(sample.value.y)
	if !x_ok || !y_ok { return .Numeric_Overflow }
	state.translation = next
	state.has_translation = true
	state.presented_translation = [2]f32{x, y}
	state.translation_active = sample.active
	state.translation_deadline_established = sample.deadline_established
	rt.motion_owners[handle.node] = state
	motion_request_presentation(rt, "retained motion translation target changed")
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
	node, found := rt.nodes[owner]
	if !found || node == nil || !node.active { return .Owner_Not_Retained }
	if intent == .Reveal && !motion_reveal_subtree_is_noninteractive(rt, owner) {
		return .Interactive_Reveal_Unsupported
	}
	policy := style_theme_motion_policy(rt, node.style_environment.theme)
	if !motion_theme_policy_valid(policy) { return .Invalid_Configuration }
	handle, owner_status := motion_owner_begin(rt, owner)
	if owner_status != .Ok { return owner_status }
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
			if status := motion_target_translation(rt, handle, initial, policy.translation, .Snap, rt.motion_time); status != .Ok {
				return status
			}
		}
		if target.has_opacity && !current.has_opacity && !node.disabled &&
			(!reduced || policy.reduced_motion == .Opacity_Fade) {
			if status := motion_target_opacity(rt, handle, 0, policy.opacity, .Snap, rt.motion_time); status != .Ok {
				return status
			}
		}
	}
	if target.has_translation {
		if status := motion_target_translation(rt, handle, target.translation, translation_config, translation_mode, rt.motion_time); status != .Ok {
			return status
		}
	}
	if target.has_opacity {
		if status := motion_target_opacity(rt, handle, target.opacity, opacity_config, opacity_mode, rt.motion_time); status != .Ok {
			return status
		}
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
	for _, state in rt.motion_owners {
		status := motion_sample_validate(state, at)
		if status != .Ok { return Motion_Tick_Result{status=status} }
	}
	result := Motion_Tick_Result{status=.Ok}
	for owner, &state in rt.motion_owners {
		changed := false
		owner_active := false
		if state.has_opacity {
			sample := motion_scalar_sample(state.opacity, at)
			presented := motion_clamp_opacity(sample.value)
			if presented != state.presented_opacity { changed = true }
			state.presented_opacity = presented
			state.opacity_active = sample.active
			state.opacity_deadline_established = sample.deadline_established
			if sample.active {
				result.active_properties += 1
				owner_active = true
				if !sample.deadline_established { result.unestablished_deadlines += 1 }
			}
		}
		if state.has_translation {
			sample := motion_translation_sample(state.translation, at)
			x, _ := motion_value_to_f32(sample.value.x)
			y, _ := motion_value_to_f32(sample.value.y)
			presented := [2]f32{x, y}
			if presented != state.presented_translation { changed = true }
			state.presented_translation = presented
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
	}
	rt.motion_time = at
	rt.motion_clock_initialized = true
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
	for _, state in rt.motion_owners {
		if state.opacity_active && !state.opacity_deadline_established {
			if status := motion_sample_validate(state, at); status != .Ok {
				return Motion_Tick_Result{status=status}
			}
		}
		if state.translation_active && !state.translation_deadline_established {
			if status := motion_sample_validate(state, at); status != .Ok {
				return Motion_Tick_Result{status=status}
			}
		}
	}
	result := Motion_Tick_Result{status=.Ok}
	for owner, &state in rt.motion_owners {
		changed := false
		if state.opacity_active && !state.opacity_deadline_established {
			next, status := motion_scalar_snap(state.opacity, state.opacity.target, at)
			if status != .Ok { return Motion_Tick_Result{status=motion_runtime_status(status)} }
			presented := motion_clamp_opacity(next.target)
			changed = changed || presented != state.presented_opacity
			state.opacity = next
			state.presented_opacity = presented
			state.opacity_active = false
			state.opacity_deadline_established = true
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
			state.translation_active = false
			state.translation_deadline_established = true
		}
		if changed { result.changed_owners += 1 }
		_ = owner
	}
	rt.motion_time = at
	rt.motion_clock_initialized = true
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
	delete_key(&rt.motion_owners, owner)
}

// motion_owner_release cancels an owner's current motion, removes its sidecar
// record, and leaves the retained node alive. Releasing resets its presentation
// to the neutral transform and opacity on the next composition; callers that
// need another resting presentation should commit that state before releasing.
motion_owner_release :: proc(rt: ^Runtime, handle: Motion_Owner_Handle) -> Motion_Runtime_Status {
	if rt == nil { return .Invalid_Runtime }
	if !motion_owner_is_current(rt, handle) { return .Stale_Owner }
	state := rt.motion_owners[handle.node]
	visible_change := state.presented_translation != [2]f32{} ||
		(state.has_opacity && state.presented_opacity != 1)
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
