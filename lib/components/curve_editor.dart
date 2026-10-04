import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants.dart';

const Color kAquamarine = Color(0xFF00E5FF);

/// 5-point tone curve editor.
///
/// Fixes vs the old version:
///  * Points can no longer cross each other (each point is clamped between its neighbours), so a curve
///    can never fold back / invert. The shader enforces the same rule as a safety net.
///  * Dragging is RELATIVE to where you grabbed the point (old version jumped the point to the finger),
///    and uses the editor's own local coordinates (old version measured against the whole row, so the
///    first touch could shift the point a long way = "tiny movement goes crazy").
///  * The preview uses the same monotone cubic (PCHIP) the shader uses, so what you see is what you get
///    (Catmull-Rom overshoots and shows curves the shader never renders).
///  * Double-tap resets the curve to a straight line.
class SplineCurveEditor extends StatefulWidget {
  final List<double> points;
  final Color curveColor;
  final ValueChanged<List<double>> onChanged;

  const SplineCurveEditor({
    super.key,
    required this.points,
    required this.curveColor,
    required this.onChanged,
  });

  @override
  State<SplineCurveEditor> createState() => _SplineCurveEditorState();
}

class _SplineCurveEditorState extends State<SplineCurveEditor> {
  int? _activePointIndex;
  double _grabTouchY = 0.0; // finger y (0..1, up = 1) when the drag started
  double _grabValue = 0.0; // point value when the drag started

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double size = math.min(constraints.maxWidth, 220.0);
        return Center(
          child: GestureDetector(
            onDoubleTap: () {
              final n = widget.points.length;
              widget.onChanged(List<double>.generate(n, (i) => i / (n - 1)));
            },
            onPanStart: (details) {
              // localPosition is relative to THIS box (size x size), not the whole row.
              final localPos = details.localPosition;
              final normX = (localPos.dx / size).clamp(0.0, 1.0);
              final normY = 1.0 - (localPos.dy / size).clamp(0.0, 1.0);

              int bestIdx = 0;
              double bestDist = 9999.0;
              for (int i = 0; i < widget.points.length; i++) {
                final px = i / (widget.points.length - 1);
                final py = widget.points[i];
                final d = math.sqrt((normX - px) * (normX - px) + (normY - py) * (normY - py));
                if (d < bestDist) {
                  bestDist = d;
                  bestIdx = i;
                }
              }
              if (bestDist < 0.25) {
                setState(() {
                  _activePointIndex = bestIdx;
                  _grabTouchY = normY;
                  _grabValue = widget.points[bestIdx];
                });
              }
            },
            onPanUpdate: (details) {
              final idx = _activePointIndex;
              if (idx == null) return;
              final normY = 1.0 - (details.localPosition.dy / size).clamp(0.0, 1.0);

              // relative drag: the point moves by how far the finger moved
              double v = _grabValue + (normY - _grabTouchY);

              // never cross a neighbour -> curve stays monotone (no inversion)
              final pts = widget.points;
              final double lo = idx > 0 ? pts[idx - 1] : 0.0;
              final double hi = idx < pts.length - 1 ? pts[idx + 1] : 1.0;
              v = v.clamp(lo, hi).clamp(0.0, 1.0).toDouble();

              final newPts = List<double>.from(pts);
              newPts[idx] = v;
              widget.onChanged(newPts);
            },
            onPanEnd: (_) => setState(() => _activePointIndex = null),
            onPanCancel: () => setState(() => _activePointIndex = null),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: CustomPaint(
                painter: _CurvePainter(
                  points: widget.points,
                  color: widget.curveColor,
                  activeIdx: _activePointIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  final int? activeIdx;

  _CurvePainter({required this.points, required this.color, this.activeIdx});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.0;

    for (int i = 1; i < 4; i++) {
      final x = size.width * (i / 4.0);
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final diagPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagPaint);

    final pts = _monotone(points);

    final path = Path();
    for (int px = 0; px <= size.width.toInt(); px++) {
      final normX = px / size.width;
      final normY = _evalPchip(normX, pts);
      final py = size.height - (normY * size.height);
      if (px == 0) {
        path.moveTo(0, py);
      } else {
        path.lineTo(px.toDouble(), py);
      }
    }

    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    for (int i = 0; i < pts.length; i++) {
      final cx = (i / (pts.length - 1)) * size.width;
      final cy = size.height - (pts[i] * size.height);
      final isAct = activeIdx == i;

      final dotPaint = Paint()
        ..color = isAct ? Colors.white : color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), isAct ? 6.0 : 4.0, dotPaint);

      final ringPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(cx, cy), isAct ? 6.0 : 4.0, ringPaint);
    }
  }

