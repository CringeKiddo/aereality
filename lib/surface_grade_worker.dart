// =============================================================================
// AEReality / Shaderly - SurfaceGradeWorker (zero-copy hardware export)
//
// Same idea as GradeWorker / MotionWorker: the blocking FFI call runs in ONE long-lived worker isolate so the UI never waits for the GPU.
// What is different: nothing comes back. process_image_to_surface grades the RGBA frame on the GPU and presents it to the encoder's input Surface
// (see native_encoder.dart); the worker only answers with a status. Frames cross the isolate boundary as TransferableTypedData.
// If the worker cannot start, the call runs inline once, so an export never just stops.
// =============================================================================

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'vulkan_bridge.dart';

class SurfaceGradeResult {
  /// 0 = graded on the GPU and presented, 1 = presented but the simplified CPU fallback grade made the frame, negative = nothing was presented.
  final int rc;
  final int gpuStatus; // vulkanLastRenderStatus(): 0 ok, 1 GPU error, 2 device lost, 3 timeout
  final int micros;
  final String error;
  const SurfaceGradeResult(this.rc, this.gpuStatus, this.micros, this.error);
  bool get presented => rc >= 0;
}

class SurfaceGradeWorker {
  SurfaceGradeWorker._();
  static final SurfaceGradeWorker instance = SurfaceGradeWorker._();

  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  Future<void>? _starting;
  bool _broken = false;
  int _nextId = 1;
  final Map<int, Completer<SurfaceGradeResult>> _pending = {};

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
        } else if (m is List && m.length == 5) {
          final c = _pending.remove(m[0] as int);
          c?.complete(SurfaceGradeResult(m[1] as int, m[2] as int, m[3] as int, m[4] as String));
        }
      });
      _recv = recv;
      _isolate = await Isolate.spawn(_workerMain, recv.sendPort, debugName: 'ShaderlySurfaceWorker');
      _send = await ready.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('SurfaceGradeWorker: could not start ($e) - running inline');
      _broken = true;
      _send = null;
    } finally {
      _starting = null;
    }
  }

  /// Grades [rgba] (w * h * 4 bytes, the EXPORT size) and presents it to the attached encoder Surface.
  Future<SurfaceGradeResult> grade({
    required Uint8List rgba,
    required int w,
    required int h,
    required Float32List uniforms,
    Float32List? lut,
  }) async {
    await _ensureStarted();
    final send = _send;
    if (send == null || _broken) return _inlineGrade(rgba, w, h, uniforms, lut);
    final id = _nextId++;
    final c = Completer<SurfaceGradeResult>();
    _pending[id] = c;
    send.send([
      id,
      0,
      TransferableTypedData.fromList([rgba]),
      w,
      h,
      TransferableTypedData.fromList([uniforms.buffer.asUint8List(uniforms.offsetInBytes, uniforms.lengthInBytes)]),
      (lut == null || lut.isEmpty) ? null : TransferableTypedData.fromList([lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes)]),
      0,
    ]);
    return c.future.timeout(const Duration(seconds: 120), onTimeout: () {
      _pending.remove(id);
      return const SurfaceGradeResult(-200, 3, 0, 'The GPU did not answer within 120 s.');
    });
  }

  /// Presents an already finished RGBA frame (no grade), e.g. a Motion S export frame.
  Future<SurfaceGradeResult> presentRgba({required Uint8List rgba, required int w, required int h}) async {
    await _ensureStarted();
    final send = _send;
    if (send == null || _broken) {
      final rc = presentRgbaToSurface(rgba, w, h);
      return SurfaceGradeResult(rc, vulkanLastRenderStatus(), 0, rc >= 0 ? '' : vulkanLastSurfaceError());
    }
    final id = _nextId++;
    final c = Completer<SurfaceGradeResult>();
    _pending[id] = c;
    send.send([id, 2, TransferableTypedData.fromList([rgba]), w, h, null, null, 0]);
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () {
      _pending.remove(id);
      return const SurfaceGradeResult(-200, 3, 0, 'The GPU did not answer within 60 s.');
    });
  }

  /// Presents the frame that is currently in the native output buffer (used right after a Time Slice emit). [windowHandle] = ANativeWindow* from Kotlin.
  Future<SurfaceGradeResult> presentCurrent(int windowHandle) async {
    await _ensureStarted();
    final send = _send;
    if (send == null || _broken) {
      final rc = vulkanRenderToSurface(windowHandle);
      return SurfaceGradeResult(rc, vulkanLastRenderStatus(), 0, rc >= 0 ? '' : vulkanLastSurfaceError());
    }
    final id = _nextId++;
    final c = Completer<SurfaceGradeResult>();
    _pending[id] = c;
    send.send([id, 1, null, 0, 0, null, null, windowHandle]);
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () {
      _pending.remove(id);
      return const SurfaceGradeResult(-200, 3, 0, 'The GPU did not answer within 60 s.');
    });
  }

  SurfaceGradeResult _inlineGrade(Uint8List rgba, int w, int h, Float32List u, Float32List? lut) {
    final sw = Stopwatch()..start();
    final rc = processImageToSurface(rgba, w, h, u, lutTable: lut);
    return SurfaceGradeResult(rc, vulkanLastRenderStatus(), sw.elapsedMicroseconds, rc >= 0 ? '' : vulkanLastSurfaceError());
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _recv?.close();
    _isolate = null;
    _send = null;
    _recv = null;
    _broken = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const SurfaceGradeResult(-201, 3, 0, 'surface worker disposed'));
    }
    _pending.clear();
  }
}

void _workerMain(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort);
  port.listen((dynamic m) {
    final List msg = m as List;
    final int id = msg[0] as int;
    final int kind = msg[1] as int;
    try {
      final sw = Stopwatch()..start();
      int rc;
      if (kind == 1) {
        rc = vulkanRenderToSurface(msg[7] as int);
      } else if (kind == 2) {
        rc = presentRgbaToSurface((msg[2] as TransferableTypedData).materialize().asUint8List(), msg[3] as int, msg[4] as int);
      } else {
        final Uint8List rgba = (msg[2] as TransferableTypedData).materialize().asUint8List();
        final int w = msg[3] as int;
        final int h = msg[4] as int;
        final Float32List u = (msg[5] as TransferableTypedData).materialize().asFloat32List();
        final Float32List? lut = msg[6] == null ? null : (msg[6] as TransferableTypedData).materialize().asFloat32List();
        rc = processImageToSurface(rgba, w, h, u, lutTable: lut);
      }
      toMain.send([id, rc, vulkanLastRenderStatus(), sw.elapsedMicroseconds, rc >= 0 ? '' : vulkanLastSurfaceError()]);
    } catch (e) {
      toMain.send([id, -202, 1, 0, e.toString()]);
    }
  });
}
