#version 460 core
#include <flutter/runtime_effect.glsl>

// ---------- UNIFORMS (ORDER MATTERS!) ----------
uniform sampler2D uTexture;   // index 0 (sampler)
uniform vec2 uResolution;     // index 1,2 (floats)

uniform float uBrightness;    // index 3
uniform float uSaturation;    // index 4
uniform float uContrast;      // index 5
uniform float uSharpness;     // index 6
uniform float uGamma;         // index 7
uniform float uHue;           // index 8
uniform float uTemperature;   // index 9
uniform float uGlowIntensity; // index 10
uniform float uLookMix;       // index 11
uniform float uVignette;      // index 12
uniform float uSplitToning;   // index 13

out vec4 fragColor;

// ---------- HELPER: RGB <-> HSV ----------
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// ---------- HELPER: COLOR TEMPERATURE (KELVIN) ----------
vec3 temperatureShift(float kelvin) {
    float t = clamp((kelvin - 2000.0) / 10000.0, 0.0, 1.0);
    float r = 1.0 + (t * 0.3);
    float g = 1.0 + (t * 0.1) - ((1.0 - t) * 0.1);
    float b = 1.0 + ((1.0 - t) * 0.3);
    return vec3(r, g, b);
}

// ---------- HELPER: FILMIC TONE MAP (Magic Bullet / AE Look) ----------
vec3 filmicTonemap(vec3 color) {
    vec3 x = max(vec3(0.0), color - 0.004);
    vec3 result = (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    return pow(result, vec3(1.0 / 2.2));
}

// ---------- HELPER: TEAL & ORANGE LOOK ----------
vec3 applyTealOrange(vec3 color, float mixAmount) {
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 teal = vec3(0.0, 0.6, 0.6);
    vec3 orange = vec3(1.0, 0.6, 0.1);
    vec3 graded = mix(teal, orange, luma);
    vec3 result = mix(color, color * graded, 0.7);
    return mix(color, result, mixAmount);
}

// ---------- MAIN SHADER ----------
void main() {
    // 1. Get the video frame
    vec2 uv = FlutterFragCoord().xy / uResolution;
    vec3 color = texture(uTexture, uv).rgb;

    // 2. SHARPENING (Unsharp Mask)
    vec2 texelSize = 1.0 / uResolution;
    vec3 left   = texture(uTexture, uv - vec2(texelSize.x, 0.0)).rgb;
    vec3 right  = texture(uTexture, uv + vec2(texelSize.x, 0.0)).rgb;
    vec3 up     = texture(uTexture, uv - vec2(0.0, texelSize.y)).rgb;
    vec3 down   = texture(uTexture, uv + vec2(0.0, texelSize.y)).rgb;
    vec3 laplacian = 4.0 * color - (left + right + up + down);
    color = color + (laplacian * uSharpness * 0.15);

    // 3. GLOW / BLOOM (9-tap box blur on bright areas)
    vec2 blurStep = texelSize * 2.0;
    vec3 blur = vec3(0.0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 offset = vec2(float(x), float(y)) * blurStep;
            blur += texture(uTexture, uv + offset).rgb;
        }
    }
    blur /= 9.0;
    float lumaBlur = dot(blur, vec3(0.2126, 0.7152, 0.0722));
    float glowMask = smoothstep(0.3, 0.8, lumaBlur);
    vec3 glow = blur * glowMask * uGlowIntensity * 0.6;
    color = color + glow;

    // 4. TEMPERATURE (White Balance)
    vec3 tempGain = temperatureShift(uTemperature);
    color = color * tempGain;

    // 5. HUE ROTATION
    if (abs(uHue) > 0.01) {
        vec3 hsv = rgb2hsv(color);
        hsv.x = fract(hsv.x + (uHue / 360.0));
        color = hsv2rgb(hsv);
    }

    // 6. SATURATION
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, uSaturation);

    // 7. CONTRAST
    color = (color - vec3(0.5)) * uContrast + vec3(0.5);

    // 8. BRIGHTNESS
    color = color + vec3(uBrightness);

    // 9. GAMMA CORRECTION
    color = pow(max(vec3(0.0), color), vec3(1.0 / max(uGamma, 0.1)));

    // 10. TEAL & ORANGE LOOK (Magic Bullet style)
    color = applyTealOrange(color, uLookMix);

    // 11. VIGNETTE (Darkens the edges)
    vec2 vigUV = uv - 0.5;
    float vigDist = length(vigUV);
    float vignetteAmount = 1.0 - (vigDist * uVignette * 1.5);
    color *= vignetteAmount;

    // 12. SPLIT TONING (Shadows -> Blue, Highlights -> Orange)
    float lumaSplit = dot(color, vec3(0.2126, 0.7152, 0.0722));
    vec3 shadowTint = vec3(0.1, 0.2, 0.6);   // Deep blue
    vec3 highlightTint = vec3(1.0, 0.5, 0.1); // Warm orange
    vec3 tonedColor = mix(shadowTint, highlightTint, lumaSplit);
    color = mix(color, color * tonedColor, uSplitToning * 0.4);

    // 13. FILMIC TONE MAPPING (Prevents clipping, gives AE rich feel)
    color = filmicTonemap(color);

    // 14. FINAL CLAMP & OUTPUT
    color = clamp(color, 0.0, 1.0);
    fragColor = vec4(color, 1.0);
}
