// =============================================================================
// AEReality / Shaderly - Editor Views & Export Suite
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
  // 1. PRESETS TAB (Tap-To-Toggle + BSL Atmospheric Overlay + Export CC Button)
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
              'BSL Volumetric Mist & God Rays Overlay',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: const Text(
              'Stackable atmospheric fog & light shafts across all active layers',
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
              title: Text(p.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(p.description, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              trailing: isSel ? Icon(Icons.check_circle_rounded, color: accent, size: 18) : null,
              onTap: () => onPresetSelected(p.name),
            ),
          );
        }).toList(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. TONEMAPPERS TAB
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
        'desc': 'Raw floating-point color response with no dynamic curve compression.',
      },
      {
        'mode': 1.0,
        'title': 'Shaderly Tonemapper 1 (ACES Filmic Studio)',
        'desc': 'Academy Color Encoding System curve with cinematic toe and rich highlight rolloff.',
      },
      {
        'mode': 2.0,
        'title': 'Shaderly Tonemapper 2 (AgX Dynamic Metal)',
        'desc': 'Modern perceptual dynamic range tonemapper protecting saturated highlight values.',
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
  // 3. LUT TAB
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
  // 4. BASIC TAB (Includes Restored Hue/Color Rotate Slider)
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
        buildSliderRow(context: context, title: 'Hue / Color Rotate', val: cur.hue, min: -3.14159, max: 3.14159, onChanged: (v) { cur.hue = v; onChanged(); }, onEnded: onEnded),
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
  // 5. MAGIC TAB
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
        buildSliderRow(context: context, title: 'Sapphire Edge Detect Glow', val: cur.copiedEdgeRays, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedEdgeRays = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Pro-Mist Halation (Black Line Safe)', val: cur.copiedProMist, min: 0.0, max: 1.0, onChanged: (v) { cur.copiedProMist = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Star Sparkle / Glint Cross', val: cur.copiedStarGlint, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedStarGlint = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. GLOWS & FLARES TAB
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
          child: Text('DEEP GLOW (REAL GAUSSIAN MULTI-OCTAVE BLOOM)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Deep Glow Intensity', val: cur.deepGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.deepGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Radius', val: cur.deepGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.deepGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Deep Glow Threshold', val: cur.deepGlowThreshold, min: 0.15, max: 0.90, onChanged: (v) { cur.deepGlowThreshold = v; onChanged(); }, onEnded: onEnded),
        
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('SAPPHIRE S_GLOW (SPECULAR FREQUENCY CORE)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Sapphire Glow Width & Intensity', val: cur.sapphireGlowWidth, min: 0.0, max: 2.0, onChanged: (v) { cur.sapphireGlowWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Sapphire Glow Threshold', val: cur.sapphireGlowThreshold, min: 0.20, max: 0.95, onChanged: (v) { cur.sapphireGlowThreshold = v; onChanged(); }, onEnded: onEnded),

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
          child: Text('AMANAI OPTICAL ANAMORPHIC FLARES (COLOR INHERITANCE)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Flare Intensity', val: cur.thinStreakIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.thinStreakIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Width', val: cur.thinStreakWidth, min: 0.05, max: 2.0, onChanged: (v) { cur.thinStreakWidth = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Flare Opacity', val: cur.thinStreakOpacity, min: 0.0, max: 1.0, onChanged: (v) { cur.thinStreakOpacity = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 8. ATMOSPHERE TAB
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
  // 9. CURVES TAB
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

  static void applyBslOverlay({required ProjectData project, required bool active}) {
    project.layers.removeWhere((l) => l.id == 'bsl_atmospheric_overlay_layer');
    if (active) {
      project.layers.add(AdjustmentLayer(
        id: 'bsl_atmospheric_overlay_layer',
        name: 'BSL Atmospheric Mist',
        blendMode: LayerBlendMode.screen,
        opacity: 0.65,
        bslaGodRays: 0.35,
        bslaFogDensity: 0.28,
        bslaBloomHaze: 0.40,
        bslFogScatter: 0.32,
        deepGlowIntensity: 0.22,
        deepGlowRadius: 0.55,
      ));
    }
  }

  static void clearPresetToNeutral(ProjectData project) {
    project.layers.clear();
    project.layers.add(AdjustmentLayer(
      id: 'neutral_base',
      name: 'Base Grade',
      contrast: 1.0,
      saturation: 1.0,
      brightness: 0.0,
      blendMode: LayerBlendMode.normal,
    ));
    project.activeLayerIndex = 0;
  }

  // ---------------------------------------------------------------------------
  // FULL PRESET ENGINE (ADEVOB / CONQUESTOR METALLIC LOOK - ZERO BLOWOUT)
  // ---------------------------------------------------------------------------
  static void applyPresetLogic(ProjectData project, String name) {
    project.layers.clear();

    switch (name.toLowerCase()) {
      case 'goku':
        project.layers.add(AdjustmentLayer(
          id: 'goku_base',
          name: 'Base Grade',
          contrast: 1.35,
          saturation: 1.05,
          brightness: 0.01,
          temperature: 6800.0,
          sharpness: 0.55,
          shadows: -0.12,
          highlights: 0.15,
          blackCrush: 0.03,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.04,
          cosmoCleanHighlight: 0.45,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'goku_specular_core',
          name: 'Specular Golden Core',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.75,
          deepGlowIntensity: 0.38,
          deepGlowRadius: 0.42,
          deepGlowThreshold: 0.55,
          edgeGlowTint: 1.0,
          sapphireGlowWidth: 0.35,
          sapphireGlowThreshold: 0.65,
          thinStreakIntensity: 0.28,
          thinStreakWidth: 0.55,
          thinStreakOpacity: 0.80,
        ));
        break;

      case 'desaturated':
        project.layers.add(AdjustmentLayer(
          id: 'desat_base',
          name: 'Base Grade',
          contrast: 1.40,
          saturation: 0.52,
          brightness: -0.02,
          temperature: 7400.0,
          sharpness: 0.68,
          shadows: -0.15,
          highlights: 0.12,
          blackCrush: 0.04,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.05,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.02, 0.15, 0.48, 0.82, 0.98],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'desat_ice_glow',
          name: 'Ice Cyan Specular',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.68,
          deepGlowIntensity: 0.32,
          deepGlowRadius: 0.38,
          deepGlowThreshold: 0.58,
          edgeGlowTint: 2.0,
          sapphireGlowWidth: 0.28,
          sapphireGlowThreshold: 0.65,
        ));
        break;

      case 'yamato':
        project.layers.add(AdjustmentLayer(
          id: 'yamato_base',
          name: 'Base Grade',
          contrast: 1.32,
          saturation: 0.92,
          temperature: 7600.0,
          sharpness: 0.58,
          shadows: -0.12,
          highlights: 0.15,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
          mblMojoTealOrange: 0.28,
          curveMaster: [0.0, 0.19, 0.51, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yamato_frost',
          name: 'Frost Edge Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.72,
          deepGlowIntensity: 0.35,
          deepGlowRadius: 0.45,
          deepGlowThreshold: 0.52,
          edgeGlowTint: 2.0,
          sapphireGlowWidth: 0.38,
          sapphireGlowThreshold: 0.60,
          thinStreakIntensity: 0.22,
          thinStreakWidth: 0.48,
          thinStreakOpacity: 0.75,
        ));
        break;

      case 'suguru':
        project.layers.add(AdjustmentLayer(
          id: 'suguru_base',
          name: 'Base Grade',
          contrast: 1.45,
          saturation: 0.85,
          temperature: 6200.0,
          shadows: -0.18,
          blackCrush: 0.06,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.14, 0.46, 0.82, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'suguru_curse_blood',
          name: 'Blood Crimson Core',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.76,
          halationRadius: 0.25,
          halationWarmth: 0.75,
          deepGlowIntensity: 0.38,
          edgeGlowTint: 4.0,
          sapphireGlowWidth: 0.38,
          sapphireGlowThreshold: 0.60,
          thinStreakIntensity: 0.28,
          thinStreakWidth: 0.55,
          thinStreakOpacity: 0.80,
        ));
        break;

      case 'home-made sauce':
        project.layers.add(AdjustmentLayer(
          id: 'hms_base',
          name: 'Base Grade',
          contrast: 1.28,
          saturation: 1.08,
          temperature: 5400.0,
          sharpness: 0.48,
          shadows: -0.08,
          highlights: 0.12,
          vignette: 0.06,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          cosmoCleanHighlight: 0.40,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.02, 0.22, 0.54, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'hms_amber_haze',
          name: 'Sunset Amber Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.70,
          deepGlowIntensity: 0.32,
          deepGlowRadius: 0.48,
          deepGlowThreshold: 0.50,
          edgeGlowTint: 3.0,
          bslaBloomHaze: 0.30,
          thinStreakIntensity: 0.20,
        ));
        break;

      case 'rin':
        project.layers.add(AdjustmentLayer(
          id: 'rin_base',
          name: 'Base Grade',
          contrast: 1.48,
          saturation: 0.20,
          brightness: -0.01,
          sharpness: 0.72,
          shadows: -0.20,
          highlights: 0.18,
          blackCrush: 0.05,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.12, 0.48, 0.86, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'rin_silver_bloom',
          name: 'Silver Peak Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.74,
          deepGlowIntensity: 0.38,
          deepGlowRadius: 0.38,
          deepGlowThreshold: 0.56,
          edgeGlowTint: 0.0,
          sapphireGlowWidth: 0.42,
          sapphireGlowThreshold: 0.62,
        ));
        break;

      case 'sukuna':
        project.layers.add(AdjustmentLayer(
          id: 'sukuna_base',
          name: 'Base Grade',
          contrast: 1.42,
          saturation: 0.92,
          sharpness: 0.65,
          shadows: -0.16,
          blackCrush: 0.06,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.06,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.16, 0.48, 0.82, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'sukuna_curse_rays',
          name: 'Blood Streaks & Rays',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.74,
          deepGlowIntensity: 0.36,
          edgeGlowTint: 4.0,
          thinStreakIntensity: 0.32,
          thinStreakWidth: 0.60,
          thinStreakOpacity: 0.80,
          copiedChromaShift: 0.28,
        ));
        break;

      case 'toji':
        project.layers.add(AdjustmentLayer(
          id: 'toji_base',
          name: 'Base Grade',
          contrast: 1.38,
          saturation: 0.72,
          temperature: 7100.0,
          sharpness: 0.70,
          shadows: -0.16,
          blackCrush: 0.05,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'toji_acutance',
          name: 'Steel Acutance',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.68,
          contrast: 1.20,
          sharpness: 0.35,
          deepGlowIntensity: 0.20,
          edgeGlowTint: 2.0,
        ));
        break;
        case 'eren':
        project.layers.add(AdjustmentLayer(
          id: 'eren_base',
          name: 'Base Grade',
          contrast: 1.32,
          saturation: 1.05,
          temperature: 5600.0,
          shadows: -0.12,
          highlights: 0.15,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
          mblMojoTealOrange: 0.28,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'eren_sun',
          name: 'Sunflare Volumetrics',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.70,
          deepGlowIntensity: 0.34,
          deepGlowRadius: 0.45,
          deepGlowThreshold: 0.50,
          edgeGlowTint: 1.0,
          bslaGodRays: 0.32,
          thinStreakIntensity: 0.22,
        ));
        break;

      case 'makima':
        project.layers.add(AdjustmentLayer(
          id: 'makima_base',
          name: 'Base Grade',
          contrast: 1.20,
          saturation: 1.02,
          temperature: 6200.0,
          sharpness: 0.40,
          cosmoCleanHighlight: 0.50,
          highlights: 0.10,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'makima_bloom',
          name: 'Pastel Peach Glow',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.68,
          deepGlowIntensity: 0.30,
          deepGlowRadius: 0.48,
          deepGlowThreshold: 0.48,
          edgeGlowTint: 3.0,
          bslaBloomHaze: 0.28,
        ));
        break;

      case 'yuta':
        project.layers.add(AdjustmentLayer(
          id: 'yuta_base',
          name: 'Base Grade',
          contrast: 1.32,
          saturation: 0.82,
          brightness: 0.01,
          temperature: 6500.0,
          sharpness: 0.52,
          shadows: -0.10,
          highlights: 0.14,
          blackCrush: 0.03,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.04,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yuta_ivory_bloom',
          name: 'Ivory Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.68,
          deepGlowIntensity: 0.30,
          deepGlowRadius: 0.40,
          deepGlowThreshold: 0.54,
          edgeGlowTint: 1.0,
          thinStreakIntensity: 0.18,
          thinStreakOpacity: 0.72,
        ));
        break;

      case 'okkotsu':
        project.layers.add(AdjustmentLayer(
          id: 'okkotsu_base',
          name: 'Base Grade',
          contrast: 1.25,
          saturation: 0.84,
          brightness: -0.01,
          temperature: 7200.0,
          sharpness: 0.45,
          shadows: -0.10,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.04,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.19, 0.50, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'okkotsu_rim',
          name: 'Specular Rim',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.62,
          deepGlowIntensity: 0.22,
          deepGlowRadius: 0.38,
          deepGlowThreshold: 0.58,
          thinStreakIntensity: 0.12,
          thinStreakOpacity: 0.65,
        ));
        break;

      case 'artoria':
        project.layers.add(AdjustmentLayer(
          id: 'artoria_base',
          name: 'Base Grade',
          contrast: 1.35,
          saturation: 0.96,
          temperature: 6400.0,
          sharpness: 0.58,
          shadows: -0.12,
          highlights: 0.18,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'artoria_gold',
          name: 'Royal Gold Glint',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.72,
          deepGlowIntensity: 0.35,
          edgeGlowTint: 1.0,
          copiedStarGlint: 0.38,
          sapphireGlowWidth: 0.35,
          sapphireGlowThreshold: 0.65,
        ));
        break;

      case 'deku tree':
        project.layers.add(AdjustmentLayer(
          id: 'deku_base',
          name: 'Base Grade',
          contrast: 1.26,
          saturation: 1.15,
          sharpness: 0.52,
          shadows: -0.08,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'deku_emerald',
          name: 'Emerald Aura & Mist',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.68,
          deepGlowIntensity: 0.32,
          deepGlowRadius: 0.45,
          deepGlowThreshold: 0.48,
          edgeGlowTint: 2.0,
          bslaBloomHaze: 0.35,
        ));
        break;

      case 'raiden':
        project.layers.add(AdjustmentLayer(
          id: 'raiden_base',
          name: 'Base Grade',
          contrast: 1.40,
          saturation: 1.02,
          temperature: 7500.0,
          sharpness: 0.68,
          shadows: -0.16,
          blackCrush: 0.05,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'raiden_electro',
          name: 'Electro Violet Glow',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.74,
          deepGlowIntensity: 0.38,
          edgeGlowTint: 5.0,
          copiedChromaShift: 0.32,
          copiedEdgeRays: 0.36,
          sapphireGlowWidth: 0.36,
          sapphireGlowThreshold: 0.64,
        ));
        break;

      case 'atmospheric haze':
        project.layers.add(AdjustmentLayer(
          id: 'atmo_base',
          name: 'Base Grade',
          contrast: 1.12,
          saturation: 0.88,
          temperature: 6700.0,
          shadows: 0.04,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'atmo_fog',
          name: 'Liminal Volumetric Fog',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.72,
          bslaFogDensity: 0.35,
          bslaBloomHaze: 0.42,
          bslFogScatter: 0.36,
          deepGlowIntensity: 0.24,
          deepGlowRadius: 0.55,
        ));
        break;

      case 'tealdropped (conq knockoff)':
        project.layers.add(AdjustmentLayer(
          id: 'conq_base',
          name: 'Base Grade',
          contrast: 1.36,
          saturation: 1.08,
          brightness: 0.01,
          temperature: 7200.0,
          sharpness: 0.65,
          shadows: -0.14,
          highlights: 0.16,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.04,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'conq_glow',
          name: 'Cyan Teal Rim',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.75,
          deepGlowIntensity: 0.36,
          deepGlowRadius: 0.42,
          deepGlowThreshold: 0.52,
          edgeGlowTint: 2.0,
          thinStreakIntensity: 0.24,
          thinStreakWidth: 0.52,
          thinStreakOpacity: 0.80,
        ));
        break;

      case 'vintage cc':
        project.layers.add(AdjustmentLayer(
          id: 'vint_base',
          name: 'Base Grade',
          contrast: 1.20,
          saturation: 0.90,
          temperature: 5700.0,
          shadows: 0.03,
          highlights: -0.02,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.06,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.03, 0.25, 0.50, 0.80, 0.96],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'vint_grain',
          name: 'Halation & Grain',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.68,
          deepGlowIntensity: 0.25,
          deepGlowRadius: 0.48,
          deepGlowThreshold: 0.52,
          edgeGlowTint: 1.0,
          halationRadius: 0.24,
          halationWarmth: 0.75,
          filmGrain: 0.12,
        ));
        break;

      case 'noir':
        project.layers.add(AdjustmentLayer(
          id: 'noir_base',
          name: 'Base Grade',
          contrast: 1.65,
          saturation: 0.0,
          brightness: -0.03,
          sharpness: 0.75,
          shadows: -0.28,
          blackCrush: 0.09,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.10,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.10, 0.45, 0.88, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'noir_specular',
          name: 'Monochrome Specular',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.72,
          deepGlowIntensity: 0.32,
          deepGlowRadius: 0.35,
          deepGlowThreshold: 0.65,
          edgeGlowTint: 0.0,
          sapphireGlowWidth: 0.32,
          sapphireGlowThreshold: 0.68,
        ));
        break;

      case 'choso':
        project.layers.add(AdjustmentLayer(
          id: 'choso_base',
          name: 'Base Grade',
          contrast: 1.44,
          saturation: 0.88,
          temperature: 6300.0,
          sharpness: 0.62,
          shadows: -0.16,
          blackCrush: 0.05,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.15, 0.48, 0.82, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'choso_blood',
          name: 'Blood Crimson Core',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.76,
          deepGlowIntensity: 0.38,
          deepGlowRadius: 0.42,
          deepGlowThreshold: 0.52,
          edgeGlowTint: 4.0,
          sapphireGlowWidth: 0.36,
          sapphireGlowThreshold: 0.62,
          thinStreakIntensity: 0.26,
          thinStreakWidth: 0.50,
          thinStreakOpacity: 0.80,
        ));
        break;

      case 'yoruichi':
        project.layers.add(AdjustmentLayer(
          id: 'yoruichi_base',
          name: 'Base Grade',
          contrast: 1.38,
          saturation: 1.12,
          temperature: 7200.0,
          sharpness: 0.64,
          shadows: -0.12,
          highlights: 0.15,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          blendMode: LayerBlendMode.normal,
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yoruichi_lightning',
          name: 'Flash Goddess Violet',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.75,
          deepGlowIntensity: 0.36,
          deepGlowRadius: 0.44,
          deepGlowThreshold: 0.52,
          edgeGlowTint: 5.0,
          copiedChromaShift: 0.26,
          sapphireGlowWidth: 0.35,
          sapphireGlowThreshold: 0.62,
          thinStreakIntensity: 0.25,
          thinStreakWidth: 0.52,
          thinStreakOpacity: 0.80,
        ));
        break;

      case 'gojo':
      default:
        project.layers.add(AdjustmentLayer(
          id: 'gojo_base',
          name: 'Base Grade',
          contrast: 1.38,
          saturation: 0.95,
          brightness: 0.01,
          temperature: 7500.0,
          sharpness: 0.65,
          shadows: -0.14,
          highlights: 0.16,
          blackCrush: 0.03,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          vignette: 0.04,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'gojo_infinity_bloom',
          name: 'Infinity Cyan Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.78,
          deepGlowIntensity: 0.40,
          deepGlowRadius: 0.42,
          deepGlowThreshold: 0.50,
          edgeGlowTint: 2.0,
          sapphireGlowWidth: 0.38,
          sapphireGlowThreshold: 0.60,
          thinStreakIntensity: 0.28,
          thinStreakWidth: 0.55,
          thinStreakOpacity: 0.80,
        ));
        break;
    }

    project.activeLayerIndex = 0;
  }

  // ---------------------------------------------------------------------------
  // 10. NEW: TEXT SUITE TAB (Isolated Bounding Region & Chrome Chisel Suite)
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
                      const Text('Draggable & resizable boundary mask', style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                'Toggle Text Suite above to display the on-screen draggable bounding box.\nOnly pixels inside the box are stylized—0% of the video footage is touched.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('METALLIC CHISEL & BEVEL CONTROLS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          buildSliderRow(context: context, title: 'Metallic Bevel Depth', val: project.textBevelDepth, min: 0.0, max: 2.0, onChanged: (v) { project.textBevelDepth = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Chrome Horizon Reflection', val: project.textChromeIntensity, min: 0.0, max: 2.0, onChanged: (v) { project.textChromeIntensity = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Specular Edge Glint', val: project.textSpecularGlint, min: 0.0, max: 2.0, onChanged: (v) { project.textSpecularGlint = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Grounding Contact Shadow', val: project.textContactShadow, min: 0.0, max: 1.0, onChanged: (v) { project.textContactShadow = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Text Luma Threshold', val: project.textLumaThreshold, min: 0.20, max: 0.95, onChanged: (v) { project.textLumaThreshold = v; onChanged(); }),

          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('METALLIC TINT OVERLAY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
            child: Wrap(
              spacing: 8,
              children: [
                {'id': 0.0, 'name': 'Polished Chrome (Silver)'},
                {'id': 1.0, 'name': 'Liquid Gold'},
                {'id': 2.0, 'name': 'Anodized Cyan'},
                {'id': 3.0, 'name': 'Blood Crimson'},
                {'id': 4.0, 'name': 'Steel Violet'},
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
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // EXPORT PRESET AS JSON / XML ACTION (TOLERANT SAFE DUMP)
  // ---------------------------------------------------------------------------
  static Future<void> exportPresetToFile(BuildContext context, ProjectData project) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final rawName = project.mediaPath.isNotEmpty
          ? project.mediaPath.split('/').last.split('.').first
          : 'AEReality_Grade';
      final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      final Map<String, dynamic> ccData = {
        'generator': 'AEReality Shaderly 2026',
        'format_version': '1.0',
        'project_name': rawName,
        'tonemap_mode': project.tonemapMode,
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
        'layers': project.layers.map((l) => {
          'name': l.name,
          'opacity': l.opacity,
          'blend_mode': l.blendMode.index,
          'brightness': l.brightness,
          'contrast': l.contrast,
          'saturation': l.saturation,
          'hue': l.hue,
          'sharpness': l.sharpness,
          'temperature': l.temperature,
          'highlights': l.highlights,
          'shadows': l.shadows,
          'black_crush': l.blackCrush,
          'deep_glow_intensity': l.deepGlowIntensity,
          'deep_glow_radius': l.deepGlowRadius,
          'deep_glow_threshold': l.deepGlowThreshold,
          'edge_glow_tint': l.edgeGlowTint,
          'sapphire_glow_width': l.sapphireGlowWidth,
          'sapphire_glow_threshold': l.sapphireGlowThreshold,
          'thin_streak_intensity': l.thinStreakIntensity,
          'thin_streak_width': l.thinStreakWidth,
          'thin_streak_opacity': l.thinStreakOpacity,
          'bsla_god_rays': l.bslaGodRays,
          'bsla_fog_density': l.bslaFogDensity,
          'bsla_bloom_haze': l.bslaBloomHaze,
          'curve_master': l.curveMaster,
          'curve_red': l.curveRed,
          'curve_green': l.curveGreen,
          'curve_blue': l.curveBlue,
        }).toList(),
      };

      final StringBuffer xmlBuffer = StringBuffer();
      xmlBuffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      xmlBuffer.writeln('<AERealityColorCorrection name="$rawName" version="1.0">');
      xmlBuffer.writeln('  <TonemapMode>${project.tonemapMode}</TonemapMode>');
      xmlBuffer.writeln('  <Layers count="${project.layers.length}">');
      for (final l in project.layers) {
        xmlBuffer.writeln('    <Layer name="${l.name}">');
        xmlBuffer.writeln('      <Opacity>${l.opacity}</Opacity>');
        xmlBuffer.writeln('      <Brightness>${l.brightness}</Brightness>');
        xmlBuffer.writeln('      <Contrast>${l.contrast}</Contrast>');
        xmlBuffer.writeln('      <Saturation>${l.saturation}</Saturation>');
        xmlBuffer.writeln('      <Hue>${l.hue}</Hue>');
        xmlBuffer.writeln('      <DeepGlow intensity="${l.deepGlowIntensity}" radius="${l.deepGlowRadius}" threshold="${l.deepGlowThreshold}" />');
        xmlBuffer.writeln('      <AmanaiFlare intensity="${l.thinStreakIntensity}" width="${l.thinStreakWidth}" opacity="${l.thinStreakOpacity}" />');
        xmlBuffer.writeln('    </Layer>');
      }
      xmlBuffer.writeln('  </Layers>');
      xmlBuffer.writeln('</AERealityColorCorrection>');

      Directory targetDir = Directory('/storage/emulated/0/Download');
      if (!targetDir.existsSync()) {
        targetDir = await getApplicationDocumentsDirectory();
      }

      final jsonFile = File('${targetDir.path}/AEReality_${safeName}_CC.json');
      await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(ccData));

      final xmlFile = File('${targetDir.path}/AEReality_${safeName}_CC.xml');
      await xmlFile.writeAsString(xmlBuffer.toString());

      scaffold.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF101016),
        content: Text('CC exported as .JSON and .XML to Downloads!', style: TextStyle(color: gCustomAccentColor.value, fontWeight: FontWeight.bold)),
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
  // PRESET SAVE / IMPORT HELPERS (TOLERANT PARSER WITH FALLBACKS)
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Loaded preset successfully!'), backgroundColor: Colors.green),
          );
        } else {
          throw Exception('File is not a valid AEReality JSON preset.');
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
  // 11. EXPORT SUITE (Hardware MediaCodec & Direct-to-Downloads Path)
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
                      'Destination: /storage/emulated/0/Download • 32-bit Vulkan Compute',
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

  // ---------------------------------------------------------------------------
  // ASYNCHRONOUS NON-BLOCKING EXPORT ENGINE (ANR CRASH PROOF)
  // ---------------------------------------------------------------------------
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
    final accent = gCustomAccentColor.value;
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
                child: LinearProgressIndicator(value: progress, minHeight: 8, color: accent, backgroundColor: Colors.white12),
              ),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (_, status, __) => Text(status, style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
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

      final extractReturnCode = await activeSession.getReturnCode();
      if (!ReturnCode.isSuccess(extractReturnCode)) {
        throw Exception('FFmpeg frame extraction encountered an error.');
      }

      if (isCancelled) return;

      var frameFiles = await framesDir.list().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      final totalFrames = frameFiles.length;

      if (totalFrames == 0) {
        throw Exception('Frame extraction failed: 0 frames produced.');
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
        
        // Prevent UI thread lock / Android ANR popup
        await Future.delayed(Duration.zero);
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

      final encodeReturnCode = await activeSession.getReturnCode();
      if (!ReturnCode.isSuccess(encodeReturnCode) || !await silentFile.exists()) {
        final logs = await activeSession.getLogsAsString();
        throw Exception('Hardware encoder failed: ${logs ?? "Encoding rejected by FFmpeg"}');
      }

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length()) > 1000;
      
      // Destination: Direct to Downloads folder
      Directory destDir = Directory('/storage/emulated/0/Download');
      if (!await destDir.exists()) {
        try {
          await destDir.create(recursive: true);
        } catch (_) {
          final extDir = await getExternalStorageDirectory();
          destDir = extDir ?? dir;
        }
      }

      final cleanCodec = codec.split(' ').first;
      final fileName = 'AEReality_${resolution}_${cleanCodec}_${bitDepth}_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      final finalOutputFile = File('${destDir.path}/$fileName');

      if (hasAudio) {
        final audioCodec = ExportMatrix.getAudioCodec(container);
        await FFmpegKit.execute('-hide_banner -i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $audioCodec -shortest -y "${finalOutputFile.path}"');
      } else {
        await File(silentOutputPath).copy(finalOutputFile.path);
      }

      if (!isCancelled && context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Master Saved to Downloads:\n${finalOutputFile.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
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

// -----------------------------------------------------------------------------
// INTERACTIVE DRAGGABLE & STRETCHABLE TEXT BOUNDING BOX OVERLAY
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
      width: math.max(40, width),
      height: math.max(30, height),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Drag Body
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                widget.project.textBoxX = (widget.project.textBoxX + details.delta.dx / parentW).clamp(0.0, 1.0 - widget.project.textBoxW);
                widget.project.textBoxY = (widget.project.textBoxY + details.delta.dy / parentH).clamp(0.0, 1.0 - widget.project.textBoxH);
              });
              widget.onUpdated();
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 1.8),
                color: accent.withOpacity(0.12),
              ),
              child: Center(
                child: Text(
                  'TEXT SUITE MASK (${(widget.project.textBoxW * 100).toInt()}% x ${(widget.project.textBoxH * 100).toInt()}%)',
                  style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ),
          ),
          // Resize Handle (Bottom-Right)
          Positioned(
            right: -8,
            bottom: -8,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  widget.project.textBoxW = (widget.project.textBoxW + details.delta.dx / parentW).clamp(0.1, 1.0 - widget.project.textBoxX);
                  widget.project.textBoxH = (widget.project.textBoxH + details.delta.dy / parentH).clamp(0.05, 1.0 - widget.project.textBoxY);
                });
                widget.onUpdated();
              },
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
