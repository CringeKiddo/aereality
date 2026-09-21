// =============================================================================
// AEReality / Shaderly - Master Studio Interface (Part 1/2)
// True 32-Bit Float Linear Pipeline - Native Vulkan Compute Architecture
// 100% Complete File - Zero Code Omissions
// =============================================================================

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
import 'editor_views.dart';

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
    final downloadDir = Directory('/storage/emulated/0/Download');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
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
        _recent = projs.take(5).toList();
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
              '-hide_banner -ss 0.1 -noaccurate_seek -i "${p.mediaPath}" -vframes 1 -vf scale=160:-1 -q:v 4 -y "$outThumb"',
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E28),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withOpacity(0.3)),
                    ),
                    child: Text(
                      '32-Bit Floating Point (Locked Native)',
                      style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text('PREVIEW QUALITY (2K / 4K SHIELD)', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
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
                          Navigator.pop(ctx);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('50% Smooth'),
                        selected: gPreviewScale == 0.50,
                        selectedColor: accent,
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 0.50);
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('100% Native'),
                        selected: gPreviewScale == 1.0,
                        selectedColor: accent,
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 1.0);
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Text('TIMELINE CC PREVIEW MODE', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Grade Active Frame on Pause Only', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Saves GPU heat and battery when scrubbing long videos', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    value: gGradeActiveFrameOnly,
                    activeColor: accent,
                    onChanged: (val) {
                      setModal(() => gGradeActiveFrameOnly = val);
                      setState(() {});
                    },
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
                    label: const Text('YouTube (@cringekiddo)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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

            const SizedBox(height: 14),

            // BUTTON 2: OPEN RECENT PROJECT
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
            const Text('SAVED PROJECTS (UP TO 5 SLOTS)', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
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
                final result = await FilePicker.platform.pickFiles(type: FileType.any);
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
                      _selectedFile == null ? 'Supports true 2K, 4K, 1080p, 720p' : '${(_selectedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
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
                              opacity: 1.0, // <-- Explicit full opacity
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
// =============================================================================
// AEReality / Shaderly - Master Studio Interface (Part 2/2)
// True 32-Bit Float Linear Pipeline - Native Vulkan Compute Architecture
// 100% Complete File - Zero Code Omissions
// =============================================================================

class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  final String? projectName;

  const ProjectScreen({
    super.key,
    this.initialProject,
    this.projectName,
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
  bool _isBslOverlayActive = false;

  Timer? _playbackTimer;
  double _currentTimelinePosition = 0.0;
  double _videoDurationSeconds = 1.0;

  List<CustomPresetItem> _customPresets = [];
  List<LutModel> _activeLuts = [];

  bool _isVulkanProcessing = false;
  bool _needsReprocess = false;
  bool _isSavingProject = false;

  AdjustmentLayer get _cur => _project.currentLayer;

  @override
  void initState() {
    super.initState();
    // 10 Categories: PRESETS, TONEMAP, LUT, BASIC, MAGIC, COPIED STUFF, GLOW / FLARE, ATMOSPHERE, CURVES, TIMELINE
    _tabController = TabController(length: 10, vsync: this);
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

    targetW = math.max(16, ((targetW + 15) ~/ 16) * 16);
    targetH = math.max(16, ((targetH + 15) ~/ 16) * 16);

    return {'width': targetW, 'height': targetH};
  }

  void _updateDimensions(int srcW, int srcH) {
    final dims = _calculateTargetDimensions('720p', _project.aspectRatio, gPreviewScale);
    _renderWidth = math.min(1080, dims['width']!);
    _renderHeight = math.min(1920, dims['height']!);
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

          _controller!.pause();
          _isPlaying = false;

          setState(() {});
          _applyGrade();

          // Continuous Timeline Position Updater
          _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
            if (_controller != null && _controller!.value.isInitialized && _controller!.value.isPlaying && mounted) {
              final newPos = _controller!.value.position.inMilliseconds / 1000.0;
              if (newPos >= _videoDurationSeconds) {
                _controller!.seekTo(Duration.zero);
                _controller!.play();
              }
              setState(() {
                _currentTimelinePosition = newPos;
              });

              // If continuous grading is enabled in settings
              if (!gGradeActiveFrameOnly) {
                _applyGrade();
              }
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

        // INSTANT SEEK FIX: -ss placed before -i with -noaccurate_seek seeks in <50ms
        await FFmpegKit.execute(
          '-hide_banner -y -ss $_currentTimelinePosition -noaccurate_seek -i "${_project.mediaPath}" -vframes 1 -s ${w}x${h} "$framePath"',
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

  Future<void> _manualSaveProject() async {
    if (_project.mediaPath.isEmpty) return;
    setState(() => _isSavingProject = true);
    final proj = StoredProject(
      id: widget.projectName ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
      name: widget.projectName ?? 'Shaderly Session',
      mediaPath: _project.mediaPath,
      data: _project,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(proj);
    if (mounted) {
      setState(() => _isSavingProject = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project saved successfully (Synced to Home)'),
          backgroundColor: Colors.teal,
          duration: Duration(milliseconds: 1000),
        ),
      );
    }
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
    uniforms[7] = _cur.copiedChromaShift;
    uniforms[8] = _cur.copiedEdgeRays;
    uniforms[9] = _cur.copiedProMist;
    uniforms[10] = _cur.copiedStarGlint;
    uniforms[11] = _cur.horizontalRamp;
    uniforms[12] = _project.ditherStrength;

    // Offsets 13..19: Isolated Text Suite Uniforms
    uniforms[13] = _project.textSuiteEnabled ? 1.0 : 0.0;
    uniforms[14] = _project.textBoxX;
    uniforms[15] = _project.textBoxY;
    uniforms[16] = _project.textBoxW;
    uniforms[17] = _project.textBoxH;
    uniforms[18] = _project.textBevelDepth;
    uniforms[19] = _project.textChromeIntensity;

    // Offsets 20..27: New Shaderly Glow & Split Toning Global Uniforms (Matches GLSL UniformBlock)
    uniforms[20] = _cur.shaderlyGlowIntensity;
    uniforms[21] = _cur.shaderlyGlowRadius;
    uniforms[22] = _cur.shaderlyGlowThreshold;
    uniforms[23] = _cur.splitToneShadowHue;
    uniforms[24] = _cur.splitToneShadowSat;
    uniforms[25] = _cur.splitToneHighHue;
    uniforms[26] = _cur.splitToneHighSat;
    uniforms[27] = _cur.splitToneBalance;

    for (int l = 0; l < math.min(_project.layers.length, 4); l++) {
      final layer = _project.layers[l];
      // Offset 28 + (l * 64): Perfectly aligns with `LayerData layers[4]` in GLSL
      final offset = 28 + (l * 64);

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
        opacity: 1.0,
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
        opacity: 1.0,
        blendMode: _cur.blendMode,
      );
      _selectedPresetName = null;
    });
    _applyGrade();
    _autoSaveProject();
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

  // ---------------------------------------------------------------------------
  // TIMELINE SCRUBBER & LIVE PLAYBACK CONTROLLER
  // ---------------------------------------------------------------------------
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
                  _applyGrade();
                } else {
                  _controller!.play();
                  _isPlaying = true;
                }
              });
            },
            child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accent, size: 24),
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
                  setState(() {
                    _currentTimelinePosition = val;
                  });
                  _controller?.seekTo(Duration(milliseconds: (val * 1000).toInt()));
                },
                onChangeEnd: (val) {
                  _controller?.seekTo(Duration(milliseconds: (val * 1000).toInt())).then((_) {
                    _applyGrade();
                  });
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

  // ---------------------------------------------------------------------------
  // INTERACTIVE TEXT SUITE DRAGGABLE & RESIZABLE BOUNDING BOX OVERLAY
  // ---------------------------------------------------------------------------
  Widget _buildTextSuiteBoundingBoxOverlay(BoxConstraints constraints) {
    if (!_project.textSuiteEnabled) return const SizedBox.shrink();

    final accent = gCustomAccentColor.value;
    final parentW = constraints.maxWidth;
    final parentH = constraints.maxHeight;

    final left = _project.textBoxX * parentW;
    final top = _project.textBoxY * parentH;
    final width = _project.textBoxW * parentW;
    final height = _project.textBoxH * parentH;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Draggable Box Body
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _project.textBoxX = (_project.textBoxX + (details.delta.dx / parentW)).clamp(0.0, 1.0 - _project.textBoxW);
                _project.textBoxY = (_project.textBoxY + (details.delta.dy / parentH)).clamp(0.0, 1.0 - _project.textBoxH);
              });
              _applyGrade();
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 1.5),
                color: accent.withOpacity(0.08),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 2,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
                      child: Text(
                        'TEXT SUITE BOX',
                        style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom-Right Corner Resize Handle
          Positioned(
            right: -8,
            bottom: -8,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _project.textBoxW = (_project.textBoxW + (details.delta.dx / parentW)).clamp(0.08, 1.0 - _project.textBoxX);
                  _project.textBoxH = (_project.textBoxH + (details.delta.dy / parentH)).clamp(0.04, 1.0 - _project.textBoxY);
                });
                _applyGrade();
              },
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(Icons.open_in_full_rounded, size: 10, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
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
              // Back Button -> Quick Save Media Player Symbol -> Switch Media -> Controls
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                tooltip: 'Back to Home',
                onPressed: () => Navigator.pop(context),
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // BUTTON: QUICK-SAVE PROJECT (SINGLE MEDIA PLAYER SYMBOL)
                  IconButton(
                    icon: _isSavingProject
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(Icons.play_circle_fill_rounded, color: accent, size: 26),
                    tooltip: 'Quick-Save Project (Synced to Home)',
                    onPressed: _isSavingProject ? null : _manualSaveProject,
                  ),
                  const SizedBox(width: 4),
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
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.video_library_rounded, color: Colors.white70),
                  tooltip: 'Switch Media',
                  onPressed: _switchMediaFile,
                ),
                IconButton(
                  icon: Icon(
                    Icons.title_rounded,
                    color: _project.textSuiteEnabled ? accent : Colors.white70,
                  ),
                  tooltip: 'Text Suite Chrome Box',
                  onPressed: () {
                    _pushUndoSnapshot();
                    setState(() => _project.textSuiteEnabled = !_project.textSuiteEnabled);
                    _applyGrade();
                    _autoSaveProject();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_project.textSuiteEnabled
                            ? 'Text Suite Enabled: Drag the bounding box over your text'
                            : 'Text Suite Disabled'),
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  },
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
                  onPressed: () => EditorViews.showUnsharpMaskDrawer(context, _cur, () {
                    setState(() {});
                    _applyGrade();
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, color: Colors.white),
                  tooltip: 'Render Master Video / Art',
                  onPressed: () => EditorViews.showExportSheet(
                    context: context,
                    project: _project,
                    curLayer: _cur,
                    packUniforms: _packMultiLayerUniforms,
                    getActiveLut: _getActiveLutTable,
                  ),
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return ClipRect(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 1. Live Native Video Playing Surface
                                  if (!_project.isImage && _controller != null && _controller!.value.isInitialized)
                                    FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _controller!.value.size.width,
                                        height: _controller!.value.size.height,
                                        child: VideoPlayer(_controller!),
                                      ),
                                    ),

                                  // 2. Graded Vulkan Static Composite
                                  if (!_isPlaying && hasMedia)
                                    FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _renderWidth.toDouble(),
                                        height: _renderHeight.toDouble(),
                                        child: RawImage(image: _processedStaticImage),
                                      ),
                                    )
                                  else if (!_isPlaying && !hasMedia)
                                    const Center(
                                      child: CircularProgressIndicator(color: Colors.white38),
                                    ),

                                  // 3. Isolated Text Suite Draggable Box Overlay
                                  _buildTextSuiteBoundingBoxOverlay(constraints),
                                ],
                              ),
                            );
                          },
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
                    Tab(text: 'TONEMAPPERS'),
                    Tab(text: 'LUT'),
                    Tab(text: 'BASIC'),
                    Tab(text: 'MAGIC'),
                    Tab(text: 'COPIED STUFF'),
                    Tab(text: 'GLOW / FLARE'),
                    Tab(text: 'ATMOSPHERE'),
                    Tab(text: 'CURVES'),
                    Tab(text: 'TIMELINE'),
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
                      EditorViews.buildPresetsTab(
                        context: context,
                        project: _project,
                        customPresets: _customPresets,
                        selectedPresetName: _selectedPresetName,
                        isBslOverlayActive: _isBslOverlayActive,
                        onToggleBslOverlay: () {
                          _pushUndoSnapshot();
                          setState(() {
                            _isBslOverlayActive = !_isBslOverlayActive;
                            EditorViews.applyBslOverlay(project: _project, active: _isBslOverlayActive);
                          });
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onPresetSelected: (presetName) {
                          _pushUndoSnapshot();
                          setState(() {
                            if (_selectedPresetName == presetName) {
                              _selectedPresetName = null;
                              EditorViews.clearPresetToNeutral(_project);
                            } else {
                              _selectedPresetName = presetName;
                              EditorViews.applyPresetLogic(_project, presetName);
                              if (_isBslOverlayActive) {
                                EditorViews.applyBslOverlay(project: _project, active: true);
                              }
                            }
                          });
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onSavePreset: () async {
                          await EditorViews.saveCurrentAsPreset(context, _project, _customPresets);
                          setState(() {});
                        },
                        onImportPreset: () async {
                          await EditorViews.importPresetFromFile(context, _project);
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onDeleteCustomPreset: (index) async {
                          setState(() => _customPresets.removeAt(index));
                          await ProjectManager.saveCustomPresets(_customPresets);
                        },
                      ),
                      EditorViews.buildTonemappersTab(
                        context: context,
                        project: _project,
                        onChanged: () {
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                      ),
                      EditorViews.buildLutsTab(
                        context: context,
                        cur: _cur,
                        activeLuts: _activeLuts,
                        onLutUpdated: () {
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onPickLut: () async {
                          await EditorViews.pickAndImportCubeLut(context, _cur, _activeLuts);
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onDeleteLut: (idx) async {
                          setState(() {
                            final rem = _activeLuts.removeAt(idx);
                            if (_cur.activeLutId == rem.id) _cur.activeLutId = null;
                          });
                          await ProjectManager.saveLuts(_activeLuts);
                          _applyGrade();
                          _autoSaveProject();
                        },
                      ),
                      EditorViews.buildBasicGradingTab(
                        context: context,
                        cur: _cur,
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                        onEnded: () {
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildMagicTab(
                        context: context,
                        cur: _cur,
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                        onEnded: () {
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildCopiedStuffTab(
                        context: context,
                        cur: _cur,
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                        onEnded: () {
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildGlowsAndFlaresTab(
                        context: context,
                        cur: _cur,
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                        onEnded: () {
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildAtmosphereTab(
                        context: context,
                        cur: _cur,
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                        onEnded: () {
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildCurvesTab(
                        context: context,
                        cur: _cur,
                        selectedCurveChannel: _selectedCurveChannel,
                        onChannelChanged: (ch) => setState(() => _selectedCurveChannel = ch),
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                        onResetCurve: () {
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                      ),
                      EditorViews.buildTimelineOptimizerTab(
                        context: context,
                        project: _project,
                        videoDuration: _videoDurationSeconds,
                        currentPosition: _currentTimelinePosition,
                        onChanged: () {
                          setState(() {});
                          _applyGrade();
                        },
                      ),
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
