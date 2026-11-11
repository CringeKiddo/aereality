// =============================================================================
// AEReality / Shaderly - Batch 19: LOOKS (diffusion looks, glimmer glass, film damage), EDGE FX (border effects) and EFFECT REGION slot tables
//
// Same idea as Bevel / MathOps / Gradient4Way (vfx_slots.dart): one flat List<double> per layer, saved in the layer JSON (keys "looks", "edgeFx", "place"),
// packed into the uniform buffer. The uniform buffer grew from 8192 to 9216 floats (Vfx.uboFloats) for these blocks:
//   8192 + layer * 32   LOOKS      8192 .. 8511   (shader: looks[320],  LK(l, i))   read by pass 33
//   8512 + layer * 48   EDGE FX    8512 .. 8991   (shader: edgefx[480], EG(l, i))   read by pass 34
//   8992 + layer *  8   REGION     8992 .. 9071   (shader: place[80],   PL(l, i))   read by VFX (pass 13), Optical Diffusion (32), Looks (33), Edge FX (34)
// Slot numbers MUST match the LK / EG / PL numbers in aereality_core.comp and findBatch6Passes() in vulkan_processor.cpp.
// Old presets have none of the keys -> defaults (everything OFF).
// =============================================================================

import 'dart:typed_data';

double _c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

List<double> _fix(List<double>? src, List<double> d) {
  if (src == null) return d;
  for (int i = 0; i < d.length && i < src.length; i++) {
    final v = src[i];
    if (!v.isNaN && !v.isInfinite) d[i] = v;
  }
  return d;
}

class Looks {
  static const int size = 32;
  static const int packBase = 8192; // + layer * 32
  static const int layers = 10;

