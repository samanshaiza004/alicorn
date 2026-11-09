package alicorn

import "core:math"
import "core:time"

// Style_Transition_Easing defines the time curve for an opted-in visual
// property. It is separate from Motion_Config, which describes spring response.
Style_Transition_Easing :: enum u8 { Linear, Ease }

// Style_Transition is a duration-based policy. A zero duration keeps the
// existing immediate style behavior.
Style_Transition :: struct {
	duration: time.Duration,
	easing: Style_Transition_Easing,
}

STYLE_TRANSITION_MAX_DURATION_NS :: u64(9_000_000_000_000_000_000)

Style_Transition_Segment :: struct {
	start_mix: f64,
	target_mix: f64,
	start_time: Motion_Time,
	duration_ns: u64,
	easing: Style_Transition_Easing,
}

Style_Transition_Sample :: struct {
	mix: f64,
	active: bool,
	ok: bool,
}

// A retained hover-fill owner is independent of Motion_Retained_Owner. The
// resolved endpoint pair and style stamp are captured separately from the
// computed-style cache so inspector reads cannot consume a target change.
Style_Transition_Pair :: struct {
	rest: Button_Resolved_Style,
	hover: Button_Resolved_Style,
	generations: Style_Generations,
	environment: Style_Environment,
	variant: Button_Variant,
	policy: Style_Transition,
}

Style_Transition_Owner :: struct {
	pair: Style_Transition_Pair,
	initialized: bool,
	adopted_hover: bool,
	presented_mix: f64,
	segment: Style_Transition_Segment,
	active: bool,
}

STYLE_TRANSITION_MAX_OWNERS :: 1024

style_transition_is_valid :: proc(transition: Style_Transition) -> bool {
	duration_ns := i64(transition.duration)
	return duration_ns >= 0 && u64(duration_ns) <= STYLE_TRANSITION_MAX_DURATION_NS &&
		(transition.easing == .Linear || transition.easing == .Ease)
}

// style_transition_ease_sample evaluates the output y for normalized input x.
// Ease is the CSS cubic-bezier(0.25, 0.1, 0.25, 1) curve. Bisection solves the
// monotone x curve in a fixed number of steps, keeping sampling deterministic
// and bounded on every platform.
style_transition_ease_sample :: proc(easing: Style_Transition_Easing, progress: f64) -> (value: f64, ok: bool) {
	if !number_is_finite(progress) || progress < 0 || progress > 1 { return 0, false }
	if easing == .Linear { return progress, true }
	if easing != .Ease { return 0, false }
	if progress == 0 || progress == 1 { return progress, true }
	low, high := f64(0), f64(1)
	for _ in 0..<32 {
		parameter := (low+high)*0.5
		x := style_transition_bezier(parameter, 0.25, 0.25)
		if x < progress { low = parameter } else { high = parameter }
	}
	parameter := (low+high)*0.5
	return style_transition_bezier(parameter, 0.1, 1), true
}

style_transition_bezier :: proc(parameter, first_control, second_control: f64) -> f64 {
	one_minus := 1-parameter
	return 3*one_minus*one_minus*parameter*first_control +
		3*one_minus*parameter*parameter*second_control + parameter*parameter*parameter
}

style_transition_segment_sample :: proc(
	segment: Style_Transition_Segment,
	at: Motion_Time,
) -> Style_Transition_Sample {
	if !number_is_finite(segment.start_mix) || !number_is_finite(segment.target_mix) ||
		segment.start_mix < 0 || segment.start_mix > 1 || segment.target_mix < 0 || segment.target_mix > 1 ||
		segment.duration_ns == 0 || segment.duration_ns > STYLE_TRANSITION_MAX_DURATION_NS ||
		(segment.easing != .Linear && segment.easing != .Ease) || i64(at) < i64(segment.start_time) {
		return {}
	}
	// Unsigned subtraction preserves the exact positive distance across zero.
	elapsed_ns := u64(i64(at))-u64(i64(segment.start_time))
	if elapsed_ns >= segment.duration_ns {
		return Style_Transition_Sample{mix=segment.target_mix, active=false, ok=true}
	}
	progress := f64(elapsed_ns)/f64(segment.duration_ns)
	eased, ok := style_transition_ease_sample(segment.easing, progress)
	if !ok { return {} }
	mix := segment.start_mix+(segment.target_mix-segment.start_mix)*eased
	if math.is_nan(mix) || math.is_inf(mix) { return {} }
	return Style_Transition_Sample{mix=clamp(mix, f64(0), f64(1)), active=true, ok=true}
}

