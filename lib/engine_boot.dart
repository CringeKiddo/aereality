// =============================================================================
// AEReality / Shaderly - EngineBoot + BootGate + BootScreen (batch 16)
//
// WHY: the Vulkan pipeline used to be built when a project opened (ProjectScreen._loadShader). The first grade had to wait for it, and
// when anything went wrong the preview sat on a spinner forever. Now everything is created ONCE, at app start, behind a loading
// screen, and the main menu / editor are not reachable until the engine reports Ready.
//
// Stages (each one is real work, the bar moves when it completes):
//    0 %   settings were already read in main() before the first frame
//    3 %   media engine (FFmpegKit)                         -> 22 %
//   22 %   shader asset (assets/shaders/aereality_core.spv)  -> 30 %
//   30 %   Vulkan compute pipeline (Isolate.run -> init_vulkan, blocking native call, many seconds on weak GPUs)  -> 88 %
//   88 %   grading worker isolate + one 64 x 64 test grade through the real uniform packer                        -> 98 %
//  100 %   Ready
// init_vulkan is ONE blocking native call, so inside that stage the bar creeps forward on a time curve (it never passes 86 % until
// the call returns); that is the only part of the bar that is an estimate. [ASSUMED]
//
// Failure: a missing shader / a timeout / an exception shows the error with RETRY and CONTINUE ANYWAY (the app then uses the
// CPU fallback grade that vulkan_bridge.dart already has). A failed GPU test grade is NOT an error: it is reported on the
// screen and the CPU fallback is used.
// =============================================================================

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'accent_state.dart';
import 'constants.dart';
import 'grade_worker.dart';
import 'models.dart';
import 'project_uniforms.dart';
import 'star_field.dart';
import 'ui_kit.dart';
import 'vulkan_bridge.dart';

/// Runs in a short-lived isolate (same idea as the old ProjectScreen / MotionEngine helpers). Touches only its arguments.
void _bootInitVulkan(Uint8List shaderBytes, int precisionBits) {
  initVulkan(shaderBytes, precisionBits);
}

class BootState {
  final double progress; // 0..1
  final String message;
  final bool ready;
  final String? error;
  final String? note; // non-fatal remark shown under the message (e.g. GPU fallback)
  const BootState({required this.progress, required this.message, this.ready = false, this.error, this.note});
}

class EngineBoot {
  static final ValueNotifier<BootState> state =
      ValueNotifier<BootState>(const BootState(progress: 0.0, message: 'Starting'));

  static Future<void>? _running;

  /// true when the GPU test grade at startup came back clean (status 0).
  static bool gpuOk = false;

  static bool get ready => state.value.ready;

  /// Starts the boot once (later calls return the same future). Never throws.
  static Future<void> start() => _running ??= _run();

  /// RETRY button.
  static Future<void> retry() {
    _running = null;
    return start();
  }

  /// CONTINUE ANYWAY button (after an error): opens the app on the CPU fallback.
  static void continueAnyway() {
    gpuOk = false;
    state.value = const BootState(progress: 1.0, message: 'Ready', ready: true, note: 'Started without the GPU engine');
  }

  static void _emit(double p, String msg, {String? note}) {
    final cur = state.value.progress;
    // the bar never moves backwards (retry restarts from 0 through _run)
    state.value = BootState(progress: math.max(cur, p.clamp(0.0, 1.0).toDouble()), message: msg, note: note);
  }

  static Future<Uint8List?> _loadShaderBytes() async {
    for (final path in const ['assets/shaders/aereality_core.spv', 'shaders/aereality_core.spv']) {
      try {
        final bd = await rootBundle.load(path);
        return bd.buffer.asUint8List();
      } catch (_) {}
    }
    return null;
  }

