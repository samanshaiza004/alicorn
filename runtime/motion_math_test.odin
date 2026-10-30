package alicorn

import "core:math"
import "core:testing"

motion_test_near :: proc(a, b, tolerance: f64) -> bool {
	return abs(a-b) <= tolerance
}

MOTION_TEST_CONFIG :: Motion_Config{
	omega=4,
	position_tolerance=0.001,
	velocity_tolerance=0.001,
}

@(test)
test_motion_scalar_matches_closed_form_and_retargets_continuously :: proc(t: ^testing.T) {
	response, status := motion_scalar_create(10, 0, 0, MOTION_TEST_CONFIG, Motion_Time(0))
	testing.expect(t, status == .Ok, "valid scalar response should initialize")
	quarter_second := motion_scalar_sample(response, Motion_Time(250_000_000))
	expected_position := f64(20) * math.exp(f64(-1))
	expected_velocity := f64(-40) * math.exp(f64(-1))
	testing.expect(t, quarter_second.status == .Ok && quarter_second.active, "response should be active before its certified deadline")
	testing.expect(t, motion_test_near(quarter_second.value, expected_position, 1e-12), "position should match the closed-form critical response")
	testing.expect(t, motion_test_near(quarter_second.velocity, expected_velocity, 1e-12), "velocity should match the closed-form critical response")

	retargeted, retarget_status := motion_scalar_settle(response, 5, Motion_Time(250_000_000))
	testing.expect(t, retarget_status == .Ok, "retarget should succeed")
	after := motion_scalar_sample(retargeted, Motion_Time(250_000_000))
	testing.expect(t, after.status == .Ok && motion_test_near(after.value, quarter_second.value, 1e-12) &&
		motion_test_near(after.velocity, quarter_second.velocity, 1e-12),
		"retargeting must preserve presented position and velocity")
}

@(test)
test_motion_certified_deadline_is_independent_of_sample_history :: proc(t: ^testing.T) {
	config := Motion_Config{omega=20, position_tolerance=0.004, velocity_tolerance=0.06}
	response, status := motion_scalar_create(1, 0, 0, config, Motion_Time(-2_000_000_000))
	testing.expect(t, status == .Ok && response.deadline_established, "the ordinary response should have a certified deadline")
	deadline := response.settle_after_ns
	testing.expect(t, deadline <= 400_000_000, "the conservative envelope should certify settlement by 400 ms")
	at_deadline := motion_scalar_sample(response, Motion_Time(-2_000_000_000+i64(deadline)))
	testing.expect(t, at_deadline.status == .Ok && at_deadline.settled &&
		at_deadline.value == response.target && at_deadline.velocity == 0,
		"the first sample at the certified deadline should return exact settled state")

	// One caller samples the response before the later observation; another
	// reaches the same timestamp without an intermediate sample. Sampling is
	// pure, so both paths return the same exact retired value.
	_ = motion_scalar_sample(response, Motion_Time(-1_600_000_000))
	sampled_path := motion_scalar_sample(response, Motion_Time(-1_500_000_000))
	direct_path := motion_scalar_sample(response, Motion_Time(-1_500_000_000))
	testing.expect(t, sampled_path.status == .Ok && direct_path.status == .Ok &&
		sampled_path.settled && direct_path.settled && sampled_path.value == direct_path.value &&
		sampled_path.velocity == direct_path.velocity,
		"settled status and presentation must not depend on prior sample history")
}

@(test)
test_motion_irregular_samples_and_repeated_retargets :: proc(t: ^testing.T) {
	response, status := motion_scalar_create(-4, 2, 1.25, MOTION_TEST_CONFIG, Motion_Time(0))
	testing.expect(t, status == .Ok, "response should initialize")
	sample_times := [4]i64{0, 13_000_000, 287_000_000, 1_370_000_000}
	for elapsed_ns in sample_times {
		sample := motion_scalar_sample(response, Motion_Time(elapsed_ns))
		seconds := f64(elapsed_ns)/MOTION_NS_PER_SECOND
		r0 := -6.0
		omega := MOTION_TEST_CONFIG.omega
		expected_residual := (r0 + (1.25+omega*r0)*seconds) * math.exp(-omega*seconds)
		expected_velocity := (1.25 - omega*(1.25+omega*r0)*seconds) * math.exp(-omega*seconds)
		testing.expect(t, sample.status == .Ok && motion_test_near(sample.value, 2+expected_residual, 1e-11) &&
			motion_test_near(sample.velocity, expected_velocity, 1e-11),
			"irregular timestamp samples should match the closed form without integration history")
	}

	retarget_times := [3]i64{100_000_000, 350_000_000, 800_000_000}
	retarget_values := [3]f64{9, -2, 3.5}
	for index in 0..<len(retarget_times) {
		at := Motion_Time(retarget_times[index])
		presented := motion_scalar_sample(response, at)
		next, retarget_status := motion_scalar_settle(response, retarget_values[index], at)
		after := motion_scalar_sample(next, at)
		testing.expect(t, retarget_status == .Ok && after.status == .Ok &&
			after.value == presented.value && after.velocity == presented.velocity,
			"every retarget in a rapid sequence must preserve the current position and velocity")
		response = next
	}
	long_stall := motion_scalar_sample(response, Motion_Time(60_000_000_000))
	testing.expect(t, long_stall.status == .Ok && long_stall.settled && !long_stall.active &&
		long_stall.value == response.target && long_stall.velocity == 0,
		"a long unsampled stall should retire directly to the exact target")
}

