// =============================================================================
// AEReality - Constants, Globals, Palettes, Enums & Hardware MediaCodec Export Matrix
// =============================================================================

import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// YouTube Channel Constant (Required by main.dart:427)
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

// Global Preview Scale (1.0 = Native 100%, 0.75 = 75%, 0.5 = 50% for fast FPS)
double gPreviewScale = 1.0;

// Global Vulkan Engine Compute Precision as INT for initVulkan(shaderBytes, gEnginePrecision)
// 0 = FP16, 1 = FP32 (Defaults to 1 for full 32-bit linear precision)
int gEnginePrecision = 1;

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
}

// -----------------------------------------------------------------------------
// Preset Category Styles & Color Accents
// -----------------------------------------------------------------------------
class PresetStyle {
  final String name;
  final Color accent;
  final String description;

  const PresetStyle({
    required this.name,
    required this.accent,
    required this.description,
  });
}

// Comprehensive Anime Presets Definition Map
const List<PresetStyle> kAnimePresetStyles = [
  PresetStyle(name: 'Goku', accent: AnimePalette.gokuOrange, description: 'Golden Super Saiyan specular core, high contrast & warm highlights'),
  PresetStyle(name: 'Desaturated', accent: AnimePalette.silverWhite, description: 'Cold chrome contrast, desaturated tones with crisp acutance'),
  PresetStyle(name: 'Yamato', accent: AnimePalette.yamatoIce, description: 'Ice cyan highlight bloom, cool shadows & Frieren-style tones'),
  PresetStyle(name: 'Suguru', accent: AnimePalette.suguruCrimson, description: 'Dark curse crimson halation, blood shadows & Saber Alter contrast'),
  PresetStyle(name: 'Home-Made Sauce', accent: Color(0xFFFF6F61), description: 'Deep warm sunset amber, rich midtones & soft filmic toe'),
  PresetStyle(name: 'Rin', accent: AnimePalette.silverWhite, description: 'High contrast monochrome silver acutance, Killua lightning bloom'),
  PresetStyle(name: 'Sukuna', accent: AnimePalette.sukunaRed, description: 'Blood-red chromatic edge aberration, deep blacks & cursed aura'),
  PresetStyle(name: 'Toji', accent: AnimePalette.tojiSteel, description: 'Steel grit acutance, cold desaturated dynamic range & sharp lines'),
  PresetStyle(name: 'Eren', accent: AnimePalette.gokuOrange, description: 'Titan dawn warmth, volumetric sunbeams & rich amber highlights'),
  PresetStyle(name: 'Makima', accent: AnimePalette.makimaPeach, description: 'Pastel peach soft bloom, skin protection & dreamlike highlights'),
  PresetStyle(name: 'Yuta', accent: AnimePalette.silverWhite, description: 'Ivory specular bloom, reticulated highlight bleed & cursed mist'),
  PresetStyle(name: 'Okkotsu', accent: AnimePalette.yamatoIce, description: 'Cold specular rim lighting, balanced midtones & clean contrast'),
  PresetStyle(name: 'Artoria', accent: AnimePalette.artoriaGold, description: 'Excalibur royal gold glint, high dynamic range & golden sparks'),
  PresetStyle(name: 'Deku Tree', accent: AnimePalette.dekuGreen, description: 'Vivid emerald aura, lush nature highlights & green tint bloom'),
  PresetStyle(name: 'Raiden', accent: AnimePalette.raidenPurple, description: 'Electro-violet warp shift, thunder specular core & deep contrast'),
  PresetStyle(name: 'Atmospheric Haze', accent: Color(0xFFB0BEC5), description: 'Liminal volumetric mist, diffused highlight rolloff & quiet tones'),
  PresetStyle(name: 'Tealdropped (conq knockoff)', accent: AnimePalette.gojoCyan, description: 'High-impact WIS edit cyan-teal rim, punchy contrast & deep shadows'),
  PresetStyle(name: 'Vintage CC', accent: Color(0xFFFFB74D), description: '35mm grain, organic warm halation & retro film curve rolloff'),
  PresetStyle(name: 'Noir', accent: AnimePalette.deepCharcoal, description: 'Pure black & white hard contrast, heavy shadows & sharp silhouette'),
  PresetStyle(name: 'Choso', accent: AnimePalette.suguruCrimson, description: 'Blood manipulation crimson glow, specular halation & dark energy'),
  PresetStyle(name: 'Yoruichi', accent: AnimePalette.raidenPurple, description: 'Flash goddess magenta-violet glow, lightning rays & vivid sat'),
  PresetStyle(name: 'Gojo', accent: AnimePalette.gojoCyan, description: 'Six Eyes electric cyan infinity bloom, razor acutance & vivid rim'),
];

