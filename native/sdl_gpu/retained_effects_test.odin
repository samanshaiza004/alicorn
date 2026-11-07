package alicorn_sdl_gpu

import "core:math"
import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

@(test)
test_effect_capture_and_composite_follow_window_swapchain_format :: proc(t:^testing.T) {
	cache := native_effect_make(nil, 1024, sdl3.GPUTextureFormat.B8G8R8A8_UNORM)
	effects := native_retained_effects_make(nil, composite_format=sdl3.GPUTextureFormat.B8G8R8A8_UNORM)
	testing.expect(t, cache.composite_format == .B8G8R8A8_UNORM &&
		effects.composite_format == .B8G8R8A8_UNORM &&
		effects.slots[0].composite_format == .B8G8R8A8_UNORM &&
		NATIVE_EFFECT_FILTER_FORMAT == .R16G16B16A16_FLOAT,
		"capture and composite use the window swapchain format while Gaussian accumulation uses half-float")
}

@(test)
test_effect_cache_identity_tracks_prefix_but_not_palette_query :: proc(t: ^testing.T) {
	region := alicorn.Rect{80, 60, 400, 300}
	clip := alicorn.Rect{0, 0, 1000, 700}
	background := alicorn.paint_surface_command(alicorn.Node_ID(1), alicorn.Rect{0,0,1000,700}, clip, alicorn.Color{0.1,0.12,0.16,1})
	marker := alicorn.paint_backdrop_effect_command(alicorn.Node_ID(2), region, clip, alicorn.backdrop_blur(4))
	button_a := alicorn.paint_surface_command(alicorn.Node_ID(4), alicorn.Rect{100,130,88,32}, clip,
		alicorn.Color{0.18,0.24,0.35,1})
	button_b := button_a
	button_b.payload = alicorn.Surface_Paint{shape={kind=.Rectangle}, fill=alicorn.Color{0.34,0.48,0.68,1}}
	query_a := alicorn.paint_text_command(alicorn.Node_ID(3), alicorn.Rect{100,90,200,32}, clip,
		alicorn.Text_Run_Handle{source=.Retained, resource=17, generation=1}, alicorn.Color{1,1,1,1})
	query_b := alicorn.paint_text_command(alicorn.Node_ID(3), alicorn.Rect{100,90,200,32}, clip,
		alicorn.Text_Run_Handle{source=.Retained, resource=18, generation=2}, alicorn.Color{1,1,1,1})
	display_a := [?]alicorn.Paint_Command{background, marker, button_a, query_a}
	display_b := [?]alicorn.Paint_Command{background, marker, button_b, query_b}
	prefix_a, marker_a, marker_index_a, found_a := native_effect_prefix_before_first_marker(display_a[:])
	prefix_b, marker_b, marker_index_b, found_b := native_effect_prefix_before_first_marker(display_b[:])
	testing.expect(t, found_a && found_b && marker_index_a == 1 && marker_index_b == 1,
		"the first effect marker should define the compositor boundary")
	if !found_a || !found_b { return }
	generation_a := native_effect_prefix_generation(prefix_a, marker_a.bounds, marker_a.clip, 2, 2, 4)
	generation_b := native_effect_prefix_generation(prefix_b, marker_b.bounds, marker_b.clip, 2, 2, 4)
	testing.expect(t, generation_a == generation_b,
		"hovering a palette button or typing after the effect boundary must reuse the same retained backdrop")
	changed_background := background
	changed_background.payload = alicorn.Surface_Paint{shape={kind=.Rectangle}, fill=alicorn.Color{0.2,0.12,0.16,1}}
	display_changed := [?]alicorn.Paint_Command{changed_background, marker, query_a}
	changed_prefix, changed_marker, _, _ := native_effect_prefix_before_first_marker(display_changed[:])
	generation_changed := native_effect_prefix_generation(changed_prefix, changed_marker.bounds, changed_marker.clip, 2, 2, 4)
	testing.expect(t, generation_changed != generation_a,
		"a paint change behind the palette must invalidate the retained backdrop")
}

