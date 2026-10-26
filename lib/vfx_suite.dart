// =============================================================================
// AEReality / Shaderly - Batch 6: VFX tab (bubbles / rain / particles) + SAPPHIRE tab (S_Glint, S_LightLeak, moved Sapphire effects)
// + (batch 12 step C3) TIME SLICE tab: buildTimeSliceTab, same helpers and look as the two tabs above
//
//  * Every slider goes through EditorViews.buildSliderRow -> SmoothSliderRow (batch 2): the handle is driven by the row's own
//    state, the model change + grade are scheduled through onChanged, so a heavy effect never blocks the handle.
//  * Everything is stored in AdjustmentLayer.vfx / AdjustmentLayer.sap (flat lists, see vfx_slots.dart) -> saved by the existing
//    layer JSON, so presets (.json only) carry it with no new file format.
//  * Mode chips call onChanged + onEnded; the caller's onEnded runs setState, which rebuilds this tab with only the settings
//    that belong to the selected mode.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'constants.dart';
import 'ui_kit.dart';
import 'editor_views.dart';
import 'models.dart';
import 'time_slice_slots.dart';
import 'vfx_slots.dart';

/// Writes the VFX and Sapphire blocks of one layer into the uniform array (floats 4096.. / 4736..).
extension LayerVfxPack on AdjustmentLayer {
  void packVfxInto(List<double> u, int layerIndex) {
    final vo = Vfx.packBase + layerIndex * Vfx.size;
    final so = Sap.packBase + layerIndex * Sap.size;
    if (layerIndex < 0 || u.length < so + Sap.size) return;
    for (int i = 0; i < Vfx.size; i++) {
      u[vo + i] = vfx[i];
    }
    for (int i = 0; i < Sap.size; i++) {
      u[so + i] = sap[i];
    }
  }
}

class VfxSuite {
  // ---------------------------------------------------------------------------
  // small UI helpers (the batch 4 helpers in EditorViews are private, so these are the same widgets for the new lists)
  // ---------------------------------------------------------------------------
  static Widget _hdr(String t) => ShelfHeader(t); // batch 7: shelf-style section title

  static Widget _note(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(t, style: const TextStyle(color: Colors.white24, fontSize: 10)),
      );

  static Widget _s(BuildContext c, List<double> l, int slot, String title, double min, double max, VoidCallback onChanged,
      VoidCallback onEnded) {
    return EditorViews.buildSliderRow(
      context: c,
      title: title,
      val: l[slot].clamp(min, max).toDouble(),
      min: min,
      max: max,
      onChanged: (v) {
        l[slot] = v;
        onChanged();
      },
      onEnded: onEnded,
    );
  }

