// =============================================================================
// AEReality / Shaderly - Gradient Map data model
// Per-layer gradient map: settings, presets, GPU packing (48 floats) and a Dart-side sampler
// that mirrors the shader so the pixel previews in the UI match the render.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Order MUST match gradientMapField() in aereality_core.comp
enum GradientMapType {
  luma,
  linear,
  corner,
  radial,
  angular,
  edge,
  splitTone,
  posterized,
  checker,
  stripes,
  halftone,
  noise,
  lumaLinear,
}

const Map<GradientMapType, String> kGradientTypeNames = {
  GradientMapType.luma: 'LUMA',
  GradientMapType.linear: 'LINEAR',
  GradientMapType.corner: 'CORNER',
  GradientMapType.radial: 'RADIAL',
  GradientMapType.angular: 'ANGULAR',
  GradientMapType.edge: 'EDGE',
  GradientMapType.splitTone: 'SPLIT',
  GradientMapType.posterized: 'BANDS',
  GradientMapType.checker: 'CHECKER',
  GradientMapType.stripes: 'STRIPES',
  GradientMapType.halftone: 'DOTS',
  GradientMapType.noise: 'NOISE',
  GradientMapType.lumaLinear: 'LUMA+LIN',
};

const Map<GradientMapType, String> kGradientTypeHints = {
  GradientMapType.luma: 'Classic: dark to light picks the colour',
  GradientMapType.linear: 'Straight ramp across the frame (angle)',
  GradientMapType.corner: 'Top-right is colour A, bottom-left is colour B',
  GradientMapType.radial: 'Colour rings out from a centre point',
  GradientMapType.angular: 'Colour sweeps around a centre point',
  GradientMapType.edge: 'Colours only follow edges and outlines',
  GradientMapType.splitTone: 'Hard split: shadows one way, lights the other',
  GradientMapType.posterized: 'Luma snapped into flat colour bands',
  GradientMapType.checker: 'Checkerboard pattern mixed with luma',
  GradientMapType.stripes: 'Angled stripes mixed with luma',
  GradientMapType.halftone: 'Halftone dots driven by luma',
  GradientMapType.noise: 'Soft blocky noise mixed with luma',
  GradientMapType.lumaLinear: 'Half luma, half linear ramp',
};

/// Hard ceiling for the mix so a LUT applied afterwards never over-contrasts.
const double kGradientMaxStrength = 0.60;

class GradientStop {
  Color color;
  double pos;
  GradientStop(this.color, this.pos);

