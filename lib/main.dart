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
import 'lut_loader.dart';

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
          iconThemeData: IconThemeData(color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------- PROJECT DATA ----------
class ProjectData {
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, lookMix, vignette, splitToning;
  String aspectRatio;
  String videoName;
  String? lutName;
  bool deepGlow;
  double? deepGlowRadius;

  ProjectData({
    required this.videoPath,
    this.brightness = 0.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.sharpness = 0.0,
    this.gamma = 1.0,
    this.hue = 0.0,
    this.temperature = 6500.0,
    this.glowIntensity = 0.0,
    this.lookMix = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.aspectRatio = "16:9",
    this.videoName = "Untitled",
    this.lutName,
    this.deepGlow = false,
    this.deepGlowRadius,
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
    'videoName': videoName,
    'lutName': lutName,
    'deepGlow': deepGlow,
    'deepGlowRadius': deepGlowRadius,
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
    glowIntensity: json['glowIntensity'] ?? 0.0,
    lookMix: json['lookMix'] ?? 0.0,
    vignette: json['vignette'] ?? 0.0,
    splitToning: json['splitToning'] ?? 0.0,
    aspectRatio: json['aspectRatio'] ?? "16:9",
    videoName: json['videoName'] ?? "Untitled",
    lutName: json['lutName'],
    deepGlow: json['deepGlow'] ?? false,
    deepGlowRadius: json['deepGlowRadius'],
  );
}

// ---------- STORED PROJECT ----------
class StoredProject {
  String id;
  String name;
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, lookMix, vignette, splitToning;
  String aspectRatio;
  DateTime lastOpened;
  String videoName;
  String? lutName;
  bool deepGlow;
  double? deepGlowRadius;

  StoredProject({
    required this.id,
    required this.name,
    required this.videoPath,
    this.brightness = 0.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.sharpness = 0.0,
    this.gamma = 1.0,
    this.hue = 0.0,
    this.temperature = 6500.0,
    this.glowIntensity = 0.0,
    this.lookMix = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.aspectRatio = "16:9",
    required this.lastOpened,
    this.videoName = "Untitled",
    this.lutName,
    this.deepGlow = false,
    this.deepGlowRadius,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
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
    'lastOpened': lastOpened.toIso8601String(),
    'videoName': videoName,
    'lutName': lutName,
    'deepGlow': deepGlow,
    'deepGlowRadius': deepGlowRadius,
  };

  factory StoredProject.fromJson(Map<String, dynamic> json) => StoredProject(
    id: json['id'],
    name: json['name'],
    videoPath: json['videoPath'],
    brightness: json['brightness'] ?? 0.0,
    saturation: json['saturation'] ?? 1.0,
    contrast: json['contrast'] ?? 1.0,
    sharpness: json['sharpness'] ?? 0.0,
    gamma: json['gamma'] ?? 1.0,
    hue: json['hue'] ?? 0.0,
    temperature: json['temperature'] ?? 6500.0,
    glowIntensity: json['glowIntensity'] ?? 0.0,
    lookMix: json['lookMix'] ?? 0.0,
    vignette: json['vignette'] ?? 0.0,
    splitToning: json['splitToning'] ?? 0.0,
    aspectRatio: json['aspectRatio'] ?? "16:9",
    lastOpened: DateTime.parse(json['lastOpened']),
    videoName: json['videoName'] ?? "Untitled",
    lutName: json['lutName'],
    deepGlow: json['deepGlow'] ?? false,
    deepGlowRadius: json['deepGlowRadius'],
  );

  ProjectData toProjectData() => ProjectData(
    videoPath: videoPath,
    brightness: brightness,
    saturation: saturation,
    contrast: contrast,
    sharpness: sharpness,
    gamma: gamma,
    hue: hue,
    temperature: temperature,
    glowIntensity: glowIntensity,
    lookMix: lookMix,
    vignette: vignette,
    splitToning: splitToning,
    aspectRatio: aspectRatio,
    videoName: videoName,
    lutName: lutName,
    deepGlow: deepGlow,
    deepGlowRadius: deepGlowRadius,
  );
}

// ---------- PROJECT MANAGER ----------
class ProjectManager {
  static const String _storageKey = 'projects.json';

  static Future<List<StoredProject>> loadProjects() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_storageKey');
      if (!await file.exists()) return [];
      final data = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList.map((j) => StoredProject.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveProjects(List<StoredProject> projects) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_storageKey');
      final data = jsonEncode(projects.map((p) => p.toJson()).toList());
      await file.writeAsString(data);
    } catch (e) {
      debugPrint('Error saving projects: $e');
    }
  }

  static Future<void> saveProject(StoredProject project) async {
    try {
      final projects = await loadProjects();
      final index = projects.indexWhere((p) => p.id == project.id);
      if (index >= 0) {
        projects[index] = project;
      } else {
        projects.add(project);
      }
      await saveProjects(projects);
    } catch (e) {
      debugPrint('Error saving project: $e');
    }
  }

  static Future<void> deleteProject(String id) async {
    try {
      final projects = await loadProjects();
      projects.removeWhere((p) => p.id == id);
      await saveProjects(projects);
    } catch (e) {
      debugPrint('Error deleting project: $e');
    }
  }
}

// ---------- HOME SCREEN ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<StoredProject>> _projectsFuture;

  @override
  void initState() {
    super.initState();
    _projectsFuture = ProjectManager.loadProjects();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('AEReality - Color Grading Suite'),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      body: FutureBuilder<List<StoredProject>>(
        future: _projectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(type: FileType.video);
                  if (result != null && mounted) {
                    final videoPath = result.files.single.path!;
                    final fileName = result.files.single.name;
                    if (mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProjectScreen(
                            project: StoredProject(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: 'New Project',
                              videoPath: videoPath,
                              videoName: fileName,
                              lastOpened: DateTime.now(),
                            ),
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('New Project'),
              ),
              const SizedBox(height: 16),
              if (projects.isEmpty)
                const Center(
                  child: Text(
                    'No projects yet. Create one to get started!',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                ...projects.map((project) => ProjectTile(project: project)),
            ],
          );
        },
      ),
    );
  }
}

class ProjectTile extends StatelessWidget {
  final StoredProject project;

  const ProjectTile({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A1A),
      child: ListTile(
        title: Text(project.name),
        subtitle: Text(project.videoName),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ProjectScreen(project: project)),
          );
        },
        trailing: IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () {
            ProjectManager.deleteProject(project.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Project deleted')),
            );
          },
        ),
      ),
    );
  }
}

