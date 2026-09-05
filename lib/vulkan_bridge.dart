// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef InitVulkanC = Bool Function(Pointer<Uint8> shaderCode, Int32 codeSize, Int32 precisionMode);
typedef InitVulkanDart = bool Function(Pointer<Uint8> shaderCode, int codeSize, int precisionMode);

typedef ProcessImageC = Void Function(
    Pointer<Uint8> inputPixels,
    Int32 inputWidth,
    Int32 inputHeight,
    Pointer<Uint8> outputPixels,
    Int32 outputWidth,
    Int32 outputHeight,
    Pointer<Float> uniforms,
    Int32 uniformCount);

typedef ProcessImageDart = void Function(
    Pointer<Uint8> inputPixels,
    int inputWidth,
    int inputHeight,
    Pointer<Uint8> outputPixels,
    int outputWidth,
    int outputHeight,
    Pointer<Float> uniforms,
    int uniformCount);

typedef ProcessImage16C = Void Function(
    Pointer<Uint16> inputPixels,
    Int32 inputWidth,
    Int32 inputHeight,
    Pointer<Uint16> outputPixels,
    Int32 outputWidth,
    Int32 outputHeight,
    Pointer<Float> uniforms,
    Int32 uniformCount);

typedef ProcessImage16Dart = void Function(
    Pointer<Uint16> inputPixels,
    int inputWidth,
    int inputHeight,
    Pointer<Uint16> outputPixels,
    int outputWidth,
    int outputHeight,
    Pointer<Float> uniforms,
    int uniformCount);

final DynamicLibrary _nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

final InitVulkanDart _initVulkan =
    _nativeLib.lookup<NativeFunction<InitVulkanC>>('initVulkan').asFunction();

final ProcessImageDart _processImage =
    _nativeLib.lookup<NativeFunction<ProcessImageC>>('processImage').asFunction();

final ProcessImage16Dart _processImage16 =
    _nativeLib.lookup<NativeFunction<ProcessImage16C>>('processImage16').asFunction();

bool initVulkan(Uint8List shaderSpv, int precisionMode) {
  final Pointer<Uint8> ptr = malloc.allocate<Uint8>(shaderSpv.length);
  final Uint8List nativeBytes = ptr.asTypedList(shaderSpv.length);
  nativeBytes.setAll(0, shaderSpv);

  final bool result = _initVulkan(ptr, shaderSpv.length, precisionMode);
  malloc.free(ptr);
  return result;
}

Uint8List processImage(
  Uint8List inputPixels,
  int inWidth,
  int inHeight,
  int outWidth,
  int outHeight,
  Float32List uniforms,
) {
  final int inSize = inWidth * inHeight * 4;
  final int outSize = outWidth * outHeight * 4;

  final Pointer<Uint8> inPtr = malloc.allocate<Uint8>(inSize);
  final Pointer<Uint8> outPtr = malloc.allocate<Uint8>(outSize);
  final Pointer<Float> uniformPtr = malloc.allocate<Float>(uniforms.length * sizeOf<Float>());

  inPtr.asTypedList(inSize).setAll(0, inputPixels);
  uniformPtr.asTypedList(uniforms.length).setAll(0, uniforms);

  _processImage(inPtr, inWidth, inHeight, outPtr, outWidth, outHeight, uniformPtr, uniforms.length);

  final Uint8List result = Uint8List.fromList(outPtr.asTypedList(outSize));

  malloc.free(inPtr);
  malloc.free(outPtr);
  malloc.free(uniformPtr);

  return result;
}

Uint16List processImage16(
  Uint16List inputPixels,
  int inWidth,
  int inHeight,
  int outWidth,
  int outHeight,
  Float32List uniforms,
) {
  final int inPixelCount = inWidth * inHeight * 4;
  final int outPixelCount = outWidth * outHeight * 4;

  final Pointer<Uint16> inPtr = malloc.allocate<Uint16>(inPixelCount * sizeOf<Uint16>());
  final Pointer<Uint16> outPtr = malloc.allocate<Uint16>(outPixelCount * sizeOf<Uint16>());
  final Pointer<Float> uniformPtr = malloc.allocate<Float>(uniforms.length * sizeOf<Float>());

  inPtr.asTypedList(inPixelCount).setAll(0, inputPixels);
  uniformPtr.asTypedList(uniforms.length).setAll(0, uniforms);

  _processImage16(inPtr, inWidth, inHeight, outPtr, outWidth, outHeight, uniformPtr, uniforms.length);

  final Uint16List result = Uint16List.fromList(outPtr.asTypedList(outPixelCount));

  malloc.free(inPtr);
  malloc.free(outPtr);
  malloc.free(uniformPtr);

  return result;
}
