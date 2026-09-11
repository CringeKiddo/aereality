// ==========================================
// PART 1 OF 2: lib/main.dart
// ==========================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

import 'constants.dart';
import 'models.dart';
import 'lut_processor.dart';
import 'components/curve_editor.dart';
import 'vulkan_bridge.dart';
import 'touch_particles.dart';
import 'ai_upscaler_screen.dart';
import 'rsmb_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await FFmpegKitExtended.initialize();
  } catch (e) {
    debugPrint('FFmpeg initialization error: $e');
  }

  try {
    final shaderlyDir = Directory('/storage/emulated/0/Shaderly');
    if (!await shaderlyDir.exists()) {
      await shaderlyDir.create(recursive: true);
    }
  } catch (_) {}

  runApp(const ShaderlyApp());
}

class ShaderlyApp extends StatelessWidget {
  const ShaderlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: gCustomAccentColor,
      builder: (context, accentColor, _) {
        return MaterialApp(
          title: 'Shaderly',
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: kBackgroundDark,
            primaryColor: accentColor,
            colorScheme: ColorScheme.dark(
              primary: accentColor,
              secondary: kCyanAccent,
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
          home: const TouchParticlesWrapper(
            child: HomeScreen(),
          ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<StoredProject> _recent = [];
  final Map<String, Uint8List?> _thumbnails = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projs = await ProjectManager.loadProjects();
    if (mounted) {
      setState(() {
        _recent = projs.take(4).toList();
      });
      _generateThumbnails(_recent);
    }
  }

  Future<void> _generateThumbnails(List<StoredProject> projects) async {
    final tempDir = await getTemporaryDirectory();
    for (final p in projects) {
      if (_thumbnails.containsKey(p.id) && _thumbnails[p.id] != null) continue;
      if (!File(p.mediaPath).existsSync()) continue;

      if (p.data.isImage) {
        try {
          final bytes = await File(p.mediaPath).readAsBytes();
          if (mounted) setState(() => _thumbnails[p.id] = bytes);
        } catch (_) {}
      } else {
        try {
          final outThumb = '${tempDir.path}/thumb_${p.id}.jpg';
          final thumbFile = File(outThumb);
          if (!await thumbFile.exists()) {
            await FFmpegKit.execute(
              '-hide_banner -ss 0.1 -i "${p.mediaPath}" -vframes 1 -vf scale=160:-1 -q:v 4 -y "$outThumb"',
            );
          }
          if (await thumbFile.exists()) {
            final bytes = await thumbFile.readAsBytes();
            if (mounted) setState(() => _thumbnails[p.id] = bytes);
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _clearAppCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int deletedBytes = 0;
      if (await tempDir.exists()) {
        final list = tempDir.listSync(recursive: true);
        for (var f in list) {
          if (f is File) {
            try {
              deletedBytes += f.lengthSync();
              f.deleteSync();
            } catch (_) {}
          }
        }
      }
      final double mbFreed = deletedBytes / (1024 * 1024);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cache Cleared: ${mbFreed.toStringAsFixed(1)} MB freed'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing cache: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteProject(int index) {
    final proj = _recent[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Project?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Delete "${proj.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _recent.removeAt(index);
                _thumbnails.remove(proj.id);
              });
              await ProjectManager.saveProjects(_recent);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project deleted.')));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showColorPickerModal() {
    final List<Map<String, dynamic>> palette = [
      {'name': 'Aquamarine', 'color': const Color(0xFF7FFFD4)},
      {'name': 'Soft Cream', 'color': const Color(0xFFFFFDD0)},
      {'name': 'Matcha Green', 'color': const Color(0xFFB7D5AC)},
      {'name': 'Lavender Mist', 'color': const Color(0xFFE6E6FA)},
      {'name': 'Muted Rose', 'color': const Color(0xFFDDA7A5)},
      {'name': 'Peach Puff', 'color': const Color(0xFFFFDAB9)},
      {'name': 'Pistachio', 'color': const Color(0xFF93C572)},
      {'name': 'Mint Cream', 'color': const Color(0xFFF5FFFA)},
      {'name': 'Pale Canary', 'color': const Color(0xFFFFFF99)},
      {'name': 'Blush Pink', 'color': const Color(0xFFFFD1DC)},
      {'name': 'Soft Lilac', 'color': const Color(0xFFC8A2C8)},
      {'name': 'Baby Blue', 'color': const Color(0xFF89CFF0)},
      {'name': 'Periwinkle', 'color': const Color(0xFFCCCCFF)},
      {'name': 'Sage Gray', 'color': const Color(0xFF9EA99C)},
      {'name': 'Almond Silk', 'color': const Color(0xFFEFDECD)},
      {'name': 'Vanilla Custard', 'color': const Color(0xFFF3E5AB)},
      {'name': 'Seafoam Frost', 'color': const Color(0xFF9FE2BF)},
      {'name': 'Celadon', 'color': const Color(0xFFACE1AF)},
      {'name': 'Muted Apricot', 'color': const Color(0xFFFBCEB1)},
      {'name': 'Mauve Taupe', 'color': const Color(0xFFB784A7)},
      {'name': 'Desert Sand', 'color': const Color(0xFFEDC9AF)},
      {'name': 'Pure White', 'color': const Color(0xFFFFFFFF)},
      {'name': 'Platinum Ice', 'color': const Color(0xFFE5E4E2)},
      {'name': 'Ghost Slate', 'color': const Color(0xFFD8D8E0)},
      {'name': 'Quincy Cyan', 'color': const Color(0xFF00E5FF)},
      {'name': 'Electric Gold', 'color': const Color(0xFFFFD700)},
      {'name': 'Neon Mint', 'color': const Color(0xFF00FF9D)},
      {'name': 'Vibrant Violet', 'color': const Color(0xFF7C4DFF)},
      {'name': 'Shogun Crimson', 'color': const Color(0xFFFF3366)},
      {'name': 'Solar Amber', 'color': const Color(0xFFFF9100)},
      {'name': 'Laser Lemon', 'color': const Color(0xFFF9E858)},
      {'name': 'Spring Meadow', 'color': const Color(0xFF69F0AE)},
      {'name': 'Hot Coral', 'color': const Color(0xFFFF6F61)},
      {'name': 'Cyber Purple', 'color': const Color(0xFFB388FF)},
      {'name': 'Deep Magenta', 'color': const Color(0xFFFF4081)},
      {'name': 'Arctic Teal', 'color': const Color(0xFF1DE9B6)},
      {'name': 'Imperial Ruby', 'color': const Color(0xFFFF1744)},
      {'name': 'Cobalt Neon', 'color': const Color(0xFF2979FF)},
      {'name': 'Sunburst Glow', 'color': const Color(0xFFFFAB00)},
      {'name': 'Emerald Glow', 'color': const Color(0xFF00E676)},
      {'name': 'Flamingo', 'color': const Color(0xFFFC8EAC)},
      {'name': 'Steel Cyan', 'color': const Color(0xFF64FFDA)},
    ];

    Color selectedTemp = gCustomAccentColor.value;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          return AlertDialog(
            backgroundColor: const Color(0xFF121218),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(
              children: [
                Icon(Icons.palette_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Accent Color', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: palette.length,
                itemBuilder: (context, i) {
                  final col = palette[i]['color'] as Color;
                  final isSel = selectedTemp.value == col.value;
                  return GestureDetector(
                    onTap: () => setModal(() => selectedTemp = col),
                    child: Container(
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSel ? Colors.white : Colors.white10,
                          width: isSel ? 3.5 : 1.0,
                        ),
                        boxShadow: isSel ? [BoxShadow(color: col.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)] : null,
                      ),
                      child: isSel ? const Icon(Icons.check_rounded, color: Colors.black, size: 16) : null,
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedTemp,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() => gCustomAccentColor.value = selectedTemp);
                  Navigator.pop(ctx);
                },
                child: const Text('APPLY COLOR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          final accent = gCustomAccentColor.value;
          return AlertDialog(
            backgroundColor: kCardDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ACCENT COLOR', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showColorPickerModal();
                    },
                    icon: Icon(Icons.color_lens_rounded, color: accent, size: 18),
                    label: const Text('Pick Color', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B1B24),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text('PROCESSING PRECISION', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [8, 16, 32].map((bit) {
                      final isSel = gEnginePrecision == bit;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text('${bit}-Bit'),
                            selected: isSel,
                            selectedColor: accent,
                            backgroundColor: const Color(0xFF1E1E28),
                            labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                            onSelected: (_) {
                              setModal(() => gEnginePrecision = bit);
                              setState(() {});
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  const Text('PREVIEW QUALITY (LAG REDUCTION / 4K SHIELD)', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('25% Draft'),
                        selected: gPreviewScale == 0.25,
                        selectedColor: accent,
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 0.25);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('50% Smooth'),
                        selected: gPreviewScale == 0.50,
                        selectedColor: accent,
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 0.50);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('100% Native'),
                        selected: gPreviewScale == 1.0,
                        selectedColor: accent,
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 1.0);
                          setState(() {});
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Text('CREATOR', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: kMyYouTubeChannel));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('YouTube channel link copied'), backgroundColor: Colors.redAccent),
                      );
                    },
                    icon: const Icon(Icons.smart_display_rounded, color: Colors.redAccent, size: 18),
                    label: const Text('YouTube (@null7839)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1418),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withOpacity(0.3)),
              ),
              child: Text('SH', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Text('Shaderly', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded, color: Colors.white70),
            tooltip: 'Clear App Cache',
            onPressed: _clearAppCache,
          ),
          IconButton(
            icon: Icon(Icons.tune_rounded, color: accent),
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
            const Text('Shaderly', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // BUTTON 1: NEW PROJECT
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.40),
                    blurRadius: 14,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())).then((_) => _load()),
                icon: const Icon(Icons.add_rounded, color: Colors.black, size: 22),
                label: const Text('NEW PROJECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: accent, width: 2.0),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // BUTTON 2: AI UPSCALER
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.35),
                    blurRadius: 14,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiUpscalerScreen())).then((_) => _load()),
                icon: const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 20),
                label: const Text('AI UPSCALER (2X / 4X)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF00E5FF), width: 2.0),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // BUTTON 3: MOTION BLUR STUDIO
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RsmbScreen())),
                icon: Icon(Icons.blur_linear_rounded, color: accent, size: 18),
                label: Text('MOTION BLUR STUDIO', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accent.withOpacity(0.6), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // RECENT PROJECT OPENER
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (_recent.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: _recent.first.data, projectName: _recent.first.name)),
                    ).then((_) => _load());
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved projects yet.')));
                  }
                },
                icon: Icon(Icons.bookmarks_rounded, color: accent, size: 18),
                label: Text('OPEN RECENT PROJECT', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accent.withOpacity(0.4), width: 1.0),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text('SAVED PROJECTS', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
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
                    Icon(Icons.layers_clear_outlined, color: Colors.white24, size: 36),
                    SizedBox(height: 10),
                    Text('No saved projects found.', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Tap "NEW PROJECT" to start.', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _recent.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = _recent[i];
                    final thumbBytes = _thumbnails[p.id];

                    return Container(
                      decoration: BoxDecoration(
                        color: kCardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 50,
                            height: 50,
                            color: Colors.black45,
                            child: thumbBytes != null
                                ? Image.memory(thumbBytes, fit: BoxFit.cover)
                                : Icon(p.data.isImage ? Icons.image_rounded : Icons.movie_creation_rounded, color: accent),
                          ),
                        ),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${p.mediaPath.split('/').last}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                              tooltip: 'Delete Project',
                              onPressed: () => _deleteProject(i),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, color: accent, size: 14),
                          ],
                        ),
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

class ProjectSetupScreen extends StatefulWidget {
  const ProjectSetupScreen({super.key});

  @override
  State<ProjectSetupScreen> createState() => _ProjectSetupScreenState();
}

class _ProjectSetupScreenState extends State<ProjectSetupScreen> {
  String _projectName = 'Shaderly Master';
  String _selectedAspect = '16:9';
  File? _selectedFile;
  bool _isImage = false;

  final List<String> _aspectRatios = ['16:9', '9:16', '4:5', '1:1', '3:4', '21:9'];

