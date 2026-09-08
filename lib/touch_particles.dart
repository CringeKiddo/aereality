import 'dart:math' as math;
import 'package:flutter/material.dart';

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
  late AnimationController _ticker;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_updateParticles)
      ..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _spawnParticles(Offset pos) {
    // Cyan + Lavender particles
    final colors = [
      const Color(0xFF00E5FF),
      const Color(0xFFE6E6FA),
      const Color(0xFF80D8FF),
      const Color(0xFFD1C4E9),
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
  }

  void _updateParticles() {
    if (_particles.isEmpty) return;
    setState(() {
      for (int i = _particles.length - 1; i >= 0; i--) {
        final p = _particles[i];
        p.x += p.vx;
        p.y += p.vy;
        p.opacity -= 0.045;
        if (p.opacity <= 0.0) {
          _particles.removeAt(i);
        }
      }
    });
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
            child: CustomPaint(
              painter: _ParticlePainter(particles: _particles),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity(p.opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 0.8);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
