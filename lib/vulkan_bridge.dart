// ==========================================
// lib/vulkan_bridge.dart
// 100% COMPLETE & EXHAUSTIVE 32-BIT VULKAN FFI BRIDGE
// ==========================================

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

// ==========================================
// FFI TYPEDEFS - VULKAN COLOR GRADING COMPUTE
// ==========================================

// Batch 17B: init_vulkan / init_vulkan_async take a 4th argument, the directory of the pipeline cache file (nullptr = no cache).
typedef _InitVulkanC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> spvBytes,
  ffi.Int32 spvLength,
  ffi.Int32 precisionBits,
  ffi.Pointer<Utf8> cacheDir,
);
typedef _InitVulkanDart = int Function(
  ffi.Pointer<ffi.Uint8> spvBytes,
  int spvLength,
  int precisionBits,
  ffi.Pointer<Utf8> cacheDir,
);

// Batch 17B: polling the background init (never blocks, never takes the native pipeline mutex)
typedef _IsReadyC = ffi.Bool Function();
typedef _IsReadyDart = bool Function();

typedef _GetStatusC = ffi.Int32 Function();
typedef _GetStatusDart = int Function();

typedef _SetBandBudgetC = ffi.Void Function(ffi.Int32 ms);
typedef _SetBandBudgetDart = void Function(int ms);
typedef _GetLastRenderUsC = ffi.Int64 Function();
typedef _GetLastRenderUsDart = int Function();
typedef _SetFlareHalfC = ffi.Void Function(ffi.Int32 on);
typedef _SetFlareHalfDart = void Function(int on);

typedef _ProcessImage8C = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> inBytes,
  ffi.Int32 inW,
  ffi.Int32 inH,
  ffi.Pointer<ffi.Uint8> outBytes,
  ffi.Int32 outW,
  ffi.Int32 outH,
  ffi.Pointer<ffi.Float> uniforms,
  ffi.Int32 numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  ffi.Int32 lutSize,
);
typedef _ProcessImage8Dart = void Function(
  ffi.Pointer<ffi.Uint8> inBytes,
  int inW,
  int inH,
  ffi.Pointer<ffi.Uint8> outBytes,
  int outW,
  int outH,
  ffi.Pointer<ffi.Float> uniforms,
  int numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  int lutSize,
);

typedef _ProcessMotionC = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> frames,
  ffi.Int32 w,
  ffi.Int32 h,
  ffi.Int32 frameCount,
  ffi.Int32 centerIdx,
  ffi.Pointer<ffi.Uint8> outBytes,
  ffi.Pointer<ffi.Float> uniforms,
  ffi.Int32 numUniforms,
);
typedef _ProcessMotionDart = void Function(
  ffi.Pointer<ffi.Uint8> frames,
  int w,
  int h,
  int frameCount,
  int centerIdx,
  ffi.Pointer<ffi.Uint8> outBytes,
  ffi.Pointer<ffi.Float> uniforms,
  int numUniforms,
);

// Batch 12 step C1: Time Slice (ring ingest + emit)
typedef _TsIngestC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> inBytes,
  ffi.Int32 w,
  ffi.Int32 h,
  ffi.Pointer<ffi.Float> uniforms,
  ffi.Int32 numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  ffi.Int32 lutSize,
  ffi.Int32 slot,
  ffi.Int32 ringSlots,
);
typedef _TsIngestDart = int Function(
  ffi.Pointer<ffi.Uint8> inBytes,
  int w,
  int h,
  ffi.Pointer<ffi.Float> uniforms,
  int numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  int lutSize,
  int slot,
  int ringSlots,
);
typedef _TsEmitC = ffi.Int32 Function(
  ffi.Int32 w,
  ffi.Int32 h,
  ffi.Pointer<ffi.Uint8> outBytes,
  ffi.Pointer<ffi.Float> uniforms,
  ffi.Int32 numUniforms,
);
typedef _TsEmitDart = int Function(
  int w,
  int h,
  ffi.Pointer<ffi.Uint8> outBytes,
  ffi.Pointer<ffi.Float> uniforms,
  int numUniforms,
);

// Batch 12 step C2: ring release + pass 23 debug counter
typedef _TsReleaseC = ffi.Int32 Function();
typedef _TsReleaseDart = int Function();
typedef _P23CountC = ffi.Int32 Function();
typedef _P23CountDart = int Function();

