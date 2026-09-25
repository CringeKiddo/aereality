// =============================================================================
// AEReality - Constants, Globals, Palettes, Enums & Master Clean Export Matrix
// True 32-Bit Linear Pipeline • Zero H.264/H.265/MediaCodec dependencies
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
const Color kBackgroundDark = Color(0xFF08080C);
const Color kSurfaceDark = Color(0xFF101016);
const Color kCardDark = Color(0xFF161620);
const Color kBorderDark = Color(0xFF222230);

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

// Global Toggle: Grade Active Scrub Frame only vs Continuous Frame Grading
bool gGradeActiveFrameOnly = true;

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

// Comprehensive Anime Presets Definition Map (Clean Title Only)
const List<PresetStyle> kAnimePresetStyles = [
  PresetStyle(name: 'Yamato', accent: AnimePalette.yamatoIce),
  PresetStyle(name: 'Okkotsu', accent: AnimePalette.silverWhite),
  PresetStyle(name: 'Home-Made Sauce', accent: Color(0xFFFF6F61)),
  PresetStyle(name: 'Arknights', accent: AnimePalette.arknightsAmber),
  PresetStyle(name: 'Adevob Slop', accent: AnimePalette.tojiSteel),
  PresetStyle(name: 'Yuta', accent: AnimePalette.silverWhite),
  PresetStyle(name: 'Malenia', accent: AnimePalette.maleniaRot),
  PresetStyle(name: 'Deku', accent: AnimePalette.dekuGreen),
  PresetStyle(name: 'JJK', accent: AnimePalette.cursedViolet),
  PresetStyle(name: 'Mahito', accent: AnimePalette.yamatoIce),
  PresetStyle(name: 'Gojo', accent: AnimePalette.gojoCyan),
  PresetStyle(name: 'Toji', accent: AnimePalette.tojiSteel),
  PresetStyle(name: 'Maki', accent: AnimePalette.dekuGreen),
  PresetStyle(name: 'Giorno', accent: AnimePalette.giornoGold),
  PresetStyle(name: 'Holland', accent: AnimePalette.gojoCyan),
  PresetStyle(name: 'Rudeus', accent: AnimePalette.arknightsAmber),
  PresetStyle(name: 'Denji', accent: AnimePalette.chainsawBlood),
  PresetStyle(name: 'Riko', accent: AnimePalette.makimaPeach),
  PresetStyle(name: 'Toji (Grit / Raw)', accent: AnimePalette.deepCharcoal),
];

// -----------------------------------------------------------------------------
// Master Clean Export Matrix Engine (AV1, VP9, ProRes, FFV1)
// Zero MediaCodec / Zero H.264/H.265 / Complete 16-Bit & 10-Bit Matrix
// -----------------------------------------------------------------------------
class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': [
      'AV1 (libsvtav1 Master)',
      'ProRes 422 HQ (10-bit)',
    ],
    'MKV': [
      'FFV1 (16-bit Lossless)',
      'AV1 (libsvtav1 Master)',
      'VP9 (libvpx-vp9 Sharp)',
      'ProRes 4444 (16-bit)',
    ],
    'MOV': [
      'ProRes 422 HQ (10-bit)',
      'ProRes 4444 (16-bit)',
      'AV1 (libsvtav1 Master)',
    ],
    'WebM': [
      'AV1 (libsvtav1 Master)',
      'VP9 (libvpx-vp9 Sharp)',
    ],
  };

  /// Validates whether a specific bit-depth is supported by the chosen codec & container
  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      // True 16-bit master formats
      if (codec.contains('FFV1') && container == 'MKV') return true;
      if (codec.contains('4444') && (container == 'MOV' || container == 'MKV')) return true;
      return false; // 16-bit is disabled for AV1, VP9, and ProRes 422
    }
    if (bitDepth == '10-bit') {
      // 10-bit master profile formats
      if (codec.contains('AV1')) return true;
      if (codec.contains('VP9')) return true;
      if (codec.contains('ProRes')) return true;
      if (codec.contains('FFV1')) return true;
      return false;
    }
    // 8-bit is universally supported
    return true;
  }

  /// Validates bitrate compatibility (Lossless FFV1 / ProRes don't use fixed lossy bitrates)
  static bool isBitrateValid(String codec, String bitrate) {
    if (codec.contains('FFV1') || codec.contains('ProRes')) {
      return bitrate == 'Lossless Variable';
    }
    return true;
  }

  /// Container-appropriate audio stream codec
  static String getAudioCodec(String container) {
    switch (container.toUpperCase()) {
      case 'WEBM':
      case 'MKV':
        return 'libopus -b:a 192k';
      case 'MOV':
        return 'pcm_s16le';
      case 'MP4':
      default:
        return 'aac -b:a 256k';
    }
  }

  /// Builds clean, high-performance FFmpeg encoding command string
  static String buildFFmpegEncodeCommand({
    required int fps,
    required String framePattern,
    required String container,
    required String codec,
    required String bitDepth,
    required int bitrateKbps,
    required String outputPath,
    int width = 1920,
    int height = 1080,
  }) {
    final bool is10 = bitDepth == '10-bit';
    final bool is16 = bitDepth == '16-bit';
    String vcodec;
    String codecFlags;
    String filterChain = '';

    if (codec.contains('AV1')) {
      vcodec = 'libsvtav1';
      final pixFmt = is10 ? 'yuv420p10le' : 'yuv420p';
      codecFlags = '-c:v $vcodec -preset 6 -crf 20 -pix_fmt $pixFmt -b:v ${bitrateKbps}k';
    } else if (codec.contains('VP9')) {
      vcodec = 'libvpx-vp9';
      final pixFmt = is10 ? 'yuv420p10le' : 'yuv420p';
      final profile = is10 ? '-profile:v 2' : '-profile:v 0';
      // Automatically injects +0.3 unsharp acutance snap for VP9 as specified
      filterChain = 'unsharp=5:5:0.3:5:5:0.0,';
      codecFlags = '-c:v $vcodec -deadline good -cpu-used 2 -crf 20 $profile -b:v ${bitrateKbps}k -pix_fmt $pixFmt';
    } else if (codec.contains('ProRes')) {
      vcodec = 'prores_ks';
      if (codec.contains('4444')) {
        final pixFmt = is16 ? 'yuva444p16le' : 'yuva444p10le';
        codecFlags = '-c:v $vcodec -profile:v 4 -vendor apl0 -pix_fmt $pixFmt';
      } else {
        codecFlags = '-c:v $vcodec -profile:v 3 -vendor apl0 -pix_fmt yuv422p10le';
      }
    } else if (codec.contains('FFV1')) {
      vcodec = 'ffv1';
      final pixFmt = is16 ? 'yuv422p16le' : (is10 ? 'yuv420p10le' : 'yuv420p');
      codecFlags = '-c:v $vcodec -level 3 -coder 1 -context 1 -pix_fmt $pixFmt';
    } else {
      vcodec = 'libsvtav1';
      codecFlags = '-c:v $vcodec -preset 6 -crf 20 -pix_fmt yuv420p -b:v ${bitrateKbps}k';
    }

    final String inputFormat = is16
        ? '-f rawvideo -pix_fmt rgba64le -s ${width}x${height}'
        : '';

    final String filterArg = filterChain.isNotEmpty
        ? '-vf "${filterChain.substring(0, filterChain.length - 1)}"'
        : '';

    return '-hide_banner -loglevel error -y $inputFormat -framerate $fps -i "$framePattern" $filterArg $codecFlags "$outputPath"';
  }
}
