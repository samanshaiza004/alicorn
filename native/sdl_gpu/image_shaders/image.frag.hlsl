Texture2D<float4> source_image : register(t0, space2);
SamplerState image_sampler : register(s0, space2);
struct Input { float4 color : TEXCOORD0; float2 uv : TEXCOORD1; };
float4 PSMain(Input input) : SV_Target {
    float4 sampled = source_image.Sample(image_sampler, input.uv);
    return float4(sampled.rgb * input.color.rgb, sampled.a * input.color.a);
}
