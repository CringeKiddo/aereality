// =============================================================================
// AEReality / Shaderly - ThemeManager (batch 16)
//
// Themes change four things, all live, across the whole app:
//   kBackgroundDark / kSurfaceDark / kCardDark / kBorderDark (+ kPanelDark / kEditorDark / kProjectBgDark)  -> gPalette (constants.dart)
//   gCustomAccentColor                                                                                    -> via gChosenAccent + applyAccent()
//
// "Default" holds the original colours, so the Default look is exactly the old one.
//
// Choosing a theme sets its palette AND its signature accent. Any accent you pick afterwards (Settings > Accent colour) still
// wins until you choose a theme again. The theme id is saved (SettingsStore); on start only the PALETTE is restored, so a
// custom accent picked after choosing a theme is not overwritten (accent.json keeps that).
//
// All text in the app is hard-coded white / white-alpha, so every theme keeps a DARK base (a light "white" background would make
// the text unreadable). The "white" of a character is therefore used as accent / edge colour where it fits. [ASSUMED]
// =============================================================================

import 'package:flutter/material.dart';

import 'accent_state.dart';
import 'app_settings.dart';
import 'constants.dart';

class AppThemeDef {
  final String id;
  final String name;
  final String note; // one line shown under the name in the dropdown
  final AppPalette palette;
  final Color accent;
  final bool gradient; // switch the accent's gradient blend on when the theme is chosen (iridescent look)

  const AppThemeDef({
    required this.id,
    required this.name,
    required this.note,
    required this.palette,
    required this.accent,
    this.gradient = false,
  });
}

class ThemeManager {
  static const String defaultId = 'default';

  static const List<AppThemeDef> themes = <AppThemeDef>[
    AppThemeDef(
      id: defaultId,
      name: 'Default',
      note: 'The original dark look',
      palette: kDefaultPalette,
      accent: kCyanAccent,
    ),
    // Outfit colours as described by the owner (batch 16 revision). All bases stay DARK (the app's text is hard-coded white).
    // Ronova: heavy dark brown, red, black.
    AppThemeDef(
      id: 'ronova',
      name: 'Ronova',
      note: 'Heavy dark brown, red, black',
      palette: AppPalette(
        bg: Color(0xFF0A0605),
        surface: Color(0xFF1A0F0B),
        card: Color(0xFF2C1A12),
        border: Color(0xFF7A1F1A),
        panel: Color(0xFF140B08),
        editor: Color(0xFF0D0705),
        project: Color(0xFF0B0604),
      ),
      accent: Color(0xFFD93025),
    ),
    // Amber: brown, red, white.
    AppThemeDef(
      id: 'amber',
      name: 'Amber',
      note: 'Brown, red, white',
      palette: AppPalette(
        bg: Color(0xFF1A0F0B),
        surface: Color(0xFF2A1812),
        card: Color(0xFF3A2218),
        border: Color(0xFFC9BDB0),
        panel: Color(0xFF22130E),
        editor: Color(0xFF150C09),
        project: Color(0xFF180E0A),
      ),
      accent: Color(0xFFE0281E),
    ),
    // Wanderer: indigo with a touch of white and cyan.
    AppThemeDef(
      id: 'wanderer',
      name: 'Wanderer',
      note: 'Indigo, white, cyan',
      palette: AppPalette(
        bg: Color(0xFF080A1E),
        surface: Color(0xFF10143A),
        card: Color(0xFF181E52),
        border: Color(0xFF5A64B8),
        panel: Color(0xFF0D1030),
        editor: Color(0xFF0A0C26),
        project: Color(0xFF090B22),
      ),
      accent: Color(0xFF4FE3F5),
    ),
    // Kazuha: white, red, cream / tan, a slight touch of green (the green is the plate-edge colour; there is only one accent slot).
    AppThemeDef(
      id: 'kazuha',
      name: 'Kazuha',
      note: 'Red, cream and tan, touch of green',
      palette: AppPalette(
        bg: Color(0xFF14110D),
        surface: Color(0xFF211B14),
        card: Color(0xFF302819),
        border: Color(0xFF6E8F5A),
        panel: Color(0xFF191510),
        editor: Color(0xFF100D0A),
        project: Color(0xFF120F0B),
      ),
      accent: Color(0xFFE23B3B),
    ),
    // Capitano: black, grey, gold.
    AppThemeDef(
      id: 'capitano',
      name: 'Capitano',
      note: 'Black, grey, gold',
      palette: AppPalette(
        bg: Color(0xFF030303),
        surface: Color(0xFF111112),
        card: Color(0xFF1D1D20),
        border: Color(0xFF55555C),
        panel: Color(0xFF0D0D0E),
        editor: Color(0xFF070707),
        project: Color(0xFF050505),
      ),
      accent: Color(0xFFD4AF37),
    ),
    // Mavuika: black, reddish orange, gold. The gradient blend turns the accent into reddish orange -> gold; the border is gold.
    AppThemeDef(
      id: 'mavuika',
      name: 'Mavuika',
      note: 'Black, reddish orange, gold',
      palette: AppPalette(
        bg: Color(0xFF050404),
        surface: Color(0xFF120C0A),
        card: Color(0xFF1F130D),
        border: Color(0xFFB8862B),
        panel: Color(0xFF0E0807),
        editor: Color(0xFF080605),
        project: Color(0xFF070504),
      ),
      accent: Color(0xFFFF5A1F),
      gradient: true,
    ),
  ];

  /// Id of the active theme (the dropdown listens to it).
  static final ValueNotifier<String> current = ValueNotifier<String>(defaultId);

  static AppThemeDef byId(String? id) {
    for (final t in themes) {
      if (t.id == id) return t;
    }
    return themes.first;
  }

  static AppThemeDef get active => byId(current.value);

  /// Startup: puts the saved theme's palette on screen. The accent is NOT touched here (accent.json owns it).
  static void restore() {
    final t = byId(SettingsStore.savedThemeId);
    current.value = t.id;
    gPalette.value = t.palette;
  }

  /// The user picked a theme in Settings: palette + signature accent, applied live and saved.
  static void select(String id) {
    final t = byId(id);
    current.value = t.id;
    gPalette.value = t.palette;
    gChosenAccent.value = t.accent;
    if (t.gradient) {
      gGradientColours.value = <int>{...gGradientColours.value, t.accent.value};
    }
    applyAccent();
    AccentStore.save();
    SettingsStore.saveThemeId(t.id);
  }
}
