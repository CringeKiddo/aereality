// =============================================================================
// AEReality / Shaderly - Batch 9: Motion S slot table, defaults, frame plan and uniform packing
//
// SMEAR REWRITE: Smear is now a directional / radial ACCUMULATION smear of the current frame only (no flow, no neighbour frames), driven by
// smLength / smAngle / smRadial / smHiThresh / smDisp / sharp / smSamples. The Main (motion blur) mode was removed from the UI and the shader;
// modeMain stays as a constant so an old save that holds mode 2 still loads (it renders as Smear).
//
// UNIFORM LAYOUT: Motion S owns floats 5376..6399 of the uniform buffer (shader: motionS[1024], pass 18..21).
// Time Slice keeps 6400..7423 (reserved2[1024], unread). 7424..8191 is free headroom. Total buffer = Vfx.uboFloats = 8192.
//
// The user's settings live in a flat List<double> (indices below = the shader's MOS(i) numbers) so they can be saved as plain JSON.
// Four settings exist per mode and are copied into the shared shader slot when packed: samples (smSamples / mainSamples -> 22) and
// blur (smBlur / mainBlur -> 20). Everything else is the same number in the list and in the shader.
//   ghost frame table (96 + k = frame slot, 112 + k = signed frame offset), global transforms (128 / 136) are written by pack() and
//   by the native side, they are not settings.
// =============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'vfx_slots.dart';

class MotionS {
  static const int size = 1024;
  static const int packBase = 5376;

  /// Intermediate (processed video kept in app-support/motion_s) is encoded by the phone's HARDWARE encoder (MediaCodec, MediaCodecEncoder.kt), never by FFmpeg.
  /// Codec: 'hevc' (default: better for smears and blurs at the same bitrate) or 'h264'. Runtime value: set by the PROCESS panel "Codec" chips,
  /// saved / loaded by SettingsStore (app_settings.dart).
  static String intermediateCodec = 'hevc';

  /// Bitrate of the intermediate in Mbps. One of [bitrateOptions]. Runtime value: PROCESS panel "Bitrate" chips, saved by SettingsStore.
  static const List<int> bitrateOptions = [10, 15, 25, 30, 40, 50, 80];
  static int bitrateMbps = 25;

  static String sanitizeCodec(Object? v) => v == 'h264' ? 'h264' : 'hevc';
  static int sanitizeBitrate(Object? v) => (v is num && bitrateOptions.contains(v.toInt())) ? v.toInt() : 25;

  /// Legacy software-encoder preset (libx265 / libx264). The hardware encoder has no preset; the value is kept only so a saved accent.json still loads.
  static String x265Preset = 'veryfast';

  /// Any value that is not exactly 'fast' becomes 'veryfast' (bad file, corrupted storage, a future version's value).
  static String sanitizePreset(Object? v) => v == 'fast' ? 'fast' : 'veryfast';

  // ---- modes ----
  static const int modeSmear = 1, modeMain = 2, modeDuplicate = 3;

  // ---- header (shader slots 0..13) ----
  static const int mode = 0, opacity = 1, blend = 2, origMix = 3, protect = 4;
  // 5..13 are filled by pack() / the native side: frameCount, centerSlot, prevSlot, nextSlot, needFlow, needFwd, linearLight, cell, flowRange
  static const int frameCountSlot = 5, centerSlot = 6, prevSlot = 7, nextSlot = 8, needFlowSlot = 9, needFwdSlot = 10,
      linearLight = 11, cell = 12, flowRange = 13;

  // ---- shared motion mapping ----
  static const int intensity = 16, threshold = 17, thresholdKnee = 18, maxLen = 19, blurAmt = 20, highlightBias = 21,
      samples = 22, dilate = 23, sharp = 24;
  // per-mode copies of samples / blur
  static const int smSamples = 26, smBlur = 27, mainSamples = 42, mainBlur = 43;

  // ---- Smear ----
  // smAngle (deg, 0 = right, 90 = up; radial: 0 = zoom burst, 90 = spin), smLength (fraction of the frame diagonal; radial: of the radius * 2),
  // smFalloff (trail brightness decay), smHead (how much of the untouched picture stays), sharp (24) = streak sharpness, smSamples (26) = trailing samples.
  // smAngleLock (33) and smSpeed (36) belonged to the old flow-based smear: kept as slots so old saves load, no longer read by the shader.
  static const int smAngle = 32, smAngleLock = 33, smFalloff = 34, smHead = 35, smSpeed = 36, smLength = 37;
  // new (Smear rewrite)
  static const int smRadial = 38, smHiThresh = 39, smDisp = 40;

  // ---- Main (classic shutter) ----
  static const int shutterAngle = 48, shutterPhase = 49, shutterSoft = 50, mainBleed = 51;

  // ---- Duplicate (echo) ----
  static const int dupCount = 64, dupSpacing = 65, dupFalloff = 66, dupDirection = 67, dupOp = 68, dupTint = 69,
      dupTintAmt = 70, dupSmear = 71, dupDrift = 72, dupStartOpacity = 73;