  /// Same guard the shader applies: points are non-decreasing and inside 0..1.
  static List<double> _monotone(List<double> src) {
    final out = List<double>.from(src);
    for (int i = 0; i < out.length; i++) {
      out[i] = out[i].clamp(0.0, 1.0).toDouble();
      if (i > 0 && out[i] < out[i - 1]) out[i] = out[i - 1];
    }
    return out;
  }

  /// Monotone cubic (PCHIP / Fritsch-Carlson). Line-for-line the same maths as evalCurve5 in the shader.
  double _evalPchip(double x, List<double> p) {
    x = x.clamp(0.0, 1.0).toDouble();
    final int n = p.length; // 5
    final int segs = n - 1;

    final d = List<double>.generate(segs, (i) => (p[i + 1] - p[i]) * segs);
    final m = List<double>.filled(n, 0.0);
    m[0] = d[0];
    m[n - 1] = d[segs - 1];
    for (int i = 1; i < n - 1; i++) {
      final prod = d[i - 1] * d[i];
      m[i] = prod <= 0.0 ? 0.0 : (2.0 * prod / (d[i - 1] + d[i]));
    }

    final double seg = x * segs;
    final int idx = math.min(seg.floor(), segs - 1);
    final double t = seg - idx;
    final double t2 = t * t;
    final double t3 = t2 * t;

    final double h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    final double h10 = t3 - 2.0 * t2 + t;
    final double h01 = -2.0 * t3 + 3.0 * t2;
    final double h11 = t3 - t2;

    final double k = 1.0 / segs;
    return (h00 * p[idx] + h10 * k * m[idx] + h01 * p[idx + 1] + h11 * k * m[idx + 1]).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}

class ColoristaWheel extends StatelessWidget {
  final String label;
  final double value;
  final Color accentColor;
  final ValueChanged<double> onChanged;

  const ColoristaWheel({
    super.key,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                accentColor.withOpacity(0.1),
                accentColor.withOpacity(0.6),
                accentColor.withOpacity(0.1),
              ],
            ),
            border: Border.all(color: Colors.white12),
          ),
          child: Center(
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        SizedBox(
          width: 84,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.2,
              activeTrackColor: kAquamarine,
              inactiveTrackColor: Colors.white12,
              thumbColor: kAquamarine,
            ),
            child: Slider(
              value: value.clamp(-0.3, 0.3),
              min: -0.3,
              max: 0.3,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// COLORISTA COLOUR WHEEL
// Drag the puck: angle = hue, distance from the centre = amount (centre = neutral).
// Double-tap resets. Output is a vector (x right, y up, length <= 1) which is exactly what the shader's
// wheelTint() expects, so the colour you see under the puck is the colour that gets pushed.
// =============================================================================
class ColorWheelPicker extends StatelessWidget {
  final String label;
  final double x;
  final double y;
  final double size;
  final void Function(double x, double y) onChanged;
  final VoidCallback? onEnded;

  const ColorWheelPicker({
    super.key,
    required this.label,
    required this.x,
    required this.y,
    required this.onChanged,
    this.onEnded,
    this.size = 128.0,
  });

  void _set(Offset p) {
    final c = size / 2.0;
    double dx = (p.dx - c) / c;
    double dy = -(p.dy - c) / c;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 1.0) {
      dx /= len;
      dy /= len;
    }
    onChanged(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    final amount = math.min(math.sqrt(x * x + y * y), 1.0);
    double hueDeg = math.atan2(y, x) * 180.0 / math.pi;
    if (hueDeg < 0) hueDeg += 360.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
        const SizedBox(height: 6),
        GestureDetector(
          onPanStart: (d) => _set(d.localPosition),
          onPanUpdate: (d) => _set(d.localPosition),
          onPanEnd: (_) => onEnded?.call(),
          onTapDown: (d) => _set(d.localPosition),
          onTapUp: (_) => onEnded?.call(),
          onDoubleTap: () {
            onChanged(0.0, 0.0);
            onEnded?.call();
          },
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _WheelPainter(x: x, y: y)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount < 0.005 ? 'neutral' : 'H ${hueDeg.toStringAsFixed(0)}\u00B0  \u2022  ${amount.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double x;
  final double y;
  _WheelPainter({required this.x, required this.y});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2.0;
    final center = Offset(r, r);
    final radius = r - 3.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Wheel angle runs counter-clockwise from the right (y up); SweepGradient runs clockwise on screen,
    // so the hue at gradient angle phi is hue(360 - phi).
    final colors = <Color>[];
    for (int i = 0; i <= 36; i++) {
      final phi = i * 10.0;
      final hue = (360.0 - phi) % 360.0;
      colors.add(HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor());
    }
    final sweep = Paint()..shader = SweepGradient(colors: colors, startAngle: 0.0, endAngle: 2 * math.pi).createShader(rect);
    canvas.drawCircle(center, radius, sweep);

    final fade = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF8A8A92), Color(0x008A8A92)],
        stops: [0.0, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, fade);

    canvas.drawCircle(center, radius, Paint()..color = Colors.black.withOpacity(0.28)..style = PaintingStyle.fill);
    canvas.drawCircle(center, radius, Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final cross = Paint()..color = Colors.white.withOpacity(0.16)..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), cross);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), cross);
    canvas.drawCircle(center, radius * 0.5, Paint()..color = Colors.white.withOpacity(0.10)..style = PaintingStyle.stroke..strokeWidth = 1.0);

