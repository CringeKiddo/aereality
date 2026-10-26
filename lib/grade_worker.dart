// =============================================================================
// AEReality / Shaderly - GradeWorker
//
// WHY: processImage() is a blocking FFI call (CPU copies + GPU submits + fence waits). Called from the UI isolate it
// freezes everything for as long as the GPU takes: sliders cannot move, taps are not handled, and with heavy effects
// (flares) the freeze is long enough for Android to show "app isn't responding".
//
// WHAT: one long-lived worker isolate owns all processImage() calls. The native Vulkan state (gVk in
// vulkan_processor.cpp) is process-global and mutex-protected, so initVulkan() stays on the main isolate and the
// worker only calls process_image. Pixel buffers cross the isolate boundary as TransferableTypedData (one memcpy,
// no serialisation).
//
// Only the 8-bit path (processImage) is wrapped: that is the only grade path main.dart / export_suite.dart use.
//
// If the worker cannot start or dies, grade() falls back to the old inline call so the app never loses its preview.
// =============================================================================

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'vulkan_bridge.dart';

// ===== TEMPORARY DEBUG (batch 12 step B regression test) - REMOVE AFTER THE TEST =====
// true = every graded frame prints one line "GRADEHASH n=.. t=.. WxH fnv1a=........" (FNV-1a 32-bit of the output RGBA bytes).
// Build once from the OLD code and once from the NEW code, run the same fixed export / the same paused frames, compare the lists.
const bool kGradeHashDebug = false;
int _gradeHashCounter = 0;
int _fnv1a32(Uint8List b) {
  int h = 0x811C9DC5;
  for (int i = 0; i < b.length; i++) {
    h ^= b[i];
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}
// ===== END TEMPORARY DEBUG =====

class GradeResult {
  final Uint8List rgba;
  final int gpuStatus; // 0 ok, 1 GPU error (CPU fallback used), 2 device lost, 3 timeout
  final int micros; // wall time of the native call inside the worker
  GradeResult(this.rgba, this.gpuStatus, this.micros);
}

class GradeWorker {
  GradeWorker._();
  static final GradeWorker instance = GradeWorker._();

  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  Future<void>? _starting;
  bool _broken = false;
  int _nextId = 1;
  final Map<int, Completer<GradeResult>> _pending = {};

  Future<void> _ensureStarted() {
    if (_send != null || _broken) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      final recv = ReceivePort();
      final ready = Completer<SendPort>();
      recv.listen((dynamic m) {
        if (m is SendPort) {
          if (!ready.isCompleted) ready.complete(m);
        } else if (m is List && m.length == 4) {
          final c = _pending.remove(m[0] as int);
          if (c == null) return;
          final ttd = m[1] as TransferableTypedData?;
          if (ttd == null) {
            c.completeError(StateError('grade worker error: ${m[3]}'));
          } else {
            c.complete(GradeResult(ttd.materialize().asUint8List(), m[2] as int, m[3] as int));
          }
        }
      });
      _recv = recv;
      _isolate = await Isolate.spawn(_workerMain, recv.sendPort, debugName: 'ShaderlyGradeWorker');
      _send = await ready.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('GradeWorker: could not start ($e) - falling back to inline grading');
      _broken = true;
      _send = null;
    } finally {
      _starting = null;
    }
  }

  /// Grades one frame. [rgba] is w*h*4 bytes. Never blocks the calling isolate while the GPU works.
  Future<GradeResult> grade({
    required Uint8List rgba,
    required int w,
    required int h,
    required Float32List uniforms,
    Float32List? lut,
  }) async {
    final r = await _gradeCore(rgba: rgba, w: w, h: h, uniforms: uniforms, lut: lut);
    if (kGradeHashDebug) {
      debugPrint('GRADEHASH n=${_gradeHashCounter++} t=${uniforms[0].toStringAsFixed(4)} ${w}x$h fnv1a=${_fnv1a32(r.rgba).toRadixString(16).padLeft(8, '0')}');
      debugPrint('P23COUNT ${vulkanPass23Count()}'); // C2 debug (own line so the GRADEHASH diff stays clean): +1 per graded frame
    }
    return r;
  }

  Future<GradeResult> _gradeCore({
    required Uint8List rgba,
    required int w,
    required int h,
    required Float32List uniforms,
    Float32List? lut,
  }) async {
    await _ensureStarted();
    final send = _send;
    if (send == null || _broken) return _inline(rgba, w, h, uniforms, lut);

    final id = _nextId++;
    final c = Completer<GradeResult>();
    _pending[id] = c;
    send.send([
      id,
      TransferableTypedData.fromList([rgba]),
      w,
      h,
      TransferableTypedData.fromList([uniforms.buffer.asUint8List(uniforms.offsetInBytes, uniforms.lengthInBytes)]),
      lut == null ? null : TransferableTypedData.fromList([lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes)]),
    ]);
    try {
      return await c.future;
    } catch (e) {
      // Worker failed for this frame: do it inline once so the caller still gets a picture.
      debugPrint('GradeWorker: $e - inline fallback');
      _pending.remove(id);
      return _inline(rgba, w, h, uniforms, lut);
    }
  }

  GradeResult _inline(Uint8List rgba, int w, int h, Float32List u, Float32List? lut) {
    final sw = Stopwatch()..start();
    final out = processImage(rgba, w, h, w, h, u, lutTable: lut);
    return GradeResult(out, vulkanLastRenderStatus(), sw.elapsedMicroseconds);
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _recv?.close();
    _isolate = null;
    _send = null;
    _recv = null;
    _broken = false; // C2: same as MotionWorker.dispose(), so a later start can try again
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('grade worker disposed'));
    }
    _pending.clear();
  }
}