// ---------- PROJECT SCREEN (MAIN GRADING UI - PORTED FROM REACT) ----------
class ProjectScreen extends StatefulWidget {
  final StoredProject project;

  const ProjectScreen({super.key, required this.project});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  // ✅ ALL ORIGINAL VULKAN/FFI STATE
  late VideoPlayerController _videoController;
  late ProjectData _projectData;

  // ✅ NEW PORTED UI STATE (from React ProjectScreen.tsx)
  late String _activeTab; // 'adjust' | 'presets' | 'export'
  late String _adjustCategory; // 'color' | 'curves' | 'sharpness' | 'bloom' | 'grade'
  
  bool _isPlaying = true;
  bool _isMuted = false;
  double _volume = 1.0;
  double _currentTime = 0.0;
  double _duration = 0.0;
  
  bool _splitMode = false;
  double _splitPosition = 0.5;
  bool _bypassGrading = false;
  bool _showScopes = false;
  String _scopeType = 'waveform';
  bool _isFullscreenPreview = false;
  
  String? _toastMessage;
  bool _isExporting = false;
  
  // Aspect ratio & fit
  String _selectedAspectRatio = '16:9';
  String _selectedVideoFit = 'cover';

  @override
  void initState() {
    super.initState();
    _projectData = widget.project.toProjectData();
    _activeTab = 'adjust';
    _adjustCategory = 'color';
    
    _initializeVideo();
  }

  void _initializeVideo() {
    _videoController = VideoPlayerController.file(File(_projectData.videoPath))
      ..initialize().then((_) {
        setState(() {
          _duration = _videoController.value.duration.inSeconds.toDouble();
        });
        _videoController.play();
      });

    _videoController.addListener(_onVideoUpdate);
  }

  void _onVideoUpdate() {
    setState(() {
      _currentTime = _videoController.value.position.inSeconds.toDouble();
    });
  }

