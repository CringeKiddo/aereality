import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:ffmpeg_kit_extended_flutter/return_code.dart';

import 'constants.dart';
import 'models.dart';
import 'main.dart';

class RsmbScreen extends StatefulWidget {
  final String? initialMediaPath;

  const RsmbScreen({Key? key, this.initialMediaPath}) : super(key: key);

  @override
  State<RsmbScreen> createState() => _RsmbScreenState();
}

class _RsmbScreenState extends State<RsmbScreen> {
  String? _videoPath;
  VideoPlayerController? _controller;
  bool _isPlaying = false;

  double _blurIntensity = 0.85;
  double _smearLength = 1.20;
  double _lineArtProtection = 0.75;
  int _shutterSteps = 8;

  bool _isProcessing = false;
  String _statusText = 'Ready';

  double _detectedFps = 30.0;
  int _videoWidth = 1920;
  int _videoHeight = 1080;

  @override
  void initState() {
    super.initState();
    if (widget.initialMediaPath != null && widget.initialMediaPath!.isNotEmpty) {
      _loadVideo(widget.initialMediaPath!);
    }
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final p = result.files.single.path!;
      final ext = p.split('.').last.toLowerCase();
      if (['mp4', 'mov', 'mkv', 'webm'].contains(ext)) {
        _loadVideo(p);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a valid video.')),
        );
      }
    }
  }

  Future<void> _loadVideo(String path) async {
    _controller?.pause();
    await _controller?.dispose();

    setState(() {
      _videoPath = path;
      _statusText = 'Loading video stream...';
    });

    _controller = VideoPlayerController.file(File(path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _videoWidth = _controller!.value.size.width.toInt();
          _videoHeight = _controller!.value.size.height.toInt();
          _isPlaying = true;
          _statusText = 'Ready (${_videoWidth}x${_videoHeight})';
        });
        _controller!.play();
        _controller!.setLooping(true);
      });

    try {
      final probeResult = await FFmpegKit.execute('-hide_banner -i "$path"');
      final logs = await probeResult.getLogsAsString() ?? '';
      final fpsMatch = RegExp(r'(\d+(?:\.\d+)?)\s*fps').firstMatch(logs);
      if (fpsMatch != null) {
        _detectedFps = double.tryParse(fpsMatch.group(1)!) ?? 30.0;
      }
    } catch (_) {}
  }

  Future<void> _processMotionBlur({required bool sendToTimeline}) async {
    if (_videoPath == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Rendering optical motion smear & preserving audio...';
    });

    _controller?.pause();

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = _videoPath!.split('.').last.toLowerCase();
      final outputPath = '${tempDir.path}/rsmb_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final int steps = _shutterSteps;
      final List<String> weightsList = List.filled(steps, '1');
      final String weightsStr = weightsList.join(' ');

      // Preserves original audio stream (-c:a copy) and uses safe scale filter
      final ffmpegCmd = '-y -i "$_videoPath" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,tmix=frames=$steps:weights=$weightsStr,format=yuv420p" -r $_detectedFps -c:v libx264 -preset veryfast -crf 17 -c:a copy -movflags +faststart "$outputPath"';

      final session = await FFmpegKit.execute(ffmpegCmd);
      final returnCode = await session.getReturnCode();

      // FIXED: Proper ReturnCode check preventing red screen crash
      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _isProcessing = false;
          _statusText = 'Complete!';
        });

        if (sendToTimeline && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ProjectScreen(
                initialProject: ProjectData(
                  mediaPath: outputPath,
                  isImage: false,
                  aspectRatio: _videoWidth >= _videoHeight ? '16:9' : '9:16',
                  layers: [
                    AdjustmentLayer(
                      id: 'rsmb_base',
                      name: 'RSMB Smear Master',
                      blendMode: LayerBlendMode.normal,
                    ),
                  ],
                ),
                projectName: 'RSMB Master Grade',
              ),
            ),
          );
        } else {
          _loadVideo(outputPath);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('RSMB Rendered! Audio preserved & ready.')),
          );
        }
      } else {
        final logs = await session.getLogsAsString();
        throw Exception('Render failed: $logs');
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = 'Error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RSMB Render Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

    return Scaffold(
      backgroundColor: kBackgroundDark,
      appBar: AppBar(
        title: const Text('ReelSmart Motion Blur Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'Load Video',
            onPressed: _pickVideo,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
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
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            backgroundColor: Colors.black54,
                            child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: accent),
                            onPressed: () {
                              setState(() {
                                if (_controller!.value.isPlaying) {
                                  _controller!.pause();
                                  _isPlaying = false;
                                } else {
                                  _controller!.play();
                                  _isPlaying = true;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.blur_linear_rounded, size: 52, color: accent.withOpacity(0.5)),
                          const SizedBox(height: 10),
                          const Text('No video loaded', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _pickVideo,
                            icon: const Icon(Icons.video_collection_rounded, size: 16),
                            label: const Text('LOAD VIDEO'),
                            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          if (_isProcessing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF1B1B26),
              child: Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(_statusText, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          Expanded(
            flex: 5,
            child: Container(
              color: kCardDark,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('RSMB OPTICAL SMEAR CONTROLS', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      Text('${_detectedFps.toStringAsFixed(0)} FPS (ORIGINAL)', style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSlider('Smear Blur Intensity', _blurIntensity, 0.1, 2.0, (v) => setState(() => _blurIntensity = v)),
                  _buildSlider('Motion Streak Length', _smearLength, 0.5, 3.0, (v) => setState(() => _smearLength = v)),
                  _buildSlider('Line-Art Edge Protection', _lineArtProtection, 0.0, 1.0, (v) => setState(() => _lineArtProtection = v)),

                  const SizedBox(height: 10),
                  const Text('SHUTTER SAMPLE STEPS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [4, 6, 8, 12].map((steps) {
                      final isSel = _shutterSteps == steps;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text('${steps}x'),
                            selected: isSel,
                            selectedColor: accent,
                            backgroundColor: const Color(0xFF161622),
                            labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            onSelected: (_) => setState(() => _shutterSteps = steps),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isProcessing || _videoPath == null ? null : () => _processMotionBlur(sendToTimeline: false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: accent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('PREVIEW SMEAR', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing || _videoPath == null ? null : () => _processMotionBlur(sendToTimeline: true),
                          icon: const Icon(Icons.send_rounded, size: 16, color: Colors.black),
                          label: const Text('PASTE TO TIMELINE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(val.toStringAsFixed(2), style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: accent,
              thumbColor: accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: val.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
