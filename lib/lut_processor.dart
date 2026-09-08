import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

class CubeLutData {
  final String title;
  final int size;
  final Float32List table; // Size: size * size * size * 3

  CubeLutData({required this.title, required this.size, required this.table});
}

class LutProcessor {
  /// Safely picks a .cube file without throwing PlatformException on Android
  static Future<File?> pickCubeFile() async {
    try {
      // Use FileType.any to avoid Android's missing MIME-type crash
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.single.path;
        if (filePath != null) {
          if (filePath.toLowerCase().endsWith('.cube')) {
            return File(filePath);
          } else {
            debugPrint("Selected file is not a .cube file: $filePath");
            return null;
          }
        }
      }
    } catch (e) {
      debugPrint("Error picking .cube file: $e");
    }
    return null;
  }

  /// Parses an Adobe/Resolve .cube file into 32x32x32 Float32List RGB table
  static Future<CubeLutData?> parseCubeFile(File file) async {
    try {
      final lines = await file.readAsLines();
      int size = 0;
      String title = file.uri.pathSegments.last.replaceAll('.cube', '');
      List<double> rawFloats = [];

      for (var rawLine in lines) {
        String line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        if (line.toUpperCase().startsWith('TITLE')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            title = parts.sublist(1).join(' ').replaceAll('"', '');
          }
        } else if (line.toUpperCase().startsWith('LUT_3D_SIZE')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            size = int.tryParse(parts[1]) ?? 0;
          }
        } else if (line.toUpperCase().startsWith('DOMAIN_MIN') ||
            line.toUpperCase().startsWith('DOMAIN_MAX')) {
          // Domain limits ignored, assumed standard [0.0, 1.0]
          continue;
        } else {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final r = double.tryParse(parts[0]);
            final g = double.tryParse(parts[1]);
            final b = double.tryParse(parts[2]);
            if (r != null && g != null && b != null) {
              rawFloats.add(r.clamp(0.0, 1.0));
              rawFloats.add(g.clamp(0.0, 1.0));
              rawFloats.add(b.clamp(0.0, 1.0));
            }
          }
        }
      }

      if (size <= 0) {
        // Infer cube size if LUT_3D_SIZE was omitted
        final totalEntries = rawFloats.length ~/ 3;
        final cbrt = (totalEntries > 0) ? (totalEntries.toDouble()) : 0.0;
        if (totalEntries == 32768) {
          size = 32;
        } else if (totalEntries == 4913) {
          size = 17;
        } else if (totalEntries == 262144) {
          size = 64;
        } else {
          size = 32; // fallback default
        }
      }

      // Resample to 32x32x32 if LUT size differs from 32 for GPU memory alignment
      final targetSize = 32;
      Float32List standardizedTable;

      if (size == targetSize && rawFloats.length == targetSize * targetSize * targetSize * 3) {
        standardizedTable = Float32List.fromList(rawFloats);
      } else {
        standardizedTable = _resampleTo32(rawFloats, size, targetSize);
      }

      return CubeLutData(
        title: title,
        size: targetSize,
        table: standardizedTable,
      );
    } catch (e) {
      debugPrint("Failed to parse LUT file: $e");
      return null;
    }
  }

  static Float32List _resampleTo32(List<double> source, int srcSize, int dstSize) {
    final result = Float32List(dstSize * dstSize * dstSize * 3);
    int dstIdx = 0;

    for (int b = 0; b < dstSize; b++) {
      double fb = (b / (dstSize - 1)) * (srcSize - 1);
      int b0 = fb.floor().clamp(0, srcSize - 1);
      int b1 = (b0 + 1).clamp(0, srcSize - 1);
      double fdb = fb - b0;

      for (int g = 0; g < dstSize; g++) {
        double fg = (g / (dstSize - 1)) * (srcSize - 1);
        int g0 = fg.floor().clamp(0, srcSize - 1);
        int g1 = (g0 + 1).clamp(0, srcSize - 1);
        double fdg = fg - g0;

        for (int r = 0; r < dstSize; r++) {
          double fr = (r / (dstSize - 1)) * (srcSize - 1);
          int r0 = fr.floor().clamp(0, srcSize - 1);
          int r1 = (r0 + 1).clamp(0, srcSize - 1);
          double fdr = fr - r0;

          // Trilinear sampling from source
          for (int c = 0; c < 3; c++) {
            double c000 = _sampleRaw(source, srcSize, r0, g0, b0, c);
            double c100 = _sampleRaw(source, srcSize, r1, g0, b0, c);
            double c010 = _sampleRaw(source, srcSize, r0, g1, b0, c);
            double c110 = _sampleRaw(source, srcSize, r1, g1, b0, c);
            double c001 = _sampleRaw(source, srcSize, r0, g0, b1, c);
            double c101 = _sampleRaw(source, srcSize, r1, g0, b1, c);
            double c011 = _sampleRaw(source, srcSize, r0, g1, b1, c);
            double c111 = _sampleRaw(source, srcSize, r1, g1, b1, c);

            double c00 = c000 * (1 - fdr) + c100 * fdr;
            double c10 = c010 * (1 - fdr) + c110 * fdr;
            double c01 = c001 * (1 - fdr) + c101 * fdr;
            double c11 = c011 * (1 - fdr) + c111 * fdr;

            double c0 = c00 * (1 - fdg) + c10 * fdg;
            double c1 = c01 * (1 - fdg) + c11 * fdg;

            double val = c0 * (1 - fdb) + c1 * fdb;
            result[dstIdx++] = val.clamp(0.0, 1.0);
          }
        }
      }
    }
    return result;
  }

  static double _sampleRaw(List<double> src, int size, int r, int g, int b, int c) {
    int index = (b * size * size + g * size + r) * 3 + c;
    if (index >= 0 && index < src.length) {
      return src[index];
    }
    return 0.0;
  }
}
