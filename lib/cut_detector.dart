// =============================================================================
// AEReality / Shaderly - Batch 12 (step A): CutDetector (Time Slice trigger source, "hard cut inside one video")
//
// Two stages, so the threshold can be tuned without scanning again:
//   1. SCAN (slow, once per video, cached on disk): per-frame scene scores at a tiny resolution.
//        method "scdet": ffmpeg's scdet filter, scores read back through the metadata filter (frame time = the real pts_time).
//        method "dart" : fallback when scdet / metadata are not in this ffmpeg build. ffmpeg writes tiny gray frames to a raw
//                        file and Dart computes the SAME two numbers (mafd and score, formulas below). Frame time = index * duration / frames
//                        (assumes a constant frame rate).
//   2. DETECT (instant, pure Dart): turns the cached scores into cut times with the Time Slice cut settings
//        (threshold, minimum gap, flash rejection). Used by the wipe scheduler (main.dart); the step A / C1 test dialogs were removed in step C3.
//
// Numbers (scdet scale 0..100): mafd = mean absolute frame difference; score = min(mafd, |mafd - previous mafd|), so a long fast pan
// (high mafd all the time) scores low while a cut (one big jump) scores high. A white flash scores high on its first frame only, which is
// why flash rejection looks at mafd (it is high again when the flash ends), not at the score.
//
// No GPU / shader / grade pipeline code is touched here. Cache: <app support>/timeslice_cuts/<key>.json
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'crash_log.dart';
import 'time_slice_slots.dart';

class CutScan {
  final String method; // 'scdet' or 'dart'
  final List<double> times; // seconds, one per frame
  final List<double> mafd;
  final List<double> score;
  // batch 3: SHIFT series (slides / pushes / whips), sampled on a fixed 30 fps grid (sample i = i / CutDetector.shiftFps seconds):
  //   shiftD[i] = how different the picture is 5 frames before and 5 frames after sample i (0..255 grey scale), shiftE[i] = mean motion around it.
  final List<double> shiftD;
  final List<double> shiftE;

  CutScan({required this.method, required this.times, required this.mafd, required this.score, this.shiftD = const <double>[], this.shiftE = const <double>[]});

  int get frames => times.length;

  Map<String, dynamic> toJson() => {
        'v': CutDetector.scannerVersion,
        'method': method,
        't': times.map((e) => double.parse(e.toStringAsFixed(4))).toList(),
        'm': mafd.map((e) => double.parse(e.toStringAsFixed(3))).toList(),
        's': score.map((e) => double.parse(e.toStringAsFixed(3))).toList(),
        'sd': shiftD.map((e) => double.parse(e.toStringAsFixed(2))).toList(),
        'se': shiftE.map((e) => double.parse(e.toStringAsFixed(2))).toList(),
      };

  static CutScan? fromJson(dynamic j) {
    if (j is! Map) return null;
    if (j['v'] != CutDetector.scannerVersion) return null;
    final t = j['t'], m = j['m'], s = j['s'];
    if (t is! List || m is! List || s is! List) return null;
    if (t.length != m.length || t.length != s.length || t.isEmpty) return null;
    return CutScan(
      method: j['method']?.toString() ?? 'dart',
      times: t.map((e) => (e as num).toDouble()).toList(),
      mafd: m.map((e) => (e as num).toDouble()).toList(),
      score: s.map((e) => (e as num).toDouble()).toList(),
      shiftD: j['sd'] is List ? (j['sd'] as List).map((e) => (e as num).toDouble()).toList() : const <double>[],
      shiftE: j['se'] is List ? (j['se'] as List).map((e) => (e as num).toDouble()).toList() : const <double>[],
    );
  }
}

class CutDetector {
  /// Bump when the scan command / scoring changes: old caches are then ignored.
  static const int scannerVersion = 2; // 2 = batch 3: the scan also stores the shift series (old caches are rescanned once)

  /// Sample rate of the shift series and the half window (frames) of its before / after comparison.
  static const int shiftFps = 30;
  static const int _shiftWin = 5;
  static const int _shiftW = 48, _shiftH = 27;

  static const int _dartW = 96, _dartH = 54;

