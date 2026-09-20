// =============================================================================
// AEReality - Constants, Globals, Palettes, Enums & Hardware MediaCodec Export Matrix
// 100% Complete File - True 32-Bit Float Linear Pipeline
// =============================================================================

import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// YouTube Channel Constant (Required by main.dart)
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
// Global Engine & Performance Settings (Required by main.dart)
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

// Global Vulkan Engine Compute Precision as INT for initVulkan(shaderBytes, gEnginePrecision)
// 0 = FP16, 1 = FP32 (Defaults to 1 for full 32-bit linear precision)
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
// Preset Category Styles & Color Accents (Clean - No Subtitle Descriptions)
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
  // 1. Kept Untouched:
  PresetStyle(name: 'Yamato', accent: AnimePalette.yamatoIce),
  PresetStyle(name: 'Okkotsu', accent: AnimePalette.silverWhite),
  PresetStyle(name: 'Home-Made Sauce', accent: Color(0xFFFF6F61)),

  // 2. New 1:1 After Effects Inspired Presets from Links:
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
// Robust Export Matrix & Universal FFmpeg Command Builder
// AV1 Reinstated + VP9 Sharpness Addition (+0.3) + Hardware MediaCodec Support
// -----------------------------------------------------------------------------
class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': [
      'H.264 (Hardware MediaCodec)',
      'H.264 (libx264 UltraFast)',
      'HEVC (libx265 Fast)',
      'HEVC (Hardware MediaCodec)',
      'AV1 (libaom-av1)',
    ],
    'MKV': [
      'FFV1 (16-bit Lossless)',
      'H.264 (libx264 UltraFast)',
      'HEVC (libx265 Fast)',
      'VP9 (libvpx-vp9 Fast)',
      'AV1 (libaom-av1)',
    ],
    'MOV': [
      'ProRes 422 HQ (10-bit)',
      'ProRes 4444 (16-bit)',
      'H.264 (libx264 UltraFast)',
      'HEVC (libx265 Fast)',
    ],
    'WebM': [
      'VP9 (libvpx-vp9 Fast)',
      'AV1 (libaom-av1)',
      'VP8 (libvpx)',
    ],
  };

  static bool isBitDepthValid(String container, String codec, String depth) {
    if (depth == '16-bit') {
      return codec.contains('FFV1') || codec.contains('ProRes 4444') || container == 'MKV';
    }
    if (depth == '10-bit') {
      return codec.contains('HEVC') ||
          codec.contains('VP9') ||
          codec.contains('AV1') ||
          codec.contains('ProRes') ||
          codec.contains('FFV1');
    }
    return true; // 8-bit is universally supported
  }

  static bool isBitrateValid(String codec, String bitrate) {
    if (bitrate == 'Lossless Variable') {
      return codec.contains('FFV1') ||
          codec.contains('ProRes') ||
          codec.contains('libx264') ||
          codec.contains('libx265') ||
          codec.contains('VP9');
    }
    return true;
  }

  static String getAudioCodec(String container) {
    switch (container.toUpperCase()) {
      case 'WEBM':
        return 'libopus -b:a 192k';
      case 'MKV':
        return 'libopus -b:a 192k';
      case 'MOV':
        return 'pcm_s16le';
      case 'MP4':
      default:
        return 'aac -b:a 256k';
    }
  }

  static String buildFFmpegEncodeCommand({
    required int fps,
    required String framePattern,
    required String container,
    required String codec,
    required String bitDepth,
    required int bitrateKbps,
    required String outputPath,
  }) {
    String vcodec;
    String extraFlags = '';
    String pixFmt = 'yuv420p';
    String filterChain = '';

    if (bitDepth == '10-bit') {
      pixFmt = 'yuv420p10le';
    } else if (bitDepth == '16-bit') {
      pixFmt = 'gbrp16le';
    }

    if (codec.contains('Hardware MediaCodec')) {
      if (codec.contains('HEVC')) {
        vcodec = 'hevc_mediacodec';
      } else {
        vcodec = 'h264_mediacodec';
      }
      pixFmt = 'yuv420p'; // MediaCodec strictly expects standard NV12/YUV420P
      extraFlags = '-b:v ${bitrateKbps}k -maxrate ${(bitrateKbps * 1.2).toInt()}k -bufsize ${bitrateKbps * 2}k';
    } else if (codec.contains('libx265') || (codec.contains('HEVC') && !codec.contains('MediaCodec'))) {
      vcodec = 'libx265';
      extraFlags = '-preset ultrafast -threads 4 -b:v ${bitrateKbps}k -tag:v hvc1';
      if (bitDepth == '10-bit') {
        extraFlags += ' -profile:v main10';
      }
    } else if (codec.contains('VP9') || codec.contains('libvpx-vp9')) {
      vcodec = 'libvpx-vp9';
      // Added +0.3 sharpness boost filter automatically for VP9 as requested
      filterChain = 'unsharp=5:5:0.3:5:5:0.0,';
      extraFlags = '-deadline realtime -cpu-used 8 -b:v ${bitrateKbps}k -threads 4';
      if (bitDepth == '10-bit') {
        extraFlags += ' -profile:v 2';
      }
    } else if (codec.contains('AV1') || codec.contains('libaom-av1')) {
      vcodec = 'libaom-av1';
      extraFlags = '-cpu-used 8 -crf 24 -b:v ${bitrateKbps}k -threads 4 -strict experimental';
    } else if (codec.contains('FFV1')) {
      vcodec = 'ffv1';
      pixFmt = bitDepth == '16-bit' ? 'gbrp16le' : (bitDepth == '10-bit' ? 'yuv420p10le' : 'yuv420p');
      extraFlags = '-level 3 -threads 4';
    } else if (codec.contains('ProRes')) {
      vcodec = 'prores_ks';
      if (codec.contains('4444')) {
        pixFmt = 'yuva444p10le';
        extraFlags = '-profile:v 4 -vendor apl0';
      } else {
        pixFmt = 'yuv422p10le';
        extraFlags = '-profile:v 3 -vendor apl0';
      }
    } else {
      // Standard Software H.264
      vcodec = 'libx264';
      extraFlags = '-preset ultrafast -tune animation -threads 4 -b:v ${bitrateKbps}k';
    }

    // Explicit framerate before -i prevents frame stalls, format filter ensures clean YUV output
    return '-hide_banner -loglevel error -y -framerate $fps -i "$framePattern" -vf "${filterChain}format=$pixFmt" -c:v $vcodec -pix_fmt $pixFmt $extraFlags "$outputPath"';
  }
}
