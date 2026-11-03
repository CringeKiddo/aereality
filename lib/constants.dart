// =============================================================================
// AEReality / Shaderly - Constants, Globals, Palettes & Master Export Matrix
// True 32-Bit Linear Pipeline • High-Bit Depth GPU Sync & Acutance Filter
// 100% Complete File - Zero Feature Omissions
// =============================================================================

import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// YouTube Channel Constant
// -----------------------------------------------------------------------------
const String kMyYouTubeChannel = 'https://youtube.com/@cringekiddo';

// -----------------------------------------------------------------------------
// Global Theme & Brand Colors
// -----------------------------------------------------------------------------
const Color kCyanAccent = Color(0xFF00E5FF);

// Batch 16: the surface colours follow the selected theme (ThemeManager, app_theme.dart). The names stay exactly the same, so every
// file that reads kBackgroundDark / kSurfaceDark / kCardDark / kBorderDark keeps working; they are getters now, not compile-time
// constants, so they cannot be used inside a `const` expression any more (the one place that did, main.dart's AppBarTheme, was changed).
// The Default theme holds the original values, so the Default look is unchanged.
class AppPalette {
  final Color bg; // kBackgroundDark: scaffold / main menu background
  final Color surface; // kSurfaceDark: panels, dialogs
  final Color card; // kCardDark: cards, tiles
  final Color border; // kBorderDark: plate edges
  final Color panel; // editor shelf bar / app bar of the editor (ui_kit.dart ShelfTabBar; was Color(0xFF0F0F14))
  final Color editor; // kEditorDark: editor tab area (was Color(0xFF0C0C10))
  final Color project; // kProjectBgDark: editor scaffold background (was Color(0xFF0A0A0E))
  final Color? controlColor; // slider rows / editor controls (was Color(0xFF14141C) in editor_views.dart); null = derived
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.card,
    required this.border,
    required this.panel,
    required this.editor,
    required this.project,
    this.controlColor,
  });

  /// Colour of slider rows / editor controls. The themes in app_theme.dart do not set it, so it sits between their surface and card.
  Color get control => controlColor ?? Color.lerp(surface, card, 0.55)!;
}

const AppPalette kDefaultPalette = AppPalette(
  bg: Color(0xFF08080C),
  surface: Color(0xFF101016),
  card: Color(0xFF161620),
  border: Color(0xFF222230),
  panel: Color(0xFF0F0F14),
  editor: Color(0xFF0C0C10),
  project: Color(0xFF0A0A0E),
  controlColor: Color(0xFF14141C),
);

/// The active palette. ThemeManager writes it; gAccentListenable (accent_state.dart) includes it, so the MaterialApp rebuilds.
final ValueNotifier<AppPalette> gPalette = ValueNotifier<AppPalette>(kDefaultPalette);

Color get kBackgroundDark => gPalette.value.bg;
Color get kSurfaceDark => gPalette.value.surface;
Color get kCardDark => gPalette.value.card;
Color get kBorderDark => gPalette.value.border;
Color get kEditorDark => gPalette.value.editor;
Color get kProjectBgDark => gPalette.value.project;

// Global Active Accent
final ValueNotifier<Color> gCustomAccentColor = ValueNotifier<Color>(kCyanAccent);

// -----------------------------------------------------------------------------
// Global Engine & Performance Settings
// -----------------------------------------------------------------------------
enum EnginePrecision {
  fp16,
  fp32,
}

enum PerformancePreset {
  powerSave,
  balanced,
  ultra,
}

// Global Preview Scale (1.0 = Native 100%, 0.75 = 75%, 0.5 = 50%, 0.25 = 25% Draft)
double gPreviewScale = 1.0;

// Global Vulkan Engine Compute Precision (1 = FP32 for full 32-bit linear precision)
int gEnginePrecision = 1;

// Grading colour space (Settings > Grading colour space): 0 = Oklab (default, the original behaviour), 1 = Linear Rec.709.
// Everything in the shader that used to be hard-wired to Oklab (basic grade, duotone, gradient map, lightness tonemappers) follows it.
// Sent to the shader in uniform slot 7 (u_gradeSpace).
int gGradeSpace = 0;

// Global Toggle: Grade Active Scrub Frame only vs Continuous Frame Grading
bool gGradeActiveFrameOnly = true;

// Pre-compute the anamorphic flare beam at half resolution (native pass 10). OFF = old per-pixel flare maths.
// Switch in Settings > Preview; compare both on the same clip before leaving it on.
bool gFlareHalfRes = false;

// -----------------------------------------------------------------------------
// Anime Aesthetic Palette Constants
// -----------------------------------------------------------------------------
class AnimePalette {
  static const Color gokuOrange = Color(0xFFFF9100);
  static const Color gojoCyan = Color(0xFF00E5FF);
  static const Color sukunaRed = Color(0xFFFF1744);
  static const Color suguruCrimson = Color(0xFFB71C1C);
  static const Color yamatoIce = Color(0xFF80D8FF);
  static const Color tojiSteel = Color(0xFF78909C);
  static const Color makimaPeach = Color(0xFFFFAB91);
  static const Color artoriaGold = Color(0xFFFFD700);
  static const Color dekuGreen = Color(0xFF00E676);
  static const Color raidenPurple = Color(0xFF7C4DFF);
  static const Color silverWhite = Color(0xFFECEFF1);
  static const Color deepCharcoal = Color(0xFF212121);
  static const Color arknightsAmber = Color(0xFFFFB300);
  static const Color maleniaRot = Color(0xFFD84315);
  static const Color cursedViolet = Color(0xFF8E24AA);
  static const Color giornoGold = Color(0xFFFFD54F);
  static const Color chainsawBlood = Color(0xFFC62828);
}

// -----------------------------------------------------------------------------
// Preset Category Styles & Color Accents
// -----------------------------------------------------------------------------
class PresetStyle {
  final String name;
  final Color accent;

  const PresetStyle({
    required this.name,
    required this.accent,
  });
}

// Built-in presets (names must match the cases in EditorViews.applyPresetLogic)
const List<PresetStyle> kAnimePresetStyles = [
  PresetStyle(name: 'Frieren v3', accent: AnimePalette.yamatoIce),
  PresetStyle(name: 'Frieren Upd', accent: AnimePalette.silverWhite),
  PresetStyle(name: 'Soft Cold CC', accent: AnimePalette.yamatoIce),
  PresetStyle(name: 'Foggy CC', accent: AnimePalette.tojiSteel),
];