// ---------------------------------------------------------------------------
// Worker isolate entry point
// ---------------------------------------------------------------------------
void _workerMain(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort);
  port.listen((dynamic m) {
    final List msg = m as List;
    final int id = msg[0] as int;
    try {
      final Uint8List rgba = (msg[1] as TransferableTypedData).materialize().asUint8List();
      final int w = msg[2] as int;
      final int h = msg[3] as int;
      final Float32List uniforms = (msg[4] as TransferableTypedData).materialize().asFloat32List();
      final Float32List? lut = msg[5] == null ? null : (msg[5] as TransferableTypedData).materialize().asFloat32List();

      final sw = Stopwatch()..start();
      final out = processImage(rgba, w, h, w, h, uniforms, lutTable: lut);
      final status = vulkanLastRenderStatus();
      toMain.send([id, TransferableTypedData.fromList([out]), status, sw.elapsedMicroseconds]);
    } catch (e) {
      toMain.send([id, null, -1, e.toString()]);
    }
  });
}

// =============================================================================
// TimeSliceWorker (batch 12 step C2)
// Same pattern as GradeWorker: ingest (grade ONE frame into a ring slot), emit (pass 22 + pass 23) and release run in ONE long-lived
// isolate so the UI isolate never waits for the GPU. Native state is process-global and mutex-protected. If the worker cannot start,
// the calls fall back to inline (blocking) calls so the effect still works.
// Message: [id, op, ...]  op 0 = ingest, 1 = emit, 2 = release.  Reply: [id, status, TransferableTypedData?, error]  (status 0 = ok, -1 = failed).
// =============================================================================
class TimeSliceWorker {
  TimeSliceWorker._();
  static final TimeSliceWorker instance = TimeSliceWorker._();

  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  Future<void>? _starting;
  bool _broken = false;
  int _nextId = 1;
  final Map<int, Completer<List<dynamic>>> _pending = {};

