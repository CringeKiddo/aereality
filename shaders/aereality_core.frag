#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform sampler2D uTexture; // not used – just to keep the signature

out vec4 fragColor;

void main() {
    // Use the fragment coordinates to create a gradient
    vec2 uv = FlutterFragCoord().xy / uResolution;
    // Red-green gradient: red varies with x, green with y
    vec3 color = vec3(uv.x, uv.y, 0.0);
    // Add a blue stripe to make it obvious
    if (uv.x > 0.5 && uv.y > 0.5) {
        color = vec3(0.0, 0.0, 1.0);
    }
    fragColor = vec4(color, 1.0);
}