  // ---- Glitch Edge (own optional effect) ----
  static const int gOn = 80, gAmount = 81, gBands = 82, gBandSize = 83, gSpeed = 84, gSeed = 85, gHold = 86,
      gEdgeGate = 87, gChance = 88;

  // ---- tables written by pack() ----
  static const int ghostSlots = 96, ghostOffsets = 112;
  static const int tPrev = 128, tNext = 136; // written by the native side

  static const int maxGhosts = 12;

  static List<double> defaults() {
    final f = List<double>.filled(size, 0.0);
    f[mode] = modeSmear.toDouble();
    f[opacity] = 1.0;
    f[blend] = 0.0; // 0 = default compositing, n = LayerBlendMode index + 1
    f[origMix] = 0.0;
    f[protect] = 0.0;
    f[linearLight] = 1.0;
    f[cell] = 16.0;

    // motion gate: below the threshold nothing happens, between threshold and threshold * knee it fades in
    f[intensity] = 1.0;
    f[threshold] = 0.0015; // fraction of the frame diagonal (about 3 px at 1080p)
    f[thresholdKnee] = 3.0;
    f[maxLen] = 0.12; // fraction of the diagonal, soft limit (it can never run away)
    f[highlightBias] = 0.35;
    f[dilate] = 3.0; // grid cells
    f[sharp] = 0.55;
    f[smSamples] = 32.0;
    f[smBlur] = 0.0; // blur is OFF by default in every mode (video quality)
    f[mainSamples] = 16.0;
    f[mainBlur] = 0.0;

    f[smAngle] = 0.0;
    f[smAngleLock] = 0.0;
    f[smFalloff] = 0.45;
    f[smHead] = 0.1;
    f[smSpeed] = 1.0;
    f[smLength] = 0.18;
    f[smRadial] = 0.0; // 0 linear, 1 radial (zoom / spin)
    f[smHiThresh] = 0.0; // 0 = every pixel leaves a trail; raise it so only the highlights do [ASSUMED default]
    f[smDisp] = 0.06; // RGB split along the trail, fraction of the trail length [ASSUMED default]

    f[shutterAngle] = 180.0;
    f[shutterPhase] = -90.0;
    f[shutterSoft] = 0.0;
    f[mainBleed] = 0.3;

    f[dupCount] = 6.0;
    f[dupSpacing] = 2.0;
    f[dupFalloff] = 0.35;
    f[dupDirection] = 0.0; // 0 past, 1 future, 2 both
    f[dupOp] = 0.0; // 0 screen, 1 add, 2 lighten, 3 blend, 4 over
    f[dupTint] = 0xBFE8FF.toDouble();
    f[dupTintAmt] = 0.0;
    f[dupSmear] = 0.0;
    f[dupDrift] = 0.0;
    f[dupStartOpacity] = 0.6;

    f[gOn] = 0.0;
    f[gAmount] = 0.35;
    f[gBands] = 24.0;
    f[gBandSize] = 0.035;
    f[gSpeed] = 1.0;
    f[gSeed] = 5.0;
    f[gHold] = 0.25;
    f[gEdgeGate] = 0.7;
    f[gChance] = 0.35;
    return f;
  }

