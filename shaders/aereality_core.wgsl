// ============================================================
// AEReality 32-Bit GPU Shader (Flutter GPU / WGSL)
// 
// All math is done in 32-bit float (highp) with:
//   - sRGB → Linear conversion at input
//   - All grading in Linear space
//   - Bloom on unclipped linear data
//   - Filmic tonemap in Linear space
//   - Linear → sRGB conversion after tonemap
//   - Dithering at the very end
//   - NO premature clamping
// ============================================================

// ---------- BINDINGS ----------
@group(0) @binding(0) var inputTexture : texture_2d<f32>;
@group(0) @binding(1) var outputTexture : texture_storage_2d<rgba32float, write>;

// ---------- UNIFORMS ----------
struct Uniforms {
    resolution : vec2f,          // width, height
    brightness : f32,
    saturation : f32,
    contrast   : f32,
    sharpness  : f32,
    gamma      : f32,
    hue        : f32,
    temperature: f32,
    glowIntensity: f32,
    lookMix    : f32,
    vignette   : f32,
    splitToning: f32,
};
@group(0) @binding(2) var<uniform> u : Uniforms;

// ---------- HELPER: sRGB ↔ Linear ----------
fn srgb_to_linear(v: f32) -> f32 {
    if (v <= 0.04045) { return v / 12.92; }
    return pow((v + 0.055) / 1.055, 2.4);
}

fn linear_to_srgb(v: f32) -> f32 {
    if (v <= 0.0031308) { return v * 12.92; }
    return pow(v, 1.0 / 2.4) * 1.055 - 0.055;
}