// Batch 17A: boot diagnostics (last init_vulkan failure text / stage timings)
typedef _InitTextC = ffi.Pointer<Utf8> Function();
typedef _InitTextDart = ffi.Pointer<Utf8> Function();

typedef _ProcessImage16C = ffi.Void Function(
  ffi.Pointer<ffi.Uint16> inBytes,
  ffi.Int32 inW,
  ffi.Int32 inH,
  ffi.Pointer<ffi.Uint16> outBytes,
  ffi.Int32 outW,
  ffi.Int32 outH,
  ffi.Pointer<ffi.Float> uniforms,
  ffi.Int32 numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  ffi.Int32 lutSize,
);
typedef _ProcessImage16Dart = void Function(
  ffi.Pointer<ffi.Uint16> inBytes,
  int inW,
  int inH,
  ffi.Pointer<ffi.Uint16> outBytes,
  int outW,
  int outH,
  ffi.Pointer<ffi.Float> uniforms,
  int numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  int lutSize,
);

// Batch 18B: NV12 video export entry points (see process_image_nv12 / convert_rgba_to_nv12 in vulkan_processor.cpp)
typedef _ProcessNv12C = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> inBytes,
  ffi.Int32 w,
  ffi.Int32 h,
  ffi.Pointer<ffi.Uint8> outNv12,
  ffi.Pointer<ffi.Float> uniforms,
  ffi.Int32 numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  ffi.Int32 lutSize,
);
typedef _ProcessNv12Dart = int Function(
  ffi.Pointer<ffi.Uint8> inBytes,
  int w,
  int h,
  ffi.Pointer<ffi.Uint8> outNv12,
  ffi.Pointer<ffi.Float> uniforms,
  int numUniforms,
  ffi.Pointer<ffi.Float> lutTable,
  int lutSize,
);
typedef _RgbaToNv12C = ffi.Void Function(ffi.Pointer<ffi.Uint8> rgba, ffi.Int32 w, ffi.Int32 h, ffi.Pointer<ffi.Uint8> outNv12);
typedef _RgbaToNv12Dart = void Function(ffi.Pointer<ffi.Uint8> rgba, int w, int h, ffi.Pointer<ffi.Uint8> outNv12);

// ==========================================
// VULKAN BRIDGE IMPLEMENTATION
// ==========================================

class VulkanBridge {
  static ffi.DynamicLibrary? _lib;
  static bool _libLoaded = false;

  static _InitVulkanDart? _initVulkanFn;
  static _InitVulkanDart? _initVulkanAsyncFn; // batch 17B: runs init_vulkan on a native std::thread and returns at once
  static _IsReadyDart? _isReadyFn; // batch 17B: is_vulkan_ready()
  static _GetStatusDart? _initStateFn; // batch 17B: vulkan_init_state()  0 running, 1 ok, -1 failed
  static _GetStatusDart? _initColdFn; // batch 17B: vulkan_init_is_cold() 1 = no valid pipeline cache (slow one-time compile)
  static _ProcessImage8Dart? _processImage8Fn;
  static _ProcessImage16Dart? _processImage16Fn;
  static _GetStatusDart? _getStatusFn;
  static _SetBandBudgetDart? _setBandBudgetFn;
  static _GetLastRenderUsDart? _getLastRenderUsFn;
  static _SetFlareHalfDart? _setFlareHalfFn;
  static _ProcessMotionDart? _processMotionFn; // batch 9 (Motion S)
  static _TsIngestDart? _tsIngestFn; // batch 12 step C1 (Time Slice)
  static _TsEmitDart? _tsEmitFn;
  static _TsReleaseDart? _tsReleaseFn; // batch 12 step C2
  static _P23CountDart? _p23CountFn;
  static _ProcessNv12Dart? _processNv12Fn; // batch 18B (video export, NV12)
  static _RgbaToNv12Dart? _rgbaToNv12Fn;
  static _InitTextDart? _initErrorFn; // batch 17A
  static _InitTextDart? _initLogFn;

  static bool _isVulkanInitialized = false;

  static void _ensureLibraryLoaded() {
    if (_libLoaded) return;
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libvulkan_processor.so');
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('vulkan_processor.dll');
      } else {
        _lib = ffi.DynamicLibrary.process();
      }

