// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef InitVulkanC = Int32 Function(Pointer<Uint8> shaderBytes, Int32 length, Int32 precision);
typedef InitVulkanDart = int Function(Pointer<Uint8> shaderBytes, int length, int precision);

typedef ProcessImageC = Void Function(
  Pointer<Uint8> inputBytes,
  Int32 inWidth,
  Int32 inHeight,
  Pointer<Uint8> outputBytes,
  Int32 outWidth,
  Int32 outHeight,
  Pointer<Float> uniforms,
  Int32 uniformCount,
);

typedef ProcessImageDart = void Function(
  Pointer<Uint8> inputBytes,
  int inWidth,
  int inHeight,
  Pointer<Uint8> outputBytes,
  int outWidth,
  int outHeight,
  Pointer<Float> uniforms,
  int uniformCount,
);

typedef ProcessImage16C = Void Function(
  Pointer<Uint16> inputBytes,
  Int32 inWidth,
  Int32 inHeight,
  Pointer<Uint16> outputBytes,
  Int32 outWidth,
  Int32 outHeight,
  Pointer<Float> uniforms,
  Int32 uniformCount,
);

typedef ProcessImage16Dart = void Function(
  Pointer<Uint16> inputBytes,
  int inWidth,
  int inHeight,
  Pointer<Uint16> outputBytes,
  int outWidth,
  int outHeight,
  Pointer<Float> uniforms,
  int uniformCount,
);

DynamicLibrary? _lib;

DynamicLibrary _getLib() {
  if (_lib != null) return _lib!;
  try {
    _lib = DynamicLibrary.open('libvulkan_processor.so');
  } catch (_) {
    _lib = DynamicLibrary.process();
  }
  return _lib!;
}

// Helper to look up both snake_case and camelCase safely
Pointer<NativeFunction<T>> _lookupSymbol<T extends Function>(DynamicLibrary lib, String snakeName, String camelName) {
  try {
    return lib.lookup<NativeFunction<T>>(snakeName);
  } catch (_) {
    return lib.lookup<NativeFunction<T>>(camelName);
  }
}

bool initVulkan(Uint8List shaderSpv, int precision) {
  try {
    final nativeLib = _getLib();
    final InitVulkanDart initFunc = _lookupSymbol<InitVulkanC>(nativeLib, 'init_vulkan', 'initVulkan').asFunction();

    final ptr = calloc<Uint8>(shaderSpv.length);
    ptr.asTypedList(shaderSpv.length).setAll(0, shaderSpv);

    final res = initFunc(ptr, shaderSpv.length, precision);
    calloc.free(ptr);
    return res == 1;
  } catch (e) {
    return false;
  }
}

Uint8List processImage(
  Uint8List inputRgba,
  int inWidth,
  int inHeight,
  int outWidth,
  int outHeight,
  Float32List uniforms,
) {
  try {
    final nativeLib = _getLib();
    final ProcessImageDart procFunc = _lookupSymbol<ProcessImageC>(nativeLib, 'process_image', 'processImage').asFunction();

    final inSize = inWidth * inHeight * 4;
    final outSize = outWidth * outHeight * 4;

    final inPtr = calloc<Uint8>(inSize);
    inPtr.asTypedList(inSize).setAll(0, inputRgba);

    final outPtr = calloc<Uint8>(outSize);

    final uniPtr = calloc<Float>(uniforms.length);
    uniPtr.asTypedList(uniforms.length).setAll(0, uniforms);

    procFunc(inPtr, inWidth, inHeight, outPtr, outWidth, outHeight, uniPtr, uniforms.length);

    final result = Uint8List.fromList(outPtr.asTypedList(outSize));

    calloc.free(inPtr);
    calloc.free(outPtr);
    calloc.free(uniPtr);

    return result;
  } catch (e) {
    return inputRgba;
  }
}

Uint16List processImage16(
  Uint16List inputRgba16,
  int inWidth,
  int inHeight,
  int outWidth,
  int outHeight,
  Float32List uniforms,
) {
  try {
    final nativeLib = _getLib();
    final ProcessImage16Dart procFunc = _lookupSymbol<ProcessImage16C>(nativeLib, 'process_image_16', 'processImage16').asFunction();

    final inSize = inWidth * inHeight * 4;
    final outSize = outWidth * outHeight * 4;

    final inPtr = calloc<Uint16>(inSize);
    inPtr.asTypedList(inSize).setAll(0, inputRgba16);

    final outPtr = calloc<Uint16>(outSize);

    final uniPtr = calloc<Float>(uniforms.length);
    uniPtr.asTypedList(uniforms.length).setAll(0, uniforms);

    procFunc(inPtr, inWidth, inHeight, outPtr, outWidth, outHeight, uniPtr, uniforms.length);

    final result = Uint16List.fromList(outPtr.asTypedList(outSize));

    calloc.free(inPtr);
    calloc.free(outPtr);
    calloc.free(uniPtr);

    return result;
  } catch (e) {
    return inputRgba16;
  }
}
