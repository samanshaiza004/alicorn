package alicorn

import "core:testing"

style_transition_test_near :: proc(a, b, epsilon: f64) -> bool {
	return abs(a-b) <= epsilon
}

@(test)
test_style_transition_easing_matches_declared_css_curves :: proc(t: ^testing.T) {
	linear, linear_ok := style_transition_ease_sample(.Linear, 0.3)
	eased, ease_ok := style_transition_ease_sample(.Ease, 0.3)
	testing.expect(t, linear_ok && style_transition_test_near(linear, 0.3, 0.000001),
		"linear transition should preserve normalized time")
	testing.expect(t, ease_ok && style_transition_test_near(eased, 0.5133, 0.001),
		"CSS ease should solve the cubic Bezier x coordinate before evaluating y")
	start, start_ok := style_transition_ease_sample(.Ease, 0)
	end, end_ok := style_transition_ease_sample(.Ease, 1)
	testing.expect(t, start_ok && end_ok && start == 0 && end == 1,
		"timing curves should preserve exact endpoints")
}

@(test)
test_style_transition_reversal_uses_eased_progress_and_fixed_endpoints :: proc(t: ^testing.T) {
	segment := Style_Transition_Segment{
		start_mix=0,
		target_mix=1,
		start_time=Motion_Time(0),
		duration_ns=300_000_000,
		easing=.Ease,
	}
	sample := style_transition_segment_sample(segment, Motion_Time(90_000_000))
	return_duration, duration_ok := style_transition_reversal_duration(300_000_000, sample.mix, 0)
	testing.expect(t, sample.ok && sample.active && style_transition_test_near(sample.mix, 0.5133, 0.001),
		"a 30 percent elapsed CSS ease segment should sample its eased visual progress")
	testing.expect(t, duration_ok && return_duration >= 153_000_000 && return_duration <= 155_000_000,
		"reversal duration should be the original duration times remaining visual distance")
	reversed := Style_Transition_Segment{
		start_mix=sample.mix,
		target_mix=0,
		start_time=Motion_Time(90_000_000),
		duration_ns=return_duration,
		easing=.Ease,
	}
	reversed_later := style_transition_segment_sample(reversed, Motion_Time(140_000_000))
	testing.expect(t, reversed_later.ok && reversed_later.active && reversed_later.mix > 0 && reversed_later.mix < sample.mix,
		"repeated reversals should continue on the fixed original color pair without a jump")
	finished := style_transition_segment_sample(reversed, Motion_Time(90_000_000+i64(return_duration)+10_000_000))
	testing.expect(t, finished.ok && !finished.active && finished.mix == 0,
		"a late sample should present the exact endpoint and settle")
}
