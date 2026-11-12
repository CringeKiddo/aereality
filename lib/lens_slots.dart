// =============================================================================
// AEReality / Shaderly - Batch 20: CHROMATIC ABERRATION (lens) and INNER EDGE GLOW slot tables
//
// Same idea as Looks / EdgeFx / Place (looks_edge_slots.dart): one flat List<double> per layer, saved in the layer JSON (keys "chroma", "innerGlow"),
// packed into the uniform buffer. The uniform buffer grew from 9216 to 9600 floats (Vfx.uboFloats) for these blocks:
//   9216 + layer * 16   CHROMA     9216 .. 9375   (shader: chroma[160],  CA(l, i))   read by pass 35 (the FIRST enabled layer with it on is applied, like the Bevel)
//   9376 + layer * 16   INNER GLOW 9376 .. 9535   (shader: inglow[160],  IG(l, i))   read inside the grade (pass 0), section 8d
//   9536 .. 9599                   free headroom (shader: _tail[64])
// Slot numbers MUST match the CA / IG numbers in aereality_core.comp and findChroma() in vulkan_processor.cpp.
// Old presets have none of the keys -> defaults (Chromatic Aberration OFF, Inner Edge Glow = the new look driven by the old Edge Darken sliders).
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

/// Real lens chromatic aberration (After Effects style): the colour spectrum is spread along the radius (or a fixed angle) with many wavelength samples
/// (smooth rainbow fringes instead of three hard copies), the shift grows towards the corners on a curve you can shape, and a second "depth" component
/// (longitudinal aberration) puts purple / green fringes on contrast edges, the way out-of-focus glass does.
class ChromaAb {
  static const int size = 16;
  static const int packBase = 9216; // + layer * 16
  static const int layers = 10;

  static const int on = 0, amount = 1, mode = 2, angle = 3, cx = 4, cy = 5, start = 6, curve = 7, smooth = 8, axial = 9, axialSize = 10,
      hiBias = 11, balance = 12, fringeSat = 13, mix = 14;
  static const List<String> modes = ['Radial (lens)', 'Linear (angle)'];

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[amount] = 0.35;
    f[mode] = 0.0;
    f[angle] = 0.0;
    f[cx] = 0.5;
    f[cy] = 0.5;
    f[start] = 0.10;
    f[curve] = 1.6;
    f[smooth] = 0.60;
    f[axial] = 0.25;
    f[axialSize] = 0.40;
    f[hiBias] = 0.25;
    f[balance] = 0.0;
    f[fringeSat] = 1.0;
    f[mix] = 1.0;
    return f;
  }

  static List<double> sanitize(List<double>? src) {
    final d = _fix(src, defaults());
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    d[amount] = _c(d[amount], 0.0, 1.0);
    d[mode] = d[mode] >= 0.5 ? 1.0 : 0.0;
    d[angle] = _c(d[angle], -360.0, 360.0);
    d[cx] = _c(d[cx], -0.5, 1.5);
    d[cy] = _c(d[cy], -0.5, 1.5);
    d[start] = _c(d[start], 0.0, 0.9);
    d[curve] = _c(d[curve], 0.4, 4.0);
    d[smooth] = _c(d[smooth], 0.0, 1.0);
    d[axial] = _c(d[axial], 0.0, 1.0);
    d[axialSize] = _c(d[axialSize], 0.0, 1.0);
    d[hiBias] = _c(d[hiBias], 0.0, 1.0);
    d[balance] = _c(d[balance], -1.0, 1.0);
    d[fringeSat] = _c(d[fringeSat], 0.0, 2.0);
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

/// Inner Edge Glow (replaces the old Edge Darken inner blur). It finds the line art (dark ink strokes), measures how close every fill pixel is to a line
/// and lays a smooth dark glow on the INSIDE of the shapes next to the line. The reach is short on purpose: it is an edge effect, not a vignette.
/// The two old sliders stay: Edge Darken (AdjustmentLayer.edgeDarken) = glow strength, Edge Darken Inner Blur (edgeDarkenBlur) = glow reach.
class InnerGlow {
  static const int size = 16;
  static const int packBase = 9376; // + layer * 16
  static const int layers = 10;

  static const int inkLevel = 0, inkSoft = 1, rolloff = 2, core = 3, colour = 4, multiply = 5, hiProtect = 6, opacity = 8;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[inkLevel] = 0.18;
    f[inkSoft] = 0.12;
    f[rolloff] = 1.7;
    f[core] = 0.35;
    f[colour] = 0x000000.toDouble();
    f[multiply] = 0.80;
    f[hiProtect] = 0.30;
    f[opacity] = 1.0;
    return f;
  }

  static List<double> sanitize(List<double>? src) {
    final d = _fix(src, defaults());
    d[inkLevel] = _c(d[inkLevel], 0.03, 0.55);
    d[inkSoft] = _c(d[inkSoft], 0.03, 0.40);
    d[rolloff] = _c(d[rolloff], 0.5, 4.0);
    d[core] = _c(d[core], 0.0, 1.0);
    d[colour] = _c(d[colour].roundToDouble(), 0.0, 16777215.0);
    d[multiply] = _c(d[multiply], 0.0, 1.0);
    d[hiProtect] = _c(d[hiProtect], 0.0, 1.0);
    d[opacity] = _c(d[opacity], 0.0, 1.0);
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
