// =============================================================================
// AEReality / Shaderly - Batch 9: Motion S slot table, defaults, frame plan and uniform packing
//
// BATCH 2B - VELOCITY VECTOR MOTION BLUR (RSMB style): Motion S is now ONE effect. The picture is blurred along the optical-flow velocity of the footage itself
// (previous / current / next frame -> velocity map at 1/4 resolution -> directional gather), so there is NO smear where nothing moves, a spinning camera gives a swirl,
// a zoom gives a radial blur. The old static linear / radial smear (angle, radial, length) and the Duplicate (echo) mode are gone from the UI and the shader; their slot
// numbers stay reserved so an old save still loads (mode 2 / 3 render as the vector blur). Glitch Edge stays as its own optional effect.
// The motion blur runs on the RAW frames: the project grade (flares, glows, bevel ...) is applied afterwards (motion_engine.dart).
//
// BATCH 20: DENSE FLOW + BENT TRAIL. Every cell finds its own displacement (x / y moves, spins and zooms all come out of the same field), the past and the future velocity are kept
// apart and the trail bends through both (no cancelling or flipping on a camera shake), and the global fit is translation-first (no invented spin / zoom on a plain pan).
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

  // ---- Velocity vector blur (batch 2B) ----
  // vShutter: trail length in FRAMES of motion (1 = the object's displacement over one frame, 2 = twice that ...). vPhase: -1 trailing (smear behind the motion), 0 centred, +1 leading.
  // vStreak: 0 = classic averaged vector blur, 1 = lighten (light streaks, "smear" look). vRefine: 1 = Lucas-Kanade refinement on the 4 px grid (sharper vectors), 0 = coarse flow only (faster).
  // vMinSpeed: pixels / frame below which a vector counts as "no motion" (no smear at all). vVersion marks a save made with these slots (old saves keep the defaults).
  static const int vShutter = 44, vPhase = 45, vStreak = 46, vRefine = 47, vMinSpeed = 52, vVersion = 53;

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
    f[dilate] = 2.0; // grid cells (batch 19: was 3; a wide dilation copied the fastest vector far out of every edge)
    f[sharp] = 0.55;
    f[smSamples] = 32.0;
    f[smBlur] = 0.0; // blur is OFF by default in every mode (video quality)
    f[mainSamples] = 16.0;
    f[mainBlur] = 0.0;

    f[smAngle] = 0.0;
    f[smAngleLock] = 0.0;
    f[smFalloff] = 0.45;
    f[smHead] = 0.0; // batch 2B: 0 = the blur fully replaces the picture where it moves (RSMB); raise it to keep part of the sharp frame
    f[smSpeed] = 1.0;
    f[smLength] = 0.18;
    f[smRadial] = 0.0; // 0 linear, 1 radial (zoom / spin)
    f[smHiThresh] = 0.0; // 0 = every pixel leaves a trail; raise it so only the highlights do [ASSUMED default]
    f[smDisp] = 0.06; // RGB split along the trail, fraction of the trail length [ASSUMED default]
    f[vShutter] = 1.0; // batch 2B velocity vector blur [ASSUMED defaults, tuned on the reference spin / zoom clips]
    f[vPhase] = -0.6; // mostly trailing: the smear sits behind the motion
    f[vStreak] = 0.6; // batch 20: streakier by default (was 0.4): more of the lighten smear, still only where the footage moves
    f[vRefine] = 1.0;
    f[vMinSpeed] = 0.6;
    f[vVersion] = 1.0;

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
    final bool legacy = src.length <= vVersion || src[vVersion] < 0.5; // a save from before batch 2B: its new slots are 0 and must NOT override the defaults
    for (int i = 0; i < size && i < src.length; i++) {
      if (legacy && (i == vShutter || i == vPhase || i == vStreak || i == vRefine || i == vMinSpeed || i == vVersion || i == smHead)) continue;
      final v = src[i];
      if (!v.isNaN && !v.isInfinite) d[i] = v;
    }
    d[smRadial] = 0.0; // legacy slots (the static smear angle / radial / length / angle lock / speed) are not read any more
    d[smHiThresh] = d[smHiThresh].clamp(0.0, 1.0).toDouble();
    d[smDisp] = d[smDisp].clamp(0.0, 0.6).toDouble();
    d[smLength] = d[smLength].clamp(0.0, 0.6).toDouble();
    d[smSamples] = d[smSamples].clamp(4.0, 96.0).toDouble();
    d[smFalloff] = d[smFalloff].clamp(0.0, 1.0).toDouble();
    d[smHead] = d[smHead].clamp(0.0, 1.0).toDouble();
    d[sharp] = d[sharp].clamp(0.0, 1.0).toDouble();
    d[maxLen] = d[maxLen].clamp(0.0, 0.6).toDouble();
    d[vShutter] = d[vShutter].clamp(0.0, 4.0).toDouble();
    d[vPhase] = d[vPhase].clamp(-1.0, 1.0).toDouble();
    d[vStreak] = d[vStreak].clamp(0.0, 1.0).toDouble();
    d[vRefine] = d[vRefine] >= 0.5 ? 1.0 : 0.0;
    d[vMinSpeed] = d[vMinSpeed].clamp(0.0, 8.0).toDouble();
    d[vVersion] = 1.0;
    return d;
  }

  /// Batch 2B: there is only the velocity vector blur now. Old saves with the removed Main (2) / Duplicate (3) mode render as it too.
  static int modeOf(List<double> s) => modeSmear;

  // ---------------------------------------------------------------------------------------------------------------
  // FRAME PLAN: which frames (relative to the output frame) the effect needs, and where they sit in the upload.
  // ---------------------------------------------------------------------------------------------------------------
  static MotionPlan plan(List<double> s, {int maxSlots = 13, bool hasPrev = true, bool hasNext = true}) {
    // Velocity vector blur: previous + current + next frame (the flow is measured both ways and merged). The first / last frame of a clip has no previous / next frame:
    // that slot is dropped (prevSlot / nextSlot = -1) so the missing side does not pull the velocity towards zero.
    final offsets = <int>[if (hasPrev) -1, 0, if (hasNext) 1];
    return MotionPlan(
      offsets: offsets,
      centerSlot: hasPrev ? 1 : 0,
      prevSlot: hasPrev ? 0 : -1,
      nextSlot: hasNext ? (hasPrev ? 2 : 1) : -1,
      ghostSlots: const <int>[],
      ghostOffsets: const <double>[],
      needFlow: hasPrev || hasNext,
      needFwd: hasNext,
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
    u[b + flowRange] = (longEdge / 60.0).round().clamp(8, 40).toDouble(); // batch 20: search range of the dense flow (log search 16, 8, 4, 2, 1 px steps: about +-31 px per frame at 2K); was 4..12

    // the vector blur reads its sample count straight from smSamples (26); the shared slots 22 / 20 are not used any more
    u[b + samples] = s[smSamples].roundToDouble().clamp(4.0, 96.0).toDouble();
    u[b + blurAmt] = 0.0;
    // no ghost table any more (Duplicate was removed): slots 96.. stay -1 / 0
    for (int k = 0; k < maxGhosts + 4; k++) {
      u[b + ghostSlots + k] = -1.0;
      u[b + ghostOffsets + k] = 0.0;
    }
    u[b + dupCount] = 0.0;
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
