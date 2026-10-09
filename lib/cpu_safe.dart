// =============================================================================
// AEReality / Shaderly - CPU-safe encoders
//
// Why this exists: a SIGILL (signal 4, ILL_ILLOPC) is the CPU refusing to run an instruction. Android reported exactly
// that inside libffmpegkit.so a few seconds after the x265 encode started, with the Vulkan grade (and the Text Suite)
// already finished fine. x265 / x264 pick hand-written ARM assembly at runtime (NEON, dot-product, i8mm, SVE ...);
// when the build and the phone disagree about what the CPU supports, the process dies and nothing in Dart can catch it.
//
// What it does:
//   1. Before the real export, a ~1 second probe encode runs with the exact same encoder settings. If the app dies
//      there, it dies in a second instead of after minutes of rendering.
//   2. CrashLog tells us on the next launch that the process died of SIGILL inside that encoder. We then step the
//      encoder down a level and remember it (cpu_safe.json):
//         level 0  default (auto-detected assembly)
//         level 1  x265/x264 restricted to base NEON assembly   (asm=2)
//         level 2  x265/x264 with assembly switched off          (asm=0, slow but runs on anything)
//         level 3  blocked: the export stops with a clear message instead of crashing again
//      SVT-AV1 and libvpx have no CPU override, so one SIGILL there blocks them straight away.
//   3. A probe that passes is remembered, so it only runs once per encoder / level / bit depth.
//   4. The RGB -> YUV conversion (FFmpeg's own swscale assembly, NOT the encoder) is probed as its own stage, because
//      it is part of every export and was not covered by the encoder probe. If THAT stage dies, FFmpeg's own CPU
//      feature flags are stepped down (-cpuflags): level 1 turns off only the newest ARM extensions
//      (dotprod / i8mm / SVE / SVE2) and keeps NEON, level 2 turns assembly off for FFmpeg's own code only.
//      The encoders keep their full-speed assembly, and the conversion is a small part of the total time.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'crash_log.dart';

class CpuSafe {
  static final Map<String, int> _levels = {};
  static final Set<String> _verified = {};
  static bool _loaded = false;
  static File? _file;

  /// Encoder key for a codec name from the export menu, or null when no guarded encoder is involved.
  static String? encoderForCodec(String codec) {
    if (codec.contains('HEVC') || codec.contains('H.265')) return 'x265';
    if (codec.contains('H.264')) return 'x264';
    if (codec.contains('AV1')) return 'svtav1';
    if (codec.contains('VP9')) return 'vpx';
    return null;
  }

  static bool _hasCpuOverride(String enc) => enc == 'x265' || enc == 'x264' || enc == 'ffcore';

  static int level(String enc) => _levels[enc] ?? 0;

  /// Appended to the -x265-params list (starts with ':' or is empty).
  static String x265AsmSuffix() {
    switch (level('x265')) {
      case 0:
        return '';
      case 1:
        return ':asm=2';
      default:
        return ':asm=0';
    }
  }

  /// Global FFmpeg option that restricts FFmpeg's OWN assembly (swscale etc.); empty at level 0. Ends with a space.
  static String ffArgs() {
    switch (level('ffcore')) {
      case 0:
        return '';
      case 1:
        return '-cpuflags -sve2-sve-i8mm-dotprod ';
      default:
        return '-cpuflags 0 ';
    }
  }

  /// Complete option for libx264 (or an empty string).
  static String x264Args() {
    switch (level('x264')) {
      case 0:
        return '';
      case 1:
        return '-x264-params asm=2';
      default:
        return '-x264-params asm=0';
    }
  }

