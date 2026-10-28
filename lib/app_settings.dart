// =============================================================================
// AEReality / Shaderly - SettingsStore (batch 16)
//
// Persists the main-menu settings with SharedPreferences so they survive an app restart:
//   * Preview quality            (gPreviewScale, constants.dart)       0.25 / 0.50 / 1.0
//   * Grade paused frame only    (gGradeActiveFrameOnly)
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

class SettingsStore {
  static const String _kScale = 'shaderly.previewScale';
  static const String _kGradeOnly = 'shaderly.gradePausedFrameOnly';
  static const String _kFlare = 'shaderly.fastFlares';
  static const String _kTheme = 'shaderly.themeId';

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
      gFlareHalfRes = p.getBool(_kFlare) ?? gFlareHalfRes;
      savedThemeId = p.getString(_kTheme);
    } catch (e) {
      debugPrint('SettingsStore.load failed: $e');
    }
  }

  /// Writes the current values of the globals. Fire-and-forget: call it right after changing a setting.
  static Future<void> save() async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setDouble(_kScale, _sanitizeScale(gPreviewScale));
      await p.setBool(_kGradeOnly, gGradeActiveFrameOnly);
      await p.setBool(_kFlare, gFlareHalfRes);
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
