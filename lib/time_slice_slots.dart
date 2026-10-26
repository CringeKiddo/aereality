// =============================================================================
// AEReality / Shaderly - Batch 12 (step A): Time Slice settings model
//
// MODEL ONLY. Nothing here is read by the shader or packed into the uniform buffer yet (that is step C). Same pattern as class Vfx /
// class Sap (vfx_slots.dart): one flat List<double> per layer, saved in the layer JSON (key "timeSlice") so it travels through the
// existing .json preset pipeline. Old presets have no key -> defaults (effect OFF).
//
// UNIFORM LAYOUT (floats), shader member timeSlice[1024] (formerly reserved2):
//   6400 + layer * 64     per-layer settings block (this class, 64 floats per layer, 10 layers)   6400 .. 7039
//   7040 .. 7423          per-frame Time Slice state written by the wipe scheduler in step C (wipe progress etc.), 384 floats
//   7424 .. 8191          free headroom (unchanged)
//
// PER-FRAME STATE 7040.. (step C1, written by Dart, read by pass 22; shader: timeSlice[640 + i]):
//   7040 active (1 = a wipe is running)   7041 progress p 0..1 (hard on 0, hard off 1)   7042 cutPoint (info)
//   7043 n = output frame number relative to the cut frame (<0 = A shot, >=0 = B shot)    7044 R = ring half width (ring has 2R + 1 slots)
//   7045 reserved   7046 layer index whose settings block is used   7047..7423 free
// RING (step C1, enlarged in C3): R = ringHalf = 11 -> 23 frames, offsets -11 .. +11 around the cut frame (was R = 4 -> 9 frames), stored PRE-dither in the
// display buffer (see shader binding 13). ringHalf is the ONE constant: ring slot count, wipe cap and the frame decode all derive from it; the native side and
// the shader get the slot count / R at run time (ingest ringSlots argument, float 7044), so nothing else holds a literal.
// Memory (packed ring: 16 bytes per pixel for slot 0 + 23 * 8 = 200 bytes per pixel): preview 960x544 ~104 MB, 1080p ~415 MB, 2560x1440 ~737 MB (decimal MB; was 46 / 182 / 324).
//   Vfx.uboFloats stays 8192. Regions 0..6399 are not touched.
//
// WIPE MODEL (owner-corrected): intensity is FULL for the whole wipe. Only the wipe front moves (0 -> 100 % along the slice direction).
// The cut lands at 50 %. Every trigger gets exactly ONE wipe. Hard on at 0 %, hard off at 100 %. No ramp, no fade, no black.
// =============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

class TimeSlice {
  static const int size = 64;
  static const int packBase = 6400; // + layer * 64
  static const int frameStateBase = 7040; // per-frame state (step C)
  static const int regionEnd = 7424; // exclusive

  // ---- modes / enums ----
  static const int placeLayer = 0, placeGlobal = 1;
  static const int overlapOverride = 0, overlapQueue = 1, overlapSkip = 2;

  // ---- main ----
  static const int on = 0; // effect on this layer (1 = on)
  static const int placement = 1; // 0 Layer, 1 Global (default Global)
  static const int direction = 2; // slice direction, degrees 0..360 (90 = top to bottom)
  static const int sliceCount = 3; // number of time slices, >= 1
  static const int frameOffset = 4; // shifts every slice's frame number in time (frames)
  static const int interpFrames = 5; // 1 = weighted blend between the two nearest frames (smooth edges), 0 = nearest frame
  static const int feather = 6; // softness of slice edges (0..1)
  static const int mix = 7; // blend with original (1 = full effect)
  static const int opacity = 8; // per-effect opacity
  static const int blend = 9; // 0 = default compositing, n = LayerBlendMode index + 1 (same convention as Vfx / MotionS)
  static const int autoTrigger = 10; // UNUSED since C3 (no continuous look, no panel control, main.dart ignores it); kept only so old presets load. The On slot (0) is the only switch: off = Time Slice does nothing

  // ---- wipe timing ----
  static const int wipeDuration = 12; // seconds the front needs for 0 -> 100 % (0.1 .. 1.5)
  static const int overlap = 13; // 0 Override (default), 1 Queue, 2 Skip later

  // ---- cut detection (Dart side only, never sent to the GPU) ----
  static const int cutThreshold = 16; // scene score that counts as a cut (scdet scale 0..100)
  static const int cutMinGap = 17; // seconds: two cuts closer than this count as one
  static const int cutFlashReject = 18; // 1 = a spike followed by a second spike inside the window is a flash, not a cut
  static const int cutFlashWindow = 19; // seconds

  // ---- intense-motion trigger (used from step E) ----
  static const int motThreshold = 20;
  static const int motMinDuration = 21; // seconds

  // ---- wipe shape (step C) ----
  static const int cutPoint = 22; // where in the wipe (0..1) the cut lands. 0.40 = just before the middle (owner's choice, was 0.50)
  static const int bandWidth = 23; // C2: width of the moving band as a fraction of the frame along Direction (0.1 .. 1.0, default 0.35)

