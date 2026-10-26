// =============================================================================
// AEReality / Shaderly - Batch 6: VFX (bubbles / rain / particles) + Sapphire (S_Glint, S_LightLeak) slot tables
//
// Same idea as class Fx (batch 4): one flat List<double> per layer, saved in the layer JSON (so it travels through the
// existing .json preset pipeline) and packed into the uniform buffer next to the other per-layer blocks.
//
// UNIFORM LAYOUT (floats). Text still owns 3872..4095 (tx[224]). Everything below is NEW and starts after it:
//   4096 + layer * 64   VFX block      (shader: vx[layer].v[i])   4096 .. 4735
//   4736 + layer * 64   Sapphire block (shader: sx[layer].s[i])   4736 .. 5375
//   5376 .. 6399        MOTION S (batch 9)   (shader: motionS[1024], class MotionS in motion_slots.dart)
//   6400 .. 7423        TIME SLICE (batch 12) (shader: timeSlice[1024], class TimeSlice in time_slice_slots.dart): per-layer blocks at 6400 + layer * 64 (..7039), per-frame wipe state 7040..7423. Per-layer blocks are read by pass 22 (step C1); per-frame state map 7040..7047 is documented in time_slice_slots.dart and above executeTimeSlice() in the shader
//   7424 .. 7583        METALLIC BEVEL (batch 13) (shader: bevel[160], class Bevel below): per-layer 16-float blocks at 7424 + layer * 16, read by pass 26
//   7584 .. 7743        MATHOPS (batch 14) (shader: mathops[160], class MathOps below): per-layer 16-float blocks at 7584 + layer * 16, read by pass 27
//   7744 .. 7903        4-WAY GRADIENT (batch 14) (shader: grad4[160], class Gradient4Way below): per-layer 16-float blocks at 7744 + layer * 16, read by pass 28
//   7904 .. 8191        free headroom (inside the buffer, not declared in the shader block)
//   total buffer = 8192 floats (4096 -> 5376 in batch 6, 5376 -> 6144 in batch 7, 6144 -> 8192 in batch 9)  ->  kUboFloats
// Slot numbers MUST match the VX_* / SX_* constants in aereality_core.comp.
// =============================================================================

import 'dart:typed_data';

class Vfx {
  static const int size = 64;
  static const int packBase = 4096; // + layer * 64
  static const int uboFloats = 8192; // whole uniform buffer (main.dart, vulkan_processor.cpp, aereality_core.comp). Every caller must send ALL of it.

  // ---- modes ----
  static const int modeOff = 0, modeBubble = 1, modeRain = 2, modeParticle = 3;

