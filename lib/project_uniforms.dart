// =============================================================================
// AEReality / Shaderly - Project uniform packing for Motion S (batch 9)
//
// MIRROR of _ProjectScreenState._packMultiLayerUniforms (main.dart): same slots, same values. Motion S opens from the main menu, where
// no ProjectScreen exists, so the grade of a saved project has to be packed from the ProjectData alone. main.dart was NOT edited for this
// (the grade is untouched); the only differences are the three inputs the original read from the screen state:
//   timeSeconds  (original: video player position)         hasLut / lutOpacity  (original: _getActiveLutTable() / _lutLayer.lutOpacity)
// If a grade slot is ever added to _packMultiLayerUniforms, add it here too (see SUMMARY.txt, "kept in sync").
// =============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'gradient_map.dart';
import 'models.dart';
import 'time_slice_slots.dart';
import 'vfx_slots.dart';
import 'vfx_suite.dart';

Float32List packProjectUniforms(
  ProjectData project,
  double imgW,
  double imgH, {
  required double timeSeconds,
  required bool hasLut,
  required double lutOpacity,
}) {
  final uniforms = Float32List(Vfx.uboFloats);

    uniforms[0] = timeSeconds;
    uniforms[1] = project.layers.length.toDouble();
    uniforms[2] = project.tonemapMode;
    uniforms[3] = imgW;
    uniforms[4] = imgH;
    uniforms[5] = hasLut ? 1.0 : 0.0;
    uniforms[6] = lutOpacity;
    uniforms[12] = project.ditherStrength;

    // Offsets 13..25: Isolated Metallic Text Suite
    uniforms[13] = project.textSuiteEnabled ? 1.0 : 0.0;
    uniforms[14] = project.textBoxX;
    uniforms[15] = project.textBoxY;
    uniforms[16] = project.textBoxW;
    uniforms[17] = project.textBoxH;
    uniforms[18] = project.textBevelDepth;
    uniforms[19] = project.textChromeIntensity;
    uniforms[20] = project.textSpecularGlint;
    uniforms[21] = project.textContactShadow;
    uniforms[22] = project.textLumaThreshold;
    uniforms[23] = project.textMetallicTint;
    uniforms[24] = 0.40; // Default Text Glow
    uniforms[25] = 0.50; // legacy text glow radius (glow now comes from the personal block)
    project.text.packInto(uniforms); // text suite personal block + vector points (floats 3872..4095)

    uniforms[28] = 0.0; // Bit depth preview mode

    // 10 Layers with 192-float stride (offsets 32 + l * 192) - must match LayerData in the shader / C++
    for (int l = 0; l < math.min(project.layers.length, 10); l++) {
      final layer = project.layers[l];
      final offset = 32 + (l * 192);
      layer.gradientMap.packInto(uniforms, GradientMapSettings.kBaseOffset + l * GradientMapSettings.kFloatsPerLayer);
      layer.packFxInto(uniforms, l);
      layer.packVfxInto(uniforms, l); // batch 6: floats 4096.. (VFX) and 4736.. (Sapphire)
      uniforms[32 + (l * 192) + 184] = layer.fx[Fx.dofPreview];

      uniforms[offset + 0] = layer.isEnabled ? 1.0 : 0.0;
      uniforms[offset + 1] = layer.opacity;
      uniforms[offset + 2] = layer.blendMode.index.toDouble();
      uniforms[offset + 3] = layer.brightness;

      uniforms[offset + 4] = layer.saturation;
      uniforms[offset + 5] = layer.contrast;
      uniforms[offset + 6] = layer.sharpness;
      uniforms[offset + 7] = layer.gamma;

      uniforms[offset + 8] = layer.hue;
      uniforms[offset + 9] = layer.temperature;
      uniforms[offset + 10] = layer.deepGlowIntensity;
      uniforms[offset + 11] = layer.deepGlowRadius;

      uniforms[offset + 12] = layer.deepGlowThreshold;
      uniforms[offset + 13] = layer.edgeGlowTint;
      uniforms[offset + 14] = layer.thinStreakIntensity;
      uniforms[offset + 15] = layer.thinStreakWidth;

      uniforms[offset + 16] = layer.lineChromaStrength;
      uniforms[offset + 17] = layer.volRaysLength;
      uniforms[offset + 18] = layer.volRaysDecay;
      uniforms[offset + 19] = layer.shadows;

      uniforms[offset + 20] = layer.highlights;
      uniforms[offset + 21] = layer.blackCrush;
      uniforms[offset + 22] = layer.vignette;
      uniforms[offset + 23] = layer.vignetteBoxed;

      uniforms[offset + 24] = layer.edgeDarken;
      uniforms[offset + 25] = layer.darkOutlines; // S_lining Slider 1
      uniforms[offset + 26] = layer.denoise;
      uniforms[offset + 27] = layer.filmGrain;

      uniforms[offset + 28] = layer.flickerIntensity;
      uniforms[offset + 29] = layer.flickerSpeed;
      uniforms[offset + 30] = layer.halationRadius;
      uniforms[offset + 31] = layer.halationWarmth;

      uniforms[offset + 32] = layer.depthOfField;
      uniforms[offset + 33] = layer.dofFocus;
      uniforms[offset + 34] = layer.dofAngle;
      uniforms[offset + 35] = layer.unsharpRadius;

      uniforms[offset + 36] = layer.unsharpAmount;
      uniforms[offset + 37] = layer.unsharpThreshold;
      uniforms[offset + 38] = layer.curveMaster[0];
      uniforms[offset + 39] = layer.curveMaster[1];

      uniforms[offset + 40] = layer.curveMaster[2];
      uniforms[offset + 41] = layer.curveMaster[3];
      uniforms[offset + 42] = layer.curveMaster[4];
      uniforms[offset + 43] = layer.curveRed[0];

      uniforms[offset + 44] = layer.curveRed[1];
      uniforms[offset + 45] = layer.curveRed[2];
      uniforms[offset + 46] = layer.curveRed[3];
      uniforms[offset + 47] = layer.curveRed[4];

      uniforms[offset + 48] = layer.curveGreen[2];
      uniforms[offset + 49] = layer.curveBlue[2];
      uniforms[offset + 50] = layer.sapphireGlowWidth;
      uniforms[offset + 51] = layer.sapphireGlowThreshold;

      uniforms[offset + 52] = layer.thinStreakOpacity;
      uniforms[offset + 53] = layer.mblMojoTealOrange;

      uniforms[offset + 54] = layer.bslaGodRays;
      uniforms[offset + 55] = layer.bslaFogDensity;
      uniforms[offset + 56] = layer.bslaFogDepth;
      uniforms[offset + 57] = layer.bslaBloomHaze;
      uniforms[offset + 58] = layer.bslFogScatter;
      uniforms[offset + 59] = layer.cosmoCleanHighlight;

      uniforms[offset + 60] = layer.mblColoristaLift;
      uniforms[offset + 61] = layer.mblColoristaGamma;
      uniforms[offset + 62] = layer.mblColoristaGain;
      uniforms[offset + 63] = layer.centerAura;

      uniforms[offset + 64] = layer.bilateralIntensity;
      uniforms[offset + 65] = layer.bilateralRadius;
      uniforms[offset + 66] = layer.bilateralRange;
      uniforms[offset + 67] = layer.debandRadius;

      uniforms[offset + 68] = layer.debandThreshold;
      uniforms[offset + 69] = layer.lineThinning;
      uniforms[offset + 70] = layer.lineThinningThreshold;
      uniforms[offset + 71] = layer.kawaseGlowIntensity;

      uniforms[offset + 72] = layer.kawaseGlowRadius;
      uniforms[offset + 73] = layer.diffuseSpGlowIntensity;
      uniforms[offset + 74] = layer.diffuseSpGlowRadius;
      uniforms[offset + 75] = layer.diffuseSpGlowThreshold;

      uniforms[offset + 76] = layer.lightWrapWidth;
      uniforms[offset + 77] = layer.lightWrapIntensity;
      uniforms[offset + 78] = layer.lightWrapThreshold;
      uniforms[offset + 79] = layer.lightWrapBlendMode.toDouble();

      // Extended offsets 80..102
      uniforms[offset + 80] = layer.blendLinear ? 1.0 : 0.0;
      uniforms[offset + 81] = layer.sLiningOpacity; // S_lining Slider 2
      uniforms[offset + 82] = layer.dofRange;
      uniforms[offset + 83] = layer.dofFalloff;
      uniforms[offset + 84] = layer.dofBokeh;
      uniforms[offset + 85] = layer.dofMode;
      uniforms[offset + 86] = layer.shaderlyGlowIntensity;
      uniforms[offset + 87] = layer.shaderlyGlowRadius;
      uniforms[offset + 88] = layer.shaderlyGlowThreshold;
      uniforms[offset + 89] = layer.shaderlyGlowTint;
      uniforms[offset + 90] = layer.splitToneShadowHue;
      uniforms[offset + 91] = layer.splitToneShadowSat;
      uniforms[offset + 92] = layer.splitToneHighHue;
      uniforms[offset + 93] = layer.splitToneHighSat;
      uniforms[offset + 94] = layer.splitToneBalance;
      uniforms[offset + 95] = layer.deepTeal;
      uniforms[offset + 96] = layer.magicCurves;
      uniforms[offset + 97] = layer.copiedChromaShift;
      uniforms[offset + 98] = layer.copiedEdgeRays;
      uniforms[offset + 99] = layer.copiedProMist;
      uniforms[offset + 100] = layer.copiedStarGlint;
      uniforms[offset + 101] = layer.horizontalRamp;
      uniforms[offset + 102] = layer.edgeHaloRadius;
      uniforms[offset + 103] = layer.chromaContrast;

      // ---- v2.3: curves (all 5 points of R / G / B, sanitised so a curve can never invert) ----
      final cM = AdjustmentLayer.sanitizeCurve(layer.curveMaster);
      final cR = AdjustmentLayer.sanitizeCurve(layer.curveRed);
      final cG = AdjustmentLayer.sanitizeCurve(layer.curveGreen);
      final cB = AdjustmentLayer.sanitizeCurve(layer.curveBlue);
      for (int k = 0; k < 5; k++) {
        uniforms[offset + 38 + k] = cM[k];
        uniforms[offset + 43 + k] = cR[k];
      }
      uniforms[offset + 48] = cG[2];
      uniforms[offset + 49] = cB[2];
      uniforms[offset + 104] = cG[0];
      uniforms[offset + 105] = cG[1];
      uniforms[offset + 106] = cG[3];
      uniforms[offset + 107] = cG[4];
      uniforms[offset + 108] = cB[0];
      uniforms[offset + 109] = cB[1];
      uniforms[offset + 110] = cB[3];
      uniforms[offset + 111] = cB[4];

      // ---- v2.3: Hue vs Sat / Hue / Lum ----
      for (int b = 0; b < 8; b++) {
        uniforms[offset + 112 + b] = layer.hsSat[b];
        uniforms[offset + 120 + b] = layer.hsHue[b];
        uniforms[offset + 128 + b] = layer.hsLum[b];
      }
      uniforms[offset + 136] = layer.hsSoftness;
      uniforms[offset + 137] = layer.hsCustomCenter;
      uniforms[offset + 138] = layer.hsCustomWidth;
      uniforms[offset + 139] = layer.hsCustomSoft;
      uniforms[offset + 140] = layer.hsCustomSat;
      uniforms[offset + 141] = layer.hsCustomHue;
      uniforms[offset + 142] = layer.hsCustomLum;

      // ---- v2.3: Colorista ----
      uniforms[offset + 143] = layer.coloristaLiftX;
      uniforms[offset + 144] = layer.coloristaLiftY;
      uniforms[offset + 145] = layer.coloristaGammaX;
      uniforms[offset + 146] = layer.coloristaGammaY;
      uniforms[offset + 147] = layer.coloristaGainX;
      uniforms[offset + 148] = layer.coloristaGainY;
      uniforms[offset + 149] = layer.coloristaOffsetX;
      uniforms[offset + 150] = layer.coloristaOffsetY;
      uniforms[offset + 151] = layer.coloristaOffsetLuma;
      uniforms[offset + 152] = layer.coloristaSaturation;
      uniforms[offset + 153] = layer.coloristaSatShadows;
      uniforms[offset + 154] = layer.coloristaSatMids;
      uniforms[offset + 155] = layer.coloristaSatHighs;
      uniforms[offset + 156] = layer.coloristaContrast;
      uniforms[offset + 157] = layer.coloristaPivot;
      uniforms[offset + 158] = layer.coloristaTemp;
      uniforms[offset + 159] = layer.coloristaTint;
      uniforms[offset + 160] = layer.coloristaShadowRange;
      uniforms[offset + 161] = layer.coloristaHighlightRange;
      uniforms[offset + 162] = layer.coloristaMix;
      uniforms[offset + 163] = layer.coloristaPreserveLuma;
      uniforms[offset + 164] = layer.thinStreakSoftness;
      uniforms[offset + 165] = layer.lineArtStrength;
      uniforms[offset + 166] = layer.lineArtWidth;
      uniforms[offset + 167] = layer.lineArtPlacement;
      uniforms[offset + 168] = layer.lineArtSaturation;
      uniforms[offset + 169] = layer.radialChroma;
      uniforms[offset + 170] = layer.clarity;
      uniforms[offset + 171] = layer.clarityRadius;
      uniforms[offset + 172] = layer.skinEdgeBleed;
      uniforms[offset + 173] = layer.skinEdgeWidth;
      uniforms[offset + 174] = layer.halationStrength;
      uniforms[offset + 175] = layer.halationThreshold;
      uniforms[offset + 176] = layer.thinStreakFromEdge ? 1.0 : layer.flareOrigin;
      uniforms[offset + 177] = layer.edgeDarkenBlur;
      uniforms[offset + 178] = layer.flareThreshold;
      uniforms[offset + 179] = layer.flareSpacing;
      uniforms[offset + 180] = layer.flareThickness;
      uniforms[offset + 181] = layer.flareFalloff;
      uniforms[offset + 182] = layer.flareSceneTint;
      uniforms[offset + 183] = layer.flareCoreWhite;
    }

    MathOps.packLayers(uniforms, [for (final l in project.layers) l.mathOps]); // batch 14, kept in sync with main.dart
    Gradient4Way.packLayers(uniforms, [for (final l in project.layers) l.grad4]); // batch 14, kept in sync with main.dart
    Bevel.packLayers(uniforms, [for (final l in project.layers) l.bevel]); // batch 13: Metallic Bevel settings 7424..7583, kept in sync with main.dart
    TimeSlice.packLayers(uniforms, [for (final l in project.layers) l.timeSlice]); // batch 12 C2: Time Slice settings (6400..7039), kept in sync with main.dart
    return uniforms;
}
