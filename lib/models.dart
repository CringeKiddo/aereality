// ==========================================
// lib/models.dart
// 100% COMPLETE FILE - Master Data Models & Layer State for Shaderly
// ==========================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum LayerBlendMode {
  normal,
  screen,
  linearAdd,
  overlay,
  softLight,
  multiply,
}

/// Represents an isolated timeline clip region where a custom CC/Preset is applied.
class TimelineClipSegment {
  String id;
  String name;
  double startTime; // Seconds
  double endTime;   // Seconds
  List<AdjustmentLayer> layers;
  double tonemapMode;
  bool isEnabled;

  TimelineClipSegment({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    List<AdjustmentLayer>? layers,
    this.tonemapMode = 0.0,
    this.isEnabled = true,
  }) : layers = layers ?? [];

  TimelineClipSegment clone() {
    return TimelineClipSegment(
      id: id,
      name: name,
      startTime: startTime,
      endTime: endTime,
      layers: layers.map((l) => l.clone()).toList(),
      tonemapMode: tonemapMode,
      isEnabled: isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startTime': startTime,
    'endTime': endTime,
    'layers': layers.map((l) => l.toJson()).toList(),
    'tonemapMode': tonemapMode,
    'isEnabled': isEnabled,
  };

  factory TimelineClipSegment.fromJson(Map<String, dynamic> json) => TimelineClipSegment(
    id: json['id'] ?? 'seg_${DateTime.now().millisecondsSinceEpoch}',
    name: json['name'] ?? 'Segment',
    startTime: (json['startTime'] as num?)?.toDouble() ?? 1.0,
    endTime: (json['endTime'] as num?)?.toDouble() ?? 5.0,
    layers: (json['layers'] as List<dynamic>?)
        ?.map((l) => AdjustmentLayer.fromJson(l))
        .toList() ?? [],
    tonemapMode: (json['tonemapMode'] as num?)?.toDouble() ?? 0.0,
    isEnabled: json['isEnabled'] ?? true,
  );
}

class AdjustmentLayer {
  String id;
  String name;
  bool isEnabled;
  double opacity = 1.0;
  LayerBlendMode blendMode;

  // Basic Grading
  double brightness;
  double contrast;
  double saturation;
  double gamma;
  double sharpness;
  double temperature;
  double hue;

  // Tonal Splits
  double shadows;
  double highlights;
  double blackCrush;

  // Split Toning Engine
  double splitToneShadowHue;  // 0.0 to 1.0 (Color wheel hue)
  double splitToneShadowSat;  // 0.0 to 1.0
  double splitToneHighHue;    // 0.0 to 1.0
  double splitToneHighSat;    // 0.0 to 1.0
  double splitToneBalance;    // -1.0 to 1.0 (Pivot)

  // Stylistic Cel & Edges
  double darkOutlines;
  double edgeDarken;
  double vignette;
  double vignetteBoxed;

  // Dynamics & Texture
  double flickerIntensity;
  double flickerSpeed;
  double halationRadius;
  double halationWarmth;
  double filmGrain;
  double denoise;

  // Deep Glow & Flares
  double deepGlowIntensity;
  double deepGlowRadius;
  double deepGlowThreshold;
  double edgeGlowTint;
  double sapphireGlowWidth;
  double sapphireGlowThreshold;

  // New CapCut / AE Soft Gaussian Saturated Bloom ("Shaderly Glow")
  double shaderlyGlowIntensity;
  double shaderlyGlowRadius;
  double shaderlyGlowThreshold;
  double shaderlyGlowTint;

  // Video Flares
  int videoFlareType;
  double thinStreakIntensity;
  double thinStreakWidth;
  double thinStreakOpacity;
  double thinStreakSoftness; // 0.0 = Crisp, 1.0 = Wide Gaussian Spread
  double lineChromaStrength;
  double centerAura;
  double horizontalRamp;

  // Atmosphere / BSLA
  double bslaGodRays;
  double bslaFogDensity;
  double bslaFogDepth;
  double bslaBloomHaze;
  double bslFogScatter;
  double volRaysLength;
  double volRaysDecay;

  // Depth of Field
  double depthOfField;
  double dofFocus;
  double dofAngle;