// ---------- HELPER: RGB <-> HSV ----------
fn rgb2hsv(r: f32, g: f32, b: f32) -> vec3f {
    let maxv = max(r, max(g, b));
    let minv = min(r, min(g, b));
    let delta = maxv - minv;
    var h = 0.0;
    var s = 0.0;
    let v = maxv;
    if (delta != 0.0) {
        s = delta / maxv;
        if (r == maxv) { h = (g - b) / delta + (g < b ? 6.0 : 0.0); }
        else if (g == maxv) { h = (b - r) / delta + 2.0; }
        else { h = (r - g) / delta + 4.0; }
        h = h / 6.0;
    }
    return vec3f(h, s, v);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3f {
    if (s == 0.0) { return vec3f(v, v, v); }
    let h6 = h * 6.0;
    let hi = floor(h6);
    let f = h6 - hi;
    let p = v * (1.0 - s);
    let q = v * (1.0 - f * s);
    let t = v * (1.0 - (1.0 - f) * s);
    var r = v; var g = t; var b = p;
    let hi_i = i32(hi);
    if (hi_i == 1) { r = q; g = v; b = p; }
    else if (hi_i == 2) { r = p; g = v; b = t; }
    else if (hi_i == 3) { r = p; g = q; b = v; }
    else if (hi_i == 4) { r = t; g = p; b = v; }
    else if (hi_i == 5) { r = v; g = p; b = q; }
    return vec3f(r, g, b);
}

// ---------- HELPER: TEMPERATURE ----------
fn temperature_shift(kelvin: f32) -> vec3f {
    let t = clamp((kelvin - 2000.0) / 10000.0, 0.0, 1.0);
    let r = 1.0 + (t * 0.3);
    let g = 1.0 + (t * 0.1) - ((1.0 - t) * 0.1);
    let b = 1.0 + ((1.0 - t) * 0.3);
    return vec3f(r, g, b);
}

// ---------- HELPER: FILMIC TONEMAP ----------
fn filmic_tonemap(color: vec3f) -> vec3f {
    let x = max(vec3f(0.0), color - 0.004);
    let result = (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    return pow(result, vec3f(1.0 / 2.2));
}

// ---------- HELPER: TEAL & ORANGE ----------
fn teal_orange(color: vec3f, mixAmount: f32) -> vec3f {
    let luma = dot(color, vec3f(0.2126, 0.7152, 0.0722));
    let teal = vec3f(0.0, 0.6, 0.6);
    let orange = vec3f(1.0, 0.6, 0.1);
    let graded = mix(teal, orange, vec3f(luma));
    let result = mix(color, color * graded, 0.7);
    return mix(color, result, mixAmount);
}

// ---------- DITHERING ----------
fn dither_noise(x: i32, y: i32) -> f32 {
    let n = f32(x) * 0.618033988749895 + f32(y) * 0.7071067811865475;
    return (n - floor(n)) - 0.5;
}

// ---------- MAIN COMPUTE SHADER ----------
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let x = i32(id.x);
    let y = i32(id.y);
    let w = i32(u.resolution.x);
    let h = i32(u.resolution.y);
    
    // Bounds check
    if (x >= w || y >= h) { return; }
    
    // ========== 1. READ INPUT (sRGB) ==========
    let uv = vec2f(f32(x) / f32(w), f32(y) / f32(h));
    let srgb = textureSampleLevel(inputTexture, textureSampler, uv, 0.0).rgb;
    
    // ========== 2. sRGB → LINEAR ==========
    var color = vec3f(
        srgb_to_linear(srgb.r),
        srgb_to_linear(srgb.g),
        srgb_to_linear(srgb.b)
    );
    
    // ========== 3. SHARPENING (linear) ==========
    if (u.sharpness > 0.005) {
        let texelSize = 1.0 / vec2f(f32(w), f32(h));
        let left   = textureSampleLevel(inputTexture, textureSampler, uv - vec2f(texelSize.x, 0.0), 0.0).rgb;
        let right  = textureSampleLevel(inputTexture, textureSampler, uv + vec2f(texelSize.x, 0.0), 0.0).rgb;
        let up     = textureSampleLevel(inputTexture, textureSampler, uv - vec2f(0.0, texelSize.y), 0.0).rgb;
        let down   = textureSampleLevel(inputTexture, textureSampler, uv + vec2f(0.0, texelSize.y), 0.0).rgb;
        let laplacian = 4.0 * color - (left + right + up + down);
        color += laplacian * u.sharpness * 0.15;
    }
    
    // ========== 4. TEMPERATURE (linear) ==========
    let tempGain = temperature_shift(u.temperature);
    color *= tempGain;
    
    // ========== 5. HUE (linear) ==========
    if (abs(u.hue) > 0.5) {
        let hsv = rgb2hsv(color.r, color.g, color.b);
        let newH = fract(hsv.x + (u.hue / 360.0));
        color = hsv2rgb(newH, hsv.y, hsv.z);
    }
    
    // ========== 6. SATURATION (linear) ==========
    let luma = dot(color, vec3f(0.2126, 0.7152, 0.0722));
    color = mix(vec3f(luma), color, u.saturation);
    
    // ========== 7. CONTRAST (linear) ==========
    color = (color - 0.5) * u.contrast + 0.5;
    
    // ========== 8. BRIGHTNESS (linear) ==========
    color += u.brightness;
    
    // ========== 9. GAMMA (linear) ==========
    let invGamma = 1.0 / max(u.gamma, 0.1);
    color = pow(max(vec3f(0.0), color), vec3f(invGamma));
    
    // ========== 10. TEAL & ORANGE (linear) ==========
    color = teal_orange(color, u.lookMix);
    
    // ========== 11. VIGNETTE (linear) ==========
    let vigUV = uv - 0.5;
    let vigDist = length(vigUV);
    let vignetteAmount = 1.0 - (vigDist * u.vignette * 1.5);
    color *= vignetteAmount;
    
    // ========== 12. SPLIT TONING (linear) ==========
    let lumaSplit = dot(color, vec3f(0.2126, 0.7152, 0.0722));
    let shadowTint = vec3f(0.1, 0.2, 0.6);
    let highlightTint = vec3f(1.0, 0.5, 0.1);
    let tonedColor = mix(shadowTint, highlightTint, vec3f(lumaSplit));
    color = mix(color, color * tonedColor, u.splitToning * 0.4);
    
    // ========== 13. GLOW (linear, BEFORE tonemap) ==========
    if (u.glowIntensity > 0.005) {
        var blur = vec3f(0.0);
        let blurStep = 2.0 / vec2f(f32(w), f32(h));
        for (var kx = -1; kx <= 1; kx++) {
            for (var ky = -1; ky <= 1; ky++) {
                let offset = vec2f(f32(kx), f32(ky)) * blurStep;
                blur += textureSampleLevel(inputTexture, textureSampler, uv + offset, 0.0).rgb;
            }
        }
        blur /= 9.0;
        // Convert blur to linear
        blur = vec3f(
            srgb_to_linear(blur.r),
            srgb_to_linear(blur.g),
            srgb_to_linear(blur.b)
        );
        let lumaBlur = dot(blur, vec3f(0.2126, 0.7152, 0.0722));
        let glowMask = smoothstep(0.3, 0.8, lumaBlur);
        let glow = blur * glowMask * u.glowIntensity * 0.6;
        color += glow;
    }
    
    // ========== 14. FILMIC TONEMAP (linear) ==========
    color = filmic_tonemap(color);
    
    // ========== 15. LINEAR → sRGB ==========
    color = vec3f(
        linear_to_srgb(color.r),
        linear_to_srgb(color.g),
        linear_to_srgb(color.b)
    );
    
    // ========== 16. DITHER (end of pipeline) ==========
    let noise = dither_noise(x, y) / 255.0;
    color += noise;
    
    // ========== 17. FINAL CLAMP & OUTPUT ==========
    let out = clamp(color, 0.0, 1.0);
    textureStore(outputTexture, vec2i(x, y), vec4f(out, 1.0));
}
