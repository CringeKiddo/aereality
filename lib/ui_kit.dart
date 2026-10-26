// =============================================================================
// AEReality / Shaderly - UI kit (batch 7)
//
// Styling only. Genshin is the reference for STRUCTURE (shelves, plates, bevelled corners, diamond ornaments, grouped
// tabs); every colour comes from the app's own palette (kCyanAccent via gCustomAccentColor, kBackgroundDark, kSurfaceDark,
// kCardDark, kBorderDark).
//
//   ShelfPanel      grouped panel with a title plate (main menu, settings)
//   ShelfHeader     section title used by the editor tabs (replaces the grey 10 pt labels)
//   ShelfTabBar     the 14 editor tabs in 4 shelves, driven by the SAME TabController (indices unchanged)
//   shelfSliderTheme / ShelfSliderTrackShape / DiamondThumbShape    slider look used by SmoothSliderRow
//   SlideInTilt     slide + slight tilt + fade entrance (never blocks touches)
//   GlowFrame       slightly glowing edge that follows the accent (timeline preview box)
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'accent_state.dart';
import 'constants.dart';

// -----------------------------------------------------------------------------
// Curves / timing
// -----------------------------------------------------------------------------
/// Fast start, long soft landing (the "good speed curve" for every entrance).
const Curve kShelfCurve = Cubic(0.16, 0.84, 0.24, 1.0);

// -----------------------------------------------------------------------------
// SlideInTilt
// -----------------------------------------------------------------------------
class _EnterStagger {
  static Duration? _frame;
  static int _n = 0;

  /// How many entrances were already requested in the current frame (0, 1, 2 ...), capped so long lists do not crawl.
  static int next() {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_frame != now) {
      _frame = now;
      _n = 0;
    }
    return math.min(_n++, 9);
  }
}

/// Slides the child up from [dy] px with a small tilt and a fade, once, when it first appears. It only draws with a
/// Transform, so hit-testing follows the child and a slider can be dragged while it is still arriving. After the
/// entrance the wrapper hands the child back untouched.
class SlideInTilt extends StatefulWidget {
  final Widget child;
  final int? index; // null = auto stagger by build order in the same frame
  final double dy;
  final double tilt; // radians at the start
  final Duration duration;

  const SlideInTilt({
    super.key,
    required this.child,
    this.index,
    this.dy = 22,
    this.tilt = 0.035,
    this.duration = const Duration(milliseconds: 460),
  });

  @override
  State<SlideInTilt> createState() => _SlideInTiltState();
}

class _SlideInTiltState extends State<SlideInTilt> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _t = CurvedAnimation(parent: _c, curve: kShelfCurve);
    final i = widget.index ?? _EnterStagger.next();
    Future<void>.delayed(Duration(milliseconds: 34 * i), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        if (_c.isCompleted) return child!;
        final v = _t.value; // 0 -> 1
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.identity()
              ..translate(0.0, widget.dy * (1.0 - v))
              ..rotateZ(widget.tilt * (1.0 - v)),
            child: child,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Bevelled plate shapes
// -----------------------------------------------------------------------------
ShapeBorder shelfShape({double cut = 9, Color? edge, double width = 1}) {
  return BeveledRectangleBorder(
    borderRadius: BorderRadius.circular(cut),
    side: BorderSide(color: edge ?? kBorderDark, width: width),
  );
}

/// Small diamond ornament.
class DiamondDot extends StatelessWidget {
  final double size;
  final Color color;
  const DiamondDot({super.key, this.size = 7, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(width: size, height: size, color: color),
    );
  }
}

// -----------------------------------------------------------------------------
// ShelfHeader  (section title inside a tab)
// -----------------------------------------------------------------------------
class ShelfHeader extends StatelessWidget {
  final String text;
  const ShelfHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: gCustomAccentColor,
      builder: (context, accent, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
          child: Row(
            children: [
              DiamondDot(size: 6, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [accent.withOpacity(0.35), Colors.white.withOpacity(0.0)]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// ShelfPanel
// -----------------------------------------------------------------------------
class ShelfPanel extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final int? enterIndex; // slide-in stagger index, null = no entrance animation
  final bool fill; // true: panel takes all the height it is given and the child gets the rest (use inside Expanded)

  const ShelfPanel({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
    this.enterIndex,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final panel = ValueListenableBuilder<Color>(
      valueListenable: gCustomAccentColor,
      builder: (context, accent, _) {
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: kSurfaceDark.withOpacity(0.92),
            shape: shelfShape(edge: Colors.white.withOpacity(0.07), cut: 10),
            shadows: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 10, 0),
                  child: Row(
                    children: [
                      if (icon != null) ...[Icon(icon, size: 15, color: accent), const SizedBox(width: 8)] else ...[DiamondDot(size: 7, color: accent), const SizedBox(width: 9)],
                      Text(title!, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 1.2,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: [accent.withOpacity(0.55), accent.withOpacity(0.0)])),
                        ),
                      ),
                      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                    ],
                  ),
                ),
              if (fill) Expanded(child: Padding(padding: padding, child: child)) else Padding(padding: padding, child: child),
            ],
          ),
        );
      },
    );
    return enterIndex == null ? panel : SlideInTilt(index: enterIndex, child: panel);
  }
}

