import 'package:flutter/material.dart';

const String kAppName = 'Shaderly';
const String kMyYouTubeChannel = 'https://youtube.com/@null7839?si=PhqyV6o_5lZnZkQH';

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

const String kRealEsrganLicense = '''
Real-ESRGAN License (BSD 3-Clause):
Copyright (c) 2021, Xintao Wang
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice.
2. Redistributions in binary form must reproduce the above copyright notice.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software.
''';

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
      // ProRes is locked and non-interactive
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
    if (codec.contains('ProRes')) return false; // ProRes freeze / block
    if (bitDepth == '16-bit') {
      return container == 'MKV' && codec.contains('FFV1');
    }
    if (bitDepth == '10-bit') {
      return codec.contains('H.265') || codec.contains('HEVC') || codec.contains('VP9') || codec.contains('FFV1');
    }
    return true; // 8-bit supported across the board
  }

  static bool isBitrateValid(String codec, String bitrate) {
    if (codec.contains('ProRes')) return false;
    // Lossless codecs ignore target bitrates
    if (codec.contains('FFV1')) {
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
      filterFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,unsharp=3:3:0.3:3:3:0.0"';
      codecFlags = is10
          ? '$filterFlags -c:v vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le'
          : '$filterFlags -c:v vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    } else if (codec.contains('VP8')) {
      codecFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v vp8 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    } else if (codec.contains('AV1')) {
      codecFlags = is10
          ? '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libaom-av1 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -strict -2'
          : '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libaom-av1 -b:v ${bitrateKbps}k -pix_fmt yuv420p -strict -2';
    } else if (codec.contains('HEVC') || codec.contains('H.265')) {
      codecFlags = is10
          ? '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p10le'
          : '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v hevc_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p';
    } else if (codec.contains('FFV1')) {
      if (is16) {
        codecFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v ffv1 -level 3 -pix_fmt gbrp16le';
      } else if (is10) {
        codecFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v ffv1 -level 3 -pix_fmt yuv420p10le';
      } else {
        codecFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v ffv1 -level 3 -pix_fmt yuv420p';
      }
    } else if (codec.contains('MPEG-4')) {
      codecFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v mpeg4 -qscale:v 2 -pix_fmt yuv420p';
    } else {
      codecFlags = '-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v h264_mediacodec -b:v ${bitrateKbps}k -pix_fmt yuv420p -movflags +faststart';
    }

    return '-hide_banner -framerate $fps -i "$framePattern" $codecFlags -y "$outputPath"';
  }
}
