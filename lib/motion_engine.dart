// =============================================================================
// AEReality / Shaderly - MotionEngine (batch 9, Motion S)
//
//  * MotionSource       : a saved project (its grade is applied to every frame first) or a plain video file (raw, no grade).
//  * MotionEngine       : decodes the frames an effect needs (ONE ffmpeg call per window / batch, raw RGBA, like the preview and the
//                         export already do), grades them when a project is the source (GradeWorker = the existing grade path),
//                         renders Motion S on Vulkan (MotionWorker -> process_motion) and writes the finished frames.
//  * Start Process      : processAll() renders EVERY frame on Vulkan in a worker isolate (UI stays free), writes batches of raw frames,
//                         hands every finished frame to the phone's HARDWARE encoder (NativeEncoder / MediaCodecEncoder.kt: HEVC by default, H.264 optional, at
//                         MotionS.bitrateMbps) - zero-copy GPU -> Surface when the driver allows it, NV12 buffers otherwise - as ONE continuous MP4 (no parts, no join).
//                         Nothing leaves a half-processed file behind: the result only appears (renamed) when the last frame is done; cancel deletes everything.
//                         ffmpeg is used ONLY to decode source frames (no FFmpeg encode, no x265 / x264). No ffmpeg motion blur anywhere.
//  * MotionExportFeed   : renderFrameToRgba / prepareFrames callbacks for ExportSuite.showExportSheet (the live export path), reading
//                         the processed video back frame by frame.
//
// Imports nothing from the dead export files (export_service.dart, export_services.dart, LegacyExportMatrix).
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'constants.dart';
import 'cpu_safe.dart';
import 'crash_log.dart';
import 'grade_worker.dart';
import 'models.dart';
import 'motion_slots.dart';
import 'native_encoder.dart';
import 'motion_worker.dart';
import 'project_uniforms.dart';
import 'vulkan_bridge.dart';

// Same numbers as the batch 2 preview system in ProjectScreen (kInteractiveScale / kInteractiveMinLongEdge). That system is private to
// ProjectScreen, so the rule is mirrored here: playing / scrubbing = lower quality, paused = sharpen.
const double kMotionInteractiveScale = 0.5;
const int kMotionInteractiveMinLongEdge = 480;
const int kMotionPreviewMaxLongEdge = 960; // Motion S preview is deliberately not full quality (motion blur is expensive)

class MotionSource {
  final String name;
  final String mediaPath;
  final ProjectData? project; // null = plain file, no grade
  final int srcW;
  final int srcH;
  final double durationSec;
  final List<LutModel> luts;

  MotionSource({
    required this.name,
    required this.mediaPath,
    required this.project,
    required this.srcW,
    required this.srcH,
    required this.durationSec,
    required this.luts,
  });

  bool get graded => project != null;

  /// [x, y, w, h] crop of the source (project aspect ratio + pan, same rule as ProjectScreen._cropRect); whole frame for a plain file.
  List<int> get crop {
    final p = project;
    if (p == null) return [0, 0, srcW & ~1, srcH & ~1];
    final r = _aspectValue(p.aspectRatio);
    int cw, ch;
    if (srcW / srcH > r) {
      ch = srcH;
      cw = (srcH * r).round();
    } else {
      cw = srcW;
      ch = (srcW / r).round();
    }
    cw = math.max(2, math.min(srcW, cw) & ~1);
    ch = math.max(2, math.min(srcH, ch) & ~1);
    final x = ((srcW - cw) * (p.panX + 1) / 2).round().clamp(0, srcW - cw).toInt();
    final y = ((srcH - ch) * (p.panY + 1) / 2).round().clamp(0, srcH - ch).toInt();
    return [x, y, cw, ch];
  }

  static double _aspectValue(String ratio) {
    switch (ratio) {
      case '4:5':
        return 4 / 5;
      case '16:9':
        return 16 / 9;
      case '9:16':
        return 9 / 16;
      case '1:1':
        return 1.0;
      case '3:4':
        return 3 / 4;
      case '21:9':
        return 21 / 9;
      default:
        return 16 / 9;
    }
  }

