#version 450
layout(set = 2, binding = 0) uniform sampler2D source_image;
layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;
layout(location = 0) out vec4 output_color;
void main() {
    vec4 sampled = texture(source_image, uv);
    output_color = vec4(sampled.rgb * color.rgb, sampled.a * color.a);
}
