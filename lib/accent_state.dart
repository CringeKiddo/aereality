// =============================================================================
// AEReality / Shaderly - Accent state (batch 7)
//
// gCustomAccentColor (constants.dart) stays THE colour every existing widget reads. It now holds the EFFECTIVE accent:
//   colour off  -> kNeutralAccent
//   colour on   -> gChosenAccent
// so nothing that already reads gCustomAccentColor.value needed to change. Colour off and the per-colour gradient blend
// are two independent switches (gColourOff / gGradientColours); colour off simply wins while it is on and the gradient
// choices are kept, so switching colour back on restores them.
//
// Persistence: accent.json in the app support directory. A missing / broken file just means defaults.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'constants.dart';
import 'motion_slots.dart' show MotionS;

/// The accent the UI shows while "Colour off" is on: a neutral cool grey-white (no hue).
const Color kNeutralAccent = Color(0xFFD5D8E0);

final ValueNotifier<bool> gColourOff = ValueNotifier<bool>(false);
final ValueNotifier<Color> gChosenAccent = ValueNotifier<Color>(kCyanAccent);

/// ARGB ints (Color.value) of the palette colours that have their gradient blend switched on.
final ValueNotifier<Set<int>> gGradientColours = ValueNotifier<Set<int>>(<int>{});

/// Listen to this for anything that must follow the accent live (glow frame, sliders, tab shelf ...).
final Listenable gAccentListenable = Listenable.merge(<Listenable>[gCustomAccentColor, gColourOff, gGradientColours]);

/// True when the effective accent should be drawn as a gradient.
bool get gAccentGradientOn => !gColourOff.value && gGradientColours.value.contains(gChosenAccent.value.value);

/// Second colour of a gradient blend: same family, hue turned 32 degrees and a little lighter. Works for every palette colour
/// (greys and whites just get the lightness step).
Color accentPartner(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withHue((hsl.hue + 32.0) % 360.0).withLightness((hsl.lightness + 0.10).clamp(0.0, 0.92)).toColor();
}

/// [accent, partner] while the gradient is on, [accent, accent] otherwise.
List<Color> accentColors() {
  final a = gCustomAccentColor.value;
  return gAccentGradientOn ? <Color>[a, accentPartner(gChosenAccent.value)] : <Color>[a, a];
}

LinearGradient accentGradient({AlignmentGeometry begin = Alignment.centerLeft, AlignmentGeometry end = Alignment.centerRight}) {
  return LinearGradient(begin: begin, end: end, colors: accentColors());
}

/// Writes the effective accent into gCustomAccentColor (the single colour the rest of the app reads).
void applyAccent() {
  final next = gColourOff.value ? kNeutralAccent : gChosenAccent.value;
  if (gCustomAccentColor.value.value != next.value) {
    gCustomAccentColor.value = next;
  } else {
    // value unchanged but gradient / colour-off flags may have changed: nudge listeners of the merged listenable
    gGradientColours.value = Set<int>.of(gGradientColours.value);
  }
}

class AccentStore {
  static File? _file;

  static Future<File?> _f() async {
    if (_file != null) return _file;
    try {
      final base = await getApplicationSupportDirectory();
      _file = File('${base.path}/accent.json');
    } catch (_) {}
    return _file;
  }

  static Future<void> load() async {
    try {
      final f = await _f();
      if (f == null || !f.existsSync()) return;
      final m = jsonDecode(f.readAsStringSync());
      if (m is! Map) return;
      final c = m['accent'];
      if (c is int) gChosenAccent.value = Color(c);
      final off = m['colourOff'];
      if (off is bool) gColourOff.value = off;
      final g = m['gradient'];
      if (g is List) gGradientColours.value = g.whereType<int>().toSet();
      MotionS.x265Preset = MotionS.sanitizePreset(m['motionPreset']); // Motion S intermediate preset (batch 11)
      applyAccent();
    } catch (e) {
      debugPrint('AccentStore.load failed: $e');
    }
  }

  static Future<void> save() async {
    try {
      final f = await _f();
      f?.writeAsStringSync(
        jsonEncode({
          'accent': gChosenAccent.value.value,
          'colourOff': gColourOff.value,
          'gradient': gGradientColours.value.toList(),
          'motionPreset': MotionS.x265Preset,
        }),
        flush: true,
      );
    } catch (_) {}
  }
}

// -----------------------------------------------------------------------------
// Palette. The first two groups are the ORIGINAL 42 colours from the main menu, same names, same order. Everything after
// them is new in batch 7.
// -----------------------------------------------------------------------------
class AccentSwatch {
  final String name;
  final Color color;
  const AccentSwatch(this.name, this.color);
}

class AccentGroup {
  final String name;
  final List<AccentSwatch> swatches;
  const AccentGroup(this.name, this.swatches);
}

