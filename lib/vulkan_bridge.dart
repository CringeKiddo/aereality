// ==========================================
// lib/vulkan_bridge.dart
// ==========================================

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

// ==========================================
// FFI TYPEDEFS - REAL-ESRGAN VULKAN NCNN
// ==========================================

typedef _InitRealEsrganC = ffi.Int32 Function(
  ffi.Pointer<Utf8> paramPath,
  ffi.Pointer<Utf8> binPath,
  ffi.Int32 scale,
);
typedef _InitRealEsrganDart = int Function(
  ffi.Pointer<Utf8> paramPath,
  ffi.Pointer<Utf8> binPath,
  int scale,
);

typedef _UpscaleFrameC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> inRgba,
  ffi.Int32 inWidth,
  ffi.Int32 inHeight,
  ffi.Pointer<ffi.Uint8> outRgba,
);
typedef _UpscaleFrameDart = int Function(
  ffi.Pointer<ffi.Uint8> inRgba,
  int inWidth,
  int inHeight,
  ffi.Pointer<ffi.Uint8> outRgba,
);

typedef _DestroyRealEsrganC = ffi.Void Function();
typedef _DestroyRealEsrganDart = void Function();

// ==========================================
// FFI TYPEDEFS - VULKAN COLOR GRADING COMPUTE
// ==========================================

typedef _InitVulkanC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> spvBytes,
  ffi.Int32 spvLength,
  ffi.Int32 precisionBits,
);
typedef _InitVulkanDart = int Function(
  ffi.Pointer<ffi.Uint8> spvBytes,
  int spvLength,
  int precisionBits,
);

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

// ==========================================
// VULKAN BRIDGE IMPLEMENTATION
// ==========================================

class VulkanBridge {
  static ffi.DynamicLibrary? _lib;
  static bool _libLoaded = false;

  // Real-ESRGAN function pointers
  static _InitRealEsrganDart? _initRealEsrganFn;
  static _UpscaleFrameDart? _upscaleFrameFn;
  static _DestroyRealEsrganDart? _destroyRealEsrganFn;

  // Vulkan Grading function pointers
  static _InitVulkanDart? _initVulkanFn;
  static _ProcessImage8Dart? _processImage8Fn;
  static _ProcessImage16Dart? _processImage16Fn;

  static bool _isVulkanInitialized = false;
  static bool _isRealEsrganInitialized = false;
  static int _currentScaleFactor = 2;

  static void _ensureLibraryLoaded() {
    if (_libLoaded) return;
    try {
      if (Platform.isAndroid) {
        // Aligned with native library produced by CMakeLists.txt
        _lib = ffi.DynamicLibrary.open('libvulkan_processor.so');
      } else if (Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libvulkan_processor.so');
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('vulkan_processor.dll');
      } else {
        _lib = ffi.DynamicLibrary.process();
      }

      if (_lib != null) {
        // Resolve Real-ESRGAN
        try {
          _initRealEsrganFn = _lib!
              .lookupFunction<_InitRealEsrganC, _InitRealEsrganDart>('init_realesrgan');
          _upscaleFrameFn = _lib!
              .lookupFunction<_UpscaleFrameC, _UpscaleFrameDart>('upscale_frame');
          _destroyRealEsrganFn = _lib!
              .lookupFunction<_DestroyRealEsrganC, _DestroyRealEsrganDart>('destroy_realesrgan');
        } catch (e) {
          debugPrint('VulkanBridge: Real-ESRGAN symbols not found in so: $e');
        }

        // Resolve Color Grading
        try {
          _initVulkanFn = _lib!
              .lookupFunction<_InitVulkanC, _InitVulkanDart>('init_vulkan');
          _processImage8Fn = _lib!
              .lookupFunction<_ProcessImage8C, _ProcessImage8Dart>('process_image');
          _processImage16Fn = _lib!
              .lookupFunction<_ProcessImage16C, _ProcessImage16Dart>('process_image_16');
        } catch (e) {
          debugPrint('VulkanBridge: Vulkan grading symbols not found: $e');
        }
      }
    } catch (e) {
      debugPrint('VulkanBridge: Native shared library load error: $e');
    }
    _libLoaded = true;
  }