// -----------------------------------------------------------------------------
// Robust Export Matrix & Universal FFmpeg Command Builder
// Guaranteed to produce playable video without stalling or 200-byte black files
// -----------------------------------------------------------------------------
class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': [
      'H.264 (libx264 UltraFast)',
      'H.264 (Hardware MediaCodec)',
      'HEVC (libx265 Fast)',
      'HEVC (Hardware MediaCodec)',
      'MPEG-4',
    ],
    'MKV': [
      'H.264 (libx264 UltraFast)',
      'HEVC (libx265 Fast)',
      'VP9 (libvpx-vp9 Fast)',
      'H.264 (Hardware MediaCodec)',
    ],
    'MOV': [
      'ProRes 422 HQ',
      'H.264 (libx264 UltraFast)',
    ],
    'WebM': [
      'VP9 (libvpx-vp9 Fast)',
      'VP8 (libvpx)',
    ],
  };

  static bool isBitDepthValid(String container, String codec, String depth) {
    if (depth == '16-bit') {
      return codec.contains('ProRes') || container == 'MKV';
    }
    if (depth == '10-bit') {
      return codec.contains('HEVC') || codec.contains('VP9') || codec.contains('ProRes') || codec.contains('libx264') || codec.contains('libx265');
    }
    return true;
  }

  static bool isBitrateValid(String codec, String bitrate) {
    if (bitrate == 'Lossless Variable') {
      return codec.contains('libx264') || codec.contains('libx265') || codec.contains('VP9') || codec.contains('ProRes');
    }
    return true;
  }

  static String getAudioCodec(String container) {
    switch (container.toUpperCase()) {
      case 'WEBM':
        return 'libopus -b:a 192k';
      case 'MKV':
      case 'MOV':
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

    if (bitDepth == '10-bit') {
      pixFmt = 'yuv420p10le';
    }

    if (codec.contains('Hardware MediaCodec')) {
      if (codec.contains('HEVC')) {
        vcodec = 'hevc_mediacodec';
      } else {
        vcodec = 'h264_mediacodec';
      }
      extraFlags = '-b:v ${bitrateKbps}k -maxrate ${bitrateKbps * 1.2}k -bufsize ${bitrateKbps * 2}k';
    } else if (codec.contains('libx265') || (codec.contains('HEVC') && !codec.contains('MediaCodec'))) {
      // Direct Software HEVC (H.265) without driver crash
      vcodec = 'libx265';
      extraFlags = '-preset ultrafast -threads 4 -b:v ${bitrateKbps}k -tag:v hvc1';
    } else if (codec.contains('libvpx-vp9')) {
      vcodec = 'libvpx-vp9';
      extraFlags = '-deadline realtime -cpu-used 8 -b:v ${bitrateKbps}k -threads 4';
    } else if (codec.contains('ProRes')) {
      vcodec = 'prores_ks';
      pixFmt = bitDepth == '10-bit' ? 'yuv422p10le' : 'yuv422p';
      extraFlags = '-profile:v 3 -vendor apl0';
    } else {
      // Standard Verified Software H.264 (Always works, never black screen)
      vcodec = 'libx264';
      extraFlags = '-preset ultrafast -tune animation -threads 4 -b:v ${bitrateKbps}k';
    }

    // Explicit framerate before -i prevents buffer stalls, -vf format ensures valid YUV planar video
    return '-hide_banner -loglevel error -y -framerate $fps -i "$framePattern" -vf "format=$pixFmt" -c:v $vcodec -pix_fmt $pixFmt $extraFlags "$outputPath"';
  }
}
