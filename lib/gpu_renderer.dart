// lib/gpu_renderer.dart
// AEReality 32-bit GPU Renderer using Flutter GPU (experimental)
// Processes video frames through a WGSL compute shader with 32-bit float textures.

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_gpu/flutter_gpu.dart';

class GpuRenderer {
  // ---------- STATE ----------
  static GpuRenderer? _instance;
  bool _initialized = false;
  
  // Flutter GPU objects
  late RenderTarget _renderTarget;
  late GraphicsShader _shader;
  late ComputeBinding _computeBinding;
  late ComputePass _computePass;
  late Pipeline _pipeline;
  
  // Texture handles for input/output
  Texture? _inputTexture;
  Texture? _outputTexture;
  
  // Dimensions
  int _width = 0;
  int _height = 0;
  
  // Uniform buffer
  Uint8List? _uniformBuffer;
  
  // ---------- SINGLETON ----------
  static GpuRenderer get instance {
    _instance ??= GpuRenderer._();
    return _instance!;
  }
  
  GpuRenderer._();
  
  // ---------- INITIALIZATION ----------
  Future<void> init() async {
    if (_initialized) return;
    
    // 1. Load the WGSL shader from assets
    final shaderBytes = await rootBundle.load('shaders/aereality_core.wgsl');
    final shaderData = shaderBytes.buffer.asUint8List();
    
    // 2. Create the graphics shader
    _shader = GraphicsShader(shaderData);
    
    // 3. Create a render target (size will be updated per frame)
    _renderTarget = RenderTarget(
      width: 1920,
      height: 1080,
      pixelFormat: PixelFormat.rgba32Float, // ✅ 32-bit float
    );
    
    // 4. Build the compute pipeline
    _computeBinding = _shader.buildComputeBinding(
      'main',
      const BindingArguments({
        'inputTexture': TextureBinding.read,
        'outputTexture': TextureBinding.write,
        'uniforms': UniformBinding.uniform,
      }),
    );
    
    _computePass = _renderTarget.createComputePass(
      computeBinding: _computeBinding,
    );
    
    _pipeline = _computePass.pipeline;
    
    // 5. Create uniform buffer (12 floats = 48 bytes)
    _uniformBuffer = Uint8List(48); // 12 floats * 4 bytes
    
    _initialized = true;
  }
  
  // ---------- PROCESS A FRAME ----------
  Future<ui.Image> processFrame(ui.Image inputImage) async {
    if (!_initialized) throw Exception('GpuRenderer not initialized');
    
    final width = inputImage.width;
    final height = inputImage.height;
    
    // Resize render target if needed
    if (width != _width || height != _height) {
      _renderTarget = RenderTarget(
        width: width,
        height: height,
        pixelFormat: PixelFormat.rgba32Float,
      );
      _computePass = _renderTarget.createComputePass(
        computeBinding: _computeBinding,
      );
      _pipeline = _computePass.pipeline;
      _width = width;
      _height = height;
    }
    
    // 1. Upload input image as texture
    _inputTexture = _renderTarget.createTexture(
      width: width,
      height: height,
      format: PixelFormat.rgba8Unorm, // Input is RGBA8
      usage: TextureUsage.read,
    );
    
    // 2. Create output texture (32-bit float)
    _outputTexture = _renderTarget.createTexture(
      width: width,
      height: height,
      format: PixelFormat.rgba32Float, // ✅ 32-bit float
      usage: TextureUsage.write,
    );
    
    // 3. Write input pixels to texture
    // We need to get the pixel data from the ui.Image
    final inputBytes = await _imageToBytes(inputImage);
    _inputTexture!.write(inputBytes);
    
    // 4. Update uniforms
    _updateUniforms();
    
    // 5. Run the compute shader
    _computePass.run(_pipeline, [
      ComputeBindingEntry('inputTexture', _inputTexture!),
      ComputeBindingEntry('outputTexture', _outputTexture!),
      ComputeBindingEntry('uniforms', _uniformBuffer!),
    ]);
    
    // 6. Read back the output texture
    final outputBytes = _outputTexture!.read();
    
    // 7. Convert raw bytes to ui.Image
    final outputImage = await _bytesToImage(outputBytes, width, height);
    
    // 8. Clean up temporary textures
    _inputTexture = null;
    _outputTexture = null;
    
    return outputImage;
  }
  
  // ---------- UNIFORM UPDATE ----------
  void updateUniforms({
    double brightness = 0.0,
    double saturation = 1.0,
    double contrast = 1.0,
    double sharpness = 0.0,
    double gamma = 1.0,
    double hue = 0.0,
    double temperature = 6500.0,
    double glowIntensity = 0.3,
    double lookMix = 0.0,
    double vignette = 0.0,
    double splitToning = 0.0,
    int width = 1920,
    int height = 1080,
  }) {
    if (_uniformBuffer == null) return;
    
    final buffer = _uniformBuffer!;
    int offset = 0;
    
    // resolution (vec2f)
    _writeFloat(buffer, offset, width.toDouble()); offset += 4;
    _writeFloat(buffer, offset, height.toDouble()); offset += 4;
    
    // brightness
    _writeFloat(buffer, offset, brightness); offset += 4;
    // saturation
    _writeFloat(buffer, offset, saturation); offset += 4;
    // contrast
    _writeFloat(buffer, offset, contrast); offset += 4;
    // sharpness
    _writeFloat(buffer, offset, sharpness); offset += 4;
    // gamma
    _writeFloat(buffer, offset, gamma); offset += 4;
    // hue
    _writeFloat(buffer, offset, hue); offset += 4;
    // temperature
    _writeFloat(buffer, offset, temperature); offset += 4;
    // glowIntensity
    _writeFloat(buffer, offset, glowIntensity); offset += 4;
    // lookMix
    _writeFloat(buffer, offset, lookMix); offset += 4;
    // vignette
    _writeFloat(buffer, offset, vignette); offset += 4;
    // splitToning
    _writeFloat(buffer, offset, splitToning); offset += 4;
  }
  
  // ---------- HELPERS ----------
  void _writeFloat(Uint8List buffer, int offset, double value) {
    final bytes = Float32List.fromList([value]).buffer.asUint8List();
    buffer.setRange(offset, offset + 4, bytes);
  }
  
  Future<Uint8List> _imageToBytes(ui.Image image) async {
    // This is a placeholder – actual implementation would use
    // image.toByteData() and convert to RGBA8
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }
  
  Future<ui.Image> _bytesToImage(Uint8List bytes, int width, int height) async {
    // This is a placeholder – actual implementation would use
    // ui.decodeImageFromPixels() or similar
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, (img) {
      completer.complete(img);
    });
    return completer.future;
  }
  
  // ---------- CLEANUP ----------
  void dispose() {
    _computePass.dispose();
    _computeBinding.dispose();
    _shader.dispose();
    _renderTarget.dispose();
    _initialized = false;
  }
}
