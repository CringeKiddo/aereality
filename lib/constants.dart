import 'package:flutter/material.dart';

const Color kAquamarine = Color(0xFF7FFFD4);
const Color kAquamarineDark = Color(0xFF45B39D);
const Color kCyanAccent = Color(0xFF00FFFF);
const Color kGold = Color(0xFFFFD700);
const Color kLavenderSoft = Color(0xFFE6E6FA);
const Color kSurfaceDark = Color(0xFF101015);
const Color kCardDark = Color(0xFF15151C);
const Color kBackgroundDark = Color(0xFF08080B);

final ValueNotifier<Color> gCustomAccentColor = ValueNotifier<Color>(kAquamarine);

int gEnginePrecision = 32;
double gPreviewScale = 0.50; // Dynamic scale for timeline preview lag reduction

class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': [
      'H.264 (Hardware MediaCodec)',
      'H.265 (HEVC MediaCodec)',
      'AV1 Native',
      'MPEG-4 Compatible',
    ],
    'WebM': [
      'VP9 Native (+0.3 Snap)',
      'VP8 Native',
    ],
    'MOV': [
      'H.264 (Hardware MediaCodec)',
      'H.265 (HEVC MediaCodec)',
      'Apple ProRes Compatible',
    ],
    'MKV': [
      'FFV1 Lossless 16-Bit',
      'H.265 (HEVC MediaCodec)',
      'H.264 (Hardware MediaCodec)',
      'VP9 Native (+0.3 Snap)',
    ],
  };

  static bool isCodecSupported(String container, String codec) {
    final list = containerCodecs[container];
    if (list == null) return false;
    return list.contains(codec);
  }

  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      return container == 'MKV' && (codec.contains('FFV1') || codec.contains('ProRes'));
    }
    if (bitDepth == '10-bit') {
      return codec.contains('H.265') || codec.contains('HEVC') || codec.contains('VP9') || codec.contains('FFV1') || codec.contains('ProRes');
    }
    return true; // 8-bit supported across the board
  }

  static bool isBitrateValid(String codec, String bitrate) {
    // Lossless codecs ignore target bitrates
    if (codec.contains('FFV1') || codec.contains('ProRes')) {
      return bitrate == 'Lossless Variable';
    }
    return bitrate != 'Lossless Variable';
  }

  static String getAudioCodec(String container) {
    switch (container) {
      case 'WebM':
      case 'MKV':
        return 'libopus';
      case 'MP4':
      case 'MOV':
      default:
        return 'aac';
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
    final bool is16 = bitDepth == '16-bit';
    final bool is10 = bitDepth == '10-bit';
    String codecFlags = '';
    String filterFlags = '';

    if (codec.contains('VP9')) {
      filterFlags = '-vf unsharp=3:3:0.3:3:3:0.0';
      codecFlags = is10
          ? '$filterFlags -c:v vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le'
          : '$filterFlags -c:v vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    } else if (codec.contains('VP8')) {
      codecFlags = '-c:v vp8 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    } else if (codec.contains('AV1')) {
      codecFlags = is10
          ? '-c:v libaom-av1 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -strict -2'
          : '-c:v libaom-av1 -b:v ${bitrateKbps}k -pix_fmt yuv420p -strict -2';
    } else if (codec.contains('HEVC') || codec.contains('H.265')) {
      codecFlags = is10
          ? '-c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p10le'
          : '-c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    } else if (codec.contains('FFV1')) {
      if (is16) {
        codecFlags = '-c:v ffv1 -level 3 -pix_fmt gbrp16le';
      } else if (is10) {
        codecFlags = '-c:v ffv1 -level 3 -pix_fmt yuv420p10le';
      } else {
        codecFlags = '-c:v ffv1 -level 3 -pix_fmt yuv420p';
      }
    } else if (codec.contains('ProRes')) {
      codecFlags = '-c:v prores -profile:v 3 -pix_fmt yuv422p10le';
    } else if (codec.contains('MPEG-4')) {
      codecFlags = '-c:v mpeg4 -qscale:v 2 -pix_fmt yuv420p';
    } else {
      codecFlags = '-c:v h264_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    }

    return '-hide_banner -framerate $fps -i "$framePattern" $codecFlags -y "$outputPath"';
  }
}