  static Widget _chips(List<double> l, String label, int slot, List<String> names, VoidCallback onChanged, VoidCallback onEnded) {
    final accent = gCustomAccentColor.value;
    final cur = l[slot].round();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          for (int i = 0; i < names.length; i++)
            ChoiceChip(
              label: Text(names[i]),
              selected: cur == i,
              selectedColor: accent,
              labelStyle: TextStyle(color: cur == i ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              onSelected: (sel) {
                if (sel) {
                  l[slot] = i.toDouble();
                  onChanged();
                  onEnded();
                }
              },
            ),
        ],
      ),
    );
  }

  static Widget _toggle(List<double> l, String label, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SwitchListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        value: l[slot] > 0.5,
        onChanged: (v) {
          l[slot] = v ? 1.0 : 0.0;
          onChanged();
          onEnded();
        },
      ),
    );
  }

  // same order as LayerBlendMode / the shader's blend modes
  static const List<String> _blendLabels = [
    'Normal', 'Screen', 'Linear Add', 'Overlay', 'Soft Light', 'Multiply', 'Add', 'Linear Dodge',
    'Darken', 'Lighten', 'Color Dodge', 'Color Burn', 'Hard Light', 'Difference', 'Exclusion',
    'Hue', 'Saturation', 'Color', 'Luminosity', 'Linear Burn', 'Subtract',
  ];

  /// Custom blend INSIDE the effect (batch 4 pattern): 0 = the effect's own default compositing, n = LayerBlendMode index + 1.
  static Widget _blend(List<double> l, String label, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    final int v = l[slot].round().clamp(0, _blendLabels.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          DropdownButton<int>(
            value: v,
            dropdownColor: kCardDark,
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            items: [
              const DropdownMenuItem(value: 0, child: Text('Default')),
              for (int i = 0; i < _blendLabels.length; i++) DropdownMenuItem(value: i + 1, child: Text(_blendLabels[i])),
            ],
            onChanged: (m) {
              if (m != null) {
                l[slot] = m.toDouble();
                onChanged();
                onEnded();
              }
            },
          ),
        ],
      ),
    );
  }

  // colour in one float slot as 0xRRGGBB (exact in float32), edited with hue / saturation / brightness sliders
  static List<double> _hsv(double packed) {
    final v = packed.round();
    final r = ((v >> 16) & 255) / 255.0, g = ((v >> 8) & 255) / 255.0, b = (v & 255) / 255.0;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final d = mx - mn;
    double h = 0.0;
    if (d > 1e-6) {
      if (mx == r) {
        h = ((g - b) / d) % 6.0;
      } else if (mx == g) {
        h = (b - r) / d + 2.0;
      } else {
        h = (r - g) / d + 4.0;
      }
      h /= 6.0;
      if (h < 0) h += 1.0;
    }
    return [h, mx <= 0 ? 0.0 : d / mx, mx];
  }

  static double _pack(double h, double s, double v) {
    final c = v * s;
    final hh = (h.clamp(0.0, 1.0) * 6.0) % 6.0;
    final x = c * (1.0 - ((hh % 2.0) - 1.0).abs());
    final m = v - c;
    double r = 0, g = 0, b = 0;
    if (hh < 1) {
      r = c; g = x;
    } else if (hh < 2) {
      r = x; g = c;
    } else if (hh < 3) {
      g = c; b = x;
    } else if (hh < 4) {
      g = x; b = c;
    } else if (hh < 5) {
      r = x; b = c;
    } else {
      r = c; b = x;
    }
    final ri = ((r + m) * 255).round().clamp(0, 255);
    final gi = ((g + m) * 255).round().clamp(0, 255);
    final bi = ((b + m) * 255).round().clamp(0, 255);
    return ((ri << 16) | (gi << 8) | bi).toDouble();
  }

  /// Batch 14: public entry to the existing colour widget (swatch + Hue / Saturation / Brightness SmoothSliderRows, packed 0xRRGGBB in a float slot),
  /// used by the 4-Way Gradient rows in the Magic tab (editor_views.dart).
  static List<Widget> colorSlot(BuildContext c, List<double> l, int slot, String label, VoidCallback onChanged, VoidCallback onEnded) =>
      _color(c, l, slot, label, onChanged, onEnded);

  static List<Widget> _color(BuildContext c, List<double> l, int slot, String label, VoidCallback onChanged, VoidCallback onEnded) {
    final hsv = _hsv(l[slot]);
    final v = l[slot].round();
    final swatch = Color.fromARGB(255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    Widget row(String t, int idx) => EditorViews.buildSliderRow(
          context: c,
          title: '$label $t',
          val: hsv[idx],
          min: 0.0,
          max: 1.0,
          onChanged: (x) {
            final n = _hsv(l[slot]);
            n[idx] = x;
            l[slot] = _pack(n[0], n[1], n[2]);
            onChanged();
          },
          onEnded: onEnded,
        );
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
      row('Hue', 0),
      row('Saturation', 1),
      row('Brightness', 2),
    ];
  }

  // ===========================================================================
  // VFX TAB
  // ===========================================================================
  static Widget buildVfxTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final l = cur.vfx;
    final int mode = l[Vfx.mode].round().clamp(0, 3);
    final bool bubble = mode == Vfx.modeBubble, rain = mode == Vfx.modeRain, part = mode == Vfx.modeParticle;
    Widget s(int slot, String title, double min, double max) => _s(context, l, slot, title, min, max, onChanged, onEnded);

    final children = <Widget>[
      _hdr('VFX  -  BUBBLES / RAIN / PARTICLES'),
      _chips(l, 'Mode', Vfx.mode, const ['Off', 'Bubbles', 'Rain', 'Particles'], onChanged, onEnded),
    ];

    if (mode == Vfx.modeOff) {
      children.add(_note('Pick a mode. Each mode only shows the settings that belong to it; shared settings are always there.'));
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), children: children);
    }

    // ---- motion ----
    children.add(_hdr('MOTION'));
    children.add(s(Vfx.speed, 'Speed (0 = frozen)', 0.0, 1.0));
    children.add(s(Vfx.progression, 'Progression (scrub the animation by hand)', 0.0, 1.0));
    if (rain) {
      children.add(s(Vfx.rainAngle, 'Fall Angle (deg, 270 = straight down, 0 = right)', 0.0, 360.0));
      children.add(s(Vfx.speedVar, 'Speed Variation (each streak falls at its own speed)', 0.0, 1.0));
    } else {
      children.add(s(Vfx.angle, 'Angle (deg, 90 = up, 0 = right)', 0.0, 360.0));
      children.add(s(Vfx.wander, 'Wander (how much each one circles around)', 0.0, 1.0));
    }
    children.add(_chips(l, 'Direction', Vfx.direction, rain ? const ['Forward', 'Reverse', 'Hold'] : const ['Forward', 'Reverse', 'Orbit in place'],
        onChanged, onEnded));
    children.add(_chips(l, 'Axis', Vfx.axis, const ['Free', 'Horizontal only', 'Vertical only'], onChanged, onEnded));

    // ---- size / amount ----
    children.add(_hdr('SIZE & AMOUNT'));
    children.add(s(Vfx.scale, rain ? 'Drop Size' : 'Scale / Size', 0.0, 1.0));
    children.add(s(Vfx.scaleVar, 'Size Variation', 0.0, 1.0));
    children.add(s(Vfx.density, 'Amount / Density', 0.0, 1.0));
    children.add(s(Vfx.seed, 'Random Seed (new layout)', 0.0, 100.0));

    // ---- shape ----
    children.add(_hdr('EDGE'));
    children.add(s(Vfx.hardness, 'Hardness (soft -> crisp edge)', 0.0, 1.0));
    children.add(s(Vfx.roughness, 'Roughness (wobbly outline)', 0.0, 1.0));

    // ---- mode specific ----
    if (bubble) {
      children.add(_hdr('GLASS BUBBLE'));
      children.add(s(Vfx.refraction, 'Refraction (magnify / bend the picture)', 0.0, 1.0));
      children.add(s(Vfx.dispersion, 'Colour Split (edge dispersion)', 0.0, 1.0));
      children.add(s(Vfx.rim, 'Rim Light', 0.0, 1.5));
      children.add(s(Vfx.specular, 'Specular Highlight', 0.0, 1.5));
      children.add(s(Vfx.innerLight, 'Inner Light', 0.0, 1.0));
      children.add(s(Vfx.defocus, 'Far Bubbles Defocus', 0.0, 1.0));
    } else if (rain) {
      children.add(_hdr('RAIN'));
      children.add(s(Vfx.streak, 'Streak Length', 0.0, 1.0));
      children.add(s(Vfx.rainBright, 'Streak Brightness', 0.0, 2.0));
      children.add(s(Vfx.refraction, 'Refraction (lens in each drop)', 0.0, 1.0));
      children.add(s(Vfx.depth, 'Depth (far layers dimmer + softer)', 0.0, 1.0));
    } else {
      children.add(_hdr('PARTICLES'));
      children.add(_chips(l, 'Colour Source', Vfx.colorSrc, const ['Fixed colour', 'From video', 'Colour x video light'], onChanged, onEnded));
      if (l[Vfx.colorSrc].round() != 1) {
        children.addAll(_color(context, l, Vfx.partColor, 'Particle Colour', onChanged, onEnded));
      }
      children.add(s(Vfx.partBright, 'Particle Brightness', 0.0, 3.0));
      children.add(s(Vfx.reactSize, 'React To Video (size + visibility)', 0.0, 1.0));
      children.add(_toggle(l, 'React To Dark Areas Instead Of Bright', Vfx.reactInvert, onChanged, onEnded));
      children.add(s(Vfx.reactThr, 'React Threshold', 0.0, 1.0));
      children.add(s(Vfx.twinkle, 'Twinkle', 0.0, 1.0));
    }

    // ---- light & shadow ----
    children.add(_hdr('SHADOW & SOFT GLOW'));
    children.add(s(Vfx.shadow, 'Shadow', 0.0, 1.5));
    children.add(s(Vfx.shadowDist, 'Shadow Distance', 0.0, 1.0));
    children.add(s(Vfx.shadowAngle, 'Shadow Angle (deg, also moves the light)', 0.0, 360.0));
    children.add(s(Vfx.glow, 'Soft Glow', 0.0, 2.0));
    children.add(s(Vfx.glowRadius, 'Soft Glow Radius', 0.0, 1.0));
    if (!part) {
      children.addAll(_color(context, l, Vfx.tint, 'Tint', onChanged, onEnded));
      children.add(s(Vfx.tintAmt, 'Tint Amount', 0.0, 1.0));
    }

    // ---- media interaction ----
    children.add(_hdr('HOW IT WORKS WITH YOUR MEDIA'));
    children.add(_chips(l, 'Show On', Vfx.maskMode, const ['Everywhere', 'Bright areas', 'Dark areas'], onChanged, onEnded));
    if (l[Vfx.maskMode].round() != 0) {
      children.add(s(Vfx.maskThr, 'Brightness Threshold', 0.0, 1.0));
      children.add(s(Vfx.maskSoft, 'Threshold Softness', 0.0, 1.0));
    }
    if (!part) children.add(s(Vfx.pickup, 'Pick Up Scene Colour (highlights take the scene hue)', 0.0, 1.0));

    // ---- composite ----
    children.add(_hdr('COMPOSITE'));
    children.add(s(Vfx.opacity, 'VFX Opacity', 0.0, 1.0));
    children.add(_blend(l, 'VFX Blend', Vfx.blend, onChanged, onEnded));

    // ---- performance (nothing is reduced silently: this tells you exactly what the slider does) ----
    final q = l[Vfx.smoothness];
    final depthLayers = 1 + (q > 0.34 ? 1 : 0) + (q > 0.67 ? 1 : 0);
    final perCell = q > 0.5 ? 2 : 1;
    children.add(_hdr('SMOOTHNESS / PERFORMANCE'));
    children.add(s(Vfx.smoothness, 'Smoothness (lower = faster preview)', 0.0, 1.0));
    children.add(_note('Now: $depthLayers depth layer${depthLayers > 1 ? 's' : ''}, up to $perCell shape${perCell > 1 ? 's' : ''} per cell'
        '${bubble ? (q > 0.5 ? ', colour split on' : ', colour split off, single refraction tap') : ''}. '
        'If the preview lags on a heavy clip, lower this first.'));

    return ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), children: children);
  }

  // ===========================================================================
  // SAPPHIRE TAB
  // ===========================================================================
  static Widget buildSapphireTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final l = cur.sap;
    Widget s(int slot, String title, double min, double max) => _s(context, l, slot, title, min, max, onChanged, onEnded);
    final glintOn = l[Sap.gOn] > 0.5;
    final leakOn = l[Sap.lOn] > 0.5;
    final q = l[Sap.gQuality];

    final children = <Widget>[
      _hdr('S_GLINT  (STAR RAYS ON BRIGHT POINTS)'),
      _toggle(l, 'S_Glint On', Sap.gOn, onChanged, onEnded),
    ];
    if (glintOn) {
      children.addAll([
        s(Sap.gIntensity, 'Glint Intensity', 0.0, 3.0),
        s(Sap.gThreshold, 'Glint Threshold (brightness where a pixel starts to glint)', 0.0, 0.99),
        s(Sap.gDensity, 'Glints Per Frame (density)', 0.0, 1.0),
        s(Sap.gSize, 'Glint Size', 0.0, 1.0),
        s(Sap.gRays, 'Ray Count (1 - 12)', 1.0, 12.0),
        s(Sap.gLength, 'Ray Length', 0.0, 1.0),
        s(Sap.gLenVar, 'Ray Length Randomness', 0.0, 1.0),
        s(Sap.gFalloff, 'Ray Falloff', 0.0, 1.0),
        s(Sap.gWidth, 'Ray Width (needs Quality > 0.85)', 0.0, 1.0),
        s(Sap.gRotate, 'Rotate / Angle (deg)', 0.0, 180.0),
        s(Sap.gShimmer, 'Shimmer (animated twinkle)', 0.0, 1.0),
        s(Sap.gSeed, 'Random Seed', 0.0, 100.0),
        _hdr('S_GLINT COLOUR & CORE'),
        ..._color(context, l, Sap.gColor, 'Ray Colour', onChanged, onEnded),
        s(Sap.gColorMix, 'Ray Colour Mix (0 = highlight colour, 1 = Ray Colour)', 0.0, 1.0),
        s(Sap.gRainbow, 'Rainbow Rays', 0.0, 1.0),
        s(Sap.gCore, 'Hot-Spot Core', 0.0, 2.0),
        s(Sap.gCoreSize, 'Hot-Spot Core Size', 0.0, 1.0),
        _hdr('S_GLINT COMPOSITE'),
        s(Sap.gOpacity, 'Glint Opacity (blend with original)', 0.0, 1.0),
        _blend(l, 'Glint Blend', Sap.gBlend, onChanged, onEnded),
        s(Sap.gQuality, 'Glint Quality (lower = faster)', 0.0, 1.0),
        _note('Now: ${(8 + 14 * q).round()} samples per ray${q > 0.85 ? ', 3-tap ray width on' : ', ray width off'}. '
            'More rays or longer rays cost more. S_Glint uses the first enabled layer that has it on.'),
      ]);
    }

    children.add(_hdr('S_LIGHT LEAK'));
    children.add(_toggle(l, 'S_Light Leak On', Sap.lOn, onChanged, onEnded));
    if (leakOn) {
      children.addAll([
        s(Sap.lIntensity, 'Leak Intensity', 0.0, 3.0),
        s(Sap.lAngle, 'Direction / Angle (deg, 0 = enters from the left)', 0.0, 360.0),
        s(Sap.lLength, 'Length', 0.0, 1.0),
        s(Sap.lStart, 'Position Start', 0.0, 1.0),
        s(Sap.lEnd, 'Position End', 0.0, 1.0),
        s(Sap.lFalloff, 'Falloff', 0.0, 1.0),
        s(Sap.lSoft, 'Softness', 0.0, 1.0),
        s(Sap.lWidth, 'Band Width (across the leak)', 0.0, 1.0),
        s(Sap.lStreaks, 'Streaks', 0.0, 1.0),
        _toggle(l, 'Mirror Leak From The Opposite Side', Sap.lMirror, onChanged, onEnded),
        _hdr('S_LIGHT LEAK COLOUR'),
        _toggle(l, 'Colour Gradient Along The Leak', Sap.lGradient, onChanged, onEnded),
        ..._color(context, l, Sap.lColorA, l[Sap.lGradient] > 0.5 ? 'Start Colour' : 'Colour', onChanged, onEnded),
        if (l[Sap.lGradient] > 0.5) ..._color(context, l, Sap.lColorB, 'Middle Colour', onChanged, onEnded),
        if (l[Sap.lGradient] > 0.5) ..._color(context, l, Sap.lColorC, 'End Colour', onChanged, onEnded),
        _hdr('S_LIGHT LEAK MOTION & MEDIA'),
        s(Sap.lDrift, 'Drift (slow slide)', 0.0, 1.0),
        s(Sap.lSway, 'Sway', 0.0, 1.0),
        s(Sap.lFlicker, 'Flicker', 0.0, 1.0),
        s(Sap.lProtect, 'Protect Highlights (leak mostly over shadows)', 0.0, 1.0),
        s(Sap.lSeed, 'Random Seed', 0.0, 100.0),
        _hdr('S_LIGHT LEAK COMPOSITE'),
        s(Sap.lOpacity, 'Leak Opacity (blend with original)', 0.0, 1.0),
        _blend(l, 'Leak Blend', Sap.lBlend, onChanged, onEnded),
      ]);
    }

    // Sapphire effects that already existed: moved here from COPIED STUFF and GLOW / FLARE. Same fields, same shader code
    // (not re-fixed), so presets saved before the move load exactly as before.
    children.addAll([
      _hdr('S_GLOW  /  EDGE DETECT GLOW  (MOVED HERE)'),
      EditorViews.buildSliderRow(context: context, title: 'Sapphire Glow Width', val: cur.sapphireGlowWidth, min: 0.0, max: 2.0,
          onChanged: (v) { cur.sapphireGlowWidth = v; onChanged(); }, onEnded: onEnded),
      EditorViews.buildSliderRow(context: context, title: 'Sapphire Glow Threshold', val: cur.sapphireGlowThreshold, min: 0.20, max: 0.95,
          onChanged: (v) { cur.sapphireGlowThreshold = v; onChanged(); }, onEnded: onEnded),
      EditorViews.buildSliderRow(context: context, title: 'Sapphire Edge Detect Glow', val: cur.copiedEdgeRays, min: 0.0, max: 1.5,
          onChanged: (v) { cur.copiedEdgeRays = v; onChanged(); }, onEnded: onEnded),
    ]);

    return ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), children: children);
  }
  // ===========================================================================
  // TIME SLICE TAB (batch 12 step C3). Settings live in AdjustmentLayer.timeSlice (class TimeSlice, time_slice_slots.dart) and are saved by the layer JSON.
  // Own tab (index 14, FX shelf): the effect is a whole-frame wipe, not a per-layer colour effect, so it does not belong in a section of another tab.
  // ===========================================================================
  static Widget buildTimeSliceTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final l = cur.timeSlice;
    final on = l[TimeSlice.on] > 0.5;
    Widget s(int slot, String title, double min, double max) => _s(context, l, slot, title, min, max, onChanged, onEnded);
    // whole-number slider: handle snaps to integers, the model always holds a whole number
    Widget whole(int slot, String title, double min, double max) => EditorViews.buildSliderRow(
          context: context,
          title: title,
          val: l[slot].clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: (v) {
            l[slot] = v.roundToDouble();
            onChanged();
          },
          onEnded: onEnded,
          whole: true, // C3: the handle snaps to integers and shows no decimals
        );

    final cp = l[TimeSlice.cutPoint].clamp(0.2, 0.8).toDouble();
    String cap(double fps) => TimeSliceScheduler.maxWipeSeconds(fps, cp).toStringAsFixed(2);
    // the Wipe duration slider ends at the real limit of the slowest common frame rate (24 fps), so the handle can never promise more than the ring can show
    final double wipeMax = math.max(0.11, (TimeSliceScheduler.maxWipeSeconds(24.0, cp) * 100).floor() / 100.0);

    final children = <Widget>[
      _hdr('TIME SLICE  (HARD CUT -> SLICED WIPE)'),
      _toggle(l, 'Time Slice On', TimeSlice.on, onChanged, onEnded),
    ];

    if (on) {
      final placement = l[TimeSlice.placement].round() == TimeSlice.placeLayer ? TimeSlice.placeLayer : TimeSlice.placeGlobal;
      children.addAll([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              const Expanded(child: Text('Placement', style: TextStyle(color: Colors.white70, fontSize: 12))),
              DropdownButton<int>(
                value: placement,
                dropdownColor: kCardDark,
                underline: const SizedBox(),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: TimeSlice.placeLayer, child: Text('Layer')),
                  DropdownMenuItem(value: TimeSlice.placeGlobal, child: Text('Global')),
                ],
                onChanged: (m) {
                  if (m != null) {
                    l[TimeSlice.placement] = m.toDouble();
                    onChanged();
                    onEnded();
                  }
                },
              ),
            ],
          ),
        ),
        _note('Global renders above all effects. Layer renders as a per-layer effect.'),
        if (placement == TimeSlice.placeLayer) _note('Layer placement is not built yet: it currently behaves as Global.'),
        _note('The preview shows the sliced wipe while the video is playing (paused = plain frame). Export always renders it.'),

        _hdr('TRIGGER'),
        _note('One wipe on every detected cut.'),
        s(TimeSlice.cutPoint, 'Cut lands at (position inside the wipe, 0.40 = just before the middle)', 0.2, 0.8),

        _hdr('SLICES'),
        whole(TimeSlice.direction, 'Direction (deg, 90 = top to bottom)', 0.0, 360.0),
        whole(TimeSlice.sliceCount, 'Slices (1 - 64)', 1.0, 64.0),
        s(TimeSlice.feather, 'Feather (softness of the slice borders)', 0.0, 1.0),
        s(TimeSlice.bandWidth, 'Band Width (share of the frame the slices cover)', 0.1, 1.0),
        _toggle(l, 'Interp Frames (blend neighbouring frames = silky, off = steps)', TimeSlice.interpFrames, onChanged, onEnded),
        whole(TimeSlice.frameOffset, 'Frame Offset (shifts the slice times, frames)', -4.0, 4.0),

        _hdr('WIPE'),
        s(TimeSlice.wipeDuration, 'Wipe Duration (seconds)', 0.1, wipeMax),
        _note('Wipe max: ${cap(24)} s (24 fps), ${cap(30)} s (30 fps), ${cap(60)} s (60 fps). A longer setting is limited to this by the frame rate of the clip.'),
        _chips(l, 'Overlap', TimeSlice.overlap, const ['Override', 'Queue', 'Skip later'], onChanged, onEnded),
        _note('Two cuts close together: Override = the new cut takes the wipe over, Queue = it waits for the running wipe, Skip later = it is ignored.'),

        _hdr('COMPOSITE'),
        s(TimeSlice.mix, 'Mix (blend with the original)', 0.0, 1.0),
        s(TimeSlice.opacity, 'Opacity', 0.0, 1.0),

        _hdr('CUT DETECTION'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
              child: ExpansionTile(
                key: const PageStorageKey<String>('ts_cut_detection'),
                initiallyExpanded: false,
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white38,
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                title: const Text('Cut detection settings', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                children: [
                  whole(TimeSlice.cutThreshold, 'Threshold (scene score that counts as a cut, lower = more cuts)', 1.0, 60.0),
                  s(TimeSlice.cutMinGap, 'Minimum Gap (seconds, closer cuts count as one)', 0.0, 1.0),
                  _toggle(l, 'Flash Reject (a double spike is a flash, not a cut)', TimeSlice.cutFlashReject, onChanged, onEnded),
                  s(TimeSlice.cutFlashWindow, 'Flash Window (seconds)', 0.0, 0.5),
                  _note('The first run scans the video once (cached afterwards); changing these values only re-detects.'),
                ],
              ),
            ),
          ),
        ),
      ]);
    } else {
      children.add(_note('Cuts the frame into slices of different moments around every hard cut of the clip. Turn it on to see the settings.'));
    }

    return ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), children: children);
  }
}
