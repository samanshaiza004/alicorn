package alicorn_sdl_gpu

import "core:math"
import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

when ALICORN_RETAINED_EFFECTS_EXPERIMENT {

@(test)
test_effect_composite_pipeline_tracks_window_swapchain_format :: proc(t:^testing.T) {
	cache := native_effect_make(nil, 1024, sdl3.GPUTextureFormat.B8G8R8A8_UNORM)
	effects := native_retained_effects_make(nil, composite_format=sdl3.GPUTextureFormat.B8G8R8A8_UNORM)
	testing.expect(t, cache.composite_format == .B8G8R8A8_UNORM &&
		effects.composite_format == .B8G8R8A8_UNORM &&
		effects.slots[0].composite_format == .B8G8R8A8_UNORM &&
		NATIVE_EFFECT_FILTER_FORMAT == .R8G8B8A8_UNORM,
		"effect filtering stays RGBA8 while the final composite follows the actual window swapchain format")
}

@(test)
test_effect_cache_identity_tracks_prefix_but_not_palette_query :: proc(t: ^testing.T) {
	region := alicorn.Rect{80, 60, 400, 300}
	clip := alicorn.Rect{0, 0, 1000, 700}
	background := alicorn.paint_surface_command(alicorn.Node_ID(1), alicorn.Rect{0,0,1000,700}, clip, alicorn.Color{0.1,0.12,0.16,1})
	marker := alicorn.paint_backdrop_effect_command(alicorn.Node_ID(2), region, clip, alicorn.experimental_backdrop_blur(4))
	query_a := alicorn.paint_text_command(alicorn.Node_ID(3), alicorn.Rect{100,90,200,32}, clip,
		alicorn.Text_Run_Handle{source=.Retained, resource=17, generation=1}, alicorn.Color{1,1,1,1})
	query_b := alicorn.paint_text_command(alicorn.Node_ID(3), alicorn.Rect{100,90,200,32}, clip,
		alicorn.Text_Run_Handle{source=.Retained, resource=18, generation=2}, alicorn.Color{1,1,1,1})
	display_a := [?]alicorn.Paint_Command{background, marker, query_a}
	display_b := [?]alicorn.Paint_Command{background, marker, query_b}
	prefix_a, marker_a, marker_index_a, found_a := native_effect_prefix_before_first_marker(display_a[:])
	prefix_b, marker_b, marker_index_b, found_b := native_effect_prefix_before_first_marker(display_b[:])
	testing.expect(t, found_a && found_b && marker_index_a == 1 && marker_index_b == 1,
		"the first effect marker should define the compositor boundary")
	if !found_a || !found_b { return }
	generation_a := native_effect_prefix_generation(prefix_a, marker_a.bounds, marker_a.clip, 2, 2, 4)
	generation_b := native_effect_prefix_generation(prefix_b, marker_b.bounds, marker_b.clip, 2, 2, 4)
	testing.expect(t, generation_a == generation_b,
		"typing in the palette after the effect boundary must reuse the same retained backdrop")
	changed_background := background
	changed_background.payload = alicorn.Surface_Paint{shape={kind=.Rectangle}, fill=alicorn.Color{0.2,0.12,0.16,1}}
	display_changed := [?]alicorn.Paint_Command{changed_background, marker, query_a}
	changed_prefix, changed_marker, _, _ := native_effect_prefix_before_first_marker(display_changed[:])
	generation_changed := native_effect_prefix_generation(changed_prefix, changed_marker.bounds, changed_marker.clip, 2, 2, 4)
	testing.expect(t, generation_changed != generation_a,
		"a paint change behind the palette must invalidate the retained backdrop")
}

effect_test_request :: proc() -> Native_Effect_Request {
    return {enabled=true,key=17,source_generation=4,region={10.25,20.25,100,50},clip={0,0,200,200},scale=1.5,spacing=2,depth=1}
}

@(test)
test_effect_boundary_uses_resolved_clip_and_physical_halo :: proc(t:^testing.T) {
    request:=effect_test_request()
    plan,ok:=native_effect_plan(request)
    testing.expect(t,ok && plan.active,"a bounded opted-in region should have an executable plan")
    if !ok { return }
    testing.expect(t,plan.source_bounds.x<=6.25 && plan.source_bounds.y<=16.25 &&
        plan.source_bounds.x+plan.source_bounds.w>=114.25 && plan.source_bounds.y+plan.source_bounds.h>=74.25,
        "the two-tap support halo must survive outward rounding at fractional DPI")
    testing.expect(t,abs(plan.source_bounds.x*plan.scale-math.round(plan.source_bounds.x*plan.scale))<0.001 &&
        abs(plan.source_bounds.y*plan.scale-math.round(plan.source_bounds.y*plan.scale))<0.001,
        "the input origin must be snapped in physical pixels")
    testing.expect(t,plan.output_clip==request.region,"halo pixels must not enlarge the output clip")
    request.clip={20,30,20,10}
    plan,ok=native_effect_plan(request)
    testing.expect(t,ok && plan.output_clip==request.clip,"resolved ancestor clipping remains authoritative")
}

@(test)
test_effect_boundary_rejects_unbounded_and_nested_requests :: proc(t:^testing.T) {
    for i in 0..<8 {
        request:=effect_test_request()
        switch i {
        case 0: request.scale=transmute(f32)u32(0x7FC00000)
        case 1: request.region.x=transmute(f32)u32(0x7F800000)
        case 2: request.depth=2
        case 3: request.source_generation=0
        case 4: request.key=0
        case 5: request.region.w=1_000_000
        case 6: request.spacing=9
        case 7: request.scale=0
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
    request=effect_test_request(); request.spacing=0
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
		"an in-flight cache slot must remain untouched; use the other safe slot or direct fallback")

	native_retained_effects_note_completed(&effects, 6)
	_ = native_retained_effects_prepare(&effects, changed)
	testing.expect(t, !effects.slots[0].valid,
		"a replaced slot may retire its old payload only after its recorded submission fence completes")
	native_retained_effects_abort(&effects)
}
}
