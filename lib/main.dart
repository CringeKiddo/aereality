// ==========================================
// PART 1 OF 3: main.dart
// ==========================================

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:image/image.dart' as img;

// ==========================================
// THEME & GLOBAL ACCENT CONFIGURATION
// ==========================================

const Color kBackgroundDark = Color(0xFF0F0F13);
const Color kCardDark = Color(0xFF17171F);
const Color kSurfaceDark = Color(0xFF1F1F2B);
const Color kNeonCyan = Color(0xFF00E5FF);

final ValueNotifier<Color> gCustomAccentColor = ValueNotifier<Color>(const Color(0xFF00E5FF));
final ValueNotifier<bool> gHdrPrecisionMode = ValueNotifier<bool>(true);
final ValueNotifier<double> gPreviewResolutionScale = ValueNotifier<double>(0.75);

final List<Color> kStudioColorPalette = [
  const Color(0xFF00E5FF),
  const Color(0xFF00B0FF),
  const Color(0xFF2979FF),
  const Color(0xFF3D5AFE),
  const Color(0xFF651FFF),
  const Color(0xFF7C4DFF),
  const Color(0xFFB388FF),
  const Color(0xFFE040FB),
  const Color(0xFFFF4081),
  const Color(0xFFFF1744),
  const Color(0xFFFF5252),
  const Color(0xFFFF6E40),
  const Color(0xFFFF9100),
  const Color(0xFFFFAB00),
  const Color(0xFFFFD600),
  const Color(0xFFAEEA00),
  const Color(0xFF76FF03),
  const Color(0xFF00E676),
  const Color(0xFF1DE9B6),
  const Color(0xFF00BFA5),
  const Color(0xFF64FFDA),
  const Color(0xFF18FFFF),
  const Color(0xFFE6E6FA),
  const Color(0xFFFFFFFF),
  const Color(0xFFB0BEC5),
  const Color(0xFF78909C),
  const Color(0xFFFF80AB),
  const Color(0xFFEA80FC),
  const Color(0xFF8C9EFF),
  const Color(0xFF82B1FF),
  const Color(0xFF80D8FF),
  const Color(0xFF84FFFF),
  const Color(0xFFA7FFEB),
  const Color(0xFFB9F6CA),
  const Color(0xFFCCFF90),
  const Color(0xFFF4FF81),
  const Color(0xFFFFE57F),
  const Color(0xFFFFD180),
  const Color(0xFFFF9E80),
  const Color(0xFFFF6D00),
];

// ==========================================
// DATA MODELS & ENUMS
// ==========================================

enum LayerBlendMode {
  normal,
  screen,
  multiply,
  overlay,
  softLight,
  colorDodge,
  add,
}

enum EffectType {
  colorCorrection,
  glow,
  vignette,
  chromaticAberration,
  rgbSplit,
  filmGrain,
  sharpen,
  blur,
  radialBlur,
  directionalBlur,
  hslSecondary,
  vignetteColor,
  reinhardTonemap,
  filmicCurve,
  edgeDetect,
  bloomHDR,
  duotone,
  lensDistortion,
}

class AdjustmentLayer {
  String id;
  String name;
  bool isVisible;
  double opacity;
  LayerBlendMode blendMode;

  // Primary Color Grading
  double exposure;
  double contrast;
  double saturation;
  double brightness;
  double vibrance;
  double temperature;
  double tint;
  double highlights;
  double shadows;
  double whites;
  double blacks;
  double gamma;

  // Secondary Wheels
  Color shadowTint;
  double shadowTintIntensity;
  Color midtoneTint;
  double midtoneTintIntensity;
  Color highlightTint;
  double highlightTintIntensity;

  // Stylized Optics
  double glowIntensity;
  double glowRadius;
  double vignetteIntensity;
  double vignetteRoundness;
  double chromaticIntensity;
  double filmGrainIntensity;
  double sharpness;
  double blurRadius;
  double bloomThreshold;
  double bloomIntensity;