  Widget _buildProportionalRatioBox(String ratio, bool isSelected, Color accent) {
    double w = 28.0;
    double h = 28.0;
    switch (ratio) {
      case '16:9': w = 36.0; h = 20.0; break;
      case '9:16': w = 20.0; h = 36.0; break;
      case '4:5':  w = 24.0; h = 30.0; break;
      case '1:1':  w = 26.0; h = 26.0; break;
      case '3:4':  w = 24.0; h = 32.0; break;
      case '21:9': w = 42.0; h = 18.0; break;
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedAspect = ratio),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.18) : kCardDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? accent : Colors.white12, width: isSelected ? 2.0 : 1.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 40,
              child: Center(
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: isSelected ? accent : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: isSelected ? Colors.black : Colors.white54, width: 1.2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ratio,
              style: TextStyle(
                color: isSelected ? accent : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

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
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'Shaderly Master',
              controller: TextEditingController(text: _projectName),
            ),
            const SizedBox(height: 20),
            const Text('OUTPUT ASPECT RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _aspectRatios.map((ratio) => _buildProportionalRatioBox(ratio, _selectedAspect == ratio, accent)).toList(),
            ),
            const SizedBox(height: 24),
            const Text('SOURCE FOOTAGE OR ART', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                );
                if (result != null && result.files.single.path != null) {
                  final p = result.files.single.path!;
                  final ext = p.split('.').last.toLowerCase();
                  final validExts = ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'];
                  if (validExts.contains(ext)) {
                    final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
                    setState(() {
                      _selectedFile = File(p);
                      _isImage = isImg;
                    });
                  }
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
                      color: accent,
                      size: 40,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _selectedFile == null ? 'Browse video file or image' : _selectedFile!.path.split('/').last,
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
                          layers: [
                            AdjustmentLayer(
                              id: 'layer_clean_base',
                              name: 'Base Grade',
                              blendMode: LayerBlendMode.normal,
                              contrast: 1.0,
                              saturation: 1.0,
                              brightness: 0.0,
                            ),
                          ],
                        ),
                        projectName: _projectName,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
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

class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  final String? projectName;
  final bool isImportedFromUpscaler;

  const ProjectScreen({
    super.key,
    this.initialProject,
    this.projectName,
    this.isImportedFromUpscaler = false,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  late ProjectData _project;
  final List<ProjectData> _undoHistory = [];

  VideoPlayerController? _controller;
  bool _isPlaying = false;
  img.Image? _cachedRawImage;
  bool _isFullScreen = false;

  late TabController _tabController;
  int _selectedCurveChannel = 0;

  ui.Image? _processedStaticImage;
  int _renderWidth = 720;
  int _renderHeight = 900;

  String? _selectedPresetName;
  bool _isBslaExtremeActive = false;

  Timer? _playbackTimer;
  double _currentTimelinePosition = 0.0;
  double _videoDurationSeconds = 1.0;

  List<CustomPresetItem> _customPresets = [];
  List<LutModel> _activeLuts = [];

  bool _isVulkanProcessing = false;
  bool _needsReprocess = false;

  // Split Toning & Dithering state
  double _splitToneShadowH = 0.60;
  double _splitToneShadowS = 0.0;
  double _splitToneHighH = 0.12;
  double _splitToneHighS = 0.0;
  double _splitToneBalance = 0.0;
  double _ditherStrength = 1.0;

  // Text Effects Suite (WIS Edits)
  double _textBevel = 0.0;
  double _textLightSweep = 0.0;
  double _textHorizonRamp = 0.0;
  double _textInnerShadow = 0.0;
  double _textOcclusionRim = 0.0;
  double _textTightCoreGlow = 0.0;
  double _textCenterAura = 0.0;

  FFmpegSession? _activeExportSession;
  bool _isExportCancelled = false;

  AdjustmentLayer get _cur => _project.currentLayer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
    _loadShader();

    _project = widget.initialProject ?? ProjectData(mediaPath: '');
    _pushUndoSnapshot();

    _loadCustomPresets();
    _loadLuts();
    _loadMedia(_project.mediaPath);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _tabController.dispose();
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _processedStaticImage?.dispose();
    super.dispose();
  }

  void _pushUndoSnapshot() {
    _undoHistory.add(_project.clone());
    if (_undoHistory.length > 50) {
      _undoHistory.removeAt(0);
    }
  }

  void _performUndo() {
    if (_undoHistory.length > 1) {
      setState(() {
        _undoHistory.removeLast();
        _project = _undoHistory.last.clone();
      });
      _applyGrade();
      _autoSaveProject();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reverted latest change'), duration: Duration(milliseconds: 750)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already at initial state'), duration: Duration(milliseconds: 750)),
      );
    }
  }

  Future<void> _loadCustomPresets() async {
    final list = await ProjectManager.loadCustomPresets();
    if (mounted) setState(() => _customPresets = list);
  }

  Future<void> _loadLuts() async {
    final list = await ProjectManager.loadLuts();
    if (mounted) setState(() => _activeLuts = list);
  }

  Map<String, int> _calculateTargetDimensions(String resolutionName, String ratioStr, [double scale = 1.0]) {
    int baseSize;
    switch (resolutionName) {
      case '720p':  baseSize = 720; break;
      case '1080p': baseSize = 1080; break;
      case '2K':    baseSize = 1440; break;
      case '4K':    baseSize = 2160; break;
      default:      baseSize = 1080;
    }

    baseSize = (baseSize * scale).round();
    final double ratio = _getAspectRatioValue(ratioStr);
    int targetW, targetH;

    if (ratio < 1.0) {
      targetW = baseSize;
      targetH = (targetW / ratio).round();
    } else {
      targetH = baseSize;
      targetW = (targetH * ratio).round();
    }

    // Hardware MediaCodec & Encoder safety: Enforce 16-pixel alignment
    targetW = math.max(16, ((targetW + 15) ~/ 16) * 16);
    targetH = math.max(16, ((targetH + 15) ~/ 16) * 16);

    return {'width': targetW, 'height': targetH};
  }

  void _updateDimensions(int srcW, int srcH) {
    final dims = _calculateTargetDimensions('720p', _project.aspectRatio, gPreviewScale);
    _renderWidth = dims['width']!;
    _renderHeight = dims['height']!;
  }

  Future<void> _loadShader() async {
    final candidateNames = [
      'assets/shaders/aereality_core.spv',
      'shaders/aereality_core.spv',
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

  Future<void> _switchMediaFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final p = result.files.single.path!;
      final ext = p.split('.').last.toLowerCase();
      final validExts = ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'];
      if (validExts.contains(ext)) {
        await _loadMedia(p);
      }
    }
  }

  Future<void> _loadMedia(String path) async {
    if (path.isEmpty) return;
    final ext = path.split('.').last.toLowerCase();
    final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);

    _playbackTimer?.cancel();
    if (_controller != null) {
      await _controller!.pause();
      await _controller!.dispose();
      _controller = null;
    }

    setState(() {
      _project.mediaPath = path;
      _project.isImage = isImg;
      _processedStaticImage?.dispose();
      _processedStaticImage = null;
      _isPlaying = false;
      _currentTimelinePosition = 0.0;
    });

