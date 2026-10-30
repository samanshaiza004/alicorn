package alicorn

import "core:math"

// This file contains a headless, allocation-free analytic motion kernel.
// Application state remains authoritative; a response only calculates a
// transient presentation between explicit state changes.

// Motion_Time is a signed nanosecond timestamp from an arbitrary monotonic
// origin. It is intentionally independent of core:time so callers can inject
// timestamps and replay motion deterministically. Timestamps may be negative.
Motion_Time :: distinct i64

// Motion_Config defines a critically damped response. Omega is in reciprocal
// seconds; tolerances are componentwise presentation and velocity thresholds.
Motion_Config :: struct {
	// Angular frequency in reciprocal seconds. This is the critically damped
	// response rate, not a duration or a frame-dependent stiffness.
	omega: f64,
	position_tolerance: f64,
	velocity_tolerance: f64,
}

Motion_Mode :: enum {
	// Analytically converge on a discrete target, preserving position and
	// velocity when a new target is supplied.
	Settle,
	// Present each supplied target immediately without transient velocity.
	Direct,
	// Commit one target immediately and clear all transient motion.
	Snap,
}

Motion_Status :: enum {
	Ok,
	Invalid_Response,
	Invalid_Configuration,
	Invalid_Value,
	Time_Rewound,
	Numeric_Overflow,
}

Motion_Scalar_Response :: struct {
	initialized: bool,
	mode: Motion_Mode,
	// Exact presentation at start_time, kept separately because target+r0 can
	// round differently when a large target is paired with a small residual.
	presented_0: f64,
	target: f64,
	residual_0: f64,
	velocity_0: f64,
	config: Motion_Config,
	start_time: Motion_Time,
	// Relative to start_time, never an absolute timestamp. If no conservative
	// deadline fits the supported horizon, samples remain active until a Direct
	// or Snap transition explicitly retires the response.
	settle_after_ns: u64,
	deadline_established: bool,
}

Motion_Scalar_Sample :: struct {
	value: f64,
	velocity: f64,
	active: bool,
	settled: bool,
	deadline_established: bool,
	status: Motion_Status,
}

Motion_Vector2 :: struct {
	x, y: f64,
}

// The two components share the same config, mode, and timestamps. They keep
// the scalar representation so evaluation and retargeting have one formula.
Motion_Translation_Response :: struct {
	x, y: Motion_Scalar_Response,
}

Motion_Translation_Sample :: struct {
	value, velocity: Motion_Vector2,
	active: bool,
	settled: bool,
	deadline_established: bool,
	status: Motion_Status,
}

MOTION_MAX_SETTLE_NS :: u64(9_000_000_000_000_000_000)
MOTION_NS_PER_SECOND :: f64(1_000_000_000)
MOTION_MAX_SETTLE_SECONDS :: f64(9_000_000_000)
MOTION_LOG_F64_MAX :: f64(709.782712893384)

motion_finite :: proc(value: f64) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

motion_config_valid :: proc(config: Motion_Config) -> bool {
	return motion_finite(config.omega) && config.omega > 0 &&
		motion_finite(config.position_tolerance) && config.position_tolerance > 0 &&
		motion_finite(config.velocity_tolerance) && config.velocity_tolerance > 0
}

// motion_log_sum_positive returns log(exp(log_a)+exp(log_b)) without forming
// either potentially enormous positive value. Missing terms are ignored.
motion_log_sum_positive :: proc(
	log_a, log_b: f64,
	has_a, has_b: bool,
) -> (log_sum: f64, has_sum: bool) {
	if !has_a { return log_b, has_b }
	if !has_b { return log_a, true }
	hi := max(log_a, log_b)
	lo := min(log_a, log_b)
	return hi + math.ln(1 + math.exp(lo-hi)), true
}

