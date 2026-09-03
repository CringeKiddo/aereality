// lib/main.dart (Part 1 of 2)
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

int gEnginePrecision = 16;
double gPreviewScale = 0.5;

class ProjectData {
  String mediaPath;
  bool isImage;
  double brightness, saturation, contrast, sharpness, gamma, hue, temperature;
  double glowIntensity, glowSpread, isDeepGlow, deepGlowRadius;
  double edgeGlow, edgeGlowSpread, edgeGlowTint;
  double anamorphicFlare, flareAmount;
  double shadows, highlights;
  double darkOutlines, edgeDarken, vignette, splitToning, denoise, blackCrush;
  double flickerIntensity, flickerSpeed;
  double depthOfField, dofFocus, dofAngle;
  double mathOpsMode, mathOpsMix, filmConvertNitrate, fourColorGradMix;
  String aspectRatio;

  List<double> curveMaster;
  List<double> curveRed;
  List<double> curveGreen;
  List<double> curveBlue;

  ProjectData({
    required this.mediaPath,
    this.isImage = false,
    this.brightness = 0.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.sharpness = 0.0,
    this.gamma = 1.0,
    this.hue = 0.0,
    this.temperature = 6500.0,
    this.glowIntensity = 0.0,
    this.glowSpread = 0.35,
    this.isDeepGlow = 1.0, // Default to deep glow
    this.deepGlowRadius = 0.5,
    this.edgeGlow = 0.0,
    this.edgeGlowSpread = 0.35,
    this.edgeGlowTint = 0.0, // 0: White, 1: Gold, 2: Quincy, 3: Cyan, 4: Crimson
    this.anamorphicFlare = 0.0,
    this.flareAmount = 0.5,
    this.shadows = 0.0,
    this.highlights = 0.0,
    this.darkOutlines = 0.0,
    this.edgeDarken = 0.0,
    this.vignette = 0.0,
    this.splitToning = 0.0,
    this.denoise = 0.0,
    this.blackCrush = 0.0,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 3.0,
    this.depthOfField = 0.0,
    this.dofFocus = 0.5,
    this.dofAngle = 0.0,
    this.mathOpsMode = 0.0,
    this.mathOpsMix = 0.0,
    this.filmConvertNitrate = 0.0,
    this.fourColorGradMix = 0.0,
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
        'mediaPath': mediaPath,
        'isImage': isImage,
        'brightness': brightness,
        'saturation': saturation,
        'contrast': contrast,
        'sharpness': sharpness,
        'gamma': gamma,
        'hue': hue,
        'temperature': temperature,
        'glowIntensity': glowIntensity,
        'glowSpread': glowSpread,
        'isDeepGlow': isDeepGlow,
        'deepGlowRadius': deepGlowRadius,
        'edgeGlow': edgeGlow,
        'edgeGlowSpread': edgeGlowSpread,
        'edgeGlowTint': edgeGlowTint,
        'anamorphicFlare': anamorphicFlare,
        'flareAmount': flareAmount,
        'shadows': shadows,
        'highlights': highlights,
        'darkOutlines': darkOutlines,
        'edgeDarken': edgeDarken,
        'vignette': vignette,
        'splitToning': splitToning,
        'denoise': denoise,
        'blackCrush': blackCrush,
        'flickerIntensity': flickerIntensity,
        'flickerSpeed': flickerSpeed,
        'depthOfField': depthOfField,
        'dofFocus': dofFocus,
        'dofAngle': dofAngle,
        'mathOpsMode': mathOpsMode,
        'mathOpsMix': mathOpsMix,
        'filmConvertNitrate': filmConvertNitrate,
        'fourColorGradMix': fourColorGradMix,
        'aspectRatio': aspectRatio,
        'curveMaster': curveMaster,
        'curveRed': curveRed,
        'curveGreen': curveGreen,
        'curveBlue': curveBlue,
      };

  factory ProjectData.fromJson(Map<String, dynamic> json) => ProjectData(
        mediaPath: json['mediaPath'] ?? json['videoPath'] ?? '',
        isImage: json['isImage'] ?? false,
        brightness: (json['brightness'] ?? 0.0).toDouble(),
        saturation: (json['saturation'] ?? 1.0).toDouble(),
        contrast: (json['contrast'] ?? 1.0).toDouble(),
        sharpness: (json['sharpness'] ?? 0.0).toDouble(),
        gamma: (json['gamma'] ?? 1.0).toDouble(),
        hue: (json['hue'] ?? 0.0).toDouble(),
        temperature: (json['temperature'] ?? 6500.0).toDouble(),
        glowIntensity: (json['glowIntensity'] ?? 0.0).toDouble(),
        glowSpread: (json['glowSpread'] ?? 0.35).toDouble(),
        isDeepGlow: (json['isDeepGlow'] ?? 1.0).toDouble(),
        deepGlowRadius: (json['deepGlowRadius'] ?? 0.5).toDouble(),
        edgeGlow: (json['edgeGlow'] ?? 0.0).toDouble(),
        edgeGlowSpread: (json['edgeGlowSpread'] ?? 0.35).toDouble(),
        edgeGlowTint: (json['edgeGlowTint'] ?? json['edgeGlowColorMode'] ?? 0.0).toDouble(),
        anamorphicFlare: (json['anamorphicFlare'] ?? 0.0).toDouble(),
        flareAmount: (json['flareAmount'] ?? 0.5).toDouble(),
        shadows: (json['shadows'] ?? 0.0).toDouble(),
        highlights: (json['highlights'] ?? 0.0).toDouble(),
        darkOutlines: (json['darkOutlines'] ?? 0.0).toDouble(),
        edgeDarken: (json['edgeDarken'] ?? 0.0).toDouble(),
        vignette: (json['vignette'] ?? 0.0).toDouble(),
        splitToning: (json['splitToning'] ?? 0.0).toDouble(),
        denoise: (json['denoise'] ?? 0.0).toDouble(),
        blackCrush: (json['blackCrush'] ?? 0.0).toDouble(),
        flickerIntensity: (json['flickerIntensity'] ?? 0.0).toDouble(),
        flickerSpeed: (json['flickerSpeed'] ?? 3.0).toDouble(),
        depthOfField: (json['depthOfField'] ?? 0.0).toDouble(),
        dofFocus: (json['dofFocus'] ?? 0.5).toDouble(),
        dofAngle: (json['dofAngle'] ?? 0.0).toDouble(),
        mathOpsMode: (json['mathOpsMode'] ?? 0.0).toDouble(),
        mathOpsMix: (json['mathOpsMix'] ?? 0.0).toDouble(),
        filmConvertNitrate: (json['filmConvertNitrate'] ?? 0.0).toDouble(),
        fourColorGradMix: (json['fourColorGradMix'] ?? 0.0).toDouble(),
        aspectRatio: json['aspectRatio'] ?? "4:5",
        curveMaster: (json['curveMaster'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveRed: (json['curveRed'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveGreen: (json['curveGreen'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveBlue: (json['curveBlue'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

class StoredProject {
  String id, name, mediaPath;
  ProjectData data;
  DateTime lastOpened;

  StoredProject({required this.id, required this.name, required this.mediaPath, required this.data, required this.lastOpened});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mediaPath': mediaPath,
        'data': data.toJson(),
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory StoredProject.fromJson(Map<String, dynamic> json) => StoredProject(
        id: json['id'],
        name: json['name'],
        mediaPath: json['mediaPath'] ?? json['videoPath'] ?? '',
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
                        leading: Icon(p.data.isImage ? Icons.image_outlined : Icons.movie_creation_outlined, color: const Color(0xFF00F0FF)),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text('${p.mediaPath.split('/').last} • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
  bool _isImage = false;

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
            const Text('SOURCE FOOTAGE OR IMAGE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'],
                );
                if (result != null && result.files.single.path != null) {
                  final p = result.files.single.path!;
                  final ext = p.split('.').last.toLowerCase();
                  final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
                  setState(() {
                    _selectedFile = File(p);
                    _isImage = isImg;
                  });
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
                    Icon(_selectedFile == null ? Icons.cloud_upload_outlined : (_isImage ? Icons.image : Icons.movie_creation), color: const Color(0xFF00F0FF), size: 36),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFile == null ? 'Tap to select video footage or high-res image' : _selectedFile!.path.split('/').last,
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a video or image file first')));
                    return;
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectScreen(
                        initialProject: ProjectData(mediaPath: _selectedFile!.path, isImage: _isImage, aspectRatio: _selectedAspect),
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
                    leading: Icon(p.data.isImage ? Icons.image_outlined : Icons.movie_creation_outlined, color: const Color(0xFF00F0FF)),
                    title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${p.mediaPath.split('/').last} • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white54)),
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
  String? _currentMediaPath;
  bool _isImage = false;
  ui.Image? _loadedRawImage;

  // Active Category Pill
  String _activeCategory = 'bloom';
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
  double _isDeepGlow = 1.0; // 0.0 = Normal Gaussian, 1.0 = Inverse Square Deep Glow
  double _deepGlowRadius = 0.5;
  double _edgeGlow = 0.0;
  double _edgeGlowSpread = 0.35;
  double _edgeGlowTint = 0.0; // 0: White, 1: Gold, 2: Quincy, 3: Cyan, 4: Crimson
  double _anamorphicFlare = 0.0;
  double _flareAmount = 0.5;
  double _shadows = 0.0;
  double _highlights = 0.0;
  double _darkOutlines = 0.0;
  double _edgeDarken = 0.0;
  double _vignette = 0.0;
  double _splitToning = 0.0;
  double _denoise = 0.0;
  double _blackCrush = 0.0;
  double _flickerIntensity = 0.0;
  double _flickerSpeed = 3.0;
  double _depthOfField = 0.0;
  double _dofFocus = 0.5;
  double _dofAngle = 0.0;

  // AE Effects
  double _mathOpsMode = 0.0; // 0=Off, 1=Screen, 2=Multiply, 3=Overlay, 4=ColorBurn
  double _mathOpsMix = 0.0;
  double _filmConvertNitrate = 0.0;
  double _fourColorGradMix = 0.0;

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
    _loadShader();

    if (widget.initialProject != null) {
      final p = widget.initialProject!;
      _isImage = p.isImage;
      _brightness = p.brightness;
      _saturation = p.saturation;
      _contrast = p.contrast;
      _sharpness = p.sharpness;
      _gamma = p.gamma;
      _hue = p.hue;
      _temperature = p.temperature;
      _glowIntensity = p.glowIntensity;
      _glowSpread = p.glowSpread;
      _isDeepGlow = p.isDeepGlow;
      _deepGlowRadius = p.deepGlowRadius;
      _edgeGlow = p.edgeGlow;
      _edgeGlowSpread = p.edgeGlowSpread;
      _edgeGlowTint = p.edgeGlowTint;
      _anamorphicFlare = p.anamorphicFlare;
      _flareAmount = p.flareAmount;
      _shadows = p.shadows;
      _highlights = p.highlights;
      _darkOutlines = p.darkOutlines;
      _edgeDarken = p.edgeDarken;
      _vignette = p.vignette;
      _splitToning = p.splitToning;
      _denoise = p.denoise;
      _blackCrush = p.blackCrush;
      _flickerIntensity = p.flickerIntensity;
      _flickerSpeed = p.flickerSpeed;
      _depthOfField = p.depthOfField;
      _dofFocus = p.dofFocus;
      _dofAngle = p.dofAngle;
      _mathOpsMode = p.mathOpsMode;
      _mathOpsMix = p.mathOpsMix;
      _filmConvertNitrate = p.filmConvertNitrate;
      _fourColorGradMix = p.fourColorGradMix;
      _selectedRatio = p.aspectRatio;
      _curveMaster = List.from(p.curveMaster);
      _curveRed = List.from(p.curveRed);
      _curveGreen = List.from(p.curveGreen);
      _curveBlue = List.from(p.curveBlue);
      _loadMedia(p.mediaPath);
    }
  }

  void _updateCanvasSize(int srcW, int srcH) {
    if (srcW <= 0 || srcH <= 0) {
      srcW = 1080;
      srcH = 1350;
    }
    final ratio = _getAspectRatioValue(_selectedRatio);
    int targetHeight = (srcH * gPreviewScale).round();
    int targetWidth = (targetHeight * ratio).round();

    _canvasWidth = (targetWidth % 2 == 0) ? targetWidth : targetWidth + 1;
    _canvasHeight = (targetHeight % 2 == 0) ? targetHeight : targetHeight + 1;
  }

  Future<void> _loadShader() async {
    final candidateNames = [
      'assets/shaders/aereality_core.spv',
      gEnginePrecision == 32 ? 'assets/shaders/aereality_core_32.spv' : 'assets/shaders/aereality_core_16.spv',
      'assets/shaders/shader.spv',
    ];

    Uint8List? shaderBytes;
    String? loadedPath;

    for (final path in candidateNames) {
      try {
        final byteData = await rootBundle.load(path);
        shaderBytes = byteData.buffer.asUint8List();
        loadedPath = path;
        break;
      } catch (_) {}
    }

    if (shaderBytes != null) {
      initVulkan(shaderBytes, gEnginePrecision);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Vulkan Initialized: ${loadedPath!.split('/').last}'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF00F0FF).withOpacity(0.8),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ No compiled .spv found in assets/shaders/! Recompile shader with glslc.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _loadMedia(String path) async {
    final ext = path.split('.').last.toLowerCase();
    final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);

    _previewTimer?.cancel();
    _controller?.removeListener(_listener);
    _controller?.dispose();
    _controller = null;

    setState(() {
      _currentMediaPath = path;
      _isImage = isImg;
      _processedImage = null;
    });

    if (isImg) {
      final fileBytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(fileBytes);
      final frame = await codec.getNextFrame();
      _loadedRawImage = frame.image;
      _updateCanvasSize(_loadedRawImage!.width, _loadedRawImage!.height);
      _processStaticImage();
    } else {
      _loadedRawImage = null;
      _controller = VideoPlayerController.file(File(path))
        ..initialize().then((_) {
          if (!mounted) return;
          final vw = _controller!.value.size.width.toInt();
          final vh = _controller!.value.size.height.toInt();
          _updateCanvasSize(vw, vh);
          setState(() {});
          _listener = () { if (mounted) setState(() {}); };
          _controller!.addListener(_listener);
          _controller!.play();
          _isPlaying = true;
          _startTimelinePreview();
        });
    }
  }

  Future<void> _processStaticImage() async {
    if (_loadedRawImage == null) return;
    try {
      final processed = await _processFrameWithVulkan(_loadedRawImage!);
      if (mounted) setState(() => _processedImage = processed);
    } catch (_) {}
  }

  void _startTimelinePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) async {
      if (_isImage) return;
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
    final uniforms = Float32List(66);
    final timeSeconds = (_controller != null && _controller!.value.isInitialized)
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
    uniforms[10] = _isDeepGlow;
    uniforms[11] = _deepGlowRadius;
    uniforms[12] = _edgeGlow;
    uniforms[13] = _edgeGlowSpread;
    uniforms[14] = _edgeGlowTint;
    uniforms[15] = _anamorphicFlare;
    uniforms[16] = _flareAmount;
    uniforms[17] = _shadows;
    uniforms[18] = _highlights;
    uniforms[19] = _darkOutlines;
    uniforms[20] = _edgeDarken;
    uniforms[21] = _vignette;
    uniforms[22] = _splitToning;
    uniforms[23] = _denoise;
    uniforms[24] = _blackCrush;
    uniforms[25] = _flickerIntensity;
    uniforms[26] = _flickerSpeed;
    uniforms[27] = _depthOfField;
    uniforms[28] = _dofFocus;
    uniforms[29] = _dofAngle;
    uniforms[30] = _mathOpsMode;
    uniforms[31] = _mathOpsMix;
    uniforms[32] = _filmConvertNitrate;
    uniforms[33] = _fourColorGradMix;

    // Master Curve (8 floats)
    uniforms[34] = _curveMaster[0];
    uniforms[35] = _curveMaster[1];
    uniforms[36] = _curveMaster[2];
    uniforms[37] = _curveMaster[3];
    uniforms[38] = _curveMaster[4];
    uniforms[39] = 0.0; uniforms[40] = 0.0; uniforms[41] = 0.0;

    // Red Curve (8 floats)
    uniforms[42] = _curveRed[0];
    uniforms[43] = _curveRed[1];
    uniforms[44] = _curveRed[2];
    uniforms[45] = _curveRed[3];
    uniforms[46] = _curveRed[4];
    uniforms[47] = 0.0; uniforms[48] = 0.0; uniforms[49] = 0.0;

    // Green Curve (8 floats)
    uniforms[50] = _curveGreen[0];
    uniforms[51] = _curveGreen[1];
    uniforms[52] = _curveGreen[2];
    uniforms[53] = _curveGreen[3];
    uniforms[54] = _curveGreen[4];
    uniforms[55] = 0.0; uniforms[56] = 0.0; uniforms[57] = 0.0;

    // Blue Curve (8 floats)
    uniforms[58] = _curveBlue[0];
    uniforms[59] = _curveBlue[1];
    uniforms[60] = _curveBlue[2];
    uniforms[61] = _curveBlue[3];
    uniforms[62] = _curveBlue[4];
    uniforms[63] = 0.0; uniforms[64] = 0.0; uniforms[65] = 0.0;

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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    final millis = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$millis';
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
      _isDeepGlow = 1.0;
      _deepGlowRadius = 0.5;
      _edgeGlow = 0.0;
      _edgeGlowSpread = 0.35;
      _edgeGlowTint = 0.0;
      _anamorphicFlare = 0.0;
      _flareAmount = 0.5;
      _shadows = 0.0;
      _highlights = 0.0;
      _darkOutlines = 0.0;
      _edgeDarken = 0.0;
      _vignette = 0.0;
      _splitToning = 0.0;
      _denoise = 0.0;
      _blackCrush = 0.0;
      _flickerIntensity = 0.0;
      _flickerSpeed = 3.0;
      _depthOfField = 0.0;
      _dofFocus = 0.5;
      _dofAngle = 0.0;
      _mathOpsMode = 0.0;
      _mathOpsMix = 0.0;
      _filmConvertNitrate = 0.0;
      _fourColorGradMix = 0.0;
      _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];
    });
    if (_isImage) _processStaticImage();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All effects reset to neutral default!'), duration: Duration(seconds: 1)),
    );
  }

  void _resetCurvesOnly() {
    setState(() {
      _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];
    });
    if (_isImage) _processStaticImage();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Curves reset to linear!'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _saveCurrentProject() async {
    if (_currentMediaPath == null) return;
    final project = StoredProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: widget.projectName ?? 'Untitled Project',
      mediaPath: _currentMediaPath!,
      data: ProjectData(
        mediaPath: _currentMediaPath!,
        isImage: _isImage,
        brightness: _brightness,
        saturation: _saturation,
        contrast: _contrast,
        sharpness: _sharpness,
        gamma: _gamma,
        hue: _hue,
        temperature: _temperature,
        glowIntensity: _glowIntensity,
        glowSpread: _glowSpread,
        isDeepGlow: _isDeepGlow,
        deepGlowRadius: _deepGlowRadius,
        edgeGlow: _edgeGlow,
        edgeGlowSpread: _edgeGlowSpread,
        edgeGlowTint: _edgeGlowTint,
        anamorphicFlare: _anamorphicFlare,
        flareAmount: _flareAmount,
        shadows: _shadows,
        highlights: _highlights,
        darkOutlines: _darkOutlines,
        edgeDarken: _edgeDarken,
        vignette: _vignette,
        splitToning: _splitToning,
        denoise: _denoise,
        blackCrush: _blackCrush,
        flickerIntensity: _flickerIntensity,
        flickerSpeed: _flickerSpeed,
        depthOfField: _depthOfField,
        dofFocus: _dofFocus,
        dofAngle: _dofAngle,
        mathOpsMode: _mathOpsMode,
        mathOpsMix: _mathOpsMix,
        filmConvertNitrate: _filmConvertNitrate,
        fourColorGradMix: _fourColorGradMix,
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

  // EXACT WEB-MATCHING PRESETS
  void _applyPreset(String name) {
    setState(() {
      _resetAllEffects();
      switch (name) {
        case 'vintage cc':
          _brightness = 0.05; _saturation = 0.90; _contrast = 1.15; _sharpness = 0.18; _gamma = 1.04;
          _temperature = 5800.0; _glowIntensity = 0.22; _glowSpread = 0.40; _isDeepGlow = 0.0;
          _vignette = 0.25; _splitToning = 0.15; _blackCrush = 0.04; _filmConvertNitrate = 0.35;
          _curveMaster = [0.05, 0.26, 0.50, 0.76, 0.96];
          break;
        case 'adevob+junho':
          _brightness = 0.02; _saturation = 1.40; _contrast = 1.55; _sharpness = 0.70; _gamma = 0.92;
          _temperature = 6000.0; _glowIntensity = 0.55; _glowSpread = 0.38; _isDeepGlow = 1.0;
          _deepGlowRadius = 0.50; _edgeGlow = 0.22; _edgeGlowTint = 1.0; // Gold
          _darkOutlines = 0.45; _blackCrush = 0.35; _vignette = 0.20;
          _curveMaster = [0.0, 0.18, 0.50, 0.82, 1.0];
          break;
        case 'adevobfiller':
          _brightness = 0.0; _saturation = 1.30; _contrast = 1.40; _sharpness = 0.55; _gamma = 0.95;
          _temperature = 6200.0; _glowIntensity = 0.40; _glowSpread = 0.48; _isDeepGlow = 1.0;
          _deepGlowRadius = 0.45; _blackCrush = 0.24; _darkOutlines = 0.30; _vignette = 0.15;
          _curveMaster = [0.0, 0.20, 0.50, 0.80, 1.0];
          break;
        case 'uryu vs ichigo':
          _brightness = -0.02; _saturation = 1.25; _contrast = 1.50; _sharpness = 0.65; _gamma = 0.94;
          _temperature = 7800.0; _glowIntensity = 0.48; _glowSpread = 0.35; _isDeepGlow = 1.0;
          _edgeGlow = 0.38; _edgeGlowTint = 2.0; // Quincy Blue
          _anamorphicFlare = 0.45; _flareAmount = 0.60; _darkOutlines = 0.50; _blackCrush = 0.32;
          _vignette = 0.22;
          _curveMaster = [0.0, 0.16, 0.48, 0.84, 1.0];
          break;
        case 'saber vs Rin':
          _brightness = 0.04; _saturation = 1.45; _contrast = 1.45; _sharpness = 0.60; _gamma = 0.93;
          _temperature = 6500.0; _glowIntensity = 0.65; _glowSpread = 0.50; _isDeepGlow = 1.0;
          _anamorphicFlare = 0.55; _flareAmount = 0.70; _edgeGlow = 0.28; _vignette = 0.18;
          _blackCrush = 0.25;
          _curveMaster = [0.0, 0.22, 0.52, 0.85, 1.0];
          break;
        case 'Dantae cc':
          _brightness = -0.03; _saturation = 1.25; _contrast = 1.55; _sharpness = 0.75; _gamma = 0.90;
          _temperature = 6800.0; _glowIntensity = 0.38; _glowSpread = 0.32; _isDeepGlow = 1.0;
          _edgeDarken = 0.25; _darkOutlines = 0.55; _blackCrush = 0.38; _vignette = 0.22;
          _curveMaster = [0.0, 0.14, 0.48, 0.85, 1.0];
          break;
        case 'toji junho':
          _brightness = -0.01; _saturation = 1.15; _contrast = 1.60; _sharpness = 0.72; _gamma = 0.88;
          _temperature = 6100.0; _glowIntensity = 0.45; _glowSpread = 0.35; _isDeepGlow = 1.0;
          _darkOutlines = 0.58; _blackCrush = 0.44; _vignette = 0.26;
          _curveMaster = [0.0, 0.12, 0.46, 0.86, 1.0];
          break;
      }
    });
    if (_isImage) _processStaticImage();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded preset "$name"'), duration: const Duration(seconds: 1)),
    );
  }

  // ---------- EXPORT SHEET ----------
  void _showExportSheet() {
    if (_isImage) {
      _exportStaticImage();
      return;
    }

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

                    // Framerate
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

  // STATIC IMAGE EXPORT
  Future<void> _exportStaticImage() async {
    if (_loadedRawImage == null || _currentMediaPath == null) return;
    try {
      final uniforms = _packUniforms();
      final byteData = await _loadedRawImage!.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rawInput = byteData!.buffer.asUint8List();

      final ratio = _getAspectRatioValue(_selectedRatio);
      const exportHeight = 1350;
      final exportWidth = (exportHeight * ratio).round();

      final outputRaw = processImage(
        rawInput,
        _loadedRawImage!.width,
        _loadedRawImage!.height,
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

      Directory exportDir = Directory('/storage/emulated/0/Download');
      if (!await exportDir.exists()) {
        final extDir = await getExternalStorageDirectory();
        exportDir = extDir ?? await getApplicationDocumentsDirectory();
      }

      final fileName = 'AEReality_Graded_${DateTime.now().millisecondsSinceEpoch}.png';
      final destFile = File('${exportDir.path}/$fileName');
      await destFile.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Graded Image Saved to Downloads:\n${destFile.path}'),
            duration: const Duration(seconds: 7),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image Export Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // VIDEO EXPORT
  Future<void> _exportVideo(
    String resolution,
    String fps,
    String bitrate,
    String container,
    String audioCodec,
    String audioBitrate,
    String sampleRate,
  ) async {
    if (_controller == null || !_controller!.value.isInitialized || _currentMediaPath == null) return;

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
      final videoPath = _currentMediaPath!;
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
      final exportHeight = 1080;
      final exportWidth = (1080 * _getAspectRatioValue(_selectedRatio)).round();

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
    String unit = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 125,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
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
                onChanged: (v) {
                  onChanged(v);
                  if (_isImage) _processStaticImage();
                },
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${value.toStringAsFixed(2)}$unit',
              style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerCard({
    required String title,
    required String badge1,
    String? badge2,
    required String subtitle,
    required Widget child,
    Widget? headerTrailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101014),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2, right: 10),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F0FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF00F0FF), size: 16),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F0FF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(badge1, style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        if (badge2 != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(badge2, style: const TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              if (headerTrailing != null) headerTrailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildCurveChannelBtn('master', 'Master', Colors.white),
                const SizedBox(width: 6),
                _buildCurveChannelBtn('red', 'Red', Colors.redAccent),
                const SizedBox(width: 6),
                _buildCurveChannelBtn('green', 'Green', Colors.greenAccent),
                const SizedBox(width: 6),
                _buildCurveChannelBtn('blue', 'Blue', Colors.lightBlueAccent),
              ],
            ),
            TextButton.icon(
              onPressed: _resetCurvesOnly,
              icon: const Icon(Icons.refresh, size: 14, color: Colors.white54),
              label: const Text('Reset', style: TextStyle(color: Colors.white70, fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                backgroundColor: const Color(0xFF18181E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
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
            (v) {
              setState(() => activeCurve[i] = v);
              if (_isImage) _processStaticImage();
            },
          ),
      ],
    );
  }

  Widget _buildCurveChannelBtn(String id, String label, Color c) {
    final isSel = _activeCurveChannel == id;
    return GestureDetector(
      onTap: () => setState(() => _activeCurveChannel = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? c.withOpacity(0.25) : const Color(0xFF141418),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSel ? c : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: isSel ? c : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEdgeGlowPalette() {
    final modes = [
      {'label': 'White', 'mode': 0.0, 'color': Colors.white},
      {'label': 'Gold', 'mode': 1.0, 'color': const Color(0xFFFFD700)},
      {'label': 'Quincy', 'mode': 2.0, 'color': const Color(0xFF64B5F6)},
      {'label': 'Cyan', 'mode': 3.0, 'color': const Color(0xFF00F0FF)},
      {'label': 'Crimson', 'mode': 4.0, 'color': const Color(0xFFFF5252)},
    ];

    return Wrap(
      spacing: 6,
      children: modes.map((m) {
        final isSel = (_edgeGlowTint - (m['mode'] as double)).abs() < 0.1;
        final c = m['color'] as Color;
        return GestureDetector(
          onTap: () {
            setState(() => _edgeGlowTint = m['mode'] as double);
            if (_isImage) _processStaticImage();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isSel ? c : const Color(0xFF18181E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isSel ? c : Colors.white12),
            ),
            child: Text(
              m['label'] as String,
              style: TextStyle(
                color: isSel ? Colors.black : Colors.white70,
                fontSize: 10,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
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
                  : (_controller != null && _controller!.value.isInitialized)
                      ? AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
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

    // Timeline duration values
    final currentPos = (_controller != null && _controller!.value.isInitialized)
        ? _controller!.value.position
        : Duration.zero;
    final totalDuration = (_controller != null && _controller!.value.isInitialized)
        ? _controller!.value.duration
        : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName ?? 'Untitled Project'),
        actions: [
          // GOLD FOLDER IMPORT BUTTON AT TOP RIGHT
          IconButton(
            icon: const Icon(Icons.folder_open, color: Color(0xFFFFD700), size: 24),
            tooltip: 'Import Video or Image',
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'],
              );
              if (result != null && result.files.single.path != null) {
                _loadMedia(result.files.single.path!);
              }
            },
          ),
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
                          if (_isImage && _loadedRawImage != null) {
                            _updateCanvasSize(_loadedRawImage!.width, _loadedRawImage!.height);
                            _processStaticImage();
                          } else if (_controller != null && _controller!.value.isInitialized) {
                            _updateCanvasSize(_controller!.value.size.width.toInt(), _controller!.value.size.height.toInt());
                          }
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
                  if (_controller != null && _controller!.value.isInitialized && !_isImage)
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
                        : (_controller != null && _controller!.value.isInitialized)
                            ? AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: VideoPlayer(_controller!),
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

          // TIMELINE SCRUBBER WITH THICKER BAR & EXACT ELAPSED/TOTAL TIMESTAMP COUNTER
          Container(
            color: const Color(0xFF0A0A0D),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                if (!_isImage) ...[
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 24),
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
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        trackHeight: 5, // THICKER PLAYBACK BAR
                        activeTrackColor: const Color(0xFF00F0FF),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: currentPos.inMilliseconds.toDouble().clamp(0.0, totalDuration.inMilliseconds.toDouble() > 0 ? totalDuration.inMilliseconds.toDouble() : 1.0),
                        min: 0,
                        max: totalDuration.inMilliseconds.toDouble() > 0 ? totalDuration.inMilliseconds.toDouble() : 1.0,
                        onChanged: (v) {
                          if (_controller != null && _controller!.value.isInitialized) {
                            _controller!.seekTo(Duration(milliseconds: v.round()));
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // EXACT TIME COUNTER
                  Text(
                    '${_formatDuration(currentPos)} / ${_formatDuration(totalDuration)}',
                    style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ] else ...[
                  const Icon(Icons.image, color: Color(0xFF00F0FF), size: 20),
                  const SizedBox(width: 10),
                  const Text('STATIC HIGH-RES IMAGE ACTIVE', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _exportStaticImage,
                    icon: const Icon(Icons.download, size: 16, color: Colors.black),
                    label: const Text('Export PNG', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  ),
                ],
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
                Tab(text: 'Adjust & Effects'),
                Tab(text: '2026 WIS Presets'),
                Tab(text: 'Master Export'),
              ],
            ),
          ),

          // TAB CONTENT (CARD DRAWERS)
          SizedBox(
            height: 260,
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: ADJUST & EFFECTS (CARD DRAWERS)
                Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          _buildSubcategoryPill('bloom', 'Bloom & Flares'),
                          _buildSubcategoryPill('color', 'Color & Tone'),
                          _buildSubcategoryPill('curves', 'Curves'),
                          _buildSubcategoryPill('ae_tools', 'AE / Sapphire'),
                          _buildSubcategoryPill('sharpness', 'Lines & Bokeh'),
                          _buildSubcategoryPill('grade', 'Grade & Strobe'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          children: [
                            if (_activeCategory == 'bloom') ...[
                              // DEEP GLOW / NORMAL GLOW TOGGLEABLE
                              _buildDrawerCard(
                                title: _isDeepGlow > 0.5 ? 'AE Deep Glow (Inverse Square)' : 'Normal Gaussian Bloom',
                                badge1: _isDeepGlow > 0.5 ? 'Deep Glow' : 'Normal',
                                subtitle: '36-tap continuous Vogel spiral with soft-knee highlight threshold (0 clumping, 0 duplicate halos)',
                                headerTrailing: ChoiceChip(
                                  label: Text(_isDeepGlow > 0.5 ? 'Deep' : 'Normal', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  selected: _isDeepGlow > 0.5,
                                  selectedColor: const Color(0xFF00F0FF),
                                  backgroundColor: const Color(0xFF18181E),
                                  onSelected: (sel) {
                                    setState(() => _isDeepGlow = sel ? 1.0 : 0.0);
                                    if (_isImage) _processStaticImage();
                                  },
                                ),
                                child: Column(
                                  children: [
                                    _buildSliderRow('Glow Intensity', 0.0, 3.0, _glowIntensity, (v) => setState(() => _glowIntensity = v)),
                                    _buildSliderRow('Glow Spread', 0.1, 2.0, _glowSpread, (v) => setState(() => _glowSpread = v)),
                                    if (_isDeepGlow > 0.5)
                                      _buildSliderRow('Falloff Radius', 0.1, 1.5, _deepGlowRadius, (v) => setState(() => _deepGlowRadius = v)),
                                  ],
                                ),
                              ),
                              // SCREEN-SPACE DIFFUSED EDGE GLOW
                              _buildDrawerCard(
                                title: 'Screen-Space Edge Rim Glow',
                                badge1: 'Rim',
                                subtitle: 'Luminous character contour bloom with spreading radius and tint palette',
                                headerTrailing: _buildEdgeGlowPalette(),
                                child: Column(
                                  children: [
                                    _buildSliderRow('Edge Glow Intensity', 0.0, 3.0, _edgeGlow, (v) => setState(() => _edgeGlow = v)),
                                    _buildSliderRow('Edge Spread', 0.1, 2.0, _edgeGlowSpread, (v) => setState(() => _edgeGlowSpread = v)),
                                  ],
                                ),
                              ),
                              // ANAMORPHIC GLASS FLARES
                              _buildDrawerCard(
                                title: 'Optical Anamorphic Flares',
                                badge1: 'Flares',
                                badge2: 'Streak',
                                subtitle: 'Horizontal specular glass glints with continuous Gaussian decay',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Flare Intensity', 0.0, 3.0, _anamorphicFlare, (v) => setState(() => _anamorphicFlare = v)),
                                    _buildSliderRow('Streak Width', 0.1, 2.0, _flareAmount, (v) => setState(() => _flareAmount = v)),
                                  ],
                                ),
                              ),
                            ] else if (_activeCategory == 'color') ...[
                              _buildDrawerCard(
                                title: 'Tone & Dynamic Contrast',
                                badge1: 'Exposure',
                                subtitle: 'Perceptual HDR luminance lift, contrast pivot and gamma grading',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Brightness', -1.0, 3.0, _brightness, (v) => setState(() => _brightness = v)),
                                    _buildSliderRow('Contrast', 0.2, 3.0, _contrast, (v) => setState(() => _contrast = v)),
                                    _buildSliderRow('Saturation', 0.0, 3.0, _saturation, (v) => setState(() => _saturation = v)),
                                    _buildSliderRow('Gamma', 0.2, 3.0, _gamma, (v) => setState(() => _gamma = v)),
                                    _buildSliderRow('Black Crush', 0.0, 1.0, _blackCrush, (v) => setState(() => _blackCrush = v)),
                                  ],
                                ),
                              ),
                              // SHADOWS & HIGHLIGHTS
                              _buildDrawerCard(
                                title: 'Shadows & Highlights Tone Map',
                                badge1: 'Dynamic Range',
                                subtitle: 'Isolates and lifts deep shadows while compressing or boosting hot highlights',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Shadows Lift', -1.0, 1.0, _shadows, (v) => setState(() => _shadows = v)),
                                    _buildSliderRow('Highlights', -1.0, 1.0, _highlights, (v) => setState(() => _highlights = v)),
                                  ],
                                ),
                              ),
                              _buildDrawerCard(
                                title: 'White Balance & Hue',
                                badge1: 'Color',
                                subtitle: 'Kelvin temperature calibration and rotational hue shifting',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Temperature', 2500, 10000, _temperature, (v) => setState(() => _temperature = v), unit: 'K'),
                                    _buildSliderRow('Hue Shift', -180, 180, _hue, (v) => setState(() => _hue = v), unit: '°'),
                                  ],
                                ),
                              ),
                            ] else if (_activeCategory == 'curves') ...[
                              _buildDrawerCard(
                                title: '5-Point Bezier Spline Curves',
                                badge1: 'Colorista',
                                subtitle: 'Master, Red, Green, and Blue independent tone grading splines',
                                child: _buildCurvesEditor(),
                              ),
                            ] else if (_activeCategory == 'ae_tools') ...[
                              // AE / SAPPHIRE RECREATIONS
                              _buildDrawerCard(
                                title: 'Sapphire S_MathOps',
                                badge1: 'Sapphire',
                                subtitle: 'Hardware mathematical blend modes: Screen, Multiply, Overlay, Color Burn',
                                headerTrailing: DropdownButton<double>(
                                  value: _mathOpsMode,
                                  dropdownColor: const Color(0xFF18181E),
                                  items: const [
                                    DropdownMenuItem(value: 0.0, child: Text('Off', style: TextStyle(fontSize: 11))),
                                    DropdownMenuItem(value: 1.0, child: Text('Screen', style: TextStyle(fontSize: 11))),
                                    DropdownMenuItem(value: 2.0, child: Text('Multiply', style: TextStyle(fontSize: 11))),
                                    DropdownMenuItem(value: 3.0, child: Text('Overlay', style: TextStyle(fontSize: 11))),
                                    DropdownMenuItem(value: 4.0, child: Text('Color Burn', style: TextStyle(fontSize: 11))),
                                  ],
                                  onChanged: (v) {
                                    setState(() => _mathOpsMode = v!);
                                    if (_isImage) _processStaticImage();
                                  },
                                ),
                                child: _buildSliderRow('Blend Mix', 0.0, 1.0, _mathOpsMix, (v) => setState(() => _mathOpsMix = v)),
                              ),
                              _buildDrawerCard(
                                title: 'FilmConvert Nitrate',
                                badge1: 'Film Stock',
                                subtitle: 'Kodak/Fuji S-curve dynamic film response & warm shadow pedestal',
                                child: _buildSliderRow('Nitrate Film Mix', 0.0, 1.0, _filmConvertNitrate, (v) => setState(() => _filmConvertNitrate = v)),
                              ),
                              _buildDrawerCard(
                                title: '4-Color Corner Gradient',
                                badge1: 'Gradient',
                                subtitle: 'Amber, Quincy Blue, Crimson and Teal corner-pinned cinematic color wash',
                                child: _buildSliderRow('Gradient Wash Mix', 0.0, 1.0, _fourColorGradMix, (v) => setState(() => _fourColorGradMix = v)),
                              ),
                            ] else if (_activeCategory == 'sharpness') ...[
                              _buildDrawerCard(
                                title: 'Laplacian Micro-Sharpness with Halos',
                                badge1: 'USM',
                                subtitle: 'High-pass unsharp masking tailored for anime with crisp micro-halos',
                                child: _buildSliderRow('Sharpness', 0.0, 3.0, _sharpness, (v) => setState(() => _sharpness = v)),
                              ),
                              // TRUE SOBEL LINE ART
                              _buildDrawerCard(
                                title: 'True Sobel Anime Ink Line Darkener',
                                badge1: 'Manga FX',
                                subtitle: 'Isolates and darkens ONLY character ink lines and outlines without touching shadow fills',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Ink Outlines', 0.0, 3.0, _darkOutlines, (v) => setState(() => _darkOutlines = v)),
                                    _buildSliderRow('Perimeter Darken', 0.0, 3.0, _edgeDarken, (v) => setState(() => _edgeDarken = v)),
                                  ],
                                ),
                              ),
                              // DIRECTIONAL DEPTH OF FIELD
                              _buildDrawerCard(
                                title: 'Directional Depth of Field (Bokeh)',
                                badge1: 'Optics',
                                subtitle: 'Focal plane depth blur with angle rotation',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Bokeh Strength', 0.0, 3.0, _depthOfField, (v) => setState(() => _depthOfField = v)),
                                    _buildSliderRow('Focus Plane', 0.0, 1.0, _dofFocus, (v) => setState(() => _dofFocus = v)),
                                    _buildSliderRow('Angle', -180.0, 180.0, _dofAngle, (v) => setState(() => _dofAngle = v), unit: '°'),
                                  ],
                                ),
                              ),
                            ] else if (_activeCategory == 'grade') ...[
                              _buildDrawerCard(
                                title: 'Bilateral Denoise & Vignette',
                                badge1: 'Look',
                                subtitle: 'Smooth color noise reduction and centered lens falloff',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Denoise', 0.0, 1.0, _denoise, (v) => setState(() => _denoise = v)),
                                    _buildSliderRow('Vignette Falloff', 0.0, 3.0, _vignette, (v) => setState(() => _vignette = v)),
                                    _buildSliderRow('Split Toning', 0.0, 3.0, _splitToning, (v) => setState(() => _splitToning = v)),
                                  ],
                                ),
                              ),
                              _buildDrawerCard(
                                title: 'Black Shutter Strobe',
                                badge1: 'Shutter',
                                subtitle: 'Rhythmic exposure cut to pure black',
                                child: Column(
                                  children: [
                                    _buildSliderRow('Strobe Intensity', 0.0, 3.0, _flickerIntensity, (v) => setState(() => _flickerIntensity = v)),
                                    _buildSliderRow('Strobe Frequency', 0.1, 10.0, _flickerSpeed, (v) => setState(() => _flickerSpeed = v), unit: 'x'),
                                  ],
                                ),
                              ),
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
                    _buildPresetCard('saber vs Rin', 'Fate UBW anamorphic glow & glass flares'),
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
                        _isImage
                            ? 'Render full resolution graded PNG directly to phone Downloads.'
                            : 'Render directly to phone Downloads with Vulkan ${gEnginePrecision}-Bit Compute.',
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
                        child: Text(_isImage ? 'EXPORT GRADED IMAGE' : 'OPEN EXPORT SETTINGS', style: const TextStyle(fontWeight: FontWeight.bold)),
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
