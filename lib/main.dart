import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'vulkan_bridge.dart';

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

  Uint8List? _spirvShader;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _projectResolution = widget.initialResolution ?? '1080p';
    _projectFps = widget.initialFps ?? '60fps';
    _projectBitrate = widget.initialBitrate ?? '35 Mbps';

    _loadShader();

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

  Future<void> _loadShader() async {
    try {
      final byteData = await rootBundle.load('assets/shaders/aereality_core.spv');
      print('✅ SPIR-V loaded: ${byteData.lengthInBytes} bytes');
      _spirvShader = byteData.buffer.asUint8List();
      initVulkan(_spirvShader!);
      print('✅ Vulkan initialized successfully');
    } catch (e) {
      print('❌ SPIR-V load failed: $e');
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
          _brightness = 0.02; _saturation = 1.2; _contrast = 1.2; _sharpness = 0.15;
          _gamma = 0.95; _hue = -4.0; _temperature = 6200; _glowIntensity = 0.05;
          _vignette = 0.0; _splitToning = 0.05; _lookMix = 0.2;
          break;
        case 'Magic Bullet':
          _brightness = 0.05; _saturation = 1.25; _contrast = 1.15; _sharpness = 0.15;
          _gamma = 1.0; _hue = 2.0; _temperature = 6500; _glowIntensity = 0.15;
          _vignette = 0.0; _splitToning = 0.0; _lookMix = 0.0;
          break;
        case 'Teal & Orange':
          _brightness = 0.0; _saturation = 1.15; _contrast = 1.2; _sharpness = 0.1;
          _gamma = 0.95; _hue = -6.0; _temperature = 5800; _glowIntensity = 0.02;
          _vignette = 0.0; _splitToning = 0.1; _lookMix = 0.5;
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

  Future<ui.Image> _convertImageToUiImage(img.Image image) async {
    final pngBytes = img.encodePng(image);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(pngBytes, (ui.Image result) {
      completer.complete(result);
    });
    return completer.future;
  }

  Future<img.Image> _uiImageToImage(ui.Image uiImage) async {
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    final image = img.Image.fromBytes(
      width: uiImage.width,
      height: uiImage.height,
      bytes: byteData!.buffer,
    );
    return image;
  }

  Future<ui.Image> _processFrameWithVulkan(ui.Image input) async {
    final byteData = await input.toByteData(format: ui.ImageByteFormat.rawRgba);
    final inputBytes = byteData!.buffer.asUint8List();
    final outputBytes = processImage(inputBytes, input.width, input.height);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      outputBytes,
      input.width,
      input.height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future;
  }
    Future<void> _previewFrame() async {
    if (_controller == null || !_controller!.value.isInitialized || _currentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import a video first'), backgroundColor: Colors.orange));
      return;
    }
    if (_spirvShader == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shader not loaded'), backgroundColor: Colors.red));
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

      final uiFrame = await _convertImageToUiImage(image);
      final gradedUi = await _processFrameWithVulkan(uiFrame);

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
                    image: gradedUi,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Frame at ${timestamp}s (Vulkan 32-bit Graded)', style: const TextStyle(color: Colors.white54)),
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
                  const Text('Exporting to 8-bit SDR (test)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            );
          },
        );
      },
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
    Future<void> _exportVideo(String resolution, String fps, String bitrate) async {
    if (_controller == null || !_controller!.value.isInitialized || _currentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import a video first'), backgroundColor: Colors.orange));
      return;
    }
    if (_spirvShader == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shader not loaded'), backgroundColor: Colors.red));
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
            const Text('Exporting... (Vulkan 32-bit → 8-bit SDR Test)', style: TextStyle(color: Colors.white, fontSize: 16)),
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

      // ✅ Copy input video to cache if it's outside (fix for Android 11+)
      String videoPathForFFmpeg = _currentVideoPath!;
      bool isCachedVideo = false;
      if (!videoPathForFFmpeg.startsWith(dir.path)) {
        statusNotifier.value = 'Copying video to cache...';
        final inputFile = File(videoPathForFFmpeg);
        if (!await inputFile.exists()) {
          throw Exception('Input video file does not exist: $videoPathForFFmpeg');
        }
        final cachedVideoPath = '${dir.path}/input_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        await inputFile.copy(cachedVideoPath);
        videoPathForFFmpeg = cachedVideoPath;
        isCachedVideo = true;
        print('📹 Video copied to cache: $videoPathForFFmpeg');
      }

      final framesDir = Directory('${dir.path}/export_frames');
      final processedDir = Directory('${dir.path}/export_processed');
      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      if (await processedDir.exists()) await processedDir.delete(recursive: true);
      await framesDir.create();
      await processedDir.create();

      statusNotifier.value = 'Extracting frames...';
      final extractCmd = '-i "${videoPathForFFmpeg}" -vsync 0 -f image2 "${framesDir.path}/frame_%05d.png"';
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

            final rawInput = decoded.data!.buffer.asUint8List();
            final outputRaw = processImage(rawInput, decoded.width, decoded.height);

            final gradedImg = img.Image.fromBytes(
              width: decoded.width,
              height: decoded.height,
              bytes: outputRaw.buffer,
            );
            final pngBytes = img.encodePng(gradedImg);
            final outputFile = File('${processedDir.path}/${file.path.split('/').last}');
            await outputFile.writeAsBytes(pngBytes);

            if (!await outputFile.exists()) {
              throw Exception('Failed to write processed frame to: ${outputFile.path}');
            }

            if (processedFrames == 1) {
              try {
                final testDir = await getTemporaryDirectory();
                final testFile = File('${testDir.path}/test_frame.png');
                await outputFile.copy(testFile.path);
                print('✅ Test frame saved to: ${testFile.path}');
              } catch (e) {
                print('❌ Failed to save test frame: $e');
              }
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

      statusNotifier.value = 'Encoding 8-bit SDR video...';
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
      final audioCmd = '-i "${videoPathForFFmpeg}" -vn -acodec copy "$audioPath"';
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

      // Save final MP4 to app's Documents folder
      final docsDir = await getApplicationDocumentsDirectory();
      final finalFile = File('${docsDir.path}/AEReality_Export_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await File(finalOutputPath).copy(finalFile.path);

      // Clean up temporary folders and files
      await framesDir.delete(recursive: true);
      await processedDir.delete(recursive: true);
      try { await File(audioPath).delete(); } catch (_) {}
      try { await File(silentOutputPath).delete(); } catch (_) {}
      if (isCachedVideo) {
        try { await File(videoPathForFFmpeg).delete(); } catch (_) {}
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Export saved to:\n${finalFile.path}'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

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
                      // Adjust tab
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
                      // Presets tab
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
                      // Export tab
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
                          const Text('Preview applies Vulkan 32-bit grading to the frame',
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

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    cleanupVulkan();
    super.dispose();
  }
}