  /// Opens a video to learn its size and duration. Returns null when it is not a readable video.
  static Future<MotionSource?> open({required String mediaPath, required String name, ProjectData? project}) async {
    if (mediaPath.isEmpty || !File(mediaPath).existsSync()) return null;
    final c = VideoPlayerController.file(File(mediaPath));
    try {
      await c.initialize();
      final sz = c.value.size;
      final dur = c.value.duration.inMilliseconds / 1000.0;
      if (sz.width < 16 || sz.height < 16 || dur <= 0) return null;
      final luts = project != null ? await ProjectManager.loadLuts() : <LutModel>[];
      return MotionSource(
        name: name,
        mediaPath: mediaPath,
        project: project,
        srcW: sz.width.toInt(),
        srcH: sz.height.toInt(),
        durationSec: dur,
        luts: luts,
      );
    } catch (e) {
      debugPrint('MotionSource.open failed: $e');
      return null;
    } finally {
      await c.dispose();
    }
  }
}

class MotionProcessResult {
  final String path;
  final int width;
  final int height;
  final double fps;
  final int frames;
  final double durationMs;
  MotionProcessResult(this.path, this.width, this.height, this.fps, this.frames, this.durationMs);
}

class MotionEngine {
  MotionEngine(this.src);
  final MotionSource src;

  static bool _vkReady = false;