  // ---- shared (all three modes) ----
  static const int mode = 0, opacity = 1, blend = 2, scale = 3, scaleVar = 4, density = 5, speed = 6, progression = 7,
      angle = 8, direction = 9, axis = 10, wander = 11, smoothness = 12, seed = 13, hardness = 14, roughness = 15,
      shadow = 16, shadowDist = 17, shadowAngle = 18, glow = 19, glowRadius = 20, tint = 21, tintAmt = 22;
  // ---- bubble ----
  static const int refraction = 23, rim = 24, specular = 25, innerLight = 26, dispersion = 27, defocus = 28;
  // ---- rain ----
  static const int streak = 29, rainAngle = 30, speedVar = 31, depth = 32, rainBright = 33;
  // ---- particle ----
  static const int colorSrc = 35, partColor = 36, partBright = 37, reactSize = 38, reactInvert = 39, reactThr = 40,
      twinkle = 42;
  // ---- how it works with the media (all modes) ----
  static const int maskMode = 44, maskThr = 45, maskSoft = 46, pickup = 47;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[mode] = 0.0;
    f[opacity] = 1.0;
    f[blend] = 0.0;
    f[scale] = 0.35;
    f[scaleVar] = 0.5;
    f[density] = 0.5;
    f[speed] = 0.4;
    f[progression] = 0.0;
    f[angle] = 90.0; // degrees, 0 = right, 90 = up
    f[direction] = 0.0;
    f[axis] = 0.0;
    f[wander] = 0.5;
    f[smoothness] = 0.75;
    f[seed] = 7.0;
    f[hardness] = 0.7;
    f[roughness] = 0.1;
    f[shadow] = 0.35;
    f[shadowDist] = 0.4;
    f[shadowAngle] = 300.0;
    f[glow] = 0.3;
    f[glowRadius] = 0.5;
    f[tint] = 0xBFE8FF.toDouble();
    f[tintAmt] = 0.15;
    f[refraction] = 0.6;
    f[rim] = 0.7;
    f[specular] = 0.8;
    f[innerLight] = 0.5;
    f[dispersion] = 0.25;
    f[defocus] = 0.3;
    f[streak] = 0.5;
    f[rainAngle] = 262.0; // degrees, direction the rain travels (270 = straight down); 262 = slightly wind-slanted
    f[speedVar] = 0.4;
    f[depth] = 0.6;
    f[rainBright] = 0.6;
    f[colorSrc] = 0.0;
    f[partColor] = 0xFFD9A8.toDouble();
    f[partBright] = 1.0;
    f[reactSize] = 0.5;
    f[reactInvert] = 0.0;
    f[reactThr] = 0.3;
    f[twinkle] = 0.3;
    f[maskMode] = 0.0;
    f[maskThr] = 0.5;
    f[maskSoft] = 0.3;
    f[pickup] = 0.4;
    return f;
  }

  /// Fixes length / NaN so old presets (no vfx key) and broken JSON can never corrupt the GPU block.
  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    return d;
  }
}

class Sap {
  static const int size = 64;
  static const int packBase = 4736; // + layer * 64

  // ---- S_Glint (0..31) ----
  static const int gOn = 0, gIntensity = 1, gThreshold = 2, gSize = 3, gRays = 4, gLength = 5, gFalloff = 6,
      gRotate = 7, gDensity = 8, gColor = 9, gColorMix = 10, gCore = 11, gCoreSize = 12, gWidth = 13, gShimmer = 14,
      gOpacity = 15, gBlend = 16, gLenVar = 17, gQuality = 18, gRainbow = 19, gSeed = 20;
  // ---- S_LightLeak (32..63) ----
  static const int lOn = 32, lIntensity = 33, lAngle = 34, lLength = 35, lColorA = 36, lColorB = 37, lColorC = 38,
      lGradient = 39, lStart = 40, lEnd = 41, lFalloff = 42, lSoft = 43, lWidth = 44, lOpacity = 45, lBlend = 46,
      lDrift = 47, lSway = 48, lStreaks = 49, lFlicker = 50, lProtect = 51, lSeed = 52, lMirror = 53;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[gIntensity] = 1.0;
    f[gThreshold] = 0.80;
    f[gSize] = 0.5;
    f[gRays] = 4.0;
    f[gLength] = 0.6;
    f[gFalloff] = 0.5;
    f[gRotate] = 0.0;
    f[gDensity] = 1.0;
    f[gColor] = 0xFFF2D8.toDouble();
    f[gColorMix] = 0.5;
    f[gCore] = 0.6;
    f[gCoreSize] = 0.3;
    f[gWidth] = 0.35;
    f[gShimmer] = 0.3;
    f[gOpacity] = 1.0;
    f[gBlend] = 0.0;
    f[gLenVar] = 0.3;
    f[gQuality] = 0.7;
    f[gRainbow] = 0.0;
    f[gSeed] = 5.0;

