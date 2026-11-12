// =============================================================================
// AEReality / Shaderly - Batch 19: LOOKS tab, EDGE FX tab and the EFFECT REGION handle
//
//  * LOOKS tab:  Effect Region switch + sliders, Looks Diffusion (lens-filter looks), Glimmer Glass, Film Damage.
//  * EDGE FX tab: border effects on the rectangular edges of the picture (water, audio visualizer, glossy leaves, blood mist, LED lights, pyro aura,
//                 anemo vortex, red / black glitch), each with its own settings and a good starting point when the mode is picked.
//  * EffectRegionGizmo: the handle drawn over the preview. Drag the centre dot to move the region, drag the right-hand dot to make it larger / smaller
//                 (or pinch). It writes Place.cx / cy / zoom of the selected layer; the shader limits that layer's VFX, diffusion, Looks and Edge FX to it.
// Batch 20: CHROMATIC ABERRATION section (real lens fringing with depth) at the end of the LOOKS tab; its settings are AdjustmentLayer.chroma (lens_slots.dart).
// Settings are flat lists in AdjustmentLayer.looks / edgeFx / place (looks_edge_slots.dart), saved by the layer JSON.
// =============================================================================

import 'package:flutter/material.dart';

import 'constants.dart';
import 'lens_slots.dart';
import 'looks_edge_slots.dart';
import 'models.dart';
import 'vfx_suite.dart';

