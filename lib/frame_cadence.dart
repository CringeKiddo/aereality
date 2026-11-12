// =============================================================================
// AEReality / Shaderly - FrameCadence (batch 20): DUPLICATE FRAME REMOVER
//
// PROBLEM: a clip that comes from another app is often a 60 fps file made of a 24 / 30 fps picture, with every picture repeated 2 or 3 times in an UNEVEN pattern
// (2, 3, 2, 3 ... or random from a variable-frame-rate editor). Exported as it is, the repeats come out at the same uneven spacing = visible judder, and the frame rate
// you picked in the export menu is not what the picture really does.
//
// WHAT THIS DOES (only when the "Duplicate frame remover" switch is on):
//   1. SCAN: the clip is decoded once as tiny 64 x 36 grey frames at its own constant frame rate (the same rate the export decode uses). A frame that is a copy of the one
//      before (mean difference under a noise threshold) is a DUPLICATE; every other frame starts a new UNIQUE picture.
//   2. REMOVE: the duplicates are dropped. Nothing is invented, no frame is blended.
//   3. RE-TIME: the unique pictures are laid on an even grid (a least-squares line through their start positions, per steady stretch), so every picture is held the same time
//      (as near as the chosen frame rate allows). A deliberate HOLD (one picture held for more than a quarter of a second) is never touched.
//   4. The export then shows, for output frame k at the chosen fps, the unique picture that belongs to that time. Output = exactly the chosen frame rate, even cadence.
//   The audio is not touched; a picture moves at most about one repeat from where it was.
//
// [ASSUMED] duplicate threshold: mean absolute difference of the 64 x 36 grey frames under max(0.35, 0.06 * the 90th percentile of all differences) levels of 255.
// Scan cost: one fast tiny decode of the whole clip (a few seconds for a minute of footage). Any failure = no plan = the export behaves exactly as before.
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cpu_safe.dart';
import 'video_proxy.dart';

class CadencePlan {
  final double srcFps; // constant frame rate the scan (and the export decode) runs at
  final int frames; // source frames scanned
  final List<int> starts; // source frame index where every unique picture starts
  final List<double> slots; // re-timed start position of every unique picture (source frame units, same length as starts)
  final int duplicates;

  const CadencePlan(this.srcFps, this.frames, this.starts, this.slots, this.duplicates);

  int get unique => starts.length;
  bool get hasDuplicates => duplicates > 0;

  /// Source frame index that output frame [k] (time k / outFps) has to show.
  int sourceIndexFor(int k, double outFps) {
    if (starts.isEmpty) return 0;
    final double pos = (k / outFps) * srcFps + 1e-6;
    int lo = 0, hi = slots.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (slots[mid] <= pos) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return starts[lo];
  }

  String get summary => '${frames} source frames at ${srcFps.toStringAsFixed(3)} fps: $unique unique pictures, $duplicates duplicates removed '
      '(${unique > 0 ? (frames / unique).toStringAsFixed(2) : '-'} frames per picture on average)';
}

class FrameCadence {
  FrameCadence._();

  /// The switch of the export sheet and the Motion S menu (saved by SettingsStore, app_settings.dart).
  static bool enabled = false;

  static const int _tw = 64, _th = 36;
  static String _planKey = '';
  static CadencePlan? _plan;
  static String lastNote = '';

