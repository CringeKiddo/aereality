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

// Minimal data models (kept compatible with original code)
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
    this.glowIntensity = 0.0,
    this.lookMix = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.aspectRatio = '16:9',
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
        videoPath: json['videoPath'] ?? '',
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
        aspectRatio: json['aspectRatio'] ?? '16:9',
      );
}

class StoredProject {
  String id;
  String name;
  String videoPath;
  double brightness, saturation, contrast, sharpness, gamma, hue;
  double temperature, glowIntensity, lookMix, vignette, splitToning;
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
    this.aspectRatio = '16:9',
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
        'aspectRatio': aspectRatio,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory StoredProject.fromJson(Map<String, dynamic> json) => StoredProject(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] ?? 'Untitled',
        videoPath: json['videoPath'] ?? '',
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
        aspectRatio: json['aspectRatio'] ?? '16:9',
        lastOpened: DateTime.tryParse(json['lastOpened'] ?? '') ?? DateTime.now(),
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
    if (projects.length > 5) projects.removeRange(5, projects.length);
    await saveProjects(projects);
  }

  static Future<void> deleteProject(String id) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == id);
    await saveProjects(projects);
  }
}

// HOME SCREEN
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AEReality')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library, size: 80, color: Colors.white24),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())),
              child: const Text('New Project'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsScreen())),
              child: const Text('Open Projects'),
            ),
          ],
        ),
      ),
    );
  }
}

// SETTINGS
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  double _previewScale = 1.0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Settings')), body: Center(child: Text('Settings - preview ${(_previewScale*1080).toInt()}p')));
  }
}

// PROJECT SETUP SCREEN
class ProjectSetupScreen extends StatefulWidget {
  const ProjectSetupScreen({super.key});
  @override
  State<ProjectSetupScreen> createState() => _ProjectSetupScreenState();
}

class _ProjectSetupScreenState extends State<ProjectSetupScreen> with SingleTickerProviderStateMixin {
  String _projectName = 'Untitled Project';
  String _selectedResolution = '1080p';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Project')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Project name'),
              onChanged: (v) => _projectName = v,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: ProjectData(videoPath: ''), projectName: _projectName)),
                );
              },
              child: const Text('Create'),
            )
          ],
        ),
      ),
    );
  }
}

// PROJECTS SCREEN
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
    _load();
  }

  Future<void> _load() async {
    final projs = await ProjectManager.loadProjects();
    setState(() => _projects = projs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: ListView.builder(
        itemCount: _projects.length,
        itemBuilder: (context, i) {
          final p = _projects[i];
          return ListTile(
            title: Text(p.name),
            subtitle: Text(p.videoPath.split('/').last),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: p.toProjectData(), projectName: p.name)));
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// PROJECT SCREEN (minimal)
class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  final String? projectName;
  const ProjectScreen({super.key, this.initialProject, this.projectName});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.projectName ?? 'Project')),
      body: const Center(child: Text('Project screen')),
    );
  }
}
