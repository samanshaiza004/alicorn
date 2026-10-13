#include <metal_stdlib>
using namespace metal;
struct Input { float4 color [[user(locn0)]]; float2 uv [[user(locn1)]]; };
fragment float4 PSMain(Input input [[stage_in]], texture2d<float> atlas [[texture(0)]], sampler atlas_sampler [[sampler(0)]]) {
    return float4(input.color.rgb, input.color.a * atlas.sample(atlas_sampler, input.uv).r);
}