// motion_log_envelope_below checks (a+c*t)*exp(-omega*t) <= tolerance in
// log space. This avoids overflow in a+c*t and underflow that could otherwise
// make an unsafe bound look smaller than its tolerance.
motion_log_envelope_below :: proc(
	log_a, log_c: f64,
	has_a, has_c: bool,
	omega, seconds, tolerance: f64,
) -> bool {
	log_ct := f64(0)
	has_ct := has_c && seconds > 0
	if has_ct { log_ct = log_c + math.ln(seconds) }
	log_sum, has_sum := motion_log_sum_positive(log_a, log_ct, has_a, has_ct)
	if !has_sum { return true }
	x := omega * seconds
	if math.is_inf(x) { return true }
	return log_sum-x <= math.ln(tolerance)
}

motion_envelopes_below :: proc(
	log_position_a, log_position_c: f64,
	has_position_a, has_position_c: bool,
	log_velocity_a, log_velocity_c: f64,
	has_velocity_a, has_velocity_c: bool,
	config: Motion_Config,
	seconds: f64,
) -> bool {
	return motion_log_envelope_below(
		log_position_a, log_position_c, has_position_a, has_position_c,
		config.omega, seconds, config.position_tolerance,
	) && motion_log_envelope_below(
		log_velocity_a, log_velocity_c, has_velocity_a, has_velocity_c,
		config.omega, seconds, config.velocity_tolerance,
	)
}

motion_deadline_predicate :: proc(
	seconds: f64,
	log_r, log_b: f64,
	has_r, has_b: bool,
	log_v, log_omega_b: f64,
	has_v: bool,
	config: Motion_Config,
) -> bool {
	return motion_envelopes_below(
		log_r, log_b, has_r, has_b,
		log_v, log_omega_b, has_v, has_b,
		config, seconds,
	)
}

// motion_certified_deadline computes a conservative relative deadline. Both
// envelopes are nonincreasing after 1/omega, so the bounded search only
// brackets and bisects inside that tail. Failure to establish a deadline in
// the supported time horizon leaves the response valid but explicitly
// unretired; it is not treated as an invalid parameter or snapped early.
motion_certified_deadline :: proc(
	residual, velocity: f64,
	config: Motion_Config,
) -> (deadline_ns: u64, established: bool) {
	if residual == 0 && velocity == 0 { return 0, true }

	log_omega := math.ln(config.omega)
	log_r, has_r := f64(0), residual != 0
	log_v, has_v := f64(0), velocity != 0
	if has_r { log_r = math.ln(abs(residual)) }
	if has_v { log_v = math.ln(abs(velocity)) }
	log_omega_r := log_omega + log_r
	log_b, has_b := motion_log_sum_positive(log_v, log_omega_r, has_v, has_r)
	log_omega_b := log_omega + log_b

	tail_start := 1 / config.omega
	if !motion_finite(tail_start) || tail_start > MOTION_MAX_SETTLE_SECONDS {
		return 0, false
	}
	hi := tail_start
	if !motion_deadline_predicate(hi, log_r, log_b, has_r, has_b, log_v, log_omega_b, has_v, config) {
		lo := hi
		hi = max(hi*2, f64(1)/MOTION_NS_PER_SECOND)
		found := false
		for _ in 0..<128 {
			if hi > MOTION_MAX_SETTLE_SECONDS { hi = MOTION_MAX_SETTLE_SECONDS }
			if motion_deadline_predicate(hi, log_r, log_b, has_r, has_b, log_v, log_omega_b, has_v, config) {
				found = true
				break
			}
			if hi >= MOTION_MAX_SETTLE_SECONDS { return 0, false }
			lo = hi
			hi = min(hi*2, MOTION_MAX_SETTLE_SECONDS)
		}
		if !found { return 0, false }

		// hi is certified and lo is not. The predicate is monotone in this
		// tail, so each midpoint narrows a safe upper bracket.
		for _ in 0..<64 {
			mid := lo + (hi-lo)*0.5
			if mid <= lo || mid >= hi { break }
			if motion_deadline_predicate(mid, log_r, log_b, has_r, has_b, log_v, log_omega_b, has_v, config) { hi = mid } else { lo = mid }
		}
	}

	// Round conservatively across f64-to-nanosecond conversion. The small
	// relative margin is far above f64 ulp error and remains negligible for UI
	// response times; at least one nanosecond is retained for nonzero motion.
	deadline_seconds := hi + max(f64(1)/MOTION_NS_PER_SECOND, hi*1e-12)
	if !motion_finite(deadline_seconds) || deadline_seconds > MOTION_MAX_SETTLE_SECONDS {
		return 0, false
	}
	rounded_ns := math.ceil(deadline_seconds * MOTION_NS_PER_SECOND)
	if !motion_finite(rounded_ns) || rounded_ns > f64(MOTION_MAX_SETTLE_NS) {
		return 0, false
	}
	if rounded_ns < 1 { rounded_ns = 1 }
	return u64(rounded_ns), true
}

