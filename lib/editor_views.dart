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
import 'vulkan_bridge.dart';
import 'export_suite.dart';
import 'export_matrix.dart';

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
  }) {
    final accent = gCustomAccentColor.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF14141C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    val.toStringAsFixed(2),
                    style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
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
                value: val.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: (_) => onEnded?.call(),
              ),
            ),
          ],
        ),
      ),
    );
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
                color: isSel ? accent.withOpacity(0.16) : kCardDark,
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

        const Text('PRESETS (TAP TO APPLY / TAP TO REMOVE)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...kAnimePresetStyles.map((p) {
          final isSel = selectedPresetName == p.name;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? accent.withOpacity(0.16) : kCardDark,
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
        'desc': 'Raw 32-bit floating-point linear light response with no dynamic curve compression.',
      },
      {
        'mode': 1.0,
        'title': 'Shaderly Tonemapper 1 (AgX Anime Punch)',
        'desc': 'Rec.2020 AgX working gamut with 6th-order S-curve contrast boost. Deepens midtone blacks while giving smooth highlight roll-off without muddy dimness.',
      },
      {
        'mode': 2.0,
        'title': 'Shaderly Tonemapper 2 (Khronos PBR Neutral+)',
        'desc': 'Official Khronos 3D Commerce standard with black-level offset and smooth highlight desaturation, preserving anime linework and preventing blown highlights.',
      },
      {
        'mode': 3.0,
        'title': 'Aurora Depth',
        'desc': 'Perceptual (Oklab) lightness S-curve. Deeper toe and midtone separation without touching hue, so frames gain depth instead of going flat. Skin keeps softer gradations.',
      },
      {
        'mode': 4.0,
        'title': 'Sakura Silk',
        'desc': 'Skin-first, hue-preserving roll-off. Faces and warm tones compress softly instead of clipping to flat pink, keep their warmth, and get a gentle depth curve. Best for character close-ups.',
      },
      {
        'mode': 5.0,
        'title': 'Prism Blend',
        'desc': 'Colour-blending tonemapper. Highlights drift into lighter tints of their own colour (orange to gold, cyan to ice) and Oklab chroma recovery keeps shadows and mids from under-saturating. Great for glows and light edges.',
      },
      {
        'mode': 6.0,
        'title': 'Obsidian Cel',
        'desc': 'Cel-shaded depth. Deeper, richer jewel-toned shadows with midtones and highlights left where the artist put them. Ideal for dark, moody scenes without crushing detail.',
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
              color: isSel ? accent.withOpacity(0.14) : kCardDark,
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
              color: kCardDark,
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
                color: isSel ? accent.withOpacity(0.16) : kCardDark,
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
            color: const Color(0xFF14141C),
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
          child: Text('S_LINING (INNER GREY-BLACK EDGE CONTOUR)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
        color: const Color(0xFF14141C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final size = math.min(c.maxWidth - 8, 150.0);
        return Column(
          children: [
            ColorWheelPicker(label: title, x: x, y: y, size: size, onChanged: onWheel, onEnded: onEnded),
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
          child: Text('SPLIT TONING (SHADOW / HIGHLIGHT DUAL COLOR)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
          child: Text('Colorista Lift / Gamma / Gain now live on the COLORISTA tab (colour wheels).', style: TextStyle(color: Colors.white24, fontSize: 10)),
        ),
        buildSliderRow(context: context, title: 'Cosmo Clean Highlights (Skin Protection)', val: cur.cosmoCleanHighlight, min: 0.0, max: 1.0, onChanged: (v) { cur.cosmoCleanHighlight = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('MAGIC BULLETS PRO: DEEP TEAL & S-CURVES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deep Teal (Dark Cyan Chrominance)', val: cur.deepTeal, min: 0.0, max: 1.5, onChanged: (v) { cur.deepTeal = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Magic Curves (Lightness S-Curve)', val: cur.magicCurves, min: 0.0, max: 1.5, onChanged: (v) { cur.magicCurves = v; onChanged(); }, onEnded: onEnded),
      ],
    );
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
        buildSliderRow(context: context, title: 'Sapphire Edge Detect Glow', val: cur.copiedEdgeRays, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedEdgeRays = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Pro-Mist Halation (Black Line Safe)', val: cur.copiedProMist, min: 0.0, max: 1.0, onChanged: (v) { cur.copiedProMist = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Star Sparkle / Glint Cross', val: cur.copiedStarGlint, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedStarGlint = v; onChanged(); }, onEnded: onEnded),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('INNER SKIN EDGE BLEED', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Skin Edge Bleed (Depth)', val: cur.skinEdgeBleed, min: 0.0, max: 1.5, onChanged: (v) { cur.skinEdgeBleed = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Skin Edge Bleed Width', val: cur.skinEdgeWidth, min: 0.0, max: 1.0, onChanged: (v) { cur.skinEdgeWidth = v; onChanged(); }, onEnded: onEnded),
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
          child: Text('SHADERLY GLOW (COLOR-AWARE SOFT BLOOM)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Shaderly Glow Intensity', val: cur.shaderlyGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.shaderlyGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Radius', val: cur.shaderlyGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.shaderlyGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Threshold', val: cur.shaderlyGlowThreshold, min: 0.10, max: 0.90, onChanged: (v) { cur.shaderlyGlowThreshold = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Tint Hue (0 = Natural)', val: cur.shaderlyGlowTint, min: 0.0, max: 1.0, onChanged: (v) { cur.shaderlyGlowTint = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DEEP GLOW & SAPPHIRE S_GLOW', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deep Glow Intensity', val: cur.deepGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.deepGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Radius', val: cur.deepGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.deepGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Threshold', val: cur.deepGlowThreshold, min: 0.15, max: 0.90, onChanged: (v) { cur.deepGlowThreshold = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Sapphire Glow Width', val: cur.sapphireGlowWidth, min: 0.0, max: 2.0, onChanged: (v) { cur.sapphireGlowWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Sapphire Glow Threshold', val: cur.sapphireGlowThreshold, min: 0.20, max: 0.95, onChanged: (v) { cur.sapphireGlowThreshold = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('KAWASE PYRAMID & PRISMATIC DIFFUSE GLOW', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Kawase Glow Intensity', val: cur.kawaseGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.kawaseGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Kawase Glow Radius', val: cur.kawaseGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.kawaseGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Diffuse SP Glow (Prismatic Dispersion)', val: cur.diffuseGlow, min: 0.0, max: 1.5, onChanged: (v) { cur.diffuseGlow = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Diffuse SP Radius', val: cur.diffuseSpGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.diffuseSpGlowRadius = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('S_LIGHTWRAP (BACKGROUND EDGE BLEED - SOFT CLAMPED)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Wrap Width', val: cur.sLightWrapWidth, min: 0.0, max: 1.0, onChanged: (v) { cur.sLightWrapWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Wrap Intensity', val: cur.sLightWrapIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.sLightWrapIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Wrap Threshold', val: cur.sLightWrapThreshold, min: 0.0, max: 1.0, onChanged: (v) { cur.sLightWrapThreshold = v; onChanged(); }, onEnded: onEnded),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
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
          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
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
        buildSliderRow(context: context, title: 'Flare Opacity', val: cur.thinStreakOpacity, min: 0.0, max: 1.0, onChanged: (v) { cur.thinStreakOpacity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Softness (Tight Core to Long Fade)', val: cur.thinStreakSoftness, min: 0.0, max: 1.0, onChanged: (v) { cur.thinStreakSoftness = v; onChanged(); }, onEnded: onEnded),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: const Text('Flare Starts From Frame Edge', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: Text(cur.thinStreakFromEdge ? 'Beams enter from the side edge of the frame' : 'Beams start at each highlight', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          value: cur.thinStreakFromEdge,
          onChanged: (val) { cur.thinStreakFromEdge = val; onChanged(); onEnded(); },
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
          child: Text('SOURCE DEBANDING FILTER (RESTORES 8-BIT GRADIENTS)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deband Radius', val: cur.debandRadius, min: 0.0, max: 2.0, onChanged: (v) { cur.debandRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deband Threshold', val: cur.debandThreshold, min: 0.005, max: 0.08, onChanged: (v) { cur.debandThreshold = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DEPTH OF FIELD (CINEMATIC BACKGROUND BLUR)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DOF Mode', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Tilt-Shift Band'),
                    selected: cur.dofMode == 0.0,
                    selectedColor: accent,
                    labelStyle: TextStyle(color: cur.dofMode == 0.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (s) {
                      if (s) {
                        cur.dofMode = 0.0;
                        onChanged();
                        onEnded();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Radial Subject'),
                    selected: cur.dofMode == 1.0,
                    selectedColor: accent,
                    labelStyle: TextStyle(color: cur.dofMode == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (s) {
                      if (s) {
                        cur.dofMode = 1.0;
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
        buildSliderRow(context: context, title: 'Blur Amount', val: cur.depthOfField, min: 0.0, max: 2.0, onChanged: (v) { cur.depthOfField = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Focus Position (Y-Axis)', val: cur.dofFocus, min: 0.0, max: 1.0, onChanged: (v) { cur.dofFocus = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'In-Focus Zone Size', val: cur.dofRange, min: 0.05, max: 0.80, onChanged: (v) { cur.dofRange = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Transition Softness', val: cur.dofFalloff, min: 0.05, max: 0.60, onChanged: (v) { cur.dofFalloff = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Bokeh Highlight Boost', val: cur.dofBokeh, min: 0.0, max: 2.0, onChanged: (v) { cur.dofBokeh = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Tilt Angle (Radians)', val: cur.dofAngle, min: -math.pi, max: math.pi, onChanged: (v) { cur.dofAngle = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('ATMOSPHERIC VOLUMETRIC SCATTER & FOG', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Light Shafts (God Rays)', val: cur.bslaGodRays, min: 0.0, max: 1.5, onChanged: (v) { cur.bslaGodRays = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Fog Density (FBM Noise Driven)', val: cur.bslaFogDensity, min: 0.0, max: 1.0, onChanged: (v) { cur.bslaFogDensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Fog Depth (Height Falloff)', val: cur.bslaFogDepth, min: 0.0, max: 1.0, onChanged: (v) { cur.bslaFogDepth = v; onChanged(); }, onEnded: onEnded),
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
        buildSliderRow(context: context, title: 'Film Grain (Midtone Responsive)', val: cur.filmGrain, min: 0.0, max: 1.0, onChanged: (v) { cur.filmGrain = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Denoise Filter (Edge-Aware Bilateral)', val: cur.denoise, min: 0.0, max: 1.0, onChanged: (v) { cur.denoise = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 9. CURVES TAB (C1 Monotone Cubic Math - Clamped, Never Inverts)
  // ---------------------------------------------------------------------------
  static Widget buildCurvesTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required int selectedCurveChannel,
    required ValueChanged<int> onChannelChanged,
    required VoidCallback onChanged,
    required VoidCallback onResetCurve,
  }) {
    List<double> activeCurve = cur.curveMaster;
    Color curveColor = Colors.white;

    if (selectedCurveChannel == 1) {
      activeCurve = cur.curveRed;
      curveColor = Colors.redAccent;
    } else if (selectedCurveChannel == 2) {
      activeCurve = cur.curveGreen;
      curveColor = Colors.greenAccent;
    } else if (selectedCurveChannel == 3) {
      activeCurve = cur.curveBlue;
      curveColor = Colors.blueAccent;
    }

    // A point can never cross its neighbours -> the curve is always monotone (no fold-back / inversion).
    double clampPt(int i, double v) {
      final lo = i > 0 ? activeCurve[i - 1] : 0.0;
      final hi = i < activeCurve.length - 1 ? activeCurve[i + 1] : 1.0;
      return v.clamp(lo, hi).toDouble();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            {'name': 'RGB', 'idx': 0, 'col': Colors.white},
            {'name': 'RED', 'idx': 1, 'col': Colors.redAccent},
            {'name': 'GREEN', 'idx': 2, 'col': Colors.greenAccent},
            {'name': 'BLUE', 'idx': 3, 'col': Colors.blueAccent},
          ].map((ch) {
            final isSel = selectedCurveChannel == ch['idx'];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(ch['name'] as String),
                selected: isSel,
                selectedColor: ch['col'] as Color,
                onSelected: (sel) {
                  if (sel) onChannelChanged(ch['idx'] as int);
                },
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        SplineCurveEditor(
          points: activeCurve,
          curveColor: curveColor,
          onChanged: (newPts) {
            for (int i = 0; i < 5; i++) {
              activeCurve[i] = newPts[i];
            }
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        buildSliderRow(context: context, title: 'Black Point (0.00)', val: activeCurve[0], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[0] = clampPt(0, v); onChanged(); }),
        buildSliderRow(context: context, title: 'Shadow Lift (0.25)', val: activeCurve[1], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[1] = clampPt(1, v); onChanged(); }),
        buildSliderRow(context: context, title: 'Midtone Gamma (0.50)', val: activeCurve[2], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[2] = clampPt(2, v); onChanged(); }),
        buildSliderRow(context: context, title: 'Highlight Rolloff (0.75)', val: activeCurve[3], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[3] = clampPt(3, v); onChanged(); }),
        buildSliderRow(context: context, title: 'White Clip (1.00)', val: activeCurve[4], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[4] = clampPt(4, v); onChanged(); }),
        Center(
          child: TextButton.icon(
            onPressed: () {
              for (int i = 0; i < 5; i++) {
                activeCurve[i] = i * 0.25;
              }
              onResetCurve();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white38),
            label: const Text('Reset Curve', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ),
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
                color: project.enableTimelineSegments ? accent.withOpacity(0.18) : const Color(0xFF14141C),
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
                  color: kCardDark,
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
                      color: kCardDark,
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
  // 11. ISOLATED TEXT SUITE TAB (Metallic Bevel, Chrome Horizon & Text Glow)
  // ---------------------------------------------------------------------------
  static Widget buildTextSuiteTab({
    required BuildContext context,
    required ProjectData project,
    required VoidCallback onChanged,
  }) {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: project.textSuiteEnabled ? accent.withOpacity(0.18) : const Color(0xFF14141C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: project.textSuiteEnabled ? accent : Colors.white10,
              width: project.textSuiteEnabled ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.text_fields_rounded, color: project.textSuiteEnabled ? accent : Colors.white54, size: 24),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Enable Isolated Text Suite', style: TextStyle(color: project.textSuiteEnabled ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Text('Position-adaptive metallic chisel & chrome', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              Switch(
                value: project.textSuiteEnabled,
                activeColor: accent,
                onChanged: (val) {
                  project.textSuiteEnabled = val;
                  onChanged();
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
                'Toggle Text Suite above to display the on-screen draggable bounding box.\nPixels inside the box receive stylized metallic bevel, chrome reflection, and text contour glow.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('METALLIC CHISEL, REFLECTION & CONTOUR GLOW', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          buildSliderRow(context: context, title: 'Metallic Bevel Depth', val: project.textBevelDepth, min: 0.0, max: 3.0, onChanged: (v) { project.textBevelDepth = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Chrome Horizon Reflection', val: project.textChromeIntensity, min: 0.0, max: 3.0, onChanged: (v) { project.textChromeIntensity = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Specular Edge Glint', val: project.textSpecularGlint, min: 0.0, max: 2.0, onChanged: (v) { project.textSpecularGlint = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Grounding Contact Shadow', val: project.textContactShadow, min: 0.0, max: 1.0, onChanged: (v) { project.textContactShadow = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Text Luma Threshold', val: project.textLumaThreshold, min: 0.15, max: 0.95, onChanged: (v) { project.textLumaThreshold = v; onChanged(); }),

          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('METALLIC TINT FINISH', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                {'id': 0.0, 'name': 'Platinum Steel'},
                {'id': 1.0, 'name': 'Gold Ingot'},
                {'id': 2.0, 'name': 'Cyan Steel'},
                {'id': 3.0, 'name': 'Crimson Alloy'},
                {'id': 4.0, 'name': 'Violet Chrome'},
              ].map((t) {
                final isSel = project.textMetallicTint == t['id'];
                return ChoiceChip(
                  label: Text(t['name'] as String),
                  selected: isSel,
                  selectedColor: accent,
                  labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  onSelected: (s) {
                    if (s) {
                      project.textMetallicTint = t['id'] as double;
                      onChanged();
                    }
                  },
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('BOX POSITION & SIZE SLIDERS (FINGER ACCURATE)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          buildSliderRow(context: context, title: 'Box Width', val: project.textBoxW, min: 0.10, max: 1.0, onChanged: (v) { project.textBoxW = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Box Height', val: project.textBoxH, min: 0.05, max: 1.0, onChanged: (v) { project.textBoxH = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Horizontal Position (X)', val: project.textBoxX, min: 0.0, max: 1.0 - project.textBoxW, onChanged: (v) { project.textBoxX = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Vertical Position (Y)', val: project.textBoxY, min: 0.0, max: 1.0 - project.textBoxH, onChanged: (v) { project.textBoxY = v; onChanged(); }),
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
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export CC Preset', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a name for your preset export file:', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
        },
        'layers': project.layers.map((l) => l.toJson()).toList(),
      };

      final StringBuffer xmlBuffer = StringBuffer();
      xmlBuffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      xmlBuffer.writeln('<AERealityColorCorrection name="$presetName" version="1.0">');
      xmlBuffer.writeln('  <TonemapMode>${project.tonemapMode}</TonemapMode>');
      xmlBuffer.writeln('  <DeepTeal>${project.deepTeal}</DeepTeal>');
      xmlBuffer.writeln('  <MagicCurves>${project.magicCurves}</MagicCurves>');
      xmlBuffer.writeln('  <Layers count="${project.layers.length}">');
      for (final l in project.layers) {
        xmlBuffer.writeln('    <Layer name="${l.name}">');
        xmlBuffer.writeln('      <Opacity>${l.opacity}</Opacity>');
        xmlBuffer.writeln('      <Brightness>${l.brightness}</Brightness>');
        xmlBuffer.writeln('      <Contrast>${l.contrast}</Contrast>');
        xmlBuffer.writeln('      <Saturation>${l.saturation}</Saturation>');
        xmlBuffer.writeln('      <Hue>${l.hue}</Hue>');
        xmlBuffer.writeln('      <DeepGlow intensity="${l.deepGlowIntensity}" radius="${l.deepGlowRadius}" threshold="${l.deepGlowThreshold}" />');
        xmlBuffer.writeln('    </Layer>');
      }
      xmlBuffer.writeln('  </Layers>');
      xmlBuffer.writeln('</AERealityColorCorrection>');

      final docs = await getApplicationDocumentsDirectory();
      final jsonFile = File('${docs.path}/Shaderly_${safeName}_CC.json');
      await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(ccData));

      final xmlFile = File('${docs.path}/Shaderly_${safeName}_CC.xml');
      await xmlFile.writeAsString(xmlBuffer.toString());

      try {
        if (Platform.isAndroid) {
          final downloadsDir = Directory('/storage/emulated/0/Download');
          if (!downloadsDir.existsSync()) downloadsDir.createSync(recursive: true);
          await jsonFile.copy('${downloadsDir.path}/Shaderly_${safeName}_CC.json');
          await xmlFile.copy('${downloadsDir.path}/Shaderly_${safeName}_CC.xml');

          const channel = MethodChannel('com.aereality/media');
          await channel.invokeMethod('scanFile', {'path': '${downloadsDir.path}/Shaderly_${safeName}_CC.json'});
          await channel.invokeMethod('scanFile', {'path': '${downloadsDir.path}/Shaderly_${safeName}_CC.xml'});
        }
      } catch (_) {}

      scaffold.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF101016),
        content: Text('CC "$presetName" exported as JSON & XML to Downloads!', style: TextStyle(color: gCustomAccentColor.value, fontWeight: FontWeight.bold)),
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
        backgroundColor: kCardDark,
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
        allowedExtensions: ['json', 'xml', 'txt'],
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
            project.textBoxX = (ts['box_x'] as num?)?.toDouble() ?? 0.15;
            project.textBoxY = (ts['box_y'] as num?)?.toDouble() ?? 0.40;
            project.textBoxW = (ts['box_w'] as num?)?.toDouble() ?? 0.70;
            project.textBoxH = (ts['box_h'] as num?)?.toDouble() ?? 0.20;
            project.textBevelDepth = (ts['bevel_depth'] as num?)?.toDouble() ?? 1.0;
            project.textChromeIntensity = (ts['chrome_intensity'] as num?)?.toDouble() ?? 1.2;
            project.textSpecularGlint = (ts['specular_glint'] as num?)?.toDouble() ?? 1.0;
            project.textContactShadow = (ts['contact_shadow'] as num?)?.toDouble() ?? 0.8;
            project.textLumaThreshold = (ts['luma_threshold'] as num?)?.toDouble() ?? 0.65;
            project.textMetallicTint = (ts['metallic_tint'] as num?)?.toDouble() ?? 0.0;
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

  const DraggableTextBoundingBox({
    Key? key,
    required this.project,
    required this.containerSize,
    required this.onUpdated,
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

    return Positioned(
      left: left,
      top: top,
      width: math.max(60, width),
      height: math.max(45, height),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              setState(() {
                widget.project.textBoxX = (widget.project.textBoxX + details.delta.dx / parentW).clamp(0.0, 1.0 - widget.project.textBoxW);
                widget.project.textBoxY = (widget.project.textBoxY + details.delta.dy / parentH).clamp(0.0, 1.0 - widget.project.textBoxH);
              });
              widget.onUpdated();
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 2.0),
                color: accent.withOpacity(0.12),
              ),
              child: Center(
                child: Text(
                  'METALLIC TEXT MASK (${(widget.project.textBoxW * 100).toInt()}% x ${(widget.project.textBoxH * 100).toInt()}%)',
                  style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
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
                  backgroundColor: const Color(0xFF14141C),
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
          child: Text('Drag a point up / down to change $modeName for that colour. Double-tap the graph to reset this curve.',
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
