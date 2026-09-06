// lib/constants.dart
import 'package:flutter/material.dart';

const Color kAquamarine = Color(0xFF7FFFD4);
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
    'MP4': ['H.265 (HEVC)', 'H.264 (AVC)', 'AV1 (libaom)'],
    'WebM': ['VP9 (libvpx)', 'AV1 (libaom)'],
    'MOV': ['H.265 (HEVC)', 'H.264 (AVC)'],
    'MKV': ['FFV1 (Lossless 16-Bit)', 'H.265 (HEVC)', 'H.264 (AVC)', 'AV1 (libaom)', 'VP9 (libvpx)'],
  };

  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      return container == 'MKV' && codec.startsWith('FFV1');
    }
    if (bitDepth == '10-bit') {
      return !codec.contains('H.264');
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

    if (container == 'MP4') {
      if (codec.contains('H.264')) {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      } else if (codec.contains('H.265')) {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le -profile:v main10'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = is10 ? '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p10le' : '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p';
      }
    } else if (container == 'WebM') {
      if (codec.contains('VP9')) {
        codecFlags = is10
            ? '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -profile:v 2'
            : '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = is10 ? '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p10le' : '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p';
      }
    } else if (container == 'MOV') {
      if (codec.contains('H.264')) {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le -profile:v main10'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      }
    } else {
      if (codec.startsWith('FFV1')) {
        if (is16) {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt gbrp16le';
        } else if (is10) {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt yuv420p10le';
        } else {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt yuv420p';
        }
      } else if (codec.contains('H.265')) {
        codecFlags = is10 ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le' : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      } else if (codec.contains('VP9')) {
        codecFlags = is10
            ? '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -profile:v 2'
            : '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      }
    }

    return '-hide_banner -framerate $fps -i "$framePattern" $codecFlags -b:v ${bitrateKbps}k -y "$outputPath"';
  }
}