motion_scalar_create :: proc(
	from, target, initial_velocity: f64,
	config: Motion_Config,
	start: Motion_Time,
) -> (response: Motion_Scalar_Response, status: Motion_Status) {
	if !motion_config_valid(config) { return {}, .Invalid_Configuration }
	if !motion_finite(from) || !motion_finite(target) || !motion_finite(initial_velocity) {
		return {}, .Invalid_Value
	}
	residual := from-target
	if !motion_finite(residual) { return {}, .Numeric_Overflow }
	deadline_ns, established := motion_certified_deadline(residual, initial_velocity, config)
	return Motion_Scalar_Response{
		initialized=true,
		mode=.Settle,
		presented_0=from,
		target=target,
		residual_0=residual,
		velocity_0=initial_velocity,
		config=config,
		start_time=start,
		settle_after_ns=deadline_ns,
		deadline_established=established,
	}, .Ok
}

// motion_signed_exp_sum evaluates (a*exp(scale_a)+b*exp(scale_b))*exp(-x)
// using a shared logarithmic scale. This avoids overflowing an intermediate
// polynomial before exponential decay is applied.
motion_signed_exp_sum :: proc(
	a, scale_a, b, scale_b, x: f64,
	has_a, has_b: bool,
) -> (value: f64, ok: bool) {
	log_a, log_b := f64(0), f64(0)
	if has_a { log_a = math.ln(abs(a)) + scale_a - x }
	if has_b { log_b = math.ln(abs(b)) + scale_b - x }
	if !has_a && !has_b { return 0, true }
	if !has_b { log_b = log_a }
	if !has_a { log_a = log_b }
	hi := max(log_a, log_b)
	a_scaled, b_scaled := f64(0), f64(0)
	if has_a { a_scaled = (1 if a > 0 else -1) * math.exp(log_a-hi) }
	if has_b { b_scaled = (1 if b > 0 else -1) * math.exp(log_b-hi) }
	sum := a_scaled+b_scaled
	if sum == 0 { return 0, true }
	log_result := hi + math.ln(abs(sum))
	if math.is_nan(log_result) || log_result > MOTION_LOG_F64_MAX { return 0, false }
	result := math.exp(log_result)
	if !motion_finite(result) { return 0, false }
	if sum < 0 { result = -result }
	return result, true
}

motion_signed_exp_sum3 :: proc(
	a, scale_a, b, scale_b, c, scale_c: f64,
	has_a, has_b, has_c: bool,
) -> (value: f64, ok: bool) {
	log_a, log_b, log_c := f64(0), f64(0), f64(0)
	has_log_a, has_log_b, has_log_c := false, false, false
	if has_a && a != 0 { log_a, has_log_a = math.ln(abs(a))+scale_a, true }
	if has_b && b != 0 { log_b, has_log_b = math.ln(abs(b))+scale_b, true }
	if has_c && c != 0 { log_c, has_log_c = math.ln(abs(c))+scale_c, true }
	if !has_log_a && !has_log_b && !has_log_c { return 0, true }
	hi := f64(0)
	if has_log_a { hi = log_a }
	if has_log_b { hi = log_b if !has_log_a else max(hi, log_b) }
	if has_log_c { hi = log_c if !has_log_a && !has_log_b else max(hi, log_c) }
	sum := f64(0)
	if has_log_a { sum += (1 if a > 0 else -1) * math.exp(log_a-hi) }
	if has_log_b { sum += (1 if b > 0 else -1) * math.exp(log_b-hi) }
	if has_log_c { sum += (1 if c > 0 else -1) * math.exp(log_c-hi) }
	if sum == 0 { return 0, true }
	log_result := hi + math.ln(abs(sum))
	if math.is_nan(log_result) || log_result > MOTION_LOG_F64_MAX { return 0, false }
	result := math.exp(log_result)
	if !motion_finite(result) { return 0, false }
	if sum < 0 { result = -result }
	return result, true
}

