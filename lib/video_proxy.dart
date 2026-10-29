// =============================================================================
// AEReality / Shaderly - VideoProxy (batch 18A)
//
// WHY: the editor's video_player (Android MediaCodec / ExoPlayer) only plays what the phone's decoders and the file's index allow.
//   * VP9 / WebM / MKV files without a duration or seek index report a wrong duration (0.1 s for a 1-minute clip) and every seek jumps to 0.
//   * HEVC at high quality (10-bit, high bitrate, 4K) can fail to initialise or die while playing.
// FFmpeg (already in the app) can decode all of these, so when the native player cannot use a file we build ONE temporary H.264
// copy ("proxy") of it and the player plays that instead.
//
// WHAT IT IS USED FOR: the proxy is ONLY what video_player plays (picture while playing, sound, the timeline clock, seeking).
// The project keeps pointing at the ORIGINAL file: preview frames, Adaptive chunks, Time Slice and the export all still read the original.
// The proxy is cached (temp dir, keyed by path + size + modified time), so opening the same video again is instant.
//
// This file only uses FFmpegKit.execute / session.getOutput(), the same calls the live code already makes. getOutput() is read through
// `dynamic` inside try/catch (as export_suite.dart does); if it returns nothing, probe() returns MediaProbe.unknown and the callers fall back.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cpu_safe.dart';

/// What `ffmpeg -i file` prints about a media file. Every field can be unknown.
class MediaProbe {
  final bool ok; // the ffmpeg log could be read and contained stream information
  final double? durationSec; // null = unknown ("N/A" or not printed)
  final int? width; // display size, rotation already applied
  final int? height;
  final String? videoCodec; // 'h264', 'hevc', 'vp9', 'av1' ...
  final bool tenBit;
  final bool hasAudio;

  const MediaProbe({
    required this.ok,
    this.durationSec,
    this.width,
    this.height,
    this.videoCodec,
    this.tenBit = false,
    this.hasAudio = false,
  });

  static const MediaProbe unknown = MediaProbe(ok: false);

  bool get hasSize => width != null && height != null && width! > 0 && height! > 0;
}

class VideoProxy {
  VideoProxy._();

  static final Map<String, Future<String?>> _inflight = {};
  static bool _purged = false;

  /// mp4 / mov / m4v / 3gp: the native player is tried first with NO extra ffmpeg process (keeps opening a project fast).
  static bool looksNativeSafe(String path) {
    final String e = path.split('.').last.toLowerCase();
    return e == 'mp4' || e == 'm4v' || e == 'mov' || e == '3gp';
  }