  AdjustmentLayer({
    required this.id,
    required this.name,
    this.isVisible = true,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.brightness = 0.0,
    this.vibrance = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.gamma = 1.0,
    this.shadowTint = const Color(0xFF00E5FF),
    this.shadowTintIntensity = 0.0,
    this.midtoneTint = const Color(0xFFFFFFFF),
    this.midtoneTintIntensity = 0.0,
    this.highlightTint = const Color(0xFFFF9100),
    this.highlightTintIntensity = 0.0,
    this.glowIntensity = 0.0,
    this.glowRadius = 15.0,
    this.vignetteIntensity = 0.0,
    this.vignetteRoundness = 0.5,
    this.chromaticIntensity = 0.0,
    this.filmGrainIntensity = 0.0,
    this.sharpness = 0.0,
    this.blurRadius = 0.0,
    this.bloomThreshold = 0.8,
    this.bloomIntensity = 0.0,
  });

  AdjustmentLayer copyWith({
    String? id,
    String? name,
    bool? isVisible,
    double? opacity,
    LayerBlendMode? blendMode,
    double? exposure,
    double? contrast,
    double? saturation,
    double? brightness,
    double? vibrance,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? gamma,
    Color? shadowTint,
    double? shadowTintIntensity,
    Color? midtoneTint,
    double? midtoneTintIntensity,
    Color? highlightTint,
    double? highlightTintIntensity,
    double? glowIntensity,
    double? glowRadius,
    double? vignetteIntensity,
    double? vignetteRoundness,
    double? chromaticIntensity,
    double? filmGrainIntensity,
    double? sharpness,
    double? blurRadius,
    double? bloomThreshold,
    double? bloomIntensity,
  }) {
    return AdjustmentLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      isVisible: isVisible ?? this.isVisible,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      brightness: brightness ?? this.brightness,
      vibrance: vibrance ?? this.vibrance,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      gamma: gamma ?? this.gamma,
      shadowTint: shadowTint ?? this.shadowTint,
      shadowTintIntensity: shadowTintIntensity ?? this.shadowTintIntensity,
      midtoneTint: midtoneTint ?? this.midtoneTint,
      midtoneTintIntensity: midtoneTintIntensity ?? this.midtoneTintIntensity,
      highlightTint: highlightTint ?? this.highlightTint,
      highlightTintIntensity: highlightTintIntensity ?? this.highlightTintIntensity,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      glowRadius: glowRadius ?? this.glowRadius,
      vignetteIntensity: vignetteIntensity ?? this.vignetteIntensity,
      vignetteRoundness: vignetteRoundness ?? this.vignetteRoundness,
      chromaticIntensity: chromaticIntensity ?? this.chromaticIntensity,
      filmGrainIntensity: filmGrainIntensity ?? this.filmGrainIntensity,
      sharpness: sharpness ?? this.sharpness,
      blurRadius: blurRadius ?? this.blurRadius,
      bloomThreshold: bloomThreshold ?? this.bloomThreshold,
      bloomIntensity: bloomIntensity ?? this.bloomIntensity,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isVisible': isVisible,
    'opacity': opacity,
    'blendMode': blendMode.index,
    'exposure': exposure,
    'contrast': contrast,
    'saturation': saturation,
    'brightness': brightness,
    'vibrance': vibrance,
    'temperature': temperature,
    'tint': tint,
    'highlights': highlights,
    'shadows': shadows,
    'whites': whites,
    'blacks': blacks,
    'gamma': gamma,
    'shadowTint': shadowTint.value,
    'shadowTintIntensity': shadowTintIntensity,
    'midtoneTint': midtoneTint.value,
    'midtoneTintIntensity': midtoneTintIntensity,
    'highlightTint': highlightTint.value,
    'highlightTintIntensity': highlightTintIntensity,
    'glowIntensity': glowIntensity,
    'glowRadius': glowRadius,
    'vignetteIntensity': vignetteIntensity,
    'vignetteRoundness': vignetteRoundness,
    'chromaticIntensity': chromaticIntensity,
    'filmGrainIntensity': filmGrainIntensity,
    'sharpness': sharpness,
    'blurRadius': blurRadius,
    'bloomThreshold': bloomThreshold,
    'bloomIntensity': bloomIntensity,
  };

