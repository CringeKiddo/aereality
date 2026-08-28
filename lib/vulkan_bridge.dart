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
    Int32 w,
    Int32 h,
    Pointer<Uint8> output,
    Pointer<Float> uniforms,
);
typedef NativeUploadLut = Void Function(Pointer<Float> data, Int32 size);
typedef NativeCleanup = Void Function();

typedef DartInit = void Function(Pointer<Uint32> spirv, int size);
typedef DartProcess = void Function(
    Pointer<Uint8> input,
    int w,
    int h,
    Pointer<Uint8> output,
    Pointer<Float> uniforms,
);
typedef DartUploadLut = void Function(Pointer<Float> data, int size);
typedef DartCleanup = void Function();

final initProcessor = nativeLib
    .lookup<NativeFunction<NativeInit>>('init_processor')
    .asFunction<DartInit>();

final processFrame = nativeLib
    .lookup<NativeFunction<NativeProcess>>('process_frame')
    .asFunction<DartProcess>();

final uploadLut = nativeLib
    .lookup<NativeFunction<NativeUploadLut>>('upload_lut')
    .asFunction<DartUploadLut>();

final cleanupProcessor = nativeLib
    .lookup<NativeFunction<NativeCleanup>>('cleanup_processor')
    .asFunction<DartCleanup>();

bool _initialized = false;

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
    int width,
    int height,
    Float32List uniforms, // must be length 14
) {
  if (!_initialized) throw Exception('Vulkan not initialized.');
  if (uniforms.length != 14) {
    throw Exception('uniforms must contain exactly 14 floats.');
  }

  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);

  final output = Uint8List(width * height * 4);
  final outputPtr = calloc<Uint8>(output.length);

  final uniformPtr = calloc<Float>(uniforms.length);
  for (int i = 0; i < uniforms.length; i++) {
    uniformPtr[i] = uniforms[i];
  }

  processFrame(inputPtr, width, height, outputPtr, uniformPtr);

  output.setAll(0, outputPtr.asTypedList(output.length));

  calloc.free(inputPtr);
  calloc.free(outputPtr);
  calloc.free(uniformPtr);

  return output;
}

void uploadLutData(Float32List lutData, int size) {
  if (!_initialized) throw Exception('Vulkan not initialized.');
  final ptr = calloc<Float>(lutData.length);
  for (int i = 0; i < lutData.length; i++) {
    ptr[i] = lutData[i];
  }
  uploadLut(ptr, size);
  calloc.free(ptr);
}

void cleanupVulkan() {
  if (!_initialized) return;
  cleanupProcessor();
  _initialized = false;
}
