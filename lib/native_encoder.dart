// =============================================================================
// AEReality / Shaderly - NativeEncoder (Dart side of MediaCodecEncoder.kt)
//
// Hardware H.264 / HEVC encoding WITHOUT FFmpeg. Used by the Motion S intermediate render and by the export (ExportSuite).
//
//   final s = await NativeEncoder.start(NativeEncoderConfig(...));     // Kotlin starts MediaCodec + MediaMuxer, Dart attaches the Vulkan swapchain
//   per frame, surface mode (s.surface):  SurfaceGradeWorker.instance.grade(...)  /  MotionWorker.run(toSurface: true)   -> frame goes GPU -> encoder
//   per frame, buffer mode (!s.surface):  NativeEncoder.queueNv12(nv12, frameIndex)
//   final r = await NativeEncoder.finish();                              // ends the stream, detaches Vulkan, releases the Surface, returns the MP4 path
//
// If the GPU driver cannot present to a Surface, start() silently switches to buffer mode (and says so in session.notes).
// 10-bit: asked through [tenBit]; the session tells which one was really used (session.tenBit) and why in notes.
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vulkan_bridge.dart';

/// The choices of the export sheet / Motion S menu (single source of truth).
class ExportChoices {
  static const Map<String, int> resolutions = {'720p': 720, '1080p': 1080, '2K': 1440, '4K': 2160}; // label -> short edge
  static const List<int> fps = [24, 30, 45, 60, 90];
  static const List<int> bitratesMbps = [10, 15, 25, 30, 40, 50, 80];
  static const List<String> codecs = ['hevc', 'h264'];
  static String codecLabel(String c) => c == 'hevc' ? 'HEVC' : 'H.264';
}

class NativeEncoderConfig {
  final String codec; // 'hevc' | 'h264'
  final int width;
  final int height;
  final double fps;
  final int bitrateMbps;
  final bool tenBit;
  final String outputPath;
  final bool preferSurface;
  final String? audioPath; // AAC audio of this file is copied (no re-encode)
  final int audioStartMs;
  final int audioDurationMs;

  const NativeEncoderConfig({
    this.codec = 'hevc',
    required this.width,
    required this.height,
    required this.fps,
    this.bitrateMbps = 25,
    this.tenBit = false,
    required this.outputPath,
    this.preferSurface = true,
    this.audioPath,
    this.audioStartMs = 0,
    this.audioDurationMs = 0,
  });

  Map<String, Object?> toMap({required bool surface}) => {
        'codec': codec,
        'width': width,
        'height': height,
        'fps': fps,
        'bitrateMbps': bitrateMbps,
        'tenBit': tenBit,
        'outputPath': outputPath,
        'preferSurface': surface,
        'audioPath': audioPath,
        'audioStartMs': audioStartMs,
        'audioDurationMs': audioDurationMs,
      };
}

class NativeEncoderSession {
  final bool surface; // true = frames go GPU -> Surface, false = queueNv12
  final int windowHandle;
  final bool tenBit; // what the encoder really uses
  final String encoder;
  final bool hardware;
  final List<String> notes;
  final int width;
  final int height;
  const NativeEncoderSession(this.surface, this.windowHandle, this.tenBit, this.encoder, this.hardware, this.notes, this.width, this.height);
}

class NativeEncoderResult {
  final bool ok;
  final String path;
  final int bytes;
  final int frames; // frames that really reached the file
  final String? error;
  final String audio; // 'copied' | 'none' | 'skipped: reason'
  final bool tenBit;
  final String encoder;
  final List<String> notes;
  const NativeEncoderResult(this.ok, this.path, this.bytes, this.frames, this.error, this.audio, this.tenBit, this.encoder, this.notes);
}

class NativeEncoderException implements Exception {
  final String message;
  NativeEncoderException(this.message);
  @override
  String toString() => message;
}

class NativeEncoder {
  NativeEncoder._();
  static const MethodChannel _ch = MethodChannel('com.aereality/encoder');
  static NativeEncoderSession? _active;
  static NativeEncoderSession? get active => _active;