  static String _cpuArgs() {
    try {
      return CpuSafe.ffArgs();
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // PROBE
  // ---------------------------------------------------------------------------
  /// `ffmpeg -i file` with no output exits with an error code on purpose; the stream information it prints first is what we read.
  static Future<MediaProbe> probe(String path) async {
    try {
      final dynamic session = await FFmpegKit.execute('-hide_banner -i "$path"');
      String out = '';
      try {
        out = ((await session.getOutput()) ?? '').toString();
      } catch (_) {}
      return parse(out);
    } catch (e) {
      debugPrint('VideoProxy.probe failed: $e');
      return MediaProbe.unknown;
    }
  }

  static MediaProbe parse(String log) {
    if (log.isEmpty) return MediaProbe.unknown;

    double? dur;
    final dm = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)').firstMatch(log);
    if (dm != null) {
      dur = int.parse(dm.group(1)!) * 3600.0 + int.parse(dm.group(2)!) * 60.0 + double.parse(dm.group(3)!);
      if (dur <= 0) dur = null;
    }

    String? codec;
    int? w;
    int? h;
    bool ten = false;
    for (final m in RegExp(r'Stream #\d+:\d+[^\n]*?: Video: ([A-Za-z0-9_]+)([^\n]*)').allMatches(log)) {
      final String rest = m.group(2) ?? '';
      if (rest.contains('attached pic')) continue; // cover art, not the picture
      codec = m.group(1)!.toLowerCase();
      final dims = RegExp(r',\s*(\d{2,5})x(\d{2,5})').firstMatch(rest);
      if (dims != null) {
        w = int.parse(dims.group(1)!);
        h = int.parse(dims.group(2)!);
      }
      ten = RegExp(r'p1[02](le|be)?').hasMatch(rest) || rest.contains('Main 10');
      break;
    }

    // phone videos: the file stores landscape frames plus a rotation; the player and ffmpeg both show them rotated
    final rot = RegExp(r'rotation of (-?\d+(?:\.\d+)?) degrees').firstMatch(log);
    if (rot != null && w != null && h != null) {
      final double deg = double.parse(rot.group(1)!).abs() % 180.0;
      if ((deg - 90.0).abs() < 1.0) {
        final int t = w;
        w = h;
        h = t;
      }
    }

    final bool audio = RegExp(r'Stream #\d+:\d+[^\n]*?: Audio:').hasMatch(log);
    final bool ok = codec != null || dur != null;
    return MediaProbe(ok: ok, durationSec: dur, width: w, height: h, videoCodec: codec, tenBit: ten, hasAudio: audio);
  }

  // ---------------------------------------------------------------------------
  // PROXY
  // ---------------------------------------------------------------------------
  static String _key(String path, int length, int modifiedMs) {
    int h = 0x811C9DC5;
    for (final int u in '$path|$length|$modifiedMs'.codeUnits) {
      h ^= u & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= (u >> 8) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Long edge is capped at 1280 px (the proxy is only what the phone screen plays); sizes are always even for H.264.
  /// Without a known size nothing is scaled except the even-size fix.
  static String _scaleFilter(MediaProbe p) {
    const int cap = 1280;
    if (p.hasSize) {
      final int w = p.width!;
      final int h = p.height!;
      final int long = math.max(w, h);
      if (long > cap) {
        final double f = cap / long;
        final int nw = math.max(2, ((w * f) / 2).round() * 2);
        final int nh = math.max(2, ((h * f) / 2).round() * 2);
        return 'scale=$nw:$nh';
      }
    }
    return 'scale=trunc(iw/2)*2:trunc(ih/2)*2';
  }

  /// Returns the path of a playable H.264 / yuv420p / 8-bit copy of [srcPath] (from the cache when it exists), or null when ffmpeg failed.
  /// Never throws. Calls for the same file share one running conversion.
  static Future<String?> ensureProxy(String srcPath, MediaProbe probe) {
    return _inflight.putIfAbsent(srcPath, () => _build(srcPath, probe).whenComplete(() => _inflight.remove(srcPath)));
  }

  static Future<String?> _build(String srcPath, MediaProbe probe) async {
    try {
      final File src = File(srcPath);
      if (!src.existsSync()) return null;
      final Directory dir = Directory('${(await getTemporaryDirectory()).path}/shaderly_proxy');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final String key = _key(srcPath, src.lengthSync(), src.lastModifiedSync().millisecondsSinceEpoch);
      final File out = File('${dir.path}/p_$key.mp4');
      if (out.existsSync() && out.lengthSync() > 4096) {
        debugPrint('VideoProxy: cached proxy ${out.path}');
        return out.path;
      }
      final File part = File('${dir.path}/p_$key.part.mp4');

      final String vf = _scaleFilter(probe);
      // Short GOP (every 12 frames): seeks and scrubbing land on the exact frame quickly. Ultrafast: this runs once, in the background.
      final String video = '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -vf "$vf" -g 12';
      final List<String> attempts = [
        '-hide_banner -y ${_cpuArgs()}-i "$srcPath" -map 0:v:0 -map 0:a:0? -sn -dn $video -c:a aac -b:a 128k -movflags +faststart "${part.path}"',
        // second try without sound: a source audio stream ffmpeg cannot convert must not cost the picture
        '-hide_banner -y ${_cpuArgs()}-i "$srcPath" -map 0:v:0 -an -sn -dn $video -movflags +faststart "${part.path}"',
      ];

      final Stopwatch sw = Stopwatch()..start();
      for (final String cmd in attempts) {
        try {
          if (part.existsSync()) part.deleteSync();
        } catch (_) {}
        final dynamic session = await FFmpegKit.execute(cmd);
        final dynamic rc = await session.getReturnCode();
        final bool good = ReturnCode.isSuccess(rc) && part.existsSync() && part.lengthSync() > 4096;
        if (good) {
          if (out.existsSync()) out.deleteSync();
          part.renameSync(out.path);
          debugPrint('VideoProxy: built ${out.path} in ${sw.elapsedMilliseconds} ms');
          unawaited(_purgeOld(dir, keepNewest: 6));
          return out.path;
        }
        debugPrint('VideoProxy: attempt failed (rc=$rc)');
      }
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      return null;
    } catch (e) {
      debugPrint('VideoProxy._build failed: $e');
      return null;
    }
  }

  /// Keeps the newest [keepNewest] proxies, removes the rest and any half-written .part file from an older run. Runs once per app start.
  static Future<void> _purgeOld(Directory dir, {required int keepNewest}) async {
    if (_purged) return;
    _purged = true;
    try {
      final List<FileSystemEntity> all = dir.listSync();
      final List<File> done = [];
      for (final FileSystemEntity e in all) {
        if (e is! File) continue;
        if (e.path.endsWith('.part.mp4')) {
          // only a leftover from an older run (a conversion running right now has a fresh timestamp)
          try {
            if (DateTime.now().difference(e.lastModifiedSync()) > const Duration(hours: 1)) e.deleteSync();
          } catch (_) {}
        } else if (e.path.endsWith('.mp4')) {
          done.add(e);
        }
      }
      done.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (int i = keepNewest; i < done.length; i++) {
        try {
          done[i].deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
