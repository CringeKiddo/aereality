class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': ['H.265', 'H.264', 'AV1'],
    'WebM': ['VP9', 'AV1'],
    'MOV': ['H.265', 'H.264'],
    'MKV': ['FFV1 (Lossless)', 'H.265', 'H.264', 'AV1', 'VP9'],
  };

  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      return container == 'MKV' && codec.startsWith('FFV1');
    }
    if (bitDepth == '10-bit') {
      return codec != 'H.264'; // H.264 is strictly 8-bit only
    }
    return true; // 8-bit is universally supported
  }

  static String getAudioCodec(String container) {
    switch (container) {
      case 'WebM':
        return 'libopus';
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
      if (codec == 'H.264') {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      } else if (codec == 'H.265') {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le -profile:v main10'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = is10
            ? '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p10le'
            : '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p';
      }
    } else if (container == 'WebM') {
      if (codec == 'VP9') {
        codecFlags = is10
            ? '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -profile:v 2'
            : '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p';
      } else {
        codecFlags = is10
            ? '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p10le'
            : '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p';
      }
    } else if (container == 'MOV') {
      if (codec == 'H.264') {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le -profile:v main10'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      }
    } else {
      // MKV
      if (codec.startsWith('FFV1')) {
        if (is16) {
          codecFlags = '-c:v ffv1 -pix_fmt gbrp16le';
        } else if (is10) {
          codecFlags = '-c:v ffv1 -pix_fmt yuv420p10le';
        } else {
          codecFlags = '-c:v ffv1 -pix_fmt yuv420p';
        }
      } else if (codec == 'H.265') {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      }
    }

    return '-framerate $fps -i "$framePattern" $codecFlags -b:v ${bitrateKbps}k "$outputPath"';
  }
}
