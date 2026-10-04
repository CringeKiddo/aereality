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
