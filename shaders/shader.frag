#version 460 core
layout (location = 0) out vec4 FragColor;

layout (location = 0) in vec2 TexCoord;
layout (location = 1) in vec2 FragPos;
layout (location = 2) in vec2 CamPos;

layout (set = 3, binding = 0) uniform Stuff {
    vec2 coordScale;
    vec2 coordOffset;
    vec4 color;
} stuff;
layout (set = 3, binding = 1) uniform Light {
    float diffuse;
    float ambient;
} lightData;

layout (set = 2, binding = 0) uniform sampler2D my_texture;

void main()
{
    float ambient_light = lightData.ambient;
    float distance = length(CamPos + vec2(8, 8) - FragPos);
    float attenuation = smoothstep(300.0, 200.0, length((CamPos + vec2(8, 8)) - FragPos));
    ambient_light *= attenuation;

    vec4 tex = texture(my_texture, TexCoord * stuff.coordScale + stuff.coordOffset);
    FragColor = tex * stuff.color * (lightData.diffuse + ambient_light);
}