  void _showToast(String message) {
    setState(() => _toastMessage = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _togglePlay() {
    setState(() {
      _isPlaying ? _videoController.pause() : _videoController.play();
      _isPlaying = !_isPlaying;
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _videoController.setVolume(_isMuted ? 0 : _volume);
    });
  }

  void _handleVolumeChange(double value) {
    setState(() {
      _volume = value;
      if (value > 0 && _isMuted) {
        _isMuted = false;
      }
      _videoController.setVolume(value);
    });
  }

  void _handleSeek(double value) {
    setState(() => _currentTime = value);
    _videoController.seekTo(Duration(seconds: value.toInt()));
  }

  void _handleSaveProject() {
    final updated = StoredProject(
      id: widget.project.id,
      name: widget.project.name,
      videoPath: widget.project.videoPath,
      brightness: _projectData.brightness,
      saturation: _projectData.saturation,
      contrast: _projectData.contrast,
      sharpness: _projectData.sharpness,
      gamma: _projectData.gamma,
      hue: _projectData.hue,
      temperature: _projectData.temperature,
      glowIntensity: _projectData.glowIntensity,
      lookMix: _projectData.lookMix,
      vignette: _projectData.vignette,
      splitToning: _projectData.splitToning,
      aspectRatio: _selectedAspectRatio,
      lastOpened: DateTime.now(),
      videoName: _projectData.videoName,
      lutName: _projectData.lutName,
      deepGlow: _projectData.deepGlow,
      deepGlowRadius: _projectData.deepGlowRadius,
    );
    ProjectManager.saveProject(updated);
    _showToast('Project saved successfully!');
  }

  void _resetParameters() {
    setState(() {
      _projectData = ProjectData(
        videoPath: _projectData.videoPath,
        aspectRatio: _selectedAspectRatio,
        videoName: _projectData.videoName,
      );
    });
    _showToast('Grading reset to neutral');
  }

  void _importVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      setState(() {
        _projectData.videoPath = result.files.single.path!;
        _projectData.videoName = result.files.single.name;
      });
      _videoController.dispose();
      _initializeVideo();
      _showToast('Video imported: ${result.files.single.name}');
    }
  }

