import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

typedef NativeInit = Void Function(Pointer<Uint32> spirv, IntPtr size);
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

final processFrame = nativeLib
    .lookup<NativeFunction<NativeProcess>>('process_frame')
    .asFunction<DartProcess>();

final cleanupProcessor = nativeLib
    .lookup<NativeFunction<NativeCleanup>>('cleanup_processor')
    .asFunction<DartCleanup>();

bool _initialized = false;

// 1 float (time) + 23 grading parameters = 24 floats total
const int kUniformCount = 24;

void initVulkan(Uint8List spirv) {
  if (_initialized) return;
  final ptr = calloc<Uint32>(spirv.length ~/ 4);
  ptr.asTypedList(spirv.length ~/ 4).setAll(0, spirv.buffer.asUint32List());
  initProcessor(ptr, spirv.length);
  calloc.free(ptr);
  _initialized = true;
}

Uint8List processImage(
    Uint8List input,
    int inWidth,
    int inHeight,
    int outWidth,
    int outHeight,
    Float32List uniforms, // Must be exactly length 24
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