    f[lIntensity] = 1.0;
    f[lAngle] = 30.0;
    f[lLength] = 0.6;
    f[lColorA] = 0xFF7A1A.toDouble();
    f[lColorB] = 0xFF2D55.toDouble();
    f[lColorC] = 0xFFD27A.toDouble();
    f[lGradient] = 1.0;
    f[lStart] = 0.0;
    f[lEnd] = 0.7;
    f[lFalloff] = 0.6;
    f[lSoft] = 0.6;
    f[lWidth] = 0.5;
    f[lOpacity] = 1.0;
    f[lBlend] = 0.0;
    f[lDrift] = 0.0;
    f[lSway] = 0.2;
    f[lStreaks] = 0.35;
    f[lFlicker] = 0.15;
    f[lProtect] = 0.4;
    f[lSeed] = 3.0;
    return f;
  }

  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    return d;
  }
}

// =============================================================================
// Batch 13: GLOBAL METALLIC BEVEL ("Send-Off" effect). One flat List<double> per layer (saved in the layer JSON, key "bevel"), 16 floats per layer
// packed at 7424 + layer * 16. Shader passes 25 (luma plane) + 26 (bevel) run after Time Slice (22) and before the dither (23).
// Slot numbers MUST match bevel[layer * 16 + i] in executeMetallicBevel() (aereality_core.comp) and findBevel() in vulkan_processor.cpp.
// Old presets have no "bevel" key -> defaults (effect OFF).
// =============================================================================
class Bevel {
  static const int size = 16;
  static const int packBase = 7424; // + layer * 16
  static const int layers = 10;

  static const int on = 0; // 0 / 1
  static const int intensity = 1; // Bevel Intensity (default 2.5)
  static const int gloss = 2; // Gloss Strength (default 2.0)
  static const int shininess = 3; // Blinn-Phong exponent (default 48)
  static const int lightX = 4; // default -0.3
  static const int lightY = 5; // default 0.4 (+ = light from the top of the screen)
  static const int mix = 6; // blend with the original (default 1.0)
  // 7 .. 15 reserved for future tuning

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[on] = 0.0;
    f[intensity] = 2.5;
    f[gloss] = 2.0;
    f[shininess] = 48.0;
    f[lightX] = -0.3;
    f[lightY] = 0.4;
    f[mix] = 1.0;
    return f;
  }

  static double _c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Fixes length / NaN / out-of-range values so an old preset, a broken file or a hand-edited .json can never corrupt the GPU block.
  /// The ranges are the same ones the shader clamps to.
  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    d[intensity] = _c(d[intensity], 0.0, 10.0);
    d[gloss] = _c(d[gloss], 0.0, 8.0);
    d[shininess] = _c(d[shininess], 1.0, 256.0);
    d[lightX] = _c(d[lightX], -1.0, 1.0);
    d[lightY] = _c(d[lightY], -1.0, 1.0);
    d[mix] = _c(d[mix], 0.0, 1.0);
    return d;
  }

  /// Writes every layer's bevel block into the uniform buffer (7424 + layer * 16). Used by _packMultiLayerUniforms (main.dart) and
  /// packProjectUniforms (project_uniforms.dart), so both stay in sync.
  static void packLayers(Float32List u, List<List<double>> blocks) {
    for (int l = 0; l < blocks.length && l < layers; l++) {
      final s = sanitize(blocks[l]);
      final base = packBase + l * size;
      for (int i = 0; i < size; i++) {
        u[base + i] = s[i];
      }
    }
  }
}

// =============================================================================
// Batch 14: MATHOPS (shader pass 27). One flat List<double> per layer (layer JSON key "mathOps"), 16 floats per layer packed at 7584 + layer * 16.
// Applies one operation between each pixel's RGB and a scalar, clamped to 0..1. Slots MUST match mathops[layer * 16 + i] in executeMathOps().
// Old presets have no key -> defaults (effect OFF).
// =============================================================================
class MathOps {
  static const int size = 16;
  static const int packBase = 7584; // + layer * 16
  static const int layers = 10;

  static const int on = 0; // 0 / 1
  static const int operation = 1; // 0 Add, 1 Subtract, 2 Multiply, 3 Divide, 4 Min, 5 Max, 6 Screen
  static const int value = 2; // 0 .. 2
  static const int channel = 3; // 0 RGB, 1 Red, 2 Green, 3 Blue
  static const int mix = 4; // 0 .. 1
  // 5 .. 15 reserved

