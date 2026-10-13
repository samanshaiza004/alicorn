#include <metal_stdlib>
using namespace metal;
struct Input { float4 color [[user(locn0)]]; float2 uv [[user(locn1)]]; };
fragment float4 PSMain(Input input [[stage_in]], texture2d<float> source_image [[texture(0)]], sampler image_sampler [[sampler(0)]]) {
    float4 sampled = source_image.sample(image_sampler, input.uv);
    return float4(sampled.rgb * input.color.rgb, sampled.a * input.color.a);
}