    final puck = Offset(center.dx + x * radius, center.dy - y * radius);
    canvas.drawLine(center, puck, Paint()..color = Colors.white.withOpacity(0.35)..strokeWidth = 1.2);
    canvas.drawCircle(puck, 7.5, Paint()..color = Colors.black);
    canvas.drawCircle(puck, 6.0, Paint()..color = Colors.white);
    canvas.drawCircle(puck, 3.0, Paint()..color = Colors.black.withOpacity(0.85));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.x != x || old.y != y;
}

// =============================================================================
// HUE vs SATURATION / HUE / LUMINANCE BAND CURVE
// 8 points on the Oklab hue axis (the same axis and the same band centres the shader uses). Drag a point up /
// down; the line drawn is the shader's own interpolation (including the softness setting), so it is exact.
// =============================================================================
const List<double> kHueBandCenters = [29.0, 65.0, 110.0, 142.0, 195.0, 264.0, 305.0, 340.0];
const List<String> kHueBandNames = ['Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta'];

/// Oklch -> sRGB colour for drawing hue strips on the same axis as the shader.
Color oklchColor(double hDeg, {double l = 0.76, double c = 0.14}) {
  final h = hDeg * math.pi / 180.0;
  final a = c * math.cos(h);
  final b = c * math.sin(h);
  final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = l - 0.0894841775 * a - 1.2914855480 * b;
  final lc = l_ * l_ * l_;
  final mc = m_ * m_ * m_;
  final sc = s_ * s_ * s_;
  final r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc;
  final g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc;
  final bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc;
  double enc(double v) {
    v = v.clamp(0.0, 1.0).toDouble();
    return v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1.0 / 2.4).toDouble() - 0.055;
  }
  return Color.fromRGBO((enc(r) * 255).round(), (enc(g) * 255).round(), (enc(bl) * 255).round(), 1.0);
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0).toDouble();
  return t * t * (3.0 - 2.0 * t);
}

/// Mirror of the shader's band interpolation.
double hueBandValue(List<double> vals, double hDeg, double softness) {
  int i0 = 7;
  for (int b = 0; b < 8; b++) {
    if (hDeg >= kHueBandCenters[b]) i0 = b;
  }
  final i1 = (i0 + 1) & 7;
  double span = kHueBandCenters[i1] - kHueBandCenters[i0];
  if (span <= 0.0) span += 360.0;
  double dh = hDeg - kHueBandCenters[i0];
  if (dh < 0.0) dh += 360.0;
  double t = (dh / span).clamp(0.0, 1.0).toDouble();
  final edge = (1.0 - softness.clamp(0.0, 1.0).toDouble()) * 0.45;
  t = _smooth(edge, 1.0 - edge, t);
  return vals[i0] + (vals[i1] - vals[i0]) * t;
}

class HueBandEditor extends StatefulWidget {
  final List<double> values; // 8 values, -1..1
  final double softness;
  final Color accent;
  final VoidCallback onChanged;
  final VoidCallback? onEnded;

  const HueBandEditor({
    super.key,
    required this.values,
    required this.softness,
    required this.accent,
    required this.onChanged,
    this.onEnded,
  });

  @override
  State<HueBandEditor> createState() => _HueBandEditorState();
}

class _HueBandEditorState extends State<HueBandEditor> {
  int? _active;
  static const double _stripH = 18.0;
  static const double _height = 168.0;

