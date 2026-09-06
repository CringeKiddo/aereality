// lib/constants.dart
import 'package:flutter/material.dart';

// Dynamic App Theme Color Notifier (Customizable via Settings)
final ValueNotifier<Color> gAppColor = ValueNotifier<Color>(const Color(0xFF7FFFD4));

Color get kAquamarine => gAppColor.value;
const Color kAquamarineDark = Color(0xFF45B39D);
const Color kCyanAccent = Color(0xFF00FFFF);
const Color kGold = Color(0xFFFFD700);
const Color kLavenderSoft = Color(0xFFE6E6FA);
const Color kSurfaceDark = Color(0xFF101015);
const Color kCardDark = Color(0xFF15151C);
const Color kBackgroundDark = Color(0xFF08080B);

int gEnginePrecision = 32;
double gPreviewScale = 0.5;

class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': [
      'H.264 (Hardware MediaCodec)',
      'H.265 (HEVC MediaCodec)',
      'H.264 (Software libx264/Native)',
      'H.265 (Software libx265/Native)',
      'MPEG-4 Standard',
    ],
    'WebM': [
      'VP8 Native',
      'VP9 Native',
    ],
    'MOV': [
      'H.264 (Hardware MediaCodec)',
      'H.265 (HEVC MediaCodec)',
      'MPEG-4 Standard',
    ],
    'MKV': [
      'H.264 (Hardware MediaCodec)',
      'H.265 (HEVC MediaCodec)',
      'Lossless Raw RGBA',
      'FFV1 Lossless 16-Bit',
      'VP9 Native',
    ],
  };

  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      return container == 'MKV' && (codec.contains('FFV1') || codec.contains('Lossless'));
    }
    if (bitDepth == '10-bit') {
      return codec.contains('H.265') || codec.contains('VP9') || codec.contains('FFV1');
    }
    return true;
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
    final bool is10 = bitDepth == '10-bit';
    final bool is16 = bitDepth == '16-bit';
    String codecFlags;

    if (codec.contains('Hardware') || codec.contains('MediaCodec')) {
      if (codec.contains('HEVC') || codec.contains('H.265')) {
        codecFlags = '-c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v h264_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      }
    } else if (container == 'MP4') {
      if (codec.contains('H.264')) {
        codecFlags = '-c:v h264_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else if (codec.contains('H.265')) {
        codecFlags = '-c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v mpeg4 -qscale:v 2 -pix_fmt yuv420p';
      }
    } else if (container == 'WebM') {
      if (codec.contains('VP9')) {
        codecFlags = '-c:v vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v vp8 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      }
    } else if (container == 'MOV') {
      if (codec.contains('HEVC') || codec.contains('H.265')) {
        codecFlags = '-c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v h264_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      }
    } else {
      // MKV
      if (codec.contains('Lossless') || codec.contains('FFV1')) {
        if (is16) {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt gbrp16le';
        } else {
          codecFlags = '-c:v rawvideo -pix_fmt rgba';
        }
      } else if (codec.contains('HEVC') || codec.contains('H.265')) {
        codecFlags = '-c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else if (codec.contains('VP9')) {
        codecFlags = '-c:v vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v h264_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      }
    }

    return '-hide_banner -framerate $fps -i "$framePattern" $codecFlags -y "$outputPath"';
  }
}
