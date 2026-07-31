import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const AERealityApp());
}

class AERealityApp extends StatelessWidget {
  const AERealityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEReality',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------- HOME SCREEN ----------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AEReality'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library, size: 80, color: Colors.white24),
            const SizedBox(height: 20),
            const Text('No Project Open', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectScreen()));
              },
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('New Project', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- SETTINGS SCREEN ----------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _previewScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: const Color(0xFF0A0A0A)),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text('Preview Resolution', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('360p', style: TextStyle(color: Colors.white54)),
                Expanded(
                  child: Slider(
                    value: _previewScale,
                    min: 0.33,
                    max: 1.0,
                    divisions: 3,
                    activeColor: Colors.white,
                    inactiveColor: Colors.grey[800],
                    onChanged: (val) => setState(() => _previewScale = val),
                  ),
                ),
                const Text('1080p', style: TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 20),
            Text('Current: ${(_previewScale * 1080).toInt()}p', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ---------- PROJECT SCREEN ----------
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  ui.FragmentProgram? _fragmentProgram;

  // ----- Color Controls -----
  double _brightness = 0.0;
  double _saturation = 1.0;
  double _contrast = 1.0;
  double _sharpness = 0.0;
  double _gamma = 1.0;
  double _hue = 0.0;
  double _temperature = 6500.0;
  double _glowIntensity = 0.3;
  double _lookMix = 0.0;
  double _vignette = 0.0;
  double _splitToning = 0.0;

  late TabController _tabController;
  VoidCallback _listener = () {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/aereality_core.frag');
      if (mounted) setState(() => _fragmentProgram = program);
    } catch (e) {
      debugPrint('Shader load error: $e');
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      final path = result.files.single.path!;
      setState(() {
        _controller?.removeListener(_listener);
        _controller?.dispose();
        _controller = VideoPlayerController.file(File(path))
          ..initialize().then((_) {
            setState(() {});
            _listener = () {
              if (mounted) setState(() {}); // Update slider
            };
            _controller!.addListener(_listener);
            _controller!.play();
            _isPlaying = true;
          });
      });
    }
  }

  void _applyPreset(String name) {
    setState(() {
      switch (name) {
        case 'Gojo Edit':
          _brightness = -0.05;
          _saturation = 1.5;
          _contrast = 1.5;
          _sharpness = 0.6;
          _gamma = 0.9;
          _hue = -8.0;
          _temperature = 4800;
          _glowIntensity = 0.7;
          _vignette = 0.4;
          _splitToning = 0.3;
          break;
        case 'Magic Bullet':
          _brightness = 0.1;
          _saturation = 1.4;
          _contrast = 1.2;
          _sharpness = 0.3;
          _gamma = 1.0;
          _hue = 5.0;
          _temperature = 6500;
          _glowIntensity = 0.6;
          _vignette = 0.1;
          _splitToning = 0.0;
          break;
        case 'Teal & Orange':
          _brightness = 0.0;
          _saturation = 1.2;
          _contrast = 1.3;
          _sharpness = 0.2;
          _gamma = 0.9;
          _hue = -10.0;
          _temperature = 5500;
          _glowIntensity = 0.2;
          _vignette = 0.0;
          _splitToning = 0.2;
          break;
        default:
          break;
      }
    });
  }

  // ---------- FIXED EXPORT DIALOG (All buttons clickable) ----------
  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            String selectedRes = '1080p';
            String selectedFps = '60fps';
            String selectedBit = '35 Mbps';
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Export Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  const Text('Resolution', style: TextStyle(color: Colors.white70)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['720p', '1080p', '2K'].map((res) {
                      return ElevatedButton(
                        onPressed: () => setStateModal(() => selectedRes = res),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedRes == res ? Colors.white : Colors.grey[800],
                          foregroundColor: selectedRes == res ? Colors.black : Colors.white,
                        ),
                        child: Text(res),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Frame Rate', style: TextStyle(color: Colors.white70)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['30fps', '60fps', '90fps'].map((fps) {
                      return ElevatedButton(
                        onPressed: () => setStateModal(() => selectedFps = fps),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedFps == fps ? Colors.white : Colors.grey[800],
                          foregroundColor: selectedFps == fps ? Colors.black : Colors.white,
                        ),
                        child: Text(fps),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Bitrate', style: TextStyle(color: Colors.white70)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['15 Mbps', '35 Mbps', '50 Mbps'].map((bit) {
                      return ElevatedButton(
                        onPressed: () => setStateModal(() => selectedBit = bit),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedBit == bit ? Colors.white : Colors.grey[800],
                          foregroundColor: selectedBit == bit ? Colors.black : Colors.white,
                        ),
                        child: Text(bit),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Exporting: $selectedRes | $selectedFps | $selectedBit'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('RENDER VIDEO', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }
    @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project'),
        backgroundColor: const Color(0xFF0A0A0A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickVideo,
            tooltip: 'Import',
          ),
        ],
      ),
      body: Column(
        children: [
          // ---------- PREVIEW (ShaderMask with srcATop) ----------
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black,
              child: Center(
                child: _controller != null && _controller!.value.isInitialized
                    ? _fragmentProgram != null
                        ? ShaderMask(
                            shaderCallback: (rect) {
                              final shader = _fragmentProgram!.fragmentShader();
                              // Resolution (indices 0 & 1)
                              shader.setFloat(0, rect.width);
                              shader.setFloat(1, rect.height);
                              // Color sliders (indices 3-13)
                              shader.setFloat(3, _brightness);
                              shader.setFloat(4, _saturation);
                              shader.setFloat(5, _contrast);
                              shader.setFloat(6, _sharpness);
                              shader.setFloat(7, _gamma);
                              shader.setFloat(8, _hue);
                              shader.setFloat(9, _temperature);
                              shader.setFloat(10, _glowIntensity);
                              shader.setFloat(11, _lookMix);
                              shader.setFloat(12, _vignette);
                              shader.setFloat(13, _splitToning);
                              return shader;
                            },
                            blendMode: BlendMode.srcATop, // <-- BEST FOR VIDEO
                            child: VideoPlayer(_controller!),
                          )
                        : VideoPlayer(_controller!)
                    : Container(
                        color: const Color(0xFF1A1A1A),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_circle_outline, size: 60, color: Colors.white24),
                              SizedBox(height: 8),
                              Text('Tap Import to add video', style: TextStyle(color: Colors.white38)),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          // ---------- TIMELINE ----------
          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: _controller != null && _controller!.value.isInitialized
                      ? () => setState(() {
                          if (_controller!.value.isPlaying) {
                            _controller!.pause();
                            _isPlaying = false;
                          } else {
                            _controller!.play();
                            _isPlaying = true;
                          }
                        })
                      : null,
                ),
                Expanded(
                  child: Slider(
                    value: _controller != null && _controller!.value.isInitialized
                        ? _controller!.value.position.inSeconds.toDouble()
                        : 0.0,
                    min: 0,
                    max: _controller != null && _controller!.value.isInitialized
                        ? _controller!.value.duration.inSeconds.toDouble()
                        : 1.0,
                    activeColor: Colors.white,
                    inactiveColor: Colors.grey[800],
                    onChanged: (val) {
                      if (_controller != null && _controller!.value.isInitialized) {
                        _controller!.seekTo(Duration(seconds: val.toInt()));
                      }
                    },
                  ),
                ),
                Text(
                  _controller != null && _controller!.value.isInitialized
                      ? '${_controller!.value.position.inSeconds ~/ 60}:${(_controller!.value.position.inSeconds % 60).toString().padLeft(2, '0')}'
                      : '--:--',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
          // ---------- BOTTOM TOOLBAR ----------
          Container(
            color: const Color(0xFF141414),
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(icon: Icon(Icons.tune), text: 'Adjust'),
                    Tab(icon: Icon(Icons.auto_awesome), text: 'Presets'),
                    Tab(icon: Icon(Icons.save_alt), text: 'Export'),
                  ],
                ),
                SizedBox(
                  height: 190,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // ADJUST
                      ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _slider('Bright', -1.0, 1.0, _brightness, (v) => setState(() => _brightness = v)),
                          _slider('Sat', 0.0, 3.0, _saturation, (v) => setState(() => _saturation = v)),
                          _slider('Contrast', 0.0, 2.0, _contrast, (v) => setState(() => _contrast = v)),
                          _slider('Sharp', 0.0, 5.0, _sharpness, (v) => setState(() => _sharpness = v)),
                          _slider('Gamma', 0.1, 2.5, _gamma, (v) => setState(() => _gamma = v)),
                          _slider('Hue', -180, 180, _hue, (v) => setState(() => _hue = v)),
                          _slider('Temp', 2000, 12000, _temperature, (v) => setState(() => _temperature = v)),
                          _slider('Glow', 0.0, 1.0, _glowIntensity, (v) => setState(() => _glowIntensity = v)),
                          _slider('Vignette', 0.0, 1.0, _vignette, (v) => setState(() => _vignette = v)),
                          _slider('Split Tone', 0.0, 1.0, _splitToning, (v) => setState(() => _splitToning = v)),
                        ],
                      ),
                      // PRESETS
                      GridView.count(
                        crossAxisCount: 3,
                        padding: const EdgeInsets.all(8),
                        children: ['Gojo Edit', 'Magic Bullet', 'Teal & Orange', 'Film Grain', 'Vintage', 'Cinematic'].map((name) {
                          return GestureDetector(
                            onTap: () => _applyPreset(name),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[800]!),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.image, color: Colors.white24, size: 30),
                                  const SizedBox(height: 4),
                                  Text(name, style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      // EXPORT
                      Center(
                        child: ElevatedButton(
                          onPressed: _showExportSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                          ),
                          child: const Text('EXPORT VIDEO', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double min, double max, double val, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: Colors.white,
            inactiveColor: Colors.grey[800],
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(val.toStringAsFixed(1), style: const TextStyle(color: Colors.white38))),
      ],
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    super.dispose();
  }
}