class LooksEdgeSuite {
  static Widget _view(List<Widget> children) => ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), children: children);

  // ---------------------------------------------------------------------------
  // EFFECT REGION controls (shown in both tabs)
  // ---------------------------------------------------------------------------
  static List<Widget> _regionSection(BuildContext c, AdjustmentLayer cur, bool isBaseLayer, VoidCallback onChanged, VoidCallback onEnded) {
    final p = cur.place;
    if (isBaseLayer) {
      return [VfxSuite.header('EFFECT REGION'), VfxSuite.note('Select a layer above the base layer to limit its effects to a part of the picture.')];
    }
    final out = <Widget>[
      VfxSuite.header('EFFECT REGION  (move / zoom this layer\'s effects)'),
      VfxSuite.toggleRow(p, 'Limit this layer\'s effects to a region', Place.on, onChanged, onEnded),
    ];
    if (p[Place.on] > 0.5) {
      out.addAll([
        VfxSuite.chipsRow(p, 'Shape', Place.shape, const ['Ellipse', 'Rectangle'], onChanged, onEnded),
        VfxSuite.sliderRow(c, p, Place.cx, 'Centre X', -0.25, 1.25, onChanged, onEnded),
        VfxSuite.sliderRow(c, p, Place.cy, 'Centre Y', -0.25, 1.25, onChanged, onEnded),
        VfxSuite.sliderRow(c, p, Place.zoom, 'Size (zoom)', 0.1, 3.0, onChanged, onEnded),
        VfxSuite.sliderRow(c, p, Place.feather, 'Edge softness', 0.02, 1.0, onChanged, onEnded),
        VfxSuite.note('Drag the dot in the middle of the picture to move the region, the dot on its right edge (or pinch) to resize it. Applies to this layer\'s VFX, '
            'Optical Diffusion, Looks and Edge FX (the glow / flare family still covers the whole picture).'),
      ]);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // CHROMATIC ABERRATION (batch 20)
  // ---------------------------------------------------------------------------
  static List<Widget> _chromaSection(BuildContext c, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    final ca = cur.chroma;
    Widget s(int slot, String title, double min, double max) => VfxSuite.sliderRow(c, ca, slot, title, min, max, onChanged, onEnded);
    final out = <Widget>[
      VfxSuite.header('CHROMATIC ABERRATION  (lens fringes with depth)'),
      VfxSuite.toggleRow(ca, 'Chromatic Aberration', ChromaAb.on, onChanged, onEnded),
    ];
    if (ca[ChromaAb.on] > 0.5) {
      final bool linear = ca[ChromaAb.mode] >= 0.5;
      out.addAll([
        VfxSuite.chipsRow(ca, 'Mode', ChromaAb.mode, ChromaAb.modes, onChanged, onEnded),
        s(ChromaAb.amount, 'Amount (spread of the colours)', 0.0, 1.0),
        if (linear) s(ChromaAb.angle, 'Angle', -180.0, 180.0),
        if (!linear) ...[
          s(ChromaAb.start, 'Clear centre (where the fringes begin)', 0.0, 0.9),
          s(ChromaAb.curve, 'Depth curve (low = even, high = only the corners)', 0.4, 4.0),
          s(ChromaAb.cx, 'Centre X', -0.25, 1.25),
          s(ChromaAb.cy, 'Centre Y', -0.25, 1.25),
        ],
        s(ChromaAb.smooth, 'Smoothness (more wavelength samples = smoother rainbow)', 0.0, 1.0),
        s(ChromaAb.balance, 'Red / blue balance (-1 blue moves more, +1 red moves more)', -1.0, 1.0),
        s(ChromaAb.axial, 'Depth fringe (purple / green halos on contrast edges)', 0.0, 1.0),
        s(ChromaAb.axialSize, 'Depth fringe size', 0.0, 1.0),
        s(ChromaAb.hiBias, 'Favour bright edges', 0.0, 1.0),
        s(ChromaAb.fringeSat, 'Fringe saturation', 0.0, 2.0),
        s(ChromaAb.mix, 'Mix', 0.0, 1.0),
        VfxSuite.note('Applied after the whole grade (flares, glows, bevel) and before the dither. If several layers have it on, the first one is used. '
            'The Effect Region of the layer limits where it acts.'),
      ]);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // LOOKS TAB
  // ---------------------------------------------------------------------------
  static Widget buildLooksTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required bool isBaseLayer,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final l = cur.looks;
    Widget s(int slot, String title, double min, double max) => VfxSuite.sliderRow(context, l, slot, title, min, max, onChanged, onEnded);
    final w = <Widget>[
      ..._regionSection(context, cur, isBaseLayer, onChanged, onEnded),
      VfxSuite.header('LOOKS DIFFUSION  (lens filter looks)'),
      VfxSuite.toggleRow(l, 'Looks Diffusion', Looks.ldOn, onChanged, onEnded),
    ];
    if (l[Looks.ldOn] > 0.5) {
      w.addAll([
        VfxSuite.chipsRow(l, 'Look', Looks.ldType, Looks.ldTypes, onChanged, onEnded),
        s(Looks.ldStrength, 'Strength', 0.0, 1.0),
        s(Looks.ldRadius, 'Radius (tight to wide)', 0.0, 1.0),
        s(Looks.ldHiBias, 'Highlight bias (0 = whole frame)', 0.0, 1.0),
        s(Looks.ldHalation, 'Halation (warm halo)', 0.0, 1.0),
        s(Looks.ldContrast, 'Contrast softening', 0.0, 1.0),
        VfxSuite.note('Black Pro-Mist: highlights bloom, shadows stay deep. White Pro-Mist: milky veil, lifted shadows. Soft FX: softens detail. '
            'Hollywood Black Magic: Black Pro-Mist with a warm halo. Classic Soft: soft copy over a sharp core.'),
      ]);
    }
    w.addAll([
      VfxSuite.header('GLIMMER GLASS  (soft halo + star glints on the highlights)'),
      VfxSuite.toggleRow(l, 'Glimmer Glass', Looks.gcOn, onChanged, onEnded),
    ]);
    if (l[Looks.gcOn] > 0.5) {
      w.addAll([
        s(Looks.gcSparkle, 'Glint strength', 0.0, 1.0),
        s(Looks.gcSize, 'Glint size', 0.0, 1.0),
        s(Looks.gcDensity, 'Glint density', 0.0, 1.0),
        s(Looks.gcThreshold, 'Highlight threshold', 0.0, 1.5),
        s(Looks.gcGlow, 'Halo', 0.0, 1.0),
        s(Looks.gcTwinkle, 'Twinkle', 0.0, 1.0),
        s(Looks.gcRays, 'Rays (2 = 4-point, 3 = 6-point, 4 = 8-point)', 2.0, 4.0),
        VfxSuite.chipsRow(l, 'Glint colour', Looks.gcColor, Looks.gcColors, onChanged, onEnded),
        s(Looks.gcSeed, 'Pattern seed', 0.0, 50.0),
      ]);
    }
    w.addAll([
      VfxSuite.header('FILM DAMAGE'),
      VfxSuite.toggleRow(l, 'Film Damage', Looks.fdOn, onChanged, onEnded),
    ]);
    if (l[Looks.fdOn] > 0.5) {
      w.addAll([
        s(Looks.fdFps, 'Damage rate (frames per second, low = "on twos")', 2.0, 30.0),
        s(Looks.fdGrain, 'Grain', 0.0, 1.0),
        s(Looks.fdGrainSize, 'Grain size', 0.0, 1.0),
        s(Looks.fdScratches, 'Scratches', 0.0, 1.0),
        s(Looks.fdDust, 'Dust', 0.0, 1.0),
        s(Looks.fdHair, 'Hairs', 0.0, 1.0),
        s(Looks.fdFlicker, 'Flicker', 0.0, 1.0),
        s(Looks.fdWeave, 'Gate weave', 0.0, 1.0),
        s(Looks.fdBlotch, 'Stains / blotches', 0.0, 1.0),
        s(Looks.fdBurn, 'Burnt edges', 0.0, 1.0),
        s(Looks.fdTint, 'Sepia tint', 0.0, 1.0),
        s(Looks.fdSeed, 'Pattern seed', 0.0, 50.0),
      ]);
    }
    w.addAll(_chromaSection(context, cur, onChanged, onEnded));
    w.addAll([
      VfxSuite.header('ALL LOOKS'),
      s(Looks.opacity, 'Looks opacity', 0.0, 1.0),
    ]);
    return _view(w);
  }

  // ---------------------------------------------------------------------------
  // EDGE FX TAB
  // ---------------------------------------------------------------------------
  static Widget buildEdgeTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required bool isBaseLayer,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final l = cur.edgeFx;
    Widget s(int slot, String title, double min, double max) => VfxSuite.sliderRow(context, l, slot, title, min, max, onChanged, onEnded);
    final int mode = l[EdgeFx.mode].round().clamp(0, EdgeFx.modes.length - 1);
    final accent = gCustomAccentColor.value;
    final w = <Widget>[
      VfxSuite.header('EDGE FX  (effects on the rectangular edges of the picture)'),
      VfxSuite.toggleRow(l, 'Edge FX', EdgeFx.on, onChanged, onEnded),
    ];
    if (l[EdgeFx.on] > 0.5) {
      w.add(Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Mode', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            for (int i = 0; i < EdgeFx.modes.length; i++)
              ChoiceChip(
                label: Text(EdgeFx.modes[i]),
                selected: mode == i,
                selectedColor: accent,
                labelStyle: TextStyle(color: mode == i ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                onSelected: (sel) {
                  if (sel && mode != i) {
                    EdgeFx.modeDefaults(l, i); // a good starting point for the picked mode
                    onChanged();
                    onEnded();
                  }
                },
              ),
          ],
        ),
      ));
      w.add(VfxSuite.header(EdgeFx.modes[mode].toUpperCase()));
      final info = EdgeFx.paramInfo[mode];
      for (int k = 0; k < info.length; k++) {
        final pi = info[k];
        if (pi != null) w.add(s(EdgeFx.p(k), pi.$1, pi.$2, pi.$3));
      }
      w.addAll([
        VfxSuite.header('SHAPE & TIMING'),
        s(EdgeFx.width, 'Band width', 0.01, 0.6),
        s(EdgeFx.intensity, 'Intensity', 0.0, 3.0),
        s(EdgeFx.speed, 'Speed', 0.0, 4.0),
        s(EdgeFx.scale, 'Pattern size', 0.0, 1.0),
        s(EdgeFx.softness, 'Softness', 0.0, 1.0),
        s(EdgeFx.inset, 'Inset from the edge', 0.0, 0.3),
        s(EdgeFx.corner, 'Rounded corners', 0.0, 0.4),
        s(EdgeFx.seed, 'Pattern seed', 0.0, 50.0),
        s(EdgeFx.opacity, 'Opacity', 0.0, 1.0),
        VfxSuite.header('EDGES'),
        VfxSuite.toggleRow(l, 'Top', EdgeFx.sideTop, onChanged, onEnded),
        VfxSuite.toggleRow(l, 'Right', EdgeFx.sideRight, onChanged, onEnded),
        VfxSuite.toggleRow(l, 'Bottom', EdgeFx.sideBottom, onChanged, onEnded),
        VfxSuite.toggleRow(l, 'Left', EdgeFx.sideLeft, onChanged, onEnded),
        VfxSuite.header('COLOURS'),
        ...VfxSuite.colorSlot(context, l, EdgeFx.colorA, 'Colour A', onChanged, onEnded),
        ...VfxSuite.colorSlot(context, l, EdgeFx.colorB, 'Colour B', onChanged, onEnded),
        if (mode == 1) VfxSuite.note('The visualizer is animated from a built-in beat (BPM) and a procedural spectrum; it does not read the audio of the clip.'),
        if (mode == 6) VfxSuite.note('Anemo vortex: spiral wind ribbons that curl off the edge. Send a screenshot of the exact look you want and I can match it more closely.'),
      ]);
    }
    w.addAll(_regionSection(context, cur, isBaseLayer, onChanged, onEnded));
    return _view(w);
  }
}

