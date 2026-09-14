// =============================================================================
// AEReality / Shaderly - Editor Views & Export Suite (Part 2/2)
// True 32-Bit Float Linear Pipeline - Presets, Sliders, Tabs & HW MediaCodec
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4.0,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white12,
                thumbColor: accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
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
  // 1. PRESETS TAB
  // ---------------------------------------------------------------------------
  static Widget buildPresetsTab({
    required BuildContext context,
    required ProjectData project,
    required List<CustomPresetItem> customPresets,
    required String? selectedPresetName,
    required ValueChanged<String> onPresetSelected,
    required VoidCallback onSavePreset,
    required VoidCallback onImportPreset,
    required ValueChanged<int> onDeleteCustomPreset,
  }) {
    final accent = gCustomAccentColor.value;

    final builtInPresets = [
      {'name': 'Goku', 'color': 0xFFFFAB00},
      {'name': 'Desaturated', 'color': 0xFF90A4AE},
      {'name': 'Yamato', 'color': 0xFF00E5FF},
      {'name': 'Suguru', 'color': 0xFFB71C1C},
      {'name': 'Home-Made Sauce', 'color': 0xFFFF6F61},
      {'name': 'Rin', 'color': 0xFFE0E0E0},
      {'name': 'Sukuna', 'color': 0xFFFF1744},
      {'name': 'Toji', 'color': 0xFF78909C},
      {'name': 'Eren', 'color': 0xFFFF9100},
      {'name': 'Makima', 'color': 0xFFFFD1DC},
      {'name': 'Yuta', 'color': 0xFFE0E0E0},
      {'name': 'Okkotsu', 'color': 0xFF90A4AE},
      {'name': 'Artoria', 'color': 0xFFFFD700},
      {'name': 'Deku Tree', 'color': 0xFF00E676},
      {'name': 'Raiden', 'color': 0xFF7C4DFF},
      {'name': 'Atmospheric Haze', 'color': 0xFFB0BEC5},
      {'name': 'Tealdropped (conq knockoff)', 'color': 0xFF00E5FF},
      {'name': 'Vintage CC', 'color': 0xFFFFB74D},
      {'name': 'Noir', 'color': 0xFFB0BEC5},
      {'name': 'Choso', 'color': 0xFFB71C1C},
      {'name': 'Yoruichi', 'color': 0xFFAB47BC},
      {'name': 'Gojo', 'color': 0xFF00E5FF},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              onPressed: onSavePreset,
              icon: const Icon(Icons.bookmark_add_rounded, size: 16, color: Colors.black),
              label: const Text('SAVE CC', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onImportPreset,
              icon: Icon(Icons.file_open_rounded, size: 16, color: accent),
              label: Text('IMPORT JSON/XML', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
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
                onTap: () {
                  project.layers = custom.layers.map((l) => l.clone()).toList();
                  project.tonemapMode = custom.tonemapMode;
                  project.activeLayerIndex = 0;
                  onPresetSelected(custom.name);
                },
              ),
            );
          }),
          const SizedBox(height: 14),
        ],

        const Text('PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...builtInPresets.map((p) {
          final isSel = selectedPresetName == p['name'];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? accent.withOpacity(0.16) : kCardDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06)),
            ),
            child: ListTile(
              title: Text(p['name'] as String, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold)),
              trailing: isSel ? Icon(Icons.check_circle_rounded, color: accent, size: 18) : null,
              onTap: () => onPresetSelected(p['name'] as String),
            ),
          );
        }).toList(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. LUT TAB
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
  // 3. BASIC TAB
  // ---------------------------------------------------------------------------
  static Widget buildBasicGradingTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        buildSliderRow(context: context, title: 'Exposure', val: cur.brightness, min: -0.8, max: 0.8, onChanged: (v) { cur.brightness = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Contrast', val: cur.contrast, min: 0.2, max: 2.5, onChanged: (v) { cur.contrast = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Saturation', val: cur.saturation, min: 0.0, max: 2.5, onChanged: (v) { cur.saturation = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Gamma', val: cur.gamma, min: 0.2, max: 2.5, onChanged: (v) { cur.gamma = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Sharpness', val: cur.sharpness, min: 0.0, max: 2.0, onChanged: (v) { cur.sharpness = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Temperature', val: cur.temperature, min: 2000.0, max: 12000.0, onChanged: (v) { cur.temperature = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Highlights', val: cur.highlights, min: -1.0, max: 1.0, onChanged: (v) { cur.highlights = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shadows', val: cur.shadows, min: -1.0, max: 1.0, onChanged: (v) { cur.shadows = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Black Crush', val: cur.blackCrush, min: 0.0, max: 0.5, onChanged: (v) { cur.blackCrush = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DYNAMICS & FLICKER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Flicker Intensity', val: cur.flickerIntensity, min: 0.0, max: 1.0, onChanged: (v) { cur.flickerIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flicker Speed (Hz)', val: cur.flickerSpeed, min: 1.0, max: 20.0, onChanged: (v) { cur.flickerSpeed = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        buildSliderRow(context: context, title: 'Sobel Cel Darkener', val: cur.darkOutlines, min: 0.0, max: 1.0, onChanged: (v) { cur.darkOutlines = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Edge Darken', val: cur.edgeDarken, min: 0.0, max: 1.0, onChanged: (v) { cur.edgeDarken = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Radial Vignette', val: cur.vignette, min: 0.0, max: 1.0, onChanged: (v) { cur.vignette = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Boxed Vignette', val: cur.vignetteBoxed, min: 0.0, max: 1.0, onChanged: (v) { cur.vignetteBoxed = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. MAGIC TAB (Magic Bullet Suite Replication)
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
          child: Text('MAGIC (MAGIC BULLET SUITE REPLICATION)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Mojo Slider (Teal & Orange Split)', val: cur.mblMojoTealOrange, min: 0.0, max: 1.5, onChanged: (v) { cur.mblMojoTealOrange = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Cosmo Clean Highlights (Face Protection)', val: cur.cosmoCleanHighlight, min: 0.0, max: 1.0, onChanged: (v) { cur.cosmoCleanHighlight = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Lift (Shadows)', val: cur.mblColoristaLift, min: -0.5, max: 0.5, onChanged: (v) { cur.mblColoristaLift = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Gamma (Midtones)', val: cur.mblColoristaGamma, min: -0.5, max: 0.5, onChanged: (v) { cur.mblColoristaGamma = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Gain (Highlights)', val: cur.mblColoristaGain, min: -0.5, max: 0.5, onChanged: (v) { cur.mblColoristaGain = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. COPIED STUFF TAB (After Effects Anime CC)
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
        buildSliderRow(context: context, title: 'Sapphire Edge Detect Glow', val: cur.copiedEdgeRays, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedEdgeRays = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Pro-Mist Halation (Black Line Safe)', val: cur.copiedProMist, min: 0.0, max: 1.0, onChanged: (v) { cur.copiedProMist = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Star Sparkle / Glint Cross', val: cur.copiedStarGlint, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedStarGlint = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 6. GLOWS & FLARES TAB
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
          child: Text('DEEP GLOW & AMBIENCE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deep Glow Intensity', val: cur.deepGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.deepGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Radius', val: cur.deepGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.deepGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Threshold (Protects Faces)', val: cur.deepGlowThreshold, min: 0.20, max: 0.95, onChanged: (v) { cur.deepGlowThreshold = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Centre Aura', val: cur.centerAura, min: 0.0, max: 1.5, onChanged: (v) { cur.centerAura = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Horizontal Ramp', val: cur.horizontalRamp, min: 0.0, max: 1.0, onChanged: (v) { cur.horizontalRamp = v; onChanged(); }, onEnded: onEnded),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('GLOW TINT', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 8,
            children: [
              {'id': 0.0, 'name': 'Natural White'},
              {'id': 1.0, 'name': 'Noble Gold'},
              {'id': 2.0, 'name': 'Cyan / Teal'},
              {'id': 3.0, 'name': 'Amber Sun'},
              {'id': 4.0, 'name': 'Blood Crimson'},
              {'id': 5.0, 'name': 'Electro Violet'},
            ].map((t) {
              final isSel = cur.edgeGlowTint == t['id'];
              return ChoiceChip(
                label: Text(t['name'] as String),
                selected: isSel,
                selectedColor: accent,
                labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
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
          child: Text('SELECTABLE VIDEO FLARES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 8,
            children: [
              {'id': 0, 'name': 'None'},
              {'id': 1, 'name': 'Anamorphic Blue'},
              {'id': 2, 'name': 'Golden Sun'},
              {'id': 3, 'name': 'Laser White'},
            ].map((flare) {
              final isSel = cur.videoFlareType == flare['id'];
              return ChoiceChip(
                label: Text(flare['name'] as String),
                selected: isSel,
                selectedColor: accent,
                labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                onSelected: (s) {
                  if (s) {
                    cur.videoFlareType = flare['id'] as int;
                    onChanged();
                    onEnded();
                  }
                },
              );
            }).toList(),
          ),
        ),
        buildSliderRow(context: context, title: 'Flare Intensity', val: cur.thinStreakIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.thinStreakIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Width', val: cur.thinStreakWidth, min: 0.05, max: 2.0, onChanged: (v) { cur.thinStreakWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Opacity', val: cur.thinStreakOpacity, min: 0.0, max: 1.0, onChanged: (v) { cur.thinStreakOpacity = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. ATMOSPHERE TAB
  // ---------------------------------------------------------------------------
  static Widget buildAtmosphereTab({
    required BuildContext context,
    required AdjustmentLayer cur,
    required VoidCallback onChanged,
    required VoidCallback onEnded,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        buildSliderRow(context: context, title: 'Light Shafts (God Rays)', val: cur.bslaGodRays, min: 0.0, max: 1.5, onChanged: (v) { cur.bslaGodRays = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Fog Density', val: cur.bslaFogDensity, min: 0.0, max: 1.0, onChanged: (v) { cur.bslaFogDensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Bloom Haze', val: cur.bslaBloomHaze, min: 0.0, max: 1.5, onChanged: (v) { cur.bslaBloomHaze = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Light Scatter', val: cur.bslFogScatter, min: 0.0, max: 1.5, onChanged: (v) { cur.bslFogScatter = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Halation Radius', val: cur.halationRadius, min: 0.0, max: 1.5, onChanged: (v) { cur.halationRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Halation Warmth', val: cur.halationWarmth, min: 0.0, max: 1.5, onChanged: (v) { cur.halationWarmth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Film Grain', val: cur.filmGrain, min: 0.0, max: 1.0, onChanged: (v) { cur.filmGrain = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Denoise Filter', val: cur.denoise, min: 0.0, max: 1.0, onChanged: (v) { cur.denoise = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 8. CURVES TAB
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
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: const Color(0xFF0C0C12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: SplineCurvePainter(points: activeCurve, curveColor: curveColor),
            ),
          ),
        ),
        const SizedBox(height: 16),
        buildSliderRow(context: context, title: 'Black Point (0.00)', val: activeCurve[0], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[0] = v; onChanged(); }),
        buildSliderRow(context: context, title: 'Shadow Lift (0.25)', val: activeCurve[1], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[1] = v; onChanged(); }),
        buildSliderRow(context: context, title: 'Midtone Gamma (0.50)', val: activeCurve[2], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[2] = v; onChanged(); }),
        buildSliderRow(context: context, title: 'Highlight Rolloff (0.75)', val: activeCurve[3], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[3] = v; onChanged(); }),
        buildSliderRow(context: context, title: 'White Clip (1.00)', val: activeCurve[4], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[4] = v; onChanged(); }),
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

  // ---------------------------------------------------------------------------
  // UNSHARP MASK DRAWER
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

  // ---------------------------------------------------------------------------
  // PRESET LOGIC ENGINE
  // ---------------------------------------------------------------------------
  static void applyPresetLogic(ProjectData project, String name) {
    project.layers.clear();

    switch (name.toLowerCase()) {
      // PRESERVED BUILT-IN PRESETS (UNCHANGED AS MANDATED)
      case 'goku':
        project.layers.add(AdjustmentLayer(
          id: 'goku_base',
          name: 'Base Grade',
          contrast: 1.44,
          saturation: 0.82,
          brightness: 0.01,
          temperature: 7300.0,
          sharpness: 0.58,
          shadows: -0.16,
          highlights: 0.22,
          blackCrush: 0.06,
          edgeDarken: 0.26,
          darkOutlines: 0.16,
          vignette: 0.05,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.16, 0.47, 0.86, 1.0],
          flickerIntensity: 0.04,
          flickerSpeed: 12.0,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'goku_rim',
          name: 'Specular Rim',
          blendMode: LayerBlendMode.screen,
          opacity: 0.78,
          deepGlowIntensity: 0.42,
          deepGlowRadius: 0.52,
          deepGlowThreshold: 0.50,
          edgeGlowTint: 1.0,
          thinStreakIntensity: 0.28,
          thinStreakWidth: 0.65,
          thinStreakOpacity: 0.82,
          lineChromaStrength: 0.25,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'goku_atmo',
          name: 'Atmospheric Haze',
          blendMode: LayerBlendMode.screen,
          opacity: 0.65,
          bslaBloomHaze: 0.58,
          bslFogScatter: 0.35,
          bslaFogDensity: 0.25,
          deepGlowIntensity: 0.28,
          deepGlowRadius: 0.68,
          deepGlowThreshold: 0.44,
        ));
        break;

      case 'desaturated':
        project.layers.add(AdjustmentLayer(
          id: 'desat_base',
          name: 'Base Grade',
          contrast: 1.48,
          saturation: 0.60,
          brightness: -0.02,
          temperature: 6900.0,
          sharpness: 0.62,
          shadows: -0.18,
          highlights: 0.14,
          blackCrush: 0.08,
          edgeDarken: 0.32,
          darkOutlines: 0.20,
          vignette: 0.06,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.02, 0.14, 0.46, 0.84, 0.98],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'desat_curve',
          name: 'Cold Tone',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.75,
          contrast: 1.15,
          saturation: 0.75,
          temperature: 7600.0,
          curveBlue: [0.04, 0.20, 0.50, 0.82, 0.96],
          curveRed: [0.0, 0.14, 0.46, 0.80, 0.96],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'desat_glow',
          name: 'Edge Specular',
          blendMode: LayerBlendMode.screen,
          opacity: 0.68,
          deepGlowIntensity: 0.34,
          deepGlowRadius: 0.44,
          deepGlowThreshold: 0.54,
          lineChromaStrength: 0.30,
          thinStreakIntensity: 0.14,
          thinStreakOpacity: 0.70,
        ));
        break;

      case 'okkotsu':
        project.layers.add(AdjustmentLayer(
          id: 'okkotsu_base',
          name: 'Base Grade',
          contrast: 1.28,
          saturation: 0.82,
          brightness: -0.02,
          temperature: 7200.0,
          sharpness: 0.48,
          shadows: -0.12,
          edgeDarken: 0.22,
          darkOutlines: 0.10,
          vignette: 0.05,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.48, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'okkotsu_rim',
          name: 'Specular Rim',
          blendMode: LayerBlendMode.screen,
          opacity: 0.68,
          deepGlowIntensity: 0.32,
          deepGlowRadius: 0.45,
          deepGlowThreshold: 0.52,
          thinStreakIntensity: 0.15,
          thinStreakOpacity: 0.70,
        ));
        break;

      case 'tealdropped (conq knockoff)':
        project.layers.add(AdjustmentLayer(
          id: 'conq_base',
          name: 'Base Grade',
          contrast: 1.18,
          saturation: 1.06,
          brightness: 0.03,
          temperature: 6800.0,
          sharpness: 0.44,
          shadows: 0.02,
          vignette: 0.04,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.25, 0.52, 0.82, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'conq_glow',
          name: 'Teal Rim',
          blendMode: LayerBlendMode.screen,
          opacity: 0.82,
          deepGlowIntensity: 0.45,
          deepGlowRadius: 0.55,
          deepGlowThreshold: 0.44,
          edgeGlowTint: 2.0,
          thinStreakIntensity: 0.22,
          thinStreakWidth: 0.60,
          thinStreakOpacity: 0.85,
          lineChromaStrength: 0.35,
        ));
        break;

      case 'yuta':
        project.layers.add(AdjustmentLayer(
          id: 'yuta_base',
          name: 'Base Grade',
          contrast: 1.40,
          saturation: 0.80,
          brightness: 0.01,
          temperature: 6400.0,
          sharpness: 0.56,
          shadows: -0.12,
          highlights: 0.18,
          blackCrush: 0.05,
          edgeDarken: 0.26,
          darkOutlines: 0.16,
          vignette: 0.04,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.17, 0.48, 0.85, 1.0],
          flickerIntensity: 0.035,
          flickerSpeed: 11.0,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yuta_ivory_bloom',
          name: 'Ivory Bloom',
          blendMode: LayerBlendMode.screen,
          opacity: 0.76,
          deepGlowIntensity: 0.42,
          deepGlowRadius: 0.48,
          deepGlowThreshold: 0.50,
          edgeGlowTint: 1.0,
          thinStreakIntensity: 0.24,
          thinStreakOpacity: 0.80,
          lineChromaStrength: 0.24,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yuta_atmo',
          name: 'Atmospheric Fog',
          blendMode: LayerBlendMode.screen,
          opacity: 0.60,
          bslaBloomHaze: 0.45,
          bslFogScatter: 0.32,
        ));
        break;

      case 'vintage cc':
        project.layers.add(AdjustmentLayer(
          id: 'vint_base',
          name: 'Base Grade',
          contrast: 1.20,
          saturation: 0.82,
          temperature: 5900.0,
          shadows: 0.04,
          highlights: -0.04,
          vignette: 0.05,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.03, 0.24, 0.49, 0.80, 0.96],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'vint_grain',
          name: 'Halation & Grain',
          blendMode: LayerBlendMode.screen,
          opacity: 0.76,
          deepGlowIntensity: 0.36,
          deepGlowRadius: 0.58,
          deepGlowThreshold: 0.46,
          edgeGlowTint: 1.0,
          halationRadius: 0.25,
          halationWarmth: 0.80,
          filmGrain: 0.11,
        ));
        break;

      // REVAMPED DISTINCT PRESETS
      case 'yamato':
        project.layers.add(AdjustmentLayer(
          id: 'yamato_base',
          name: 'Base Grade',
          contrast: 1.40,
          saturation: 0.92,
          temperature: 6600.0,
          sharpness: 0.56,
          shadows: -0.12,
          highlights: 0.16,
          edgeDarken: 0.28,
          blendMode: LayerBlendMode.normal,
          mblMojoTealOrange: 0.35,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yamato_specular',
          name: 'Cyan Specular',
          blendMode: LayerBlendMode.screen,
          opacity: 0.76,
          deepGlowIntensity: 0.44,
          deepGlowRadius: 0.50,
          deepGlowThreshold: 0.48,
          edgeGlowTint: 2.0,
          thinStreakIntensity: 0.24,
        ));
        break;

      case 'suguru':
        project.layers.add(AdjustmentLayer(
          id: 'suguru_base',
          name: 'Base Grade',
          contrast: 1.46,
          saturation: 0.78,
          temperature: 6400.0,
          shadows: -0.16,
          blackCrush: 0.09,
          edgeDarken: 0.30,
          darkOutlines: 0.22,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'suguru_curse',
          name: 'Curse Halation',
          blendMode: LayerBlendMode.screen,
          opacity: 0.74,
          halationRadius: 0.28,
          halationWarmth: 0.82,
          deepGlowIntensity: 0.38,
          edgeGlowTint: 4.0,
        ));
        break;

      default:
        project.layers.add(AdjustmentLayer(
          id: 'default_base',
          name: 'Base Grade',
          contrast: 1.15,
          saturation: 1.05,
          sharpness: 0.35,
          blendMode: LayerBlendMode.normal,
        ));
    }
    project.activeLayerIndex = 0;
  }

  // ---------------------------------------------------------------------------
  // PRESET SAVE / IMPORT HELPERS
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

  static Future<void> importPresetFromFile(BuildContext context, ProjectData project) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);

        if (data.containsKey('layers')) {
          final List<dynamic> layerList = data['layers'];
          project.layers.clear();
          for (var l in layerList) {
            project.layers.add(AdjustmentLayer.fromJson(l));
          }
          if (data.containsKey('tonemapMode')) {
            project.tonemapMode = (data['tonemapMode'] as num).toDouble();
          }
          project.activeLayerIndex = 0;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Loaded preset successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid preset file: $e'), backgroundColor: Colors.red),
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
  // 9. EXPORT SUITE (Hardware MediaCodec & Multi-Resolution Engine)
  // ---------------------------------------------------------------------------
  static void showExportSheet({
    required BuildContext context,
    required ProjectData project,
    required AdjustmentLayer curLayer,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) {
    String selectedContainer = 'MP4';
    String selectedCodec = 'H.264 (Hardware MediaCodec)';
    String selectedBitDepth = '8-bit';
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBitrate = '35 Mbps';
    String selectedAudioMode = 'Lossless Source Copy';

    final containers = ['MP4', 'WebM', 'MOV', 'MKV'];
    final resolutions = ['720p', '1080p', '2K', '4K'];
    final fpsOptions = ['24fps', '30fps', '60fps', '90fps'];
    final bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps', '80 Mbps', '120 Mbps', 'Lossless Variable'];

    final accent = gCustomAccentColor.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final availableCodecs = ExportMatrix.containerCodecs[selectedContainer] ?? ['H.264 (Hardware MediaCodec)'];
            if (!availableCodecs.contains(selectedCodec)) {
              selectedCodec = availableCodecs.first;
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Render Master', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Text(
                      'Destination: /storage/emulated/0/Shaderly • 32-bit Vulkan Compute',
                      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    const Text('CONTAINER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: containers.map((c) => ChoiceChip(
                        label: Text(c),
                        selected: selectedContainer == c,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedContainer == c ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) {
                            setStateModal(() {
                              selectedContainer = c;
                              selectedCodec = (ExportMatrix.containerCodecs[c] ?? ['H.264 (Hardware MediaCodec)']).first;
                              if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
                                selectedBitDepth = '8-bit';
                              }
                            });
                          }
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('CODECS FOR $selectedContainer', style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: availableCodecs.map((codec) {
                        return ChoiceChip(
                          label: Text(codec),
                          selected: selectedCodec == codec,
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF18181E),
                          labelStyle: TextStyle(color: selectedCodec == codec ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (sel) {
                            if (sel) {
                              setStateModal(() {
                                selectedCodec = codec;
                                if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
                                  selectedBitDepth = '8-bit';
                                }
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('BIT-DEPTH PRECISION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: ['8-bit', '10-bit', '16-bit'].map((depth) {
                        final isValid = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, depth);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Text(depth),
                              selected: selectedBitDepth == depth,
                              selectedColor: accent,
                              backgroundColor: isValid ? const Color(0xFF18181E) : Colors.black26,
                              labelStyle: TextStyle(
                                color: !isValid
                                    ? Colors.white24
                                    : (selectedBitDepth == depth ? Colors.black : Colors.white),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              onSelected: isValid ? (_) => setStateModal(() => selectedBitDepth = depth) : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('RESOLUTION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: resolutions.map((res) => ChoiceChip(
                        label: Text(res),
                        selected: selectedRes == res,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedRes = res);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('FRAMERATE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: fpsOptions.map((fps) => ChoiceChip(
                        label: Text(fps),
                        selected: selectedFps == fps,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedFps == fps ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedFps = fps);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('TARGET BITRATE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: bitrateOptions.map((bit) {
                        final isValid = ExportMatrix.isBitrateValid(selectedCodec, bit);
                        return ChoiceChip(
                          label: Text(bit),
                          selected: selectedBitrate == bit,
                          selectedColor: accent,
                          backgroundColor: isValid ? const Color(0xFF18181E) : Colors.black26,
                          labelStyle: TextStyle(
                            color: !isValid ? Colors.white24 : (selectedBitrate == bit ? Colors.black : Colors.white),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          onSelected: isValid ? (sel) {
                            if (sel) setStateModal(() => selectedBitrate = bit);
                          } : null,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          executeVideoExport(
                            context: context,
                            project: project,
                            resolution: selectedRes,
                            fps: selectedFps,
                            bitrate: selectedBitrate,
                            container: selectedContainer,
                            codec: selectedCodec,
                            bitDepth: selectedBitDepth,
                            audioMode: selectedAudioMode,
                            packUniforms: packUniforms,
                            getActiveLut: getActiveLut,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'RENDER $selectedContainer (${selectedCodec.split(' ').first} • $selectedBitDepth)',
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> executeVideoExport({
    required BuildContext context,
    required ProjectData project,
    required String resolution,
    required String fps,
    required String bitrate,
    required String container,
    required String codec,
    required String bitDepth,
    required String audioMode,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) async {
    if (project.mediaPath.isEmpty) return;

    int baseSize;
    switch (resolution) {
      case '720p': baseSize = 720; break;
      case '1080p': baseSize = 1080; break;
      case '2K': baseSize = 1440; break;
      case '4K': baseSize = 2160; break;
      default: baseSize = 1080;
    }

    double ratio = 16 / 9;
    if (project.aspectRatio == '9:16') ratio = 9 / 16;
    else if (project.aspectRatio == '4:5') ratio = 4 / 5;
    else if (project.aspectRatio == '1:1') ratio = 1 / 1;
    else if (project.aspectRatio == '3:4') ratio = 3 / 4;
    else if (project.aspectRatio == '21:9') ratio = 21 / 9;

    int outW, outH;
    if (ratio < 1.0) {
      outW = baseSize;
      outH = (outW / ratio).round();
    } else {
      outH = baseSize;
      outW = (outH * ratio).round();
    }
    outW = math.max(16, ((outW + 15) ~/ 16) * 16);
    outH = math.max(16, ((outH + 15) ~/ 16) * 16);

    final uniforms = packUniforms(outW.toDouble(), outH.toDouble());
    final lutTable = getActiveLut();

    int bitrateKbps = 35000;
    if (bitrate.contains('15')) bitrateKbps = 15000;
    else if (bitrate.contains('50')) bitrateKbps = 50000;
    else if (bitrate.contains('80')) bitrateKbps = 80000;
    else if (bitrate.contains('120')) bitrateKbps = 120000;

    int targetFps = int.parse(fps.replaceAll('fps', ''));
    String containerExt = container.toLowerCase();

    final bool is16Bit = bitDepth == '16-bit';
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Initializing 32-bit Vulkan Engine: 0%');
    bool isCancelled = false;
    FFmpegSession? activeSession;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101014),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Exporting $outW x $outH ($bitDepth)', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
              onPressed: () {
                isCancelled = true;
                activeSession?.cancel();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export cancelled by user.')));
              },
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (_, progress, __) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: progress, minHeight: 8, color: kCyanAccent, backgroundColor: Colors.white12),
              ),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (_, status, __) => Text(status, style: const TextStyle(color: kCyanAccent, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final framesDir = Directory('${dir.path}/export_frames');
      final processedDir = Directory('${dir.path}/export_processed');

      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      if (await processedDir.exists()) await processedDir.delete(recursive: true);
      await framesDir.create(recursive: true);
      await processedDir.create(recursive: true);

      final audioPath = '${dir.path}/current_audio.aac';
      final oldAudio = File(audioPath);
      if (await oldAudio.exists()) await oldAudio.delete();
      await FFmpegKit.execute('-hide_banner -i "${project.mediaPath}" -vn -c:a aac -y "$audioPath"');

      if (isCancelled) return;

      statusNotifier.value = 'Extracting $outW x $outH frames...';
      activeSession = await FFmpegKit.execute(
        '-hide_banner -i "${project.mediaPath}" -r $targetFps -s ${outW}x${outH} -pix_fmt rgba -y "${framesDir.path}/frame_%05d.png"',
      );

      if (isCancelled) return;

      var frameFiles = await framesDir.list().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      final totalFrames = frameFiles.length;

      if (totalFrames == 0) {
        throw Exception('Frame extraction failed.');
      }

      for (int i = 0; i < totalFrames; i++) {
        if (isCancelled) return;

        final file = frameFiles[i];
        if (file is! File) continue;
        final bytes = await file.readAsBytes();
        final decoded = img.decodePng(bytes);
        if (decoded == null) continue;

        uniforms[0] = i / targetFps.toDouble();

        img.Image gradedImg;
        if (is16Bit) {
          final rawInput8 = decoded.getBytes(order: img.ChannelOrder.rgba);
          final rawInput16 = Uint16List(outW * outH * 4);
          for (int px = 0; px < rawInput8.length; px++) {
            rawInput16[px] = (rawInput8[px] << 8) | rawInput8[px];
          }
          final outputRaw16 = processImage16(rawInput16, outW, outH, outW, outH, uniforms, lutTable: lutTable);
          gradedImg = img.Image.fromBytes(
            width: outW,
            height: outH,
            bytes: outputRaw16.buffer,
            numChannels: 4,
            format: img.Format.uint16,
            order: img.ChannelOrder.rgba,
          );
        } else {
          final rawInput8 = decoded.getBytes(order: img.ChannelOrder.rgba);
          final outputRaw8 = processImage(rawInput8, outW, outH, outW, outH, uniforms, lutTable: lutTable);
          gradedImg = img.Image.fromBytes(
            width: outW,
            height: outH,
            bytes: outputRaw8.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba,
          );
        }

        final pngBytes = img.encodePng(gradedImg);
        final paddedIndex = (i + 1).toString().padLeft(5, '0');
        final outputFile = File('${processedDir.path}/frame_$paddedIndex.png');
        await outputFile.writeAsBytes(pngBytes);

        progressNotifier.value = (i + 1) / totalFrames;
        statusNotifier.value = 'Grading frames: ${(((i + 1) / totalFrames) * 100).toInt()}% (${i + 1}/$totalFrames)';
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (isCancelled) return;

      statusNotifier.value = 'Encoding hardware master ($codec)...';
      final silentOutputPath = '${dir.path}/silent_video.$containerExt';
      final silentFile = File(silentOutputPath);
      if (await silentFile.exists()) await silentFile.delete();

      final encodeCmd = ExportMatrix.buildFFmpegEncodeCommand(
        fps: targetFps,
        framePattern: '${processedDir.path}/frame_%05d.png',
        container: container,
        codec: codec,
        bitDepth: bitDepth,
        bitrateKbps: bitrateKbps,
        outputPath: silentOutputPath,
      );
      activeSession = await FFmpegKit.execute(encodeCmd);

      if (isCancelled) return;

      if (!await silentFile.exists()) {
        final logs = await activeSession.getLogsAsString();
        throw Exception('Hardware encoder failed: ${logs ?? "No logs"}');
      }

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length()) > 1000;
      final shaderlyDir = Directory('/storage/emulated/0/Shaderly');
      final cleanCodec = codec.split(' ').first;
      final fileName = 'Shaderly_${resolution}_${cleanCodec}_${bitDepth}_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      final finalOutputFile = File('${shaderlyDir.path}/$fileName');

      if (hasAudio) {
        final audioCodec = ExportMatrix.getAudioCodec(container);
        await FFmpegKit.execute('-hide_banner -i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $audioCodec -shortest -y "${finalOutputFile.path}"');
      } else {
        await File(silentOutputPath).copy(finalOutputFile.path);
      }

      if (!isCancelled && context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Master Saved to /storage/emulated/0/Shaderly:\n${finalOutputFile.path}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!isCancelled && context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

class SplineCurvePainter extends CustomPainter {
  final List<double> points;
  final Color curveColor;

  SplineCurvePainter({required this.points, required this.curveColor});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.0;

    for (int i = 1; i < 4; i++) {
      double x = size.width * (i / 4.0);
      double y = size.height * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = curveColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int px = 0; px <= size.width.toInt(); px++) {
      double normX = px / size.width;
      double normY = _evalCatmullRom(normX, points);
      double py = size.height - (normY * size.height);

      if (px == 0) {
        path.moveTo(px.toDouble(), py.clamp(0.0, size.height));
      } else {
        path.lineTo(px.toDouble(), py.clamp(0.0, size.height));
      }
    }
    canvas.drawPath(path, linePaint);

    final knotPaint = Paint()..color = curveColor;
    for (int i = 0; i < 5; i++) {
      double kx = size.width * (i / 4.0);
      double ky = size.height - (points[i] * size.height);
      canvas.drawCircle(Offset(kx, ky.clamp(0.0, size.height)), 5.0, knotPaint);
      canvas.drawCircle(Offset(kx, ky.clamp(0.0, size.height)), 2.5, Paint()..color = Colors.black);
    }
  }

  double _evalCatmullRom(double x, List<double> p) {
    x = x.clamp(0.0, 1.0);
    double seg = x * 4.0;
    int idx = seg.floor();
    if (idx >= 4) return p[4];
    double t = seg - idx;

    double p0 = (idx == 0) ? p[0] : (idx == 1) ? p[0] : (idx == 2) ? p[1] : p[2];
    double p1 = (idx == 0) ? p[0] : (idx == 1) ? p[1] : (idx == 2) ? p[2] : p[3];
    double p2 = (idx == 0) ? p[1] : (idx == 1) ? p[2] : (idx == 2) ? p[3] : p[4];
    double p3 = (idx == 0) ? p[2] : (idx == 1) ? p[3] : (idx == 2) ? p[4] : p[4];

    double m1 = 0.5 * (p2 - p0);
    double m2 = 0.5 * (p3 - p1);

    double t2 = t * t;
    double t3 = t2 * t;

    double h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    double h10 = t3 - 2.0 * t2 + t;
    double h01 = -2.0 * t3 + 3.0 * t2;
    double h11 = t3 - t2;

    return (h00 * p1 + h10 * m1 + h01 * p2 + h11 * m2).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant SplineCurvePainter oldDelegate) => true;
}