  // ---- ring (C2) ----
  static const int ringHalf = 11; // R: the ring holds the frames cutFrame - 11 .. cutFrame + 11 (C3: was 4)
  static const int ringSlots = 2 * ringHalf + 1; // 23 (C3: was 9)

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[on] = 0.0;
    f[placement] = placeGlobal.toDouble();
    f[direction] = 90.0;
    f[sliceCount] = 12.0;
    f[frameOffset] = 0.0;
    f[interpFrames] = 1.0;
    f[feather] = 0.25; // [ASSUMED]
    f[mix] = 1.0;
    f[opacity] = 1.0;
    f[blend] = 0.0;
    f[autoTrigger] = 1.0; // unused (see above); original default kept

    f[wipeDuration] = 0.30;
    f[overlap] = overlapOverride.toDouble();

    f[cutThreshold] = 8.0; // [ASSUMED] tuned on a real edit in the step A test
    f[cutMinGap] = 0.06;
    f[cutFlashReject] = 1.0;
    f[cutFlashWindow] = 0.12;

    f[motThreshold] = 0.5; // [ASSUMED] step E
    f[motMinDuration] = 0.15; // [ASSUMED] step E
    f[cutPoint] = 0.40;
    f[bandWidth] = 0.35;
    return f;
  }

  static double _c(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Fixes length / NaN / out-of-range values so an old preset, a broken file or a hand-edited .json can never corrupt the GPU block.
  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    d[on] = d[on] >= 0.5 ? 1.0 : 0.0;
    d[placement] = d[placement].round() == placeLayer ? placeLayer.toDouble() : placeGlobal.toDouble();
    d[direction] = (((d[direction] % 360.0) + 360.0) % 360.0).roundToDouble() % 360.0; // C3: whole degrees
    d[sliceCount] = _c(d[sliceCount].roundToDouble(), 1.0, 64.0);
    d[frameOffset] = _c(d[frameOffset].roundToDouble(), -4.0, 4.0); // C3: the panel offers -4..+4 (was -30..30; the shader clamps to the ring anyway)
    d[interpFrames] = d[interpFrames] >= 0.5 ? 1.0 : 0.0;
    d[feather] = _c(d[feather], 0.0, 1.0);
    d[mix] = _c(d[mix], 0.0, 1.0);
    d[opacity] = _c(d[opacity], 0.0, 1.0);
    d[blend] = _c(d[blend].roundToDouble(), 0.0, 64.0);
    d[autoTrigger] = d[autoTrigger] >= 0.5 ? 1.0 : 0.0;
    d[wipeDuration] = _c(d[wipeDuration], 0.1, 1.5);
    d[overlap] = _c(d[overlap].roundToDouble(), 0.0, 2.0);
    d[cutThreshold] = _c(d[cutThreshold].roundToDouble(), 1.0, 60.0); // C3: whole numbers
    d[cutMinGap] = _c(d[cutMinGap], 0.0, 1.0);
    d[cutFlashReject] = d[cutFlashReject] >= 0.5 ? 1.0 : 0.0;
    d[cutFlashWindow] = _c(d[cutFlashWindow], 0.0, 0.5);
    d[motThreshold] = _c(d[motThreshold], 0.0, 1.0);
    d[motMinDuration] = _c(d[motMinDuration], 0.0, 2.0);
    d[cutPoint] = _c(d[cutPoint], 0.2, 0.8);
    if (d[bandWidth] < 0.05) d[bandWidth] = 0.35; // presets saved before C2 have 0 here
    d[bandWidth] = _c(d[bandWidth], 0.1, 1.0);
    return d;
  }

  /// Writes every layer's settings block into the uniform buffer (6400 + layer * 64). Harmless while the effect is off: only pass 22 / 24 read it,
  /// and the host only runs those during a wipe. Used by _packMultiLayerUniforms (main.dart) and packProjectUniforms (project_uniforms.dart).
  static void packLayers(Float32List u, List<List<double>> blocks) {
    for (int l = 0; l < blocks.length && l < 10; l++) {
      final s = sanitize(blocks[l]);
      final base = packBase + l * size;
      for (int i = 0; i < size; i++) {
        u[base + i] = s[i];
      }
    }
  }

  /// Per-frame wipe state (floats 7040..7046). Only call this for a frame that is inside a wipe. 7045 (ring format) is set by the native side.
  static void packFrameState(Float32List u, {required double p, required int n, required double cutPointValue, required int layer}) {
    u[frameStateBase + 0] = 1.0;
    u[frameStateBase + 1] = p;
    u[frameStateBase + 2] = cutPointValue;
    u[frameStateBase + 3] = n.toDouble();
    u[frameStateBase + 4] = ringHalf.toDouble();
    u[frameStateBase + 6] = layer.toDouble();
  }

  static bool isOn(List<double> s) => s[on] > 0.5;
  static bool isGlobal(List<double> s) => s[placement].round() == placeGlobal;
}

