import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;

void main() {
  runApp(const AERealityApp());
}

class AERealityApp extends StatelessWidget {
  const AERealityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEReality',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------- PROJECT DATA MODEL ----------
class ProjectData {
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, lookMix, vignette, splitToning;
  String aspectRatio;

  ProjectData({
    required this.videoPath,
    this.brightness = 0.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.sharpness = 0.0,
    this.gamma = 1.0,
    this.hue = 0.0,
    this.temperature = 6500.0,
    this.glowIntensity = 0.3,
    this.lookMix = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.aspectRatio = "16:9",
  });

  Map<String, dynamic> toJson() => {
    'videoPath': videoPath,
    'brightness': brightness,
    'saturation': saturation,
    'contrast': contrast,
    'sharpness': sharpness,
    'gamma': gamma,
    'hue': hue,
    'temperature': temperature,
    'glowIntensity': glowIntensity,
    'lookMix': lookMix,
    'vignette': vignette,
    'splitToning': splitToning,
    'aspectRatio': aspectRatio,
  };

  factory ProjectData.fromJson(Map<String, dynamic> json) => ProjectData(
    videoPath: json['videoPath'],
    brightness: json['brightness'] ?? 0.0,
    saturation: json['saturation'] ?? 1.0,
    contrast: json['contrast'] ?? 1.0,
    sharpness: json['sharpness'] ?? 0.0,
    gamma: json['gamma'] ?? 1.0,
    hue: json['hue'] ?? 0.0,
    temperature: json['temperature'] ?? 6500.0,
    glowIntensity: json['glowIntensity'] ?? 0.3,
    lookMix: json['lookMix'] ?? 0.0,
    vignette: json['vignette'] ?? 0.0,
    splitToning: json['splitToning'] ?? 0.0,
    aspectRatio: json['aspectRatio'] ?? "16:9",
  );
}

// ---------- HOME SCREEN ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AEReality'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _loadProject,
            tooltip: 'Load Project',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library, size: 80, color: Colors.white24),
            const SizedBox(height: 20),
            const Text('No Project Open', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectScreen()));
              },
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('New Project', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadProject,
              icon: const Icon(Icons.folder_open, color: Colors.white),
              label: const Text('Load Project', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProject() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/aereality_project.json');
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved project found'), backgroundColor: Colors.orange),
        );
        return;
      }
      final data = await file.readAsString();
      final json = jsonDecode(data);
      final project = ProjectData.fromJson(json);
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectScreen(initialProject: project),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// ---------- SETTINGS ----------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _previewScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: const Color(0xFF0A0A0A)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text('Preview Resolution', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('360p', style: TextStyle(color: Colors.white54)),
                Expanded(
                  child: Slider(
                    value: _previewScale,
                    min: 0.33,
                    max: 1.0,
                    divisions: 3,
                    activeColor: Colors.white,
                    inactiveColor: Colors.grey[800],
                    onChanged: (val) => setState(() => _previewScale = val),
                  ),
                ),
                const Text('1080p', style: TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 20),
            Text('Current: ${(_previewScale * 1080).toInt()}p', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ---------- SHADER PREVIEW PAINTER (FIXED SAMPLER INDEX) ----------
class ShaderPreviewPainter extends CustomPainter {
  final ui.Image image;
  final ui.FragmentProgram program;
  final double brightness, saturation, contrast, sharpness, gamma, hue;
  final double temperature, glowIntensity, lookMix, vignette, splitToning;

  const ShaderPreviewPainter({
    required this.image,
    required this.program,
    required this.brightness,
    required this.saturation,
    required this.contrast,
    required this.sharpness,
    required this.gamma,
    required this.hue,
    required this.temperature,
    required this.glowIntensity,
    required this.lookMix,
    required this.vignette,
    required this.splitToning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    
    // FIX: Use index 0 for sampler (matches _applyShaderToImage)
    shader.setImageSampler(0, image);
    
    // Resolution floats at 1 and 2
    shader.setFloat(1, size.width);
    shader.setFloat(2, size.height);
    
    // Sliders at 3-13
    shader.setFloat(3, brightness);
    shader.setFloat(4, saturation);
    shader.setFloat(5, contrast);
    shader.setFloat(6, sharpness);
    shader.setFloat(7, gamma);
    shader.setFloat(8, hue);
    shader.setFloat(9, temperature);
    shader.setFloat(10, glowIntensity);
    shader.setFloat(11, lookMix);
    shader.setFloat(12, vignette);
    shader.setFloat(13, splitToning);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant ShaderPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.brightness != brightness ||
        oldDelegate.saturation != saturation ||
        oldDelegate.contrast != contrast ||
        oldDelegate.sharpness != sharpness ||
        oldDelegate.gamma != gamma ||
        oldDelegate.hue != hue ||
        oldDelegate.temperature != temperature ||
        oldDelegate.glowIntensity != glowIntensity ||
        oldDelegate.lookMix != lookMix ||
        oldDelegate.vignette != vignette ||
        oldDelegate.splitToning != splitToning;
  }
}
// ---------- PROJECT SCREEN ----------
class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  const ProjectScreen({super.key, this.initialProject});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  String? _currentVideoPath;

  // Color Controls
  double _brightness = 0.0;
  double _saturation = 1.0;
  double _contrast = 1.0;
  double _sharpness = 0.0;
  double _gamma = 1.0;
  double _hue = 0.0;
  double _temperature = 6500.0;
  double _glowIntensity = 0.3;
  double _lookMix = 0.0;
  double _vignette = 0.0;
  double _splitToning = 0.0;

  String _selectedRatio = "16:9";
  late TabController _tabController;
  VoidCallback _listener = () {};
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialProject != null) {
      final p = widget.initialProject!;
      _brightness = p.brightness;
      _saturation = p.saturation;
      _contrast = p.contrast;
      _sharpness = p.sharpness;
      _gamma = p.gamma;
      _hue = p.hue;
      _temperature = p.temperature;
      _glowIntensity = p.glowIntensity;
      _lookMix = p.lookMix;
      _vignette = p.vignette;
      _splitToning = p.splitToning;
      _selectedRatio = p.aspectRatio;
      _loadVideo(p.videoPath);
    }
  }

  Future<void> _loadVideo(String path) async {
    setState(() {
      _controller?.removeListener(_listener);
      _controller?.dispose();
      _currentVideoPath = path;
      _controller = VideoPlayerController.file(File(path))
        ..initialize().then((_) {
          setState(() {});
          _listener = () { if (mounted) setState(() {}); };
          _controller!.addListener(_listener);
          _controller!.play();
          _isPlaying = true;
        });
    });
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      await _loadVideo(result.files.single.path!);
    }
  }

  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case 'Gojo Edit':
          _brightness = -0.05; _saturation = 1.5; _contrast = 1.5; _sharpness = 0.6;
          _gamma = 0.9; _hue = -8.0; _temperature = 4800; _glowIntensity = 0.7;
          _vignette = 0.4; _splitToning = 0.3;
          break;
        case 'Magic Bullet':
          _brightness = 0.1; _saturation = 1.4; _contrast = 1.2; _sharpness = 0.3;
          _gamma = 1.0; _hue = 5.0; _temperature = 6500; _glowIntensity = 0.6;
          _vignette = 0.1; _splitToning = 0.0;
          break;
        case 'Teal & Orange':
          _brightness = 0.0; _saturation = 1.2; _contrast = 1.3; _sharpness = 0.2;
          _gamma = 0.9; _hue = -10.0; _temperature = 5500; _glowIntensity = 0.2;
          _vignette = 0.0; _splitToning = 0.2;
          break;
        default: break;
      }
    });
  }

  // ---------- SAVE PROJECT ----------
  Future<void> _saveCurrentProject() async {
    if (_currentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import a video first'), backgroundColor: Colors.orange));
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/aereality_project.json');
      final project = ProjectData(
        videoPath: _currentVideoPath!,
        brightness: _brightness, saturation: _saturation, contrast: _contrast,
        sharpness: _sharpness, gamma: _gamma, hue: _hue, temperature: _temperature,
        glowIntensity: _glowIntensity, lookMix: _lookMix, vignette: _vignette,
        splitToning: _splitToning, aspectRatio: _selectedRatio,
      );
      await file.writeAsString(jsonEncode(project.toJson()));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project Saved!'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red));
    }
  }

  // ---------- ASPECT RATIO ----------
  double _getAspectRatioValue(String ratio) {
    switch (ratio) {
      case "4:5": return 4 / 5;
      case "16:9": return 16 / 9;
      case "1:1": return 1 / 1;
      default: return 16 / 9;
    }
  }
  void _showRatioSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => SafeArea(
        child: Wrap(
          children: ["4:5", "16:9", "1:1"].map((ratio) => ListTile(
            title: Text(ratio, style: const TextStyle(color: Colors.white)),
            trailing: _selectedRatio == ratio ? const Icon(Icons.check, color: Colors.cyanAccent) : null,
            onTap: () { setState(() => _selectedRatio = ratio); Navigator.pop(context); },
          )).toList(),
        ),
      ),
    );
  }
    // ---------- PREVIEW FRAME (FIXED: captures stdout + stderr) ----------
  Future<void> _previewFrame() async {
    if (_controller == null || !_controller!.value.isInitialized || _currentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import a video first'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isPreviewing = true);
    try {
      final timestamp = _controller!.value.position.inSeconds;
      final dir = await getTemporaryDirectory();
      final outputPath = '${dir.path}/preview_frame_$timestamp.jpg';
      
      final cmd = '-ss $timestamp -i "${_currentVideoPath!}" -vframes 1 -q:v 2 "$outputPath"';
      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();
      
      if (!ReturnCode.isSuccess(returnCode)) {
        // Get BOTH output and logs
        final output = await session.getOutput() ?? "No stdout";
        final allLogs = await session.getAllLogs();
        String logMessages = "";
        if (allLogs != null && allLogs.isNotEmpty) {
          logMessages = allLogs.map((log) => log.getMessage()).join("\n");
        }
        final combined = "Stdout: $output\nLogs: $logMessages";
        throw Exception('FFmpeg error:\n$combined');
      }

      final file = File(outputPath);
      if (!await file.exists()) {
        throw Exception('Frame not saved (file missing)');
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');
      final uiImage = await _convertToUiImage(image);
      if (uiImage == null) throw Exception('Failed to convert to UI image');
      
      final program = await ui.FragmentProgram.fromAsset('shaders/aereality_core.frag');
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: ShaderPreviewPainter(
                      image: uiImage, program: program,
                      brightness: _brightness, saturation: _saturation, contrast: _contrast,
                      sharpness: _sharpness, gamma: _gamma, hue: _hue,
                      temperature: _temperature, glowIntensity: _glowIntensity, lookMix: _lookMix,
                      vignette: _vignette, splitToning: _splitToning,
                    ),
                    size: Size(uiImage.width.toDouble(), uiImage.height.toDouble()),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Frame at ${timestamp}s', style: const TextStyle(color: Colors.white54)),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Close Preview')),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isPreviewing = false);
    }
  }

  Future<ui.Image?> _convertToUiImage(img.Image image) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(img.encodePng(image), completer.complete);
    return completer.future;
  }

  // ---------- FULL EXPORT (with zero-frame check) ----------
  Future<void> _exportVideo(String resolution, String fps, String bitrate) async {
    if (_controller == null || !_controller!.value.isInitialized || _currentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import a video first'), backgroundColor: Colors.orange));
      return;
    }

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Initializing...');
    final etaNotifier = ValueNotifier<String>('--:--');
    final stopwatch = Stopwatch();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Exporting...', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (_, progress, __) => LinearProgressIndicator(value: progress, color: Colors.white),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (_, status, __) => Text(status, style: const TextStyle(color: Colors.white70)),
            ),
            ValueListenableBuilder<String>(
              valueListenable: etaNotifier,
              builder: (_, eta, __) => Text('Estimated time remaining: $eta', style: const TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final framesDir = Directory('${dir.path}/export_frames');
      final processedDir = Directory('${dir.path}/export_processed');
      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      if (await processedDir.exists()) await processedDir.delete(recursive: true);
      await framesDir.create();
      await processedDir.create();

      statusNotifier.value = 'Extracting frames...';
      final extractCmd = '-i "${_currentVideoPath!}" -vsync 0 -f image2 "${framesDir.path}/frame_%05d.png"';
      final extractSession = await FFmpegKit.execute(extractCmd);
      final extractReturnCode = await extractSession.getReturnCode();
      if (!ReturnCode.isSuccess(extractReturnCode)) {
        final err = await extractSession.getOutput();
        throw Exception('Extract failed: ${err ?? "Unknown error"}');
      }

      final frameFiles = await framesDir.list().toList();
      // --- CHECK FOR ZERO FRAMES ---
      if (frameFiles.isEmpty) {
        throw Exception('No frames extracted. The video may be corrupted, unsupported, or the path is incorrect.');
      }

      final totalFrames = frameFiles.length;
      int processedFrames = 0;
      stopwatch.start();

      final program = await ui.FragmentProgram.fromAsset('shaders/aereality_core.frag');
      const batchSize = 10;

      // ---------- UPDATED FRAME PROCESSING LOOP WITH CHECKS ----------
      for (int i = 0; i < totalFrames; i += batchSize) {
        final batch = frameFiles.skip(i).take(batchSize).toList();
        await Future.wait(batch.map((file) async {
          if (file is! File) return;
          try {
            final bytes = await file.readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded == null) {
              throw Exception('Failed to decode frame: ${file.path}');
            }
            final uiImage = await _convertToUiImage(decoded);
            if (uiImage == null) {
              throw Exception('Failed to convert frame to UI image: ${file.path}');
            }
            final processed = await _applyShaderToImage(
              uiImage, program,
              brightness: _brightness, saturation: _saturation, contrast: _contrast,
              sharpness: _sharpness, gamma: _gamma, hue: _hue,
              temperature: _temperature, glowIntensity: _glowIntensity, lookMix: _lookMix,
              vignette: _vignette, splitToning: _splitToning,
            );
            if (processed == null) {
              throw Exception('_applyShaderToImage returned null for frame: ${file.path}');
            }
            
            final pngBytes = await processed.toByteData(format: ui.ImageByteFormat.png);
            if (pngBytes == null) {
              throw Exception('Failed to get PNG bytes for frame: ${file.path}');
            }
            
            final outputFile = File('${processedDir.path}/${file.path.split('/').last}');
            await outputFile.writeAsBytes(pngBytes.buffer.asUint8List());
            
            // Verify the file was written
            if (!await outputFile.exists()) {
              throw Exception('Failed to write processed frame to: ${outputFile.path}');
            }
            
            processedFrames++;
            final p = processedFrames / totalFrames;
            progressNotifier.value = p;
            statusNotifier.value = 'Processing frame $processedFrames of $totalFrames';
            if (stopwatch.elapsed.inSeconds > 5 && processedFrames > 0) {
              final totalSec = (totalFrames / processedFrames) * stopwatch.elapsed.inSeconds;
              final remaining = totalSec - stopwatch.elapsed.inSeconds;
              final mins = remaining ~/ 60;
              final secs = remaining % 60;
              etaNotifier.value = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
            }
          } catch (e) {
            throw Exception('Frame processing failed at $processedFrames: $e');
          }
        }));
      }
      // ---------- END OF UPDATED LOOP ----------

      stopwatch.stop();

      statusNotifier.value = 'Encoding video...';
      final targetFps = int.parse(fps.replaceAll('fps', ''));
      final silentOutputPath = '${dir.path}/silent_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      // Try libx264 first
      var encodeCmd = '-framerate $targetFps -i "${processedDir.path}/frame_%05d.png" ' +
                      '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p "$silentOutputPath"';
      var encodeSession = await FFmpegKit.execute(encodeCmd);
      var encodeReturnCode = await encodeSession.getReturnCode();

      // If libx264 fails, fallback to mpeg4
      if (!ReturnCode.isSuccess(encodeReturnCode)) {
        statusNotifier.value = 'Retrying with mpeg4...';
        final fallbackCmd = '-framerate $targetFps -i "${processedDir.path}/frame_%05d.png" ' +
                            '-c:v mpeg4 -q:v 5 -pix_fmt yuv420p "$silentOutputPath"';
        encodeSession = await FFmpegKit.execute(fallbackCmd);
        encodeReturnCode = await encodeSession.getReturnCode();
      }

      // Now read the actual error if it still fails
      if (!ReturnCode.isSuccess(encodeReturnCode)) {
        final combined = await encodeSession.getOutput() ?? "No output";
        final errorSnippet = combined.length > 500 
            ? "...${combined.substring(combined.length - 500)}" 
            : combined;
        throw Exception('Encode failed:\n$errorSnippet');
      }

      // ---------- EXTRACT AUDIO ----------
      statusNotifier.value = 'Extracting audio...';
      final audioPath = '${dir.path}/extracted_audio.aac';
      final audioCmd = '-i "${_currentVideoPath!}" -vn -acodec copy "$audioPath"';
      final audioSession = await FFmpegKit.execute(audioCmd);
      if (!ReturnCode.isSuccess(await audioSession.getReturnCode())) {
        print('Audio extraction skipped');
      }

      // ---------- MUX AUDIO + VIDEO ----------
      statusNotifier.value = 'Muxing audio and video...';
      final finalOutputPath = '${dir.path}/final_export_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final muxCmd = '-i "$silentOutputPath" -i "$audioPath" -c copy -shortest "$finalOutputPath"';
      final muxSession = await FFmpegKit.execute(muxCmd);
      if (!ReturnCode.isSuccess(await muxSession.getReturnCode())) {
        await File(silentOutputPath).copy(File(finalOutputPath).path);
      }

      // ---------- SAVE TO DOWNLOADS FOLDER ----------
      final downloadsDir = Directory('/storage/emulated/0/Download/');
      if (!await downloadsDir.exists()) {
        final docsDir = await getApplicationDocumentsDirectory();
        final finalFile = File('${docsDir.path}/AEReality_Export_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await File(finalOutputPath).copy(finalFile.path);
        await framesDir.delete(recursive: true);
        await processedDir.delete(recursive: true);
        try { await File(audioPath).delete(); } catch (_) {}
        try { await File(silentOutputPath).delete(); } catch (_) {}
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('⚠️ Saved to app folder: ${finalFile.path}'), backgroundColor: Colors.orange, duration: const Duration(seconds: 5)),
          );
        }
        return;
      }

      final finalFile = File('${downloadsDir.path}/AEReality_Export_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await File(finalOutputPath).copy(finalFile.path);

      await framesDir.delete(recursive: true);
      await processedDir.delete(recursive: true);
      try { await File(audioPath).delete(); } catch (_) {}
      try { await File(silentOutputPath).delete(); } catch (_) {}

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Saved to Downloads: ${finalFile.path}'), backgroundColor: Colors.green, duration: const Duration(seconds: 5)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export Error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 10)),
        );
      }
    }
  }

  // ---------- APPLY SHADER TO IMAGE (FIXED SAMPLER INDEX) ----------
  Future<ui.Image?> _applyShaderToImage(ui.Image image, ui.FragmentProgram program, {
    required double brightness, required double saturation, required double contrast,
    required double sharpness, required double gamma, required double hue,
    required double temperature, required double glowIntensity, required double lookMix,
    required double vignette, required double splitToning,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final shader = program.fragmentShader();
    
    // FIX: Use index 0 for sampler (instead of 2)
    shader.setImageSampler(0, image);
    
    // Resolution floats at 1 and 2
    shader.setFloat(1, size.width);
    shader.setFloat(2, size.height);
    
    // Sliders at 3-13
    shader.setFloat(3, brightness);
    shader.setFloat(4, saturation);
    shader.setFloat(5, contrast);
    shader.setFloat(6, sharpness);
    shader.setFloat(7, gamma);
    shader.setFloat(8, hue);
    shader.setFloat(9, temperature);
    shader.setFloat(10, glowIntensity);
    shader.setFloat(11, lookMix);
    shader.setFloat(12, vignette);
    shader.setFloat(13, splitToning);
    
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    final picture = recorder.endRecording();
    return picture.toImage(image.width, image.height);
  }

  // ---------- EXPORT DIALOG ----------
  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            String selectedRes = '1080p';
            String selectedFps = '60fps';
            String selectedBit = '35 Mbps';
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Export Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  const Text('Resolution', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['720p', '1080p', '2K'].map((res) => ChoiceChip(
                      label: Text(res),
                      selected: selectedRes == res,
                      selectedColor: Colors.white,
                      labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() => selectedRes = res),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Frame Rate', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['30fps', '60fps', '90fps'].map((fps) => ChoiceChip(
                      label: Text(fps),
                      selected: selectedFps == fps,
                      selectedColor: Colors.white,
                      labelStyle: TextStyle(color: selectedFps == fps ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() => selectedFps = fps),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Bitrate', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['15 Mbps', '35 Mbps', '50 Mbps'].map((bit) => ChoiceChip(
                      label: Text(bit),
                      selected: selectedBit == bit,
                      selectedColor: Colors.white,
                      labelStyle: TextStyle(color: selectedBit == bit ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() => selectedBit = bit),
                    )).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _exportVideo(selectedRes, selectedFps, selectedBit);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('RENDER VIDEO', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Full 32-bit export may take several minutes.', style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            );
          },
        );
      },
    );
  }
    // ---------- BUILD METHOD ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project'),
        backgroundColor: const Color(0xFF0A0A0A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveCurrentProject, tooltip: 'Save Project'),
          IconButton(icon: const Icon(Icons.aspect_ratio), onPressed: _showRatioSelector, tooltip: 'Aspect Ratio'),
          IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickVideo, tooltip: 'Import Video'),
        ],
      ),
      body: Column(
        children: [
          // ---------- PREVIEW (RAW VIDEO) ----------
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black,
              child: Center(
                child: _controller != null && _controller!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _getAspectRatioValue(_selectedRatio),
                        child: VideoPlayer(_controller!),
                      )
                    : Container(
                        color: const Color(0xFF1A1A1A),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_circle_outline, size: 60, color: Colors.white24),
                              SizedBox(height: 8),
                              Text('Tap Import to add video', style: TextStyle(color: Colors.white38)),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          // ---------- TIMELINE (FRAME-ACCURATE) ----------
          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: _controller != null && _controller!.value.isInitialized
                      ? () => setState(() {
                          if (_controller!.value.isPlaying) {
                            _controller!.pause();
                            _isPlaying = false;
                          } else {
                            _controller!.play();
                            _isPlaying = true;
                          }
                        })
                      : null,
                ),
                Expanded(
                  child: Slider(
                    value: _controller != null && _controller!.value.isInitialized
                        ? _controller!.value.position.inSeconds.toDouble()
                        : 0.0,
                    min: 0,
                    max: _controller != null && _controller!.value.isInitialized
                        ? _controller!.value.duration.inSeconds.toDouble()
                        : 1.0,
                    activeColor: Colors.white,
                    inactiveColor: Colors.grey[800],
                    onChanged: (val) {
                      if (_controller != null && _controller!.value.isInitialized) {
                        _controller!.seekTo(Duration(milliseconds: (val * 1000).round()));
                      }
                    },
                  ),
                ),
                Text(
                  _controller != null && _controller!.value.isInitialized
                      ? '${_controller!.value.position.inSeconds ~/ 60}:${(_controller!.value.position.inSeconds % 60).toString().padLeft(2, '0')}'
                      : '--:--',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
          // ---------- BOTTOM TOOLBAR ----------
          Container(
            color: const Color(0xFF141414),
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(icon: Icon(Icons.tune), text: 'Adjust'),
                    Tab(icon: Icon(Icons.auto_awesome), text: 'Presets'),
                    Tab(icon: Icon(Icons.save_alt), text: 'Export'),
                  ],
                ),
                SizedBox(
                  height: 190,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // ADJUST
                      ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _slider('Bright', -1.0, 1.0, _brightness, (v) => setState(() => _brightness = v)),
                          _slider('Sat', 0.0, 3.0, _saturation, (v) => setState(() => _saturation = v)),
                          _slider('Contrast', 0.0, 2.0, _contrast, (v) => setState(() => _contrast = v)),
                          _slider('Sharp', 0.0, 5.0, _sharpness, (v) => setState(() => _sharpness = v)),
                          _slider('Gamma', 0.1, 2.5, _gamma, (v) => setState(() => _gamma = v)),
                          _slider('Hue', -180, 180, _hue, (v) => setState(() => _hue = v)),
                          _slider('Temp', 2000, 12000, _temperature, (v) => setState(() => _temperature = v)),
                          _slider('Glow', 0.0, 1.0, _glowIntensity, (v) => setState(() => _glowIntensity = v)),
                          _slider('Vignette', 0.0, 1.0, _vignette, (v) => setState(() => _vignette = v)),
                          _slider('Split Tone', 0.0, 1.0, _splitToning, (v) => setState(() => _splitToning = v)),
                        ],
                      ),
                      // PRESETS
                      GridView.count(
                        crossAxisCount: 3,
                        padding: const EdgeInsets.all(8),
                        children: ['Gojo Edit', 'Magic Bullet', 'Teal & Orange', 'Film Grain', 'Vintage', 'Cinematic'].map((name) {
                          return GestureDetector(
                            onTap: () => _applyPreset(name),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[800]!),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.image, color: Colors.white24, size: 30),
                                  const SizedBox(height: 4),
                                  Text(name, style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      // EXPORT
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isPreviewing ? null : _previewFrame,
                                icon: const Icon(Icons.image, color: Colors.black),
                                label: Text(_isPreviewing ? 'Loading...' : 'Preview Frame'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyanAccent,
                                  foregroundColor: Colors.black,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _showExportSheet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                                ),
                                child: const Text('EXPORT VIDEO', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('Preview applies shader to the frame on your timeline',
                            style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double min, double max, double val, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: Colors.white,
            inactiveColor: Colors.grey[800],
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(val.toStringAsFixed(1), style: const TextStyle(color: Colors.white38))),
      ],
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    super.dispose();
  }
}
