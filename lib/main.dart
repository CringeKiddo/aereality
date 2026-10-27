// =============================================================================
// AEReality / Shaderly - Master Studio Interface (Part 1/2)
// True 32-Bit Float Linear Pipeline - Native Vulkan Compute Architecture
// 100% Complete Section - Zero Feature Omissions
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'gradient_map.dart';
import 'gradient_maps_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:image/image.dart' as img;

import 'constants.dart';
import 'models.dart';
import 'vulkan_bridge.dart';
import 'touch_particles.dart';
import 'editor_views.dart';
import 'vfx_slots.dart';
import 'vfx_suite.dart';
import 'export_suite.dart';
import 'crash_log.dart';
import 'cpu_safe.dart';
import 'grade_worker.dart';
import 'accent_state.dart';
import 'ui_kit.dart';
import 'star_field.dart';
import 'motion_s_screen.dart'; // batch 9: Motion S (full screen, opened from the main menu)
import 'time_slice_slots.dart'; // batch 12 step C2: wipe scheduler + packing
import 'cut_detector.dart'; // batch 12: CutDetector (cut scan + detection for the Time Slice wipe scheduler)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Crash evidence: reads what happened last session (shown as a dialog after the first frame).
  await CrashLog.init();
  CrashLog.install();

  try {
    await FFmpegKitExtended.initialize();
  } catch (e) {
    debugPrint('FFmpeg initialization error: $e');
  }

  await AccentStore.load(); // saved accent colour / gradient blend / colour off (batch 7)
  Music.init(); // bundled music only (never touches the export pipeline)
  runApp(const ShaderlyApp());
  CrashLog.scheduleReport();
}