  factory AdjustmentLayer.fromJson(Map<String, dynamic> j) {
    return AdjustmentLayer(
      id: j['id'] ?? 'layer_${DateTime.now().millisecondsSinceEpoch}',
      name: j['name'] ?? 'Layer',
      isVisible: j['isVisible'] ?? true,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: LayerBlendMode.values[j['blendMode'] ?? 0],
      exposure: (j['exposure'] as num?)?.toDouble() ?? 0.0,
      contrast: (j['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (j['saturation'] as num?)?.toDouble() ?? 1.0,
      brightness: (j['brightness'] as num?)?.toDouble() ?? 0.0,
      vibrance: (j['vibrance'] as num?)?.toDouble() ?? 0.0,
      temperature: (j['temperature'] as num?)?.toDouble() ?? 0.0,
      tint: (j['tint'] as num?)?.toDouble() ?? 0.0,
      highlights: (j['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (j['shadows'] as num?)?.toDouble() ?? 0.0,
      whites: (j['whites'] as num?)?.toDouble() ?? 0.0,
      blacks: (j['blacks'] as num?)?.toDouble() ?? 0.0,
      gamma: (j['gamma'] as num?)?.toDouble() ?? 1.0,
      shadowTint: Color(j['shadowTint'] ?? 0xFF00E5FF),
      shadowTintIntensity: (j['shadowTintIntensity'] as num?)?.toDouble() ?? 0.0,
      midtoneTint: Color(j['midtoneTint'] ?? 0xFFFFFFFF),
      midtoneTintIntensity: (j['midtoneTintIntensity'] as num?)?.toDouble() ?? 0.0,
      highlightTint: Color(j['highlightTint'] ?? 0xFFFF9100),
      highlightTintIntensity: (j['highlightTintIntensity'] as num?)?.toDouble() ?? 0.0,
      glowIntensity: (j['glowIntensity'] as num?)?.toDouble() ?? 0.0,
      glowRadius: (j['glowRadius'] as num?)?.toDouble() ?? 15.0,
      vignetteIntensity: (j['vignetteIntensity'] as num?)?.toDouble() ?? 0.0,
      vignetteRoundness: (j['vignetteRoundness'] as num?)?.toDouble() ?? 0.5,
      chromaticIntensity: (j['chromaticIntensity'] as num?)?.toDouble() ?? 0.0,
      filmGrainIntensity: (j['filmGrainIntensity'] as num?)?.toDouble() ?? 0.0,
      sharpness: (j['sharpness'] as num?)?.toDouble() ?? 0.0,
      blurRadius: (j['blurRadius'] as num?)?.toDouble() ?? 0.0,
      bloomThreshold: (j['bloomThreshold'] as num?)?.toDouble() ?? 0.8,
      bloomIntensity: (j['bloomIntensity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ProjectData {
  String mediaPath;
  bool isImage;
  String aspectRatio; // '16:9', '9:16', '1:1', '4:3', '21:9'
  List<AdjustmentLayer> layers;

  ProjectData({
    required this.mediaPath,
    required this.isImage,
    required this.aspectRatio,
    required this.layers,
  });

  Map<String, dynamic> toJson() => {
    'mediaPath': mediaPath,
    'isImage': isImage,
    'aspectRatio': aspectRatio,
    'layers': layers.map((l) => l.toJson()).toList(),
  };

  factory ProjectData.fromJson(Map<String, dynamic> j) {
    return ProjectData(
      mediaPath: j['mediaPath'] ?? '',
      isImage: j['isImage'] ?? false,
      aspectRatio: j['aspectRatio'] ?? '16:9',
      layers: (j['layers'] as List? ?? [])
          .map((e) => AdjustmentLayer.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ==========================================
// BUILT-IN PRESETS ENGINE (12 PRESETS)
// ==========================================

class PresetProfile {
  final String id;
  final String title;
  final String category;
  final Color badgeColor;
  final List<AdjustmentLayer> layers;

  PresetProfile({
    required this.id,
    required this.title,
    required this.category,
    required this.badgeColor,
    required this.layers,
  });
}

final List<PresetProfile> kBuiltInPresets = [
  PresetProfile(
    id: 'yuta_jjk0',
    title: 'Yuta JJK0 Cursed',
    category: 'Anime',
    badgeColor: const Color(0xFFB388FF),
    layers: [
      AdjustmentLayer(
        id: 'yuta_grade',
        name: 'Cursed Energy Grade',
        exposure: 0.15,
        contrast: 1.35,
        saturation: 0.85,
        highlights: -0.20,
        shadows: 0.30,
        temperature: -0.25,
        tint: 0.20,
        shadowTint: const Color(0xFF4A148C),
        shadowTintIntensity: 0.45,
        highlightTint: const Color(0xFFE1BEE7),
        highlightTintIntensity: 0.30,
        glowIntensity: 0.40,
        glowRadius: 20.0,
        chromaticIntensity: 0.25,
        sharpness: 0.35,
      ),
    ],
  ),
  PresetProfile(
    id: 'okkotsu_ring',
    title: 'Okkotsu Ring Manifest',
    category: 'Anime',
    badgeColor: const Color(0xFF00E5FF),
    layers: [
      AdjustmentLayer(
        id: 'okkotsu_base',
        name: 'Rika Pure Love',
        exposure: 0.25,
        contrast: 1.45,
        saturation: 1.10,
        highlights: 0.30,
        shadows: -0.15,
        whites: 0.20,
        shadowTint: const Color(0xFF006064),
        shadowTintIntensity: 0.50,
        highlightTint: const Color(0xFF84FFFF),
        highlightTintIntensity: 0.40,
        bloomIntensity: 0.60,
        bloomThreshold: 0.70,
        sharpness: 0.45,
      ),
    ],
  ),
  PresetProfile(
    id: 'artoria_excalibur_morgan',
    title: 'Artoria Excalibur Morgan',
    category: 'Anime',
    badgeColor: const Color(0xFFFF1744),
    layers: [
      AdjustmentLayer(
        id: 'morgan_alter',
        name: 'Vortigern Dark Blade',
        exposure: -0.10,
        contrast: 1.60,
        saturation: 1.30,
        highlights: 0.40,
        shadows: -0.40,
        blacks: -0.30,
        shadowTint: const Color(0xFF212121),
        shadowTintIntensity: 0.70,
        highlightTint: const Color(0xFFFF1744),
        highlightTintIntensity: 0.65,
        glowIntensity: 0.75,
        glowRadius: 25.0,
        vignetteIntensity: 0.60,
        filmGrainIntensity: 0.20,
      ),
    ],
  ),
  PresetProfile(
    id: 'deku_one_for_all',
    title: 'Deku OFA Full Cowl',
    category: 'Anime',
    badgeColor: const Color(0xFF00E676),
    layers: [
      AdjustmentLayer(
        id: 'deku_lightning',
        name: 'Verdant Lightning',
        exposure: 0.20,
        contrast: 1.30,
        saturation: 1.25,
        temperature: -0.15,
        tint: -0.25,
        shadowTint: const Color(0xFF004D40),
        shadowTintIntensity: 0.40,
        highlightTint: const Color(0xFF69F0AE),
        highlightTintIntensity: 0.50,
        glowIntensity: 0.55,
        sharpness: 0.50,
        chromaticIntensity: 0.30,
      ),
    ],
  ),
  PresetProfile(
    id: 'raiden_shogun_musou',
    title: 'Raiden Musou no Hitotachi',
    category: 'Game',
    badgeColor: const Color(0xFFD500F9),
    layers: [
      AdjustmentLayer(
        id: 'raiden_grade',
        name: 'Electro Archon Radiance',
        exposure: 0.05,
        contrast: 1.40,
        saturation: 1.15,
        highlights: 0.25,
        shadows: -0.20,
        shadowTint: const Color(0xFF311B92),
        shadowTintIntensity: 0.55,
        highlightTint: const Color(0xFFEA80FC),
        highlightTintIntensity: 0.45,
        bloomIntensity: 0.50,
        vignetteIntensity: 0.45,
      ),
    ],
  ),
  PresetProfile(
    id: 'bsla_cinematic',
    title: 'BSLA 35mm Master',
    category: 'Cinematic',
    badgeColor: const Color(0xFFFF9100),
    layers: [
      AdjustmentLayer(
        id: 'bsla_lut',
        name: 'Teal & Orange Hollywood',
        exposure: 0.0,
        contrast: 1.25,
        saturation: 0.95,
        temperature: 0.10,
        highlights: -0.15,
        shadows: 0.15,
        shadowTint: const Color(0xFF00695C),
        shadowTintIntensity: 0.40,
        highlightTint: const Color(0xFFFF6D00),
        highlightTintIntensity: 0.35,
        filmGrainIntensity: 0.25,
        vignetteIntensity: 0.30,
      ),
    ],
  ),
  PresetProfile(
    id: 'vintage_kodak',
    title: 'Kodak Portra 400',
    category: 'Analog',
    badgeColor: const Color(0xFFFFD54F),
    layers: [
      AdjustmentLayer(
        id: 'kodak_base',
        name: 'Warm Halation Portra',
        exposure: 0.10,
        contrast: 1.10,
        saturation: 0.90,
        temperature: 0.20,
        tint: 0.05,
        shadows: 0.20,
        blacks: 0.15,
        highlightTint: const Color(0xFFFFE082),
        highlightTintIntensity: 0.25,
        filmGrainIntensity: 0.40,
      ),
    ],
  ),
  PresetProfile(
    id: 'monochrome_noir',
    title: 'Tokyo Street Noir',
    category: 'B&W',
    badgeColor: const Color(0xFFECEFF1),
    layers: [
      AdjustmentLayer(
        id: 'noir_base',
        name: 'High Contrast Silver',
        exposure: 0.0,
        contrast: 1.70,
        saturation: 0.0,
        whites: 0.30,
        blacks: -0.40,
        filmGrainIntensity: 0.50,
        sharpness: 0.60,
        vignetteIntensity: 0.70,
      ),
    ],
  ),
  PresetProfile(
    id: 'choso_blood_manipulation',
    title: 'Choso Blood Piercing',
    category: 'Anime',
    badgeColor: const Color(0xFFD50000),
    layers: [
      AdjustmentLayer(
        id: 'choso_blood',
        name: 'Crimson Scale',
        exposure: 0.05,
        contrast: 1.50,
        saturation: 1.35,
        highlights: 0.20,
        shadows: -0.30,
        shadowTint: const Color(0xFF3E2723),
        shadowTintIntensity: 0.50,
        highlightTint: const Color(0xFFFF1744),
        highlightTintIntensity: 0.55,
        vignetteIntensity: 0.50,
      ),
    ],
  ),
  PresetProfile(
    id: 'yoruichi_shunko',
    title: 'Yoruichi Raijin Shunko',
    category: 'Anime',
    badgeColor: const Color(0xFFFFD600),
    layers: [
      AdjustmentLayer(
        id: 'shunko_lightning',
        name: 'Lightning Beast',
        exposure: 0.30,
        contrast: 1.35,
        saturation: 1.20,
        highlights: 0.40,
        highlightTint: const Color(0xFFFFFF00),
        highlightTintIntensity: 0.60,
        bloomIntensity: 0.70,
        glowIntensity: 0.60,
        chromaticIntensity: 0.35,
      ),
    ],
  ),
  PresetProfile(
    id: 'gojo_infinite_void',
    title: 'Gojo Satoru Domain Void',
    category: 'Anime',
    badgeColor: const Color(0xFF40C4FF),
    layers: [
      AdjustmentLayer(
        id: 'void_blue',
        name: 'Six Eyes Celestial',
        exposure: 0.20,
        contrast: 1.45,
        saturation: 1.15,
        temperature: -0.40,
        tint: -0.10,
        shadowTint: const Color(0xFF01579B),
        shadowTintIntensity: 0.60,
        highlightTint: const Color(0xFF80D8FF),
        highlightTintIntensity: 0.50,
        glowIntensity: 0.65,
        sharpness: 0.50,
      ),
    ],
  ),
  PresetProfile(
    id: 'cyberpunk_neo_tokyo',
    title: 'Cyberpunk 2077 Night City',
    category: 'Sci-Fi',
    badgeColor: const Color(0xFFFF007F),
    layers: [
      AdjustmentLayer(
        id: 'cyber_lut',
        name: 'Neon Magenta Teal',
        exposure: 0.10,
        contrast: 1.55,
        saturation: 1.40,
        shadowTint: const Color(0xFF00E5FF),
        shadowTintIntensity: 0.50,
        highlightTint: const Color(0xFFFF007F),
        highlightTintIntensity: 0.50,
        chromaticIntensity: 0.45,
        vignetteIntensity: 0.40,
      ),
    ],
  ),
];

// ==========================================
// VULKAN COMPUTE NATIVE FFI BRIDGE
// ==========================================

typedef _VulkanApplyGradingC = Int32 Function(
    Pointer<Uint8> inPixels,
    Pointer<Uint8> outPixels,
    Int32 width,
    Int32 height,
    Float exposure,
    Float contrast,
    Float saturation,
    Float brightness,
    Float gamma,
    Float rTint,
    Float gTint,
    Float bTint,
    Float tintIntensity,
    Float glowIntensity,
    Float vignetteIntensity,
    Float chromaticIntensity,
    Float sharpness,
);

typedef _VulkanApplyGradingDart = int Function(
    Pointer<Uint8> inPixels,
    Pointer<Uint8> outPixels,
    int width,
    int height,
    double exposure,
    double contrast,
    double saturation,
    double brightness,
    double gamma,
    double rTint,
    double gTint,
    double bTint,
    double tintIntensity,
    double glowIntensity,
    double vignetteIntensity,
    double chromaticIntensity,
    double sharpness,
);

typedef _InitRealEsrganC = Int32 Function(
    Pointer<Utf8> paramPath,
    Pointer<Utf8> binPath,
    Int32 scale,
);
typedef _InitRealEsrganDart = int Function(
    Pointer<Utf8> paramPath,
    Pointer<Utf8> binPath,
    int scale,
);

typedef _UpscaleFrameC = Int32 Function(
    Pointer<Uint8> inRgba,
    Int32 inW,
    Int32 inH,
    Pointer<Uint8> outRgba,
);
typedef _UpscaleFrameDart = int Function(
    Pointer<Uint8> inRgba,
    int inW,
    int inH,
    Pointer<Uint8> outRgba,
);

typedef _DestroyRealEsrganC = Void Function();
typedef _DestroyRealEsrganDart = void Function();

class VulkanBridge {
  static DynamicLibrary? _lib;
  static _VulkanApplyGradingDart? _applyGrading;
  static _InitRealEsrganDart? _initEsrgan;
  static _UpscaleFrameDart? _upscaleFrameNative;
  static _DestroyRealEsrganDart? _destroyEsrgan;
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libshaderly_vulkan.so');
        _applyGrading = _lib!.lookupFunction<_VulkanApplyGradingC, _VulkanApplyGradingDart>('applyGradingVulkan');
        _initEsrgan = _lib!.lookupFunction<_InitRealEsrganC, _InitRealEsrganDart>('initRealEsrganVulkan');
        _upscaleFrameNative = _lib!.lookupFunction<_UpscaleFrameC, _UpscaleFrameDart>('upscaleFrameVulkan');
        _destroyEsrgan = _lib!.lookupFunction<_DestroyRealEsrganC, _DestroyRealEsrganDart>('destroyRealEsrganVulkan');
      }
    } catch (_) {
      // Fallback to pure SIMD Dart / CPU processing if shared object is absent
    }
    _initialized = true;
  }

  static Future<bool> initRealEsrgan({
    required String paramPath,
    required String binPath,
    required int scaleFactor,
  }) async {
    init();
    if (_initEsrgan != null) {
      final pParam = paramPath.toNativeUtf8();
      final pBin = binPath.toNativeUtf8();
      final res = _initEsrgan!(pParam, pBin, scaleFactor);
      calloc.free(pParam);
      calloc.free(pBin);
      return res == 1;
    }
    return false;
  }

  static Future<Uint8List?> upscaleFrame({
    required Uint8List frameBytes,
    required int width,
    required int height,
  }) async {
    init();
    if (_upscaleFrameNative != null) {
      final inPtr = calloc<Uint8>(frameBytes.length);
      inPtr.asTypedList(frameBytes.length).setAll(0, frameBytes);

      final outSize = width * height * 4 * 16;
      final outPtr = calloc<Uint8>(outSize);

      final res = _upscaleFrameNative!(inPtr, width, height, outPtr);
      calloc.free(inPtr);

      if (res == 1) {
        final upscaledBytes = Uint8List.fromList(outPtr.asTypedList(outSize));
        calloc.free(outPtr);
        return upscaledBytes;
      }
      calloc.free(outPtr);
    }
    return null;
  }

  static Future<void> destroyRealEsrgan() async {
    if (_destroyEsrgan != null) {
      _destroyEsrgan!();
    }
  }

  static Uint8List gradeFrameCpuFallback(Uint8List rgba, int width, int height, AdjustmentLayer layer) {
    final copy = Uint8List.fromList(rgba);
    final len = copy.length;
    final exp = math.pow(2.0, layer.exposure).toDouble();
    final con = layer.contrast;
    final sat = layer.saturation;
    final gam = layer.gamma;
    final brt = layer.brightness * 255.0;

    final shadowR = layer.shadowTint.red / 255.0;
    final shadowG = layer.shadowTint.green / 255.0;
    final shadowB = layer.shadowTint.blue / 255.0;
    final shadowInt = layer.shadowTintIntensity;

    for (int i = 0; i < len; i += 4) {
      double r = copy[i] / 255.0;
      double g = copy[i + 1] / 255.0;
      double b = copy[i + 2] / 255.0;

      r *= exp;
      g *= exp;
      b *= exp;

      r = (r - 0.5) * con + 0.5;
      g = (g - 0.5) * con + 0.5;
      b = (b - 0.5) * con + 0.5;

      final gray = 0.299 * r + 0.587 * g + 0.114 * b;
      r = gray + (r - gray) * sat;
      g = gray + (g - gray) * sat;
      b = gray + (b - gray) * sat;

      if (shadowInt > 0.0) {
        final shadowMask = (1.0 - gray).clamp(0.0, 1.0);
        r += (shadowR - r) * shadowInt * shadowMask;
        g += (shadowG - g) * shadowInt * shadowMask;
        b += (shadowB - b) * shadowInt * shadowMask;
      }

      if (gam != 1.0 && gam > 0.0) {
        r = math.pow(r.clamp(0.0, 1.0), 1.0 / gam).toDouble();
        g = math.pow(g.clamp(0.0, 1.0), 1.0 / gam).toDouble();
        b = math.pow(b.clamp(0.0, 1.0), 1.0 / gam).toDouble();
      }

      copy[i] = ((r * 255.0) + brt).clamp(0, 255).toInt();
      copy[i + 1] = ((g * 255.0) + brt).clamp(0, 255).toInt();
      copy[i + 2] = ((b * 255.0) + brt).clamp(0, 255).toInt();
    }
    return copy;
  }
}

// ==========================================
// ENTRY POINT & APP ROOT
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: kBackgroundDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  VulkanBridge.init();
  runApp(const ShaderlyApp());
}

class ShaderlyApp extends StatelessWidget {
  const ShaderlyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: gCustomAccentColor,
      builder: (context, accentColor, _) {
        return MaterialApp(
          title: 'Shaderly',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: kBackgroundDark,
            primaryColor: accentColor,
            colorScheme: ColorScheme.dark(
              primary: accentColor,
              secondary: accentColor,
              surface: kSurfaceDark,
              background: kBackgroundDark,
            ),
            cardTheme: CardTheme(
              color: kCardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.white10, width: 1),
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: kBackgroundDark,
              elevation: 0,
              centerTitle: true,
            ),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

// ==========================================
// HOME SCREEN (PROJECT CREATOR & RECENT SESSIONS)
// ==========================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<ProjectData> _recentProjects = [];
  String _selectedAspectRatio = '16:9';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedProjects();
  }

  Future<void> _loadSavedProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('saved_projects') ?? [];
    setState(() {
      _recentProjects.clear();
      for (var str in jsonList) {
        try {
          final decoded = json.decode(str);
          _recentProjects.add(ProjectData.fromJson(decoded));
        } catch (_) {}
      }
    });
  }

  Future<void> _saveProjectToDisk(ProjectData project) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('saved_projects') ?? [];
    if (jsonList.length >= 4) {
      jsonList.removeLast();
    }
    jsonList.insert(0, json.encode(project.toJson()));
    await prefs.setStringList('saved_projects', jsonList);
    _loadSavedProjects();
  }

  void _openPaletteSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Studio Accent Glow',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: kStudioColorPalette.map((color) {
                      final isSelected = gCustomAccentColor.value.value == color.value;
                      return GestureDetector(
                        onTap: () {
                          gCustomAccentColor.value = color;
                          setModalState(() {});
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: isSelected ? 3.0 : 0.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(isSelected ? 0.6 : 0.2),
                                blurRadius: isSelected ? 12 : 4,
                                spreadRadius: isSelected ? 2 : 0,
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.black87, size: 22)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
