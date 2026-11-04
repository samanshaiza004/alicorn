package alicorn_sdl_gpu

import "core:math"
import "core:testing"
import alicorn "../../runtime"

when ALICORN_RETAINED_EFFECTS_EXPERIMENT {

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
}
