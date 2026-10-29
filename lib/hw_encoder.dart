// =============================================================================
// AEReality / Shaderly - HwEncoder (batch 18B)
//
// Hardware H.264 / HEVC encoding for the video export through FFmpeg's `h264_mediacodec` / `hevc_mediacodec` encoders (Android MediaCodec, i.e. the
// phone's video encoder chip). The export feeds FFmpeg raw NV12 frames that the GPU already converted (pass 29), so the MediaCodec encoder gets
// exactly the format it wants and FFmpeg does no colour conversion at all.
//
// WHY A TEST ENCODE: whether the wrapper exists depends on the pinned ffmpeg-kit-extended build (0.6.2), and whether the chip's encoder accepts the
// size / bitrate depends on the phone. Nothing here is assumed: pick() runs a real 8-frame encode at the real export size and bitrate and only then
// returns a choice. null = "use the software encoder" (the caller keeps libx264 / libx265, exactly as before). The result is cached per
// codec + size + fps + bitrate, so a second export with the same settings does not test again.
//
// Hardware encoders have no CRF: they are bitrate controlled. wantedMbps comes from the export sheet's profile (Standard 12 / High 25 / Ultra 50 /
// Master 80 Mbps). If the chip refuses that bitrate the test retries at 20 and 8 Mbps and the returned choice says which one worked.
// =============================================================================

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';

class HwEncoderChoice {
  final String encoder; // 'h264_mediacodec' | 'hevc_mediacodec'
  final String pixFmt; // pixel format the encoder takes: 'nv12' (no conversion at all) or 'yuv420p'
  final int bitrateMbps;
  final bool hevc;

  const HwEncoderChoice({required this.encoder, required this.pixFmt, required this.bitrateMbps, required this.hevc});

  String get label => 'Hardware ${hevc ? 'HEVC' : 'H.264'} ($encoder, $bitrateMbps Mbps)';
}

class HwEncoder {
  HwEncoder._();

  static final Map<String, HwEncoderChoice?> _cache = {};

  /// Why the last pick() returned null (for the export log). Empty when it succeeded.
  static String lastFailure = '';

  /// Returns a hardware encoder that really encoded 8 frames at this size / bitrate on THIS phone, or null.
  static Future<HwEncoderChoice?> pick({
    required bool hevc,
    required int w,
    required int h,
    required double fps,
    required int wantedMbps,
  }) async {
    final String key = '${hevc ? 'hevc' : 'h264'}|${w}x$h|${fps.toStringAsFixed(2)}|$wantedMbps';
    if (_cache.containsKey(key)) return _cache[key];

    final String enc = hevc ? 'hevc_mediacodec' : 'h264_mediacodec';
    lastFailure = '';
    final List<int> rates = <int>{wantedMbps, if (wantedMbps > 20) 20, 8}.toList();

    HwEncoderChoice? found;
    outer:
    for (final int mbps in rates) {
      for (final String pf in const ['nv12', 'yuv420p']) {
        // raw zero frames from /dev/zero: no filter graph and no lavfi device needed, only the encoder is exercised
        final String cmd = '-hide_banner -y -f rawvideo -pixel_format nv12 -video_size ${w}x$h -framerate ${fps.toStringAsFixed(3)} -i /dev/zero '
            '-frames:v 8 -pix_fmt $pf -c:v $enc -b:v ${mbps}M -g ${(fps * 2).round()} -f null -';
        try {
          final dynamic session = await FFmpegKit.execute(cmd); // same call every other file uses (execute is synchronous in 0.6.2, so it has no .timeout)
          final dynamic rc = await session.getReturnCode();
          if (ReturnCode.isSuccess(rc)) {
            found = HwEncoderChoice(encoder: enc, pixFmt: pf, bitrateMbps: mbps, hevc: hevc);
            break outer;
          }
          String tail = '';
          try {
            final String out = ((await session.getOutput()) ?? '').toString();
            tail = out.length > 400 ? out.substring(out.length - 400) : out;
          } catch (_) {}
          lastFailure = '$enc ${w}x$h ${mbps}M $pf -> rc=$rc ${tail.replaceAll('\n', ' | ')}';
          // the wrapper itself is not in this FFmpeg build: no point trying other bitrates / formats
          if (tail.contains('Unknown encoder') || tail.contains('Encoder not found')) {
            lastFailure = '$enc is not available in this FFmpeg build';
            break outer;
          }
        } catch (e) {
          lastFailure = '$enc test encode failed: $e';
        }
      }
    }
    debugPrint('HwEncoder: ${found == null ? 'NOT available (${lastFailure.isEmpty ? 'no detail' : lastFailure})' : found.label}');
    _cache[key] = found;
    return found;
  }
}
