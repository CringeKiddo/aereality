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
    // Ronova: deep purples, abyssal black, gold accents.
    AppThemeDef(
      id: 'ronova',
      name: 'Ronova',
      note: 'Abyssal purple, gold',
      palette: AppPalette(
        bg: Color(0xFF09061A),
        surface: Color(0xFF130C2B),
        card: Color(0xFF1E1340),
        border: Color(0xFF4B3585),
        panel: Color(0xFF1A1138),
        editor: Color(0xFF0D0820),
        project: Color(0xFF0B0720),
      ),
      accent: Color(0xFFE8B84B),
    ),
    // Amber: white, vibrant red, light brown (dark warm base, see header note).
    AppThemeDef(
      id: 'amber',
      name: 'Amber',
      note: 'Vibrant red, light brown',
      palette: AppPalette(
        bg: Color(0xFF1C100D),
        surface: Color(0xFF2B1914),
        card: Color(0xFF3B2419),
        border: Color(0xFF7A5642),
        panel: Color(0xFF34211A),
        editor: Color(0xFF22140F),
        project: Color(0xFF1F120E),
      ),
      accent: Color(0xFFFF3B30),
    ),
    // Wanderer: teal, dark blue, white, gold.
    AppThemeDef(
      id: 'wanderer',
      name: 'Wanderer',
      note: 'Teal, dark blue, gold',
      palette: AppPalette(
        bg: Color(0xFF060E1D),
        surface: Color(0xFF0C1C33),
        card: Color(0xFF122A47),
        border: Color(0xFF2A6C7A),
        panel: Color(0xFF10253F),
        editor: Color(0xFF081426),
        project: Color(0xFF07111F),
      ),
      accent: Color(0xFF35D9C6),
    ),
    // Kazuha: maple red, white, dark grey, autumn orange.
    AppThemeDef(
      id: 'kazuha',
      name: 'Kazuha',
      note: 'Maple red, autumn orange',
      palette: AppPalette(
        bg: Color(0xFF131214),
        surface: Color(0xFF1E1C1F),
        card: Color(0xFF2A272B),
        border: Color(0xFF5A3029),
        panel: Color(0xFF252226),
        editor: Color(0xFF171518),
        project: Color(0xFF151316),
      ),
      accent: Color(0xFFE8452F),
    ),
    // Capitano: ice blue, dark steel, pure black, silver.
    AppThemeDef(
      id: 'capitano',
      name: 'Capitano',
      note: 'Ice blue, dark steel, silver',
      palette: AppPalette(
        bg: Color(0xFF000000),
        surface: Color(0xFF0B1118),
        card: Color(0xFF131C26),
        border: Color(0xFF3A4E60),
        panel: Color(0xFF101922),
        editor: Color(0xFF05090D),
        project: Color(0xFF020406),
      ),
      accent: Color(0xFF9FDCFF),
    ),
    // Mavuika: iridescent flame (orange, gold, magenta) on dark charcoal. The gradient blend turns the accent into
    // orange -> gold; the deep red-magenta lives in the border / card tints.
    AppThemeDef(
      id: 'mavuika',
      name: 'Mavuika',
      note: 'Iridescent flame on charcoal',
      palette: AppPalette(
        bg: Color(0xFF100C0D),
        surface: Color(0xFF1B1416),
        card: Color(0xFF291A1E),
        border: Color(0xFF8A2D52),
        panel: Color(0xFF231719),
        editor: Color(0xFF140E10),
        project: Color(0xFF120D0F),
      ),
      accent: Color(0xFFFF6A1F),
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
