import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
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
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen()));
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
// ---------- PROJECT SETUP SCREEN ----------
class ProjectSetupScreen extends StatefulWidget {
  const ProjectSetupScreen({super.key});

  @override
  State<ProjectSetupScreen> createState() => _ProjectSetupScreenState();
}

class _ProjectSetupScreenState extends State<ProjectSetupScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _tiltAnimation;

  String _projectName = 'Untitled Project';

  String _selectedResolution = '1080p';
  String _selectedFps = '60fps';
  String _selectedBitrate = '35 Mbps';

  bool _isResExpanded = false;
  bool _isFpsExpanded = false;
  bool _isBitrateExpanded = false;

  final List<String> _resolutions = ['720p', '1080p', '2K'];
  final List<String> _fpsOptions = ['30fps', '60fps', '90fps'];
  final List<String> _bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _tiltAnimation = Tween<double>(begin: 0.0, end: 0.08).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _createProject() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    String? videoPath;
    if (result != null) {
      videoPath = result.files.single.path;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectScreen(
          initialResolution: _selectedResolution,
          initialFps: _selectedFps,
          initialBitrate: _selectedBitrate,
          initialVideoPath: videoPath,
          projectName: _projectName,
        ),
      ),
    );
  }

  Widget _buildSlantedBox(String title, List<String> options, String selectedValue,
      ValueChanged<String> onSelected, bool isExpanded, VoidCallback onToggle) {
    return AnimatedBuilder(
      animation: _tiltAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _tiltAnimation.value,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[800]!),
            ),
            child: ExpansionTile(
              trailing: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70,
              ),
              title: Row(
                children: [
                  Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      selectedValue,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              initiallyExpanded: isExpanded,
              onExpansionChanged: (val) => onToggle(),
              children: options.map((opt) {
                return ListTile(
                  title: Text(opt, style: const TextStyle(color: Colors.white70)),
                  trailing: selectedValue == opt
                      ? const Icon(Icons.check, color: Colors.cyanAccent, size: 18)
                      : null,
                  onTap: () {
                    onSelected(opt);
                    onToggle();
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Project'),
        backgroundColor: const Color(0xFF0A0A0A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PROJECT NAME', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 4),
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Enter project name',
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
                onChanged: (val) => _projectName = val.isNotEmpty ? val : 'Untitled Project',
                controller: TextEditingController(text: _projectName),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildSlantedBox(
                      'Quality',
                      _resolutions,
                      _selectedResolution,
                      (val) => setState(() => _selectedResolution = val),
                      _isResExpanded,
                      () => setState(() => _isResExpanded = !_isResExpanded),
                    ),
                    _buildSlantedBox(
                      'Framerate',
                      _fpsOptions,
                      _selectedFps,
                      (val) => setState(() => _selectedFps = val),
                      _isFpsExpanded,
                      () => setState(() => _isFpsExpanded = !_isFpsExpanded),
                    ),
                    _buildSlantedBox(
                      'Bitrate',
                      _bitrateOptions,
                      _selectedBitrate,
                      (val) => setState(() => _selectedBitrate = val),
                      _isBitrateExpanded,
                      () => setState(() => _isBitrateExpanded = !_isBitrateExpanded),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _createProject,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('CREATE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
// ---------- PROJECT SCREEN ----------
class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  final String? initialResolution;
  final String? initialFps;
  final String? initialBitrate;
  final String? initialVideoPath;
  final String? projectName;

  const ProjectScreen({
    super.key,
    this.initialProject,
    this.initialResolution,
    this.initialFps,
    this.initialBitrate,
    this.initialVideoPath,
    this.projectName,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  String? _currentVideoPath;

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

  late String _projectResolution;
  late String _projectFps;
  late String _projectBitrate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _projectResolution = widget.initialResolution ?? '1080p';
    _projectFps = widget.initialFps ?? '60fps';
    _projectBitrate = widget.initialBitrate ?? '35 Mbps';

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
    } else if (widget.initialVideoPath != null) {
      _loadVideo(widget.initialVideoPath!);
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

  // ---------- PREVIEW FRAME (CPU-BASED) ----------
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
      
      final gradedImage = _applyGradingToImage(image);
      
      final uiImage = await _convertToUiImage(gradedImage);
      if (uiImage == null) throw Exception('Failed to convert to UI image');
      if (uiImage.width == 0 || uiImage.height == 0) {
        throw Exception('Converted image has zero size');
      }
      
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
                  child: RawImage(
                    image: uiImage,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Frame at ${timestamp}s (CPU Graded)', style: const TextStyle(color: Colors.white54)),
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

  // ---------- CONVERT FUNCTION (for preview) ----------
  Future<ui.Image?> _convertToUiImage(img.Image image) async {
    if (image.width == 0 || image.height == 0) {
      throw Exception('Invalid image dimensions: ${image.width}x${image.height}');
    }
    try {
      final pngBytes = img.encodePng(image);
      if (pngBytes.isEmpty) throw Exception('PNG encoding produced empty bytes');
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(pngBytes, (ui.Image result) {
        completer.complete(result);
      });
      final uiImage = await completer.future;
      if (uiImage != null && uiImage.width > 0 && uiImage.height > 0) {
        return uiImage;
      } else {
        throw Exception('Decoded image is null or zero size');
      }
    } catch (e) {
      debugPrint('❌ PNG conversion failed: $e');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final redPaint = Paint()..color = const Color(0xFFFF0000);
      canvas.drawRect(Offset.zero & size, redPaint);
      final picture = recorder.endRecording();
      return picture.toImage(image.width, image.height);
    }
  }
    // ---------- FULL CPU GRADING (WITH BOUNDS SAFETY) ----------
  img.Image _applyGradingToImage(img.Image image) {
    Uint8List data = image.getBytes();
    int w = image.width, h = image.height;
    int len = data.length;

    // Safe pixel accessors – clamp to valid range
    int getR(int x, int y) {
      x = x.clamp(0, w - 1);
      y = y.clamp(0, h - 1);
      int idx = (y * w + x) * 4;
      return data[idx];
    }
    int getG(int x, int y) {
      x = x.clamp(0, w - 1);
      y = y.clamp(0, h - 1);
      int idx = (y * w + x) * 4;
      return data[idx + 1];
    }
    int getB(int x, int y) {
      x = x.clamp(0, w - 1);
      y = y.clamp(0, h - 1);
      int idx = (y * w + x) * 4;
      return data[idx + 2];
    }
    void setRGB(int x, int y, int r, int g, int b) {
      x = x.clamp(0, w - 1);
      y = y.clamp(0, h - 1);
      int idx = (y * w + x) * 4;
      if (idx + 2 >= len) return; // safety guard
      data[idx] = r.clamp(0, 255);
      data[idx + 1] = g.clamp(0, 255);
      data[idx + 2] = b.clamp(0, 255);
    }

    // 1. SHARPENING
    if (_sharpness > 0) {
      Uint8List sharpData = Uint8List.fromList(data);
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          int idx = (y * w + x) * 4;
          int r = data[idx], g = data[idx + 1], b = data[idx + 2];
          int rL = data[(y * w + (x - 1)) * 4];
          int rR = data[(y * w + (x + 1)) * 4];
          int rU = data[((y - 1) * w + x) * 4];
          int rD = data[((y + 1) * w + x) * 4];
          int gL = data[(y * w + (x - 1)) * 4 + 1];
          int gR = data[(y * w + (x + 1)) * 4 + 1];
          int gU = data[((y - 1) * w + x) * 4 + 1];
          int gD = data[((y + 1) * w + x) * 4 + 1];
          int bL = data[(y * w + (x - 1)) * 4 + 2];
          int bR = data[(y * w + (x + 1)) * 4 + 2];
          int bU = data[((y - 1) * w + x) * 4 + 2];
          int bD = data[((y + 1) * w + x) * 4 + 2];
          int rSharp = r - ((rL + rR + rU + rD) ~/ 4);
          int gSharp = g - ((gL + gR + gU + gD) ~/ 4);
          int bSharp = b - ((bL + bR + bU + bD) ~/ 4);
          r = (r + (_sharpness * rSharp * 0.15).toInt()).clamp(0, 255);
          g = (g + (_sharpness * gSharp * 0.15).toInt()).clamp(0, 255);
          b = (b + (_sharpness * bSharp * 0.15).toInt()).clamp(0, 255);
          sharpData[idx] = r;
          sharpData[idx + 1] = g;
          sharpData[idx + 2] = b;
        }
      }
      data = sharpData;
    }

    // 2. GLOW
    if (_glowIntensity > 0) {
      Uint8List glowData = Uint8List.fromList(data);
      int radius = 1;
      for (int y = radius; y < h - radius; y++) {
        for (int x = radius; x < w - radius; x++) {
          double lumaSum = 0.0;
          for (int ky = -radius; ky <= radius; ky++) {
            for (int kx = -radius; kx <= radius; kx++) {
              int idx = ((y + ky) * w + (x + kx)) * 4;
              double rr = data[idx] / 255.0;
              double gg = data[idx + 1] / 255.0;
              double bb = data[idx + 2] / 255.0;
              lumaSum += 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
            }
          }
          double avgLuma = lumaSum / 9.0;
          double glowMask = ((avgLuma - 0.3) / 0.5).clamp(0.0, 1.0);
          double glowAmount = glowMask * _glowIntensity * 0.6;
          int idx = (y * w + x) * 4;
          int r = data[idx], g = data[idx + 1], b = data[idx + 2];
          r = (r + glowAmount * avgLuma * 255).toInt().clamp(0, 255);
          g = (g + glowAmount * avgLuma * 255).toInt().clamp(0, 255);
          b = (b + glowAmount * avgLuma * 255).toInt().clamp(0, 255);
          glowData[idx] = r;
          glowData[idx + 1] = g;
          glowData[idx + 2] = b;
        }
      }
      data = glowData;
    }

    // 3. TEMPERATURE
    if (_temperature != 6500.0) {
      double t = ((_temperature - 2000.0) / 10000.0).clamp(0.0, 1.0);
      double rGain = 1.0 + (t * 0.3);
      double gGain = 1.0 + (t * 0.1) - ((1.0 - t) * 0.1);
      double bGain = 1.0 + ((1.0 - t) * 0.3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          int r = (data[idx] * rGain).toInt().clamp(0, 255);
          int g = (data[idx + 1] * gGain).toInt().clamp(0, 255);
          int b = (data[idx + 2] * bGain).toInt().clamp(0, 255);
          data[idx] = r;
          data[idx + 1] = g;
          data[idx + 2] = b;
        }
      }
    }

    // 4. HUE
    if (_hue != 0.0) {
      double hueShift = _hue / 360.0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          double r = data[idx] / 255.0;
          double g = data[idx + 1] / 255.0;
          double b = data[idx + 2] / 255.0;
          double max = r > g ? (r > b ? r : b) : (g > b ? g : b);
          double min = r < g ? (r < b ? r : b) : (g < b ? g : b);
          double h = 0, s = 0, v = max;
          double delta = max - min;
          if (delta != 0) {
            s = delta / max;
            if (r == max) h = (g - b) / delta + (g < b ? 6 : 0);
            else if (g == max) h = (b - r) / delta + 2;
            else h = (r - g) / delta + 4;
            h /= 6;
          }
          h = (h + hueShift) % 1.0;
          if (h < 0) h += 1.0;
          if (s == 0) {
            r = g = b = v;
          } else {
            double h6 = h * 6;
            int hi = h6.floor();
            double f = h6 - hi;
            double pv = v * (1 - s);
            double q = v * (1 - f * s);
            double t = v * (1 - (1 - f) * s);
            switch (hi) {
              case 0: r = v; g = t; b = pv; break;
              case 1: r = q; g = v; b = pv; break;
              case 2: r = pv; g = v; b = t; break;
              case 3: r = pv; g = q; b = v; break;
              case 4: r = t; g = pv; b = v; break;
              case 5: r = v; g = pv; b = q; break;
              default: r = v; g = t; b = pv; break;
            }
          }
          data[idx] = (r * 255).toInt().clamp(0, 255);
          data[idx + 1] = (g * 255).toInt().clamp(0, 255);
          data[idx + 2] = (b * 255).toInt().clamp(0, 255);
        }
      }
    }

    // 5. SATURATION
    if (_saturation != 1.0) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          double r = data[idx] / 255.0;
          double g = data[idx + 1] / 255.0;
          double b = data[idx + 2] / 255.0;
          double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          r = luma + (r - luma) * _saturation;
          g = luma + (g - luma) * _saturation;
          b = luma + (b - luma) * _saturation;
          data[idx] = (r * 255).toInt().clamp(0, 255);
          data[idx + 1] = (g * 255).toInt().clamp(0, 255);
          data[idx + 2] = (b * 255).toInt().clamp(0, 255);
        }
      }
    }

    // 6. CONTRAST
    if (_contrast != 1.0) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          double r = data[idx] / 255.0;
          double g = data[idx + 1] / 255.0;
          double b = data[idx + 2] / 255.0;
          r = ((r - 0.5) * _contrast + 0.5).clamp(0.0, 1.0);
          g = ((g - 0.5) * _contrast + 0.5).clamp(0.0, 1.0);
          b = ((b - 0.5) * _contrast + 0.5).clamp(0.0, 1.0);
          data[idx] = (r * 255).toInt().clamp(0, 255);
          data[idx + 1] = (g * 255).toInt().clamp(0, 255);
          data[idx + 2] = (b * 255).toInt().clamp(0, 255);
        }
      }
    }

    // 7. BRIGHTNESS
    if (_brightness != 0.0) {
      int offset = (_brightness * 255).toInt();
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          int r = (data[idx] + offset).clamp(0, 255);
          int g = (data[idx + 1] + offset).clamp(0, 255);
          int b = (data[idx + 2] + offset).clamp(0, 255);
          data[idx] = r;
          data[idx + 1] = g;
          data[idx + 2] = b;
        }
      }
    }

    // 8. GAMMA
    if (_gamma != 1.0) {
      double invGamma = 1.0 / _gamma.clamp(0.1, 2.5);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          double r = data[idx] / 255.0;
          double g = data[idx + 1] / 255.0;
          double b = data[idx + 2] / 255.0;
          r = math.pow(r, invGamma).toDouble().clamp(0.0, 1.0);
          g = math.pow(g, invGamma).toDouble().clamp(0.0, 1.0);
          b = math.pow(b, invGamma).toDouble().clamp(0.0, 1.0);
          data[idx] = (r * 255).toInt().clamp(0, 255);
          data[idx + 1] = (g * 255).toInt().clamp(0, 255);
          data[idx + 2] = (b * 255).toInt().clamp(0, 255);
        }
      }
    }

    // 9. TEAL & ORANGE (LookMix)
    if (_lookMix > 0.0) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          double r = data[idx] / 255.0;
          double g = data[idx + 1] / 255.0;
          double b = data[idx + 2] / 255.0;
          double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          double tealR = 0.0, tealG = 0.6, tealB = 0.6;
          double orangeR = 1.0, orangeG = 0.6, orangeB = 0.1;
          double gradedR = tealR + (orangeR - tealR) * luma;
          double gradedG = tealG + (orangeG - tealG) * luma;
          double gradedB = tealB + (orangeB - tealB) * luma;
          double mixedR = r * (1.0 - 0.7) + r * gradedR * 0.7;
          double mixedG = g * (1.0 - 0.7) + g * gradedG * 0.7;
          double mixedB = b * (1.0 - 0.7) + b * gradedB * 0.7;
          r = r * (1.0 - _lookMix) + mixedR * _lookMix;
          g = g * (1.0 - _lookMix) + mixedG * _lookMix;
          b = b * (1.0 - _lookMix) + mixedB * _lookMix;
          data[idx] = (r * 255).toInt().clamp(0, 255);
          data[idx + 1] = (g * 255).toInt().clamp(0, 255);
          data[idx + 2] = (b * 255).toInt().clamp(0, 255);
        }
      }
    }

    // 10. VIGNETTE
    if (_vignette > 0.0) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          double dx = (x / w - 0.5) * 2.0;
          double dy = (y / h - 0.5) * 2.0;
          double dist = math.sqrt(dx * dx + dy * dy);
          double amount = 1.0 - (dist * _vignette * 1.5).clamp(0.0, 1.0);
          int idx = (y * w + x) * 4;
          int r = (data[idx] * amount).toInt().clamp(0, 255);
          int g = (data[idx + 1] * amount).toInt().clamp(0, 255);
          int b = (data[idx + 2] * amount).toInt().clamp(0, 255);
          data[idx] = r;
          data[idx + 1] = g;
          data[idx + 2] = b;
        }
      }
    }

    // 11. SPLIT TONING
    if (_splitToning > 0.0) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int idx = (y * w + x) * 4;
          double r = data[idx] / 255.0;
          double g = data[idx + 1] / 255.0;
          double b = data[idx + 2] / 255.0;
          double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          double shadowR = 0.1, shadowG = 0.2, shadowB = 0.6;
          double highlightR = 1.0, highlightG = 0.5, highlightB = 0.1;
          double tintR = shadowR + (highlightR - shadowR) * luma;
          double tintG = shadowG + (highlightG - shadowG) * luma;
          double tintB = shadowB + (highlightB - shadowB) * luma;
          r = r * (1.0 - _splitToning * 0.4) + r * tintR * _splitToning * 0.4;
          g = g * (1.0 - _splitToning * 0.4) + g * tintG * _splitToning * 0.4;
          b = b * (1.0 - _splitToning * 0.4) + b * tintB * _splitToning * 0.4;
          data[idx] = (r * 255).toInt().clamp(0, 255);
          data[idx + 1] = (g * 255).toInt().clamp(0, 255);
          data[idx + 2] = (b * 255).toInt().clamp(0, 255);
        }
      }
    }

    // 12. FILMIC TONE MAPPING
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int idx = (y * w + x) * 4;
        double r = data[idx] / 255.0;
        double g = data[idx + 1] / 255.0;
        double b = data[idx + 2] / 255.0;
        double xr = math.max(0.0, r - 0.004);
        double xg = math.max(0.0, g - 0.004);
        double xb = math.max(0.0, b - 0.004);
        double rr = (xr * (6.2 * xr + 0.5)) / (xr * (6.2 * xr + 1.7) + 0.06);
        double rg = (xg * (6.2 * xg + 0.5)) / (xg * (6.2 * xg + 1.7) + 0.06);
        double rb = (xb * (6.2 * xb + 0.5)) / (xb * (6.2 * xb + 1.7) + 0.06);
        r = math.pow(rr, 1.0 / 2.2).toDouble().clamp(0.0, 1.0);
        g = math.pow(rg, 1.0 / 2.2).toDouble().clamp(0.0, 1.0);
        b = math.pow(rb, 1.0 / 2.2).toDouble().clamp(0.0, 1.0);
        data[idx] = (r * 255).toInt().clamp(0, 255);
        data[idx + 1] = (g * 255).toInt().clamp(0, 255);
        data[idx + 2] = (b * 255).toInt().clamp(0, 255);
      }
    }

    return img.Image.fromBytes(width: w, height: h, bytes: data.buffer);
  }
    // ---------- FULL EXPORT (CPU GRADING) ----------
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
            const Text('Exporting... (CPU Grading)', style: TextStyle(color: Colors.white, fontSize: 16)),
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
      if (frameFiles.isEmpty) {
        throw Exception('No frames extracted.');
      }

      final totalFrames = frameFiles.length;
      int processedFrames = 0;
      stopwatch.start();

      const batchSize = 5;

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

            final graded = _applyGradingToImage(decoded);

            final pngBytes = img.encodePng(graded);
            final outputFile = File('${processedDir.path}/${file.path.split('/').last}');
            await outputFile.writeAsBytes(pngBytes);

            if (!await outputFile.exists()) {
              throw Exception('Failed to write processed frame to: ${outputFile.path}');
            }

            processedFrames++;
            final p = processedFrames / totalFrames;
            progressNotifier.value = p;
            final percent = (processedFrames / totalFrames * 100).toInt();
            statusNotifier.value = 'Processing... $percent%';
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
      stopwatch.stop();

      statusNotifier.value = 'Encoding video...';
      final targetFps = int.parse(fps.replaceAll('fps', ''));
      final silentOutputPath = '${dir.path}/silent_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      var encodeCmd = '-framerate $targetFps -i "${processedDir.path}/frame_%05d.png" ' +
                      '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p "$silentOutputPath"';
      var encodeSession = await FFmpegKit.execute(encodeCmd);
      var encodeReturnCode = await encodeSession.getReturnCode();

      if (!ReturnCode.isSuccess(encodeReturnCode)) {
        statusNotifier.value = 'Retrying with mpeg4...';
        final fallbackCmd = '-framerate $targetFps -i "${processedDir.path}/frame_%05d.png" ' +
                            '-c:v mpeg4 -q:v 5 -pix_fmt yuv420p "$silentOutputPath"';
        encodeSession = await FFmpegKit.execute(fallbackCmd);
        encodeReturnCode = await encodeSession.getReturnCode();
      }

      if (!ReturnCode.isSuccess(encodeReturnCode)) {
        final combined = await encodeSession.getOutput() ?? "No output";
        final errorSnippet = combined.length > 500 
            ? "...${combined.substring(combined.length - 500)}" 
            : combined;
        throw Exception('Encode failed:\n$errorSnippet');
      }

      statusNotifier.value = 'Extracting audio...';
      final audioPath = '${dir.path}/extracted_audio.aac';
      final audioCmd = '-i "${_currentVideoPath!}" -vn -acodec copy "$audioPath"';
      final audioSession = await FFmpegKit.execute(audioCmd);
      if (!ReturnCode.isSuccess(await audioSession.getReturnCode())) {
        print('Audio extraction skipped');
      }

      statusNotifier.value = 'Muxing audio and video...';
      final finalOutputPath = '${dir.path}/final_export_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final muxCmd = '-i "$silentOutputPath" -i "$audioPath" -c copy -shortest "$finalOutputPath"';
      final muxSession = await FFmpegKit.execute(muxCmd);
      if (!ReturnCode.isSuccess(await muxSession.getReturnCode())) {
        await File(silentOutputPath).copy(File(finalOutputPath).path);
      }

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
    // ---------- EXPORT DIALOG ----------
  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            String selectedRes = _projectResolution;
            String selectedFps = _projectFps;
            String selectedBit = _projectBitrate;
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
                  const Text('Full 32-bit CPU export may take several minutes.', style: TextStyle(color: Colors.white38, fontSize: 10)),
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
        title: Text(widget.projectName ?? 'Project'),
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
                          const Text('Preview applies CPU grading to the frame',
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