      if (_lib != null) {
        try {
          _initVulkanFn = _lib!.lookupFunction<_InitVulkanC, _InitVulkanDart>('init_vulkan');
          _processImage8Fn = _lib!.lookupFunction<_ProcessImage8C, _ProcessImage8Dart>('process_image');
          _processImage16Fn = _lib!.lookupFunction<_ProcessImage16C, _ProcessImage16Dart>('process_image_16');
          try {
            _getStatusFn = _lib!.lookupFunction<_GetStatusC, _GetStatusDart>('get_last_render_status');
          } catch (_) {
            _getStatusFn = null; // older native lib without status reporting
          }
          try {
            _initErrorFn = _lib!.lookupFunction<_InitTextC, _InitTextDart>('get_last_init_error');
            _initLogFn = _lib!.lookupFunction<_InitTextC, _InitTextDart>('get_last_init_log');
          } catch (_) {
            _initErrorFn = null; // older native lib without boot diagnostics
            _initLogFn = null;
          }
          try {
            _initVulkanAsyncFn = _lib!.lookupFunction<_InitVulkanC, _InitVulkanDart>('init_vulkan_async');
            _isReadyFn = _lib!.lookupFunction<_IsReadyC, _IsReadyDart>('is_vulkan_ready');
            _initStateFn = _lib!.lookupFunction<_GetStatusC, _GetStatusDart>('vulkan_init_state');
            _initColdFn = _lib!.lookupFunction<_GetStatusC, _GetStatusDart>('vulkan_init_is_cold');
          } catch (_) {
            _initVulkanAsyncFn = null; // native lib without the batch 17B background init: EngineBoot falls back to the blocking call
            _isReadyFn = null;
            _initStateFn = null;
            _initColdFn = null;
          }
          try {
            _setBandBudgetFn = _lib!.lookupFunction<_SetBandBudgetC, _SetBandBudgetDart>('set_band_budget_ms');
            _getLastRenderUsFn = _lib!.lookupFunction<_GetLastRenderUsC, _GetLastRenderUsDart>('get_last_render_us');
            _setFlareHalfFn = _lib!.lookupFunction<_SetFlareHalfC, _SetFlareHalfDart>('set_flare_half_res');
          } catch (_) {
            _setBandBudgetFn = null; // older native lib
            _getLastRenderUsFn = null;
            _setFlareHalfFn = null;
          }
          try {
            _processMotionFn = _lib!.lookupFunction<_ProcessMotionC, _ProcessMotionDart>('process_motion');
          } catch (_) {
            _processMotionFn = null; // older native lib without Motion S
          }
          try {
            _tsIngestFn = _lib!.lookupFunction<_TsIngestC, _TsIngestDart>('process_timeslice_ingest');
            _tsEmitFn = _lib!.lookupFunction<_TsEmitC, _TsEmitDart>('process_timeslice_emit');
          } catch (_) {
            _tsIngestFn = null; // older native lib without Time Slice
            _tsEmitFn = null;
          }
          try {
            _tsReleaseFn = _lib!.lookupFunction<_TsReleaseC, _TsReleaseDart>('process_timeslice_release');
            _p23CountFn = _lib!.lookupFunction<_P23CountC, _P23CountDart>('get_pass23_count');
          } catch (_) {
            _tsReleaseFn = null; // C1 native lib: no release / counter
            _p23CountFn = null;
          }
          try {
            _processNv12Fn = _lib!.lookupFunction<_ProcessNv12C, _ProcessNv12Dart>('process_image_nv12');
            _rgbaToNv12Fn = _lib!.lookupFunction<_RgbaToNv12C, _RgbaToNv12Dart>('convert_rgba_to_nv12');
          } catch (_) {
            _processNv12Fn = null; // native lib without the batch 18B NV12 export: the export falls back to RGBA frames + FFmpeg conversion
            _rgbaToNv12Fn = null;
          }
        } catch (e) {
          debugPrint('VulkanBridge: Vulkan grading symbols lookup note: $e');
        }
      }
    } catch (e) {
      debugPrint('VulkanBridge: Native shared library load error: $e');
    }
    _libLoaded = true;
  }

  static Uint8List gradeFrameCpuFallback(
    Uint8List rgba,
    int width,
    int height,
    AdjustmentLayer layer,
  ) {
    final result = Uint8List.fromList(rgba);
    final double c = layer.contrast;
    final double s = layer.saturation;
    final double b = layer.brightness * 255.0;
    final double op = layer.opacity;

    if ((c - 1.0).abs() < 0.01 && (s - 1.0).abs() < 0.01 && b.abs() < 0.01) {
      return result;
    }

    for (int i = 0; i < result.length; i += 4) {
      double r = result[i].toDouble() + b;
      double g = result[i + 1].toDouble() + b;
      double bCol = result[i + 2].toDouble() + b;

      r = (r - 128.0) * c + 128.0;
      g = (g - 128.0) * c + 128.0;
      bCol = (bCol - 128.0) * c + 128.0;

      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * bCol;
      r = luma + (r - luma) * s;
      g = luma + (g - luma) * s;
      bCol = luma + (bCol - luma) * s;

      result[i] = ((1.0 - op) * rgba[i] + op * r).clamp(0.0, 255.0).toInt();
      result[i + 1] = ((1.0 - op) * rgba[i + 1] + op * g).clamp(0.0, 255.0).toInt();
      result[i + 2] = ((1.0 - op) * rgba[i + 2] + op * bCol).clamp(0.0, 255.0).toInt();
    }

    return result;
  }
}

