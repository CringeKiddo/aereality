#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    vec3 color = texture(uTexture, uv).rgb;
    
    // Tint the video RED – if you see red, the pipeline works!
    color = color * vec3(1.0, 0.0, 0.0);
    
    fragColor = vec4(color, 1.0);
}
