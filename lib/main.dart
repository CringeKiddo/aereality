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

// Modern Palette: Aquamarine Accents & Elegant Lavender Slider Tracks
const Color kAquamarine = Color(0xFF7FFFD4);
const Color kAquamarineDark = Color(0xFF45B39D);
const Color kLavender = Color(0xFFC8B6FF);      // Lavender slider line
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
    debugPrint('FFmpegKitExtended initialization warning: $e');
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
          secondary: kLavender,
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
        codecFlags = '-c:v libx264 -preset fast -pix_fmt yuv420p';
      } else if (codec.contains('H.265')) {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -pix_fmt yuv420p10le'
            : '-c:v libx265 -preset fast -pix_fmt yuv420p';
      } else {
        codecFlags = is10 ? '-c:v libaom-av1 -pix_fmt yuv420p10le' : '-c:v libaom-av1 -pix_fmt yuv420p';
      }
    } else if (container == 'WebM') {
      if (codec.contains('VP9')) {
        codecFlags = is10
            ? '-c:v libvpx-vp9 -pix_fmt yuv420p10le'
            : '-c:v libvpx-vp9 -pix_fmt yuv420p';
      } else {
        codecFlags = is10 ? '-c:v libaom-av1 -pix_fmt yuv420p10le' : '-c:v libaom-av1 -pix_fmt yuv420p';
      }
    } else if (container == 'MOV') {
      if (codec.contains('H.264')) {
        codecFlags = '-c:v libx264 -preset fast -pix_fmt yuv420p';
      } else {
        codecFlags = is10
            ? '-c:v libx265 -preset fast -pix_fmt yuv420p10le'
            : '-c:v libx265 -preset fast -pix_fmt yuv420p';
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
        codecFlags = is10 ? '-c:v libx265 -preset fast -pix_fmt yuv420p10le' : '-c:v libx265 -preset fast -pix_fmt yuv420p';
      } else {
        codecFlags = '-c:v libx264 -preset fast -pix_fmt yuv420p';
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
  double splitToning;
  double denoise;
  double blackCrush;
  double filmGrain;
  double flickerIntensity;
  double flickerSpeed;
  double depthOfField;
  double dofFocus;
  double dofAngle;

  double sapphireBlendMix;
  double mathOpsMode;
  double filmConvertNitrate;
  double fourColorGradMix;
  double tonemapMode;
  double chromaticAberration;

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
    this.splitToning = 0.0,
    this.denoise = 0.0,
    this.blackCrush = 0.0,
    this.filmGrain = 0.0,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 3.0,
    this.depthOfField = 0.0,
    this.dofFocus = 0.5,
    this.dofAngle = 0.0,
    this.sapphireBlendMix = 0.0,
    this.mathOpsMode = 0.0,
    this.filmConvertNitrate = 0.0,
    this.fourColorGradMix = 0.0,
    this.tonemapMode = 1.0,
    this.chromaticAberration = 0.0,
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
        'splitToning': splitToning,
        'denoise': denoise,
        'blackCrush': blackCrush,
        'filmGrain': filmGrain,
        'flickerIntensity': flickerIntensity,
        'flickerSpeed': flickerSpeed,
        'depthOfField': depthOfField,
        'dofFocus': dofFocus,
        'dofAngle': dofAngle,
        'sapphireBlendMix': sapphireBlendMix,
        'mathOpsMode': mathOpsMode,
        'filmConvertNitrate': filmConvertNitrate,
        'fourColorGradMix': fourColorGradMix,
        'tonemapMode': tonemapMode,
        'chromaticAberration': chromaticAberration,
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
        splitToning: (json['splitToning'] ?? 0.0).toDouble(),
        denoise: (json['denoise'] ?? 0.0).toDouble(),
        blackCrush: (json['blackCrush'] ?? 0.0).toDouble(),
        filmGrain: (json['filmGrain'] ?? 0.0).toDouble(),
        flickerIntensity: (json['flickerIntensity'] ?? 0.0).toDouble(),
        flickerSpeed: (json['flickerSpeed'] ?? 3.0).toDouble(),
        depthOfField: (json['depthOfField'] ?? 0.0).toDouble(),
        dofFocus: (json['dofFocus'] ?? 0.5).toDouble(),
        dofAngle: (json['dofAngle'] ?? 0.0).toDouble(),
        sapphireBlendMix: (json['sapphireBlendMix'] ?? 0.0).toDouble(),
        mathOpsMode: (json['mathOpsMode'] ?? 0.0).toDouble(),
        filmConvertNitrate: (json['filmConvertNitrate'] ?? 0.0).toDouble(),
        fourColorGradMix: (json['fourColorGradMix'] ?? 0.0).toDouble(),
        tonemapMode: (json['tonemapMode'] ?? 1.0).toDouble(),
        chromaticAberration: (json['chromaticAberration'] ?? 0.0).toDouble(),
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
        mediaPath: json['mediaPath'],
        data: ProjectData.fromJson(json['data']),
        lastOpened: DateTime.parse(json['lastOpened']),
      );
}

