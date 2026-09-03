// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

typedef NativeInit = Void Function(Pointer<Uint32> spirv, IntPtr size);
typedef NativePrecision = Void Function(Int32 mode);
typedef NativeProcess = Void Function(
    Pointer<Uint8> input,
    Int32 inW,
    Int32 inH,
    Int32 outW,
    Int32 outH,
    Pointer<Uint8> output,
    Pointer<Float> uniforms,
);
typedef NativeCleanup = Void Function();

typedef DartInit = void Function(Pointer<Uint32> spirv, int size);
typedef DartPrecision = void Function(int mode);
typedef DartProcess = void Function(
    Pointer<Uint8> input,
    int inW,
    int inH,
    int outW,
    int outH,
    Pointer<Uint8> output,
    Pointer<Float> uniforms,
);
typedef DartCleanup = void Function();

final initProcessor = nativeLib
    .lookup<NativeFunction<NativeInit>>('init_processor')
    .asFunction<DartInit>();

final setPrecisionNative = nativeLib
    .lookup<NativeFunction<NativePrecision>>('set_engine_precision')
    .asFunction<DartPrecision>();

final processFrame = nativeLib
    .lookup<NativeFunction<NativeProcess>>('process_frame')
    .asFunction<DartProcess>();

final cleanupProcessor = nativeLib
    .lookup<NativeFunction<NativeCleanup>>('cleanup_processor')
    .asFunction<DartCleanup>();

bool _initialized = false;

// 1 time float + 25 parameters + 32 floats for 4 curves (8 floats per curve) = 58 floats total
const int kUniformCount = 58;

void initVulkan(Uint8List spirv, [int precision = 16]) {
  if (_initialized) {
    setEnginePrecision(precision);
    return;
  }
  final ptr = calloc<Uint32>(spirv.length ~/ 4);
  ptr.asTypedList(spirv.length ~/ 4).setAll(0, spirv.buffer.asUint32List());
  initProcessor(ptr, spirv.length);
  calloc.free(ptr);
  _initialized = true;
  setEnginePrecision(precision);
}

void setEnginePrecision(int bits) {
  if (!_initialized) return;
  setPrecisionNative(bits);
}

Uint8List processImage(
    Uint8List input,
    int inWidth,
    int inHeight,
    int outWidth,
    int outHeight,
    Float32List uniforms,
) {
  if (!_initialized) throw Exception('Vulkan not initialized.');
  if (uniforms.length != kUniformCount) {
    throw Exception('uniforms must contain exactly $kUniformCount floats, got ${uniforms.length}.');
  }

  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);

  final output = Uint8List(outWidth * outHeight * 4);
  final outputPtr = calloc<Uint8>(output.length);

  final uniformPtr = calloc<Float>(uniforms.length);
  for (int i = 0; i < uniforms.length; i++) {
    uniformPtr[i] = uniforms[i];
  }

  processFrame(inputPtr, inWidth, inHeight, outWidth, outHeight, outputPtr, uniformPtr);

  output.setAll(0, outputPtr.asTypedList(output.length));

  calloc.free(inputPtr);
  calloc.free(outputPtr);
  calloc.free(uniformPtr);

  return output;
}

void cleanupVulkan() {
  if (!_initialized) return;
  cleanupProcessor();
  _initialized = false;
}
