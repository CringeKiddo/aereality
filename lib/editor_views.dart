// =============================================================================
// AEReality / Shaderly - Editor Views (Part 1/3)
// True 32-Bit Float Linear Pipeline - Presets, Tonemappers, LUT, Basic & Magic
// 100% Complete Section - Zero Feature Omissions
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:image/image.dart' as img;

import 'constants.dart';
import 'models.dart';
import 'lut_processor.dart';
import 'components/curve_editor.dart';
import 'export_suite.dart';
import 'ui_kit.dart';
import 'vfx_suite.dart'; // batch 14: VfxSuite.colorSlot (existing colour widget) for the 4-Way Gradient
import 'vfx_slots.dart'; // batch 13: Bevel slot numbers (Metallic Bevel rows in the Magic tab)

class EditorViews {
  // ---------------------------------------------------------------------------
  // SLIDER BUILDER
  // ---------------------------------------------------------------------------
  static Widget buildSliderRow({
    required BuildContext context,
    required String title,
    required double val,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    VoidCallback? onEnded,
    bool whole = false, // C3: true = the handle snaps to whole numbers (one notch per integer) and the label shows no decimals
  }) {
    return SmoothSliderRow(title: title, val: val, min: min, max: max, onChanged: onChanged, onEnded: onEnded, whole: whole);
  }