effect_test_request :: proc() -> Native_Effect_Request {
    return {enabled=true,key=17,source_generation=4,region={10.25,20.25,100,50},clip={0,0,200,200},scale=1.5,sigma=2,depth=1}
}

@(test)
test_effect_boundary_uses_resolved_clip_and_physical_halo :: proc(t:^testing.T) {
    request:=effect_test_request()
    plan,ok:=native_effect_plan(request)
    testing.expect(t,ok && plan.active,"a bounded opted-in region should have an executable plan")
    if !ok { return }
    testing.expect(t,plan.source_bounds.x<=4.25 && plan.source_bounds.y<=14.25 &&
        plan.source_bounds.x+plan.source_bounds.w>=116.25 && plan.source_bounds.y+plan.source_bounds.h>=76.25,
        "the complete 3-sigma support halo must survive outward rounding at fractional DPI")
    testing.expect(t,abs(plan.source_bounds.x*plan.scale-math.round(plan.source_bounds.x*plan.scale))<0.001 &&
        abs(plan.source_bounds.y*plan.scale-math.round(plan.source_bounds.y*plan.scale))<0.001,
        "the input origin must be snapped in physical pixels")
    testing.expect(t,plan.output_clip==request.region,"halo pixels must not enlarge the output clip")
    request.clip={20,30,20,10}
    plan,ok=native_effect_plan(request)
    testing.expect(t,ok && plan.output_clip==request.clip,"resolved ancestor clipping remains authoritative")
}

@(test)
test_effect_gaussian_taps_reconstruct_normalized_dense_kernel :: proc(t:^testing.T) {
	sigma := f32(12)
	dense, radius, dense_ok := native_effect_gaussian_weights(sigma)
	taps, tap_count, taps_ok := native_effect_gaussian_taps(sigma)
	testing.expect(t, dense_ok && taps_ok && radius == 36 && tap_count == 37,
		"sigma 12 should use a normalized 3-sigma kernel and 37 bilinear-paired samples")
	if !dense_ok || !taps_ok { return }

	center := NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS
	dense_sum, variance := f64(0), f64(0)
	for offset in -radius..<(radius+1) {
		weight := f64(dense[center+offset])
		dense_sum += weight
		variance += f64(offset*offset)*weight
		if offset > 0 {
			testing.expect(t, abs(dense[center+offset]-dense[center-offset]) < 0.000001,
				"the dense Gaussian kernel must be symmetric")
			testing.expect(t, dense[center+offset] <= dense[center+offset-1],
				"the truncated Gaussian weights must decay monotonically away from the center")
		}
	}
	sigma_squared := f64(sigma)*f64(sigma)
	testing.expect(t, abs(dense_sum-1) < 0.00001 && variance > sigma_squared*0.9 && variance < sigma_squared*1.01,
		"the truncated kernel must stay normalized and preserve the requested blur scale")

	// A linear texture sample at each paired fractional offset must reconstruct
	// the dense integer-tap kernel exactly, including the odd-radius edge pair.
	reconstructed: [NATIVE_EFFECT_MAX_GAUSSIAN_KERNEL_WIDTH]f32
	for tap in taps[:tap_count] {
		low := int(math.floor(f64(tap.offset_pixels)))
		fraction := f32(f64(tap.offset_pixels)-f64(low))
		reconstructed[center+low] += tap.weight*(1-fraction)
		reconstructed[center+low+1] += tap.weight*fraction
	}
	for offset in -radius..<(radius+1) {
		testing.expect(t, abs(reconstructed[center+offset]-dense[center+offset]) < 0.00001,
			"bilinear tap pairing must reproduce each dense Gaussian coefficient")
	}
}

@(test)
test_effect_gaussian_tiny_sigma_has_finite_identity_taps :: proc(t:^testing.T) {
	taps, count, ok := native_effect_gaussian_taps(1e-20)
	testing.expect(t, ok && count == 3,
		"a positive sigma whose tail underflows should still produce a bounded kernel")
	if !ok { return }
	for tap in taps[:count] {
		testing.expect(t, native_effect_finite(tap.offset_pixels) && native_effect_finite(tap.weight) && tap.weight >= 0,
			"underflowed tail taps must remain finite zero-weight samples")
	}
	testing.expect(t, taps[0].offset_pixels == 0 && taps[0].weight == 1 &&
		taps[1].weight == 0 && taps[2].weight == 0,
		"a tiny sampled Gaussian should safely reduce to an identity kernel")
}

