Texture2D<float> atlas : register(t0, space2);
SamplerState atlas_sampler : register(s0, space2);
struct Input { float4 color : TEXCOORD0; float2 uv : TEXCOORD1; };
float4 PSMain(Input input) : SV_Target {
    float coverage = atlas.Sample(atlas_sampler, input.uv);
    return float4(input.color.rgb, input.color.a * coverage);
}
