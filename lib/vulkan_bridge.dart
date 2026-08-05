// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- Load the native library ---
final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

// --- FFI function signatures (Dart types) ---
typedef InitNative = Void Function(Pointer<Uint32> spirv, int size);
typedef ProcessNative = Void Function(Pointer<Uint8> input, int w, int h, Pointer<Uint8> output);
typedef CleanupNative = Void Function();

// --- Dart bindings ---
final initProcessor = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Uint32>, IntPtr)>>('init_processor')
    .asFunction<InitNative>();

final processFrame = nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Uint8>, Int32, Int32, Pointer<Uint8>)>>('process_frame')
    .asFunction<ProcessNative>();

final cleanupProcessor = nativeLib
    .lookup<NativeFunction<Void Function()>>('cleanup_processor')
    .asFunction<CleanupNative>();

// --- Global state ---
bool _initialized = false;

/// Initialize the Vulkan processor with the SPIR-V shader binary.
void initVulkan(Uint8List spirv) {
  if (_initialized) return;
  final ptr = calloc<Uint32>(spirv.length ~/ 4);
  ptr.asTypedList(spirv.length ~/ 4).setAll(0, spirv.buffer.asUint32List());
  // Pass size as int – Dart FFI converts to size_t automatically
  initProcessor(ptr, spirv.length);
  calloc.free(ptr);
  _initialized = true;
}

/// Process an RGBA8 image. Returns the processed RGBA8 image.
Uint8List processImage(Uint8List input, int width, int height) {
  if (!_initialized) throw Exception('Vulkan not initialized. Call initVulkan() first.');
  
  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);
  
  final output = Uint8List(width * height * 4);
  final outputPtr = calloc<Uint8>(output.length);
  
  // Pass width/height as int – Dart FFI converts to int32_t automatically
  processFrame(inputPtr, width, height, outputPtr);
  
  output.setAll(0, outputPtr.asTypedList(output.length));
  
  calloc.free(inputPtr);
  calloc.free(outputPtr);
  
  return output;
}

/// Clean up Vulkan resources.
void cleanupVulkan() {
  if (!_initialized) return;
  cleanupProcessor();
  _initialized = false;
}
