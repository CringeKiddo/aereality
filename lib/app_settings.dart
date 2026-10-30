// =============================================================================
// AEReality / Shaderly - SettingsStore (batch 16)
//
// Persists the main-menu settings with SharedPreferences so they survive an app restart:
//   * Preview quality            (gPreviewScale, constants.dart)       0.25 / 0.50 / 1.0
//   * Preview Engine             (gPreviewEngine, below)   Smooth (Native) / Adaptive (Slow)     [batch 17B]
//       It REPLACES the old "Grade paused frame only" switch: Smooth = that switch ON, Adaptive = that switch OFF. The old global
//       gGradeActiveFrameOnly (constants.dart) is kept and mirrors the engine (true = Smooth), and the old stored value is read once to
//       migrate an existing install (OFF -> Adaptive), so nobody loses their setting.
//   * Fast flares (half-res)     (gFlareHalfRes)
//   * Theme                      (ThemeManager, app_theme.dart)
//
// Already persisted elsewhere (NOT duplicated here, still loaded at startup as before):
//   * accent colour / colour off / gradient blend / Motion S preset -> accent.json  (AccentStore, accent_state.dart)
//   * music on / volume                                              -> Music settings file (models.dart)
//   * processing precision is locked (32-bit) and has no setting.
//
// load() never throws: a missing / broken store just means the defaults in constants.dart stay.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'motion_slots.dart';

/// Batch 17B: how the editor preview behaves while the video PLAYS.
///  * smooth   - "Smooth (Native)": the native video plays at full speed, NOTHING is graded during playback, the frame is graded when you pause.
///  * adaptive - "Adaptive (Slow)": every frame is graded before the next one is shown. If the GPU needs 100 ms per frame the clip plays at
///               half speed (CapCut style); the audio is muted while it cannot keep up.
enum PreviewEngine { smooth, adaptive }

PreviewEngine gPreviewEngine = PreviewEngine.smooth;

/// Names shown in Settings.
String previewEngineLabel(PreviewEngine e) => e == PreviewEngine.smooth ? 'Smooth (Native)' : 'Adaptive (Slow)';

class SettingsStore {
  static const String _kScale = 'shaderly.previewScale';
  static const String _kGradeOnly = 'shaderly.gradePausedFrameOnly'; // legacy (batch 16), still written so it mirrors the engine
  static const String _kEngine = 'shaderly.previewEngine'; // batch 17B: 'smooth' | 'adaptive'
  static const String _kFlare = 'shaderly.fastFlares';
  static const String _kTheme = 'shaderly.themeId';
  static const String _kMotionBitrate = 'shaderly.motionBitrateMbps'; // Motion S intermediate bitrate (hardware encoder)
  static const String _kMotionCodec = 'shaderly.motionCodec'; // 'hevc' | 'h264'

  static SharedPreferences? _prefs;

  /// Theme id read from disk by [load] (null = never saved). app_theme.dart applies it.
  static String? savedThemeId;

  static double _sanitizeScale(double? v) {
    if (v == null || v.isNaN) return 1.0;
    if ((v - 0.25).abs() < 0.001) return 0.25;
    if ((v - 0.50).abs() < 0.001) return 0.50;
    return 1.0;
  }

  /// Reads the saved values into the globals of constants.dart. Safe to call more than once.
  static Future<void> load() async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      gPreviewScale = _sanitizeScale(p.getDouble(_kScale));
      gGradeActiveFrameOnly = p.getBool(_kGradeOnly) ?? gGradeActiveFrameOnly;
      // Batch 17B: Preview Engine. A missing / unknown value = migrate from the old switch (OFF = continuous grading = Adaptive).
      final String? eng = p.getString(_kEngine);
      if (eng == 'smooth') {
        gPreviewEngine = PreviewEngine.smooth;
      } else if (eng == 'adaptive') {
        gPreviewEngine = PreviewEngine.adaptive;
      } else {
        gPreviewEngine = gGradeActiveFrameOnly ? PreviewEngine.smooth : PreviewEngine.adaptive;
      }
      gGradeActiveFrameOnly = gPreviewEngine == PreviewEngine.smooth; // keep the legacy global in step
      gFlareHalfRes = p.getBool(_kFlare) ?? gFlareHalfRes;
      savedThemeId = p.getString(_kTheme);
      MotionS.bitrateMbps = MotionS.sanitizeBitrate(p.getInt(_kMotionBitrate));
      MotionS.intermediateCodec = MotionS.sanitizeCodec(p.getString(_kMotionCodec));
    } catch (e) {
      debugPrint('SettingsStore.load failed: $e');
    }
  }

  /// Writes the current values of the globals. Fire-and-forget: call it right after changing a setting.
  static Future<void> save() async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setDouble(_kScale, _sanitizeScale(gPreviewScale));
      gGradeActiveFrameOnly = gPreviewEngine == PreviewEngine.smooth; // legacy mirror
      await p.setBool(_kGradeOnly, gGradeActiveFrameOnly);
      await p.setString(_kEngine, gPreviewEngine == PreviewEngine.adaptive ? 'adaptive' : 'smooth');
      await p.setBool(_kFlare, gFlareHalfRes);
      await p.setInt(_kMotionBitrate, MotionS.sanitizeBitrate(MotionS.bitrateMbps));
      await p.setString(_kMotionCodec, MotionS.sanitizeCodec(MotionS.intermediateCodec));
    } catch (e) {
      debugPrint('SettingsStore.save failed: $e');
    }
  }

  static Future<void> saveThemeId(String id) async {
    savedThemeId = id;
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setString(_kTheme, id);
    } catch (e) {
      debugPrint('SettingsStore.saveThemeId failed: $e');
    }
  }
}
