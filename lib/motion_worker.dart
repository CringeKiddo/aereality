// =============================================================================
// AEReality / Shaderly - MotionWorker (batch 9)
//
// Same idea as GradeWorker (batch 2): processMotion() is a blocking FFI call (CPU motion estimate + GPU submits + fence waits), so it
// runs in ONE long-lived worker isolate and the UI isolate never waits for it. The native Vulkan state is process-global and
// mutex-protected, so initVulkan() stays on the main isolate. Frames cross the isolate boundary as TransferableTypedData.
// If the worker cannot start or dies, run() falls back to an inline call once, so a preview never just disappears.
// =============================================================================

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'vulkan_bridge.dart';

class MotionResult {
  final Uint8List rgba;
  final int gpuStatus; // 0 ok, 1 GPU error (centre frame returned), 2 device lost, 3 timeout
  final int micros;
  MotionResult(this.rgba, this.gpuStatus, this.micros);
}

class MotionWorker {
  MotionWorker._();
  static final MotionWorker instance = MotionWorker._();

  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _recv;
  Future<void>? _starting;
  bool _broken = false;
  int _nextId = 1;
  final Map<int, Completer<MotionResult>> _pending = {};

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
            c.completeError(StateError('motion worker error: ${m[3]}'));
          } else {
            c.complete(MotionResult(ttd.materialize().asUint8List(), m[2] as int, m[3] as int));
          }
        }
      });
      _recv = recv;
      _isolate = await Isolate.spawn(_workerMain, recv.sendPort, debugName: 'ShaderlyMotionWorker');
      _send = await ready.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('MotionWorker: could not start ($e) - falling back to inline processing');
      _broken = true;
      _send = null;
    } finally {
      _starting = null;
    }
  }

  /// Renders one Motion S frame. [frames] are the planned frames in slot order (each w * h * 4 bytes), [center] the slot being rendered,
  /// [uniforms] the FULL uniform buffer from MotionS.pack().
  ///
  /// [toSurface] (hardware encoder, zero copy): the finished frame is presented to the attached encoder Surface on the GPU and NOT returned
  /// ([MotionResult.rgba] is empty); [MotionResult.gpuStatus] is 0 when it was presented.
  Future<MotionResult> run({
    required List<Uint8List> frames,
    required int w,
    required int h,
    required int center,
    required Float32List uniforms,
    bool toSurface = false,
  }) async {
    await _ensureStarted();
    final send = _send;
    if (send == null || _broken) return _inline(frames, w, h, center, uniforms, toSurface);

    final id = _nextId++;
    final c = Completer<MotionResult>();
    _pending[id] = c;
    send.send([
      id,
      TransferableTypedData.fromList(frames),
      w,
      h,
      frames.length,
      center,
      TransferableTypedData.fromList([uniforms.buffer.asUint8List(uniforms.offsetInBytes, uniforms.lengthInBytes)]),
      toSurface,
    ]);
    try {
      return await c.future;
    } catch (e) {
      debugPrint('MotionWorker: $e - inline fallback');
      _pending.remove(id);
      return _inline(frames, w, h, center, uniforms, toSurface);
    }
  }

  MotionResult _inline(List<Uint8List> frames, int w, int h, int center, Float32List u, bool toSurface) {
    final sw = Stopwatch()..start();
    final all = BytesBuilder(copy: false);
    for (final f in frames) {
      all.add(f);
    }
    if (toSurface) {
      final rc = processMotionToSurface(all.toBytes(), w, h, frames.length, center, u);
      return MotionResult(Uint8List(0), rc == 0 ? 0 : _surfaceStatus(), sw.elapsedMicroseconds);
    }
    final out = processMotion(all.toBytes(), w, h, frames.length, center, u);
    return MotionResult(out, vulkanLastRenderStatus(), sw.elapsedMicroseconds);
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _recv?.close();
    _isolate = null;
    _send = null;
    _recv = null;
    _broken = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('motion worker disposed'));
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
    try {
      final Uint8List frames = (msg[1] as TransferableTypedData).materialize().asUint8List();
      final int w = msg[2] as int;
      final int h = msg[3] as int;
      final int count = msg[4] as int;
      final int center = msg[5] as int;
      final Float32List uniforms = (msg[6] as TransferableTypedData).materialize().asFloat32List();
      final bool toSurface = msg.length > 7 && msg[7] == true;

      final sw = Stopwatch()..start();
      if (toSurface) {
        final rc = processMotionToSurface(frames, w, h, count, center, uniforms);
        toMain.send([id, TransferableTypedData.fromList([Uint8List(0)]), rc == 0 ? 0 : _surfaceStatus(), sw.elapsedMicroseconds]);
        return;
      }
      final out = processMotion(frames, w, h, count, center, uniforms);
      final status = vulkanLastRenderStatus();
      toMain.send([id, TransferableTypedData.fromList([out]), status, sw.elapsedMicroseconds]);
    } catch (e) {
      toMain.send([id, null, -1, e.toString()]);
    }
  });
}

/// A surface frame that was not presented: the GPU status when there is one, else 1 (generic GPU error). Never 0.
int _surfaceStatus() {
  final s = vulkanLastRenderStatus();
  return s != 0 ? s : 1;
}