class ShaderlyApp extends StatelessWidget {
  const ShaderlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gAccentListenable,
      builder: (context, _) {
        final accentColor = gCustomAccentColor.value;
        return MaterialApp(
          navigatorKey: CrashLog.navigatorKey,
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
          home: TouchParticlesWrapper(
            child: const HomeScreen(),
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
  List<StoredProject> _all = [];
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
        _all = projs;
        _recent = projs.take(5).toList();
      });
      _generateThumbnails(_all);
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
              '-hide_banner -y -ss 0.1 -noaccurate_seek -i "${p.mediaPath}" -vframes 1 -vf scale=120:-1 -q:v 6 "$outThumb"',
            );
          }
          if (await thumbFile.exists() && mounted) {
            final bytes = await thumbFile.readAsBytes();
            setState(() => _thumbnails[p.id] = bytes);
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
                _all.removeWhere((x) => x.id == proj.id);
                _recent = _all.take(5).toList();
                _thumbnails.remove(proj.id);
              });
              await ProjectManager.saveProjects(_all);
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
    // Batch 7: grouped palette (the original 42 colours first, then new groups), a gradient-blend mini button on every colour,
    // and an independent "Colour off" switch. Nothing is applied until APPLY.
    Color selectedTemp = gChosenAccent.value;
    final Set<int> gradTemp = Set<int>.of(gGradientColours.value);
    bool offTemp = gColourOff.value;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          final size = MediaQuery.of(context).size;
          final bool gradOn = gradTemp.contains(selectedTemp.value);
          final Color shown = offTemp ? kNeutralAccent : selectedTemp;
          final Color shownEnd = (!offTemp && gradOn) ? accentPartner(selectedTemp) : shown;

          Widget swatch(AccentSwatch sw) {
            final bool isSel = selectedTemp.value == sw.color.value;
            final bool hasGrad = gradTemp.contains(sw.color.value);
            return SizedBox(
              width: 48,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => setModal(() => selectedTemp = sw.color),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasGrad ? null : sw.color,
                          gradient: hasGrad
                              ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [sw.color, accentPartner(sw.color)])
                              : null,
                          border: Border.all(color: isSel ? Colors.white : Colors.white10, width: isSel ? 3.0 : 1.0),
                          boxShadow: isSel ? [BoxShadow(color: sw.color.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)] : null,
                        ),
                        child: isSel ? const Icon(Icons.check_rounded, color: Colors.black, size: 16) : null,
                      ),
                    ),
                  ),
                  // gradient blend mini button
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => setModal(() {
                        selectedTemp = sw.color;
                        if (hasGrad) {
                          gradTemp.remove(sw.color.value);
                        } else {
                          gradTemp.add(sw.color.value);
                        }
                      }),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: ShapeDecoration(
                          color: hasGrad ? Colors.white : const Color(0xFF1B1B24),
                          shape: shelfShape(cut: 5, edge: hasGrad ? sw.color : Colors.white30),
                        ),
                        child: Icon(Icons.gradient_rounded, size: 13, color: hasGrad ? Colors.black : Colors.white60),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
            child: ShelfPanel(
              title: 'ACCENT COLOUR',
              icon: Icons.palette_rounded,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), gradient: LinearGradient(colors: [shown, shownEnd])),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: offTemp,
                    activeColor: shown,
                    title: const Text('Colour off', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: const Text('Neutral grey accent', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    onChanged: (v) => setModal(() => offTemp = v),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: size.height * 0.46),
                    child: Opacity(
                      opacity: offTemp ? 0.55 : 1.0,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final g in kAccentGroups) ...[
                              ShelfHeader(g.name),
                              Wrap(spacing: 8, runSpacing: 8, children: g.swatches.map(swatch).toList()),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: shown,
                            foregroundColor: Colors.black,
                            shape: shelfShape(cut: 8, edge: Colors.transparent),
                          ),
                          onPressed: () {
                            gChosenAccent.value = selectedTemp;
                            gGradientColours.value = gradTemp;
                            gColourOff.value = offTemp;
                            applyAccent();
                            AccentStore.save();
                            setState(() {});
                            Navigator.pop(ctx);
                          },
                          child: const Text('APPLY', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _soundRow(
    String label,
    bool enabled,
    double value,
    Color accent,
    StateSetter setModal,
    void Function(bool) setEnabled,
    void Function(double) setValue, {
    String? note,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Checkbox(
                  value: enabled,
                  activeColor: accent,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) {
                    setModal(() => setEnabled(v ?? false));
                    Music.apply();
                    Music.save();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
              Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          Slider(
            value: value.clamp(0.0, 1.0).toDouble(),
            min: 0.0,
            max: 1.0,
            activeColor: accent,
            inactiveColor: Colors.white12,
            onChanged: enabled
                ? (v) {
                    setModal(() => setValue(v));
                    Music.apply();
                  }
                : null,
            onChangeEnd: (_) => Music.save(),
          ),
          if (note != null) Padding(padding: const EdgeInsets.only(left: 36, bottom: 4), child: Text(note, style: const TextStyle(color: Colors.white38, fontSize: 10))),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          final accent = gCustomAccentColor.value;
          final h = MediaQuery.of(context).size.height;

          Widget shelf(int i, String title, IconData icon, List<Widget> kids) => ShelfPanel(
                enterIndex: i,
                title: title,
                icon: icon,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: kids),
              );

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h * 0.86),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          shelf(0, 'ACCENT COLOUR', Icons.palette_rounded, [
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showColorPickerModal();
                              },
                              icon: Icon(Icons.color_lens_rounded, color: accent, size: 18),
                              label: const Text('Pick Colour', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B1B24),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: shelfShape(cut: 8, edge: Colors.white12),
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('Colour off', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              value: gColourOff.value,
                              activeColor: accent,
                              onChanged: (val) {
                                gColourOff.value = val;
                                applyAccent();
                                AccentStore.save();
                                setModal(() {});
                                setState(() {});
                              },
                            ),
                          ]),
                          const SizedBox(height: 10),
                          shelf(1, 'PROCESSING PRECISION', Icons.memory_rounded, [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: ShapeDecoration(
                                color: const Color(0xFF1E1E28),
                                shape: shelfShape(cut: 7, edge: accent.withOpacity(0.3)),
                              ),
                              child: Text(
                                '32-Bit Floating Point (Locked Native)',
                                style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          shelf(2, 'PREVIEW', Icons.visibility_rounded, [
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
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Grade paused frame only', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              value: gGradeActiveFrameOnly,
                              activeColor: accent,
                              onChanged: (val) {
                                setModal(() => gGradeActiveFrameOnly = val);
                                setState(() {});
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Fast flares (half-res beam)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              value: gFlareHalfRes,
                              activeColor: accent,
                              onChanged: (val) {
                                setModal(() => gFlareHalfRes = val);
                                vulkanSetFlareHalfRes(val);
                                setState(() {});
                              },
                            ),
                          ]),
                          const SizedBox(height: 10),
                          shelf(3, 'MUSIC', Icons.music_note_rounded, [
                            _soundRow('Music', Music.enabled, Music.volume, accent, setModal,
                                (v) => Music.enabled = v, (v) => Music.volume = v,
                                note: Music.trackCount == 0
                                    ? 'No tracks found in assets/music/'
                                    : '${Music.trackCount} tracks, shuffled.'),
                          ]),
                          const SizedBox(height: 10),
                          shelf(4, 'CREATOR', Icons.person_rounded, [
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
                                shape: shelfShape(cut: 8, edge: Colors.white12),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Close', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;
    final double top = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      backgroundColor: kBackgroundDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: ShapeDecoration(
                color: accent.withOpacity(0.12),
                shape: shelfShape(cut: 5, edge: accent.withOpacity(0.4)),
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
      body: PixelStarField(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, top + 6, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SlideInTilt(
                index: 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 14),
                  child: Row(
                    children: [
                      DiamondDot(size: 9, color: accent),
                      const SizedBox(width: 10),
                      const Text('SHADERLY', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4)),
                    ],
                  ),
                ),
              ),

              // SHELF 1: start
              ShelfPanel(
                enterIndex: 1,
                title: 'START',
                icon: Icons.play_arrow_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // BUTTON 1: NEW PROJECT
                    Container(
                      decoration: ShapeDecoration(
                        gradient: accentGradient(),
                        shape: shelfShape(cut: 11, edge: Colors.white.withOpacity(0.35)),
                        shadows: [BoxShadow(color: accent.withOpacity(0.40), blurRadius: 14, spreadRadius: 1.0)],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: shelfShape(cut: 11),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectSetupScreen())).then((_) => _load()),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded, color: Colors.black, size: 22),
                                SizedBox(width: 8),
                                Text('NEW PROJECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // BUTTON 2: PROJECTS
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: shelfShape(cut: 9),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ProjectsScreen(thumbnails: _thumbnails)),
                        ).then((_) => _load()),
                        child: Ink(
                          decoration: ShapeDecoration(shape: shelfShape(cut: 9, edge: accent.withOpacity(0.45))),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bookmarks_rounded, color: accent, size: 18),
                              const SizedBox(width: 8),
                              Text('PROJECTS', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // MOTION S (batch 9): big shelf plate, accent / gradient / colour-off aware. Not a panel, so the stars stay visible around it.
              SlideInTilt(
                index: 2,
                child: Builder(builder: (context) {
                  final cols = accentColors();
                  return Container(
                    decoration: ShapeDecoration(
                      gradient: LinearGradient(colors: [cols.first.withOpacity(0.26), cols.last.withOpacity(0.08)]),
                      shape: shelfShape(cut: 16, edge: cols.first.withOpacity(0.75), width: 1.4),
                      shadows: [BoxShadow(color: cols.first.withOpacity(0.22), blurRadius: 18)],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: shelfShape(cut: 16),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MotionSScreen())),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                          child: Row(
                            children: [
                              DiamondDot(size: 9, color: cols.first),
                              const SizedBox(width: 14),
                              Icon(Icons.motion_photos_on_rounded, color: cols.first, size: 30),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('MOTION S', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 3)),
                                    const SizedBox(height: 3),
                                    Text('SMEAR  /  MAIN  /  DUPLICATE', style: TextStyle(color: cols.first.withOpacity(0.9), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, color: cols.first, size: 16),
                              const SizedBox(width: 6),
                              DiamondDot(size: 9, color: cols.last),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 14),

              // SHELF 2: recent
              Expanded(
                child: ShelfPanel(
                  enterIndex: 3,
                  title: 'RECENT',
                  icon: Icons.history_rounded,
                  fill: true,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: _recent.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.layers_clear_outlined, color: Colors.white24, size: 36),
                              SizedBox(height: 10),
                              Text('No saved projects found.', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Tap "NEW PROJECT" to start.', style: TextStyle(color: Colors.white24, fontSize: 11)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _recent.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final p = _recent[i];
                            final thumbBytes = _thumbnails[p.id];

                            return SlideInTilt(
                              index: i,
                              child: Container(
                                decoration: ShapeDecoration(
                                  color: kCardDark,
                                  shape: shelfShape(cut: 9, edge: Colors.white.withOpacity(0.06)),
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
                                      MaterialPageRoute(
                                        builder: (_) => ProjectScreen(
                                          initialProject: p.data,
                                          projectName: p.name,
                                          projectId: p.id,
                                        ),
                                      ),
                                    ).then((_) => _load());
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectsScreen extends StatefulWidget {
  final Map<String, Uint8List?> thumbnails;
  const ProjectsScreen({super.key, required this.thumbnails});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<StoredProject> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await ProjectManager.loadProjects();
    if (!mounted) return;
    setState(() {
      _all = l;
      _loading = false;
    });
  }

  Future<void> _delete(StoredProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCardDark,
        title: const Text('Delete Project?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Delete "${p.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _all.removeWhere((x) => x.id == p.id));
    await ProjectManager.saveProjects(_all);
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? const Center(child: Text('No saved projects.', style: TextStyle(color: Colors.white54)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _all.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = _all[i];
                    final thumb = widget.thumbnails[p.id];
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
                            child: thumb != null
                                ? Image.memory(thumb, fit: BoxFit.cover)
                                : Icon(p.data.isImage ? Icons.image_rounded : Icons.movie_creation_rounded, color: accent),
                          ),
                        ),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${p.data.aspectRatio}  ·  ${p.lastOpened.toString().substring(0, 16)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                          tooltip: 'Delete',
                          onPressed: () => _delete(p),
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProjectScreen(initialProject: p.data, projectName: p.name, projectId: p.id),
                            ),
                          );
                          _load();
                        },
                      ),
                    );
                  },
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
      appBar: AppBar(title: const Text('New Project')),
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
            const Text('RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _aspectRatios.map((ratio) => _buildProportionalRatioBox(ratio, _selectedAspect == ratio, accent)).toList(),
            ),
            const SizedBox(height: 24),
            const Text('MEDIA', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
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
                      _selectedFile == null ? 'Choose video or image' : _selectedFile!.path.split('/').last,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedFile == null ? 'Video or image' : '${(_selectedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
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
                  final newId = 'session_${DateTime.now().millisecondsSinceEpoch}';
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
                              opacity: 1.0,
                              blendMode: LayerBlendMode.normal,
                              contrast: 1.0,
                              saturation: 1.0,
                              brightness: 0.0,
                            ),
                          ],
                        ),
                        projectName: _projectName,
                        projectId: newId,
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
                child: const Text('OPEN EDITOR', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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
// 100% Complete Section - Zero Feature Omissions
// =============================================================================

/// Runs in a short-lived isolate (see _loadShader). Must only touch its arguments and top-level code.
void _initVulkanOffUi(Uint8List shaderBytes, int precisionBits) {
  initVulkan(shaderBytes, precisionBits);
}

class ProjectScreen extends StatefulWidget {
  final ProjectData? initialProject;
  final String? projectName;
  final String? projectId;

  const ProjectScreen({
    super.key,
    this.initialProject,
    this.projectName,
    this.projectId,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  late ProjectData _project;
  final List<ProjectData> _undoHistory = [];
  final List<ProjectData> _redoHistory = [];
  late String _activeSessionId;

  VideoPlayerController? _controller;
  bool _isPlaying = false;
  img.Image? _cachedRawImage;
  bool _isFullScreen = false;

  late TabController _tabController;
  int _selectedCurveChannel = 0;

  ui.Image? _processedStaticImage;
  int _renderWidth = 720;
  int _renderHeight = 900;
  int _srcW = 0;
  int _srcH = 0;
  bool _pendingExtract = false;

  String? _selectedPresetName;
  bool _isBslOverlayActive = false;

  Timer? _playbackTimer;
  double _currentTimelinePosition = 0.0;
  double _videoDurationSeconds = 1.0;

  List<CustomPresetItem> _customPresets = [];
  List<LutModel> _activeLuts = [];

  bool _isVulkanProcessing = false;
  bool _needsReprocess = false;

  // --- preview engine (B5) -------------------------------------------------------------------------------------
  // Quality while playing / scrubbing: preview size is multiplied by this (effect radii scale with resolution in the
  // shader, so the look stays comparable). Paused = full preview quality again. [ASSUMED floor, tune on the N20]
  static const double kInteractiveScale = 0.5;
  static const int kInteractiveMinLongEdge = 480;
  bool _scrubbing = false;
  Uint8List? _videoFrameRgba; // last decoded preview frame of the video (raw RGBA, _videoFrameW x _videoFrameH)
  int _videoFrameW = 0;
  int _videoFrameH = 0;
  Uint8List? _imgFrameRgba; // cropped + resized still image (cached so slider drags do not redo it)
  String _imgFrameKey = '';
  String _lastGradeSig = '';
  final ValueNotifier<int> _previewTick = ValueNotifier<int>(0); // repaints ONLY the graded preview layer
  bool _liveReady = false; // true once a live-graded frame is on screen during playback

  // continuous graded playback ("Grade paused frame only" OFF): 2 s chunks decoded by ONE ffmpeg call each
  Timer? _pbTimer;
  static const double _pbFps = 24.0;
  static const int _pbChunkFrames = 48;
  Uint8List? _pbBuf;
  double _pbStart = 0;
  int _pbCount = 0;
  int _pbW = 0;
  int _pbH = 0;
  Uint8List? _pbNextBuf;
  double _pbNextStart = -1;
  int _pbNextCount = 0;
  bool _pbDecoding = false;
  int _pbGen = 0;
  bool _isSavingProject = false;
  Future<void>? _vkReady; // completes when the Vulkan engine has been created (off the UI thread); the first grade waits for it

  AdjustmentLayer get _cur => _project.currentLayer;

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.projectId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    _tabController = TabController(length: 15, vsync: this); // 15 since batch 12 C3 (index 14 = TIME SLICE)
    _vkReady = _loadShader();

    _project = widget.initialProject ?? ProjectData(mediaPath: '');
    _pushUndoSnapshot();

    _loadCustomPresets();
    _loadLuts();
    _loadMedia(_project.mediaPath);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _pbTimer?.cancel();
    _rebuildThrottle?.cancel();
    _previewTick.dispose();
    _tabController.dispose();
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _processedStaticImage?.dispose();
    _tsReleaseRing(); // batch 12 C2: give the Time Slice ring memory back
    super.dispose();
  }

  void _pushUndoSnapshot() {
    _undoHistory.add(_project.clone());
    _redoHistory.clear();
    if (_undoHistory.length > 50) {
      _undoHistory.removeAt(0);
    }
  }

  void _performUndo() {
    if (_undoHistory.length > 1) {
      final oldView = _viewKey();
      setState(() {
        _redoHistory.add(_undoHistory.removeLast());
        _project = _undoHistory.last.clone();
      });
      _resyncPreview(oldView);
      _autoSaveProject();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reverted latest change'), duration: Duration(milliseconds: 600)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already at initial state'), duration: Duration(milliseconds: 600)),
      );
    }
  }

  void _performRedo() {
    if (_redoHistory.isNotEmpty) {
      final oldView = _viewKey();
      setState(() {
        final nextState = _redoHistory.removeLast();
        _undoHistory.add(nextState);
        _project = nextState.clone();
      });
      _resyncPreview(oldView);
      _autoSaveProject();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Redone change'), duration: Duration(milliseconds: 600)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No further actions to redo'), duration: Duration(milliseconds: 600)),
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

  // ignore: unused_element
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

  /// Largest crop of the source with aspect [r] (fill, no stretch), placed by the pan offset. [x, y, w, h], even numbers.
  List<int> _cropRect(int srcW, int srcH, double r) {
    int cw, ch;
    if (srcW / srcH > r) {
      ch = srcH;
      cw = (srcH * r).round();
    } else {
      cw = srcW;
      ch = (srcW / r).round();
    }
    cw = math.max(2, math.min(srcW, cw) & ~1);
    ch = math.max(2, math.min(srcH, ch) & ~1);
    final x = ((srcW - cw) * (_project.panX + 1) / 2).round().clamp(0, srcW - cw).toInt();
    final y = ((srcH - ch) * (_project.panY + 1) / 2).round().clamp(0, srcH - ch).toInt();
    return [x, y, cw, ch];
  }

  // Preview size follows the imported media: native resolution (times the preview scale), long edge capped at 2560.
  void _updateDimensions(int srcW, int srcH) {
    _srcW = srcW;
    _srcH = srcH;
    final c = _cropRect(srcW, srcH, _getAspectRatioValue(_project.aspectRatio));
    double sc = gPreviewScale;
    final longEdge = math.max(c[2], c[3]);
    if (_isPlaying || _scrubbing) {
      // dynamic quality: smoother while moving, never below ~480 px on the long edge
      sc = math.max(sc * kInteractiveScale, math.min(sc, kInteractiveMinLongEdge / longEdge));
    }
    if (longEdge * sc > 2560) sc = 2560 / longEdge;
    _renderWidth = math.max(16, ((c[2] * sc + 8) ~/ 16) * 16);
    _renderHeight = math.max(16, ((c[3] * sc + 8) ~/ 16) * 16);
  }

  List<int> _previewCrop() => _cropRect(_srcW, _srcH, _renderWidth / _renderHeight);

  String _previewVf(int w, int h) {
    if (_srcW <= 0 || _srcH <= 0) return 'scale=$w:$h';
    final c = _previewCrop();
    return 'crop=${c[2]}:${c[3]}:${c[0]}:${c[1]},scale=$w:$h';
  }

  String _viewKey() => '${_project.aspectRatio}|${_project.panX}|${_project.panY}';

  void _resyncPreview(String oldView) {
    final changed = oldView != _viewKey();
    if (changed && _srcW > 0) _updateDimensions(_srcW, _srcH);
    _applyGrade(forceExtract: changed && !_project.isImage);
  }

  void _setRatio(String r) {
    if (r == _project.aspectRatio) return;
    _pushUndoSnapshot();
    setState(() {
      _project.aspectRatio = r;
      _project.panX = 0.0;
      _project.panY = 0.0;
    });
    if (_srcW > 0) _updateDimensions(_srcW, _srcH);
    _applyGrade(forceExtract: !_project.isImage);
    _autoSaveProject();
  }

  void _showRatioChanger() {
    const ratios = ['16:9', '9:16', '4:5', '1:1', '3:4', '21:9'];
    final accent = gCustomAccentColor.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: kCardDark,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('RATIO', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ratios
                    .map((r) => ChoiceChip(
                          label: Text(r),
                          selected: _project.aspectRatio == r,
                          selectedColor: accent,
                          onSelected: (_) {
                            Navigator.pop(ctx);
                            _setRatio(r);
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _panPreview(DragUpdateDetails d, Size box) {
    if (_srcW <= 0 || _srcH <= 0 || box.width <= 0 || box.height <= 0) return;
    final sc = math.max(box.width / _srcW, box.height / _srcH);
    final exX = _srcW * sc - box.width;
    final exY = _srcH * sc - box.height;
    setState(() {
      if (exX > 1) _project.panX = (_project.panX - d.delta.dx * 2 / exX).clamp(-1.0, 1.0).toDouble();
      if (exY > 1) _project.panY = (_project.panY - d.delta.dy * 2 / exY).clamp(-1.0, 1.0).toDouble();
    });
    _applyGrade(forceExtract: !_project.isImage);
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
      // init_vulkan builds the whole compute pipeline (one huge shader) and can take many seconds on a weak GPU / battery saver.
      // Run on the UI isolate it froze every tap until Android's ANR watchdog fired. The native state is process-global and
      // mutex-protected (init_vulkan returns 1 if already initialised), so a short-lived isolate can create it safely.
      final bytes = shaderBytes;
      final prec = gEnginePrecision; // globals are per isolate: pass the value in
      try {
        await Isolate.run(() => _initVulkanOffUi(bytes, prec));
      } catch (e) {
        debugPrint('initVulkan isolate failed ($e) - initialising inline');
        initVulkan(bytes, prec);
      }
      vulkanSetFlareHalfRes(gFlareHalfRes);
    }
  }

  Future<void> _switchMediaFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final p = result.files.single.path!;
      final ext = p.split('.').last.toLowerCase();
      final validExts = ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'];
      if (validExts.contains(ext)) {
        _project.panX = 0.0;
        _project.panY = 0.0;
        await _loadMedia(p);
      }
    }
  }

  Future<void> _loadMedia(String path) async {
    if (path.isEmpty) return;
    final ext = path.split('.').last.toLowerCase();
    final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);

    _playbackTimer?.cancel();
    _pbTimer?.cancel();
    _pbGen++;
    _pbBuf = null;
    _pbNextBuf = null;
    _videoFrameRgba = null;
    _imgFrameKey = '';
    _lastGradeSig = '';
    Music.onVideoPause();
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
        _imgFrameKey = '';
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
          _applyGrade(forceExtract: true);

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

            }
          });
        });
    }

    _autoSaveProject();
  }

  Future<ui.Image> _rgbaToImage(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  /// One raw RGBA preview frame via ONE ffmpeg call (no PNG encode / decode in between).
  Future<Uint8List?> _extractPreviewFrameRgba(int w, int h) async {
    final tempDir = await getTemporaryDirectory();
    final out = File('${tempDir.path}/tl_frame_preview.rgba');
    try {
      if (out.existsSync()) out.deleteSync();
    } catch (_) {}
    await FFmpegKit.execute(
      '-hide_banner -y -ss $_currentTimelinePosition -noaccurate_seek -i "${_project.mediaPath}" -frames:v 1 '
      '-vf "${_previewVf(w, h)}" -f rawvideo -pix_fmt rgba "${out.path}"',
    );
    if (!out.existsSync()) return null;
    final bytes = await out.readAsBytes();
    try {
      out.deleteSync();
    } catch (_) {}
    return bytes.length == w * h * 4 ? bytes : null;
  }

  Future<void> _applyGrade({bool forceExtract = false}) async {
    // While playing, the picture is either the raw video (grade-paused-only mode) or the live loop below.
    if (_isPlaying) return;
    if (_isVulkanProcessing) {
      _needsReprocess = true;
      if (forceExtract) _pendingExtract = true;
      return;
    }
    _isVulkanProcessing = true;
    _needsReprocess = false;

    try {
      await _vkReady; // engine creation runs off the UI thread now: do not grade before it is ready
      if (_srcW > 0) _updateDimensions(_srcW, _srcH); // paused = full quality, scrubbing = interactive quality
      final int w = _renderWidth;
      final int h = _renderHeight;
      Uint8List? rawBytes;

      if (_project.isImage && _cachedRawImage != null) {
        final key = '${w}x$h|${_viewKey()}';
        if (_imgFrameRgba == null || _imgFrameKey != key) {
          final pc = _previewCrop();
          final cropped = img.copyCrop(_cachedRawImage!, x: pc[0], y: pc[1], width: pc[2], height: pc[3]);
          final resized = img.copyResize(cropped, width: w, height: h);
          _imgFrameRgba = resized.getBytes(order: img.ChannelOrder.rgba);
          _imgFrameKey = key;
        }
        rawBytes = _imgFrameRgba;
      } else if (!_project.isImage && _project.mediaPath.isNotEmpty) {
        if (forceExtract || _videoFrameRgba == null || _videoFrameW != w || _videoFrameH != h) {
          final f = await _extractPreviewFrameRgba(w, h);
          if (f != null) {
            _videoFrameRgba = f;
            _videoFrameW = w;
            _videoFrameH = h;
          }
        }
        rawBytes = _videoFrameRgba;
        if (rawBytes != null && rawBytes.length != w * h * 4) rawBytes = null;
      }

      if (rawBytes != null) {
        final uniforms = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
        final lutTable = _getActiveLutTable();

        // Nothing changed since the picture on screen (same frame, same settings): skip the GPU completely.
        final sig = '${identityHashCode(rawBytes)}|$w|$h|${Object.hashAll(uniforms)}|${lutTable == null ? 0 : identityHashCode(lutTable)}';
        if (sig == _lastGradeSig && _processedStaticImage != null) return;

        // The GPU work runs in the worker isolate: the UI isolate stays free (sliders, taps, animations).
        final res = await GradeWorker.instance.grade(rgba: rawBytes, w: w, h: h, uniforms: uniforms, lut: lutTable);
        final im = await _rgbaToImage(res.rgba, w, h);

        if (mounted) {
          _processedStaticImage?.dispose();
          _processedStaticImage = im;
          _lastGradeSig = sig;
          _previewTick.value++;
        } else {
          im.dispose();
        }
      }
    } catch (_) {
    } finally {
      _isVulkanProcessing = false;
      if (_needsReprocess && mounted) {
        final fe = _pendingExtract;
        _pendingExtract = false;
        _applyGrade(forceExtract: fe);
      }
    }
  }

  // Slider / curve / wheel callbacks. The grade is requested immediately (latest wins, runs in the worker). The whole-screen
  // rebuild that used to happen on EVERY drag event (~60-120 per second) is now throttled to ~16 per second: SmoothSliderRow
  // moves its own handle instantly, and the other controls (wheels, switches, curves) still refresh.
  Timer? _rebuildThrottle;
  void _onSliderChanged() {
    _applyGrade();
    if (_rebuildThrottle?.isActive ?? false) return;
    _rebuildThrottle = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  // ---------------------------------------------------------------------------------------------------
  // CONTINUOUS GRADED PLAYBACK  (settings: "Grade paused frame only" = OFF)
  // The video plays normally (it is the clock and the sound). Every ~40 ms the frame for the current play position is
  // cut from a 2-second chunk (ONE ffmpeg call per chunk, decoded at the lower play quality), graded in the worker
  // isolate and shown over the video. If the GPU is still busy the tick is skipped = frames are DROPPED, the UI never
  // waits. Until the first graded frame is ready the raw video stays visible.
  // ---------------------------------------------------------------------------------------------------
  void _startLivePlayback() {
    _pbTimer?.cancel();
    _pbGen++;
    _pbBuf = null;
    _pbNextBuf = null;
    _liveReady = false;
    _previewTick.value++;
    if (_srcW > 0) _updateDimensions(_srcW, _srcH); // _isPlaying is already true -> lower quality
    vulkanSetBandBudgetMs(12);
    if (!gGradeActiveFrameOnly && !_project.isImage) {
      _pbTimer = Timer.periodic(const Duration(milliseconds: 40), (_) => _playbackGradeTick());
    }
  }

  void _stopLivePlayback() {
    _pbTimer?.cancel();
    _pbTimer = null;
    _pbGen++;
    _pbBuf = null;
    _pbNextBuf = null;
    _liveReady = false;
    vulkanSetBandBudgetMs(40);
    if (_srcW > 0) _updateDimensions(_srcW, _srcH); // _isPlaying is already false -> full quality
    _previewTick.value++;
  }

  Future<Uint8List?> _decodeChunk(double startSec, int w, int h) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/pb_chunk.rgba');
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await FFmpegKit.execute(
      '-hide_banner -y -ss ${startSec.toStringAsFixed(3)} -i "${_project.mediaPath}" -an -sn -dn '
      '-vf "fps=$_pbFps,${_previewVf(w, h)}" -frames:v $_pbChunkFrames -f rawvideo -pix_fmt rgba "${f.path}"',
    );
    if (!f.existsSync()) return null;
    final b = await f.readAsBytes();
    try {
      f.deleteSync();
    } catch (_) {}
    return b.length >= w * h * 4 ? b : null;
  }

  Future<void> _pbRequest(double startSec, int w, int h, {required bool asNext}) async {
    if (_pbDecoding) return;
    _pbDecoding = true;
    final gen = _pbGen;
    try {
      final b = await _decodeChunk(startSec, w, h);
      if (b == null || gen != _pbGen || !mounted) return;
      final n = b.length ~/ (w * h * 4);
      if (asNext) {
        _pbNextBuf = b;
        _pbNextStart = startSec;
        _pbNextCount = n;
      } else {
        _pbBuf = b;
        _pbStart = startSec;
        _pbCount = n;
        _pbW = w;
        _pbH = h;
      }
    } catch (_) {
    } finally {
      _pbDecoding = false;
    }
  }

  void _playbackGradeTick() {
    final c = _controller;
    if (!mounted || c == null || !c.value.isInitialized || !c.value.isPlaying || _srcW <= 0) return;
    final pos = c.value.position.inMilliseconds / 1000.0;
    final w = _renderWidth;
    final h = _renderHeight;
    final fb = w * h * 4;

    if (_pbBuf != null && (_pbW != w || _pbH != h)) {
      _pbBuf = null;
      _pbNextBuf = null;
    }
    bool inCur = _pbBuf != null && _pbCount > 0 && pos >= _pbStart && pos < _pbStart + _pbCount / _pbFps;
    if (!inCur) {
      if (_pbNextBuf != null && pos >= _pbNextStart && pos < _pbNextStart + _pbNextCount / _pbFps) {
        _pbBuf = _pbNextBuf;
        _pbStart = _pbNextStart;
        _pbCount = _pbNextCount;
        _pbW = w;
        _pbH = h;
        _pbNextBuf = null;
        inCur = true;
      } else {
        _pbRequest(pos, w, h, asNext: false); // not ready yet: the raw video keeps showing
        return;
      }
    }
    if (_pbNextBuf == null && pos > _pbStart + (_pbChunkFrames / _pbFps) * 0.5) {
      _pbRequest(_pbStart + _pbCount / _pbFps, w, h, asNext: true); // prefetch the next 2 s
    }
    if (_isVulkanProcessing) return; // GPU busy: drop this frame
    int idx = ((pos - _pbStart) * _pbFps).floor();
    idx = idx.clamp(0, _pbCount - 1).toInt();
    if (_tsPreviewTick(pos, w, h)) return; // batch 12 C2: inside a Time Slice wipe the ring emit replaces the plain grade of this frame
    _gradeLive(Uint8List.sublistView(_pbBuf!, idx * fb, (idx + 1) * fb), w, h);
  }

  Future<void> _gradeLive(Uint8List frame, int w, int h) async {
    if (_isVulkanProcessing) return;
    _isVulkanProcessing = true;
    try {
      final uniforms = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
      final res = await GradeWorker.instance.grade(rgba: frame, w: w, h: h, uniforms: uniforms, lut: _getActiveLutTable());
      final im = await _rgbaToImage(res.rgba, w, h);
      if (!mounted || !(_controller?.value.isPlaying ?? false)) {
        im.dispose();
        return;
      }
      _processedStaticImage?.dispose();
      _processedStaticImage = im;
      _renderWidth = w;
      _renderHeight = h;
      _liveReady = true;
      _previewTick.value++;
    } catch (_) {
    } finally {
      _isVulkanProcessing = false;
      _needsReprocess = false;
    }
  }

  List<int> _exportCrop() {
    int sw, sh;
    if (_project.isImage && _cachedRawImage != null) {
      sw = _cachedRawImage!.width;
      sh = _cachedRawImage!.height;
    } else {
      final sz = _controller!.value.size;
      sw = sz.width.toInt();
      sh = sz.height.toInt();
    }
    return _cropRect(sw, sh, _getAspectRatioValue(_project.aspectRatio));
  }

  List<int> _exportSize() {
    final c = _exportCrop();
    return [c[2], c[3]];
  }

  String _exportCropFilter() {
    final c = _exportCrop();
    return 'crop=${c[2]}:${c[3]}:${c[0]}:${c[1]},';
  }

  void _openExportSheet() {
    final bool isImage = _project.isImage;
    final bool ready = isImage
        ? _cachedRawImage != null
        : (_controller != null && _controller!.value.isInitialized);
    if (!ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load a video or image first.')),
      );
      return;
    }

    _controller?.pause();
    _isPlaying = false;
    Music.setExporting(true); // music steps aside during export (nothing is ever mixed into the video)

    final size = _exportSize();
    ExportSuite.showExportSheet(
      context: context,
      project: _project,
      curLayer: _cur,
      packUniforms: _packMultiLayerUniforms,
      getActiveLut: _getActiveLutTable,
      renderFrameToRgba: _renderFrameForExport,
      prepareFrames: _prepareExportFrames,
      videoDurationMs: _videoDurationSeconds * 1000.0,
      videoFps: 30.0,
      videoWidth: size[0],
      videoHeight: size[1],
      audioSourcePath: isImage ? null : _project.mediaPath,
    );
  }

  Uint8List? _lastExportSource;

  // ---------------------------------------------------------------------------------------------------
  // BATCH SOURCE DECODE FOR EXPORT
  // The export asks for one batch (e.g. 30 frames) at a time. ONE ffmpeg call decodes that whole batch into a raw
  // RGBA file (fps filter = exactly the chosen frame rate, scale = export size); frames are then read from the file
  // one at a time, so memory stays at a single frame. frameCount == 0 releases the batch file.
  // ---------------------------------------------------------------------------------------------------
  File? _batchFile;
  RandomAccessFile? _batchRaf;
  double _batchStartMs = 0;
  double _batchFps = 30;
  int _batchRequested = 0; // frames the export asked for
  int _batchFrames = 0; // frames actually present in the file
  int _batchFrameBytes = 0;

  Future<void> _releaseExportBatch() async {
    try { await _batchRaf?.close(); } catch (_) {}
    _batchRaf = null;
    try { if (_batchFile != null && _batchFile!.existsSync()) _batchFile!.deleteSync(); } catch (_) {}
    _batchFile = null;
    _batchRequested = 0;
    _batchFrames = 0;
  }

  Future<void> _prepareExportFrames(double startMs, int frameCount, double fps) async {
    await _releaseExportBatch();
    if (frameCount <= 0) {
      _tsExportBroken = false;
      _tsReleaseRing(); // batch 12 C2: the export is over, free the ring
    }
    if (frameCount <= 0 || _project.isImage) return;

    final size = _exportSize();
    final w = size[0];
    final h = size[1];
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/export_src_batch.rgba');
    final startSec = (startMs / 1000.0).toStringAsFixed(4);

    CrashLog.note('  decode batch: $frameCount frames from ${startSec}s @ ${fps}fps, ${w}x$h');
    await FFmpegKit.execute(
      '-hide_banner -y ${CpuSafe.ffArgs()}-ss $startSec -i "${_project.mediaPath}" -an -sn -dn '
      '-vf "fps=$fps,${_exportCropFilter()}scale=$w:$h" -frames:v $frameCount -f rawvideo -pix_fmt rgba "${file.path}"',
    );

    final frameBytes = w * h * 4;
    if (!file.existsSync() || file.lengthSync() < frameBytes) {
      CrashLog.note('  decode batch produced no frames, per-frame fallback will be used');
      try { if (file.existsSync()) file.deleteSync(); } catch (_) {}
      return;
    }
    _batchFile = file;
    _batchFrameBytes = frameBytes;
    _batchFrames = file.lengthSync() ~/ frameBytes;
    _batchRequested = frameCount;
    _batchStartMs = startMs;
    _batchFps = fps;
    _batchRaf = await file.open(mode: FileMode.read);
    if (_batchFrames < frameCount) {
      CrashLog.note('  decode batch gave $_batchFrames of $frameCount frames (clip end): last frame is repeated');
    }
  }

  /// One frame from the prepared batch, or null when this timestamp is not inside it.
  Future<Uint8List?> _readBatchFrame(double timestampMs, int expectedBytes) async {
    final raf = _batchRaf;
    if (raf == null || _batchFrames <= 0 || _batchFrameBytes != expectedBytes) return null;
    int idx = ((timestampMs - _batchStartMs) * _batchFps / 1000.0).round();
    if (idx < 0 || idx >= _batchRequested) return null;
    if (idx >= _batchFrames) idx = _batchFrames - 1; // source ended early: hold the last frame
    await raf.setPosition(idx * _batchFrameBytes);
    final bytes = await raf.read(_batchFrameBytes);
    return bytes.length == _batchFrameBytes ? bytes : null;
  }

  // ---------------------------------------------------------------------------------------------------
  // TIME SLICE (batch 12 step C2)
  // The wipe schedule (TimeSliceScheduler) says which output frames are inside a wipe. The 23 frames around a cut (cutFrame - 11 .. + 11 = TimeSlice.ringSlots; C3: was 9) are graded ONCE
  // each into the native ring (pre-dither), then every wipe frame is emitted from the ring (pass 22 + the one dither of pass 23).
  // PREVIEW: only while PLAYING (paused = plain grade). The ring for the next cut is filled up to 2 s before its wipe starts; if it is not ready in time
  // the plain frame is shown (never black, never half sliced). EXPORT: the ring is filled when the first frame of a wipe is rendered; no look-ahead needed.
  // Effect OFF / no cuts / no native support: none of this runs, nothing is allocated, the normal path is untouched.
  // ---------------------------------------------------------------------------------------------------
  List<double>? _tsCutsCache;
  String _tsCutsKey = '';
  TimeSliceScheduler? _tsSched;
  String _tsSchedKey = '';
  bool _tsSchedBuilding = false;
  String _tsRingKey = ''; // which ring is in native memory ('' = none / invalid)
  int _tsRingSig = 0; // grade signature the preview ring was filled with (a changed grade makes the ring stale)
  bool _tsPrepping = false;
  bool _tsExportBroken = false; // the ring failed during this export: plain frames for the rest (no retry loop)

  /// Index of the first layer with Time Slice on, or -1 (also -1 for images / without native support).
  int _tsLayer() {
    if (_project.isImage || !vulkanTimeSliceAvailable()) return -1;
    for (int i = 0; i < _project.layers.length && i < 10; i++) {
      final s = _project.layers[i].timeSlice;
      if (TimeSlice.isOn(s)) return i; // C3: no continuous mode (owner decision), so the effect is always one wipe per cut; the old autoTrigger slot (10) is ignored
    }
    return -1;
  }

  // C3: the ring holds graded frames around ONE cut frame, so its identity is the cut FRAME (+ size / fps), not the schedule: dragging Wipe Duration / Overlap / Cut lands at
  // no longer throws the ring away and regrades 23 frames on every slider tick (the old key contained the schedule key).
  String _tsKeyOf(String tag, int cutFrame, int w, int h, double fps) => '$tag|$cutFrame|$w|$h|$fps';

  /// Hash of the grade part of the uniform buffer (float 1..6399; not the time, not the Time Slice block): changes when the look changes.
  int _tsSig(Float32List u) {
    final b = u.buffer.asUint32List(u.offsetInBytes, 6400);
    int h = 0x811C9DC5;
    for (int i = 1; i < 6400; i++) {
      h ^= b[i];
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  String _tsDetKey(List<double> s) => '${_project.mediaPath}|${s[TimeSlice.cutThreshold]}|${s[TimeSlice.cutMinGap]}|${s[TimeSlice.cutFlashReject]}|${s[TimeSlice.cutFlashWindow]}';
  String _tsSchedKeyFor(List<double> s, double fps) => '${_tsDetKey(s)}|$fps|${s[TimeSlice.wipeDuration]}|${s[TimeSlice.cutPoint]}|${s[TimeSlice.overlap]}';

  Future<TimeSliceScheduler> _tsScheduler(List<double> s, double fps) async {
    final detKey = _tsDetKey(s);
    final key = _tsSchedKeyFor(s, fps);
    if (_tsSched != null && _tsSchedKey == key) return _tsSched!;
    if (_tsCutsCache == null || _tsCutsKey != detKey) {
      final scan = await CutDetector.scan(_project.mediaPath, _videoDurationSeconds); // cached per video on disk
      _tsCutsCache = scan == null ? <double>[] : CutDetector.detect(scan, s);
      _tsCutsKey = detKey;
    }
    final sched = TimeSliceScheduler.build(cuts: _tsCutsCache!, fps: fps, settings: s);
    _tsSched = sched;
    _tsSchedKey = key;
    return sched;
  }

  void _tsReleaseRing() {
    final had = _tsRingKey.isNotEmpty;
    _tsRingKey = '';
    if (had) unawaited(TimeSliceWorker.instance.release());
  }

  /// Decodes the source frames cutFrame - R .. cutFrame + R (R = TimeSlice.ringHalf, 23 frames; clamped to the clip: frames before the start repeat the first frame,
  /// after the end the last). C3: returns the decoded bytes as they are plus the mapping; the old version copied them into a second 23-frame buffer, which would
  /// have doubled the Dart memory (2 x 340 MB at 2K) now that the ring is 23 frames. The caller reads each slot straight out of [_TsDecoded.bytes].
  Future<_TsDecoded?> _tsDecodeRing(int cutFrame, int w, int h, double fps, bool preview) async {
    final fb = w * h * 4;
    const slots = TimeSlice.ringSlots;
    final lead = math.max(0, TimeSlice.ringHalf - cutFrame); // slots before frame 0
    final need = slots - lead;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/ts_ring.rgba');
    try { if (f.existsSync()) f.deleteSync(); } catch (_) {}
    final start = math.max(0.0, (cutFrame - TimeSlice.ringHalf) / fps);
    final vf = preview ? _previewVf(w, h) : '${_exportCropFilter()}scale=$w:$h';
    await FFmpegKit.execute('-hide_banner -y ${CpuSafe.ffArgs()}-ss ${start.toStringAsFixed(4)} -i "${_project.mediaPath}" -an -sn -dn '
        '-vf "fps=$fps,$vf" -frames:v $need -f rawvideo -pix_fmt rgba "${f.path}"');
    if (!f.existsSync()) return null;
    final b = await f.readAsBytes();
    try { f.deleteSync(); } catch (_) {}
    final have = b.length ~/ fb;
    if (have < 1) return null;
    return _TsDecoded(b, lead, have);
  }

  /// Fills the native ring for one cut (23 ingests, each frame graded once). Returns false when it could not.
  Future<bool> _tsPrepareRing(TimeSliceWipe wipe, int w, int h, double fps, String key, {required bool preview}) async {
    if (_tsPrepping) return false;
    _tsPrepping = true;
    final gen = _pbGen;
    try {
      _tsRingKey = ''; // the ring is being overwritten
      final raw = await _tsDecodeRing(wipe.cutFrame, w, h, fps, preview);
      if (raw == null) return false;
      final fb = w * h * 4;
      final lut = _getActiveLutTable();
      int sig = 0;
      for (int j = 0; j < TimeSlice.ringSlots; j++) {
        if (preview && (gen != _pbGen || !mounted)) return false;
        final u = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
        if (j == 0) sig = _tsSig(u);
        u[0] = math.max(0, wipe.cutFrame + j - TimeSlice.ringHalf) / fps; // each frame is graded at its own time (grain / flicker)
        final ok = await TimeSliceWorker.instance.ingest(
            rgba: raw.frame(j, fb), w: w, h: h, uniforms: u, slot: j, ringSlots: TimeSlice.ringSlots, lut: lut);
        if (!ok) return false;
      }
      _tsRingKey = key;
      _tsRingSig = sig;
      return true;
    } catch (e) {
      debugPrint('Time Slice ring: $e');
      return false;
    } finally {
      _tsPrepping = false;
    }
  }

  Future<void> _tsPrepSchedule(List<double> s, double fps) async {
    if (_tsSchedBuilding) return;
    _tsSchedBuilding = true;
    try {
      await _tsScheduler(s, fps);
    } catch (e) {
      debugPrint('Time Slice schedule: $e');
    } finally {
      _tsSchedBuilding = false;
    }
  }

  /// Called once per playback tick (GPU idle). Returns true when this tick started a ring emit (the plain grade is then skipped).
  bool _tsPreviewTick(double pos, int w, int h) {
    final lay = _tsLayer();
    if (lay < 0) {
      if (_tsRingKey.isNotEmpty) _tsReleaseRing();
      return false;
    }
    final s = TimeSlice.sanitize(_project.layers[lay].timeSlice);
    final sched = _tsSched;
    if (sched == null || _tsSchedKey != _tsSchedKeyFor(s, _pbFps)) {
      _tsPrepSchedule(s, _pbFps); // cut scan (cached) + schedule, in the background; plain frames meanwhile
      return false;
    }
    final frame = (pos * _pbFps).round();
    final cur = sched.at(frame);
    if (cur == null) {
      final up = sched.upcoming(frame, (_pbFps * 2.0).round()); // C3: 2 s of look-ahead at ANY frame rate (was a fixed 36 frames = 0.6 s at 60 fps; the ring is now 23 frames)
      if (up != null && !_tsPrepping) {
        final k = _tsKeyOf('pv', up.cutFrame, w, h, _pbFps);
        if (k != _tsRingKey) _tsPrepareRing(up, w, h, _pbFps, k, preview: true);
      }
      return false;
    }
    final key = _tsKeyOf('pv', cur.cutFrame, w, h, _pbFps);
    if (key != _tsRingKey) {
      if (!_tsPrepping) {
        final wipe = sched.wipes.firstWhere((x) => x.cutIndex == cur.cutIndex);
        _tsPrepareRing(wipe, w, h, _pbFps, key, preview: true);
      }
      return false; // not ready: plain frame
    }
    _tsEmitLive(cur, s, lay, w, h, pos);
    return true;
  }

  Future<void> _tsEmitLive(TimeSliceFrame cur, List<double> s, int lay, int w, int h, double pos) async {
    if (_isVulkanProcessing) return;
    _isVulkanProcessing = true;
    try {
      final u = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
      if (_tsSig(u) != _tsRingSig) {
        _tsRingKey = ''; // the grade changed since the ring was filled: plain frames until it is refilled
        return;
      }
      u[0] = pos;
      TimeSlice.packFrameState(u, p: cur.p, n: cur.n, cutPointValue: s[TimeSlice.cutPoint], layer: lay);
      final out = await TimeSliceWorker.instance.emit(w: w, h: h, uniforms: u);
      if (out == null) {
        _tsRingKey = ''; // ring gone (buffers were resized) or GPU error: plain frames, ring is refilled on the next tick
        return;
      }
      final im = await _rgbaToImage(out, w, h);
      if (!mounted || !(_controller?.value.isPlaying ?? false)) {
        im.dispose();
        return;
      }
      _processedStaticImage?.dispose();
      _processedStaticImage = im;
      _renderWidth = w;
      _renderHeight = h;
      _liveReady = true;
      _previewTick.value++;
    } catch (_) {
    } finally {
      _isVulkanProcessing = false;
      _needsReprocess = false;
    }
  }

  /// Export: the finished frame when [timestampMs] is inside a wipe, else null (normal path). The export frame rate is the one the batch was decoded with.
  Future<Uint8List?> _tsExportFrame(double timestampMs, int w, int h) async {
    if (_tsExportBroken) return null;
    final lay = _tsLayer();
    if (lay < 0) return null;
    try {
      final s = TimeSlice.sanitize(_project.layers[lay].timeSlice);
      final fps = _batchFps;
      final sched = await _tsScheduler(s, fps);
      final frame = (timestampMs / 1000.0 * fps).round();
      final cur = sched.at(frame);
      if (cur == null) return null;
      final key = _tsKeyOf('ex', cur.cutFrame, w, h, fps);
      if (key != _tsRingKey) {
        final wipe = sched.wipes.firstWhere((x) => x.cutIndex == cur.cutIndex);
        if (!await _tsPrepareRing(wipe, w, h, fps, key, preview: false)) {
          _tsExportBroken = true;
          return null;
        }
      }
      final u = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
      u[0] = timestampMs / 1000.0;
      TimeSlice.packFrameState(u, p: cur.p, n: cur.n, cutPointValue: s[TimeSlice.cutPoint], layer: lay);
      final out = await TimeSliceWorker.instance.emit(w: w, h: h, uniforms: u);
      if (out == null) {
        _tsRingKey = '';
        _tsExportBroken = true;
        return null;
      }
      return out;
    } catch (e) {
      debugPrint('Time Slice export frame: $e');
      _tsExportBroken = true;
      return null;
    }
  }

  Future<Uint8List> _renderFrameForExport(double timestampMs) async {
    final size = _exportSize();
    final w = size[0];
    final h = size[1];
    Uint8List? raw;

    if (!_project.isImage) {
      // batch 12 C2: a frame inside a Time Slice wipe comes from the ring (pass 22 + the single dither of pass 23); every other frame takes the normal path below
      final tsOut = await _tsExportFrame(timestampMs, w, h);
      if (tsOut != null) return tsOut;
    }

    if (_project.isImage) {
      final ec = _exportCrop();
      raw = img.copyCrop(_cachedRawImage!, x: ec[0], y: ec[1], width: ec[2], height: ec[3]).getBytes(order: img.ChannelOrder.rgba);
    } else {
      // Fast path: the frame is cut out of the batch that _prepareExportFrames decoded in ONE ffmpeg call.
      final readWatch = Stopwatch()..start();
      raw = await _readBatchFrame(timestampMs, w * h * 4);
      if (raw != null) {
        StageTimer.add('frame: read from batch', readWatch.elapsedMicroseconds);
        _lastExportSource = raw;
      } else {
        // Fallback (no batch available): the old one-ffmpeg-call-per-frame decode. Slow, but always works.
        final slowWatch = Stopwatch()..start();
        final tempDir = await getTemporaryDirectory();
        final rawFile = File('${tempDir.path}/export_src_frame.rgba');
        if (rawFile.existsSync()) rawFile.deleteSync();

        final t = (timestampMs / 1000.0).toStringAsFixed(3);
        CrashLog.note('  decode source frame (ffmpeg -ss $t) [slow path]');
        await FFmpegKit.execute(
          '-hide_banner -y -ss $t -i "${_project.mediaPath}" -frames:v 1 '
          '-vf "${_exportCropFilter()}scale=$w:$h" -f rawvideo -pix_fmt rgba "${rawFile.path}"',
        );

        if (rawFile.existsSync() && rawFile.lengthSync() == w * h * 4) {
          raw = await rawFile.readAsBytes();
          _lastExportSource = raw;
        } else {
          raw = _lastExportSource;
        }
        try { if (rawFile.existsSync()) rawFile.deleteSync(); } catch (_) {}
        StageTimer.add('frame: decode per-frame (slow path)', slowWatch.elapsedMicroseconds);
      }
    }

    if (raw == null || raw.length != w * h * 4) {
      throw Exception('Could not decode source frame at ${timestampMs.toStringAsFixed(0)} ms');
    }

    final uniforms = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
    uniforms[0] = timestampMs / 1000.0;
    CrashLog.note('  vulkan processImage ${w}x$h');
    final gradeWatch = Stopwatch()..start();
    // Worker isolate: the UI isolate keeps running during the GPU work (no freeze, no "not responding").
    final res = await GradeWorker.instance.grade(rgba: raw, w: w, h: h, uniforms: uniforms, lut: _getActiveLutTable());
    StageTimer.add('frame: grade (Vulkan, incl. copies)', gradeWatch.elapsedMicroseconds);
    CrashLog.note('  vulkan done, gpu status=${res.gpuStatus} (0 = ok), native ${res.micros ~/ 1000} ms');
    return res.rgba;
  }

  /// The LUT is GLOBAL (the shader applies it once, after all layers). It lives on whichever layer holds it,
  /// regardless of which layer is currently selected - so editing a glow on another layer never drops it.
  AdjustmentLayer get _lutLayer {
    for (final l in _project.layers) {
      if (l.activeLutId != null && _activeLuts.any((x) => x.id == l.activeLutId)) return l;
    }
    return _cur;
  }

  /// Keeps exactly one layer holding the LUT (legacy projects / presets could have several).
  void _syncGlobalLut() {
    final owner = _lutLayer;
    for (final l in _project.layers) {
      if (!identical(l, owner)) l.activeLutId = null;
    }
  }

  Float32List? _getActiveLutTable() {
    final id = _lutLayer.activeLutId;
    if (id == null) return null;
    final match = _activeLuts.where((l) => l.id == id);
    if (match.isEmpty) return null;
    return match.first.table;
  }

  Future<void> _manualSaveProject() async {
    if (_project.mediaPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to save yet: load a video or image first.'), duration: Duration(milliseconds: 1200)),
      );
      return;
    }
    setState(() => _isSavingProject = true);
    final proj = StoredProject(
      id: _activeSessionId,
      name: widget.projectName ?? 'Shaderly Session',
      mediaPath: _project.mediaPath,
      data: _project,
      lastOpened: DateTime.now(),
    );
    final saved = await ProjectManager.saveProject(proj);
    if (mounted) {
      setState(() => _isSavingProject = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved
              ? 'Project saved to Home!'
              : 'Save failed: ${ProjectManager.lastSaveError ?? 'unknown error'}'),
          backgroundColor: saved ? Colors.teal : Colors.redAccent,
          duration: Duration(milliseconds: saved ? 900 : 2500),
        ),
      );
    }
  }

  Future<void> _autoSaveProject() async {
    if (_project.mediaPath.isEmpty) return;
    final proj = StoredProject(
      id: _activeSessionId,
      name: widget.projectName ?? 'Shaderly Session',
      mediaPath: _project.mediaPath,
      data: _project,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(proj);
  }

  // ===========================================================================
  // UNIFORM BUFFER ENGINE (192-Float Stride per Layer + 48-Float Gradient Map per Layer, 6144 Floats Capacity: text owns 3872..4095, VFX 4096..4735, Sapphire 4736..5375, 5376..6143 reserved headroom)
  // Perfectly synchronised with aereality_core.comp layout
  // ===========================================================================
  Float32List _packMultiLayerUniforms(double imgW, double imgH) {
    final uniforms = Float32List(Vfx.uboFloats); // 6144 (batch 7): 4096 as before + VFX + Sapphire blocks (batch 6) + 768 reserved headroom floats
    final timeSeconds = (_controller != null && _controller!.value.isInitialized)
        ? _controller!.value.position.inMilliseconds / 1000.0
        : 0.0;

    uniforms[0] = timeSeconds;
    uniforms[1] = _project.layers.length.toDouble();
    uniforms[2] = _project.tonemapMode;
    uniforms[3] = imgW;
    uniforms[4] = imgH;
    uniforms[5] = _getActiveLutTable() != null ? 1.0 : 0.0;
    uniforms[6] = _lutLayer.lutOpacity;
    uniforms[12] = _project.ditherStrength;

    // Offsets 13..25: Isolated Metallic Text Suite
    uniforms[13] = _project.textSuiteEnabled ? 1.0 : 0.0;
    uniforms[14] = _project.textBoxX;
    uniforms[15] = _project.textBoxY;
    uniforms[16] = _project.textBoxW;
    uniforms[17] = _project.textBoxH;
    uniforms[18] = _project.textBevelDepth;
    uniforms[19] = _project.textChromeIntensity;
    uniforms[20] = _project.textSpecularGlint;
    uniforms[21] = _project.textContactShadow;
    uniforms[22] = _project.textLumaThreshold;
    uniforms[23] = _project.textMetallicTint;
    uniforms[24] = 0.40; // Default Text Glow
    uniforms[25] = 0.50; // legacy text glow radius (glow now comes from the personal block)
    _project.text.packInto(uniforms); // text suite personal block + vector points (floats 3872..4095)

    uniforms[28] = 0.0; // Bit depth preview mode

    // 10 Layers with 192-float stride (offsets 32 + l * 192) - must match LayerData in the shader / C++
    for (int l = 0; l < math.min(_project.layers.length, 10); l++) {
      final layer = _project.layers[l];
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

    TimeSlice.packLayers(uniforms, [for (final l in _project.layers) l.timeSlice]); // batch 12 C2: Time Slice settings 6400..7039 (mirror in project_uniforms.dart)
    MathOps.packLayers(uniforms, [for (final l in _project.layers) l.mathOps]); // batch 14: MathOps settings 7584..7743 (mirror in project_uniforms.dart)
    Gradient4Way.packLayers(uniforms, [for (final l in _project.layers) l.grad4]); // batch 14: 4-Way Gradient settings 7744..7903 (mirror in project_uniforms.dart)
    Bevel.packLayers(uniforms, [for (final l in _project.layers) l.bevel]); // batch 13: Metallic Bevel settings 7424..7583 (mirror in project_uniforms.dart)
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
    if (_project.layers.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 10 Adjustment Layers allowed.')));
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
            tooltip: 'Add Adjustment Layer (Max 10)',
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
            icon: const Icon(Icons.redo_rounded, color: Colors.white70, size: 20),
            tooltip: 'Redo',
            onPressed: _performRedo,
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
              DropdownMenuItem(value: LayerBlendMode.add, child: Text('Add')),
              DropdownMenuItem(value: LayerBlendMode.linearDodge, child: Text('Linear Dodge (= Linear Add)')),
              DropdownMenuItem(value: LayerBlendMode.darken, child: Text('Darken')),
              DropdownMenuItem(value: LayerBlendMode.lighten, child: Text('Lighten')),
              DropdownMenuItem(value: LayerBlendMode.colorDodge, child: Text('Color Dodge')),
              DropdownMenuItem(value: LayerBlendMode.colorBurn, child: Text('Color Burn')),
              DropdownMenuItem(value: LayerBlendMode.hardLight, child: Text('Hard Light')),
              DropdownMenuItem(value: LayerBlendMode.linearBurn, child: Text('Linear Burn')),
              DropdownMenuItem(value: LayerBlendMode.difference, child: Text('Difference')),
              DropdownMenuItem(value: LayerBlendMode.exclusion, child: Text('Exclusion')),
              DropdownMenuItem(value: LayerBlendMode.subtract, child: Text('Subtract')),
              DropdownMenuItem(value: LayerBlendMode.hue, child: Text('Hue')),
              DropdownMenuItem(value: LayerBlendMode.saturationBlend, child: Text('Saturation')),
              DropdownMenuItem(value: LayerBlendMode.colorBlend, child: Text('Color')),
              DropdownMenuItem(value: LayerBlendMode.luminosity, child: Text('Luminosity')),
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
                  Music.onVideoPause(); // music fades back in ~7 s after pausing
                  _stopLivePlayback(); // sharpen: back to full preview quality
                  _applyGrade(forceExtract: true);
                } else {
                  _controller!.play();
                  _isPlaying = true;
                  Music.onVideoPlay(); // music fades out so the video's audio is clean
                  _startLivePlayback(); // lower quality while playing (+ live grade when the setting is OFF)
                }
              });
            },
            child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 8),
          Text(
            EditorViews.formatTimestampMs(_currentTimelinePosition),
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: _currentTimelinePosition.clamp(0.0, _videoDurationSeconds),
                min: 0.0,
                max: _videoDurationSeconds,
                onChangeStart: (_) => _scrubbing = true,
                onChanged: (val) {
                  setState(() {
                    _currentTimelinePosition = val;
                  });
                  _controller?.seekTo(Duration(milliseconds: (val * 1000).toInt()));
                  if (!gGradeActiveFrameOnly) {
                    _applyGrade(forceExtract: true);
                  }
                },
                onChangeEnd: (val) {
                  _scrubbing = false; // sharpen after the scrub
                  _controller?.seekTo(Duration(milliseconds: (val * 1000).toInt())).then((_) {
                    _applyGrade(forceExtract: true);
                  });
                },
              ),
            ),
          ),
          Text(
            EditorViews.formatTimestampMs(_videoDurationSeconds),
            style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSuiteBoundingBoxOverlay(BoxConstraints constraints) {
    if (!_project.textSuiteEnabled) return const SizedBox.shrink();

    return DraggableTextBoundingBox(
      project: _project,
      containerSize: Size(constraints.maxWidth, constraints.maxHeight),
      onUpdated: () => _applyGrade(),
      onEnded: () {
        _pushUndoSnapshot();
        _autoSaveProject();
      },
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
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                tooltip: 'Back to Home',
                onPressed: () => Navigator.pop(context),
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: _isSavingProject
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(Icons.home_outlined, color: accent, size: 24),
                    tooltip: 'Save',
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
                  tooltip: 'Text Suite',
                  onPressed: () {
                    _pushUndoSnapshot();
                    setState(() => _project.textSuiteEnabled = !_project.textSuiteEnabled);
                    if (_project.textSuiteEnabled) _tabController.animateTo(11); // opens the TEXT settings tab
                    _applyGrade();
                    _autoSaveProject();
                  },
                ),
                IconButton(
                  icon: Icon(Icons.aspect_ratio_rounded, color: accent),
                  tooltip: 'Change Ratio',
                  onPressed: _showRatioChanger,
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
                  tooltip: 'Export',
                  onPressed: _openExportSheet,
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
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: GlowFrame(child: AspectRatio(
                        aspectRatio: _getAspectRatioValue(_project.aspectRatio),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: _project.textSuiteEnabled ? null : (_) => _pushUndoSnapshot(),
                              onPanUpdate: _project.textSuiteEnabled ? null : (d) => _panPreview(d, Size(constraints.maxWidth, constraints.maxHeight)),
                              onPanEnd: _project.textSuiteEnabled ? null : (_) => _autoSaveProject(),
                              child: ClipRect(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (!_project.isImage && _controller != null && _controller!.value.isInitialized)
                                    FittedBox(
                                      fit: BoxFit.cover,
                                      alignment: Alignment(_project.panX, _project.panY),
                                      child: SizedBox(
                                        width: _controller!.value.size.width,
                                        height: _controller!.value.size.height,
                                        child: VideoPlayer(_controller!),
                                      ),
                                    ),

                                  ValueListenableBuilder<int>(
                                    valueListenable: _previewTick,
                                    builder: (context, _, __) {
                                      final has = _processedStaticImage != null;
                                      final show = has && (gGradeActiveFrameOnly ? !_isPlaying : (!_isPlaying || _liveReady));
                                      if (show) {
                                        return FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width: _renderWidth.toDouble(),
                                            height: _renderHeight.toDouble(),
                                            child: RawImage(image: _processedStaticImage),
                                          ),
                                        );
                                      }
                                      if (!_isPlaying && !has) {
                                        return const Center(child: CircularProgressIndicator(color: Colors.white38));
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),

                                  _buildTextSuiteBoundingBoxOverlay(constraints),
                                ],
                              ),
                              ),
                            );
                          },
                        ),
                      )),
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

              // Batch 7: the same tabs (15 since batch 12 C3) shown as 4 shelves (LOOK / TONE / FX / TEXT). Same controller, same indices, same TabBarView.
              ShelfTabBar(controller: _tabController),

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
                              final customMatch = _customPresets.where((p) => p.name == presetName);
                              if (customMatch.isNotEmpty) {
                                final cp = customMatch.first;
                                _project.layers
                                  ..clear()
                                  ..addAll(cp.layers.map((l) => l.clone()));
                                _project.tonemapMode = cp.tonemapMode;
                                _project.activeLayerIndex = 0;
                              } else {
                                EditorViews.applyPresetLogic(_project, presetName);
                              }
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
                          await EditorViews.importPresetFromFile(context, _project, _customPresets);
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
                      GradientMapsTab(
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildLutsTab(
                        context: context,
                        cur: _lutLayer,
                        activeLuts: _activeLuts,
                        onLutUpdated: () {
                          _syncGlobalLut();
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onPickLut: () async {
                          await EditorViews.pickAndImportCubeLut(context, _lutLayer, _activeLuts);
                          _syncGlobalLut();
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                        onDeleteLut: (idx) async {
                          setState(() {
                            final rem = _activeLuts.removeAt(idx);
                            for (final l in _project.layers) {
                              if (l.activeLutId == rem.id) l.activeLutId = null;
                            }
                          });
                          await ProjectManager.saveLuts(_activeLuts);
                          _applyGrade();
                          _autoSaveProject();
                        },
                      ),
                      EditorViews.buildBasicGradingTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildColoristaTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildMagicTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildCopiedStuffTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildGlowsAndFlaresTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      EditorViews.buildAtmosphereTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
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
                        onChanged: _onSliderChanged,
                        onResetCurve: () {
                          _pushUndoSnapshot();
                          setState(() {});
                          _applyGrade();
                          _autoSaveProject();
                        },
                      ),
                      EditorViews.buildTextSuiteTab(
                        context: context,
                        project: _project,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      VfxSuite.buildVfxTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      VfxSuite.buildSapphireTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
                      ),
                      VfxSuite.buildTimeSliceTab(
                        context: context,
                        cur: _cur,
                        onChanged: _onSliderChanged,
                        onEnded: () {
                          setState(() {}); // values changed during the drag: refresh everything else once, now
                          _pushUndoSnapshot();
                          _autoSaveProject();
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

/// Result of _tsDecodeRing: the decoded frames plus how ring slot j maps onto them (slots before the clip start repeat the first frame, slots after the end the last).
class _TsDecoded {
  final Uint8List bytes;
  final int lead; // ring slots before frame 0
  final int have; // frames actually decoded
  _TsDecoded(this.bytes, this.lead, this.have);

  Uint8List frame(int slot, int frameBytes) {
    final src = (slot < lead) ? 0 : math.min(slot - lead, have - 1);
    return Uint8List.sublistView(bytes, src * frameBytes, (src + 1) * frameBytes);
  }
}