  // ---------------------------------------------------------------------------------------------------------------
  // CACHE
  // ---------------------------------------------------------------------------------------------------------------
  static int _fnv(String s) {
    int h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static Future<File?> _cacheFile(String mediaPath) async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/timeslice_cuts');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File(mediaPath);
      String stamp = '';
      if (f.existsSync()) stamp = '${f.lengthSync()}|${f.lastModifiedSync().millisecondsSinceEpoch}';
      final key = _fnv('$mediaPath|$stamp|v$scannerVersion').toRadixString(16);
      return File('${dir.path}/$key.json');
    } catch (_) {
      return null;
    }
  }

  static Future<CutScan?> loadCached(String mediaPath) async {
    try {
      final f = await _cacheFile(mediaPath);
      if (f == null || !f.existsSync()) return null;
      return CutScan.fromJson(jsonDecode(f.readAsStringSync()));
    } catch (e) {
      debugPrint('CutDetector.loadCached failed: $e');
      return null;
    }
  }

  static Future<void> _store(String mediaPath, CutScan s) async {
    try {
      final f = await _cacheFile(mediaPath);
      f?.writeAsStringSync(jsonEncode(s.toJson()), flush: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------------------------------------------
  // SCAN
  // ---------------------------------------------------------------------------------------------------------------
  /// Returns the cached scan, or scans the video (scdet first, Dart fallback) and caches it. [forceDart] skips scdet (used by the test dialog
  /// to try the fallback). [durationSeconds] is only used by the Dart fallback for frame times. Returns null when both methods failed.
  static Future<CutScan?> scan(String mediaPath, double durationSeconds, {bool forceRescan = false, bool forceDart = false}) async {
    if (!forceRescan) {
      final c = await loadCached(mediaPath);
      if (c != null) return c;
    }
    CutScan? s;
    if (!forceDart) s = await _scanScdet(mediaPath);
    s ??= await _scanDart(mediaPath, durationSeconds);
    if (s != null) {
      final sh = await _scanShift(mediaPath);
      if (sh != null) {
        s = CutScan(method: s.method, times: s.times, mafd: s.mafd, score: s.score, shiftD: sh[0], shiftE: sh[1]);
      }
      await _store(mediaPath, s);
    }
    return s;
  }

  /// batch 3: one more small decode (48 x 27 grey, 30 fps, real timestamps from ffmpeg's fps filter) for slides / pushes / whips, which have NO single
  /// big jump and so score ~0 in the scdet / mafd numbers above. Returns [shiftD, shiftE] or null when ffmpeg could not.
  static Future<List<List<double>>?> _scanShift(String mediaPath) async {
    final dir = await _tmp();
    final out = File('${dir.path}/ts_shift.gray');
    try {
      if (out.existsSync()) out.deleteSync();
    } catch (_) {}
    final cmd = '-hide_banner -loglevel error -y -i "$mediaPath" -an -sn -dn '
        '-vf "fps=$shiftFps,scale=$_shiftW:$_shiftH:flags=area,format=gray" -f rawvideo "${out.path}"';
    CrashLog.note('cut scan (shift) START: ffmpeg $cmd');
    try {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      CrashLog.note('cut scan (shift) RETURNED rc=$rc');
      if (!ReturnCode.isSuccess(rc) || !out.existsSync()) return null;
      final Uint8List b = await out.readAsBytes();
      try {
        out.deleteSync();
      } catch (_) {}
      final int fb = _shiftW * _shiftH;
      final int n = b.length ~/ fb;
      if (n < 2 * _shiftWin + 2) return null;
      double mad(int a, int c) {
        int sum = 0;
        final int oa = a * fb, oc = c * fb;
        for (int i = 0; i < fb; i++) {
          final int d = b[oa + i] - b[oc + i];
          sum += d < 0 ? -d : d;
        }
        return sum / fb;
      }
      final d1 = List<double>.filled(n, 0.0);
      for (int i = 1; i < n; i++) {
        d1[i] = mad(i - 1, i);
      }
      final dd = List<double>.filled(n, 0.0);
      final ee = List<double>.filled(n, 0.0);
      for (int i = _shiftWin; i < n - _shiftWin; i++) {
        dd[i] = mad(i - _shiftWin, i + _shiftWin);
        double e = 0.0;
        for (int k = -_shiftWin; k <= _shiftWin; k++) {
          e += d1[i + k];
        }
        ee[i] = e / (2 * _shiftWin + 1);
      }
      return <List<double>>[dd, ee];
    } catch (e) {
      CrashLog.note('cut scan (shift) RETURNED with Dart exception: $e');
      return null;
    }
  }

  static Future<Directory> _tmp() => getTemporaryDirectory();

  static Future<CutScan?> _scanScdet(String mediaPath) async {
    final dir = await _tmp();
    final out = File('${dir.path}/ts_scdet.txt');
    try {
      if (out.existsSync()) out.deleteSync();
    } catch (_) {}
    final cmd = '-hide_banner -loglevel error -y -i "$mediaPath" -an -sn -dn '
        '-vf "scale=160:90:flags=fast_bilinear,scdet=threshold=0:sc_pass=0,metadata=mode=print:file=${out.path}" -f null -';
    CrashLog.note('cut scan (scdet) START: ffmpeg $cmd');
    try {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      CrashLog.note('cut scan (scdet) RETURNED rc=$rc');
      if (!ReturnCode.isSuccess(rc) || !out.existsSync()) return null;
      final parsed = parseScdetMetadata(out.readAsStringSync());
      try {
        out.deleteSync();
      } catch (_) {}
      return parsed;
    } catch (e) {
      CrashLog.note('cut scan (scdet) RETURNED with Dart exception: $e');
      return null;
    }
  }

  /// Parses the metadata filter's print output:
  ///   frame:30   pts:15360  pts_time:1
  ///   lavfi.scd.mafd=28.451
  ///   lavfi.scd.score=28.451
  ///   lavfi.scd.time=1
  /// Public so the format can be unit-tested. Returns null when no frame was found.
  static CutScan? parseScdetMetadata(String text) {
    final times = <double>[];
    final mafd = <double>[];
    final score = <double>[];
    final reTime = RegExp(r'pts_time:\s*([-+0-9.eE]+)');
    double? t;
    double? m;
    for (final line in text.split('\n')) {
      if (line.startsWith('frame:')) {
        final mt = reTime.firstMatch(line);
        t = mt == null ? null : double.tryParse(mt.group(1)!);
        m = null;
      } else if (line.startsWith('lavfi.scd.mafd=')) {
        m = double.tryParse(line.substring('lavfi.scd.mafd='.length).trim());
      } else if (line.startsWith('lavfi.scd.score=')) {
        final s = double.tryParse(line.substring('lavfi.scd.score='.length).trim());
        if (t != null && m != null && s != null) {
          times.add(t);
          mafd.add(m);
          score.add(s);
        }
        t = null;
        m = null;
      }
    }
    if (times.isEmpty) return null;
    return CutScan(method: 'scdet', times: times, mafd: mafd, score: score);
  }

  static Future<CutScan?> _scanDart(String mediaPath, double durationSeconds) async {
    final dir = await _tmp();
    final out = File('${dir.path}/ts_gray.raw');
    final vf = 'scale=$_dartW:$_dartH:flags=area,format=gray';
    bool ok = false;
    // -fps_mode needs ffmpeg 5.1+, -vsync 0 is the older spelling: try both.
    for (final opt in const ['-fps_mode passthrough', '-vsync 0']) {
      try {
        if (out.existsSync()) out.deleteSync();
      } catch (_) {}
      final cmd = '-hide_banner -loglevel error -y -i "$mediaPath" -an -sn -dn $opt -vf "$vf" -f rawvideo "${out.path}"';
      CrashLog.note('cut scan (dart) START: ffmpeg $cmd');
      try {
        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();
        CrashLog.note('cut scan (dart) RETURNED rc=$rc');
        if (ReturnCode.isSuccess(rc) && out.existsSync() && out.lengthSync() >= _dartW * _dartH * 2) {
          ok = true;
          break;
        }
      } catch (e) {
        CrashLog.note('cut scan (dart) RETURNED with Dart exception: $e');
      }
    }
    if (!ok) return null;

    final frameBytes = _dartW * _dartH;
    final n = out.lengthSync() ~/ frameBytes;
    final step = durationSeconds > 0.0 ? durationSeconds / n : 1.0 / 30.0;
    final times = List<double>.filled(n, 0.0);
    final mafd = List<double>.filled(n, 0.0);
    final score = List<double>.filled(n, 0.0);
    final raf = await out.open();
    try {
      Uint8List prev = Uint8List(0);
      double prevM = 0.0;
      for (int i = 0; i < n; i++) {
        final cur = await raf.read(frameBytes);
        if (cur.length < frameBytes) break;
        times[i] = i * step;
        if (i > 0) {
          int sad = 0;
          for (int k = 0; k < frameBytes; k++) {
            final d = cur[k] - prev[k];
            sad += d < 0 ? -d : d;
          }
          final m = sad / frameBytes / 255.0 * 100.0;
          mafd[i] = m;
          score[i] = math.min(m, (m - prevM).abs());
          prevM = m;
        }
        prev = cur;
      }
    } finally {
      await raf.close();
      try {
        out.deleteSync();
      } catch (_) {}
    }
    return CutScan(method: 'dart', times: times, mafd: mafd, score: score);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // DETECT (pure, instant)
  // ---------------------------------------------------------------------------------------------------------------
  /// Cut times in seconds (time of the FIRST frame of the new shot) from a scan and the Time Slice settings list.
  static List<double> detect(CutScan scan, List<double> settings) {
    return detectWith(
      scan,
      threshold: settings[TimeSlice.cutThreshold],
      minGap: settings[TimeSlice.cutMinGap],
      flashReject: settings[TimeSlice.cutFlashReject] > 0.5,
      flashWindow: settings[TimeSlice.cutFlashWindow],
      shifts: settings[TimeSlice.shiftOff] < 0.5,
      shiftSensitivity: settings[TimeSlice.shiftSens],
    );
  }

  /// batch 3: slide / push / whip triggers from the shift series. A trigger is a local maximum of shiftD (picture 5 frames before vs 5 after) above a threshold
  /// (sensitivity 1 -> 11, 0.5 -> 24, 0.05 -> 38 on the 0..255 grey scale) with motion around it; the time is the centre of the transition.
  static List<double> _detectShifts(CutScan scan, double sensitivity, double minGap) {
    final dd = scan.shiftD;
    final ee = scan.shiftE;
    final n = dd.length;
    if (n < 2 * _shiftWin + 2 || ee.length != n) return <double>[];
    final double sens = sensitivity.clamp(0.05, 1.0).toDouble();
    final double thr = 38.0 - (sens - 0.05) * (27.0 / 0.95);
    final int gap = math.max((minGap * shiftFps).round(), 8);
    final out = <double>[];
    int last = -1000000;
    for (int i = _shiftWin; i < n - _shiftWin; i++) {
      final v = dd[i];
      if (v < thr || ee[i] < thr * 0.22) continue;
      bool peak = true;
      for (int k = -_shiftWin; k <= _shiftWin && peak; k++) {
        final j = i + k;
        if (j >= _shiftWin && j < n - _shiftWin && dd[j] > v) peak = false;
      }
      if (!peak) continue;
      if (i - last < gap) {
        if (out.isNotEmpty && v > dd[last]) {
          out.removeLast();
        } else {
          continue;
        }
      }
      last = i;
      out.add(i / shiftFps);
    }
    return out;
  }

  static List<double> detectWith(CutScan scan, {required double threshold, required double minGap, required bool flashReject, required double flashWindow, bool shifts = false, double shiftSensitivity = 0.5}) {
    final n = scan.frames;
    final t = scan.times;
    final m = scan.mafd;
    final s = scan.score;
    final cuts = <double>[];
    // Flash pass first: a spike whose picture is back to "different again" a few frames later (mafd high at the entry AND at the exit of
    // the flash) is a flash, and every frame from entry to exit is excluded. (A real cut has a quiet mafd on the frames after it.)
    final flashFrames = <int>{};
    if (flashReject) {
      for (int i = 1; i < n; i++) {
        if (s[i] < threshold || flashFrames.contains(i)) continue;
        for (int j = i + 1; j < n; j++) {
          if (t[j] - t[i] > flashWindow) break;
          if (m[j] >= threshold && m[j] >= 0.6 * m[i]) {
            for (int k = i; k <= j; k++) {
              flashFrames.add(k);
            }
            break;
          }
        }
      }
    }
    for (int i = 1; i < n; i++) {
      if (s[i] < threshold || flashFrames.contains(i)) continue;
      // only the strongest frame of a small neighbourhood counts (a cut blended over two frames is still one cut)
      bool isPeak = true;
      final lo = math.max(1, i - 2), hi = math.min(n - 1, i + 2);
      for (int j = lo; j <= hi; j++) {
        if (j == i || flashFrames.contains(j)) continue;
        if (s[j] > s[i] || (s[j] == s[i] && j < i)) {
          isPeak = false;
          break;
        }
      }
      if (!isPeak) continue;
      if (cuts.isNotEmpty && t[i] - cuts.last < minGap) continue;
      cuts.add(t[i]);
    }
    if (shifts && scan.shiftD.isNotEmpty) {
      // a shift within 0.3 s of a hard cut is the same event: the hard cut wins
      for (final double st in _detectShifts(scan, shiftSensitivity, math.max(0.25, minGap))) {
        bool dup = false;
        for (final double c in cuts) {
          if ((c - st).abs() < 0.3) {
            dup = true;
            break;
          }
        }
        if (!dup) cuts.add(st);
      }
      cuts.sort();
    }
    return cuts;
  }
}
