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

  // Ensure public /storage/emulated/0/Shadely directory exists
  try {
    final shadelyDir = Directory('/storage/emulated/0/Shadely');
    if (!await shadelyDir.exists()) {
      await shadelyDir.create(recursive: true);
    }
  } catch (_) {}

  runApp(const ShadelyApp());
}

class ShadelyApp extends StatelessWidget {
  const ShadelyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: gCustomAccentColor,
      builder: (context, accentColor, _) {
        return MaterialApp(
          title: 'Shadely',
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
          home: const HomeScreen(),
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
      setState(() => _recent = projs);
      _generateThumbnails(projs);
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

  void _deleteProject(int index) {
    final proj = _recent[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Session?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${proj.name}"? This cannot be undone.', style: const TextStyle(color: Colors.white70)),
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session deleted.')));
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
                Text('Choose Theme Accent Color', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
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
          return AlertDialog(
            backgroundColor: kCardDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: gCustomAccentColor.value, size: 20),
                const SizedBox(width: 8),
                const Text('App & Engine Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('THEME ACCENT COLOR', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showColorPickerModal();
                    },
                    icon: Icon(Icons.color_lens_rounded, color: gCustomAccentColor.value, size: 18),
                    label: const Text('COLOURS (40+ SOFT & HARD SHADES)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B1B24),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('TIMELINE PREVIEW QUALITY (FPS & LAG REDUCTION)', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('25% Draft (Zero Lag)'),
                        selected: gPreviewScale == 0.25,
                        selectedColor: gCustomAccentColor.value,
                        backgroundColor: const Color(0xFF1E1E28),
                        labelStyle: TextStyle(color: gPreviewScale == 0.25 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 0.25);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('50% Smooth'),
                        selected: gPreviewScale == 0.50,
                        selectedColor: gCustomAccentColor.value,
                        backgroundColor: const Color(0xFF1E1E28),
                        labelStyle: TextStyle(color: gPreviewScale == 0.50 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 0.50);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('75% High'),
                        selected: gPreviewScale == 0.75,
                        selectedColor: gCustomAccentColor.value,
                        backgroundColor: const Color(0xFF1E1E28),
                        labelStyle: TextStyle(color: gPreviewScale == 0.75 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 0.75);
                          setState(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('100% Native 32-Bit'),
                        selected: gPreviewScale == 1.0,
                        selectedColor: gCustomAccentColor.value,
                        backgroundColor: const Color(0xFF1E1E28),
                        labelStyle: TextStyle(color: gPreviewScale == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (_) {
                          setModal(() => gPreviewScale = 1.0);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: TextStyle(color: gCustomAccentColor.value, fontWeight: FontWeight.bold)),
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
            const Text('Shadely'),
          ],
        ),
        actions: [
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ADJUSTMENT LAYER COMPOSITOR • FP32 HDR',
                  style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    'SHADELY CORE',
                    style: TextStyle(color: accent, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Shadely', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Adjustment Layers, Physical Inverse-Square Bloom, Real Anamorphic Flares & 4K Master Pipeline.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())).then((_) => _load()),
                    icon: const Icon(Icons.add_rounded, color: Colors.black, size: 20),
                    label: const Text('NEW PROJECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (_recent.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProjectScreen(initialProject: _recent.first.data, projectName: _recent.first.name)),
                        ).then((_) => _load());
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved sessions yet.')));
                      }
                    },
                    icon: Icon(Icons.bookmarks_rounded, color: accent, size: 18),
                    label: Text('OPEN RECENT', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accent, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text('SAVED SESSIONS (WITH TIMELINE THUMBNAILS)', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
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
                    Text('No saved sessions found.', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Tap "NEW PROJECT" to grade high-res footage or art.', style: TextStyle(color: Colors.white24, fontSize: 11)),
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
                        subtitle: Text('${p.mediaPath.split('/').last} • ${p.data.layers.length} Layers • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
  String _projectName = 'Shadely Master';
  String _selectedAspect = '16:9';
  File? _selectedFile;
  bool _isImage = false;

  final List<String> _aspectRatios = ['16:9', '9:16', '4:5', '1:1', '3:4', '21:9'];

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
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'Shadely Master',
              controller: TextEditingController(text: _projectName),
            ),
            const SizedBox(height: 20),
            const Text('OUTPUT ASPECT RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _aspectRatios.map((ratio) => ChoiceChip(
                label: Text(ratio),
                selected: _selectedAspect == ratio,
                selectedColor: accent,
                backgroundColor: kCardDark,
                labelStyle: TextStyle(color: _selectedAspect == ratio ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                onSelected: (_) => setState(() => _selectedAspect = ratio),
              )).toList(),
            ),
            const SizedBox(height: 24),
            const Text('SOURCE FOOTAGE OR ART', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.any, // Uses safe extension check to prevent Android MIME crashes
                );
                if (result != null && result.files.single.path != null) {
                  final p = result.files.single.path!;
                  final ext = p.split('.').last.toLowerCase();
                  final validExts = ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp', 'cube'];
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
                      _selectedFile == null ? 'Browse video file or high-res image' : _selectedFile!.path.split('/').last,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedFile == null ? 'Supports MKV, WebM, MP4, MOV, Real-ESRGAN 2K/4K' : '${(_selectedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
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

  const ProjectScreen({super.key, this.initialProject, this.projectName});

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

  AdjustmentLayer get _cur => _project.currentLayer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
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

    // Force even dimensions required by H.264 / VP9 hardware encoders
    targetW = math.max(16, ((targetW + 1) ~/ 2) * 2);
    targetH = math.max(16, ((targetH + 1) ~/ 2) * 2);

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
          setState(() {});
          _controller!.play();
          _controller!.setLooping(true);
          _isPlaying = true;
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

  // Pure live grading: For images runs Vulkan; for video triggers direct GPU filter rebuild with ZERO ghost overlays
  Future<void> _applyGrade() async {
    if (_project.isImage && _cachedRawImage != null) {
      try {
        int w = _renderWidth;
        int h = _renderHeight;
        final resized = img.copyResize(_cachedRawImage!, width: w, height: h);
        final rawBytes = resized.getBytes(order: img.ChannelOrder.rgba);
        final uniforms = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
        final outBytes = processImage(rawBytes, w, h, w, h, uniforms);

        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(outBytes, w, h, ui.PixelFormat.rgba8888, (im) => completer.complete(im));
        final res = await completer.future;

        if (mounted) {
          setState(() {
            _processedStaticImage?.dispose();
            _processedStaticImage = res;
          });
        }
      } catch (_) {}
    } else {
      if (mounted) {
        setState(() {
          _processedStaticImage?.dispose();
          _processedStaticImage = null;
        });
      }
    }
  }

  // Real-time Color Matrix computed from active adjustment layers for the live moving video
  ColorFilter _buildLiveColorFilter() {
    double c = 1.0;
    double s = 1.0;
    double b = 0.0;
    double temp = 6500.0;
    double highLift = 0.0;
    double shadowLift = 0.0;
    double flickerFactor = 1.0;

    for (final l in _project.layers) {
      if (!l.isEnabled) continue;
      final op = l.opacity;
      c *= (1.0 + (l.contrast - 1.0) * op);
      s *= (1.0 + (l.saturation - 1.0) * op);
      b += l.brightness * 255.0 * op;

      // Strictly isolated Highlights vs. Shadows
      highLift += (l.highlights * 30.0 * op);
      shadowLift += (l.shadows * 30.0 * op);
      temp += (l.temperature - 6500.0) * op;

      if (l.flickerIntensity > 0.01) {
        double t = (_controller?.value.position.inMilliseconds ?? DateTime.now().millisecondsSinceEpoch) / 1000.0 * l.flickerSpeed;
        double fWave = (math.sin(t * 6.28318) * 0.5 + 0.5);
        flickerFactor *= (1.0 + (fWave - 0.5) * l.flickerIntensity * 0.45 * op);
      }
    }

    // White balance multiplier
    double rMult = 1.0;
    double bMult = 1.0;
    if (temp > 6500) {
      rMult += (temp - 6500) / 7000.0;
      bMult -= (temp - 6500) / 10000.0;
    } else {
      bMult += (6500 - temp) / 7000.0;
      rMult -= (6500 - temp) / 10000.0;
    }

    // Saturation matrix coefficients
    final double sr = (1 - s) * 0.2126;
    final double sg = (1 - s) * 0.7152;
    final double sb = (1 - s) * 0.0722;

    final double t = (1.0 - c) * 128.0;

    final List<double> matrix = [
      (sr + s) * c * rMult * flickerFactor, sg * c,           sb * c,           0, t + b + shadowLift + highLift,
      sr * c,               (sg + s) * c * flickerFactor,     sb * c,           0, t + b + shadowLift + highLift,
      sr * c,               sg * c,           (sb + s) * c * bMult * flickerFactor, 0, t + b + shadowLift + highLift,
      0,                    0,                0,                1, 0,
    ];

    return ColorFilter.matrix(matrix);
  }

  // Real-time bloom / glow / BSL fog layer rendered directly on top of the live video
  Widget _buildLiveBloomAtmosphere() {
    double totalBloom = 0.0;
    Color bloomTint = Colors.white;
    double flareOpacity = 0.0;
    double bslFogAmt = 0.0;
    double bslScatterAmt = 0.0;
    double bslDepthAmt = 0.5;

    for (final l in _project.layers) {
      if (!l.isEnabled) continue;
      final op = l.opacity;
      totalBloom += (l.deepGlowIntensity * 0.4 + l.bslaBloomHaze * 0.5) * op;
      flareOpacity += (l.thinStreakIntensity * l.thinStreakOpacity * 0.6) * op;

      if (l.bslaFogDensity > 0.001) {
        bslFogAmt += l.bslaFogDensity * op;
        bslScatterAmt += l.bslFogScatter * op;
        bslDepthAmt = l.bslaFogDepth;
      }

      if (l.edgeGlowTint == 1.0) bloomTint = const Color(0xFFFFD700);
      else if (l.edgeGlowTint == 2.0) bloomTint = const Color(0xFF00E5FF);
      else if (l.edgeGlowTint == 4.0) bloomTint = const Color(0xFFFF1744);
      else if (l.edgeGlowTint == 5.0) bloomTint = const Color(0xFF7C4DFF);
    }

    totalBloom = totalBloom.clamp(0.0, 0.85);
    flareOpacity = flareOpacity.clamp(0.0, 0.90);
    bslFogAmt = bslFogAmt.clamp(0.0, 0.85);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Deep Glow & S_Glow Core
          if (totalBloom > 0.02)
            Opacity(
              opacity: totalBloom,
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      bloomTint.withOpacity(0.45),
                      bloomTint.withOpacity(0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          // 2. Anamorphic Flare Streak
          if (flareOpacity > 0.02)
            Center(
              child: Opacity(
                opacity: flareOpacity,
                child: Container(
                  height: 3.5,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 3. Authentic BSL Volumetric Liminal Fog Overlay (Slate / Rain Mist)
          if (bslFogAmt > 0.01)
            Opacity(
              opacity: bslFogAmt,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, (1.0 - bslDepthAmt).clamp(0.1, 0.9), 1.0],
                    colors: [
                      const Color(0xFFB0BEC5).withOpacity(0.55 * (1.0 + bslScatterAmt * 0.4)),
                      const Color(0xFF90A4AE).withOpacity(0.40),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _autoSaveProject() async {
    if (_project.mediaPath.isEmpty) return;
    final proj = StoredProject(
      id: widget.projectName ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
      name: widget.projectName ?? 'Shadely Session',
      mediaPath: _project.mediaPath,
      data: _project,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(proj);
  }

  Float32List _packMultiLayerUniforms(double imgW, double imgH) {
    final uniforms = Float32List(256);
    final timeSeconds = (_controller != null && _controller!.value.isInitialized)
        ? _controller!.value.position.inMilliseconds / 1000.0
        : 0.0;

    uniforms[0] = timeSeconds;
    uniforms[1] = _project.layers.length.toDouble();
    uniforms[2] = _project.tonemapMode;
    uniforms[3] = imgW;
    uniforms[4] = imgH;
    uniforms[5] = 0.0;
    uniforms[6] = 0.0;
    uniforms[7] = 0.0;

    for (int l = 0; l < math.min(_project.layers.length, 4); l++) {
      final layer = _project.layers[l];
      final offset = 8 + (l * 55);

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
  