@(test)
test_motion_does_not_retire_small_position_with_large_velocity :: proc(t: ^testing.T) {
	config := Motion_Config{omega=10, position_tolerance=0.001, velocity_tolerance=0.001}
	response, status := motion_scalar_create(1e-9, 0, 100, config, Motion_Time(0))
	testing.expect(t, status == .Ok, "tiny displacement and large velocity are valid")
	initial := motion_scalar_sample(response, Motion_Time(0))
	testing.expect(t, abs(initial.value) < config.position_tolerance, "the displacement starts within its tolerance")
	testing.expect(t, initial.active && !initial.settled, "large velocity must prevent premature retirement")
	still_moving := motion_scalar_sample(response, Motion_Time(10_000_000))
	testing.expect(t, still_moving.status == .Ok && still_moving.active && abs(still_moving.velocity) > config.velocity_tolerance,
		"motion remains active while its velocity exceeds tolerance")
}

@(test)
test_motion_mode_transitions_and_same_target_rules :: proc(t: ^testing.T) {
	response, status := motion_scalar_create(0, 10, 0, MOTION_TEST_CONFIG, Motion_Time(0))
	testing.expect(t, status == .Ok, "response should initialize")
	unchanged, no_op_status := motion_scalar_settle(response, 10, Motion_Time(-1))
	testing.expect(t, no_op_status == .Ok && unchanged.start_time == response.start_time && unchanged.residual_0 == response.residual_0,
		"same Settle target is a no-op even if a new timestamp was supplied")

	direct, direct_status := motion_scalar_direct(response, 3, Motion_Time(100_000_000))
	testing.expect(t, direct_status == .Ok && direct.mode == .Direct, "Direct must take effect even after a settling response")
	direct_sample := motion_scalar_sample(direct, Motion_Time(100_000_000))
	testing.expect(t, direct_sample.value == 3 && !direct_sample.active && direct_sample.velocity == 0,
		"Direct presents its target immediately with zero residual velocity")

	settling, settle_status := motion_scalar_settle(direct, 8, Motion_Time(200_000_000))
	testing.expect(t, settle_status == .Ok && settling.mode == .Settle, "Direct-to-Settle must process the mode change")
	settling_sample := motion_scalar_sample(settling, Motion_Time(200_000_000))
	testing.expect(t, settling_sample.value == 3 && settling_sample.velocity == 0 && settling_sample.active,
		"Direct-to-Settle begins from the direct position with zero velocity")

	snapped, snap_status := motion_scalar_snap(settling, 8, Motion_Time(200_000_000))
	testing.expect(t, snap_status == .Ok && snapped.mode == .Snap, "Snap must process a mode change with an unchanged numeric target")
	snapped_sample := motion_scalar_sample(snapped, Motion_Time(200_000_000))
	testing.expect(t, snapped_sample.value == 8 && snapped_sample.velocity == 0 && snapped_sample.settled,
		"Snap commits the target immediately")
}

@(test)
test_motion_handles_large_timestamps_and_unestablished_slow_deadline :: proc(t: ^testing.T) {
	config := Motion_Config{omega=1e-20, position_tolerance=1e-12, velocity_tolerance=1e-12}
	response, status := motion_scalar_create(1, 0, 0, config, Motion_Time(-9_000_000_000_000_000_000))
	testing.expect(t, status == .Ok && !response.deadline_established,
		"a deadline beyond the supported time horizon is reported as unestablished")
	sample := motion_scalar_sample(response, Motion_Time(9_000_000_000_000_000_000))
	testing.expect(t, sample.status == .Ok && sample.active && !sample.deadline_established &&
		motion_finite(sample.value) && motion_finite(sample.velocity),
		"large signed timestamps must not overflow elapsed-time arithmetic or snap without a deadline")
}

