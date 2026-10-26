// =============================================================================
// AEReality / Shaderly - ExportClockPanel (batch 7)
//
// Replaces the progress bar of the export sheets. Pure visual: it receives the progress number the export already reports
// and draws it; it never calls into the export, never awaits it and costs nothing inside the encode loop.
//
//   * Odette background (OdetteArt) whose sun sets as the export advances (and sets faster towards the end).
//   * A clock face with an arrow. Arrow angle = progress * 360 degrees, starting at 12 o'clock, clockwise: linear, so the
//     arrow speed IS the export speed (it only eases the last few hundred ms between two reported values).
//   * The arrow tip is a blob of "paint"; the arc it leaves behind fills the groove. At 100 % the trail meets its start and
//     closes the circle.
//   * A small percentage in the middle.
//
// Repaint load: values closer than 0.2 % to the last drawn one are ignored, one RepaintBoundary, no blur on the background.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accent_state.dart';
import 'constants.dart';
import 'odette_art.dart';
import 'ui_kit.dart';

class ExportClockPanel extends StatefulWidget {
  final double progress; // 0..1 as reported by the export
  final String status;
  final double height;

  const ExportClockPanel({super.key, required this.progress, required this.status, this.height = 380});

  /// How long the sheets keep the finished (closed) clock on screen before closing. UI only: the file is already saved.
  static const int holdMs = 1100;
  static Future<void> holdFinished() => Future<void>.delayed(const Duration(milliseconds: holdMs));

  @override
  State<ExportClockPanel> createState() => _ExportClockPanelState();
}

class _ExportClockPanelState extends State<ExportClockPanel> {
  OdetteArt? _art = OdetteArt.cached;
  double _shown = 0.0;