// ==========================================
// TOP-LEVEL VULKAN GRADING FUNCTIONS
// ==========================================

/// 0 = last GPU render OK, 1 = GPU error (CPU fallback used), 2 = device lost, 3 = GPU timeout.
/// Call right after processImage / processImage16 to detect a bad render.
int vulkanLastRenderStatus() {
  VulkanBridge._ensureLibraryLoaded();
  return VulkanBridge._getStatusFn?.call() ?? 0;
}

/// Target wall time of one GPU submit in ms (4..500). Small = phone UI stays fluid, large = less submit overhead.
void vulkanSetBandBudgetMs(int ms) {
  VulkanBridge._ensureLibraryLoaded();
  VulkanBridge._setBandBudgetFn?.call(ms);
}

/// Wall time of the last native GPU pipeline run in microseconds (0 if the native lib is too old).
int vulkanLastRenderMicros() {
  VulkanBridge._ensureLibraryLoaded();
  return VulkanBridge._getLastRenderUsFn?.call() ?? 0;
}

/// true = flare beam is pre-computed at half resolution (native pass 10). Native state is process-wide.
void vulkanSetFlareHalfRes(bool on) {
  VulkanBridge._ensureLibraryLoaded();
  VulkanBridge._setFlareHalfFn?.call(on ? 1 : 0);
}

/// Batch 17A: returns true when the native engine is ready (init_vulkan returned 1). BLOCKING (it can take ~90 s on a cold shader cache):
/// since batch 17B EngineBoot uses [startVulkanInit] + polling instead and only falls back to this when the native lib is too old.
/// [cacheDir] (batch 17B) = directory of the pipeline cache file, null = no cache. When it returns false, [vulkanLastInitError] says which Vulkan call failed.
bool initVulkan(Uint8List shaderBytes, int precisionBits, {String? cacheDir}) {
  VulkanBridge._ensureLibraryLoaded();
  if (VulkanBridge._initVulkanFn == null) return false;
  final ptr = calloc<ffi.Uint8>(shaderBytes.length);
  final ffi.Pointer<Utf8> dirPtr = (cacheDir == null || cacheDir.isEmpty) ? ffi.nullptr.cast<Utf8>() : cacheDir.toNativeUtf8(allocator: calloc);
  try {
    ptr.asTypedList(shaderBytes.length).setAll(0, shaderBytes);
    final res = VulkanBridge._initVulkanFn!(ptr, shaderBytes.length, precisionBits, dirPtr);
    VulkanBridge._isVulkanInitialized = (res == 1);
    if (res != 1) debugPrint('initVulkan FAILED: ${vulkanLastInitError()}');
    return res == 1;
  } catch (e) {
    debugPrint('initVulkan error: $e');
    return false;
  } finally {
    calloc.free(ptr);
    if (dirPtr != ffi.nullptr) calloc.free(dirPtr);
  }
}

/// Batch 17B: true when this native lib has the background init (init_vulkan_async).
bool get vulkanHasAsyncInit {
  VulkanBridge._ensureLibraryLoaded();
  return VulkanBridge._initVulkanAsyncFn != null && VulkanBridge._initStateFn != null;
}