// -----------------------------------------------------------------------------
// GlowFrame  (preview box edge)
// -----------------------------------------------------------------------------
/// Draws a slightly glowing accent edge around [child] OUTSIDE the child's own clip. It is its own DecoratedBox layer and
/// listens to the accent, so it follows the colour changer live (and the gradient blend, and colour off).
class GlowFrame extends StatelessWidget {
  final Widget child;
  final double radius;
  const GlowFrame({super.key, required this.child, this.radius = 3});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gAccentListenable,
      child: child,
      builder: (context, child) {
        final cols = accentColors();
        final a = cols.first;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            // glow (outside the box)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(color: a.withOpacity(0.38), blurRadius: 12, spreadRadius: 0.5),
                      if (cols.last != a) BoxShadow(color: cols.last.withOpacity(0.22), blurRadius: 18, spreadRadius: 1.5),
                    ],
                  ),
                ),
              ),
            ),
            child!,
            // crisp 1 px edge on top of the picture
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: a.withOpacity(0.75), width: 1.0),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// ShelfTabBar : the same tabs (15 since batch 12 C3), 4 shelves
//
// Controller index map (UNCHANGED, identical to the old TabBar order):
//   0 PRESETS  1 TONEMAPPERS  2 GRADIENT MAP  3 LUT  4 BASIC  5 COLORISTA  6 MAGIC  7 COPIED STUFF
//   8 GLOW / FLARE  9 ATMOSPHERE  10 CURVES  11 TEXT  12 VFX  13 SAPPHIRE  14 TIME SLICE (added in batch 12 C3, appended so no old index moved)
// Shelves only decide which tabs are shown together.
// -----------------------------------------------------------------------------
class _TabDef {
  final int index;
  final String label;
  const _TabDef(this.index, this.label);
}

class _ShelfDef {
  final String name;
  final IconData icon;
  final List<_TabDef> tabs;
  const _ShelfDef(this.name, this.icon, this.tabs);
}

const List<_ShelfDef> _kShelves = <_ShelfDef>[
  _ShelfDef('LOOK', Icons.palette_outlined, <_TabDef>[_TabDef(0, 'PRESETS'), _TabDef(1, 'TONEMAPPERS'), _TabDef(2, 'GRADIENT MAP'), _TabDef(3, 'LUT')]),
  _ShelfDef('TONE', Icons.tune_rounded, <_TabDef>[_TabDef(4, 'BASIC'), _TabDef(5, 'COLORISTA'), _TabDef(10, 'CURVES'), _TabDef(6, 'MAGIC')]),
  _ShelfDef('FX', Icons.auto_awesome_rounded, <_TabDef>[
    _TabDef(8, 'GLOW / FLARE'),
    _TabDef(9, 'ATMOSPHERE'),
    _TabDef(7, 'COPIED STUFF'),
    _TabDef(12, 'VFX'),
    _TabDef(13, 'SAPPHIRE'),
    _TabDef(14, 'TIME SLICE'),
  ]),
  _ShelfDef('TEXT', Icons.title_rounded, <_TabDef>[_TabDef(11, 'TEXT')]),
];

class ShelfTabBar extends StatefulWidget {
  final TabController controller;
  const ShelfTabBar({super.key, required this.controller});

  @override
  State<ShelfTabBar> createState() => _ShelfTabBarState();
}

class _ShelfTabBarState extends State<ShelfTabBar> {
  final Map<int, int> _lastInShelf = {}; // shelf -> last tab opened inside it
  final ScrollController _scroll = ScrollController();

  int _shelfOf(int tab) {
    for (int i = 0; i < _kShelves.length; i++) {
      if (_kShelves[i].tabs.any((t) => t.index == tab)) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTab);
  }

