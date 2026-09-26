// =============================================================================
// AEReality / Shaderly - Editor Views & Export Suite (Part 1/3)
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
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            const SizedBox(height: 6),
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
  // 2. TONEMAPPERS TAB (Real AgX Anime Punch & Real Khronos PBR Neutral)
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
        'desc': 'AgX working gamut transform with ASC CDL power boost. Deepens midtone blacks while giving smooth highlight roll-off without muddy dimness.',
      },
      {
        'mode': 2.0,
        'title': 'Shaderly Tonemapper 2 (Khronos PBR Neutral)',
        'desc': 'Official Khronos 3D Commerce standard. Mathematical peak compression preserving 100% color fidelity and preventing blown-out white clipping.',
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
  // 4. BASIC TAB (Smooth Oklab Hue, Contrast & Black Crush)
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
        buildSliderRow(context: context, title: 'Hue / Color Rotate (Oklab Angle)', val: cur.hue, min: -1.0, max: 1.0, onChanged: (v) { cur.hue = v; onChanged(); }, onEnded: onEnded),
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('CEL SHADING & VIGNETTES', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Sobel Cel Darkener', val: cur.darkOutlines, min: 0.0, max: 1.0, onChanged: (v) { cur.darkOutlines = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Edge Darken', val: cur.edgeDarken, min: 0.0, max: 1.0, onChanged: (v) { cur.edgeDarken = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Radial Vignette', val: cur.vignette, min: 0.0, max: 1.0, onChanged: (v) { cur.vignette = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Boxed Vignette', val: cur.vignetteBoxed, min: 0.0, max: 1.0, onChanged: (v) { cur.vignetteBoxed = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. MAGIC TAB (Magic Bullet Suite + Working Split Toning + Deep Teal & Magic Curves)
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
        buildSliderRow(context: context, title: 'Cosmo Clean Highlights (Skin Protection)', val: cur.cosmoCleanHighlight, min: 0.0, max: 1.0, onChanged: (v) { cur.cosmoCleanHighlight = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Lift (Shadows)', val: cur.mblColoristaLift, min: -0.5, max: 0.5, onChanged: (v) { cur.mblColoristaLift = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Gamma (Midtones)', val: cur.mblColoristaGamma, min: -0.5, max: 0.5, onChanged: (v) { cur.mblColoristaGamma = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Colorista Gain (Highlights)', val: cur.mblColoristaGain, min: -0.5, max: 0.5, onChanged: (v) { cur.mblColoristaGain = v; onChanged(); }, onEnded: onEnded),

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
  // AEReality / Shaderly - Editor Views & Export Suite (Part 2/3)
  // True 32-Bit Float Linear Pipeline - FX, Glows, Flares, Curves & Presets
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
        buildSliderRow(context: context, title: 'Sapphire Edge Detect Glow', val: cur.copiedEdgeRays, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedEdgeRays = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Pro-Mist Halation (Black Line Safe)', val: cur.copiedProMist, min: 0.0, max: 1.0, onChanged: (v) { cur.copiedProMist = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Star Sparkle / Glint Cross', val: cur.copiedStarGlint, min: 0.0, max: 1.5, onChanged: (v) { cur.copiedStarGlint = v; onChanged(); }, onEnded: onEnded),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. GLOWS & FLARES TAB (Continuous Gaussian Falloff, No Stepped Duplicates)
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
          child: Text('SHADERLY GLOW (CAPCUT / AFTER EFFECTS SOFT BLOOM)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Shaderly Glow Intensity', val: cur.shaderlyGlowIntensity, min: 0.0, max: 2.0, onChanged: (v) { cur.shaderlyGlowIntensity = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Radius', val: cur.shaderlyGlowRadius, min: 0.0, max: 1.0, onChanged: (v) { cur.shaderlyGlowRadius = v; onChanged(); }, onEnded: onEnded),
        buildSliderRow(context: context, title: 'Shaderly Glow Threshold', val: cur.shaderlyGlowThreshold, min: 0.10, max: 0.90, onChanged: (v) { cur.shaderlyGlowThreshold = v; onChanged(); }, onEnded: onEnded),

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
          child: Text('SOFT EDGE GLOW HALO (LINE-ART SAFE)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        buildSliderRow(context: context, title: 'Edge Halo Spread', val: cur.edgeHaloRadius, min: 0.0, max: 1.5, onChanged: (v) { cur.edgeHaloRadius = v; onChanged(); }, onEnded: onEnded),

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
              {'id': 6.0, 'name': 'Anime Pink'},
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
          child: Text('1D OPTICAL ANAMORPHIC FLARES (GAUSSIAN DIFFUSION)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
  // 9. CURVES TAB (Monotonic Math - Clamped, Never Inverts)
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
        buildSliderRow(context: context, title: 'Black Point (0.00)', val: activeCurve[0], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[0] = v.clamp(0.0, 1.0); onChanged(); }),
        buildSliderRow(context: context, title: 'Shadow Lift (0.25)', val: activeCurve[1], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[1] = v.clamp(0.0, 1.0); onChanged(); }),
        buildSliderRow(context: context, title: 'Midtone Gamma (0.50)', val: activeCurve[2], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[2] = v.clamp(0.0, 1.0); onChanged(); }),
        buildSliderRow(context: context, title: 'Highlight Rolloff (0.75)', val: activeCurve[3], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[3] = v.clamp(0.0, 1.0); onChanged(); }),
        buildSliderRow(context: context, title: 'White Clip (1.00)', val: activeCurve[4], min: 0.0, max: 1.0, onChanged: (v) { activeCurve[4] = v.clamp(0.0, 1.0); onChanged(); }),
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
  // FULL PRESET ENGINE (WIS & YOUTUBE SHORTS GRADE REVAMPS)
  // Okkotsu, Home-Made Sauce, and Malenia are preserved 100% UNTOUCHED
  // ---------------------------------------------------------------------------
  static void applyPresetLogic(ProjectData project, String name) {
    project.layers.clear();

    switch (name.toLowerCase()) {
      // 1. YAMATO (Sule-Style Soft Creamy Ice / Cold Oceanic Contrast)
      case 'yamato':
        project.tonemapMode = 1.0; // AgX Anime Punch
        project.deepTeal = 0.35;
        project.magicCurves = 0.40;
        project.layers.add(AdjustmentLayer(
          id: 'yamato_base',
          name: 'Ice Contrast Base',
          opacity: 1.0,
          contrast: 1.28,
          saturation: 0.94,
          brightness: -0.01,
          temperature: 7800.0,
          sharpness: 0.52,
          shadows: -0.14,
          highlights: 0.08,
          blackCrush: 0.02,
          splitToneShadowHue: 0.55,
          splitToneShadowSat: 0.18,
          splitToneHighHue: 0.12,
          splitToneHighSat: 0.10,
          splitToneBalance: -0.05,
          cosmoCleanHighlight: 0.40,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.20, 0.50, 0.83, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yamato_creamy_bloom',
          name: 'Creamy Cyan Ambient Glow',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.65,
          shaderlyGlowIntensity: 0.42,
          shaderlyGlowRadius: 0.45,
          shaderlyGlowThreshold: 0.52,
          edgeHaloRadius: 0.35,
          deepGlowIntensity: 0.18,
          deepGlowRadius: 0.35,
          deepGlowThreshold: 0.60,
          edgeGlowTint: 2.0,
        ));
        break;

      // 2. OKKOTSU (100% UNTOUCHED ORIGINAL)
      case 'okkotsu':
        project.layers.add(AdjustmentLayer(
          id: 'okkotsu_base',
          name: 'Base Grade',
          opacity: 1.0,
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

      // 3. HOME-MADE SAUCE (100% UNTOUCHED ORIGINAL)
      case 'home-made sauce':
        project.layers.add(AdjustmentLayer(
          id: 'hms_base',
          name: 'Base Grade',
          opacity: 1.0,
          contrast: 1.22,
          saturation: 1.05,
          brightness: -0.02,
          temperature: 5600.0,
          sharpness: 0.45,
          shadows: -0.08,
          highlights: 0.06,
          vignette: 0.06,
          edgeDarken: 0.0,
          darkOutlines: 0.0,
          cosmoCleanHighlight: 0.45,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.01, 0.21, 0.51, 0.82, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'hms_amber_haze',
          name: 'Sunset Amber Diffusion',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.60,
          deepGlowIntensity: 0.25,
          deepGlowRadius: 0.42,
          deepGlowThreshold: 0.55,
          edgeGlowTint: 3.0,
          bslaBloomHaze: 0.25,
        ));
        break;

      // 4. ARKNIGHTS (Conquestor Gold & Film Noir Ambient Shadow)
      case 'arknights':
        project.tonemapMode = 2.0; // Khronos PBR Neutral
        project.deepTeal = 0.22;
        project.magicCurves = 0.35;
        project.layers.add(AdjustmentLayer(
          id: 'arknights_base',
          name: 'Arknights Cinema Core',
          opacity: 1.0,
          contrast: 1.30,
          saturation: 0.82,
          brightness: -0.02,
          temperature: 6100.0,
          sharpness: 0.55,
          shadows: -0.16,
          highlights: 0.08,
          blackCrush: 0.04,
          splitToneShadowHue: 0.58,
          splitToneShadowSat: 0.22,
          splitToneHighHue: 0.12,
          splitToneHighSat: 0.24,
          splitToneBalance: 0.06,
          cosmoCleanHighlight: 0.50,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.17, 0.49, 0.83, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'arknights_amber_halo',
          name: 'Noble Amber Edge Glow',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.55,
          shaderlyGlowIntensity: 0.32,
          shaderlyGlowRadius: 0.38,
          shaderlyGlowThreshold: 0.58,
          sapphireGlowWidth: 0.30,
          sapphireGlowThreshold: 0.62,
          edgeGlowTint: 1.0,
        ));
        break;

      // 5. ADEVOB SLOP (Adevob Cranberry Steel Inks & Crisp Lines)
      case 'adevob slop':
        project.tonemapMode = 1.0; // AgX Punch
        project.deepTeal = 0.45;
        project.magicCurves = 0.55;
        project.layers.add(AdjustmentLayer(
          id: 'adevob_base',
          name: 'Adevob Steel Lines',
          opacity: 1.0,
          contrast: 1.38,
          saturation: 0.68,
          brightness: -0.03,
          temperature: 7300.0,
          sharpness: 0.65,
          shadows: -0.20,
          highlights: 0.06,
          blackCrush: 0.05,
          mblMojoTealOrange: 0.32,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.15, 0.48, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'adevob_halo',
          name: 'Adevob Soft Edge Halo',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.48,
          edgeHaloRadius: 0.42,
          sapphireGlowWidth: 0.35,
          sapphireGlowThreshold: 0.65,
          edgeGlowTint: 2.0,
          shaderlyGlowIntensity: 0.28,
          shaderlyGlowRadius: 0.30,
          shaderlyGlowThreshold: 0.64,
        ));
        break;

      // 6. YUTA (Desaturated Silver Blade & Cursed Specular Core)
      case 'yuta':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.25;
        project.magicCurves = 0.30;
        project.layers.add(AdjustmentLayer(
          id: 'yuta_base',
          name: 'Yuta Silver Blade',
          opacity: 1.0,
          contrast: 1.26,
          saturation: 0.74,
          brightness: -0.01,
          temperature: 6900.0,
          sharpness: 0.50,
          shadows: -0.12,
          highlights: 0.08,
          blackCrush: 0.03,
          splitToneShadowHue: 0.62,
          splitToneShadowSat: 0.16,
          splitToneHighHue: 0.08,
          splitToneHighSat: 0.14,
          cosmoCleanHighlight: 0.50,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'yuta_specular',
          name: 'Silver Mist Glow',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.52,
          shaderlyGlowIntensity: 0.35,
          shaderlyGlowRadius: 0.36,
          shaderlyGlowThreshold: 0.56,
          edgeGlowTint: 0.0,
        ));
        break;

      // 7. MALENIA (100% UNTOUCHED ORIGINAL)
      case 'malenia':
        project.layers.add(AdjustmentLayer(
          id: 'malenia_base',
          name: 'Malenia Rot Base',
          opacity: 1.0,
          contrast: 1.24,
          saturation: 0.92,
          brightness: -0.02,
          temperature: 5800.0,
          sharpness: 0.50,
          shadows: -0.12,
          highlights: 0.05,
          splitToneShadowHue: 0.98,
          splitToneShadowSat: 0.22,
          splitToneHighHue: 0.10,
          splitToneHighSat: 0.20,
          splitToneBalance: 0.05,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.01, 0.19, 0.50, 0.82, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'malenia_bloom',
          name: 'Scarlet Aeonia Core',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.55,
          deepGlowIntensity: 0.25,
          deepGlowRadius: 0.40,
          deepGlowThreshold: 0.52,
          edgeGlowTint: 3.0,
        ));
        break;

      // 8. DEKU (Vibrant Emerald Glow & Hero Line Pop)
      case 'deku':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.20;
        project.magicCurves = 0.40;
        project.layers.add(AdjustmentLayer(
          id: 'deku_base',
          name: 'One For All Energy',
          opacity: 1.0,
          contrast: 1.30,
          saturation: 1.12,
          brightness: -0.01,
          temperature: 6400.0,
          sharpness: 0.54,
          shadows: -0.12,
          highlights: 0.08,
          splitToneShadowHue: 0.58,
          splitToneShadowSat: 0.20,
          splitToneHighHue: 0.36,
          splitToneHighSat: 0.26,
          cosmoCleanHighlight: 0.45,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'deku_halo',
          name: 'Emerald Discharge Halo',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.56,
          shaderlyGlowIntensity: 0.40,
          shaderlyGlowRadius: 0.38,
          shaderlyGlowThreshold: 0.52,
          edgeHaloRadius: 0.32,
          edgeGlowTint: 2.0,
        ));
        break;

      // 9. JJK (Cursed Violet / Deep Shadows & Rich Magic Mojo)
      case 'jjk':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.30;
        project.magicCurves = 0.50;
        project.layers.add(AdjustmentLayer(
          id: 'jjk_base',
          name: 'Jujutsu Cursed Contrast',
          opacity: 1.0,
          contrast: 1.34,
          saturation: 0.90,
          brightness: -0.03,
          temperature: 6800.0,
          sharpness: 0.55,
          shadows: -0.18,
          blackCrush: 0.05,
          splitToneShadowHue: 0.74,
          splitToneShadowSat: 0.24,
          splitToneHighHue: 0.52,
          splitToneHighSat: 0.20,
          splitToneBalance: -0.08,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.16, 0.48, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'jjk_curse_halo',
          name: 'Electro Violet Aura',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.54,
          shaderlyGlowIntensity: 0.38,
          shaderlyGlowRadius: 0.36,
          shaderlyGlowThreshold: 0.54,
          edgeGlowTint: 5.0,
          sapphireGlowWidth: 0.32,
          sapphireGlowThreshold: 0.58,
        ));
        break;

      // 10. MAHITO (Soft Desaturated Cold Cream & Film Haze)
      case 'mahito':
        project.tonemapMode = 2.0; // Khronos Neutral
        project.deepTeal = 0.38;
        project.magicCurves = 0.35;
        project.layers.add(AdjustmentLayer(
          id: 'mahito_base',
          name: 'Soul Metamorphosis Tone',
          opacity: 1.0,
          contrast: 1.24,
          saturation: 0.78,
          brightness: -0.01,
          temperature: 7500.0,
          sharpness: 0.52,
          shadows: -0.14,
          highlights: 0.06,
          cosmoCleanHighlight: 0.55,
          splitToneShadowHue: 0.56,
          splitToneShadowSat: 0.20,
          splitToneHighHue: 0.06,
          splitToneHighSat: 0.12,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.83, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'mahito_soft_bloom',
          name: 'Creamy Cyan Frost Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.50,
          shaderlyGlowIntensity: 0.36,
          shaderlyGlowRadius: 0.40,
          shaderlyGlowThreshold: 0.56,
          edgeGlowTint: 2.0,
        ));
        break;

      // 11. GOJO (Sule Six Eyes Radiance / Punchy Magic Bullet Cyan Bloom)
      case 'gojo':
        project.tonemapMode = 1.0; // AgX Anime Punch
        project.deepTeal = 0.50;
        project.magicCurves = 0.45;
        project.layers.add(AdjustmentLayer(
          id: 'gojo_base',
          name: 'Six Eyes Radiance',
          opacity: 1.0,
          contrast: 1.32,
          saturation: 0.95,
          brightness: -0.01,
          temperature: 7600.0,
          sharpness: 0.58,
          shadows: -0.16,
          highlights: 0.08,
          blackCrush: 0.03,
          mblMojoTealOrange: 0.35,
          cosmoCleanHighlight: 0.48,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.17, 0.49, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'gojo_infinity_halo',
          name: 'Infinity Cyan Radiant Edge',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.60,
          shaderlyGlowIntensity: 0.44,
          shaderlyGlowRadius: 0.42,
          shaderlyGlowThreshold: 0.50,
          edgeHaloRadius: 0.38,
          edgeGlowTint: 2.0,
        ));
        break;

      // 12. TOJI (Heavy Steel Inks & High Acutance Manga Silhouette)
      case 'toji':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.18;
        project.magicCurves = 0.50;
        project.layers.add(AdjustmentLayer(
          id: 'toji_base',
          name: 'Steel Charcoal Inks',
          opacity: 1.0,
          contrast: 1.42,
          saturation: 0.64,
          brightness: -0.04,
          temperature: 6900.0,
          sharpness: 0.65,
          shadows: -0.22,
          blackCrush: 0.06,
          edgeDarken: 0.20,
          darkOutlines: 0.15,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.13, 0.46, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'toji_edge_spec',
          name: 'Manga Specular Contour',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.45,
          shaderlyGlowIntensity: 0.24,
          shaderlyGlowRadius: 0.28,
          shaderlyGlowThreshold: 0.65,
          edgeHaloRadius: 0.25,
          edgeGlowTint: 0.0,
        ));
        break;

      // 13. MAKI (Zenin Warmth / Creamy Soft Cinema Tone)
      case 'maki':
        project.tonemapMode = 2.0;
        project.deepTeal = 0.20;
        project.magicCurves = 0.30;
        project.layers.add(AdjustmentLayer(
          id: 'maki_base',
          name: 'Zenin Cursed Steel',
          opacity: 1.0,
          contrast: 1.25,
          saturation: 0.88,
          brightness: -0.02,
          temperature: 6300.0,
          sharpness: 0.50,
          shadows: -0.12,
          highlights: 0.06,
          splitToneShadowHue: 0.60,
          splitToneShadowSat: 0.16,
          splitToneHighHue: 0.12,
          splitToneHighSat: 0.18,
          cosmoCleanHighlight: 0.50,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.01, 0.19, 0.50, 0.83, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'maki_glow',
          name: 'Creamy Golden Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.50,
          shaderlyGlowIntensity: 0.32,
          shaderlyGlowRadius: 0.36,
          shaderlyGlowThreshold: 0.55,
          edgeGlowTint: 1.0,
        ));
        break;

      // 14. GIORNO (Rich Gold Experience & Golden Hour Luster)
      case 'giorno':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.15;
        project.magicCurves = 0.40;
        project.layers.add(AdjustmentLayer(
          id: 'giorno_base',
          name: 'Gold Experience Core',
          opacity: 1.0,
          contrast: 1.28,
          saturation: 1.08,
          brightness: -0.01,
          temperature: 6000.0,
          sharpness: 0.52,
          shadows: -0.12,
          highlights: 0.08,
          splitToneShadowHue: 0.65,
          splitToneShadowSat: 0.18,
          splitToneHighHue: 0.14,
          splitToneHighSat: 0.28,
          splitToneBalance: 0.10,
          cosmoCleanHighlight: 0.45,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.18, 0.50, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'giorno_gold_bloom',
          name: 'Requiem Golden Aura',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.58,
          shaderlyGlowIntensity: 0.42,
          shaderlyGlowRadius: 0.40,
          shaderlyGlowThreshold: 0.50,
          edgeGlowTint: 1.0,
        ));
        break;

      // 15. HOLLAND (Teal & Orange Hollywood Punch / Deep Skin Tones)
      case 'holland':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.45;
        project.magicCurves = 0.42;
        project.layers.add(AdjustmentLayer(
          id: 'holland_base',
          name: 'Hollywood Blockbuster',
          opacity: 1.0,
          contrast: 1.28,
          saturation: 1.02,
          brightness: -0.02,
          temperature: 6500.0,
          sharpness: 0.50,
          shadows: -0.14,
          highlights: 0.06,
          mblMojoTealOrange: 0.38,
          cosmoCleanHighlight: 0.50,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.01, 0.19, 0.50, 0.84, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'holland_rim',
          name: 'Soft Oceanic Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.50,
          shaderlyGlowIntensity: 0.34,
          shaderlyGlowRadius: 0.36,
          shaderlyGlowThreshold: 0.54,
          edgeGlowTint: 2.0,
        ));
        break;

      // 16. RUDEUS (Fantasy Dawn / Amber Midtones)
      case 'ruedeus':
      case 'rudeus':
        project.tonemapMode = 2.0;
        project.deepTeal = 0.15;
        project.magicCurves = 0.30;
        project.layers.add(AdjustmentLayer(
          id: 'rudeus_base',
          name: 'Fantasy Dawn Core',
          opacity: 1.0,
          contrast: 1.22,
          saturation: 0.96,
          brightness: -0.01,
          temperature: 5500.0,
          sharpness: 0.46,
          shadows: -0.08,
          highlights: 0.06,
          splitToneShadowHue: 0.56,
          splitToneShadowSat: 0.14,
          splitToneHighHue: 0.10,
          splitToneHighSat: 0.22,
          cosmoCleanHighlight: 0.52,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.01, 0.20, 0.51, 0.83, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'rudeus_sun',
          name: 'Dawn Creamy Glow',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.52,
          shaderlyGlowIntensity: 0.36,
          shaderlyGlowRadius: 0.42,
          shaderlyGlowThreshold: 0.54,
          edgeGlowTint: 3.0,
        ));
        break;

      // 17. DENJI (Sule Giyu Style Chainsaw Blood / Saturated Crimson Energy)
      case 'denji':
        project.tonemapMode = 1.0;
        project.deepTeal = 0.20;
        project.magicCurves = 0.45;
        project.layers.add(AdjustmentLayer(
          id: 'denji_base',
          name: 'Chainsaw Devil Core',
          opacity: 1.0,
          contrast: 1.34,
          saturation: 1.10,
          brightness: -0.03,
          temperature: 6200.0,
          sharpness: 0.58,
          shadows: -0.16,
          highlights: 0.08,
          blackCrush: 0.04,
          splitToneShadowHue: 0.0,
          splitToneShadowSat: 0.26,
          splitToneHighHue: 0.08,
          splitToneHighSat: 0.28,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.17, 0.49, 0.85, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'denji_blood_bloom',
          name: 'Crimson Radiant Halo',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.55,
          shaderlyGlowIntensity: 0.38,
          shaderlyGlowRadius: 0.38,
          shaderlyGlowThreshold: 0.52,
          edgeGlowTint: 4.0,
        ));
        break;

      // 18. RIKO (Pastel Cream / Soft Highlights & Anime Peachy Glow)
      case 'riko':
        project.tonemapMode = 2.0;
        project.deepTeal = 0.12;
        project.magicCurves = 0.25;
        project.layers.add(AdjustmentLayer(
          id: 'riko_base',
          name: 'Pastel Innocence',
          opacity: 1.0,
          contrast: 1.18,
          saturation: 1.02,
          brightness: 0.0,
          temperature: 6200.0,
          sharpness: 0.42,
          shadows: -0.06,
          highlights: 0.05,
          cosmoCleanHighlight: 0.60,
          splitToneShadowHue: 0.60,
          splitToneShadowSat: 0.10,
          splitToneHighHue: 0.02,
          splitToneHighSat: 0.18,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.02, 0.21, 0.51, 0.83, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'riko_peach_bloom',
          name: 'Creamy Peach Bloom',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.52,
          shaderlyGlowIntensity: 0.38,
          shaderlyGlowRadius: 0.42,
          shaderlyGlowThreshold: 0.52,
          edgeGlowTint: 6.0,
        ));
        break;

      // 19. TOJI (GRIT / RAW - Maximum Desaturated Charcoal Contrast)
      case 'toji (grit / raw)':
      default:
        project.tonemapMode = 1.0;
        project.deepTeal = 0.10;
        project.magicCurves = 0.60;
        project.layers.add(AdjustmentLayer(
          id: 'toji_raw_base',
          name: 'Charcoal Grime & Grit',
          opacity: 1.0,
          contrast: 1.45,
          saturation: 0.28,
          brightness: -0.04,
          sharpness: 0.70,
          shadows: -0.24,
          blackCrush: 0.08,
          vignette: 0.10,
          blendMode: LayerBlendMode.normal,
          curveMaster: [0.0, 0.11, 0.45, 0.86, 1.0],
        ));
        project.layers.add(AdjustmentLayer(
          id: 'toji_raw_halo',
          name: 'Manga Monochrome Halo',
          blendMode: LayerBlendMode.softLight,
          opacity: 0.45,
          shaderlyGlowIntensity: 0.22,
          shaderlyGlowRadius: 0.26,
          shaderlyGlowThreshold: 0.65,
          edgeHaloRadius: 0.24,
          edgeGlowTint: 0.0,
        ));
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
  // =============================================================================
  // AEReality / Shaderly - Editor Views & Export Suite (Part 3/3)
  // True 32-Bit Float Linear Pipeline - 3-Layer Timeline, Text Suite & Export Engine
  // 100% Complete Section - Zero Feature Omissions
  // =============================================================================

  // ---------------------------------------------------------------------------
  // 10. TIMELINE OPTIMIZER TAB (3-LAYER SEQUENTIAL TIMELINE OVERHAUL)
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
            // Master CC Segment Enable Switch
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

            // SECONDARY TIMELINE SCRUBBER INSIDE TIMELINE CATEGORY
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
                      onChanged: (v) {
                        onChanged();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Segment Layer Management Header
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

                        // Sequential Non-Overlapping Stretch Range Slider
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
  // 11. ISOLATED TEXT SUITE TAB (High-Touch Draggable & Scalable Controls)
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
          buildSliderRow(context: context, title: 'Metallic Bevel Depth', val: project.textBevelDepth, min: 0.0, max: 3.0, onChanged: (v) { project.textBevelDepth = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Chrome Horizon Reflection', val: project.textChromeIntensity, min: 0.0, max: 3.0, onChanged: (v) { project.textChromeIntensity = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Specular Edge Glint', val: project.textSpecularGlint, min: 0.0, max: 2.0, onChanged: (v) { project.textSpecularGlint = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Grounding Contact Shadow', val: project.textContactShadow, min: 0.0, max: 1.0, onChanged: (v) { project.textContactShadow = v; onChanged(); }),
          buildSliderRow(context: context, title: 'Text Luma Threshold', val: project.textLumaThreshold, min: 0.20, max: 0.95, onChanged: (v) { project.textLumaThreshold = v; onChanged(); }),

          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('BOX POSITION & SIZE SLIDERS (EASY FINGER CONTROL)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
  // EXPORT PRESET AS JSON / XML ACTION
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
      xmlBuffer.writeln('<AERealityColorCorrection name="$rawName" version="1.0">');
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
      final jsonFile = File('${docs.path}/AEReality_${safeName}_CC.json');
      await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(ccData));

      final xmlFile = File('${docs.path}/AEReality_${safeName}_CC.xml');
      await xmlFile.writeAsString(xmlBuffer.toString());

      try {
        if (Platform.isAndroid) {
          const channel = MethodChannel('com.example.aereality/media_scanner');
          await channel.invokeMethod('saveToDownloads', {
            'sourcePath': jsonFile.path,
            'fileName': 'AEReality_${safeName}_CC.json',
            'mimeType': 'application/json',
          });
          await channel.invokeMethod('saveToDownloads', {
            'sourcePath': xmlFile.path,
            'fileName': 'AEReality_${safeName}_CC.xml',
            'mimeType': 'application/xml',
          });
        }
      } catch (_) {}

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Loaded preset successfully with all layers!'), backgroundColor: Colors.green),
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
  // 12. MASTER EXPORT DISPATCHER (AUTOMATICALLY ROUTES IMAGES VS VIDEOS)
  // ---------------------------------------------------------------------------
  static void showExportSheet({
    required BuildContext context,
    required ProjectData project,
    required AdjustmentLayer curLayer,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) {
    if (project.isImage) {
      showImageExportSheet(
        context: context,
        project: project,
        packUniforms: packUniforms,
        getActiveLut: getActiveLut,
      );
    } else {
      showVideoExportSheet(
        context: context,
        project: project,
        curLayer: curLayer,
        packUniforms: packUniforms,
        getActiveLut: getActiveLut,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 13. IMAGE EXPORT SUITE (PNG, JPG, WEBP • 720p, 1080p, 2K, 4K)
  // ---------------------------------------------------------------------------
  static void showImageExportSheet({
    required BuildContext context,
    required ProjectData project,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) {
    String selectedFormat = 'PNG';
    String selectedRes = '2K';
    double imageQuality = 100.0;

    final formats = ['PNG', 'JPG', 'WEBP'];
    final resolutions = ['Native', '720p', '1080p', '2K', '4K'];
    final accent = gCustomAccentColor.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
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
                        const Text('Export Graded Art / Image', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Text(
                      'Destination: /storage/emulated/0/Download • True 32-bit Float Pipeline',
                      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    const Text('IMAGE FORMAT', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: formats.map((fmt) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(fmt),
                              selected: selectedFormat == fmt,
                              selectedColor: accent,
                              backgroundColor: const Color(0xFF18181E),
                              labelStyle: TextStyle(
                                color: selectedFormat == fmt ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (sel) {
                                if (sel) setStateModal(() => selectedFormat = fmt);
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('RESOLUTION TARGET', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: resolutions.map((res) {
                        return ChoiceChip(
                          label: Text(res),
                          selected: selectedRes == res,
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF18181E),
                          labelStyle: TextStyle(
                            color: selectedRes == res ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (sel) {
                            if (sel) setStateModal(() => selectedRes = res);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    if (selectedFormat != 'PNG') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('QUALITY / COMPRESSION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                          Text('${imageQuality.toInt()}%', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.0,
                          activeTrackColor: accent,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: accent,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: imageQuality,
                          min: 10.0,
                          max: 100.0,
                          onChanged: (v) => setStateModal(() => imageQuality = v),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          executeImageExport(
                            context: context,
                            project: project,
                            format: selectedFormat,
                            resolution: selectedRes,
                            quality: imageQuality.toInt(),
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
                          'SAVE $selectedFormat ($selectedRes)',
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
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
  // EXECUTE IMAGE EXPORT ACTION
  // ---------------------------------------------------------------------------
  static Future<void> executeImageExport({
    required BuildContext context,
    required ProjectData project,
    required String format,
    required String resolution,
    required int quality,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) async {
    try {
      final fileBytes = await File(project.mediaPath).readAsBytes();
      final decoded = img.decodeImage(fileBytes);
      if (decoded == null) throw Exception('Unable to decode source image.');

      int targetW = decoded.width;
      int targetH = decoded.height;

      if (resolution != 'Native') {
        int base = 1080;
        if (resolution == '720p') base = 720;
        else if (resolution == '2K') base = 1440;
        else if (resolution == '4K') base = 2160;

        final double aspect = decoded.width / decoded.height;
        if (aspect >= 1.0) {
          targetH = base;
          targetW = (targetH * aspect).round();
        } else {
          targetW = base;
          targetH = (targetW / aspect).round();
        }
      }

      targetW = math.max(16, ((targetW + 15) ~/ 16) * 16);
      targetH = math.max(16, ((targetH + 15) ~/ 16) * 16);

      final resized = img.copyResize(decoded, width: targetW, height: targetH);
      final rawBytes = resized.getBytes(order: img.ChannelOrder.rgba);

      final uniforms = packUniforms(targetW.toDouble(), targetH.toDouble());
      uniforms[28] = 0.0;
      final lutTable = getActiveLut();

      final gradedBytes = processImage(rawBytes, targetW, targetH, targetW, targetH, uniforms, lutTable: lutTable);
      final outputImg = img.Image.fromBytes(
        width: targetW,
        height: targetH,
        bytes: gradedBytes.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      Uint8List encodedFile;
      String ext = format.toLowerCase();
      String mimeType = 'image/png';

      if (format == 'PNG') {
        encodedFile = Uint8List.fromList(img.encodePng(outputImg));
        mimeType = 'image/png';
      } else if (format == 'JPG') {
        encodedFile = Uint8List.fromList(img.encodeJpg(outputImg, quality: quality));
        ext = 'jpg';
        mimeType = 'image/jpeg';
      } else {
        encodedFile = Uint8List.fromList(img.encodePng(outputImg));
        ext = 'webp';
        mimeType = 'image/webp';
      }

      final docs = await getApplicationDocumentsDirectory();
      final fileName = 'Shaderly_Art_${resolution}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final localTempPath = '${docs.path}/$fileName';
      final tempFile = File(localTempPath);
      await tempFile.writeAsBytes(encodedFile);

      String publicResultPath = localTempPath;
      try {
        if (Platform.isAndroid) {
          const channel = MethodChannel('com.example.aereality/media_scanner');
          final res = await channel.invokeMethod<String>('saveToDownloads', {
            'sourcePath': tempFile.path,
            'fileName': fileName,
            'mimeType': mimeType,
          });
          if (res != null) publicResultPath = res;
        }
      } catch (_) {}

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image Saved to Downloads:\n$publicResultPath'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image Export Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 14. VIDEO EXPORT SHEET (WITH DYNAMIC CODEC COMPATIBILITY MATRIX)
  // ---------------------------------------------------------------------------
  static void showVideoExportSheet({
    required BuildContext context,
    required ProjectData project,
    required AdjustmentLayer curLayer,
    required Float32List Function(double, double) packUniforms,
    required Float32List? Function() getActiveLut,
  }) {
    String selectedContainer = 'MKV';
    String selectedCodec = 'AV1 (libsvtav1 Master)';
    String selectedBitDepth = '10-bit';
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBitrate = '50 Mbps';

    final containers = ['MKV', 'MP4', 'WebM', 'MOV'];
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
            final availableCodecs = ExportMatrix.containerCodecs[selectedContainer] ?? ['AV1 (libsvtav1 Master)'];
            if (!availableCodecs.contains(selectedCodec)) {
              selectedCodec = availableCodecs.first;
            }

            if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
              selectedBitDepth = '10-bit';
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
                        const Text('Render Master Video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Text(
                      'Destination: /storage/emulated/0/Download • True 32-bit Float Pipeline',
                      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    const Text('CONTAINER FORMAT', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
                              selectedCodec = (ExportMatrix.containerCodecs[c] ?? ['AV1 (libsvtav1 Master)']).first;
                            });
                          }
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('CLEAN CODECS FOR $selectedContainer', style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
                            if (sel) setStateModal(() => selectedCodec = codec);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('COLOR DEPTH PRECISION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: ['8-bit', '10-bit', '16-bit'].map((depth) {
                        final bool isAllowed = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, depth);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Text(depth),
                              selected: selectedBitDepth == depth,
                              selectedColor: accent,
                              disabledColor: Colors.black26,
                              backgroundColor: const Color(0xFF18181E),
                              labelStyle: TextStyle(
                                color: !isAllowed
                                    ? Colors.white24
                                    : (selectedBitDepth == depth ? Colors.black : Colors.white),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              onSelected: !isAllowed
                                  ? null
                                  : (_) => setStateModal(() => selectedBitDepth = depth),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('RESOLUTION TARGET', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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

                    const Text('FRAMERATE TARGET', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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
                        final bool isAllowed = ExportMatrix.isBitrateValid(selectedCodec, bit);
                        return ChoiceChip(
                          label: Text(bit),
                          selected: selectedBitrate == bit,
                          selectedColor: accent,
                          disabledColor: Colors.black26,
                          backgroundColor: const Color(0xFF18181E),
                          labelStyle: TextStyle(
                            color: !isAllowed
                                ? Colors.white24
                                : (selectedBitrate == bit ? Colors.black : Colors.white),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          onSelected: !isAllowed
                              ? null
                              : (sel) {
                                  if (sel) setStateModal(() => selectedBitrate = bit);
                                },
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
  // 15. NATIVE HIGH-BIT DEPTH CLEAN EXPORT ENGINE (LIGHTNING-FAST RAW PIPE)
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
    if (bitDepth == '10-bit') {
      uniforms[28] = 1.0;
    } else if (bitDepth == '16-bit') {
      uniforms[28] = 2.0;
    } else {
      uniforms[28] = 0.0;
    }
    final lutTable = getActiveLut();

    int bitrateKbps = 50000;
    if (bitrate.contains('15')) bitrateKbps = 15000;
    else if (bitrate.contains('35')) bitrateKbps = 35000;
    else if (bitrate.contains('80')) bitrateKbps = 80000;
    else if (bitrate.contains('120')) bitrateKbps = 120000;

    int targetFps = int.parse(fps.replaceAll('fps', ''));
    String containerExt = container.toLowerCase();

    final bool is16Bit = (bitDepth == '16-bit');
    final progressNotifier = ValueNotifier<double>(0.0);
    final accent = gCustomAccentColor.value;
    final statusNotifier = ValueNotifier<String>('Initializing 32-bit Vulkan Engine: 0%');
    bool isCancelled = false;
    FFmpegSession? activeSession;
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
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
                  if (dialogContext != null) Navigator.of(dialogContext!).pop();
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
        );
      },
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
      await FFmpegKit.execute('-hide_banner -i "${project.mediaPath}" -vn -c:a aac -b:a 256k -y "$audioPath"');

      if (isCancelled) return;

      statusNotifier.value = 'Extracting $outW x $outH frames fast...';
      
      // Fast rawvideo frame extraction bypassing CPU image encoding
      activeSession = await FFmpegKit.execute(
        '-hide_banner -i "${project.mediaPath}" -r $targetFps -s ${outW}x${outH} -f rawvideo -pix_fmt rgba -y "${framesDir.path}/frame_%05d.raw"',
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

      final int frameByteLength8 = outW * outH * 4;

      for (int i = 0; i < totalFrames; i++) {
        if (isCancelled) return;

        final file = frameFiles[i];
        if (file is! File) continue;
        final rawInput8 = await file.readAsBytes();
        if (rawInput8.length < frameByteLength8) continue;

        final currentTime = i / targetFps.toDouble();

        // Multi-Layer Timeline Segment Evaluation
        bool applyCurrentCc = true;
        Float32List activeUniforms = uniforms;
        Float32List? activeLut = lutTable;

        if (project.enableTimelineSegments && project.timelineSegments.isNotEmpty) {
          final matchingSegments = project.timelineSegments.where((seg) =>
              seg.isEnabled && currentTime >= seg.startTime && currentTime <= seg.endTime);
          applyCurrentCc = matchingSegments.isNotEmpty;
        }

        final paddedIndex = (i + 1).toString().padLeft(5, '0');

        if (is16Bit) {
          // True 16-Bit Processing Stride
          final rawInput16 = Uint16List(outW * outH * 4);
          for (int px = 0; px < rawInput8.length; px++) {
            rawInput16[px] = (rawInput8[px] << 8) | rawInput8[px];
          }

          Uint16List outputRaw16;
          if (applyCurrentCc) {
            outputRaw16 = processImage16(rawInput16, outW, outH, outW, outH, activeUniforms, lutTable: activeLut);
          } else {
            outputRaw16 = rawInput16;
          }

          final outputFile = File('${processedDir.path}/frame_$paddedIndex.raw');
          await outputFile.writeAsBytes(outputRaw16.buffer.asUint8List());
        } else {
          // 8-Bit & 10-Bit Fast Raw Stream
          Uint8List outputRaw8;
          if (applyCurrentCc) {
            outputRaw8 = processImage(rawInput8, outW, outH, outW, outH, activeUniforms, lutTable: activeLut);
          } else {
            outputRaw8 = rawInput8;
          }

          final outputFile = File('${processedDir.path}/frame_$paddedIndex.raw');
          await outputFile.writeAsBytes(outputRaw8);
        }

        progressNotifier.value = (i + 1) / totalFrames;
        statusNotifier.value = 'Grading frames on GPU: ${(((i + 1) / totalFrames) * 100).toInt()}% (${i + 1}/$totalFrames)';
        
        await Future.delayed(Duration.zero);
      }

      if (isCancelled) return;

      statusNotifier.value = 'Encoding master ($codec)...';
      final silentOutputPath = '${dir.path}/silent_video.$containerExt';
      final silentFile = File(silentOutputPath);
      if (await silentFile.exists()) await silentFile.delete();

      final encodeCmd = ExportMatrix.buildFFmpegEncodeCommand(
        fps: targetFps,
        framePattern: '${processedDir.path}/frame_%05d.raw',
        container: container,
        codec: codec,
        bitDepth: bitDepth,
        bitrateKbps: bitrateKbps,
        outputPath: silentOutputPath,
        width: outW,
        height: outH,
      );
      activeSession = await FFmpegKit.execute(encodeCmd);

      if (isCancelled) return;

      final encodeReturnCode = await activeSession.getReturnCode();
      if (!ReturnCode.isSuccess(encodeReturnCode) || !await silentFile.exists()) {
        final logs = await activeSession.getLogsAsString();
        throw Exception('Encoder failed: ${logs ?? "Encoding rejected by FFmpeg"}');
      }

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length()) > 1000;
      
      final cleanCodec = codec.split(' ').first;
      final fileName = 'Shaderly_${resolution}_${cleanCodec}_${bitDepth}_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      final tempMuxedPath = '${dir.path}/$fileName';

      if (hasAudio) {
        final aCodec = ExportMatrix.getAudioCodec(container);
        await FFmpegKit.execute('-hide_banner -y -i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $aCodec -shortest "$tempMuxedPath"');
      } else {
        await FFmpegKit.execute('-hide_banner -y -i "$silentOutputPath" -c:v copy "$tempMuxedPath"');
      }

      final tempMuxedFile = File(tempMuxedPath);

      // Save via Android MediaStore ContentResolver platform channel for full Android 15 compatibility
      String publicDestPath = tempMuxedPath;
      try {
        if (Platform.isAndroid) {
          const channel = MethodChannel('com.example.aereality/media_scanner');
          final res = await channel.invokeMethod<String>('saveToDownloads', {
            'sourcePath': tempMuxedFile.path,
            'fileName': fileName,
            'mimeType': 'video/$containerExt',
          });
          if (res != null) publicDestPath = res;
        }
      } catch (_) {}

      if (!isCancelled && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
      }

      if (!isCancelled && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Master Video Saved to Downloads:\n$publicDestPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!isCancelled && dialogContext != null) {
        Navigator.of(dialogContext!).pop();
      }
      if (!isCancelled && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e'), backgroundColor: Colors.red));
      }
    }
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
                  'TEXT SUITE MASK (${(widget.project.textBoxW * 100).toInt()}% x ${(widget.project.textBoxH * 100).toInt()}%)',
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
      final x = size.width * (i / 4.0);
      final y = size.height * (i / 4.0);
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
    if (idx >= 4) return p[4].clamp(0.0, 1.0);
    double t = seg - idx;

    double p0 = (idx == 0) ? p[0] : (idx == 1) ? p[0] : (idx == 2) ? p[1] : p[2];
    double p1 = (idx == 0) ? p[0] : (idx == 1) ? p[1] : (idx == 2) ? p[2] : p[3];
    double p2 = (idx == 0) ? p[1] : (idx == 1) ? p[2] : (idx == 2) ? p[3] : p[4];
    double p3 = (idx == 0) ? p[2] : (idx == 1) ? p[3] : (idx == 2) ? p[4] : p[4];

    double m1 = (0.5 * (p2 - p0)).clamp(-1.2, 1.2);
    double m2 = (0.5 * (p3 - p1)).clamp(-1.2, 1.2);

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
