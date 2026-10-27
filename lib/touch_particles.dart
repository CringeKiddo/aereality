// =============================================================================
// AEReality / Shaderly - TouchParticlesWrapper (batch 8: no setState per tick)
//
// Same look and behaviour as before (sparkle colours, spawn rule, per-frame motion, fade-out). What changed is HOW it
// animates, using the same pattern as PixelStarField (star_field.dart):
//   * one Ticker (from SingleTickerProviderStateMixin, so it is muted automatically while another screen covers this one),
//   * a ValueNotifier<int> that only repaints the CustomPaint (CustomPainter(repaint: ...)): no setState, no widget rebuilds,
//   * a RepaintBoundary around the paint layer, so a sparkle frame never repaints the screen underneath it
//     (and never touches the star field's own layer: the two animate independently),
//   * the Ticker only runs while particles exist (it stops itself when the last one has faded; the next touch restarts it).
//
// Motion is still ONE step per frame (x += vx, opacity -= 0.045), exactly like the old AnimationController listener.
// Colour off (gColourOff) is still read at spawn time and gives the neutral grey-white sparkles.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'accent_state.dart';

class TouchParticlesWrapper extends StatefulWidget {
  final Widget child;

  const TouchParticlesWrapper({Key? key, required this.child}) : super(key: key);

  @override
  State<TouchParticlesWrapper> createState() => _TouchParticlesWrapperState();
}

class _Particle {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double opacity;
  Color color;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.opacity,
    required this.color,
  });
}

class _TouchParticlesWrapperState extends State<TouchParticlesWrapper> with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick); // not started: it only runs while there are particles
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  static const int _maxParticles = 40; // each one is a blurred draw: unbounded drags made the UI thread stall on weaker phones

  void _spawnParticles(Offset pos) {
    if (_particles.length >= _maxParticles) return;
    // Cyan + Lavender particles
    final colors = gColourOff.value
        ? const [Color(0xFFFFFFFF), Color(0xFFD5D8E0), Color(0xFFB8BCC8), Color(0xFFE8EAF0)] // colour off: neutral
        : const [
            Color(0xFF00E5FF),
            Color(0xFFE6E6FA),
            Color(0xFF80D8FF),
            Color(0xFFD1C4E9),
          ];

    for (int i = 0; i < 4; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = _random.nextDouble() * 2.2 + 0.8;
      _particles.add(
        _Particle(
          x: pos.dx,
          y: pos.dy,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          radius: _random.nextDouble() * 2.5 + 1.2,
          opacity: 0.85,
          color: colors[_random.nextInt(colors.length)],
        ),
      );
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (_particles.isEmpty) {
      _ticker.stop();
      return;
    }
    for (int i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.opacity -= 0.045;
      if (p.opacity <= 0.0) {
        _particles.removeAt(i);
      }
    }
    _frame.value++; // repaint the sparkle layer only
    if (_particles.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _spawnParticles(e.position),
      onPointerMove: (e) => _spawnParticles(e.position),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ParticlePainter(particles: _particles, repaint: _frame),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  _ParticlePainter({required this.particles, required Listenable repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity(p.opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 0.8);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, paint);
    }
  }

  // The list is shared with the state and mutated in place; repaints come from the `repaint` notifier.
  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => oldDelegate.particles != particles;
}