  // ---- Looks Diffusion (lens-filter looks) ----
  static const int ldOn = 0, ldType = 1, ldStrength = 2, ldRadius = 3, ldHalation = 4, ldContrast = 5, ldHiBias = 6;
  static const List<String> ldTypes = ['Black Pro-Mist', 'White Pro-Mist', 'Soft FX', 'Hollywood Black Magic', 'Classic Soft'];
  // ---- Film Damage ----
  static const int fdOn = 8, fdGrain = 9, fdGrainSize = 10, fdScratches = 11, fdDust = 12, fdHair = 13, fdFlicker = 14, fdWeave = 15,
      fdBlotch = 16, fdBurn = 17, fdFps = 18, fdSeed = 19, fdTint = 20;
  // ---- Glimmer Glass ----
  static const int gcOn = 21, gcSparkle = 22, gcSize = 23, gcThreshold = 24, gcGlow = 25, gcDensity = 26, gcRays = 27, gcTwinkle = 28, gcColor = 29, gcSeed = 30;
  static const List<String> gcColors = ['White', 'Warm', 'Cool', 'Rainbow'];
  static const int opacity = 31;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[ldType] = 0.0;
    f[ldStrength] = 0.55;
    f[ldRadius] = 0.5;
    f[ldHalation] = 0.25;
    f[ldContrast] = 0.20;
    f[ldHiBias] = 0.35;
    f[fdGrain] = 0.45;
    f[fdGrainSize] = 0.35;
    f[fdScratches] = 0.35;
    f[fdDust] = 0.45;
    f[fdHair] = 0.20;
    f[fdFlicker] = 0.25;
    f[fdWeave] = 0.25;
    f[fdBlotch] = 0.20;
    f[fdBurn] = 0.0;
    f[fdFps] = 12.0;
    f[fdSeed] = 3.0;
    f[fdTint] = 0.0;
    f[gcSparkle] = 0.7;
    f[gcSize] = 0.60;
    f[gcThreshold] = 0.60;
    f[gcGlow] = 0.45;
    f[gcDensity] = 0.45;
    f[gcRays] = 2.0;
    f[gcTwinkle] = 0.5;
    f[gcColor] = 0.0;
    f[gcSeed] = 5.0;
    f[opacity] = 1.0;
    return f;
  }

  static List<double> sanitize(List<double>? src) {
    final d = _fix(src, defaults());
    for (final s in const [ldOn, fdOn, gcOn]) {
      d[s] = d[s] >= 0.5 ? 1.0 : 0.0;
    }
    d[ldType] = _c(d[ldType].roundToDouble(), 0.0, (ldTypes.length - 1).toDouble());
    for (final s in const [ldStrength, ldRadius, ldHalation, ldContrast, ldHiBias, fdGrain, fdGrainSize, fdScratches, fdDust, fdHair, fdFlicker, fdWeave, fdBlotch, fdBurn, fdTint, gcSparkle, gcSize, gcGlow, gcDensity, gcTwinkle, opacity]) {
      d[s] = _c(d[s], 0.0, 1.0);
    }
    d[fdFps] = _c(d[fdFps], 2.0, 30.0);
    d[gcThreshold] = _c(d[gcThreshold], 0.0, 1.5);
    d[gcRays] = _c(d[gcRays].roundToDouble(), 2.0, 4.0);
    d[gcColor] = _c(d[gcColor].roundToDouble(), 0.0, 3.0);
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

class EdgeFx {
  static const int size = 48;
  static const int packBase = 8512; // + layer * 48
  static const int layers = 10;

  static const int on = 0, mode = 1, width = 2, intensity = 3, speed = 4, scale = 5, softness = 6, opacity = 7, seed = 8;
  static const int sideTop = 9, sideRight = 10, sideBottom = 11, sideLeft = 12, colorA = 13, colorB = 14, inset = 15, blend = 16, p0 = 17, corner = 27;
  static int p(int k) => p0 + k;

  static const List<String> modes = ['Water', 'Audio visualizer', 'Glossy leaves', 'Blood mist', 'LED lights', 'Pyro aura', 'Anemo vortex', 'Red / black glitch'];

  /// Labels, ranges of the mode parameters (slots 17..26). null = the slot is not used by the mode.
  static const List<List<(String, double, double)?>> paramInfo = [
    // 0 Water
    [('Refraction', 0.0, 2.0), ('Specular glint', 0.0, 1.5), ('Flow / ripple speed', 0.0, 2.0), ('Tint amount', 0.0, 1.0), null, ('Ripple strength', 0.0, 1.5)],
    // 1 Audio visualizer
    [('Bars', 8.0, 120.0), ('Bar height', 0.2, 1.5), ('Double sided (0 / 1)', 0.0, 1.0), ('Offset from edge (double sided)', 0.0, 0.15), ('Gap between bars', 0.0, 0.85), ('Beat (BPM)', 40.0, 200.0)],
    // 2 Glossy leaves
    [('Spacing', 0.0, 1.0), ('Leaf size', 0.0, 1.0), ('Sway', 0.0, 1.5), ('Gloss', 0.0, 1.5), ('Layers (1-3)', 1.0, 3.0), ('Autumn shift', 0.0, 1.0)],
    // 3 Blood mist
    [('Density', 0.0, 1.5), ('Drift speed', 0.0, 2.0), ('Darkness', 0.0, 1.0), ('Wisp size', 0.0, 1.0)],
    // 4 LED lights
    [('LED spacing', 0.0, 1.0), ('LED size', 0.0, 1.0), ('Glow', 0.0, 1.0), ('Pattern (0 solid, 1 chase, 2 rainbow, 3 pulse, 4 twinkle)', 0.0, 4.0), ('Light spill into picture', 0.0, 1.0), ('Rows (1-3)', 1.0, 3.0)],
    // 5 Pyro aura
    [('Flame height', 0.1, 1.5), ('Turbulence', 0.0, 1.5), ('Heat (white-hot core)', 0.0, 1.0), ('Flicker', 0.0, 1.0), ('Embers', 0.0, 1.0)],
    // 6 Anemo vortex
    [('Vortices', 1.0, 12.0), ('Spiral arms', 2.0, 8.0), ('Twist', 0.0, 2.0), ('Ribbon thinness', 0.0, 1.0), null, ('Glow', 0.0, 1.0)],
    // 7 Red / black glitch
    [('Blocks', 2.0, 24.0), ('Max block size', 0.02, 0.6), ('Chance per step', 0.0, 1.0), ('Red vs black', 0.0, 1.0), ('RGB split', 0.0, 1.5), ('Steps per second', 1.0, 30.0), ('Scan tears', 0.0, 1.0)],
  ];

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[mode] = 0.0;
    f[width] = 0.14;
    f[intensity] = 1.0;
    f[speed] = 1.0;
    f[scale] = 0.5;
    f[softness] = 0.5;
    f[opacity] = 1.0;
    f[seed] = 4.0;
    f[sideTop] = 1.0;
    f[sideRight] = 1.0;
    f[sideBottom] = 1.0;
    f[sideLeft] = 1.0;
    f[colorA] = 0x7FD8FF.toDouble();
    f[colorB] = 0xFFFFFF.toDouble();
    f[inset] = 0.0;
    f[corner] = 0.0;
    modeDefaults(f, 0);
    return f;
  }

  /// Sets the parameters, colours and a few common values to a good starting point for [m] (called when a mode is picked).
  static void modeDefaults(List<double> f, int m) {
    for (int k = 0; k < 10; k++) {
      f[p(k)] = 0.0;
    }
    f[mode] = m.toDouble();
    f[sideTop] = 1.0;
    f[sideRight] = 1.0;
    f[sideBottom] = 1.0;
    f[sideLeft] = 1.0;
    f[inset] = 0.0;
    switch (m) {
      case 0:
        f[width] = 0.09; f[softness] = 0.5; f[scale] = 0.5; f[speed] = 1.0;
        f[p(0)] = 1.0; f[p(1)] = 0.8; f[p(2)] = 0.5; f[p(3)] = 0.25; f[p(5)] = 0.6;
        f[colorA] = 0x7FD8FF.toDouble(); f[colorB] = 0xFFFFFF.toDouble();
        break;
      case 1:
        f[width] = 0.18; f[speed] = 1.0;
        f[p(0)] = 48.0; f[p(1)] = 1.3; f[p(2)] = 0.0; f[p(3)] = 0.03; f[p(4)] = 0.30; f[p(5)] = 120.0;
        f[sideTop] = 0.0; f[sideLeft] = 0.0; f[sideRight] = 0.0; // bottom edge only
        f[colorA] = 0x00E5FF.toDouble(); f[colorB] = 0xFF2BD6.toDouble();
        break;
      case 2:
        f[width] = 0.20; f[speed] = 1.0;
        f[p(0)] = 0.40; f[p(1)] = 0.50; f[p(2)] = 0.60; f[p(3)] = 0.70; f[p(4)] = 2.0; f[p(5)] = 0.0;
        f[colorA] = 0x1E6B2E.toDouble(); f[colorB] = 0x7BD66A.toDouble();
        break;
      case 3:
        f[width] = 0.22; f[softness] = 0.6; f[speed] = 1.0;
        f[p(0)] = 1.0; f[p(1)] = 0.5; f[p(2)] = 0.6; f[p(3)] = 0.5;
        f[colorA] = 0x3A0005.toDouble(); f[colorB] = 0xC1121F.toDouble();
        break;
      case 4:
        f[width] = 0.06; f[speed] = 1.0;
        f[p(0)] = 0.35; f[p(1)] = 0.50; f[p(2)] = 0.60; f[p(3)] = 2.0; f[p(4)] = 0.60; f[p(5)] = 1.0;
        f[colorA] = 0x00E5FF.toDouble(); f[colorB] = 0xFF2BD6.toDouble();
        break;
      case 5:
        f[width] = 0.22; f[softness] = 0.5; f[speed] = 1.0;
        f[p(0)] = 1.1; f[p(1)] = 0.7; f[p(2)] = 0.6; f[p(3)] = 0.5; f[p(4)] = 0.5;
        f[sideTop] = 0.0; f[sideLeft] = 0.0; f[sideRight] = 0.0; // flames from the bottom edge
        f[colorA] = 0xFF3300.toDouble(); f[colorB] = 0xFFC21A.toDouble();
        break;
      case 6:
        f[width] = 0.20; f[speed] = 1.0; f[scale] = 0.5;
        f[p(0)] = 3.0; f[p(1)] = 4.0; f[p(2)] = 0.8; f[p(3)] = 0.5; f[p(5)] = 0.6;
        f[colorA] = 0x3FE0C8.toDouble(); f[colorB] = 0xF2FFFB.toDouble();
        break;
      default:
        f[width] = 0.14; f[speed] = 1.0;
        f[p(0)] = 10.0; f[p(1)] = 0.15; f[p(2)] = 0.35; f[p(3)] = 0.6; f[p(4)] = 0.5; f[p(5)] = 12.0; f[p(6)] = 0.5;
        f[colorA] = 0xE0111F.toDouble(); f[colorB] = 0x000000.toDouble();
    }
  }

  static List<double> sanitize(List<double>? src) {
    final d = _fix(src, defaults());
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    d[mode] = _c(d[mode].roundToDouble(), 0.0, (modes.length - 1).toDouble());
    d[width] = _c(d[width], 0.01, 0.6);
    d[intensity] = _c(d[intensity], 0.0, 3.0);
    d[speed] = _c(d[speed], 0.0, 4.0);
    d[scale] = _c(d[scale], 0.0, 1.0);
    d[softness] = _c(d[softness], 0.0, 1.0);
    d[opacity] = _c(d[opacity], 0.0, 1.0);
    for (final s in const [sideTop, sideRight, sideBottom, sideLeft]) {
      d[s] = d[s] >= 0.5 ? 1.0 : 0.0;
    }
    d[colorA] = _c(d[colorA].roundToDouble(), 0.0, 16777215.0);
    d[colorB] = _c(d[colorB].roundToDouble(), 0.0, 16777215.0);
    d[inset] = _c(d[inset], 0.0, 0.3);
    d[blend] = _c(d[blend].roundToDouble(), 0.0, 40.0);
    d[corner] = _c(d[corner], 0.0, 0.4);
    for (int k = 0; k < 10; k++) {
      d[p(k)] = _c(d[p(k)], -1000.0, 1000.0);
    }
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

/// Effect region: where on the picture a layer's VFX / diffusion / Looks / Edge FX act. Moved and sized with the handle in the preview (EffectRegionGizmo).
class Place {
  static const int size = 8;
  static const int packBase = 8992; // + layer * 8
  static const int layers = 10;

  static const int on = 0, cx = 1, cy = 2, zoom = 3, feather = 4, shape = 5;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[cx] = 0.5;
    f[cy] = 0.5;
    f[zoom] = 1.0;
    f[feather] = 0.35;
    f[shape] = 0.0;
    return f;
  }

  static List<double> sanitize(List<double>? src) {
    final d = _fix(src, defaults());
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    d[cx] = _c(d[cx], -0.5, 1.5);
    d[cy] = _c(d[cy], -0.5, 1.5);
    d[zoom] = _c(d[zoom], 0.1, 4.0);
    d[feather] = _c(d[feather], 0.02, 1.0);
    d[shape] = d[shape] >= 0.5 ? 1.0 : 0.0;
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