  // Unsharp Mask
  double unsharpRadius;
  double unsharpAmount;
  double unsharpThreshold;

  // Spline Curves
  List<double> curveMaster;
  List<double> curveRed;
  List<double> curveGreen;
  List<double> curveBlue;

  // 3D LUT Integration
  String? activeLutId;
  double lutOpacity;

  // Magic Category (Magic Bullet Suite Replication)
  double mblMojoTealOrange;
  double cosmoCleanHighlight;
  double mblColoristaLift;
  double mblColoristaGamma;
  double mblColoristaGain;

  // Copied Stuff Category (After Effects Style FX)
  double copiedChromaShift;
  double copiedEdgeRays;
  double copiedProMist;
  double copiedStarGlint;

  AdjustmentLayer({
    required this.id,
    required this.name,
    this.isEnabled = true,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.gamma = 1.0,
    this.sharpness = 0.0,
    this.temperature = 6500.0,
    this.hue = 0.0,
    this.shadows = 0.0,
    this.highlights = 0.0,
    this.blackCrush = 0.0,
    this.splitToneShadowHue = 0.55, // Default Cool Cyan/Blue Shadow
    this.splitToneShadowSat = 0.0,
    this.splitToneHighHue = 0.10,   // Default Warm Amber Highlight
    this.splitToneHighSat = 0.0,
    this.splitToneBalance = 0.0,
    this.darkOutlines = 0.0,
    this.edgeDarken = 0.0,
    this.vignette = 0.0,
    this.vignetteBoxed = 0.0,
    this.flickerIntensity = 0.0,
    this.flickerSpeed = 10.0,
    this.halationRadius = 0.0,
    this.halationWarmth = 0.0,
    this.filmGrain = 0.0,
    this.denoise = 0.0,
    this.deepGlowIntensity = 0.0,
    this.deepGlowRadius = 0.40,
    this.deepGlowThreshold = 0.60,
    this.edgeGlowTint = 0.0,
    this.sapphireGlowWidth = 0.0,
    this.sapphireGlowThreshold = 0.70,
    this.shaderlyGlowIntensity = 0.0,
    this.shaderlyGlowRadius = 0.45,
    this.shaderlyGlowThreshold = 0.50,
    this.shaderlyGlowTint = 0.0,
    this.videoFlareType = 0,
    this.thinStreakIntensity = 0.0,
    this.thinStreakWidth = 0.50,
    this.thinStreakOpacity = 0.80,
    this.thinStreakSoftness = 0.50,
    this.lineChromaStrength = 0.0,
    this.centerAura = 0.0,
    this.horizontalRamp = 0.0,
    this.bslaGodRays = 0.0,
    this.bslaFogDensity = 0.0,
    this.bslaFogDepth = 0.50,
    this.bslaBloomHaze = 0.0,
    this.bslFogScatter = 0.0,
    this.volRaysLength = 0.0,
    this.volRaysDecay = 0.88,
    this.depthOfField = 0.0,
    this.dofFocus = 0.50,
    this.dofAngle = 0.0,
    this.unsharpRadius = 1.5,
    this.unsharpAmount = 0.0,
    this.unsharpThreshold = 0.02,
    List<double>? curveMaster,
    List<double>? curveRed,
    List<double>? curveGreen,
    List<double>? curveBlue,
    this.activeLutId,
    this.lutOpacity = 1.0,
    this.mblMojoTealOrange = 0.0,
    this.cosmoCleanHighlight = 0.0,
    this.mblColoristaLift = 0.0,
    this.mblColoristaGamma = 0.0,
    this.mblColoristaGain = 0.0,
    this.copiedChromaShift = 0.0,
    this.copiedEdgeRays = 0.0,
    this.copiedProMist = 0.0,
    this.copiedStarGlint = 0.0,
  })  : curveMaster = curveMaster ?? [0.0, 0.25, 0.50, 0.75, 1.0],
        curveRed = curveRed ?? [0.0, 0.25, 0.50, 0.75, 1.0],
        curveGreen = curveGreen ?? [0.0, 0.25, 0.50, 0.75, 1.0],
        curveBlue = curveBlue ?? [0.0, 0.25, 0.50, 0.75, 1.0];

