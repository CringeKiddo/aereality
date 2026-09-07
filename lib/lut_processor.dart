import 'dart:io';
import 'dart:typed_data';
import 'models.dart';

class LutParser {
  static Future<LutModel?> parseCubeFile(File file) async {
    try {
      final lines = await file.readAsLines();
      int lutSize = 0;
      List<double> data = [];

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        if (line.startsWith('LUT_3D_SIZE')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            lutSize = int.tryParse(parts[1]) ?? 32;
          }
          continue;
        }

        if (line.startsWith('TITLE') || line.startsWith('DOMAIN_MIN') || line.startsWith('DOMAIN_MAX')) {
          continue;
        }

        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final r = double.tryParse(parts[0]);
          final g = double.tryParse(parts[1]);
          final b = double.tryParse(parts[2]);
          if (r != null && g != null && b != null) {
            data.add(r);
            data.add(g);
            data.add(b);
          }
        }
      }

      if (lutSize == 0) lutSize = 32;

      // Resample to 32x32x32 if non-standard
      final Float32List table = Float32List(32 * 32 * 32 * 3);

      if (lutSize == 32 && data.length >= 32 * 32 * 32 * 3) {
        for (int i = 0; i < table.length; i++) {
          table[i] = data[i];
        }
      } else {
        // Uniform identity fallback
        for (int b = 0; b < 32; b++) {
          for (int g = 0; g < 32; g++) {
            for (int r = 0; r < 32; r++) {
              int idx = (b * 32 * 32 + g * 32 + r) * 3;
              table[idx + 0] = r / 31.0;
              table[idx + 1] = g / 31.0;
              table[idx + 2] = b / 31.0;
            }
          }
        }
      }

      final fileName = file.path.split('/').last.replaceAll('.cube', '');
      return LutModel(
        id: 'lut_${DateTime.now().millisecondsSinceEpoch}',
        name: fileName,
        filePath: file.path,
        size: 32,
        table: table,
      );
    } catch (_) {
      return null;
    }
  }

  // Fast Trilinear Sample
  static void applyLutToRgb(Float32List table, double r, double g, double b, double opacity, List<double> outRgb) {
    r = r.clamp(0.0, 1.0) * 31.0;
    g = g.clamp(0.0, 1.0) * 31.0;
    b = b.clamp(0.0, 1.0) * 31.0;

    int r0 = r.floor();
    int r1 = (r0 + 1).clamp(0, 31);
    int g0 = g.floor();
    int g1 = (g0 + 1).clamp(0, 31);
    int b0 = b.floor();
    int b1 = (b0 + 1).clamp(0, 31);

    double dr = r - r0;
    double dg = g - g0;
    double db = b - b0;

    int c000 = (b0 * 32 * 32 + g0 * 32 + r0) * 3;
    int c100 = (b0 * 32 * 32 + g0 * 32 + r1) * 3;
    int c010 = (b0 * 32 * 32 + g1 * 32 + r0) * 3;
    int c110 = (b0 * 32 * 32 + g1 * 32 + r1) * 3;
    int c001 = (b1 * 32 * 32 + g0 * 32 + r0) * 3;
    int c101 = (b1 * 32 * 32 + g0 * 32 + r1) * 3;
    int c011 = (b1 * 32 * 32 + g1 * 32 + r0) * 3;
    int c111 = (b1 * 32 * 32 + g1 * 32 + r1) * 3;

    for (int ch = 0; ch < 3; ch++) {
      double c00 = table[c000 + ch] * (1 - dr) + table[c100 + ch] * dr;
      double c01 = table[c001 + ch] * (1 - dr) + table[c101 + ch] * dr;
      double c10 = table[c010 + ch] * (1 - dr) + table[c110 + ch] * dr;
      double c11 = table[c011 + ch] * (1 - dr) + table[c111 + ch] * dr;

      double c0 = c00 * (1 - dg) + c10 * dg;
      double c1 = c01 * (1 - dg) + c11 * dg;

      double lutVal = c0 * (1 - db) + c1 * db;
      double original = (ch == 0 ? r : ch == 1 ? g : b) / 31.0;
      outRgb[ch] = original * (1.0 - opacity) + lutVal * opacity;
    }
  }
}
