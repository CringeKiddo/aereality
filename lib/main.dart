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

// Global Engine Precision: 16 (FP16 Fast) or 32 (FP32 True Float)
int gEnginePrecision = 16;
double gPreviewScale = 0.5;

// ---------- PROJECT DATA MODEL ----------
class ProjectData {
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, glowSpread, edgeGlow, edgeDarken;
  double vignette, splitToning, denoise, darkOutlines, blackCrush;
  double flickerIntensity, flickerSpeed;
  bool dustParticles;
  double dustIntensity, dustSpeed;
  double godRays, volumetricFog, depthOfField;
  String aspectRatio;

  // 5-Point Spline Curves: [Blacks, Shadows, Midtones, Highlights, Whites]
  List<double> curveMaster;
  List<double> curveRed;
  List<double> curveGreen;
  List<double> curveBlue;

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
    this.glowSpread = 0.35,
    this.edgeGlow = 0.0,
    this.edgeDarken = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.denoise = 0.0,
    this.darkOutlines = 0.0,
    this.blackCrush = 0.0,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 3.0,
    this.dustParticles = false,
    this.dustIntensity = 0.45,
    this.dustSpeed = 1.0,
    this.godRays = 0.0,
    this.volumetricFog = 0.0,
    this.depthOfField = 0.0,
    this.aspectRatio = "4:5",
    List<double>? curveMaster,
    List<double>? curveRed,
    List<double>? curveGreen,
    List<double>? curveBlue,
  })  : curveMaster = curveMaster ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveRed = curveRed ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveGreen = curveGreen ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveBlue = curveBlue ?? [0.0, 0.25, 0.5, 0.75, 1.0];

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
        'glowSpread': glowSpread,
        'edgeGlow': edgeGlow,
        'edgeDarken': edgeDarken,
        'vignette': vignette,
        'splitToning': splitToning,
        'denoise': denoise,
        'darkOutlines': darkOutlines,
        'blackCrush': blackCrush,
        'flickerIntensity': flickerIntensity,
        'flickerSpeed': flickerSpeed,
        'dustParticles': dustParticles,
        'dustIntensity': dustIntensity,
        'dustSpeed': dustSpeed,
        'godRays': godRays,
        'volumetricFog': volumetricFog,
        'depthOfField': depthOfField,
        'aspectRatio': aspectRatio,
        'curveMaster': curveMaster,
        'curveRed': curveRed,
        'curveGreen': curveGreen,
        'curveBlue': curveBlue,
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
        glowSpread: (json['glowSpread'] ?? 0.35).toDouble(),
        edgeGlow: (json['edgeGlow'] ?? 0.0).toDouble(),
        edgeDarken: (json['edgeDarken'] ?? 0.0).toDouble(),
        vignette: (json['vignette'] ?? 0.0).toDouble(),
        splitToning: (json['splitToning'] ?? 0.0).toDouble(),
        denoise: (json['denoise'] ?? 0.0).toDouble(),
        darkOutlines: (json['darkOutlines'] ?? 0.0).toDouble(),
        blackCrush: (json['blackCrush'] ?? 0.0).toDouble(),
        flickerIntensity: (json['flickerIntensity'] ?? 0.0).toDouble(),
        flickerSpeed: (json['flickerSpeed'] ?? 3.0).toDouble(),
        dustParticles: json['dustParticles'] ?? false,
        dustIntensity: (json['dustIntensity'] ?? 0.45).toDouble(),
        dustSpeed: (json['dustSpeed'] ?? 1.0).toDouble(),
        godRays: (json['godRays'] ?? 0.0).toDouble(),
        volumetricFog: (json['volumetricFog'] ?? 0.0).toDouble(),
        depthOfField: (json['depthOfField'] ?? 0.0).toDouble(),
        aspectRatio: json['aspectRatio'] ?? "4:5",
        curveMaster: (json['curveMaster'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveRed: (json['curveRed'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveGreen: (json['curveGreen'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveBlue: (json['curveBlue'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

class StoredProject {
  String id, name, videoPath;
  ProjectData data;
  DateTime lastOpened;

  StoredProject({required this.id, required this.name, required this.videoPath, required this.data, required this.lastOpened});

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
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => setState(() {})),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'VULKAN ${gEnginePrecision}-BIT COMPUTE',
                  style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    gEnginePrecision == 32 ? 'FP32 TRUE FLOAT' : 'FP16 ULTRA FAST',
                    style: const TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Professional WIS Grading Engine', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Hardware-accelerated deep optical glow, spline curves, and black crush on Mali & Adreno GPUs.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())).then((_) => _load()),
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
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsScreen())).then((_) => _load()),
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
  late int _tempPrecision;

  @override
  void initState() {
    super.initState();
    _tempScale = gPreviewScale;
    _tempPrecision = gEnginePrecision;
  }

  @override
  Widget build(BuildContext context) {
    final resLabel = (_tempScale <= 0.35)
        ? '360p (Fast Mobile Scrubber)'
        : (_tempScale <= 0.55)
            ? '540p (Balanced 60fps)'
            : (_tempScale <= 0.75)
                ? '720p (High Precision)'
                : '1080p (Native Pixel Match)';

    return Scaffold(
      appBar: AppBar(title: const Text('Engine Settings')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VULKAN HARDWARE COMPUTE PRECISION', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            const Text('Toggle between double-throughput FP16 or full 32-bit floating HDR buffers on your GPU.', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('16-Bit Half Float ⚡'),
                    selected: _tempPrecision == 16,
                    selectedColor: const Color(0xFF00F0FF),
                    backgroundColor: const Color(0xFF101014),
                    labelStyle: TextStyle(color: _tempPrecision == 16 ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                    onSelected: (sel) {
                      if (sel) setState(() => _tempPrecision = 16);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('32-Bit True Float 💎'),
                    selected: _tempPrecision == 32,
                    selectedColor: const Color(0xFF00F0FF),
                    backgroundColor: const Color(0xFF101014),
                    labelStyle: TextStyle(color: _tempPrecision == 32 ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                    onSelected: (sel) {
                      if (sel) setState(() => _tempPrecision = 32);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Text('TIMELINE PREVIEW FIDELITY', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  gPreviewScale = _tempScale;
                  gEnginePrecision = _tempPrecision;
                  setEnginePrecision(_tempPrecision);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Settings saved: ${gEnginePrecision}-bit float active!'), backgroundColor: Colors.green),
                  );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F0FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('SAVE & APPLY ENGINE CONFIG', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      _selectedFile == null ? 'Tap to select video footage' : _selectedFile!.path.split('/').last,
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
  bool _isMuted = false;
  String? _currentVideoPath;

  String _activeCategory = 'color';
  String _activeCurveChannel = 'master'; // 'master' | 'red' | 'green' | 'blue'

  // Master Sliders
  double _brightness = 0.0;
  double _saturation = 1.0;
  double _contrast = 1.0;
  double _sharpness = 0.0;
  double _gamma = 1.0;
  double _hue = 0.0;
  double _temperature = 6500.0;
  double _glowIntensity = 0.0;
  double _glowSpread = 0.35;
  double _edgeGlow = 0.0;
  double _edgeDarken = 0.0;
  double _vignette = 0.0;
  double _splitToning = 0.0;
  double _denoise = 0.0;
  double _darkOutlines = 0.0;
  double _blackCrush = 0.0;
  double _flickerIntensity = 0.0;
  double _flickerSpeed = 3.0;
  bool _dustParticles = false;
  double _dustIntensity = 0.45;
  double _dustSpeed = 1.0;
  double _godRays = 0.0;
  double _volumetricFog = 0.0;
  double _depthOfField = 0.0;

  // 5-Point Splines: [Blacks, Shadows, Midtones, Highlights, Whites]
  List<double> _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
  List<double> _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
  List<double> _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
  List<double> _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];

  String _selectedRatio = "4:5";
  late TabController _tabController;
  VoidCallback _listener = () {};

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
      _glowSpread = p.glowSpread;
      _edgeGlow = p.edgeGlow;
      _edgeDarken = p.edgeDarken;
      _vignette = p.vignette;
      _splitToning = p.splitToning;
      _denoise = p.denoise;
      _darkOutlines = p.darkOutlines;
      _blackCrush = p.blackCrush;
      _flickerIntensity = p.flickerIntensity;
      _flickerSpeed = p.flickerSpeed;
      _dustParticles = p.dustParticles;
      _dustIntensity = p.dustIntensity;
      _dustSpeed = p.dustSpeed;
      _godRays = p.godRays;
      _volumetricFog = p.volumetricFog;
      _depthOfField = p.depthOfField;
      _selectedRatio = p.aspectRatio;
      _curveMaster = List.from(p.curveMaster);
      _curveRed = List.from(p.curveRed);
      _curveGreen = List.from(p.curveGreen);
      _curveBlue = List.from(p.curveBlue);
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
      final spvPath = gEnginePrecision == 32
          ? 'assets/shaders/aereality_core_32.spv'
          : 'assets/shaders/aereality_core_16.spv';
      final byteData = await rootBundle.load(spvPath);
      final spirvShader = byteData.buffer.asUint8List();
      initVulkan(spirvShader, gEnginePrecision);
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
    final uniforms = Float32List(58);
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
    uniforms[9] = _glowSpread;
    uniforms[10] = _edgeGlow;
    uniforms[11] = _edgeDarken;
    uniforms[12] = _vignette;
    uniforms[13] = _splitToning;
    uniforms[14] = _denoise;
    uniforms[15] = _darkOutlines;
    uniforms[16] = _blackCrush;
    uniforms[17] = _flickerIntensity;
    uniforms[18] = _flickerSpeed;
    uniforms[19] = _dustParticles ? 1.0 : 0.0;
    uniforms[20] = _dustIntensity;
    uniforms[21] = _dustSpeed;
    uniforms[22] = _godRays;
    uniforms[23] = _volumetricFog;
    uniforms[24] = _depthOfField;
    uniforms[25] = 0.0; // pad0

    // Master Curve (8 floats)
    uniforms[26] = _curveMaster[0];
    uniforms[27] = _curveMaster[1];
    uniforms[28] = _curveMaster[2];
    uniforms[29] = _curveMaster[3];
    uniforms[30] = _curveMaster[4];
    uniforms[31] = 0.0; uniforms[32] = 0.0; uniforms[33] = 0.0;

    // Red Curve (8 floats)
    uniforms[34] = _curveRed[0];
    uniforms[35] = _curveRed[1];
    uniforms[36] = _curveRed[2];
    uniforms[37] = _curveRed[3];
    uniforms[38] = _curveRed[4];
    uniforms[39] = 0.0; uniforms[40] = 0.0; uniforms[41] = 0.0;

    // Green Curve (8 floats)
    uniforms[42] = _curveGreen[0];
    uniforms[43] = _curveGreen[1];
    uniforms[44] = _curveGreen[2];
    uniforms[45] = _curveGreen[3];
    uniforms[46] = _curveGreen[4];
    uniforms[47] = 0.0; uniforms[48] = 0.0; uniforms[49] = 0.0;

    // Blue Curve (8 floats)
    uniforms[50] = _curveBlue[0];
    uniforms[51] = _curveBlue[1];
    uniforms[52] = _curveBlue[2];
    uniforms[53] = _curveBlue[3];
    uniforms[54] = _curveBlue[4];
    uniforms[55] = 0.0; uniforms[56] = 0.0; uniforms[57] = 0.0;

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

  void _resetAllEffects() {
    setState(() {
      _brightness = 0.0;
      _saturation = 1.0;
      _contrast = 1.0;
      _sharpness = 0.0;
      _gamma = 1.0;
      _hue = 0.0;
      _temperature = 6500.0;
      _glowIntensity = 0.0;
      _glowSpread = 0.35;
      _edgeGlow = 0.0;
      _edgeDarken = 0.0;
      _vignette = 0.0;
      _splitToning = 0.0;
      _denoise = 0.0;
      _darkOutlines = 0.0;
      _blackCrush = 0.0;
      _flickerIntensity = 0.0;
      _flickerSpeed = 3.0;
      _dustParticles = false;
      _dustIntensity = 0.45;
      _dustSpeed = 1.0;
      _godRays = 0.0;
      _volumetricFog = 0.0;
      _depthOfField = 0.0;
      _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All effects reset to neutral default!'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _saveCurrentProject() async {
    if (_currentVideoPath == null) return;
    final project = StoredProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: widget.projectName ?? 'Untitled Project',
      videoPath: _currentVideoPath!,
      data: ProjectData(
        videoPath: _currentVideoPath!,
        brightness: _brightness,
        saturation: _saturation,
        contrast: _contrast,
        sharpness: _sharpness,
        gamma: _gamma,
        hue: _hue,
        temperature: _temperature,
        glowIntensity: _glowIntensity,
        glowSpread: _glowSpread,
        edgeGlow: _edgeGlow,
        edgeDarken: _edgeDarken,
        vignette: _vignette,
        splitToning: _splitToning,
        denoise: _denoise,
        darkOutlines: _darkOutlines,
        blackCrush: _blackCrush,
        flickerIntensity: _flickerIntensity,
        flickerSpeed: _flickerSpeed,
        dustParticles: _dustParticles,
        dustIntensity: _dustIntensity,
        dustSpeed: _dustSpeed,
        godRays: _godRays,
        volumetricFog: _volumetricFog,
        depthOfField: _depthOfField,
        aspectRatio: _selectedRatio,
        curveMaster: _curveMaster,
        curveRed: _curveRed,
        curveGreen: _curveGreen,
        curveBlue: _curveBlue,
      ),
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(project);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project saved successfully!'), backgroundColor: Colors.green),
    );
  }

  // Exact 2026 YouTube WIS Presets Analyzed from URLs
  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case 'vintage cc':
          _brightness = 0.08; _saturation = 0.88; _contrast = 1.15; _sharpness = 0.20; _gamma = 1.05;
          _temperature = 5700.0; _glowIntensity = 0.25; _glowSpread = 0.45; _edgeDarken = 0.15;
          _vignette = 0.35; _splitToning = 0.25; _blackCrush = 0.08; _dustParticles = true;
          _dustIntensity = 0.40; _dustSpeed = 0.8;
          _curveMaster = [0.06, 0.28, 0.50, 0.74, 0.94];
          break;
        case 'adevob+junho':
          _brightness = 0.04; _saturation = 1.45; _contrast = 1.65; _sharpness = 0.85; _gamma = 0.90;
          _temperature = 5900.0; _glowIntensity = 0.65; _glowSpread = 0.40; _edgeGlow = 0.25;
          _edgeDarken = 0.20; _vignette = 0.25; _blackCrush = 0.42; _darkOutlines = 0.50;
          _curveMaster = [0.0, 0.18, 0.50, 0.82, 1.0];
          break;
        case 'adevobfiller':
          _brightness = 0.02; _saturation = 1.35; _contrast = 1.45; _sharpness = 0.60; _gamma = 0.94;
          _temperature = 6100.0; _glowIntensity = 0.45; _glowSpread = 0.55; _edgeDarken = 0.12;
          _vignette = 0.18; _blackCrush = 0.28; _darkOutlines = 0.35;
          _curveMaster = [0.0, 0.20, 0.50, 0.80, 1.0];
          break;
        case 'uryu vs ichigo':
          _brightness = -0.02; _saturation = 1.25; _contrast = 1.55; _sharpness = 0.75; _gamma = 0.92;
          _temperature = 8200.0; _glowIntensity = 0.55; _glowSpread = 0.35; _edgeGlow = 0.45;
          _edgeDarken = 0.25; _vignette = 0.28; _splitToning = 0.40; _blackCrush = 0.38; _darkOutlines = 0.60;
          _curveMaster = [0.0, 0.16, 0.48, 0.84, 1.0];
          break;
        case 'saber vs Rin':
          _brightness = 0.06; _saturation = 1.50; _contrast = 1.50; _sharpness = 0.70; _gamma = 0.92;
          _temperature = 6600.0; _glowIntensity = 0.80; _glowSpread = 0.60; _godRays = 0.45;
          _edgeGlow = 0.35; _vignette = 0.20; _blackCrush = 0.30;
          _curveMaster = [0.0, 0.22, 0.52, 0.85, 1.0];
          break;
        case 'Dantae cc':
          _brightness = -0.04; _saturation = 1.30; _contrast = 1.60; _sharpness = 0.90; _gamma = 0.88;
          _temperature = 6900.0; _glowIntensity = 0.40; _glowSpread = 0.30; _edgeDarken = 0.32;
          _vignette = 0.25; _blackCrush = 0.45; _darkOutlines = 0.70;
          _curveMaster = [0.0, 0.14, 0.48, 0.85, 1.0];
          break;
        case 'toji junho':
          _brightness = 0.0; _saturation = 1.15; _contrast = 1.70; _sharpness = 0.85; _gamma = 0.86;
          _temperature = 6200.0; _glowIntensity = 0.50; _glowSpread = 0.38; _edgeDarken = 0.28;
          _vignette = 0.30; _blackCrush = 0.50; _darkOutlines = 0.65;
          _curveMaster = [0.0, 0.12, 0.46, 0.86, 1.0];
          break;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded preset "$name"'), duration: const Duration(seconds: 1)),
    );
  }

  // ---------- EXPORT SHEET ----------
  void _showExportSheet() {
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBit = '35 Mbps';
    String selectedContainer = 'MP4';
    String selectedAudioCodec = 'AAC High Fidelity';
    String selectedAudioBitrate = '256k';
    String selectedSampleRate = '48000';

    final containers = ['MP4', 'WebM', 'MOV'];
    final resolutions = ['720p', '1080p', '2K'];
    final fpsOptions = ['30fps', '60fps', '90fps'];
    final bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps'];
    final audioCodecs = ['AAC High Fidelity', 'Opus Studio', 'MP3 320k'];
    final audioBitrates = ['168k', '256k', '320k'];
    final sampleRates = ['44100', '48000'];

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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Master Render Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Text(
                      'Vulkan ${gEnginePrecision}-bit Compute Pipeline',
                      style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
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

                    // Video Bitrate
                    const Text('VIDEO BITRATE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
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
                    const SizedBox(height: 14),

                    // Audio Settings
                    const Text('AUDIO MASTER EXPORT', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: audioCodecs.map((ac) => ChoiceChip(
                        label: Text(ac),
                        selected: selectedAudioCodec == ac,
                        selectedColor: const Color(0xFF00F0FF),
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedAudioCodec == ac ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedAudioCodec = ac);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('BITRATE', style: TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace')),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: selectedAudioBitrate,
                                dropdownColor: const Color(0xFF18181E),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF18181E),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: audioBitrates.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 12)))).toList(),
                                onChanged: (v) => setStateModal(() => selectedAudioBitrate = v!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SAMPLE RATE', style: TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace')),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: selectedSampleRate,
                                dropdownColor: const Color(0xFF18181E),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF18181E),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: sampleRates.map((s) => DropdownMenuItem(value: s, child: Text('${s} Hz', style: const TextStyle(fontSize: 12)))).toList(),
                                onChanged: (v) => setStateModal(() => selectedSampleRate = v!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportVideo(
                            selectedRes,
                            selectedFps,
                            selectedBit,
                            selectedContainer,
                            selectedAudioCodec,
                            selectedAudioBitrate,
                            selectedSampleRate,
                          );
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

  // ---------- EXPORT VIDEO (Public /storage/emulated/0/Download/ Fix) ----------
  Future<void> _exportVideo(
    String resolution,
    String fps,
    String bitrate,
    String container,
    String audioCodec,
    String audioBitrate,
    String sampleRate,
  ) async {
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

      String encodeCmd;
      if (container == 'WebM') {
        encodeCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v libvpx-vp9 -b:v ${bitrateKbps}k -pix_fmt yuv420p "$silentOutputPath"';
      } else if (container == 'MOV') {
        encodeCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v prores_ks -profile:v 3 -pix_fmt yuv420p "$silentOutputPath"';
      } else {
        encodeCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p "$silentOutputPath"';
      }

      var session = await FFmpegKit.execute(encodeCmd);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        final fallbackCmd = '-start_number 1 -framerate $targetFps -i "${processedDir.path}/frame_%05d.png" -vf scale=$outW:$outH -c:v mpeg4 -q:v 3 -pix_fmt yuv420p "$silentOutputPath"';
        await FFmpegKit.execute(fallbackCmd);
      }

      final audioPath = '${dir.path}/extracted_audio.aac';
      await FFmpegKit.execute('-i "$videoPath" -vn -acodec copy "$audioPath"');

      String audioCodecParam = audioCodec.contains('Opus') ? 'libopus' : audioCodec.contains('MP3') ? 'libmp3lame' : 'aac';
      final finalOutputPath = '${dir.path}/AEReality_Master_${DateTime.now().millisecondsSinceEpoch}.$containerExt';

      await FFmpegKit.execute(
        '-i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $audioCodecParam -b:a $audioBitrate -ar $sampleRate -shortest "$finalOutputPath"',
      );

      // PUBLIC DOWNLOADS FOLDER FIX (Bypasses Scoped Storage errno = 13)
      Directory exportDir = Directory('/storage/emulated/0/Download');
      if (!await exportDir.exists()) {
        final extDir = await getExternalStorageDirectory();
        exportDir = extDir ?? await getApplicationDocumentsDirectory();
      }

      final destFile = File('${exportDir.path}/${finalOutputPath.split('/').last}');
      await File(finalOutputPath).copy(destFile.path);

      if (dialogCtx != null) Navigator.pop(dialogCtx!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Master Saved to Downloads:\n${destFile.path}'),
            duration: const Duration(seconds: 7),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (dialogCtx != null) Navigator.pop(dialogCtx!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildSliderRow(
    String label,
    double min,
    double max,
    double value,
    ValueChanged<double> onChanged, {
    double step = 0.01,
    String unit = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
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
            width: 48,
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

  // ---------- INTERACTIVE CURVES EDITOR WIDGET ----------
  Widget _buildCurvesEditor() {
    List<double> activeCurve;
    Color channelColor;
    if (_activeCurveChannel == 'red') {
      activeCurve = _curveRed;
      channelColor = Colors.redAccent;
    } else if (_activeCurveChannel == 'green') {
      activeCurve = _curveGreen;
      channelColor = Colors.greenAccent;
    } else if (_activeCurveChannel == 'blue') {
      activeCurve = _curveBlue;
      channelColor = Colors.lightBlueAccent;
    } else {
      activeCurve = _curveMaster;
      channelColor = Colors.white;
    }

    final pointLabels = ['Blacks', 'Shadows', 'Midtones', 'Highlights', 'Whites'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCurveChannelBtn('master', 'Master', Colors.white),
            const SizedBox(width: 8),
            _buildCurveChannelBtn('red', 'Red', Colors.redAccent),
            const SizedBox(width: 8),
            _buildCurveChannelBtn('green', 'Green', Colors.greenAccent),
            const SizedBox(width: 8),
            _buildCurveChannelBtn('blue', 'Blue', Colors.lightBlueAccent),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 220,
            height: 130,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0E),
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              painter: CurvePainter(points: activeCurve, color: channelColor),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < 5; i++)
          _buildSliderRow(
            pointLabels[i],
            0.0,
            1.0,
            activeCurve[i],
            (v) => setState(() => activeCurve[i] = v),
          ),
      ],
    );
  }

  Widget _buildCurveChannelBtn(String id, String label, Color c) {
    final isSel = _activeCurveChannel == id;
    return GestureDetector(
      onTap: () => setState(() => _activeCurveChannel = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? c.withOpacity(0.25) : const Color(0xFF141418),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSel ? c : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: isSel ? c : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
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
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Reset All Effects',
            onPressed: _resetAllEffects,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF00F0FF)),
            tooltip: 'Save Project',
            onPressed: _saveCurrentProject,
          ),
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

          // TIMELINE SCRUBBER & VOLUME
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
                IconButton(
                  icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
                  onPressed: () {
                    if (_controller != null && _controller!.value.isInitialized) {
                      setState(() {
                        _isMuted = !_isMuted;
                        _controller!.setVolume(_isMuted ? 0.0 : 1.0);
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

          // TABS (Adjust / WIS Presets / Export)
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
                // TAB 1: ADJUST
                Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          _buildSubcategoryPill('color', 'Color & Tone'),
                          _buildSubcategoryPill('curves', 'Curves'),
                          _buildSubcategoryPill('bloom', 'Deep Glow & Rays'),
                          _buildSubcategoryPill('sharpness', 'Sharpness & Inks'),
                          _buildSubcategoryPill('grade', 'Grade & Split'),
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
                              _buildSliderRow('Brightness', -1.0, 3.0, _brightness, (v) => setState(() => _brightness = v)),
                              _buildSliderRow('Contrast', 0.2, 3.0, _contrast, (v) => setState(() => _contrast = v)),
                              _buildSliderRow('Saturation', 0.0, 3.0, _saturation, (v) => setState(() => _saturation = v)),
                              _buildSliderRow('Gamma', 0.2, 3.0, _gamma, (v) => setState(() => _gamma = v)),
                              _buildSliderRow('Temperature', 2500, 10000, _temperature, (v) => setState(() => _temperature = v), unit: 'K'),
                              _buildSliderRow('Hue Shift', -180, 180, _hue, (v) => setState(() => _hue = v), unit: '°'),
                              _buildSliderRow('Black Crush', 0.0, 1.0, _blackCrush, (v) => setState(() => _blackCrush = v)),
                            ] else if (_activeCategory == 'curves') ...[
                              _buildCurvesEditor(),
                            ] else if (_activeCategory == 'bloom') ...[
                              _buildSliderRow('Deep Glow Intensity', 0.0, 3.0, _glowIntensity, (v) => setState(() => _glowIntensity = v)),
                              _buildSliderRow('Glow Spread', 0.1, 2.0, _glowSpread, (v) => setState(() => _glowSpread = v)),
                              _buildSliderRow('Edge Glow Outward', 0.0, 3.0, _edgeGlow, (v) => setState(() => _edgeGlow = v)),
                              _buildSliderRow('RTX God Rays', 0.0, 3.0, _godRays, (v) => setState(() => _godRays = v)),
                              _buildSliderRow('Volumetric Fog', 0.0, 3.0, _volumetricFog, (v) => setState(() => _volumetricFog = v)),
                            ] else if (_activeCategory == 'sharpness') ...[
                              _buildSliderRow('Laplacian Sharpness', 0.0, 3.0, _sharpness, (v) => setState(() => _sharpness = v)),
                              _buildSliderRow('Dark Manga Outlines', 0.0, 3.0, _darkOutlines, (v) => setState(() => _darkOutlines = v)),
                              _buildSliderRow('Edge Darken Blur', 0.0, 3.0, _edgeDarken, (v) => setState(() => _edgeDarken = v)),
                              _buildSliderRow('Depth of Field', 0.0, 3.0, _depthOfField, (v) => setState(() => _depthOfField = v)),
                            ] else if (_activeCategory == 'grade') ...[
                              _buildSliderRow('Denoise', 0.0, 1.0, _denoise, (v) => setState(() => _denoise = v)),
                              _buildSliderRow('Split Toning', 0.0, 3.0, _splitToning, (v) => setState(() => _splitToning = v)),
                              _buildSliderRow('Vignette Falloff', 0.0, 3.0, _vignette, (v) => setState(() => _vignette = v)),
                            ] else if (_activeCategory == 'strobe') ...[
                              _buildSliderRow('Black Shutter Strobe', 0.0, 3.0, _flickerIntensity, (v) => setState(() => _flickerIntensity = v)),
                              _buildSliderRow('Strobe Frequency', 0.1, 10.0, _flickerSpeed, (v) => setState(() => _flickerSpeed = v), unit: 'x'),
                              SwitchListTile(
                                title: const Text('Floating Dust Motes', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                value: _dustParticles,
                                activeColor: const Color(0xFF00F0FF),
                                onChanged: (v) => setState(() => _dustParticles = v),
                              ),
                              if (_dustParticles) ...[
                                _buildSliderRow('Dust Intensity', 0.0, 3.0, _dustIntensity, (v) => setState(() => _dustIntensity = v)),
                                _buildSliderRow('Dust Drift Speed', 0.1, 3.0, _dustSpeed, (v) => setState(() => _dustSpeed = v), unit: 'x'),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // TAB 2: WIS PRESETS
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  padding: const EdgeInsets.all(12),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _buildPresetCard('vintage cc', 'Filmic warm pedestal, soft glow & grain'),
                    _buildPresetCard('adevob+junho', 'Signature Adevob x Junho golden specular & black crush'),
                    _buildPresetCard('adevobfiller', 'High-saturation amber bloom & deep teal contrast'),
                    _buildPresetCard('uryu vs ichigo', 'Bleach TYBW cyan specular core & cold shadows'),
                    _buildPresetCard('saber vs Rin', 'Fate UBW anamorphic glow & volumetric god rays'),
                    _buildPresetCard('Dantae cc', 'High-voltage contrast, micro-sharpness & edge blur'),
                    _buildPresetCard('toji junho', 'Gritty bleach bypass, golden weapon glints & crushed gamma'),
                  ],
                ),

                // TAB 3: EXPORT
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Render directly to phone storage with Vulkan ${gEnginePrecision}-Bit Compute.',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
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
      onTap: () => _applyPreset(name),
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

// ---------- CURVE CANVAS PAINTER ----------
class CurvePainter extends CustomPainter {
  final List<double> points;
  final Color color;

  CurvePainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;

    for (int i = 1; i < 4; i++) {
      double x = size.width * (i / 4.0);
      double y = size.height * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      double px = size.width * (i / (points.length - 1));
      double py = size.height * (1.0 - points[i].clamp(0.0, 1.0));
      offsets.add(Offset(px, py));
    }

    path.moveTo(offsets[0].dx, offsets[0].dy);
    for (int i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i];
      final p1 = offsets[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    final dotPaint = Paint()..color = color;
    for (var pt in offsets) {
      canvas.drawCircle(pt, 4.0, dotPaint);
      canvas.drawCircle(pt, 2.0, Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(covariant CurvePainter oldDelegate) => true;
}