  AdjustmentLayer clone() {
    return AdjustmentLayer(
      id: id,
      name: name,
      isEnabled: isEnabled,
      opacity: opacity,
      blendMode: blendMode,
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      gamma: gamma,
      sharpness: sharpness,
      temperature: temperature,
      hue: hue,
      shadows: shadows,
      highlights: highlights,
      blackCrush: blackCrush,
      splitToneShadowHue: splitToneShadowHue,
      splitToneShadowSat: splitToneShadowSat,
      splitToneHighHue: splitToneHighHue,
      splitToneHighSat: splitToneHighSat,
      splitToneBalance: splitToneBalance,
      darkOutlines: darkOutlines,
      edgeDarken: edgeDarken,
      vignette: vignette,
      vignetteBoxed: vignetteBoxed,
      flickerIntensity: flickerIntensity,
      flickerSpeed: flickerSpeed,
      halationRadius: halationRadius,
      halationWarmth: halationWarmth,
      filmGrain: filmGrain,
      denoise: denoise,
      deepGlowIntensity: deepGlowIntensity,
      deepGlowRadius: deepGlowRadius,
      deepGlowThreshold: deepGlowThreshold,
      edgeGlowTint: edgeGlowTint,
      sapphireGlowWidth: sapphireGlowWidth,
      sapphireGlowThreshold: sapphireGlowThreshold,
      shaderlyGlowIntensity: shaderlyGlowIntensity,
      shaderlyGlowRadius: shaderlyGlowRadius,
      shaderlyGlowThreshold: shaderlyGlowThreshold,
      shaderlyGlowTint: shaderlyGlowTint,
      videoFlareType: videoFlareType,
      thinStreakIntensity: thinStreakIntensity,
      thinStreakWidth: thinStreakWidth,
      thinStreakOpacity: thinStreakOpacity,
      thinStreakSoftness: thinStreakSoftness,
      lineChromaStrength: lineChromaStrength,
      centerAura: centerAura,
      horizontalRamp: horizontalRamp,
      bslaGodRays: bslaGodRays,
      bslaFogDensity: bslaFogDensity,
      bslaFogDepth: bslaFogDepth,
      bslaBloomHaze: bslaBloomHaze,
      bslFogScatter: bslFogScatter,
      volRaysLength: volRaysLength,
      volRaysDecay: volRaysDecay,
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
      activeLutId: activeLutId,
      lutOpacity: lutOpacity,
      mblMojoTealOrange: mblMojoTealOrange,
      cosmoCleanHighlight: cosmoCleanHighlight,
      mblColoristaLift: mblColoristaLift,
      mblColoristaGamma: mblColoristaGamma,
      mblColoristaGain: mblColoristaGain,
      copiedChromaShift: copiedChromaShift,
      copiedEdgeRays: copiedEdgeRays,
      copiedProMist: copiedProMist,
      copiedStarGlint: copiedStarGlint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isEnabled': isEnabled,
      'opacity': opacity,
      'blendMode': blendMode.index,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'gamma': gamma,
      'sharpness': sharpness,
      'temperature': temperature,
      'hue': hue,
      'shadows': shadows,
      'highlights': highlights,
      'blackCrush': blackCrush,
      'splitToneShadowHue': splitToneShadowHue,
      'splitToneShadowSat': splitToneShadowSat,
      'splitToneHighHue': splitToneHighHue,
      'splitToneHighSat': splitToneHighSat,
      'splitToneBalance': splitToneBalance,
      'darkOutlines': darkOutlines,
      'edgeDarken': edgeDarken,
      'vignette': vignette,
      'vignetteBoxed': vignetteBoxed,
      'flickerIntensity': flickerIntensity,
      'flickerSpeed': flickerSpeed,
      'halationRadius': halationRadius,
      'halationWarmth': halationWarmth,
      'filmGrain': filmGrain,
      'denoise': denoise,
      'deepGlowIntensity': deepGlowIntensity,
      'deepGlowRadius': deepGlowRadius,
      'deepGlowThreshold': deepGlowThreshold,
      'edgeGlowTint': edgeGlowTint,
      'sapphireGlowWidth': sapphireGlowWidth,
      'sapphireGlowThreshold': sapphireGlowThreshold,
      'shaderlyGlowIntensity': shaderlyGlowIntensity,
      'shaderlyGlowRadius': shaderlyGlowRadius,
      'shaderlyGlowThreshold': shaderlyGlowThreshold,
      'shaderlyGlowTint': shaderlyGlowTint,
      'videoFlareType': videoFlareType,
      'thinStreakIntensity': thinStreakIntensity,
      'thinStreakWidth': thinStreakWidth,
      'thinStreakOpacity': thinStreakOpacity,
      'thinStreakSoftness': thinStreakSoftness,
      'lineChromaStrength': lineChromaStrength,
      'centerAura': centerAura,
      'horizontalRamp': horizontalRamp,
      'bslaGodRays': bslaGodRays,
      'bslaFogDensity': bslaFogDensity,
      'bslaFogDepth': bslaFogDepth,
      'bslaBloomHaze': bslaBloomHaze,
      'bslFogScatter': bslFogScatter,
      'volRaysLength': volRaysLength,
      'volRaysDecay': volRaysDecay,
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
      'activeLutId': activeLutId,
      'lutOpacity': lutOpacity,
      'mblMojoTealOrange': mblMojoTealOrange,
      'cosmoCleanHighlight': cosmoCleanHighlight,
      'mblColoristaLift': mblColoristaLift,
      'mblColoristaGamma': mblColoristaGamma,
      'mblColoristaGain': mblColoristaGain,
      'copiedChromaShift': copiedChromaShift,
      'copiedEdgeRays': copiedEdgeRays,
      'copiedProMist': copiedProMist,
      'copiedStarGlint': copiedStarGlint,
    };
  }