/// Batch 17B: starts init_vulkan on a native std::thread and RETURNS AT ONCE (the UI isolate is never blocked, not even on the first boot,
/// when an empty pipeline cache means a ~90 s shader compile). The native side copies [shaderBytes] and [cacheDir], so both are freed here.
/// Returns false when the native lib has no async init or the thread could not be started. Calling it again while the thread still runs
/// (RETRY after a timeout) just keeps waiting for that same thread. Poll with [isVulkanReady] / [vulkanInitState].
bool startVulkanInit(Uint8List shaderBytes, int precisionBits, String cacheDir) {
  VulkanBridge._ensureLibraryLoaded();
  final fn = VulkanBridge._initVulkanAsyncFn;
  if (fn == null) return false;
  final ptr = calloc<ffi.Uint8>(shaderBytes.length);
  final ffi.Pointer<Utf8> dirPtr = cacheDir.isEmpty ? ffi.nullptr.cast<Utf8>() : cacheDir.toNativeUtf8(allocator: calloc);
  try {
    ptr.asTypedList(shaderBytes.length).setAll(0, shaderBytes);
    return fn(ptr, shaderBytes.length, precisionBits, dirPtr) == 1;
  } catch (e) {
    debugPrint('startVulkanInit error: $e');
    return false;
  } finally {
    calloc.free(ptr);
    if (dirPtr != ffi.nullptr) calloc.free(dirPtr);
  }
}

/// Batch 17B: true once the background init finished successfully (native is_vulkan_ready()). Cheap, never blocks.
bool isVulkanReady() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    final ready = VulkanBridge._isReadyFn?.call() ?? false;
    VulkanBridge._isVulkanInitialized = ready || VulkanBridge._isVulkanInitialized;
    return ready;
  } catch (_) {
    return false;
  }
}

/// Batch 17B: 0 = the background init is still running (or never started), 1 = finished OK, -1 = finished with an error
/// ([vulkanLastInitError] then has the text). Cheap, never blocks.
int vulkanInitState() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    return VulkanBridge._initStateFn?.call() ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Batch 17B: true while the running init has NO valid pipeline cache, i.e. the one-time slow shader compile is happening (after a first
/// install, an app update with a new shader, or a GPU driver update). false = cache hit = a few seconds.
bool vulkanInitIsCold() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    return (VulkanBridge._initColdFn?.call() ?? 1) != 0;
  } catch (_) {
    return true;
  }
}

/// Text of the last init_vulkan failure (exact failing call + VkResult name and number), or '' when none / not supported by this native lib.
String vulkanLastInitError() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    final p = VulkanBridge._initErrorFn?.call();
    return (p == null || p == ffi.nullptr) ? '' : p.toDartString();
  } catch (_) {
    return '';
  }
}

/// GPU name and per-stage timings of the last init_vulkan run ("pipeline compile 4210ms; ...").
String vulkanLastInitLog() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    final p = VulkanBridge._initLogFn?.call();
    return (p == null || p == ffi.nullptr) ? '' : p.toDartString();
  } catch (_) {
    return '';
  }
}

Uint8List processImage(
  Uint8List inBytes,
  int inW,
  int inH,
  int outW,
  int outH,
  Float32List uniforms, {
  Float32List? lutTable,
}) {
  VulkanBridge._ensureLibraryLoaded();

  final outLen = outW * outH * 4;
  final outBytes = Uint8List(outLen);

  if (VulkanBridge._processImage8Fn != null) {
    final inPtr = calloc<ffi.Uint8>(inBytes.length);
    final outPtr = calloc<ffi.Uint8>(outLen);
    final uPtr = calloc<ffi.Float>(uniforms.length);
    ffi.Pointer<ffi.Float>? lutPtr;

    try {
      inPtr.asTypedList(inBytes.length).setAll(0, inBytes);
      uPtr.asTypedList(uniforms.length).setAll(0, uniforms);

      int lutSize = 0;
      if (lutTable != null && lutTable.isNotEmpty) {
        lutPtr = calloc<ffi.Float>(lutTable.length);
        lutPtr.asTypedList(lutTable.length).setAll(0, lutTable);
        lutSize = lutTable.length;
      }

      VulkanBridge._processImage8Fn!(
        inPtr,
        inW,
        inH,
        outPtr,
        outW,
        outH,
        uPtr,
        uniforms.length,
        lutPtr ?? ffi.Pointer.fromAddress(0),
        lutSize,
      );

      outBytes.setAll(0, outPtr.asTypedList(outLen));
      return outBytes;
    } catch (e) {
      debugPrint('processImage Vulkan error: $e');
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
      calloc.free(uPtr);
      if (lutPtr != null) calloc.free(lutPtr);
    }
  }

  return _cpuFallbackGrade(inBytes, inW, inH, uniforms);
}

