import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum LayerBlendMode {
  normal,
  screen,
  linearAdd,
  overlay,
  softLight,
  multiply,
}

class LutModel {
  final String id;
  final String name;
  final String filePath;
  final int size; // Usually 32 or 33
  final Float32List table; // size * size * size * 3

  LutModel({
    required this.id,
    required this.name,
    required this.filePath,
    required this.size,
    required this.table,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'size': size,
  };

  factory LutModel.fromJson(Map<String, dynamic> json) => LutModel(
    id: json['id'] ?? '',
    name: json['name'] ?? 'LUT',
    filePath: json['filePath'] ?? '',
    size: json['size'] ?? 32,
    table: Float32List(0),
  );
}

class AdjustmentLayer {
  String id;
  String name;
  bool isEnabled;
  double opacity;
  LayerBlendMode blendMode;

  // Grade
  double contrast;
  double saturation;
  double brightness;
  double sharpness;
  double gamma;
  double hue;
  double temperature;
  double shadows;
  double highlights;
  double blackCrush;
  double vignette;
  double vignetteBoxed;
  double edgeDarken;
  double darkOutlines;
  double denoise;
  double filmGrain;
  double flickerIntensity;
  double flickerSpeed;
  double halationRadius;
  double halationWarmth;

  // AE & Sapphire Glows / Flares
  double deepGlowIntensity;
  double deepGlowRadius;
  double deepGlowThreshold;
  double edgeGlowTint;
  double thinStreakIntensity;
  double thinStreakWidth;
  double thinStreakOpacity;
  double lineChromaStrength;
  double volRaysLength;
  double volRaysDecay;
  double sapphireGlowWidth;
  double sapphireGlowThreshold;

  // Depth of Field
  double depthOfField;
  double dofFocus;
  double dofAngle;

  // Unsharp Mask Sub-Sliders
  double unsharpRadius;
  double unsharpAmount;
  double unsharpThreshold;

  // Spline Curves
  List<double> curveMaster;
  List<double> curveRed;
  List<double> curveGreen;
  List<double> curveBlue;

  // Magic Bullet & BSLA
  double mblMojoTealOrange;
  double mblColoristaLift;
  double mblColoristaGamma;
  double mblColoristaGain;
  double bslaGodRays;
  double bslaFogDensity;
  double bslaFogDepth;
  double bslaBloomHaze;
  double bslFogScatter; // Added: Volumetric mist atmosphere scattering

  // 3D LUT Implementation
  String? activeLutId;
  double lutOpacity;

  AdjustmentLayer({
    required this.id,
    required this.name,
    this.isEnabled = true,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.brightness = 0.0,
    this.sharpness = 0.0,
    this.gamma = 1.0,
    this.hue = 0.0,
    this.temperature = 6500.0,
    this.shadows = 0.0,
    this.highlights = 0.0,
    this.blackCrush = 0.0,
    this.vignette = 0.0,
    this.vignetteBoxed = 0.0,
    this.edgeDarken = 0.0,
    this.darkOutlines = 0.0,
    this.denoise = 0.0,
    this.filmGrain = 0.0,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 6.0,
    this.halationRadius = 0.0,
    this.halationWarmth = 0.0,
    this.deepGlowIntensity = 0.0,
    this.deepGlowRadius = 0.5,
    this.deepGlowThreshold = 0.45,
    this.edgeGlowTint = 0.0,
    this.thinStreakIntensity = 0.0,
    this.thinStreakWidth = 0.5,
    this.thinStreakOpacity = 1.0,
    this.lineChromaStrength = 0.0,
    this.volRaysLength = 0.0,
    this.volRaysDecay = 0.88,
    this.sapphireGlowWidth = 0.0,
    this.sapphireGlowThreshold = 0.5,
    this.depthOfField = 0.0,
    this.dofFocus = 0.5,
    this.dofAngle = 0.0,
    this.unsharpRadius = 1.5,
    this.unsharpAmount = 0.0,
    this.unsharpThreshold = 0.02,
    List<double>? curveMaster,
    List<double>? curveRed,
    List<double>? curveGreen,
    List<double>? curveBlue,
    this.mblMojoTealOrange = 0.0,
    this.mblColoristaLift = 0.0,
    this.mblColoristaGamma = 0.0,
    this.mblColoristaGain = 0.0,
    this.bslaGodRays = 0.0,
    this.bslaFogDensity = 0.0,
    this.bslaFogDepth = 0.5,
    this.bslaBloomHaze = 0.0,
    this.bslFogScatter = 0.35,
    this.activeLutId,
    this.lutOpacity = 1.0,
  })  : curveMaster = curveMaster ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveRed = curveRed ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveGreen = curveGreen ?? [0.0, 0.25, 0.5, 0.75, 1.0],
        curveBlue = curveBlue ?? [0.0, 0.25, 0.5, 0.75, 1.0];

