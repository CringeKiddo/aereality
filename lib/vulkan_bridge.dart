// lib/vulkan_bridge.dart
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- Load the native library ---
final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libvulkan_processor.so')
    : DynamicLibrary.process();

// --- FFI function signatures ---
typedef InitFn = Void Function(Pointer<Uint32> spirv, IntPtr size);
typedef ProcessFn = Void Function(Pointer<Uint8> input, Int32 w, Int32 h, Pointer<Uint8> output);
typedef CleanupFn = Void Function();

// --- Dart bindings ---
final initProcessor = nativeLib.lookup<NativeFunction<InitFn>>('init_processor').asFunction<InitFn>();
final processFrame = nativeLib.lookup<NativeFunction<ProcessFn>>('process_frame').asFunction<ProcessFn>();
final cleanupProcessor = nativeLib.lookup<NativeFunction<CleanupFn>>('cleanup_processor').asFunction<CleanupFn>();

// --- Global state ---
bool _initialized = false;

/// Initialize the Vulkan processor with the SPIR-V shader binary.
void initVulkan(Uint8List spirv) {
  if (_initialized) return;
  final ptr = calloc<Uint32>(spirv.length ~/ 4);
  ptr.asTypedList(spirv.length ~/ 4).setAll(0, spirv.buffer.asUint32List());
  initProcessor(ptr, spirv.length);
  calloc.free(ptr);
  _initialized = true;
}

/// Process an RGBA8 image.
Uint8List processImage(Uint8List input, int width, int height) {
  if (!_initialized) throw Exception('Vulkan not initialized. Call initVulkan() first.');
  final inputPtr = calloc<Uint8>(input.length);
  inputPtr.asTypedList(input.length).setAll(0, input);
  final output = Uint8List(width * height * 4);
  final outputPtr = calloc<Uint8>(output.length);
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