// ==========================================
// NV12 VIDEO EXPORT (batch 18B)
// ==========================================

/// True when the native library has the GPU RGB -> NV12 export entry points.
bool vulkanNv12Available() {
  VulkanBridge._ensureLibraryLoaded();
  return VulkanBridge._processNv12Fn != null && VulkanBridge._rgbaToNv12Fn != null;
}

/// Grades one RGBA8 frame of size [w] x [h] (the EXPORT size: the GPU renders at it) and returns it as NV12 (w * h * 3 / 2 bytes: Y plane, then interleaved
/// UV; BT.709, limited range). The RGB -> YUV conversion runs on the GPU (pass 29); only the NV12 bytes are read back.
/// Returns null when the native entry point is missing or the size is not valid (w % 4 == 0 and h % 2 == 0 are required).
/// Check [vulkanLastRenderStatus] afterwards: 0 = GPU, 1 = GPU failed and the CPU fallback made the frame.
Uint8List? processImageNv12(
  Uint8List inBytes,
  int w,
  int h,
  Float32List uniforms, {
  Float32List? lutTable,
}) {
  VulkanBridge._ensureLibraryLoaded();
  final fn = VulkanBridge._processNv12Fn;
  if (fn == null || w <= 0 || h <= 0 || (w & 3) != 0 || (h & 1) != 0 || inBytes.length < w * h * 4) return null;

  final outLen = w * h * 3 ~/ 2;
  final inPtr = calloc<ffi.Uint8>(w * h * 4);
  final outPtr = calloc<ffi.Uint8>(outLen);
  final uPtr = calloc<ffi.Float>(uniforms.length);
  ffi.Pointer<ffi.Float>? lutPtr;
  try {
    inPtr.asTypedList(w * h * 4).setAll(0, inBytes.length == w * h * 4 ? inBytes : Uint8List.sublistView(inBytes, 0, w * h * 4));
    uPtr.asTypedList(uniforms.length).setAll(0, uniforms);
    int lutSize = 0;
    if (lutTable != null && lutTable.isNotEmpty) {
      lutPtr = calloc<ffi.Float>(lutTable.length);
      lutPtr.asTypedList(lutTable.length).setAll(0, lutTable);
      lutSize = lutTable.length;
    }
    final int rc = fn(inPtr, w, h, outPtr, uPtr, uniforms.length, lutPtr ?? ffi.Pointer.fromAddress(0), lutSize);
    if (rc < 0) return null;
    return Uint8List.fromList(outPtr.asTypedList(outLen)); // one copy out of native memory
  } catch (e) {
    debugPrint('processImageNv12 error: $e');
    return null;
  } finally {
    calloc.free(inPtr);
    calloc.free(outPtr);
    calloc.free(uPtr);
    if (lutPtr != null) calloc.free(lutPtr);
  }
}

/// CPU conversion of an RGBA8 frame to NV12 (same matrix and range as the GPU pass). Used for the frames that come back RGBA from the Time Slice ring.
Uint8List? rgbaToNv12(Uint8List rgba, int w, int h) {
  VulkanBridge._ensureLibraryLoaded();
  final fn = VulkanBridge._rgbaToNv12Fn;
  if (fn == null || w <= 0 || h <= 0 || rgba.length < w * h * 4) return null;
  final outLen = w * h * 3 ~/ 2;
  final inPtr = calloc<ffi.Uint8>(w * h * 4);
  final outPtr = calloc<ffi.Uint8>(outLen);
  try {
    inPtr.asTypedList(w * h * 4).setAll(0, rgba.length == w * h * 4 ? rgba : Uint8List.sublistView(rgba, 0, w * h * 4));
    fn(inPtr, w, h, outPtr);
    return Uint8List.fromList(outPtr.asTypedList(outLen));
  } catch (e) {
    debugPrint('rgbaToNv12 error: $e');
    return null;
  } finally {
    calloc.free(inPtr);
    calloc.free(outPtr);
  }
}