  static Future<void> _run() async {
    gpuOk = false;
    state.value = const BootState(progress: 0.0, message: 'Starting');
    Timer? creep;
    try {
      // ---- media engine ------------------------------------------------------------------------------------------
      _emit(0.03, 'Waking the media engine');
      try {
        await FFmpegKitExtended.initialize();
      } catch (e) {
        debugPrint('FFmpeg initialization error: $e'); // same as before: logged, not fatal
      }

      // ---- shader asset ------------------------------------------------------------------------------------------
      _emit(0.22, 'Loading the shader');
      final bytes = await _loadShaderBytes();
      if (bytes == null) {
        throw StateError('The shader file (assets/shaders/aereality_core.spv) is not in this build.');
      }

      // ---- Vulkan pipeline ---------------------------------------------------------------------------------------
      _emit(0.30, 'Building the GPU pipeline');
      final started = DateTime.now();
      creep = Timer.periodic(const Duration(milliseconds: 120), (_) {
        final t = DateTime.now().difference(started).inMilliseconds / 1000.0;
        // 0.30 -> 0.86 on an exponential curve (time constant ~6 s): moves, but never claims to be done
        _emit(0.30 + 0.56 * (1.0 - math.exp(-t / 6.0)), 'Building the GPU pipeline');
      });
      final prec = gEnginePrecision; // globals are per isolate: pass the value in
      try {
        await Isolate.run(() => _bootInitVulkan(bytes, prec)).timeout(const Duration(seconds: 90));
      } on TimeoutException {
        rethrow;
      } catch (e) {
        debugPrint('initVulkan isolate failed ($e) - initialising inline');
        initVulkan(bytes, prec);
      }
      creep.cancel();
      creep = null;
      vulkanSetFlareHalfRes(gFlareHalfRes);

      // ---- grading worker + test grade -----------------------------------------------------------------------------
      _emit(0.88, 'Starting the grading worker');
      String? note;
      try {
        const int tw = 64, th = 64;
        final rgba = Uint8List(tw * th * 4);
        for (int i = 0; i < rgba.length; i += 4) {
          rgba[i] = 120;
          rgba[i + 1] = 130;
          rgba[i + 2] = 140;
          rgba[i + 3] = 255;
        }
        // the same layer the New Project screen creates, packed by the same packer the editor mirrors
        final project = ProjectData(
          mediaPath: '',
          layers: [
            AdjustmentLayer(
              id: 'boot_warmup',
              name: 'Warm-up',
              opacity: 1.0,
              blendMode: LayerBlendMode.normal,
              contrast: 1.0,
              saturation: 1.0,
              brightness: 0.0,
            ),
          ],
        );
        final u = packProjectUniforms(project, tw.toDouble(), th.toDouble(), timeSeconds: 0.0, hasLut: false, lutOpacity: 1.0);
        final r = await GradeWorker.instance.grade(rgba: rgba, w: tw, h: th, uniforms: u).timeout(const Duration(seconds: 30));
        gpuOk = r.gpuStatus == 0;
        if (!gpuOk) note = 'GPU test returned status ${r.gpuStatus}: the CPU fallback will be used for grading.';
      } catch (e) {
        debugPrint('Boot test grade failed: $e');
        gpuOk = false;
        note = 'GPU test failed: the CPU fallback will be used for grading.';
      }

      _emit(0.98, 'Final checks', note: note);
      await Future<void>.delayed(const Duration(milliseconds: 250)); // let the finished bar be seen
      state.value = BootState(progress: 1.0, message: 'Ready', ready: true, note: note);
    } catch (e, st) {
      debugPrint('EngineBoot failed: $e\n$st');
      creep?.cancel();
      state.value = BootState(progress: state.value.progress, message: 'The engine could not start', error: e.toString());
    }
  }
}

// =============================================================================
// BootGate: shows the loading screen until EngineBoot says Ready, then the app. The child is not even built before that, so no
// screen (main menu, project list, editor) can start work on a half-created engine.
// =============================================================================
class BootGate extends StatefulWidget {
  final Widget child;
  const BootGate({super.key, required this.child});

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  @override
  void initState() {
    super.initState();
    EngineBoot.start(); // idempotent: main() already started it
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BootState>(
      valueListenable: EngineBoot.state,
      builder: (context, s, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: s.ready ? KeyedSubtree(key: const ValueKey('app'), child: widget.child) : BootScreen(key: const ValueKey('boot'), state: s),
        );
      },
    );
  }
}