@(test)
test_effect_gaussian_suppresses_checker_and_sparse_tap_passbands :: proc(t:^testing.T) {
	sigma := f32(6)
	weights, radius, ok := native_effect_gaussian_weights(sigma)
	testing.expect(t, ok, "the checkerboard fixture needs a valid Gaussian kernel")
	if !ok { return }
	center := NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS
	period_six_response, checkerboard_response := f64(0), f64(0)
	omega := 2*3.141592653589793/6
	for offset in -radius..<(radius+1) {
		weight := f64(weights[center+offset])
		period_six_response += weight*math.cos(omega*f64(offset))
		checker_sign := f64(1)
		if offset%2 != 0 { checker_sign = -1 }
		checkerboard_response += weight*checker_sign
	}
	// The previous spaced binomial has H(w)=cos^4(6w/2), which equals one
	// for the period-six pattern. A sampled dense Gaussian should remove it.
	legacy_cosine := math.cos(f64(6)*omega/2)
	legacy_period_six_response := legacy_cosine*legacy_cosine*legacy_cosine*legacy_cosine
	testing.expect(t, abs(legacy_period_six_response-1) < 0.000001 && abs(period_six_response) < 0.01,
		"the Gaussian must suppress the repeating detail passed unchanged by a six-pixel-spaced five-tap kernel")
	testing.expect(t, abs(checkerboard_response) < 0.01,
		"the Gaussian impulse response must strongly attenuate alternating-pixel checker detail")
}

@(test)
test_effect_gaussian_maximum_supported_physical_sigma :: proc(t:^testing.T) {
	request := effect_test_request()
	request.sigma = 8
	request.scale = 4
	plan, ok := native_effect_plan(request)
	testing.expect(t, ok && plan.active && plan.sigma_pixels == 32 &&
		plan.filter_tap_count == NATIVE_EFFECT_MAX_FILTER_TAPS,
		"the maximum physical sigma must fit the bounded 97-tap vertex allocation")
	if ok {
		radius, radius_ok := native_effect_gaussian_radius(plan.sigma_pixels)
		testing.expect(t, radius_ok && radius == NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS &&
			plan.bytes == native_effect_byte_size(plan.width, plan.height),
			"the maximum supported kernel must retain its complete 3-sigma halo and charge half-float storage")
	}
}

@(test)
test_effect_boundary_rejects_unbounded_and_nested_requests :: proc(t:^testing.T) {
	for i in 0..<9 {
        request:=effect_test_request()
        switch i {
        case 0: request.scale=transmute(f32)u32(0x7FC00000)
        case 1: request.region.x=transmute(f32)u32(0x7F800000)
        case 2: request.depth=2
        case 3: request.source_generation=0
        case 4: request.key=0
        case 5: request.region.w=1_000_000
		case 6: request.sigma=9
		case 7: request.scale=0
		case 8: request.sigma=8; request.scale=64
        }
        _,ok:=native_effect_plan(request)
        testing.expect(t,!ok,"invalid requests must fail before a GPU allocation or integer cast")
    }
}

@(test)
test_effect_flat_path_never_creates_resources :: proc(t:^testing.T) {
    cache:=native_effect_make(nil,16*1024*1024)
    for _ in 0..<100 {
        plan,ok:=native_effect_plan({})
        testing.expect(t,ok && !plan.active && native_effect_prepare(&cache,plan)==.Inactive,
            "flat scenes need no GPU device, allocation, filter pass, or retry timer")
    }
    request:=effect_test_request()
    request.clip=alicorn.Rect{500,500,10,10}
    plan,ok:=native_effect_plan(request)
    testing.expect(t,ok && !plan.active,"a fully clipped region must retire its effect")
	request=effect_test_request(); request.sigma=0
    plan,ok=native_effect_plan(request)
    testing.expect(t,ok && !plan.active,"zero blur should take the direct draw path")
    testing.expect(t,cache.allocations==0 && cache.live_bytes==0 && cache.filter_passes==0 && cache.output_generation==0,
        "disabled cache construction and planning must have no GPU side effects")
    native_effect_reset(&cache)
}