@(test)
test_motion_short_circuits_large_transient_without_intermediate_overflow :: proc(t: ^testing.T) {
	config := Motion_Config{omega=1e100, position_tolerance=1e-6, velocity_tolerance=1e-6}
	response, status := motion_scalar_create(1e300, 0, 0, config, Motion_Time(0))
	testing.expect(t, status == .Ok && response.deadline_established,
		"log-domain envelope search should certify a rapidly decaying large transient")
	sample := motion_scalar_sample(response, Motion_Time(1))
	testing.expect(t, sample.status == .Ok && sample.settled && sample.value == 0 && sample.velocity == 0,
		"the certified deadline should avoid overflowing a polynomial before decay")
}

@(test)
test_motion_preserves_small_presentation_near_large_target :: proc(t: ^testing.T) {
	config := Motion_Config{omega=4, position_tolerance=1, velocity_tolerance=1}
	response, status := motion_scalar_create(1e-6, 1e15, 0, config, Motion_Time(0))
	testing.expect(t, status == .Ok, "finite but widely separated values should initialize")
	sample := motion_scalar_sample(response, Motion_Time(1))
	testing.expect(t, sample.status == .Ok && motion_test_near(sample.value, 0.008001, 1e-9),
		"early presentation should retain small coordinates instead of losing them to target-plus-residual cancellation")
}

@(test)
test_motion_translation_uses_componentwise_shared_settlement :: proc(t: ^testing.T) {
	config := Motion_Config{omega=5, position_tolerance=0.001, velocity_tolerance=0.001}
	response, status := motion_translation_create(
		Motion_Vector2{1, 0.0001}, Motion_Vector2{0, 0}, Motion_Vector2{0, 0}, config, Motion_Time(0),
	)
	testing.expect(t, status == .Ok && response.x.settle_after_ns == response.y.settle_after_ns,
		"translation components should share a certified max-norm deadline")
	before_deadline := Motion_Time(i64(response.x.start_time)+i64(response.x.settle_after_ns)-1)
	before := motion_translation_sample(response, before_deadline)
	testing.expect(t, before.status == .Ok && before.active, "the vector remains active until both component bounds settle")
	at_deadline := Motion_Time(i64(response.x.start_time)+i64(response.x.settle_after_ns))
	after := motion_translation_sample(response, at_deadline)
	testing.expect(t, after.status == .Ok && after.settled && after.value.x == 0 && after.value.y == 0,
		"both components retire together at the shared deadline")

	retargeted, retarget_status := motion_translation_settle(response, Motion_Vector2{2, -3}, Motion_Time(100_000_000))
	testing.expect(t, retarget_status == .Ok && retargeted.x.start_time == retargeted.y.start_time &&
		retargeted.x.settle_after_ns == retargeted.y.settle_after_ns,
		"a partial-axis change must retarget the whole translation at one timestamp")
}

@(test)
test_motion_invalid_inputs_leave_response_unchanged :: proc(t: ^testing.T) {
	response, status := motion_scalar_create(0, 1, 0, MOTION_TEST_CONFIG, Motion_Time(0))
	testing.expect(t, status == .Ok, "response should initialize")
	invalid_config := Motion_Config{omega=0, position_tolerance=0.1, velocity_tolerance=0.1}
	_, invalid_config_status := motion_scalar_create(0, 1, 0, invalid_config, Motion_Time(0))
	testing.expect(t, invalid_config_status == .Invalid_Configuration, "zero frequency should be rejected")
	invalid_numeric_config := Motion_Config{omega=1, position_tolerance=math.inf_f64(1), velocity_tolerance=0.1}
	_, nonfinite_config_status := motion_scalar_create(0, 1, 0, invalid_numeric_config, Motion_Time(0))
	testing.expect(t, nonfinite_config_status == .Invalid_Configuration, "infinite tolerance should be rejected")
	unchanged, invalid_value_status := motion_scalar_settle(response, math.nan_f64(), Motion_Time(1))
	testing.expect(t, invalid_value_status == .Invalid_Value && unchanged.start_time == response.start_time && unchanged.target == response.target,
		"failed retargets must leave the original immutable response unchanged")
	rewound := motion_scalar_sample(response, Motion_Time(-1))
	testing.expect(t, rewound.status == .Time_Rewound, "sampling before the response start should be rejected")
}