// =============================================================================
// BootScreen: pixel staircase loading bar (steps light up with the real progress), star field behind it.
// =============================================================================
class BootScreen extends StatelessWidget {
  final BootState state;
  const BootScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gAccentListenable,
      builder: (context, _) {
        final cols = accentColors();
        final accent = cols.first;
        final hasError = state.error != null;
        return Scaffold(
          backgroundColor: kBackgroundDark,
          body: PixelStarField(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SHADERLY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 7,
                            shadows: [Shadow(color: accent.withOpacity(0.55), blurRadius: 14)],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('AEREALITY ENGINE', style: TextStyle(color: accent.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 4)),
                        const SizedBox(height: 38),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: state.progress),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          builder: (context, p, _) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 96,
                                  width: double.infinity,
                                  child: CustomPaint(painter: _StairsPainter(progress: p, colors: cols, failed: hasError)),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  hasError ? 'ERROR' : '${(p * 100).floor()}%',
                                  style: TextStyle(
                                    color: hasError ? Colors.redAccent : Colors.white,
                                    fontSize: 15,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          state.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                        ),
                        if (state.note != null) ...[
                          const SizedBox(height: 6),
                          Text(state.note!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                        if (hasError) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: ShapeDecoration(color: Colors.black.withOpacity(0.5), shape: shelfShape(cut: 6, edge: Colors.redAccent.withOpacity(0.5))),
                            child: Text(state.error!, style: const TextStyle(color: Colors.white70, fontSize: 11.5), maxLines: 6, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: EngineBoot.retry,
                                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: shelfShape(cut: 8, edge: Colors.transparent)),
                                child: const Text('RETRY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: EngineBoot.continueAnyway,
                                child: const Text('CONTINUE ANYWAY', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A rising staircase of square-edged blocks. Block i is lit when progress has passed i / N, the block being climbed glows partly, and a
/// small cursor sits on top of it. Anti-aliasing is off so the edges stay crisp (pixel look).
class _StairsPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final bool failed;
  _StairsPainter({required this.progress, required this.colors, required this.failed});

  static const int _n = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 2.0;
    final bw = (size.width - gap * (_n - 1)) / _n;
    final unit = (size.height - 8.0) / _n;
    final fill = Paint()..isAntiAlias = false;
    final cur = (progress * _n).clamp(0.0, _n.toDouble());
    for (int i = 0; i < _n; i++) {
      final h = unit * (i + 1);
      final x = i * (bw + gap);
      final rect = Rect.fromLTWH(x, size.height - h, bw, h);
      final t = _n == 1 ? 0.0 : i / (_n - 1);
      final lit = Color.lerp(colors.first, colors.last, t)!;
      if (failed) {
        fill.color = i < cur ? Colors.redAccent.withOpacity(0.55) : Colors.white.withOpacity(0.07);
      } else if (cur >= i + 1) {
        fill.color = lit;
      } else if (cur > i) {
        fill.color = lit.withOpacity(0.25 + 0.7 * (cur - i)); // the block being climbed
      } else {
        fill.color = Colors.white.withOpacity(0.07);
      }
      canvas.drawRect(rect, fill);
      // top highlight on lit blocks
      if (!failed && cur > i) {
        canvas.drawRect(Rect.fromLTWH(x, size.height - h, bw, 2), Paint()..isAntiAlias = false..color = Colors.white.withOpacity(0.55));
      }
    }
    // cursor on the step being climbed
    if (!failed && progress < 1.0) {
      final k = cur.floor().clamp(0, _n - 1);
      final h = unit * (k + 1);
      final x = k * (bw + gap);
      canvas.drawRect(Rect.fromLTWH(x + bw * 0.2, size.height - h - 7, bw * 0.6, 5), Paint()..isAntiAlias = false..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _StairsPainter old) => old.progress != progress || old.failed != failed || old.colors.first != colors.first || old.colors.last != colors.last;
}
