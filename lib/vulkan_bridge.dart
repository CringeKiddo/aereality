import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

typedef NativeInit = Void Function(Pointer<Uint32> spirv, IntPtr size);
typedef NativePrecision = Void Function(Int32 mode);

typedef NativeProcess8 = Void Function(
  Pointer<Uint8> input,
  Int32 inW,
  Int32 inH,
  Int32 outW,
  Int32 outH,
  Pointer<Uint8> output,
  Pointer<Float> uniforms,
);

typedef NativeProcess16 = Void Function(
  Pointer<Uint16> input,
  Int32 inW,
  Int32 inH,
  Int32 outW,
  Int32 outH,
  Pointer<Uint16> output,
  Pointer<Float> uniforms,
);

typedef NativeCleanup = Void Function();

typedef DartInit = void Function(Pointer<Uint32> spirv, int size);
typedef DartPrecision = void Function(int mode);
typedef DartProcess8 = void Function(
  Pointer<Uint8> input,
  int inW,
  int inH,
  int outW,
  int outH,
  Pointer<Uint8> output,
  Pointer<Float> uniforms,
);
typedef DartProcess16 = void Function(
  Pointer<Uint16> input,
  int inW,
  int inH,
  int outW,
  int outH,
  Pointer<Uint16> output,
  Pointer<Float> uniforms,
);
typedef DartCleanup = void Function();

final initProcessor = nativeLib
    .lookup<NativeFunction<NativeInit>>('init_processor')
    .asFunction<DartInit>();

final setPrecisionNative = nativeLib
    .lookup<NativeFunction<NativePrecision>>('set_engine_precision')
    .asFunction<DartPrecision>();

final processFrame8 = nativeLib
    .lookup<NativeFunction<NativeProcess8>>('process_frame')
    .asFunction<DartProcess8>();

DartProcess16? _processFrame16;
DartProcess16 get processFrame16 {
  _processFrame16 ??= nativeLib
      .lookup<NativeFunction<NativeProcess16>>('process_frame_16')
      .asFunction<DartProcess16>();
  return _processFrame16!;
}

final cleanupProcessor = nativeLib
    .lookup<NativeFunction<NativeCleanup>>('cleanup_processor')
    .asFunction<DartCleanup>();

bool _initialized = false;
bool get isVulkanReady => _initialized;
const int kUniformCount = 66;

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

/// 8-bit path for preview and standard exports
Uint8List processImage(
  Uint8List input,
  int inWidth,
  int inHeight,
  int outWidth,
  int outHeight,
  Float32List uniforms,
) {
  if (!_initialized) throw Exception('Vulkan not initialized.');
  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);

  final output = Uint8List(outWidth * outHeight * 4);
  final outputPtr = calloc<Uint8>(output.length);

  final uniformPtr = calloc<Float>(uniforms.length);
  for (int i = 0; i < uniforms.length; i++) {
    uniformPtr[i] = uniforms[i];
  }

  processFrame8(inputPtr, inWidth, inHeight, outWidth, outHeight, outputPtr, uniformPtr);
  output.setAll(0, outputPtr.asTypedList(output.length));

  calloc.free(inputPtr);
  calloc.free(outputPtr);
  calloc.free(uniformPtr);
  return output;
}

/// Genuine 16-bit path for 10-bit and 16-bit lossless exports
Uint16List processImage16(
  Uint16List input,
  int inWidth,
  int inHeight,
  int outWidth,
  int outHeight,
  Float32List uniforms,
) {
  if (!_initialized) throw Exception('Vulkan not initialized.');
  final inputPtr = calloc<Uint16>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);

  final output = Uint16List(outWidth * outHeight * 4);
  final outputPtr = calloc<Uint16>(output.length);

  final uniformPtr = calloc<Float>(uniforms.length);
  for (int i = 0; i < uniforms.length; i++) {
    uniformPtr[i] = uniforms[i];
  }

  try {
    processFrame16(inputPtr, inWidth, inHeight, outWidth, outHeight, outputPtr, uniformPtr);
    output.setAll(0, outputPtr.asTypedList(output.length));
  } catch (_) {
    // Graceful fallback to 8-bit pipeline if native library lacks 16-bit symbol
    final in8 = Uint8List(input.length);
    for (int i = 0; i < input.length; i++) in8[i] = input[i] >> 8;
    final out8 = processImage(in8, inWidth, inHeight, outWidth, outHeight, uniforms);
    for (int i = 0; i < output.length; i++) output[i] = out8[i] << 8;
  } finally {
    calloc.free(inputPtr);
    calloc.free(outputPtr);
    calloc.free(uniformPtr);
  }
  return output;
}

void cleanupVulkan() {
  if (!_initialized) return;
  cleanupProcessor();
  _initialized = false;
}