// =============================================================================
// WIPE SCHEDULER (batch 12 step C2). Pure maths, no GPU, no I/O.
// Cut times (seconds, first frame of the new shot) -> for every OUTPUT frame: none, or {p, n, cut}.
//   n = frame - cutFrame (output frame number relative to the cut frame; < 0 = A shot, >= 0 = B shot)
//   p = cutPoint + n / wipeFrames  (0 .. 1: hard on at 0, hard off at 1; the cut lands at p = cutPoint)
// The wipe STARTS BEFORE the cut: start = cutFrame - cutPoint * wipeFrames. Exactly ONE wipe per trigger.
// Overlap: 0 Override (a new cut takes the wipe over), 1 Queue (the next wipe starts when the running one ends), 2 Skip later (cuts inside a wipe are ignored).
// The ring only holds R = 11 frames on each side of the cut, so the wipe length is limited: see maxWipeSeconds (the UI shows it).
// Caps with cutPoint 0.40: ~0.80 s at 24 fps, ~0.64 s at 30 fps, ~0.32 s at 60 fps (was 0.31 / 0.25 / 0.125 s with R = 4). 0.30 s at 60 fps = 18 wipe frames.
// =============================================================================
class TimeSliceWipe {
  final int cutIndex; // index in the cut list the scheduler was built from
  final int cutFrame;
  final double start; // frames (fractional)
  final double end;
  const TimeSliceWipe(this.cutIndex, this.cutFrame, this.start, this.end);
}

class TimeSliceFrame {
  final int cutIndex;
  final int cutFrame;
  final int n; // clamped to -R .. R (what the ring can hold)
  final double p;
  const TimeSliceFrame(this.cutIndex, this.cutFrame, this.n, this.p);
}

class TimeSliceScheduler {
  final double fps;
  final double wipeFrames;
  final double cutPoint;
  final List<TimeSliceWipe> wipes;
  final String key; // changes whenever the schedule changes (the host uses it to drop a stale ring)

  TimeSliceScheduler._(this.fps, this.wipeFrames, this.cutPoint, this.wipes, this.key);

  /// Longest wipe (seconds) the ring can show at this frame rate: the longer side of the wipe must fit into R frames.
  static double maxWipeSeconds(double fps, double cutPoint) =>
      (TimeSlice.ringHalf + 0.49) / (fps * math.max(cutPoint, 1.0 - cutPoint));

  /// The wipe length actually used: the setting, limited by the ring (never longer than maxWipeSeconds).
  static double effectiveWipeSeconds(List<double> s, double fps) =>
      math.min(s[TimeSlice.wipeDuration], maxWipeSeconds(fps, s[TimeSlice.cutPoint]));

  factory TimeSliceScheduler.build({required List<double> cuts, required double fps, required List<double> settings}) {
    final s = TimeSlice.sanitize(settings);
    final cp = s[TimeSlice.cutPoint];
    final wf = math.max(1.0, effectiveWipeSeconds(s, fps) * fps);
    final overlap = s[TimeSlice.overlap].round();
    final list = <TimeSliceWipe>[];
    double lastEnd = -1e18;
    for (int i = 0; i < cuts.length; i++) {
      final cutFrame = (cuts[i] * fps).round();
      double st = cutFrame - cp * wf;
      if (overlap == 1) {
        if (st < lastEnd) st = lastEnd; // Queue: wait for the running wipe
      } else if (overlap == 2) {
        if (st < lastEnd) continue; // Skip later: ignore this cut
      }
      final en = st + wf;
      list.add(TimeSliceWipe(i, cutFrame, st, en));
      lastEnd = en;
    }
    final key = '${fps.toStringAsFixed(3)}|${wf.toStringAsFixed(3)}|$cp|$overlap|${cuts.length}|${cuts.isEmpty ? 0 : cuts.first}|${cuts.isEmpty ? 0 : cuts.last}';
    return TimeSliceScheduler._(fps, wf, cp, list, key);
  }

  /// The wipe frame [frame] belongs to, or null (= plain video). Override: the latest wipe that has started wins.
  TimeSliceFrame? at(int frame) {
    for (int k = wipes.length - 1; k >= 0; k--) {
      final w = wipes[k];
      if (w.start <= frame) {
        if (frame > w.end) return null; // earlier wipes ended even earlier
        final p = ((frame - w.start) / wipeFrames).clamp(0.0, 1.0).toDouble();
        final n = (frame - w.cutFrame).clamp(-TimeSlice.ringHalf, TimeSlice.ringHalf).toInt();
        return TimeSliceFrame(w.cutIndex, w.cutFrame, n, p);
      }
    }
    return null;
  }

  /// The next wipe that has not ended yet and starts within [lead] frames (used by the preview to fill the ring early), or null.
  TimeSliceWipe? upcoming(int frame, int lead) {
    for (final w in wipes) {
      if (w.end >= frame) return (w.start - lead <= frame) ? w : null;
    }
    return null;
  }
}
