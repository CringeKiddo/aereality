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
  final double? fps; // frames per second the stream header says (null = unknown)

  const MediaProbe({
    required this.ok,
    this.durationSec,
    this.width,
    this.height,
    this.videoCodec,
    this.tenBit = false,
    this.hasAudio = false,
    this.fps,
  });

  static const MediaProbe unknown = MediaProbe(ok: false);

  bool get hasSize => width != null && height != null && width! > 0 && height! > 0;
}

class VideoProxy {
  VideoProxy._();

  static final Map<String, Future<String?>> _inflight = {};

  /// Why the last conversion failed (ffmpeg's last lines), for the "could not be opened" message. '' = nothing failed.
  static String lastFailure = '';
  static bool _purged = false;

  /// Long edge of the proxy (batch 18B: 1920, was 1280). Sources up to 1080p are NOT scaled at all; 4K sources become 1080p proxies, because many phone
  /// decoders cannot play 4K H.264 and the conversion would take minutes. 0 = never scale.
  static const int maxLongEdge = 1920;

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
    double? fps;
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
      final fm = RegExp(r'(\d+(?:\.\d+)?) fps').firstMatch(rest);
      if (fm != null) fps = double.tryParse(fm.group(1)!);
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
    return MediaProbe(ok: ok, durationSec: dur, width: w, height: h, videoCodec: codec, tenBit: ten, hasAudio: audio, fps: fps);
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