// =============================================================================
// EffectRegionGizmo: the draggable handle over the preview
// =============================================================================
class EffectRegionGizmo extends StatefulWidget {
  final AdjustmentLayer layer;
  final VoidCallback onUpdated;
  final VoidCallback? onEnded;
  const EffectRegionGizmo({super.key, required this.layer, required this.onUpdated, this.onEnded});

  @override
  State<EffectRegionGizmo> createState() => _EffectRegionGizmoState();
}

class _EffectRegionGizmoState extends State<EffectRegionGizmo> {
  double _startZoom = 1.0;

  @override
  Widget build(BuildContext context) {
    final p = widget.layer.place;
    if (p[Place.on] < 0.5) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final double W = c.maxWidth, H = c.maxHeight;
      final accent = gCustomAccentColor.value;
      final double z = p[Place.zoom];
      final double cx = p[Place.cx] * W, cy = p[Place.cy] * H;
      final Rect rect = Rect.fromCenter(center: Offset(cx, cy), width: z * W, height: z * H);
      Widget dot(IconData icon) => Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: accent.withOpacity(0.85), shape: BoxShape.circle, border: Border.all(color: Colors.black54, width: 1.5)),
            child: Icon(icon, size: 18, color: Colors.black),
          );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _RegionPainter(rect, p[Place.shape] > 0.5, p[Place.feather], accent))),
          ),
          Positioned(
            left: cx - 24,
            top: cy - 24,
            width: 48,
            height: 48,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _startZoom = p[Place.zoom],
              onScaleUpdate: (d) {
                setState(() {
                  p[Place.cx] = (p[Place.cx] + d.focalPointDelta.dx / W).clamp(-0.25, 1.25).toDouble();
                  p[Place.cy] = (p[Place.cy] + d.focalPointDelta.dy / H).clamp(-0.25, 1.25).toDouble();
                  if (d.pointerCount > 1) p[Place.zoom] = (_startZoom * d.scale).clamp(0.1, 3.0).toDouble();
                });
                widget.onUpdated();
              },
              onScaleEnd: (_) => widget.onEnded?.call(),
              child: Center(child: dot(Icons.open_with_rounded)),
            ),
          ),
          Positioned(
            left: rect.right - 24,
            top: cy - 24,
            width: 48,
            height: 48,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) {
                setState(() => p[Place.zoom] = (p[Place.zoom] + d.delta.dx / (0.5 * W)).clamp(0.1, 3.0).toDouble());
                widget.onUpdated();
              },
              onPanEnd: (_) => widget.onEnded?.call(),
              child: Center(child: dot(Icons.zoom_out_map_rounded)),
            ),
          ),
        ],
      );
    });
  }
}

class _RegionPainter extends CustomPainter {
  final Rect rect;
  final bool box;
  final double feather;
  final Color accent;
  _RegionPainter(this.rect, this.box, this.feather, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent.withOpacity(0.9);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withOpacity(0.45);
    final Rect r2 = Rect.fromCenter(center: rect.center, width: rect.width * (1.0 - feather.clamp(0.02, 1.0)), height: rect.height * (1.0 - feather.clamp(0.02, 1.0)));
    if (box) {
      canvas.drawRect(rect, line);
      canvas.drawRect(r2, inner);
    } else {
      canvas.drawOval(rect, line);
      canvas.drawOval(r2, inner);
    }
  }

  @override
  bool shouldRepaint(covariant _RegionPainter old) => old.rect != rect || old.box != box || old.feather != feather || old.accent != accent;
}