final List<AccentGroup> kAccentGroups = <AccentGroup>[
  const AccentGroup('SOFT', <AccentSwatch>[
    AccentSwatch('Aquamarine', Color(0xFF7FFFD4)),
    AccentSwatch('Soft Cream', Color(0xFFFFFDD0)),
    AccentSwatch('Matcha Green', Color(0xFFB7D5AC)),
    AccentSwatch('Lavender Mist', Color(0xFFE6E6FA)),
    AccentSwatch('Muted Rose', Color(0xFFDDA7A5)),
    AccentSwatch('Peach Puff', Color(0xFFFFDAB9)),
    AccentSwatch('Pistachio', Color(0xFF93C572)),
    AccentSwatch('Mint Cream', Color(0xFFF5FFFA)),
    AccentSwatch('Pale Canary', Color(0xFFFFFF99)),
    AccentSwatch('Blush Pink', Color(0xFFFFD1DC)),
    AccentSwatch('Soft Lilac', Color(0xFFC8A2C8)),
    AccentSwatch('Baby Blue', Color(0xFF89CFF0)),
    AccentSwatch('Periwinkle', Color(0xFFCCCCFF)),
    AccentSwatch('Sage Gray', Color(0xFF9EA99C)),
    AccentSwatch('Almond Silk', Color(0xFFEFDECD)),
    AccentSwatch('Vanilla Custard', Color(0xFFF3E5AB)),
    AccentSwatch('Seafoam Frost', Color(0xFF9FE2BF)),
    AccentSwatch('Celadon', Color(0xFFACE1AF)),
    AccentSwatch('Muted Apricot', Color(0xFFFBCEB1)),
    AccentSwatch('Mauve Taupe', Color(0xFFB784A7)),
    AccentSwatch('Desert Sand', Color(0xFFEDC9AF)),
    AccentSwatch('Pure White', Color(0xFFFFFFFF)),
    AccentSwatch('Platinum Ice', Color(0xFFE5E4E2)),
    AccentSwatch('Ghost Slate', Color(0xFFD8D8E0)),
  ]),
  const AccentGroup('VIVID', <AccentSwatch>[
    AccentSwatch('Quincy Cyan', Color(0xFF00E5FF)),
    AccentSwatch('Electric Gold', Color(0xFFFFD700)),
    AccentSwatch('Neon Mint', Color(0xFF00FF9D)),
    AccentSwatch('Vibrant Violet', Color(0xFF7C4DFF)),
    AccentSwatch('Shogun Crimson', Color(0xFFFF3366)),
    AccentSwatch('Solar Amber', Color(0xFFFF9100)),
    AccentSwatch('Laser Lemon', Color(0xFFF9E858)),
    AccentSwatch('Spring Meadow', Color(0xFF69F0AE)),
    AccentSwatch('Hot Coral', Color(0xFFFF6F61)),
    AccentSwatch('Cyber Purple', Color(0xFFB388FF)),
    AccentSwatch('Deep Magenta', Color(0xFFFF4081)),
    AccentSwatch('Arctic Teal', Color(0xFF1DE9B6)),
    AccentSwatch('Imperial Ruby', Color(0xFFFF1744)),
    AccentSwatch('Cobalt Neon', Color(0xFF2979FF)),
    AccentSwatch('Sunburst Glow', Color(0xFFFFAB00)),
    AccentSwatch('Emerald Glow', Color(0xFF00E676)),
    AccentSwatch('Flamingo', Color(0xFFFC8EAC)),
    AccentSwatch('Steel Cyan', Color(0xFF64FFDA)),
  ]),
  const AccentGroup('NEON', <AccentSwatch>[
    AccentSwatch('Neon Lime', Color(0xFF39FF14)),
    AccentSwatch('Electric Blue', Color(0xFF00B8FF)),
    AccentSwatch('Plasma Pink', Color(0xFFFF2BD6)),
    AccentSwatch('Acid Yellow', Color(0xFFD4FF00)),
    AccentSwatch('Ultra Orange', Color(0xFFFF5E00)),
    AccentSwatch('Laser Green', Color(0xFF00FF41)),
    AccentSwatch('Hyper Cyan', Color(0xFF00FFFF)),
    AccentSwatch('Toxic Violet', Color(0xFFB026FF)),
    AccentSwatch('Hot Magenta', Color(0xFFFF00AA)),
    AccentSwatch('Volt Yellow', Color(0xFFCEFF00)),
  ]),
  const AccentGroup('DEEP', <AccentSwatch>[
    AccentSwatch('Royal Sapphire', Color(0xFF3D5AFE)),
    AccentSwatch('Deep Teal', Color(0xFF00A896)),
    AccentSwatch('Ruby Wine', Color(0xFFD81B60)),
    AccentSwatch('Amethyst', Color(0xFF9C27B0)),
    AccentSwatch('Forest Jade', Color(0xFF2E9E6B)),
    AccentSwatch('Burnt Sienna', Color(0xFFE65100)),
    AccentSwatch('Indigo Glow', Color(0xFF5C6BC0)),
    AccentSwatch('Garnet', Color(0xFFE53935)),
    AccentSwatch('Ocean Blue', Color(0xFF0288D1)),
    AccentSwatch('Plum', Color(0xFF8E4585)),
  ]),
  const AccentGroup('EARTH', <AccentSwatch>[
    AccentSwatch('Terracotta', Color(0xFFE2725B)),
    AccentSwatch('Clay', Color(0xFFC97B63)),
    AccentSwatch('Sandstone', Color(0xFFD9B382)),
    AccentSwatch('Moss', Color(0xFF8A9A5B)),
    AccentSwatch('Olive Drab', Color(0xFF9AA24A)),
    AccentSwatch('Rust', Color(0xFFC1572A)),
    AccentSwatch('Bronze', Color(0xFFCD7F32)),
    AccentSwatch('Copper', Color(0xFFB87333)),
    AccentSwatch('Cocoa', Color(0xFFA9745B)),
    AccentSwatch('Driftwood', Color(0xFFB8A88A)),
  ]),
  const AccentGroup('ICE & METAL', <AccentSwatch>[
    AccentSwatch('Glacier', Color(0xFFBFE9FF)),
    AccentSwatch('Frost Blue', Color(0xFFA6D8F0)),
    AccentSwatch('Steel Blue', Color(0xFF7FA6C9)),
    AccentSwatch('Silver', Color(0xFFC0C0C8)),
    AccentSwatch('Titanium', Color(0xFF9AA0AA)),
    AccentSwatch('Pearl', Color(0xFFF4F1EA)),
    AccentSwatch('Moonstone', Color(0xFFCFD8E8)),
    AccentSwatch('Gunmetal', Color(0xFF8A94A6)),
    AccentSwatch('Rose Gold', Color(0xFFE8B4A0)),
    AccentSwatch('Champagne', Color(0xFFF7E7CE)),
  ]),
  const AccentGroup('SKY & SEA', <AccentSwatch>[
    AccentSwatch('Sky Azure', Color(0xFF5AB9FF)),
    AccentSwatch('Lagoon', Color(0xFF2EC4B6)),
    AccentSwatch('Tide Pool', Color(0xFF4DD0E1)),
    AccentSwatch('Deep Cyan', Color(0xFF00BCD4)),
    AccentSwatch('Cerulean', Color(0xFF3BA3EC)),
    AccentSwatch('Turquoise', Color(0xFF40E0D0)),
    AccentSwatch('Mint Wave', Color(0xFF7EE8C4)),
    AccentSwatch('Storm Cloud', Color(0xFF90A4C0)),
    AccentSwatch('Dusk Blue', Color(0xFF7986CB)),
    AccentSwatch('Horizon Peach', Color(0xFFFFB88C)),
  ]),
  const AccentGroup('BLOOM', <AccentSwatch>[
    AccentSwatch('Sakura', Color(0xFFF8BBD0)),
    AccentSwatch('Cherry Pop', Color(0xFFFF5C8A)),
    AccentSwatch('Orchid', Color(0xFFDA70D6)),
    AccentSwatch('Wisteria', Color(0xFFB39DDB)),
    AccentSwatch('Lilac Haze', Color(0xFFCE93D8)),
    AccentSwatch('Peony', Color(0xFFFF8FAB)),
    AccentSwatch('Berry', Color(0xFFE0407A)),
    AccentSwatch('Apricot', Color(0xFFFFB77D)),
    AccentSwatch('Marigold', Color(0xFFFFC107)),
    AccentSwatch('Honey', Color(0xFFF2B134)),
  ]),
  AccentGroup('ANIME', <AccentSwatch>[
    AccentSwatch('Goku Orange', AnimePalette.gokuOrange),
    AccentSwatch('Gojo Cyan', AnimePalette.gojoCyan),
    AccentSwatch('Sukuna Red', AnimePalette.sukunaRed),
    AccentSwatch('Suguru Crimson', AnimePalette.suguruCrimson),
    AccentSwatch('Yamato Ice', AnimePalette.yamatoIce),
    AccentSwatch('Toji Steel', AnimePalette.tojiSteel),
    AccentSwatch('Makima Peach', AnimePalette.makimaPeach),
    AccentSwatch('Artoria Gold', AnimePalette.artoriaGold),
    AccentSwatch('Deku Green', AnimePalette.dekuGreen),
    AccentSwatch('Raiden Purple', AnimePalette.raidenPurple),
    AccentSwatch('Silver White', AnimePalette.silverWhite),
    AccentSwatch('Arknights Amber', AnimePalette.arknightsAmber),
    AccentSwatch('Malenia Rot', AnimePalette.maleniaRot),
    AccentSwatch('Cursed Violet', AnimePalette.cursedViolet),
    AccentSwatch('Giorno Gold', AnimePalette.giornoGold),
    AccentSwatch('Chainsaw Blood', AnimePalette.chainsawBlood),
  ]),
];

int get kAccentCount => kAccentGroups.fold<int>(0, (n, g) => n + g.swatches.length);
