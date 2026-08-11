#version 460 core
layout (location = 0) out vec4 FragColor;

layout (location = 0) in vec2 TexCoord;

layout (set = 3, binding = 0) uniform Stuff {
    vec2 coordScale;
    vec2 coordOffset;
    vec4 color;
    vec4 slice9;
    vec2 size;
    vec2 tex_size;
} stuff;

layout (set = 2, binding = 0) uniform sampler2D my_texture;

// Helper: convert uv for nine-slice sampling
vec2 uv9slice(vec2 uv, vec2 s, vec4 b) {
    vec2 t = clamp((s * uv - b.xy) / (s - b.xy - b.zw), 0.0, 1.0);
    return mix(uv * s, 1.0 - s * (1.0 - uv), t);
}

// Draw (sample) the nine-slice texture at the provided uv
vec4 draw_nine_slice(vec2 uv) {
    vec2 _s = stuff.size / stuff.tex_size;
    vec4 _b = stuff.slice9 / vec4(stuff.tex_size.x, stuff.tex_size.x, stuff.tex_size.y, stuff.tex_size.y);
    vec2 _uv = uv9slice(uv, _s, _b);
    return texture(my_texture, _uv);
}

void main()
{
    vec2 uv = TexCoord;
    // Apply any coordinate transform provided by the uniform block
    vec2 adj_uv = uv * stuff.coordScale + stuff.coordOffset;
    vec4 tex;
    if (stuff.slice9.x != 0.0) {
        tex = draw_nine_slice(adj_uv);
    } else {
        tex = texture(my_texture, adj_uv);
    }
    
    if (tex.a == 0.0) {
        discard;
    }
    FragColor = tex * stuff.color;
}