  // ---------------------------------------------------------------------------
  // 1. PRESETS TAB (Clean Display - Tap to Toggle, No Subtitle Clutter)
  // ---------------------------------------------------------------------------
  static Widget buildPresetsTab({
    required BuildContext context,
    required ProjectData project,
    required List<CustomPresetItem> customPresets,
    required String? selectedPresetName,
    required bool isBslOverlayActive,
    required VoidCallback onToggleBslOverlay,
    required ValueChanged<String> onPresetSelected,
    required VoidCallback onSavePreset,
    required VoidCallback onImportPreset,
    required ValueChanged<int> onDeleteCustomPreset,
  }) {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isBslOverlayActive ? accent.withOpacity(0.20) : const Color(0xFF161622),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isBslOverlayActive ? accent : Colors.white12,
              width: isBslOverlayActive ? 1.8 : 1.0,
            ),
          ),
          child: ListTile(
            leading: Icon(
              Icons.cloud_sync_rounded,
              color: isBslOverlayActive ? accent : Colors.white70,
              size: 24,
            ),
            title: const Text(
              'BSL Volumetric Mist & Atmosphere Overlay',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: const Text(
              'Stackable atmospheric fog & light scatter across all active layers',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            trailing: Switch(
              value: isBslOverlayActive,
              activeColor: accent,
              onChanged: (_) => onToggleBslOverlay(),
            ),
          ),
        ),

        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onSavePreset,
                icon: const Icon(Icons.bookmark_add_rounded, size: 16, color: Colors.black),
                label: const Text('SAVE CC', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onImportPreset,
                icon: Icon(Icons.file_open_rounded, size: 16, color: accent),
                label: Text('IMPORT CC', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.file_download_outlined, color: accent),
              tooltip: 'Export CC as JSON / XML',
              onPressed: () => exportPresetToFile(context, project),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (customPresets.isNotEmpty) ...[
          const Text('MY PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...List.generate(customPresets.length, (index) {
            final custom = customPresets[index];
            final isSel = selectedPresetName == custom.name;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSel ? accent.withOpacity(0.16) : gPalette.value.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06)),
              ),
              child: ListTile(
                title: Text(custom.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                  onPressed: () => onDeleteCustomPreset(index),
                ),
                onTap: () => onPresetSelected(custom.name),
              ),
            );
          }),
          const SizedBox(height: 14),
        ],

        const Text('PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...kAnimePresetStyles.map((p) {
          final isSel = selectedPresetName == p.name;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? accent.withOpacity(0.16) : gPalette.value.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06)),
            ),
            child: ListTile(
              title: Text(p.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              trailing: isSel ? Icon(Icons.check_circle_rounded, color: accent, size: 18) : null,
              onTap: () => onPresetSelected(p.name),
            ),
          );
        }).toList(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. TONEMAPPERS TAB (Linear, AgX, Khronos Neutral+, Aurora Depth, Sakura Silk, Prism Blend, Obsidian Cel)
  // ---------------------------------------------------------------------------
  static Widget buildTonemappersTab({
    required BuildContext context,
    required ProjectData project,
    required VoidCallback onChanged,
  }) {
    final accent = gCustomAccentColor.value;

    final tonemappers = [
      {
        'mode': 0.0,
        'title': 'Linear (Off / Native Passthrough)',
        'desc': 'Raw linear response.',
      },
      {
        'mode': 1.0,
        'title': 'Shaderly Tonemapper 1 (AgX Anime Punch)',
        'desc': 'AgX, deeper blacks, smooth highlights.',
      },
      {
        'mode': 2.0,
        'title': 'Shaderly Tonemapper 2 (Khronos PBR Neutral+)',
        'desc': 'Khronos PBR Neutral.',
      },
      {
        'mode': 3.0,
        'title': 'Aurora Depth',
        'desc': 'Oklab lightness S-curve.',
      },
      {
        'mode': 4.0,
        'title': 'Sakura Silk',
        'desc': 'Skin-friendly roll-off.',
      },
      {
        'mode': 5.0,
        'title': 'Prism Blend',
        'desc': 'Colour-blending highlights.',
      },
      {
        'mode': 6.0,
        'title': 'Obsidian Cel',
        'desc': 'Rich, deep shadows.',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('COLOR SPACE & TONEMAPPING', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 6),
        const Text(
          'Select the display transform for your true 32-bit float linear grade.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 16),
        ...tonemappers.map((tm) {
          final isSel = project.tonemapMode == tm['mode'];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSel ? accent.withOpacity(0.14) : gPalette.value.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSel ? accent : Colors.white.withOpacity(0.06),
                width: isSel ? 1.5 : 1.0,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                tm['title'] as String,
                style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  tm['desc'] as String,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
              trailing: isSel ? Icon(Icons.radio_button_checked, color: accent) : const Icon(Icons.radio_button_off, color: Colors.white24),
              onTap: () {
                project.tonemapMode = tm['mode'] as double;
                onChanged();
              },
            ),
          );
        }).toList(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. LUT TAB (Applied Display-Referred in sRGB)
  // ---------------------------------------------------------------------------
  static Widget buildLutsTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required List<LutModel> activeLuts,
    required VoidCallback onLutUpdated,
    required VoidCallback onPickLut,
    required ValueChanged<int> onDeleteLut,
  }) {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('3D LUT', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: onPickLut,
              icon: const Icon(Icons.add_rounded, size: 16, color: Colors.black),
              label: const Text('IMPORT .CUBE', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (cur.activeLutId != null) ...[
          buildSliderRow(
            context: context,
            title: 'Active LUT Opacity',
            val: cur.lutOpacity,
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              cur.lutOpacity = v;
              onLutUpdated();
            },
            onEnded: onLutUpdated,
          ),
          const SizedBox(height: 14),
        ],

        if (activeLuts.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: gPalette.value.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: const Center(
              child: Text(
                'No .cube LUTs imported yet.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          )
        else
          ...List.generate(activeLuts.length, (idx) {
            final lut = activeLuts[idx];
            final isSel = cur.activeLutId == lut.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSel ? accent.withOpacity(0.16) : gPalette.value.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06), width: isSel ? 1.5 : 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSel ? accent : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '3D',
                        style: TextStyle(
                          color: isSel ? Colors.black : Colors.white54,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        cur.activeLutId = isSel ? null : lut.id;
                        onLutUpdated();
                      },
                      child: Text(lut.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                    tooltip: 'Delete LUT',
                    onPressed: () => onDeleteLut(idx),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. BASIC TAB (S_lining 2 Sliders + Bilateral + Blend Color Space)
  // ---------------------------------------------------------------------------
  static Widget buildBasicGradingTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        // Gamma Space vs Linear Space Blending Option
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: gPalette.value.control,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Blend Color Space', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(
                    cur.blendLinear ? 'Linear Light (Physical)' : 'Gamma Space (After Effects Style)',
                    style: TextStyle(color: accent, fontSize: 10),
                  ),
                ],
              ),
              Switch(
                value: !cur.blendLinear,
                activeColor: accent,
                onChanged: (val) {
                  cur.blendLinear = !val;
                  onChanged();
                  onEnded();
                },
              ),
            ],
          ),
        ),

        buildSliderRow(context: context, title: 'Exposure', val: cur.brightness, min: -0.8, max: 0.8, onChanged: (v) { cur.brightness = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Contrast', val: cur.contrast, min: 0.2, max: 2.5, onChanged: (v) { cur.contrast = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Saturation', val: cur.saturation, min: 0.0, max: 2.5, onChanged: (v) { cur.saturation = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Chroma Contrast (S-Curve on Colour Intensity)', val: cur.chromaContrast, min: -1.0, max: 1.0, onChanged: (v) { cur.chromaContrast = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Hue / Color Rotate (Oklab Angle)', val: cur.hue, min: -1.0, max: 1.0, onChanged: (v) { cur.hue = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Gamma', val: cur.gamma, min: 0.2, max: 2.5, onChanged: (v) { cur.gamma = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Sharpness', val: cur.sharpness, min: 0.0, max: 2.0, onChanged: (v) { cur.sharpness = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Clarity / Local Contrast', val: cur.clarity, min: -1.0, max: 1.0, onChanged: (v) { cur.clarity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Clarity Size (Fine to Broad)', val: cur.clarityRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.clarityRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Temperature', val: cur.temperature, min: 2000.0, max: 12000.0, onChanged: (v) { cur.temperature = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Highlights', val: cur.highlights, min: -1.0, max: 1.0, onChanged: (v) { cur.highlights = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shadows', val: cur.shadows, min: -1.0, max: 1.0, onChanged: (v) { cur.shadows = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Black Crush', val: cur.blackCrush, min: 0.0, max: 0.5, onChanged: (v) { cur.blackCrush = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        HueSatPanel(cur: cur, onChanged: onChanged, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('S_LINING', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'S_lining Intensity / Radius', val: cur.darkOutlines, min: 0.0, max: 1.0, onChanged: (v) { cur.darkOutlines = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'S_lining Opacity', val: cur.sLiningOpacity, min: 0.0, max: 1.0, onChanged: (v) { cur.sLiningOpacity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Edge Line Thinning', val: cur.lineThinning, min: 0.0, max: 1.0, onChanged: (v) { cur.lineThinning = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('BILATERAL ANIME SKIN SMOOTHING', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Bilateral Intensity', val: cur.bilateralIntensity, min: 0.0, max: 1.0, onChanged: (v) { cur.bilateralIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Bilateral Radius', val: cur.bilateralRadius, min: 0.0, max: 5.0, onChanged: (v) { cur.bilateralRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Bilateral Range (Edge Preserve)', val: cur.bilateralRange, min: 0.0, max: 1.0, onChanged: (v) { cur.bilateralRange = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DYNAMICS & FLICKER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Flicker Intensity', val: cur.flickerIntensity, min: 0.0, max: 1.0, onChanged: (v) { cur.flickerIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flicker Speed (Hz)', val: cur.flickerSpeed, min: 1.0, max: 20.0, onChanged: (v) { cur.flickerSpeed = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('CEL SHADING & VIGNETTES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Edge Darken', val: cur.edgeDarken, min: 0.0, max: 1.0, onChanged: (v) { cur.edgeDarken = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Edge Darken Inner Blur (Spread)', val: cur.edgeDarkenBlur, min: 0.0, max: 1.0, onChanged: (v) { cur.edgeDarkenBlur = v; onChanged(); }, onEnded: onEnded),
        // Tuned to 0.70 max so it doesn't aggressively black out borders
        buildSliderRow(context: context, title: 'Radial Vignette', val: cur.vignette, min: 0.0, max: 0.70, onChanged: (v) { cur.vignette = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Boxed Vignette', val: cur.vignetteBoxed, min: 0.0, max: 0.70, onChanged: (v) { cur.vignetteBoxed = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4b. COLORISTA TAB (Lift / Gamma / Gain / Offset colour wheels + full primary controls)
  // ---------------------------------------------------------------------------
  static Widget _miniSlider({
    required BuildContext context,
    required String label,
    required double val,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    VoidCallback? onEnded,
  }) {
    final accent = gCustomAccentColor.value;
    return Row(
      children: [
        SizedBox(width: 30, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.6,
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: val.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (_) => onEnded?.call(),
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(val.toStringAsFixed(2), textAlign: TextAlign.right, style: TextStyle(color: accent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  static Widget _wheelCard({
    required BuildContext context,
    required String title,
    required double x,
    required double y,
    required double luma,
    required double lumaMin,
    required double lumaMax,
    required void Function(double, double) onWheel,
    required ValueChanged<double> onLuma,
    required VoidCallback onEnded,
  }) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(
        color: gPalette.value.control,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final size = math.min(c.maxWidth - 8, 150.0);
        return Column(
          children: [
            ColorWheelPicker(label: title, x: x, y: y, size: size, onChanged: onWheel, onEnded: onEnded), // gesture lock lives inside the control (DragLock, curve_editor.dart)
            const SizedBox(height: 4),
            _miniSlider(context: context, label: 'Luma', val: luma, min: lumaMin, max: lumaMax, onChanged: onLuma, onEnded: onEnded),
          ],
        );
      }),
    );
  }

  static Widget buildColoristaTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final accent = gCustomAccentColor.value;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(t, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        header('COLORISTA  -  3-WAY COLOUR WHEELS (DRAG THE PUCK, DOUBLE-TAP A WHEEL TO RESET IT)'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _wheelCard(
                context: context,
                title: 'SHADOWS  /  LIFT',
                x: cur.coloristaLiftX,
                y: cur.coloristaLiftY,
                luma: cur.mblColoristaLift,
                lumaMin: -0.5,
                lumaMax: 0.5,
                onWheel: (x, y) { cur.coloristaLiftX = x; cur.coloristaLiftY = y; onChanged(); },
                onLuma: (v) { cur.mblColoristaLift = v; onChanged(); },
                onEnded: onEnded,
              ),
            ),
            Expanded(
              child: _wheelCard(
                context: context,
                title: 'MIDTONES  /  GAMMA',
                x: cur.coloristaGammaX,
                y: cur.coloristaGammaY,
                luma: cur.mblColoristaGamma,
                lumaMin: -0.5,
                lumaMax: 0.5,
                onWheel: (x, y) { cur.coloristaGammaX = x; cur.coloristaGammaY = y; onChanged(); },
                onLuma: (v) { cur.mblColoristaGamma = v; onChanged(); },
                onEnded: onEnded,
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _wheelCard(
                context: context,
                title: 'HIGHLIGHTS  /  GAIN',
                x: cur.coloristaGainX,
                y: cur.coloristaGainY,
                luma: cur.mblColoristaGain,
                lumaMin: -0.5,
                lumaMax: 0.5,
                onWheel: (x, y) { cur.coloristaGainX = x; cur.coloristaGainY = y; onChanged(); },
                onLuma: (v) { cur.mblColoristaGain = v; onChanged(); },
                onEnded: onEnded,
              ),
            ),
            Expanded(
              child: _wheelCard(
                context: context,
                title: 'MASTER  /  OFFSET',
                x: cur.coloristaOffsetX,
                y: cur.coloristaOffsetY,
                luma: cur.coloristaOffsetLuma,
                lumaMin: -0.5,
                lumaMax: 0.5,
                onWheel: (x, y) { cur.coloristaOffsetX = x; cur.coloristaOffsetY = y; onChanged(); },
                onLuma: (v) { cur.coloristaOffsetLuma = v; onChanged(); },
                onEnded: onEnded,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        header('SATURATION'),
        buildSliderRow(context: context, title: 'Colorista Saturation', val: cur.coloristaSaturation, min: 0.0, max: 2.0, onChanged: (v) { cur.coloristaSaturation = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shadow Saturation', val: cur.coloristaSatShadows, min: -1.0, max: 1.0, onChanged: (v) { cur.coloristaSatShadows = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Midtone Saturation', val: cur.coloristaSatMids, min: -1.0, max: 1.0, onChanged: (v) { cur.coloristaSatMids = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Highlight Saturation', val: cur.coloristaSatHighs, min: -1.0, max: 1.0, onChanged: (v) { cur.coloristaSatHighs = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shadow Range (where shadows end)', val: cur.coloristaShadowRange, min: 0.05, max: 0.70, onChanged: (v) { cur.coloristaShadowRange = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Highlight Range (where highlights begin)', val: cur.coloristaHighlightRange, min: 0.30, max: 0.95, onChanged: (v) { cur.coloristaHighlightRange = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        header('CONTRAST & PIVOT'),
        buildSliderRow(context: context, title: 'Colorista Contrast', val: cur.coloristaContrast, min: -1.0, max: 1.0, onChanged: (v) { cur.coloristaContrast = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Pivot (what stays put)', val: cur.coloristaPivot, min: 0.10, max: 0.90, onChanged: (v) { cur.coloristaPivot = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        header('TEMPERATURE & TINT'),
        buildSliderRow(context: context, title: 'Temperature (Cool to Warm)', val: cur.coloristaTemp, min: -1.0, max: 1.0, onChanged: (v) { cur.coloristaTemp = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Tint (Green to Magenta)', val: cur.coloristaTint, min: -1.0, max: 1.0, onChanged: (v) { cur.coloristaTint = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        header('OUTPUT'),
        buildSliderRow(context: context, title: 'Preserve Luminance', val: cur.coloristaPreserveLuma, min: 0.0, max: 1.0, onChanged: (v) { cur.coloristaPreserveLuma = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Mix', val: cur.coloristaMix, min: 0.0, max: 1.0, onChanged: (v) { cur.coloristaMix = v; onChanged(); }, onEnded: onEnded),

        Center(
          child: TextButton.icon(
            onPressed: () {
              cur.resetColorista();
              onChanged();
              onEnded();
            },
            icon: Icon(Icons.refresh_rounded, size: 16, color: accent),
            label: Text('Reset Colorista', style: TextStyle(color: accent, fontSize: 11)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. MAGIC TAB (Split Toning, Magic Bullet Suite & Deep Teal)
  // ---------------------------------------------------------------------------
  static Widget buildMagicTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('SPLIT TONING', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Shadow Hue', val: cur.splitToneShadowHue, min: 0.0, max: 1.0, onChanged: (v) { cur.splitToneShadowHue = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shadow Saturation', val: cur.splitToneShadowSat, min: 0.0, max: 1.0, onChanged: (v) { cur.splitToneShadowSat = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Highlight Hue', val: cur.splitToneHighHue, min: 0.0, max: 1.0, onChanged: (v) { cur.splitToneHighHue = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Highlight Saturation', val: cur.splitToneHighSat, min: 0.0, max: 1.0, onChanged: (v) { cur.splitToneHighSat = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Split Tone Balance', val: cur.splitToneBalance, min: -1.0, max: 1.0, onChanged: (v) { cur.splitToneBalance = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('MAGIC BULLET SUITE REPLICATION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Mojo (Teal & Orange Split)', val: cur.mblMojoTealOrange, min: 0.0, max: 1.5, onChanged: (v) { cur.mblMojoTealOrange = v; onChanged(); }, onEnded: onEnded),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('Lift / Gamma / Gain: COLORISTA tab.', style: TextStyle(color: Colors.white24, fontSize: 10)),
        ),
        buildSliderRow(context: context, title: 'Cosmo Clean Highlights (Skin Protection)', val: cur.cosmoCleanHighlight, min: 0.0, max: 1.0, onChanged: (v) { cur.cosmoCleanHighlight = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('MAGIC BULLETS PRO: DEEP TEAL & S-CURVES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deep Teal (Dark Cyan Chrominance)', val: cur.deepTeal, min: 0.0, max: 1.5, onChanged: (v) { cur.deepTeal = v; onChanged(); }, onEnded: onEnded),
        ..._magicBatch4Rows(context, cur, onChanged, onEnded),
        buildSliderRow(context: context, title: 'Magic Curves (Lightness S-Curve)', val: cur.magicCurves, min: 0.0, max: 1.5, onChanged: (v) { cur.magicCurves = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('METALLIC BEVEL (GLOBAL SEND-OFF)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        ..._metallicBevelRows(context, cur, onChanged, onEnded),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('MATHOPS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        ..._mathOpsRows(context, cur, onChanged, onEnded),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('4-WAY GRADIENT', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        ..._gradient4Rows(context, cur, onChanged, onEnded),
      ],
    );
  }

  // Batch 14: a labelled dropdown over a list of names stored as a whole number in a float slot (same look as the blend-mode dropdowns).
  static Widget _slotDropdown(List<double> l, String label, int slot, List<String> names, VoidCallback onChanged, VoidCallback onEnded) {
    final int v = l[slot].round().clamp(0, names.length - 1).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          DropdownButton<int>(
            value: v,
            dropdownColor: gPalette.value.card,
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            items: [for (int i = 0; i < names.length; i++) DropdownMenuItem(value: i, child: Text(names[i]))],
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

  static Widget _slotSwitch(List<double> l, String title, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SwitchListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        value: l[slot] > 0.5,
        onChanged: (v) {
          l[slot] = v ? 1.0 : 0.0;
          onChanged();
          onEnded();
        },
      ),
    );
  }

  // Batch 14: MathOps (pass 27). Slots = class MathOps, packed at 7584 + layer * 16.
  static List<Widget> _mathOpsRows(BuildContext context, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    final l = cur.mathOps;
    return [
      _slotSwitch(l, 'MathOps', MathOps.on, onChanged, onEnded),
      _slotDropdown(l, 'Operation', MathOps.operation, MathOps.opLabels, onChanged, onEnded),
      buildSliderRow(context: context, title: 'Value', val: l[MathOps.value].clamp(0.0, 2.0).toDouble(), min: 0.0, max: 2.0, onChanged: (v) { l[MathOps.value] = v; onChanged(); }, onEnded: onEnded),
      _slotDropdown(l, 'Channel', MathOps.channel, MathOps.channelLabels, onChanged, onEnded),
      buildSliderRow(context: context, title: 'Mix', val: l[MathOps.mix].clamp(0.0, 1.0).toDouble(), min: 0.0, max: 1.0, onChanged: (v) { l[MathOps.mix] = v; onChanged(); }, onEnded: onEnded),
      _note('Applied to the whole finished frame, after the Bevel and before dither. Layers that have it on are applied in layer order.'),
    ];
  }

  // Batch 14: 4-Way Gradient (pass 28). Slots = class Gradient4Way, packed at 7744 + layer * 16. Colours use the existing colour widget (VfxSuite.colorSlot).
  static List<Widget> _gradient4Rows(BuildContext context, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    final l = cur.grad4;
    Widget pos(String title, int slot) => buildSliderRow(context: context, title: title, val: l[slot].clamp(0.0, 1.0).toDouble(), min: 0.0, max: 1.0, onChanged: (v) { l[slot] = v; onChanged(); }, onEnded: onEnded);
    return [
      _slotSwitch(l, '4-Way Gradient', Gradient4Way.on, onChanged, onEnded),
      for (int k = 0; k < 4; k++) ...[
        const SizedBox(height: 6),
        ...VfxSuite.colorSlot(context, l, Gradient4Way.pointSlot(k) + 2, 'Point ${k + 1} Colour', onChanged, onEnded),
        pos('Point ${k + 1} X', Gradient4Way.pointSlot(k)),
        pos('Point ${k + 1} Y', Gradient4Way.pointSlot(k) + 1),
      ],
      const SizedBox(height: 6),
      buildSliderRow(context: context, title: 'Mix / Opacity', val: l[Gradient4Way.mix].clamp(0.0, 1.0).toDouble(), min: 0.0, max: 1.0, onChanged: (v) { l[Gradient4Way.mix] = v; onChanged(); }, onEnded: onEnded),
      _note('Colours blend by inverse distance to the four points (0,0 = top left). Applied after MathOps, before dither.'),
    ];
  }

  // Batch 13: Global Metallic Bevel. All sliders are SmoothSliderRow (through buildSliderRow). Slot numbers = class Bevel (vfx_slots.dart), packed at 7424 + layer * 16.
  static List<Widget> _metallicBevelRows(BuildContext context, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    Widget row(String title, int slot, double min, double max) => buildSliderRow(
          context: context,
          title: title,
          val: cur.bevel[slot].clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: (v) {
            cur.bevel[slot] = v;
            onChanged();
          },
          onEnded: onEnded,
        );
    final on = cur.bevel[Bevel.on] > 0.5;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          title: const Text('Metallic Bevel', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          value: on,
          onChanged: (v) {
            cur.bevel[Bevel.on] = v ? 1.0 : 0.0;
            onChanged();
            onEnded();
          },
        ),
      ),
      row('Bevel Intensity', Bevel.intensity, 0.0, 10.0),
      row('Gloss Strength', Bevel.gloss, 0.0, 8.0),
      row('Shininess', Bevel.shininess, 1.0, 256.0),
      row('Light X (left / right)', Bevel.lightX, -1.0, 1.0),
      row('Light Y (bottom / top)', Bevel.lightY, -1.0, 1.0),
      row('Mix', Bevel.mix, 0.0, 1.0),
      _note('Applied once to the whole finished frame (after Time Slice, before dither). If several layers have it on, the first one is used.'),
    ];
  }
  // =============================================================================
  // AEReality / Shaderly - Editor Views (Part 2/3)
  // True 32-Bit Float Linear Pipeline - FX, Glows, Flares, Atmosphere & Curves
  // 100% Complete Section - Zero Feature Omissions
  // =============================================================================

  // ---------------------------------------------------------------------------
  // 6. COPIED STUFF TAB
  // ---------------------------------------------------------------------------
  static Widget buildCopiedStuffTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('COPIED STUFF (AFTER EFFECTS ANIME CC)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'RGB Warp Shift (Directional Edges)', val: cur.copiedChromaShift, min: 0.0, max: 1.0, onChanged: (v) { cur.copiedChromaShift = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Radial Chromatic Aberration (Lens, Corners)', val: cur.radialChroma, min: 0.0, max: 1.0, onChanged: (v) { cur.radialChroma = v; onChanged(); }, onEnded: onEnded),
        _note('Sapphire Edge Detect Glow moved to the SAPPHIRE tab.'),
        buildSliderRow(context: context, title: 'Pro-Mist Halation (Black Line Safe)', val: cur.copiedProMist, min: 0.0, max: 1.0, onChanged: (v) { cur.copiedProMist = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Star Sparkle / Glint Cross', val: cur.copiedStarGlint, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedStarGlint = v; onChanged(); }, onEnded: onEnded),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('INNER SKIN EDGE BLEED', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Skin Edge Bleed (Depth)', val: cur.skinEdgeBleed, min: 0.0, max: 1.5, onChanged: (v) { cur.skinEdgeBleed = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Skin Edge Bleed Width', val: cur.skinEdgeWidth, min: 0.0, max: 1.0, onChanged: (v) { cur.skinEdgeWidth = v; onChanged(); }, onEnded: onEnded),
        _fxRow(context, cur, 'Skin Edge Bleed Opacity', Fx.opEdgeBleed, 0.0, 1.0, onChanged, onEnded),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('COLOURED LINE ART', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Coloured Line Art Amount', val: cur.lineArtStrength, min: 0.0, max: 1.5, onChanged: (v) { cur.lineArtStrength = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Line Art Width', val: cur.lineArtWidth, min: 0.0, max: 1.0, onChanged: (v) { cur.lineArtWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Line Art Placement (All / Lit Areas / Skin)', val: cur.lineArtPlacement, min: 0.0, max: 1.0, onChanged: (v) { cur.lineArtPlacement = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Line Art Colour Richness', val: cur.lineArtSaturation, min: 0.0, max: 1.0, onChanged: (v) { cur.lineArtSaturation = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. GLOWS & FLARES TAB (Continuous Falloff, No Stepped Duplicates)
  // ---------------------------------------------------------------------------
  static Widget buildGlowsAndFlaresTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('SHADERLY GLOW', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Shaderly Glow Intensity', val: cur.shaderlyGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.shaderlyGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Radius', val: cur.shaderlyGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.shaderlyGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Threshold', val: cur.shaderlyGlowThreshold, min: 0.10, max: 0.90, onChanged: (v) { cur.shaderlyGlowThreshold = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Tint Hue (0 = Natural)', val: cur.shaderlyGlowTint, min: 0.0, max: 1.0, onChanged: (v) { cur.shaderlyGlowTint = v; onChanged(); }, onEnded: onEnded),
        _fxRow(context, cur, 'Shaderly Glow Opacity', Fx.opShaderly, 0.0, 1.0, onChanged, onEnded),
        _blendPicker(cur, 'Shaderly Glow blend', Fx.cbShaderly, onChanged, onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DEEP GLOW  (SAPPHIRE S_GLOW IS NOW IN THE SAPPHIRE TAB)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deep Glow Intensity', val: cur.deepGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.deepGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Radius (Rolloff: High = Wide Spread)', val: cur.deepGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.deepGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Threshold', val: cur.deepGlowThreshold, min: 0.15, max: 0.90, onChanged: (v) { cur.deepGlowThreshold = v; onChanged(); }, onEnded: onEnded),
        _fxRow(context, cur, 'Deep Glow Opacity', Fx.opDeepGlow, 0.0, 1.0, onChanged, onEnded),
        _blendPicker(cur, 'Deep Glow blend', Fx.cbDeepGlow, onChanged, onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('KAWASE PYRAMID & PRISMATIC DIFFUSE GLOW', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Kawase Glow Intensity', val: cur.kawaseGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.kawaseGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Kawase Glow Radius', val: cur.kawaseGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.kawaseGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Diffuse SP Glow (Prismatic Dispersion)', val: cur.diffuseGlow, min: 0.0, max: 1.5, onChanged: (v) { cur.diffuseGlow = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Diffuse SP Radius', val: cur.diffuseSpGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.diffuseSpGlowRadius = v; onChanged(); }, onEnded: onEnded),
        _fxRow(context, cur, 'Kawase Glow Opacity', Fx.opKawase, 0.0, 1.0, onChanged, onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('S_LIGHTWRAP', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Wrap Width', val: cur.sLightWrapWidth, min: 0.0, max: 1.0, onChanged: (v) { cur.sLightWrapWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Wrap Intensity', val: cur.sLightWrapIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.sLightWrapIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Wrap Threshold', val: cur.sLightWrapThreshold, min: 0.0, max: 1.0, onChanged: (v) { cur.sLightWrapThreshold = v; onChanged(); }, onEnded: onEnded),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Wrap Blend Mode', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Screen'),
                    selected: cur.sLightWrapBlendMode == 0.0,
                    selectedColor: accent,
                    labelStyle: TextStyle(color: cur.sLightWrapBlendMode == 0.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (s) {
                      if (s) {
                        cur.sLightWrapBlendMode = 0.0;
                        onChanged();
                        onEnded();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Linear Add'),
                    selected: cur.sLightWrapBlendMode == 1.0,
                    selectedColor: accent,
                    labelStyle: TextStyle(color: cur.sLightWrapBlendMode == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (s) {
                      if (s) {
                        cur.sLightWrapBlendMode = 1.0;
                        onChanged();
                        onEnded();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        _fxRow(context, cur, 'Light Wrap Opacity', Fx.opLightWrap, 0.0, 1.0, onChanged, onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('SOFT EDGE GLOW HALO (LINE-ART SAFE)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Edge Halo Spread', val: cur.edgeHaloRadius, min: 0.0, max: 1.5, onChanged: (v) { cur.edgeHaloRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Centre Aura', val: cur.centerAura, min: 0.0, max: 1.5, onChanged: (v) { cur.centerAura = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Horizontal Ramp', val: cur.horizontalRamp, min: 0.0, max: 1.0, onChanged: (v) { cur.horizontalRamp = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('GLOW TINT PALETTE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              {'id': 0.0, 'name': 'Natural White'},
              {'id': 1.0, 'name': 'Noble Gold'},
              {'id': 2.0, 'name': 'Cyan / Teal'},
              {'id': 3.0, 'name': 'Amber Sun'},
              {'id': 4.0, 'name': 'Blood Crimson'},
              {'id': 5.0, 'name': 'Electro Violet'},
              {'id': 6.0, 'name': 'Anime Pink'},
            ].map((t) {
              final isSel = cur.edgeGlowTint == t['id'];
              return ChoiceChip(
                label: Text(t['name'] as String),
                selected: isSel,
                selectedColor: accent,
                labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                onSelected: (s) {
                  if (s) {
                    cur.edgeGlowTint = t['id'] as double;
                    onChanged();
                    onEnded();
                  }
                },
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('ANAMORPHIC FLARES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Flare Intensity', val: cur.thinStreakIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.thinStreakIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Width / Length', val: cur.thinStreakWidth, min: 0.05, max: 2.0, onChanged: (v) { cur.thinStreakWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Colour Respect (Low = Transparent White Haze / High = Colours From The Video)', val: cur.flareSceneTint, min: 0.0, max: 1.0, onChanged: (v) { cur.flareSceneTint = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Source Threshold (Higher = Fewer Flares)', val: cur.flareThreshold, min: 0.0, max: 1.0, onChanged: (v) { cur.flareThreshold = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Origin (0 Highlight / 1 Frame Edges Inward)', val: cur.flareOrigin, min: 0.0, max: 1.0, onChanged: (v) { cur.flareOrigin = v; cur.thinStreakFromEdge = false; onChanged(); }, onEnded: onEnded),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const PageStorageKey<String>('flare_advanced_settings'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            iconColor: Colors.white54,
            collapsedIconColor: Colors.white38,
            title: const Text('ADVANCED FLARE SETTINGS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
            children: [
              buildSliderRow(context: context, title: 'Flare Opacity', val: cur.thinStreakOpacity, min: 0.0, max: 1.0, onChanged: (v) { cur.thinStreakOpacity = v; onChanged(); }, onEnded: onEnded),
              buildSliderRow(context: context, title: 'Flare Softness (Hard Flat Edge to Soft Blurred Edge)', val: cur.thinStreakSoftness, min: 0.0, max: 1.0, onChanged: (v) { cur.thinStreakSoftness = v; onChanged(); }, onEnded: onEnded),
              buildSliderRow(context: context, title: 'Flare Spacing (Min Distance Between Flares)', val: cur.flareSpacing, min: 0.0, max: 0.5, onChanged: (v) { cur.flareSpacing = v; onChanged(); }, onEnded: onEnded),
              buildSliderRow(context: context, title: 'Flare Thickness', val: cur.flareThickness, min: 0.0, max: 1.0, onChanged: (v) { cur.flareThickness = v; onChanged(); }, onEnded: onEnded),
              buildSliderRow(context: context, title: 'Flare Falloff (Long Fade to Short)', val: cur.flareFalloff, min: 0.0, max: 1.0, onChanged: (v) { cur.flareFalloff = v; onChanged(); }, onEnded: onEnded),
              buildSliderRow(context: context, title: 'Flare White Core', val: cur.flareCoreWhite, min: 0.0, max: 1.0, onChanged: (v) { cur.flareCoreWhite = v; onChanged(); }, onEnded: onEnded),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 8. ATMOSPHERE & DEBAND TAB (Restored Debanding & Full DOF Controls)
  // ---------------------------------------------------------------------------
  static Widget buildAtmosphereTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DEBANDING FILTER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deband Radius', val: cur.debandRadius, min: 0.0, max: 2.0, onChanged: (v) { cur.debandRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deband Threshold', val: cur.debandThreshold, min: 0.005, max: 0.08, onChanged: (v) { cur.debandThreshold = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DEPTH OF FIELD', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Text(
            '1. Pick a shape.  2. Switch FOCUS PREVIEW on: the GREEN area stays sharp, everything else gets blurred.  '
            '3. Move FOCAL POSITION onto your subject, size the sharp zone, then raise BLUR AMOUNT.',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Shape', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ChoiceChip(
                label: const Text('Band (sharp line)'),
                selected: cur.dofMode == 0.0,
                selectedColor: accent,
                labelStyle: TextStyle(color: cur.dofMode == 0.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                onSelected: (sel) {
                  if (sel) {
                    cur.dofMode = 0.0;
                    onChanged();
                    onEnded();
                  }
                },
              ),
              ChoiceChip(
                label: const Text('Spot (sharp circle)'),
                selected: cur.dofMode == 1.0,
                selectedColor: accent,
                labelStyle: TextStyle(color: cur.dofMode == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                onSelected: (sel) {
                  if (sel) {
                    cur.dofMode = 1.0;
                    onChanged();
                    onEnded();
                  }
                },
              ),
              FilterChip(
                label: const Text('FOCUS PREVIEW'),
                selected: cur.fx[Fx.dofPreview] > 0.5,
                selectedColor: Colors.greenAccent,
                labelStyle: TextStyle(color: cur.fx[Fx.dofPreview] > 0.5 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                onSelected: (sel) {
                  cur.fx[Fx.dofPreview] = sel ? 1.0 : 0.0;
                  onChanged();
                  onEnded();
                },
              ),
            ],
          ),
        ),
        buildSliderRow(context: context, title: 'Focal Position (0 = top, 1 = bottom)', val: cur.dofFocus, min: 0.0, max: 1.0, onChanged: (v) { cur.dofFocus = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Sharp Zone Size', val: cur.dofRange, min: 0.05, max: 0.80, onChanged: (v) { cur.dofRange = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Blur Transition (hard to soft)', val: cur.dofFalloff, min: 0.05, max: 0.60, onChanged: (v) { cur.dofFalloff = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Blur Amount (aperture)', val: cur.depthOfField, min: 0.0, max: 2.0, onChanged: (v) { cur.depthOfField = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Bokeh Highlights', val: cur.dofBokeh, min: 0.0, max: 2.0, onChanged: (v) { cur.dofBokeh = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'DOF Opacity', val: cur.fx[Fx.opDof], min: 0.0, max: 1.0, onChanged: (v) { cur.fx[Fx.opDof] = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('ATMOSPHERIC VOLUMETRIC SCATTER & FOG', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Light Shafts (God Rays)', val: cur.bslaGodRays, min: 0.0, max: 1.5, onChanged: (v) { cur.bslaGodRays = v; onChanged(); }, onEnded: onEnded),
        ..._fogV2Rows(context, cur, onChanged, onEnded),
        buildSliderRow(context: context, title: 'Bloom Haze', val: cur.bslaBloomHaze, min: 0.0, max: 1.5, onChanged: (v) { cur.bslaBloomHaze = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Light Scatter', val: cur.bslFogScatter, min: 0.0, max: 1.5, onChanged: (v) { cur.bslFogScatter = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('OPTICAL HALATION & TEXTURE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Halation Radius', val: cur.halationRadius, min: 0.0, max: 1.5, onChanged: (v) { cur.halationRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Halation Warmth', val: cur.halationWarmth, min: 0.0, max: 1.5, onChanged: (v) { cur.halationWarmth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Halation Strength', val: cur.halationStrength, min: 0.0, max: 1.5, onChanged: (v) { cur.halationStrength = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Halation Highlight Threshold', val: cur.halationThreshold, min: 0.25, max: 0.95, onChanged: (v) { cur.halationThreshold = v; onChanged(); }, onEnded: onEnded),
        _fxRow(context, cur, 'Halation Opacity', Fx.opHalation, 0.0, 1.0, onChanged, onEnded),
        _blendPicker(cur, 'Halation blend', Fx.cbHalation, onChanged, onEnded),
        buildSliderRow(context: context, title: 'Film Grain (Midtone Responsive)', val: cur.filmGrain, min: 0.0, max: 1.0, onChanged: (v) { cur.filmGrain = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Denoise Filter (Edge-Aware Bilateral)', val: cur.denoise, min: 0.0, max: 1.0, onChanged: (v) { cur.denoise = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 9. CURVES TAB (C1 Monotone Cubic Math - Clamped, Never Inverts)
  // ---------------------------------------------------------------------------

  // ===========================================================================
  // BATCH 4 UI HELPERS (Duotone, Optical Diffusion, Pro Mist, Overall Blend, Edge Softness, Fog v2, per-effect opacity)
  // ===========================================================================
  static Widget _hdr(String t) => ShelfHeader(t); // batch 7: shelf-style section title

  static Widget _note(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(t, style: const TextStyle(color: Colors.white24, fontSize: 10)),
      );

  static Widget _fxRow(BuildContext c, AdjustmentLayer cur, String title, int slot, double min, double max,
      VoidCallback onChanged, VoidCallback onEnded) {
    return buildSliderRow(
      context: c,
      title: title,
      val: cur.fx[slot].clamp(min, max).toDouble(),
      min: min,
      max: max,
      onChanged: (v) {
        cur.fx[slot] = v;
        onChanged();
      },
      onEnded: onEnded,
    );
  }

  static Widget _fxChips(AdjustmentLayer cur, String label, int slot, List<String> names, VoidCallback onChanged,
      VoidCallback onEnded) {
    final accent = gCustomAccentColor.value;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          for (int i = 0; i < names.length; i++)
            ChoiceChip(
              label: Text(names[i]),
              selected: cur.fx[slot].round() == i,
              selectedColor: accent,
              labelStyle: TextStyle(color: cur.fx[slot].round() == i ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              onSelected: (sel) {
                if (sel) {
                  cur.fx[slot] = i.toDouble();
                  onChanged();
                  onEnded();
                }
              },
            ),
        ],
      ),
    );
  }

  static Widget _fxToggle(AdjustmentLayer cur, String label, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    final on = cur.fx[slot] > 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SwitchListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        value: on,
        onChanged: (v) {
          cur.fx[slot] = v ? 1.0 : 0.0;
          onChanged();
          onEnded();
        },
      ),
    );
  }

  static const List<String> _blendLabels = [
    'Normal', 'Screen', 'Linear Add', 'Overlay', 'Soft Light', 'Multiply', 'Add', 'Linear Dodge',
    'Darken', 'Lighten', 'Color Dodge', 'Color Burn', 'Hard Light', 'Difference', 'Exclusion',
    'Hue', 'Saturation', 'Color', 'Luminosity', 'Linear Burn', 'Subtract',
  ];

  /// Custom blend INSIDE one effect (independent of the layer blend mode). 0 = the effect's own default compositing.
  static Widget _blendPicker(AdjustmentLayer cur, String label, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    final int v = cur.fx[slot].round().clamp(0, _blendLabels.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          DropdownButton<int>(
            value: v,
            dropdownColor: gPalette.value.card,
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            items: [
              const DropdownMenuItem(value: 0, child: Text('Default')),
              for (int i = 0; i < _blendLabels.length; i++) DropdownMenuItem(value: i + 1, child: Text(_blendLabels[i])),
            ],
            onChanged: (m) {
              if (m != null) {
                cur.fx[slot] = m.toDouble();
                onChanged();
                onEnded();
              }
            },
          ),
        ],
      ),
    );
  }

  // ---- colour slot: swatch + hue / saturation / brightness sliders (packed 0xRRGGBB in a float slot) ----
  static List<double> _packedToHsv(double packed) {
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
      h *= 60.0;
      if (h < 0) h += 360.0;
    }
    return [h, mx <= 0 ? 0.0 : d / mx, mx];
  }

  static double _hsvToPacked(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - ((h / 60.0) % 2.0 - 1.0).abs());
    final m = v - c;
    double r = 0, g = 0, b = 0;
    final hh = (h % 360.0) / 60.0;
    if (hh < 1) { r = c; g = x; }
    else if (hh < 2) { r = x; g = c; }
    else if (hh < 3) { g = c; b = x; }
    else if (hh < 4) { g = x; b = c; }
    else if (hh < 5) { r = x; b = c; }
    else { r = c; b = x; }
    final ri = ((r + m) * 255).round().clamp(0, 255), gi = ((g + m) * 255).round().clamp(0, 255), bi = ((b + m) * 255).round().clamp(0, 255);
    return ((ri << 16) | (gi << 8) | bi).toDouble();
  }

  static Widget _colorSlot(BuildContext c, AdjustmentLayer cur, String label, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    final hsv = _packedToHsv(cur.fx[slot] < 0 ? 0.0 : cur.fx[slot]);
    void setHsv(double h, double s, double v) {
      cur.fx[slot] = _hsvToPacked(h, s, v);
      onChanged();
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | (cur.fx[slot] < 0 ? 0 : cur.fx[slot].round())),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          buildSliderRow(context: c, title: 'Hue', val: hsv[0], min: 0.0, max: 360.0, onChanged: (v) => setHsv(v, hsv[1], hsv[2]), onEnded: onEnded),
          buildSliderRow(context: c, title: 'Saturation', val: hsv[1], min: 0.0, max: 1.0, onChanged: (v) => setHsv(hsv[0], v, hsv[2]), onEnded: onEnded),
          buildSliderRow(context: c, title: 'Brightness', val: hsv[2], min: 0.0, max: 1.0, onChanged: (v) => setHsv(hsv[0], hsv[1], v), onEnded: onEnded),
        ],
      ),
    );
  }

  // name, shadow, [mid or -1], highlight (0xRRGGBB)
  static const List<List<dynamic>> _duoCombos = [
    ['Midnight / Peach', 0x14233A, -1, 0xF4B183],
    ['Teal / Orange', 0x0B3C49, -1, 0xFF9A3C],
    ['Magenta / Cyan', 0x3A0CA3, -1, 0x4CC9F0],
    ['Crimson / Gold', 0x4A0D16, -1, 0xFFD166],
    ['Indigo / Mint', 0x1B1464, -1, 0xA8F0D0],
    ['Forest / Cream', 0x16352A, -1, 0xF3EBCF],
    ['Noir / Ice', 0x050608, -1, 0xCFE8FF],
    ['Sepia', 0x2B1A0F, -1, 0xF0DDB8],
    ['Cyber (3 colour)', 0x1A0638, 0xF0289B, 0x47E6FF],
    ['Sunset (3 colour)', 0x141B4D, 0xD9467D, 0xFFC857],
    ['Ocean (3 colour)', 0x03122B, 0x1B7FA5, 0xE6F7F1],
    ['Rose Gold', 0x3B1D2A, -1, 0xF2C6B0],
    ['Toxic', 0x0A1F0F, -1, 0xC6FF3D],
    ['Lava (3 colour)', 0x120505, 0xC4281C, 0xFFD27A],
    ['Dusk (3 colour)', 0x1D1646, 0x7B5EA7, 0xF7B7A3],
    ['Frieren Frost', 0x14223A, -1, 0xDDEBFF],
  ];

  static List<Widget> _duotoneRows(BuildContext c, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    final accent = gCustomAccentColor.value;
    final on = cur.fx[Fx.duoOn] > 0.5;
    return [
      _hdr('DUOTONE'),
      _note('Maps the picture\'s brightness onto a shadow -> (mid) -> highlight colour ramp. Add a middle colour for a 3-colour tritone.'),
      _fxToggle(cur, 'Duotone On', Fx.duoOn, onChanged, onEnded),
      if (on) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final combo in _duoCombos)
                ActionChip(
                  backgroundColor: gPalette.value.control,
                  avatar: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(colors: [
                        Color(0xFF000000 | (combo[1] as int)),
                        if ((combo[2] as int) >= 0) Color(0xFF000000 | (combo[2] as int)),
                        Color(0xFF000000 | (combo[3] as int)),
                      ]),
                    ),
                  ),
                  label: Text(combo[0] as String, style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    cur.fx[Fx.duoShadow] = (combo[1] as int).toDouble();
                    cur.fx[Fx.duoMid] = (combo[2] as int).toDouble();
                    cur.fx[Fx.duoHigh] = (combo[3] as int).toDouble();
                    onChanged();
                    onEnded();
                  },
                ),
            ],
          ),
        ),
        _colorSlot(c, cur, 'Shadow Colour', Fx.duoShadow, onChanged, onEnded),
        SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: const Text('Middle Colour (3-colour ramp)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                value: cur.fx[Fx.duoMid] >= 0.0,
                onChanged: (v) {
                  cur.fx[Fx.duoMid] = v ? 0x7B5EA7.toDouble() : -1.0;
                  onChanged();
                  onEnded();
                },
              ),
        if (cur.fx[Fx.duoMid] >= 0.0) ...[
          _colorSlot(c, cur, 'Middle Colour', Fx.duoMid, onChanged, onEnded),
          _fxRow(c, cur, 'Middle Position', Fx.duoMidPos, 0.05, 0.95, onChanged, onEnded),
        ],
        _colorSlot(c, cur, 'Highlight Colour', Fx.duoHigh, onChanged, onEnded),
        _fxChips(cur, 'Brightness source', Fx.duoMode, const ['Luma', 'Lightness (Oklab)', 'Brightest channel'], onChanged, onEnded),
        _fxRow(c, cur, 'Contrast', Fx.duoContrast, -1.0, 1.0, onChanged, onEnded),
        _fxRow(c, cur, 'Gamma (mid shift)', Fx.duoGamma, 0.3, 3.0, onChanged, onEnded),
        _fxRow(c, cur, 'Posterise Steps (0 = smooth)', Fx.duoBands, 0.0, 12.0, onChanged, onEnded),
        _fxRow(c, cur, 'Keep Original Lightness', Fx.duoKeepLight, 0.0, 1.0, onChanged, onEnded),
        _fxToggle(cur, 'Invert Ramp', Fx.duoInvert, onChanged, onEnded),
        _fxRow(c, cur, 'Mix With Original', Fx.duoMix, 0.0, 1.0, onChanged, onEnded),
      ],
      _fxRow(c, cur, 'Duotone Opacity', Fx.opDuotone, 0.0, 1.0, onChanged, onEnded),
      _blendPicker(cur, 'Duotone blend', Fx.cbDuotone, onChanged, onEnded),
    ];
  }

  static List<Widget> _magicBatch4Rows(BuildContext c, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    return [
      ..._duotoneRows(c, cur, onChanged, onEnded),

      _hdr('OPTICAL DIFFUSION'),
      _note('Softens highlights into a cinematic glow and removes digital edge sharpness, without blurring the picture.'),
      _fxRow(c, cur, 'Diffusion Strength', Fx.diffAmt, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Highlight Threshold', Fx.diffThreshold, 0.0, 1.5, onChanged, onEnded),
      _fxRow(c, cur, 'Diffusion Radius', Fx.diffRadius, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Keep Original Sharp Frame', Fx.diffMix, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Warmth (cool - warm)', Fx.diffWarmth, -1.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Optical Diffusion Opacity', Fx.opDiffusion, 0.0, 1.0, onChanged, onEnded),
      _blendPicker(cur, 'Optical Diffusion blend', Fx.cbDiffusion, onChanged, onEnded),

      _hdr('PRO MIST'),
      _note('Black Pro-Mist style: wide tinted halation bloom, milky blacks, softer contrast.'),
      _fxRow(c, cur, 'Mist Strength', Fx.mistAmt, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Highlight Threshold', Fx.mistThreshold, 0.0, 1.5, onChanged, onEnded),
      _fxRow(c, cur, 'Mist Radius', Fx.mistRadius, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Halation Tint (neutral - red/orange)', Fx.mistTint, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Black Lift', Fx.mistLift, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Pro Mist Opacity', Fx.opProMist, 0.0, 1.0, onChanged, onEnded),
      _blendPicker(cur, 'Pro Mist blend', Fx.cbProMist, onChanged, onEnded),

      _hdr('OVERALL BLEND (two colour regions into one look)'),
      _note('Pick the two hues to merge (e.g. a red side and a blue side). UNIFY pulls both to one in-between colour, GRADIENT melts the border into a smooth transition.'),
      _fxRow(c, cur, 'Blend Strength', Fx.obStrength, 0.0, 1.0, onChanged, onEnded),
      _fxChips(cur, 'Result', Fx.obMode, const ['Unify to one colour', 'Smooth gradient'], onChanged, onEnded),
      _colorSlotHue(c, cur, 'Region A hue', Fx.obHueA, onChanged, onEnded),
      _colorSlotHue(c, cur, 'Region B hue', Fx.obHueB, onChanged, onEnded),
      _fxRow(c, cur, 'Hue Range (width)', Fx.obWidth, 0.02, 0.5, onChanged, onEnded),
      _fxRow(c, cur, 'Edge Softness of Regions / Transition Size', Fx.obSoft, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Keep Luminance', Fx.obKeepLum, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Output Saturation', Fx.obSat, 0.0, 2.0, onChanged, onEnded),
      _fxRow(c, cur, 'Overall Blend Opacity', Fx.opBlendFx, 0.0, 1.0, onChanged, onEnded),

      _hdr('EDGE SOFTNESS'),
      _note('Softens edges only, with a direction. X / Y lean the softening to one side of every edge, Z favours bright (+) or dark (-) areas.'),
      _fxRow(c, cur, 'Softness Amount', Fx.esAmount, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Width', Fx.esWidth, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Falloff (soft - selective)', Fx.esFalloff, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'X Offset (left - right)', Fx.esX, -1.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Y Offset (up - down)', Fx.esY, -1.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Z Depth (dark - bright)', Fx.esZ, -1.0, 1.0, onChanged, onEnded),
      _fxToggle(cur, 'X axis active', Fx.esAxisX, onChanged, onEnded),
      _fxToggle(cur, 'Y axis active', Fx.esAxisY, onChanged, onEnded),
      _fxToggle(cur, 'Z axis active', Fx.esAxisZ, onChanged, onEnded),
      _fxRow(c, cur, 'Edge Softness Opacity', Fx.opEdgeSoft, 0.0, 1.0, onChanged, onEnded),

      // Batch 17A: Curves Opacity moved to the CURVES tab (directly under the curve editor).
      _hdr('GRADIENT MAP OPACITY & BLEND'),
      _note('The gradient map itself is picked in the GRADIENT MAPS tab; this is its opacity and custom blend (Default keeps the effect as it was).'),
      _fxRow(c, cur, 'Gradient Map Opacity', Fx.opGradMap, 0.0, 1.0, onChanged, onEnded),
      _blendPicker(cur, 'Gradient Map blend', Fx.cbGradMap, onChanged, onEnded),
    ];
  }

  /// Hue picker (0..1 around the HSV wheel) with a live swatch.
  static Widget _colorSlotHue(BuildContext c, AdjustmentLayer cur, String label, int slot, VoidCallback onChanged, VoidCallback onEnded) {
    final packed = _hsvToPacked(cur.fx[slot] * 360.0, 1.0, 1.0).round();
    return Row(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 14),
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: Color(0xFF000000 | packed), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white24)),
        ),
        Expanded(child: _fxRow(c, cur, label, slot, 0.0, 1.0, onChanged, onEnded)),
      ],
    );
  }

  static List<Widget> _fogV2Rows(BuildContext c, AdjustmentLayer cur, VoidCallback onChanged, VoidCallback onEnded) {
    return [
      _note('FOG: optical depth from a drifting cloud field, light from bright areas spreads into the fog, per-channel extinction.'),
      _fxRow(c, cur, 'Fog Density', Fx.fogDensity, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Spread Distance (light scatter)', Fx.fogSpread, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Cloud Size', Fx.fogScale, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Height (0 = ground fog, 0.5 = even, 1 = high mist)', Fx.fogHeight, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Reacts To Brightness (bright areas punch through)', Fx.fogReact, 0.0, 1.0, onChanged, onEnded),
      _fxRow(c, cur, 'Drift Speed', Fx.fogDrift, 0.0, 3.0, onChanged, onEnded),
      _colorSlot(c, cur, 'Fog Colour', Fx.fogColor, onChanged, onEnded),
      _fxRow(c, cur, 'Fog Opacity', Fx.opFog, 0.0, 1.0, onChanged, onEnded),
      _blendPicker(cur, 'Fog blend', Fx.cbFog, onChanged, onEnded),
    ];
  }

  static Widget buildCurvesTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required int selectedCurveChannel,
    required ValueChanged<int> onChannelChanged,
    required VoidCallback onChanged,
    required VoidCallback onResetCurve,
    VoidCallback? onEnded, // batch 17A: for the Curves Opacity slider (null = the slider still moves, nothing is committed on release)
  }) {
    final int ch = selectedCurveChannel.clamp(0, 3);
    const colors = [Colors.white, Colors.redAccent, Colors.greenAccent, Colors.blueAccent];
    const names = ['RGB', 'RED', 'GREEN', 'BLUE'];
    final xy = cur.curveXY(ch);
    final nPts = xy.length ~/ 2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(names[i]),
                selected: ch == i,
                selectedColor: colors[i],
                onSelected: (sel) {
                  if (sel) onChannelChanged(i);
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        FreeCurveEditor(
          key: ValueKey('curve_${cur.id}_$ch'),
          xy: xy,
          curveColor: colors[ch],
          onChanged: (pts) {
            cur.setCurveXY(ch, pts);
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '$nPts points  -  tap empty space to add  -  drag to move  -  double-tap a point to delete',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Curves run in display space like After Effects. Points can never cross, so the curve cannot clip or invert.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () {
                cur.resetCurveXY(ch);
                onResetCurve();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white38),
              label: Text('Reset ${names[ch]}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                for (int i = 0; i < 4; i++) {
                  cur.resetCurveXY(i);
                }
                onResetCurve();
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Colors.white38),
              label: const Text('Reset all', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _hdr('CURVES OPACITY'),
        _note('Opacity of the curves effect (on top of the layer opacity). The curves have no custom blend slot.'),
        _fxRow(context, cur, 'Curves Opacity', Fx.opCurves, 0.0, 1.0, onChanged, onEnded ?? () {}),
      ],
    );
  }
  // =============================================================================
  // AEReality / Shaderly - Editor Views (Part 3/3)
  // True 32-Bit Float Linear Pipeline - WIS 2026 Presets, Timeline & Text Suite
  // 100% Complete Section - Zero Feature Omissions
  // =============================================================================

  // ---------------------------------------------------------------------------
  // PRESET ENGINE (Frieren v3 + Frieren Upd, extracted from the .json presets)
  // ---------------------------------------------------------------------------
  static void applyPresetLogic(ProjectData project, String name) {
    project.layers.clear();

    switch (name.toLowerCase()) {
      // 1. FRIEREN V3
      case 'frieren v3':
        project.tonemapMode = 2.0;
        project.deepTeal = 0.15;
        project.magicCurves = 0.0;
        project.layers.add(AdjustmentLayer(
          id: 'default',
          name: 'Base Grade',
          saturation: 0.85,
          splitToneShadowHue: 0.54,
          splitToneShadowSat: 0.22,
          splitToneHighHue: 0.52,
          splitToneHighSat: 0.14,
          curveMaster: [0.0, 0.14, 0.42, 0.81, 1.0],
          curveRed: [0.0, 0.235, 0.47, 0.745, 1.0],
          curveBlue: [0.0, 0.245, 0.49, 0.77, 1.0],
          cosmoCleanHighlight: 0.2,
          deepTeal: 0.2,
          hsSat: [0.08, 0.0, -0.15, -0.25, 0.15, -0.35, -0.45, -0.4],
          hsHue: [0.04, 0.0, 0.0, 0.0, 0.0, -0.1, -0.1, -0.05],
          hsLum: [0.0, 0.0, 0.0, 0.0, 0.05, -0.15, -0.15, -0.2],
          hsSoftness: 0.8,
          coloristaSatShadows: -0.2,
          coloristaSatMids: 0.2,
          coloristaSatHighs: 0.1,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_line_art',
          name: 'Line Art Definition',
          darkOutlines: 0.35,
          sLiningOpacity: 0.15,
          edgeDarken: 0.1,
          edgeDarkenBlur: 0.35,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_edge_halo',
          name: 'Edge Halo',
          opacity: 0.6,
          edgeGlowTint: 0.2,
          edgeHaloRadius: 0.06,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_bloom',
          name: 'Soft Bloom',
          opacity: 0.5,
          deepGlowIntensity: 0.07,
          deepGlowRadius: 0.45,
          deepGlowThreshold: 0.85,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_finish',
          name: 'Finish + Anti-Band',
          vignette: 0.1,
          bilateralIntensity: 0.1,
          bilateralRange: 0.1,
          debandRadius: 3.0,
          filmGrain: 0.015,
          radialChroma: 0.05,
          clarity: 0.05,
          unsharpRadius: 1.2,
          unsharpAmount: 0.15,
        ));
        break;

      // 3. SOFT COLD CC (batch 4): cool, gentle lift, muted contrast. Built from the existing tools + Curves v2.
      case 'soft cold cc':
        project.tonemapMode = 2.0;
        project.layers.add(AdjustmentLayer(
          id: 'soft_cold',
          name: 'Soft Cold CC',
          contrast: 0.94,
          saturation: 0.90,
          splitToneShadowHue: 0.58,
          splitToneShadowSat: 0.30,
          splitToneHighHue: 0.54,
          splitToneHighSat: 0.10,
          splitToneBalance: 0.0,
          curveXYM: const [0.0, 0.04, 0.28, 0.30, 0.62, 0.64, 1.0, 0.97],
          curveXYB: const [0.0, 0.03, 0.5, 0.52, 1.0, 1.0],
          fx: (Fx.defaults()
            ..[Fx.mistAmt] = 0.22
            ..[Fx.mistThreshold] = 0.55
            ..[Fx.mistTint] = 0.0
            ..[Fx.mistLift] = 0.25),
        ));
        break;

      // 4. FOGGY CC (batch 4): hazy, milky blacks, low contrast, slight cool shift.
      case 'foggy cc':
        project.tonemapMode = 2.0;
        project.layers.add(AdjustmentLayer(
          id: 'foggy',
          name: 'Foggy CC',
          contrast: 0.86,
          saturation: 0.82,
          splitToneShadowHue: 0.56,
          splitToneShadowSat: 0.18,
          splitToneHighHue: 0.12,
          splitToneHighSat: 0.05,
          curveXYM: const [0.0, 0.12, 0.30, 0.34, 0.65, 0.66, 1.0, 0.95],
          fx: (Fx.defaults()
            ..[Fx.fogDensity] = 0.28
            ..[Fx.fogSpread] = 0.6
            ..[Fx.fogHeight] = 0.35
            ..[Fx.fogReact] = 0.4
            ..[Fx.fogColor] = 0xBFCBD6.toDouble()
            ..[Fx.mistAmt] = 0.30
            ..[Fx.mistThreshold] = 0.45
            ..[Fx.mistTint] = 0.0
            ..[Fx.mistLift] = 0.45),
        ));
        break;

      // 2. FRIEREN UPD
      case 'frieren upd':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.15;
        project.magicCurves = 0.0;
        project.layers.add(AdjustmentLayer(
          id: 'layer_line_art',
          name: 'Line Art Definition',
          saturation: 0.7699839497366111,
          darkOutlines: 0.35,
          sLiningOpacity: 0.15,
          edgeDarken: 0.1,
          edgeDarkenBlur: 0.35,
          skinEdgeBleed: 1.4746308096466199,
          skinEdgeWidth: 0.9901006228050921,
          deepTeal: 0.7460543102502194,
          magicCurves: 0.6040223400460931,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_edge_halo',
          name: 'Edge Halo',
          opacity: 0.7110938850086407,
          contrast: 1.025339867756804,
          saturation: 0.607783691834943,
          debandRadius: 1.0227961753731343,
          edgeGlowTint: 0.1,
          shaderlyGlowIntensity: 0.2758073145302897,
          clarity: -0.09994718503072875,
          clarityRadius: 0.4465179845258999,
          skinEdgeBleed: 1.4483279260864794,
          skinEdgeWidth: 0.9673061622036874,
          copiedProMist: 0.9076869787093942,
          hsSat: [0.0, 0.0, 0.0, 0.0, 0.8368219549127344, -0.19110959270631311, 0.0, 0.0],
          coloristaLiftX: 0.020848214285714258,
          coloristaLiftY: -0.10042410714286688,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_1791189154471',
          name: 'Layer 4',
          blendMode: LayerBlendMode.softLight,
          edgeHaloRadius: 0.033260569852941166,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'layer_finish',
          name: 'Finish + Anti-Band',
          vignette: 0.1,
          bilateralIntensity: 0.1,
          bilateralRange: 0.1,
          debandRadius: 3.0,
          filmGrain: 0.015,
          radialChroma: 0.05,
          clarity: 0.05,
          unsharpRadius: 1.2,
          unsharpAmount: 0.15,
        ));
        break;

      default:
        // Unknown name -> neutral base layer
        project.layers.add(AdjustmentLayer(id: 'neutral_base', name: 'Base Grade'));
        break;
    }

    project.activeLayerIndex = 0;
  }

  // ---------------------------------------------------------------------------
  // UNSHARP MASK DRAWER & PRESET HELPERS
  // ---------------------------------------------------------------------------
  static void showUnsharpMaskDrawer(BuildContext context, AdjustmentLayer cur, VoidCallback onUpdated) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101016),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('UNSHARP MASK', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 14),
              buildSliderRow(context: context, title: 'Amount', val: cur.unsharpAmount, min: 0.0, max: 2.0, onChanged: (v) { setModal(() => cur.unsharpAmount = v); onUpdated(); }),
              buildSliderRow(context: context, title: 'Radius', val: cur.unsharpRadius, min: 0.0, max: 5.0, onChanged: (v) { setModal(() => cur.unsharpRadius = v); onUpdated(); }),
              buildSliderRow(context: context, title: 'Threshold', val: cur.unsharpThreshold, min: 0.0, max: 0.5, onChanged: (v) { setModal(() => cur.unsharpThreshold = v); onUpdated(); }),
            ],
          ),
        ),
      ),
    );
  }

  static void applyBslOverlay({required ProjectData project, required bool active}) {
    project.layers.removeWhere((l) => l.id == 'bsl_atmospheric_overlay_layer');
    if (active) {
      project.layers.add(AdjustmentLayer(
        id: 'bsl_atmospheric_overlay_layer',
        name: 'BSL Atmospheric Mist',
        blendMode: LayerBlendMode.screen,
        opacity: 0.55,
        bslaGodRays: 0.25,
        bslaFogDensity: 0.24,
        bslaBloomHaze: 0.32,
        bslFogScatter: 0.28,
        deepGlowIntensity: 0.18,
        deepGlowRadius: 0.45,
      ));
    }
  }

  static void clearPresetToNeutral(ProjectData project) {
    project.layers.clear();
    project.layers.add(AdjustmentLayer(
      id: 'neutral_base',
      name: 'Base Grade',
      opacity: 1.0,
      contrast: 1.0,
      saturation: 1.0,
      brightness: 0.0,
      blendMode: LayerBlendMode.normal,
    ));
    project.activeLayerIndex = 0;
  }

  // ---------------------------------------------------------------------------
  // 10. TIMELINE OPTIMIZER TAB (3-LAYER SEQUENTIAL TIMELINE)
  // ---------------------------------------------------------------------------
  static String formatTimestampMs(double seconds) {
    final int totalMs = (seconds * 1000).toInt();
    final int mins = totalMs ~/ 60000;
    final int secs = (totalMs % 60000) ~/ 1000;
    final int ms = totalMs % 1000;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  static Widget buildTimelineOptimizerTab({
    required BuildContext context,
    required ProjectData project,
    required double videoDuration,
    required double currentPosition,
    required VoidCallback onChanged,
  }) {
    final accent = gCustomAccentColor.value;

    return StatefulBuilder(
      builder: (context, setTabState) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: project.enableTimelineSegments ? accent.withOpacity(0.18) : gPalette.value.control,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: project.enableTimelineSegments ? accent : Colors.white10,
                  width: project.enableTimelineSegments ? 1.8 : 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timeline_rounded, color: project.enableTimelineSegments ? accent : Colors.white54, size: 24),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Apply CC Only to Segments',
                            style: TextStyle(
                              color: project.enableTimelineSegments ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const Text(
                            'Leave collaborator sections untouched (Up to 3 layers)',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Switch(
                    value: project.enableTimelineSegments,
                    activeColor: accent,
                    onChanged: (val) {
                      project.enableTimelineSegments = val;
                      onChanged();
                      setTabState(() {});
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF101016),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'INTERNAL VIDEO SCRUBBER',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                      Text(
                        '${formatTimestampMs(currentPosition)} / ${formatTimestampMs(videoDuration)}',
                        style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.0,
                      activeTrackColor: accent,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: accent,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: currentPosition.clamp(0.0, videoDuration),
                      min: 0.0,
                      max: videoDuration > 0.0 ? videoDuration : 1.0,
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ACTIVE SEGMENT LAYERS (${project.timelineSegments.length} / 3)',
                  style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                ElevatedButton.icon(
                  onPressed: project.timelineSegments.length >= 3
                      ? null
                      : () {
                          double start = 0.0;
                          if (project.timelineSegments.isNotEmpty) {
                            start = project.timelineSegments.last.endTime;
                          }
                          start = start.clamp(0.0, videoDuration);
                          double end = (start + 4.0).clamp(0.0, videoDuration);
                          if (end <= start) end = (start + 1.0).clamp(0.0, videoDuration);

                          project.timelineSegments.add(
                            TimelineClipSegment(
                              id: 'seg_${DateTime.now().millisecondsSinceEpoch}',
                              name: 'Layer ${project.timelineSegments.length + 1}',
                              startTime: start,
                              endTime: end,
                              layers: project.layers.map((l) => l.clone()).toList(),
                              tonemapMode: project.tonemapMode,
                            ),
                          );
                          project.activeTimelineSegmentIndex = project.timelineSegments.length - 1;
                          onChanged();
                          setTabState(() {});
                        },
                  icon: const Icon(Icons.add_rounded, size: 16, color: Colors.black),
                  label: const Text('ADD LAYER', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: project.timelineSegments.length >= 3 ? Colors.white24 : accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (project.timelineSegments.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: gPalette.value.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: const Center(
                  child: Text(
                    'No timeline layers added yet.\nTap "ADD LAYER" (up to 3) to stretch CC ranges across the video without touching collaborator parts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                  ),
                ),
              )
            else
              ...List.generate(project.timelineSegments.length, (idx) {
                final seg = project.timelineSegments[idx];
                final isSelected = project.activeTimelineSegmentIndex == idx;

                return AnimatedRainbowBorderContainer(
                  isActive: isSelected,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: gPalette.value.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (project.activeTimelineSegmentIndex < project.timelineSegments.length) {
                                  project.timelineSegments[project.activeTimelineSegmentIndex].layers =
                                      project.layers.map((l) => l.clone()).toList();
                                  project.timelineSegments[project.activeTimelineSegmentIndex].tonemapMode =
                                      project.tonemapMode;
                                }

                                project.activeTimelineSegmentIndex = idx;
                                project.layers = seg.layers.map((l) => l.clone()).toList();
                                project.tonemapMode = seg.tonemapMode;
                                onChanged();
                                setTabState(() {});
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.layers_rounded,
                                    color: isSelected ? accent : Colors.white54,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    seg.name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'EDITING',
                                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Switch(
                                  value: seg.isEnabled,
                                  activeColor: accent,
                                  onChanged: (en) {
                                    seg.isEnabled = en;
                                    onChanged();
                                    setTabState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                                  onPressed: () {
                                    project.timelineSegments.removeAt(idx);
                                    if (project.activeTimelineSegmentIndex >= project.timelineSegments.length) {
                                      project.activeTimelineSegmentIndex =
                                          math.max(0, project.timelineSegments.length - 1);
                                    }
                                    onChanged();
                                    setTabState(() {});
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Text(
                              'In: ${formatTimestampMs(seg.startTime)}',
                              style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Text(
                              'Out: ${formatTimestampMs(seg.endTime)}',
                              style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        RangeSlider(
                          values: RangeValues(
                            seg.startTime.clamp(0.0, videoDuration),
                            seg.endTime.clamp(seg.startTime, videoDuration),
                          ),
                          min: 0.0,
                          max: videoDuration > 0.0 ? videoDuration : 1.0,
                          activeColor: accent,
                          inactiveColor: Colors.white12,
                          onChanged: (RangeValues vals) {
                            double minAllowed = (idx > 0) ? project.timelineSegments[idx - 1].endTime : 0.0;
                            double maxAllowed = (idx < project.timelineSegments.length - 1)
                                ? project.timelineSegments[idx + 1].startTime
                                : videoDuration;

                            seg.startTime = vals.start.clamp(minAllowed, maxAllowed);
                            seg.endTime = vals.end.clamp(seg.startTime + 0.1, maxAllowed);
                            onChanged();
                            setTabState(() {});
                          },
                        ),
                        Text(
                          'Duration: ${(seg.endTime - seg.startTime).toStringAsFixed(2)}s (${seg.layers.length} internal grade layers)',
                          style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 11. TEXT SUITE TAB (Metal / Silk finish, colour wheels, deep glow, softeners, fill pattern, vector mode, personal tuning)
  // All sliders use SmoothSliderRow (handle moves first, grade scheduled after, commit on release) like every other tab.
  // ---------------------------------------------------------------------------
  static Widget buildTextSuiteTab({
    required BuildContext context,
    required ProjectData project,
    required VoidCallback onChanged,
    VoidCallback? onEnded,
  }) {
    final accent = gCustomAccentColor.value;
    final fx = project.text;

    void commit() {
      onChanged();
      onEnded?.call();
    }

    Widget hdr(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 4),
          child: Text(t, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        );

    Widget sl(String title, double v, double mn, double mx, void Function(double) set) => buildSliderRow(
          context: context,
          title: title,
          val: v,
          min: mn,
          max: mx,
          onChanged: (x) {
            set(x);
            onChanged();
          },
          onEnded: onEnded,
        );

    Widget chips(List<List<Object>> items, double cur, void Function(double) set) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((t) {
              final id = t[0] as double;
              final isSel = (cur - id).abs() < 0.01;
              return ChoiceChip(
                label: Text(t[1] as String),
                selected: isSel,
                selectedColor: accent,
                labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                onSelected: (sel) {
                  if (sel) {
                    set(id);
                    commit();
                  }
                },
              );
            }).toList(),
          ),
        );

    Widget action(String label, IconData icon, VoidCallback run) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withOpacity(0.6)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          onPressed: run,
        );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: project.textSuiteEnabled ? accent.withOpacity(0.18) : gPalette.value.control,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: project.textSuiteEnabled ? accent : Colors.white10,
              width: project.textSuiteEnabled ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.title_rounded, color: project.textSuiteEnabled ? accent : Colors.white54, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Text Suite (T button)', style: TextStyle(color: project.textSuiteEnabled ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                          const Text('Metal / silk, deep glow, vector mode', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: project.textSuiteEnabled,
                activeColor: accent,
                onChanged: (val) {
                  project.textSuiteEnabled = val;
                  commit();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!project.textSuiteEnabled)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF101014), borderRadius: BorderRadius.circular(10)),
            child: const Center(
              child: Text(
                'Turn the Text Suite on here or with the T button at the top.\nThe draggable box appears over the preview: text inside it gets the metal / silk finish, deep glow and vector warp.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ),
          )
        else ...[
          hdr('OVERLAY'),
          sl('Text Overlay Opacity', fx.opacity, 0.0, 1.0, (v) => fx.opacity = v),

          hdr('FINISH'),
          chips(const [
            [0.0, 'Metallic'],
            [1.0, 'Silky'],
          ], fx.style, (v) => fx.style = v),
          const SizedBox(height: 6),
          sl('Metal Amount (Chrome Horizon Reflection)', project.textChromeIntensity, 0.0, 3.0, (v) => project.textChromeIntensity = v),
          sl('Stroke Roundness (tube reflection)', fx.roundness, 0.0, 1.5, (v) => fx.roundness = v),
          sl('Highlight Bands (across the box)', fx.bandCount, 0.5, 6.0, (v) => fx.bandCount = v),
          sl('Band Angle', fx.bandAngle, -1.57, 1.57, (v) => fx.bandAngle = v),
          sl('Band Softness (0 = hard metal, 1 = silk)', fx.bandSoft, 0.0, 1.0, (v) => fx.bandSoft = v),
          sl('Band Strength', fx.bandStrength, 0.0, 2.0, (v) => fx.bandStrength = v),
          sl('Silk Sheen (brushed highlight)', fx.anisotropy, 0.0, 1.0, (v) => fx.anisotropy = v),
          sl('Darker Body', fx.bodyDark, 0.0, 1.0, (v) => fx.bodyDark = v),
          sl('Sharp Rim', fx.rimSharp, 0.0, 2.0, (v) => fx.rimSharp = v),
          sl('Soft Ambient Reflection', fx.ambient, 0.0, 1.0, (v) => fx.ambient = v),
          sl('Fresnel Edge Reflection', fx.fresnel, 0.0, 1.0, (v) => fx.fresnel = v),
          sl('Metallic Bevel Depth', project.textBevelDepth, 0.0, 3.0, (v) => project.textBevelDepth = v),
          sl('Specular Edge Glint', project.textSpecularGlint, 0.0, 2.0, (v) => project.textSpecularGlint = v),
          sl('Grounding Contact Shadow', project.textContactShadow, 0.0, 1.0, (v) => project.textContactShadow = v),

          hdr('COLOUR WHEELS'),
          TextColourWheelCard(
            title: 'Highlight colour',
            h: fx.hiH,
            s: fx.hiS,
            v: fx.hiV,
            onChanged: (h, sa, v) {
              fx.hiH = h;
              fx.hiS = sa;
              fx.hiV = v;
              if (fx.tintMix < 0.01) fx.tintMix = 1.0;
              onChanged();
            },
            onEnded: onEnded,
          ),
          TextColourWheelCard(
            title: 'Body (shadow) colour',
            h: fx.bodyH,
            s: fx.bodyS,
            v: fx.bodyV,
            onChanged: (h, sa, v) {
              fx.bodyH = h;
              fx.bodyS = sa;
              fx.bodyV = v;
              if (fx.tintMix < 0.01) fx.tintMix = 1.0;
              onChanged();
            },
            onEnded: onEnded,
          ),
          sl('Wheel Colour Influence (0 = text colour)', fx.tintMix, 0.0, 1.0, (v) => fx.tintMix = v),
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text('Tint finish override (0 = text colour):', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ),
          chips(const [
            [0.0, 'Text Colour (Auto)'],
            [1.0, 'Gold Ingot'],
            [2.0, 'Cyan Steel'],
            [3.0, 'Crimson Alloy'],
            [4.0, 'Violet Chrome'],
          ], project.textMetallicTint, (v) => project.textMetallicTint = v),

          hdr('DEEP GLOW (one continuous falloff, no copies)'),
          sl('Glow Intensity', fx.glowIntensity, 0.0, 3.0, (v) => fx.glowIntensity = v),
          sl('Glow Size', fx.glowRadius, 0.02, 4.0, (v) => fx.glowRadius = v),
          sl('Glow Rolloff / Spread (higher = wider, slower)', fx.glowRolloff, 0.0, 2.0, (v) => fx.glowRolloff = v),
          sl('Glow Position X', fx.glowOffX, -2.0, 2.0, (v) => fx.glowOffX = v),
          sl('Glow Position Y', fx.glowOffY, -2.0, 2.0, (v) => fx.glowOffY = v),
          sl('Inner Glow (bleeds onto letters)', fx.glowInner, 0.0, 1.0, (v) => fx.glowInner = v),
          sl('Hot White Core', fx.glowWhiteCore, 0.0, 1.0, (v) => fx.glowWhiteCore = v),
          sl('Glow Smoothness (samples)', fx.glowQuality, 0.0, 1.0, (v) => fx.glowQuality = v),
          TextColourWheelCard(
            title: 'Glow colour',
            h: fx.glowH,
            s: fx.glowS,
            v: fx.glowV,
            onChanged: (h, sa, v) {
              fx.glowH = h;
              fx.glowS = sa;
              fx.glowV = v;
              if (fx.glowColorMix < 0.01) fx.glowColorMix = 1.0;
              onChanged();
            },
            onEnded: onEnded,
          ),
          sl('Glow Wheel Influence (0 = text colour)', fx.glowColorMix, 0.0, 1.0, (v) => fx.glowColorMix = v),

          hdr('SOFTENERS & RANGES'),
          sl('Edge Softener (removes ragged edges)', fx.edgeSoften, 0.0, 1.0, (v) => fx.edgeSoften = v),
          sl('Text Luma Threshold', project.textLumaThreshold, 0.15, 0.95, (v) => project.textLumaThreshold = v),
          sl('Mask Range Low (soft below threshold)', fx.rangeLo, 0.02, 0.45, (v) => fx.rangeLo = v),
          sl('Mask Range High (soft above threshold)', fx.rangeHi, 0.02, 0.45, (v) => fx.rangeHi = v),

          hdr('FILL PATTERN (pixel / texture look on the metal)'),
          chips(const [
            [0.0, 'None'],
            [1.0, 'Pixel Mosaic'],
            [2.0, 'Scanlines'],
            [3.0, 'Checker'],
            [4.0, 'Halftone'],
            [5.0, 'Grain'],
          ], fx.patternType, (v) => fx.patternType = v),
          if (fx.patternType > 0.5) ...[
            sl('Pattern Size', fx.patternScale, 2.0, 40.0, (v) => fx.patternScale = v),
            sl('Pattern Strength', fx.patternStrength, 0.0, 1.0, (v) => fx.patternStrength = v),
            sl('Pattern Angle', fx.patternAngle, -1.57, 1.57, (v) => fx.patternAngle = v),
          ],

          hdr('VECTOR MODE (drag points to deform the text)'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: gPalette.value.control, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Vector mode  (${fx.points.length}/${TextFx.kMaxPoints} points)', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    Switch(
                      value: fx.vecEnabled,
                      activeColor: accent,
                      onChanged: (val) {
                        fx.vecEnabled = val;
                        if (val && fx.points.isEmpty) fx.autoGrid(4, 2);
                        if (!val) fx.vecAddMode = false;
                        commit();
                      },
                    ),
                  ],
                ),
                if (fx.vecEnabled) ...[
                  const Text(
                    'Drag a point on the box to pull the text. Long-press a point to remove it. Turn on Add Points, then tap the box to place new ones.',
                    style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      action(fx.vecAddMode ? 'Add Points: ON' : 'Add Points: OFF', Icons.add_location_alt_rounded, () {
                        fx.vecAddMode = !fx.vecAddMode;
                        commit();
                      }),
                      action('Auto Grid 4x2', Icons.grid_on_rounded, () {
                        fx.autoGrid(4, 2);
                        commit();
                      }),
                      action('Remove Last', Icons.undo_rounded, () {
                        if (fx.points.isNotEmpty) fx.removePoint(fx.points.length - 1);
                        commit();
                      }),
                      action('Reset / Restore Text', Icons.restart_alt_rounded, () {
                        fx.resetDisplacement();
                        commit();
                      }),
                      action('Clear Points', Icons.delete_outline_rounded, () {
                        fx.clearPoints();
                        commit();
                      }),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (fx.vecEnabled) ...[
            sl('Point Reach (influence)', fx.vecInfluence, 0.05, 1.5, (v) => fx.vecInfluence = v),
            sl('Warp Amount', fx.vecAmount, 0.0, 1.5, (v) => fx.vecAmount = v),
          ],

          hdr('BOX POSITION & SIZE'),
          sl('Box Width', project.textBoxW, 0.10, 1.0, (v) => project.textBoxW = v),
          sl('Box Height', project.textBoxH, 0.05, 1.0, (v) => project.textBoxH = v),
          sl('Horizontal Position (X)', project.textBoxX, 0.0, 1.0 - project.textBoxW, (v) => project.textBoxX = v),
          sl('Vertical Position (Y)', project.textBoxY, 0.0, 1.0 - project.textBoxH, (v) => project.textBoxY = v),

          const SizedBox(height: 10),
          Center(
            child: action('Reset Look to Defaults', Icons.restart_alt_rounded, () {
              fx.resetLook();
              commit();
            }),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT PRESET WITH NAMING PROMPT DIALOG
  // ---------------------------------------------------------------------------
  static Future<void> exportPresetToFile(BuildContext context, ProjectData project) async {
    final defaultName = project.mediaPath.isNotEmpty
        ? project.mediaPath.split('/').last.split('.').first
        : 'Shaderly_Grade';
    final nameController = TextEditingController(text: defaultName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: gPalette.value.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export CC Preset', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preset name', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF101016),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: gCustomAccentColor.value, foregroundColor: Colors.black),
            onPressed: () async {
              final chosenName = nameController.text.trim().isNotEmpty ? nameController.text.trim() : defaultName;
              Navigator.pop(ctx);
              await _performPresetExport(context, project, chosenName);
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  static Future<void> _performPresetExport(BuildContext context, ProjectData project, String presetName) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final safeName = presetName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      final Map<String, dynamic> ccData = {
        'generator': 'AEReality Shaderly 2026',
        'format_version': '1.0',
        'project_name': presetName,
        'tonemap_mode': project.tonemapMode,
        'deep_teal': project.deepTeal,
        'magic_curves': project.magicCurves,
        'text_suite': {
          'enabled': project.textSuiteEnabled,
          'box_x': project.textBoxX,
          'box_y': project.textBoxY,
          'box_w': project.textBoxW,
          'box_h': project.textBoxH,
          'bevel_depth': project.textBevelDepth,
          'chrome_intensity': project.textChromeIntensity,
          'specular_glint': project.textSpecularGlint,
          'contact_shadow': project.textContactShadow,
          'luma_threshold': project.textLumaThreshold,
          'metallic_tint': project.textMetallicTint,
          'personal': project.text.toJson(), // batch 5: personal tuning + vector points
        },
        'layers': project.layers.map((l) => l.toJson()).toList(),
      };

      // ONE .json file: Downloads when writable, otherwise the app folder.
      final fileName = 'Shaderly_${safeName}_CC.json';
      final jsonText = const JsonEncoder.withIndent('  ').convert(ccData);
      File? outFile;
      String where = 'Downloads';
      if (Platform.isAndroid) {
        try {
          final downloadsDir = Directory('/storage/emulated/0/Download');
          if (!downloadsDir.existsSync()) downloadsDir.createSync(recursive: true);
          final f = File('${downloadsDir.path}/$fileName');
          await f.writeAsString(jsonText);
          outFile = f;
          try {
            await const MethodChannel('com.aereality/media').invokeMethod('scanFile', {'path': f.path});
          } catch (_) {}
        } catch (_) {
          outFile = null;
        }
      }
      if (outFile == null) {
        final docs = await getApplicationDocumentsDirectory();
        final f = File('${docs.path}/$fileName');
        await f.writeAsString(jsonText);
        outFile = f;
        where = 'app folder';
      }

      scaffold.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF101016),
        content: Text('CC "$presetName" saved as .json to $where', style: TextStyle(color: gCustomAccentColor.value, fontWeight: FontWeight.bold)),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('Failed to export CC: $e'),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // PRESET SAVE / IMPORT HELPERS (STAYS IN PRESETS LIST PERMANENTLY)
  // ---------------------------------------------------------------------------
  static Future<void> saveCurrentAsPreset(BuildContext context, ProjectData project, List<CustomPresetItem> customPresets) async {
    final controller = TextEditingController(text: 'My Custom Grade');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: gPalette.value.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Save Preset', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Preset Name', labelStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: gCustomAccentColor.value, foregroundColor: Colors.black),
            onPressed: () async {
              final name = controller.text.trim().isNotEmpty ? controller.text.trim() : 'My Custom Grade';
              Navigator.pop(ctx);

              final newPreset = CustomPresetItem(
                name: name,
                description: '${project.layers.length} Layers',
                accentColor: gCustomAccentColor.value.value,
                isBuiltIn: false,
                layers: project.layers.map((l) => l.clone()).toList(),
                tonemapMode: project.tonemapMode,
              );

              customPresets.add(newPreset);
              await ProjectManager.saveCustomPresets(customPresets);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Preset "$name" saved!'), backgroundColor: Colors.teal),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static Future<void> importPresetFromFile(BuildContext context, ProjectData project, List<CustomPresetItem> customPresets) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();

        dynamic decoded;
        try {
          decoded = jsonDecode(content);
        } catch (_) {
          decoded = null;
        }

        if (decoded is Map<String, dynamic>) {
          String presetName = file.path.split('/').last.split('.').first.replaceAll('Shaderly_', '').replaceAll('_CC', '');
          if (decoded.containsKey('project_name')) {
            presetName = decoded['project_name'].toString();
          }

          if (decoded.containsKey('layers') && decoded['layers'] is List) {
            project.layers.clear();
            for (var l in decoded['layers']) {
              if (l is Map<String, dynamic>) {
                project.layers.add(AdjustmentLayer.fromJson(l));
              }
            }
          }
          if (decoded.containsKey('tonemap_mode') || decoded.containsKey('tonemapMode')) {
            project.tonemapMode = ((decoded['tonemap_mode'] ?? decoded['tonemapMode']) as num).toDouble();
          }
          if (decoded.containsKey('deep_teal')) {
            project.deepTeal = (decoded['deep_teal'] as num).toDouble();
          }
          if (decoded.containsKey('magic_curves')) {
            project.magicCurves = (decoded['magic_curves'] as num).toDouble();
          }
          if (decoded.containsKey('text_suite') && decoded['text_suite'] is Map<String, dynamic>) {
            final ts = decoded['text_suite'] as Map<String, dynamic>;
            project.textSuiteEnabled = ts['enabled'] == true;
            project.textBoxX = (ts['box_x'] as num?)?.toDouble() ?? 0.07;
            project.textBoxY = (ts['box_y'] as num?)?.toDouble() ?? 0.415;
            project.textBoxW = (ts['box_w'] as num?)?.toDouble() ?? 0.88;
            project.textBoxH = (ts['box_h'] as num?)?.toDouble() ?? 0.10;
            project.textBevelDepth = (ts['bevel_depth'] as num?)?.toDouble() ?? 1.0;
            project.textChromeIntensity = (ts['chrome_intensity'] as num?)?.toDouble() ?? 1.8;
            project.textSpecularGlint = (ts['specular_glint'] as num?)?.toDouble() ?? 1.2;
            project.textContactShadow = (ts['contact_shadow'] as num?)?.toDouble() ?? 0.6;
            project.textLumaThreshold = (ts['luma_threshold'] as num?)?.toDouble() ?? 0.40;
            project.textMetallicTint = (ts['metallic_tint'] as num?)?.toDouble() ?? 0.0;
            project.text = (ts['personal'] is Map)
                ? TextFx.fromJson(Map<String, dynamic>.from(ts['personal'] as Map))
                : TextFx(); // older presets have no personal block: defaults
          }
          project.activeLayerIndex = 0;

          // PERMANENTLY ADD TO CUSTOM PRESETS
          customPresets.removeWhere((p) => p.name == presetName);
          final newPreset = CustomPresetItem(
            name: presetName,
            description: '${project.layers.length} Layers (Imported)',
            accentColor: gCustomAccentColor.value.value,
            isBuiltIn: false,
            layers: project.layers.map((l) => l.clone()).toList(),
            tonemapMode: project.tonemapMode,
          );
          customPresets.add(newPreset);
          await ProjectManager.saveCustomPresets(customPresets);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported and saved "$presetName" into presets!'), backgroundColor: Colors.green),
          );
        } else {
          throw Exception('File is not a valid Shaderly JSON preset.');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load preset: $e'), backgroundColor: Colors.red),
      );
    }
  }

  static Future<void> pickAndImportCubeLut(BuildContext context, AdjustmentLayer cur, List<LutModel> activeLuts) async {
    try {
      final file = await LutProcessor.pickCubeFile();
      if (file == null) return;

      final parsed = await LutProcessor.parseCubeFile(file);
      if (parsed != null) {
        final lut = LutModel(
          id: 'lut_${DateTime.now().millisecondsSinceEpoch}',
          name: parsed.title,
          filePath: file.path,
          size: parsed.size,
          table: parsed.table,
        );

        if (activeLuts.length >= 4) activeLuts.removeAt(0);
        activeLuts.add(lut);
        await ProjectManager.saveLuts(activeLuts);

        cur.activeLutId = lut.id;
        cur.lutOpacity = 1.0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied "${lut.name}.cube"'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to parse LUT: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 12. MASTER EXPORT DISPATCHER (DELEGATES DIRECTLY TO EXPORTSUITE)
  // ---------------------------------------------------------------------------
  static void showExportSheet({
    required BuildContext context,
    required ProjectData project,
    required AdjustmentLayer curLayer,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) {
    ExportSuite.showExportSheet(
      context: context,
      project: project,
      curLayer: curLayer,
      packUniforms: packUniforms,
      getActiveLut: getActiveLut,
    );
  }
}

// -----------------------------------------------------------------------------
// ANIMATED RAINBOW BORDER CONTAINER (FOR ACTIVE TIMELINE SEGMENT HIGHLIGHT)
// -----------------------------------------------------------------------------
class AnimatedRainbowBorderContainer extends StatefulWidget {
  final Widget child;
  final bool isActive;

  const AnimatedRainbowBorderContainer({
    super.key,
    required this.child,
    required this.isActive,
  });

  @override
  State<AnimatedRainbowBorderContainer> createState() => _AnimatedRainbowBorderContainerState();
}

class _AnimatedRainbowBorderContainerState extends State<AnimatedRainbowBorderContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: SweepGradient(
              startAngle: 0.0,
              endAngle: math.pi * 2,
              transform: GradientRotation(_animCtrl.value * math.pi * 2),
              colors: const [
                Color(0xFFFF0055),
                Color(0xFFFF9900),
                Color(0xFF00FF66),
                Color(0xFF00E5FF),
                Color(0xFF7C4DFF),
                Color(0xFFFF0055),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// RESPONSIVE DRAGGABLE & STRETCHABLE TEXT BOUNDING BOX
// -----------------------------------------------------------------------------
class DraggableTextBoundingBox extends StatefulWidget {
  final ProjectData project;
  final Size containerSize;
  final VoidCallback onUpdated;
  final VoidCallback? onEnded; // gesture finished: commit undo snapshot + autosave

  const DraggableTextBoundingBox({
    Key? key,
    required this.project,
    required this.containerSize,
    required this.onUpdated,
    this.onEnded,
  }) : super(key: key);

  @override
  State<DraggableTextBoundingBox> createState() => _DraggableTextBoundingBoxState();
}

class _DraggableTextBoundingBoxState extends State<DraggableTextBoundingBox> {
  @override
  Widget build(BuildContext context) {
    if (!widget.project.textSuiteEnabled) return const SizedBox.shrink();

    final accent = gCustomAccentColor.value;
    final parentW = widget.containerSize.width;
    final parentH = widget.containerSize.height;

    final left = widget.project.textBoxX * parentW;
    final top = widget.project.textBoxY * parentH;
    final width = widget.project.textBoxW * parentW;
    final height = widget.project.textBoxH * parentH;
    final boxW = math.max(60.0, width);
    final boxH = math.max(45.0, height);
    final fx = widget.project.text;
    final vec = fx.vecEnabled;

    return Positioned(
      left: left,
      top: top,
      width: boxW,
      height: boxH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (vec && fx.vecAddMode)
                ? (details) {
                    if (!fx.canAddPoint) return;
                    setState(() => fx.addPoint(details.localPosition.dx / boxW, details.localPosition.dy / boxH));
                    widget.onUpdated();
                    widget.onEnded?.call();
                  }
                : null,
            onPanUpdate: (details) {
              setState(() {
                widget.project.textBoxX = (widget.project.textBoxX + details.delta.dx / parentW).clamp(0.0, 1.0 - widget.project.textBoxW);
                widget.project.textBoxY = (widget.project.textBoxY + details.delta.dy / parentH).clamp(0.0, 1.0 - widget.project.textBoxH);
              });
              widget.onUpdated();
            },
            onPanEnd: (_) => widget.onEnded?.call(),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 2.0),
                color: accent.withOpacity(0.12),
              ),
              child: Center(
                child: Text(
                  vec
                      ? 'VECTOR MODE (${fx.points.length} points${fx.vecAddMode ? ', tap to add' : ''})'
                      : 'METALLIC TEXT MASK (${(widget.project.textBoxW * 100).toInt()}% x ${(widget.project.textBoxH * 100).toInt()}%)',
                  style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ),
          ),
          if (vec)
            for (int i = 0; i < fx.points.length; i++)
              Positioned(
                left: fx.points[i].cx * boxW - 16,
                top: fx.points[i].cy * boxH - 16,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final p = fx.points[i];
                    setState(() {
                      p.cx = (p.cx + details.delta.dx / boxW).clamp(-0.25, 1.25).toDouble();
                      p.cy = (p.cy + details.delta.dy / boxH).clamp(-0.25, 1.25).toDouble();
                    });
                    widget.onUpdated();
                  },
                  onPanEnd: (_) => widget.onEnded?.call(),
                  onLongPress: () {
                    setState(() => fx.removePoint(i));
                    widget.onUpdated();
                    widget.onEnded?.call();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.85),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2.0),
                    ),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          Positioned(
            right: -16,
            bottom: -16,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                setState(() {
                  widget.project.textBoxW = (widget.project.textBoxW + details.delta.dx / parentW).clamp(0.10, 1.0 - widget.project.textBoxX);
                  widget.project.textBoxH = (widget.project.textBoxH + details.delta.dy / parentH).clamp(0.05, 1.0 - widget.project.textBoxY);
                });
                widget.onUpdated();
              },
              onPanEnd: (_) => widget.onEnded?.call(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.5), blurRadius: 6, spreadRadius: 1),
                  ],
                ),
                child: const Icon(Icons.open_in_full_rounded, size: 16, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// COLOUR WHEEL (hue = angle, saturation = distance from the centre) + brightness slider
// =============================================================================
class TextColourWheelCard extends StatefulWidget {
  final String title;
  final double h; // 0..1
  final double s; // 0..1
  final double v; // 0..1
  final void Function(double h, double s, double v) onChanged;
  final VoidCallback? onEnded;

  const TextColourWheelCard({
    super.key,
    required this.title,
    required this.h,
    required this.s,
    required this.v,
    required this.onChanged,
    this.onEnded,
  });

  @override
  State<TextColourWheelCard> createState() => _TextColourWheelCardState();
}

class _TextColourWheelCardState extends State<TextColourWheelCard> {
  static const double _size = 124.0;
  late double _h;
  late double _s;
  late double _v;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _h = widget.h;
    _s = widget.s;
    _v = widget.v;
  }

  @override
  void didUpdateWidget(covariant TextColourWheelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) {
      _h = widget.h;
      _s = widget.s;
      _v = widget.v;
    }
  }

  void _pick(Offset p) {
    final c = const Offset(_size / 2, _size / 2);
    final d = p - c;
    double a = math.atan2(d.dy, d.dx);
    if (a < 0) a += 2 * math.pi;
    setState(() {
      _h = (a / (2 * math.pi)).clamp(0.0, 1.0).toDouble();
      _s = (d.distance / (_size / 2)).clamp(0.0, 1.0).toDouble();
    });
    widget.onChanged(_h, _s, _v);
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;
    final swatch = HSVColor.fromAHSV(1.0, (_h * 360.0).clamp(0.0, 360.0).toDouble(), _s.clamp(0.0, 1.0).toDouble(), _v.clamp(0.0, 1.0).toDouble()).toColor();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gPalette.value.control,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onPanStart: (d) {
              _dragging = true;
              _pick(d.localPosition);
            },
            onPanUpdate: (d) => _pick(d.localPosition),
            onPanEnd: (_) {
              _dragging = false;
              widget.onEnded?.call();
            },
            onTapDown: (d) => _pick(d.localPosition),
            onTapUp: (_) => widget.onEnded?.call(),
            child: SizedBox(
              width: _size,
              height: _size,
              child: CustomPaint(painter: _WheelPainter(_h, _s, _v)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: swatch,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Brightness', style: TextStyle(color: Colors.white38, fontSize: 10)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    activeTrackColor: accent,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: accent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: _v.clamp(0.0, 1.0).toDouble(),
                    min: 0.0,
                    max: 1.0,
                    onChangeStart: (_) => _dragging = true,
                    onChanged: (x) {
                      setState(() => _v = x);
                      widget.onChanged(_h, _s, _v);
                    },
                    onChangeEnd: (_) {
                      _dragging = false;
                      widget.onEnded?.call();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double h;
  final double s;
  final double v;
  _WheelPainter(this.h, this.s, this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final vv = v.clamp(0.25, 1.0);
    final sweep = SweepGradient(colors: [
      for (int i = 0; i <= 6; i++) HSVColor.fromAHSV(1.0, i * 60.0, 1.0, vv).toColor(),
    ]);
    canvas.drawCircle(c, r, Paint()..shader = sweep.createShader(rect));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withOpacity(vv), Colors.white.withOpacity(0.0)]).createShader(rect),
    );
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white24);
    final a = h.clamp(0.0, 1.0) * 2 * math.pi;
    final m = c + Offset(math.cos(a), math.sin(a)) * (s.clamp(0.0, 1.0) * r);
    canvas.drawCircle(m, 8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.black);
    canvas.drawCircle(m, 8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.h != h || old.s != s || old.v != v;
}


// =============================================================================
// HUE vs SATURATION / HUE / LUMINANCE PANEL (lives in the BASIC tab)
// =============================================================================
class HueSatPanel extends StatefulWidget {
  final AdjustmentLayer cur;
  final VoidCallback onChanged;
  final VoidCallback onEnded;

  const HueSatPanel({super.key, required this.cur, required this.onChanged, required this.onEnded});

  @override
  State<HueSatPanel> createState() => _HueSatPanelState();
}

class _HueSatPanelState extends State<HueSatPanel> {
  int _mode = 0; // 0 = Hue vs Sat, 1 = Hue vs Hue, 2 = Hue vs Lum

  @override
  Widget build(BuildContext context) {
    final cur = widget.cur;
    final accent = gCustomAccentColor.value;
    final onChanged = widget.onChanged;
    final onEnded = widget.onEnded;

    final List<double> vals = _mode == 0 ? cur.hsSat : (_mode == 1 ? cur.hsHue : cur.hsLum);
    final String modeName = _mode == 0 ? 'Saturation' : (_mode == 1 ? 'Hue Shift' : 'Luminance');

    Widget header(String t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(t, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        );

    final tileTheme = Theme.of(context).copyWith(dividerColor: Colors.transparent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header('HUE vs SATURATION / HUE / LUMINANCE'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final m in const [
                {'n': 'Hue vs Sat', 'i': 0},
                {'n': 'Hue vs Hue', 'i': 1},
                {'n': 'Hue vs Lum', 'i': 2},
              ])
                ChoiceChip(
                  label: Text(m['n'] as String, style: TextStyle(fontSize: 11, color: _mode == m['i'] ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)),
                  selected: _mode == m['i'],
                  selectedColor: accent,
                  backgroundColor: gPalette.value.control,
                  onSelected: (_) => setState(() => _mode = m['i'] as int),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: HueBandEditor(
            key: ValueKey('hsEditor$_mode'),
            values: vals,
            softness: cur.hsSoftness,
            accent: accent,
            onChanged: onChanged,
            onEnded: onEnded,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
          child: Text('Drag points to edit. Double-tap to reset.',
              style: const TextStyle(color: Colors.white24, fontSize: 10)),
        ),
        EditorViews.buildSliderRow(context: context, title: 'Band Blend Softness', val: cur.hsSoftness, min: 0.0, max: 1.0, onChanged: (v) { cur.hsSoftness = v; onChanged(); }, onEnded: onEnded),

        Theme(
          data: tileTheme,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            iconColor: accent,
            collapsedIconColor: Colors.white38,
            title: Text('Fine sliders  -  $modeName per colour', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            children: [
              for (int i = 0; i < 8; i++)
                EditorViews.buildSliderRow(
                  context: context,
                  title: kHueBandNames[i],
                  val: vals[i],
                  min: -1.0,
                  max: 1.0,
                  onChanged: (v) { vals[i] = v; onChanged(); },
                  onEnded: onEnded,
                ),
            ],
          ),
        ),

        Theme(
          data: tileTheme,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            iconColor: accent,
            collapsedIconColor: Colors.white38,
            title: const Text('Custom hue range (pick any colour)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 16,
                    child: LayoutBuilder(builder: (context, c) {
                      final w = c.maxWidth;
                      final n = 36;
                      return Stack(
                        children: [
                          Row(
                            children: [
                              for (int i = 0; i < n; i++) Expanded(child: Container(color: oklchColor(i / n * 360.0))),
                            ],
                          ),
                          Positioned(
                            left: (cur.hsCustomCenter.clamp(0.0, 1.0) * w - 2).clamp(0.0, w - 4).toDouble(),
                            top: 0,
                            bottom: 0,
                            child: Container(width: 4, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 1))),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
              EditorViews.buildSliderRow(context: context, title: 'Range Centre (Hue)', val: cur.hsCustomCenter, min: 0.0, max: 1.0, onChanged: (v) { cur.hsCustomCenter = v; onChanged(); }, onEnded: onEnded),
              EditorViews.buildSliderRow(context: context, title: 'Range Width', val: cur.hsCustomWidth, min: 0.0, max: 1.0, onChanged: (v) { cur.hsCustomWidth = v; onChanged(); }, onEnded: onEnded),
              EditorViews.buildSliderRow(context: context, title: 'Range Feather', val: cur.hsCustomSoft, min: 0.0, max: 1.0, onChanged: (v) { cur.hsCustomSoft = v; onChanged(); }, onEnded: onEnded),
              EditorViews.buildSliderRow(context: context, title: 'Range Saturation', val: cur.hsCustomSat, min: -1.0, max: 1.0, onChanged: (v) { cur.hsCustomSat = v; onChanged(); }, onEnded: onEnded),
              EditorViews.buildSliderRow(context: context, title: 'Range Hue Shift', val: cur.hsCustomHue, min: -1.0, max: 1.0, onChanged: (v) { cur.hsCustomHue = v; onChanged(); }, onEnded: onEnded),
              EditorViews.buildSliderRow(context: context, title: 'Range Luminance', val: cur.hsCustomLum, min: -1.0, max: 1.0, onChanged: (v) { cur.hsCustomLum = v; onChanged(); }, onEnded: onEnded),
            ],
          ),
        ),

        Center(
          child: TextButton.icon(
            onPressed: () {
              cur.resetHueSat();
              onChanged();
              onEnded();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white38),
            label: const Text('Reset Hue vs Sat', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SmoothSliderRow - same look as the old buildSliderRow. The thumb and the number are driven by this row's OWN state,
// so dragging only rebuilds this one row; the (possibly slow) grade is triggered through onChanged and never blocks the
// handle. When the parent hands in a new value (preset, undo, reset) and no drag is running, the row adopts it.
// =============================================================================
class SmoothSliderRow extends StatefulWidget {
  final String title;
  final double val;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onEnded;
  final bool whole; // C3: whole-number slider (default false = every existing slider unchanged)

  const SmoothSliderRow({
    super.key,
    required this.title,
    required this.val,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onEnded,
    this.whole = false,
  });

  @override
  State<SmoothSliderRow> createState() => _SmoothSliderRowState();
}

class _SmoothSliderRowState extends State<SmoothSliderRow> {
  late double _v;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _v = widget.val;
  }

  @override
  void didUpdateWidget(covariant SmoothSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) _v = widget.val;
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;
    // Batch 7 look: bevelled shelf plate, diamond handle, gradient-aware fill, slide-in entrance.
    // The drag logic is untouched: the handle moves first (setState), then onChanged, then onEnded (batch 2 pattern).
    return SlideInTilt(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: gPalette.value.control,
            shape: shelfShape(cut: 7, edge: Colors.white.withOpacity(0.05)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          DiamondDot(size: 5, color: accent.withOpacity(0.8)),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: ShapeDecoration(
                        color: accent.withOpacity(0.12),
                        shape: shelfShape(cut: 4, edge: accent.withOpacity(0.35)),
                      ),
                      child: Text(
                        widget.whole ? _v.round().toString() : _v.toStringAsFixed(2),
                        style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: shelfSliderTheme(context),
                  child: Slider(
                    value: _v.clamp(widget.min, widget.max).toDouble(),
                    min: widget.min,
                    max: widget.max,
                    divisions: widget.whole ? math.max(1, (widget.max - widget.min).round()) : null,
                    onChangeStart: (_) => _dragging = true,
                    onChanged: (x) {
                      setState(() => _v = x); // the handle moves first ...
                      widget.onChanged(x); //    ... then the model changes and the grade is scheduled
                    },
                    onChangeEnd: (_) {
                      _dragging = false;
                      widget.onEnded?.call();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
