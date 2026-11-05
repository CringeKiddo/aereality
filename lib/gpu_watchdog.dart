// =============================================================================
// AEReality / Shaderly - GpuWatchdog (batch 3: engine dead-state recovery)
//
// PROBLEM: at random the app ended up in a state where no grade rendered at all and only "force stop + clear cache" helped. Causes seen in the field:
// Android killed / invalidated the Vulkan context while the app was in the background (VK_ERROR_DEVICE_LOST on every later submit), or the grade
// worker isolate sat inside a native call that never came back.
//
// WHAT THIS DOES (GradeWorker reports every frame to it):
//   * a frame that does not come back within [frameTimeout] (3 s) = failure, and a hung worker is not trusted any more -> restart at once,
//   * an exception / empty result / GPU status 2 (VK_ERROR_DEVICE_LOST, also counted natively) / a native engine that says "not ready" = failure,
//   * [maxFailures] (3) failures in a row, or ONE device-lost, ONE timeout = restart,
//   * restart = kill the worker isolates, ask the native side to rebuild the context (reset_vulkan: destroy + init on a native thread, the pipeline cache
//     file makes it a few seconds), poll until it says ready (or failed), then everything continues. [restarting] drives the "Restarting GPU..." banner.
//   * while it restarts, preview frames are returned unchanged (the UI never freezes); an export frame waits for the restart to finish.
//   * at most one restart per [cooldown] when the restart itself keeps failing, so a truly broken GPU cannot loop forever.
//
// BATCH 19 (why the "no grade until force stop" state kept coming back):
//   * A SLOW frame is not a dead frame. The old 3 s preview timeout restarted the whole GPU engine whenever a heavy-but-healthy frame (100 % preview, flare,
//     glows, Time Slice) took longer than 3 s on a mid-range phone. While it restarted, preview frames were returned unchanged and cached as "the graded
//     picture", and the next heavy frame timed out again = a restart loop. The native side already gives up on a stuck GPU after 30 s (fence timeout, status 3),
//     so the Dart side now only declares the worker hung after [frameTimeout] (45 s, export [exportFrameTimeout] 60 s), which is longer than that.
//   * ok() used to reset the failure counter on every good frame, and checkNative() ran right after it, so "the native engine is not ready" could never reach
//     [maxFailures]: a torn-down engine that stayed down was never restarted. The not-ready streak now has its own counter that ok() does not touch.
//   * restarts are rate limited (max [maxRestartsPerWindow] per [restartWindow]); beyond that the GPU is declared bad and the CPU fallback message is shown
//     instead of restarting forever.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'vulkan_bridge.dart';

class GpuWatchdog {
  GpuWatchdog._();

  static const Duration frameTimeout = Duration(seconds: 45); // batch 19 (was 3 s): longer than the native 30 s fence timeout, see the note above
  static const Duration exportFrameTimeout = Duration(seconds: 60); // batch 19 (was 25 s)
  static const int maxRestartsPerWindow = 3;
  static const Duration restartWindow = Duration(minutes: 2);
  static const int maxFailures = 3;
  static const Duration restartLimit = Duration(seconds: 150);
  static const Duration cooldown = Duration(seconds: 20);

  /// true while the GPU engine is being rebuilt (the banner in main.dart listens to it).
  static final ValueNotifier<bool> restarting = ValueNotifier<bool>(false);

  /// Text of the last restart outcome ('' = none, or the restart worked). Shown by the banner after a failed restart.
  static final ValueNotifier<String> lastProblem = ValueNotifier<String>('');

  /// Called by the workers' owners when a restart starts, so they can drop their isolates (GradeWorker / TimeSliceWorker / MotionWorker ...).
  static final List<VoidCallback> onRestart = <VoidCallback>[];

  static int _failures = 0;
  static int _notReadyStreak = 0; // batch 19: frames in a row where the native engine was down although nobody was rebuilding it
  static final List<DateTime> _restartTimes = <DateTime>[];
  static int _lostSeen = 0;
  static DateTime _lastRestart = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void>? _running;

  /// A frame went fine.
  static void ok() {
    _failures = 0;
  }

  /// A frame failed. [immediate] = restart now (timeout, device lost). Returns true when a restart was started or is running.
  static bool failed(String why, {bool immediate = false}) {
    _failures++;
    debugPrint('GpuWatchdog: failure $_failures ($why)');
    if (immediate || _failures >= maxFailures) return restart(why);
    return restarting.value;
  }

  /// Looks at the native side after a frame: a device-lost counter that moved, or an engine that is not ready although nobody is rebuilding it.
  static bool checkNative() {
    try {
      final int lost = vulkanDeviceLostCount();
      if (lost != _lostSeen) {
        _lostSeen = lost;
        return failed('VK_ERROR_DEVICE_LOST', immediate: true);
      }
      if (!restarting.value && vulkanCanReset && !isVulkanReady() && vulkanInitState() != 0) {
        _notReadyStreak++;
        if (_notReadyStreak >= maxFailures) {
          _notReadyStreak = 0;
          return failed('the native engine is not ready', immediate: true);
        }
        return false;
      }
      _notReadyStreak = 0;
    } catch (_) {}
    return false;
  }

  /// Starts the engine restart (once). Returns true when one is running after the call.
  static bool restart(String why) {
    if (_running != null) return true;
    if (!vulkanCanReset) return false; // older native lib: nothing to rebuild with (callers keep their CPU fallback)
    if (DateTime.now().difference(_lastRestart) < cooldown && lastProblem.value.isNotEmpty) return false;
    final DateTime now = DateTime.now();
    _restartTimes.removeWhere((t) => now.difference(t) > restartWindow);
    if (_restartTimes.length >= maxRestartsPerWindow) {
      lastProblem.value = 'The GPU keeps failing (${_restartTimes.length} restarts in ${restartWindow.inMinutes} min). Close the app completely and open it again; until then a simplified fallback grade is used.';
      return false;
    }
    _restartTimes.add(now);
    _lastRestart = now;
    _running = _doRestart(why).whenComplete(() => _running = null);
    return true;
  }

  static Future<void> _doRestart(String why) async {
    debugPrint('GpuWatchdog: restarting the GPU engine ($why)');
    restarting.value = true;
    lastProblem.value = '';
    _failures = 0;
    for (final cb in List<VoidCallback>.of(onRestart)) {
      try {
        cb();
      } catch (_) {}
    }
    bool started = false;
    try {
      started = resetVulkan();
    } catch (_) {}
    if (!started) {
      lastProblem.value = 'The GPU could not be restarted.';
      restarting.value = false;
      return;
    }
    final Stopwatch sw = Stopwatch()..start();
    while (sw.elapsed < restartLimit) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final int st = vulkanInitState();
      if (st == 1) {
        debugPrint('GpuWatchdog: GPU engine is back after ${sw.elapsedMilliseconds} ms');
        try {
          _lostSeen = vulkanDeviceLostCount();
        } catch (_) {}
        restarting.value = false;
        return;
      }
      if (st == -1) {
        lastProblem.value = 'The GPU restart failed: ${vulkanLastInitError()}';
        restarting.value = false;
        return;
      }
    }
    lastProblem.value = 'The GPU restart took too long.';
    restarting.value = false;
  }

  /// Export frames wait here while a restart runs (preview frames do not wait).
  static Future<void> waitReady() async {
    final f = _running;
    if (f != null) await f;
  }
}
