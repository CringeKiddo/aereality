// =============================================================================
// AEReality / Shaderly - Gradient Maps tab (Minecraft-style pixel UI)
// Pixel previews are drawn from the same maths as the shader (GradientMapSettings.fieldT),
// so what the tiles show is what the GPU renders.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'gradient_map.dart';
import 'models.dart';

// ---- Pixel theme -----------------------------------------------------------
const Color _pxFill = Color(0xFF2B2B2E);
const Color _pxLight = Color(0xFF4C4C52);
const Color _pxDark = Color(0xFF111114);
const Color _pxBlack = Color(0xFF000000);
const Color _pxGrass = Color(0xFF5DBB3F);
const Color _pxGold = Color(0xFFFFD43B);
const Color _pxText = Color(0xFFE8E8E8);
const Color _pxMuted = Color(0xFF9A9AA2);

const TextStyle _pxFont = TextStyle(
  fontFamily: 'monospace',
  fontWeight: FontWeight.w800,
  letterSpacing: 1.0,
  color: _pxText,
  fontSize: 11,
);

// The 16 Minecraft dye colours as quick swatches
const List<int> _dyeColors = [
  0xF9FFFE, 0xF9801D, 0xC74EBD, 0x3AB3DA, 0xFED83D, 0x80C71F, 0xF38BAA, 0x474F52,
  0x9D9D97, 0x169C9C, 0x8932B8, 0x3C44AA, 0x835432, 0x5E7C16, 0xB02E26, 0x1D1D21,
];

class GradientMapsTab extends StatefulWidget {
  final AdjustmentLayer cur;
  final VoidCallback onChanged; // live update (slider drag)
  final VoidCallback onEnded; // commit (undo snapshot + save + grade)

  const GradientMapsTab({super.key, required this.cur, required this.onChanged, required this.onEnded});

  @override
  State<GradientMapsTab> createState() => _GradientMapsTabState();
}

class _GradientMapsTabState extends State<GradientMapsTab> {
  int _sel = 0;
  HSVColor _hsv = const HSVColor.fromAHSV(1, 180, 0.5, 0.5);
  final TextEditingController _hex = TextEditingController();
  String? _layerId;

  GradientMapSettings get g => widget.cur.gradientMap;

