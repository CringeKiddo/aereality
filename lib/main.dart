// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:image/image.dart' as img;

import 'vulkan_bridge.dart';

// Aesthetic Palette: Radiant Aquamarine, Electric Cyan, Gold Highlights, Deep Luxury Carbon
const Color kAquamarine = Color(0xFF7FFFD4);
const Color kAquamarineDark = Color(0xFF45B39D);
const Color kCyanAccent = Color(0xFF00FFFF);
const Color kGold = Color(0xFFFFD700);
const Color kLavenderSoft = Color(0xFFE6E6FA);
const Color kSurfaceDark = Color(0xFF101015);
const Color kCardDark = Color(0xFF15151C);
const Color kBackgroundDark = Color(0xFF08080B);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await FFmpegKitExtended.initialize();
  } catch (e) {
    debugPrint('FFmpegKitExtended startup message: $e');
  }

  runApp(const AERealityApp());
}

class AERealityApp extends StatelessWidget {
  const AERealityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEReality Studio Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBackgroundDark,
        primaryColor: kAquamarine,
        colorScheme: const ColorScheme.dark(
          primary: kAquamarine,
          secondary: kCyanAccent,
          surface: kCardDark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBackgroundDark,
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

int gEnginePrecision = 32;
double gPreviewScale = 0.5;

// ============================================================================
// 1. EXPORT MATRIX & CODEC ENGINE
// ============================================================================
class ExportMatrix {
  static const Map<String, List<String>> containerCodecs = {
    'MP4': ['H.265 (HEVC)', 'H.264 (AVC)', 'AV1 (libaom)'],
    'WebM': ['VP9 (libvpx)', 'AV1 (libaom)'],
    'MOV': ['H.265 (HEVC)', 'H.264 (AVC)'],
    'MKV': ['FFV1 (Lossless 16-Bit)', 'H.265 (HEVC)', 'H.264 (AVC)', 'AV1 (libaom)', 'VP9 (libvpx)'],
  };

  static bool isBitDepthValid(String container, String codec, String bitDepth) {
    if (bitDepth == '16-bit') {
      return container == 'MKV' && codec.startsWith('FFV1');
    }
    if (bitDepth == '10-bit') {
      return !codec.contains('H.264');
    }
    return true;
  }

  static String getAudioCodec(String container) {
    switch (container) {
      case 'WebM':
      case 'MKV':
        return 'libopus';
      case 'MP4':
      case 'MOV':
      default:
        return 'aac';
    }
  }

  static String buildFFmpegEncodeCommand({
    required int fps,
    required String framePattern,
    required String container,
    required String codec,
    required String bitDepth,
    required int bitrateKbps,
    required String outputPath,
  }) {
    final bool is10 = bitDepth == '10-bit';
    final bool is16 = bitDepth == '16-bit';
    String codecFlags;

    if (container == 'MP4') {
      if (codec.contains('H.264')) {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      } else if (codec.contains('H.265')) {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le -profile:v main10'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = is10 ? '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p10le' : '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p';
      }
    } else if (container == 'WebM') {
      if (codec.contains('VP9')) {
        codecFlags = is10
            ? '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -profile:v 2 -vf "unsharp=5:5:0.3:5:5:0.0"'
            : '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p -vf "unsharp=5:5:0.3:5:5:0.0"';
      } else {
        codecFlags = is10 ? '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p10le' : '-c:v libaom-av1 -crf 24 -pix_fmt yuv420p';
      }
    } else if (container == 'MOV') {
      if (codec.contains('H.264')) {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      } else {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le -profile:v main10'
            : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      }
    } else {
      if (codec.startsWith('FFV1')) {
        if (is16) {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt gbrp16le';
        } else if (is10) {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt yuv420p10le';
        } else {
          codecFlags = '-c:v ffv1 -level 3 -pix_fmt yuv420p';
        }
      } else if (codec.contains('H.265')) {
        codecFlags = is10 ? '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p10le' : '-c:v libx265 -preset fast -crf 18 -pix_fmt yuv420p';
      } else if (codec.contains('VP9')) {
        codecFlags = is10
            ? '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p10le -profile:v 2 -vf "unsharp=5:5:0.3:5:5:0.0"'
            : '-c:v libvpx-vp9 -crf 20 -b:v ${bitrateKbps}k -pix_fmt yuv420p -vf "unsharp=5:5:0.3:5:5:0.0"';
      } else {
        codecFlags = '-c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p';
      }
    }

    return '-framerate $fps -i "$framePattern" $codecFlags -b:v ${bitrateKbps}k -y "$outputPath"';
  }
}

// ============================================================================
// 2. PROJECT DATA MODEL
// ============================================================================
class ProjectData {
  String mediaPath;
  bool isImage;
  double brightness;
  double saturation;
  double contrast;
  double sharpness;
  double gamma;
  double hue;
  double temperature;

  double bloomIntensity;
  double bloomSpread;
  double bloomThreshold;
  double bloomRadius;
  double edgeGlowTint;
  double edgeDarken;
  double anamorphicFlare;
  double flareAmount;
  double lightRays;
  double lightRaysDecay;

  double shadows;
  double highlights;
  double darkOutlines;
  double vignette;
  double vignetteBoxed;
  double splitToning;
  double denoise;
  double blackCrush;
  double filmGrain;
  double flickerIntensity;
  double flickerSpeed;
  double depthOfField;
  double dofFocus;
  double dofAngle;
  double chromaticAberration;

  double sapphireBlendMix;
  double mathOpsMode;
  double filmConvertNitrate;
  double fourColorGradMix;
  double tonemapMode;

  double mblCosmoSkin;
  double mblRenoirHalation;
  double mblColoristaLift;
  double mblColoristaGamma;
  double mblColoristaGain;
  double mblMojoTealOrange;

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
    this.bloomIntensity = 0.0,
    this.bloomSpread = 0.40,
    this.bloomThreshold = 0.45,
    this.bloomRadius = 1.0,
    this.edgeGlowTint = 0.0,
    this.edgeDarken = 0.0,
    this.anamorphicFlare = 0.0,
    this.flareAmount = 0.50,
    this.lightRays = 0.0,
    this.lightRaysDecay = 0.90,
    this.shadows = 0.0,
    this.highlights = 0.0,
    this.darkOutlines = 0.0,
    this.vignette = 0.0,
    this.vignetteBoxed = 0.0,
    this.splitToning = 0.0,
    this.denoise = 0.0,
    this.blackCrush = 0.0,
    this.filmGrain = 0.0,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 3.0,
    this.depthOfField = 0.0,
    this.dofFocus = 0.5,
    this.dofAngle = 0.0,
    this.chromaticAberration = 0.0,
    this.sapphireBlendMix = 0.0,
    this.mathOpsMode = 0.0,
    this.filmConvertNitrate = 0.0,
    this.fourColorGradMix = 0.0,
    this.tonemapMode = 1.0,
    this.mblCosmoSkin = 0.0,
    this.mblRenoirHalation = 0.0,
    this.mblColoristaLift = 0.0,
    this.mblColoristaGamma = 0.0,
    this.mblColoristaGain = 0.0,
    this.mblMojoTealOrange = 0.0,
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
        'bloomIntensity': bloomIntensity,
        'bloomSpread': bloomSpread,
        'bloomThreshold': bloomThreshold,
        'bloomRadius': bloomRadius,
        'edgeGlowTint': edgeGlowTint,
        'edgeDarken': edgeDarken,
        'anamorphicFlare': anamorphicFlare,
        'flareAmount': flareAmount,
        'lightRays': lightRays,
        'lightRaysDecay': lightRaysDecay,
        'shadows': shadows,
        'highlights': highlights,
        'darkOutlines': darkOutlines,
        'vignette': vignette,
        'vignetteBoxed': vignetteBoxed,
        'splitToning': splitToning,
        'denoise': denoise,
        'blackCrush': blackCrush,
        'filmGrain': filmGrain,
        'flickerIntensity': flickerIntensity,
        'flickerSpeed': flickerSpeed,
        'depthOfField': depthOfField,
        'dofFocus': dofFocus,
        'dofAngle': dofAngle,
        'chromaticAberration': chromaticAberration,
        'sapphireBlendMix': sapphireBlendMix,
        'mathOpsMode': mathOpsMode,
        'filmConvertNitrate': filmConvertNitrate,
        'fourColorGradMix': fourColorGradMix,
        'tonemapMode': tonemapMode,
        'mblCosmoSkin': mblCosmoSkin,
        'mblRenoirHalation': mblRenoirHalation,
        'mblColoristaLift': mblColoristaLift,
        'mblColoristaGamma': mblColoristaGamma,
        'mblColoristaGain': mblColoristaGain,
        'mblMojoTealOrange': mblMojoTealOrange,
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
        bloomIntensity: (json['bloomIntensity'] ?? 0.0).toDouble(),
        bloomSpread: (json['bloomSpread'] ?? 0.40).toDouble(),
        bloomThreshold: (json['bloomThreshold'] ?? 0.45).toDouble(),
        bloomRadius: (json['bloomRadius'] ?? 1.0).toDouble(),
        edgeGlowTint: (json['edgeGlowTint'] ?? 0.0).toDouble(),
        edgeDarken: (json['edgeDarken'] ?? 0.0).toDouble(),
        anamorphicFlare: (json['anamorphicFlare'] ?? 0.0).toDouble(),
        flareAmount: (json['flareAmount'] ?? 0.50).toDouble(),
        lightRays: (json['lightRays'] ?? 0.0).toDouble(),
        lightRaysDecay: (json['lightRaysDecay'] ?? 0.90).toDouble(),
        shadows: (json['shadows'] ?? 0.0).toDouble(),
        highlights: (json['highlights'] ?? 0.0).toDouble(),
        darkOutlines: (json['darkOutlines'] ?? 0.0).toDouble(),
        vignette: (json['vignette'] ?? 0.0).toDouble(),
        vignetteBoxed: (json['vignetteBoxed'] ?? 0.0).toDouble(),
        splitToning: (json['splitToning'] ?? 0.0).toDouble(),
        denoise: (json['denoise'] ?? 0.0).toDouble(),
        blackCrush: (json['blackCrush'] ?? 0.0).toDouble(),
        filmGrain: (json['filmGrain'] ?? 0.0).toDouble(),
        flickerIntensity: (json['flickerIntensity'] ?? 0.0).toDouble(),
        flickerSpeed: (json['flickerSpeed'] ?? 3.0).toDouble(),
        depthOfField: (json['depthOfField'] ?? 0.0).toDouble(),
        dofFocus: (json['dofFocus'] ?? 0.5).toDouble(),
        dofAngle: (json['dofAngle'] ?? 0.0).toDouble(),
        chromaticAberration: (json['chromaticAberration'] ?? 0.0).toDouble(),
        sapphireBlendMix: (json['sapphireBlendMix'] ?? 0.0).toDouble(),
        mathOpsMode: (json['mathOpsMode'] ?? 0.0).toDouble(),
        filmConvertNitrate: (json['filmConvertNitrate'] ?? 0.0).toDouble(),
        fourColorGradMix: (json['fourColorGradMix'] ?? 0.0).toDouble(),
        tonemapMode: (json['tonemapMode'] ?? 1.0).toDouble(),
        mblCosmoSkin: (json['mblCosmoSkin'] ?? 0.0).toDouble(),
        mblRenoirHalation: (json['mblRenoirHalation'] ?? 0.0).toDouble(),
        mblColoristaLift: (json['mblColoristaLift'] ?? 0.0).toDouble(),
        mblColoristaGamma: (json['mblColoristaGamma'] ?? 0.0).toDouble(),
        mblColoristaGain: (json['mblColoristaGain'] ?? 0.0).toDouble(),
        mblMojoTealOrange: (json['mblMojoTealOrange'] ?? 0.0).toDouble(),
        aspectRatio: json['aspectRatio'] ?? "4:5",
        curveMaster: (json['curveMaster'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveRed: (json['curveRed'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveGreen: (json['curveGreen'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveBlue: (json['curveBlue'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

class StoredProject {
  String id;
  String name;
  String mediaPath;
  ProjectData data;
  DateTime lastOpened;

  StoredProject({
    required this.id,
    required this.name,
    required this.mediaPath,
    required this.data,
    required this.lastOpened,
  });

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
  static const String _storageKey = 'aereality_projects_v3.json';

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
    if (projects.length > 40) projects.removeRange(40, projects.length);
    await saveProjects(projects);
  }
}

// ============================================================================
// 3. HOME SCREEN
// ============================================================================
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
    if (mounted) setState(() => _recent = projs);
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => AlertDialog(
          backgroundColor: kCardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, color: kAquamarine, size: 20),
              SizedBox(width: 8),
              Text('Engine & Preview Quality', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TIMELINE PREVIEW QUALITY', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('25% Draft'),
                    selected: gPreviewScale == 0.25,
                    selectedColor: kAquamarine,
                    backgroundColor: const Color(0xFF1E1E28),
                    labelStyle: TextStyle(color: gPreviewScale == 0.25 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (_) {
                      setModal(() => gPreviewScale = 0.25);
                      setState(() {});
                    },
                  ),
                  ChoiceChip(
                    label: const Text('50% Smooth'),
                    selected: gPreviewScale == 0.50,
                    selectedColor: kAquamarine,
                    backgroundColor: const Color(0xFF1E1E28),
                    labelStyle: TextStyle(color: gPreviewScale == 0.50 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (_) {
                      setModal(() => gPreviewScale = 0.50);
                      setState(() {});
                    },
                  ),
                  ChoiceChip(
                    label: const Text('75% High'),
                    selected: gPreviewScale == 0.75,
                    selectedColor: kAquamarine,
                    backgroundColor: const Color(0xFF1E1E28),
                    labelStyle: TextStyle(color: gPreviewScale == 0.75 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (_) {
                      setModal(() => gPreviewScale = 0.75);
                      setState(() {});
                    },
                  ),
                  ChoiceChip(
                    label: const Text('100% Native'),
                    selected: gPreviewScale == 1.0,
                    selectedColor: kAquamarine,
                    backgroundColor: const Color(0xFF1E1E28),
                    labelStyle: TextStyle(color: gPreviewScale == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    onSelected: (_) {
                      setModal(() => gPreviewScale = 1.0);
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.memory_rounded, color: kAquamarine, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Grading Engine: IEEE FP32 Floating-Point Compute Shader Pipeline.',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Save & Apply', style: TextStyle(color: kAquamarine, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kAquamarine.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kAquamarine.withOpacity(0.3)),
              ),
              child: const Text('AE', style: TextStyle(color: kAquamarine, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Text('AEReality Studio Pro'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: kAquamarine),
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
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
                const Text(
                  'VULKAN COMPUTE • FP32 HDR',
                  style: TextStyle(color: kAquamarine, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: kAquamarine.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: const Text(
                    'FP32 ENGINE',
                    style: TextStyle(color: kAquamarine, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Anime WIS & Master Grade', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Continuous Ring-Free Gaussian Glows, 4K Master Pipeline, Sapphire & Magic Bullet Suite.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())).then((_) => _load()),
                    icon: const Icon(Icons.add_rounded, color: Colors.black, size: 20),
                    label: const Text('NEW PROJECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAquamarine,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (_recent.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: _recent.first.data, projectName: _recent.first.name)),
                        ).then((_) => _load());
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved presets/sessions yet.')));
                      }
                    },
                    icon: const Icon(Icons.bookmarks_rounded, color: kAquamarine, size: 18),
                    label: const Text('SAVED', style: TextStyle(color: kAquamarine, fontWeight: FontWeight.w700, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kAquamarine, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text('RECENT SESSIONS', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_recent.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: kSurfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.video_library_outlined, color: Colors.white24, size: 36),
                    SizedBox(height: 10),
                    Text('No saved sessions found.', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Tap "NEW PROJECT" to grade high-res footage or art.', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
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
                        color: kCardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ListTile(
                        leading: Icon(p.data.isImage ? Icons.image_rounded : Icons.movie_creation_rounded, color: kAquamarine),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${p.mediaPath.split('/').last} • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
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

// ============================================================================
// 4. PROJECT SETUP SCREEN
// ============================================================================
class ProjectSetupScreen extends StatefulWidget {
  const ProjectSetupScreen({super.key});

  @override
  State<ProjectSetupScreen> createState() => _ProjectSetupScreenState();
}

class _ProjectSetupScreenState extends State<ProjectSetupScreen> {
  String _projectName = 'AEReality Master';
  String _selectedAspect = '4:5';
  File? _selectedFile;
  bool _isImage = false;

  final List<String> _aspectRatios = ['4:5', '9:16', '16:9', '1:1', '3:4', '21:9'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Session')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PROJECT TITLE', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: kCardDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'AEReality Master',
              controller: TextEditingController(text: _projectName),
            ),
            const SizedBox(height: 20),
            const Text('OUTPUT ASPECT RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _aspectRatios.map((ratio) => ChoiceChip(
                label: Text(ratio),
                selected: _selectedAspect == ratio,
                selectedColor: kAquamarine,
                backgroundColor: kCardDark,
                labelStyle: TextStyle(color: _selectedAspect == ratio ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                onSelected: (_) => setState(() => _selectedAspect = ratio),
              )).toList(),
            ),
            const SizedBox(height: 24),
            const Text('SOURCE FOOTAGE OR ART', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
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
                  color: kCardDark,
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFile == null ? Icons.folder_open_rounded : (_isImage ? Icons.image_rounded : Icons.movie_creation_rounded),
                      color: kAquamarine,
                      size: 40,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFile == null ? 'Browse video file or high-res image' : _selectedFile!.path.split('/').last,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedFile == null ? 'Supports MKV, WebM, MP4, MOV, PNG, JPG' : '${(_selectedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a media file first')));
                    return;
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectScreen(
                        initialProject: ProjectData(
                          mediaPath: _selectedFile!.path,
                          isImage: _isImage,
                          aspectRatio: _selectedAspect,
                        ),
                        projectName: _projectName,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAquamarine,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('OPEN STUDIO EDITOR', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 5. SPLINE CURVE EDITOR & PAINTER
// ============================================================================
class SplineCurveEditor extends StatefulWidget {
  final List<double> points;
  final Color curveColor;
  final ValueChanged<List<double>> onChanged;

  const SplineCurveEditor({
    super.key,
    required this.points,
    required this.curveColor,
    required this.onChanged,
  });

  @override
  State<SplineCurveEditor> createState() => _SplineCurveEditorState();
}

class _SplineCurveEditorState extends State<SplineCurveEditor> {
  int? _activePointIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double size = math.min(constraints.maxWidth, 220.0);
        return Center(
          child: GestureDetector(
            onPanStart: (details) {
              final RenderBox box = context.findRenderObject() as RenderBox;
              final localPos = box.globalToLocal(details.globalPosition);
              final normX = (localPos.dx / size).clamp(0.0, 1.0);
              final normY = 1.0 - (localPos.dy / size).clamp(0.0, 1.0);

              int bestIdx = 0;
              double bestDist = 9999.0;
              for (int i = 0; i < widget.points.length; i++) {
                final px = i / (widget.points.length - 1);
                final py = widget.points[i];
                final d = math.sqrt((normX - px) * (normX - px) + (normY - py) * (normY - py));
                if (d < bestDist) {
                  bestDist = d;
                  bestIdx = i;
                }
              }
              if (bestDist < 0.25) {
                setState(() => _activePointIndex = bestIdx);
              }
            },
            onPanUpdate: (details) {
              if (_activePointIndex == null) return;
              final RenderBox box = context.findRenderObject() as RenderBox;
              final localPos = box.globalToLocal(details.globalPosition);
              final normY = (1.0 - (localPos.dy / size)).clamp(0.0, 1.0);

              final newPts = List<double>.from(widget.points);
              newPts[_activePointIndex!] = normY;
              widget.onChanged(newPts);
            },
            onPanEnd: (_) => setState(() => _activePointIndex = null),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: CustomPaint(
                painter: _CurvePainter(
                  points: widget.points,
                  color: widget.curveColor,
                  activeIdx: _activePointIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  final int? activeIdx;

  _CurvePainter({required this.points, required this.color, this.activeIdx});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.0;

    for (int i = 1; i < 4; i++) {
      final x = size.width * (i / 4.0);
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final diagPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), diagPaint);

    final path = Path();
    for (int px = 0; px <= size.width.toInt(); px++) {
      final normX = px / size.width;
      final normY = _evalCatmullRom(normX, points);
      final py = size.height - (normY * size.height);
      if (px == 0) {
        path.moveTo(0, py);
      } else {
        path.lineTo(px.toDouble(), py);
      }
    }

    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    for (int i = 0; i < points.length; i++) {
      final cx = (i / (points.length - 1)) * size.width;
      final cy = size.height - (points[i] * size.height);
      final isAct = activeIdx == i;

      final dotPaint = Paint()
        ..color = isAct ? Colors.white : color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), isAct ? 6.0 : 4.0, dotPaint);

      final ringPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(cx, cy), isAct ? 6.0 : 4.0, ringPaint);
    }
  }

  double _evalCatmullRom(double x, List<double> pts) {
    x = x.clamp(0.0, 1.0);
    double seg = x * 4.0;
    int idx = seg.floor();
    if (idx >= 4) return pts[4];
    double t = seg - idx;

    double p0 = pts[math.max(0, idx - 1)];
    double p1 = pts[idx];
    double p2 = pts[math.min(4, idx + 1)];
    double p3 = pts[math.min(4, idx + 2)];

    double m1 = 0.5 * (p2 - p0);
    double m2 = 0.5 * (p3 - p1);

    double t2 = t * t;
    double t3 = t2 * t;

    double h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    double h10 = t3 - 2.0 * t2 + t;
    double h01 = -2.0 * t3 + 3.0 * t2;
    double h11 = t3 - t2;

    return (h00 * p1 + h10 * m1 + h01 * p2 + h11 * m2).clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}

// ============================================================================
// 6. COLORISTA 3-WAY WHEEL
// ============================================================================
class ColoristaWheel extends StatelessWidget {
  final String label;
  final double value;
  final Color accentColor;
  final ValueChanged<double> onChanged;

  const ColoristaWheel({
    super.key,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                accentColor.withOpacity(0.1),
                accentColor.withOpacity(0.6),
                accentColor.withOpacity(0.1),
              ],
            ),
            border: Border.all(color: Colors.white12),
          ),
          child: Center(
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        SizedBox(
          width: 84,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.2,
              activeTrackColor: kAquamarine,
              inactiveTrackColor: Colors.white12,
              thumbColor: kAquamarine,
            ),
            child: Slider(
              value: value.clamp(-0.3, 0.3),
              min: -0.3,
              max: 0.3,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 7. STUDIO EDITOR SCREEN
// ============================================================================
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
  String? _currentMediaPath;
  bool _isImage = false;
  img.Image? _cachedRawImage;
  bool _isFullScreen = false;

  // Primary Grading
  double _brightness = 0.0;
  double _saturation = 1.0;
  double _contrast = 1.0;
  double _sharpness = 0.0;
  double _gamma = 1.0;
  double _hue = 0.0;
  double _temperature = 6500.0;
  double _shadows = 0.0;
  double _highlights = 0.0;
  double _blackCrush = 0.0;
  double _vignette = 0.0;
  double _vignetteBoxed = 0.0;
  double _splitToning = 0.0;
  double _denoise = 0.0;
  double _filmGrain = 0.0;
  double _chromaticAberration = 0.0;

  // Glow & Linework
  double _bloomIntensity = 0.0;
  double _bloomSpread = 0.40;
  double _bloomThreshold = 0.45;
  double _bloomRadius = 1.0;
  double _edgeGlowTint = 0.0;
  double _edgeDarken = 0.0;
  double _darkOutlines = 0.0;
  double _anamorphicFlare = 0.0;
  double _flareAmount = 0.50;
  double _lightRays = 0.0;
  double _lightRaysDecay = 0.90;

  // Flicker
  double _flickerIntensity = 0.0;
  double _flickerSpeed = 3.0;

  // Depth of Field
  double _depthOfField = 0.0;
  double _dofFocus = 0.5;
  double _dofAngle = 0.0;

  // AE & Sapphire Suite
  double _sapphireBlendMix = 0.0;
  double _mathOpsMode = 0.0;
  double _filmConvertNitrate = 0.0;
  double _fourColorGradMix = 0.0;
  double _tonemapMode = 1.0;

  // Magic Bullet Suite
  double _mblCosmoSkin = 0.0;
  double _mblRenoirHalation = 0.0;
  double _mblColoristaLift = 0.0;
  double _mblColoristaGamma = 0.0;
  double _mblColoristaGain = 0.0;
  double _mblMojoTealOrange = 0.0;

  // Spline Curves
  List<double> _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
  List<double> _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
  List<double> _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
  List<double> _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];
  int _selectedCurveChannel = 0;

  String _selectedRatio = "4:5";
  late TabController _tabController;

  ui.Image? _processedImage;
  final GlobalKey _activeCanvasKey = GlobalKey();

  int _renderWidth = 720;
  int _renderHeight = 900;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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
      _bloomIntensity = p.bloomIntensity;
      _bloomSpread = p.bloomSpread;
      _bloomThreshold = p.bloomThreshold;
      _bloomRadius = p.bloomRadius;
      _edgeGlowTint = p.edgeGlowTint;
      _edgeDarken = p.edgeDarken;
      _anamorphicFlare = p.anamorphicFlare;
      _flareAmount = p.flareAmount;
      _lightRays = p.lightRays;
      _lightRaysDecay = p.lightRaysDecay;
      _shadows = p.shadows;
      _highlights = p.highlights;
      _darkOutlines = p.darkOutlines;
      _vignette = p.vignette;
      _vignetteBoxed = p.vignetteBoxed;
      _splitToning = p.splitToning;
      _denoise = p.denoise;
      _blackCrush = p.blackCrush;
      _filmGrain = p.filmGrain;
      _flickerIntensity = p.flickerIntensity;
      _flickerSpeed = p.flickerSpeed;
      _depthOfField = p.depthOfField;
      _dofFocus = p.dofFocus;
      _dofAngle = p.dofAngle;
      _chromaticAberration = p.chromaticAberration;
      _sapphireBlendMix = p.sapphireBlendMix;
      _mathOpsMode = p.mathOpsMode;
      _filmConvertNitrate = p.filmConvertNitrate;
      _fourColorGradMix = p.fourColorGradMix;
      _tonemapMode = p.tonemapMode;
      _mblCosmoSkin = p.mblCosmoSkin;
      _mblRenoirHalation = p.mblRenoirHalation;
      _mblColoristaLift = p.mblColoristaLift;
      _mblColoristaGamma = p.mblColoristaGamma;
      _mblColoristaGain = p.mblColoristaGain;
      _mblMojoTealOrange = p.mblMojoTealOrange;
      _selectedRatio = p.aspectRatio;
      _curveMaster = List.from(p.curveMaster);
      _curveRed = List.from(p.curveRed);
      _curveGreen = List.from(p.curveGreen);
      _curveBlue = List.from(p.curveBlue);
      _loadMedia(p.mediaPath);
    }
  }

  Map<String, int> _calculateTargetDimensions(String resolutionName, String ratioStr) {
    int baseSize;
    switch (resolutionName) {
      case '720p':  baseSize = 720; break;
      case '1080p': baseSize = 1080; break;
      case '2K':    baseSize = 1440; break;
      case '4K':    baseSize = 2160; break;
      default:      baseSize = 1080;
    }

    final double ratio = _getAspectRatioValue(ratioStr);
    int targetW, targetH;

    if (ratio < 1.0) {
      targetW = baseSize;
      targetH = (targetW / ratio).round();
    } else {
      targetH = baseSize;
      targetW = (targetH * ratio).round();
    }

    // 16-pixel workgroup boundary alignment
    targetW = ((targetW + 15) ~/ 16) * 16;
    targetH = ((targetH + 15) ~/ 16) * 16;

    return {'width': targetW, 'height': targetH};
  }

  void _updateDimensions(int srcW, int srcH) {
    final dims = _calculateTargetDimensions('720p', _selectedRatio);
    _renderWidth = dims['width']!;
    _renderHeight = dims['height']!;
  }

  Future<void> _loadShader() async {
    final candidateNames = [
      'assets/shaders/aereality_core.spv',
      'assets/shaders/shader.spv',
      'assets/shaders/aereality_core_32.spv',
    ];

    Uint8List? shaderBytes;
    for (final path in candidateNames) {
      try {
        final byteData = await rootBundle.load(path);
        shaderBytes = byteData.buffer.asUint8List();
        break;
      } catch (_) {}
    }

    if (shaderBytes != null) {
      initVulkan(shaderBytes, gEnginePrecision);
    }
  }

  Future<void> _loadMedia(String path) async {
    final ext = path.split('.').last.toLowerCase();
    final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);

    if (_controller != null) {
      await _controller!.pause();
      await _controller!.dispose();
      _controller = null;
    }

    setState(() {
      _currentMediaPath = path;
      _isImage = isImg;
      _processedImage = null;
      _isPlaying = false;
    });

    if (isImg) {
      final fileBytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(fileBytes);
      if (decoded != null) {
        _cachedRawImage = decoded;
        _updateDimensions(decoded.width, decoded.height);
        _applyGrade();
      }
    } else {
      _cachedRawImage = null;
      _controller = VideoPlayerController.file(File(path))
        ..initialize().then((_) {
          if (!mounted) return;
          final vw = _controller!.value.size.width.toInt();
          final vh = _controller!.value.size.height.toInt();
          _updateDimensions(vw, vh);
          setState(() {});
          _controller!.play();
          _controller!.setLooping(true);
          _isPlaying = true;
          _applyGrade();
        });
    }

    _autoSaveProject();
  }

  Future<void> _applyGrade() async {
    try {
      Uint8List? rawBytes;
      int w = _renderWidth;
      int h = _renderHeight;

      if (_isImage && _cachedRawImage != null) {
        final resized = img.copyResize(_cachedRawImage!, width: w, height: h);
        rawBytes = resized.getBytes(order: img.ChannelOrder.rgba);
      } else {
        final boundary = _activeCanvasKey.currentContext?.findRenderObject();
        if (boundary is RenderRepaintBoundary) {
          final image = await boundary.toImage(pixelRatio: 1.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (byteData != null) {
            w = image.width;
            h = image.height;
            w = ((w + 15) ~/ 16) * 16;
            h = ((h + 15) ~/ 16) * 16;
            rawBytes = byteData.buffer.asUint8List();
          }
          image.dispose();
        }
      }

      if (rawBytes == null) return;

      final uniforms = _packUniforms();
      final outBytes = processImage(rawBytes, w, h, w, h, uniforms);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(outBytes, w, h, ui.PixelFormat.rgba8888, (img) => completer.complete(img));
      final res = await completer.future;

      if (mounted) setState(() => _processedImage = res);
    } catch (_) {}
  }

  Future<void> _autoSaveProject() async {
    if (_currentMediaPath == null) return;
    final proj = StoredProject(
      id: widget.projectName ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
      name: widget.projectName ?? 'AEReality Session',
      mediaPath: _currentMediaPath!,
      data: _buildCurrentProjectData(),
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(proj);
  }

  ProjectData _buildCurrentProjectData() {
    return ProjectData(
      mediaPath: _currentMediaPath ?? '',
      isImage: _isImage,
      brightness: _brightness,
      saturation: _saturation,
      contrast: _contrast,
      sharpness: _sharpness,
      gamma: _gamma,
      hue: _hue,
      temperature: _temperature,
      bloomIntensity: _bloomIntensity,
      bloomSpread: _bloomSpread,
      bloomThreshold: _bloomThreshold,
      bloomRadius: _bloomRadius,
      edgeGlowTint: _edgeGlowTint,
      edgeDarken: _edgeDarken,
      anamorphicFlare: _anamorphicFlare,
      flareAmount: _flareAmount,
      lightRays: _lightRays,
      lightRaysDecay: _lightRaysDecay,
      shadows: _shadows,
      highlights: _highlights,
      darkOutlines: _darkOutlines,
      vignette: _vignette,
      vignetteBoxed: _vignetteBoxed,
      splitToning: _splitToning,
      denoise: _denoise,
      blackCrush: _blackCrush,
      filmGrain: _filmGrain,
      flickerIntensity: _flickerIntensity,
      flickerSpeed: _flickerSpeed,
      depthOfField: _depthOfField,
      dofFocus: _dofFocus,
      dofAngle: _dofAngle,
      chromaticAberration: _chromaticAberration,
      sapphireBlendMix: _sapphireBlendMix,
      mathOpsMode: _mathOpsMode,
      filmConvertNitrate: _filmConvertNitrate,
      fourColorGradMix: _fourColorGradMix,
      tonemapMode: _tonemapMode,
      mblCosmoSkin: _mblCosmoSkin,
      mblRenoirHalation: _mblRenoirHalation,
      mblColoristaLift: _mblColoristaLift,
      mblColoristaGamma: _mblColoristaGamma,
      mblColoristaGain: _mblColoristaGain,
      mblMojoTealOrange: _mblMojoTealOrange,
      aspectRatio: _selectedRatio,
      curveMaster: List.from(_curveMaster),
      curveRed: List.from(_curveRed),
      curveGreen: List.from(_curveGreen),
      curveBlue: List.from(_curveBlue),
    );
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

    uniforms[8] = _bloomIntensity;
    uniforms[9] = _bloomSpread;
    uniforms[10] = _bloomThreshold;
    uniforms[11] = _bloomRadius;
    uniforms[12] = _edgeGlowTint;
    uniforms[13] = _anamorphicFlare;
    uniforms[14] = _flareAmount;
    uniforms[15] = _lightRays;
    uniforms[16] = _lightRaysDecay;

    uniforms[17] = _shadows + _mblColoristaLift;
    uniforms[18] = _highlights + _mblColoristaGain;
    uniforms[19] = _darkOutlines;
    uniforms[20] = _edgeDarken;
    uniforms[21] = _vignette;
    uniforms[22] = _splitToning + _mblMojoTealOrange;
    uniforms[23] = _denoise + _mblCosmoSkin;
    uniforms[24] = _blackCrush;
    uniforms[25] = _flickerIntensity;
    uniforms[26] = _flickerSpeed;
    uniforms[27] = _depthOfField;
    uniforms[28] = _dofFocus;
    uniforms[29] = _dofAngle;
    uniforms[30] = _mathOpsMode;
    uniforms[31] = _sapphireBlendMix;
    uniforms[32] = _filmConvertNitrate + _mblRenoirHalation;
    uniforms[33] = _fourColorGradMix;

    uniforms[34] = _curveMaster[0];
    uniforms[35] = _curveMaster[1];
    uniforms[36] = _curveMaster[2];
    uniforms[37] = _curveMaster[3];
    uniforms[38] = _curveMaster[4];

    uniforms[39] = _filmGrain;
    uniforms[40] = _tonemapMode;
    uniforms[41] = _chromaticAberration;

    uniforms[42] = _curveRed[0];
    uniforms[43] = _curveRed[1];
    uniforms[44] = _curveRed[2];
    uniforms[45] = _curveRed[3];
    uniforms[46] = _curveRed[4];

    uniforms[47] = _vignetteBoxed;

    uniforms[50] = _curveGreen[0];
    uniforms[51] = _curveGreen[1];
    uniforms[52] = _curveGreen[2];
    uniforms[53] = _curveGreen[3];
    uniforms[54] = _curveGreen[4];

    uniforms[58] = _curveBlue[0];
    uniforms[59] = _curveBlue[1];
    uniforms[60] = _curveBlue[2];
    uniforms[61] = _curveBlue[3];
    uniforms[62] = _curveBlue[4];

    return uniforms;
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
      _shadows = 0.0;
      _highlights = 0.0;
      _bloomIntensity = 0.0;
      _bloomSpread = 0.40;
      _bloomThreshold = 0.45;
      _bloomRadius = 1.0;
      _edgeGlowTint = 0.0;
      _edgeDarken = 0.0;
      _darkOutlines = 0.0;
      _anamorphicFlare = 0.0;
      _flareAmount = 0.50;
      _lightRays = 0.0;
      _lightRaysDecay = 0.90;
      _vignette = 0.0;
      _vignetteBoxed = 0.0;
      _splitToning = 0.0;
      _denoise = 0.0;
      _blackCrush = 0.0;
      _filmGrain = 0.0;
      _chromaticAberration = 0.0;
      _flickerIntensity = 0.0;
      _flickerSpeed = 3.0;
      _depthOfField = 0.0;
      _dofFocus = 0.5;
      _dofAngle = 0.0;
      _sapphireBlendMix = 0.0;
      _mathOpsMode = 0.0;
      _filmConvertNitrate = 0.0;
      _fourColorGradMix = 0.0;
      _tonemapMode = 1.0;
      _mblCosmoSkin = 0.0;
      _mblRenoirHalation = 0.0;
      _mblColoristaLift = 0.0;
      _mblColoristaGamma = 0.0;
      _mblColoristaGain = 0.0;
      _mblMojoTealOrange = 0.0;
      _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
      _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _applyPreset(String name) {
    setState(() {
      _resetAllEffects();
      switch (name) {
        case 'vintage cc':
          _brightness = -0.02;
          _saturation = 0.82;
          _contrast = 1.38;
          _sharpness = 0.35;
          _gamma = 0.95;
          _temperature = 6000.0;
          _bloomIntensity = 0.38;
          _bloomSpread = 0.45;
          _bloomThreshold = 0.42;
          _blackCrush = 0.28;
          _darkOutlines = 0.35;
          _vignette = 0.28;
          _filmGrain = 0.20;
          _curveMaster = [0.0, 0.22, 0.50, 0.78, 1.0];
          break;

        case 'adevob+junho':
          _brightness = 0.01;
          _saturation = 1.25;
          _contrast = 1.48;
          _sharpness = 0.65;
          _gamma = 0.92;
          _temperature = 6300.0;
          _bloomIntensity = 0.45;
          _bloomSpread = 0.40;
          _bloomThreshold = 0.42;
          _edgeGlowTint = 1.0;
          _darkOutlines = 0.52;
          _edgeDarken = 0.25;
          _blackCrush = 0.30;
          _vignette = 0.16;
          _curveMaster = [0.0, 0.20, 0.50, 0.82, 1.0];
          break;

        case 'adevobfiller':
          _brightness = 0.0;
          _saturation = 1.20;
          _contrast = 1.38;
          _sharpness = 0.55;
          _gamma = 0.96;
          _temperature = 6400.0;
          _bloomIntensity = 0.36;
          _bloomSpread = 0.42;
          _bloomThreshold = 0.44;
          _blackCrush = 0.20;
          _darkOutlines = 0.38;
          _vignette = 0.12;
          _curveMaster = [0.0, 0.22, 0.50, 0.80, 1.0];
          break;

        case 'uryu vs ichigo':
          _brightness = -0.01;
          _saturation = 1.15;
          _contrast = 1.46;
          _sharpness = 0.68;
          _gamma = 0.94;
          _temperature = 7500.0;
          _bloomIntensity = 0.48;
          _bloomSpread = 0.38;
          _bloomThreshold = 0.40;
          _edgeGlowTint = 2.0;
          _darkOutlines = 0.48;
          _edgeDarken = 0.30;
          _blackCrush = 0.26;
          _vignette = 0.18;
          _curveMaster = [0.0, 0.18, 0.48, 0.82, 1.0];
          break;

        case 'saber vs Rin':
          _brightness = 0.02;
          _saturation = 1.28;
          _contrast = 1.42;
          _sharpness = 0.62;
          _gamma = 0.92;
          _temperature = 6600.0;
          _bloomIntensity = 0.50;
          _bloomSpread = 0.48;
          _bloomThreshold = 0.40;
          _anamorphicFlare = 0.30;
          _flareAmount = 0.45;
          _darkOutlines = 0.35;
          _blackCrush = 0.22;
          _vignette = 0.15;
          _curveMaster = [0.0, 0.22, 0.52, 0.84, 1.0];
          break;

        case 'Dantae cc':
          _brightness = -0.02;
          _saturation = 1.18;
          _contrast = 1.52;
          _sharpness = 0.76;
          _gamma = 0.88;
          _temperature = 6700.0;
          _bloomIntensity = 0.38;
          _bloomSpread = 0.35;
          _bloomThreshold = 0.44;
          _darkOutlines = 0.60;
          _edgeDarken = 0.40;
          _blackCrush = 0.36;
          _vignette = 0.20;
          _curveMaster = [0.0, 0.16, 0.48, 0.86, 1.0];
          break;

        case 'solargotcarried':
          _brightness = 0.02;
          _saturation = 1.30;
          _contrast = 1.55;
          _sharpness = 0.70;
          _gamma = 0.90;
          _temperature = 6100.0;
          _bloomIntensity = 0.52;
          _bloomSpread = 0.42;
          _bloomThreshold = 0.38;
          _edgeGlowTint = 1.0;
          _blackCrush = 0.32;
          _darkOutlines = 0.50;
          _vignette = 0.22;
          _curveMaster = [0.0, 0.18, 0.50, 0.86, 1.0];
          break;

        case 'alucard cc':
          _brightness = -0.03;
          _saturation = 0.90;
          _contrast = 1.58;
          _sharpness = 0.72;
          _gamma = 0.86;
          _temperature = 6000.0;
          _bloomIntensity = 0.32;
          _bloomSpread = 0.32;
          _bloomThreshold = 0.46;
          _darkOutlines = 0.65;
          _edgeDarken = 0.50;
          _blackCrush = 0.42;
          _vignette = 0.30;
          _curveMaster = [0.0, 0.14, 0.45, 0.85, 1.0];
          break;

        case 'mb-mojo':
          _contrast = 1.35;
          _saturation = 1.15;
          _mblMojoTealOrange = 0.65;
          _mblColoristaLift = -0.05;
          _mblColoristaGain = 0.08;
          _bloomIntensity = 0.30;
          _bloomSpread = 0.40;
          _bloomThreshold = 0.45;
          _blackCrush = 0.18;
          _curveMaster = [0.0, 0.22, 0.50, 0.80, 1.0];
          break;

        case 'mb-cosmo':
          _contrast = 1.25;
          _saturation = 1.10;
          _mblCosmoSkin = 0.60;
          _sharpness = 0.35;
          _darkOutlines = 0.30;
          _bloomIntensity = 0.35;
          _bloomSpread = 0.45;
          _bloomThreshold = 0.42;
          break;

        case 'mb-renoir':
          _contrast = 1.30;
          _saturation = 1.05;
          _mblRenoirHalation = 0.55;
          _bloomIntensity = 0.40;
          _bloomSpread = 0.50;
          _bloomThreshold = 0.38;
          _edgeGlowTint = 1.0;
          _blackCrush = 0.15;
          _vignette = 0.15;
          break;

        case 'mb-colorista':
          _contrast = 1.32;
          _saturation = 1.12;
          _mblColoristaLift = 0.04;
          _mblColoristaGamma = 0.02;
          _mblColoristaGain = -0.04;
          _sharpness = 0.40;
          _darkOutlines = 0.25;
          _blackCrush = 0.20;
          break;
      }
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _showExportSheet() {
    if (_isImage) {
      _exportStaticImage();
      return;
    }

    String selectedContainer = 'MP4';
    String selectedCodec = 'H.265 (HEVC)';
    String selectedBitDepth = '10-bit';
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBitrate = '35 Mbps';

    final containers = ['MP4', 'WebM', 'MOV', 'MKV'];
    final resolutions = ['720p', '1080p', '2K', '4K'];
    final fpsOptions = ['24fps', '30fps', '60fps', '90fps'];
    final bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps', '80 Mbps', '120 Mbps'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final targetDims = _calculateTargetDimensions(selectedRes, _selectedRatio);
            final availableCodecs = ExportMatrix.containerCodecs[selectedContainer] ?? ['H.264 (AVC)'];

            if (!availableCodecs.contains(selectedCodec)) {
              selectedCodec = availableCodecs.first;
            }

            if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
              selectedBitDepth = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, '10-bit') ? '10-bit' : '8-bit';
            }

            final is10Supported = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, '10-bit');
            final is16Supported = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, '16-bit');

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
                        const Text('Master Render Pipeline', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Text(
                      '${targetDims['width']} x ${targetDims['height']} • Audio: ${ExportMatrix.getAudioCodec(selectedContainer)} • Engine: Vulkan FP32',
                      style: const TextStyle(color: kAquamarine, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    const Text('CONTAINER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: containers.map((c) => ChoiceChip(
                        label: Text(c),
                        selected: selectedContainer == c,
                        selectedColor: kAquamarine,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedContainer == c ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) {
                            setStateModal(() {
                              selectedContainer = c;
                              selectedCodec = (ExportMatrix.containerCodecs[c] ?? ['H.264 (AVC)']).first;
                            });
                          }
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('CODEC FOR $selectedContainer', style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: availableCodecs.map((codec) => ChoiceChip(
                        label: Text(codec),
                        selected: selectedCodec == codec,
                        selectedColor: kAquamarine,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedCodec == codec ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedCodec = codec);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('BIT-DEPTH PRECISION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('8-bit'),
                            selected: selectedBitDepth == '8-bit',
                            selectedColor: kAquamarine,
                            backgroundColor: const Color(0xFF18181E),
                            labelStyle: TextStyle(color: selectedBitDepth == '8-bit' ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                            onSelected: (_) => setStateModal(() => selectedBitDepth = '8-bit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('10-bit'),
                            selected: selectedBitDepth == '10-bit',
                            selectedColor: kAquamarine,
                            disabledColor: const Color(0xFF121215),
                            backgroundColor: const Color(0xFF18181E),
                            labelStyle: TextStyle(
                              color: !is10Supported ? Colors.white24 : (selectedBitDepth == '10-bit' ? Colors.black : Colors.white),
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: is10Supported ? (_) => setStateModal(() => selectedBitDepth = '10-bit') : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('16-bit (MKV)'),
                            selected: selectedBitDepth == '16-bit',
                            selectedColor: kAquamarine,
                            disabledColor: const Color(0xFF121215),
                            backgroundColor: const Color(0xFF18181E),
                            labelStyle: TextStyle(
                              color: !is16Supported ? Colors.white24 : (selectedBitDepth == '16-bit' ? Colors.black : Colors.white),
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: is16Supported ? (_) => setStateModal(() => selectedBitDepth = '16-bit') : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    const Text('RESOLUTION (UP TO 4K MASTER)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: resolutions.map((res) => ChoiceChip(
                        label: Text(res),
                        selected: selectedRes == res,
                        selectedColor: kAquamarine,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedRes = res);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('FRAMERATE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: fpsOptions.map((fps) => ChoiceChip(
                        label: Text(fps),
                        selected: selectedFps == fps,
                        selectedColor: kAquamarine,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedFps == fps ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedFps = fps);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('TARGET BITRATE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: bitrateOptions.map((bit) => ChoiceChip(
                        label: Text(bit),
                        selected: selectedBitrate == bit,
                        selectedColor: kAquamarine,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedBitrate == bit ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedBitrate = bit);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportVideo(selectedRes, selectedFps, selectedBitrate, selectedContainer, selectedCodec, selectedBitDepth);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAquamarine,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'RENDER $selectedContainer (${selectedCodec.split(' ').first} • $selectedBitDepth)',
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
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

  Future<String> _getSafeMovieDirectory() async {
    final moviesDir = Directory('/storage/emulated/0/Movies');
    if (await moviesDir.exists()) {
      return moviesDir.path;
    }
    final extDir = await getExternalStorageDirectory();
    return extDir?.path ?? (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> _exportStaticImage() async {
    if (_cachedRawImage == null || _currentMediaPath == null) return;
    try {
      final dims = _calculateTargetDimensions('1080p', _selectedRatio);
      final exportWidth = dims['width']!;
      final exportHeight = dims['height']!;

      final resized = img.copyResize(_cachedRawImage!, width: exportWidth, height: exportHeight);
      final rawInput = resized.getBytes(order: img.ChannelOrder.rgba);
      final uniforms = _packUniforms();

      final outputRaw = processImage(
        rawInput,
        exportWidth,
        exportHeight,
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
      final folderPath = await _getSafeMovieDirectory();
      final fileName = 'AEReality_Graded_${DateTime.now().millisecondsSinceEpoch}.png';
      final destFile = File('$folderPath/$fileName');
      await destFile.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Graded Image Saved: ${destFile.path}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image Export Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportVideo(
    String resolution,
    String fps,
    String bitrate,
    String container,
    String codec,
    String bitDepth,
  ) async {
    if (_controller == null || !_controller!.value.isInitialized || _currentMediaPath == null) return;

    final uniforms = _packUniforms();
    final targetDims = _calculateTargetDimensions(resolution, _selectedRatio);
    final int outW = targetDims['width']!;
    final int outH = targetDims['height']!;

    int bitrateKbps = 35000;
    if (bitrate.contains('15')) bitrateKbps = 15000;
    else if (bitrate.contains('50')) bitrateKbps = 50000;
    else if (bitrate.contains('80')) bitrateKbps = 80000;
    else if (bitrate.contains('120')) bitrateKbps = 120000;

    int targetFps = int.parse(fps.replaceAll('fps', ''));
    String containerExt = container.toLowerCase();

    final bool is16Bit = bitDepth == '16-bit';
    final bool is10Bit = bitDepth == '10-bit';

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Extracting pristine frames: 0%');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101014),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Exporting $outW x $outH Master ($bitDepth)', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: kCyanAccent, // Vibrant Cyan Progress Bar
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (_, status, __) => Text(
                  status,
                  style: const TextStyle(color: kCyanAccent, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                ),
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
      await framesDir.create(recursive: true);
      await processedDir.create(recursive: true);

      final audioPath = '${dir.path}/current_audio.aac';
      final oldAudio = File(audioPath);
      if (await oldAudio.exists()) await oldAudio.delete();
      await FFmpegKit.execute('-i "$videoPath" -vn -c:a aac -y "$audioPath"');

      statusNotifier.value = 'Extracting pristine frames...';
      final extractSession = await FFmpegKit.execute(
        '-i "$videoPath" -r $targetFps -s ${outW}x${outH} -pix_fmt rgba -y "${framesDir.path}/frame_%05d.png"',
      );

      var frameFiles = await framesDir.list().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      final totalFrames = frameFiles.length;

      if (totalFrames == 0) {
        final logs = await extractSession.getLogsAsString();
        throw Exception('FFmpeg frame extraction failed. Logs: ${logs ?? "No logs"}');
      }

      for (int i = 0; i < totalFrames; i++) {
        final file = frameFiles[i];
        if (file is! File) continue;
        final bytes = await file.readAsBytes();
        final decoded = img.decodePng(bytes);
        if (decoded == null) continue;

        uniforms[0] = i / targetFps.toDouble();

        img.Image gradedImg;
        if (is10Bit || is16Bit) {
          final rawInput16 = decoded.getBytes(order: img.ChannelOrder.rgba);
          final u16In = rawInput16.buffer.asUint16List();
          final outputRaw16 = processImage16(u16In, outW, outH, outW, outH, uniforms);
          gradedImg = img.Image.fromBytes(
            width: outW,
            height: outH,
            bytes: outputRaw16.buffer,
            numChannels: 4,
            format: img.Format.uint16,
            order: img.ChannelOrder.rgba,
          );
        } else {
          final rawInput8 = decoded.getBytes(order: img.ChannelOrder.rgba);
          final outputRaw8 = processImage(rawInput8, outW, outH, outW, outH, uniforms);
          gradedImg = img.Image.fromBytes(
            width: outW,
            height: outH,
            bytes: outputRaw8.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba,
          );
        }

        final pngBytes = img.encodePng(gradedImg);
        final paddedIndex = (i + 1).toString().padLeft(5, '0');
        final outputFile = File('${processedDir.path}/frame_$paddedIndex.png');
        await outputFile.writeAsBytes(pngBytes);

        final percent = (((i + 1) / totalFrames) * 100).toInt();
        progressNotifier.value = (i + 1) / totalFrames;
        statusNotifier.value = 'Grading frames: $percent% (${i + 1}/$totalFrames)';
      }

      statusNotifier.value = 'Assembling final $container master...';
      final silentOutputPath = '${dir.path}/silent_video.$containerExt';
      final silentFile = File(silentOutputPath);
      if (await silentFile.exists()) await silentFile.delete();

      final encodeCmd = ExportMatrix.buildFFmpegEncodeCommand(
        fps: targetFps,
        framePattern: '${processedDir.path}/frame_%05d.png',
        container: container,
        codec: codec,
        bitDepth: bitDepth,
        bitrateKbps: bitrateKbps,
        outputPath: silentOutputPath,
      );
      final encodeSession = await FFmpegKit.execute(encodeCmd);

      if (!await silentFile.exists()) {
        final logs = await encodeSession.getLogsAsString();
        throw Exception('Encoder failed to generate video. Logs: ${logs ?? "No logs"}');
      }

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length()) > 1000;
      final moviesDir = await _getSafeMovieDirectory();
      final cleanCodec = codec.split(' ').first;
      final fileName = 'AEReality_${resolution}_${cleanCodec}_${bitDepth}_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      final finalOutputFile = File('$moviesDir/$fileName');

      if (hasAudio) {
        final audioCodec = ExportMatrix.getAudioCodec(container);
        await FFmpegKit.execute('-i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $audioCodec -shortest -y "${finalOutputFile.path}"');
      } else {
        await File(silentOutputPath).copy(finalOutputFile.path);
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Master Video Exported:\n${finalOutputFile.path}'), backgroundColor: Colors.green),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName ?? 'AEReality Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: kGold),
            tooltip: 'Import New Footage/Art',
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
            icon: const Icon(Icons.save_rounded, color: Colors.white70),
            tooltip: 'Save Session',
            onPressed: () async {
              await _autoSaveProject();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project saved successfully!'), backgroundColor: Colors.teal));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Reset Grading',
            onPressed: _resetAllEffects,
          ),
          IconButton(
            icon: const Icon(Icons.movie_creation_outlined, color: kAquamarine),
            tooltip: 'Master Render Pipeline',
            onPressed: _showExportSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: _isFullScreen ? 10 : 5,
            child: Center(
              child: AspectRatio(
                aspectRatio: _getAspectRatioValue(_selectedRatio),
                child: Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!_isImage && _controller != null && _controller!.value.isInitialized)
                        RepaintBoundary(
                          key: _activeCanvasKey,
                          child: VideoPlayer(_controller!),
                        ),

                      if (_processedImage != null)
                        RawImage(image: _processedImage, fit: BoxFit.contain),

                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Row(
                          children: [
                            if (!_isImage && _controller != null)
                              GestureDetector(
                                onTap: () {
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
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Icon(
                                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(() => _isFullScreen = !_isFullScreen),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Icon(
                                  _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (!_isFullScreen) ...[
            Container(
              color: kSurfaceDark,
              child: TabBar(
                controller: _tabController,
                indicatorColor: kAquamarine,
                labelColor: kAquamarine,
                unselectedLabelColor: Colors.white38,
                isScrollable: true,
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                tabs: const [
                  Tab(text: 'PRESETS'),
                  Tab(text: 'GRADE'),
                  Tab(text: 'CURVES'),
                  Tab(text: 'GLOWS'),
                  Tab(text: 'SAPPHIRE/AE'),
                  Tab(text: 'MAGIC BULLET'),
                ],
              ),
            ),

            Expanded(
              flex: 4,
              child: Container(
                color: kBackgroundDark,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPresetsTab(),
                    _buildGradingTab(),
                    _buildCurvesTab(),
                    _buildGlowsTab(),
                    _buildSapphireTab(),
                    _buildMagicBulletTab(),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetsTab() {
    final presets = [
      {'name': 'adevob+junho', 'desc': 'Warm golden speculars, crisp ink outlines, clean contrast', 'color': 0xFFFFB300},
      {'name': 'vintage cc', 'desc': 'Deep crushed blacks, authentic film contrast, desaturated tones', 'color': 0xFF9E9E9E},
      {'name': 'adevobfiller', 'desc': 'Balanced midtones, micro-sharp linework, controlled bloom', 'color': 0xFF29B6F6},
      {'name': 'uryu vs ichigo', 'desc': 'Quincy icy cyan specular bloom, deep shadows, high micro-contrast', 'color': 0xFF00E5FF},
      {'name': 'saber vs Rin', 'desc': 'Ufotable cinema style with anamorphic flare and deep blacks', 'color': 0xFFFF4081},
      {'name': 'Dantae cc', 'desc': 'Heavy ink isolation, cold palette, high-contrast dynamic range', 'color': 0xFF7C4DFF},
      {'name': 'solargotcarried', 'desc': 'High-contrast solarized grade calibrated to the 0:28 mark', 'color': 0xFFFFAB00},
      {'name': 'alucard cc', 'desc': 'Hellsing gothic dark grade with cold blacks and natural desaturation', 'color': 0xFFE53935},
      {'name': 'mb-mojo', 'desc': 'Teal shadows and warm specular skin highlights', 'color': 0xFF00ACC1},
      {'name': 'mb-cosmo', 'desc': 'Facial and line-preserving bilateral skin smoothing', 'color': 0xFFEC407A},
      {'name': 'mb-renoir', 'desc': 'Authentic 35mm warm specular halation on high-contrast edges', 'color': 0xFFFF7043},
      {'name': 'mb-colorista', 'desc': 'Balanced 3-way color wheel master grade', 'color': 0xFFAB47BC},
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: presets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = presets[i];
        return GestureDetector(
          onTap: () => _applyPreset(item['name'] as String),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kCardDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(item['color'] as int),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(item['desc'] as String, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradingTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildSliderRow('Contrast (0.18 Mid-Gray Pivot)', _contrast, 0.5, 2.5, (v) => setState(() => _contrast = v)),
        _buildSliderRow('Highlights', _highlights, -1.0, 1.0, (v) => setState(() => _highlights = v)),
        _buildSliderRow('Shadows', _shadows, -1.0, 1.0, (v) => setState(() => _shadows = v)),
        _buildSliderRow('Black Crush', _blackCrush, 0.0, 1.0, (v) => setState(() => _blackCrush = v)),
        _buildSliderRow('Gamma Curve', _gamma, 0.4, 2.0, (v) => setState(() => _gamma = v)),
        _buildSliderRow('Saturation (Headroom-Safe)', _saturation, 0.0, 2.5, (v) => setState(() => _saturation = v)),
        _buildSliderRow('Hue Shift', _hue, -0.5, 0.5, (v) => setState(() => _hue = v)),
        _buildSliderRow('Exposure / Brightness', _brightness, -1.0, 1.0, (v) => setState(() => _brightness = v)),
        _buildSliderRow('Micro-Sharpness (With Edge Halo)', _sharpness, 0.0, 1.5, (v) => setState(() => _sharpness = v)),
        _buildSliderRow('Chromatic Aberration (Prism Fringe)', _chromaticAberration, 0.0, 1.0, (v) => setState(() => _chromaticAberration = v)),
        _buildSliderRow('Split Toning (Subtle Push)', _splitToning, 0.0, 1.0, (v) => setState(() => _splitToning = v)),
        _buildSliderRow('Denoise (Bilateral Filter)', _denoise, 0.0, 1.0, (v) => setState(() => _denoise = v)),
        _buildSliderRow('Film Grain & Micro-Texture', _filmGrain, 0.0, 1.0, (v) => setState(() => _filmGrain = v)),
        _buildSliderRow('Consistent Flicker Intensity', _flickerIntensity, 0.0, 1.0, (v) => setState(() => _flickerIntensity = v)),
        _buildSliderRow('Consistent Flicker Speed', _flickerSpeed, 1.0, 10.0, (v) => setState(() => _flickerSpeed = v)),
        _buildSliderRow('Vignette (Radial)', _vignette, 0.0, 1.0, (v) => setState(() => _vignette = v)),
        _buildSliderRow('Vignette (Boxed / Letterbox Shape)', _vignetteBoxed, 0.0, 1.0, (v) => setState(() => _vignetteBoxed = v)),
        _buildSliderRow('Color Temperature (K)', _temperature, 3000.0, 9500.0, (v) => setState(() => _temperature = v)),
      ],
    );
  }

  Widget _buildCurvesTab() {
    final channelColors = [Colors.white, Colors.redAccent, Colors.greenAccent, Colors.blueAccent];
    final channelNames = ['RGB Master', 'Red', 'Green', 'Blue'];

    List<double> currentPts;
    switch (_selectedCurveChannel) {
      case 1: currentPts = _curveRed; break;
      case 2: currentPts = _curveGreen; break;
      case 3: currentPts = _curveBlue; break;
      case 0:
      default: currentPts = _curveMaster; break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (idx) {
              final isSel = _selectedCurveChannel == idx;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(channelNames[idx]),
                  selected: isSel,
                  selectedColor: channelColors[idx].withOpacity(0.25),
                  backgroundColor: kCardDark,
                  labelStyle: TextStyle(
                    color: isSel ? channelColors[idx] : Colors.white60,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedCurveChannel = idx);
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          SplineCurveEditor(
            points: currentPts,
            curveColor: channelColors[_selectedCurveChannel],
            onChanged: (newPts) {
              setState(() {
                switch (_selectedCurveChannel) {
                  case 1: _curveRed = newPts; break;
                  case 2: _curveGreen = newPts; break;
                  case 3: _curveBlue = newPts; break;
                  case 0:
                  default: _curveMaster = newPts; break;
                }
              });
              _applyGrade();
            },
          ),
          const SizedBox(height: 12),
          const Text('CURVE POINT SLIDERS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...List.generate(5, (pIdx) {
            final labels = ['Blacks (P0)', 'Shadows (P1)', 'Midtones (P2)', 'Highlights (P3)', 'Whites (P4)'];
            return _buildSliderRow(
              labels[pIdx],
              currentPts[pIdx],
              0.0,
              1.0,
              (v) {
                setState(() {
                  final updated = List<double>.from(currentPts);
                  updated[pIdx] = v;
                  switch (_selectedCurveChannel) {
                    case 1: _curveRed = updated; break;
                    case 2: _curveGreen = updated; break;
                    case 3: _curveBlue = updated; break;
                    case 0:
                    default: _curveMaster = updated; break;
                  }
                });
                _applyGrade();
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGlowsTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildSliderRow('Gaussian Bloom Intensity', _bloomIntensity, 0.0, 1.5, (v) => setState(() => _bloomIntensity = v)),
        _buildSliderRow('Bloom Spread (Smoothness)', _bloomSpread, 0.1, 1.0, (v) => setState(() => _bloomSpread = v)),
        _buildSliderRow('Bright-Pass Threshold', _bloomThreshold, 0.1, 0.9, (v) => setState(() => _bloomThreshold = v)),
        const SizedBox(height: 10),
        const Text('BLOOM TINT HARMONY (INCLUDING INK BLACK GLOW)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Neutral'),
              selected: _edgeGlowTint == 0.0,
              selectedColor: kAquamarine,
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _edgeGlowTint = 0.0); _applyGrade(); },
            ),
            ChoiceChip(
              label: const Text('Gold / Warm'),
              selected: _edgeGlowTint == 1.0,
              selectedColor: const Color(0xFFFFB300),
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _edgeGlowTint = 1.0); _applyGrade(); },
            ),
            ChoiceChip(
              label: const Text('Quincy Cyan'),
              selected: _edgeGlowTint == 2.0,
              selectedColor: const Color(0xFF00E5FF),
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _edgeGlowTint = 2.0); _applyGrade(); },
            ),
            ChoiceChip(
              label: const Text('Crimson'),
              selected: _edgeGlowTint == 4.0,
              selectedColor: const Color(0xFFE53935),
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _edgeGlowTint = 4.0); _applyGrade(); },
            ),
            ChoiceChip(
              label: const Text('Black / Ink Shadow'),
              selected: _edgeGlowTint == 5.0,
              selectedColor: Colors.white54,
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _edgeGlowTint = 5.0); _applyGrade(); },
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildSliderRow('Edge Darken (Weak/Fade Line-Art Glow Shadow)', _edgeDarken, 0.0, 1.0, (v) => setState(() => _edgeDarken = v)),
        _buildSliderRow('Sobel Ink Outlines', _darkOutlines, 0.0, 1.0, (v) => setState(() => _darkOutlines = v)),
        _buildSliderRow('Anamorphic 1D Flare', _anamorphicFlare, 0.0, 1.0, (v) => setState(() => _anamorphicFlare = v)),
        _buildSliderRow('Flare Stretch', _flareAmount, 0.1, 1.0, (v) => setState(() => _flareAmount = v)),
        _buildSliderRow('Light Rays / God Rays', _lightRays, 0.0, 1.0, (v) => setState(() => _lightRays = v)),
        _buildSliderRow('Light Rays Decay', _lightRaysDecay, 0.70, 0.98, (v) => setState(() => _lightRaysDecay = v)),
      ],
    );
  }

  Widget _buildSapphireTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text('HDR TONEMAPPING OPERATOR', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Off (Linear)'),
              selected: _tonemapMode == 0.0,
              selectedColor: kAquamarine,
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _tonemapMode = 0.0); _applyGrade(); },
            ),
            ChoiceChip(
              label: const Text('Reinhard'),
              selected: _tonemapMode == 1.0,
              selectedColor: kAquamarine,
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _tonemapMode = 1.0); _applyGrade(); },
            ),
            ChoiceChip(
              label: const Text('ACES Filmic'),
              selected: _tonemapMode == 2.0,
              selectedColor: kAquamarine,
              backgroundColor: const Color(0xFF18181E),
              onSelected: (_) { setState(() => _tonemapMode = 2.0); _applyGrade(); },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSliderRow('Sapphire Blend Mix', _sapphireBlendMix, 0.0, 1.0, (v) => setState(() => _sapphireBlendMix = v)),
        _buildSliderRow('FilmConvert Nitrate Stock Mix', _filmConvertNitrate, 0.0, 1.0, (v) => setState(() => _filmConvertNitrate = v)),
        _buildSliderRow('4-Corner Vignette Gradient Mix', _fourColorGradMix, 0.0, 1.0, (v) => setState(() => _fourColorGradMix = v)),
      ],
    );
  }

  Widget _buildMagicBulletTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text('3-WAY COLORISTA WHEELS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ColoristaWheel(
              label: 'LIFT (Shadows)',
              value: _mblColoristaLift,
              accentColor: kAquamarine,
              onChanged: (v) { setState(() => _mblColoristaLift = v); _applyGrade(); },
            ),
            ColoristaWheel(
              label: 'GAMMA (Mids)',
              value: _mblColoristaGamma,
              accentColor: kAquamarine,
              onChanged: (v) { setState(() => _mblColoristaGamma = v); _applyGrade(); },
            ),
            ColoristaWheel(
              label: 'GAIN (Highs)',
              value: _mblColoristaGain,
              accentColor: const Color(0xFFFF7043),
              onChanged: (v) { setState(() => _mblColoristaGain = v); _applyGrade(); },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSliderRow('Cosmo II (Bilateral Skin Smooth)', _mblCosmoSkin, 0.0, 1.0, (v) => setState(() => _mblCosmoSkin = v)),
        _buildSliderRow('Mojo II (Teal / Orange Contrast)', _mblMojoTealOrange, 0.0, 1.0, (v) => setState(() => _mblMojoTealOrange = v)),
        _buildSliderRow('Renoir (35mm Edge Halation)', _mblRenoirHalation, 0.0, 1.0, (v) => setState(() => _mblRenoirHalation = v)),
        _buildSliderRow('Depth of Field (Tilt-Shift)', _depthOfField, 0.0, 1.0, (v) => setState(() => _depthOfField = v)),
        _buildSliderRow('Focal Plane Position', _dofFocus, 0.0, 1.0, (v) => setState(() => _dofFocus = v)),
      ],
    );
  }

  Widget _buildSliderRow(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(val.toStringAsFixed(2), style: const TextStyle(color: kAquamarine, fontSize: 11, fontFamily: 'monospace')),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.2,
              activeTrackColor: kAquamarine,
              inactiveTrackColor: Colors.white12,
              thumbColor: kAquamarine,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: val.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                onChanged(v);
                _applyGrade();
              },
              onChangeEnd: (_) {
                _autoSaveProject();
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_controller != null) {
      _controller!.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }
}