  @override
  void didUpdateWidget(covariant ShelfTabBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTab);
      widget.controller.addListener(_onTab);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTab);
    _scroll.dispose();
    super.dispose();
  }

  void _onTab() {
    if (!mounted) return;
    final t = widget.controller.index;
    _lastInShelf[_shelfOf(t)] = t;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gAccentListenable,
      builder: (context, _) {
        final accent = gCustomAccentColor.value;
        final cur = widget.controller.index;
        final shelf = _shelfOf(cur);
        final def = _kShelves[shelf];
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F14),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- shelf row
              Row(
                children: [
                  for (int i = 0; i < _kShelves.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == shelf) return;
                          final target = _lastInShelf[i] ?? _kShelves[i].tabs.first.index;
                          widget.controller.animateTo(target);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: kShelfCurve,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: ShapeDecoration(
                            color: i == shelf ? accent.withOpacity(0.14) : Colors.white.withOpacity(0.03),
                            shape: shelfShape(cut: 6, edge: i == shelf ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_kShelves[i].icon, size: 13, color: i == shelf ? accent : Colors.white38),
                              const SizedBox(width: 5),
                              Text(
                                _kShelves[i].name,
                                style: TextStyle(
                                  color: i == shelf ? accent : Colors.white38,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              // ---- tabs of the open shelf
              SizedBox(
                height: 28,
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: def.tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, k) {
                    final t = def.tabs[k];
                    final sel = t.index == cur;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.controller.animateTo(t.index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: kShelfCurve,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: sel ? accentGradient() : null,
                          color: sel ? null : Colors.white.withOpacity(0.04),
                        ),
                        child: Text(
                          t.label,
                          style: TextStyle(
                            color: sel ? Colors.black : Colors.white54,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Slider look
// -----------------------------------------------------------------------------
/// Thin groove with end gems and quarter ticks; the filled part uses the accent gradient when it is on.
class ShelfSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const ShelfSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final Rect track = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme, isEnabled: isEnabled, isDiscrete: isDiscrete);
    final Canvas canvas = context.canvas;
    final double cy = track.center.dy;
    final double h = 3.0;
    final RRect groove = RRect.fromLTRBR(track.left, cy - h / 2, track.right, cy + h / 2, const Radius.circular(2));
    canvas.drawRRect(groove, Paint()..color = Colors.white.withOpacity(0.10));

    // filled part
    final cols = accentColors();
    final RRect fill = RRect.fromLTRBR(track.left, cy - h / 2, thumbCenter.dx, cy + h / 2, const Radius.circular(2));
    final Paint fp = Paint();
    if (cols.first != cols.last) {
      fp.shader = LinearGradient(colors: cols).createShader(Rect.fromLTRB(track.left, cy - 2, math.max(thumbCenter.dx, track.left + 1), cy + 2));
    } else {
      fp.color = cols.first;
    }
    canvas.drawRRect(fill, fp);
    // soft light on the fill
    canvas.drawRRect(
      RRect.fromLTRBR(track.left, cy - h / 2 - 1.5, thumbCenter.dx, cy + h / 2 + 1.5, const Radius.circular(3)),
      Paint()
        ..color = cols.first.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // quarter ticks
    final tick = Paint()
      ..color = Colors.white.withOpacity(0.16)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = track.left + track.width * i / 4;
      canvas.drawLine(Offset(x, cy - 5), Offset(x, cy + 5), tick);
    }
    // end gems
    for (final x in [track.left, track.right]) {
      _gem(canvas, Offset(x, cy), 3.2, x <= thumbCenter.dx ? cols.first : Colors.white.withOpacity(0.28));
    }
  }

  static void _gem(Canvas c, Offset p, double r, Color col) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..lineTo(p.dx + r, p.dy)
      ..lineTo(p.dx, p.dy + r)
      ..lineTo(p.dx - r, p.dy)
      ..close();
    c.drawPath(path, Paint()..color = col);
  }
}

/// Diamond handle with a light core and an accent halo.
class DiamondThumbShape extends SliderComponentShape {
  final double radius;
  const DiamondThumbShape({this.radius = 9});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(radius + 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas c = context.canvas;
    final cols = accentColors();
    final double grow = 1.0 + 0.18 * activationAnimation.value; // swells slightly while dragging
    final double r = radius * grow;

    Path diamond(double rr) => Path()
      ..moveTo(center.dx, center.dy - rr)
      ..lineTo(center.dx + rr * 0.78, center.dy)
      ..lineTo(center.dx, center.dy + rr)
      ..lineTo(center.dx - rr * 0.78, center.dy)
      ..close();

    // halo
    c.drawPath(
      diamond(r + 2),
      Paint()
        ..color = cols.first.withOpacity(0.30 + 0.25 * activationAnimation.value)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // body
    final body = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cols.last, cols.first]).createShader(Rect.fromCircle(center: center, radius: r));
    c.drawPath(diamond(r), body);
    // rim
    c.drawPath(
      diamond(r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withOpacity(0.9),
    );
    // core
    c.drawPath(diamond(r * 0.38), Paint()..color = Colors.white.withOpacity(0.95));
  }
}

SliderThemeData shelfSliderTheme(BuildContext context) {
  final accent = gCustomAccentColor.value;
  return SliderTheme.of(context).copyWith(
    trackHeight: 3,
    trackShape: const ShelfSliderTrackShape(),
    thumbShape: const DiamondThumbShape(radius: 8),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    overlayColor: accent.withOpacity(0.12),
    activeTrackColor: accent,
    inactiveTrackColor: Colors.white12,
    thumbColor: accent,
  );
}
