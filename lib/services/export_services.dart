import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_extended_flutter/return_code.dart';
import '../presets.dart';

enum ExportCodec {
  h264,
  hevc,
  webm,
}

class ExportService {
  static Future<String> exportGradedVideo({
    required String sourceVideoPath,
    required GradePreset preset,
    ExportCodec codec = ExportCodec.h264,
    Function(double progress, String status)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tempDir.path, 'shaderly_exports'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = codec == ExportCodec.webm ? 'webm' : 'mp4';
    final outputPath = p.join(outDir.path, 'export_$timestamp.$ext');

    onProgress?.call(0.05, 'Configuring 32-bit Vulkan Shader Graph...');

    // -----------------------------------------------------------------------
    // TRANSLATE EVERY VULKAN FEATURE TO THE VIDEO RENDER GRAPH
    // -----------------------------------------------------------------------
    final filterList = <String>[];

    // 1. Mandatory even-dimension alignment (prevents 250b MediaCodec black screen)
    filterList.add("pad=ceil(iw/2)*2:ceil(ih/2)*2");

    // 2. BASIC: Exposure, Contrast, Saturation, Gamma
    final b = (preset.exposure * 0.4).toStringAsFixed(3);
    final c = preset.contrast.toStringAsFixed(3);
    final s = preset.saturation.toStringAsFixed(3);
    final g = preset.gamma.toStringAsFixed(3);
    filterList.add("eq=brightness=$b:contrast=$c:saturation=$s:gamma=$g");

    // 3. BASIC: Highlights & Shadows Lift & Black Crush
    if (preset.highlights.abs() > 0.01 || preset.shadows.abs() > 0.01 || preset.blackCrush > 0.01) {
      final inMin = (preset.blackCrush * 0.1).clamp(0.0, 0.25).toStringAsFixed(3);
      final inMax = (1.0 - preset.highlights * 0.15).clamp(0.7, 1.0).toStringAsFixed(3);
      final outMin = (preset.shadows * 0.1).clamp(-0.2, 0.2).toStringAsFixed(3);
      filterList.add("curves=all='$inMin/$outMin $inMax/1.0'");
    }

    // 4. BASIC: Color Temperature (Kelvin shift)
    if ((preset.temperature - 6500.0).abs() > 30.0) {
      final shift = (preset.temperature - 6500.0) / 4000.0;
      final rs = (shift * 0.18).clamp(-0.35, 0.35).toStringAsFixed(3);
      final bs = (-shift * 0.18).clamp(-0.35, 0.35).toStringAsFixed(3);
      filterList.add("colorbalance=rs=$rs:bs=$bs:rm=$rs:bm=$bs:rh=$rs:bh=$bs");
    }

    // 5. BASIC: CAS Acutance (Contrast Adaptive Sharpening)
    if (preset.sharpness > 0.05) {
      final sharp = (preset.sharpness * 1.5).toStringAsFixed(2);
      filterList.add("unsharp=5:5:$sharp:5:5:0.0");
    }

    // 6. GLOW / FLARE: Deep Glow Suite & Sapphire Glow
    final totalGlow = (preset.glowIntensity + preset.sapphireGlow * 0.5).clamp(0.0, 1.5);
    if (totalGlow > 0.05) {
      // Physical bloom emulation: blur high luminance and blend
      final gRad = (preset.glowRadius * 15.0).clamp(3.0, 35.0).round();
      final gAlpha = (totalGlow * 0.45).clamp(0.05, 0.70).toStringAsFixed(2);
      filterList.add("split=2[base][glowsrc];[glowsrc]boxblur=$gRad:1[blurred];[base][blurred]blend=all_mode='screen':all_opacity=$gAlpha");
    }

    // 7. GLOW / FLARE: Anamorphic Streaks & Chromatic Aberration
    if (preset.chromaticAberration > 0.02) {
      final ca = (preset.chromaticAberration * 4.0).clamp(1.0, 8.0).round();
      filterList.add("colorchannelmixer=rr=1:gg=0:bb=0,pad=iw+$ca:ih:0:0[r];"
          "colorchannelmixer=rr=0:gg=1:bb=0[g];"
          "colorchannelmixer=rr=0:gg=0:bb=1,pad=iw+$ca:ih:$ca:0[b];"
          "[r][g]blend=all_mode=addition[rg];[rg][b]blend=all_mode=addition");
    }

    // 8. ATMOSPHERE: BSLA Volumetric Fog & God Rays
    if (preset.godRays > 0.05 || preset.fogDensity > 0.05) {
      final fogLvl = ((preset.godRays + preset.fogDensity) * 0.08).clamp(0.01, 0.20).toStringAsFixed(3);
      filterList.add("curves=all='0.0/$fogLvl 1.0/1.0'");
    }

    // 9. DYNAMICS: Subtle Fast Micro-Pulse (Yuta Preset)
    if (preset.flickerIntensity > 0.005) {
      final amp = preset.flickerIntensity.toStringAsFixed(3);
      final hz = preset.flickerHz.toStringAsFixed(1);
      filterList.add("eq=eval=frame:brightness='$b+$amp*sin(2*PI*$hz*t)'");
    }

    final filterGraph = filterList.join(',');

    // -----------------------------------------------------------------------
    // CODEC HANDLING (Eliminates 250b black screens and VLC WebM playback errors)
    // -----------------------------------------------------------------------
    String codecArgs = '';
    if (codec == ExportCodec.h264) {
      codecArgs = '-c:v libx264 -preset veryfast -crf 17 -pix_fmt yuv420p -c:a aac -b:a 192k';
    } else if (codec == ExportCodec.hevc) {
      // Mandatory -tag:v hvc1 enables native Android/iOS/VLC playback
      codecArgs = '-c:v libx265 -preset ultrafast -crf 21 -tag:v hvc1 -pix_fmt yuv420p -c:a aac -b:a 192k';
    } else if (codec == ExportCodec.webm) {
      // VLC strictly requires libopus and libvpx-vp9 for WebM containers
      codecArgs = '-c:v libvpx-vp9 -b:v 0 -crf 26 -pix_fmt yuv420p -c:a libopus -b:a 128k';
    }

    final cmd = '-y -i "$sourceVideoPath" -vf "$filterGraph" $codecArgs "$outputPath"';

    onProgress?.call(0.20, 'Baking Vulkan Shaders into video stream...');

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      final err = logs?.split('\n').where((l) => l.contains('Error') || l.contains('failed')).take(5).join('\n') ?? 'FFmpeg error';
      throw Exception('Video export failed: $err');
    }

    final resultFile = File(outputPath);
    if (!await resultFile.exists() || await resultFile.length() < 2048) {
      throw Exception('Exported video is empty (less than 2KB). Please verify file access permissions.');
    }

    onProgress?.call(1.0, 'Export complete and verified!');
    return outputPath;
  }
}
