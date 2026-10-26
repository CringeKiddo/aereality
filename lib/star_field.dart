// =============================================================================
// AEReality / Shaderly - PixelStarField (batch 7, main menu background)
//
//  * Stars are blocky squares snapped to a pixel grid (no circles, no blur, anti-aliasing off).
//  * Not coloured: white / cool grey only. "Slight glow" = a dimmer 3x3-cell square (and a small + cross on the big stars)
//    drawn around the star, still on the same pixel grid.
//  * Touch (and drag) pushes stars away from the finger; when the finger leaves, every star springs back to its home spot.
//    Several fingers work at once.
//  * One Ticker drives a ValueNotifier that only repaints the CustomPaint: no setState, no widget rebuilds. The Ticker comes
//    from SingleTickerProviderStateMixin, so it is muted automatically while another screen covers the menu.
// =============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class PixelStarField extends StatefulWidget {
  final Widget child;
  final int starCount;
  final double cell; // size of one pixel in logical px
  final double repelRadius;

  const PixelStarField({
    super.key,
    required this.child,
    this.starCount = 150,
    this.cell = 3.0,
    this.repelRadius = 120.0,
  });

  @override
  State<PixelStarField> createState() => _PixelStarFieldState();
}

class _PixelStarFieldState extends State<PixelStarField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final Map<int, Offset> _touches = <int, Offset>{};

  // per star (struct of arrays)
  late Float32List _hx, _hy; // home position in 0..1 of the field size
  late Float32List _ox, _oy, _vx, _vy; // offset from home in px + velocity
  late Float32List _phase, _speed;
  late Uint8List _size; // 1 = one cell, 2 = two cells, 3 = two cells + cross
  late Uint8List _bright; // 0..3

  Size _area = Size.zero;
  Duration _last = Duration.zero;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    final n = widget.starCount;
    final r = math.Random(20261025);
    _hx = Float32List(n);
    _hy = Float32List(n);
    _ox = Float32List(n);
    _oy = Float32List(n);
    _vx = Float32List(n);
    _vy = Float32List(n);
    _phase = Float32List(n);
    _speed = Float32List(n);
    _size = Uint8List(n);
    _bright = Uint8List(n);
    for (int i = 0; i < n; i++) {
      _hx[i] = r.nextDouble();
      _hy[i] = r.nextDouble();
      _phase[i] = r.nextDouble() * math.pi * 2;
      _speed[i] = 0.6 + r.nextDouble() * 1.6;
      final roll = r.nextDouble();
      _size[i] = roll < 0.62 ? 1 : (roll < 0.90 ? 2 : 3);
      _bright[i] = (r.nextDouble() * 3).floor() + 1;
    }
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    dt = math.min(dt, 0.033);
    _time += dt;
    final w = _area.width, h = _area.height;
    if (w > 0 && h > 0) {
      final R = widget.repelRadius;
      final R2 = R * R;
      final n = _hx.length;
      for (int i = 0; i < n; i++) {
        final px = _hx[i] * w + _ox[i];
        final py = _hy[i] * h + _oy[i];
        double fx = 0, fy = 0;
        for (final t in _touches.values) {
          final dx = px - t.dx, dy = py - t.dy;
          final d2 = dx * dx + dy * dy;
          if (d2 < R2) {
            final d = math.sqrt(d2) + 0.001;
            final k = 1.0 - d / R; // 1 at the finger, 0 at the edge
            final push = 2600.0 * k * k;
            fx += dx / d * push;
            fy += dy / d * push;
          }
        }
        // spring back to home + damping (critically-ish damped)
        fx += -_ox[i] * 38.0 - _vx[i] * 9.0;
        fy += -_oy[i] * 38.0 - _vy[i] * 9.0;
        _vx[i] += fx * dt;
        _vy[i] += fy * dt;
        _ox[i] += _vx[i] * dt;
        _oy[i] += _vy[i] * dt;
      }
    }
    _frame.value++;
  }

  void _down(PointerEvent e) => _touches[e.pointer] = e.localPosition;
  void _up(PointerEvent e) => _touches.remove(e.pointer);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, c) {
                _area = Size(c.maxWidth, c.maxHeight);
                return CustomPaint(
                  size: Size.infinite,
                  painter: _StarPainter(this, _frame),
                );
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final _PixelStarFieldState s;
  _StarPainter(this.s, ValueNotifier<int> repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = s.widget.cell;
    final star = Paint()..isAntiAlias = false;
    final glow = Paint()..isAntiAlias = false;
    final n = s._hx.length;
    for (int i = 0; i < n; i++) {
      final x = s._hx[i] * size.width + s._ox[i];
      final y = s._hy[i] * size.height + s._oy[i];
      if (x < -cell * 4 || y < -cell * 4 || x > size.width + cell * 4 || y > size.height + cell * 4) continue;
      // twinkle: stepped, so it flickers in pixel-art steps instead of fading smoothly
      final tw = (math.sin(s._time * s._speed[i] + s._phase[i]) * 0.5 + 0.5);
      final step = (tw * 3.999).floor(); // 0..3
      final level = (s._bright[i] + step).clamp(1, 6);
      final a = 0.16 + level * 0.13; // 0.29 .. 0.94
      final gx = (x / cell).floorToDouble() * cell;
      final gy = (y / cell).floorToDouble() * cell;
      final k = s._size[i] == 1 ? 1.0 : 2.0;
      // glow halo: same grid, dimmer, bigger
      glow.color = Color.fromRGBO(210, 222, 255, 0.045 + level * 0.012);
      canvas.drawRect(Rect.fromLTWH(gx - cell, gy - cell, cell * (k + 2), cell * (k + 2)), glow);
      if (s._size[i] == 3) {
        glow.color = Color.fromRGBO(230, 236, 255, 0.10 + level * 0.02);
        canvas.drawRect(Rect.fromLTWH(gx - cell * 2, gy + cell * 0.5, cell * 6, cell), glow);
        canvas.drawRect(Rect.fromLTWH(gx + cell * 0.5, gy - cell * 2, cell, cell * 6), glow);
      }
      star.color = Color.fromRGBO(244, 247, 255, a);
      canvas.drawRect(Rect.fromLTWH(gx, gy, cell * k, cell * k), star);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => false; // driven by the repaint notifier
}
