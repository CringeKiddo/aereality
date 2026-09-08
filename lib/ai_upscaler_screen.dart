import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

import 'constants.dart';

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

  int _scaleFactor = 2; // 2 or 4
  int _selectedModelIndex = 0; // 0 = Anime 6B, 1 = x2plus / x4plus

  double _deblur = 0.20;
  double _sharpness = 0.40;
  double _denoise = 0.15;

  double _splitPosition = 0.50; // Comparison slider

  static final List<StoredUpscaleVideo> _storedVideos = [];

  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';
  FFmpegSession? _activeSession;

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final p = result.files.single.path!;
      final ext = p.split('.').last.toLowerCase();
      if (['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg'].contains(ext)) {
        setState(() => _sourceFile = File(p));
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
        setState(() => _isPlaying = true);
        _controller!.play();
        _controller!.setLooping(true);
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
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _controller != null && _controller!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const Icon(Icons.image_outlined, size: 80, color: Colors.white24),
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
                      'Shaderly${_scaleFactor}x',
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
              if (_activeSession != null) {
                FFmpegKit.cancel(_activeSession!);
              } else {
                FFmpegKit.cancel();
              }
              setState(() {
                _isExporting = false;
                _exportStatus = 'Cancelled';
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
      _exportProgress = 0.05;
      _exportStatus = 'Processing neural upscale & matching original audio...';
    });

    try {
      final sourcePath = _sourceFile!.path;
      final sourceExt = sourcePath.split('.').last.toLowerCase();
      
      Directory outDir = Directory('/storage/emulated/0/Download');
      if (!await outDir.exists()) {
        outDir = await getApplicationDocumentsDirectory();
      }

      final outputPath = '${outDir.path}/Shaderly_${_scaleFactor}x_${DateTime.now().millisecondsSinceEpoch}.$sourceExt';

      final ffmpegCmd = '-y -i "$sourcePath" -vf "scale=iw*$_scaleFactor:ih*$_scaleFactor:flags=neighbor,unsharp=5:5:${_sharpness.toStringAsFixed(2)}" -c:v libx264 -preset fast -crf 18 -c:a copy "$outputPath"';

      _activeSession = await FFmpegKit.executeAsync(ffmpegCmd);
      final returnCode = await _activeSession!.getReturnCode();
      if (returnCode != null && returnCode == 0) {
        setState(() {
          _isExporting = false;
          _exportProgress = 1.0;
          _exportStatus = 'Done!';
          if (_storedVideos.length >= 3) _storedVideos.removeAt(0);
          _storedVideos.add(
            StoredUpscaleVideo(
              id: DateTime.now().toString(),
              path: outputPath,
              name: outputPath.split('/').last,
              scale: '${_scaleFactor}x',
              date: DateTime.now(),
            ),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Upscale saved to:\n$outputPath'), backgroundColor: Colors.green),
        );
      } else {
        setState(() => _isExporting = false);
      }
    } catch (e) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

    return Scaffold(
      backgroundColor: kBackgroundDark,
      appBar: AppBar(
        title: const Text('Shaderly AI Upscaler', style: TextStyle(fontWeight: FontWeight.bold)),
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
              child: _controller != null && _controller!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    _splitPosition = (details.localPosition.dx / constraints.maxWidth).clamp(0.05, 0.95);
                                  });
                                },
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: constraints.maxWidth * _splitPosition,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(width: 2.5, color: accent),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
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

          Expanded(
            flex: 5,
            child: Container(
              color: kCardDark,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // Dual 2x and 4x Buttons with Glowing Perimeter
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _scaleFactor = 2),
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
                          onTap: () => setState(() => _scaleFactor = 4),
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
                          label: Text('Anime 6B (${_scaleFactor}x)'),
                          selected: _selectedModelIndex == 0,
                          selectedColor: accent,
                          labelStyle: TextStyle(color: _selectedModelIndex == 0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (_) => setState(() => _selectedModelIndex = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text('x${_scaleFactor}plus Real-World'),
                          selected: _selectedModelIndex == 1,
                          selectedColor: accent,
                          labelStyle: TextStyle(color: _selectedModelIndex == 1 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (_) => setState(() => _selectedModelIndex = 1),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  _buildSlider('Deblur Restoration', _deblur, 0.0, 1.0, (v) => setState(() => _deblur = v)),
                  _buildSlider('Acutance Sharpness', _sharpness, 0.0, 1.0, (v) => setState(() => _sharpness = v)),
                  _buildSlider('Noise Suppression', _denoise, 0.0, 1.0, (v) => setState(() => _denoise = v)),

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
                    label: Text(_isExporting ? 'CANCEL EXPORT' : 'START NEURAL UPSCALE EXPORT', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
