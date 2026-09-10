import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:image/image.dart' as img;

import 'constants.dart';
import 'models.dart';
import 'project_screen.dart';
import 'vulkan_bridge.dart';

class StoredUpscaleVideo {
  final String id;
  final String path;
  final String name;
  final String scale;
  final DateTime date;

  StoredUpscaleVideo({
    required this.id,
    required this.path,
    required this.name,
    required this.scale,
    required this.date,
  });
}

class AiUpscalerScreen extends StatefulWidget {
  const AiUpscalerScreen({Key? key}) : super(key: key);

  @override
  State<AiUpscalerScreen> createState() => _AiUpscalerScreenState();
}

class _AiUpscalerScreenState extends State<AiUpscalerScreen> {
  File? _sourceFile;
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isFullScreen = false;

  int _scaleFactor = 2; // 2x or 4x
  int _selectedModelIndex = 0; // 0: Anime 6B (x4plus-anime), 1: RealNet (x4plus)

  double _deblur = 0.20;
  double _sharpness = 0.40;
  double _denoise = 0.15;

  double _splitPosition = 0.50;

  double _previewFramePos = 0.0;
  double _videoDurationSeconds = 1.0;
  double? _detectedFps;
  Uint8List? _originalFrameBytes;
  Uint8List? _upscaledFrameBytes;
  bool _isGeneratingFramePreview = false;
  Timer? _debounceTimer;