  /// Scans [path] (cached per file + size) and returns the plan, or null when the scan failed / the clip is too short.
  static Future<CadencePlan?> analyze(String path) async {
    try {
      final File f = File(path);
      if (!f.existsSync()) return null;
      final String key = '$path|${f.lengthSync()}';
      if (_plan != null && _planKey == key) return _plan;

      final MediaProbe probe = await VideoProxy.probe(path);
      final double fps = double.tryParse(VideoProxy.cfrRate(probe)) ?? 30.0;
      final Directory tmp = await getTemporaryDirectory();
      final File out = File('${tmp.path}/cadence_scan.gray');
      try {
        if (out.existsSync()) out.deleteSync();
      } catch (_) {}

      await FFmpegKit.execute('-hide_banner -y ${CpuSafe.ffArgs()}-i "$path" -an -sn -dn '
          '-vf "fps=${fps.toStringAsFixed(3)},scale=$_tw:$_th:flags=area,format=gray" -f rawvideo "${out.path}"');
      if (!out.existsSync()) return null;
      final Uint8List bytes = await out.readAsBytes();
      try {
        out.deleteSync();
      } catch (_) {}
      const int fb = _tw * _th;
      final int n = bytes.length ~/ fb;
      if (n < 4) return null;

      // ---- 1. difference of every frame to the one before ----
      final List<double> diff = List<double>.filled(n, 0.0);
      for (int i = 1; i < n; i++) {
        int acc = 0;
        final int a = i * fb, b = (i - 1) * fb;
        for (int k = 0; k < fb; k++) {
          final int d = bytes[a + k] - bytes[b + k];
          acc += d < 0 ? -d : d;
        }
        diff[i] = acc / fb;
      }
      final List<double> sorted = List<double>.of(diff.sublist(1))..sort();
      final double p90 = sorted[((sorted.length - 1) * 0.9).floor()];
      final double thr = math.max(0.35, 0.06 * p90);

      // ---- 2. unique pictures ----
      final List<int> starts = <int>[0];
      for (int i = 1; i < n; i++) {
        if (diff[i] > thr) starts.add(i);
      }
      final int dups = n - starts.length;

      // ---- 3. even re-timing inside every steady stretch (a long hold splits the stretches and keeps its own time) ----
      final int holdMax = math.max(6, (fps * 0.25).round());
      final int m = starts.length;
      final List<double> slots = List<double>.generate(m, (j) => starts[j].toDouble());
      final List<int> span = List<int>.generate(m, (j) => (j + 1 < m ? starts[j + 1] : n) - starts[j]);
      int runStart = 0;
      while (runStart < m) {
        int runEnd = runStart; // inclusive
        while (runEnd + 1 < m && span[runEnd] <= holdMax) {
          runEnd++;
        }
        // the unique picture that is held for long (span > holdMax) ends the run and keeps its own time
        final int fitEnd = (span[runEnd] > holdMax) ? runEnd - 1 : runEnd;
        for (int j = runStart; j <= fitEnd; j++) {
          final int lo = math.max(runStart, j - 6), hi = math.min(fitEnd, j + 6);
          if (hi - lo < 2) continue;
          double sx = 0, sy = 0, sxx = 0, sxy = 0;
          final int cnt = hi - lo + 1;
          for (int q = lo; q <= hi; q++) {
            final double x = (q - lo).toDouble(), y = starts[q].toDouble();
            sx += x;
            sy += y;
            sxx += x * x;
            sxy += x * y;
          }
          final double den = cnt * sxx - sx * sx;
          if (den.abs() < 1e-9) continue;
          final double slope = (cnt * sxy - sx * sy) / den;
          final double icpt = (sy - slope * sx) / cnt;
          slots[j] = icpt + slope * (j - lo).toDouble();
        }
        runStart = runEnd + 1;
      }
      for (int j = 1; j < m; j++) {
        if (slots[j] < slots[j - 1] + 0.25) slots[j] = slots[j - 1] + 0.25; // never out of order
      }

      final CadencePlan plan = CadencePlan(fps, n, starts, slots, dups);
      _plan = plan;
      _planKey = key;
      lastNote = plan.summary;
      debugPrint('FrameCadence: ${plan.summary}');
      return plan;
    } catch (e) {
      debugPrint('FrameCadence.analyze failed: $e');
      lastNote = 'duplicate frame scan failed: $e';
      return null;
    }
  }

  /// Source frame index every output frame of the LAST [decodeExpanded] call shows (index 0 = [startFrame]); the export compares neighbours to re-present an unchanged picture.
  static List<int> lastPicks = <int>[];

  /// Decodes the output frames [startFrame] .. [startFrame] + [count] - 1 (at [outFps]) of [path] as raw RGBA into [out], one frame per output frame, but every output frame holds
  /// the UNIQUE picture the [plan] assigns to it (duplicates are gone, cadence is even). [vfTail] = the crop + scale part of the filter ("crop=..,scale=w:h").
  /// Returns the number of frames written (0 = failed: the caller then decodes the normal way). Only the unique pictures are decoded; the rest is copied.
  static Future<int> decodeExpanded({
    required CadencePlan plan,
    required String path,
    required int startFrame,
    required int count,
    required double outFps,
    required String vfTail,
    required int frameBytes,
    required File out,
  }) async {
    try {
      final List<int> picks = <int>[for (int k = 0; k < count; k++) plan.sourceIndexFor(startFrame + k, outFps)];
      final List<int> uniq = picks.toSet().toList()..sort();
      final int first = uniq.first;
      final double tSeek = math.max(0.0, (first - 0.5) / plan.srcFps); // half a frame early: frame [first] is then surely the first one the decoder returns
      final String expr = uniq.map((i) => 'eq(n,${i - first})').join('+');
      final double dur = (uniq.last - first + 2) / plan.srcFps;
      final File tmp = File('${out.path}.u');
      for (final String vs in const ['-fps_mode passthrough', '-vsync 0']) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
        final String cmd = '-hide_banner -y ${CpuSafe.ffArgs()}-ss ${tSeek.toStringAsFixed(4)} -i "$path" -an -sn -dn '
            '-vf "fps=${plan.srcFps.toStringAsFixed(3)},select=\'$expr\',$vfTail" $vs -t ${dur.toStringAsFixed(4)} -f rawvideo -pix_fmt rgba "${tmp.path}"';
        await FFmpegKit.execute(cmd);
        if (tmp.existsSync() && tmp.lengthSync() == uniq.length * frameBytes) break;
      }
      if (!tmp.existsSync() || tmp.lengthSync() != uniq.length * frameBytes) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
        return 0;
      }
      // expand: output frame k gets the bytes of its unique picture
      final RandomAccessFile rin = await tmp.open(mode: FileMode.read);
      final RandomAccessFile rout = await out.open(mode: FileMode.write);
      try {
        for (int k = 0; k < count; k++) {
          await rin.setPosition(uniq.indexOf(picks[k]) * frameBytes);
          await rout.writeFrom(await rin.read(frameBytes));
        }
        await rout.flush();
      } finally {
        await rin.close();
        await rout.close();
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      lastPicks = picks;
      return count;
    } catch (e) {
      debugPrint('FrameCadence.decodeExpanded failed: $e');
      return 0;
    }
  }
}