class ProjectManager {
  static const String _kStorageKey = 'aereality_saved_projects_v2';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_kStorageKey.json');
  }

  static Future<List<StoredProject>> getRecentProjects() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content);
      return list.map((e) => StoredProject.fromJson(e)).toList()
        ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveProject(StoredProject project) async {
    try {
      final list = await getRecentProjects();
      final idx = list.indexWhere((p) => p.id == project.id || p.mediaPath == project.mediaPath);
      if (idx >= 0) {
        list[idx] = project;
      } else {
        list.insert(0, project);
      }
      final file = await _getFile();
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
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
    final res = await ProjectManager.getRecentProjects();
    if (mounted) setState(() => _recent = res);
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: kCardDark,
          title: const Text('Render & Pipeline Settings', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('VULKAN ENGINE PRECISION', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('FP32 High-End'),
                    selected: gEnginePrecision == 32,
                    selectedColor: kAquamarine,
                    backgroundColor: kSurfaceDark,
                    labelStyle: TextStyle(color: gEnginePrecision == 32 ? Colors.black : Colors.white),
                    onSelected: (_) => setDlgState(() => setState(() => gEnginePrecision = 32)),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('FP16 Fast Mobile'),
                    selected: gEnginePrecision == 16,
                    selectedColor: kAquamarine,
                    backgroundColor: kSurfaceDark,
                    labelStyle: TextStyle(color: gEnginePrecision == 16 ? Colors.black : Colors.white),
                    onSelected: (_) => setDlgState(() => setState(() => gEnginePrecision = 16)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('TIMELINE DRAFT RESOLUTION', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [0.25, 0.5, 0.75, 1.0].map((s) => ChoiceChip(
                  label: Text('${(s * 100).toInt()}%'),
                  selected: gPreviewScale == s,
                  selectedColor: kAquamarine,
                  backgroundColor: kSurfaceDark,
                  labelStyle: TextStyle(color: gPreviewScale == s ? Colors.black : Colors.white),
                  onSelected: (_) => setDlgState(() => setState(() => gPreviewScale = s)),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('DONE', style: TextStyle(color: kAquamarine, fontWeight: FontWeight.bold)),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: kAquamarine.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: const Text(
                'AEREALITY',
                style: TextStyle(color: kAquamarine, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            const Text('PRO STUDIO', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: kLavender),
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
                  decoration: BoxDecoration(color: kLavender.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: const Text(
                    'FP32 ENGINE',
                    style: TextStyle(color: kLavenderSoft, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
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
                    icon: const Icon(Icons.bookmarks_rounded, color: kLavender, size: 18),
                    label: const Text('SAVED', style: TextStyle(color: kLavenderSoft, fontWeight: FontWeight.w700, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kLavender, width: 1.2),
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
// 5. INTERACTIVE SPLINE CURVE EDITOR WIDGET
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
// 6. COLORISTA WHEEL
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
              activeTrackColor: kLavender,
              inactiveTrackColor: Colors.white12,
              thumbColor: kLavenderSoft,
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
  ui.Image? _loadedRawImage;
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
  double _splitToning = 0.0;
  double _denoise = 0.0;
  double _filmGrain = 0.0;

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
  double _chromaticAberration = 0.0;

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
  VoidCallback _listener = () {};

  ui.Image? _processedImage;
  Timer? _previewTimer;
  bool _isProcessingFrame = false;
  final GlobalKey _activeCanvasKey = GlobalKey();

  int _canvasWidth = 720;
  int _canvasHeight = 900;
  int _srcWidth = 720;
  int _srcHeight = 900;

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
      _splitToning = p.splitToning;
      _denoise = p.denoise;
      _blackCrush = p.blackCrush;
      _filmGrain = p.filmGrain;
      _flickerIntensity = p.flickerIntensity;
      _flickerSpeed = p.flickerSpeed;
      _depthOfField = p.depthOfField;
      _dofFocus = p.dofFocus;
      _dofAngle = p.dofAngle;
      _sapphireBlendMix = p.sapphireBlendMix;
      _mathOpsMode = p.mathOpsMode;
      _filmConvertNitrate = p.filmConvertNitrate;
      _fourColorGradMix = p.fourColorGradMix;
      _tonemapMode = p.tonemapMode;
      _chromaticAberration = p.chromaticAberration;
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

    targetW = (targetW % 2 == 0) ? targetW : targetW + 1;
    targetH = (targetH % 2 == 0) ? targetH : targetH + 1;

    return {'width': targetW, 'height': targetH};
  }

  void _updateCanvasSize(int srcW, int srcH) {
    _srcWidth = srcW;
    _srcHeight = srcH;
    final dims = _calculateTargetDimensions('1080p', _selectedRatio);
    int targetW = (dims['width']! * gPreviewScale).round();
    int targetH = (dims['height']! * gPreviewScale).round();

    _canvasWidth = (targetW % 2 == 0) ? targetW : targetW + 1;
    _canvasHeight = (targetH % 2 == 0) ? targetH : targetH + 1;
  }

  Future<void> _loadShader() async {
    final candidateNames = [
      'assets/shaders/aereality_core.spv',
      'assets/shaders/shader.spv',
      'assets/shaders/aereality_core_32.spv',
      'assets/shaders/aereality_core_16.spv',
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

    _previewTimer?.cancel();
    if (_controller != null) {
      _controller!.removeListener(_listener);
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

    _autoSaveProject();
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
      splitToning: _splitToning,
      denoise: _denoise,
      blackCrush: _blackCrush,
      filmGrain: _filmGrain,
      flickerIntensity: _flickerIntensity,
      flickerSpeed: _flickerSpeed,
      depthOfField: _depthOfField,
      dofFocus: _dofFocus,
      dofAngle: _dofAngle,
      sapphireBlendMix: _sapphireBlendMix,
      mathOpsMode: _mathOpsMode,
      filmConvertNitrate: _filmConvertNitrate,
      fourColorGradMix: _fourColorGradMix,
      tonemapMode: _tonemapMode,
      chromaticAberration: _chromaticAberration,
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
    final uniforms = Float32List(128);

    uniforms[0] = _brightness;
    uniforms[1] = _contrast;
    uniforms[2] = _saturation;
    uniforms[3] = _sharpness;
    uniforms[4] = _gamma;
    uniforms[5] = _hue;
    uniforms[6] = _temperature;

    uniforms[7] = _bloomIntensity;
    uniforms[8] = _bloomSpread;
    uniforms[9] = _bloomThreshold;
    uniforms[10] = _bloomRadius;

    uniforms[11] = _edgeGlowTint;
    uniforms[12] = _edgeDarken;
    uniforms[13] = _anamorphicFlare;
    uniforms[14] = _flareAmount;
    uniforms[15] = _lightRays;
    uniforms[16] = _lightRaysDecay;

    uniforms[17] = _shadows;
    uniforms[18] = _highlights;
    uniforms[19] = _darkOutlines;
    uniforms[20] = _vignette;
    uniforms[21] = _splitToning;
    uniforms[22] = _denoise;
    uniforms[23] = _blackCrush;

    uniforms[24] = _flickerIntensity;
    uniforms[25] = _flickerSpeed;

    double timeSec = 0.0;
    if (_controller != null && _controller!.value.isInitialized) {
      timeSec = _controller!.value.position.inMilliseconds / 1000.0;
    }
    uniforms[26] = timeSec;

    uniforms[27] = _depthOfField;
    uniforms[28] = _dofFocus;
    uniforms[29] = _dofAngle;

    uniforms[30] = _mblCosmoSkin;
    uniforms[31] = _mblRenoirHalation;
    uniforms[32] = _mblColoristaLift;
    uniforms[33] = _mblColoristaGamma;
    uniforms[34] = _mblColoristaGain;
    uniforms[35] = _mblMojoTealOrange;

    uniforms[36] = _sapphireBlendMix;
    uniforms[37] = _mathOpsMode;
    uniforms[38] = _filmConvertNitrate;

    uniforms[39] = _filmGrain;
    uniforms[40] = _tonemapMode;
    uniforms[41] = _chromaticAberration;

    uniforms[42] = _curveRed[0];
    uniforms[43] = _curveRed[1];
    uniforms[44] = _curveRed[2];
    uniforms[45] = _curveRed[3];
    uniforms[46] = _curveRed[4];

    uniforms[47] = _curveGreen[0];
    uniforms[48] = _curveGreen[1];
    uniforms[49] = _curveGreen[2];
    uniforms[50] = _curveGreen[3];
    uniforms[51] = _curveGreen[4];

    uniforms[52] = _curveBlue[0];
    uniforms[53] = _curveBlue[1];
    uniforms[54] = _curveBlue[2];
    uniforms[55] = _curveBlue[3];
    uniforms[56] = _curveBlue[4];

    uniforms[57] = _curveMaster[0];
    uniforms[58] = _curveMaster[1];
    uniforms[59] = _curveMaster[2];
    uniforms[60] = _curveMaster[3];
    uniforms[61] = _curveMaster[4];

    uniforms[62] = _fourColorGradMix;

    return uniforms;
  }

  void _startTimelinePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      if (!mounted || _isProcessingFrame || !_isPlaying || _controller == null) return;
      if (!_controller!.value.isPlaying) return;

      _isProcessingFrame = true;
      try {
        await _processActiveFrame();
      } catch (_) {
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _processActiveFrame() async {
    try {
      final boundary = _activeCanvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final inputBytes = byteData.buffer.asUint8List();
      final uniforms = _packUniforms();

      final outBytes = await computeShaderPass(
        inputBytes: inputBytes,
        width: image.width,
        height: image.height,
        precision: gEnginePrecision,
        uniforms: uniforms,
      );

      final compImage = await _rawRgbaToUiImage(outBytes, image.width, image.height);
      if (mounted) {
        setState(() {
          _processedImage = compImage;
        });
      }
    } catch (_) {}
  }

  Future<void> _processStaticImage() async {
    if (_loadedRawImage == null) return;
    try {
      final byteData = await _loadedRawImage!.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final inputBytes = byteData.buffer.asUint8List();
      final uniforms = _packUniforms();

      final outBytes = await computeShaderPass(
        inputBytes: inputBytes,
        width: _loadedRawImage!.width,
        height: _loadedRawImage!.height,
        precision: gEnginePrecision,
        uniforms: uniforms,
      );

      final compImage = await _rawRgbaToUiImage(outBytes, _loadedRawImage!.width, _loadedRawImage!.height);
      if (mounted) {
        setState(() {
          _processedImage = compImage;
        });
      }
    } catch (_) {}
  }

  Future<ui.Image> _rawRgbaToUiImage(Uint8List rawBytes, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rawBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future;
  }

  void _resetParameters() {
    setState(() {
      _brightness = 0.0;
      _saturation = 1.0;
      _contrast = 1.0;
      _sharpness = 0.0;
      _gamma = 1.0;
      _hue = 0.0;
      _temperature = 6500.0;
      _bloomIntensity = 0.0;
      _bloomSpread = 0.40;
      _bloomThreshold = 0.45;
      _bloomRadius = 1.0;
      _edgeGlowTint = 0.0;
      _edgeDarken = 0.0;
      _anamorphicFlare = 0.0;
      _flareAmount = 0.50;
      _lightRays = 0.0;
      _lightRaysDecay = 0.90;
      _shadows = 0.0;
      _highlights = 0.0;
      _darkOutlines = 0.0;
      _vignette = 0.0;
      _splitToning = 0.0;
      _denoise = 0.0;
      _blackCrush = 0.0;
      _filmGrain = 0.0;
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
      _chromaticAberration = 0.0;
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
    _autoSaveProject();
    if (_isImage) _processStaticImage();
  }

  void _applyPreset(String name) {
    setState(() {
      _resetParameters();
      switch (name) {
        case 'Anime WIS Master':
          _contrast = 1.35;
          _saturation = 1.40;
          _sharpness = 0.35;
          _bloomIntensity = 0.55;
          _bloomSpread = 0.45;
          _bloomThreshold = 0.38;
          _bloomRadius = 1.2;
          _darkOutlines = 0.35;
          _vignette = 0.28;
          _filmGrain = 0.20;
          _chromaticAberration = 0.15;
          _curveMaster = [0.0, 0.22, 0.50, 0.78, 1.0];
          break;

        case 'Kyoto Glow & Warmth':
          _contrast = 1.15;
          _saturation = 1.25;
          _temperature = 5600.0;
          _bloomIntensity = 0.70;
          _bloomSpread = 0.55;
          _bloomThreshold = 0.30;
          _edgeGlowTint = 0.35;
          _anamorphicFlare = 0.25;
          _highlights = 0.20;
          _vignette = 0.20;
          break;

        case 'Makoto Shinkai Sky':
          _contrast = 1.25;
          _saturation = 1.50;
          _sharpness = 0.40;
          _bloomIntensity = 0.45;
          _lightRays = 0.40;
          _highlights = 0.25;
          _curveBlue = [0.0, 0.28, 0.55, 0.80, 1.0];
          _curveRed = [0.0, 0.20, 0.46, 0.72, 1.0];
          break;

        case 'Cyberpunk Neon Drift':
          _contrast = 1.45;
          _saturation = 1.65;
          _darkOutlines = 0.50;
          _anamorphicFlare = 0.60;
          _splitToning = 0.45;
          _bloomIntensity = 0.65;
          _mblMojoTealOrange = 0.55;
          _vignette = 0.40;
          break;

        case 'Moffun Classic 90s Cel':
          _contrast = 1.20;
          _saturation = 1.10;
          _darkOutlines = 0.60;
          _filmGrain = 0.45;
          _flickerIntensity = 0.15;
          _flickerSpeed = 4.0;
          _vignette = 0.35;
          break;
      }
    });
    _autoSaveProject();
    if (_isImage) _processStaticImage();
  }

  void _showPresetPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VULKAN PRESET VAULT', style: TextStyle(color: kAquamarine, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            ...['Anime WIS Master', 'Kyoto Glow & Warmth', 'Makoto Shinkai Sky', 'Cyberpunk Neon Drift', 'Moffun Classic 90s Cel'].map((preset) => ListTile(
              title: Text(preset, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.bolt_rounded, color: kAquamarine, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _applyPreset(preset);
              },
            )),
          ],
        ),
      ),
    );
  }

  double _getAspectRatioValue(String ratio) {
    switch (ratio) {
      case "9:16": return 9.0 / 16.0;
      case "16:9": return 16.0 / 9.0;
      case "1:1":  return 1.0;
      case "3:4":  return 3.0 / 4.0;
      case "21:9": return 21.0 / 9.0;
      case "4:5":
      default:     return 4.0 / 5.0;
    }
  }

  // ============================================================================
  // EXPORT PIPELINE
  // ============================================================================
  void _openExportModal() {
    String selectedContainer = 'MP4';
    String selectedCodec = 'H.265 (HEVC)';
    String selectedRes = '1080p';
    String selectedBitDepth = '8-bit';
    int bitrateMbps = 35;
    int fps = 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: kCardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final codecs = ExportMatrix.containerCodecs[selectedContainer] ?? ['H.264 (AVC)'];
          if (!codecs.contains(selectedCodec)) {
            selectedCodec = codecs.first;
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('MASTER EXPORT SETTINGS', style: TextStyle(color: kAquamarine, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('CONTAINER', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['MP4', 'MKV', 'WebM', 'MOV'].map((c) => ChoiceChip(
                      label: Text(c),
                      selected: selectedContainer == c,
                      selectedColor: kAquamarine,
                      backgroundColor: kSurfaceDark,
                      labelStyle: TextStyle(color: selectedContainer == c ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                      onSelected: (_) => setModalState(() {
                        selectedContainer = c;
                        selectedCodec = ExportMatrix.containerCodecs[c]!.first;
                        if (!ExportMatrix.isBitDepthValid(c, selectedCodec, selectedBitDepth)) {
                          selectedBitDepth = '8-bit';
                        }
                      }),
                    )).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('ENCODE CODEC', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: codecs.map((codec) => ChoiceChip(
                      label: Text(codec),
                      selected: selectedCodec == codec,
                      selectedColor: kLavender,
                      backgroundColor: kSurfaceDark,
                      labelStyle: TextStyle(color: selectedCodec == codec ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                      onSelected: (_) => setModalState(() {
                        selectedCodec = codec;
                        if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
                          selectedBitDepth = '8-bit';
                        }
                      }),
                    )).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('COLOR BIT DEPTH', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['8-bit', '10-bit', '16-bit'].map((bd) {
                      final valid = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, bd);
                      return ChoiceChip(
                        label: Text(bd),
                        selected: selectedBitDepth == bd,
                        selectedColor: kAquamarine,
                        backgroundColor: valid ? kSurfaceDark : Colors.white10,
                        labelStyle: TextStyle(color: !valid ? Colors.white24 : (selectedBitDepth == bd ? Colors.black : Colors.white)),
                        onSelected: valid ? (_) => setModalState(() => selectedBitDepth = bd) : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('TARGET RESOLUTION', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['720p', '1080p', '2K', '4K'].map((res) => ChoiceChip(
                      label: Text(res),
                      selected: selectedRes == res,
                      selectedColor: kAquamarine,
                      backgroundColor: kSurfaceDark,
                      labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                      onSelected: (_) => setModalState(() => selectedRes = res),
                    )).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TARGET BITRATE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('${bitrateMbps} Mbps', style: const TextStyle(color: kAquamarine, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: kLavender,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: kLavenderSoft,
                    ),
                    child: Slider(
                      value: bitrateMbps.toDouble(),
                      min: 5.0,
                      max: 100.0,
                      divisions: 95,
                      onChanged: (v) => setModalState(() => bitrateMbps = v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('EXPORT FPS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('$fps fps', style: const TextStyle(color: kAquamarine, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: kLavender,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: kLavenderSoft,
                    ),
                    child: Slider(
                      value: fps.toDouble(),
                      min: 24.0,
                      max: 60.0,
                      divisions: 36,
                      onChanged: (v) => setModalState(() => fps = v.round()),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startExportProcess(
                          container: selectedContainer,
                          codec: selectedCodec,
                          bitDepth: selectedBitDepth,
                          resolution: selectedRes,
                          bitrateKbps: bitrateMbps * 1000,
                          fps: fps,
                        );
                      },
                      icon: const Icon(Icons.rocket_launch_rounded, color: Colors.black, size: 18),
                      label: const Text('START COMPUTE RENDER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAquamarine,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startExportProcess({
    required String container,
    required String codec,
    required String bitDepth,
    required String resolution,
    required int bitrateKbps,
    required int fps,
  }) async {
    final dims = _calculateTargetDimensions(resolution, _selectedRatio);
    final int outW = dims['width']!;
    final int outH = dims['height']!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RenderExportDialog(
        mediaPath: _currentMediaPath!,
        isImage: _isImage,
        width: outW,
        height: outH,
        fps: fps,
        container: container,
        codec: codec,
        bitDepth: bitDepth,
        bitrateKbps: bitrateKbps,
        uniforms: _packUniforms(),
      ),
    );
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    if (_controller != null) {
      _controller!.removeListener(_listener);
      _controller!.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  // ============================================================================
  // UI BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.projectName ?? 'AEReality Studio Pro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: kAquamarine),
            tooltip: 'Presets',
            onPressed: _showPresetPicker,
          ),
          IconButton(
            icon: const Icon(Icons.replay_rounded, color: Colors.white70),
            tooltip: 'Reset',
            onPressed: _resetParameters,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, color: kAquamarine),
            tooltip: 'Export',
            onPressed: _openExportModal,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Preview Canvas Stage
            Expanded(
              flex: _isFullScreen ? 10 : 5,
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _getAspectRatioValue(_selectedRatio),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0E),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: ClipRect(
                          child: RepaintBoundary(
                            key: _activeCanvasKey,
                            child: _processedImage != null
                                ? RawImage(image: _processedImage, fit: BoxFit.contain)
                                : (_isImage
                                    ? (_loadedRawImage != null ? RawImage(image: _loadedRawImage, fit: BoxFit.contain) : const Center(child: CircularProgressIndicator()))
                                    : (_controller != null && _controller!.value.isInitialized
                                        ? VideoPlayer(_controller!)
                                        : const Center(child: CircularProgressIndicator(color: kAquamarine)))),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          '${_canvasWidth}x$_canvasHeight • $_selectedRatio',
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        icon: Icon(_isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white70),
                        onPressed: () => setState(() => _isFullScreen = !_isFullScreen),
                      ),
                    ),
                    if (!_isImage && _controller != null && _controller!.value.isInitialized)
                      Positioned(
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: kAquamarine),
                                onPressed: () {
                                  setState(() {
                                    if (_isPlaying) {
                                      _controller!.pause();
                                      _isPlaying = false;
                                    } else {
                                      _controller!.play();
                                      _isPlaying = true;
                                    }
                                  });
                                },
                              ),
                              SizedBox(
                                width: 140,
                                child: VideoProgressIndicator(
                                  _controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: kAquamarine,
                                    bufferedColor: Colors.white24,
                                    backgroundColor: Colors.white10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Controls Tabs
            if (!_isFullScreen) ...[
              Container(
                color: kCardDark,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: kAquamarine,
                  labelColor: kAquamarine,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Basic Grade'),
                    Tab(text: 'Glow & Rays'),
                    Tab(text: 'Curves'),
                    Tab(text: 'Colorista'),
                    Tab(text: 'Sapphire & AE'),
                    Tab(text: 'Atmosphere'),
                  ],
                ),
              ),
              Expanded(
                flex: 6,
                child: Container(
                  color: kSurfaceDark,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBasicGradeTab(),
                      _buildGlowRaysTab(),
                      _buildCurvesTab(),
                      _buildColoristaTab(),
                      _buildSapphireTab(),
                      _buildAtmosphereTab(),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // PARAMETER SLIDER BUILDER
  // Lavender Slider Active Track: 0xFFC8B6FF
  // ============================================================================
  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String unit = ''}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.2,
                activeTrackColor: kLavender,       // Lavender active line
                inactiveTrackColor: Colors.white12,
                thumbColor: kLavenderSoft,        // Soft lavender thumb
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: (v) {
                  onChanged(v);
                  _autoSaveProject();
                  if (_isImage) _processStaticImage();
                },
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${value.toStringAsFixed(2)}$unit',
              textAlign: TextAlign.right,
              style: const TextStyle(color: kAquamarine, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB IMPLEMENTATIONS
  // ============================================================================
  Widget _buildBasicGradeTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        _buildSlider('Brightness', _brightness, -1.0, 1.0, (v) => setState(() => _brightness = v)),
        _buildSlider('Contrast', _contrast, 0.0, 2.5, (v) => setState(() => _contrast = v)),
        _buildSlider('Saturation', _saturation, 0.0, 2.5, (v) => setState(() => _saturation = v)),
        _buildSlider('Sharpness (Unsharp)', _sharpness, 0.0, 1.0, (v) => setState(() => _sharpness = v)),
        _buildSlider('Gamma Exponent', _gamma, 0.2, 2.5, (v) => setState(() => _gamma = v)),
        _buildSlider('Hue Offset', _hue, -3.1415, 3.1415, (v) => setState(() => _hue = v)),
        _buildSlider('Color Temp (Kelvin)', _temperature, 2000.0, 12000.0, (v) => setState(() => _temperature = v), unit: 'K'),
        _buildSlider('Shadows Lift', _shadows, -1.0, 1.0, (v) => setState(() => _shadows = v)),
        _buildSlider('Highlights Gain', _highlights, -1.0, 1.0, (v) => setState(() => _highlights = v)),
        _buildSlider('Black Crush (Toe)', _blackCrush, 0.0, 0.5, (v) => setState(() => _blackCrush = v)),
        _buildSlider('Denoise Bilateral', _denoise, 0.0, 1.0, (v) => setState(() => _denoise = v)),
      ],
    );
  }

  Widget _buildGlowRaysTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        _buildSlider('Gaussian Bloom', _bloomIntensity, 0.0, 2.0, (v) => setState(() => _bloomIntensity = v)),
        _buildSlider('Bloom Spread', _bloomSpread, 0.05, 1.5, (v) => setState(() => _bloomSpread = v)),
        _buildSlider('Bloom Luma Cutoff', _bloomThreshold, 0.0, 1.0, (v) => setState(() => _bloomThreshold = v)),
        _buildSlider('Bloom Radius Scale', _bloomRadius, 0.2, 3.0, (v) => setState(() => _bloomRadius = v)),
        _buildSlider('Warm Edge Glow Tint', _edgeGlowTint, 0.0, 1.0, (v) => setState(() => _edgeGlowTint = v)),
        _buildSlider('Vignette Falloff', _vignette, 0.0, 1.0, (v) => setState(() => _vignette = v)),
        _buildSlider('Edge Darken', _edgeDarken, 0.0, 1.0, (v) => setState(() => _edgeDarken = v)),
        _buildSlider('Anamorphic Blue Streak', _anamorphicFlare, 0.0, 1.0, (v) => setState(() => _anamorphicFlare = v)),
        _buildSlider('Flare Width', _flareAmount, 0.1, 1.0, (v) => setState(() => _flareAmount = v)),
        _buildSlider('Radial God Rays', _lightRays, 0.0, 1.0, (v) => setState(() => _lightRays = v)),
        _buildSlider('Rays Decay Length', _lightRaysDecay, 0.5, 0.98, (v) => setState(() => _lightRaysDecay = v)),
      ],
    );
  }

  Widget _buildCurvesTab() {
    Color activeColor;
    List<double> activeList;
    switch (_selectedCurveChannel) {
      case 1:  activeColor = const Color(0xFFFF5252); activeList = _curveRed; break;
      case 2:  activeColor = const Color(0xFF69F0AE); activeList = _curveGreen; break;
      case 3:  activeColor = const Color(0xFF448AFF); activeList = _curveBlue; break;
      case 0:
      default: activeColor = Colors.white; activeList = _curveMaster; break;
    }

    return Column(
      children: [
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCurveChip('Master', 0, Colors.white),
            const SizedBox(width: 8),
            _buildCurveChip('Red', 1, const Color(0xFFFF5252)),
            const SizedBox(width: 8),
            _buildCurveChip('Green', 2, const Color(0xFF69F0AE)),
            const SizedBox(width: 8),
            _buildCurveChip('Blue', 3, const Color(0xFF448AFF)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SplineCurveEditor(
            points: activeList,
            curveColor: activeColor,
            onChanged: (newPts) {
              setState(() {
                if (_selectedCurveChannel == 0) _curveMaster = newPts;
                if (_selectedCurveChannel == 1) _curveRed = newPts;
                if (_selectedCurveChannel == 2) _curveGreen = newPts;
                if (_selectedCurveChannel == 3) _curveBlue = newPts;
              });
              _autoSaveProject();
              if (_isImage) _processStaticImage();
            },
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              if (_selectedCurveChannel == 0) _curveMaster = [0.0, 0.25, 0.5, 0.75, 1.0];
              if (_selectedCurveChannel == 1) _curveRed = [0.0, 0.25, 0.5, 0.75, 1.0];
              if (_selectedCurveChannel == 2) _curveGreen = [0.0, 0.25, 0.5, 0.75, 1.0];
              if (_selectedCurveChannel == 3) _curveBlue = [0.0, 0.25, 0.5, 0.75, 1.0];
            });
            _autoSaveProject();
            if (_isImage) _processStaticImage();
          },
          icon: const Icon(Icons.refresh, size: 14, color: Colors.white54),
          label: const Text('Reset Channel Curve', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildCurveChip(String label, int index, Color col) {
    final sel = _selectedCurveChannel == index;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: col.withOpacity(0.25),
      backgroundColor: kCardDark,
      labelStyle: TextStyle(color: sel ? col : Colors.white60, fontWeight: FontWeight.bold, fontSize: 12),
      side: BorderSide(color: sel ? col : Colors.transparent),
      onSelected: (_) => setState(() => _selectedCurveChannel = index),
    );
  }

  Widget _buildColoristaTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('3-WAY COLOR WHEELS (LIFT / GAMMA / GAIN)', style: TextStyle(color: kAquamarine, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ColoristaWheel(label: 'LIFT (Shadows)', value: _mblColoristaLift, accentColor: const Color(0xFF64B5F6), onChanged: (v) => setState(() => _mblColoristaLift = v)),
            ColoristaWheel(label: 'GAMMA (Mids)', value: _mblColoristaGamma, accentColor: const Color(0xFF81C784), onChanged: (v) => setState(() => _mblColoristaGamma = v)),
            ColoristaWheel(label: 'GAIN (Highlights)', value: _mblColoristaGain, accentColor: const Color(0xFFFFB74D), onChanged: (v) => setState(() => _mblColoristaGain = v)),
          ],
        ),
        const SizedBox(height: 14),
        _buildSlider('Cosmo Skin Smoothing', _mblCosmoSkin, 0.0, 1.0, (v) => setState(() => _mblCosmoSkin = v)),
        _buildSlider('Renoir Warm Halation', _mblRenoirHalation, 0.0, 1.0, (v) => setState(() => _mblRenoirHalation = v)),
        _buildSlider('Mojo II Teal & Orange', _mblMojoTealOrange, 0.0, 1.0, (v) => setState(() => _mblMojoTealOrange = v)),
        _buildSlider('Split Toning Balance', _splitToning, 0.0, 1.0, (v) => setState(() => _splitToning = v)),
      ],
    );
  }

  Widget _buildSapphireTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        _buildSlider('S_MathOps Transfer Mix', _sapphireBlendMix, 0.0, 1.0, (v) => setState(() => _sapphireBlendMix = v)),
        _buildSlider('Anime Dark Linework (Cel)', _darkOutlines, 0.0, 1.0, (v) => setState(() => _darkOutlines = v)),
        _buildSlider('Retro Cel Flicker Intensity', _flickerIntensity, 0.0, 0.5, (v) => setState(() => _flickerIntensity = v)),
        _buildSlider('Flicker Frequency', _flickerSpeed, 1.0, 10.0, (v) => setState(() => _flickerSpeed = v)),
        _buildSlider('Film Grain Texture', _filmGrain, 0.0, 1.0, (v) => setState(() => _filmGrain = v)),
        _buildSlider('FilmConvert Nitrate Halation', _filmConvertNitrate, 0.0, 1.0, (v) => setState(() => _filmConvertNitrate = v)),
        _buildSlider('Chromatic Aberration (RGB Split)', _chromaticAberration, 0.0, 1.0, (v) => setState(() => _chromaticAberration = v)),
        _buildSlider('Tilt-Shift Depth of Field', _depthOfField, 0.0, 1.0, (v) => setState(() => _depthOfField = v)),
        _buildSlider('DoF Focus Center', _dofFocus, 0.0, 1.0, (v) => setState(() => _dofFocus = v)),
        _buildSlider('4-Corner Vignette Gradient', _fourColorGradMix, 0.0, 1.0, (v) => setState(() => _fourColorGradMix = v)),
      ],
    );
  }

  Widget _buildAtmosphereTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      children: [
        const Text('ACES TONEMAPPING OPERATOR', style: TextStyle(color: kAquamarine, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('ACES Filmic Curve'),
              selected: _tonemapMode == 1.0,
              selectedColor: kAquamarine,
              backgroundColor: kCardDark,
              labelStyle: TextStyle(color: _tonemapMode == 1.0 ? Colors.black : Colors.white70),
              onSelected: (_) => setState(() => _tonemapMode = 1.0),
            ),
            ChoiceChip(
              label: const Text('Reinhard Classic'),
              selected: _tonemapMode == 2.0,
              selectedColor: kAquamarine,
              backgroundColor: kCardDark,
              labelStyle: TextStyle(color: _tonemapMode == 2.0 ? Colors.black : Colors.white70),
              onSelected: (_) => setState(() => _tonemapMode = 2.0),
            ),
            ChoiceChip(
              label: const Text('Linear Pass-through'),
              selected: _tonemapMode == 0.0,
              selectedColor: kAquamarine,
              backgroundColor: kCardDark,
              labelStyle: TextStyle(color: _tonemapMode == 0.0 ? Colors.black : Colors.white70),
              onSelected: (_) => setState(() => _tonemapMode = 0.0),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('ASPECT RATIO CROP & LETTERBOX', style: TextStyle(color: kAquamarine, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['4:5', '9:16', '16:9', '1:1', '3:4', '21:9'].map((r) => ChoiceChip(
            label: Text(r),
            selected: _selectedRatio == r,
            selectedColor: kLavender,
            backgroundColor: kCardDark,
            labelStyle: TextStyle(color: _selectedRatio == r ? Colors.black : Colors.white70),
            onSelected: (_) {
              setState(() => _selectedRatio = r);
              if (_controller != null && _controller!.value.isInitialized) {
                _updateCanvasSize(_controller!.value.size.width.toInt(), _controller!.value.size.height.toInt());
              }
              _autoSaveProject();
            },
          )).toList(),
        ),
      ],
    );
  }
}

// ============================================================================
// 8. RENDER EXPORT PROGRESS DIALOG
// ============================================================================
class _RenderExportDialog extends StatefulWidget {
  final String mediaPath;
  final bool isImage;
  final int width;
  final int height;
  final int fps;
  final String container;
  final String codec;
  final String bitDepth;
  final int bitrateKbps;
  final Float32List uniforms;

  const _RenderExportDialog({
    required this.mediaPath,
    required this.isImage,
    required this.width,
    required this.height,
    required this.fps,
    required this.container,
    required this.codec,
    required this.bitDepth,
    required this.bitrateKbps,
    required this.uniforms,
  });

  @override
  State<_RenderExportDialog> createState() => _RenderExportDialogState();
}

class _RenderExportDialogState extends State<_RenderExportDialog> {
  double _progress = 0.0;
  String _status = 'Initializing Vulkan Compute Master Pipeline...';
  bool _done = false;
  String? _outputPath;

  @override
  void initState() {
    super.initState();
    _startWork();
  }

  Future<void> _startWork() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outDir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;

      if (widget.isImage) {
        setState(() => _status = 'Grading high-res still image in FP32...');
        final fileBytes = await File(widget.mediaPath).readAsBytes();
        final rawImg = img.decodeImage(fileBytes);
        if (rawImg == null) throw Exception('Failed to decode source image');

        final resized = img.copyResize(rawImg, width: widget.width, height: widget.height);
        final inBytes = resized.toUint8List();

        final outBytes = await computeShaderPass(
          inputBytes: inBytes,
          width: widget.width,
          height: widget.height,
          precision: gEnginePrecision,
          uniforms: widget.uniforms,
        );

        final resultImg = img.Image.fromBytes(
          width: widget.width,
          height: widget.height,
          bytes: outBytes.buffer,
          order: img.ChannelOrder.rgba,
        );

        final outPath = '${outDir.path}/aereality_$stamp.png';
        await File(outPath).writeAsBytes(img.encodePng(resultImg));

        setState(() {
          _progress = 1.0;
          _status = 'Export finished successfully!';
          _done = true;
          _outputPath = outPath;
        });
      } else {
        setState(() => _status = 'Extracting video frames via FFmpeg...');
        final framesDir = Directory('${tempDir.path}/frames_$stamp');
        await framesDir.create(recursive: true);

        final extractCmd = '-i "${widget.mediaPath}" -r ${widget.fps} "${framesDir.path}/frame_%05d.png"';
        await FFmpegKitExtended.execute(extractCmd);

        final frameFiles = framesDir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

        final totalFrames = frameFiles.length;
        if (totalFrames == 0) throw Exception('No frames extracted from source');

        final processedDir = Directory('${tempDir.path}/proc_$stamp');
        await processedDir.create(recursive: true);

        for (int i = 0; i < totalFrames; i++) {
          final file = frameFiles[i];
          final fBytes = await file.readAsBytes();
          final raw = img.decodeImage(fBytes);
          if (raw != null) {
            final resized = img.copyResize(raw, width: widget.width, height: widget.height);
            final graded = await computeShaderPass(
              inputBytes: resized.toUint8List(),
              width: widget.width,
              height: widget.height,
              precision: gEnginePrecision,
              uniforms: widget.uniforms,
            );
            final outImg = img.Image.fromBytes(
              width: widget.width,
              height: widget.height,
              bytes: graded.buffer,
              order: img.ChannelOrder.rgba,
            );
            final targetPath = '${processedDir.path}/frame_${(i + 1).toString().padLeft(5, '0')}.png';
            await File(targetPath).writeAsBytes(img.encodePng(outImg));
          }

          setState(() {
            _progress = (i + 1) / totalFrames;
            _status = 'Grading frame ${i + 1} of $totalFrames in Vulkan...';
          });
        }

        setState(() => _status = 'Muxing Master Container (${widget.container} / ${widget.codec})...');
        final outExt = widget.container.toLowerCase();
        final finalVideoPath = '${outDir.path}/aereality_master_$stamp.$outExt';

        final muxCmd = ExportMatrix.buildFFmpegEncodeCommand(
          fps: widget.fps,
          framePattern: '${processedDir.path}/frame_%05d.png',
          container: widget.container,
          codec: widget.codec,
          bitDepth: widget.bitDepth,
          bitrateKbps: widget.bitrateKbps,
          outputPath: finalVideoPath,
        );

        await FFmpegKitExtended.execute(muxCmd);

        // Clean up temp directories
        try {
          await framesDir.delete(recursive: true);
          await processedDir.delete(recursive: true);
        } catch (_) {}

        setState(() {
          _progress = 1.0;
          _status = 'Render complete!';
          _done = true;
          _outputPath = finalVideoPath;
        });
      }
    } catch (err) {
      setState(() {
        _status = 'Render failed: $err';
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCardDark,
      title: const Text('Exporting Master Render', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress > 0.0 ? _progress : null,
            color: kAquamarine,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 14),
          Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
          if (_outputPath != null) ...[
            const SizedBox(height: 10),
            Text('Saved to:\n$_outputPath', style: const TextStyle(color: kLavender, fontSize: 10, fontFamily: 'monospace'), textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: [
        if (_done)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(color: kAquamarine, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