  @override
  void initState() {
    super.initState();
    _shown = widget.progress.clamp(0.0, 1.0).toDouble();
    if (_art == null) {
      OdetteArt.load().then((a) {
        if (mounted) setState(() => _art = a);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExportClockPanel old) {
    super.didUpdateWidget(old);
    final p = widget.progress.clamp(0.0, 1.0).toDouble();
    if ((p - _shown).abs() >= 0.002 || p >= 1.0 || p <= 0.0) _shown = p;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gAccentListenable,
      builder: (context, _) {
        final cols = accentColors();
        return ClipPath(
          clipper: ShapeBorderClipper(shape: shelfShape(cut: 14)),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(color: kBackgroundDark, border: Border.all(color: Colors.white10)),
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _shown),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, p, _) {
                  final u = OdetteArt.sunCurve(p);
                  return LayoutBuilder(
                    builder: (context, c) {
                      final dial = math.min(math.min(c.maxWidth * 0.66, c.maxHeight * 0.74), 260.0);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: OdettePainter(_art, p)),
                          // time of day (follows the sun)
                          Positioned(
                            left: 12,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white12)),
                              child: Text(OdetteArt.timeLabel(u), style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                          ),
                          Align(
                            alignment: const Alignment(0, -0.12),
                            child: SizedBox(
                              width: dial,
                              height: dial,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(size: Size.square(dial), painter: _DialPainter(p, cols)),
                                  Align(
                                    alignment: const Alignment(0, 0.40),
                                    child: Text(
                                      p >= 0.995 ? '100%' : '${(p * 100).floor()}%',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: dial * 0.075 + 6,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                        shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: ShapeDecoration(color: Colors.black.withOpacity(0.55), shape: shelfShape(cut: 6, edge: Colors.white12)),
                              child: Text(widget.status, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  final double p;
  final List<Color> cols;
  _DialPainter(this.p, this.cols);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = math.min(size.width, size.height) / 2 - 3;
    final trackR = R * 0.72;
    final tw = R * 0.13; // groove / paint width
    final start = -math.pi / 2;

    // plate
    canvas.drawCircle(c, R, Paint()..color = kBackgroundDark.withOpacity(0.64));
    canvas.drawCircle(
      c,
      R,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withOpacity(0.28),
    );
    canvas.drawCircle(
      c,
      R * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.10),
    );

    // hour marks: 24, diamonds on the 12 even hours
    for (int i = 0; i < 24; i++) {
      final a = start + i * math.pi * 2 / 24;
      final d = Offset(math.cos(a), math.sin(a));
      if (i % 2 == 0) {
        final p0 = c + d * (R * 0.965);
        final r = i % 6 == 0 ? 4.6 : 3.0;
        final path = Path()
          ..moveTo(p0.dx + d.dx * r, p0.dy + d.dy * r)
          ..lineTo(p0.dx - d.dy * r * 0.7, p0.dy + d.dx * r * 0.7)
          ..lineTo(p0.dx - d.dx * r, p0.dy - d.dy * r)
          ..lineTo(p0.dx + d.dy * r * 0.7, p0.dy - d.dx * r * 0.7)
          ..close();
        canvas.drawPath(path, Paint()..color = (i % 6 == 0 ? cols.first : Colors.white).withOpacity(i % 6 == 0 ? 0.95 : 0.5));
      } else {
        canvas.drawLine(
          c + d * (R * 0.93),
          c + d * (R * 0.885),
          Paint()
            ..color = Colors.white.withOpacity(0.28)
            ..strokeWidth = 1,
        );
      }
    }

    // groove
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tw
      ..color = Colors.white.withOpacity(0.08);
    canvas.drawCircle(c, trackR, groove);
    canvas.drawCircle(
      c,
      trackR + tw / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.10),
    );
    canvas.drawCircle(
      c,
      trackR - tw / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.10),
    );

    // paint trail
    final sweep = p * math.pi * 2;
    final arcRect = Rect.fromCircle(center: c, radius: trackR);
    if (p > 0.0005) {
      final shader = SweepGradient(
        colors: [cols.first, cols.last, cols.first],
        stops: const [0.0, 0.5, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(arcRect);
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tw * 1.45
          ..strokeCap = StrokeCap.round
          ..color = cols.first.withOpacity(0.34)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tw
          ..strokeCap = p >= 0.995 ? StrokeCap.butt : StrokeCap.round
          ..shader = shader,
      );
      // wet highlight along the upper edge of the paint
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: trackR + tw * 0.22),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tw * 0.22
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.28),
      );
    }

    final done = p >= 0.995;
    if (done) {
      // the trail has come round and met its start: seal the seam
      canvas.drawCircle(
        c,
        trackR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tw
          ..shader = SweepGradient(colors: [cols.first, cols.last, cols.first], transform: const GradientRotation(-math.pi / 2)).createShader(arcRect),
      );
      canvas.drawCircle(
        c,
        trackR + tw * 0.9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withOpacity(0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // arrow
    final ang = start + sweep;
    final dir = Offset(math.cos(ang), math.sin(ang));
    final perp = Offset(-dir.dy, dir.dx);
    final tip = c + dir * trackR;
    final handEnd = c + dir * (trackR - tw * 0.2);
    canvas.drawLine(
      c + dir * (R * 0.12),
      handEnd,
      Paint()
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.92),
    );
    // arrow head, sitting on the paint blob
    final head = Path()
      ..moveTo((tip + dir * (tw * 0.95)).dx, (tip + dir * (tw * 0.95)).dy)
      ..lineTo((tip - dir * (tw * 0.1) + perp * (tw * 0.62)).dx, (tip - dir * (tw * 0.1) + perp * (tw * 0.62)).dy)
      ..lineTo((tip - dir * (tw * 0.1) - perp * (tw * 0.62)).dx, (tip - dir * (tw * 0.1) - perp * (tw * 0.62)).dy)
      ..close();
    // paint blob at the very tip: this is the paint that is laid down
    canvas.drawCircle(tip, tw * 1.05, Paint()..color = cols.first.withOpacity(0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(
      tip,
      tw * 0.78,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white, cols.first, cols.last], stops: const [0.0, 0.55, 1.0]).createShader(Rect.fromCircle(center: tip, radius: tw * 0.78)),
    );
    canvas.drawPath(head, Paint()..color = Colors.white.withOpacity(0.95));

    // hub
    canvas.drawCircle(c, R * 0.10, Paint()..color = kCardDark);
    canvas.drawCircle(
      c,
      R * 0.10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = cols.first,
    );
    final d = R * 0.045;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - d)
        ..lineTo(c.dx + d, c.dy)
        ..lineTo(c.dx, c.dy + d)
        ..lineTo(c.dx - d, c.dy)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) => old.p != p || old.cols.first != cols.first || old.cols.last != cols.last;
}
