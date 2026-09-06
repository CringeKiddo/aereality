// lib/models.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

enum LayerBlendMode {
  normal,      // 0
  screen,      // 1 (Essential for S_Glow / Deep Glow)
  linearAdd,   // 2 (Exposure / Light wrap)
  overlay,     // 3 (Midtone contrast)
  softLight,   // 4 (Gentle film grade)
  multiply,    // 5 (Deep ink shadows)
}

class AdjustmentLayer {
  String id;
  String name;
  bool isEnabled;
  double opacity; // 0.0 to 1.0
  LayerBlendMode blendMode;

  // Layer Specific Grading Parameters
  double brightness;
  double saturation;
  double contrast;
  double sharpness;
  double gamma;
  double hue;
  double temperature;
  double shadows;
  double highlights;
  double blackCrush;

  // AE Knockoffs & Glows on this layer
  double deepGlowIntensity;
  double deepGlowRadius;
  double deepGlowThreshold;
  double edgeGlowTint; // 0: Neutral, 1: Gold, 2: Cyan, 3: Dark, 4: Crimson
  double thinStreakIntensity;
  double lineChromaStrength;
  double volRaysLength;
  double volRaysDecay;
  double halationRadius;
  double halationWarmth;

  // Sapphire / MBL Suite on this layer
  double sapphireBlendMix;
  double filmConvertNitrate;
  double mblCosmoSkin;
  double mblMojoTealOrange;
  double mblColoristaLift;
  double mblColoristaGamma;
  double mblColoristaGain;
  double vignette;
  double filmGrain;

  // Spline Curves on this layer
  List<double> curveMaster;
  List<double> curveRed;
  List<double> curveGreen;
  List<double> curveBlue;

  AdjustmentLayer({
    required this.id,
    required this.name,
    this.isEnabled = true,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.brightness = 0.0,
    this.saturation = 1.0,
    this.contrast = 1.0,
    this.sharpness = 0.0,
    this.gamma = 1.0,
    this.hue = 0.0,
    this.temperature = 6500.0,
    this.shadows = 0.0,
    this.highlights = 0.0,
    this.blackCrush = 0.0,
    this.deepGlowIntensity = 0.0,
    this.deepGlowRadius = 0.5,
    this.deepGlowThreshold = 0.45,
    this.edgeGlowTint = 0.0,
    this.thinStreakIntensity = 0.0,
    this.lineChromaStrength = 0.0,
    this.volRaysLength = 0.0,
    this.volRaysDecay = 0.92,
    this.halationRadius = 0.0,
    this.halationWarmth = 0.5,
    this.sapphireBlendMix = 0.0,
    this.filmConvertNitrate = 0.0,
    this.mblCosmoSkin = 0.0,
    this.mblMojoTealOrange = 0.0,
    this.mblColoristaLift = 0.0,
    this.mblColoristaGamma = 0.0,
    this.mblColoristaGain = 0.0,
    this.vignette = 0.0,
    this.filmGrain = 0.0,
    List<double>? curveMaster,
    List<double>? curveRed,
    List<double>? curveGreen,
    List<double>? curveBlue,
  })  : curveMaster = curveMaster ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveRed = curveRed ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveGreen = curveGreen ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveBlue = curveBlue ?? [0.0, 0.25, 0.5, 0.75, 1.0];