// motion_one_minus_linear_decay evaluates 1-(1+x)e^-x without cancellation
// near zero. The Taylor series converges rapidly in this small-x interval.
motion_one_minus_linear_decay :: proc(x: f64) -> f64 {
	if x == 0 { return 0 }
	if x <= 0.5 {
		term := x*x*0.5
		sum := term
		for n in 3..=14 {
			term *= -x * f64(n-1) / (f64(n)*f64(n-2))
			sum += term
		}
		return max(0, min(1, sum))
	}
	return 1 - (1+x)*math.exp(-x)
}

motion_scalar_evaluate :: proc(response: Motion_Scalar_Response, seconds: f64) -> (value, velocity: f64, ok: bool) {
	if seconds == 0 { return response.presented_0, response.velocity_0, true }
	x := response.config.omega * seconds
	if math.is_inf(x) { return response.target, 0, true }
	decay := math.exp(-x)
	one_minus_q := motion_one_minus_linear_decay(x)
	q := 1-one_minus_q
	if x > 0.5 { q = (1+x)*decay; one_minus_q = 1-q }
	velocity_scale := math.ln(seconds)-x
	presented, presented_ok := motion_signed_exp_sum3(
		response.presented_0, math.ln(q),
		response.target, math.ln(one_minus_q),
		response.velocity_0, velocity_scale,
		q > 0, one_minus_q > 0, response.velocity_0 != 0,
	)
	if !presented_ok { return 0, 0, false }

	// V(t) = (v0*(1-omega*t) - omega*r0*(omega*t)) * exp(-omega*t).
	velocity_factor := 1-x
	velocity_first := response.velocity_0
	if velocity_factor < 0 { velocity_first = -velocity_first }
	velocity_first_scale := math.ln(abs(velocity_factor)) if velocity_factor != 0 else 0
	velocity_second_scale := math.ln(response.config.omega) + math.ln(x) if x > 0 else 0
	computed_velocity, velocity_ok := motion_signed_exp_sum(
		velocity_first, velocity_first_scale,
		-response.residual_0, velocity_second_scale,
		x, response.velocity_0 != 0 && velocity_factor != 0,
		response.residual_0 != 0 && x > 0,
	)
	if !velocity_ok { return 0, 0, false }
	return presented, computed_velocity, true
}

// motion_scalar_sample is pure. It returns the exact target and zero velocity
// at or beyond a precomputed conservative deadline; it never mutates response.
motion_scalar_sample :: proc(response: Motion_Scalar_Response, at: Motion_Time) -> Motion_Scalar_Sample {
	if !response.initialized || !motion_config_valid(response.config) {
		return Motion_Scalar_Sample{status=.Invalid_Response}
	}
	start_ns, now_ns := i64(response.start_time), i64(at)
	if now_ns < start_ns { return Motion_Scalar_Sample{status=.Time_Rewound} }
	// Unsigned subtraction preserves the exact positive difference even when
	// valid signed timestamps straddle zero or the signed range.
	elapsed_ns := u64(now_ns)-u64(start_ns)
	if response.mode != .Settle ||
		(response.deadline_established && elapsed_ns >= response.settle_after_ns) {
		return Motion_Scalar_Sample{
			value=response.target,
			velocity=0,
			active=false,
			settled=true,
			deadline_established=response.deadline_established,
			status=.Ok,
		}
	}
	if elapsed_ns == 0 {
		return Motion_Scalar_Sample{
			value=response.presented_0,
			velocity=response.velocity_0,
			active=true,
			settled=false,
			deadline_established=response.deadline_established,
			status=.Ok,
		}
	}
	seconds := f64(elapsed_ns)/MOTION_NS_PER_SECOND
	value, velocity, ok := motion_scalar_evaluate(response, seconds)
	if !ok { return Motion_Scalar_Sample{status=.Numeric_Overflow} }
	if !motion_finite(value) || !motion_finite(velocity) {
		return Motion_Scalar_Sample{status=.Numeric_Overflow}
	}
	return Motion_Scalar_Sample{
		value=value,
		velocity=velocity,
		active=true,
		settled=false,
		deadline_established=response.deadline_established,
		status=.Ok,
	}
}

