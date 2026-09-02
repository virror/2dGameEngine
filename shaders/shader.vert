#version 460 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;

layout (location = 0) out vec2 TexCoord;
layout (location = 1) out vec2 FragPos;
layout (location = 2) out vec2 CamPos;

layout (set = 1, binding = 0) uniform Stuff {
    mat4 model;
	vec2 resolution;
    vec2 cameraPos;
    vec2 flip;
    float virtualHeight;
} stuff;

void main()
{
    float width = stuff.resolution.x / stuff.resolution.y * stuff.virtualHeight;
    gl_Position =
        (stuff.model * vec4(aPos, 0.0, 1.0) - vec4(stuff.cameraPos, 0.0, 0.0)) /
        vec4(width / 2.0, stuff.virtualHeight / 2.0, 1, 1);

    vec2 tx = aTexCoord;
    if(stuff.flip.x == 1)
        tx = vec2(1.0 - tx.x, tx.y);
    if(stuff.flip.y == 1)
        tx = vec2(tx.x, 1.0 - tx.y);
    TexCoord = tx;
    FragPos = vec2(stuff.model * vec4(aPos, 0.0, 1.0)).xy;
    CamPos = stuff.cameraPos;
}