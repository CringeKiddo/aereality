import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class LutLoader {
  static Future<(Float32List, int)?> loadLutFromFile() async {
    // Use FileType.any to avoid extension filter bugs
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null) return null;

    final file = result.files.single;
    final path = file.path;
    if (path == null || !path.toLowerCase().endsWith('.cube')) {
      throw Exception('Selected file is not a .cube file.');
    }

    final bytes = await File(path).readAsBytes();
    final content = String.fromCharCodes(bytes);
    return parseCube(content);
  }

  static (Float32List, int) parseCube(String content) {
    final lines = content.split('\n');
    int size = 0;
    final List<double> data = [];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('LUT_3D_SIZE')) {
        size = int.parse(line.split(' ').last);
        continue;
      }

      if (line.startsWith('TITLE') || line.startsWith('DOMAIN')) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final r = double.parse(parts[0]);
        final g = double.parse(parts[1]);
        final b = double.parse(parts[2]);
        data.add(r);
        data.add(g);
        data.add(b);
      }
    }

    if (size == 0) throw Exception('Invalid LUT file: LUT_3D_SIZE not found');
    final expected = size * size * size * 3;
    if (data.length != expected) {
      throw Exception('LUT data size mismatch: expected $expected, got ${data.length}');
    }

    return (Float32List.fromList(data), size);
  }
}
