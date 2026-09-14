import 'package:flutter/material.dart';

const Color kBackgroundDark = Color(0xFF0A0A0E);
const Color kCardDark = Color(0xFF121218);
const Color kSurfaceDark = Color(0xFF181822);
const Color kCyanAccent = Color(0xFF00E5FF);
const String kMyYouTubeChannel = 'https://youtube.com/@null7839';

final ValueNotifier<Color> gCustomAccentColor = ValueNotifier<Color>(const Color(0xFF7FFFD4));
const int gEnginePrecision = 32; // Strictly 32-bit float
double gPreviewScale = 0.50; // Active preview scaler (shield for 2K/4K imports)

class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': [
      'H.264 (Hardware MediaCodec)',
      'H.265 / HEVC (Hardware MediaCodec)',
      'AV1 High Efficiency (libsvtav1)',
    ],
    'WebM': [
      'VP9 Broadcast Master (libvpx-vp9)',
      'AV1 High Efficiency (libaom-av1)',
    ],
    'MOV': [
      'Apple ProRes 422 HQ',
      'Apple ProRes 4444 XQ',
      'H.264 (Hardware MediaCodec)',
      'H.265 / HEVC (Hardware MediaCodec)',
    ],
    'MKV': [
      'H.264 (Hardware MediaCodec)',
      'H.265 / HEVC (Hardware MediaCodec)',
      'VP9 Broadcast Master (libvpx-vp9)',
      'AV1 High Efficiency (libsvtav1)',
      'FFV1 Master (Lossless Archival)',
    ],
  };

  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      return container == 'MKV' && (codec.contains('FFV1') || codec.contains('ProRes'));
    }
    if (bitDepth == '10-bit') {
      if (codec.contains('H.264')) return false;
      return true;
    }
    return true;
  }

  static bool isBitrateValid(String codec, String bitrate) {
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
    String vcodecParam = '';
    String pixFmtParam = '';
    String extraParams = '';
    String videoFilter = '';

    // =========================================================================
    // 1. HARDWARE MEDIACODEC (Native Android HW Encode)
    // =========================================================================
    if (codec.contains('H.264 (Hardware MediaCodec)')) {
      vcodecParam = '-c:v h264_mediacodec';
      pixFmtParam = '-pix_fmt yuv420p';
      extraParams = '-b:v ${bitrateKbps}k -maxrate ${bitrateKbps * 1.2}k -bufsize ${bitrateKbps * 2}k';
    } else if (codec.contains('H.265 / HEVC (Hardware MediaCodec)')) {
      vcodecParam = '-c:v hevc_mediacodec';
      pixFmtParam = (bitDepth == '10-bit') ? '-pix_fmt yuv420p10le' : '-pix_fmt yuv420p';
      extraParams = '-b:v ${bitrateKbps}k -maxrate ${bitrateKbps * 1.2}k -bufsize ${bitrateKbps * 2}k';
    }
    // =========================================================================
    // 2. VP9 (With +0.3 Contrast/Sharpness Snap)
    // =========================================================================
    else if (codec.contains('VP9')) {
      vcodecParam = '-c:v libvpx-vp9';
      pixFmtParam = (bitDepth == '10-bit') ? '-pix_fmt yuv420p10le' : '-pix_fmt yuv420p';
      videoFilter = '-vf "unsharp=5:5:0.3:5:5:0.0"';
      extraParams = '-b:v ${bitrateKbps}k -deadline realtime -cpu-used 4 -row-mt 1';
    }
    // =========================================================================
    // 3. AV1 (Bound thread params to prevent OOM hang)
    // =========================================================================
    else if (codec.contains('libsvtav1')) {
      vcodecParam = '-c:v libsvtav1';
      pixFmtParam = (bitDepth == '10-bit') ? '-pix_fmt yuv420p10le' : '-pix_fmt yuv420p';
      extraParams = '-preset 7 -b:v ${bitrateKbps}k -g $fps';
    } else if (codec.contains('libaom-av1')) {
      vcodecParam = '-c:v libaom-av1';
      pixFmtParam = (bitDepth == '10-bit') ? '-pix_fmt yuv420p10le' : '-pix_fmt yuv420p';
      extraParams = '-cpu-used 5 -row-mt 1 -tiles 2x1 -strict -2 -b:v ${bitrateKbps}k -g $fps';
    }
    // =========================================================================
    // 4. APPLE PRORES & FFV1
    // =========================================================================
    else if (codec.contains('ProRes 4444')) {
      vcodecParam = '-c:v prores_ks -profile:v 4';
      pixFmtParam = '-pix_fmt yuva444p10le';
      extraParams = '-qscale:v 4';
    } else if (codec.contains('ProRes 422')) {
      vcodecParam = '-c:v prores_ks -profile:v 3';
      pixFmtParam = '-pix_fmt yuv422p10le';
      extraParams = '-qscale:v 6';
    } else if (codec.contains('FFV1')) {
      vcodecParam = '-c:v ffv1 -level 3 -slicecrc 1';
      pixFmtParam = (bitDepth == '16-bit')
          ? '-pix_fmt gbrp16le'
          : (bitDepth == '10-bit' ? '-pix_fmt yuv420p10le' : '-pix_fmt yuv420p');
      extraParams = '';
    } else {
      vcodecParam = '-c:v h264_mediacodec';
      pixFmtParam = '-pix_fmt yuv420p';
      extraParams = '-b:v ${bitrateKbps}k';
    }

    final vfPart = videoFilter.isNotEmpty ? ' $videoFilter' : '';
    return '-hide_banner -framerate $fps -i "$framePattern"$vfPart $vcodecParam $pixFmtParam $extraParams -y "$outputPath"';
  }
}