  // -------------------------------------------------------------
  // REAL-ESRGAN NCNN GPU METHODS
  // -------------------------------------------------------------

  static Future<bool> initRealEsrgan({
    required String paramPath,
    required String binPath,
    int scaleFactor = 2,
  }) async {
    _ensureLibraryLoaded();
    _currentScaleFactor = scaleFactor;

    if (_initRealEsrganFn != null) {
      final paramPtr = paramPath.toNativeUtf8();
      final binPtr = binPath.toNativeUtf8();
      try {
        final res = _initRealEsrganFn!(paramPtr, binPtr, scaleFactor);
        _isRealEsrganInitialized = (res == 1 || res == 0);
        return _isRealEsrganInitialized;
      } catch (e) {
        debugPrint('VulkanBridge initRealEsrgan FFI error: $e');
      } finally {
        calloc.free(paramPtr);
        calloc.free(binPtr);
      }
    }
    return false;
  }

  static Future<Uint8List?> upscaleFrame({
    required Uint8List frameBytes,
    required int width,
    required int height,
  }) async {
    _ensureLibraryLoaded();

    final int outWidth = width * _currentScaleFactor;
    final int outHeight = height * _currentScaleFactor;
    final int outBytesLength = outWidth * outHeight * 4;

    if (_isRealEsrganInitialized && _upscaleFrameFn != null) {
      final inPtr = calloc<ffi.Uint8>(frameBytes.length);
      final outPtr = calloc<ffi.Uint8>(outBytesLength);

      try {
        inPtr.asTypedList(frameBytes.length).setAll(0, frameBytes);
        final ret = _upscaleFrameFn!(inPtr, width, height, outPtr);
        if (ret == 1 || ret == 0) {
          final resultBytes = Uint8List.fromList(outPtr.asTypedList(outBytesLength));
          return resultBytes;
        }
      } catch (e) {
        debugPrint('VulkanBridge upscaleFrame FFI error: $e');
      } finally {
        calloc.free(inPtr);
        calloc.free(outPtr);
      }
    }

    return null;
  }

  static Future<void> destroyRealEsrgan() async {
    if (_isRealEsrganInitialized && _destroyRealEsrganFn != null) {
      try {
        _destroyRealEsrganFn!();
      } catch (e) {
        debugPrint('VulkanBridge destroyRealEsrgan error: $e');
      }
      _isRealEsrganInitialized = false;
    }
  }

  // -------------------------------------------------------------
  // CPU FALLBACK GRADING HELPER
  // -------------------------------------------------------------

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
      double r = result[i].toDouble();
      double g = result[i + 1].toDouble();
      double bCol = result[i + 2].toDouble();

      // Exposure / Brightness
      r += b;
      g += b;
      bCol += b;

      // Contrast around midpoint 128
      r = (r - 128.0) * c + 128.0;
      g = (g - 128.0) * c + 128.0;
      bCol = (bCol - 128.0) * c + 128.0;

      // Saturation (Rec.709 luma)
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

void initVulkan(Uint8List shaderBytes, int precisionBits) {
  VulkanBridge._ensureLibraryLoaded();
  if (VulkanBridge._initVulkanFn != null) {
    final ptr = calloc<ffi.Uint8>(shaderBytes.length);
    try {
      ptr.asTypedList(shaderBytes.length).setAll(0, shaderBytes);
      final res = VulkanBridge._initVulkanFn!(ptr, shaderBytes.length, precisionBits);
      VulkanBridge._isVulkanInitialized = (res == 1);
    } catch (e) {
      debugPrint('initVulkan error: $e');
    } finally {
      calloc.free(ptr);
    }
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

  // CPU fallback grading
  return _cpuFallbackGrade(inBytes, inW, inH, uniforms);
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

  // Pass-through fallback
  outBytes.setAll(0, inBytes);
  return outBytes;
}

Uint8List _cpuFallbackGrade(Uint8List inBytes, int w, int h, Float32List uniforms) {
  final out = Uint8List.fromList(inBytes);
  if (uniforms.length < 25) return out;

  // Layer 0 brightness, contrast, saturation offsets
  final double b = uniforms[23] * 255.0;
  final double s = uniforms[24];
  final double c = uniforms[25];

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
