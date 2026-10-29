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
import 'engine_boot.dart'; // batch 16: engine starts at app start behind a loading screen
import 'app_settings.dart'; // batch 16: SharedPreferences settings
import 'app_theme.dart'; // batch 16: theme manager
import 'motion_s_screen.dart'; // batch 9: Motion S (full screen, opened from the main menu)
import 'time_slice_slots.dart'; // batch 12 step C2: wipe scheduler + packing
import 'cut_detector.dart'; // batch 12: CutDetector (cut scan + detection for the Time Slice wipe scheduler)
import 'video_proxy.dart'; // batch 18A: media probe + H.264 proxy for files the native player cannot use

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Crash evidence: reads what happened last session (shown as a dialog after the first frame).
  await CrashLog.init();
  CrashLog.install();

  // Settings first (they are tiny and decide how the very first frame looks): preview quality / grade-paused-only / fast flares /
  // theme (batch 16, SharedPreferences), then the saved accent colour / gradient blend / colour off (batch 7, accent.json).
  await SettingsStore.load();
  await AccentStore.load();
  ThemeManager.restore(); // palette only: the accent comes from accent.json

  Music.init(); // bundled music only (never touches the export pipeline)
  runApp(const ShaderlyApp());
  CrashLog.scheduleReport();

  // Batch 16: FFmpeg + the Vulkan pipeline + the grading worker are created HERE, once, behind the loading screen (BootGate below).
  // Nothing else in the app creates the engine any more.
  EngineBoot.start();
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
            appBarTheme: AppBarTheme( // not const any more: kBackgroundDark follows the theme
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
            child: const BootGate(child: HomeScreen()), // loading screen until EngineBoot reports Ready
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

  void _onPalette() {
    if (mounted) setState(() {}); // theme changed: re-read the palette in this screen
  }

  @override
  void initState() {
    super.initState();
    gPalette.addListener(_onPalette);
    _load();
  }

  @override
  void dispose() {
    gPalette.removeListener(_onPalette);
    super.dispose();
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
                          shelf(1, 'THEME', Icons.dashboard_customize_rounded, [
                            ThemeDropdown(
                              onChanged: () {
                                setModal(() {});
                                setState(() {});
                              },
                            ), // ui_kit.dart: Default + 6 character themes, applied live and saved
                          ]),
                          const SizedBox(height: 10),
                          shelf(2, 'PROCESSING PRECISION', Icons.memory_rounded, [
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
                          shelf(3, 'PREVIEW', Icons.visibility_rounded, [
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
                                    SettingsStore.save(); // batch 16: survives a restart
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
                                    SettingsStore.save(); // batch 16: survives a restart
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
                                    SettingsStore.save(); // batch 16: survives a restart
                                    setState(() {});
                                    Navigator.pop(ctx);
                                  },
                                ),
                              ],
                            ),
                            // batch 17B: Preview Engine (replaces the old "Grade paused frame only" switch; gGradeActiveFrameOnly mirrors it)
                            const Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 6),
                              child: Text('PREVIEW ENGINE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final PreviewEngine e in PreviewEngine.values)
                                  ChoiceChip(
                                    label: Text(previewEngineLabel(e)),
                                    selected: gPreviewEngine == e,
                                    selectedColor: accent,
                                    onSelected: (_) {
                                      setModal(() => gPreviewEngine = e);
                                      SettingsStore.save(); // survives a restart
                                      setState(() {});
                                    },
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 6),
                              child: Text(
                                gPreviewEngine == PreviewEngine.smooth
                                    ? 'The video plays at full speed with no grading. The frame is graded when you pause.'
                                    : 'Every frame is graded before the next one shows. A heavy grade plays slower (like CapCut); the sound is muted while it cannot keep up.',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Fast flares (half-res beam)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              value: gFlareHalfRes,
                              activeColor: accent,
                              onChanged: (val) {
                                setModal(() => gFlareHalfRes = val);
                                vulkanSetFlareHalfRes(val);
                                SettingsStore.save(); // batch 16
                                setState(() {});
                              },
                            ),
                          ]),
                          const SizedBox(height: 10),
                          shelf(4, 'MUSIC', Icons.music_note_rounded, [
                            _soundRow('Music', Music.enabled, Music.volume, accent, setModal,
                                (v) => Music.enabled = v, (v) => Music.volume = v,
                                note: Music.trackCount == 0
                                    ? 'No tracks found in assets/music/'
                                    : '${Music.trackCount} tracks, shuffled.'),
                          ]),
                          const SizedBox(height: 10),
                          shelf(5, 'CREATOR', Icons.person_rounded, [
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
                                    ).then((_) => Future<void>.delayed(const Duration(milliseconds: 350), _load)); // 18A: not during the pop animation
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
                          Future<void>.delayed(const Duration(milliseconds: 350), _load); // 18A: the list is parsed after the pop animation, not during it
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
      // batch 16 (16B layout): SafeArea + scroll view keep OPEN EDITOR above the Android navigation bar / gesture bar on every screen height.
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight - 40),
              child: IntrinsicHeight(
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
            ),
          ),
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
  // batch 18A: _isPlaying is backed by a ValueNotifier so the play / pause icon repaints ON ITS OWN the instant it is assigned (no whole-screen
  // rebuild in between). Every existing read and write of _isPlaying keeps working unchanged.
  final ValueNotifier<bool> _playingNotifier = ValueNotifier<bool>(false);
  bool get _isPlaying => _playingNotifier.value;
  set _isPlaying(bool v) => _playingNotifier.value = v;
  // batch 16 playback state (see _togglePlayPause / _onControllerValue / live playback below)
  bool _playTransition = false; // a play / pause / end handler is running: the controller listener ignores values meanwhile
  bool _gradeStale = false; // the graded picture on screen is older than the video position (play started / video ended): show the video until a fresh grade lands
  // batch 17B Preview Engine (see "PREVIEW ENGINE" below): the old live-overlay bookkeeping (_liveFresh / _liveMisses / _liveSuspended ...) is gone
  bool _adaptiveActive = false; // an Adaptive (Slow) play session is running: its loop is the clock, the controller is only the sound
  double _adaptShownPos = 0.0; // video time (s) of the graded frame on screen during an Adaptive session
  double? _adaptJump; // set by the scrubber while playing: the Adaptive loop continues from there
  img.Image? _cachedRawImage;
  bool _isFullScreen = false;

  // ---- batch 18A: media opening / proxy / seeking ----
  int _loadGen = 0; // every _loadMedia call (and dispose) bumps it: an older, slower load notices and drops what it opened
  bool _preparingMedia = false; // the video is being opened / converted: the editor shows a note and play is disabled
  String _preparingNote = '';
  bool _usingProxy = false; // the player plays a temporary H.264 copy; frames and export still read the ORIGINAL file
  bool _proxyTried = false; // a proxy was already attempted for this media (never loop)
  int _mediaW = 0; // true size of the ORIGINAL video (crop maths); the player may be playing a smaller proxy
  int _mediaH = 0;
  /// false: a scrub leaves the video PAUSED on the frame that was picked (Task 3). true: the video plays on after the scrub ends.
  static const bool _kResumeAfterScrub = false;
  bool _scrubWasPlaying = false;
  double? _seekPending; // latest seek target (seconds): drags only ever queue ONE seek behind the one in flight
  bool _seekRunning = false;
  Future<void>? _seekLoop;

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
  // batch 16 (16B): the time text + slider listen to this instead of a whole-screen setState every 100 ms, so playback no longer rebuilds all
  // editor tabs ten times a second. _currentTimelinePosition stays the value every other piece of code reads.
  final ValueNotifier<double> _posNotifier = ValueNotifier<double>(0.0);
  void _setPos(double v) {
    _currentTimelinePosition = v;
    _posNotifier.value = v;
  }
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

  // Adaptive (Slow) playback: 2 s chunks decoded by ONE ffmpeg call each
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

  AdjustmentLayer get _cur => _project.currentLayer;

  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.projectId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    _tabController = TabController(length: 15, vsync: this); // 15 since batch 12 C3 (index 14 = TIME SLICE)

    _project = widget.initialProject ?? ProjectData(mediaPath: '');
    _pushUndoSnapshot();

    _loadCustomPresets();
    _loadLuts();
    _loadMedia(_project.mediaPath);
  }

  @override
  void dispose() {
    _loadGen++; // batch 18A: a media load that is still running notices and drops whatever it opened
    _playbackTimer?.cancel();
    _adaptiveActive = false; // batch 17B: a running Adaptive loop ends (it also checks mounted)
    _pbGen++;
    _rebuildThrottle?.cancel();
    _seekPending = null;
    // batch 18A: release the player first and without waiting (it used to be pause() + dispose(), both unawaited, after the notifiers)
    final VideoPlayerController? c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onControllerValue);
      unawaited(_releaseController(c));
    }
    _previewTick.dispose();
    _posNotifier.dispose();
    _tabController.dispose();
    _processedStaticImage?.dispose();
    _processedStaticImage = null;
    // big pixel buffers: drop the references now instead of waiting for the screen object to be collected
    _cachedRawImage = null;
    _videoFrameRgba = null;
    _imgFrameRgba = null;
    _pbBuf = null;
    _pbNextBuf = null;
    _lastExportSource = null;
    _tsReleaseRing(); // batch 12 C2: give the Time Slice ring memory back
    // NOT released on purpose: the Vulkan pipeline, shader and GPU buffers (created once by EngineBoot, they are what makes the next
    // project open fast) and the GradeWorker / TimeSliceWorker isolates.
    super.dispose();
  }

  Future<void> _releaseController(VideoPlayerController c) async {
    try {
      await c.dispose(); // dispose stops playback and frees the decoder and the texture
    } catch (_) {}
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

  Future<void> _loadMedia(String path, {bool forceProxy = false}) async {
    if (path.isEmpty) return;
    final int gen = ++_loadGen;
    final ext = path.split('.').last.toLowerCase();
    final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
    final Stopwatch sw = Stopwatch()..start();

    _playbackTimer?.cancel();
    _adaptiveActive = false; // batch 17B
    _adaptJump = null;
    _pbGen++;
    _pbBuf = null;
    _pbNextBuf = null;
    _videoFrameRgba = null;
    _imgFrameKey = '';
    _lastGradeSig = '';
    _seekPending = null;
    Music.onVideoPause();
    // batch 18A: the old player is taken off the screen at once and released in the background (it used to be awaited here: pause + dispose
    // blocked the whole media switch). It is released AFTER the frame that removes its VideoPlayer widget.
    final VideoPlayerController? old = _controller;
    _controller = null;
    if (old != null) old.removeListener(_onControllerValue);
    _gradeStale = false;
    if (!forceProxy) {
      _proxyTried = false;
      _usingProxy = false;
    }

    setState(() {
      _project.mediaPath = path;
      _project.isImage = isImg;
      _processedStaticImage?.dispose();
      _processedStaticImage = null;
      _isPlaying = false;
      _preparingMedia = !isImg;
      _preparingNote = 'Opening video…';
      _currentTimelinePosition = 0.0;
      _posNotifier.value = 0.0;
    });
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_releaseController(old)));
    }

    if (isImg) {
      _mediaW = 0;
      _mediaH = 0;
      final fileBytes = await File(path).readAsBytes();
      if (gen != _loadGen || !mounted) return;
      final decoded = img.decodeImage(fileBytes);
      if (decoded != null) {
        _cachedRawImage = decoded;
        _imgFrameKey = '';
        _updateDimensions(decoded.width, decoded.height);
        _applyGrade();
      }
    } else {
      _cachedRawImage = null;
      await _openVideo(path, gen, forceProxy: forceProxy);
    }
    debugPrint('18A open: media ready in ${sw.elapsedMilliseconds} ms (proxy=$_usingProxy)');

    // batch 18A: the save used to run right here, so on a project with many saved projects the load-all / encode-all / write-all of
    // saved_projects.json (on the UI isolate) competed with the video opening and the first frame. It now runs a moment later; it still runs
    // (the project is created / moved to the top of the list), and it is not cancelled when the screen closes.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1500), _autoSaveProject));
  }

  /// Opens [path] in the native player. mp4 / mov: no extra process. webm / mkv / anything else: one cheap ffmpeg probe first, then the
  /// same attempt with the duration check and a seek test. If the player rejects the file (or [forceProxy]) an H.264 proxy is built and
  /// the player plays that instead.
  Future<void> _openVideo(String path, int gen, {required bool forceProxy}) async {
    bool stale() => gen != _loadGen || !mounted;

    MediaProbe probe = MediaProbe.unknown;
    VideoPlayerController? c;
    bool proxied = false;

    if (!forceProxy) {
      if (VideoProxy.looksNativeSafe(path)) {
        c = await _tryNativeController(path, null, gen);
      } else {
        probe = await VideoProxy.probe(path);
        if (stale()) return;
        c = await _tryNativeController(path, probe, gen, selfTest: true);
      }
      if (stale()) {
        if (c != null) unawaited(_releaseController(c));
        return;
      }
    }

    if (c == null) {
      // the native player cannot use this file: silent H.264 proxy
      _proxyTried = true;
      if (!probe.ok) {
        probe = await VideoProxy.probe(path);
        if (stale()) return;
      }
      if (mounted) setState(() => _preparingNote = 'Preparing a compatible copy of this video (first time only)…');
      final String? proxyPath = await VideoProxy.ensureProxy(path, probe);
      if (stale()) return;
      if (proxyPath != null) {
        c = await _tryNativeController(proxyPath, null, gen);
        proxied = c != null;
        if (stale()) {
          if (c != null) unawaited(_releaseController(c));
          return;
        }
      }
    }

    if (c == null) {
      if (mounted) {
        setState(() => _preparingMedia = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This video could not be opened (not even after converting it). Try another file.')),
        );
      }
      return;
    }
    await _adoptController(c, probe, proxied, gen);
  }

  /// Initialises a player on [playPath] and checks it is really usable. Returns it, or null (it is disposed) when it is not:
  /// init failed / timed out, no picture size, a duration under 0.3 s, a duration that disagrees with the file ([probe]), or - for
  /// containers that are often unseekable - a seek to the middle that does not land there.
  Future<VideoPlayerController?> _tryNativeController(String playPath, MediaProbe? probe, int gen, {bool selfTest = false}) async {
    final VideoPlayerController c = VideoPlayerController.file(File(playPath));
    try {
      await c.initialize().timeout(const Duration(seconds: 12));
      if (gen != _loadGen || !mounted) {
        await c.dispose();
        return null;
      }
      final v = c.value;
      final double d = v.duration.inMilliseconds / 1000.0;
      if (!v.isInitialized || v.hasError || v.size.width < 2 || v.size.height < 2) {
        throw StateError('player is not usable (initialized=${v.isInitialized}, size=${v.size}, error=${v.errorDescription})');
      }
      if (d < 0.3) throw StateError('player reports a duration of ${d.toStringAsFixed(2)} s');
      final double? pd = probe?.durationSec;
      if (pd != null && pd > 0.5 && (d - pd).abs() > math.max(1.0, pd * 0.05)) {
        throw StateError('player duration ${d.toStringAsFixed(1)} s, file says ${pd.toStringAsFixed(1)} s');
      }
      if (selfTest) {
        final int targetMs = (d * 500).round();
        await c.seekTo(Duration(milliseconds: targetMs)).timeout(const Duration(seconds: 6));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final Duration? real = await c.position; // asks the player (value.position is only the value we just set)
        final int realMs = real?.inMilliseconds ?? 0;
        if ((realMs - targetMs).abs() > math.max(2000, (d * 100).round())) {
          throw StateError('seek to $targetMs ms landed at $realMs ms (file is not seekable)');
        }
        await c.seekTo(Duration.zero);
      }
      return c;
    } catch (e) {
      debugPrint('18A: native player rejected $playPath: $e');
      try {
        await c.dispose();
      } catch (_) {}
      return null;
    }
  }

  /// Makes a validated player the project's player: paused at 0, duration and true size stored, first frame graded.
  Future<void> _adoptController(VideoPlayerController c, MediaProbe probe, bool proxied, int gen) async {
    if (gen != _loadGen || !mounted) {
      unawaited(_releaseController(c));
      return;
    }
    final Size sz = c.value.size;
    _usingProxy = proxied;
    // the crop maths (preview frames + export) works in the ORIGINAL video's pixels, even when the player plays a smaller proxy
    _mediaW = (proxied && probe.hasSize) ? probe.width! : sz.width.toInt();
    _mediaH = (proxied && probe.hasSize) ? probe.height! : sz.height.toInt();
    _videoDurationSeconds = c.value.duration.inMilliseconds / 1000.0; // validated above: >= 0.3 s and matching the file when it could be checked

    try {
      await c.setLooping(false);
      await c.setVolume(1.0);
      await c.pause(); // a project always opens PAUSED
      await c.seekTo(Duration.zero);
    } catch (_) {}
    if (gen != _loadGen || !mounted) {
      unawaited(_releaseController(c));
      return;
    }

    _controller = c;
    _isPlaying = false;
    c.addListener(_onControllerValue); // batch 16: the play icon / end of video follow the player
    _updateDimensions(_mediaW, _mediaH);
    _setPos(0.0);
    setState(() {
      _preparingMedia = false;
      _preparingNote = '';
    });
    _applyGrade(forceExtract: true);
    _startPlaybackTimer();
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final c = _controller;
      if (c != null && c.value.isInitialized && c.value.isPlaying && mounted && !_playTransition && !_adaptiveActive && !_scrubbing) {
        // batch 16: the old "seek to 0 and play again" loop is gone from here; the end of the video is handled by
        // _onControllerValue (pause cleanly and stay on the last frame)
        _setPos(math.min(c.value.position.inMilliseconds / 1000.0, _videoDurationSeconds)); // no setState: only the scrubber repaints
      }
    });
  }

  /// The native player failed AFTER it had opened the file (a decoder that dies on play, HEVC at high quality ...): rebuild the player on
  /// an H.264 proxy. Runs at most once per media.
  Future<void> _recoverWithProxy(String why) async {
    if (_proxyTried || _preparingMedia || _project.isImage || _project.mediaPath.isEmpty) return;
    _proxyTried = true;
    debugPrint('18A: the player failed ($why): switching to an H.264 proxy');
    await _loadMedia(_project.mediaPath, forceProxy: true);
  }

  // ---------------------------------------------------------------------------------------------------
  // SEEKING / SCRUBBING (batch 18A)
  // A drag fires dozens of seeks per second. They used to be sent one after the other without waiting, so the player was always several
  // seeks behind. Now only ONE seek is in flight and only the LATEST target waits behind it; _seekTo()'s future completes when the
  // player has landed on the last target.
  // ---------------------------------------------------------------------------------------------------
  Future<void> _seekTo(double sec) {
    _seekPending = sec;
    if (_seekRunning) return _seekLoop!;
    _seekLoop = _runSeekLoop();
    return _seekLoop!;
  }

  Future<void> _runSeekLoop() async {
    _seekRunning = true;
    try {
      while (_seekPending != null && mounted) {
        final double s = _seekPending!;
        _seekPending = null;
        final c = _controller;
        if (c == null || !c.value.isInitialized) break;
        final int ms = (s * 1000).round().clamp(0, (_videoDurationSeconds * 1000).round()).toInt();
        await c.seekTo(Duration(milliseconds: ms));
      }
    } catch (e) {
      debugPrint('seek failed: $e');
    } finally {
      _seekRunning = false;
    }
  }

  void _onScrubStart() {
    _scrubbing = true;
    _scrubWasPlaying = _isPlaying;
    if (_isPlaying) unawaited(_pauseForScrub());
  }

  /// Touching the timeline while the video plays pauses it at once (icon first, player second).
  Future<void> _pauseForScrub() async {
    final c = _controller;
    final bool adaptive = _adaptiveMode;
    _isPlaying = false; // the icon flips now, before anything is awaited
    if (!adaptive) _gradeStale = true; // Smooth: the native video shows the frames while scrubbing (Adaptive keeps its graded frame)
    Music.onVideoPause();
    _endPlaybackSession(); // stops the Adaptive loop (generation bump) and drops its chunk buffers
    if (c == null) return;
    try {
      await c.pause();
      await c.setVolume(1.0); // Adaptive may have muted the sound
    } catch (e) {
      debugPrint('pause for scrub failed: $e');
    }
  }

  void _onScrubUpdate(double val) {
    _setPos(val);
    unawaited(_seekTo(val));
    if (gPreviewEngine == PreviewEngine.adaptive) {
      _applyGrade(forceExtract: true); // Adaptive: the frame under the thumb is graded while scrubbing
    } // Smooth: nothing is graded until the thumb is released
  }

  Future<void> _onScrubEnd(double val) async {
    _setPos(val);
    final bool resume = _kResumeAfterScrub && _scrubWasPlaying;
    _scrubWasPlaying = false;
    await _seekTo(val); // wait until the player really is on the frame
    _scrubbing = false; // sharpen after the scrub
    if (!mounted) return;
    _setPos(val);
    _applyGrade(forceExtract: true); // the exact frame under the thumb, full quality
    if (resume) await _togglePlayPause();
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
      '-hide_banner -y -ss $_currentTimelinePosition ${(_scrubbing || _isPlaying) ? '-noaccurate_seek ' : ''}-i "${_project.mediaPath}" -frames:v 1 '
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
    _previewTick.value++; // batch 16: lets the preview layer show / hide its spinner

    try {
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
        if (sig == _lastGradeSig && _processedStaticImage != null) {
          _gradeStale = false;
          return;
        }

        // The GPU work runs in the worker isolate: the UI isolate stays free (sliders, taps, animations).
        final res = await GradeWorker.instance.grade(rgba: rawBytes, w: w, h: h, uniforms: uniforms, lut: lutTable);
        final im = await _rgbaToImage(res.rgba, w, h);

        if (mounted) {
          _processedStaticImage?.dispose();
          _processedStaticImage = im;
          _lastGradeSig = sig;
          _gradeStale = false; // batch 16: a fresh grade of the current position is on screen
          _previewTick.value++;
        } else {
          im.dispose();
        }
      }
    } catch (_) {
    } finally {
      _isVulkanProcessing = false;
      if (mounted) _previewTick.value++; // batch 16: spinner / picture state may have changed
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
  // PREVIEW ENGINE (batch 17B)            Settings > Preview > Preview Engine (gPreviewEngine, app_settings.dart)
  //
  // The old frame-skipping overlay (a 40 ms timer that graded "whatever frame the video is at" and DROPPED frames when the GPU was busy,
  // then hid / re-showed the overlay depending on how far it trailed) is gone: it was the source of the half-second stutter, of the grade
  // that rarely showed and of the old frames that flashed. There are now exactly two behaviours while the video plays:
  //
  //  * Smooth (Native):   the native video plays at full speed and NOTHING is graded. The frame is graded when you pause (and while you
  //                       drag a slider on the paused frame), exactly as before.
  //  * Adaptive (Slow):   the loop below is the CLOCK. For every frame it decodes, grades (the loop waits for the GPU) and only then shows
  //                       it and moves on to the next frame. 100 ms of GPU time per frame = the clip plays at ~0.4x speed. No frame is ever
  //                       skipped. The video_player controller is only the SOUND: it plays muted-or-not next to the loop, and while the
  //                       picture cannot keep up with it (the sound would run ahead) it is muted; the sound comes back by itself after about a
  //                       second of keeping up (the controller is then seeked to the picture first).
  //
  // Frames come from the same 2-second chunks as before (ONE ffmpeg call per chunk, 24 fps grid, _pbFps / _pbChunkFrames); the next chunk
  // is prefetched half a chunk early, and when a chunk is still missing the loop simply waits for it (that wait is part of the slow-down).
  // ---------------------------------------------------------------------------------------------------

  /// Adaptive (Slow) mode is selected and the project is a video.
  bool get _adaptiveMode => gPreviewEngine == PreviewEngine.adaptive && !_project.isImage;

  /// Called when play starts (both engines): drops every chunk of an older session; Adaptive also drops to the lower play quality.
  void _beginPlaybackSession() {
    _pbGen++;
    _pbBuf = null;
    _pbNextBuf = null;
    if (_adaptiveMode) {
      if (_srcW > 0) _updateDimensions(_srcW, _srcH); // _isPlaying is already true -> lower quality (faster frames)
      vulkanSetBandBudgetMs(12);
    }
    _previewTick.value++;
  }

  /// Called on pause / end / media change: stops a running adaptive loop (it checks _pbGen) and drops in-flight chunk decodes.
  void _endPlaybackSession() {
    final bool wasAdaptive = _adaptiveActive;
    _adaptiveActive = false;
    _adaptJump = null;
    _pbGen++;
    _pbBuf = null;
    _pbNextBuf = null;
    if (wasAdaptive) vulkanSetBandBudgetMs(40);
    if (_srcW > 0) _updateDimensions(_srcW, _srcH); // _isPlaying is already false -> full quality
    _previewTick.value++;
  }

  // Decoding (ffmpeg, its own native threads) and grading (GradeWorker isolate) are separate pipelines. The chunk files:
  //  * every chunk goes to its own temp file (the current-chunk and the prefetch decode can run at the same time),
  //  * the chunk file is read in a short-lived isolate: reading tens of MB on the UI isolate was a visible stall at every chunk change,
  //  * "current" and "next" have separate in-flight flags, so a prefetch can never block the decode the player needs right now.
  int _pbFileCounter = 0;
  bool _pbDecodingNext = false;

  Future<Uint8List?> _decodeChunk(double startSec, int w, int h) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/pb_chunk_${_pbFileCounter++ % 4}.rgba';
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await FFmpegKit.execute(
      '-hide_banner -y -ss ${startSec.toStringAsFixed(3)} -i "${_project.mediaPath}" -an -sn -dn '
      '-vf "fps=$_pbFps,${_previewVf(w, h)}" -frames:v $_pbChunkFrames -f rawvideo -pix_fmt rgba "$path"',
    );
    final Uint8List b = await Isolate.run<Uint8List>(() {
      final file = File(path);
      if (!file.existsSync()) return Uint8List(0);
      final bytes = file.readAsBytesSync();
      try {
        file.deleteSync();
      } catch (_) {}
      return bytes;
    });
    return b.length >= w * h * 4 ? b : null;
  }

  Future<void> _pbRequest(double startSec, int w, int h, {required bool asNext}) async {
    if (asNext ? _pbDecodingNext : _pbDecoding) return;
    if (asNext) {
      _pbDecodingNext = true;
    } else {
      _pbDecoding = true;
    }
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
      if (asNext) {
        _pbDecodingNext = false;
      } else {
        _pbDecoding = false;
      }
    }
  }

  /// Adaptive (Slow): the raw RGBA of frame [fr] (24 fps grid, w x h) from the chunk buffers. Waits for the decode when the chunk is not there
  /// yet (the slow-down). null = the session ended / the media has no such frame / decoding failed.
  Future<Uint8List?> _adaptFrame(int fr, int w, int h, int gen) async {
    final int fb = w * h * 4;
    if (_pbBuf != null && (_pbW != w || _pbH != h)) {
      _pbBuf = null; // the preview size changed during the session: the chunks are the wrong size
      _pbNextBuf = null;
    }
    for (int attempt = 0; attempt < 8; attempt++) {
      if (gen != _pbGen || !mounted) return null;
      final Uint8List? cur = _pbBuf;
      if (cur != null) {
        final int idx = fr - (_pbStart * _pbFps).round();
        if (idx >= 0 && idx < _pbCount && cur.length >= (idx + 1) * fb) {
          if (_pbNextBuf == null && idx >= _pbChunkFrames ~/ 2) {
            _pbRequest(_pbStart + _pbCount / _pbFps, w, h, asNext: true); // prefetch the next 2 s while this one plays
          }
          return Uint8List.sublistView(cur, idx * fb, (idx + 1) * fb);
        }
      }
      final Uint8List? nxt = _pbNextBuf;
      if (nxt != null) {
        final int nIdx = fr - (_pbNextStart * _pbFps).round();
        if (nIdx >= 0 && nIdx < _pbNextCount && nxt.length == _pbNextCount * fb) {
          _pbBuf = nxt; // the prefetched chunk becomes the current one
          _pbStart = _pbNextStart;
          _pbCount = _pbNextCount;
          _pbW = w;
          _pbH = h;
          _pbNextBuf = null;
          continue;
        }
        if (nxt.length != _pbNextCount * fb) _pbNextBuf = null; // wrong size (preview size changed)
      }
      if (_pbDecoding) {
        // a decode is already running (maybe the very one we need): wait for it, then look again
        int waited = 0;
        while (_pbDecoding && gen == _pbGen && mounted && waited < 20000) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          waited += 20;
        }
        continue;
      }
      final Uint8List? before = _pbBuf;
      await _pbRequest(fr / _pbFps, w, h, asNext: false); // decode the chunk starting at this frame (awaited: the playback waits)
      if (identical(_pbBuf, before)) return null; // the decode produced nothing (end of the media / failure / session gone): no frame
    }
    return null;
  }

  /// Adaptive (Slow): the playback loop. It is the clock; [c] only provides the sound. One frame at a time: decode -> grade (GPU, awaited)
  /// -> wait until the frame is due -> show it. See the comment block above for the rules. Ends by itself at the end of the video.
  Future<void> _adaptiveLoop(VideoPlayerController c, int gen, int startFrame) async {
    final int stepUs = (1000000.0 / _pbFps).round();
    final int lastFrame = math.max(0, (_videoDurationSeconds * _pbFps).floor() - 1);
    final Stopwatch sw = Stopwatch()..start();
    int fr = startFrame.clamp(0, lastFrame).toInt();
    int nextDueUs = 0; // wall time (sw) at which the next frame should appear
    bool audioStarted = false; // the controller is only started together with the FIRST graded frame (the first chunk decode takes a while)
    bool muted = false;
    int onTime = 0; // consecutive frames shown on time (used to bring the sound back)
    int frameNo = 0;
    int failures = 0;
    bool ended = false;

    bool alive() => gen == _pbGen && mounted && _adaptiveActive && _isPlaying;

    try {
      while (alive()) {
        final double? jump = _adaptJump; // the scrubber was moved while playing
        if (jump != null) {
          _adaptJump = null;
          fr = (jump * _pbFps).round().clamp(0, lastFrame).toInt();
          nextDueUs = sw.elapsedMicroseconds;
        }
        if (fr > lastFrame) {
          ended = true;
          break;
        }

        final int w = _renderWidth;
        final int h = _renderHeight;
        final Uint8List? frame = await _adaptFrame(fr, w, h, gen);
        if (!alive()) break;
        if (frame == null) {
          ended = true; // no such frame: the end of the media (or the decode failed): finish cleanly
          break;
        }
        final double pos = fr / _pbFps;

        // ---- grade: the loop waits for the GPU here ----
        ui.Image? im;
        _isVulkanProcessing = true;
        try {
          im = await _tsPreviewImage(pos, w, h); // inside a Time Slice wipe the ring emit replaces the plain grade of this frame
          if (im == null && alive()) {
            final Float32List u = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
            u[0] = pos; // time-based effects (grain, flicker) follow the frame being graded, not the controller
            final res = await GradeWorker.instance.grade(rgba: frame, w: w, h: h, uniforms: u, lut: _getActiveLutTable());
            im = await _rgbaToImage(res.rgba, w, h);
          }
        } catch (e) {
          debugPrint('Adaptive grade failed: $e');
          im = null;
        } finally {
          _isVulkanProcessing = false;
        }
        if (!alive()) {
          im?.dispose();
          break;
        }
        if (im == null) {
          if (++failures > 5) {
            debugPrint('Adaptive preview: 5 frames in a row could not be graded, stopping playback.');
            ended = true;
            break;
          }
          fr++;
          continue;
        }
        failures = 0;

        // ---- sound: starts together with the first graded frame ----
        if (!audioStarted) {
          audioStarted = true;
          try {
            await c.seekTo(Duration(milliseconds: (pos * 1000).round()));
            await c.setVolume(1.0);
            await c.play();
          } catch (e) {
            debugPrint('Adaptive preview: sound could not start: $e');
          }
          if (!alive()) {
            im.dispose();
            break;
          }
          nextDueUs = sw.elapsedMicroseconds;
        }

        // ---- pace: never faster than real time, never skipping when slower ----
        final int nowUs = sw.elapsedMicroseconds;
        if (nowUs < nextDueUs) {
          await Future<void>.delayed(Duration(microseconds: nextDueUs - nowUs));
          if (!alive()) {
            im.dispose();
            break;
          }
        }
        final int shownUs = sw.elapsedMicroseconds;
        final int lateUs = shownUs - nextDueUs;

        // ---- show it ----
        _processedStaticImage?.dispose();
        _processedStaticImage = im;
        _renderWidth = w;
        _renderHeight = h;
        _gradeStale = false;
        _adaptShownPos = pos;
        if (!_scrubbing) _setPos(pos); // while the thumb is held the scrubber belongs to the finger
        _previewTick.value++;

        // a frame that was only a little late keeps the schedule (jitter must not slow the clip down); a really late one re-bases it
        nextDueUs = lateUs <= stepUs ~/ 2 ? nextDueUs + stepUs : shownUs + stepUs;
        onTime = lateUs <= stepUs ~/ 2 ? onTime + 1 : 0;

        // ---- sound vs picture (checked every 6th frame; c.position asks the player, c.value.position is only refreshed every 500 ms) ----
        frameNo++;
        if (audioStarted && frameNo % 6 == 0) {
          if (!muted) {
            final Duration? cp = await c.position;
            if (!alive()) break;
            if (cp != null && (cp.inMilliseconds / 1000.0 - pos).abs() > kAdaptDesyncSec) {
              muted = true; // the sound runs ahead of the picture: mute it instead of playing it out of sync
              onTime = 0;
              await c.setVolume(0.0);
            }
          } else if (onTime >= kAdaptResyncFrames) {
            try {
              await c.seekTo(Duration(milliseconds: (pos * 1000).round())); // the picture keeps up again: the sound joins it
              await c.setVolume(1.0);
              if (!c.value.isPlaying) await c.play();
              muted = false;
              onTime = 0;
            } catch (_) {}
            nextDueUs = sw.elapsedMicroseconds;
          }
        }
        fr++;
      }
    } catch (e, st) {
      debugPrint('Adaptive preview loop failed: $e\n$st');
      ended = true;
    }

    // the video reached its end (not a pause, which bumps _pbGen first): stop cleanly on the last frame
    if (ended && gen == _pbGen && mounted && _adaptiveActive && _isPlaying) {
      await _onAdaptiveEnded(c);
    }
  }

  Future<void> _onAdaptiveEnded(VideoPlayerController c) async {
    _adaptiveActive = false;
    try {
      await c.pause();
      await c.setVolume(1.0);
    } catch (_) {}
    if (!mounted) return;
    await _onPlaybackEnded(c, keepPicture: true); // the graded frame stays on screen until the full-quality grade of the last frame replaces it
  }

  // ---------------------------------------------------------------------------------------------------
  // PLAY / PAUSE / END OF VIDEO
  // The play icon follows the player: _isPlaying flips the instant the button is tapped, and the controller listener corrects it if
  // the player disagrees (Smooth mode: the video ended, the OS paused it ...). The end of the video pauses cleanly and parks on the last
  // frame; pressing play there starts again from 0. The picture shown after a pause is only the graded frame of THAT position: in Smooth
  // mode the native video texture shows until it is ready (never a graded frame from before the video was played); in Adaptive mode the
  // last graded frame simply stays (it IS the frame of the pause position), so nothing flashes.
  // ---------------------------------------------------------------------------------------------------
  static const Duration _kEndSlack = Duration(milliseconds: 120);

  /// Adaptive (Slow): the sound is muted when it runs this far (seconds) ahead of / behind the picture ...
  static const double kAdaptDesyncSec = 0.12;

  /// ... and comes back after this many consecutive frames shown on time (24 = about one second).
  static const int kAdaptResyncFrames = 24;

  bool _controllerAtEnd(VideoPlayerController c) {
    // batch 18A: the VALIDATED duration, not the player's raw value. A player that claimed 0.1 s made "position >= duration - 120 ms" true
    // at position 0: every pause looked like the end of the video and parked it at the start, and play always restarted from 0.
    final Duration d = Duration(milliseconds: (_videoDurationSeconds * 1000).round());
    return d >= const Duration(seconds: 1) && c.value.position >= d - _kEndSlack;
  }

  Future<void> _togglePlayPause() async {
    final c = _controller;
    // batch 18A: play needs an initialised player AND a valid duration (the controller is only set once both are true)
    if (c == null || !c.value.isInitialized || _preparingMedia || _videoDurationSeconds < 0.3 || _playTransition) return;
    _playTransition = true;
    try {
      if (_isPlaying) {
        // ---- pause ----
        final bool wasAdaptive = _adaptiveActive;
        final double shown = _adaptShownPos;
        _isPlaying = false; // the icon flips instantly (batch 18A: notifier-backed, no whole-screen rebuild first)
        _previewTick.value++;
        _pbGen++; // the adaptive loop stops at its next check (_isPlaying is false and its generation is gone)
        await c.pause();
        if (wasAdaptive) {
          // the controller ran ahead of the picture (it only provided the sound): put it on the frame that is on screen
          try {
            await c.setVolume(1.0);
            await c.seekTo(Duration(milliseconds: (shown * 1000).round()));
          } catch (_) {}
        }
        _onPlaybackPaused(c, adaptivePos: wasAdaptive ? shown : null);
      } else {
        // ---- play ----
        final bool restart = _controllerAtEnd(c);
        final bool adaptive = _adaptiveMode;
        _isPlaying = true; // the icon flips instantly (batch 18A: notifier-backed, no whole-screen rebuild first)
        _previewTick.value++;
        // Smooth: the graded frame on screen belongs to the old position, the native video shows until a fresh grade lands after the pause.
        // Adaptive: the graded frame on screen IS the first frame of the session (except after the end, where play restarts at 0).
        _gradeStale = !adaptive || restart;
        if (restart) {
          await c.seekTo(Duration.zero);
          _setPos(0.0);
        }
        Music.onVideoPlay(); // music fades out so the video's audio is clean
        _beginPlaybackSession();
        if (adaptive) {
          _adaptiveActive = true;
          _adaptJump = null;
          _adaptShownPos = _currentTimelinePosition;
          final int startFrame = restart ? 0 : (_currentTimelinePosition * _pbFps).round();
          unawaited(_adaptiveLoop(c, _pbGen, startFrame)); // the loop is the clock; the controller starts with its first graded frame
        } else {
          await c.play(); // Smooth: the native video is the clock and plays untouched, nothing is graded until the pause
        }
      }
    } catch (e) {
      debugPrint('play / pause failed: $e');
      if (mounted) setState(() => _isPlaying = c.value.isPlaying || _adaptiveActive);
    } finally {
      _playTransition = false;
    }
  }

  void _onControllerValue() {
    final c = _controller;
    // batch 18A: the player opened the file but failed later (decoder error): silently continue on an H.264 proxy
    if (c != null && mounted && c.value.hasError && !_usingProxy && !_proxyTried && !_preparingMedia && !_project.isImage) {
      unawaited(_recoverWithProxy(c.value.errorDescription ?? 'player error'));
      return;
    }
    if (c == null || !mounted || _playTransition || !c.value.isInitialized) return;
    if (_adaptiveActive) return; // Adaptive: the loop is the clock, the controller is only the sound (it may end / pause on its own)
    if (_isPlaying && !c.value.isPlaying) {
      if (_controllerAtEnd(c)) {
        _onPlaybackEnded(c);
      } else {
        // the platform stopped playback by itself (audio focus, app switch ...): the icon follows
        setState(() => _isPlaying = false);
        _onPlaybackPaused(c);
      }
    }
  }

  void _onPlaybackPaused(VideoPlayerController c, {double? adaptivePos}) {
    if (!mounted) return;
    // the exact paused position (the 100 ms timer can be one tick behind): the graded frame is cut from here.
    // Adaptive: the position of the frame that is on screen (the controller was only the sound).
    _setPos(adaptivePos ?? math.min(c.value.position.inMilliseconds / 1000.0, _videoDurationSeconds));
    setState(() {}); // play icon
    Music.onVideoPause(); // music fades back in ~7 s after pausing
    _endPlaybackSession(); // sharpen: back to full preview quality
    _gradeAfterPause();
  }

  Future<void> _gradeAfterPause() async {
    // A grade may still be in flight (Adaptive: the frame the loop was grading) and clears _needsReprocess when it ends, so wait for it
    // here instead of queueing.
    int guard = 0;
    while (_isVulkanProcessing && guard++ < 100 && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (!mounted || _isPlaying) return;
    _applyGrade(forceExtract: true);
  }

  Future<void> _onPlaybackEnded(VideoPlayerController c, {bool keepPicture = false}) async {
    _playTransition = true;
    try {
      final d = Duration(milliseconds: (_videoDurationSeconds * 1000).round()); // batch 18A: validated duration
      // one frame before the very end: the texture keeps a real picture there (a seek to the exact end can show black or jump)
      final Duration last = d > const Duration(milliseconds: 80) ? d - const Duration(milliseconds: 40) : Duration.zero;
      setState(() {
        _isPlaying = false;
        _currentTimelinePosition = last.inMilliseconds / 1000.0;
        _posNotifier.value = _currentTimelinePosition;
      });
      if (!keepPicture) _gradeStale = true; // Adaptive keeps its last graded frame on screen (no flash of the ungraded video)
      Music.onVideoPause();
      _endPlaybackSession();
      await c.seekTo(last);
      if (!mounted) return;
      _gradeAfterPause();
    } catch (e) {
      debugPrint('end of video handling failed: $e');
    } finally {
      _playTransition = false;
    }
  }

  List<int> _exportCrop() {
    int sw, sh;
    if (_project.isImage && _cachedRawImage != null) {
      sw = _cachedRawImage!.width;
      sh = _cachedRawImage!.height;
    } else {
      if (_mediaW > 0 && _mediaH > 0) {
        sw = _mediaW; // batch 18A: the ORIGINAL video's size (the player may be playing a smaller proxy)
        sh = _mediaH;
      } else {
        final sz = _controller!.value.size;
        sw = sz.width.toInt();
        sh = sz.height.toInt();
      }
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
    _controller?.setVolume(1.0); // batch 17B: Adaptive may have muted the sound
    _adaptiveActive = false;
    _adaptJump = null;
    _pbGen++;
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

  /// Adaptive (Slow) preview, once per frame: the finished Time Slice wipe frame for [pos] (ring emit, awaited), or null when the plain grade
  /// should be used (no Time Slice layer, outside a wipe, ring not ready yet / filled for an older grade, GPU error). The ring itself is still
  /// prepared in the background exactly as before (plain frames meanwhile). Batch 17B: was _tsPreviewTick + _tsEmitLive (fire-and-forget).
  Future<ui.Image?> _tsPreviewImage(double pos, int w, int h) async {
    final lay = _tsLayer();
    if (lay < 0) {
      if (_tsRingKey.isNotEmpty) _tsReleaseRing();
      return null;
    }
    final s = TimeSlice.sanitize(_project.layers[lay].timeSlice);
    final sched = _tsSched;
    if (sched == null || _tsSchedKey != _tsSchedKeyFor(s, _pbFps)) {
      _tsPrepSchedule(s, _pbFps); // cut scan (cached) + schedule, in the background; plain frames meanwhile
      return null;
    }
    final frame = (pos * _pbFps).round();
    final cur = sched.at(frame);
    if (cur == null) {
      final up = sched.upcoming(frame, (_pbFps * 2.0).round()); // C3: 2 s of look-ahead at ANY frame rate (was a fixed 36 frames = 0.6 s at 60 fps; the ring is now 23 frames)
      if (up != null && !_tsPrepping) {
        final k = _tsKeyOf('pv', up.cutFrame, w, h, _pbFps);
        if (k != _tsRingKey) _tsPrepareRing(up, w, h, _pbFps, k, preview: true);
      }
      return null;
    }
    final key = _tsKeyOf('pv', cur.cutFrame, w, h, _pbFps);
    if (key != _tsRingKey) {
      if (!_tsPrepping) {
        final wipe = sched.wipes.firstWhere((x) => x.cutIndex == cur.cutIndex);
        _tsPrepareRing(wipe, w, h, _pbFps, key, preview: true);
      }
      return null; // not ready: plain frame
    }
    return _tsEmitImage(cur, s, lay, w, h, pos);
  }

  Future<ui.Image?> _tsEmitImage(TimeSliceFrame cur, List<double> s, int lay, int w, int h, double pos) async {
    try {
      final u = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
      if (_tsSig(u) != _tsRingSig) {
        _tsRingKey = ''; // the grade changed since the ring was filled: plain frames until it is refilled
        return null;
      }
      u[0] = pos;
      TimeSlice.packFrameState(u, p: cur.p, n: cur.n, cutPointValue: s[TimeSlice.cutPoint], layer: lay);
      final out = await TimeSliceWorker.instance.emit(w: w, h: h, uniforms: u);
      if (out == null) {
        _tsRingKey = ''; // ring gone (buffers were resized) or GPU error: plain frames, ring is refilled on the next frame
        return null;
      }
      return await _rgbaToImage(out, w, h);
    } catch (_) {
      return null;
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
            behavior: HitTestBehavior.opaque, // batch 16: the whole padded box is the button, not just the glyph
            onTap: _togglePlayPause, // flips the icon instantly, then plays / pauses; the controller listener keeps it in sync
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ValueListenableBuilder<bool>(
                valueListenable: _playingNotifier, // batch 18A: only the icon repaints, the moment _isPlaying changes
                builder: (context, playing, _) => Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accent, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<double>(
            valueListenable: _posNotifier,
            builder: (context, pos, _) => Text(
              EditorViews.formatTimestampMs(pos),
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
            ),
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
              child: ValueListenableBuilder<double>(
                valueListenable: _posNotifier,
                builder: (context, pos, _) => Slider(
                  value: pos.clamp(0.0, _videoDurationSeconds).toDouble(),
                  min: 0.0,
                  max: _videoDurationSeconds,
                  // batch 18A: touching the timeline pauses the video, drags seek one target at a time, and releasing the thumb leaves the
                  // video paused ON the chosen frame (see _onScrubStart / _onScrubUpdate / _onScrubEnd).
                  onChangeStart: (_) => _onScrubStart(),
                  onChanged: (val) => _onScrubUpdate(val),
                  onChangeEnd: (val) => _onScrubEnd(val),
                ),
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
      backgroundColor: kProjectBgDark,
      appBar: _isFullScreen
          ? null
          : AppBar(
              backgroundColor: gPalette.value.panel,
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
              flex: _isFullScreen ? 10 : (_getAspectRatioValue(_project.aspectRatio) < 1.0 ? 6 : 5), // taller share for portrait ratios [ASSUMED]
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black,
                    child: LayoutBuilder(
                      builder: (context, area) {
                        // batch 16: the preview box is computed from the free space and the ratio, then centred: 4:5, 16:9, 1:1 ... all fill
                        // the area as far as their shape allows, with the same 6 px margin, never offset.
                        const double margin = 6.0;
                        final double ratio = _getAspectRatioValue(_project.aspectRatio);
                        final double availW = math.max(1.0, area.maxWidth - margin * 2);
                        final double availH = math.max(1.0, area.maxHeight - margin * 2);
                        double boxW = availW;
                        double boxH = boxW / ratio;
                        if (boxH > availH) {
                          boxH = availH;
                          boxW = boxH * ratio;
                        }
                        boxW = math.max(1.0, boxW.floorToDouble());
                        boxH = math.max(1.0, boxH.floorToDouble());
                        return Center(
                          child: SizedBox(
                            width: boxW,
                            height: boxH,
                            child: GlowFrame(child: LayoutBuilder(
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
                                      // batch 17B: while playing, Smooth (Native) shows the native video alone; Adaptive (Slow) shows the graded frame the loop put
                                      // there (every frame is graded before it is shown, so it is never old). Paused: the graded frame of THIS position (never a
                                      // stale one from before the video was played).
                                      final bool show = _isPlaying
                                          ? (has && _adaptiveActive && !_gradeStale)
                                          : (has && !_gradeStale);
                                      if (show) {
                                        return FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            // the picture's own size: _renderWidth / _renderHeight already switched to full quality on a pause while the
                                            // lower-quality frame of the playback is still on screen
                                            width: _processedStaticImage!.width.toDouble(),
                                            height: _processedStaticImage!.height.toDouble(),
                                            child: RawImage(image: _processedStaticImage),
                                          ),
                                        );
                                      }
                                      // the spinner only runs while a grade is really in progress (or the media is still opening), never forever
                                      final mediaOpening = !_project.isImage && (_controller == null || !_controller!.value.isInitialized);
                                      if (!_isPlaying && !has && (_isVulkanProcessing || mediaOpening)) {
                                        return const Center(child: CircularProgressIndicator(color: Colors.white38));
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),

                                  _buildTextSuiteBoundingBoxOverlay(constraints),

                                  if (_preparingMedia)
                                    Positioned(
                                      left: 12,
                                      right: 12,
                                      bottom: 12,
                                      child: IgnorePointer(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                          child: Text(
                                            _preparingNote,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              ),
                            );
                          },
                        ))));
                      },
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
                  color: kEditorDark,
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
                        onEnded: () { // batch 17A: Curves Opacity slider now lives in the Curves tab
                          setState(() {});
                          _pushUndoSnapshot();
                          _autoSaveProject();
                          _applyGrade();
                        },
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