@(test)
test_effect_allocation_boundary_rejects_forged_plans :: proc(t:^testing.T) {
    plan,ok:=native_effect_plan(effect_test_request())
    testing.expect(t,ok && native_effect_plan_valid(plan),"a generated plan must pass the allocation boundary")
    if !ok { return }
    forged:=plan
    forged.bytes=1
    testing.expect(t,!native_effect_plan_valid(forged),"callers cannot lower the charged memory by forging bytes")
    forged=plan; forged.width=0xFFFFFFFF
    testing.expect(t,!native_effect_plan_valid(forged),"hand-authored plans cannot bypass dimension limits")
    forged=plan; forged.output_clip={-1000,-1000,4000,4000}
    testing.expect(t,!native_effect_plan_valid(forged),"composition cannot read beyond the captured input extent")
    cache:=native_effect_make(nil,plan.bytes)
    testing.expect(t,native_effect_prepare(&cache,plan)==.Fallback && cache.live_bytes==0,
        "missing devices use the direct path without partially constructing a cache")
}

@(test)
test_effect_slot_reuse_waits_for_its_submission_fence :: proc(t:^testing.T) {
	plan, ok := native_effect_plan(effect_test_request())
	if !ok { testing.expect(t, false, "retirement fixture should have a bounded effect plan"); return }
	effects := native_retained_effects_make(nil)
	effects.slots[0].valid = true
	effects.slots[0].plan = plan
	effects.slot_last_use_serial[0] = 6
	changed := plan
	changed.source_generation += 1
	status := native_retained_effects_prepare(&effects, changed)
	testing.expect(t, status == .Fallback && effects.slots[0].valid && effects.slots[0].plan == plan,
		"without a device, a cache slot remains untouched; the host may use direct fallback")
	testing.expect(t, native_retained_effects_slot_in_flight(&effects, 0),
		"the cache is not writable before its recorded submission fence completes")

	native_retained_effects_note_completed(&effects, 6)
	testing.expect(t, !native_retained_effects_slot_in_flight(&effects, 0),
		"retiring its submission fence makes the cache slot eligible for replacement")
}

@(test)
test_effect_reports_deferred_when_both_cache_slots_are_in_flight :: proc(t:^testing.T) {
	plan, ok := native_effect_plan(effect_test_request())
	if !ok { testing.expect(t, false, "deferred fixture should have a bounded effect plan"); return }
	effects := native_retained_effects_make(nil)
	// This nonnil token is never dereferenced: both slots are marked in flight,
	// so prepare must classify the wait before any SDL GPU operation.
	effects.device = cast(^sdl3.GPUDevice)uintptr(1)
	for &slot, index in effects.slots {
		slot.valid = true
		slot.plan = plan
		slot.live_bytes = plan.bytes
		effects.slot_last_use_serial[index] = u64(index+8)
	}
	effects.completed_serial = 0
	changed := plan
	changed.source_generation += 1
	status := native_retained_effects_prepare(&effects, changed)
	testing.expect(t, status == .Deferred,
		"a valid effect blocked only by outstanding slot fences needs a scheduled retry, not a permanent direct fallback")
	testing.expect(t, effects.slots[0].valid && effects.slots[1].valid,
		"preparing a deferred effect must preserve both in-flight cache generations")
	testing.expect(t, native_retained_effects_next_busy_serial(&effects) == 8,
		"the host should wait only through the earliest fence that can free a cache slot")
	native_retained_effects_note_completed(&effects, 8)
	testing.expect(t, native_retained_effects_next_busy_serial(&effects) == 9,
		"the next slot fence remains protected until its own submission retires")
	native_retained_effects_note_completed(&effects, 9)
	testing.expect(t, native_retained_effects_next_busy_serial(&effects) == 0,
		"once all retained generations complete, effect recovery requires no more fence wait")
}