  /// Fixes length / NaN so a broken save can never corrupt the GPU block.
  static List<double> sanitize(List<double>? src) {
    final d = defaults();
    if (src == null) return d;
    for (int i = 0; i < size && i < src.length; i++) {
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    d[smRadial] = d[smRadial] >= 0.5 ? 1.0 : 0.0;
    d[smHiThresh] = d[smHiThresh].clamp(0.0, 1.0).toDouble();
    d[smDisp] = d[smDisp].clamp(0.0, 0.6).toDouble();
    d[smLength] = d[smLength].clamp(0.0, 0.6).toDouble();
    return d;
  }

  /// 1 = Smear, 3 = Duplicate. The removed Main mode (2) maps to Smear.
  static int modeOf(List<double> s) {
    final m = s[mode].round().clamp(1, 3).toInt();
    return m == modeMain ? modeSmear : m;
  }

  // ---------------------------------------------------------------------------------------------------------------
  // FRAME PLAN: which frames (relative to the output frame) the effect needs, and where they sit in the upload.
  // ---------------------------------------------------------------------------------------------------------------
  static MotionPlan plan(List<double> s, {int maxSlots = 13}) {
    final m = modeOf(s);
    final glitch = s[gOn] > 0.5;
    int ghosts = 0;
    final ghostOff = <int>[];
    bool needFlow = false;
    bool needFwd = false;
    bool needPrev = false;

    if (m == modeSmear) {
      // Smear only reads the current frame: no neighbour frames, no flow passes (18..20 are skipped natively when needFlow is false)
    } else {
      ghosts = s[dupCount].round().clamp(0, maxGhosts).toInt();
      final sp = s[dupSpacing].round().clamp(1, 4).toInt();
      final dir = s[dupDirection].round().clamp(0, 2).toInt();
      for (int k = 1; k <= ghosts; k++) {
        int off;
        if (dir == 0) {
          off = -sp * k;
        } else if (dir == 1) {
          off = sp * k;
        } else {
          off = (k.isOdd ? -1 : 1) * sp * ((k + 1) ~/ 2);
        }
        ghostOff.add(off);
      }
      needFlow = s[dupDrift].abs() > 0.001 || s[dupSmear] > 0.001;
      needPrev = needFlow;
      needFwd = needFlow && ghostOff.any((o) => o > 0);
    }
    if (glitch && s[gHold] > 0.001) needPrev = true;
    if (glitch && s[gEdgeGate] > 0.02) {
      needFlow = true;
      needPrev = true;
    }

    // reduce the ghost count until the frame set fits the memory budget
    List<int> offsets;
    while (true) {
      final set = <int>{0};
      if (needPrev) set.add(-1);
      if (needFwd) set.add(1);
      for (int i = 0; i < ghostOff.length; i++) {
        set.add(ghostOff[i]);
      }
      offsets = set.toList()..sort();
      if (offsets.length <= maxSlots || ghostOff.isEmpty) break;
      ghostOff.removeLast();
    }
    final slotOf = <int, int>{for (int i = 0; i < offsets.length; i++) offsets[i]: i};
    return MotionPlan(
      offsets: offsets,
      centerSlot: slotOf[0]!,
      prevSlot: needPrev ? slotOf[-1]! : -1,
      nextSlot: (needFwd && slotOf.containsKey(1)) ? slotOf[1]! : -1,
      ghostSlots: [for (final o in ghostOff) slotOf[o]!],
      ghostOffsets: [for (final o in ghostOff) o.toDouble()],
      needFlow: needFlow,
      needFwd: needFwd,
    );
  }

  // ---------------------------------------------------------------------------------------------------------------
  // PACK: the complete uniform buffer for one Motion S frame (always Vfx.uboFloats floats).
  // ---------------------------------------------------------------------------------------------------------------
  static Float32List pack({
    required List<double> s,
    required MotionPlan plan,
    required int w,
    required int h,
    required double timeSeconds,
  }) {
    final u = Float32List(Vfx.uboFloats);
    u[0] = timeSeconds;
    u[3] = w.toDouble();
    u[4] = h.toDouble();
    final b = packBase;
    final m = modeOf(s);

    // copy the user's settings 0..127
    for (int i = 0; i < 96; i++) {
      u[b + i] = s[i];
    }
    u[b + mode] = m.toDouble();
    u[b + frameCountSlot] = plan.offsets.length.toDouble();
    u[b + centerSlot] = plan.centerSlot.toDouble();
    u[b + prevSlot] = plan.prevSlot.toDouble();
    u[b + nextSlot] = plan.nextSlot.toDouble();
    u[b + needFlowSlot] = plan.needFlow ? 1.0 : 0.0;
    u[b + needFwdSlot] = (plan.needFlow && plan.needFwd && plan.nextSlot >= 0) ? 1.0 : 0.0;
    u[b + cell] = 16.0;
    final longEdge = math.max(w, h);
    u[b + flowRange] = ((longEdge / 160.0).round() ~/ 4 * 4).clamp(4, 12).toDouble();

    // per-mode samples / blur -> shared slots
    if (m == modeSmear) {
      u[b + samples] = s[smSamples].roundToDouble().clamp(4.0, 96.0).toDouble();
      u[b + blurAmt] = 0.0; // the old perpendicular blur is gone from Smear
    } else {
      u[b + samples] = 8.0;
      u[b + blurAmt] = 0.0;
    }

    // ghost table
    for (int k = 0; k < maxGhosts + 4; k++) {
      u[b + ghostSlots + k] = -1.0;
      u[b + ghostOffsets + k] = 0.0;
    }
    for (int k = 0; k < plan.ghostSlots.length && k < maxGhosts; k++) {
      u[b + ghostSlots + k] = plan.ghostSlots[k].toDouble();
      u[b + ghostOffsets + k] = plan.ghostOffsets[k];
    }
    u[b + dupCount] = plan.ghostSlots.length.toDouble();
    return u;
  }
}

class MotionPlan {
  final List<int> offsets; // frame offsets relative to the output frame, sorted (always contains 0)
  final int centerSlot;
  final int prevSlot; // -1 = not needed
  final int nextSlot; // -1 = not needed
  final List<int> ghostSlots;
  final List<double> ghostOffsets;
  final bool needFlow;
  final bool needFwd;

  const MotionPlan({
    required this.offsets,
    required this.centerSlot,
    required this.prevSlot,
    required this.nextSlot,
    required this.ghostSlots,
    required this.ghostOffsets,
    required this.needFlow,
    required this.needFwd,
  });

  int get back => offsets.first < 0 ? -offsets.first : 0;
  int get fwd => offsets.last > 0 ? offsets.last : 0;
  int get frameCount => offsets.length;
}