  // ---------------------------------------------------------------------------
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/crash_log');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _file = File('${dir.path}/cpu_safe.json');
      if (_file!.existsSync()) {
        final m = jsonDecode(_file!.readAsStringSync());
        if (m is Map) {
          final lv = m['levels'];
          if (lv is Map) lv.forEach((k, v) { if (v is num) _levels[k.toString()] = v.toInt(); });
          final ve = m['verified'];
          if (ve is List) _verified.addAll(ve.map((e) => e.toString()));
        }
      }
      _absorbLastCrash();
    } catch (e) {
      debugPrint('CpuSafe.ensureLoaded failed: $e');
    }
  }

  static void _save() {
    try {
      _file?.writeAsStringSync(jsonEncode({'levels': _levels, 'verified': _verified.toList()}), flush: true);
    } catch (_) {}
  }

  /// If the previous session died of SIGILL inside an encoder, step that encoder down one level.
  static void _absorbLastCrash() {
    if (!CrashLog.lastCrashWasSigill) return;
    if (!CrashLog.lastInterruptedOp.contains('Video export')) return;
    final enc = _encoderInTrail(CrashLog.lastInterruptedTrail);
    CrashLog.lastCrashWasSigill = false; // consume
    if (enc == null) return;
    final int next = _hasCpuOverride(enc) ? (level(enc) + 1).clamp(0, 3).toInt() : 3;
    _levels[enc] = next;
    _verified.removeWhere((k) => k.startsWith('$enc|'));
    _save();
    debugPrint('CpuSafe: $enc crashed with SIGILL -> level $next');
  }

  /// The encoder of the LAST encode step that started but never returned (null if the last step finished).
  static String? _encoderInTrail(String trail) {
    final lines = trail.split('\n');
    for (int i = lines.length - 1; i >= 0; i--) {
      final l = lines[i];
      if (l.contains('RETURNED')) return null;
      if (l.contains('START')) {
        if (l.contains('probe START (convert')) return 'ffcore';
        if (l.contains('libx265')) return 'x265';
        if (l.contains('libx264')) return 'x264';
        if (l.contains('libsvtav1')) return 'svtav1';
        if (l.contains('libvpx')) return 'vpx';
        return null;
      }
    }
    return null;
  }

  static String _name(String enc) {
    switch (enc) {
      case 'x265':
        return 'HEVC (x265)';
      case 'x264':
        return 'H.264 (x264)';
      case 'svtav1':
        return 'AV1 (SVT-AV1)';
      case 'ffcore':
        return 'colour conversion (FFmpeg core)';
      default:
        return 'VP9 (libvpx)';
    }
  }

  // ---------------------------------------------------------------------------
  /// Probes FFmpeg's own RGB -> YUV conversion exactly the way the exports do it (bgr0 / rgba in, matrix + range tags,
  /// accurate rounding, with and without a resize). No encoder is involved (-f null), so a crash here is NOT x265 / x264.
  static Future<void> verifyConversion({required bool tenBit}) async {
    await ensureLoaded();
    final lv = level('ffcore');
    if (lv >= 3) {
      throw Exception('FFmpeg\'s colour conversion crashes on this phone\'s CPU even in compatibility mode, so exporting is disabled.');
    }
    final key = 'ffcore|$lv|${tenBit ? 10 : 8}';
    if (_verified.contains(key)) return;
    final pix = tenBit ? 'yuv420p10le' : 'yuv420p';
    final matrix = tenBit ? 'bt2020' : 'bt709';
    final stages = <String, String>{
      'convert-noresize': 'format=bgr0,scale=out_color_matrix=$matrix:out_range=tv:flags=accurate_rnd,format=$pix',
      'convert-resize': 'format=rgba,scale=1920:1080:flags=lanczos+accurate_rnd:out_color_matrix=$matrix:out_range=tv,format=$pix',
    };
    bool allOk = true;
    for (final e in stages.entries) {
      final cmd = '-y ${ffArgs()}-f lavfi -i testsrc2=size=1280x720:rate=25 -frames:v 10 -vf ${e.value} -f null -';
      CrashLog.note('probe START (${e.key}, level $lv): ffmpeg $cmd');
      try {
        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();
        CrashLog.note('probe RETURNED rc=$rc');
        if (!ReturnCode.isSuccess(rc)) allOk = false;
      } catch (err) {
        CrashLog.note('probe RETURNED with Dart exception: $err');
        allOk = false;
      }
    }
    if (allOk) {
      _verified.add(key);
      _save();
    }
  }

  // ---------------------------------------------------------------------------
  /// Runs a ~1 s probe of the encoder with the settings the export will use. A SIGILL kills the app right here (and the
  /// next launch steps the encoder down); a normal failure is ignored. Throws only when the encoder is blocked.
  static Future<void> verifyEncoder(String enc, {required bool tenBit}) async {
    await ensureLoaded();
    await verifyConversion(tenBit: tenBit);
    final lv = level(enc);
    if (lv >= 3) {
      throw Exception('${_name(enc)} crashes on this phone\'s CPU even in compatibility mode, so it is disabled. '
          'Export with ${enc == 'x265' ? 'H.264 or AV1' : (enc == 'x264' ? 'HEVC' : 'HEVC or H.264')} instead.');
    }
    final key = '$enc|$lv|${tenBit ? 10 : 8}';
    if (_verified.contains(key)) return;

    final pix = tenBit ? 'yuv420p10le' : 'yuv420p';
    String codecArgs;
    switch (enc) {
      case 'x265':
        codecArgs = '-c:v libx265 -preset veryfast '
            '-x265-params log-level=error:pools=none:frame-threads=1:bframes=3:rc-lookahead=20${x265AsmSuffix()} -b:v 8M';
        break;
      case 'x264':
        codecArgs = '-c:v libx264 -preset fast ${x264Args()} -b:v 8M';
        break;
      case 'svtav1':
        codecArgs = '-c:v libsvtav1 -preset 6 -b:v 8M';
        break;
      default:
        codecArgs = '-c:v libvpx-vp9 -deadline good -cpu-used 4 -row-mt 1 -b:v 8M';
    }
    final cmd = '-y ${ffArgs()}-f lavfi -i testsrc2=size=1280x720:rate=25 -frames:v 14 -vf format=$pix $codecArgs -f null -';
    CrashLog.note('probe START (${_name(enc)}, level $lv): ffmpeg $cmd');
    try {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      CrashLog.note('probe RETURNED rc=$rc');
      if (ReturnCode.isSuccess(rc)) {
        _verified.add(key);
        _save();
      }
      // A non-zero return code here (e.g. no lavfi in this build, or no 10-bit x264) is not a crash: carry on.
    } catch (e) {
      CrashLog.note('probe RETURNED with Dart exception: $e');
    }
  }
}
