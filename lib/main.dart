import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:image/image.dart' as img;

import 'constants.dart';
import 'models.dart';
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
    debugPrint('FFmpeg startup message: $e');
  }

  runApp(const AERealityApp());
}

class AERealityApp extends StatelessWidget {
  const AERealityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: gCustomAccentColor,
      builder: (context, accentColor, _) {
        return MaterialApp(
          title: 'AEReality Studio Pro',
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projs = await ProjectManager.loadProjects();
    if (mounted) setState(() => _recent = projs);
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          final List<Color> palette = [
            const Color(0xFF7FFFD4),
            const Color(0xFF00E5FF),
            const Color(0xFFFFD700),
            const Color(0xFF7C4DFF),
            const Color(0xFFFF5252),
            const Color(0xFF69F0AE),
            const Color(0xFFFF4081),
            const Color(0xFFFFFFFF),
          ];

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
                  const Text('APP THEME ACCENT COLOR', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: palette.map((col) {
                      final isSel = gCustomAccentColor.value.value == col.value;
                      return GestureDetector(
                        onTap: () {
                          setModal(() => gCustomAccentColor.value = col);
                          setState(() {});
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSel ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: isSel ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('TIMELINE PREVIEW QUALITY', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('25% Draft'),
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
                        label: const Text('100% Native'),
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.layers_rounded, color: gCustomAccentColor.value, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Grading Engine: Multi-Layer 32-bit Floating-Point Compositor (Max 4 Layers).',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Save & Apply', style: TextStyle(color: gCustomAccentColor.value, fontWeight: FontWeight.bold)),
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
              child: Text('AE', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Text('AEReality Studio Pro'),
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
                    '4-LAYER PIPELINE',
                    style: TextStyle(color: accent, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Anime WIS & Layer Studio', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Adjustment Layers, Physical Inverse-Square Bloom, AE Knockoffs & 4K Master Pipeline.',
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved presets/sessions yet.')));
                      }
                    },
                    icon: Icon(Icons.bookmarks_rounded, color: accent, size: 18),
                    label: Text('SAVED', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
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
            const Text('RECENT SESSIONS', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = _recent[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: kCardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ListTile(
                        leading: Icon(p.data.isImage ? Icons.image_rounded : Icons.movie_creation_rounded, color: accent),
                        title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${p.mediaPath.split('/').last} • ${p.data.layers.length} Layers • ${p.data.aspectRatio}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
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
  String _projectName = 'AEReality Master';
  String _selectedAspect = '4:5';
  File? _selectedFile;
  bool _isImage = false;

  final List<String> _aspectRatios = ['4:5', '9:16', '16:9', '1:1', '3:4', '21:9'];

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
              onChanged: (val) => _projectName = val.isNotEmpty ? val : 'AEReality Master',
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
                  type: FileType.custom,
                  allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'],
                );
                if (result != null && result.files.single.path != null) {
                  final p = result.files.single.path!;
                  final ext = p.split('.').last.toLowerCase();
                  final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
                  setState(() {
                    _selectedFile = File(p);
                    _isImage = isImg;
                  });
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
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  img.Image? _cachedRawImage;
  bool _isFullScreen = false;

  late TabController _tabController;
  int _selectedCurveChannel = 0;

  ui.Image? _processedImage;
  int _renderWidth = 720;
  int _renderHeight = 900;

  AdjustmentLayer get _cur => _project.currentLayer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadShader();

    _project = widget.initialProject ?? ProjectData(mediaPath: '');
    _loadMedia(_project.mediaPath);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _processedImage?.dispose();
    super.dispose();
  }

  Map<String, int> _calculateTargetDimensions(String resolutionName, String ratioStr) {
    int baseSize;
    switch (resolutionName) {
      case '720p':  baseSize = 720; break;
      case '1080p': baseSize = 1080; break;
      case '2K':    baseSize = 1440; break;
      case '4K':    baseSize = 2160; break;
      default:      baseSize = 1080;
    }

    final double ratio = _getAspectRatioValue(ratioStr);
    int targetW, targetH;

    if (ratio < 1.0) {
      targetW = baseSize;
      targetH = (targetW / ratio).round();
    } else {
      targetH = baseSize;
      targetW = (targetH * ratio).round();
    }

    targetW = ((targetW + 15) ~/ 16) * 16;
    targetH = ((targetH + 15) ~/ 16) * 16;

    return {'width': targetW, 'height': targetH};
  }

  void _updateDimensions(int srcW, int srcH) {
    final dims = _calculateTargetDimensions('720p', _project.aspectRatio);
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

    if (_controller != null) {
      await _controller!.pause();
      await _controller!.dispose();
      _controller = null;
    }

    setState(() {
      _project.mediaPath = path;
      _project.isImage = isImg;
      _processedImage?.dispose();
      _processedImage = null;
      _isPlaying = false;
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
          setState(() {});
          _controller!.play();
          _controller!.setLooping(true);
          _isPlaying = true;
          _applyGrade();
        });
    }

    _autoSaveProject();
  }

  Future<void> _applyGrade() async {
    try {
      Uint8List? rawBytes;
      int w = _renderWidth;
      int h = _renderHeight;

      if (_project.isImage && _cachedRawImage != null) {
        final resized = img.copyResize(_cachedRawImage!, width: w, height: h);
        rawBytes = resized.getBytes(order: img.ChannelOrder.rgba);
      } else if (_project.mediaPath.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final previewFramePath = '${dir.path}/preview_frame.png';
        final posSec = _controller != null ? _controller!.value.position.inMilliseconds / 1000.0 : 0.0;
        await FFmpegKit.execute(
          '-hide_banner -ss $posSec -i "${_project.mediaPath}" -vframes 1 -s ${w}x$h -pix_fmt rgba -y "$previewFramePath"',
        );
        final file = File(previewFramePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final decoded = img.decodePng(bytes);
          if (decoded != null) {
            rawBytes = decoded.getBytes(order: img.ChannelOrder.rgba);
          }
        }
      }

      if (rawBytes == null) return;

      final uniforms = _packMultiLayerUniforms(w.toDouble(), h.toDouble());
      final outBytes = processImage(rawBytes, w, h, w, h, uniforms);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(outBytes, w, h, ui.PixelFormat.rgba8888, (img) => completer.complete(img));
      final res = await completer.future;

      if (mounted) {
        setState(() {
          _processedImage?.dispose();
          _processedImage = res;
        });
      }
    } catch (_) {}
  }

  Future<void> _autoSaveProject() async {
    if (_project.mediaPath.isEmpty) return;
    final proj = StoredProject(
      id: widget.projectName ?? 'session_${DateTime.now().millisecondsSinceEpoch}',
      name: widget.projectName ?? 'AEReality Session',
      mediaPath: _project.mediaPath,
      data: _project,
      lastOpened: DateTime.now(),
    );
    await ProjectManager.saveProject(proj);
  }

  Float32List _packMultiLayerUniforms(double imgW, double imgH) {
    // 8 global floats + (4 layers * 51 floats) = 212 floats
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
      final offset = 8 + (l * 51);

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
      uniforms[offset + 15] = layer.lineChromaStrength * 0.35;
      uniforms[offset + 16] = layer.volRaysLength;
      uniforms[offset + 17] = layer.volRaysDecay;

      uniforms[offset + 18] = layer.shadows + layer.mblColoristaLift;
      uniforms[offset + 19] = layer.highlights + layer.mblColoristaGain;
      uniforms[offset + 20] = layer.blackCrush;
      uniforms[offset + 21] = layer.vignette;
      uniforms[offset + 22] = layer.vignetteBoxed;
      uniforms[offset + 23] = layer.edgeDarken;
      uniforms[offset + 24] = layer.darkOutlines;
      uniforms[offset + 25] = layer.denoise;
      uniforms[offset + 26] = layer.filmGrain;
      uniforms[offset + 27] = layer.flickerIntensity;
      uniforms[offset + 28] = layer.flickerSpeed;
      uniforms[offset + 29] = layer.halationRadius;
      uniforms[offset + 30] = layer.halationWarmth;
      uniforms[offset + 31] = layer.depthOfField;
      uniforms[offset + 32] = layer.dofFocus;
      uniforms[offset + 33] = layer.mblMojoTealOrange;
      uniforms[offset + 34] = layer.fourColorGradMix;

      // Master curve P0..P4
      uniforms[offset + 35] = layer.curveMaster[0];
      uniforms[offset + 36] = layer.curveMaster[1];
      uniforms[offset + 37] = layer.curveMaster[2];
      uniforms[offset + 38] = layer.curveMaster[3];
      uniforms[offset + 39] = layer.curveMaster[4];

      // Red curve P0..P4
      uniforms[offset + 40] = layer.curveRed[0];
      uniforms[offset + 41] = layer.curveRed[1];
      uniforms[offset + 42] = layer.curveRed[2];
      uniforms[offset + 43] = layer.curveRed[3];
      uniforms[offset + 44] = layer.curveRed[4];

      // Green curve P0..P4
      uniforms[offset + 45] = layer.curveGreen[0];
      uniforms[offset + 46] = layer.curveGreen[1];
      uniforms[offset + 47] = layer.curveGreen[2];
      uniforms[offset + 48] = layer.curveGreen[3];
      uniforms[offset + 49] = layer.curveGreen[4];

      // Blue curve (first anchor)
      uniforms[offset + 50] = layer.curveBlue[2];
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
      default: return 4 / 5;
    }
  }

  void _addNewAdjustmentLayer() {
    if (_project.layers.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 4 Adjustment Layers allowed for FP32 performance.')));
      return;
    }
    setState(() {
      final newIndex = _project.layers.length + 1;
      _project.layers.add(AdjustmentLayer(
        id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Layer $newIndex',
        blendMode: LayerBlendMode.screen,
      ));
      _project.activeLayerIndex = _project.layers.length - 1;
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _removeCurrentLayer() {
    if (_project.layers.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the last remaining layer.')));
      return;
    }
    setState(() {
      _project.layers.removeAt(_project.activeLayerIndex);
      _project.activeLayerIndex = math.max(0, _project.activeLayerIndex - 1);
    });
    _applyGrade();
    _autoSaveProject();
  }

  void _resetCurrentLayer() {
    setState(() {
      _project.layers[_project.activeLayerIndex] = AdjustmentLayer(
        id: _cur.id,
        name: _cur.name,
        blendMode: _cur.blendMode,
      );
    });
    _applyGrade();
    _autoSaveProject();
  }

  // 13 Full Anime WIS CC Presets (Strictly calibrated without blackouts)
  void _applyPreset(String name) {
    setState(() {
      _project.layers.clear();

      switch (name) {
        case 'Gojo':
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_base',
            name: 'Base Grade',
            contrast: 1.16,
            saturation: 1.06,
            brightness: 0.01,
            temperature: 7100.0,
            sharpness: 0.28,
            shadows: -0.05,
            edgeDarken: 0.20,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.22, 0.50, 0.80, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'gojo_bloom',
            name: 'Infinity Cyan Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.55,
            deepGlowRadius: 0.65,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.15,
          ));
          break;

        case 'Raiden':
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_base',
            name: 'Shogun Contrast',
            contrast: 1.20,
            saturation: 1.12,
            temperature: 6800.0,
            sharpness: 0.30,
            shadows: -0.06,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.21, 0.49, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'raiden_glow',
            name: 'Electro Violet Glow',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.55,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 5.0,
            halationRadius: 0.12,
          ));
          break;

        case 'bina':
          _project.layers.add(AdjustmentLayer(
            id: 'bina_base',
            name: 'Dreamcore Base',
            contrast: 1.10,
            saturation: 1.08,
            brightness: 0.02,
            gamma: 0.98,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.02, 0.26, 0.52, 0.84, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'bina_glow',
            name: 'Radiant Pastel Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.75,
            deepGlowIntensity: 0.50,
            deepGlowRadius: 0.75,
            deepGlowThreshold: 0.35,
            edgeGlowTint: 0.0,
          ));
          break;

        case 'potential, man.':
          _project.layers.add(AdjustmentLayer(
            id: 'pot_base',
            name: 'Shadows & Ink',
            contrast: 1.22,
            saturation: 1.04,
            temperature: 6400.0,
            sharpness: 0.35,
            shadows: -0.08,
            edgeDarken: 0.25,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.21, 0.50, 0.81, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'pot_glow',
            name: 'Specular Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.70,
            deepGlowIntensity: 0.40,
            deepGlowRadius: 0.50,
            deepGlowThreshold: 0.48,
          ));
          break;

        case 'potential 2.0':
          _project.layers.add(AdjustmentLayer(
            id: 'pot2_base',
            name: 'Wheel Contrast',
            contrast: 1.24,
            saturation: 1.15,
            temperature: 6600.0,
            sharpness: 0.30,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.84, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'pot2_rays',
            name: 'Mahoraga Rays & Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.55,
            deepGlowRadius: 0.70,
            deepGlowThreshold: 0.38,
            edgeGlowTint: 1.0,
            volRaysLength: 0.22,
          ));
          break;

        case 'maki':
          _project.layers.add(AdjustmentLayer(
            id: 'maki_base',
            name: 'Cursed Steel Clarity',
            contrast: 1.22,
            saturation: 1.05,
            temperature: 6200.0,
            sharpness: 0.38,
            shadows: -0.05,
            edgeDarken: 0.30,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.22, 0.50, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'maki_streak',
            name: 'Blade Flare & Glow',
            blendMode: LayerBlendMode.screen,
            opacity: 0.75,
            deepGlowIntensity: 0.38,
            deepGlowRadius: 0.52,
            deepGlowThreshold: 0.42,
            thinStreakIntensity: 0.25,
          ));
          break;

        case 'yuta':
          _project.layers.add(AdjustmentLayer(
            id: 'yuta_base',
            name: 'Rika Cursed Aura',
            contrast: 1.24,
            saturation: 1.08,
            temperature: 7000.0,
            sharpness: 0.32,
            shadows: -0.07,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'yuta_glow',
            name: 'Cold Specular Bleed',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.48,
            deepGlowRadius: 0.62,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 2.0,
          ));
          break;

        case 'uryu':
          _project.layers.add(AdjustmentLayer(
            id: 'uryu_base',
            name: 'Heilig Bogen Precision',
            contrast: 1.26,
            saturation: 1.10,
            temperature: 7400.0,
            sharpness: 0.40,
            shadows: -0.08,
            edgeDarken: 0.22,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.21, 0.51, 0.83, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'uryu_rays',
            name: 'Quincy Arrow Rays',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.60,
            deepGlowRadius: 0.68,
            deepGlowThreshold: 0.36,
            edgeGlowTint: 2.0,
            volRaysLength: 0.25,
            thinStreakIntensity: 0.20,
          ));
          break;

        case 'saber':
          _project.layers.add(AdjustmentLayer(
            id: 'saber_base',
            name: 'Excalibur Radiant Steel',
            contrast: 1.20,
            saturation: 1.14,
            temperature: 6600.0,
            sharpness: 0.32,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.22, 0.50, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'saber_glow',
            name: 'Golden Divine Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.58,
            deepGlowRadius: 0.72,
            deepGlowThreshold: 0.38,
            edgeGlowTint: 1.0,
            thinStreakIntensity: 0.18,
          ));
          break;

        case 'sukuna':
          _project.layers.add(AdjustmentLayer(
            id: 'sukuna_base',
            name: 'Malevolent Shrine',
            contrast: 1.28,
            saturation: 1.16,
            temperature: 6100.0,
            shadows: -0.10,
            sharpness: 0.34,
            edgeDarken: 0.25,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.19, 0.49, 0.83, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'sukuna_crimson',
            name: 'Crimson Halation Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.85,
            deepGlowIntensity: 0.50,
            deepGlowRadius: 0.55,
            deepGlowThreshold: 0.40,
            edgeGlowTint: 4.0,
            halationRadius: 0.22,
            halationWarmth: 0.75,
          ));
          break;

        case 'sasuke':
          _project.layers.add(AdjustmentLayer(
            id: 'sasuke_base',
            name: 'Chidori Steel Midtones',
            contrast: 1.25,
            saturation: 1.06,
            temperature: 6900.0,
            sharpness: 0.38,
            shadows: -0.09,
            edgeDarken: 0.28,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.81, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'sasuke_flare',
            name: 'Lightning Streak Flare',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.58,
            deepGlowThreshold: 0.42,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.35,
          ));
          break;

        case 'toji':
          _project.layers.add(AdjustmentLayer(
            id: 'toji_base',
            name: 'Heavenly Restriction Ink',
            contrast: 1.30,
            saturation: 1.02,
            temperature: 6200.0,
            sharpness: 0.42,
            shadows: -0.12,
            edgeDarken: 0.35,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.18, 0.48, 0.80, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'toji_spec',
            name: 'Inverted Spear Specular',
            blendMode: LayerBlendMode.screen,
            opacity: 0.70,
            deepGlowIntensity: 0.35,
            deepGlowRadius: 0.45,
            deepGlowThreshold: 0.50,
          ));
          break;

        case 'shiki':
          _project.layers.add(AdjustmentLayer(
            id: 'shiki_base',
            name: 'Mystic Eyes Clarity',
            contrast: 1.26,
            saturation: 1.12,
            temperature: 6700.0,
            sharpness: 0.40,
            shadows: -0.08,
            edgeDarken: 0.30,
            blendMode: LayerBlendMode.normal,
            curveMaster: [0.0, 0.20, 0.50, 0.82, 1.0],
          ));
          _project.layers.add(AdjustmentLayer(
            id: 'shiki_glow',
            name: 'Death Perception Bloom',
            blendMode: LayerBlendMode.screen,
            opacity: 0.80,
            deepGlowIntensity: 0.52,
            deepGlowRadius: 0.60,
            deepGlowThreshold: 0.38,
            edgeGlowTint: 2.0,
            thinStreakIntensity: 0.22,
          ));
          break;
      }

      _project.activeLayerIndex = 0;
    });

    _applyGrade();
    _autoSaveProject();
  }

  void _showExportSheet() {
    if (_project.isImage) {
      _exportStaticImage();
      return;
    }

    String selectedContainer = 'MP4';
    String selectedCodec = 'H.264 (Hardware MediaCodec)';
    String selectedBitDepth = '10-bit';
    String selectedRes = '1080p';
    String selectedFps = '60fps';
    String selectedBitrate = '35 Mbps';

    final containers = ['MP4', 'WebM', 'MOV', 'MKV'];
    final resolutions = ['720p', '1080p', '2K', '4K'];
    final fpsOptions = ['24fps', '30fps', '60fps', '90fps'];
    final bitrateOptions = ['15 Mbps', '35 Mbps', '50 Mbps', '80 Mbps', '120 Mbps'];

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
                      '${targetDims['width']} x ${targetDims['height']} • Audio: ${ExportMatrix.getAudioCodec(selectedContainer)} • Layers: ${_project.layers.length}',
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
                            });
                          }
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    Text('CODEC FOR $selectedContainer', style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: availableCodecs.map((codec) => ChoiceChip(
                        label: Text(codec),
                        selected: selectedCodec == codec,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedCodec == codec ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedCodec = codec);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('BIT-DEPTH PRECISION', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('8-bit'),
                            selected: selectedBitDepth == '8-bit',
                            selectedColor: accent,
                            backgroundColor: const Color(0xFF18181E),
                            labelStyle: TextStyle(color: selectedBitDepth == '8-bit' ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                            onSelected: (_) => setStateModal(() => selectedBitDepth = '8-bit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('10-bit'),
                            selected: selectedBitDepth == '10-bit',
                            selectedColor: accent,
                            backgroundColor: const Color(0xFF18181E),
                            labelStyle: TextStyle(color: selectedBitDepth == '10-bit' ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                            onSelected: (_) => setStateModal(() => selectedBitDepth = '10-bit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('16-bit (MKV)'),
                            selected: selectedBitDepth == '16-bit',
                            selectedColor: accent,
                            backgroundColor: const Color(0xFF18181E),
                            labelStyle: TextStyle(color: selectedBitDepth == '16-bit' ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                            onSelected: (_) => setStateModal(() => selectedBitDepth = '16-bit'),
                          ),
                        ),
                      ],
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
                      children: bitrateOptions.map((bit) => ChoiceChip(
                        label: Text(bit),
                        selected: selectedBitrate == bit,
                        selectedColor: accent,
                        backgroundColor: const Color(0xFF18181E),
                        labelStyle: TextStyle(color: selectedBitrate == bit ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                        onSelected: (sel) {
                          if (sel) setStateModal(() => selectedBitrate = bit);
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportVideo(selectedRes, selectedFps, selectedBitrate, selectedContainer, selectedCodec, selectedBitDepth);
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

  // Strictly route exports to /storage/emulated/0/Download
  Future<String> _getSafeMovieDirectory() async {
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
      final fileName = 'AEReality_Graded_${DateTime.now().millisecondsSinceEpoch}.png';
      final destFile = File('$folderPath/$fileName');
      await destFile.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Graded Image Saved to Downloads:\n${destFile.path}'), backgroundColor: Colors.green),
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
    final bool is10Bit = bitDepth == '10-bit';

    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Extracting pristine frames: 0%');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101014),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Exporting $outW x $outH Master ($bitDepth)', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
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

      statusNotifier.value = 'Extracting pristine frames...';
      final extractSession = await FFmpegKit.execute(
        '-hide_banner -i "$videoPath" -r $targetFps -s ${outW}x${outH} -pix_fmt rgba -y "${framesDir.path}/frame_%05d.png"',
      );

      var frameFiles = await framesDir.list().toList();
      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      final totalFrames = frameFiles.length;

      if (totalFrames == 0) {
        final logs = await extractSession.getLogsAsString();
        throw Exception('Frame extraction failed. Logs: ${logs ?? "No logs"}');
      }

      for (int i = 0; i < totalFrames; i++) {
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
        statusNotifier.value = 'Grading frames: $percent% (${i + 1}/$totalFrames)';
      }

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

      if (!await silentFile.exists()) {
        final logs = await encodeSession.getLogsAsString();
        throw Exception('Encoder failed to generate video. Logs: ${logs ?? "No logs"}');
      }

      final hasAudio = await File(audioPath).exists() && (await File(audioPath).length()) > 1000;
      final moviesDir = await _getSafeMovieDirectory();
      final cleanCodec = codec.split(' ').first;
      final fileName = 'AEReality_${resolution}_${cleanCodec}_${bitDepth}_${DateTime.now().millisecondsSinceEpoch}.$containerExt';
      final finalOutputFile = File('$moviesDir/$fileName');

      if (hasAudio) {
        final audioCodec = ExportMatrix.getAudioCodec(container);
        await FFmpegKit.execute('-hide_banner -i "$silentOutputPath" -i "$audioPath" -c:v copy -c:a $audioCodec -shortest -y "${finalOutputFile.path}"');
      } else {
        await File(silentOutputPath).copy(finalOutputFile.path);
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Master Video Exported to Downloads:\n${finalOutputFile.path}'), backgroundColor: Colors.green),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildSliderRow(String title, double val, double min, double max, ValueChanged<double> onChanged) {
    final accent = gCustomAccentColor.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(
                val.toStringAsFixed(2),
                style: TextStyle(color: accent, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: val.clamp(min, max),
              min: min,
              max: max,
              onChanged: (newVal) {
                onChanged(newVal);
                _applyGrade();
              },
              onChangeEnd: (_) => _autoSaveProject(),
            ),
          ),
        ],
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
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _project.layers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final l = _project.layers[idx];
                  final isSel = _project.activeLayerIndex == idx;
                  return GestureDetector(
                    onTap: () => setState(() => _project.activeLayerIndex = idx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel ? accent.withOpacity(0.18) : kCardDark,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSel ? accent : Colors.white12),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(() => l.isEnabled = !l.isEnabled);
                              _applyGrade();
                            },
                            child: Icon(
                              l.isEnabled ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                              color: l.isEnabled ? (isSel ? accent : Colors.white70) : Colors.white24,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l.name,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white60,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
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
          if (_project.layers.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
              tooltip: 'Remove Active Layer',
              onPressed: _removeCurrentLayer,
            ),
        ],
      ),
    );
  }

  Widget _buildLayerSettingsHeader() {
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
              ),
            ),
          ),
          Text('${(_cur.opacity * 100).toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = gCustomAccentColor.value;

    return WillPopScope(
      onWillPop: () async {
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
              if (_controller != null) {
                await _controller!.pause();
                await _controller!.dispose();
                _controller = null;
              }
              Navigator.pop(context);
            },
          ),
          title: Text(widget.projectName ?? 'AEReality Editor'),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_open_rounded, color: kGold),
              tooltip: 'Import New Footage/Art',
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', 'png', 'jpg', 'jpeg', 'webp'],
                );
                if (result != null && result.files.single.path != null) {
                  _loadMedia(result.files.single.path!);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white70),
              tooltip: 'Save Session',
              onPressed: () async {
                await _autoSaveProject();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project saved successfully!'), backgroundColor: Colors.teal));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              tooltip: 'Reset Current Layer',
              onPressed: _resetCurrentLayer,
            ),
            IconButton(
              icon: Icon(Icons.movie_creation_outlined, color: accent),
              tooltip: 'Master Render Pipeline',
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
                          VideoPlayer(_controller!),

                        if (_processedImage != null)
                          RawImage(image: _processedImage, fit: BoxFit.contain),

                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Row(
                            children: [
                              if (!_project.isImage && _controller != null)
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
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Icon(
                                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              GestureDetector(
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (!_isFullScreen) ...[
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
                    Tab(text: 'AE KNOCKOFFS'),
                    Tab(text: 'GRADE'),
                    Tab(text: 'CURVES'),
                    Tab(text: 'GLOWS'),
                    Tab(text: 'SAPPHIRE/AE'),
                    Tab(text: 'MAGIC BULLET'),
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
                      _buildAEKnockoffsTab(),
                      _buildGradingTab(),
                      _buildCurvesTab(),
                      _buildGlowsTab(),
                      _buildSapphireTab(),
                      _buildMagicBulletTab(),
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

  Widget _buildPresetsTab() {
    final presets = [
      {'name': 'Gojo', 'desc': 'Infinity cyan specular bloom & clean line contrast', 'color': 0xFF00E5FF},
      {'name': 'Raiden', 'desc': 'Electro violet & cyan split, protected skin tones', 'color': 0xFF7C4DFF},
      {'name': 'bina', 'desc': 'Radiant dreamcore soft glow, gentle pastel lift', 'color': 0xFFF48FB1},
      {'name': 'potential, man.', 'desc': 'High midtone clarity, deep ink shadows', 'color': 0xFF3F51B5},
      {'name': 'potential 2.0', 'desc': 'Mahoraga wheel radiance, golden-white bloom', 'color': 0xFFFFB300},
      {'name': 'maki', 'desc': 'High-acutance micro-contrast, crisp blade flare', 'color': 0xFF00B0FF},
      {'name': 'yuta', 'desc': 'Rika cursed energy cold specular aura', 'color': 0xFF40C4FF},
      {'name': 'uryu', 'desc': 'Quincy arrow volumetric light shafts & streak', 'color': 0xFF00E5FF},
      {'name': 'saber', 'desc': 'Excalibur radiant steel & golden divine bloom', 'color': 0xFFFFD700},
      {'name': 'sukuna', 'desc': 'Malevolent crimson halation & bone speculars', 'color': 0xFFE53935},
      {'name': 'sasuke', 'desc': 'Chidori electrical streak flare & steel midtones', 'color': 0xFF00B0FF},
      {'name': 'toji', 'desc': 'Heavenly restriction high-contrast ink shadow', 'color': 0xFF78909C},
      {'name': 'shiki', 'desc': 'Mystic eyes of death perception cyan bloom', 'color': 0xFF00E676},
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: presets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = presets[i];
        return GestureDetector(
          onTap: () => _applyPreset(item['name'] as String),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kCardDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 36,
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
                      Text(item['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(item['desc'] as String, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAEKnockoffsTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('DEEP GLOW SUITE (INVERSE-SQUARE NO-RING BLOOM)', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _buildSliderRow('Deep Glow Intensity', _cur.deepGlowIntensity, 0.0, 1.5, (v) => setState(() => _cur.deepGlowIntensity = v)),
        _buildSliderRow('Deep Glow Radius (Falloff)', _cur.deepGlowRadius, 0.1, 1.0, (v) => setState(() => _cur.deepGlowRadius = v)),
        _buildSliderRow('Soft Knee Threshold', _cur.deepGlowThreshold, 0.1, 0.9, (v) => setState(() => _cur.deepGlowThreshold = v)),

        const SizedBox(height: 14),
        Text('LINE ART INTERIOR EDGE DARKEN & SOBEL', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _buildSliderRow('Interior Edge Shadow (Depth)', _cur.edgeDarken, 0.0, 1.0, (v) => setState(() => _cur.edgeDarken = v)),
        _buildSliderRow('Sobel Outline Sharpness', _cur.darkOutlines, 0.0, 1.0, (v) => setState(() => _cur.darkOutlines = v)),

        const SizedBox(height: 14),
        Text('EDGE-TARGETED CHROMATIC ABERRATION', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _buildSliderRow('Line-Art Dispersion Strength', _cur.lineChromaStrength, 0.0, 1.0, (v) => setState(() => _cur.lineChromaStrength = v)),

        const SizedBox(height: 14),
        Text('SAPPHIRE S_EDGERAYS (VOLUMETRIC OCCLUDED SHAFTS)', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _buildSliderRow('Ray Shaft Length', _cur.volRaysLength, 0.0, 1.0, (v) => setState(() => _cur.volRaysLength = v)),
        _buildSliderRow('Exponential Ray Decay', _cur.volRaysDecay, 0.70, 0.98, (v) => setState(() => _cur.volRaysDecay = v)),

        const SizedBox(height: 14),
        Text('SAPPHIRE 1D ANAMORPHIC STREAK FLARE', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _buildSliderRow('Thin Streak Flare Intensity', _cur.thinStreakIntensity, 0.0, 1.0, (v) => setState(() => _cur.thinStreakIntensity = v)),

        const SizedBox(height: 14),
        Text('FILM HALATION & SUBTRACTIVE DENSITY', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _buildSliderRow('Edge Red Halation Bleed', _cur.halationRadius, 0.0, 1.0, (v) => setState(() => _cur.halationRadius = v)),
        _buildSliderRow('Halation Warmth', _cur.halationWarmth, 0.0, 1.0, (v) => setState(() => _cur.halationWarmth = v)),
      ],
    );
  }

  Widget _buildGradingTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
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
        _buildSliderRow('Soft Radial Vignette', _cur.vignette, 0.0, 0.5, (v) => setState(() => _cur.vignette = v)),
        _buildSliderRow('Boxed Vignette', _cur.vignetteBoxed, 0.0, 0.5, (v) => setState(() => _cur.vignetteBoxed = v)),
        _buildSliderRow('Film Grain', _cur.filmGrain, 0.0, 0.3, (v) => setState(() => _cur.filmGrain = v)),
        _buildSliderRow('Color Temperature (K)', _cur.temperature, 3000.0, 9500.0, (v) => setState(() => _cur.temperature = v)),
        _buildSliderRow('Sinusoidal Flicker', _cur.flickerIntensity, 0.0, 1.0, (v) => setState(() => _cur.flickerIntensity = v)),
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
      padding: const EdgeInsets.all(14),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 14),
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
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildSliderRow('Gaussian Bloom Intensity', _cur.deepGlowIntensity, 0.0, 1.5, (v) => setState(() => _cur.deepGlowIntensity = v)),
        _buildSliderRow('Bloom Spread (Smoothness)', _cur.deepGlowRadius, 0.0, 1.0, (v) => setState(() => _cur.deepGlowRadius = v)),
        _buildSliderRow('Bright-Pass Threshold', _cur.deepGlowThreshold, 0.0, 1.0, (v) => setState(() => _cur.deepGlowThreshold = v)),
        const SizedBox(height: 10),
        const Text('BLOOM TINT HARMONY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _buildTintChip('Neutral', 0.0),
            _buildTintChip('Gold / Warm', 1.0),
            _buildTintChip('Quincy Cyan', 2.0),
            _buildTintChip('Black / Ink', 3.0),
            _buildTintChip('Crimson', 4.0),
            _buildTintChip('Shogun Violet', 5.0),
          ],
        ),
        const SizedBox(height: 14),
        _buildSliderRow('Thin Anamorphic Flare', _cur.thinStreakIntensity, 0.0, 1.0, (v) => setState(() => _cur.thinStreakIntensity = v)),
        _buildSliderRow('Light Rays / God Rays', _cur.volRaysLength, 0.0, 1.0, (v) => setState(() => _cur.volRaysLength = v)),
        _buildSliderRow('Light Rays Decay', _cur.volRaysDecay, 0.7, 0.98, (v) => setState(() => _cur.volRaysDecay = v)),
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
        setState(() => _cur.edgeGlowTint = code);
        _applyGrade();
        _autoSaveProject();
      },
    );
  }

  Widget _buildSapphireTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(14),
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
        const SizedBox(height: 14),
        _buildSliderRow('Bilateral Denoise', _cur.denoise, 0.0, 1.0, (v) => setState(() => _cur.denoise = v)),
        _buildSliderRow('Tilt-Shift Depth of Field', _cur.depthOfField, 0.0, 1.0, (v) => setState(() => _cur.depthOfField = v)),
        _buildSliderRow('DOF Focus Plane', _cur.dofFocus, 0.0, 1.0, (v) => setState(() => _cur.dofFocus = v)),
        _buildSliderRow('4-Corner Vignette Gradient', _cur.fourColorGradMix, 0.0, 1.0, (v) => setState(() => _cur.fourColorGradMix = v)),
      ],
    );
  }

  Widget _buildMagicBulletTab() {
    final accent = gCustomAccentColor.value;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('MAGIC BULLET SUITE MODULES', style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildSliderRow('MB Mojo (Teal Shadows & Orange Highlights)', _cur.mblMojoTealOrange, 0.0, 1.0, (v) => setState(() => _cur.mblMojoTealOrange = v)),
        const SizedBox(height: 16),
        const Text('MB COLORISTA 3-WAY WHEELS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ColoristaWheel(
              label: 'LIFT (BLACKS)',
              value: _cur.mblColoristaLift,
              accentColor: Colors.lightBlueAccent,
              onChanged: (v) {
                setState(() => _cur.mblColoristaLift = v);
                _applyGrade();
              },
            ),
            ColoristaWheel(
              label: 'GAMMA (MIDS)',
              value: _cur.mblColoristaGamma,
              accentColor: accent,
              onChanged: (v) {
                setState(() => _cur.mblColoristaGamma = v);
                _applyGrade();
              },
            ),
            ColoristaWheel(
              label: 'GAIN (WHITES)',
              value: _cur.mblColoristaGain,
              accentColor: kGold,
              onChanged: (v) {
                setState(() => _cur.mblColoristaGain = v);
                _applyGrade();
              },
            ),
          ],
        ),
      ],
    );
  }
}