  @override
  void initState() {
    super.initState();
    _syncFromSelection();
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _syncFromSelection() {
    _layerId = widget.cur.id;
    if (_sel >= g.stops.length) _sel = 0;
    final c = g.stops[_sel].color;
    _hsv = HSVColor.fromColor(c);
    _hex.text = _hexOf(c);
  }

  @override
  void didUpdateWidget(covariant GradientMapsTab old) {
    super.didUpdateWidget(old);
    if (old.cur.id != widget.cur.id) {
      _layerId = widget.cur.id;
      _sel = 0;
      _hsv = HSVColor.fromColor(g.stops[0].color);
      final txt = _hexOf(g.stops[0].color);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hex.text = txt;
      });
    }
  }

  String _hexOf(Color c) => '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _live(VoidCallback fn) {
    setState(() {
      fn();
      g.presetName = '';
    });
    widget.onChanged();
  }

  void _commit() => widget.onEnded();

  void _setStopColor(Color c, {bool commit = false}) {
    _live(() {
      g.stops[_sel].color = c;
      _hsv = HSVColor.fromColor(c);
      _hex.text = _hexOf(c);
    });
    if (commit) _commit();
  }

  @override
  Widget build(BuildContext context) {
    if (_sel >= g.stops.length) _sel = 0;
    final t = g.type;
    final usesAngle = {GradientMapType.linear, GradientMapType.angular, GradientMapType.stripes, GradientMapType.lumaLinear}.contains(t);
    final usesScale = {GradientMapType.linear, GradientMapType.corner, GradientMapType.radial, GradientMapType.edge, GradientMapType.lumaLinear}.contains(t);
    final usesCenter = {GradientMapType.radial, GradientMapType.angular}.contains(t);
    final usesBands = t == GradientMapType.posterized;
    final usesPattern = {GradientMapType.checker, GradientMapType.stripes, GradientMapType.halftone, GradientMapType.noise}.contains(t);
    final usesEdge = {GradientMapType.edge, GradientMapType.splitTone}.contains(t);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        _header(),
        const SizedBox(height: 12),
        _section('PRESETS', _presets()),
        _section('MAP TYPE', _typeGrid()),
        _section('COLOURS', _colourSection()),
        _section('SETTINGS', Column(children: [
          _bar('STRENGTH', g.strength, 0.0, kGradientMaxStrength, (v) => _live(() => g.strength = v), fmt: (v) => '${(v / kGradientMaxStrength * 100).round()}%'),
          _bar('LUMA KEEP', g.lumaKeep, 0.0, 1.0, (v) => _live(() => g.lumaKeep = v)),
          _bar('CURVE', g.curve, 0.4, 2.5, (v) => _live(() => g.curve = v)),
          _bar('RANGE LOW', g.rangeLo, 0.0, 0.9, (v) => _live(() => g.rangeLo = math.min(v, g.rangeHi - 0.05))),
          _bar('RANGE HIGH', g.rangeHi, 0.1, 1.0, (v) => _live(() => g.rangeHi = math.max(v, g.rangeLo + 0.05))),
          if (usesAngle) _bar('ANGLE', g.angle, 0.0, 360.0, (v) => _live(() => g.angle = v), fmt: (v) => '${v.round()}°'),
          if (usesScale) _bar('SCALE', g.scale, 0.25, 2.5, (v) => _live(() => g.scale = v)),
          if (usesCenter) _bar('CENTER X', g.centerX, 0.0, 1.0, (v) => _live(() => g.centerX = v)),
          if (usesCenter) _bar('CENTER Y', g.centerY, 0.0, 1.0, (v) => _live(() => g.centerY = v)),
          if (usesBands) _bar('BANDS', g.bands.toDouble(), 2, 12, (v) => _live(() => g.bands = v.round()), steps: 10, fmt: (v) => '${v.round()}'),
          if (usesPattern) _bar('PATTERN SIZE', g.patternSize, 0.0, 1.0, (v) => _live(() => g.patternSize = v)),
          if (usesEdge) _bar(t == GradientMapType.edge ? 'EDGE WIDTH' : 'SOFTNESS', g.edgeWidth, 0.0, 1.0, (v) => _live(() => g.edgeWidth = v)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _button(g.invert ? 'INVERT: ON' : 'INVERT: OFF', g.invert ? _pxGrass : _pxFill, () {
              _live(() => g.invert = !g.invert);
              _commit();
            })),
            const SizedBox(width: 8),
            Expanded(child: _button('RESET MAP', _pxFill, () {
              setState(() {
                final keep = g.enabled;
                g.copyFrom(GradientMapSettings());
                g.enabled = keep;
                _sel = 0;
                _syncFromSelection();
              });
              widget.onChanged();
              _commit();
            })),
          ]),
        ])),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  Widget _header() {
    return _panel(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GRADIENT MAP', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, fontSize: 15, color: _pxGold, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text('LAYER: ${widget.cur.name}', style: _pxFont.copyWith(color: _pxMuted, fontSize: 10)),
            Text('BLEND: ${widget.cur.blendMode.name.toUpperCase()}  ·  RUNS BEFORE LUT', style: _pxFont.copyWith(color: _pxMuted, fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: _button(g.enabled ? 'ON' : 'OFF', g.enabled ? _pxGrass : const Color(0xFF6A2A2A), () {
            _live(() => g.enabled = !g.enabled);
            _commit();
          }),
        ),
      ]),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(children: [
            Container(width: 8, height: 8, color: _pxGrass),
            const SizedBox(width: 6),
            Text(title, style: _pxFont.copyWith(fontSize: 12, color: _pxGold)),
          ]),
        ),
        _panel(child: child),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _presets() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kGradientPresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = kGradientPresets[i];
          final tmp = GradientMapSettings(type: p.type, stops: p.stops.map((s) => s.clone()).toList(), angle: p.angle);
          final selected = g.presetName == p.name;
          return GestureDetector(
            onTap: () {
              setState(() {
                p.applyTo(g);
                _sel = 0;
                _syncFromSelection();
              });
              widget.onChanged();
              _commit();
            },
            child: _frame(
              selected: selected,
              width: 104,
              child: Column(children: [
                Expanded(child: CustomPaint(painter: _PixelFieldPainter(tmp, cols: 20, rows: 10), size: Size.infinite)),
                const SizedBox(height: 4),
                Text(p.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.clip, style: _pxFont.copyWith(fontSize: 9)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _typeGrid() {
    final types = GradientMapType.values;
    return Column(children: [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.15,
        children: [
          for (final t in types)
            GestureDetector(
              onTap: () {
                _live(() {
                  g.type = t;
                  g.enabled = true;
                });
                _commit();
              },
              child: _frame(
                selected: g.type == t,
                child: Column(children: [
                  Expanded(child: CustomPaint(painter: _PixelFieldPainter(g.clone()..type = t, cols: 20, rows: 12), size: Size.infinite)),
                  const SizedBox(height: 4),
                  Text(kGradientTypeNames[t]!, style: _pxFont.copyWith(fontSize: 10, color: g.type == t ? _pxGold : _pxText)),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: Text(kGradientTypeHints[g.type] ?? '', style: _pxFont.copyWith(color: _pxMuted, fontSize: 10))),
    ]);
  }

  // ---------------------------------------------------------------------------
  Widget _colourSection() {
    final stops = g.stops;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Ramp strip (pixel blocks) with draggable stop markers
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        const m = 20.0;
        return SizedBox(
          height: 70,
          child: Stack(children: [
            Positioned(left: 0, right: 0, top: 0, height: 32, child: _frame(selected: false, pad: 3, child: CustomPaint(painter: _PixelRampPainter(g), size: Size.infinite))),
            for (int i = 0; i < stops.length; i++)
              Positioned(
                left: (stops[i].pos * (w - m)).clamp(0.0, w - m),
                top: 38,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _sel = i;
                      _syncFromSelection();
                    });
                  },
                  onHorizontalDragStart: (_) => setState(() {
                    _sel = i;
                    _syncFromSelection();
                  }),
                  onHorizontalDragUpdate: (d) => _live(() {
                    _sel = i;
                    stops[i].pos = (stops[i].pos + d.delta.dx / (w - m)).clamp(0.0, 1.0);
                  }),
                  onHorizontalDragEnd: (_) => _commit(),
                  child: Container(
                    width: m,
                    height: m + 6,
                    decoration: BoxDecoration(color: stops[i].color, border: Border.all(color: i == _sel ? _pxGold : _pxBlack, width: 3)),
                  ),
                ),
              ),
          ]),
        );
      }),
      Row(children: [
        Expanded(
          child: _button('+ STOP', stops.length < 6 ? _pxFill : _pxDark, () {
            if (stops.length >= 6) return;
            final s = g.sortedStops;
            int bi = 1;
            double bg = -1;
            for (int i = 1; i < s.length; i++) {
              final gap = s[i].pos - s[i - 1].pos;
              if (gap > bg) {
                bg = gap;
                bi = i;
              }
            }
            final mid = (s[bi].pos + s[bi - 1].pos) / 2;
            final ns = GradientStop(g.colorAt(mid), mid);
            _live(() {
              stops.add(ns);
              _sel = stops.length - 1;
              _syncFromSelection();
            });
            _commit();
          }),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _button('- STOP', stops.length > 2 ? _pxFill : _pxDark, () {
            if (stops.length <= 2) return;
            _live(() {
              stops.removeAt(_sel);
              _sel = 0;
              _syncFromSelection();
            });
            _commit();
          }),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _button('FLIP', _pxFill, () {
            _live(() {
              for (final s in stops) {
                s.pos = 1.0 - s.pos;
              }
            });
            _commit();
          }),
        ),
      ]),
      const SizedBox(height: 10),
      _bar('STOP POSITION', stops[_sel].pos, 0.0, 1.0, (v) => _live(() => stops[_sel].pos = v)),
      const SizedBox(height: 6),
      // Colour wheel + value + hex
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PixelWheel(
          hsv: _hsv,
          onChanged: (h) => _setStopColor(h.toColor()),
          onEnd: _commit,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('STOP ${_sel + 1}/${stops.length}', style: _pxFont.copyWith(color: _pxGold)),
            const SizedBox(height: 6),
            Container(height: 22, decoration: BoxDecoration(color: stops[_sel].color, border: Border.all(color: _pxBlack, width: 3))),
            const SizedBox(height: 8),
            _bar('BRIGHT', _hsv.value, 0.0, 1.0, (v) => _setStopColor(_hsv.withValue(v).toColor())),
            const SizedBox(height: 4),
            _frame(
              selected: false,
              pad: 2,
              child: TextField(
                controller: _hex,
                style: _pxFont.copyWith(fontSize: 13),
                maxLength: 7,
                cursorColor: _pxGold,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]'))],
                decoration: const InputDecoration(isDense: true, counterText: '', border: InputBorder.none, hintText: '#RRGGBB', contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
                onChanged: (s) {
                  final h = s.replaceAll('#', '');
                  if (h.length == 6) {
                    final v = int.tryParse(h, radix: 16);
                    if (v != null) {
                      g.stops[_sel].color = Color(0xFF000000 | v);
                      _hsv = HSVColor.fromColor(g.stops[_sel].color);
                      setState(() => g.presetName = '');
                      widget.onChanged();
                    }
                  }
                },
                onSubmitted: (_) => _commit(),
              ),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Text('QUICK COLOURS', style: _pxFont.copyWith(color: _pxMuted, fontSize: 10)),
      const SizedBox(height: 6),
      Wrap(spacing: 5, runSpacing: 5, children: [
        for (final d in _dyeColors)
          GestureDetector(
            onTap: () {
              _setStopColor(Color(0xFF000000 | d), commit: true);
            },
            child: Container(width: 24, height: 24, decoration: BoxDecoration(color: Color(0xFF000000 | d), border: Border.all(color: _pxBlack, width: 2))),
          ),
      ]),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Pixel widgets
  // ---------------------------------------------------------------------------
  Widget _panel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(color: _pxBlack, border: Border.all(color: _pxBlack, width: 2)),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: _pxFill,
          border: Border(
            top: BorderSide(color: _pxLight, width: 3),
            left: BorderSide(color: _pxLight, width: 3),
            bottom: BorderSide(color: _pxDark, width: 3),
            right: BorderSide(color: _pxDark, width: 3),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _frame({required Widget child, required bool selected, double? width, double pad = 5}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(2),
      color: selected ? _pxGold : _pxBlack,
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: const BoxDecoration(
          color: _pxFill,
          border: Border(
            top: BorderSide(color: _pxDark, width: 2),
            left: BorderSide(color: _pxDark, width: 2),
            bottom: BorderSide(color: _pxLight, width: 2),
            right: BorderSide(color: _pxLight, width: 2),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _button(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        onTap();
      },
      child: Container(
        color: _pxBlack,
        padding: const EdgeInsets.all(2),
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            border: const Border(
              top: BorderSide(color: Color(0x55FFFFFF), width: 3),
              left: BorderSide(color: Color(0x55FFFFFF), width: 3),
              bottom: BorderSide(color: Color(0x66000000), width: 3),
              right: BorderSide(color: Color(0x66000000), width: 3),
            ),
          ),
          child: Text(label, style: _pxFont),
        ),
      ),
    );
  }

  Widget _bar(String label, double value, double min, double max, ValueChanged<double> onChanged,
      {String Function(double)? fmt, int? steps}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: _pxFont.copyWith(fontSize: 10, color: _pxMuted)),
          Text(fmt != null ? fmt(value) : value.toStringAsFixed(2), style: _pxFont.copyWith(fontSize: 10)),
        ]),
        const SizedBox(height: 3),
        _PixelBar(
          value: value,
          min: min,
          max: max,
          steps: steps,
          colorAt: (f) => g.colorAt(f),
          onChanged: onChanged,
          onEnd: _commit,
        ),
      ]),
    );
  }
}

