// =============================================================================
// AEReality / Shaderly - OdetteArt (batch 7)
//
// Decodes the Odette pixel data (odette_pixels.dart, 180 x 320 = 57,600 pixels taken from the reference image) once, and
// paints it as the export-screen background with a time of day:
//   u = 0   the picture exactly as in the reference
//   u -> 1  the sun goes down: the light warms, then turns dusk blue, the pixel sun sinks on the left (the reference is lit
//           from the left: the soft shadow sits on the right-hand wall), her shadow swings right and gets longer.
//
// It is a pure UI painter: it reads one number (export progress) and touches nothing in the export loop.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'odette_pixels.dart';

class OdetteArt {
  OdetteArt._(this.bg, this.fg, this.runs);

  /// Full picture (character included). The shadow is drawn on top of it, the cut-out character on top of the shadow.
  final ui.Image bg;

  /// Character only (alpha = silhouette mask).
  final ui.Image fg;

  /// Silhouette as row runs: flat list of (y, x0, x1) triples, x1 inclusive.
  final List<int> runs;

  static Future<OdetteArt>? _loading;
  static OdetteArt? cached;

  static Future<OdetteArt> load() => _loading ??= _decode().then((a) => cached = a);

  static Future<ui.Image> _toImage(Uint8List rgba) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, kOdetteW, kOdetteH, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  static Future<OdetteArt> _decode() async {
    const w = kOdetteW, h = kOdetteH;
    final pal = base64Decode(kOdettePalette);
    final idx = zlib.decode(base64Decode(kOdetteIndices));
    final bits = zlib.decode(base64Decode(kOdetteMask));
    final bgPx = Uint8List(w * h * 4);
    final fgPx = Uint8List(w * h * 4);
    final runs = <int>[];
    for (int y = 0; y < h; y++) {
      int runStart = -1;
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        final p = idx[i] * 3;
        final r = pal[p], g = pal[p + 1], b = pal[p + 2];
        final o = i * 4;
        bgPx[o] = r;
        bgPx[o + 1] = g;
        bgPx[o + 2] = b;
        bgPx[o + 3] = 255;
        final isChar = ((bits[i >> 3] >> (7 - (i & 7))) & 1) == 1;
        fgPx[o] = r;
        fgPx[o + 1] = g;
        fgPx[o + 2] = b;
        fgPx[o + 3] = isChar ? 255 : 0;
        if (isChar) {
          if (runStart < 0) runStart = x;
        } else if (runStart >= 0) {
          runs..add(y)..add(runStart)..add(x - 1);
          runStart = -1;
        }
      }
      if (runStart >= 0) runs..add(y)..add(runStart)..add(w - 1);
    }
    return OdetteArt._(await _toImage(bgPx), await _toImage(fgPx), runs);
  }

  /// Sun position as a function of export progress. Slow at first, quicker and quicker towards the end
  /// (closer to completion = the sun goes down faster).
  static double sunCurve(double p) {
    final t = p.clamp(0.0, 1.0);
    const a = 1.35;
    return (t + a * t * t * t) / (1.0 + a);
  }

  /// Clock-face time shown for a sun position (13:30 -> 19:45).
  static String timeLabel(double u) {
    final minutes = (13 * 60 + 30 + (6 * 60 + 15) * u.clamp(0.0, 1.0)).round();
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class OdettePainter extends CustomPainter {
  final OdetteArt? art;
  final double progress;
  OdettePainter(this.art, this.progress);

  static const _keyU = <double>[0.0, 0.45, 0.75, 0.92, 1.0];
  static const _keyR = <double>[1.00, 1.00, 0.92, 0.62, 0.40];
  static const _keyG = <double>[1.00, 0.90, 0.66, 0.50, 0.44];
  static const _keyB = <double>[1.00, 0.78, 0.62, 0.70, 0.72];

  static double _key(List<double> v, double u) {
    for (int i = 0; i < _keyU.length - 1; i++) {
      if (u <= _keyU[i + 1]) {
        final t = ((u - _keyU[i]) / (_keyU[i + 1] - _keyU[i])).clamp(0.0, 1.0);
        return v[i] + (v[i + 1] - v[i]) * t;
      }
    }
    return v.last;
  }

  static ColorFilter _grade(double r, double g, double b) =>
      ColorFilter.matrix(<double>[r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0]);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    final a = art;
    if (a == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF0B0B10));
      canvas.restore();
      return;
    }

    final u = OdetteArt.sunCurve(progress);
    final s = math.max(size.width / kOdetteW, size.height / kOdetteH);
    final imgW = kOdetteW * s, imgH = kOdetteH * s;
    final ox = (size.width - imgW) / 2;
    final oy = imgH > size.height ? -(imgH - size.height) * 0.14 : (size.height - imgH) / 2;
    final dst = Rect.fromLTWH(ox, oy, imgW, imgH);
    final src = Rect.fromLTWH(0, 0, kOdetteW.toDouble(), kOdetteH.toDouble());

    final mr = _key(_keyR, u), mg = _key(_keyG, u), mb = _key(_keyB, u);
    final bgPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false
      ..colorFilter = _grade(mr, mg, mb);
    final fgPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false
      ..colorFilter = _grade(math.min(1.0, mr * 1.05), math.min(1.0, mg * 1.04), math.min(1.0, mb * 1.03)); // she is the lit one

    // 1. picture
    canvas.drawImageRect(a.bg, src, dst, bgPaint);

    // 2. shadow of the silhouette (only visible beside her: the cut-out is drawn over it afterwards)
    final elev = (64.0 + (6.0 - 64.0) * u) * math.pi / 180.0;
    final len = (1.0 / math.tan(elev)).clamp(0.45, 7.0);
    final shiftX = len * 3.2; // art pixels to the right (light comes from the left)
    final shiftY = len * 0.9;
    final path = Path();
    final runs = a.runs;
    for (int i = 0; i < runs.length; i += 3) {
      final y = runs[i];
      final k = 0.55 + 0.45 * (y / kOdetteH); // lower parts throw further
      final sx = (shiftX * k).roundToDouble();
      final sy = shiftY.roundToDouble();
      path.addRect(Rect.fromLTWH(ox + (runs[i + 1] + sx) * s, oy + (y + sy) * s, (runs[i + 2] - runs[i + 1] + 1) * s, s + 0.6));
    }
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFF0B0716).withOpacity(0.20 + 0.30 * u),
    );

    // 3. her
    canvas.drawImageRect(a.fg, src, dst, fgPaint);

    // 4. sun light
    final sunX = size.width * (0.27 + (-0.03 - 0.27) * u * u);
    final sunY = size.height * (0.09 + (0.52 - 0.09) * math.pow(u, 1.5));
    final sunCol = Color.lerp(Color.lerp(const Color(0xFFFFF4D2), const Color(0xFFFF9A48), (u / 0.8).clamp(0.0, 1.0)), const Color(0xFFFF4F5E), ((u - 0.8) / 0.2).clamp(0.0, 1.0))!;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(Offset(sunX, sunY), size.width * 0.85, [sunCol.withOpacity(0.30 * (1.0 - 0.35 * u)), sunCol.withOpacity(0.0)]),
    );

    // 5. pixel sun (chunky squares on a 5 px grid)
    final cell = math.max(4.0, size.width / 72.0);
    final rad = 4.0 + 2.5 * u;
    final cx = (sunX / cell).roundToDouble(), cy = (sunY / cell).roundToDouble();
    final sp = Paint()..isAntiAlias = false;
    final ri = rad.ceil() + 2;
    for (int dy = -ri; dy <= ri; dy++) {
      for (int dx = -ri; dx <= ri; dx++) {
        final d = math.sqrt((dx * dx + dy * dy).toDouble());
        if (d <= rad) {
          sp.color = Color.lerp(sunCol, const Color(0xFFFFFFFF), d < rad * 0.45 ? 0.55 : 0.0)!;
        } else if (d <= rad + 1.2) {
          sp.color = sunCol.withOpacity(0.38);
        } else if (d <= rad + 2.4 && ((dx + dy) & 1) == 0) {
          sp.color = sunCol.withOpacity(0.16);
        } else {
          continue;
        }
        canvas.drawRect(Rect.fromLTWH((cx + dx) * cell, (cy + dy) * cell, cell, cell), sp);
      }
    }

    // 6. night: faint pixel stars come out near the end, a little cold tint
    if (u > 0.78) {
      final f = ((u - 0.78) / 0.22).clamp(0.0, 1.0);
      canvas.drawRect(rect, Paint()..color = const Color(0xFF10163A).withOpacity(0.20 * f));
      final r = math.Random(7);
      final sp2 = Paint()..isAntiAlias = false;
      for (int i = 0; i < 22; i++) {
        final x = (r.nextDouble() * size.width / cell).floorToDouble() * cell;
        final y = (r.nextDouble() * size.height * 0.34 / cell).floorToDouble() * cell;
        sp2.color = Colors.white.withOpacity((0.25 + r.nextDouble() * 0.6) * f);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), sp2);
      }
    }

    // 7. vignette
    canvas.drawRect(
      rect,
      Paint()..shader = ui.Gradient.radial(rect.center, size.longestSide * 0.72, [Colors.transparent, Colors.black.withOpacity(0.55)], [0.55, 1.0]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OdettePainter old) => old.art != art || old.progress != progress;
}