motion_scalar_settle :: proc(
	response: Motion_Scalar_Response,
	target: f64,
	at: Motion_Time,
) -> (next: Motion_Scalar_Response, status: Motion_Status) {
	if !response.initialized { return response, .Invalid_Response }
	if !motion_finite(target) { return response, .Invalid_Value }
	if response.mode == .Settle && response.target == target { return response, .Ok }
	if i64(at) < i64(response.start_time) { return response, .Time_Rewound }
	current := motion_scalar_sample(response, at)
	if current.status != .Ok { return response, current.status }
	return motion_scalar_create(current.value, target, current.velocity, response.config, at)
}

motion_scalar_direct :: proc(
	response: Motion_Scalar_Response,
	target: f64,
	at: Motion_Time,
) -> (next: Motion_Scalar_Response, status: Motion_Status) {
	if !response.initialized { return response, .Invalid_Response }
	if !motion_finite(target) { return response, .Invalid_Value }
	if response.mode == .Direct && response.target == target { return response, .Ok }
	if i64(at) < i64(response.start_time) { return response, .Time_Rewound }
	next = response
	next.mode = .Direct
	next.presented_0 = target
	next.target = target
	next.residual_0 = 0
	next.velocity_0 = 0
	next.start_time = at
	next.settle_after_ns = 0
	next.deadline_established = true
	return next, .Ok
}

motion_scalar_snap :: proc(
	response: Motion_Scalar_Response,
	target: f64,
	at: Motion_Time,
) -> (next: Motion_Scalar_Response, status: Motion_Status) {
	if !response.initialized { return response, .Invalid_Response }
	if !motion_finite(target) { return response, .Invalid_Value }
	if response.mode == .Snap && response.target == target { return response, .Ok }
	if i64(at) < i64(response.start_time) { return response, .Time_Rewound }
	next = response
	next.mode = .Snap
	next.presented_0 = target
	next.target = target
	next.residual_0 = 0
	next.velocity_0 = 0
	next.start_time = at
	next.settle_after_ns = 0
	next.deadline_established = true
	return next, .Ok
}

motion_translation_create :: proc(
	from, target, initial_velocity: Motion_Vector2,
	config: Motion_Config,
	start: Motion_Time,
) -> (response: Motion_Translation_Response, status: Motion_Status) {
	x, x_status := motion_scalar_create(from.x, target.x, initial_velocity.x, config, start)
	if x_status != .Ok { return {}, x_status }
	y, y_status := motion_scalar_create(from.y, target.y, initial_velocity.y, config, start)
	if y_status != .Ok { return {}, y_status }
	response = Motion_Translation_Response{x=x, y=y}
	motion_translation_share_deadline(&response)
	return response, .Ok
}

motion_translation_share_deadline :: proc(response: ^Motion_Translation_Response) {
	if !response.x.deadline_established || !response.y.deadline_established {
		response.x.deadline_established = false
		response.y.deadline_established = false
		response.x.settle_after_ns = 0
		response.y.settle_after_ns = 0
		return
	}
	deadline := max(response.x.settle_after_ns, response.y.settle_after_ns)
	response.x.settle_after_ns = deadline
	response.y.settle_after_ns = deadline
}