  void _loadCustomLut() async {
    try {
      final result = await LutLoader.loadLutFromFile();
      if (result != null) {
        final (lutData, size) = result;
        uploadLutData(lutData, size);
        setState(() => _projectData.lutName = 'Custom LUT');
        _showToast('LUT loaded successfully!');
      }
    } catch (e) {
      _showToast('Failed to load LUT: $e');
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  // ✅ SLIDER WIDGET
  Widget _buildSlider({
    required String label,
    required double min,
    required double max,
    required double value,
    required Function(double) onChanged,
    double step = 0.01,
    String unit = '',
    String? description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              '${value.toStringAsFixed(2)}$unit',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFF06B6D4),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (description != null)
          Text(
            description,
            style: const TextStyle(fontSize: 9, color: Colors.white54),
          ),
        Slider(
          min: min,
          max: max,
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF06B6D4),
          inactiveColor: Colors.white12,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 1024;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project.name),
            Text(
              _projectData.videoName,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Save Project',
            child: IconButton(
              icon: const Icon(Icons.save),
              onPressed: _handleSaveProject,
            ),
          ),
        ],
      ),
      body: isMobile
          ? _buildMobileLayout()
          : _buildDesktopLayout(),
    );
  }

  // ✅ DESKTOP LAYOUT (Main UI Port from React)
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // ✅ MAIN VIDEO VIEWPORT (8/12 cols)
        Expanded(
          flex: 8,
          child: Column(
            children: [
              // ✅ HEADER BAR
              Container(
                height: 48,
                color: const Color(0xFF121212),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Aspect Ratio, LUT, Import
                    Row(
                      children: [
                        Tooltip(
                          message: 'Change Aspect Ratio',
                          child: ElevatedButton.icon(
                            onPressed: () => _showAspectRatioDialog(),
                            icon: const Icon(Icons.aspect_ratio, size: 16),
                            label: Text(_selectedAspectRatio),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Load 3D LUT',
                          child: ElevatedButton.icon(
                            onPressed: _loadCustomLut,
                            icon: const Icon(Icons.palette, size: 16),
                            label: Text(_projectData.lutName ?? '3D LUT'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _projectData.lutName != null
                                  ? const Color(0xFF06B6D4).withOpacity(0.2)
                                  : Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Import Video',
                          child: ElevatedButton.icon(
                            onPressed: _importVideo,
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: const Text('Import'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Right: Save Project
                    Tooltip(
                      message: 'Save Project',
                      child: ElevatedButton.icon(
                        onPressed: _handleSaveProject,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ VIDEO CANVAS VIEWPORT
              Expanded(
                child: Container(
                  color: const Color(0xFF050505),
                  padding: const EdgeInsets.all(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Video
                      if (_videoController.value.isInitialized)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _videoController.value.aspectRatio,
                            child: VideoPlayer(_videoController),
                          ),
                        ),
                      // Toast
                      if (_toastMessage != null)
                        Positioned(
                          top: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF06B6D4),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _toastMessage!,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      // Play/Pause + Split + Bypass buttons
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: _togglePlay,
                              style: ElevatedButton.styleFrom(
                                shape: const CircleBorder(),
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.all(8),
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => setState(() => _splitMode = !_splitMode),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _splitMode
                                    ? const Color(0xFF06B6D4)
                                    : Colors.black54,
                              ),
                              child: const Text('A/B Split'),
                            ),
                            ElevatedButton(
                              onPressed: () => setState(() => _bypassGrading = !_bypassGrading),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _bypassGrading
                                    ? Colors.orange
                                    : Colors.black54,
                              ),
                              child: const Text('Bypass'),
                            ),
                            ElevatedButton(
                              onPressed: () => setState(() => _showScopes = !_showScopes),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _showScopes
                                    ? const Color(0xFF06B6D4)
                                    : Colors.black54,
                              ),
                              child: const Text('Scopes'),
                            ),
                          ],
                        ),
                      ),
                      // Fullscreen Button
                      if (!_isFullscreenPreview)
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() => _isFullscreenPreview = true);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                            ),
                            child: const Icon(Icons.fullscreen),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // ✅ SCRUBBER & TIME
              Container(
                color: const Color(0xFF111111),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: _duration,
                        value: _currentTime,
                        onChanged: _handleSeek,
                        activeColor: const Color(0xFF06B6D4),
                        inactiveColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_currentTime.toInt()}:${((_currentTime % 60).toInt()).toString().padLeft(2, '0')} / ${_duration.toInt()}:${((_duration % 60).toInt()).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ✅ RIGHT SIDEBAR - ADJUSTMENT CONTROLS (4/12 cols)
        Container(
          width: 400,
          color: const Color(0xFF0A0A0A),
          child: Column(
            children: [
              // Tab Headers
              Container(
                color: const Color(0xFF0E0E0E),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton('Adjust', 'adjust'),
                    ),
                    Expanded(
                      child: _buildTabButton('Presets', 'presets'),
                    ),
                    Expanded(
                      child: _buildTabButton('Export', 'export'),
                    ),
                  ],
                ),
              ),
              // Tab Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _activeTab == 'adjust'
                      ? _buildAdjustPanel()
                      : _activeTab == 'presets'
                          ? _buildPresetsPanel()
                          : _buildExportPanel(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ TAB BUTTON
  Widget _buildTabButton(String label, String tabId) {
    final isActive = _activeTab == tabId;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isActive ? const Color(0xFF06B6D4) : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: TextButton(
        onPressed: () => setState(() => _activeTab = tabId),
        style: TextButton.styleFrom(
          backgroundColor: isActive ? const Color(0xFF06B6D4).withOpacity(0.1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? const Color(0xFF06B6D4) : Colors.white54,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ✅ ADJUST PANEL (Color, Curves, Sharpness, Bloom, etc.)
  Widget _buildAdjustPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        // Sub-category Pills
        Wrap(
          spacing: 8,
          children: [
            _buildCategoryPill('Color', 'color'),
            _buildCategoryPill('Sharpness', 'sharpness'),
            _buildCategoryPill('Bloom', 'bloom'),
            _buildCategoryPill('Grade', 'grade'),
          ],
        ),
        const Divider(color: Colors.white12),
        // Reset Button
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _resetParameters,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset all'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
            ),
          ),
        ),
        // Dynamic Controls Based on Category
        if (_adjustCategory == 'color') ...[
          _buildSlider(
            label: 'Brightness',
            min: -3.0,
            max: 3.0,
            value: _projectData.brightness,
            onChanged: (v) => setState(() => _projectData.brightness = v),
            description: 'Exposure compensation in full EV stops',
          ),
          _buildSlider(
            label: 'Contrast',
            min: 0.0,
            max: 3.0,
            value: _projectData.contrast,
            onChanged: (v) => setState(() => _projectData.contrast = v),
            description: 'Punchy 32-bit S-curve contrast',
          ),
          _buildSlider(
            label: 'Saturation',
            min: 0.0,
            max: 3.0,
            value: _projectData.saturation,
            onChanged: (v) => setState(() => _projectData.saturation = v),
            description: 'Rec.709 color vibrancy',
          ),
          _buildSlider(
            label: 'Gamma',
            min: 0.1,
            max: 2.5,
            value: _projectData.gamma,
            onChanged: (v) => setState(() => _projectData.gamma = v),
            description: 'Non-linear power curve balance',
          ),
          _buildSlider(
            label: 'Hue Rotate',
            min: -180,
            max: 180,
            value: _projectData.hue,
            onChanged: (v) => setState(() => _projectData.hue = v),
            unit: '°',
            description: '3x3 RGB color rotation matrix',
          ),
          _buildSlider(
            label: 'Color Temp',
            min: 2000,
            max: 12000,
            value: _projectData.temperature,
            onChanged: (v) => setState(() => _projectData.temperature = v),
            unit: 'K',
            description: 'Kelvin white balance (6500K neutral)',
          ),
        ],
        if (_adjustCategory == 'sharpness') ...[
          _buildSlider(
            label: 'Sharpness',
            min: 0.0,
            max: 6.0,
            value: _projectData.sharpness,
            onChanged: (v) => setState(() => _projectData.sharpness = v),
            step: 0.05,
            description: 'Laplacian high-pass unsharp mask convolution',
          ),
        ],
        if (_adjustCategory == 'bloom') ...[
          _buildSlider(
            label: 'Bloom Intensity',
            min: 0.0,
            max: 1.0,
            value: _projectData.glowIntensity,
            onChanged: (v) => setState(() => _projectData.glowIntensity = v),
            step: 0.01,
            description: 'Smooth continuous 32-bit Gaussian radiance',
          ),
        ],
        if (_adjustCategory == 'grade') ...[
          _buildSlider(
            label: 'Look Mix (Teal/Orange)',
            min: 0.0,
            max: 1.0,
            value: _projectData.lookMix,
            onChanged: (v) => setState(() => _projectData.lookMix = v),
            description: 'Cinematic Hollywood blockbuster matrix',
          ),
          _buildSlider(
            label: 'Split Toning',
            min: 0.0,
            max: 1.0,
            value: _projectData.splitToning,
            onChanged: (v) => setState(() => _projectData.splitToning = v),
            description: 'Deep navy shadow tone vs warm golden highlight split',
          ),
          _buildSlider(
            label: 'Vignette Darkness',
            min: 0.0,
            max: 1.0,
            value: _projectData.vignette,
            onChanged: (v) => setState(() => _projectData.vignette = v),
            step: 0.01,
            description: 'Intense radial corner falloff darkening',
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryPill(String label, String categoryId) {
    final isActive = _adjustCategory == categoryId;
    return FilterChip(
      label: Text(label),
      backgroundColor: isActive ? const Color(0xFF06B6D4) : Colors.white12,
      labelStyle: TextStyle(
        color: isActive ? Colors.black : Colors.white,
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _adjustCategory = categoryId);
        }
      },
    );
  }

  // ✅ PRESETS PANEL
  Widget _buildPresetsPanel() {
    return const Column(
      spacing: 8,
      children: [
        Text('Coming soon: Built-in color presets'),
      ],
    );
  }

  // ✅ EXPORT PANEL
  Widget _buildExportPanel() {
    return Column(
      spacing: 12,
      children: [
        ElevatedButton.icon(
          onPressed: () => _showToast('Preview feature coming soon'),
          icon: const Icon(Icons.preview),
          label: const Text('Preview Graded Frame'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF06B6D4),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _showToast('Export feature coming soon'),
          icon: const Icon(Icons.download),
          label: const Text('EXPORT MASTER VIDEO'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(40),
          ),
        ),
        const Text(
          'MP4 / WebM / MOV Encodings • 168k-384k Audio • Vulkan 32-Bit Floating Point Pipeline',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white54,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Video
          _videoController.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _videoController.value.aspectRatio,
                  child: VideoPlayer(_videoController),
                )
              : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              spacing: 16,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _togglePlay,
                      child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    ElevatedButton(
                      onPressed: () => setState(() => _splitMode = !_splitMode),
                      child: const Text('Split'),
                    ),
                    ElevatedButton(
                      onPressed: _toggleMute,
                      child: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                    ),
                  ],
                ),
                Slider(
                  min: 0,
                  max: _duration,
                  value: _currentTime,
                  onChanged: _handleSeek,
                ),
                _buildAdjustPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAspectRatioDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Select Aspect Ratio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['4:5', '9:16', '1:1', '16:9', '21:9'].map((ratio) {
              return ListTile(
                title: Text(ratio),
                selected: _selectedAspectRatio == ratio,
                onTap: () {
                  setState(() => _selectedAspectRatio = ratio);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