Uint16List processImage16(
  Uint16List inBytes,
  int inW,
  int inH,
  int outW,
  int outH,
  Float32List uniforms, {
  Float32List? lutTable,
}) {
  VulkanBridge._ensureLibraryLoaded();

  final outLen = outW * outH * 4;
  final outBytes = Uint16List(outLen);

  if (VulkanBridge._processImage16Fn != null) {
    final inPtr = calloc<ffi.Uint16>(inBytes.length);
    final outPtr = calloc<ffi.Uint16>(outLen);
    final uPtr = calloc<ffi.Float>(uniforms.length);
    ffi.Pointer<ffi.Float>? lutPtr;

    try {
      inPtr.asTypedList(inBytes.length).setAll(0, inBytes);
      uPtr.asTypedList(uniforms.length).setAll(0, uniforms);

      int lutSize = 0;
      if (lutTable != null && lutTable.isNotEmpty) {
        lutPtr = calloc<ffi.Float>(lutTable.length);
        lutPtr.asTypedList(lutTable.length).setAll(0, lutTable);
        lutSize = lutTable.length;
      }

      VulkanBridge._processImage16Fn!(
        inPtr,
        inW,
        inH,
        outPtr,
        outW,
        outH,
        uPtr,
        uniforms.length,
        lutPtr ?? ffi.Pointer.fromAddress(0),
        lutSize,
      );

      outBytes.setAll(0, outPtr.asTypedList(outLen));
      return outBytes;
    } catch (e) {
      debugPrint('processImage16 Vulkan error: $e');
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
      calloc.free(uPtr);
      if (lutPtr != null) calloc.free(lutPtr);
    }
  }

  outBytes.setAll(0, inBytes);
  return outBytes;
}

Uint8List _cpuFallbackGrade(Uint8List inBytes, int w, int h, Float32List uniforms) {
  final out = Uint8List.fromList(inBytes);
  if (uniforms.length < 38) return out;

  final double b = uniforms[35] * 255.0;
  final double s = uniforms[36];
  final double c = uniforms[37];

  for (int i = 0; i < out.length; i += 4) {
    double r = out[i].toDouble() + b;
    double g = out[i + 1].toDouble() + b;
    double bCol = out[i + 2].toDouble() + b;

    r = (r - 128.0) * c + 128.0;
    g = (g - 128.0) * c + 128.0;
    bCol = (bCol - 128.0) * c + 128.0;

    final luma = 0.2126 * r + 0.7152 * g + 0.0722 * bCol;
    r = luma + (r - luma) * s;
    g = luma + (g - luma) * s;
    bCol = luma + (bCol - luma) * s;

    out[i] = r.clamp(0.0, 255.0).toInt();
    out[i + 1] = g.clamp(0.0, 255.0).toInt();
    out[i + 2] = bCol.clamp(0.0, 255.0).toInt();
  }
  return out;
}

// ==========================================
// MOTION S (batch 9)
// ==========================================

/// True when the native library has the Motion S entry point.
bool vulkanMotionAvailable() {
  VulkanBridge._ensureLibraryLoaded();
  return VulkanBridge._processMotionFn != null;
}

/// One Motion S output frame. [frames] holds [frameCount] packed 8-bit RGBA frames (w * h * 4 bytes each, back to back),
/// [centerIdx] is the frame being rendered, [uniforms] MUST be the full uniform buffer (Vfx.uboFloats floats).
/// If the native side cannot do it, the centre frame comes back unchanged (check vulkanLastRenderStatus()).
Uint8List processMotion(Uint8List frames, int w, int h, int frameCount, int centerIdx, Float32List uniforms) {
  VulkanBridge._ensureLibraryLoaded();
  final frameBytes = w * h * 4;
  final out = Uint8List(frameBytes);
  final fn = VulkanBridge._processMotionFn;
  if (fn != null && frames.length >= frameBytes * frameCount && centerIdx >= 0 && centerIdx < frameCount) {
    final inPtr = calloc<ffi.Uint8>(frames.length);
    final outPtr = calloc<ffi.Uint8>(frameBytes);
    final uPtr = calloc<ffi.Float>(uniforms.length);
    try {
      inPtr.asTypedList(frames.length).setAll(0, frames);
      uPtr.asTypedList(uniforms.length).setAll(0, uniforms);
      fn(inPtr, w, h, frameCount, centerIdx, outPtr, uPtr, uniforms.length);
      out.setAll(0, outPtr.asTypedList(frameBytes));
      return out;
    } catch (e) {
      debugPrint('processMotion error: $e');
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
      calloc.free(uPtr);
    }
  }
  if (centerIdx >= 0 && (centerIdx + 1) * frameBytes <= frames.length) {
    out.setAll(0, Uint8List.sublistView(frames, centerIdx * frameBytes, (centerIdx + 1) * frameBytes));
  }
  return out;
}


