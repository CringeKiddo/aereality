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

  // Ensure public /storage/emulated/0/Shaderly directory exists
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
          // Wrapped with Cyan + Lavender touch particle emitter for smooth slides & touches
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
            content: Text('✅ Cache Cleared: ${mbFreed.toStringAsFixed(1)} MB freed!'),
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

                  const Text('DEVELOPER & COMMUNITY', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: kMyYouTubeChannel));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('YouTube channel link copied to clipboard: @null7839'), backgroundColor: Colors.redAccent),
                      );
                    },
                    icon: const Icon(Icons.smart_display_rounded, color: Colors.redAccent, size: 18),
                    label: const Text('COPY MY YOUTUBE CHANNEL LINK (@null7839)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E1418),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text('ABOUT & LICENSING', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shaderly HDR Studio v3.5', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        SizedBox(height: 4),
                        Text(
                          'Powered by Vulkan FP32 compute pipelines, Real-ESRGAN neural super-resolution (BSD 3-Clause), and FFmpeg Kit multimedia engines.',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
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
            const Text('Shaderly'),
          ],
        ),
        actions: [
          // CLEAR CACHE BUTTON IN MAIN MENU
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
                    'SHADERLY CORE',
                    style: TextStyle(color: accent, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Shaderly', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Adjustment Layers, Physical Inverse-Square Bloom, Real Anamorphic Flares & 4K Master Pipeline.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // BUTTON 1: NEW PROJECT WITH GLOWING PERIMETER EDGE
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

            // BUTTON 2: SHADERLY AI UPSCALER WITH GLOWING PERIMETER EDGE
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
                label: const Text('SHADERLY AI UPSCALER (2X / 4X)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
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

            // BUTTON 3: REELSMART MOTION BLUR STUDIO
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RsmbScreen())),
                icon: Icon(Icons.blur_linear_rounded, color: accent, size: 18),
                label: Text('REELSMART MOTION BLUR STUDIO', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accent.withOpacity(0.6), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // RECENT SESSION OPENER
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved sessions yet.')));
                  }
                },
                icon: Icon(Icons.bookmarks_rounded, color: accent, size: 18),
                label: Text('OPEN MOST RECENT SESSION', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accent.withOpacity(0.4), width: 1.0),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 24),
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
  String _projectName = 'Shaderly Master';
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
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'Shaderly Master',
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
                  type: FileType.any,
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

  // Export cancellation reference
  FFmpegSession? _activeExportSession;
  bool _isExportCancelled = false;

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

      highLift += (l.highlights * 30.0 * op);
      shadowLift += (l.shadows * 30.0 * op);
      temp += (l.temperature - 6500.0) * op;

      if (l.flickerIntensity > 0.01) {
        double t = (_controller?.value.position.inMilliseconds ?? DateTime.now().millisecondsSinceEpoch) / 1000.0 * l.flickerSpeed;
        double fWave = (math.sin(t * 6.28318) * 0.5 + 0.5);
        flickerFactor *= (1.0 + (fWave - 0.5) * l.flickerIntensity * 0.45 * op);
      }
    }

    double rMult = 1.0;
    double bMult = 1.0;
    if (temp > 6500) {
      rMult += (temp - 6500) / 7000.0;
      bMult -= (temp - 6500) / 10000.0;
    } else {
      bMult += (6500 - temp) / 7000.0;
      rMult -= (6500 - temp) / 10000.0;
    }

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
      name: widget.projectName ?? 'Shaderly Session',
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
          name: 'BSLA Extreme Atmospheric',
          blendMode: LayerBlendMode.screen,
          opacity: 0.90,
          bslaGodRays: 0.75,
          bslaFogDensity: 0.65,
          bslaFogDepth: 0.70,
          bslaBloomHaze: 0.85,
          bslFogScatter: 0.45,
          deepGlowIntensity: 0.60,
          deepGlowRadius: 0.75,
          deepGlowThreshold: 0.35,
          edgeGlowTint: 1.0,
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

      switch (name) {
        case 'tealdropped (conq knockoff)':
          _project.layers.add(AdjustmentLayer(
            id: 'conq_base',
            name: 'Base Grade',
            contrast: 1.16,
            saturation: 1.04,
            brightness: 0.04,
            temperature: 6800.0,
            sharpness: 0.40,
            shadows: 0.02,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.25, 0.52, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'conq_glow',
            name: 'Teal Rim Flare',
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

        case 'vintage cc':
          _project.layers.add(AdjustmentLayer(
            id: 'vint_base',
            name: 'Warm Film Stock',
            contrast: 1.15,
            saturation: 0.88,
            temperature: 5600.0,
            shadows: 0.08,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.05, 0.26, 0.50, 0.78, 0.95],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'vint_grain',
            name: 'Halation & Soft Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.75,
            deepGlowIntensity: 0.35,
            deepGlowRadius: 0.65,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 1.0,
            halationRadius: 0.25,
            halationWarmth: 0.85,
            filmGrain: 0.10,
          ));
          break;

        case 'noir':
          _project.layers.add(AdjustmentLayer(
            id: 'noir_base',
            name: 'Deep Ink & Silver',
            contrast: 1.35,
            saturation: 0.12,
            temperature: 7200.0,
            shadows: -0.15,
            sharpness: 0.42,
            edgeDarken: 0.30,
            darkOutlines: 0.25,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.16, 0.48, 0.84, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'noir_specular',
            name: 'Silver Specular Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.70,
            deepGlowIntensity: 0.42,
            deepGlowRadius: 0.50,
            deepGlowThreshold: 0.48,
            edgeGlowTint: 0.0,
            thinStreakIntensity: 0.15,
            thinStreakOpacity: 0.80,
          ));
          break;

        case 'choso':
          _project.layers.add(AdjustmentLayer(
            id: 'choso_base',
            name: 'Piercing Blood Midtones',
            contrast: 1.25,
            saturation: 1.15,
            temperature: 6100.0,
            sharpness: 0.36,
            shadows: -0.08,
            edgeDarken: 0.25,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'choso_blood',
            name: 'Dark Blood Halation',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.38,
            edgeGlowTint: 4.0,
            halationRadius: 0.28,
            halationWarmth: 0.90,
            thinStreakIntensity: 0.20,
            thinStreakOpacity: 0.85,
          ));
          break;

        case 'yoruichi':
          _project.layers.add(AdjustmentLayer(
            id: 'yoru_base',
            name: 'Flash Step Contrast',
            contrast: 1.24,
            saturation: 1.12,
            temperature: 6800.0,
            sharpness: 0.38,
            shadows: -0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.21, 0.50, 0.83, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'yoru_lightning',
            name: 'Electro Violet Streak',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.58,
            deepGlowRadius: 0.65,
            deepGlowThreshold: 0.36,
            edgeGlowTint: 5.0,
            thinStreakIntensity: 0.35,
            thinStreakWidth: 0.70,
            thinStreakOpacity: 0.90,
            lineChromaStrength: 0.35,
          ));
          break;

        case 'Gojo':
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_base',
            name: 'Infinity Base',
            contrast: 1.18,
            saturation: 1.08,
            temperature: 7000.0,
            sharpness: 0.30,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.22, 0.50, 0.81, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_bloom',
            name: 'Infinity Cyan Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.82,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.62,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.20,
            thinStreakOpacity: 0.85,
          ));
          break;

        case 'Raiden':
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_base',
            name: 'Base Grade',
            contrast: 1.20,
            saturation: 1.10,
            temperature: 6700.0,
            sharpness: 0.30,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_glow',
            name: 'Electro Violet Glow',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 5.0,
          ));
          break;

        case 'bina':
          _project.layers.add(AdjustmentLayer(
            id: 'bina_base',
            name: 'Base Grade',
            contrast: 1.10,
            saturation: 1.06,
            brightness: 0.02,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'bina_glow',
            name: 'Pastel Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.75,
            deepGlowIntensity: 0.45,
            deepGlowRadius: 0.65,
            deepGlowThreshold: 0.38,
          ));
          break;

        case 'potential, man.':
          _project.layers.add(AdjustmentLayer(
            id: 'pot_base',
            name: 'Base Grade',
            contrast: 1.22,
            saturation: 1.04,
            sharpness: 0.32,
            edgeDarken: 0.20,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'pot_glow',
            name: 'Specular Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.70,
            deepGlowIntensity: 0.36,
            deepGlowRadius: 0.48,
            deepGlowThreshold: 0.48,
          ));
          break;

        case 'potential 2.0':
          _project.layers.add(AdjustmentLayer(
            id: 'pot2_base',
            name: 'Base Grade',
            contrast: 1.24,
            saturation: 1.12,
            sharpness: 0.30,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'pot2_rays',
            name: 'Mahoraga Rays',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.50,
            deepGlowRadius: 0.65,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 1.0,
            volRaysLength: 0.22,
          ));
          break;

        case 'saber':
          _project.layers.add(AdjustmentLayer(
            id: 'saber_base',
            name: 'Base Grade',
            contrast: 1.20,
            saturation: 1.12,
            temperature: 6600.0,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'saber_glow',
            name: 'Golden Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.82,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.68,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 1.0,
            thinStreakIntensity: 0.20,
            thinStreakOpacity: 0.85,
          ));
          break;

        case 'sasuke':
          _project.layers.add(AdjustmentLayer(
            id: 'sasuke_base',
            name: 'Base Grade',
            contrast: 1.25,
            saturation: 1.06,
            temperature: 6900.0,
            sharpness: 0.36,
            edgeDarken: 0.25,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'sasuke_flare',
            name: 'Chidori Flare',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.55,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.35,
            thinStreakWidth: 0.65,
            thinStreakOpacity: 0.90,
          ));
          break;

        case 'toji':
          _project.layers.add(AdjustmentLayer(
            id: 'toji_base',
            name: 'Base Grade',
            contrast: 1.30,
            saturation: 1.00,
            temperature: 6200.0,
            sharpness: 0.40,
            shadows: -0.12,
            edgeDarken: 0.30,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'toji_spec',
            name: 'Specular Sheen',
            blendMode: LayerBlendMode.screen,
            opacity: 0.65,
            deepGlowIntensity: 0.32,
            deepGlowRadius: 0.42,
            deepGlowThreshold: 0.50,
          ));
          break;

        case 'shiki':
          _project.layers.add(AdjustmentLayer(
            id: 'shiki_base',
            name: 'Base Grade',
            contrast: 1.26,
            saturation: 1.10,
            temperature: 6700.0,
            sharpness: 0.38,
            blendMode: LayerBlendMode.normal,
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'shiki_glow',
            name: 'Death Perception Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.20,
            thinStreakOpacity: 0.85,
          ));
          break;
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
        title: const Text('Save Current CC as Preset', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                description: '${_project.layers.length} Layers • Custom Saved CC',
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
                  SnackBar(content: Text('Preset "$name" saved to Presets tab!'), backgroundColor: Colors.teal),
                );
              }
            },
            child: const Text('Save Preset'),
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Loaded preset "${_selectedPresetName}"!'), backgroundColor: Colors.green));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please choose a valid JSON/XML preset file ($e)'), backgroundColor: Colors.red));
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
        title: const Text('Confirm Deletion', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete preset "${item.name}"?', style: const TextStyle(color: Colors.white70)),
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
            SnackBar(content: Text('Imported and Applied "${lut.name}.cube" (32x32x32)'), backgroundColor: Colors.teal),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse .cube file: $e'), backgroundColor: Colors.red),
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
                  const Text('UNSHARP MASK CONTROLS', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 14),
              _buildSliderRow('Unsharp Amount', _cur.unsharpAmount, 0.0, 2.0, (v) {
                setModal(() => _cur.unsharpAmount = v);
                setState(() {});
              }),
              _buildSliderRow('Unsharp Radius', _cur.unsharpRadius, 0.0, 5.0, (v) {
                setModal(() => _cur.unsharpRadius = v);
                setState(() {});
              }),
              _buildSliderRow('Threshold (Luma Floor)', _cur.unsharpThreshold, 0.0, 0.5, (v) {
                setModal(() => _cur.unsharpThreshold = v);
                setState(() {});
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportSheet() {
    if (_project.isImage) {
      _exportStaticImage();
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
                        const Text('Master Render Pipeline', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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

                    const Text('RESOLUTION (UP TO 4K MASTER)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
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

  Future<void> _exportStaticImage() async {
    if (_cachedRawImage == null || _project.mediaPath.isEmpty) return;
    try {
      final dims = _calculateTargetDimensions('1080p', _project.aspectRatio);
      final exportWidth = dims['width']!;
      final exportHeight = dims['height']!;

      final resized = img.copyResize(_cachedRawImage!, width: exportWidth, height: exportHeight);
      final rawInput = resized.getBytes(order: img.ChannelOrder.rgba);
      final uniforms = _packMultiLayerUniforms(exportWidth.toDouble(), exportHeight.toDouble());

      final outputRaw = processImage(
        rawInput,
        exportWidth,
        exportHeight,
        exportWidth,
        exportHeight,
        uniforms,
      );

      final gradedImg = img.Image.fromBytes(
        width: exportWidth,
        height: exportHeight,
        bytes: outputRaw.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      final pngBytes = img.encodePng(gradedImg);
      final folderPath = await _getSafeMovieDirectory();
      final fileName = 'Shaderly_Graded_${DateTime.now().millisecondsSinceEpoch}.png';
      final destFile = File('$folderPath/$fileName');
      await destFile.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Graded Image Saved to:\n${destFile.path}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image Export Error: $e'), backgroundColor: Colors.red));
      }
    }
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

    int bitrateKbps = 35000;
    if (bitrate.contains('15')) bitrateKbps = 15000;
    else if (bitrate.contains('50')) bitrateKbps = 50000;
    else if (bitrate.contains('80')) bitrateKbps = 80000;
    else if (bitrate.contains('120')) bitrateKbps = 120000;

    int targetFps = int.parse(fps.replaceAll('fps', ''));
    String containerExt = container.toLowerCase();

    final bool is16Bit = bitDepth == '16-bit';
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Starting 4K Master Extraction: 0%');

    _isExportCancelled = false;

    // Export Dialog with "X" Cancel Button + Confirmation
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
                            if (_activeExportSession != null) {
                              FFmpegKit.cancel(_activeExportSession!);
                            } else {
                              FFmpegKit.cancel();
                            }
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

      // Demux audio stream
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
          final outputRaw16 = processImage16(rawInput16, outW, outH, outW, outH, uniforms);
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
          final outputRaw8 = processImage(rawInput8, outW, outH, outW, outH, uniforms);
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
        statusNotifier.value = 'Grading 4K frames: $percent% (${i + 1}/$totalFrames)';

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
        throw Exception('Encoder failed. Logs: ${logs ?? "No logs"}');
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
          SnackBar(content: Text('✅ Master Saved to /storage/emulated/0/Shaderly:\n${finalOutputFile.path}'), backgroundColor: Colors.green),
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
                  onChanged(newVal);
                  _applyGrade();
                },
                onChangeEnd: (_) {
                  _pushUndoSnapshot();
                  _autoSaveProject();
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
            tooltip: 'Revert Latest Change (Undo All)',
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('3D LUT SUITE (.CUBE)', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                const SizedBox(height: 2),
                const Text('Stores up to 4 .cube LUTs with trilinear sampling', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
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

        const Text('LOADED .CUBE LUTS (MAX 4)', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),

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
                'No .cube LUTs imported yet.\nTap "IMPORT .CUBE" or the top "LUT" button to load any 32x32x32 look.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lut.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            isSel ? 'ACTIVE ON CURRENT LAYER' : 'Tap to apply to layer',
                            style: TextStyle(color: isSel ? accent.withOpacity(0.8) : Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
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
      {'name': 'tealdropped (conq knockoff)', 'desc': 'Bright high-key lift with soft cyan-teal edge bloom & sharp lines', 'color': 0xFF00E5FF},
      {'name': 'vintage cc', 'desc': 'Warm amber film tone with raised blacks and gentle halation', 'color': 0xFFFFB74D},
      {'name': 'noir', 'desc': 'High-contrast stylized ink with a touch of cold silver tone', 'color': 0xFFB0BEC5},
      {'name': 'choso', 'desc': 'Blood manipulation dark crimson aura with high midtone contrast', 'color': 0xFFB71C1C},
      {'name': 'yoruichi', 'desc': 'Purple electric flare with clean high-acutance highlights', 'color': 0xFFAB47BC},
      {'name': 'Gojo', 'desc': 'Infinity cyan specular bloom and clean line contrast', 'color': 0xFF00E5FF},
      {'name': 'Raiden', 'desc': 'Electro violet highlights with balanced natural tones', 'color': 0xFF7C4DFF},
      {'name': 'bina', 'desc': 'Dreamcore soft radiant glow with pastel lift', 'color': 0xFFF48FB1},
      {'name': 'potential, man.', 'desc': 'Crisp midtone contrast and deep ink shadows', 'color': 0xFF3F51B5},
      {'name': 'potential 2.0', 'desc': 'Golden-white radiance with volumetric light shafts', 'color': 0xFFFFB300},
      {'name': 'saber', 'desc': 'Golden divine bloom with clean steel highlights', 'color': 0xFFFFD700},
      {'name': 'sasuke', 'desc': 'Electric horizontal streak flare with cold midtones', 'color': 0xFF00B0FF},
      {'name': 'toji', 'desc': 'High-contrast ink shadows with specular blade sheens', 'color': 0xFF78909C},
      {'name': 'shiki', 'desc': 'Cyan specular edge glow with enhanced line clarity', 'color': 0xFF00E676},
    ];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _importPresetFromFile,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('LOAD CC PRESET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kCardDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveCurrentAsPreset,
                icon: const Icon(Icons.bookmark_add_rounded, size: 16),
                label: const Text('SAVE CURRENT CC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        GestureDetector(
          onTap: _toggleBslaExtremePreset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _isBslaExtremeActive ? const Color(0xFFFFB300).withOpacity(0.20) : const Color(0xFF1E1810),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isBslaExtremeActive ? const Color(0xFFFFB300) : Colors.amber.withOpacity(0.35),
                width: _isBslaExtremeActive ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('BSLA EXTREME', style: TextStyle(color: Color(0xFFFFB300), fontWeight: FontWeight.w900, fontSize: 14)),
                          SizedBox(width: 6),
                          Text('STACKABLE ATMO SHADER', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      SizedBox(height: 3),
                      Text('Screen-Space Light Shafts, 32-Bit Deep Bloom Haze & Liminal Slate Mist Fog', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(
                  _isBslaExtremeActive ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                  color: const Color(0xFFFFB300),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_customPresets.isNotEmpty) ...[
          const Text('MY SAVED PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...List.generate(_customPresets.length, (idx) {
            final p = _customPresets[idx];
            final isSel = _selectedPresetName == p.name;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSel ? accent.withOpacity(0.16) : kCardDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSel ? accent : Colors.white12),
              ),
              child: Row(
                children: [
                  Container(width: 8, height: 36, decoration: BoxDecoration(color: Color(p.accentColor), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _pushUndoSnapshot();
                        setState(() {
                          _project.layers.clear();
                          for (var l in p.layers) {
                            _project.layers.add(l.clone());
                          }
                          _project.tonemapMode = p.tonemapMode;
                          _project.activeLayerIndex = 0;
                          _selectedPresetName = p.name;
                        });
                        _applyGrade();
                        _autoSaveProject();
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: TextStyle(color: isSel ? accent : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(p.description, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                    onPressed: () => _confirmDeleteCustomPreset(idx),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        const Text('BUILT-IN CINEMATIC PRESETS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),

        ...builtInPresets.map((item) {
          final isSelected = _selectedPresetName == item['name'];
          return GestureDetector(
            onTap: () => _applyPreset(item['name'] as String),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? accent.withOpacity(0.16) : kCardDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? accent : Colors.white.withOpacity(0.06),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(item['color'] as int),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] as String,
                          style: TextStyle(
                            color: isSelected ? accent : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(item['desc'] as String, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                    color: isSelected ? accent : Colors.white24,
                    size: 16,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildAEKnockoffsTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF14141C),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UNSHARP MASK ENGINE', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  const Text('Threshold, Amount & Radius sub-sliders', style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showUnsharpMaskDrawer,
                icon: const Icon(Icons.tune_rounded, size: 14, color: Colors.black),
                label: const Text('Open Sub-Sliders', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Text('CIRCULAR & DIRECTIONAL DEPTH OF FIELD', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Depth of Field Blur Intensity', _cur.depthOfField, 0.0, 1.0, (v) => setState(() => _cur.depthOfField = v)),
        _buildSliderRow('Focal Plane Center Y', _cur.dofFocus, 0.0, 1.0, (v) => setState(() => _cur.dofFocus = v)),
        _buildSliderRow('Directional Smear Angle', _cur.dofAngle, 0.0, 3.1415, (v) => setState(() => _cur.dofAngle = v)),

        const SizedBox(height: 14),
        Text('DEEP GLOW SUITE (INVERSE-SQUARE BLOOM)', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Deep Glow Intensity', _cur.deepGlowIntensity, 0.0, 1.5, (v) => setState(() => _cur.deepGlowIntensity = v)),
        _buildSliderRow('Deep Glow Radius (Falloff)', _cur.deepGlowRadius, 0.1, 1.0, (v) => setState(() => _cur.deepGlowRadius = v)),
        _buildSliderRow('Soft Knee Threshold', _cur.deepGlowThreshold, 0.1, 0.9, (v) => setState(() => _cur.deepGlowThreshold = v)),

        const SizedBox(height: 14),
        Text('ALL-EDGE CHROMATIC ABERRATION', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('All-Edge Lineart Dispersion', _cur.lineChromaStrength, 0.0, 1.0, (v) => setState(() => _cur.lineChromaStrength = v)),

        const SizedBox(height: 14),
        Text('WHITE HORIZONTAL ANAMORPHIC FLARE (SPARSE ~8 PEAKS)', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Flare Intensity', _cur.thinStreakIntensity, 0.0, 1.0, (v) => setState(() => _cur.thinStreakIntensity = v)),
        _buildSliderRow('Flare Horizontal Stretch', _cur.thinStreakWidth, 0.1, 1.0, (v) => setState(() => _cur.thinStreakWidth = v)),
        _buildSliderRow('Flare Opacity (Neutral White)', _cur.thinStreakOpacity, 0.0, 1.0, (v) => setState(() => _cur.thinStreakOpacity = v)),

        const SizedBox(height: 14),
        Text('LINE ART INTERIOR EDGE DARKEN & SOBEL', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Interior Edge Shadow (Depth)', _cur.edgeDarken, 0.0, 1.0, (v) => setState(() => _cur.edgeDarken = v)),
        _buildSliderRow('Sobel Outline Sharpness', _cur.darkOutlines, 0.0, 1.0, (v) => setState(() => _cur.darkOutlines = v)),

        const SizedBox(height: 14),
        Text('FLICKER GENERATOR (WITH FREQUENCY)', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Flicker Intensity', _cur.flickerIntensity, 0.0, 1.0, (v) => setState(() => _cur.flickerIntensity = v)),
        _buildSliderRow('Flicker Frequency Speed (Hz)', _cur.flickerSpeed, 1.0, 20.0, (v) => setState(() => _cur.flickerSpeed = v)),

        const SizedBox(height: 14),
        Text('FILM HALATION', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Edge Red Halation Bleed', _cur.halationRadius, 0.0, 1.0, (v) => setState(() => _cur.halationRadius = v)),
        _buildSliderRow('Halation Warmth', _cur.halationWarmth, 0.0, 1.0, (v) => setState(() => _cur.halationWarmth = v)),
      ],
    );
  }

  Widget _buildMagicStuffTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('MAGIC STUFF MOJO (BLOCKBUSTER TEAL / ORANGE)', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Mojo Teal / Orange Split', _cur.mblMojoTealOrange, 0.0, 1.0, (v) => setState(() => _cur.mblMojoTealOrange = v)),

        const SizedBox(height: 16),
        Text('COLORISTA 3-WAY WHEELS (LIFT, GAMMA, GAIN)', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Colorista Lift (Shadows Balance)', _cur.mblColoristaLift, -0.5, 0.5, (v) => setState(() => _cur.mblColoristaLift = v)),
        _buildSliderRow('Colorista Gamma (Midtone Warmth)', _cur.mblColoristaGamma, -0.5, 0.5, (v) => setState(() => _cur.mblColoristaGamma = v)),
        _buildSliderRow('Colorista Gain (Highlight Exposure)', _cur.mblColoristaGain, -0.5, 0.5, (v) => setState(() => _cur.mblColoristaGain = v)),

        const SizedBox(height: 16),
        Text('BSLA SCREEN-SPACE GOD RAYS & FOG', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Volumetric Light Shafts', _cur.bslaGodRays, 0.0, 1.0, (v) => setState(() => _cur.bslaGodRays = v)),
        _buildSliderRow('Atmospheric Fog Density', _cur.bslaFogDensity, 0.0, 1.0, (v) => setState(() => _cur.bslaFogDensity = v)),
        _buildSliderRow('Fog Z-Depth Separation', _cur.bslaFogDepth, 0.0, 1.0, (v) => setState(() => _cur.bslaFogDepth = v)),
        _buildSliderRow('32-Bit Float Over-Bloom Haze', _cur.bslaBloomHaze, 0.0, 1.0, (v) => setState(() => _cur.bslaBloomHaze = v)),
      ],
    );
  }

  Widget _buildGradingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSliderRow('Contrast (0.18 Mid-Gray Pivot)', _cur.contrast, 0.5, 2.0, (v) => setState(() => _cur.contrast = v)),
        _buildSliderRow('Highlights', _cur.highlights, -1.0, 1.0, (v) => setState(() => _cur.highlights = v)),
        _buildSliderRow('Shadows', _cur.shadows, -1.0, 1.0, (v) => setState(() => _cur.shadows = v)),
        _buildSliderRow('Black Crush', _cur.blackCrush, 0.0, 0.5, (v) => setState(() => _cur.blackCrush = v)),
        _buildSliderRow('Gamma Curve', _cur.gamma, 0.4, 2.0, (v) => setState(() => _cur.gamma = v)),
        _buildSliderRow('Saturation (Headroom-Safe)', _cur.saturation, 0.0, 2.0, (v) => setState(() => _cur.saturation = v)),
        _buildSliderRow('Hue Shift', _cur.hue, -0.5, 0.5, (v) => setState(() => _cur.hue = v)),
        _buildSliderRow('Exposure / Brightness', _cur.brightness, -0.5, 0.5, (v) => setState(() => _cur.brightness = v)),
        _buildSliderRow('Micro-Sharpness', _cur.sharpness, 0.0, 1.0, (v) => setState(() => _cur.sharpness = v)),
        _buildSliderRow('Soft Radial Vignette', _cur.vignette, 0.0, 1.0, (v) => setState(() => _cur.vignette = v)),
        _buildSliderRow('Boxed Vignette', _cur.vignetteBoxed, 0.0, 1.0, (v) => setState(() => _cur.vignetteBoxed = v)),
        _buildSliderRow('Film Grain', _cur.filmGrain, 0.0, 0.3, (v) => setState(() => _cur.filmGrain = v)),
        _buildSliderRow('Color Temperature (K)', _cur.temperature, 3000.0, 9500.0, (v) => setState(() => _cur.temperature = v)),
      ],
    );
  }

  Widget _buildCurvesTab() {
    final channelColors = [Colors.white, Colors.redAccent, Colors.greenAccent, Colors.blueAccent];
    final channelNames = ['RGB Master', 'Red', 'Green', 'Blue'];

    List<double> currentPts;
    switch (_selectedCurveChannel) {
      case 1: currentPts = _cur.curveRed; break;
      case 2: currentPts = _cur.curveGreen; break;
      case 3: currentPts = _cur.curveBlue; break;
      case 0:
      default: currentPts = _cur.curveMaster; break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (idx) {
              final isSel = _selectedCurveChannel == idx;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(channelNames[idx]),
                  selected: isSel,
                  selectedColor: channelColors[idx].withOpacity(0.25),
                  backgroundColor: kCardDark,
                  labelStyle: TextStyle(
                    color: isSel ? channelColors[idx] : Colors.white54,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  onSelected: (_) => setState(() => _selectedCurveChannel = idx),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          SplineCurveEditor(
            points: currentPts,
            curveColor: channelColors[_selectedCurveChannel],
            onChanged: (newPts) {
              setState(() {
                switch (_selectedCurveChannel) {
                  case 1: _cur.curveRed = newPts; break;
                  case 2: _cur.curveGreen = newPts; break;
                  case 3: _cur.curveBlue = newPts; break;
                  case 0:
                  default: _cur.curveMaster = newPts; break;
                }
              });
              _applyGrade();
            },
          ),
          const SizedBox(height: 16),
          const Text('CURVE POINT SLIDERS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _buildSliderRow('Blacks (P0)', currentPts[0], 0.0, 1.0, (v) => _updateCurvePt(0, v)),
          _buildSliderRow('Shadows (P1)', currentPts[1], 0.0, 1.0, (v) => _updateCurvePt(1, v)),
          _buildSliderRow('Midtones (P2)', currentPts[2], 0.0, 1.0, (v) => _updateCurvePt(2, v)),
          _buildSliderRow('Highlights (P3)', currentPts[3], 0.0, 1.0, (v) => _updateCurvePt(3, v)),
          _buildSliderRow('Whites (P4)', currentPts[4], 0.0, 1.0, (v) => _updateCurvePt(4, v)),
        ],
      ),
    );
  }

  void _updateCurvePt(int idx, double val) {
    setState(() {
      switch (_selectedCurveChannel) {
        case 1: _cur.curveRed[idx] = val; break;
        case 2: _cur.curveGreen[idx] = val; break;
        case 3: _cur.curveBlue[idx] = val; break;
        case 0:
        default: _cur.curveMaster[idx] = val; break;
      }
    });
    _applyGrade();
    _autoSaveProject();
  }

  Widget _buildGlowsTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSliderRow('Gaussian Bloom Intensity', _cur.deepGlowIntensity, 0.0, 1.5, (v) => setState(() => _cur.deepGlowIntensity = v)),
        _buildSliderRow('Bloom Spread (Smoothness)', _cur.deepGlowRadius, 0.0, 1.0, (v) => setState(() => _cur.deepGlowRadius = v)),
        _buildSliderRow('Bright-Pass Threshold', _cur.deepGlowThreshold, 0.0, 1.0, (v) => setState(() => _cur.deepGlowThreshold = v)),
        const SizedBox(height: 12),
        const Text('BLOOM TINT HARMONY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildTintChip('Neutral', 0.0),
            _buildTintChip('Gold / Warm', 1.0),
            _buildTintChip('Quincy Cyan', 2.0),
            _buildTintChip('Black / Ink', 3.0),
            _buildTintChip('Deep Blood Crimson', 4.0),
            _buildTintChip('Shogun Violet', 5.0),
          ],
        ),
        const SizedBox(height: 16),
        _buildSliderRow('Thin Anamorphic Flare', _cur.thinStreakIntensity, 0.0, 1.0, (v) => setState(() => _cur.thinStreakIntensity = v)),
        _buildSliderRow('Light Rays / God Rays', _cur.volRaysLength, 0.0, 1.0, (v) => setState(() => _cur.volRaysLength = v)),
        _buildSliderRow('Light Rays Decay', _cur.volRaysDecay, 0.7, 0.98, (v) => setState(() => _cur.volRaysDecay = v)),

        const SizedBox(height: 24),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('BSL VOLUMETRIC FOG OVERLAY', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            if (_cur.bslaFogDensity > 0.0)
              GestureDetector(
                onTap: () {
                  setState(() => _cur.bslaFogDensity = 0.0);
                  _applyGrade();
                  _autoSaveProject();
                },
                child: const Text('Reset Fog', style: TextStyle(color: Colors.white38, fontSize: 10)),
              ),
          ],
        ),
        const SizedBox(height: 2),
        const Text('Liminal slate / rain mist atmosphere. Set to 0.0 when not in use.', style: TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 6),
        _buildSliderRow('BSL Fog Density', _cur.bslaFogDensity, 0.0, 1.0, (v) => setState(() => _cur.bslaFogDensity = v)),
        if (_cur.bslaFogDensity > 0.001) ...[
          _buildSliderRow('BSL Fog Horizon Altitude', _cur.bslaFogDepth, 0.0, 1.0, (v) => setState(() => _cur.bslaFogDepth = v)),
          _buildSliderRow('BSL Fog Luminance Scatter', _cur.bslFogScatter, 0.0, 1.0, (v) => setState(() => _cur.bslFogScatter = v)),
        ],
      ],
    );
  }

  Widget _buildTintChip(String title, double code) {
    final isSel = _cur.edgeGlowTint == code;
    final accent = gCustomAccentColor.value;

    return ChoiceChip(
      label: Text(title),
      selected: isSel,
      selectedColor: accent,
      backgroundColor: kCardDark,
      labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 11),
      onSelected: (_) {
        _pushUndoSnapshot();
        setState(() => _cur.edgeGlowTint = code);
        _applyGrade();
        _autoSaveProject();
      },
    );
  }

  Widget _buildSapphireTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('HDR TONEMAPPING OPERATOR', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('Off (Linear)'),
                selected: _project.tonemapMode == 0.0,
                selectedColor: accent,
                backgroundColor: kCardDark,
                labelStyle: TextStyle(color: _project.tonemapMode == 0.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                onSelected: (_) {
                  setState(() => _project.tonemapMode = 0.0);
                  _applyGrade();
                  _autoSaveProject();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Reinhard'),
                selected: _project.tonemapMode == 1.0,
                selectedColor: accent,
                backgroundColor: kCardDark,
                labelStyle: TextStyle(color: _project.tonemapMode == 1.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                onSelected: (_) {
                  setState(() => _project.tonemapMode = 1.0);
                  _applyGrade();
                  _autoSaveProject();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('ACES Filmic'),
                selected: _project.tonemapMode == 2.0,
                selectedColor: accent,
                backgroundColor: kCardDark,
                labelStyle: TextStyle(color: _project.tonemapMode == 2.0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                onSelected: (_) {
                  setState(() => _project.tonemapMode = 2.0);
                  _applyGrade();
                  _autoSaveProject();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('SAPPHIRE S_GLOW CORE', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Sapphire Glow Width', _cur.sapphireGlowWidth, 0.0, 2.0, (v) => setState(() => _cur.sapphireGlowWidth = v)),
        _buildSliderRow('Sapphire Glow Threshold', _cur.sapphireGlowThreshold, 0.0, 1.0, (v) => setState(() => _cur.sapphireGlowThreshold = v)),

        const SizedBox(height: 16),
        Text('VOLUMETRIC S_EDGERAYS', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildSliderRow('Edge Rays Length', _cur.volRaysLength, 0.0, 1.0, (v) => setState(() => _cur.volRaysLength = v)),
        _buildSliderRow('Ray Decay Falloff', _cur.volRaysDecay, 0.70, 0.98, (v) => setState(() => _cur.volRaysDecay = v)),

        const SizedBox(height: 16),
        _buildSliderRow('Bilateral Denoise', _cur.denoise, 0.0, 1.0, (v) => setState(() => _cur.denoise = v)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

    return WillPopScope(
      onWillPop: () async {
        _playbackTimer?.cancel();
        if (_controller != null) {
          await _controller!.pause();
          await _controller!.dispose();
          _controller = null;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              _playbackTimer?.cancel();
              if (_controller != null) {
                await _controller!.pause();
                await _controller!.dispose();
                _controller = null;
              }
              Navigator.pop(context);
            },
          ),
          title: Text(widget.projectName ?? 'Shaderly Editor'),
          actions: [
            GestureDetector(
              onTap: _pickAndImportCubeLut,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _cur.activeLutId != null ? accent : const Color(0xFF1E1E28),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _cur.activeLutId != null ? Colors.white : accent, width: 1.2),
                ),
                child: Center(
                  child: Text(
                    'LUT',
                    style: TextStyle(
                      color: _cur.activeLutId != null ? Colors.black : accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white70),
              tooltip: 'Save Session',
              onPressed: () async {
                await _autoSaveProject();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session saved successfully!'), backgroundColor: Colors.teal));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              tooltip: 'Reset Active Layer',
              onPressed: _resetCurrentLayer,
            ),
            IconButton(
              icon: Icon(Icons.movie_creation_outlined, color: accent),
              tooltip: 'Render Master Video',
              onPressed: _showExportSheet,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              flex: _isFullScreen ? 10 : 5,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _getAspectRatioValue(_project.aspectRatio),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!_project.isImage && _controller != null && _controller!.value.isInitialized)
                          ColorFiltered(
                            colorFilter: _buildLiveColorFilter(),
                            child: VideoPlayer(_controller!),
                          ),

                        if (_project.isImage && _processedStaticImage != null)
                          RawImage(image: _processedStaticImage, fit: BoxFit.contain),

                        if (!_project.isImage)
                          _buildLiveBloomAtmosphere(),

                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () => setState(() => _isFullScreen = !_isFullScreen),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Icon(
                                _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (!_isFullScreen) ...[
              _buildTimelineScrubber(),
              _buildAdjustmentLayerBar(),
              _buildLayerSettingsHeader(),

              Container(
                color: kSurfaceDark,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: accent,
                  labelColor: accent,
                  unselectedLabelColor: Colors.white38,
                  isScrollable: true,
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  tabs: const [
                    Tab(text: 'PRESETS'),
                    Tab(text: 'LUTS'),
                    Tab(text: 'AE KNOCKOFFS'),
                    Tab(text: 'MAGIC STUFF'),
                    Tab(text: 'GRADE'),
                    Tab(text: 'CURVES'),
                    Tab(text: 'GLOWS'),
                    Tab(text: 'SAPPHIRE'),
                  ],
                ),
              ),

              Expanded(
                flex: 4,
                child: Container(
                  color: kBackgroundDark,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPresetsTab(),
                      _buildLutsTab(),
                      _buildAEKnockoffsTab(),
                      _buildMagicStuffTab(),
                      _buildGradingTab(),
                      _buildCurvesTab(),
                      _buildGlowsTab(),
                      _buildSapphireTab(),
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