  GradientStop clone() => GradientStop(color, pos);
  Map<String, dynamic> toJson() => {'c': color.value & 0xFFFFFF, 'p': pos};
  factory GradientStop.fromJson(Map<String, dynamic> j) => GradientStop(
        Color(0xFF000000 | ((j['c'] as num?)?.toInt() ?? 0)),
        ((j['p'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      );
}

class GradientMapSettings {
  bool enabled;
  GradientMapType type;
  double strength; // 0..kGradientMaxStrength
  double angle; // degrees
  double scale; // 0.25..2.5
  double centerX;
  double centerY;
  bool invert;
  int bands; // 2..12
  double patternSize; // 0..1
  double edgeWidth; // 0..1 (edge width / split softness)
  double lumaKeep; // 0..1
  double curve; // 0.4..2.5
  double rangeLo;
  double rangeHi;
  List<GradientStop> stops;
  String presetName;

  GradientMapSettings({
    this.enabled = false,
    this.type = GradientMapType.luma,
    this.strength = 0.30,
    this.angle = 45.0,
    this.scale = 1.0,
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.invert = false,
    this.bands = 5,
    this.patternSize = 0.40,
    this.edgeWidth = 0.40,
    this.lumaKeep = 0.60,
    this.curve = 1.0,
    this.rangeLo = 0.0,
    this.rangeHi = 1.0,
    List<GradientStop>? stops,
    this.presetName = '',
  }) : stops = stops ??
            [
              GradientStop(const Color(0xFF0B2A33), 0.0),
              GradientStop(const Color(0xFF3E8E8F), 0.55),
              GradientStop(const Color(0xFFE6F2EF), 1.0),
            ];

  GradientMapSettings clone() => GradientMapSettings(
        enabled: enabled,
        type: type,
        strength: strength,
        angle: angle,
        scale: scale,
        centerX: centerX,
        centerY: centerY,
        invert: invert,
        bands: bands,
        patternSize: patternSize,
        edgeWidth: edgeWidth,
        lumaKeep: lumaKeep,
        curve: curve,
        rangeLo: rangeLo,
        rangeHi: rangeHi,
        stops: stops.map((s) => s.clone()).toList(),
        presetName: presetName,
      );

  void copyFrom(GradientMapSettings o) {
    enabled = o.enabled;
    type = o.type;
    strength = o.strength;
    angle = o.angle;
    scale = o.scale;
    centerX = o.centerX;
    centerY = o.centerY;
    invert = o.invert;
    bands = o.bands;
    patternSize = o.patternSize;
    edgeWidth = o.edgeWidth;
    lumaKeep = o.lumaKeep;
    curve = o.curve;
    rangeLo = o.rangeLo;
    rangeHi = o.rangeHi;
    stops = o.stops.map((s) => s.clone()).toList();
    presetName = o.presetName;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'type': type.index,
        'strength': strength,
        'angle': angle,
        'scale': scale,
        'centerX': centerX,
        'centerY': centerY,
        'invert': invert,
        'bands': bands,
        'patternSize': patternSize,
        'edgeWidth': edgeWidth,
        'lumaKeep': lumaKeep,
        'curve': curve,
        'rangeLo': rangeLo,
        'rangeHi': rangeHi,
        'stops': stops.map((s) => s.toJson()).toList(),
        'presetName': presetName,
      };

  factory GradientMapSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return GradientMapSettings();
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    final ti = (j['type'] as num?)?.toInt() ?? 0;
    final rawStops = j['stops'];
    List<GradientStop>? st;
    if (rawStops is List && rawStops.length >= 2) {
      st = rawStops.whereType<Map>().map((e) => GradientStop.fromJson(Map<String, dynamic>.from(e))).toList();
      if (st.length < 2) st = null;
    }
    return GradientMapSettings(
      enabled: j['enabled'] == true,
      type: GradientMapType.values[ti.clamp(0, GradientMapType.values.length - 1)],
      strength: d('strength', 0.30).clamp(0.0, kGradientMaxStrength),
      angle: d('angle', 45.0),
      scale: d('scale', 1.0),
      centerX: d('centerX', 0.5),
      centerY: d('centerY', 0.5),
      invert: j['invert'] == true,
      bands: ((j['bands'] as num?)?.toInt() ?? 5).clamp(2, 12),
      patternSize: d('patternSize', 0.40),
      edgeWidth: d('edgeWidth', 0.40),
      lumaKeep: d('lumaKeep', 0.60),
      curve: d('curve', 1.0),
      rangeLo: d('rangeLo', 0.0),
      rangeHi: d('rangeHi', 1.0),
      stops: st,
      presetName: (j['presetName'] as String?) ?? '',
    );
  }

  // ---------------------------------------------------------------------------
  // Stops
  // ---------------------------------------------------------------------------
  List<GradientStop> get sortedStops {
    final l = stops.map((s) => s).toList()..sort((a, b) => a.pos.compareTo(b.pos));
    return l;
  }

  /// Colour of the ramp at t (sRGB interpolation, mirrors gmapRamp in the shader).
  Color colorAt(double t) {
    final s = sortedStops;
    t = t.clamp(0.0, 1.0);
    if (t <= s.first.pos) return s.first.color;
    for (int i = 1; i < s.length; i++) {
      if (t <= s[i].pos) {
        final span = math.max(s[i].pos - s[i - 1].pos, 1e-4);
        return Color.lerp(s[i - 1].color, s[i].color, ((t - s[i - 1].pos) / span).clamp(0.0, 1.0))!;
      }
    }
    return s.last.color;
  }

  // ---------------------------------------------------------------------------
  // GPU packing: 48 floats, layout = struct GMapData in aereality_core.comp
  // ---------------------------------------------------------------------------
  static const int kFloatsPerLayer = 48;
  static const int kBaseOffset = 32 + 10 * 192; // 1952

  void packInto(List<double> u, int o) {
    final s = sortedStops;
    final n = math.min(s.length, 6);
    u[o + 0] = enabled ? 1.0 : 0.0;
    u[o + 1] = type.index.toDouble();
    u[o + 2] = strength.clamp(0.0, kGradientMaxStrength);
    u[o + 3] = angle * math.pi / 180.0;
    u[o + 4] = scale;
    u[o + 5] = centerX;
    u[o + 6] = centerY;
    u[o + 7] = invert ? 1.0 : 0.0;
    u[o + 8] = n.toDouble();
    u[o + 9] = bands.toDouble();
    u[o + 10] = patternSize;
    u[o + 11] = edgeWidth;
    u[o + 12] = lumaKeep;
    u[o + 13] = curve;
    u[o + 14] = rangeLo;
    u[o + 15] = math.max(rangeHi, rangeLo + 0.01);
    for (int k = 0; k < 6; k++) {
      final st = s[math.min(k, n - 1)];
      u[o + 16 + k] = (st.color.value & 0xFFFFFF).toDouble(); // exact in fp32 (24-bit integer)
      u[o + 22 + k] = k < n ? st.pos : 1.0;
    }
  }

  // ---------------------------------------------------------------------------
  // Preview sampler (mirrors gradientMapField for the pixel tiles)
  // ---------------------------------------------------------------------------
  /// Demo luma used by previews: a pixel-art style sky / sun / hills scene.
  static double demoLuma(double u, double v) {
    final sun = math.max(0.0, 1.0 - math.sqrt(math.pow(u - 0.72, 2) + math.pow((v - 0.28) * 1.2, 2)) * 5.5);
    final hill1 = v > 0.62 + 0.10 * math.sin(u * 6.0) ? 0.22 : 0.0;
    final hill2 = v > 0.78 + 0.06 * math.sin(u * 9.0 + 1.0) ? 0.12 : 0.0;
    final sky = 0.35 + 0.35 * (1.0 - v);
    return (hill2 > 0 ? 0.10 : (hill1 > 0 ? 0.20 : sky + sun * 0.6)).clamp(0.0, 1.0);
  }

  double _hash(double x, double y) {
    final s = math.sin(x * 127.1 + y * 311.7) * 43758.5453;
    return s - s.floorToDouble();
  }

  double fieldT(double u, double v, {double aspect = 1.6, int cells = 16}) {
    final luma = demoLuma(u, v);
    final px = u - 0.5, py = v - 0.5;
    double t = luma;
    final cx = (u * cells).floor(), cy = (v * cells).floor();
    switch (type) {
      case GradientMapType.luma:
        t = luma;
        break;
      case GradientMapType.linear:
      case GradientMapType.corner:
      case GradientMapType.lumaLinear:
        final la = type == GradientMapType.corner ? 2.3561945 : angle * math.pi / 180.0;
        final ldx = math.cos(la), ldy = math.sin(la);
        final lin = (px * ldx + py * ldy) / math.max(ldx.abs() + ldy.abs(), 1e-4) * scale + 0.5;
        t = type == GradientMapType.lumaLinear ? luma * 0.5 + lin.clamp(0.0, 1.0) * 0.5 : lin;
        break;
      case GradientMapType.radial:
        final rdx = (u - centerX) * aspect, rdy = v - centerY;
        t = math.sqrt(rdx * rdx + rdy * rdy) * scale * 1.4;
        break;
      case GradientMapType.angular:
        final adx = (u - centerX) * aspect, ady = v - centerY;
        final aa = math.atan2(ady, adx) / (2 * math.pi) + 0.5 + angle / 360.0;
        t = aa - aa.floorToDouble();
        break;
      case GradientMapType.edge:
        const e = 0.012;
        final gx = demoLuma(u + e, v) - demoLuma(u - e, v);
        final gy = demoLuma(u, v + e) - demoLuma(u, v - e);
        t = math.sqrt(gx * gx + gy * gy) * 9.0 * scale;
        break;
      case GradientMapType.splitTone:
        final soft = 0.03 + (0.5 - 0.03) * edgeWidth;
        final x = ((luma - (0.5 - soft)) / (2 * soft)).clamp(0.0, 1.0);
        t = x * x * (3 - 2 * x);
        break;
      case GradientMapType.posterized:
        final nb = math.max(bands, 2).toDouble();
        t = (luma.clamp(0.0, 0.999) * nb).floorToDouble() / (nb - 1.0);
        break;
      case GradientMapType.checker:
        t = luma * 0.7 + ((cx + cy) % 2) * 0.3;
        break;
      case GradientMapType.stripes:
        final sa = angle * math.pi / 180.0;
        final proj = (u * math.cos(sa) + v * math.sin(sa)) * cells * 0.8;
        final tri = ((proj - proj.floorToDouble()) * 2 - 1).abs();
        t = luma * 0.7 + tri * 0.3;
        break;
      case GradientMapType.halftone:
        final fx = u * cells - (u * cells).floorToDouble() - 0.5;
        final fy = v * cells - (v * cells).floorToDouble() - 0.5;
        final hd = math.sqrt(fx * fx + fy * fy) * 2.0;
        final dv = (hd - math.sqrt(luma) * 1.15) < 0 ? 1.0 : 0.0;
        t = luma * 0.4 + dv * 0.6;
        break;
      case GradientMapType.noise:
        t = luma * 0.6 + _hash(cx.toDouble(), cy.toDouble()) * 0.4;
        break;
    }
    if (invert) t = 1.0 - t;
    t = math.pow(t.clamp(0.0, 1.0), math.max(curve, 0.05)).toDouble();
    return ((t - rangeLo) / math.max(rangeHi - rangeLo, 1e-3)).clamp(0.0, 1.0);
  }
}

// =============================================================================
// PRESETS (low strength + luma keep by default so a LUT afterwards stays clean)
// =============================================================================
class GradientPreset {
  final String name;
  final GradientMapType type;
  final List<GradientStop> stops;
  final double strength;
  final double lumaKeep;
  final double angle;
  const GradientPreset(this.name, this.type, this.stops, {this.strength = 0.30, this.lumaKeep = 0.60, this.angle = 45});

  void applyTo(GradientMapSettings g) {
    g.enabled = true;
    g.type = type;
    g.stops = stops.map((s) => s.clone()).toList();
    g.strength = strength;
    g.lumaKeep = lumaKeep;
    g.angle = angle;
    g.presetName = name;
  }
}

Color _c(int rgb) => Color(0xFF000000 | rgb);

final List<GradientPreset> kGradientPresets = [
  GradientPreset('Desaturated Teal', GradientMapType.luma, [GradientStop(_c(0x0F2B30), 0.0), GradientStop(_c(0x4C8B8A), 0.55), GradientStop(_c(0xDDEBE6), 1.0)], strength: 0.28),
  GradientPreset('Warm Dusk', GradientMapType.luma, [GradientStop(_c(0x2A1A3A), 0.0), GradientStop(_c(0xC0603C), 0.6), GradientStop(_c(0xFFD9A8), 1.0)], strength: 0.30),
  GradientPreset('Cold Steel', GradientMapType.luma, [GradientStop(_c(0x10161F), 0.0), GradientStop(_c(0x5E7387), 0.5), GradientStop(_c(0xE3ECF4), 1.0)], strength: 0.30),
  GradientPreset('Sakura Haze', GradientMapType.luma, [GradientStop(_c(0x3A2233), 0.0), GradientStop(_c(0xE79AB3), 0.55), GradientStop(_c(0xFFF0F2), 1.0)], strength: 0.26),
  GradientPreset('Ash Orange', GradientMapType.luma, [GradientStop(_c(0x1B1B1F), 0.0), GradientStop(_c(0x8C6A55), 0.5), GradientStop(_c(0xFFB46B), 1.0)], strength: 0.30),
  GradientPreset('Moonlit Blue', GradientMapType.luma, [GradientStop(_c(0x070B1E), 0.0), GradientStop(_c(0x3B5BA5), 0.55), GradientStop(_c(0xCFE0FF), 1.0)], strength: 0.32),
  GradientPreset('Golden Hour', GradientMapType.luma, [GradientStop(_c(0x241A12), 0.0), GradientStop(_c(0xD08A3E), 0.6), GradientStop(_c(0xFFF3C9), 1.0)], strength: 0.28),
  GradientPreset('Teal & Orange', GradientMapType.splitTone, [GradientStop(_c(0x1A5F6B), 0.0), GradientStop(_c(0xF28C3C), 1.0)], strength: 0.24, lumaKeep: 0.8),
  GradientPreset('Sunset Corner', GradientMapType.corner, [GradientStop(_c(0xFF8A4C), 0.0), GradientStop(_c(0x7B5BD6), 0.5), GradientStop(_c(0x1D3C78), 1.0)], strength: 0.30, lumaKeep: 0.7),
  GradientPreset('Edge Glow Cyan', GradientMapType.edge, [GradientStop(_c(0x000000), 0.0), GradientStop(_c(0x00E5FF), 1.0)], strength: 0.45, lumaKeep: 0.2),
  GradientPreset('Pixel Bands', GradientMapType.posterized, [GradientStop(_c(0x1B1030), 0.0), GradientStop(_c(0x7A3E8E), 0.35), GradientStop(_c(0xE8789A), 0.7), GradientStop(_c(0xFFE7B0), 1.0)], strength: 0.30),
  GradientPreset('Mono Mint', GradientMapType.luma, [GradientStop(_c(0x0B1F1A), 0.0), GradientStop(_c(0x58B59A), 0.6), GradientStop(_c(0xEAFFF6), 1.0)], strength: 0.25),
];
