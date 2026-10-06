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

// Built-in presets (names must match the cases in EditorViews.applyPresetLogic)
const List<PresetStyle> kAnimePresetStyles = [
  PresetStyle(name: 'Frieren v3', accent: AnimePalette.yamatoIce),
  PresetStyle(name: 'Frieren Upd', accent: AnimePalette.silverWhite),
];

// -----------------------------------------------------------------------------
// Master Clean Export Matrix Engine (AV1, VP9, ProRes, FFV1)
// Complete 16-Bit & 10-Bit Matrix • Zero Stride Mismatches • Faststart Support
// -----------------------------------------------------------------------------
class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MKV': [
      'AV1 (libsvtav1 Master)',
      'VP9 (libvpx-vp9 Sharp)',
      'FFV1 (16-bit Lossless)',
      'ProRes 4444 (16-bit)',
    ],
    'MP4': [
      'AV1 (libsvtav1 Master)',
    ],
    'MOV': [
      'ProRes 422 HQ (10-bit)',
      'ProRes 4444 (16-bit)',
      'AV1 (libsvtav1 Master)',
    ],
    'WebM': [
      'VP9 (libvpx-vp9 Sharp)',
      'AV1 (libsvtav1 Master)',
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
        return 'libopus -b:a 128k';
      case 'MKV':
        return 'libopus -b:a 192k';
      case 'MOV':
        return 'aac -b:a 256k';
      case 'MP4':
      default:
        return 'aac -b:a 192k';
    }
  }

  /// Builds a clean, fully synchronized FFmpeg encoding command string
  /// Fixes pixel format matching and enables acutance sharpening on VP9
  static String buildFFmpegEncodeCommand({
    required int fps,
    required String framePattern,
    required String container,
    required String codec,
    required String bitDepth,
    required int bitrateKbps,
    required String outputPath,
    required int width,
    required int height,
  }) {
    final bool is10 = (bitDepth == '10-bit');
    final bool is16 = (bitDepth == '16-bit');
    final bool inputIs16BitRaw = is10 || is16; // 10-bit and 16-bit feed rgba64le for true linear precision

    // Strict alignment with Dart: rgba64le (8 bytes/px) for 10/16-bit, rgba (4 bytes/px) for 8-bit
    final String pixFmtIn = inputIs16BitRaw ? 'rgba64le' : 'rgba';
    final String inputFormat = '-f image2 -c:v rawvideo -pix_fmt $pixFmtIn -s ${width}x${height}';

    String vcodec;
    String codecFlags;
    String filterChain = '';

    if (codec.contains('AV1')) {
      vcodec = 'libsvtav1';
      final pixFmt = is10 ? 'yuv420p10le' : 'yuv420p';
      final fastStart = (container.toUpperCase() == 'MP4' || container.toUpperCase() == 'MOV') ? '-movflags +faststart' : '';
      codecFlags = '-c:v $vcodec -preset 6 -crf 20 -pix_fmt $pixFmt -b:v ${bitrateKbps}k $fastStart';
    } else if (codec.contains('VP9')) {
      vcodec = 'libvpx-vp9';
      final pixFmt = is10 ? 'yuv420p10le' : 'yuv420p';
      final profile = is10 ? '-profile:v 2' : '-profile:v 0';
      // Automatically injects +0.3 unsharp acutance snap for clean anime lines
      filterChain = 'unsharp=5:5:0.3:5:5:0.0';
      codecFlags = '-c:v $vcodec -deadline good -cpu-used 2 -crf 18 $profile -b:v ${bitrateKbps}k -pix_fmt $pixFmt';
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

    final String filterArg = filterChain.isNotEmpty ? '-vf "$filterChain"' : '';

    return '-hide_banner -loglevel error -y $inputFormat -framerate $fps -i "$framePattern" $filterArg $codecFlags "$outputPath"';
  }
}