// =============================================================================
// Painters / small widgets
// =============================================================================

/// Draws the type preview: a grid of solid pixels coloured by the gradient map over a demo scene.
class _PixelFieldPainter extends CustomPainter {
  final GradientMapSettings s;
  final int cols;
  final int rows;
  _PixelFieldPainter(this.s, {required this.cols, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / cols;
    final ch = size.height / rows;
    final p = Paint()..isAntiAlias = false;
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final u = (x + 0.5) / cols;
        final v = (y + 0.5) / rows;
        p.color = s.colorAt(s.fieldT(u, v, aspect: cw == 0 ? 1.6 : size.width / size.height, cells: cols ~/ 2));
        canvas.drawRect(Rect.fromLTWH((x * cw).floorToDouble(), (y * ch).floorToDouble(), cw.ceilToDouble() + 0.5, ch.ceilToDouble() + 0.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelFieldPainter old) => true;
}

class _PixelRampPainter extends CustomPainter {
  final GradientMapSettings s;
  _PixelRampPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 40;
    final cw = size.width / n;
    final p = Paint()..isAntiAlias = false;
    for (int i = 0; i < n; i++) {
      p.color = s.colorAt(i / (n - 1));
      canvas.drawRect(Rect.fromLTWH(i * cw, 0, cw + 0.8, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelRampPainter old) => true;
}

/// Segmented pixel slider. Filled blocks take the colours of the current gradient.
class _PixelBar extends StatelessWidget {
  final double value, min, max;
  final int? steps;
  final Color Function(double) colorAt;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _PixelBar({required this.value, required this.min, required this.max, required this.colorAt, required this.onChanged, required this.onEnd, this.steps});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void setFrom(double dx) {
        final double f = (dx / w).clamp(0.0, 1.0).toDouble();
        double v = min + (max - min) * f;
        if (steps != null) v = (min + ((v - min) / (max - min) * steps!).round() * (max - min) / steps!).clamp(min, max).toDouble();
        onChanged(v);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => setFrom(d.localPosition.dx),
        onTapUp: (_) => onEnd(),
        onHorizontalDragStart: (d) => setFrom(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => setFrom(d.localPosition.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: Container(
          height: 22,
          color: _pxBlack,
          padding: const EdgeInsets.all(2),
          child: CustomPaint(
            size: Size.infinite,
            painter: _BarPainter(frac: ((value - min) / (max - min)).clamp(0.0, 1.0), colorAt: colorAt),
          ),
        ),
      );
    });
  }
}

class _BarPainter extends CustomPainter {
  final double frac;
  final Color Function(double) colorAt;
  _BarPainter({required this.frac, required this.colorAt});

  @override
  void paint(Canvas canvas, Size size) {
    const n = 24;
    const gap = 2.0;
    final bw = (size.width - gap * (n - 1)) / n;
    final p = Paint()..isAntiAlias = false;
    final filled = (frac * n).round();
    for (int i = 0; i < n; i++) {
      p.color = i < filled ? colorAt(i / (n - 1)) : const Color(0xFF3A3A40);
      canvas.drawRect(Rect.fromLTWH(i * (bw + gap), 0, bw, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}

/// Pixelated hue / saturation wheel.
class _PixelWheel extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final VoidCallback onEnd;
  static const double size = 150;

  const _PixelWheel({required this.hsv, required this.onChanged, required this.onEnd});

  void _pick(Offset o) {
    final c = const Offset(size / 2, size / 2);
    final d = o - c;
    final r = math.min(d.distance / (size / 2), 1.0);
    double hue = math.atan2(d.dy, d.dx) * 180 / math.pi;
    if (hue < 0) hue += 360;
    onChanged(HSVColor.fromAHSV(1, hue, r, hsv.value));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _pick(d.localPosition),
      onPanUpdate: (d) => _pick(d.localPosition),
      onPanEnd: (_) => onEnd(),
      onTapDown: (d) => _pick(d.localPosition),
      onTapUp: (_) => onEnd(),
      child: Container(
        width: size + 8,
        height: size + 8,
        color: _pxBlack,
        padding: const EdgeInsets.all(4),
        child: CustomPaint(size: const Size(size, size), painter: _WheelPainter(hsv)),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  _WheelPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    const n = 30;
    final cell = size.width / n;
    final p = Paint()..isAntiAlias = false;
    for (int y = 0; y < n; y++) {
      for (int x = 0; x < n; x++) {
        final dx = (x + 0.5) / n * 2 - 1;
        final dy = (y + 0.5) / n * 2 - 1;
        final r = math.sqrt(dx * dx + dy * dy);
        if (r > 1.0) continue;
        double hue = math.atan2(dy, dx) * 180 / math.pi;
        if (hue < 0) hue += 360;
        p.color = HSVColor.fromAHSV(1, hue, r, hsv.value).toColor();
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.6, cell + 0.6), p);
      }
    }
    // selector (square cursor)
    final a = hsv.hue * math.pi / 180;
    final pos = Offset(size.width / 2 + math.cos(a) * hsv.saturation * size.width / 2, size.height / 2 + math.sin(a) * hsv.saturation * size.height / 2);
    canvas.drawRect(Rect.fromCenter(center: pos, width: 12, height: 12), Paint()..color = _pxBlack);
    canvas.drawRect(Rect.fromCenter(center: pos, width: 8, height: 8), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromCenter(center: pos, width: 4, height: 4), Paint()..color = hsv.toColor());
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => true;
}
