#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Light
{
    float diffuse;
    float ambient;
};

struct Stuff
{
    float2 coordScale;
    float2 coordOffset;
    float4 color;
};

struct main0_out
{
    float4 FragColor [[color(0)]];
};

struct main0_in
{
    float2 TexCoord [[user(locn0)]];
    float2 FragPos [[user(locn1)]];
    float2 CamPos [[user(locn2)]];
};

fragment main0_out main0(main0_in in [[stage_in]], constant Stuff& stuff [[buffer(0)]], constant Light& lightData [[buffer(1)]], texture2d<float> my_texture [[texture(0)]], sampler my_textureSmplr [[sampler(0)]])
{
    main0_out out = {};
    float ambient_light = lightData.ambient;
    float _distance = length((in.CamPos + float2(8.0)) - in.FragPos);
    float attenuation = smoothstep(300.0, 200.0, length((in.CamPos + float2(8.0)) - in.FragPos));
    ambient_light *= attenuation;
    float4 tex = my_texture.sample(my_textureSmplr, ((in.TexCoord * stuff.coordScale) + stuff.coordOffset));
    out.FragColor = (tex * stuff.color) * (lightData.diffuse + ambient_light);
    return out;
}