  /// Long edge is capped at [maxLongEdge]; sizes are always even for H.264.
  /// Without a known size nothing is scaled except the even-size fix.
  static String _scaleFilter(MediaProbe p) {
    final int cap = maxLongEdge;
    if (cap > 0 && p.hasSize) {
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
  ///
  /// The caller waits at most [proxyTimeout] (15 s): after that this returns null and the caller falls back, so the UI never hangs. The conversion itself is NOT
  /// abandoned: it keeps running in the background and fills the cache, so opening the same video again a little later finds the finished proxy at once.
  static const Duration proxyTimeout = Duration(seconds: 15);

  /// true while a conversion of [srcPath] is still running (after ensureProxy gave up waiting).
  static bool isConverting(String srcPath) => _inflight.containsKey(srcPath);

  /// Keeps waiting for a running conversion (at most [limit]); null when none runs, it failed, or the limit passed.
  static Future<String?> awaitConversion(String srcPath, {Duration limit = const Duration(minutes: 4)}) {
    final Future<String?>? w = _inflight[srcPath];
    if (w == null) return Future<String?>.value(null);
    return w.timeout(limit, onTimeout: () => null);
  }

  static Future<String?> ensureProxy(String srcPath, MediaProbe probe) {
    final Future<String?> work = _inflight.putIfAbsent(srcPath, () => _build(srcPath, probe).whenComplete(() => _inflight.remove(srcPath)));
    return work.timeout(proxyTimeout, onTimeout: () {
      debugPrint('VideoProxy: no proxy after ${proxyTimeout.inSeconds} s, continuing without it (the conversion keeps running in the background)');
      return null;
    });
  }

  static Future<String?> _build(String srcPath, MediaProbe probe) async {
    try {
      lastFailure = '';
      final File src = File(srcPath);
      if (!src.existsSync()) {
        lastFailure = 'the source file is not readable';
        return null;
      }
      final Directory dir = Directory('${(await getTemporaryDirectory()).path}/shaderly_proxy');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final String key = _key(srcPath, src.lengthSync(), src.lastModifiedSync().millisecondsSinceEpoch);
      final File out = File('${dir.path}/p_$key.mp4');
      if (out.existsSync() && out.lengthSync() > 4096) {
        // a cached proxy that is much shorter than its source (an earlier, broken conversion) is not trusted
        if (await _looksComplete(out.path, probe.durationSec)) {
          debugPrint('VideoProxy: cached proxy ${out.path}');
          return out.path;
        }
        debugPrint('VideoProxy: cached proxy is too short, rebuilding');
        try {
          out.deleteSync();
        } catch (_) {}
      }
      final File part = File('${dir.path}/p_$key.part.mp4');

      final String vf = _scaleFilter(probe);
      // Short GOP (every 12 frames): seeks and scrubbing land on the exact frame quickly. Ultrafast: this runs once, in the background.
      // Import fix (task 5): the plainest, safest libx264 command - ultrafast preset, 8-bit yuv420p, no extra encoder options. -vf only makes the size even / caps 4K,
      // -g 12 keeps the seeks exact (both are encoder-independent).
      final String video = '-c:v libx264 -preset ultrafast -pix_fmt yuv420p -vf "$vf" -g 12';
      // -fflags +genpts: WebM / MKV files with missing or broken timestamps get generated ones (without them ffmpeg can drop every frame but the first,
      // which is a proxy that is "a single static image").
      final String fpsArg = (probe.fps != null && probe.fps! >= 1 && probe.fps! <= 120) ? probe.fps!.toStringAsFixed(3) : '30';
      final List<String> attempts = [
        '-hide_banner -y ${_cpuArgs()}-fflags +genpts -i "$srcPath" -map 0:v:0 -map 0:a:0? -sn -dn $video -c:a aac -b:a 128k -movflags +faststart "${part.path}"',
        // second try without sound: a source audio stream ffmpeg cannot convert must not cost the picture
        '-hide_banner -y ${_cpuArgs()}-fflags +genpts -i "$srcPath" -map 0:v:0 -an -sn -dn $video -movflags +faststart "${part.path}"',
        // last try: constant frame rate with generated timestamps (accepted even if it cannot be checked against the source)
        '-hide_banner -y ${_cpuArgs()}-fflags +genpts -i "$srcPath" -map 0:v:0 -an -sn -dn $video -vsync cfr -r $fpsArg -movflags +faststart "${part.path}"',
      ];

      final Stopwatch sw = Stopwatch()..start();
      for (int ai = 0; ai < attempts.length; ai++) {
        final String cmd = attempts[ai];
        try {
          if (part.existsSync()) part.deleteSync();
        } catch (_) {}
        final dynamic session = await FFmpegKit.execute(cmd);
        final dynamic rc = await session.getReturnCode();
        bool good = ReturnCode.isSuccess(rc) && part.existsSync() && part.lengthSync() > 4096;
        // the result must be about as long as the source (a one-frame "video" is not a proxy); the last attempt is accepted as it is
        if (good && ai < attempts.length - 1 && !await _looksComplete(part.path, probe.durationSec)) {
          debugPrint('VideoProxy: attempt $ai produced a too short video');
          good = false;
        }
        if (good) {
          if (out.existsSync()) out.deleteSync();
          part.renameSync(out.path);
          debugPrint('VideoProxy: built ${out.path} in ${sw.elapsedMilliseconds} ms');
          unawaited(_purgeOld(dir, keepNewest: 6));
          return out.path;
        }
        debugPrint('VideoProxy: attempt failed (rc=$rc)');
        try {
          String tail = '';
          try {
            tail = ((await session.getOutput()) ?? '').toString();
          } catch (_) {}
          final lines = tail.split('\n').where((l) => l.trim().isNotEmpty).toList();
          final last = lines.length > 3 ? lines.sublist(lines.length - 3).join(' / ') : lines.join(' / ');
          lastFailure = 'attempt ${ai + 1} (rc=$rc): $last';
        } catch (_) {}
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

  /// false when [path] is clearly shorter than the source ([srcDur] seconds, null = unknown) or shorter than half a second.
  static Future<bool> _looksComplete(String path, double? srcDur) async {
    final MediaProbe p = await probe(path);
    final double? pd = p.durationSec;
    if (pd == null) return true; // cannot be measured: do not reject a good file
    if (pd < 0.5 && (srcDur == null || srcDur >= 0.5)) return false;
    if (srcDur != null && srcDur >= 1.0 && pd < srcDur * 0.8) return false;
    return true;
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
