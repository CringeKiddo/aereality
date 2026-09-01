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
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E5FF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
          titleMedium: TextStyle(color: Colors.white),
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
  double temperature, glowIntensity, lookMix, vignette, splitToning, edgeDarken;
  double denoise, cellShading, colourCrush;
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
    'edgeDarken': edgeDarken,
    'denoise': denoise,
    'cellShading': cellShading,
    'colourCrush': colourCrush,
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
    glowIntensity: json['glowIntensity'] ?? 0.0,
    lookMix: json['lookMix'] ?? 0.0,
    vignette: json['vignette'] ?? 0.0,
    splitToning: json['splitToning'] ?? 0.0,
    edgeDarken: json['edgeDarken'] ?? 0.0,
    denoise: json['denoise'] ?? 0.0,
    cellShading: json['cellShading'] ?? 0.0,
    colourCrush: json['colourCrush'] ?? 0.0,
    aspectRatio: json['aspectRatio'] ?? "16:9",
  );
}

// ---------- STORED PROJECT ----------
class StoredProject {
  String id;
  String name;
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, lookMix, vignette, splitToning, edgeDarken;
  double denoise, cellShading, colourCrush;
  String aspectRatio;
  DateTime lastOpened;

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
    this.edgeDarken = 0.0,
    this.denoise = 0.0,
    this.cellShading = 0.0,
    this.colourCrush = 0.0,
    this.aspectRatio = "16:9",
    required this.lastOpened,
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
    'edgeDarken': edgeDarken,
    'denoise': denoise,
    'cellShading': cellShading,
    'colourCrush': colourCrush,
    'aspectRatio': aspectRatio,
    'lastOpened': lastOpened.toIso8601String(),
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
    edgeDarken: json['edgeDarken'] ?? 0.0,
    denoise: json['denoise'] ?? 0.0,
    cellShading: json['cellShading'] ?? 0.0,
    colourCrush: json['colourCrush'] ?? 0.0,
    aspectRatio: json['aspectRatio'] ?? "16:9",
    lastOpened: DateTime.parse(json['lastOpened']),
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
    edgeDarken: edgeDarken,
    denoise: denoise,
    cellShading: cellShading,
    colourCrush: colourCrush,
    aspectRatio: aspectRatio,
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
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_storageKey');
    final jsonList = projects.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  static Future<void> saveProject(StoredProject project) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == project.id);
    projects.add(project);
    projects.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    if (projects.length > 20) {
      projects.removeRange(20, projects.length);
    }
    await saveProjects(projects);
  }

  static Future<void> deleteProject(String id) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == id);
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
  List<StoredProject> _recentProjects = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final all = await ProjectManager.loadProjects();
    setState(() {
      _recentProjects = all.take(5).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AEReality'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No Project Open', style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('Create a new 32-bit floating point color grading project or upscale footage with AI Super-Resolution.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen()));
                    },
                    icon: const Icon(Icons.add, color: Colors.black),
                    label: const Text('New Project', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsScreen()));
                    },
                    icon: const Icon(Icons.folder_open, color: Colors.white),
                    label: const Text('Open Projects', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('RECENT PROJECTS', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 8),
            if (_recentProjects.isEmpty)
              const Text('No recent projects', style: TextStyle(color: Colors.white38))
            else
              Column(
                children: _recentProjects.map((p) => ListTile(
                  leading: const Icon(Icons.video_file, color: Color(0xFF00E5FF)),
                  title: Text(p.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${p.videoPath.split('/').last} • ${p.lastOpened.toLocal().toString().split(' ')[0]}', style: const TextStyle(color: Colors.white54)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectScreen(initialProject: p.toProjectData(), projectName: p.name),
                      ),
                    ).then((_) => _loadRecent());
                  },
                )).toList(),
              ),
            const Spacer(),
            const Divider(color: Colors.white10),
            const Text('AI Super-Resolution Upscaler', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('REAL-CUGAN & REAL-ESRGAN', style: TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
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
                    activeColor: const Color(0xFF00E5FF),
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
  String _projectName = 'Untitled Project';
  String _selectedAspect = '16:9';
  String _selectedRes = '1080p';
  String _selectedFps = '60fps';
  String _selectedBitrate = '35 Mbps';
  File? _selectedFile;

  final List<String> _aspectRatios = ['4:5', '9:16', '16:9', '1:1', '3:4', '21:9'];
  final List<String> _resolutions = ['720p', '1080p', '2K'];
  final List<String> _fpsOptions = ['30fps', '60fps', '90fps'];
  final List<String> _bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps'];

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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PROJECT NAME', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 4),
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Untitled Project',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'Untitled Project',
              controller: TextEditingController(text: _projectName),
            ),
            const SizedBox(height: 20),
            const Text('SOURCE FOOTAGE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(type: FileType.video);
                if (result != null) {
                  setState(() => _selectedFile = File(result.files.single.path!));
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[700]!, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(_selectedFile == null ? Icons.cloud_upload : Icons.check_circle, color: const Color(0xFF00E5FF), size: 40),
                    const SizedBox(height: 8),
                    Text(_selectedFile == null ? 'Click to select footage or image from device' : _selectedFile!.path.split('/').last,
                      style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('CANVAS ASPECT RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _aspectRatios.map((ratio) => ChoiceChip(
                label: Text(ratio, style: TextStyle(color: _selectedAspect == ratio ? Colors.black : Colors.white70)),
                selected: _selectedAspect == ratio,
                selectedColor: const Color(0xFF00E5FF),
                backgroundColor: Colors.grey[900],
                onSelected: (sel) => setState(() => _selectedAspect = ratio),
              )).toList(),
            ),
            const SizedBox(height: 20),
            const Text('PROJECT PIPELINE SPECS', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Canvas Aspect Ratio', style: TextStyle(color: Colors.white54)),
                      Text(_selectedAspect, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quality / Resolution', style: TextStyle(color: Colors.white54)),
                      DropdownButton<String>(
                        value: _selectedRes,
                        items: _resolutions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                        onChanged: (v) => setState(() => _selectedRes = v!),
                        dropdownColor: Colors.grey[900],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Framerate', style: TextStyle(color: Colors.white54)),
                      DropdownButton<String>(
                        value: _selectedFps,
                        items: _fpsOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                        onChanged: (v) => setState(() => _selectedFps = v!),
                        dropdownColor: Colors.grey[900],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Target Bitrate', style: TextStyle(color: Colors.white54)),
                      DropdownButton<String>(
                        value: _selectedBitrate,
                        items: _bitrateOptions.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                        onChanged: (v) => setState(() => _selectedBitrate = v!),
                        dropdownColor: Colors.grey[900],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a video')));
                    return;
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectScreen(
                        initialProject: ProjectData(videoPath: _selectedFile!.path),
                        projectName: _projectName,
                        initialResolution: _selectedRes,
                        initialFps: _selectedFps,
                        initialBitrate: _selectedBitrate,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('CREATE PROJECT', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------- PROJECTS SCREEN ----------
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
    setState(() => _projects = projs);
  }

  Future<void> _openProject(StoredProject project) async {
    final updated = StoredProject(
      id: project.id,
      name: project.name,
      videoPath: project.videoPath,
      brightness: project.brightness,
      saturation: project.saturation,
      contrast: project.contrast,
      sharpness: project.sharpness,
      gamma: project.gamma,
      hue: project.hue,
      temperature: project.temperature,
      glowIntensity: project.glowIntensity,
      lookMix: project.lookMix,
      vignette: project.vignette,
      splitToning: project.splitToning,
      edgeDarken: project.edgeDarken,
      denoise: project.denoise,
      cellShading: project.cellShading,
      colourCrush: project.colourCrush,
      aspectRatio: project.aspectRatio,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(updated);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectScreen(
          initialProject: project.toProjectData(),
          projectName: project.name,
        ),
      ),
    ).then((_) => _loadProjects());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        backgroundColor: const Color(0xFF0A0A0A),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProjects),
        ],
      ),
      body: _projects.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('No projects yet', style: TextStyle(color: Colors.white38)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final p = _projects[index];
                return ListTile(
                  leading: const Icon(Icons.video_file, color: Color(0xFF00E5FF)),
                  title: Text(p.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${p.videoPath.split('/').last} • ${p.lastOpened.toLocal().toString().split(' ')[0]}', style: const TextStyle(color: Colors.white54)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white38),
                    onPressed: () async {
                      await ProjectManager.deleteProject(p.id);
                      _loadProjects();
                    },
                  ),
                  onTap: () => _openProject(p),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen()))
            .then((_) => _loadProjects());
        },
        child: const Icon(Icons.add),
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: Colors.black,
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
  final String? projectName;

  const ProjectScreen({
    super.key,
    this.initialProject,
    this.initialResolution,
    this.initialFps,
    this.initialBitrate,
    this.projectName,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  String? _currentVideoPath;

  // Grading params
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

  String _selectedRatio = "16:9";
  late TabController _tabController;
  VoidCallback _listener = () {};
  bool _isPreviewing = false;

  Uint8List? _spirvShader;

  // Timeline preview
  ui.Image? _processedImage;
  Timer? _previewTimer;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

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
      _selectedRatio = p.aspectRatio;
      _loadVideo(p.videoPath);
    }
  }

  Future<void> _loadShader() async {
    try {
      final byteData = await rootBundle.load('assets/shaders/aereality_core.spv');
      _spirvShader = byteData.buffer.asUint8List();
      initVulkan(_spirvShader!);
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
          _startTimelinePreview();
        });
    });
  }

  // ---------- TIMELINE PREVIEW (fixed) ----------
  void _startTimelinePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_controller == null || !_controller!.value.isInitialized || _isUpdating) return;
      _isUpdating = true;
      try {
        // ✅ Fixed: use videoTexture.toImage() or fallback
        final frame = await _controller!.value.videoTexture?.toImage();
        if (frame == null) return;
        final processed = await _processFrameWithVulkan(frame);
        if (mounted) {
          setState(() {
            _processedImage = processed;
          });
        }
        frame.dispose();
      } catch (e) {
        // ignore
      }
      _isUpdating = false;
    });
  }

  void _stopTimelinePreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
  }

  @override
  void dispose() {
    _stopTimelinePreview();
    _controller?.removeListener(_listener);
    _controller?.dispose();
    cleanupVulkan();
    super.dispose();
  }

  // ---------- PICK VIDEO ----------
  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      final file = result.files.single;
      if (file.path == null) return;
      final dir = await getTemporaryDirectory();
      final cachedPath = '${dir.path}/input_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(file.path!).copy(cachedPath);
      _loadVideo(cachedPath);
    }
  }

  // ---------- SHOW LOG ----------
  Future<void> _showLog() async { /* keep existing */ }

  // ---------- PRESETS ----------
  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case 'Gojo Edit':
          _brightness = 0.15; _saturation = 1.3; _contrast = 1.25; _sharpness = 0.0; _gamma = 0.95;
          _hue = 0.0; _temperature = 6200.0; _glowIntensity = 0.0; _lookMix = 0.3;
          _vignette = 0.0; _splitToning = 0.15; _edgeDarken = 0.0;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0;
          break;
        case 'Magic Bullet':
          _brightness = 0.0; _saturation = 1.2; _contrast = 1.5; _sharpness = 0.0; _gamma = 0.95;
          _hue = 0.0; _temperature = 5600.0; _glowIntensity = 0.0; _lookMix = 0.0;
          _vignette = 0.0; _splitToning = 0.4; _edgeDarken = 0.0;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0;
          break;
        case 'Teal & Orange':
          _brightness = 0.0; _saturation = 1.4; _contrast = 1.3; _sharpness = 0.0; _gamma = 0.95;
          _hue = 0.0; _temperature = 5500.0; _glowIntensity = 0.0; _lookMix = 0.7;
          _vignette = 0.0; _splitToning = 0.0; _edgeDarken = 0.0;
          _denoise = 0.0; _cellShading = 0.0; _colourCrush = 0.0;
          break;
        default: break;
      }
    });
  }

  // ---------- SAVE PROJECT ----------
  Future<void> _saveCurrentProject() async {
    if (_currentVideoPath == null) return;
    final project = StoredProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: widget.projectName ?? 'Untitled',
      videoPath: _currentVideoPath!,
      brightness: _brightness,
      saturation: _saturation,
      contrast: _contrast,
      sharpness: _sharpness,
      gamma: _gamma,
      hue: _hue,
      temperature: _temperature,
      glowIntensity: _glowIntensity,
      lookMix: _lookMix,
      vignette: _vignette,
      splitToning: _splitToning,
      edgeDarken: _edgeDarken,
      denoise: _denoise,
      cellShading: _cellShading,
      colourCrush: _colourCrush,
      aspectRatio: _selectedRatio,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(project);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project Saved!'), backgroundColor: Colors.green),
    );
  }

  double _getAspectRatioValue(String ratio) {
    switch (ratio) {
      case "4:5": return 4 / 5;
      case "16:9": return 16 / 9;
      case "9:16": return 9 / 16;
      case "1:1": return 1 / 1;
      case "3:4": return 3 / 4;
      case "21:9": return 21 / 9;
      default: return 16 / 9;
    }
  }

  void _showRatioSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => SafeArea(
        child: Wrap(
          children: ["4:5", "9:16", "16:9", "1:1", "3:4", "21:9"].map((ratio) => ListTile(
            title: Text(ratio, style: const TextStyle(color: Colors.white)),
            trailing: _selectedRatio == ratio ? const Icon(Icons.check, color: Color(0xFF00E5FF)) : null,
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

  // ---------- VULKAN PROCESSING (18 floats) ----------
  Future<ui.Image> _processFrameWithVulkan(ui.Image input) async {
    final byteData = await input.toByteData(format: ui.ImageByteFormat.rawRgba);
    final inputBytes = byteData!.buffer.asUint8List();

    // 18 floats: resolution (2) + 16 grading params
    final uniforms = Float32List(18);
    uniforms[0] = input.width.toDouble();
    uniforms[1] = input.height.toDouble();
    uniforms[2] = _brightness;
    uniforms[3] = _saturation;
    uniforms[4] = _contrast;
    uniforms[5] = _sharpness;
    uniforms[6] = _gamma;
    uniforms[7] = _hue;
    uniforms[8] = _temperature;
    uniforms[9] = _glowIntensity;
    uniforms[10] = _lookMix;
    uniforms[11] = _vignette;
    uniforms[12] = _splitToning;
    uniforms[13] = _edgeDarken;
    uniforms[14] = _denoise;
    uniforms[15] = _cellShading;
    uniforms[16] = _colourCrush;
    uniforms[17] = 0.0; // placeholder

    final outputBytes = processImage(inputBytes, input.width, input.height, uniforms);
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
    // ---------- SINGLE PREVIEW FRAME ----------
  Future<void> _previewFrame() async {
    // keep existing – you can keep it for manual previews
  }

  // ---------- EXPORT SHEET (with 8-bit/10-bit toggle) ----------
  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            String selectedRes = widget.initialResolution ?? '1080p';
            String selectedFps = widget.initialFps ?? '60fps';
            String selectedBit = widget.initialBitrate ?? '35 Mbps';
            String selectedColorDepth = '8-bit SDR';
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Export Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  // Resolution
                  const Text('Resolution', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['720p', '1080p', '2K'].map((res) => ChoiceChip(
                      label: Text(res),
                      selected: selectedRes == res,
                      selectedColor: const Color(0xFF00E5FF),
                      labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() { if (sel) selectedRes = res; }),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Frame Rate
                  const Text('Frame Rate', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['30fps', '60fps', '90fps'].map((fps) => ChoiceChip(
                      label: Text(fps),
                      selected: selectedFps == fps,
                      selectedColor: const Color(0xFF00E5FF),
                      labelStyle: TextStyle(color: selectedFps == fps ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() { if (sel) selectedFps = fps; }),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Bitrate
                  const Text('Video Bitrate', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['15 Mbps', '35 Mbps', '50 Mbps'].map((bit) => ChoiceChip(
                      label: Text(bit),
                      selected: selectedBit == bit,
                      selectedColor: const Color(0xFF00E5FF),
                      labelStyle: TextStyle(color: selectedBit == bit ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() { if (sel) selectedBit = bit; }),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Color Depth
                  const Text('Color Depth & Profile', style: TextStyle(color: Colors.white70)),
                  Wrap(
                    spacing: 8,
                    children: ['8-bit SDR', '10-bit HDR'].map((depth) => ChoiceChip(
                      label: Text(depth),
                      selected: selectedColorDepth == depth,
                      selectedColor: const Color(0xFF00E5FF),
                      labelStyle: TextStyle(color: selectedColorDepth == depth ? Colors.black : Colors.white),
                      onSelected: (sel) => setStateModal(() { if (sel) selectedColorDepth = depth; }),
                    )).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _exportVideo(selectedRes, selectedFps, selectedBit, selectedColorDepth);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('RENDER VIDEO', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- SLIDER WIDGET ----------
  Widget _slider(String label, double min, double max, double val, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFF00E5FF),
            inactiveColor: Colors.grey[800],
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(val.toStringAsFixed(1), style: const TextStyle(color: Colors.white38))),
      ],
    );
  }
    // ---------- EXPORT VIDEO ----------
  Future<void> _exportVideo(String resolution, String fps, String bitrate, String colorDepth) async {
    if (_controller == null || !_controller!.value.isInitialized || _currentVideoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import a video first'), backgroundColor: Colors.orange));
      return;
    }
    if (_spirvShader == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shader not loaded'), backgroundColor: Colors.red));
      return;
    }

    // Capture current values
    final double brightness = _brightness;
    final double saturation = _saturation;
    final double contrast = _contrast;
    final double sharpness = _sharpness;
    final double gamma = _gamma;
    final double hue = _hue;
    final double temperature = _temperature;
    final double glowIntensity = _glowIntensity;
    final double lookMix = _lookMix;
    final double vignette = _vignette;
    final double splitToning = _splitToning;
    final double edgeDarken = _edgeDarken;
    final double denoise = _denoise;
    final double cellShading = _cellShading;
    final double colourCrush = _colourCrush;

    String pixFmt = (colorDepth == '10-bit HDR') ? 'yuv420p10le' : 'yuv420p';

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Initializing...');
    final etaNotifier = ValueNotifier<String>('--:--');
    final stopwatch = Stopwatch();

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Exporting... (${colorDepth})', style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => LinearProgressIndicator(value: progress, color: const Color(0xFF00E5FF)),
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

      statusNotifier.value = 'Extracting frames...';
      final extractCmd = '-i "$videoPath" -vsync 0 -f image2 "${framesDir.path}/frame_%05d.png"';
      final extractSession = await FFmpegKit.execute(extractCmd);
      if (!ReturnCode.isSuccess(await extractSession.getReturnCode())) {
        throw Exception('Extract failed');
      }

      final frameFiles = await framesDir.list().toList();
      final totalFrames = frameFiles.length;
      int processedFrames = 0;
      stopwatch.start();
      const batchSize = 1;

      for (int i = 0; i < totalFrames; i += batchSize) {
        final batch = frameFiles.skip(i).take(batchSize).toList();
        await Future.wait(batch.map((file) async {
          if (file is! File) return;
          final bytes = await file.readAsBytes();
          final decoded = img.decodeImage(bytes);
          if (decoded == null) return;

          final rawInput = decoded.data!.buffer.asUint8List();
          final uniforms = Float32List(18);
          uniforms[0] = decoded.width.toDouble();
          uniforms[1] = decoded.height.toDouble();
          uniforms[2] = brightness;
          uniforms[3] = saturation;
          uniforms[4] = contrast;
          uniforms[5] = sharpness;
          uniforms[6] = gamma;
          uniforms[7] = hue;
          uniforms[8] = temperature;
          uniforms[9] = glowIntensity;
          uniforms[10] = lookMix;
          uniforms[11] = vignette;
          uniforms[12] = splitToning;
          uniforms[13] = edgeDarken;
          uniforms[14] = denoise;
          uniforms[15] = cellShading;
          uniforms[16] = colourCrush;
          uniforms[17] = 0.0;

          final outputRaw = await Future(() => processImage(rawInput, decoded.width, decoded.height, uniforms))
              .timeout(const Duration(seconds: 30));

          final gradedImg = img.Image.fromBytes(
            width: decoded.width,
            height: decoded.height,
            bytes: outputRaw.buffer,
          );
          final pngBytes = img.encodePng(gradedImg);
          final paddedIndex = (i + 1).toString().padLeft(5, '0');
          final outputFile = File('${processedDir.path}/frame_${paddedIndex}.png');
          await outputFile.writeAsBytes(pngBytes);

          processedFrames++;
          progressNotifier.value = processedFrames / totalFrames;
          statusNotifier.value = 'Processing... ${(processedFrames / totalFrames * 100).toInt()}%';
        }));
      }

      statusNotifier.value = 'Encoding video...';
      final targetFps = int.parse(fps.replaceAll('fps', ''));
      final silentOutputPath = '${dir.path}/silent_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      var encodeCmd = '-framerate $targetFps -i "${processedDir.path}/frame_%05d.png" ' +
                      '-c:v libx264 -preset ultrafast -crf 23 -pix_fmt $pixFmt "$silentOutputPath"';
      var encodeSession = await FFmpegKit.execute(encodeCmd);
      if (!ReturnCode.isSuccess(await encodeSession.getReturnCode())) {
        final fallbackCmd = '-framerate $targetFps -i "${processedDir.path}/frame_%05d.png" ' +
                            '-c:v mpeg4 -q:v 5 -pix_fmt $pixFmt "$silentOutputPath"';
        encodeSession = await FFmpegKit.execute(fallbackCmd);
        if (!ReturnCode.isSuccess(await encodeSession.getReturnCode())) {
          throw Exception('Encoding failed');
        }
      }

      final audioPath = '${dir.path}/audio.aac';
      final audioCmd = '-i "$videoPath" -vn -acodec copy "$audioPath"';
      await FFmpegKit.execute(audioCmd);

      final finalOutputPath = '${dir.path}/final_export_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final muxCmd = '-i "$silentOutputPath" -i "$audioPath" -c copy -shortest "$finalOutputPath"';
      final muxSession = await FFmpegKit.execute(muxCmd);
      if (!ReturnCode.isSuccess(await muxSession.getReturnCode())) {
        await File(silentOutputPath).copy(File(finalOutputPath).path);
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final finalFile = File('${docsDir.path}/AEReality_Export_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await File(finalOutputPath).copy(finalFile.path);

      await framesDir.delete(recursive: true);
      await processedDir.delete(recursive: true);
      try { await File(audioPath).delete(); } catch (_) {}
      try { await File(silentOutputPath).delete(); } catch (_) {}

      if (dialogContext != null) Navigator.pop(dialogContext!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Export saved to:\n${finalFile.path}'), duration: const Duration(seconds: 8)),
        );
      }
    } catch (e) {
      if (dialogContext != null) Navigator.pop(dialogContext!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export Error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 10)),
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
          // ---------- TIMELINE PREVIEW ----------
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black,
              child: Center(
                child: _processedImage != null
                    ? AspectRatio(
                        aspectRatio: _getAspectRatioValue(_selectedRatio),
                        child: RawImage(
                          image: _processedImage,
                          fit: BoxFit.contain,
                        ),
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
          // ---------- PLAYBACK CONTROLS ----------
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
                            _stopTimelinePreview();
                          } else {
                            _controller!.play();
                            _isPlaying = true;
                            _startTimelinePreview();
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
                    activeColor: const Color(0xFF00E5FF),
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
          // ---------- TABS ----------
          Container(
            color: const Color(0xFF141414),
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicatorColor: const Color(0xFF00E5FF),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(icon: Icon(Icons.tune), text: 'Adjust'),
                    Tab(icon: Icon(Icons.auto_awesome), text: 'Presets'),
                    Tab(icon: Icon(Icons.save_alt), text: 'Export'),
                  ],
                ),
                SizedBox(
                  height: 240,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // ---------- Adjust tab ----------
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
                          _slider('Edge Darken', 0.0, 1.0, _edgeDarken, (v) => setState(() => _edgeDarken = v)),
                          _slider('Denoise', 0.0, 1.0, _denoise, (v) => setState(() => _denoise = v)),
                          _slider('Cell Shading', 0.0, 1.0, _cellShading, (v) => setState(() => _cellShading = v)),
                          _slider('Colour Crush', 0.0, 1.0, _colourCrush, (v) => setState(() => _colourCrush = v)),
                        ],
                      ),
                      // ---------- Presets tab ----------
                      GridView.count(
                        crossAxisCount: 3,
                        padding: const EdgeInsets.all(8),
                        children: ['Gojo Edit', 'Magic Bullet', 'Teal & Orange'].map((name) {
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
                      // ---------- Export tab ----------
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
                                  backgroundColor: const Color(0xFF00E5FF),
                                  foregroundColor: Colors.black,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _showExportSheet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showLog,
        child: const Icon(Icons.bug_report),
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: Colors.black,
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