// style_transition_reversal_duration shortens a reversal in proportion to
// remaining visual distance. Callers retain the original endpoint pair and
// sample the previous segment before creating the reversed segment.
style_transition_reversal_duration :: proc(
	full_duration_ns: u64,
	presented_mix, target_mix: f64,
) -> (duration_ns: u64, ok: bool) {
	if full_duration_ns == 0 || full_duration_ns > STYLE_TRANSITION_MAX_DURATION_NS ||
		!number_is_finite(presented_mix) || !number_is_finite(target_mix) ||
		presented_mix < 0 || presented_mix > 1 || target_mix < 0 || target_mix > 1 {
		return 0, false
	}
	remaining := abs(target_mix-presented_mix)
	if remaining == 0 { return 0, true }
	scaled := f64(full_duration_ns)*remaining
	if !number_is_finite(scaled) || scaled > f64(STYLE_TRANSITION_MAX_DURATION_NS) { return 0, false }
	duration_ns = u64(scaled)
	if duration_ns == 0 { duration_ns = 1 }
	return duration_ns, true
}

style_transition_button_pair :: proc(rt: ^Runtime, node: ^Node, policy: Style_Transition) -> Style_Transition_Pair {
	return Style_Transition_Pair{
		rest=style_button_resolve(rt, node.style_environment, node.button_variant, Button_Visual_State{}),
		hover=style_button_resolve(rt, node.style_environment, node.button_variant, Button_Visual_State{hovered=true}),
		generations=node.style_generations,
		environment=node.style_environment,
		variant=node.button_variant,
		policy=policy,
	}
}

style_transition_button_pair_is_eligible :: proc(pair: Style_Transition_Pair) -> bool {
	return style_transition_is_valid(pair.policy) && pair.policy.duration > 0 &&
		pair.rest.surface != pair.hover.surface &&
		pair.rest.surface.a == 1 && pair.hover.surface.a == 1 &&
		pair.rest.text == pair.hover.text &&
		pair.rest.material == MATERIAL_FLAT && pair.hover.material == MATERIAL_FLAT &&
		pair.rest.shape == pair.hover.shape &&
		pair.rest.physical_height == pair.hover.physical_height
}

style_transition_pair_matches :: proc(left, right: Style_Transition_Pair) -> bool {
	return left.rest == right.rest && left.hover == right.hover &&
		left.generations == right.generations && left.environment == right.environment &&
		left.variant == right.variant && left.policy == right.policy
}

style_transition_diagnostic_record :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	kind: Motion_Diagnostic_Kind,
	reason: Motion_Diagnostic_Reason,
	mix: f64,
	target_hovered: bool,
	duration_ns: u64 = 0,
) {
	diagnostics := motion_diagnostics_ensure(rt)
	if diagnostics == nil { return }
	diagnostics.revision += 1
	diagnostics.sequence += 1
	event := Motion_Diagnostic_Event{
		sequence=diagnostics.sequence,
		time=rt.motion_time,
		clock_source=rt.motion_clock_source,
		kind=kind,
		reason=reason,
		owner=motion_diagnostics_owner_snapshot(rt, owner),
		style_transition_sample=true,
		style_transition_mix=mix,
		style_transition_target_hovered=target_hovered,
		style_transition_duration_ns=duration_ns,
		repeat_count=1,
	}
	diagnostics.events[diagnostics.next] = event
	diagnostics.next = (diagnostics.next+1) % MOTION_DIAGNOSTIC_EVENT_CAPACITY
	if diagnostics.count < MOTION_DIAGNOSTIC_EVENT_CAPACITY { diagnostics.count += 1 }
	else { diagnostics.stats.trace_evictions += 1 }
	#partial switch kind {
	case .Style_Transition_Retarget: diagnostics.stats.style_transition_retargets += 1
	case .Style_Transition_Settled: diagnostics.stats.style_transition_settlements += 1
	case .Style_Transition_Snap: diagnostics.stats.style_transition_snaps += 1
	}
}

style_transition_owner_snap :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	reason: Motion_Diagnostic_Reason,
	target_hovered: bool,
) {
	if rt == nil || rt.style_transition_owners == nil { return }
	track, found := rt.style_transition_owners[owner]
	if found && track.active {
		style_transition_diagnostic_record(
			rt, owner, .Style_Transition_Snap, reason,
			track.presented_mix, target_hovered,
		)
	}
	delete_key(&rt.style_transition_owners, owner)
}