  AdjustmentLayer copyWith({String? name, bool? isEnabled, double? opacity, LayerBlendMode? blendMode}) {
    return AdjustmentLayer(
      id: id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      brightness: brightness,
      saturation: saturation,
      contrast: contrast,
      sharpness: sharpness,
      gamma: gamma,
      hue: hue,
      temperature: temperature,
      shadows: shadows,
      highlights: highlights,
      blackCrush: blackCrush,
      deepGlowIntensity: deepGlowIntensity,
      deepGlowRadius: deepGlowRadius,
      deepGlowThreshold: deepGlowThreshold,
      edgeGlowTint: edgeGlowTint,
      thinStreakIntensity: thinStreakIntensity,
      lineChromaStrength: lineChromaStrength,
      volRaysLength: volRaysLength,
      volRaysDecay: volRaysDecay,
      halationRadius: halationRadius,
      halationWarmth: halationWarmth,
      sapphireBlendMix: sapphireBlendMix,
      filmConvertNitrate: filmConvertNitrate,
      mblCosmoSkin: mblCosmoSkin,
      mblMojoTealOrange: mblMojoTealOrange,
      mblColoristaLift: mblColoristaLift,
      mblColoristaGamma: mblColoristaGamma,
      mblColoristaGain: mblColoristaGain,
      vignette: vignette,
      filmGrain: filmGrain,
      curveMaster: List.from(curveMaster),
      curveRed: List.from(curveRed),
      curveGreen: List.from(curveGreen),
      curveBlue: List.from(curveBlue),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isEnabled': isEnabled,
        'opacity': opacity,
        'blendMode': blendMode.index,
        'brightness': brightness,
        'saturation': saturation,
        'contrast': contrast,
        'sharpness': sharpness,
        'gamma': gamma,
        'hue': hue,
        'temperature': temperature,
        'shadows': shadows,
        'highlights': highlights,
        'blackCrush': blackCrush,
        'deepGlowIntensity': deepGlowIntensity,
        'deepGlowRadius': deepGlowRadius,
        'deepGlowThreshold': deepGlowThreshold,
        'edgeGlowTint': edgeGlowTint,
        'thinStreakIntensity': thinStreakIntensity,
        'lineChromaStrength': lineChromaStrength,
        'volRaysLength': volRaysLength,
        'volRaysDecay': volRaysDecay,
        'halationRadius': halationRadius,
        'halationWarmth': halationWarmth,
        'sapphireBlendMix': sapphireBlendMix,
        'filmConvertNitrate': filmConvertNitrate,
        'mblCosmoSkin': mblCosmoSkin,
        'mblMojoTealOrange': mblMojoTealOrange,
        'mblColoristaLift': mblColoristaLift,
        'mblColoristaGamma': mblColoristaGamma,
        'mblColoristaGain': mblColoristaGain,
        'vignette': vignette,
        'filmGrain': filmGrain,
        'curveMaster': curveMaster,
        'curveRed': curveRed,
        'curveGreen': curveGreen,
        'curveBlue': curveBlue,
      };

  factory AdjustmentLayer.fromJson(Map<String, dynamic> json) => AdjustmentLayer(
        id: json['id'] ?? 'layer_0',
        name: json['name'] ?? 'Adjustment Layer',
        isEnabled: json['isEnabled'] ?? true,
        opacity: (json['opacity'] ?? 1.0).toDouble(),
        blendMode: LayerBlendMode.values[(json['blendMode'] ?? 0) as int],
        brightness: (json['brightness'] ?? 0.0).toDouble(),
        saturation: (json['saturation'] ?? 1.0).toDouble(),
        contrast: (json['contrast'] ?? 1.0).toDouble(),
        sharpness: (json['sharpness'] ?? 0.0).toDouble(),
        gamma: (json['gamma'] ?? 1.0).toDouble(),
        hue: (json['hue'] ?? 0.0).toDouble(),
        temperature: (json['temperature'] ?? 6500.0).toDouble(),
        shadows: (json['shadows'] ?? 0.0).toDouble(),
        highlights: (json['highlights'] ?? 0.0).toDouble(),
        blackCrush: (json['blackCrush'] ?? 0.0).toDouble(),
        deepGlowIntensity: (json['deepGlowIntensity'] ?? 0.0).toDouble(),
        deepGlowRadius: (json['deepGlowRadius'] ?? 0.5).toDouble(),
        deepGlowThreshold: (json['deepGlowThreshold'] ?? 0.45).toDouble(),
        edgeGlowTint: (json['edgeGlowTint'] ?? 0.0).toDouble(),
        thinStreakIntensity: (json['thinStreakIntensity'] ?? 0.0).toDouble(),
        lineChromaStrength: (json['lineChromaStrength'] ?? 0.0).toDouble(),
        volRaysLength: (json['volRaysLength'] ?? 0.0).toDouble(),
        volRaysDecay: (json['volRaysDecay'] ?? 0.92).toDouble(),
        halationRadius: (json['halationRadius'] ?? 0.0).toDouble(),
        halationWarmth: (json['halationWarmth'] ?? 0.5).toDouble(),
        sapphireBlendMix: (json['sapphireBlendMix'] ?? 0.0).toDouble(),
        filmConvertNitrate: (json['filmConvertNitrate'] ?? 0.0).toDouble(),
        mblCosmoSkin: (json['mblCosmoSkin'] ?? 0.0).toDouble(),
        mblMojoTealOrange: (json['mblMojoTealOrange'] ?? 0.0).toDouble(),
        mblColoristaLift: (json['mblColoristaLift'] ?? 0.0).toDouble(),
        mblColoristaGamma: (json['mblColoristaGamma'] ?? 0.0).toDouble(),
        mblColoristaGain: (json['mblColoristaGain'] ?? 0.0).toDouble(),
        vignette: (json['vignette'] ?? 0.0).toDouble(),
        filmGrain: (json['filmGrain'] ?? 0.0).toDouble(),
        curveMaster: (json['curveMaster'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveRed: (json['curveRed'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveGreen: (json['curveGreen'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
        curveBlue: (json['curveBlue'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

class ProjectData {
  String mediaPath;
  bool isImage;
  String aspectRatio;
  double tonemapMode; // 0: Off (Linear default), 1: Reinhard, 2: ACES Filmic

  // The Multi-Layer Pipeline (Max 4 Layers)
  List<AdjustmentLayer> layers;
  int activeLayerIndex;

  ProjectData({
    required this.mediaPath,
    this.isImage = false,
    this.aspectRatio = "4:5",
    this.tonemapMode = 0.0, // Default Off
    List<AdjustmentLayer>? layers,
    this.activeLayerIndex = 0,
  }) : layers = layers ?? [
          AdjustmentLayer(id: 'layer_base', name: 'Base Grade', blendMode: LayerBlendMode.normal),
          AdjustmentLayer(id: 'layer_glow', name: 'Deep Glow & Rays', blendMode: LayerBlendMode.screen, deepGlowIntensity: 0.0),
        ];

  AdjustmentLayer get currentLayer => layers[activeLayerIndex.clamp(0, layers.length - 1)];

  Map<String, dynamic> toJson() => {
        'mediaPath': mediaPath,
        'isImage': isImage,
        'aspectRatio': aspectRatio,
        'tonemapMode': tonemapMode,
        'layers': layers.map((l) => l.toJson()).toList(),
        'activeLayerIndex': activeLayerIndex,
      };

  factory ProjectData.fromJson(Map<String, dynamic> json) => ProjectData(
        mediaPath: json['mediaPath'] ?? json['videoPath'] ?? '',
        isImage: json['isImage'] ?? false,
        aspectRatio: json['aspectRatio'] ?? "4:5",
        tonemapMode: (json['tonemapMode'] ?? 0.0).toDouble(),
        layers: (json['layers'] as List<dynamic>?)?.map((l) => AdjustmentLayer.fromJson(l as Map<String, dynamic>)).toList() ??
            [AdjustmentLayer(id: 'layer_base', name: 'Base Grade')],
        activeLayerIndex: (json['activeLayerIndex'] ?? 0) as int,
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
  static const String _storageKey = 'aereality_layers_v5.json';

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
