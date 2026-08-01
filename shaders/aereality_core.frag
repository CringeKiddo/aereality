#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    // Ignore texture – just output red
    fragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