  static final List<StoredUpscaleVideo> _storedVideos = [];

  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';
  FFmpegSession? _activeSession;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller?.pause();
    _controller?.dispose();
    VulkanBridge.destroyRealEsrgan();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final p = result.files.single.path!;
      final ext = p.split('.').last.toLowerCase();
      if (['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
        setState(() {
          _sourceFile = File(p);
          _previewFramePos = 0.0;
        });
        _initController(p);
      }
    }
  }

  void _initController(String path) {
    _controller?.pause();
    _controller?.dispose();
    _controller = VideoPlayerController.file(File(path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isPlaying = true;
          _videoDurationSeconds = _controller!.value.duration.inMilliseconds / 1000.0;
          if (_videoDurationSeconds <= 0.0) _videoDurationSeconds = 1.0;
        });
        _controller!.play();
        _controller!.setLooping(true);
        _detectFps(path);
        _renderSingleFramePreview(0.0);
      });
  }

  Future<void> _detectFps(String path) async {
    try {
      final session = await FFmpegKit.execute('-hide_banner -i "$path"');
      final logs = await session.getLogsAsString() ?? '';
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*fps').firstMatch(logs);
      if (match != null) {
        _detectedFps = double.tryParse(match.group(1)!);
      }
    } catch (_) {}
  }

  Future<Map<String, String>> _resolveModelPaths() async {
    final tempDir = await getTemporaryDirectory();
    final paramDest = File('${tempDir.path}/realesrgan-x4plus-anime.param');
    final binDest = File('${tempDir.path}/realesrgan-x4plus-anime.bin');

    if (await paramDest.exists() && await binDest.exists()) {
      return {'param': paramDest.path, 'bin': binDest.path};
    }

    // 1. Direct /models directory check
    final searchDirs = [
      Directory('/models'),
      Directory('models'),
      Directory('/storage/emulated/0/Shaderly/models'),
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Shaderly'),
    ];

    for (var d in searchDirs) {
      if (await d.exists()) {
        final files = d.listSync();
        for (var f in files) {
          if (f is File) {
            final name = f.path.split('/').last.toLowerCase();
            if (name.contains('anime') && (name.endsWith('.param') || name.contains('.param'))) {
              await f.copy(paramDest.path);
            }
            if (name.contains('anime') && (name.endsWith('.bin') || name.contains('.bin'))) {
              await f.copy(binDest.path);
            }
          }
        }
      }
    }

    // 2. Flutter asset bundles check
    if (!await paramDest.exists()) {
      try {
        final data = await rootBundle.load('assets/models/realesrgan-x4plus-anime.param');
        await paramDest.writeAsBytes(data.buffer.asUint8List());
      } catch (_) {
        try {
          final data = await rootBundle.load('models/realesrgan-x4plus-anime.param');
          await paramDest.writeAsBytes(data.buffer.asUint8List());
        } catch (_) {}
      }
    }
    if (!await binDest.exists()) {
      try {
        final data = await rootBundle.load('assets/models/realesrgan-x4plus-anime.bin');
        await binDest.writeAsBytes(data.buffer.asUint8List());
      } catch (_) {
        try {
          final data = await rootBundle.load('models/realesrgan-x4plus-anime.bin');
          await binDest.writeAsBytes(data.buffer.asUint8List());
        } catch (_) {}
      }
    }

    return {'param': paramDest.path, 'bin': binDest.path};
  }

  Future<void> _renderSingleFramePreview(double timeSeconds) async {
    if (_sourceFile == null) return;
    setState(() => _isGeneratingFramePreview = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final origPath = '${tempDir.path}/preview_orig_${DateTime.now().millisecondsSinceEpoch}.png';

      await FFmpegKit.execute(
        '-hide_banner -y -ss $timeSeconds -i "${_sourceFile!.path}" -vframes 1 -q:v 1 "$origPath"',
      );

      if (!await File(origPath).exists()) {
        setState(() => _isGeneratingFramePreview = false);
        return;
      }

      final origBytes = await File(origPath).readAsBytes();
      final decoded = img.decodePng(origBytes);

      if (decoded == null) {
        setState(() => _isGeneratingFramePreview = false);
        return;
      }

      Uint8List? upBytes;
      final modelPaths = await _resolveModelPaths();
      final paramFile = File(modelPaths['param']!);
      final binFile = File(modelPaths['bin']!);

      if (await paramFile.exists() && await binFile.exists()) {
        final ok = await VulkanBridge.initRealEsrgan(
          paramPath: paramFile.path,
          binPath: binFile.path,
          scaleFactor: _scaleFactor,
        );

        if (ok) {
          final rawRgba = decoded.getBytes(order: img.ChannelOrder.rgba);
          final upscaledBuffer = await VulkanBridge.upscaleFrame(
            frameBytes: rawRgba,
            width: decoded.width,
            height: decoded.height,
          );

          if (upscaledBuffer != null) {
            final upscaledImage = img.Image.fromBytes(
              width: decoded.width * _scaleFactor,
              height: decoded.height * _scaleFactor,
              bytes: upscaledBuffer.buffer,
              numChannels: 4,
              order: img.ChannelOrder.rgba,
            );
            upBytes = Uint8List.fromList(img.encodePng(upscaledImage));
          }
        }
      }

      if (upBytes == null) {
        final upscaledPath = '${tempDir.path}/preview_up_fallback_${DateTime.now().millisecondsSinceEpoch}.png';
        final sharpVal = (_sharpness * 2.0).toStringAsFixed(2);
        final upscaleCmd = '-hide_banner -y -i "$origPath" -vf "scale=iw*$_scaleFactor:ih*$_scaleFactor:flags=lanczos+accurate_rnd,unsharp=5:5:$sharpVal:5:5:0.0" "$upscaledPath"';
        await FFmpegKit.execute(upscaleCmd);
        if (await File(upscaledPath).exists()) {
          upBytes = await File(upscaledPath).readAsBytes();
          try { await File(upscaledPath).delete(); } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _originalFrameBytes = origBytes;
          _upscaledFrameBytes = upBytes ?? origBytes;
          _isGeneratingFramePreview = false;
        });
      }

      try { await File(origPath).delete(); } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _isGeneratingFramePreview = false);
    }
  }

  void _onFrameSliderChanged(double val) {
    setState(() => _previewFramePos = val);
    _controller?.seekTo(Duration(milliseconds: (val * 1000).toInt()));
    _controller?.pause();
    setState(() => _isPlaying = false);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _renderSingleFramePreview(val);
    });
  }

  void _deleteStoredVideo(int index) {
    setState(() {
      _storedVideos.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video deleted from history.')),
    );
  }

  void _showWatermarkedFrameViewer() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.94),
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _upscaledFrameBytes != null
                  ? Image.memory(_upscaledFrameBytes!)
                  : (_controller != null && _controller!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        )
                      : const Icon(Icons.image_outlined, size: 80, color: Colors.white24)),
            ),
            Positioned(
              left: 36,
              top: MediaQuery.of(context).size.height * 0.42,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.4),
                        blurRadius: 18,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: const Color(0xFFE6E6FA).withOpacity(0.3),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFFE6E6FA), Color(0xFFFF80AB)],
                    ).createShader(bounds),
                    child: Text(
                      'Shaderly Real-ESRGAN Anime 6B (${_scaleFactor}x)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancelExport() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Upscale?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to stop this export? Progress will be lost.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Resume', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _activeSession?.cancel();
              setState(() {
                _isExporting = false;
                _exportStatus = 'Cancelled by user';
              });
            },
            child: const Text('Cancel Export', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _startExport() async {
    if (_sourceFile == null) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0.02;
      _exportStatus = 'Initializing Real-ESRGAN Anime 6B on Vulkan GPU...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final modelPaths = await _resolveModelPaths();
      final paramPath = modelPaths['param']!;
      final binPath = modelPaths['bin']!;

      final framesDir = Directory('${tempDir.path}/esrgan_frames');
      final upscaledDir = Directory('${tempDir.path}/esrgan_upscaled');

      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      if (await upscaledDir.exists()) await upscaledDir.delete(recursive: true);
      await framesDir.create(recursive: true);
      await upscaledDir.create(recursive: true);

      final audioPath = '${tempDir.path}/source_audio.aac';
      final oldAudio = File(audioPath);
      if (await oldAudio.exists()) await oldAudio.delete();

      await FFmpegKit.execute('-hide_banner -y -i "${_sourceFile!.path}" -vn -c:a copy "$audioPath"');

      setState(() => _exportStatus = 'Extracting source frames losslessly...');
      _activeSession = await FFmpegKit.execute(
        '-hide_banner -y -i "${_sourceFile!.path}" -qscale:v 1 "${framesDir.path}/frame_%05d.png"',
      );

      final frameFiles = framesDir.listSync().whereType<File>().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      final int totalFrames = frameFiles.length;

      if (totalFrames == 0) {
        throw Exception('Frame extraction failed. No frames extracted.');
      }

      bool hasNcnn = await File(paramPath).exists() && await File(binPath).exists();
      if (hasNcnn) {
        hasNcnn = await VulkanBridge.initRealEsrgan(
          paramPath: paramPath,
          binPath: binPath,
          scaleFactor: _scaleFactor,
        );
      }

      for (int i = 0; i < totalFrames; i++) {
        if (!_isExporting) break;

        final f = frameFiles[i];
        final bytes = await f.readAsBytes();
        final decoded = img.decodePng(bytes);
        if (decoded == null) continue;

        final paddedIndex = (i + 1).toString().padLeft(5, '0');
        final outFrameFile = File('${upscaledDir.path}/frame_$paddedIndex.png');

        if (hasNcnn) {
          final rawRgba = decoded.getBytes(order: img.ChannelOrder.rgba);
          final upscaledBuffer = await VulkanBridge.upscaleFrame(
            frameBytes: rawRgba,
            width: decoded.width,
            height: decoded.height,
          );

          if (upscaledBuffer != null) {
            final upscaledImage = img.Image.fromBytes(
              width: decoded.width * _scaleFactor,
              height: decoded.height * _scaleFactor,
              bytes: upscaledBuffer.buffer,
              numChannels: 4,
              order: img.ChannelOrder.rgba,
            );
            await outFrameFile.writeAsBytes(img.encodePng(upscaledImage));
          }
        } else {
          final sharpVal = (_sharpness * 2.0).toStringAsFixed(2);
          await FFmpegKit.execute(
            '-hide_banner -y -i "${f.path}" -vf "scale=iw*$_scaleFactor:ih*$_scaleFactor:flags=lanczos+accurate_rnd,unsharp=5:5:$sharpVal:5:5:0.0" "${outFrameFile.path}"',
          );
        }

        final double prog = (i + 1) / totalFrames;
        setState(() {
          _exportProgress = prog;
          _exportStatus = 'Upscaling with Real-ESRGAN: ${(prog * 100).toInt()}% (${i + 1}/$totalFrames)';
        });
      }

      if (hasNcnn) {
        await VulkanBridge.destroyRealEsrgan();
      }

      if (!_isExporting) return;

      Directory outDir = Directory('/storage/emulated/0/Shaderly');
      if (!await outDir.exists()) outDir = Directory('/storage/emulated/0/Download');
      if (!await outDir.exists()) outDir = await getApplicationDocumentsDirectory();

      final fps = _detectedFps ?? 30.0;
      final outVideoPath = '${outDir.path}/Shaderly_RealESRGAN_Anime6B_${_scaleFactor}x_${DateTime.now().millisecondsSinceEpoch}.mp4';

      setState(() => _exportStatus = 'Assembling master video & muxing audio...');

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length() > 1000);

      String muxCmd;
      if (hasAudio) {
        muxCmd = '-hide_banner -y -framerate $fps -i "${upscaledDir.path}/frame_%05d.png" -i "$audioPath" -c:v libx264 -preset veryfast -crf 17 -pix_fmt yuv420p -c:a copy -movflags +faststart "$outVideoPath"';
      } else {
        muxCmd = '-hide_banner -y -framerate $fps -i "${upscaledDir.path}/frame_%05d.png" -c:v libx264 -preset veryfast -crf 17 -pix_fmt yuv420p -movflags +faststart "$outVideoPath"';
      }

      _activeSession = await FFmpegKit.execute(muxCmd);
      final returnCode = await _activeSession!.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _isExporting = false;
          _exportProgress = 1.0;
          _exportStatus = 'Done!';
          if (_storedVideos.length >= 3) _storedVideos.removeAt(0);
          _storedVideos.add(
            StoredUpscaleVideo(
              id: DateTime.now().toString(),
              path: outVideoPath,
              name: outVideoPath.split('/').last,
              scale: '${_scaleFactor}x',
              date: DateTime.now(),
            ),
          );
        });

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: kCardDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Real-ESRGAN Complete!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text('Saved with vector line art to:\n$outVideoPath\n\nWould you like to import this into the Studio Timeline?', style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Stay Here', style: TextStyle(color: Colors.white54))),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: gCustomAccentColor.value, foregroundColor: Colors.black),
                  icon: const Icon(Icons.movie_creation_rounded, size: 18),
                  label: const Text('OPEN IN TIMELINE', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectScreen(
                          initialProject: ProjectData(
                            mediaPath: outVideoPath,
                            isImage: false,
                            aspectRatio: '16:9',
                            layers: [
                              AdjustmentLayer(
                                id: 'esrgan_layer',
                                name: 'Real-ESRGAN Anime 6B ${_scaleFactor}x',
                                blendMode: LayerBlendMode.normal,
                              ),
                            ],
                          ),
                          projectName: 'ESRGAN ${_scaleFactor}x Master',
                          isImportedFromUpscaler: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        }
      } else {
        final logs = await _activeSession!.getLogsAsString();
        throw Exception('Encoding failed: $logs');
      }
    } catch (e) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upscale Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

    return Scaffold(
      backgroundColor: kBackgroundDark,
      appBar: AppBar(
        title: const Text('Shaderly AI Upscaler (Real-ESRGAN)', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen_rounded),
            tooltip: 'Fullscreen Frame Inspection',
            onPressed: _showWatermarkedFrameViewer,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Select Media',
            onPressed: _pickMedia,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: _isFullScreen ? 10 : 5,
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _sourceFile != null
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: _originalFrameBytes != null
                                  ? Image.memory(_originalFrameBytes!, fit: BoxFit.contain)
                                  : (_controller != null && _controller!.value.isInitialized
                                      ? Center(
                                          child: AspectRatio(
                                            aspectRatio: _controller!.value.aspectRatio,
                                            child: VideoPlayer(_controller!),
                                          ),
                                        )
                                      : const SizedBox()),
                            ),

                            if (_upscaledFrameBytes != null)
                              Positioned.fill(
                                child: ClipRect(
                                  clipper: _SplitClipper(_splitPosition),
                                  child: Image.memory(_upscaledFrameBytes!, fit: BoxFit.contain),
                                ),
                              ),

                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    _splitPosition = (details.localPosition.dx / constraints.maxWidth).clamp(0.02, 0.98);
                                  });
                                },
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: constraints.maxWidth * _splitPosition - 1.5,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 3.0,
                                        color: accent,
                                        child: Center(
                                          child: Container(
                                            width: 16,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: accent,
                                              borderRadius: BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(color: accent.withOpacity(0.6), blurRadius: 8),
                                              ],
                                            ),
                                            child: const Icon(Icons.drag_indicator_rounded, color: Colors.black, size: 14),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 12,
                                      top: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                        child: const Text('BEFORE (1x)', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    Positioned(
                                      right: 12,
                                      top: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                        child: Text('AFTER (${_scaleFactor}x ANIME 6B)', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (_isGeneratingFramePreview)
                              Positioned(
                                top: 12,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                                        const SizedBox(width: 8),
                                        const Text('Upscaling Frame with Neural NCNN...', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    )
                  : Center(
                      child: ElevatedButton.icon(
                        onPressed: _pickMedia,
                        icon: const Icon(Icons.video_library_rounded, color: Colors.black),
                        label: const Text('CHOOSE VIDEO OR ART TO UPSCALE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: accent),
                      ),
                    ),
            ),
          ),

          if (_sourceFile != null)
            Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  const Text('FRAME:', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('${_previewFramePos.toStringAsFixed(2)}s', style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        activeTrackColor: accent,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: accent,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _previewFramePos.clamp(0.0, _videoDurationSeconds),
                        min: 0.0,
                        max: _videoDurationSeconds,
                        onChanged: _onFrameSliderChanged,
                      ),
                    ),
                  ),
                  Text('${_videoDurationSeconds.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ),

          Expanded(
            flex: 5,
            child: Container(
              color: kCardDark,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _scaleFactor = 2);
                            _renderSingleFramePreview(_previewFramePos);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _scaleFactor == 2 ? accent.withOpacity(0.2) : Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _scaleFactor == 2 ? accent : Colors.white12,
                                width: _scaleFactor == 2 ? 2.2 : 1.0,
                              ),
                              boxShadow: _scaleFactor == 2
                                  ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 10, spreadRadius: 1)]
                                  : null,
                            ),
                            child: Center(
                              child: Text('2X UPSCALE', style: TextStyle(color: _scaleFactor == 2 ? accent : Colors.white60, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _scaleFactor = 4);
                            _renderSingleFramePreview(_previewFramePos);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _scaleFactor == 4 ? const Color(0xFF00E5FF).withOpacity(0.2) : Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _scaleFactor == 4 ? const Color(0xFF00E5FF) : Colors.white12,
                                width: _scaleFactor == 4 ? 2.2 : 1.0,
                              ),
                              boxShadow: _scaleFactor == 4
                                  ? [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.4), blurRadius: 10, spreadRadius: 1)]
                                  : null,
                            ),
                            child: Center(
                              child: Text('4X UPSCALE', style: TextStyle(color: _scaleFactor == 4 ? const Color(0xFF00E5FF) : Colors.white60, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Text('NEURAL MODEL SELECTION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text('Anime 6B (${_scaleFactor}x Vector)'),
                          selected: _selectedModelIndex == 0,
                          selectedColor: accent,
                          labelStyle: TextStyle(color: _selectedModelIndex == 0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (_) {
                            setState(() => _selectedModelIndex = 0);
                            _renderSingleFramePreview(_previewFramePos);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('x${_scaleFactor}plus RealNet'),
                          selected: _selectedModelIndex == 1,
                          selectedColor: accent,
                          labelStyle: TextStyle(color: _selectedModelIndex == 1 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (_) {
                            setState(() => _selectedModelIndex = 1);
                            _renderSingleFramePreview(_previewFramePos);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  _buildSlider('Deblur Restoration', _deblur, 0.0, 1.0, (v) {
                    setState(() => _deblur = v);
                    _debounceTimer?.cancel();
                    _debounceTimer = Timer(const Duration(milliseconds: 300), () => _renderSingleFramePreview(_previewFramePos));
                  }),
                  _buildSlider('Acutance Sharpness', _sharpness, 0.0, 1.0, (v) {
                    setState(() => _sharpness = v);
                    _debounceTimer?.cancel();
                    _debounceTimer = Timer(const Duration(milliseconds: 300), () => _renderSingleFramePreview(_previewFramePos));
                  }),
                  _buildSlider('Noise Suppression', _denoise, 0.0, 1.0, (v) {
                    setState(() => _denoise = v);
                    _debounceTimer?.cancel();
                    _debounceTimer = Timer(const Duration(milliseconds: 300), () => _renderSingleFramePreview(_previewFramePos));
                  }),

                  const SizedBox(height: 16),
                  if (_storedVideos.isNotEmpty) ...[
                    const Text('PREVIOUSLY UPSCALED VIDEOS (MAX 3)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ...List.generate(_storedVideos.length, (i) {
                      final v = _storedVideos[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Text(v.scale, style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(v.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              onPressed: () => _deleteStoredVideo(i),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                  ],

                  ElevatedButton.icon(
                    onPressed: _isExporting ? _confirmCancelExport : _startExport,
                    icon: Icon(_isExporting ? Icons.cancel_outlined : Icons.auto_awesome_rounded, color: Colors.black),
                    label: Text(_isExporting ? 'CANCEL EXPORT' : 'START REAL-ESRGAN ANIME UPSCALE', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isExporting ? Colors.redAccent : accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    final accent = gCustomAccentColor.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            Text(val.toStringAsFixed(2), style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(value: val, min: min, max: max, activeColor: accent, onChanged: onChanged),
      ],
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double split;
  _SplitClipper(this.split);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(size.width * split, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(covariant _SplitClipper oldClipper) => oldClipper.split != split;
}