motion_translation_sample :: proc(response: Motion_Translation_Response, at: Motion_Time) -> Motion_Translation_Sample {
	x := motion_scalar_sample(response.x, at)
	if x.status != .Ok { return Motion_Translation_Sample{status=x.status} }
	y := motion_scalar_sample(response.y, at)
	if y.status != .Ok { return Motion_Translation_Sample{status=y.status} }
	active := x.active || y.active
	return Motion_Translation_Sample{
		value=Motion_Vector2{x.value, y.value},
		velocity=Motion_Vector2{x.velocity, y.velocity},
		active=active,
		settled=!active,
		deadline_established=x.deadline_established && y.deadline_established,
		status=.Ok,
	}
}

motion_translation_settle :: proc(
	response: Motion_Translation_Response,
	target: Motion_Vector2,
	at: Motion_Time,
) -> (next: Motion_Translation_Response, status: Motion_Status) {
	if !response.x.initialized || !response.y.initialized { return response, .Invalid_Response }
	if !motion_finite(target.x) || !motion_finite(target.y) { return response, .Invalid_Value }
	if response.x.mode == .Settle && response.y.mode == .Settle &&
		response.x.target == target.x && response.y.target == target.y { return response, .Ok }
	current := motion_translation_sample(response, at)
	if current.status != .Ok { return response, current.status }
	next, status = motion_translation_create(current.value, target, current.velocity, response.x.config, at)
	if status != .Ok { return response, status }
	return next, .Ok
}

motion_translation_direct :: proc(
	response: Motion_Translation_Response,
	target: Motion_Vector2,
	at: Motion_Time,
) -> (next: Motion_Translation_Response, status: Motion_Status) {
	if !response.x.initialized || !response.y.initialized { return response, .Invalid_Response }
	if !motion_finite(target.x) || !motion_finite(target.y) { return response, .Invalid_Value }
	if response.x.mode == .Direct && response.y.mode == .Direct &&
		response.x.target == target.x && response.y.target == target.y { return response, .Ok }
	if i64(at) < i64(response.x.start_time) || i64(at) < i64(response.y.start_time) { return response, .Time_Rewound }
	next = response
	next.x.mode, next.y.mode = .Direct, .Direct
	next.x.presented_0, next.y.presented_0 = target.x, target.y
	next.x.target, next.y.target = target.x, target.y
	next.x.residual_0, next.y.residual_0 = 0, 0
	next.x.velocity_0, next.y.velocity_0 = 0, 0
	next.x.start_time, next.y.start_time = at, at
	next.x.settle_after_ns, next.y.settle_after_ns = 0, 0
	next.x.deadline_established, next.y.deadline_established = true, true
	return next, .Ok
}

motion_translation_snap :: proc(
	response: Motion_Translation_Response,
	target: Motion_Vector2,
	at: Motion_Time,
) -> (next: Motion_Translation_Response, status: Motion_Status) {
	if !response.x.initialized || !response.y.initialized { return response, .Invalid_Response }
	if !motion_finite(target.x) || !motion_finite(target.y) { return response, .Invalid_Value }
	if response.x.mode == .Snap && response.y.mode == .Snap &&
		response.x.target == target.x && response.y.target == target.y { return response, .Ok }
	if i64(at) < i64(response.x.start_time) || i64(at) < i64(response.y.start_time) { return response, .Time_Rewound }
	next = response
	next.x.mode, next.y.mode = .Snap, .Snap
	next.x.presented_0, next.y.presented_0 = target.x, target.y
	next.x.target, next.y.target = target.x, target.y
	next.x.residual_0, next.y.residual_0 = 0, 0
	next.x.velocity_0, next.y.velocity_0 = 0, 0
	next.x.start_time, next.y.start_time = at, at
	next.x.settle_after_ns, next.y.settle_after_ns = 0, 0
	next.x.deadline_established, next.y.deadline_established = true, true
	return next, .Ok
}
