import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AERealityApp());
}

class AERealityApp extends StatelessWidget {
  const AERealityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEReality Studio',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080808),
        primaryColor: const Color(0xFF00F0FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFF00F0FF),
          surface: Color(0xFF101014),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080808),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Global live preview resolution scaler (360p = 0.33, 540p = 0.5, 720p = 0.66, 1080p = 1.0)
double gPreviewScale = 0.5;

// ---------- PROJECT DATA MODEL ----------
class ProjectData {
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, lookMix, vignette, splitToning, edgeDarken;
  double denoise, cellShading, colourCrush, cellThickness;
  // Stylized FX
  double mangaRageAura, mangaRageSpread, mangaRageJitter;
  double flickerIntensity, flickerSpeed;
  bool dustParticles;
  double dustIntensity, dustSpeed;
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
    this.glowIntensity = 0.0,
    this.lookMix = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.edgeDarken = 0.0,
    this.denoise = 0.0,
    this.cellShading = 0.0,
    this.colourCrush = 0.0,
    this.cellThickness = 0.3,
    this.mangaRageAura = 0.0,
    this.mangaRageSpread = 0.4,
    this.mangaRageJitter = 0.5,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 3.0,
    this.dustParticles = false,
    this.dustIntensity = 0.45,
    this.dustSpeed = 1.0,
    this.aspectRatio = "4:5",
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
    'edgeDarken': edgeDarken,
    'denoise': denoise,
    'cellShading': cellShading,
    'colourCrush': colourCrush,
    'cellThickness': cellThickness,
    'mangaRageAura': mangaRageAura,
    'mangaRageSpread': mangaRageSpread,
    'mangaRageJitter': mangaRageJitter,
    'flickerIntensity': flickerIntensity,
    'flickerSpeed': flickerSpeed,
    'dustParticles': dustParticles,
    'dustIntensity': dustIntensity,
    'dustSpeed': dustSpeed,
    'aspectRatio': aspectRatio,
  };

  factory ProjectData.fromJson(Map<String, dynamic> json) => ProjectData(
    videoPath: json['videoPath'],
    brightness: (json['brightness'] ?? 0.0).toDouble(),
    saturation: (json['saturation'] ?? 1.0).toDouble(),
    contrast: (json['contrast'] ?? 1.0).toDouble(),
    sharpness: (json['sharpness'] ?? 0.0).toDouble(),
    gamma: (json['gamma'] ?? 1.0).toDouble(),
    hue: (json['hue'] ?? 0.0).toDouble(),
    temperature: (json['temperature'] ?? 6500.0).toDouble(),
    glowIntensity: (json['glowIntensity'] ?? 0.0).toDouble(),
    lookMix: (json['lookMix'] ?? 0.0).toDouble(),
    vignette: (json['vignette'] ?? 0.0).toDouble(),
    splitToning: (json['splitToning'] ?? 0.0).toDouble(),
    edgeDarken: (json['edgeDarken'] ?? 0.0).toDouble(),
    denoise: (json['denoise'] ?? 0.0).toDouble(),
    cellShading: (json['cellShading'] ?? 0.0).toDouble(),
    colourCrush: (json['colourCrush'] ?? 0.0).toDouble(),
    cellThickness: (json['cellThickness'] ?? 0.3).toDouble(),
    mangaRageAura: (json['mangaRageAura'] ?? 0.0).toDouble(),
    mangaRageSpread: (json['mangaRageSpread'] ?? 0.4).toDouble(),
    mangaRageJitter: (json['mangaRageJitter'] ?? 0.5).toDouble(),
    flickerIntensity: (json['flickerIntensity'] ?? 0.0).toDouble(),
    flickerSpeed: (json['flickerSpeed'] ?? 3.0).toDouble(),
    dustParticles: json['dustParticles'] ?? false,
    dustIntensity: (json['dustIntensity'] ?? 0.45).toDouble(),
    dustSpeed: (json['dustSpeed'] ?? 1.0).toDouble(),
    aspectRatio: json['aspectRatio'] ?? "4:5",
  );
}

class StoredProject {
  String id, name, videoPath;
  ProjectData data;
  DateTime lastOpened;