  /// Loads the grade shader into the native engine (same assets as ProjectScreen._loadShader). Safe to call many times.
  static Future<bool> ensureVulkan() async {
    if (_vkReady) return vulkanMotionAvailable();
    for (final path in const ['assets/shaders/aereality_core.spv', 'shaders/aereality_core.spv']) {
      try {
        final bd = await rootBundle.load(path);
        // Batch 17A: no Isolate.run any more. EngineBoot already created the pipeline behind the loading screen, so in the normal case
        // init_vulkan returns 1 at once ("already initialised"). Only when the boot was continued without the GPU does this run the real
        // init, directly and blocking, and it stops at the first failing Vulkan call (vulkanLastInitError() names it).
        final bytes = bd.buffer.asUint8List();
        final bool ok = initVulkan(bytes, gEnginePrecision);
        if (!ok) {
          debugPrint('MotionEngine.ensureVulkan: init_vulkan failed: ${vulkanLastInitError()}');
          return false;
        }
        vulkanSetFlareHalfRes(gFlareHalfRes);
        _vkReady = true;
        break;
      } catch (_) {}
    }
    return _vkReady && vulkanMotionAvailable();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // SIZES
  // ---------------------------------------------------------------------------------------------------------------
  /// Preview size: capped at [kMotionPreviewMaxLongEdge]; while playing / scrubbing it drops to the interactive size (batch 2 rule).
  List<int> previewSize({required bool interactive}) {
    final c = src.crop;
    final longEdge = math.max(c[2], c[3]).toDouble();
    double sc = gPreviewScale;
    sc = math.min(sc, kMotionPreviewMaxLongEdge / longEdge);
    if (interactive) {
      sc = math.max(sc * kMotionInteractiveScale, math.min(sc, kMotionInteractiveMinLongEdge / longEdge));
    }
    sc = math.min(sc, 1.0);
    return [math.max(16, ((c[2] * sc) ~/ 2) * 2), math.max(16, ((c[3] * sc) ~/ 2) * 2)];
  }

  /// Processing size. [target]: 0 = native (long edge capped at 2560), 1080 / 720 = short edge.
  List<int> processSize(int target) {
    final c = src.crop;
    final shortEdge = math.min(c[2], c[3]).toDouble();
    final longEdge = math.max(c[2], c[3]).toDouble();
    double sc = 1.0;
    if (target > 0) sc = math.min(1.0, target / shortEdge);
    sc = math.min(sc, 2560 / longEdge);
    return [math.max(16, ((c[2] * sc) ~/ 2) * 2), math.max(16, ((c[3] * sc) ~/ 2) * 2)];
  }

  // ---------------------------------------------------------------------------------------------------------------
  // DECODE (one ffmpeg call per window / batch)
  // ---------------------------------------------------------------------------------------------------------------
  String _vf(double fps, int w, int h) {
    final c = src.crop;
    final crop = (c[0] == 0 && c[1] == 0 && c[2] == src.srcW && c[3] == src.srcH) ? '' : 'crop=${c[2]}:${c[3]}:${c[0]}:${c[1]},';
    return 'fps=$fps,${crop}scale=$w:$h';
  }

  /// Decodes [count] frames starting at [startSec] into [out] (raw RGBA). Returns how many frames really came out.
  Future<int> _decode(double startSec, double fps, int count, int w, int h, File out) async {
    try {
      if (out.existsSync()) out.deleteSync();
    } catch (_) {}
    final cmd = '-hide_banner -y ${CpuSafe.ffArgs()}-ss ${math.max(0.0, startSec).toStringAsFixed(4)} -i "${src.mediaPath}" -an -sn -dn '
        '-vf "${_vf(fps, w, h)}" -frames:v $count -f rawvideo -pix_fmt rgba "${out.path}"';
    CrashLog.note('Motion S decode START: ffmpeg $cmd');
    await FFmpegKit.execute(cmd);
    CrashLog.note('Motion S decode RETURNED');
    if (!out.existsSync()) return 0;
    return out.lengthSync() ~/ (w * h * 4);
  }

  // ---------------------------------------------------------------------------------------------------------------
  // GRADE (project source only): the existing grade path, one frame at a time
  // ---------------------------------------------------------------------------------------------------------------
  Float32List? _lutTable;
  double _lutOpacity = 1.0;
  bool _lutResolved = false;

  void _resolveLut() {
    if (_lutResolved) return;
    _lutResolved = true;
    final p = src.project;
    if (p == null) return;
    AdjustmentLayer owner = p.currentLayer;
    for (final l in p.layers) {
      if (l.activeLutId != null && src.luts.any((x) => x.id == l.activeLutId)) {
        owner = l;
        break;
      }
    }
    final id = owner.activeLutId;
    if (id != null) {
      final m = src.luts.where((l) => l.id == id);
      if (m.isNotEmpty) _lutTable = m.first.table;
    }
    _lutOpacity = owner.lutOpacity;
  }

  Future<Uint8List> _grade(Uint8List raw, int w, int h, double timeSeconds) async {
    final p = src.project;
    if (p == null) return raw;
    _resolveLut();
    final u = packProjectUniforms(p, w.toDouble(), h.toDouble(), timeSeconds: timeSeconds, hasLut: _lutTable != null, lutOpacity: _lutOpacity);
    u[0] = timeSeconds;
    final res = await GradeWorker.instance.grade(rgba: raw, w: w, h: h, uniforms: u, lut: _lutTable);
    return res.rgba;
  }

  // small caches (preview): graded frames by index, so scrubbing back and forth does not regrade
  final Map<String, Uint8List> _gradeCache = {};

  // ---------------------------------------------------------------------------------------------------------------
  // PREVIEW
  // ---------------------------------------------------------------------------------------------------------------
  /// One Motion S preview frame at [tSec]. Returns RGBA (w * h * 4) or null when nothing could be decoded.
  Future<Uint8List?> renderPreview({
    required double tSec,
    required List<double> settings,
    required double fps,
    required int w,
    required int h,
    bool original = false,
  }) async {
    final plan = MotionS.plan(settings);
    final offsets = original ? <int>[0] : plan.offsets; // "original" = the (graded) frame itself, no Motion S
    final total = math.max(1, (src.durationSec * fps).floor());
    final c = (tSec * fps).round().clamp(0, total - 1).toInt();

    final first = offsets.first;
    final last = offsets.last;
    final startIdx = math.max(0, c + first);
    final count = (c + last) - startIdx + 1;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/motion_s_preview_window.rgba');
    final fb = w * h * 4;
    final got = await _decode(startIdx / fps, fps, count, w, h, file);
    if (got < 1) return null;
    final raf = await file.open(mode: FileMode.read);
    final slotFrames = <Uint8List>[];
    try {
      for (final off in offsets) {
        int i = (c + off) - startIdx;
        if (i < 0) i = 0;
        if (i >= got) i = got - 1;
        final absIdx = math.max(0, c + off);
        final key = '$absIdx|$w|$h';
        Uint8List? fr = src.graded ? _gradeCache[key] : null;
        if (fr == null) {
          await raf.setPosition(i * fb);
          final raw = await raf.read(fb);
          if (raw.length != fb) return null;
          fr = src.graded ? await _grade(raw, w, h, absIdx / fps) : raw;
          if (src.graded) {
            if (_gradeCache.length > 40) _gradeCache.remove(_gradeCache.keys.first);
            _gradeCache[key] = fr;
          }
        }
        slotFrames.add(fr);
      }
    } finally {
      await raf.close();
      try {
        file.deleteSync();
      } catch (_) {}
    }
    if (original) return slotFrames[0];

    final u = MotionS.pack(s: settings, plan: plan, w: w, h: h, timeSeconds: c / fps);
    final res = await MotionWorker.instance.run(frames: slotFrames, w: w, h: h, center: plan.centerSlot, uniforms: u);
    return res.rgba;
  }

  // ---------------------------------------------------------------------------------------------------------------
  // START PROCESS: every frame, on Vulkan, in the worker isolate
  // ---------------------------------------------------------------------------------------------------------------
  /// Returns the processed video (hardware HEVC / H.264 in MP4, see MotionS.intermediateCodec / bitrateMbps) or null when cancelled / failed ([lastError] says why).
  String? lastError;

  Future<MotionProcessResult?> processAll({
    required List<double> settings,
    required double fps,
    required int w,
    required int h,
    required void Function(double progress, String status) onProgress,
    required bool Function() cancelled,
  }) async {
    lastError = null;
    final plan = MotionS.plan(settings);
    final total = math.max(1, (src.durationSec * fps).round());
    final fb = w * h * 4;
    final back = plan.back;
    final fwd = plan.fwd;
    final base = await getApplicationSupportDirectory();
    final outDir = Directory('${base.path}/motion_s');
    final work = Directory('${(await getTemporaryDirectory()).path}/motion_s_work');
    try {
      if (work.existsSync()) work.deleteSync(recursive: true);
      work.createSync(recursive: true);
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
    } catch (e) {
      lastError = 'Could not create the work folder: $e';
      return null;
    }

    // batch size from a ~190 MB source window
    final batch = (((190 * 1024 * 1024) ~/ fb) - back - fwd).clamp(4, 24).toInt();
    final rawCache = <int, Uint8List>{};
    final gradedCache = <int, Uint8List>{};
    final started = DateTime.now();
    final tmpOut = File('${work.path}/final.mp4');
    CrashLog.begin('Motion S process', {'frames': total, 'size': '${w}x$h', 'fps': fps, 'mode': MotionS.modeOf(settings), 'graded': src.graded, 'codec': MotionS.intermediateCodec, 'mbps': MotionS.bitrateMbps});
    vulkanSetBandBudgetMs(24); // shorter GPU submits: the phone UI stays fluid while this runs
    int done = 0;
    bool failed = false;
    bool encoderOpen = false;
    NativeEncoderSession? session;
    try {
      // Decoding still uses FFmpeg's colour conversion (swscale): run the existing CPU-safety probe first (once per level).
      try {
        await CpuSafe.verifyConversion(tenBit: false);
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
        return null;
      }

      // ENCODING: the phone's hardware encoder (MediaCodec) - no x265 / x264 / FFmpeg encode at all. One continuous encode of the whole video:
      // no parts, no concat join. HEVC by default (best for smears / blurs); if this phone has no HEVC encoder it silently uses H.264.
      String codec = MotionS.sanitizeCodec(MotionS.intermediateCodec);
      for (int attempt = 0; attempt < 2 && session == null; attempt++) {
        try {
          session = await NativeEncoder.start(NativeEncoderConfig(
            codec: codec,
            width: w,
            height: h,
            fps: fps,
            bitrateMbps: MotionS.sanitizeBitrate(MotionS.bitrateMbps),
            outputPath: tmpOut.path,
            preferSurface: vulkanMotionSurfaceAvailable(),
          ));
        } catch (e) {
          CrashLog.note('Motion S encoder start ($codec) failed: $e');
          if (codec == 'hevc') {
            codec = 'h264';
          } else {
            lastError = 'The phone\'s hardware video encoder could not start: ${e.toString().replaceFirst('Exception: ', '')}';
            return null;
          }
        }
      }
      if (session == null) {
        lastError = 'The phone\'s hardware video encoder could not start.';
        return null;
      }
      encoderOpen = true;
      final bool viaSurface = session.surface;
      CrashLog.note('Motion S encoder: ${session.encoder} ($codec, ${viaSurface ? 'zero-copy surface' : 'NV12 buffers'}, hardware=${session.hardware})');

      for (int b0 = 0; b0 < total && !failed; b0 += batch) {
        if (cancelled()) break;
        final b1 = math.min(total, b0 + batch);
        final s0 = math.max(0, b0 - back);
        final e0 = math.min(total - 1, (b1 - 1) + fwd);
        final srcFile = File('${work.path}/src_batch.rgba');
        final got = await _decode(s0 / fps, fps, e0 - s0 + 1, w, h, srcFile);
        if (got < 1) {
          lastError = 'The source video could not be decoded at ${(s0 / fps).toStringAsFixed(2)} s.';
          failed = true;
          break;
        }
        final raf = await srcFile.open(mode: FileMode.read);
        try {
          Future<Uint8List> rawAt(int idx) async {
            idx = idx.clamp(0, total - 1).toInt();
            final hit = rawCache[idx];
            if (hit != null) return hit;
            int i = idx - s0;
            if (i < 0) i = 0;
            if (i >= got) i = got - 1;
            await raf.setPosition(i * fb);
            final bytes = await raf.read(fb);
            if (bytes.length != fb) throw Exception('short read in the source batch');
            rawCache[idx] = bytes;
            return bytes;
          }

          Future<Uint8List> frameAt(int idx) async {
            idx = idx.clamp(0, total - 1).toInt();
            if (!src.graded) return rawAt(idx);
            final hit = gradedCache[idx];
            if (hit != null) return hit;
            final g = await _grade(await rawAt(idx), w, h, idx / fps);
            gradedCache[idx] = g;
            return g;
          }

          for (int i = b0; i < b1; i++) {
            if (cancelled()) break;
            final slotFrames = <Uint8List>[];
            for (final off in plan.offsets) {
              slotFrames.add(await frameAt(i + off));
            }
            final u = MotionS.pack(s: settings, plan: plan, w: w, h: h, timeSeconds: i / fps);
            CrashLog.note('Motion S frame ${i + 1}/$total render START');
            final res = await MotionWorker.instance.run(frames: slotFrames, w: w, h: h, center: plan.centerSlot, uniforms: u, toSurface: viaSurface);
            CrashLog.note('Motion S frame ${i + 1}/$total RETURNED status=${res.gpuStatus} native ${res.micros ~/ 1000} ms');
            if (res.gpuStatus == 2 || res.gpuStatus == 3) {
              lastError = 'The GPU stopped answering (status ${res.gpuStatus}). Try a lower processing size or fewer samples.';
              failed = true;
              break;
            }
            if (viaSurface) {
              if (res.gpuStatus != 0) {
                lastError = 'A frame could not be handed to the video encoder (${vulkanLastSurfaceError().isEmpty ? 'GPU status ${res.gpuStatus}' : vulkanLastSurfaceError()}).';
                failed = true;
                break;
              }
            } else {
              final nv12 = rgbaToNv12(res.rgba, w, h);
              if (nv12 == null || !await NativeEncoder.queueNv12(nv12, i)) {
                lastError = 'The video encoder did not accept frame ${i + 1}.';
                failed = true;
                break;
              }
            }
            done++;
            // keep only the frames the next outputs can still need
            rawCache.removeWhere((k, _) => k < i + 1 - back - 1);
            gradedCache.removeWhere((k, _) => k < i + 1 - back - 1);
            final p = done / total;
            final elapsed = DateTime.now().difference(started).inSeconds;
            final eta = done > 2 ? ((elapsed / done) * (total - done)).round() : -1;
            onProgress(p * 0.98, 'Motion S ${i + 1}/$total${eta >= 0 ? '  -  about ${_fmtSec(eta)} left' : ''}');
          }
        } finally {
          await raf.close();
          try {
            srcFile.deleteSync();
          } catch (_) {}
        }
        if (failed || cancelled()) break;
      }

      if (failed || cancelled() || done < total) {
        if (!failed && cancelled()) lastError = null;
        return null; // the encoder is cancelled in finally
      }

      onProgress(0.99, 'Finishing the processed video...');
      final enc = await NativeEncoder.finish();
      encoderOpen = false;
      if (!enc.ok || !tmpOut.existsSync() || tmpOut.lengthSync() < 1024) {
        lastError = 'Could not finish the processed video${enc.error == null ? '' : ': ${enc.error}'}.';
        return null;
      }
      if (enc.frames < total) {
        CrashLog.note('Motion S: encoder wrote ${enc.frames} of $total frames');
        if (enc.frames < total * 0.95) {
          lastError = 'The video encoder dropped too many frames (${enc.frames} of $total).';
          return null;
        }
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final finalFile = File('${outDir.path}/motion_s_$stamp.mp4');
      try {
        tmpOut.renameSync(finalFile.path);
      } catch (_) {
        tmpOut.copySync(finalFile.path);
      }
      onProgress(1.0, 'Motion S processing finished');
      return MotionProcessResult(finalFile.path, w, h, fps, total, total / fps * 1000.0);
    } catch (e, st) {
      CrashLog.error(e, st);
      lastError = 'Processing stopped: $e';
      return null;
    } finally {
      if (encoderOpen) {
        try {
          await NativeEncoder.cancel();
        } catch (_) {}
      }
      vulkanSetBandBudgetMs(40);
      CrashLog.end(lastError == null ? 'finished' : 'stopped: $lastError');
      try {
        if (work.existsSync()) work.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static String _fmtSec(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
  }

  void dispose() {
    _gradeCache.clear();
  }
}

// =============================================================================
// MotionExportFeed: renderFrameToRgba / prepareFrames for ExportSuite.showExportSheet (the LIVE export path).
// Mirrors ProjectScreen._prepareExportFrames / _readBatchFrame / _renderFrameForExport, but the source is the processed video, and
// no grade is applied (the frames already contain it).
// =============================================================================
class MotionExportFeed {
  MotionExportFeed({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;

  File? _batchFile;
  RandomAccessFile? _raf;
  double _startMs = 0;
  double _fps = 30;
  int _requested = 0;
  int _frames = 0;
  int _frameBytes = 0;
  Uint8List? _last;

  Future<void> release() async {
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
    try {
      if (_batchFile != null && _batchFile!.existsSync()) _batchFile!.deleteSync();
    } catch (_) {}
    _batchFile = null;
    _requested = 0;
    _frames = 0;
  }

  /// prepareFrames callback. frameCount == 0 releases the batch.
  Future<void> prepare(double startMs, int frameCount, double fps) async {
    await release();
    if (frameCount <= 0) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/motion_s_export_batch.rgba');
    final fb = width * height * 4;
    final cmd = '-hide_banner -y ${CpuSafe.ffArgs()}-ss ${(startMs / 1000.0).toStringAsFixed(4)} -i "$path" -an -sn -dn '
        '-vf "fps=$fps,scale=$width:$height" -frames:v $frameCount -f rawvideo -pix_fmt rgba "${file.path}"';
    CrashLog.note('  Motion S export decode: ffmpeg $cmd');
    await FFmpegKit.execute(cmd);
    if (!file.existsSync() || file.lengthSync() < fb) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      return;
    }
    _batchFile = file;
    _frameBytes = fb;
    _frames = file.lengthSync() ~/ fb;
    _requested = frameCount;
    _startMs = startMs;
    _fps = fps;
    _raf = await file.open(mode: FileMode.read);
  }

  /// renderFrameToRgba callback.
  Future<Uint8List> render(double timestampMs) async {
    final fb = width * height * 4;
    final raf = _raf;
    if (raf != null && _frames > 0 && _frameBytes == fb) {
      int idx = ((timestampMs - _startMs) * _fps / 1000.0).round();
      if (idx >= 0 && idx < _requested) {
        if (idx >= _frames) idx = _frames - 1;
        await raf.setPosition(idx * fb);
        final bytes = await raf.read(fb);
        if (bytes.length == fb) {
          _last = bytes;
          return bytes;
        }
      }
    }
    // slow path: one ffmpeg call for this frame
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/motion_s_export_frame.rgba');
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await FFmpegKit.execute('-hide_banner -y ${CpuSafe.ffArgs()}-ss ${(timestampMs / 1000.0).toStringAsFixed(3)} -i "$path" -frames:v 1 '
        '-vf "scale=$width:$height" -f rawvideo -pix_fmt rgba "${f.path}"');
    Uint8List? out;
    if (f.existsSync() && f.lengthSync() == fb) out = await f.readAsBytes();
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    out ??= _last;
    if (out == null || out.length != fb) throw Exception('Could not read the processed frame at ${timestampMs.toStringAsFixed(0)} ms');
    _last = out;
    return out;
  }
}