// ==========================================
// TIME SLICE (batch 12 step C1)
// ==========================================

/// True when the native library has the Time Slice entry points.
bool vulkanTimeSliceAvailable() {
  VulkanBridge._ensureLibraryLoaded();
  return VulkanBridge._tsIngestFn != null && VulkanBridge._tsEmitFn != null;
}

/// Grades ONE 8-bit RGBA frame (full grade, NO dither) and stores the finished look in ring slot [slot] (0 .. ringSlots-1).
/// Returns false when the native side could not do it (then the caller grades normally). Blocking FFI call: run it in a worker (step C2).
bool timeSliceIngest(Uint8List rgba, int w, int h, Float32List uniforms, int slot, int ringSlots, {Float32List? lutTable}) {
  VulkanBridge._ensureLibraryLoaded();
  final fn = VulkanBridge._tsIngestFn;
  if (fn == null || rgba.length < w * h * 4) return false;
  final inPtr = calloc<ffi.Uint8>(w * h * 4);
  final uPtr = calloc<ffi.Float>(uniforms.length);
  ffi.Pointer<ffi.Float>? lutPtr;
  try {
    inPtr.asTypedList(w * h * 4).setAll(0, Uint8List.sublistView(rgba, 0, w * h * 4));
    uPtr.asTypedList(uniforms.length).setAll(0, uniforms);
    int lutSize = 0;
    if (lutTable != null && lutTable.isNotEmpty) {
      lutPtr = calloc<ffi.Float>(lutTable.length);
      lutPtr.asTypedList(lutTable.length).setAll(0, lutTable);
      lutSize = lutTable.length;
    }
    return fn(inPtr, w, h, uPtr, uniforms.length, lutPtr ?? ffi.Pointer.fromAddress(0), lutSize, slot, ringSlots) == 0;
  } catch (e) {
    debugPrint('timeSliceIngest error: $e');
    return false;
  } finally {
    calloc.free(inPtr);
    calloc.free(uPtr);
    if (lutPtr != null) calloc.free(lutPtr);
  }
}

/// Runs pass 22 (Time Slice) + pass 23 (dither + quantise) on the ring filled by [timeSliceIngest] and returns the 8-bit RGBA frame,
/// or null when the ring is not valid / the GPU failed. [uniforms] = the full buffer incl. the Time Slice block and the per-frame state.
Uint8List? timeSliceEmit(int w, int h, Float32List uniforms) {
  VulkanBridge._ensureLibraryLoaded();
  final fn = VulkanBridge._tsEmitFn;
  if (fn == null) return null;
  final outLen = w * h * 4;
  final outPtr = calloc<ffi.Uint8>(outLen);
  final uPtr = calloc<ffi.Float>(uniforms.length);
  try {
    uPtr.asTypedList(uniforms.length).setAll(0, uniforms);
    if (fn(w, h, outPtr, uPtr, uniforms.length) != 0) return null;
    return Uint8List.fromList(outPtr.asTypedList(outLen));
  } catch (e) {
    debugPrint('timeSliceEmit error: $e');
    return null;
  } finally {
    calloc.free(outPtr);
    calloc.free(uPtr);
  }
}

/// Batch 12 step C2: gives the Time Slice ring memory back (the display buffer is one frame long again). Safe to call when no ring exists.
void timeSliceRelease() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    VulkanBridge._tsReleaseFn?.call();
  } catch (e) {
    debugPrint('timeSliceRelease error: $e');
  }
}

/// Batch 12 step C2 debug: complete pass 23 (dither) runs since start, or -1 when the native lib has no counter. Grows by exactly 1 per frame.
int vulkanPass23Count() {
  VulkanBridge._ensureLibraryLoaded();
  try {
    return VulkanBridge._p23CountFn?.call() ?? -1;
  } catch (_) {
    return -1;
  }
}
