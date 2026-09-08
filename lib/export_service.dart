import 'dart:io';

class ExportService {
  /// Builds safe FFmpeg CLI commands preventing black screens on Android & VLC
  static List<String> buildExportCommand({
    required String inputVideoPath,
    required String outputVideoPath,
    required bool isWebM,
    required bool is10Bit,
    double fps = 30.0,
  }) {
    // 1. Force even dimensions (trunc(iw/2)*2)
    // 2. Force yuv420p for 8-bit to ensure mobile HW decoder & VLC compatibility
    // 3. Set proper color space metadata flags
    final List<String> cmd = [
      '-y',
      '-i', inputVideoPath,
    ];

    if (isWebM) {
      // VP9 WebM standard encoding
      if (is10Bit) {
        cmd.addAll([
          '-c:v', 'libvpx-vp9',
          '-pix_fmt', 'yuv420p10le',
          '-profile:v', '2',
          '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
          '-b:v', '0',
          '-crf', '24',
          '-c:a', 'libopus',
          '-b:a', '128k',
        ]);
      } else {
        cmd.addAll([
          '-c:v', 'libvpx-vp9',
          '-pix_fmt', 'yuv420p',
          '-profile:v', '0',
          '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
          '-b:v', '0',
          '-crf', '28',
          '-c:a', 'libopus',
          '-b:a', '128k',
        ]);
      }
    } else {
      // Universal MP4 (H.264)
      cmd.addAll([
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '18',
        '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
        '-color_range', 'tv',
        '-colorspace', 'bt709',
        '-color_primaries', 'bt709',
        '-color_trc', 'bt709',
        '-movflags', '+faststart', // Instant streaming on mobile players
        '-c:a', 'aac',
        '-b:a', '192k',
      ]);
    }

    cmd.add(outputVideoPath);
    return cmd;
  }
}
