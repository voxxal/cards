#version 330
uniform mat4 mvp;

in vec4 position;
in vec4 color0;
in vec2 texcoord0;

out vec4 tint;
out vec2 uv;

void main() {
    gl_Position = mvp * position;
    tint = color0;
    uv = texcoord0;
}