  int _nearest(double dx, double w) {
    int best = 0;
    double bestD = 1e9;
    for (int i = 0; i < 8; i++) {
      final px = kHueBandCenters[i] / 360.0 * w;
      double d = (dx - px).abs();
      d = math.min(d, w - d);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _setValue(double dy) {
    final idx = _active;
    if (idx == null) return;
    final plotH = _height - _stripH;
    final v = (1.0 - 2.0 * (dy / plotH)).clamp(-1.0, 1.0).toDouble();
    widget.values[idx] = (v.abs() < 0.03) ? 0.0 : v; // snap to zero near the centre line
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        onPanStart: (d) {
          setState(() => _active = _nearest(d.localPosition.dx, w));
          _setValue(d.localPosition.dy);
        },
        onPanUpdate: (d) => _setValue(d.localPosition.dy),
        onPanEnd: (_) {
          setState(() => _active = null);
          widget.onEnded?.call();
        },
        onPanCancel: () => setState(() => _active = null),
        onTapDown: (d) {
          setState(() => _active = _nearest(d.localPosition.dx, w));
          _setValue(d.localPosition.dy);
        },
        onTapUp: (_) {
          setState(() => _active = null);
          widget.onEnded?.call();
        },
        onDoubleTap: () {
          for (int i = 0; i < 8; i++) {
            widget.values[i] = 0.0;
          }
          widget.onChanged();
          widget.onEnded?.call();
        },
        child: SizedBox(
          width: w,
          height: _height,
          child: CustomPaint(
            painter: _HueBandPainter(
              values: List<double>.from(widget.values),
              softness: widget.softness,
              accent: widget.accent,
              active: _active,
              stripH: _stripH,
            ),
          ),
        ),
      );
    });
  }
}

class _HueBandPainter extends CustomPainter {
  final List<double> values;
  final double softness;
  final Color accent;
  final int? active;
  final double stripH;

  _HueBandPainter({required this.values, required this.softness, required this.accent, required this.active, required this.stripH});

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - stripH;
    final bg = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, plotH), const Radius.circular(8));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFF0C0C10));
    canvas.drawRRect(bg, Paint()..color = Colors.white12..style = PaintingStyle.stroke..strokeWidth = 1.0);

    final grid = Paint()..color = Colors.white.withOpacity(0.06)..strokeWidth = 1.0;
    for (int i = 1; i < 4; i++) {
      final yy = plotH * i / 4.0;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), grid);
    }
    canvas.drawLine(Offset(0, plotH / 2), Offset(size.width, plotH / 2), Paint()..color = Colors.white24..strokeWidth = 1.2);

    // hue strip (same Oklab hue axis as the shader)
    final px = size.width.floor();
    for (int i = 0; i < px; i++) {
      final h = i / size.width * 360.0;
      canvas.drawRect(Rect.fromLTWH(i.toDouble(), plotH + 4, 1.5, stripH - 4), Paint()..color = oklchColor(h));
    }

    double yOf(double v) => plotH / 2 - v * (plotH / 2 - 6);

    final path = Path();
    for (int i = 0; i <= px; i++) {
      final h = (i / size.width * 360.0) % 360.0;
      final v = hueBandValue(values, h, softness);
      final yy = yOf(v);
      if (i == 0) {
        path.moveTo(0, yy);
      } else {
        path.lineTo(i.toDouble(), yy);
      }
    }
    canvas.drawPath(path, Paint()..color = accent..strokeWidth = 2.4..style = PaintingStyle.stroke);

    for (int i = 0; i < 8; i++) {
      final cx = kHueBandCenters[i] / 360.0 * size.width;
      final cy = yOf(values[i]);
      final isAct = active == i;
      canvas.drawLine(Offset(cx, plotH), Offset(cx, plotH + 4), Paint()..color = Colors.white54..strokeWidth = 1.0);
      canvas.drawCircle(Offset(cx, cy), isAct ? 8.0 : 6.0, Paint()..color = Colors.black);
      canvas.drawCircle(Offset(cx, cy), isAct ? 6.5 : 4.8, Paint()..color = oklchColor(kHueBandCenters[i], l: 0.82, c: 0.16));
      if (isAct) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${kHueBandNames[i]} ${values[i].toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final tx = (cx - tp.width / 2).clamp(2.0, size.width - tp.width - 2.0).toDouble();
        tp.paint(canvas, Offset(tx, cy < 24 ? cy + 12 : cy - 20));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HueBandPainter old) => true;
}