  StoredProject({
    required this.id,
    required this.name,
    required this.videoPath,
    required this.data,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'videoPath': videoPath,
    'data': data.toJson(),
    'lastOpened': lastOpened.toIso8601String(),
  };

  factory StoredProject.fromJson(Map<String, dynamic> json) => StoredProject(
    id: json['id'],
    name: json['name'],
    videoPath: json['videoPath'],
    data: ProjectData.fromJson(json['data'] ?? json),
    lastOpened: DateTime.parse(json['lastOpened']),
  );
}

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
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveProjects(List<StoredProject> projects) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_storageKey');
    await file.writeAsString(jsonEncode(projects.map((p) => p.toJson()).toList()));
  }

  static Future<void> saveProject(StoredProject project) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == project.id);
    projects.insert(0, project);
    if (projects.length > 20) projects.removeRange(20, projects.length);
    await saveProjects(projects);
  }
}

// ---------- HOME SCREEN ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<StoredProject> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projs = await ProjectManager.loadProjects();
    if (mounted) setState(() => _recent = projs.take(5).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00F0FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
              ),
              child: const Text('AE', style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            const Text('AEReality Studio'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VULKAN HARDWARE COMPUTE', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            const Text('32-Bit Floating Point HDR Engine', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Master 2026 anime and WIS style grades with hardware float16 compute directly on device.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())),
                    icon: const Icon(Icons.add, color: Colors.black, size: 20),
                    label: const Text('New Project', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsScreen())),
                    icon: const Icon(Icons.folder_open, color: Colors.white, size: 20),
                    label: const Text('Saved Projects', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text('RECENT PROJECTS', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_recent.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF101014),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: const Text('No recent projects found. Tap "New Project" to start grading.', style: TextStyle(color: Colors.white38, fontSize: 13)),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _recent.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = _recent[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF101014),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.movie_creation_outlined, color: Color(0xFF00F0FF)),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text('${p.videoPath.split('/').last} • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: p.data, projectName: p.name)),
                          ).then((_) => _load());
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- SETTINGS SCREEN ----------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _tempScale;

  @override
  void initState() {
    super.initState();
    _tempScale = gPreviewScale;
  }

  @override
  Widget build(BuildContext context) {
    final resLabel = (_tempScale <= 0.35)
        ? '360p (Fast Mobile Scrubber)'
        : (_tempScale <= 0.55)
            ? '540p (Balanced 60fps)'
            : (_tempScale <= 0.75)
                ? '720p (High Precision)'
                : '1080p (Native 1:1 Float Match)';

    return Scaffold(
      appBar: AppBar(title: const Text('Engine Settings')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TIMELINE PREVIEW FIDELITY', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            const Text('Controls the live Vulkan compute canvas buffer size during playback.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF101014),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      const Text('Resolution Mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text(resLabel, style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: _tempScale,
                    min: 0.33,
                    max: 1.0,
                    divisions: 3,
                    activeColor: const Color(0xFF00F0FF),
                    inactiveColor: Colors.white12,
                    onChanged: (v) => setState(() => _tempScale = v),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => gPreviewScale = _tempScale);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Preview resolution set to $resLabel!'), backgroundColor: Colors.green),
                  );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F0FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('SAVE & APPLY SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
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

class _ProjectSetupScreenState extends State<ProjectSetupScreen> {
  String _projectName = 'Untitled Project';
  String _selectedAspect = '4:5';
  File? _selectedFile;

  final List<String> _aspectRatios = ['4:5', '9:16', '16:9', '1:1', '3:4', '21:9'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Project')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PROJECT NAME', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF101014),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'Untitled Project',
              controller: TextEditingController(text: _projectName),
            ),
            const SizedBox(height: 24),
            const Text('CANVAS ASPECT RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _aspectRatios.map((ratio) => ChoiceChip(
                label: Text(ratio),
                selected: _selectedAspect == ratio,
                selectedColor: const Color(0xFF00F0FF),
                backgroundColor: const Color(0xFF101014),
                labelStyle: TextStyle(color: _selectedAspect == ratio ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                onSelected: (_) => setState(() => _selectedAspect = ratio),
              )).toList(),
            ),
            const SizedBox(height: 24),
            const Text('SOURCE FOOTAGE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(type: FileType.video);
                if (result != null) {
                  setState(() => _selectedFile = File(result.files.single.path!));
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF101014),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(_selectedFile == null ? Icons.cloud_upload_outlined : Icons.check_circle, color: const Color(0xFF00F0FF), size: 36),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFile == null ? 'Tap to select video file' : _selectedFile!.path.split('/').last,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a video file first')));
                    return;
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectScreen(
                        initialProject: ProjectData(videoPath: _selectedFile!.path, aspectRatio: _selectedAspect),
                        projectName: _projectName,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F0FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('OPEN STUDIO EDITOR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- SAVED PROJECTS SCREEN ----------
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<StoredProject> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final projs = await ProjectManager.loadProjects();
    if (mounted) setState(() => _projects = projs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Projects')),
      body: _projects.isEmpty
          ? const Center(child: Text('No saved projects', style: TextStyle(color: Colors.white38)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _projects.length,
              itemBuilder: (ctx, i) {
                final p = _projects[i];
                return Card(
                  color: const Color(0xFF101014),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${p.videoPath.split('/').last} • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white54)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white38),
                      onPressed: () async {
                        await ProjectManager.saveProjects(_projects..removeAt(i));
                        _loadProjects();
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: p.data, projectName: p.name)),
                      ).then((_) => _loadProjects());
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ---------- STUDIO EDITOR SCREEN ----------
class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  final String? projectName;

  const ProjectScreen({super.key, this.initialProject, this.projectName});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  String? _currentVideoPath;

  // Active subcategory pill: 'color' | 'bloom' | 'sharpness' | 'grade' | 'anime' | 'strobe'
  String _activeCategory = 'color';

  // 23 Color Grading & Stylized Parameters
  double _brightness = 0.0;
  double _saturation = 1.0;
  double _contrast = 1.0;
  double _sharpness = 0.0;
  double _gamma = 1.0;
  double _hue = 0.0;
  double _temperature = 6500.0;
  double _glowIntensity = 0.0;
  double _lookMix = 0.0;
  double _vignette = 0.0;
  double _splitToning = 0.0;
  double _edgeDarken = 0.0;
  double _denoise = 0.0;
  double _cellShading = 0.0;
  double _colourCrush = 0.0;
  double _cellThickness = 0.3;
  // Stylized FX
  double _mangaRageAura = 0.0;
  double _mangaRageSpread = 0.4;
  double _mangaRageJitter = 0.5;
  double _flickerIntensity = 0.0;
  double _flickerSpeed = 3.0;
  bool _dustParticles = false;
  double _dustIntensity = 0.45;
  double _dustSpeed = 1.0;

  String _selectedRatio = "4:5";
  late TabController _tabController;
  VoidCallback _listener = () {};

  Uint8List? _spirvShader;
  ui.Image? _processedImage;
  Timer? _previewTimer;
  bool _isUpdating = false;
  final GlobalKey _videoCaptureKey = GlobalKey();

  int _canvasWidth = 864;
  int _canvasHeight = 1080;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _updateCanvasSize();
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
      _edgeDarken = p.edgeDarken;
      _denoise = p.denoise;
      _cellShading = p.cellShading;
      _colourCrush = p.colourCrush;
      _cellThickness = p.cellThickness;
      _mangaRageAura = p.mangaRageAura;
      _mangaRageSpread = p.mangaRageSpread;
      _mangaRageJitter = p.mangaRageJitter;
      _flickerIntensity = p.flickerIntensity;
      _flickerSpeed = p.flickerSpeed;
      _dustParticles = p.dustParticles;
      _dustIntensity = p.dustIntensity;
      _dustSpeed = p.dustSpeed;
      _selectedRatio = p.aspectRatio;
      _loadVideo(p.videoPath);
    }
  }

  void _updateCanvasSize() {
    const baseHeight = 1080;
    final ratio = _getAspectRatioValue(_selectedRatio);
    final scaledHeight = (baseHeight * gPreviewScale).round();
    final scaledWidth = (scaledHeight * ratio).round();
    _canvasWidth = scaledWidth;
    _canvasHeight = scaledHeight;
  }

  Future<void> _loadShader() async {
    try {
      final byteData = await rootBundle.load('assets/shaders/aereality_core.spv');
      _spirvShader = byteData.buffer.asUint8List();
      initVulkan(_spirvShader!);
    } catch (e) {
      print('❌ SPIR-V load error: $e');
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
          _startTimelinePreview();
        });
    });
  }

  void _startTimelinePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) async {
      if (_controller == null || !_controller!.value.isInitialized || _isUpdating) return;
      _isUpdating = true;
      try {
        final renderObject = _videoCaptureKey.currentContext?.findRenderObject();
        if (renderObject is RenderRepaintBoundary) {
          final frame = await renderObject.toImage();
          final processed = await _processFrameWithVulkan(frame);
          if (mounted) setState(() => _processedImage = processed);
          frame.dispose();
        }
      } catch (_) {}
      _isUpdating = false;
    });
  }

  void _stopTimelinePreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
  }

  Float32List _packUniforms() {
    final uniforms = Float32List(24);
    // Time uniform driven by video playback progress
    final timeSeconds = _controller != null && _controller!.value.isInitialized
        ? _controller!.value.position.inMilliseconds / 1000.0
        : 0.0;
    uniforms[0] = timeSeconds;
    uniforms[1] = _brightness;
    uniforms[2] = _saturation;
    uniforms[3] = _contrast;
    uniforms[4] = _sharpness;
    uniforms[5] = _gamma;
    uniforms[6] = _hue;
    uniforms[7] = _temperature;
    uniforms[8] = _glowIntensity;
    uniforms[9] = _lookMix;
    uniforms[10] = _vignette;
    uniforms[11] = _splitToning;
    uniforms[12] = _edgeDarken;
    uniforms[13] = _denoise;
    uniforms[14] = _cellShading;
    uniforms[15] = _colourCrush;
    uniforms[16] = _cellThickness;
    uniforms[17] = _mangaRageAura;
    uniforms[18] = _mangaRageSpread;
    uniforms[19] = _mangaRageJitter;
    uniforms[20] = _flickerIntensity;
    uniforms[21] = _flickerSpeed;
    uniforms[22] = _dustParticles ? 1.0 : 0.0;
    uniforms[23] = _dustIntensity;
    return uniforms;
  }

  Future<ui.Image> _processFrameWithVulkan(ui.Image input) async {
    final byteData = await input.toByteData(format: ui.ImageByteFormat.rawRgba);
    final inputBytes = byteData!.buffer.asUint8List();

    final uniforms = _packUniforms();
    final outputBytes = processImage(
      inputBytes,
      input.width,
      input.height,
      _canvasWidth,
      _canvasHeight,
      uniforms,
    );

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      outputBytes,
      _canvasWidth,
      _canvasHeight,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future;
  }

  double _getAspectRatioValue(String ratio) {
    switch (ratio) {
      case "4:5": return 4 / 5;
      case "16:9": return 16 / 9;
      case "9:16": return 9 / 16;
      case "1:1": return 1 / 1;
      case "3:4": return 3 / 4;
      case "21:9": return 21 / 9;
      default: return 4 / 5;
    }
  }

  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case 'Gon: Menacing Rage':
          _brightness = -0.05; _saturation = 1.15; _contrast = 1.55; _sharpness = 0.50; _gamma = 0.90;
          _hue = 0.0; _temperature = 5800.0; _glowIntensity = 0.25; _lookMix = 0.15;
          _vignette = 0.20; _splitToning = 0.15; _edgeDarken = 0.38;
          _denoise = 0.0; _cellShading = 0.35; _colourCrush = 0.10; _cellThickness = 0.3;
          _mangaRageAura = 0.65; _mangaRageSpread = 0.50; _mangaRageJitter = 0.65;
          _flickerIntensity = 0.15; _flickerSpeed = 3.2;
          _dustParticles = true; _dustIntensity = 0.48; _dustSpeed = 1.1;
          break;
        case 'Adevob: Junho Jr':
          _brightness = 0.05; _saturation = 1.35; _contrast = 1.30; _sharpness = 0.50; _gamma = 0.92;
          _hue = 0.0; _temperature = 6000.0; _glowIntensity = 0.45; _lookMix = 0.25;
          _vignette = 0.20; _splitToning = 0.20; _edgeDarken = 0.15;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0; _cellThickness = 0.3;
          _mangaRageAura = 0.0; _flickerIntensity = 0.0; _dustParticles = false;
          break;
        case 'Dantaes CC':
          _brightness = -0.05; _saturation = 1.25; _contrast = 1.45; _sharpness = 0.60; _gamma = 0.88;
          _hue = 0.0; _temperature = 6800.0; _glowIntensity = 0.35; _lookMix = 0.0;
          _vignette = 0.30; _splitToning = 0.35; _edgeDarken = 0.25;
          _denoise = 0.0; _cellShading = 0.20; _colourCrush = 0.15; _cellThickness = 0.3;
          _mangaRageAura = 0.0; _flickerIntensity = 0.0; _dustParticles = false;
          break;
        case 'Gojo: Infinite Void':
          _brightness = 0.15; _saturation = 1.40; _contrast = 1.25; _sharpness = 0.40; _gamma = 0.95;
          _hue = -5.0; _temperature = 7500.0; _glowIntensity = 0.60; _lookMix = 0.30;
          _vignette = 0.15; _splitToning = 0.40; _edgeDarken = 0.10;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0; _cellThickness = 0.3;
          _mangaRageAura = 0.0; _flickerIntensity = 0.08; _dustParticles = true; _dustIntensity = 0.40;
          break;
        case 'Teal & Orange WIS':
          _brightness = 0.0; _saturation = 1.40; _contrast = 1.35; _sharpness = 0.30; _gamma = 0.95;
          _hue = 0.0; _temperature = 5500.0; _glowIntensity = 0.25; _lookMix = 0.70;
          _vignette = 0.20; _splitToning = 0.10; _edgeDarken = 0.10;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0; _cellThickness = 0.3;
          _mangaRageAura = 0.0; _flickerIntensity = 0.0; _dustParticles = false;
          break;
        case 'Magic Bullet Pro':
          _brightness = 0.0; _saturation = 1.20; _contrast = 1.50; _sharpness = 0.25; _gamma = 0.95;
          _hue = 0.0; _temperature = 5600.0; _glowIntensity = 0.20; _lookMix = 0.10;
          _vignette = 0.25; _splitToning = 0.40; _edgeDarken = 0.20;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0; _cellThickness = 0.3;
          _mangaRageAura = 0.0; _flickerIntensity = 0.0; _dustParticles = false;
          break;
      }
    });
  }

  // ---------- EXPORT SHEET (Persistent state across chip selections) ----------
  void _showExportSheet() {
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBit = '35 Mbps';
    String selectedColorDepth = '8-bit SDR';
    String selectedContainer = 'MP4';
    String selectedAudioBitrate = '256k';

    final containers = ['MP4', 'WebM', 'MOV'];
    final colorDepths = ['8-bit SDR', '10-bit HDR'];
    final resolutions = ['720p', '1080p', '2K'];
    final fpsOptions = ['30fps', '60fps', '90fps'];
    final bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F12),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.between,
                      children: [
                        const Text('Master Render Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Text('32-bit Floating Point Compute Export', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // Container
                    const Text('CONTAINER', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: containers.map((c) => ChoiceChip(
                        label: Text(c),
                        selected: selectedContainer == c,
                        selectedColor: const Color(0xFF00F0FF),
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedContainer == c ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedContainer = c);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Color Depth
                    const Text('COLOR DEPTH', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: colorDepths.map((d) => ChoiceChip(
                        label: Text(d),
                        selected: selectedColorDepth == d,
                        selectedColor: const Color(0xFF00F0FF),
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedColorDepth == d ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedColorDepth = d);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Resolution
                    const Text('OUTPUT RESOLUTION', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: resolutions.map((res) => ChoiceChip(
                        label: Text(res),
                        selected: selectedRes == res,
                        selectedColor: const Color(0xFF00F0FF),
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedRes = res);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Frame Rate
                    const Text('FRAMERATE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: fpsOptions.map((fps) => ChoiceChip(
                        label: Text(fps),
                        selected: selectedFps == fps,
                        selectedColor: const Color(0xFF00F0FF),
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedFps == fps ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedFps = fps);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Bitrate
                    const Text('TARGET BITRATE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: bitrateOptions.map((bit) => ChoiceChip(
                        label: Text(bit),
                        selected: selectedBit == bit,
                        selectedColor: const Color(0xFF00F0FF),
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedBit == bit ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedBit = bit);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportVideo(selectedRes, selectedFps, selectedBit, selectedColorDepth, selectedContainer, selectedAudioBitrate);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F0FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('RENDER $selectedContainer MASTER VIDEO', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- EXPORT VIDEO (Zero Empty Frames + -start_number 1) ----------
  Future<void> _exportVideo(String resolution, String fps, String bitrate, String colorDepth, String container, String audioBitrate) async {
    if (_controller == null || !_controller!.value.isInitialized || _currentVideoPath == null) return;

    final uniforms = _packUniforms();

    int outW, outH;
    switch (resolution) {
      case '720p': outW = 1280; outH = 720; break;
      case '1080p': outW = 1920; outH = 1080; break;
      case '2K': outW = 2560; outH = 1440; break;
      default: outW = 1920; outH = 1080;
    }

    int bitrateKbps = (bitrate == '15 Mbps') ? 15000 : (bitrate == '50 Mbps') ? 50000 : 35000;
    int targetFps = int.parse(fps.replaceAll('fps', ''));
    String pixFmt = (colorDepth == '10-bit HDR') ? 'yuv420p10le' : 'yuv420p';
    String containerExt = container.toLowerCase();

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Extracting frames...');
    BuildContext? dialogCtx;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return AlertDialog(
          backgroundColor: const Color(0xFF101014),
          title: const Text('Exporting Master Video', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => LinearProgressIndicator(value: progress, color: const Color(0xFF00F0FF), backgroundColor: Colors.white12),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (_, status, __) => Text(status, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );

    try {
      final dir = await getTemporaryDirectory();
      final videoPath = _currentVideoPath!;
      final framesDir = Directory('${dir.path}/export_frames');
      final processedDir = Directory('${dir.path}/export_processed');
      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      if (await processedDir.exists()) await processedDir.delete(recursive: true);
      await framesDir.create();
      await processedDir.create();

      final extractCmd = '-i "$videoPath" -vsync 0 -f image2 "${framesDir.path}/frame_%05d.png"';
      await FFmpegKit.execute(extractCmd);

      final frameFiles = await framesDir.list().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));

      final totalFrames = frameFiles.length;
      final exportWidth = (1080 * _getAspectRatioValue(_selectedRatio)).round();
      const exportHeight = 1080;

      for (int i = 0; i < totalFrames; i++) {
        final file = frameFiles[i];
        if (file is! File) continue;
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;

        final rawInput = decoded.getBytes(order: img.ChannelOrder.rgba);

        // Update time dynamically across frames for procedural shaders
        uniforms[0] = i / targetFps.toDouble();

        final outputRaw = processImage(
          rawInput,
          decoded.width,
          decoded.height,
          exportWidth,
          exportHeight,
          uniforms,
        );

        final gradedImg = img.Image.fromBytes(
          width: exportWidth,
          height: exportHeight,
          bytes: outputRaw.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );

        final pngBytes = img.encodePng(gradedImg);
        final paddedIndex = (i + 1).toString().padLeft(5, '0');
        final outputFile = File('${processedDir.path}/frame_$paddedIndex.png');
        await outputFile.writeAsBytes(pngBytes);

        progressNotifier.value = (i + 1) / totalFrames;
        statusNotifier.value = 'Grading frame ${i + 1} / $totalFrames...';
      }

      statusNotifier.value = 'Assembling final video stream...';
      final silentOutputPath = '${dir.path}/silent_video_${DateTime.now().millisecondsSinceEpoch}.$containerExt';

      // CRITICAL FIX: -start_number 1 matches frame_00001.png perfectly
      String encodeCmd;
      if (container == 'WebM') {
        encodeCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v libvpx-vp9 -b:v ${bitrateKbps}k -pix_fmt $pixFmt "$silentOutputPath"';
      } else if (container == 'MOV') {
        encodeCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v prores_ks -profile:v 3 -pix_fmt $pixFmt "$silentOutputPath"';
      } else {
        encodeCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v libx264 -preset medium -crf 20 -pix_fmt $pixFmt "$silentOutputPath"';
      }

      var session = await FFmpegKit.execute(encodeCmd);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        final fallbackCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v mpeg4 -q:v 4 -pix_fmt yuv420p "$silentOutputPath"';
        await FFmpegKit.execute(fallbackCmd);
      }

      final audioPath = '${dir.path}/audio.aac';
      await FFmpegKit.execute('-i "$videoPath" -vn -acodec copy "$audioPath"');

      final finalOutputPath = '${dir.path}/AEReality_Master_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      await FFmpegKit.execute('-i "$silentOutputPath" -i "$audioPath" -c copy -shortest "$finalOutputPath"');

      final extStorage = await getExternalStorageDirectory();
      final moviesDir = Directory('${extStorage?.parent.parent.path}/Movies');
      if (!await moviesDir.exists()) await moviesDir.create(recursive: true);
      final destFile = File('${moviesDir.path}/${finalOutputPath.split('/').last}');
      await File(finalOutputPath).copy(destFile.path);

      if (dialogCtx != null) Navigator.pop(dialogCtx!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Master Rendered to:\n${destFile.path}'), duration: const Duration(seconds: 6), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (dialogCtx != null) Navigator.pop(dialogCtx!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildSliderRow(String label, double min, double max, double value, ValueChanged<double> onChanged, {double step = 0.05, String unit = ''}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 105,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
                activeTrackColor: const Color(0xFF00F0FF),
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${value.toStringAsFixed(2)}$unit',
              style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: _processedImage != null
                  ? AspectRatio(
                      aspectRatio: _getAspectRatioValue(_selectedRatio),
                      child: RawImage(image: _processedImage, fit: BoxFit.contain),
                    )
                  : const CircularProgressIndicator(color: Color(0xFF00F0FF)),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 30),
                onPressed: () => setState(() => _isFullscreen = false),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName ?? 'Untitled Project'),
        actions: [
          IconButton(
            icon: const Icon(Icons.aspect_ratio),
            tooltip: 'Aspect Ratio',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF101014),
                builder: (_) => SafeArea(
                  child: Wrap(
                    children: ["4:5", "9:16", "16:9", "1:1", "3:4", "21:9"].map((r) => ListTile(
                      title: Text(r, style: const TextStyle(color: Colors.white)),
                      trailing: _selectedRatio == r ? const Icon(Icons.check, color: Color(0xFF00F0FF)) : null,
                      onTap: () {
                        setState(() {
                          _selectedRatio = r;
                          _updateCanvasSize();
                        });
                        Navigator.pop(context);
                      },
                    )).toList(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Fullscreen Preview',
            onPressed: () => setState(() => _isFullscreen = true),
          ),
        ],
      ),
      body: Column(
        children: [
          // PREVIEW CANVAS
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  if (_controller != null && _controller!.value.isInitialized)
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.01,
                        child: RepaintBoundary(
                          key: _videoCaptureKey,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                    ),
                  Center(
                    child: _processedImage != null
                        ? AspectRatio(
                            aspectRatio: _getAspectRatioValue(_selectedRatio),
                            child: RawImage(image: _processedImage, fit: BoxFit.contain),
                          )
                        : Container(
                            color: const Color(0xFF0C0C0F),
                            child: const Center(child: Icon(Icons.movie_outlined, size: 48, color: Colors.white24)),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // TIMELINE SCRUBBER
          Container(
            color: const Color(0xFF0A0A0D),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22),
                  onPressed: () {
                    if (_controller != null && _controller!.value.isInitialized) {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                          _isPlaying = false;
                        } else {
                          _controller!.play();
                          _isPlaying = true;
                        }
                      });
                    }
                  },
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      trackHeight: 2,
                      activeTrackColor: const Color(0xFF00F0FF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _controller != null && _controller!.value.isInitialized
                          ? _controller!.value.position.inSeconds.toDouble()
                          : 0.0,
                      min: 0,
                      max: _controller != null && _controller!.value.isInitialized
                          ? _controller!.value.duration.inSeconds.toDouble()
                          : 1.0,
                      onChanged: (v) {
                        if (_controller != null && _controller!.value.isInitialized) {
                          _controller!.seekTo(Duration(milliseconds: (v * 1000).round()));
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // TABS (Adjust / Presets / Export)
          Container(
            color: const Color(0xFF0C0C0F),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF00F0FF),
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              tabs: const [
                Tab(text: 'Adjust'),
                Tab(text: 'WIS Presets'),
                Tab(text: 'Export'),
              ],
            ),
          ),

          // TAB CONTENT
          SizedBox(
            height: 250,
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: ADJUST (Web-Matched Subcategory Pills)
                Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          _buildSubcategoryPill('color', 'Color & Tone'),
                          _buildSubcategoryPill('bloom', 'Bloom & WIS'),
                          _buildSubcategoryPill('sharpness', 'Sharpness & Lines'),
                          _buildSubcategoryPill('grade', 'Grade & Grain'),
                          _buildSubcategoryPill('anime', 'Anime FX & Manga'),
                          _buildSubcategoryPill('strobe', 'Strobe & Dust'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            if (_activeCategory == 'color') ...[
                              _buildSliderRow('Brightness', -1.0, 1.0, _brightness, (v) => setState(() => _brightness = v)),
                              _buildSliderRow('Contrast', 0.2, 2.5, _contrast, (v) => setState(() => _contrast = v)),
                              _buildSliderRow('Saturation', 0.0, 2.5, _saturation, (v) => setState(() => _saturation = v)),
                              _buildSliderRow('Gamma', 0.2, 2.5, _gamma, (v) => setState(() => _gamma = v)),
                              _buildSliderRow('Temperature', 2500, 10000, _temperature, (v) => setState(() => _temperature = v), unit: 'K'),
                              _buildSliderRow('Hue Shift', -180, 180, _hue, (v) => setState(() => _hue = v), unit: '°'),
                              _buildSliderRow('Color Crush', 0.0, 0.5, _colourCrush, (v) => setState(() => _colourCrush = v)),
                            ] else if (_activeCategory == 'bloom') ...[
                              _buildSliderRow('Glow Intensity', 0.0, 2.0, _glowIntensity, (v) => setState(() => _glowIntensity = v)),
                              _buildSliderRow('Vignette', 0.0, 1.0, _vignette, (v) => setState(() => _vignette = v)),
                              _buildSliderRow('Perimeter Darken', 0.0, 1.0, _edgeDarken, (v) => setState(() => _edgeDarken = v)),
                            ] else if (_activeCategory == 'sharpness') ...[
                              _buildSliderRow('Sharpness', 0.0, 2.0, _sharpness, (v) => setState(() => _sharpness = v)),
                              _buildSliderRow('Cell Outlines', 0.0, 1.0, _cellShading, (v) => setState(() => _cellShading = v)),
                              _buildSliderRow('Outline Thickness', 0.1, 1.0, _cellThickness, (v) => setState(() => _cellThickness = v)),
                            ] else if (_activeCategory == 'grade') ...[
                              _buildSliderRow('Denoise', 0.0, 1.0, _denoise, (v) => setState(() => _denoise = v)),
                              _buildSliderRow('Look Mix', 0.0, 1.0, _lookMix, (v) => setState(() => _lookMix = v)),
                              _buildSliderRow('Split Toning', 0.0, 1.0, _splitToning, (v) => setState(() => _splitToning = v)),
                            ] else if (_activeCategory == 'anime') ...[
                              _buildSliderRow('Gon Manga Aura', 0.0, 1.0, _mangaRageAura, (v) => setState(() => _mangaRageAura = v)),
                              _buildSliderRow('Tendril Spread', 0.0, 1.0, _mangaRageSpread, (v) => setState(() => _mangaRageSpread = v)),
                              _buildSliderRow('Aura Jitter', 0.0, 1.0, _mangaRageJitter, (v) => setState(() => _mangaRageJitter = v)),
                            ] else if (_activeCategory == 'strobe') ...[
                              _buildSliderRow('Flicker Strobe', 0.0, 1.0, _flickerIntensity, (v) => setState(() => _flickerIntensity = v)),
                              _buildSliderRow('Flicker Speed', 0.1, 10.0, _flickerSpeed, (v) => setState(() => _flickerSpeed = v), unit: 'x'),
                              SwitchListTile(
                                title: const Text('Floating Dust Motes', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                value: _dustParticles,
                                activeColor: const Color(0xFF00F0FF),
                                onChanged: (v) => setState(() => _dustParticles = v),
                              ),
                              if (_dustParticles) ...[
                                _buildSliderRow('Dust Intensity', 0.0, 1.0, _dustIntensity, (v) => setState(() => _dustIntensity = v)),
                                _buildSliderRow('Dust Drift Speed', 0.1, 3.0, _dustSpeed, (v) => setState(() => _dustSpeed = v), unit: 'x'),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // TAB 2: PRESETS
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _buildPresetCard('Gon: Menacing Rage', 'Chimera Ant rage aura, black manga speedlines & dust'),
                    _buildPresetCard('Adevob: Junho Jr', 'Golden specular bloom & deep black crush'),
                    _buildPresetCard('Dantaes CC', 'High-voltage contrast & anime outlines'),
                    _buildPresetCard('Gojo: Infinite Void', 'Ethereal cyan specular core & cool highlights'),
                    _buildPresetCard('Teal & Orange WIS', 'Cinematic blockbusting split tone'),
                    _buildPresetCard('Magic Bullet Pro', 'Clean saturated high-gloss color grade'),
                  ],
                ),

                // TAB 3: EXPORT
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Render 32-bit floating HDR master video directly on GPU.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _showExportSheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F0FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('OPEN EXPORT SETTINGS', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildSubcategoryPill(String id, String label) {
    final isSelected = _activeCategory == id;
    return GestureDetector(
      onTap: () => setState(() => _activeCategory = id),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F0FF) : const Color(0xFF141418),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF00F0FF) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetCard(String name, String desc) {
    return GestureDetector(
      onTap: () {
        _applyPreset(name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied preset "$name"'), duration: const Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF101014),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopTimelinePreview();
    _controller?.removeListener(_listener);
    _controller?.dispose();
    cleanupVulkan();
    super.dispose();
  }
}
