// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- Load the native library ---
final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

// --- FFI function signatures using correct types ---
typedef InitNative = Void Function(Pointer<Uint32> spirv, IntPtr size);
typedef ProcessNative = Void Function(Pointer<Uint8> input, Int32 w, Int32 h, Pointer<Uint8> output);
typedef CleanupNative = Void Function();

// --- Dart bindings with explicit casting ---
final initProcessor = nativeLib
    .lookup<NativeFunction<InitNative>>('init_processor')
    .asFunction<InitNative>();

final processFrame = nativeLib
    .lookup<NativeFunction<ProcessNative>>('process_frame')
    .asFunction<ProcessNative>();

final cleanupProcessor = nativeLib
    .lookup<NativeFunction<CleanupNative>>('cleanup_processor')
    .asFunction<CleanupNative>();

// --- Global state ---
bool _initialized = false;

/// Initialize the Vulkan processor with the SPIR-V shader binary.
void initVulkan(Uint8List spirv) {
  if (_initialized) return;
  // Allocate memory for the SPIR-V binary (size in bytes)
  final ptr = calloc<Uint32>(spirv.length ~/ 4);
  ptr.asTypedList(spirv.length ~/ 4).setAll(0, spirv.buffer.asUint32List());
  // Pass size as IntPtr (size_t)
  initProcessor(ptr, IntPtr(spirv.length));
  calloc.free(ptr);
  _initialized = true;
}

/// Process an RGBA8 image. Returns the processed RGBA8 image.
Uint8List processImage(Uint8List input, int width, int height) {
  if (!_initialized) throw Exception('Vulkan not initialized. Call initVulkan() first.');
  
  // Allocate input buffer
  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);
  
  // Allocate output buffer
  final output = Uint8List(width * height * 4);
  final outputPtr = calloc<Uint8>(output.length);
  
  // Process – cast width/height to Int32
  processFrame(inputPtr, Int32(width), Int32(height), outputPtr);
  
  // Copy output back
  output.setAll(0, outputPtr.asTypedList(output.length));
  
  // Free memory
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
