// =============================================================================
// AEReality / Shaderly - Master Export Matrix Engine
// True 32-Bit Linear Pipeline - Clean Modern Codecs (AV1, VP9, ProRes, FFV1)
// 100% Complete File - Zero 264 / 265 / MediaCodec Legacy Codecs
// =============================================================================

class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': ['AV1', 'ProRes 422 HQ'],
    'MKV': ['AV1', 'VP9', 'FFV1 (Lossless 16-bit)', 'ProRes 4444'],
    'WebM': ['AV1', 'VP9'],
    'MOV': ['ProRes 422 HQ', 'ProRes 4444', 'AV1'],
  };

  /// Validates whether a specific bit-depth is supported by the chosen codec & container
  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      // True 16-bit master formats
      if (codec.startsWith('FFV1') && container == 'MKV') return true;
      if (codec.contains('4444') && (container == 'MOV' || container == 'MKV')) return true;
      return false;
    }
    if (bitDepth == '10-bit') {
      // Modern 10-bit color profile support
      if (codec.contains('AV1')) return true;
      if (codec.contains('VP9')) return true;
      if (codec.contains('ProRes')) return true;
      if (codec.startsWith('FFV1')) return true;
      return false;
    }
    // 8-bit fallback
    return true;
  }

  /// Validates bitrate compatibility (Lossless FFV1 / ProRes don't use fixed lossy bitrates)
  static bool isBitrateValid(String codec, String bitrate) {
    if (codec.startsWith('FFV1') || codec.contains('ProRes')) {
      return bitrate == 'Lossless Variable';
    }
    return true;
  }

  /// Container-appropriate audio stream codec
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

  /// Builds clean, high-performance FFmpeg encoding command string
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

    if (codec.contains('AV1')) {
      // SVT-AV1 / AOM-AV1 high performance master
      final pixFmt = is10 ? 'yuv420p10le' : 'yuv420p';
      codecFlags = '-c:v libsvtav1 -preset 6 -crf 20 -pix_fmt $pixFmt -b:v ${bitrateKbps}k';
    } else if (codec.contains('VP9')) {
      // Google VP9 Profile 0 (8-bit) / Profile 2 (10-bit)
      final pixFmt = is10 ? 'yuv420p10le' : 'yuv420p';
      final profile = is10 ? '-profile:v 2' : '-profile:v 0';
      codecFlags = '-c:v libvpx-vp9 -crf 20 $profile -b:v ${bitrateKbps}k -pix_fmt $pixFmt';
    } else if (codec.contains('ProRes')) {
      // Apple ProRes Master Ks
      if (codec.contains('4444')) {
        final pixFmt = is16 ? 'yuva444p16le' : 'yuva444p10le';
        codecFlags = '-c:v prores_ks -profile:v 4 -pix_fmt $pixFmt';
      } else {
        codecFlags = '-c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le';
      }
    } else if (codec.startsWith('FFV1')) {
      // Pure mathematical intra-frame lossless master
      if (is16) {
        codecFlags = '-c:v ffv1 -level 3 -coder 1 -context 1 -pix_fmt yuv422p16le';
      } else if (is10) {
        codecFlags = '-c:v ffv1 -level 3 -coder 1 -context 1 -pix_fmt yuv420p10le';
      } else {
        codecFlags = '-c:v ffv1 -level 3 -coder 1 -context 1 -pix_fmt yuv420p';
      }
    } else {
      // Default clean fallback
      codecFlags = '-c:v libsvtav1 -preset 6 -crf 20 -pix_fmt yuv420p -b:v ${bitrateKbps}k';
    }

    return '-hide_banner -y -framerate $fps -i "$framePattern" $codecFlags "$outputPath"';
  }
}