  /// {api, surfaceBridge, hevc: {available, hardware, name, tenBit, maxWidth, maxHeight}, h264: {...}}. Empty map when the channel is missing.
  static Future<Map<String, dynamic>> capabilities() async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('capabilities');
      return r ?? <String, dynamic>{};
    } catch (e) {
      debugPrint('NativeEncoder.capabilities: $e');
      return <String, dynamic>{};
    }
  }

  /// true when this phone has an encoder (hardware preferred) for [codec] ('hevc' | 'h264').
  static Future<bool> available(String codec) async {
    final c = await capabilities();
    final m = c[codec];
    return m is Map && m['available'] == true;
  }

  static Future<Map<String, dynamic>?> _startRaw(NativeEncoderConfig c, bool surface) =>
      _ch.invokeMapMethod<String, dynamic>('start', c.toMap(surface: surface));

  /// Starts the encoder. Throws [NativeEncoderException] (readable text) when no encoder can start.
  static Future<NativeEncoderSession> start(NativeEncoderConfig c) async {
    if (_active != null) await cancel();
    final bool wantSurface = c.preferSurface && vulkanSurfaceExportAvailable();
    var r = await _startRaw(c, wantSurface);
    if (r == null || r['ok'] != true) throw NativeEncoderException((r?['error'] ?? 'The hardware encoder did not start.').toString());
    final notes = <String>[...((r['notes'] as List?) ?? const []).map((e) => e.toString())];
    bool surface = r['mode'] == 'surface';
    int handle = (r['windowHandle'] as num?)?.toInt() ?? 0;
    bool ten = r['tenBit'] == true;

    if (surface) {
      final rc = vulkanAttachSurface(handle, c.width, c.height, tenBit: ten, fps: c.fps);
      if (rc != 0) {
        notes.add('GPU surface export is not possible on this phone (${vulkanLastSurfaceError()}); using buffer mode.');
        await _ch.invokeMethod('cancel'); // releases encoder + window
        r = await _startRaw(c, false);
        if (r == null || r['ok'] != true) throw NativeEncoderException((r?['error'] ?? 'The hardware encoder did not start.').toString());
        notes.addAll(((r['notes'] as List?) ?? const []).map((e) => e.toString()));
        surface = false;
        handle = 0;
        ten = r['tenBit'] == true;
      } else if (ten && !vulkanSurfaceIsTenBit()) {
        notes.add('The GPU could not make 10-bit frames: the 10-bit encoder gets 8-bit frames.');
      }
    }
    final s = NativeEncoderSession(surface, handle, ten, (r['encoder'] ?? '').toString(), r['hardware'] == true, notes, c.width, c.height);
    _active = s;
    return s;
  }

  /// Buffer mode only: one NV12 frame (w * h * 3 / 2 bytes). false = the encoder did not accept it (stop the export).
  static Future<bool> queueNv12(Uint8List nv12, int frameIndex) async {
    try {
      return (await _ch.invokeMethod<bool>('queueNv12', {'data': nv12, 'index': frameIndex})) == true;
    } catch (e) {
      debugPrint('NativeEncoder.queueNv12: $e');
      return false;
    }
  }

  /// Ends the stream after the last frame, waits for the encoder, closes the MP4, detaches Vulkan, releases the Surface.
  /// Order matters: Kotlin finishes FIRST (queued frames are still delivered), then the swapchain goes, then the window is released.
  static Future<NativeEncoderResult> finish() async {
    final s = _active;
    Map<String, dynamic>? r;
    try {
      r = await _ch.invokeMapMethod<String, dynamic>('finish');
    } catch (e) {
      r = {'ok': false, 'error': e.toString()};
    }
    final String timing = s?.surface == true ? vulkanSurfaceTiming() : ''; // read BEFORE the swapchain is destroyed (it resets the counters)
    if (s?.surface == true) vulkanDetachSurface();
    try {
      await _ch.invokeMethod('releaseWindow');
    } catch (_) {}
    _active = null;
    r ??= {'ok': false, 'error': 'The encoder gave no answer.'};
    return NativeEncoderResult(
      r['ok'] == true,
      (r['path'] ?? '').toString(),
      (r['bytes'] as num?)?.toInt() ?? 0,
      (r['frames'] as num?)?.toInt() ?? 0,
      r['error']?.toString(),
      (r['audio'] ?? 'none').toString(),
      r['tenBit'] == true,
      (r['encoder'] ?? '').toString(),
      [...((r['notes'] as List?) ?? const []).map((e) => e.toString()), ...?s?.notes, if (timing.isNotEmpty) timing],
    );
  }

  /// Abandons the export: detaches Vulkan first, then stops the encoder and deletes the partial file.
  static Future<void> cancel() async {
    if (_active?.surface == true) vulkanDetachSurface();
    try {
      await _ch.invokeMethod('cancel');
    } catch (_) {}
    _active = null;
  }
}