  Future<void> _ensureStarted() {
    if (_send != null || _broken) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      final recv = ReceivePort();
      final ready = Completer<SendPort>();
      recv.listen((dynamic m) {
        if (m is SendPort) {
          if (!ready.isCompleted) ready.complete(m);
        } else if (m is List && m.length == 4) {
          final c = _pending.remove(m[0] as int);
          if (c != null && !c.isCompleted) c.complete(m);
        }
      });
      _recv = recv;
      _isolate = await Isolate.spawn(_tsWorkerMain, recv.sendPort, debugName: 'ShaderlyTimeSliceWorker');
      _send = await ready.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('TimeSliceWorker: could not start ($e) - falling back to inline calls');
      _broken = true;
      _send = null;
    } finally {
      _starting = null;
    }
  }

  Future<List<dynamic>?> _call(List<dynamic> msg) async {
    await _ensureStarted();
    final send = _send;
    if (send == null || _broken) return null;
    final id = _nextId++;
    final c = Completer<List<dynamic>>();
    _pending[id] = c;
    send.send([id, ...msg]);
    try {
      return await c.future;
    } catch (_) {
      _pending.remove(id);
      return null;
    }
  }

  /// Grades one 8-bit RGBA frame (full grade, no dither) into ring slot [slot]. Returns false when the native side could not do it.
  Future<bool> ingest({required Uint8List rgba, required int w, required int h, required Float32List uniforms, required int slot, required int ringSlots, Float32List? lut}) async {
    final r = await _call([
      0,
      TransferableTypedData.fromList([rgba]),
      w,
      h,
      TransferableTypedData.fromList([uniforms.buffer.asUint8List(uniforms.offsetInBytes, uniforms.lengthInBytes)]),
      slot,
      ringSlots,
      lut == null ? null : TransferableTypedData.fromList([lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes)]),
    ]);
    if (r == null) return timeSliceIngest(rgba, w, h, uniforms, slot, ringSlots, lutTable: lut); // inline fallback
    return r[1] == 0;
  }

  /// Pass 22 + pass 23 on the filled ring. Returns the 8-bit RGBA frame, or null (ring not valid / GPU error): the caller then shows the plain frame.
  Future<Uint8List?> emit({required int w, required int h, required Float32List uniforms}) async {
    final r = await _call([
      1,
      w,
      h,
      TransferableTypedData.fromList([uniforms.buffer.asUint8List(uniforms.offsetInBytes, uniforms.lengthInBytes)]),
    ]);
    if (r == null) return timeSliceEmit(w, h, uniforms); // inline fallback
    final ttd = r[2] as TransferableTypedData?;
    if (r[1] != 0 || ttd == null) return null;
    return ttd.materialize().asUint8List();
  }

  /// Frees the ring memory (display buffer back to one frame).
  Future<void> release() async {
    final r = await _call([2]);
    if (r == null) timeSliceRelease();
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _recv?.close();
    _isolate = null;
    _send = null;
    _recv = null;
    _broken = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete([0, -1, null, 'disposed']);
    }
    _pending.clear();
  }
}

void _tsWorkerMain(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort);
  port.listen((dynamic m) {
    final List msg = m as List;
    final int id = msg[0] as int;
    try {
      final int op = msg[1] as int;
      if (op == 0) {
        final Uint8List rgba = (msg[2] as TransferableTypedData).materialize().asUint8List();
        final int w = msg[3] as int;
        final int h = msg[4] as int;
        final Float32List uniforms = (msg[5] as TransferableTypedData).materialize().asFloat32List();
        final int slot = msg[6] as int;
        final int ringSlots = msg[7] as int;
        final Float32List? lut = msg[8] == null ? null : (msg[8] as TransferableTypedData).materialize().asFloat32List();
        final ok = timeSliceIngest(rgba, w, h, uniforms, slot, ringSlots, lutTable: lut);
        toMain.send([id, ok ? 0 : -1, null, '']);
      } else if (op == 1) {
        final int w = msg[2] as int;
        final int h = msg[3] as int;
        final Float32List uniforms = (msg[4] as TransferableTypedData).materialize().asFloat32List();
        final out = timeSliceEmit(w, h, uniforms);
        toMain.send([id, out == null ? -1 : 0, out == null ? null : TransferableTypedData.fromList([out]), '']);
      } else {
        timeSliceRelease();
        toMain.send([id, 0, null, '']);
      }
    } catch (e) {
      toMain.send([id, -1, null, e.toString()]);
    }
  });
}