    if (isImg) {
      final fileBytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(fileBytes);
      if (decoded != null) {
        _cachedRawImage = decoded;
        _updateDimensions(decoded.width, decoded.height);
        _applyGrade();
      }
    } else {
      _cachedRawImage = null;
      _controller = VideoPlayerController.file(File(path))
        ..initialize().then((_) {
          if (!mounted) return;
          final vw = _controller!.value.size.width.toInt();
          final vh = _controller!.value.size.height.toInt();
          _updateDimensions(vw, vh);
          _videoDurationSeconds = _controller!.value.duration.inMilliseconds / 1000.0;
          if (_videoDurationSeconds <= 0.0) _videoDurationSeconds = 1.0;

          if (widget.isImportedFromUpscaler) {
            _controller!.pause();
            _isPlaying = false;
          } else {
            _controller!.play();
            _controller!.setLooping(true);
            _isPlaying = true;
          }

          setState(() {});
          _applyGrade();

          _playbackTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
            if (_controller != null && _controller!.value.isPlaying && mounted) {
              setState(() {
                _currentTimelinePosition = _controller!.value.position.inMilliseconds / 1000.0;
              });
            }
          });
        });
    }

    _autoSaveProject();
  }

  Future<void> _applyGrade() async {
    if (_isVulkanProcessing) {
      _needsReprocess = true;
      return;
    }
    _isVulkanProcessing = true;
    _needsReprocess = false;

    try {
      int w = _renderWidth;
      int h = _renderHeight;
      Uint8List? rawBytes;

      if (_project.isImage && _cachedRawImage != null) {
        final resized = img.copyResize(_cachedRawImage!, width: w, height: h);
        rawBytes = resized.getBytes(order: img.ChannelOrder.rgba);
      } else if (!_project.isImage && _project.mediaPath.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final framePath = '${tempDir.path}/tl_frame_preview.png';
        await FFmpegKit.execute(
          '-hide_banner -y -ss $_currentTimelinePosition -i "${_project.mediaPath}" -vframes 1 -s ${w}x${h} "$framePath"',
        );

        final frameFile = File(framePath);
        if (await frameFile.exists()) {
          final fBytes = await frameFile.readAsBytes();
          final decoded = img.decodePng(fBytes);
          if (decoded != null) {
            rawBytes = decoded.getBytes(order: img.ChannelOrder.rgba);
          }
          try { await frameFile.delete(); } catch (_) {}
        }
      }

      if (rawBytes != null) {
        final uniforms = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
        final lutTable = _getActiveLutTable();

        // 100% PURE 32-BIT VULKAN COMPUTE EXECUTION (ZERO CPU COLORFILTER MATRIX)
        final outBytes = processImage(rawBytes, w, h, w, h, uniforms, lutTable: lutTable);

        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(outBytes, w, h, ui.PixelFormat.rgba8888, (im) => completer.complete(im));
        final res = await completer.future;

        if (mounted) {
          setState(() {
            _processedStaticImage?.dispose();
            _processedStaticImage = res;
          });
        }
      }
    } catch (_) {
    } finally {
      _isVulkanProcessing = false;
      if (_needsReprocess && mounted) {
        _applyGrade();
      }
    }
  }

  Float32List? _getActiveLutTable() {
    if (_cur.activeLutId == null) return null;
    final match = _activeLuts.where((l) => l.id == _cur.activeLutId);
    if (match.isEmpty) return null;
    return match.first.table;
  }

  Future<void> _autoSaveProject() async {
    if (_project.mediaPath.isEmpty) return;
    final proj = StoredProject(
      id: widget.projectName ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
      name: widget.projectName ?? 'Shaderly Session',
      mediaPath: _project.mediaPath,
      data: _project,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(proj);
  }

  Float32List _packMultiLayerUniforms(double imgW, double imgH) {
    final uniforms = Float32List(512);
    final timeSeconds = (_controller != null && _controller!.value.isInitialized)
        ? _controller!.value.position.inMilliseconds / 1000.0
        : 0.0;

    uniforms[0] = timeSeconds;
    uniforms[1] = _project.layers.length.toDouble();
    uniforms[2] = _project.tonemapMode;
    uniforms[3] = imgW;
    uniforms[4] = imgH;
    uniforms[5] = _cur.activeLutId != null ? 1.0 : 0.0;
    uniforms[6] = _cur.lutOpacity;
    uniforms[7] = _splitToneShadowH;
    uniforms[8] = _splitToneShadowS;
    uniforms[9] = _splitToneHighH;
    uniforms[10] = _splitToneHighS;
    uniforms[11] = _splitToneBalance;
    uniforms[12] = _ditherStrength;
    uniforms[13] = _textBevel;
    uniforms[14] = _textLightSweep;
    uniforms[15] = _textHorizonRamp;
    uniforms[16] = _textInnerShadow;
    uniforms[17] = _textOcclusionRim;
    uniforms[18] = _textTightCoreGlow;
    uniforms[19] = _textCenterAura;

    for (int l = 0; l < math.min(_project.layers.length, 4); l++) {
      final layer = _project.layers[l];
      final offset = 20 + (l * 64);

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
      uniforms[offset + 25] = layer.darkOutlines;
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

      // FIXED: Magic Bullet Mojo passes normalized balance & skin protection
      uniforms[offset + 53] = layer.mblMojoTealOrange;

      uniforms[offset + 54] = layer.bslaGodRays;
      uniforms[offset + 55] = layer.bslaFogDensity;
      uniforms[offset + 56] = layer.bslaFogDepth;

      // FIXED: Bloom Haze threshold & dispersion scaling
      uniforms[offset + 57] = layer.bslaBloomHaze;

      uniforms[offset + 58] = layer.bslFogScatter;
      uniforms[offset + 59] = 0.0;
      uniforms[offset + 60] = 0.0;
      uniforms[offset + 61] = 0.0;
      uniforms[offset + 62] = 0.0;
      uniforms[offset + 63] = 0.0;
    }

    return uniforms;
  }

  double _getAspectRatioValue(String ratio) {
    switch (ratio) {
      case "4:5": return 4 / 5;
      case "16:9": return 16 / 9;
      case "9:16": return 9 / 16;
      case "1:1": return 1 / 1;
      case "3:4": return 3 / 4;
      case "21:9": return 21 / 9;
      default: return 16 / 9;
    }
  }

  void _addNewAdjustmentLayer() {
    if (_project.layers.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 4 Adjustment Layers allowed.')));
      return;
    }
    _pushUndoSnapshot();
    setState(() {
      final newIndex = _project.layers.length + 1;
      _project.layers.add(AdjustmentLayer(
        id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Layer $newIndex',
        blendMode: LayerBlendMode.screen,
      ));
      _project.activeLayerIndex = _project.layers.length - 1;
      _selectedPresetName = null;
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _removeCurrentLayer() {
    _pushUndoSnapshot();
    setState(() {
      if (_project.layers.isNotEmpty) {
        _project.layers.removeAt(_project.activeLayerIndex);
        if (_project.layers.isNotEmpty) {
          _project.activeLayerIndex = math.max(0, _project.activeLayerIndex - 1);
        } else {
          _project.activeLayerIndex = 0;
        }
      }
      _selectedPresetName = null;
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _resetCurrentLayer() {
    if (_project.layers.isEmpty) return;
    _pushUndoSnapshot();
    setState(() {
      _project.layers[_project.activeLayerIndex] = AdjustmentLayer(
        id: _cur.id,
        name: _cur.name,
        blendMode: _cur.blendMode,
      );
      _selectedPresetName = null;
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _toggleBslaExtremePreset() {
    _pushUndoSnapshot();
    setState(() {
      if (_isBslaExtremeActive) {
        _project.layers.removeWhere((l) => l.id == 'bsla_extreme_atmospheric');
        _isBslaExtremeActive = false;
      } else {
        if (_project.layers.length >= 4) {
          _project.layers.removeLast();
        }
        final bslaLayer = AdjustmentLayer(
          id: 'bsla_extreme_atmospheric',
          name: 'BSLA Clean Atmospheric',
          blendMode: LayerBlendMode.screen,
          opacity: 0.90,
          bslaGodRays: 0.75,
          bslaFogDensity: 0.55,
          bslaFogDepth: 0.65,
          bslaBloomHaze: 0.65,
          bslFogScatter: 0.40,
          deepGlowIntensity: 0.45,
          deepGlowRadius: 0.65,
          deepGlowThreshold: 0.40,
          edgeGlowTint: 0.0,
          contrast: 1.0,
          saturation: 1.0,
        );
        _project.layers.add(bslaLayer);
        _project.activeLayerIndex = _project.layers.length - 1;
        _isBslaExtremeActive = true;
      }
    });
    _applyGrade();
    _autoSaveProject();
  }
  void _applyPreset(String name) {
    _pushUndoSnapshot();
    setState(() {
      _project.layers.clear();
      _selectedPresetName = name;
      _isBslaExtremeActive = false;

      switch (name.toLowerCase()) {
        // =====================================================================
        // NEW PRESETS (WIS STYLE COPIED FROM YOUR LINKS)
        // =====================================================================
        case 'goku':
          // Layer 1: Cold Heavy Dynamic Base (Druko style)
          _project.layers.add(AdjustmentLayer(
            id: 'goku_base',
            name: 'Base Grade',
            contrast: 1.44,
            saturation: 0.82,
            brightness: 0.01,
            temperature: 7300.0,
            sharpness: 0.58,
            shadows: -0.16,
            highlights: 0.22,
            blackCrush: 0.06,
            edgeDarken: 0.26,
            darkOutlines: 0.16,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.16, 0.47, 0.86, 1.0],
            flickerIntensity: 0.04,
            flickerSpeed: 12.0,
          ));
          // Layer 2: High Specular Rim & Amber Glint
          _project.layers.add(AdjustmentLayer(
            id: 'goku_rim',
            name: 'Specular Rim',
            blendMode: LayerBlendMode.screen,
            opacity: 0.78,
            deepGlowIntensity: 0.42,
            deepGlowRadius: 0.52,
            deepGlowThreshold: 0.50,
            edgeGlowTint: 1.0, // Noble Gold / Amber specular
            thinStreakIntensity: 0.28,
            thinStreakWidth: 0.65,
            thinStreakOpacity: 0.82,
            lineChromaStrength: 0.25,
          ));
          // Layer 3: Atmospheric Diffusion Mist
          _project.layers.add(AdjustmentLayer(
            id: 'goku_atmo',
            name: 'Atmospheric Haze',
            blendMode: LayerBlendMode.screen,
            opacity: 0.65,
            bslaBloomHaze: 0.58,
            bslFogScatter: 0.35,
            bslaFogDensity: 0.25,
            deepGlowIntensity: 0.28,
            deepGlowRadius: 0.68,
            deepGlowThreshold: 0.44,
            edgeGlowTint: 0.0,
          ));
          break;

        case 'desaturated':
          // Layer 1: Gritty Desaturated Core (Conquestor style)
          _project.layers.add(AdjustmentLayer(
            id: 'desat_base',
            name: 'Base Grade',
            contrast: 1.48,
            saturation: 0.60,
            brightness: -0.02,
            temperature: 6900.0,
            sharpness: 0.62,
            shadows: -0.18,
            highlights: 0.14,
            blackCrush: 0.08,
            edgeDarken: 0.32,
            darkOutlines: 0.20,
            vignette: 0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.02, 0.14, 0.46, 0.84, 0.98],
          ));
          // Layer 2: Cold S-Curve Split
          _project.layers.add(AdjustmentLayer(
            id: 'desat_curve',
            name: 'Cold Tone',
            blendMode: LayerBlendMode.softLight,
            opacity: 0.75,
            contrast: 1.15,
            saturation: 0.75,
            temperature: 7600.0,
            curveBlue: [0.04, 0.20, 0.50, 0.82, 0.96],
            curveRed: [0.0, 0.14, 0.46, 0.80, 0.96],
          ));
          // Layer 3: Specular Edge & Fine Chromatic Aberration
          _project.layers.add(AdjustmentLayer(
            id: 'desat_glow',
            name: 'Edge Specular',
            blendMode: LayerBlendMode.screen,
            opacity: 0.68,
            deepGlowIntensity: 0.34,
            deepGlowRadius: 0.44,
            deepGlowThreshold: 0.54,
            edgeGlowTint: 0.0,
            lineChromaStrength: 0.30,
            thinStreakIntensity: 0.14,
            thinStreakOpacity: 0.70,
          ));
          break;

        case 'yamato':
          // Layer 1: High Contrast Neutral Fidelity (Adevob WIS style - no pink shift)
          _project.layers.add(AdjustmentLayer(
            id: 'yamato_base',
            name: 'Base Grade',
            contrast: 1.40,
            saturation: 0.92,
            brightness: 0.01,
            temperature: 6600.0,
            sharpness: 0.56,
            shadows: -0.12,
            highlights: 0.16,
            edgeDarken: 0.28,
            darkOutlines: 0.15,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.17, 0.49, 0.85, 1.0],
          ));
          // Layer 2: Crisp Ivory/Cyan Specular Edge
          _project.layers.add(AdjustmentLayer(
            id: 'yamato_specular',
            name: 'Ivory Specular',
            blendMode: LayerBlendMode.screen,
            opacity: 0.76,
            deepGlowIntensity: 0.44,
            deepGlowRadius: 0.50,
            deepGlowThreshold: 0.48,
            edgeGlowTint: 0.0,
            thinStreakIntensity: 0.24,
            thinStreakWidth: 0.62,
            thinStreakOpacity: 0.84,
            lineChromaStrength: 0.22,
          ));
          // Layer 3: Subtle Light Scatter Mist
          _project.layers.add(AdjustmentLayer(
            id: 'yamato_scatter',
            name: 'Light Scatter',
            blendMode: LayerBlendMode.screen,
            opacity: 0.60,
            bslFogScatter: 0.38,
            bslaBloomHaze: 0.42,
            bslaFogDensity: 0.20,
            deepGlowIntensity: 0.22,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.50,
          ));
          break;

        case 'suguru':
          // Layer 1: Gritty Dark Crushed Contrast (Myroxz style)
          _project.layers.add(AdjustmentLayer(
            id: 'suguru_base',
            name: 'Base Grade',
            contrast: 1.46,
            saturation: 0.78,
            brightness: -0.03,
            temperature: 6400.0,
            sharpness: 0.52,
            shadows: -0.16,
            highlights: 0.18,
            blackCrush: 0.09,
            edgeDarken: 0.30,
            darkOutlines: 0.22,
            vignette: 0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.01, 0.15, 0.48, 0.86, 1.0],
          ));
          // Layer 2: Subtle Warm Blood Halation on Highlights
          _project.layers.add(AdjustmentLayer(
            id: 'suguru_halation',
            name: 'Halation',
            blendMode: LayerBlendMode.screen,
            opacity: 0.74,
            halationRadius: 0.28,
            halationWarmth: 0.82,
            filmGrain: 0.09,
            deepGlowIntensity: 0.38,
            deepGlowRadius: 0.46,
            deepGlowThreshold: 0.52,
            edgeGlowTint: 4.0,
          ));
          // Layer 3: Specular Aura
          _project.layers.add(AdjustmentLayer(
            id: 'suguru_aura',
            name: 'Curse Aura',
            blendMode: LayerBlendMode.screen,
            opacity: 0.70,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.62,
            deepGlowThreshold: 0.42,
            thinStreakIntensity: 0.20,
            thinStreakOpacity: 0.80,
          ));
          break;

        case 'home-made sauce':
          // Layer 1: Punchy Dynamic Range (Druko Maki vs Naoya style)
          _project.layers.add(AdjustmentLayer(
            id: 'sauce_base',
            name: 'Base Grade',
            contrast: 1.42,
            saturation: 0.88,
            temperature: 6800.0,
            sharpness: 0.64,
            shadows: -0.14,
            highlights: 0.20,
            blackCrush: 0.05,
            edgeDarken: 0.32,
            darkOutlines: 0.18,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.17, 0.48, 0.86, 1.0],
            flickerIntensity: 0.03,
            flickerSpeed: 10.0,
          ));
          // Layer 2: Anamorphic Horizontal Streak & Deep Glow
          _project.layers.add(AdjustmentLayer(
            id: 'sauce_streak',
            name: 'Anamorphic Streak',
            blendMode: LayerBlendMode.screen,
            opacity: 0.82,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.52,
            deepGlowThreshold: 0.45,
            edgeGlowTint: 1.0,
            thinStreakIntensity: 0.36,
            thinStreakWidth: 0.72,
            thinStreakOpacity: 0.88,
            lineChromaStrength: 0.28,
          ));
          // Layer 3: Organic Film Grain & Halation
          _project.layers.add(AdjustmentLayer(
            id: 'sauce_texture',
            name: 'Texture & Halation',
            blendMode: LayerBlendMode.screen,
            opacity: 0.68,
            halationRadius: 0.22,
            halationWarmth: 0.70,
            filmGrain: 0.10,
            bslaBloomHaze: 0.35,
            bslFogScatter: 0.30,
          ));
          break;

        case 'rin':
          // Layer 1: Neutral-Cold Elegance Base (Adevob Rin vs Saber style)
          _project.layers.add(AdjustmentLayer(
            id: 'rin_base',
            name: 'Base Grade',
            contrast: 1.38,
            saturation: 0.82,
            temperature: 7100.0,
            sharpness: 0.54,
            shadows: -0.15,
            highlights: 0.14,
            edgeDarken: 0.26,
            darkOutlines: 0.16,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.02, 0.16, 0.48, 0.84, 0.98],
          ));
          // Layer 2: Specular Ivory Bloom Glint
          _project.layers.add(AdjustmentLayer(
            id: 'rin_specular',
            name: 'Specular Glint',
            blendMode: LayerBlendMode.screen,
            opacity: 0.78,
            deepGlowIntensity: 0.40,
            deepGlowRadius: 0.46,
            deepGlowThreshold: 0.54,
            edgeGlowTint: 0.0,
            thinStreakIntensity: 0.22,
            thinStreakWidth: 0.58,
            thinStreakOpacity: 0.80,
          ));
          // Layer 3: Edge Chromatic Aberration & Soft Rolloff
          _project.layers.add(AdjustmentLayer(
            id: 'rin_chroma',
            name: 'Chroma Rolloff',
            blendMode: LayerBlendMode.screen,
            opacity: 0.64,
            lineChromaStrength: 0.32,
            bslaBloomHaze: 0.38,
            bslFogScatter: 0.28,
            deepGlowIntensity: 0.24,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.48,
          ));
          break;

        case 'sukuna':
          // Layer 1: Malevolent Shrine Deep Orange-Crimson Contrast
          _project.layers.add(AdjustmentLayer(
            id: 'sukuna_base',
            name: 'Base Grade',
            contrast: 1.46,
            saturation: 0.92,
            temperature: 6100.0,
            sharpness: 0.60,
            shadows: -0.18,
            highlights: 0.22,
            blackCrush: 0.08,
            edgeDarken: 0.34,
            darkOutlines: 0.22,
            vignette: 0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.15, 0.48, 0.88, 1.0],
            curveRed: [0.0, 0.18, 0.52, 0.90, 1.0],
          ));
          // Layer 2: Amber-Crimson Specular Flare
          _project.layers.add(AdjustmentLayer(
            id: 'sukuna_flare',
            name: 'Crimson Glow',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.56,
            deepGlowThreshold: 0.38,
            edgeGlowTint: 4.0,
            thinStreakIntensity: 0.34,
            thinStreakWidth: 0.72,
            thinStreakOpacity: 0.90,
            lineChromaStrength: 0.32,
          ));
          // Layer 3: Volcanic Halation
          _project.layers.add(AdjustmentLayer(
            id: 'sukuna_halation',
            name: 'Blood Halation',
            blendMode: LayerBlendMode.screen,
            opacity: 0.76,
            halationRadius: 0.28,
            halationWarmth: 0.88,
            filmGrain: 0.09,
          ));
          break;

        case 'toji':
          // Layer 1: Cold Steel & Razor Sharpening
          _project.layers.add(AdjustmentLayer(
            id: 'toji_base',
            name: 'Base Grade',
            contrast: 1.48,
            saturation: 0.64,
            temperature: 7500.0,
            sharpness: 0.70,
            shadows: -0.20,
            highlights: 0.15,
            blackCrush: 0.08,
            edgeDarken: 0.35,
            darkOutlines: 0.25,
            vignette: 0.07,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.01, 0.14, 0.46, 0.85, 0.99],
          ));
          // Layer 2: Silver Specular Edge
          _project.layers.add(AdjustmentLayer(
            id: 'toji_silver',
            name: 'Steel Specular',
            blendMode: LayerBlendMode.screen,
            opacity: 0.72,
            deepGlowIntensity: 0.36,
            deepGlowRadius: 0.44,
            deepGlowThreshold: 0.55,
            edgeGlowTint: 0.0,
            lineChromaStrength: 0.35,
          ));
          // Layer 3: Cold Fog Scatter
          _project.layers.add(AdjustmentLayer(
            id: 'toji_fog',
            name: 'Cold Scatter',
            blendMode: LayerBlendMode.screen,
            opacity: 0.60,
            bslFogScatter: 0.40,
            bslaBloomHaze: 0.35,
            bslaFogDensity: 0.22,
          ));
          break;

        case 'eren':
          // Layer 1: Gritty Volcanic Founding Grade
          _project.layers.add(AdjustmentLayer(
            id: 'eren_base',
            name: 'Base Grade',
            contrast: 1.44,
            saturation: 0.84,
            temperature: 6300.0,
            sharpness: 0.58,
            shadows: -0.16,
            highlights: 0.18,
            blackCrush: 0.07,
            edgeDarken: 0.30,
            darkOutlines: 0.18,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.16, 0.48, 0.86, 1.0],
          ));
          // Layer 2: Solar Amber Anamorphic Glint
          _project.layers.add(AdjustmentLayer(
            id: 'eren_amber',
            name: 'Amber Anamorphic',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.55,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 3.0,
            thinStreakIntensity: 0.32,
            thinStreakWidth: 0.68,
            thinStreakOpacity: 0.86,
          ));
          // Layer 3: Dust Atmosphere & Film Grain
          _project.layers.add(AdjustmentLayer(
            id: 'eren_dust',
            name: 'Dust Atmosphere',
            blendMode: LayerBlendMode.screen,
            opacity: 0.72,
            bslaBloomHaze: 0.52,
            bslaFogDensity: 0.30,
            bslFogScatter: 0.38,
            filmGrain: 0.11,
          ));
          break;

        case 'makima':
          // Layer 1: Velvet Pastel Control Base
          _project.layers.add(AdjustmentLayer(
            id: 'makima_base',
            name: 'Base Grade',
            contrast: 1.28,
            saturation: 0.90,
            temperature: 6500.0,
            sharpness: 0.46,
            shadows: -0.06,
            highlights: 0.12,
            edgeDarken: 0.20,
            darkOutlines: 0.10,
            vignette: 0.04,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.03, 0.20, 0.52, 0.84, 0.98],
          ));
          // Layer 2: Glowing Ivory-Rose Speculars
          _project.layers.add(AdjustmentLayer(
            id: 'makima_bloom',
            name: 'Velvet Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.76,
            deepGlowIntensity: 0.42,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.44,
            edgeGlowTint: 0.0,
            thinStreakIntensity: 0.18,
            thinStreakOpacity: 0.76,
          ));
          // Layer 3: Soft Halation Rolloff
          _project.layers.add(AdjustmentLayer(
            id: 'makima_soft',
            name: 'Soft Halation',
            blendMode: LayerBlendMode.screen,
            opacity: 0.66,
            halationRadius: 0.24,
            halationWarmth: 0.76,
            bslaBloomHaze: 0.44,
          ));
          break;

        // =====================================================================
        // PRESERVED BUILT-IN PRESETS (UNCHANGED AS REQUESTED)
        // =====================================================================
        case 'okkotsu':
          _project.layers.add(AdjustmentLayer(
            id: 'okkotsu_base',
            name: 'Base Grade',
            contrast: 1.28,
            saturation: 0.82,
            brightness: -0.02,
            temperature: 7200.0,
            sharpness: 0.48,
            shadows: -0.12,
            edgeDarken: 0.22,
            darkOutlines: 0.10,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.18, 0.48, 0.85, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'okkotsu_rim',
            name: 'Specular Rim',
            blendMode: LayerBlendMode.screen,
            opacity: 0.68,
            deepGlowIntensity: 0.32,
            deepGlowRadius: 0.45,
            deepGlowThreshold: 0.52,
            edgeGlowTint: 0.0,
            thinStreakIntensity: 0.15,
            thinStreakOpacity: 0.70,
          ));
          break;

        case 'tealdropped (conq knockoff)':
          _project.layers.add(AdjustmentLayer(
            id: 'conq_base',
            name: 'Base Grade',
            contrast: 1.18,
            saturation: 1.06,
            brightness: 0.03,
            temperature: 6800.0,
            sharpness: 0.44,
            shadows: 0.02,
            vignette: 0.04,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.25, 0.52, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'conq_glow',
            name: 'Teal Rim',
            blendMode: LayerBlendMode.screen,
            opacity: 0.82,
            deepGlowIntensity: 0.45,
            deepGlowRadius: 0.55,
            deepGlowThreshold: 0.44,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.22,
            thinStreakWidth: 0.60,
            thinStreakOpacity: 0.85,
            lineChromaStrength: 0.35,
          ));
          break;

        // =====================================================================
        // REVAMPED WIS PRESETS (MULTI-LAYER DEPTH)
        // =====================================================================
        case 'yuta':
          _project.layers.add(AdjustmentLayer(
            id: 'yuta_base',
            name: 'Base Grade',
            contrast: 1.40,
            saturation: 0.80,
            brightness: 0.01,
            temperature: 6400.0,
            sharpness: 0.56,
            shadows: -0.12,
            highlights: 0.18,
            blackCrush: 0.05,
            edgeDarken: 0.26,
            darkOutlines: 0.16,
            vignette: 0.04,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.17, 0.48, 0.85, 1.0],
            flickerIntensity: 0.035,
            flickerSpeed: 11.0,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'yuta_ivory_bloom',
            name: 'Ivory Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.76,
            deepGlowIntensity: 0.42,
            deepGlowRadius: 0.48,
            deepGlowThreshold: 0.50,
            edgeGlowTint: 1.0,
            thinStreakIntensity: 0.24,
            thinStreakOpacity: 0.80,
            lineChromaStrength: 0.24,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'yuta_atmo',
            name: 'Atmospheric Fog',
            blendMode: LayerBlendMode.screen,
            opacity: 0.60,
            bslaBloomHaze: 0.45,
            bslFogScatter: 0.32,
          ));
          break;

        case 'artoria':
          _project.layers.add(AdjustmentLayer(
            id: 'artoria_base',
            name: 'Base Grade',
            contrast: 1.38,
            saturation: 0.95,
            temperature: 6400.0,
            sharpness: 0.55,
            shadows: -0.14,
            highlights: 0.15,
            edgeDarken: 0.30,
            darkOutlines: 0.16,
            vignette: 0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.16, 0.49, 0.87, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'artoria_core',
            name: 'Gold Specular',
            blendMode: LayerBlendMode.screen,
            opacity: 0.84,
            deepGlowIntensity: 0.50,
            deepGlowRadius: 0.55,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 1.0,
            thinStreakIntensity: 0.32,
            thinStreakWidth: 0.64,
            thinStreakOpacity: 0.88,
            lineChromaStrength: 0.25,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'artoria_haze',
            name: 'Light Diffusion',
            blendMode: LayerBlendMode.screen,
            opacity: 0.62,
            bslaBloomHaze: 0.48,
            bslFogScatter: 0.35,
          ));
          break;

        case 'deku tree':
          _project.layers.add(AdjustmentLayer(
            id: 'deku_base',
            name: 'Base Grade',
            contrast: 1.32,
            saturation: 1.10,
            temperature: 6800.0,
            sharpness: 0.56,
            shadows: -0.08,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.85, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'deku_aura',
            name: 'Mint Flare',
            blendMode: LayerBlendMode.screen,
            opacity: 0.84,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.34,
            thinStreakWidth: 0.68,
            thinStreakOpacity: 0.88,
            lineChromaStrength: 0.35,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'deku_mist',
            name: 'Forest Mist',
            blendMode: LayerBlendMode.screen,
            opacity: 0.65,
            bslaBloomHaze: 0.50,
            bslFogScatter: 0.36,
          ));
          break;

        case 'raiden':
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_base',
            name: 'Base Grade',
            contrast: 1.36,
            saturation: 0.98,
            temperature: 7300.0,
            sharpness: 0.52,
            shadows: -0.16,
            edgeDarken: 0.28,
            darkOutlines: 0.15,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.16, 0.48, 0.85, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_violet',
            name: 'Electro Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.82,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 5.0,
            sapphireGlowWidth: 0.85,
            sapphireGlowThreshold: 0.42,
            thinStreakIntensity: 0.28,
            thinStreakOpacity: 0.86,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_atmo',
            name: 'Thunder Haze',
            blendMode: LayerBlendMode.screen,
            opacity: 0.62,
            bslaBloomHaze: 0.46,
            bslFogScatter: 0.34,
          ));
          break;

        case 'atmospheric haze':
          _project.layers.add(AdjustmentLayer(
            id: 'haze_base',
            name: 'Base Grade',
            contrast: 1.12,
            saturation: 0.88,
            temperature: 6500.0,
            brightness: 0.02,
            shadows: 0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.03, 0.26, 0.50, 0.80, 0.96],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'haze_overlay',
            name: 'White Mist',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            bslaFogDensity: 0.50,
            bslaFogDepth: 0.65,
            bslaBloomHaze: 0.60,
            bslFogScatter: 0.45,
            deepGlowIntensity: 0.35,
            deepGlowRadius: 0.70,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 0.0,
          ));
          break;

        case 'vintage cc':
          _project.layers.add(AdjustmentLayer(
            id: 'vint_base',
            name: 'Base Grade',
            contrast: 1.20,
            saturation: 0.82,
            temperature: 5900.0,
            shadows: 0.04,
            highlights: -0.04,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.03, 0.24, 0.49, 0.80, 0.96],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'vint_grain',
            name: 'Halation & Grain',
            blendMode: LayerBlendMode.screen,
            opacity: 0.76,
            deepGlowIntensity: 0.36,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.46,
            edgeGlowTint: 1.0,
            halationRadius: 0.25,
            halationWarmth: 0.80,
            filmGrain: 0.11,
          ));
          break;

        case 'noir':
          _project.layers.add(AdjustmentLayer(
            id: 'noir_base',
            name: 'Base Grade',
            contrast: 1.42,
            saturation: 0.15,
            temperature: 7500.0,
            shadows: -0.16,
            sharpness: 0.52,
            edgeDarken: 0.30,
            darkOutlines: 0.20,
            vignette: 0.07,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.01, 0.14, 0.47, 0.86, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'noir_specular',
            name: 'Silver Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.74,
            deepGlowIntensity: 0.42,
            deepGlowRadius: 0.50,
            deepGlowThreshold: 0.50,
            edgeGlowTint: 0.0,
            thinStreakIntensity: 0.18,
            thinStreakOpacity: 0.82,
          ));
          break;

        case 'choso':
          _project.layers.add(AdjustmentLayer(
            id: 'choso_base',
            name: 'Base Grade',
            contrast: 1.34,
            saturation: 0.94,
            temperature: 6300.0,
            sharpness: 0.50,
            shadows: -0.12,
            edgeDarken: 0.28,
            darkOutlines: 0.16,
            vignette: 0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.18, 0.49, 0.84, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'choso_blood',
            name: 'Blood Halation',
            blendMode: LayerBlendMode.screen,
            opacity: 0.84,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.56,
            deepGlowThreshold: 0.38,
            edgeGlowTint: 4.0,
            halationRadius: 0.28,
            halationWarmth: 0.88,
            thinStreakIntensity: 0.24,
            thinStreakOpacity: 0.88,
          ));
          break;

        case 'yoruichi':
          _project.layers.add(AdjustmentLayer(
            id: 'yoru_base',
            name: 'Base Grade',
            contrast: 1.32,
            saturation: 0.95,
            temperature: 7000.0,
            sharpness: 0.50,
            shadows: -0.10,
            vignette: 0.05,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.19, 0.49, 0.84, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'yoru_lightning',
            name: 'Electro Streak',
            blendMode: LayerBlendMode.screen,
            opacity: 0.84,
            deepGlowIntensity: 0.54,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 5.0,
            thinStreakIntensity: 0.32,
            thinStreakWidth: 0.68,
            thinStreakOpacity: 0.88,
            lineChromaStrength: 0.32,
          ));
          break;

        case 'gojo':
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_base',
            name: 'Base Grade',
            contrast: 1.28,
            saturation: 0.92,
            temperature: 7200.0,
            sharpness: 0.48,
            vignette: 0.04,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.83, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_bloom',
            name: 'Six Eyes Cyan Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.82,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.24,
            thinStreakOpacity: 0.86,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_haze',
            name: 'Infinity Haze',
            blendMode: LayerBlendMode.screen,
            opacity: 0.60,
            bslaBloomHaze: 0.44,
            bslFogScatter: 0.32,
          ));
          break;

        default:
          _project.layers.add(AdjustmentLayer(
            id: 'default_base',
            name: 'Base Grade',
            contrast: 1.15,
            saturation: 1.05,
            sharpness: 0.35,
            blendMode: LayerBlendMode.normal,
          ));
      }

      _project.activeLayerIndex = 0;
    });

    _applyGrade();
    _autoSaveProject();
  }

  Future<void> _saveCurrentAsPreset() async {
    final controller = TextEditingController(text: 'My Custom Grade');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Save Preset', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Preset Name', labelStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: gCustomAccentColor.value, foregroundColor: Colors.black),
            onPressed: () async {
              final name = controller.text.trim().isNotEmpty ? controller.text.trim() : 'My Custom Grade';
              Navigator.pop(ctx);

              final newPreset = CustomPresetItem(
                name: name,
                description: '${_project.layers.length} Layers',
                accentColor: gCustomAccentColor.value.value,
                isBuiltIn: false,
                layers: _project.layers.map((l) => l.clone()).toList(),
                tonemapMode: _project.tonemapMode,
              );

              _customPresets.add(newPreset);
              await ProjectManager.saveCustomPresets(_customPresets);
              setState(() {});

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Preset "$name" saved!'), backgroundColor: Colors.teal),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _importPresetFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);

        if (data.containsKey('layers')) {
          final List<dynamic> layerList = data['layers'];
          _pushUndoSnapshot();
          setState(() {
            _project.layers.clear();
            for (var l in layerList) {
              _project.layers.add(AdjustmentLayer.fromJson(l));
            }
            if (data.containsKey('tonemapMode')) {
              _project.tonemapMode = (data['tonemapMode'] as num).toDouble();
            }
            _project.activeLayerIndex = 0;
            _selectedPresetName = data['presetName'] ?? 'Imported Preset';
          });
          _applyGrade();
          _autoSaveProject();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Loaded preset "${_selectedPresetName}"'), backgroundColor: Colors.green));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid preset file: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _confirmDeleteCustomPreset(int index) {
    final item = _customPresets[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Preset?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Delete "${item.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _customPresets.removeAt(index);
              });
              await ProjectManager.saveCustomPresets(_customPresets);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preset deleted.')));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImportCubeLut() async {
    try {
      final file = await LutProcessor.pickCubeFile();
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No .cube file selected.'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final parsed = await LutProcessor.parseCubeFile(file);
      if (parsed != null) {
        final lut = LutModel(
          id: 'lut_${DateTime.now().millisecondsSinceEpoch}',
          name: parsed.title,
          filePath: file.path,
          size: parsed.size,
          table: parsed.table,
        );

        if (_activeLuts.length >= 4) {
          _activeLuts.removeAt(0);
        }
        _activeLuts.add(lut);
        await ProjectManager.saveLuts(_activeLuts);

        _pushUndoSnapshot();
        setState(() {
          _cur.activeLutId = lut.id;
          _cur.lutOpacity = 1.0;
        });
        _applyGrade();
        _autoSaveProject();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Applied "${lut.name}.cube"'), backgroundColor: Colors.teal),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse LUT: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteLut(int index) async {
    setState(() {
      final removed = _activeLuts.removeAt(index);
      if (_cur.activeLutId == removed.id) {
        _cur.activeLutId = null;
      }
    });
    await ProjectManager.saveLuts(_activeLuts);
    _applyGrade();
    _autoSaveProject();
  }

  void _showUnsharpMaskDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101016),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('UNSHARP MASK', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 14),
              _buildSliderRow('Amount', _cur.unsharpAmount, 0.0, 2.0, (v) {
                setModal(() => _cur.unsharpAmount = v);
                setState(() {});
              }),
              _buildSliderRow('Radius', _cur.unsharpRadius, 0.0, 5.0, (v) {
                setModal(() => _cur.unsharpRadius = v);
                setState(() {});
              }),
              _buildSliderRow('Threshold', _cur.unsharpThreshold, 0.0, 0.5, (v) {
                setModal(() => _cur.unsharpThreshold = v);
                setState(() {});
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showImageExportSheet() {
    String format = 'PNG';
    String resolution = '1080p';
    int quality = 95;
    final accent = gCustomAccentColor.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Export Image', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 14),
              const Text('FORMAT', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: ['PNG', 'JPG', 'WEBP'].map((fmt) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Center(child: Text(fmt)),
                      selected: format == fmt,
                      selectedColor: accent,
                      labelStyle: TextStyle(color: format == fmt ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                      onSelected: (_) => setSheet(() => format = fmt),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 14),
              const Text('RESOLUTION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: ['1080p', '2K', '4K'].map((res) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Center(child: Text(res)),
                      selected: resolution == res,
                      selectedColor: accent,
                      labelStyle: TextStyle(color: resolution == res ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                      onSelected: (_) => setSheet(() => resolution = res),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('QUALITY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('$quality%', style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: quality.toDouble(),
                min: 50,
                max: 100,
                activeColor: accent,
                onChanged: (v) => setSheet(() => quality = v.round()),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _exportStaticImageWithParams(format, resolution, quality);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('EXPORT $format ($resolution)', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportStaticImageWithParams(String format, String resolution, int quality) async {
    if (_cachedRawImage == null) return;
    try {
      final dims = _calculateTargetDimensions(resolution, _project.aspectRatio);
      final outW = dims['width']!;
      final outH = dims['height']!;

      final resized = img.copyResize(_cachedRawImage!, width: outW, height: outH);
      final rawInput = resized.getBytes(order: img.ChannelOrder.rgba);
      final uniforms = _packMultiLayerUniforms(outW.toDouble(), outH.toDouble());
      final lutTable = _getActiveLutTable();

      final outRaw = processImage(rawInput, outW, outH, outW, outH, uniforms, lutTable: lutTable);

      final gradedImg = img.Image.fromBytes(
        width: outW,
        height: outH,
        bytes: outRaw.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      Uint8List fileBytes;
      if (format == 'JPG') {
        fileBytes = Uint8List.fromList(img.encodeJpg(gradedImg, quality: quality));
      } else {
        fileBytes = Uint8List.fromList(img.encodePng(gradedImg));
      }

      final dir = await _getSafeMovieDirectory();
      final ext = format.toLowerCase();
      final dest = File('$dir/Shaderly_${resolution}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await dest.writeAsBytes(fileBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved image to:\n${dest.path}'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showExportSheet() {
    if (_project.isImage) {
      _showImageExportSheet();
      return;
    }

    String selectedContainer = 'MP4';
    String selectedCodec = 'H.264 (Hardware MediaCodec)';
    String selectedBitDepth = '8-bit';
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBitrate = '35 Mbps';
    String selectedAudioMode = 'Lossless Source Copy';

    final containers = ['MP4', 'WebM', 'MOV', 'MKV'];
    final resolutions = ['720p', '1080p', '2K', '4K'];
    final fpsOptions = ['24fps', '30fps', '60fps', '90fps'];
    final bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps', '80 Mbps', '120 Mbps', 'Lossless Variable'];

    final accent = gCustomAccentColor.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final targetDims = _calculateTargetDimensions(selectedRes, _project.aspectRatio);
            final availableCodecs = ExportMatrix.containerCodecs[selectedContainer] ?? ['H.264 (Hardware MediaCodec)'];

            if (!availableCodecs.contains(selectedCodec)) {
              selectedCodec = availableCodecs.first;
            }

            if (selectedCodec.contains('FFV1') || selectedCodec.contains('ProRes')) {
              selectedBitrate = 'Lossless Variable';
            } else if (selectedBitrate == 'Lossless Variable') {
              selectedBitrate = '35 Mbps';
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Render Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Text(
                      'Destination: /storage/emulated/0/Shaderly • ${targetDims['width']} x ${targetDims['height']}',
                      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    const Text('CONTAINER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: containers.map((c) => ChoiceChip(
                        label: Text(c),
                        selected: selectedContainer == c,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedContainer == c ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) {
                            setStateModal(() {
                              selectedContainer = c;
                              selectedCodec = (ExportMatrix.containerCodecs[c] ?? ['H.264 (Hardware MediaCodec)']).first;
                              if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
                                selectedBitDepth = '8-bit';
                              }
                            });
                          }
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('CODECS FOR $selectedContainer', style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: availableCodecs.map((codec) {
                        return ChoiceChip(
                          label: Text(codec),
                          selected: selectedCodec == codec,
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF18181E),
                          labelStyle: TextStyle(color: selectedCodec == codec ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (sel) {
                            if (sel) {
                              setStateModal(() {
                                selectedCodec = codec;
                                if (!ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, selectedBitDepth)) {
                                  selectedBitDepth = '8-bit';
                                }
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('BIT-DEPTH PRECISION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: ['8-bit', '10-bit', '16-bit'].map((depth) {
                        final isValid = ExportMatrix.isBitDepthValid(selectedContainer, selectedCodec, depth);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ChoiceChip(
                              label: Text(depth),
                              selected: selectedBitDepth == depth,
                              selectedColor: accent,
                              backgroundColor: isValid ? const Color(0xFF18181E) : Colors.black26,
                              labelStyle: TextStyle(
                                color: !isValid
                                    ? Colors.white24
                                    : (selectedBitDepth == depth ? Colors.black : Colors.white),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              onSelected: isValid ? (_) => setStateModal(() => selectedBitDepth = depth) : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('RESOLUTION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: resolutions.map((res) => ChoiceChip(
                        label: Text(res),
                        selected: selectedRes == res,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedRes == res ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedRes = res);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('FRAMERATE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: fpsOptions.map((fps) => ChoiceChip(
                        label: Text(fps),
                        selected: selectedFps == fps,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedFps == fps ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedFps = fps);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('TARGET BITRATE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: bitrateOptions.map((bit) {
                        final isValid = ExportMatrix.isBitrateValid(selectedCodec, bit);
                        return ChoiceChip(
                          label: Text(bit),
                          selected: selectedBitrate == bit,
                          selectedColor: accent,
                          backgroundColor: isValid ? const Color(0xFF18181E) : Colors.black26,
                          labelStyle: TextStyle(
                            color: !isValid
                                ? Colors.white24
                                : (selectedBitrate == bit ? Colors.black : Colors.white),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          onSelected: isValid ? (sel) {
                            if (sel) setStateModal(() => selectedBitrate = bit);
                          } : null,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('AUDIO PIPELINE', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Lossless Source Copy'),
                          selected: selectedAudioMode == 'Lossless Source Copy',
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF18181E),
                          labelStyle: TextStyle(color: selectedAudioMode == 'Lossless Source Copy' ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (_) => setStateModal(() => selectedAudioMode = 'Lossless Source Copy'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('AAC 320 kbps Studio'),
                          selected: selectedAudioMode == 'AAC 320 kbps Studio',
                          selectedColor: accent,
                          backgroundColor: const Color(0xFF18181E),
                          labelStyle: TextStyle(color: selectedAudioMode == 'AAC 320 kbps Studio' ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                          onSelected: (_) => setStateModal(() => selectedAudioMode = 'AAC 320 kbps Studio'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportVideo(
                            selectedRes,
                            selectedFps,
                            selectedBitrate,
                            selectedContainer,
                            selectedCodec,
                            selectedBitDepth,
                            selectedAudioMode,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'RENDER $selectedContainer (${selectedCodec.split(' ').first} • $selectedBitDepth)',
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String> _getSafeMovieDirectory() async {
    final shaderlyDir = Directory('/storage/emulated/0/Shaderly');
    if (!await shaderlyDir.exists()) {
      try {
        await shaderlyDir.create(recursive: true);
        return shaderlyDir.path;
      } catch (_) {}
    } else {
      return shaderlyDir.path;
    }

    final directDownload = Directory('/storage/emulated/0/Download');
    if (await directDownload.exists()) {
      return directDownload.path;
    }
    final docDir = await getApplicationDocumentsDirectory();
    return docDir.path;
  }

  Future<void> _exportVideo(
    String resolution,
    String fps,
    String bitrate,
    String container,
    String codec,
    String bitDepth,
    String audioMode,
  ) async {
    if (_project.mediaPath.isEmpty) return;

    final targetDims = _calculateTargetDimensions(resolution, _project.aspectRatio);
    final int outW = targetDims['width']!;
    final int outH = targetDims['height']!;
    final uniforms = _packMultiLayerUniforms(outW.toDouble(), outH.toDouble());
    final lutTable = _getActiveLutTable();

    int bitrateKbps = 35000;
    if (bitrate.contains('15')) bitrateKbps = 15000;
    else if (bitrate.contains('50')) bitrateKbps = 50000;
    else if (bitrate.contains('80')) bitrateKbps = 80000;
    else if (bitrate.contains('120')) bitrateKbps = 120000;

    int targetFps = int.parse(fps.replaceAll('fps', ''));
    String containerExt = container.toLowerCase();

    final bool is16Bit = bitDepth == '16-bit';
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Starting Master Extraction: 0%');

    _isExportCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101014),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Exporting $outW x $outH ($bitDepth)',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                tooltip: 'Cancel Export',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (confirmCtx) => AlertDialog(
                      backgroundColor: kCardDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: const Text('Cancel Video Export?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      content: const Text('Are you sure you want to cancel the render in progress? All processed frames will be discarded.', style: TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx),
                          child: const Text('Keep Rendering', style: TextStyle(color: Colors.white54)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () {
                            Navigator.pop(confirmCtx);
                            _isExportCancelled = true;
                            _activeExportSession?.cancel();
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Export cancelled by user.')),
                            );
                          },
                          child: const Text('Cancel Export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (_, progress, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: kCyanAccent,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (_, status, __) => Text(
                  status,
                  style: const TextStyle(color: kCyanAccent, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final dir = await getTemporaryDirectory();
      final videoPath = _project.mediaPath;
      final framesDir = Directory('${dir.path}/export_frames');
      final processedDir = Directory('${dir.path}/export_processed');

      if (await framesDir.exists()) await framesDir.delete(recursive: true);
      if (await processedDir.exists()) await processedDir.delete(recursive: true);
      await framesDir.create(recursive: true);
      await processedDir.create(recursive: true);

      final audioPath = '${dir.path}/current_audio.aac';
      final oldAudio = File(audioPath);
      if (await oldAudio.exists()) await oldAudio.delete();
      await FFmpegKit.execute('-hide_banner -i "$videoPath" -vn -c:a aac -y "$audioPath"');

      if (_isExportCancelled) return;

      statusNotifier.value = 'Extracting $outW x $outH frames...';
      final extractSession = await FFmpegKit.execute(
        '-hide_banner -i "$videoPath" -r $targetFps -s ${outW}x${outH} -pix_fmt rgba -y "${framesDir.path}/frame_%05d.png"',
      );

      if (_isExportCancelled) return;

      var frameFiles = await framesDir.list().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      final totalFrames = frameFiles.length;

      if (totalFrames == 0) {
        final logs = await extractSession.getLogsAsString();
        throw Exception('Frame extraction failed. Logs: ${logs ?? "No logs"}');
      }

      for (int i = 0; i < totalFrames; i++) {
        if (_isExportCancelled) return;

        final file = frameFiles[i];
        if (file is! File) continue;
        final bytes = await file.readAsBytes();
        final decoded = img.decodePng(bytes);
        if (decoded == null) continue;

        uniforms[0] = i / targetFps.toDouble();

        img.Image gradedImg;
        if (is16Bit) {
          final rawInput8 = decoded.getBytes(order: img.ChannelOrder.rgba);
          final rawInput16 = Uint16List(outW * outH * 4);
          for (int px = 0; px < rawInput8.length; px++) {
            rawInput16[px] = (rawInput8[px] << 8) | rawInput8[px];
          }
          final outputRaw16 = processImage16(rawInput16, outW, outH, outW, outH, uniforms, lutTable: lutTable);
          gradedImg = img.Image.fromBytes(
            width: outW,
            height: outH,
            bytes: outputRaw16.buffer,
            numChannels: 4,
            format: img.Format.uint16,
            order: img.ChannelOrder.rgba,
          );
        } else {
          final rawInput8 = decoded.getBytes(order: img.ChannelOrder.rgba);
          final outputRaw8 = processImage(rawInput8, outW, outH, outW, outH, uniforms, lutTable: lutTable);
          gradedImg = img.Image.fromBytes(
            width: outW,
            height: outH,
            bytes: outputRaw8.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba,
          );
        }

        final pngBytes = img.encodePng(gradedImg);
        final paddedIndex = (i + 1).toString().padLeft(5, '0');
        final outputFile = File('${processedDir.path}/frame_$paddedIndex.png');
        await outputFile.writeAsBytes(pngBytes);

        final percent = (((i + 1) / totalFrames) * 100).toInt();
        progressNotifier.value = (i + 1) / totalFrames;
        statusNotifier.value = 'Grading frames: $percent% (${i + 1}/$totalFrames)';

        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (_isExportCancelled) return;

      statusNotifier.value = 'Assembling final $container master...';
      final silentOutputPath = '${dir.path}/silent_video.$containerExt';
      final silentFile = File(silentOutputPath);
      if (await silentFile.exists()) await silentFile.delete();

      final encodeCmd = ExportMatrix.buildFFmpegEncodeCommand(
        fps: targetFps,
        framePattern: '${processedDir.path}/frame_%05d.png',
        container: container,
        codec: codec,
        bitDepth: bitDepth,
        bitrateKbps: bitrateKbps,
        outputPath: silentOutputPath,
      );
      final encodeSession = await FFmpegKit.execute(encodeCmd);

      if (_isExportCancelled) return;

      if (!await silentFile.exists()) {
        final logs = await encodeSession.getLogsAsString();
        throw Exception('Encoder failed: ${logs ?? "No logs"}');
      }

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length()) > 1000;
      final moviesDir = await _getSafeMovieDirectory();
      final cleanCodec = codec.split(' ').first;
      final fileName = 'Shaderly_${resolution}_${cleanCodec}_${bitDepth}_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      final finalOutputFile = File('$moviesDir/$fileName');

      if (hasAudio) {
        if (audioMode == 'Lossless Source Copy') {
          final audioCodec = ExportMatrix.getAudioCodec(container);
          await FFmpegKit.execute('-hide_banner -i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $audioCodec -shortest -y "${finalOutputFile.path}"');
        } else {
          await FFmpegKit.execute('-hide_banner -i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a aac -b:a 320k -shortest -y "${finalOutputFile.path}"');
        }
      } else {
        await File(silentOutputPath).copy(finalOutputFile.path);
      }

      if (!_isExportCancelled && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Master Saved to /storage/emulated/0/Shaderly:\n${finalOutputFile.path}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!_isExportCancelled && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildSliderRow(String title, double val, double min, double max, ValueChanged<double> onChanged) {
    final accent = gCustomAccentColor.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF14141C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    val.toStringAsFixed(2),
                    style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4.0,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white12,
                thumbColor: accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: val.clamp(min, max),
                min: min,
                max: max,
                onChanged: (newVal) {
                  setState(() => onChanged(newVal));
                  _applyGrade();
                },
                onChangeEnd: (_) {
                  _pushUndoSnapshot();
                  _autoSaveProject();
                  _applyGrade();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustmentLayerBar() {
    final accent = gCustomAccentColor.value;

    return Container(
      color: const Color(0xFF0D0D12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.add_box_rounded, color: accent, size: 22),
            tooltip: 'Add Adjustment Layer (Max 4)',
            onPressed: _addNewAdjustmentLayer,
          ),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _project.layers.length,
                onReorder: (oldIndex, newIndex) {
                  _pushUndoSnapshot();
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _project.layers.removeAt(oldIndex);
                    _project.layers.insert(newIndex, item);
                    _project.activeLayerIndex = newIndex;
                  });
                  _applyGrade();
                  _autoSaveProject();
                },
                itemBuilder: (context, idx) {
                  final l = _project.layers[idx];
                  final isSel = _project.activeLayerIndex == idx;
                  return GestureDetector(
                    key: ValueKey(l.id),
                    onTap: () => setState(() => _project.activeLayerIndex = idx),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel ? accent.withOpacity(0.18) : kCardDark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSel ? accent : Colors.white12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() => l.isEnabled = !l.isEnabled);
                                  _applyGrade();
                                },
                                child: Icon(
                                  l.isEnabled ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                  color: l.isEnabled ? (isSel ? accent : Colors.white70) : Colors.white24,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l.name,
                                style: TextStyle(
                                  color: isSel ? Colors.white : Colors.white60,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '#${idx + 1}',
                            style: TextStyle(
                              color: isSel ? accent : Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo_rounded, color: Colors.white70, size: 20),
            tooltip: 'Undo',
            onPressed: _performUndo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
            tooltip: 'Delete Current Layer',
            onPressed: _removeCurrentLayer,
          ),
        ],
      ),
    );
  }

  Widget _buildLayerSettingsHeader() {
    if (_project.layers.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFF14141A),
        child: const Text(
          'RAW PASSTHROUGH (0 LAYERS ACTIVE)',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
        ),
      );
    }

    final accent = gCustomAccentColor.value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF14141A),
      child: Row(
        children: [
          Text(
            _cur.name.toUpperCase(),
            style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8),
          ),
          const SizedBox(width: 12),
          DropdownButton<LayerBlendMode>(
            value: _cur.blendMode,
            dropdownColor: kCardDark,
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            items: const [
              DropdownMenuItem(value: LayerBlendMode.normal, child: Text('Normal')),
              DropdownMenuItem(value: LayerBlendMode.screen, child: Text('Screen (Glow)')),
              DropdownMenuItem(value: LayerBlendMode.linearAdd, child: Text('Linear Add')),
              DropdownMenuItem(value: LayerBlendMode.overlay, child: Text('Overlay')),
              DropdownMenuItem(value: LayerBlendMode.softLight, child: Text('Soft Light')),
              DropdownMenuItem(value: LayerBlendMode.multiply, child: Text('Multiply')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                _pushUndoSnapshot();
                setState(() => _cur.blendMode = mode);
                _applyGrade();
              }
            },
          ),
          const Spacer(),
          SizedBox(
            width: 110,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white12,
                thumbColor: accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              ),
              child: Slider(
                value: _cur.opacity,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  setState(() => _cur.opacity = v);
                  _applyGrade();
                },
                onChangeEnd: (_) => _pushUndoSnapshot(),
              ),
            ),
          ),
          Text('${(_cur.opacity * 100).toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildTimelineScrubber() {
    if (_project.isImage || _controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final accent = gCustomAccentColor.value;

    return Container(
      color: Colors.black45,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                if (_controller!.value.isPlaying) {
                  _controller!.pause();
                  _isPlaying = false;
                } else {
                  _controller!.play();
                  _isPlaying = true;
                }
              });
            },
            child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 8),
          Text(
            '${_currentTimelinePosition.toStringAsFixed(1)}s',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: _currentTimelinePosition.clamp(0.0, _videoDurationSeconds),
                min: 0.0,
                max: _videoDurationSeconds,
                onChanged: (val) {
                  setState(() => _currentTimelinePosition = val);
                  _controller?.seekTo(Duration(milliseconds: (val * 1000).toInt()));
                  _applyGrade();
                },
              ),
            ),
          ),
          Text(
            '${_videoDurationSeconds.toStringAsFixed(1)}s',
            style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildLutsTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('3D LUT', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _pickAndImportCubeLut,
              icon: const Icon(Icons.add_rounded, size: 16, color: Colors.black),
              label: const Text('IMPORT .CUBE', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (_cur.activeLutId != null) ...[
          _buildSliderRow('Active LUT Opacity', _cur.lutOpacity, 0.0, 1.0, (v) => setState(() => _cur.lutOpacity = v)),
          const SizedBox(height: 14),
        ],

        if (_activeLuts.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kCardDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: const Center(
              child: Text(
                'No .cube LUTs imported yet.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          )
        else
          ...List.generate(_activeLuts.length, (idx) {
            final lut = _activeLuts[idx];
            final isSel = _cur.activeLutId == lut.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSel ? accent.withOpacity(0.16) : kCardDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06), width: isSel ? 1.5 : 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSel ? accent : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '3D',
                        style: TextStyle(
                          color: isSel ? Colors.black : Colors.white54,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _pushUndoSnapshot();
                        setState(() {
                          _cur.activeLutId = isSel ? null : lut.id;
                        });
                        _applyGrade();
                        _autoSaveProject();
                      },
                      child: Text(lut.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                    tooltip: 'Delete LUT',
                    onPressed: () => _deleteLut(idx),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPresetsTab() {
    final accent = gCustomAccentColor.value;

    final builtInPresets = [
      {'name': 'Goku', 'color': 0xFFFFAB00},
      {'name': 'Desaturated', 'color': 0xFF90A4AE},
      {'name': 'Yamato', 'color': 0xFF00E5FF},
      {'name': 'Suguru', 'color': 0xFFB71C1C},
      {'name': 'Home-Made Sauce', 'color': 0xFFFF6F61},
      {'name': 'Rin', 'color': 0xFFE0E0E0},
      {'name': 'Sukuna', 'color': 0xFFFF1744},
      {'name': 'Toji', 'color': 0xFF78909C},
      {'name': 'Eren', 'color': 0xFFFF9100},
      {'name': 'Makima', 'color': 0xFFFFD1DC},
      {'name': 'Yuta', 'color': 0xFFE0E0E0},
      {'name': 'Okkotsu', 'color': 0xFF90A4AE},
      {'name': 'Artoria', 'color': 0xFFFFD700},
      {'name': 'Deku Tree', 'color': 0xFF00E676},
      {'name': 'Raiden', 'color': 0xFF7C4DFF},
      {'name': 'Atmospheric Haze', 'color': 0xFFB0BEC5},
      {'name': 'Tealdropped (conq knockoff)', 'color': 0xFF00E5FF},
      {'name': 'Vintage CC', 'color': 0xFFFFB74D},
      {'name': 'Noir', 'color': 0xFFB0BEC5},
      {'name': 'Choso', 'color': 0xFFB71C1C},
      {'name': 'Yoruichi', 'color': 0xFFAB47BC},
      {'name': 'Gojo', 'color': 0xFF00E5FF},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              onPressed: _saveCurrentAsPreset,
              icon: const Icon(Icons.bookmark_add_rounded, size: 16, color: Colors.black),
              label: const Text('SAVE CC', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _importPresetFromFile,
              icon: Icon(Icons.file_open_rounded, size: 16, color: accent),
              label: Text('IMPORT JSON/XML', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isBslaExtremeActive ? accent.withOpacity(0.18) : kCardDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _isBslaExtremeActive ? accent : Colors.white12, width: _isBslaExtremeActive ? 1.5 : 1.0),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _isBslaExtremeActive ? accent : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    Icons.cloud_queue_rounded,
                    color: _isBslaExtremeActive ? Colors.black : Colors.white70,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'BSLA Clean Atmospheric',
                  style: TextStyle(
                    color: _isBslaExtremeActive ? accent : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Switch(
                value: _isBslaExtremeActive,
                activeColor: accent,
                onChanged: (_) => _toggleBslaExtremePreset(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        if (_customPresets.isNotEmpty) ...[
          const Text('MY PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...List.generate(_customPresets.length, (index) {
            final custom = _customPresets[index];
            final isSel = _selectedPresetName == custom.name;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSel ? accent.withOpacity(0.16) : kCardDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06)),
              ),
              child: ListTile(
                title: Text(custom.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                  onPressed: () => _confirmDeleteCustomPreset(index),
                ),
                onTap: () {
                  _pushUndoSnapshot();
                  setState(() {
                    _project.layers = custom.layers.map((l) => l.clone()).toList();
                    _project.tonemapMode = custom.tonemapMode;
                    _project.activeLayerIndex = 0;
                    _selectedPresetName = custom.name;
                  });
                  _applyGrade();
                  _autoSaveProject();
                },
              ),
            );
          }),
          const SizedBox(height: 14),
        ],

        const Text('PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...builtInPresets.map((p) {
          final isSel = _selectedPresetName == p['name'];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? accent.withOpacity(0.16) : kCardDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSel ? accent : Colors.white.withOpacity(0.06)),
            ),
            child: ListTile(
              title: Text(p['name'] as String, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold)),
              trailing: isSel ? Icon(Icons.check_circle_rounded, color: accent, size: 18) : null,
              onTap: () => _applyPreset(p['name'] as String),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildBasicGradingTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        _buildSliderRow('Exposure', _cur.brightness, -0.8, 0.8, (v) => _cur.brightness = v),
        _buildSliderRow('Contrast', _cur.contrast, 0.2, 2.5, (v) => _cur.contrast = v),
        _buildSliderRow('Saturation', _cur.saturation, 0.0, 2.5, (v) => _cur.saturation = v),
        _buildSliderRow('Gamma', _cur.gamma, 0.2, 2.5, (v) => _cur.gamma = v),
        _buildSliderRow('Sharpness', _cur.sharpness, 0.0, 2.0, (v) => _cur.sharpness = v),
        _buildSliderRow('Temperature', _cur.temperature, 2000.0, 12000.0, (v) => _cur.temperature = v),
        _buildSliderRow('Highlights', _cur.highlights, -1.0, 1.0, (v) => _cur.highlights = v),
        _buildSliderRow('Shadows', _cur.shadows, -1.0, 1.0, (v) => _cur.shadows = v),
        _buildSliderRow('Black Crush', _cur.blackCrush, 0.0, 0.5, (v) => _cur.blackCrush = v),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('DYNAMICS & FLICKER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        _buildSliderRow('Flicker Intensity', _cur.flickerIntensity, 0.0, 1.0, (v) => _cur.flickerIntensity = v),
        _buildSliderRow('Flicker Frequency (Hz)', _cur.flickerSpeed, 1.0, 20.0, (v) => _cur.flickerSpeed = v),

        const SizedBox(height: 10),
        _buildSliderRow('Sobel Outlines', _cur.darkOutlines, 0.0, 1.0, (v) => _cur.darkOutlines = v),
        _buildSliderRow('Edge Darken', _cur.edgeDarken, 0.0, 1.0, (v) => _cur.edgeDarken = v),
        _buildSliderRow('Vignette', _cur.vignette, 0.0, 1.0, (v) => _cur.vignette = v),
        _buildSliderRow('Boxed Vignette', _cur.vignetteBoxed, 0.0, 1.0, (v) => _cur.vignetteBoxed = v),
      ],
    );
  }

  Widget _buildHslTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSliderRow('Hue Shift', _cur.hue, -3.14159, 3.14159, (v) => _cur.hue = v),
        _buildSliderRow('Teal / Orange Split', _cur.mblMojoTealOrange, 0.0, 1.5, (v) => _cur.mblMojoTealOrange = v),
      ],
    );
  }

  Widget _buildGlowsAndFlaresTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        _buildSliderRow('Deep Glow Intensity', _cur.deepGlowIntensity, 0.0, 2.0, (v) => _cur.deepGlowIntensity = v),
        _buildSliderRow('Deep Glow Radius', _cur.deepGlowRadius, 0.0, 2.0, (v) => _cur.deepGlowRadius = v),
        _buildSliderRow('Deep Glow Threshold', _cur.deepGlowThreshold, 0.0, 1.0, (v) => _cur.deepGlowThreshold = v),
        _buildSliderRow('Sapphire Glow Width', _cur.sapphireGlowWidth, 0.0, 2.0, (v) => _cur.sapphireGlowWidth = v),
        _buildSliderRow('Sapphire Threshold', _cur.sapphireGlowThreshold, 0.0, 1.0, (v) => _cur.sapphireGlowThreshold = v),

        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('GLOW TINT', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(10)),
          child: Wrap(
            spacing: 8,
            children: [
              {'id': 0.0, 'name': 'Natural White'},
              {'id': 1.0, 'name': 'Noble Gold'},
              {'id': 2.0, 'name': 'Cyan / Teal'},
              {'id': 3.0, 'name': 'Amber Sun'},
              {'id': 4.0, 'name': 'Blood Crimson'},
              {'id': 5.0, 'name': 'Electro Violet'},
            ].map((t) {
              final isSel = _cur.edgeGlowTint == t['id'];
              return ChoiceChip(
                label: Text(t['name'] as String),
                selected: isSel,
                selectedColor: accent,
                backgroundColor: const Color(0xFF1E1E28),
                labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                onSelected: (sel) {
                  if (sel) {
                    _pushUndoSnapshot();
                    setState(() => _cur.edgeGlowTint = t['id'] as double);
                    _applyGrade();
                  }
                },
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),
        _buildSliderRow('Streak Intensity', _cur.thinStreakIntensity, 0.0, 2.0, (v) => _cur.thinStreakIntensity = v),
        _buildSliderRow('Streak Width', _cur.thinStreakWidth, 0.0, 2.0, (v) => _cur.thinStreakWidth = v),
        _buildSliderRow('Streak Opacity', _cur.thinStreakOpacity, 0.0, 1.0, (v) => _cur.thinStreakOpacity = v),
        _buildSliderRow('Chromatic Aberration', _cur.lineChromaStrength, 0.0, 2.0, (v) => _cur.lineChromaStrength = v),
      ],
    );
  }

  Widget _buildAtmosphereTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        _buildSliderRow('Light Shafts', _cur.bslaGodRays, 0.0, 1.5, (v) => _cur.bslaGodRays = v),
        _buildSliderRow('Fog Density', _cur.bslaFogDensity, 0.0, 1.0, (v) => _cur.bslaFogDensity = v),
        _buildSliderRow('Fog Depth', _cur.bslaFogDepth, 0.0, 1.0, (v) => _cur.bslaFogDepth = v),
        _buildBloomHazeSlider(),
        _buildSliderRow('Light Scatter', _cur.bslFogScatter, 0.0, 1.5, (v) => _cur.bslFogScatter = v),

        const SizedBox(height: 8),
        _buildSliderRow('Halation Radius', _cur.halationRadius, 0.0, 1.5, (v) => _cur.halationRadius = v),
        _buildSliderRow('Halation Warmth', _cur.halationWarmth, 0.0, 1.5, (v) => _cur.halationWarmth = v),
        _buildSliderRow('Film Grain', _cur.filmGrain, 0.0, 1.0, (v) => _cur.filmGrain = v),
        _buildSliderRow('Denoise', _cur.denoise, 0.0, 1.0, (v) => _cur.denoise = v),
      ],
    );
  }

  Widget _buildBloomHazeSlider() {
    return _buildSliderRow('Bloom Haze', _cur.bslaBloomHaze, 0.0, 1.5, (v) => _cur.bslaBloomHaze = v);
  }

  Widget _buildTextEffectsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSliderRow('Bevel', _textBevel, 0.0, 1.0, (v) => setState(() => _textBevel = v)),
        _buildSliderRow('Light Sweep', _textLightSweep, 0.0, 1.0, (v) => setState(() => _textLightSweep = v)),
        _buildSliderRow('Horizon Ramp', _textHorizonRamp, 0.0, 1.0, (v) => setState(() => _textHorizonRamp = v)),
        _buildSliderRow('Inner Shadow', _textInnerShadow, 0.0, 1.0, (v) => setState(() => _textInnerShadow = v)),
        _buildSliderRow('Occlusion Rim', _textOcclusionRim, 0.0, 1.0, (v) => setState(() => _textOcclusionRim = v)),
        _buildSliderRow('Core Glow', _textTightCoreGlow, 0.0, 1.5, (v) => setState(() => _textTightCoreGlow = v)),
        _buildSliderRow('Center Aura', _textCenterAura, 0.0, 1.5, (v) => setState(() => _textCenterAura = v)),
      ],
    );
  }

  Widget _buildCurvesTab() {
    List<double> activeCurve;
    Color curveColor;

    switch (_selectedCurveChannel) {
      case 1:
        activeCurve = _cur.curveRed;
        curveColor = Colors.redAccent;
        break;
      case 2:
        activeCurve = _cur.curveGreen;
        curveColor = Colors.greenAccent;
        break;
      case 3:
        activeCurve = _cur.curveBlue;
        curveColor = Colors.blueAccent;
        break;
      default:
        activeCurve = _cur.curveMaster;
        curveColor = Colors.white;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            {'name': 'RGB', 'idx': 0, 'col': Colors.white},
            {'name': 'RED', 'idx': 1, 'col': Colors.redAccent},
            {'name': 'GREEN', 'idx': 2, 'col': Colors.greenAccent},
            {'name': 'BLUE', 'idx': 3, 'col': Colors.blueAccent},
          ].map((ch) {
            final isSel = _selectedCurveChannel == ch['idx'];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(ch['name'] as String),
                selected: isSel,
                selectedColor: ch['col'] as Color,
                backgroundColor: const Color(0xFF14141C),
                labelStyle: TextStyle(
                  color: isSel ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                onSelected: (sel) {
                  if (sel) setState(() => _selectedCurveChannel = ch['idx'] as int);
                },
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        Container(
          height: 220,
          decoration: BoxDecoration(
            color: const Color(0xFF0C0C12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: SplineCurvePainter(points: activeCurve, curveColor: curveColor),
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildSliderRow('Black Point (0.00)', activeCurve[0], 0.0, 1.0, (v) => activeCurve[0] = v),
        _buildSliderRow('Shadow Lift (0.25)', activeCurve[1], 0.0, 1.0, (v) => activeCurve[1] = v),
        _buildSliderRow('Midtone Gamma (0.50)', activeCurve[2], 0.0, 1.0, (v) => activeCurve[2] = v),
        _buildSliderRow('Highlight Rolloff (0.75)', activeCurve[3], 0.0, 1.0, (v) => activeCurve[3] = v),
        _buildSliderRow('White Clip (1.00)', activeCurve[4], 0.0, 1.0, (v) => activeCurve[4] = v),

        Center(
          child: TextButton.icon(
            onPressed: () {
              _pushUndoSnapshot();
              setState(() {
                for (int i = 0; i < 5; i++) {
                  activeCurve[i] = i * 0.25;
                }
              });
              _applyGrade();
              _autoSaveProject();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white38),
            label: const Text('Reset Curve', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildTonemappingTab() {
    final accent = gCustomAccentColor.value;

    final tonemappers = [
      {'id': 0.0, 'name': 'Linear (No Tonemap)'},
      {'id': 1.0, 'name': 'ACES Filmic (Compensated)'},
      {'id': 2.0, 'name': 'Reinhard Extended (Compensated)'},
      {'id': 3.0, 'name': 'AgX Natural'},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('TONEMAPPING (TRUE HDR ROLL-OFF)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        ...tonemappers.map((t) {
          final isSel = _project.tonemapMode == t['id'];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? accent.withOpacity(0.16) : kCardDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSel ? accent : Colors.white12),
            ),
            child: ListTile(
              title: Text(t['name'] as String, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              onTap: () {
                _pushUndoSnapshot();
                setState(() => _project.tonemapMode = t['id'] as double);
                _applyGrade();
                _autoSaveProject();
              },
            ),
          );
        }).toList(),

        const SizedBox(height: 16),
        const Text('SPLIT TONING', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        _buildSliderRow('Shadows Hue', _splitToneShadowH, 0.0, 1.0, (v) => setState(() => _splitToneShadowH = v)),
        _buildSliderRow('Shadows Saturation', _splitToneShadowS, 0.0, 1.0, (v) => setState(() => _splitToneShadowS = v)),
        _buildSliderRow('Highlights Hue', _splitToneHighH, 0.0, 1.0, (v) => setState(() => _splitToneHighH = v)),
        _buildSliderRow('Highlights Saturation', _splitToneHighS, 0.0, 1.0, (v) => setState(() => _splitToneHighS = v)),
        _buildSliderRow('Balance', _splitToneBalance, -1.0, 1.0, (v) => setState(() => _splitToneBalance = v)),

        const SizedBox(height: 16),
        const Text('DITHERING', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        _buildSliderRow('Dither Strength', _ditherStrength, 0.0, 2.0, (v) => setState(() => _ditherStrength = v)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;
    final bool hasMedia = _processedStaticImage != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: _isFullScreen
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0F0F14),
              elevation: 0,
              title: Row(
                children: [
                  Text(
                    'SHADERLY',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _project.aspectRatio,
                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.isImportedFromUpscaler) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.teal, width: 0.8),
                      ),
                      child: const Text(
                        'AI UPSCALED',
                        style: TextStyle(color: Colors.tealAccent, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.video_library_rounded, color: Colors.white70),
                  tooltip: 'Switch Video or Art',
                  onPressed: _switchMediaFile,
                ),
                IconButton(
                  icon: const Icon(Icons.undo_rounded, color: Colors.white70),
                  tooltip: 'Undo',
                  onPressed: _performUndo,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  tooltip: 'Reset Layer',
                  onPressed: _resetCurrentLayer,
                ),
                IconButton(
                  icon: Icon(Icons.filter_hdr_rounded, color: _cur.unsharpAmount > 0.01 ? accent : Colors.white70),
                  tooltip: 'Unsharp Mask',
                  onPressed: _showUnsharpMaskDrawer,
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, color: Colors.white),
                  tooltip: 'Render Master Video / Art',
                  onPressed: _showExportSheet,
                ),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: _isFullScreen ? 10 : 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _getAspectRatioValue(_project.aspectRatio),
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 100% PURE 32-BIT VULKAN COMPUTE OUTPUT (ZERO FLUTTER CPU FILTER FALLBACK)
                              if (hasMedia)
                                FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _renderWidth.toDouble(),
                                    height: _renderHeight.toDouble(),
                                    child: RawImage(image: _processedStaticImage),
                                  ),
                                )
                              else
                                const Center(
                                  child: CircularProgressIndicator(color: Colors.white38),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => setState(() => _isFullScreen = !_isFullScreen),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Icon(
                          _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (!_isFullScreen) ...[
              _buildTimelineScrubber(),
              _buildAdjustmentLayerBar(),
              _buildLayerSettingsHeader(),

              Container(
                color: const Color(0xFF0F0F14),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: accent,
                  labelColor: accent,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  tabs: const [
                    Tab(text: 'PRESETS'),
                    Tab(text: 'LUT'),
                    Tab(text: 'BASIC'),
                    Tab(text: 'HSL'),
                    Tab(text: 'GLOW / FLARE'),
                    Tab(text: 'ATMOSPHERE'),
                    Tab(text: 'TEXT FX'),
                    Tab(text: 'CURVES'),
                    Tab(text: 'TONEMAP'),
                  ],
                ),
              ),

              Expanded(
                flex: 5,
                child: Container(
                  color: const Color(0xFF0C0C10),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPresetsTab(),
                      _buildLutsTab(),
                      _buildBasicGradingTab(),
                      _buildHslTab(),
                      _buildGlowsAndFlaresTab(),
                      _buildAtmosphereTab(),
                      _buildTextEffectsTab(),
                      _buildCurvesTab(),
                      _buildTonemappingTab(),
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
}

class SplineCurvePainter extends CustomPainter {
  final List<double> points;
  final Color curveColor;

  SplineCurvePainter({required this.points, required this.curveColor});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.0;

    for (int i = 1; i < 4; i++) {
      double x = size.width * (i / 4.0);
      double y = size.height * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final linePaint = Paint()
      ..color = curveColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int px = 0; px <= size.width.toInt(); px++) {
      double normX = px / size.width;
      double normY = _evalCatmullRom(normX, points);
      double py = size.height - (normY * size.height);

      if (px == 0) {
        path.moveTo(px.toDouble(), py.clamp(0.0, size.height));
      } else {
        path.lineTo(px.toDouble(), py.clamp(0.0, size.height));
      }
    }
    canvas.drawPath(path, linePaint);

    final knotPaint = Paint()..color = curveColor;
    for (int i = 0; i < 5; i++) {
      double kx = size.width * (i / 4.0);
      double ky = size.height - (points[i] * size.height);
      canvas.drawCircle(Offset(kx, ky.clamp(0.0, size.height)), 5.0, knotPaint);
      canvas.drawCircle(Offset(kx, ky.clamp(0.0, size.height)), 2.5, Paint()..color = Colors.black);
    }
  }

  double _evalCatmullRom(double x, List<double> p) {
    x = x.clamp(0.0, 1.0);
    double seg = x * 4.0;
    int idx = seg.floor();
    if (idx >= 4) return p[4];
    double t = seg - idx;

    double p0 = (idx == 0) ? p[0] : (idx == 1) ? p[0] : (idx == 2) ? p[1] : p[2];
    double p1 = (idx == 0) ? p[0] : (idx == 1) ? p[1] : (idx == 2) ? p[2] : p[3];
    double p2 = (idx == 0) ? p[1] : (idx == 1) ? p[2] : (idx == 2) ? p[3] : p[4];
    double p3 = (idx == 0) ? p[2] : (idx == 1) ? p[3] : (idx == 2) ? p[4] : p[4];

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
  bool shouldRepaint(covariant SplineCurvePainter oldDelegate) => true;
}