  factory AdjustmentLayer.fromJson(Map<String, dynamic> json) {
    return AdjustmentLayer(
      id: json['id'] ?? 'layer_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] ?? 'Layer',
      isEnabled: json['isEnabled'] ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: LayerBlendMode.values[(json['blendMode'] as int?) ?? 0],
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
      gamma: (json['gamma'] as num?)?.toDouble() ?? 1.0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 6500.0,
      hue: (json['hue'] as num?)?.toDouble() ?? 0.0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
      blackCrush: (json['blackCrush'] as num?)?.toDouble() ?? 0.0,
      splitToneShadowHue: (json['splitToneShadowHue'] as num?)?.toDouble() ?? 0.55,
      splitToneShadowSat: (json['splitToneShadowSat'] as num?)?.toDouble() ?? 0.0,
      splitToneHighHue: (json['splitToneHighHue'] as num?)?.toDouble() ?? 0.10,
      splitToneHighSat: (json['splitToneHighSat'] as num?)?.toDouble() ?? 0.0,
      splitToneBalance: (json['splitToneBalance'] as num?)?.toDouble() ?? 0.0,
      darkOutlines: (json['darkOutlines'] as num?)?.toDouble() ?? 0.0,
      edgeDarken: (json['edgeDarken'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
      vignetteBoxed: (json['vignetteBoxed'] as num?)?.toDouble() ?? 0.0,
      flickerIntensity: (json['flickerIntensity'] as num?)?.toDouble() ?? 0.0,
      flickerSpeed: (json['flickerSpeed'] as num?)?.toDouble() ?? 10.0,
      halationRadius: (json['halationRadius'] as num?)?.toDouble() ?? 0.0,
      halationWarmth: (json['halationWarmth'] as num?)?.toDouble() ?? 0.0,
      filmGrain: (json['filmGrain'] as num?)?.toDouble() ?? 0.0,
      denoise: (json['denoise'] as num?)?.toDouble() ?? 0.0,
      deepGlowIntensity: (json['deepGlowIntensity'] as num?)?.toDouble() ?? 0.0,
      deepGlowRadius: (json['deepGlowRadius'] as num?)?.toDouble() ?? 0.40,
      deepGlowThreshold: (json['deepGlowThreshold'] as num?)?.toDouble() ?? 0.60,
      edgeGlowTint: (json['edgeGlowTint'] as num?)?.toDouble() ?? 0.0,
      sapphireGlowWidth: (json['sapphireGlowWidth'] as num?)?.toDouble() ?? 0.0,
      sapphireGlowThreshold: (json['sapphireGlowThreshold'] as num?)?.toDouble() ?? 0.70,
      shaderlyGlowIntensity: (json['shaderlyGlowIntensity'] as num?)?.toDouble() ?? 0.0,
      shaderlyGlowRadius: (json['shaderlyGlowRadius'] as num?)?.toDouble() ?? 0.45,
      shaderlyGlowThreshold: (json['shaderlyGlowThreshold'] as num?)?.toDouble() ?? 0.50,
      shaderlyGlowTint: (json['shaderlyGlowTint'] as num?)?.toDouble() ?? 0.0,
      videoFlareType: json['videoFlareType'] ?? 0,
      thinStreakIntensity: (json['thinStreakIntensity'] as num?)?.toDouble() ?? 0.0,
      thinStreakWidth: (json['thinStreakWidth'] as num?)?.toDouble() ?? 0.50,
      thinStreakOpacity: (json['thinStreakOpacity'] as num?)?.toDouble() ?? 0.80,
      thinStreakSoftness: (json['thinStreakSoftness'] as num?)?.toDouble() ?? 0.50,
      lineChromaStrength: (json['lineChromaStrength'] as num?)?.toDouble() ?? 0.0,
      centerAura: (json['centerAura'] as num?)?.toDouble() ?? 0.0,
      horizontalRamp: (json['horizontalRamp'] as num?)?.toDouble() ?? 0.0,
      bslaGodRays: (json['bslaGodRays'] as num?)?.toDouble() ?? 0.0,
      bslaFogDensity: (json['bslaFogDensity'] as num?)?.toDouble() ?? 0.0,
      bslaFogDepth: (json['bslaFogDepth'] as num?)?.toDouble() ?? 0.50,
      bslaBloomHaze: (json['bslaBloomHaze'] as num?)?.toDouble() ?? 0.0,
      bslFogScatter: (json['bslFogScatter'] as num?)?.toDouble() ?? 0.0,
      volRaysLength: (json['volRaysLength'] as num?)?.toDouble() ?? 0.0,
      volRaysDecay: (json['volRaysDecay'] as num?)?.toDouble() ?? 0.88,
      depthOfField: (json['depthOfField'] as num?)?.toDouble() ?? 0.0,
      dofFocus: (json['dofFocus'] as num?)?.toDouble() ?? 0.50,
      dofAngle: (json['dofAngle'] as num?)?.toDouble() ?? 0.0,
      unsharpRadius: (json['unsharpRadius'] as num?)?.toDouble() ?? 1.5,
      unsharpAmount: (json['unsharpAmount'] as num?)?.toDouble() ?? 0.0,
      unsharpThreshold: (json['unsharpThreshold'] as num?)?.toDouble() ?? 0.02,
      curveMaster: (json['curveMaster'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      curveRed: (json['curveRed'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      curveGreen: (json['curveGreen'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      curveBlue: (json['curveBlue'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      activeLutId: json['activeLutId'],
      lutOpacity: (json['lutOpacity'] as num?)?.toDouble() ?? 1.0,
      mblMojoTealOrange: (json['mblMojoTealOrange'] as num?)?.toDouble() ?? 0.0,
      cosmoCleanHighlight: (json['cosmoCleanHighlight'] as num?)?.toDouble() ?? 0.0,
      mblColoristaLift: (json['mblColoristaLift'] as num?)?.toDouble() ?? 0.0,
      mblColoristaGamma: (json['mblColoristaGamma'] as num?)?.toDouble() ?? 0.0,
      mblColoristaGain: (json['mblColoristaGain'] as num?)?.toDouble() ?? 0.0,
      copiedChromaShift: (json['copiedChromaShift'] as num?)?.toDouble() ?? 0.0,
      copiedEdgeRays: (json['copiedEdgeRays'] as num?)?.toDouble() ?? 0.0,
      copiedProMist: (json['copiedProMist'] as num?)?.toDouble() ?? 0.0,
      copiedStarGlint: (json['copiedStarGlint'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ProjectData {
  String mediaPath;
  bool isImage;
  String aspectRatio;
  List<AdjustmentLayer> layers;
  int activeLayerIndex;
  double tonemapMode; // 0=Off, 1=Shaderly Filmic 1, 2=Shaderly AgX 2

  // --- Isolated Text Suite Bounding Region & Stylization ---
  bool textSuiteEnabled;
  double textBoxX;
  double textBoxY;
  double textBoxW;
  double textBoxH;
  double textBevelDepth;
  double textChromeIntensity;
  double textSpecularGlint;
  double textContactShadow;
  double textLumaThreshold;
  double textMetallicTint;

  // --- Timeline Optimizer / Multiple Range Placer ---
  bool enableTimelineSegments;
  List<TimelineClipSegment> timelineSegments;

  // --- Master Dither Strength ---
  double ditherStrength;

  ProjectData({
    required this.mediaPath,
    this.isImage = false,
    this.aspectRatio = '16:9',
    List<AdjustmentLayer>? layers,
    this.activeLayerIndex = 0,
    this.tonemapMode = 0.0,
    this.textSuiteEnabled = false,
    this.textBoxX = 0.15,
    this.textBoxY = 0.40,
    this.textBoxW = 0.70,
    this.textBoxH = 0.20,
    this.textBevelDepth = 1.0,
    this.textChromeIntensity = 1.2,
    this.textSpecularGlint = 1.0,
    this.textContactShadow = 0.8,
    this.textLumaThreshold = 0.65,
    this.textMetallicTint = 0.0,
    this.enableTimelineSegments = false,
    List<TimelineClipSegment>? timelineSegments,
    this.ditherStrength = 1.0,
  })  : layers = layers ?? [],
        timelineSegments = timelineSegments ?? [];

  AdjustmentLayer get currentLayer {
    if (layers.isEmpty) {
      layers.add(AdjustmentLayer(id: 'default', name: 'Base Grade'));
      activeLayerIndex = 0;
    }
    if (activeLayerIndex >= layers.length) {
      activeLayerIndex = layers.length - 1;
    }
    return layers[activeLayerIndex];
  }

  ProjectData clone() {
    return ProjectData(
      mediaPath: mediaPath,
      isImage: isImage,
      aspectRatio: aspectRatio,
      layers: layers.map((l) => l.clone()).toList(),
      activeLayerIndex: activeLayerIndex,
      tonemapMode: tonemapMode,
      textSuiteEnabled: textSuiteEnabled,
      textBoxX: textBoxX,
      textBoxY: textBoxY,
      textBoxW: textBoxW,
      textBoxH: textBoxH,
      textBevelDepth: textBevelDepth,
      textChromeIntensity: textChromeIntensity,
      textSpecularGlint: textSpecularGlint,
      textContactShadow: textContactShadow,
      textLumaThreshold: textLumaThreshold,
      textMetallicTint: textMetallicTint,
      enableTimelineSegments: enableTimelineSegments,
      timelineSegments: timelineSegments.map((s) => s.clone()).toList(),
      ditherStrength: ditherStrength,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mediaPath': mediaPath,
      'isImage': isImage,
      'aspectRatio': aspectRatio,
      'layers': layers.map((l) => l.toJson()).toList(),
      'activeLayerIndex': activeLayerIndex,
      'tonemapMode': tonemapMode,
      'textSuiteEnabled': textSuiteEnabled,
      'textBoxX': textBoxX,
      'textBoxY': textBoxY,
      'textBoxW': textBoxW,
      'textBoxH': textBoxH,
      'textBevelDepth': textBevelDepth,
      'textChromeIntensity': textChromeIntensity,
      'textSpecularGlint': textSpecularGlint,
      'textContactShadow': textContactShadow,
      'textLumaThreshold': textLumaThreshold,
      'textMetallicTint': textMetallicTint,
      'enableTimelineSegments': enableTimelineSegments,
      'timelineSegments': timelineSegments.map((s) => s.toJson()).toList(),
      'ditherStrength': ditherStrength,
    };
  }

  factory ProjectData.fromJson(Map<String, dynamic> json) {
    return ProjectData(
      mediaPath: json['mediaPath'] ?? '',
      isImage: json['isImage'] ?? false,
      aspectRatio: json['aspectRatio'] ?? '16:9',
      layers: (json['layers'] as List<dynamic>?)
              ?.map((l) => AdjustmentLayer.fromJson(l))
              .toList() ??
          [],
      activeLayerIndex: json['activeLayerIndex'] ?? 0,
      tonemapMode: (json['tonemapMode'] as num?)?.toDouble() ?? 0.0,
      textSuiteEnabled: json['textSuiteEnabled'] ?? false,
      textBoxX: (json['textBoxX'] as num?)?.toDouble() ?? 0.15,
      textBoxY: (json['textBoxY'] as num?)?.toDouble() ?? 0.40,
      textBoxW: (json['textBoxW'] as num?)?.toDouble() ?? 0.70,
      textBoxH: (json['textBoxH'] as num?)?.toDouble() ?? 0.20,
      textBevelDepth: (json['textBevelDepth'] as num?)?.toDouble() ?? 1.0,
      textChromeIntensity: (json['textChromeIntensity'] as num?)?.toDouble() ?? 1.2,
      textSpecularGlint: (json['textSpecularGlint'] as num?)?.toDouble() ?? 1.0,
      textContactShadow: (json['textContactShadow'] as num?)?.toDouble() ?? 0.8,
      textLumaThreshold: (json['textLumaThreshold'] as num?)?.toDouble() ?? 0.65,
      textMetallicTint: (json['textMetallicTint'] as num?)?.toDouble() ?? 0.0,
      enableTimelineSegments: json['enableTimelineSegments'] ?? false,
      timelineSegments: (json['timelineSegments'] as List<dynamic>?)
              ?.map((s) => TimelineClipSegment.fromJson(s))
              .toList() ??
          [],
      ditherStrength: (json['ditherStrength'] as num?)?.toDouble() ?? 1.0,
    );
  }
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
    this.isBuiltIn = false,
    required this.layers,
    this.tonemapMode = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'accentColor': accentColor,
        'isBuiltIn': isBuiltIn,
        'layers': layers.map((l) => l.toJson()).toList(),
        'tonemapMode': tonemapMode,
      };

  factory CustomPresetItem.fromJson(Map<String, dynamic> json) =>
      CustomPresetItem(
        name: json['name'],
        description: json['description'] ?? '',
        accentColor: json['accentColor'] ?? 0xFF00E5FF,
        isBuiltIn: json['isBuiltIn'] ?? false,
        layers: (json['layers'] as List<dynamic>)
            .map((l) => AdjustmentLayer.fromJson(l))
            .toList(),
        tonemapMode: (json['tonemapMode'] as num?)?.toDouble() ?? 0.0,
      );
}

class LutModel {
  final String id;
  final String name;
  final String filePath;
  final int size;
  final Float32List table;

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
        'table': base64Encode(table.buffer.asUint8List()),
      };

  factory LutModel.fromJson(Map<String, dynamic> json) {
    final bytes = base64Decode(json['table']);
    return LutModel(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      size: json['size'],
      table: Float32List.view(bytes.buffer),
    );
  }
}

class ProjectManager {
  static Future<File> _getFile(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$filename');
  }

  static Future<List<StoredProject>> loadProjects() async {
    try {
      final file = await _getFile('saved_projects.json');
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content);
      return list.map((item) => StoredProject.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveProject(StoredProject project) async {
    final list = await loadProjects();
    list.removeWhere((p) => p.id == project.id || p.name == project.name);
    list.insert(0, project);
    await saveProjects(list);
  }

  static Future<void> saveProjects(List<StoredProject> list) async {
    try {
      final file = await _getFile('saved_projects.json');
      final content = jsonEncode(list.map((p) => p.toJson()).toList());
      await file.writeAsString(content, flush: true);
    } catch (_) {}
  }

  static Future<List<CustomPresetItem>> loadCustomPresets() async {
    try {
      final file = await _getFile('custom_presets.json');
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content);
      return list.map((item) => CustomPresetItem.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCustomPresets(List<CustomPresetItem> list) async {
    try {
      final file = await _getFile('custom_presets.json');
      final content = jsonEncode(list.map((p) => p.toJson()).toList());
      await file.writeAsString(content, flush: true);
    } catch (_) {}
  }

  static Future<List<LutModel>> loadLuts() async {
    try {
      final file = await _getFile('active_luts.json');
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content);
      return list.map((item) => LutModel.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLuts(List<LutModel> list) async {
    try {
      final file = await _getFile('active_luts.json');
      final content = jsonEncode(list.map((p) => p.toJson()).toList());
      await file.writeAsString(content, flush: true);
    } catch (_) {}
  }
}