  static const List<String> opLabels = ['Add', 'Subtract', 'Multiply', 'Divide', 'Min', 'Max', 'Screen'];
  static const List<String> channelLabels = ['RGB', 'Red', 'Green', 'Blue'];

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[on] = 0.0;
    f[operation] = 2.0; // [ASSUMED] Multiply: with Value 1.0 it changes nothing, so switching the effect on starts neutral
    f[value] = 1.0;
    f[channel] = 0.0;
    f[mix] = 1.0;
    return f;
  }

  static double _c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Fixes length / NaN / out-of-range values (same ranges the shader clamps to).
  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    d[operation] = _c(d[operation].roundToDouble(), 0.0, 6.0);
    d[value] = _c(d[value], 0.0, 2.0);
    d[channel] = _c(d[channel].roundToDouble(), 0.0, 3.0);
    d[mix] = _c(d[mix], 0.0, 1.0);
    return d;
  }

  static void packLayers(Float32List u, List<List<double>> blocks) {
    for (int l = 0; l < blocks.length && l < layers; l++) {
      final s = sanitize(blocks[l]);
      final base = packBase + l * size;
      for (int i = 0; i < size; i++) {
        u[base + i] = s[i];
      }
    }
  }
}

// =============================================================================
// Batch 14: 4-WAY GRADIENT (shader pass 28). One flat List<double> per layer (layer JSON key "grad4"), 16 floats per layer packed at 7744 + layer * 16.
// Four control points (UV 0..1, (0,0) = top left) with packed 0xRRGGBB colours, blended with inverse distance weighting. Slots MUST match
// grad4[layer * 16 + i] in executeGradient4(). Old presets have no key -> defaults (effect OFF).
// =============================================================================
class Gradient4Way {
  static const int size = 16;
  static const int packBase = 7744; // + layer * 16
  static const int layers = 10;

  static const int on = 0; // 0 / 1
  static const int p1x = 1, p1y = 2, p1c = 3;
  static const int p2x = 4, p2y = 5, p2c = 6;
  static const int p3x = 7, p3y = 8, p3c = 9;
  static const int p4x = 10, p4y = 11, p4c = 12;
  static const int mix = 13; // 0 .. 1
  // 14, 15 reserved

  /// Slot of point [k] (0..3): X is the returned slot, Y is +1, colour is +2.
  static int pointSlot(int k) => 1 + k * 3;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[on] = 0.0;
    f[p1x] = 0.0; f[p1y] = 0.0; f[p1c] = 0x00E5FF.toDouble(); // [ASSUMED] corners + app palette colours as a starting point
    f[p2x] = 1.0; f[p2y] = 0.0; f[p2c] = 0xFF3366.toDouble();
    f[p3x] = 0.0; f[p3y] = 1.0; f[p3c] = 0xFFD700.toDouble();
    f[p4x] = 1.0; f[p4y] = 1.0; f[p4c] = 0x7C4DFF.toDouble();
    f[mix] = 1.0;
    return f;
  }

  static double _c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Fixes length / NaN / out-of-range values (same ranges the shader clamps to). Colours stay whole numbers 0 .. 0xFFFFFF (exact in a float).
  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    for (int k = 0; k < 4; k++) {
      final b = pointSlot(k);
      d[b] = _c(d[b], 0.0, 1.0);
      d[b + 1] = _c(d[b + 1], 0.0, 1.0);
      d[b + 2] = _c(d[b + 2].roundToDouble(), 0.0, 16777215.0);
    }
    d[mix] = _c(d[mix], 0.0, 1.0);
    return d;
  }

  static void packLayers(Float32List u, List<List<double>> blocks) {
    for (int l = 0; l < blocks.length && l < layers; l++) {
      final s = sanitize(blocks[l]);
      final base = packBase + l * size;
      for (int i = 0; i < size; i++) {
        u[base + i] = s[i];
      }
    }
  }
}