// style_transition_button_fill returns the sampled fill for an eligible
// ordinary Button. Unsupported states snap to the style resolver's target.
style_transition_button_fill :: proc(
	rt: ^Runtime,
	node: ^Node,
	resolved: Button_Resolved_Style,
	hovered: bool,
) -> Color {
	if rt == nil || node == nil { return resolved.surface }
	policy := style_button_recipe(rt, node.style_environment, node.button_variant).hover_fill_transition
	preferences := node.style_environment.accessibility
	if node.disabled || node.selected || node.pressed || node.drop_position != .None {
		style_transition_owner_snap(rt, node.id, .Style_Transition_Interaction_State, hovered)
		return resolved.surface
	}
	if preferences.reduce_motion || preferences.increased_contrast || preferences.differentiate_without_color {
		style_transition_owner_snap(rt, node.id, .Style_Transition_Accessibility_Preference, hovered)
		return resolved.surface
	}
	if !rt.motion_clock_initialized {
		style_transition_owner_snap(rt, node.id, .Style_Transition_No_Clock, hovered)
		return resolved.surface
	}
	if !style_transition_is_valid(policy) {
		style_transition_owner_snap(rt, node.id, .Style_Transition_Invalid_Policy, hovered)
		return resolved.surface
	}
	if policy.duration <= 0 {
		style_transition_owner_cancel(rt, node.id)
		return resolved.surface
	}
	pair := style_transition_button_pair(rt, node, policy)
	if !style_transition_button_pair_is_eligible(pair) {
		style_transition_owner_snap(rt, node.id, .Style_Transition_Style_Changed, hovered)
		return resolved.surface
	}
	if rt.style_transition_owners == nil {
		rt.style_transition_owners = make(map[Node_ID]Style_Transition_Owner, allocator=rt.persistent_allocator)
	}
	track, found := rt.style_transition_owners[node.id]
	if !found {
		if len(rt.style_transition_owners) >= STYLE_TRANSITION_MAX_OWNERS { return resolved.surface }
		initial_mix := f64(0)
		if hovered { initial_mix = 1 }
		track = Style_Transition_Owner{
			pair=pair,
			initialized=true,
			adopted_hover=hovered,
			presented_mix=initial_mix,
		}
		rt.style_transition_owners[node.id] = track
		return style_color_mix(pair.rest.surface, pair.hover.surface, f32(initial_mix))
	}
	if !track.initialized || !style_transition_pair_matches(track.pair, pair) {
		style_transition_owner_snap(rt, node.id, .Style_Transition_Style_Changed, hovered)
		initial_mix := f64(0)
		if hovered { initial_mix = 1 }
		track = Style_Transition_Owner{
			pair=pair,
			initialized=true,
			adopted_hover=hovered,
			presented_mix=initial_mix,
		}
		rt.style_transition_owners[node.id] = track
		return style_color_mix(pair.rest.surface, pair.hover.surface, f32(initial_mix))
	}
	if hovered != track.adopted_hover {
		if track.active {
			sample := style_transition_segment_sample(track.segment, rt.motion_time)
			if sample.ok { track.presented_mix = sample.mix }
		}
		target_mix := f64(0)
		if hovered { target_mix = 1 }
		full_duration_ns := u64(i64(policy.duration))
		duration_ns, ok := style_transition_reversal_duration(full_duration_ns, track.presented_mix, target_mix)
		track.adopted_hover = hovered
		if ok && duration_ns > 0 {
			track.segment = Style_Transition_Segment{
				start_mix=track.presented_mix,
				target_mix=target_mix,
				start_time=rt.motion_time,
				duration_ns=duration_ns,
				easing=policy.easing,
			}
			track.active = true
		} else {
			track.presented_mix = target_mix
			track.active = false
		}
		rt.style_transition_owners[node.id] = track
		style_transition_diagnostic_record(
			rt, node.id, .Style_Transition_Retarget, .None,
			track.presented_mix, hovered, duration_ns,
		)
	}
	return style_color_mix(pair.rest.surface, pair.hover.surface, f32(track.presented_mix))
}

style_transition_owner_cancel :: proc(rt: ^Runtime, owner: Node_ID) {
	if rt != nil && rt.style_transition_owners != nil { delete_key(&rt.style_transition_owners, owner) }
}

style_transition_request_owner_paint :: proc(rt: ^Runtime, owner: Node_ID) {
	node, found := rt.nodes[owner]
	if !found || node == nil || !node.active || !node.present { return }
	dirty_set(&node.dirty, .Paint, true)
	dirty_set(&node.dirty, .Composite, true)
	queue_paint(rt, owner)
}