  AdjustmentLayer clone() {
    return AdjustmentLayer(
      id: id,
      name: name,
      isEnabled: isEnabled,
      opacity: opacity,
      blendMode: blendMode,
      contrast: contrast,
      saturation: saturation,
      brightness: brightness,
      sharpness: sharpness,
      gamma: gamma,
      hue: hue,
      temperature: temperature,
      shadows: shadows,
      highlights: highlights,
      blackCrush: blackCrush,
      vignette: vignette,
      vignetteBoxed: vignetteBoxed,
      edgeDarken: edgeDarken,
      darkOutlines: darkOutlines,
      denoise: denoise,
      filmGrain: filmGrain,
      flickerIntensity: flickerIntensity,
      flickerSpeed: flickerSpeed,
      halationRadius: halationRadius,
      halationWarmth: halationWarmth,
      deepGlowIntensity: deepGlowIntensity,
      deepGlowRadius: deepGlowRadius,
      deepGlowThreshold: deepGlowThreshold,
      edgeGlowTint: edgeGlowTint,
      thinStreakIntensity: thinStreakIntensity,
      thinStreakWidth: thinStreakWidth,
      thinStreakOpacity: thinStreakOpacity,
      lineChromaStrength: lineChromaStrength,
      volRaysLength: volRaysLength,
      volRaysDecay: volRaysDecay,
      sapphireGlowWidth: sapphireGlowWidth,
      sapphireGlowThreshold: sapphireGlowThreshold,
      depthOfField: depthOfField,
      dofFocus: dofFocus,
      dofAngle: dofAngle,
      unsharpRadius: unsharpRadius,
      unsharpAmount: unsharpAmount,
      unsharpThreshold: unsharpThreshold,
      curveMaster: List<double>.from(curveMaster),
      curveRed: List<double>.from(curveRed),
      curveGreen: List<double>.from(curveGreen),
      curveBlue: List<double>.from(curveBlue),
      mblMojoTealOrange: mblMojoTealOrange,
      mblColoristaLift: mblColoristaLift,
      mblColoristaGamma: mblColoristaGamma,
      mblColoristaGain: mblColoristaGain,
      bslaGodRays: bslaGodRays,
      bslaFogDensity: bslaFogDensity,
      bslaFogDepth: bslaFogDepth,
      bslaBloomHaze: bslaBloomHaze,
      bslFogScatter: bslFogScatter,
      activeLutId: activeLutId,
      lutOpacity: lutOpacity,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isEnabled': isEnabled,
    'opacity': opacity,
    'blendMode': blendMode.index,
    'contrast': contrast,
    'saturation': saturation,
    'brightness': brightness,
    'sharpness': sharpness,
    'gamma': gamma,
    'hue': hue,
    'temperature': temperature,
    'shadows': shadows,
    'highlights': highlights,
    'blackCrush': blackCrush,
    'vignette': vignette,
    'vignetteBoxed': vignetteBoxed,
    'edgeDarken': edgeDarken,
    'darkOutlines': darkOutlines,
    'denoise': denoise,
    'filmGrain': filmGrain,
    'flickerIntensity': flickerIntensity,
    'flickerSpeed': flickerSpeed,
    'halationRadius': halationRadius,
    'halationWarmth': halationWarmth,
    'deepGlowIntensity': deepGlowIntensity,
    'deepGlowRadius': deepGlowRadius,
    'deepGlowThreshold': deepGlowThreshold,
    'edgeGlowTint': edgeGlowTint,
    'thinStreakIntensity': thinStreakIntensity,
    'thinStreakWidth': thinStreakWidth,
    'thinStreakOpacity': thinStreakOpacity,
    'lineChromaStrength': lineChromaStrength,
    'volRaysLength': volRaysLength,
    'volRaysDecay': volRaysDecay,
    'sapphireGlowWidth': sapphireGlowWidth,
    'sapphireGlowThreshold': sapphireGlowThreshold,
    'depthOfField': depthOfField,
    'dofFocus': dofFocus,
    'dofAngle': dofAngle,
    'unsharpRadius': unsharpRadius,
    'unsharpAmount': unsharpAmount,
    'unsharpThreshold': unsharpThreshold,
    'curveMaster': curveMaster,
    'curveRed': curveRed,
    'curveGreen': curveGreen,
    'curveBlue': curveBlue,
    'mblMojoTealOrange': mblMojoTealOrange,
    'mblColoristaLift': mblColoristaLift,
    'mblColoristaGamma': mblColoristaGamma,
    'mblColoristaGain': mblColoristaGain,
    'bslaGodRays': bslaGodRays,
    'bslaFogDensity': bslaFogDensity,
    'bslaFogDepth': bslaFogDepth,
    'bslaBloomHaze': bslaBloomHaze,
    'bslFogScatter': bslFogScatter,
    'activeLutId': activeLutId,
    'lutOpacity': lutOpacity,
  };

  factory AdjustmentLayer.fromJson(Map<String, dynamic> json) => AdjustmentLayer(
    id: json['id'] ?? 'layer',
    name: json['name'] ?? 'Adjustment Layer',
    isEnabled: json['isEnabled'] ?? true,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    blendMode: LayerBlendMode.values[json['blendMode'] ?? 0],
    contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
    saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
    brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
    sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
    gamma: (json['gamma'] as num?)?.toDouble() ?? 1.0,
    hue: (json['hue'] as num?)?.toDouble() ?? 0.0,
    temperature: (json['temperature'] as num?)?.toDouble() ?? 6500.0,
    shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
    highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
    blackCrush: (json['blackCrush'] as num?)?.toDouble() ?? 0.0,
    vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
    vignetteBoxed: (json['vignetteBoxed'] as num?)?.toDouble() ?? 0.0,
    edgeDarken: (json['edgeDarken'] as num?)?.toDouble() ?? 0.0,
    darkOutlines: (json['darkOutlines'] as num?)?.toDouble() ?? 0.0,
    denoise: (json['denoise'] as num?)?.toDouble() ?? 0.0,
    filmGrain: (json['filmGrain'] as num?)?.toDouble() ?? 0.0,
    flickerIntensity: (json['flickerIntensity'] as num?)?.toDouble() ?? 0.0,
    flickerSpeed: (json['flickerSpeed'] as num?)?.toDouble() ?? 6.0,
    halationRadius: (json['halationRadius'] as num?)?.toDouble() ?? 0.0,
    halationWarmth: (json['halationWarmth'] as num?)?.toDouble() ?? 0.0,
    deepGlowIntensity: (json['deepGlowIntensity'] as num?)?.toDouble() ?? 0.0,
    deepGlowRadius: (json['deepGlowRadius'] as num?)?.toDouble() ?? 0.5,
    deepGlowThreshold: (json['deepGlowThreshold'] as num?)?.toDouble() ?? 0.45,
    edgeGlowTint: (json['edgeGlowTint'] as num?)?.toDouble() ?? 0.0,
    thinStreakIntensity: (json['thinStreakIntensity'] as num?)?.toDouble() ?? 0.0,
    thinStreakWidth: (json['thinStreakWidth'] as num?)?.toDouble() ?? 0.5,
    thinStreakOpacity: (json['thinStreakOpacity'] as num?)?.toDouble() ?? 1.0,
    lineChromaStrength: (json['lineChromaStrength'] as num?)?.toDouble() ?? 0.0,
    volRaysLength: (json['volRaysLength'] as num?)?.toDouble() ?? 0.0,
    volRaysDecay: (json['volRaysDecay'] as num?)?.toDouble() ?? 0.88,
    sapphireGlowWidth: (json['sapphireGlowWidth'] as num?)?.toDouble() ?? 0.0,
    sapphireGlowThreshold: (json['sapphireGlowThreshold'] as num?)?.toDouble() ?? 0.5,
    depthOfField: (json['depthOfField'] as num?)?.toDouble() ?? 0.0,
    dofFocus: (json['dofFocus'] as num?)?.toDouble() ?? 0.5,
    dofAngle: (json['dofAngle'] as num?)?.toDouble() ?? 0.0,
    unsharpRadius: (json['unsharpRadius'] as num?)?.toDouble() ?? 1.5,
    unsharpAmount: (json['unsharpAmount'] as num?)?.toDouble() ?? 0.0,
    unsharpThreshold: (json['unsharpThreshold'] as num?)?.toDouble() ?? 0.02,
    curveMaster: (json['curveMaster'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    curveRed: (json['curveRed'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    curveGreen: (json['curveGreen'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    curveBlue: (json['curveBlue'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    mblMojoTealOrange: (json['mblMojoTealOrange'] as num?)?.toDouble() ?? 0.0,
    mblColoristaLift: (json['mblColoristaLift'] as num?)?.toDouble() ?? 0.0,
    mblColoristaGamma: (json['mblColoristaGamma'] as num?)?.toDouble() ?? 0.0,
    mblColoristaGain: (json['mblColoristaGain'] as num?)?.toDouble() ?? 0.0,
    bslaGodRays: (json['bslaGodRays'] as num?)?.toDouble() ?? 0.0,
    bslaFogDensity: (json['bslaFogDensity'] as num?)?.toDouble() ?? 0.0,
    bslaFogDepth: (json['bslaFogDepth'] as num?)?.toDouble() ?? 0.5,
    bslaBloomHaze: (json['bslaBloomHaze'] as num?)?.toDouble() ?? 0.0,
    bslFogScatter: (json['bslFogScatter'] as num?)?.toDouble() ?? 0.35,
    activeLutId: json['activeLutId'],
    lutOpacity: (json['lutOpacity'] as num?)?.toDouble() ?? 1.0,
  );
}

class ProjectData {
  String mediaPath;
  bool isImage;
  String aspectRatio;
  double tonemapMode;
  List<AdjustmentLayer> layers;
  int activeLayerIndex;

  ProjectData({
    required this.mediaPath,
    this.isImage = false,
    this.aspectRatio = '16:9',
    this.tonemapMode = 0.0,
    List<AdjustmentLayer>? layers,
    this.activeLayerIndex = 0,
  }) : layers = layers ?? [];

  AdjustmentLayer get currentLayer {
    if (layers.isEmpty) {
      layers.add(AdjustmentLayer(id: 'layer_0', name: 'Base Grade'));
      activeLayerIndex = 0;
    }
    if (activeLayerIndex < 0 || activeLayerIndex >= layers.length) {
      activeLayerIndex = 0;
    }
    return layers[activeLayerIndex];
  }

  ProjectData clone() {
    return ProjectData(
      mediaPath: mediaPath,
      isImage: isImage,
      aspectRatio: aspectRatio,
      tonemapMode: tonemapMode,
      layers: layers.map((l) => l.clone()).toList(),
      activeLayerIndex: activeLayerIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'mediaPath': mediaPath,
    'isImage': isImage,
    'aspectRatio': aspectRatio,
    'tonemapMode': tonemapMode,
    'activeLayerIndex': activeLayerIndex,
    'layers': layers.map((l) => l.toJson()).toList(),
  };

  factory ProjectData.fromJson(Map<String, dynamic> json) => ProjectData(
    mediaPath: json['mediaPath'] ?? '',
    isImage: json['isImage'] ?? false,
    aspectRatio: json['aspectRatio'] ?? '16:9',
    tonemapMode: (json['tonemapMode'] as num?)?.toDouble() ?? 0.0,
    activeLayerIndex: json['activeLayerIndex'] ?? 0,
    layers: (json['layers'] as List<dynamic>?)?.map((e) => AdjustmentLayer.fromJson(e)).toList(),
  );
}

class StoredProject {
  final String id;
  final String name;
  final String mediaPath;
  final ProjectData data;
  final DateTime lastOpened;

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

class CustomPresetItem {
  final String name;
  final String description;
  final int accentColor;
  final bool isBuiltIn;
  final List<AdjustmentLayer> layers;
  final double tonemapMode;

  CustomPresetItem({
    required this.name,
    required this.description,
    required this.accentColor,
    required this.isBuiltIn,
    required this.layers,
    required this.tonemapMode,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'accentColor': accentColor,
    'isBuiltIn': isBuiltIn,
    'tonemapMode': tonemapMode,
    'layers': layers.map((l) => l.toJson()).toList(),
  };

  factory CustomPresetItem.fromJson(Map<String, dynamic> json) => CustomPresetItem(
    name: json['name'] ?? '',
    description: json['description'] ?? '',
    accentColor: json['accentColor'] ?? 0xFF7FFFD4,
    isBuiltIn: json['isBuiltIn'] ?? false,
    tonemapMode: (json['tonemapMode'] as num?)?.toDouble() ?? 0.0,
    layers: (json['layers'] as List<dynamic>?)?.map((e) => AdjustmentLayer.fromJson(e)).toList() ?? [],
  );
}

class ProjectManager {
  static const String _kProjectsKey = 'shadely_saved_projects_v3';
  static const String _kPresetsKey = 'shadely_custom_presets_v3';
  static const String _kLutsKey = 'shadely_stored_luts_v1';

  static List<StoredProject> _inMemoryProjects = [];
  static List<CustomPresetItem> _inMemoryPresets = [];
  static List<LutModel> _inMemoryLuts = [];

  static Future<List<StoredProject>> loadProjects() async {
    return _inMemoryProjects;
  }

  static Future<void> saveProject(StoredProject project) async {
    _inMemoryProjects.removeWhere((p) => p.id == project.id);
    _inMemoryProjects.insert(0, project);
  }

  static Future<void> saveProjects(List<StoredProject> list) async {
    _inMemoryProjects = List.from(list);
  }

  static Future<List<CustomPresetItem>> loadCustomPresets() async {
    return _inMemoryPresets;
  }

  static Future<void> saveCustomPresets(List<CustomPresetItem> presets) async {
    _inMemoryPresets = List.from(presets);
  }

  static Future<List<LutModel>> loadLuts() async {
    return _inMemoryLuts;
  }

  static Future<void> saveLuts(List<LutModel> luts) async {
    _inMemoryLuts = List.from(luts);
  }
}
