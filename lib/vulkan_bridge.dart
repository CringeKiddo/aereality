// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

// --- Native function signatures (using FFI types) ---
typedef NativeInit = Void Function(Pointer<Uint32> spirv, IntPtr size);
typedef NativeProcess = Void Function(Pointer<Uint8> input, Int32 w, Int32 h, Pointer<Uint8> output);
typedef NativeCleanup = Void Function();

// --- Dart function signatures (using Dart types) ---
typedef DartInit = void Function(Pointer<Uint32> spirv, int size);
typedef DartProcess = void Function(Pointer<Uint8> input, int w, int h, Pointer<Uint8> output);
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

void initVulkan(Uint8List spirv) {
  if (_initialized) return;
  final ptr = calloc<Uint32>(spirv.length ~/ 4);
  ptr.asTypedList(spirv.length ~/ 4).setAll(0, spirv.buffer.asUint32List());
  initProcessor(ptr, spirv.length);
  calloc.free(ptr);
  _initialized = true;
}

Uint8List processImage(Uint8List input, int width, int height) {
  if (!_initialized) throw Exception('Vulkan not initialized. Call initVulkan() first.');
  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);
  final output = Uint8List(width * height * 4);
  final outputPtr = calloc<Uint8>(output.length);
  
  // ✅ DEBUG: print pointer addresses
  print('🔵 Calling processFrame with inputPtr: $inputPtr, outputPtr: $outputPtr, w: $width, h: $height');
  processFrame(inputPtr, width, height, outputPtr);
  print('🔵 processFrame returned');
  
  output.setAll(0, outputPtr.asTypedList(output.length));
  calloc.free(inputPtr);
  calloc.free(outputPtr);
  return output;
}

void cleanupVulkan() {
  if (!_initialized) return;
  cleanupProcessor();
  _initialized = false;
}
