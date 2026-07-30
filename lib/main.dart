import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const AfterEffectsMobileApp());
}

class AfterEffectsMobileApp extends StatelessWidget {
  const AfterEffectsMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '32-Bit Pro Video Engine',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.deepPurpleAccent,
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.cyanAccent,
        ),
      ),
      home: const VideoEditorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Effect {
  final String name;
  double value;
  Effect({required this.name, this.value = 0.0});
}

class Layer {
  String id;
  String name;
  bool enabled;
  List<Effect> effects;

  Layer({
    required this.id,
    this.name = 'Layer',
    this.enabled = true,
    this.effects = const [],
  });

  Layer copyWith({String? id, String? name, bool? enabled, List<Effect>? effects}) {
    return Layer(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      effects: effects ?? this.effects,
    );
  }
}

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;

  double _brightness = 0.0;
  double _saturation = 1.0;
  double _contrast = 1.0;
  double _sharpness = 0.0;
  double _gamma = 1.0;
  double _hue = 0.0;
  double _temperature = 6500.0;
  double _glowIntensity = 0.3;
  double _lookMix = 0.0;

  List<Layer> _layers = [];
  int _layerCounter = 0;
  String _selectedRatio = "4:5";

  @override
  void initState() {
    super.initState();
    _addDefaultLayer();
  }

  void _addDefaultLayer() {
    setState(() {
      _layerCounter++;
      _layers.add(Layer(
        id: 'layer_$_layerCounter',
        name: 'Base Grade',
        effects: [
          Effect(name: 'Brightness', value: 0.0),
          Effect(name: 'Saturation', value: 1.0),
          Effect(name: 'Contrast', value: 1.0),
          Effect(name: 'Gamma', value: 1.0),
        ],
      ));
    });
  }

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    if (result != null) {
      final path = result.files.single.path!;
      setState(() {
        _controller?.dispose();
        _controller = VideoPlayerController.file(File(path))
          ..initialize().then((_) {
            setState(() {});
            _controller!.play();
            _isPlaying = true;
          });
      });
    }
  }

  void _addNewLayer() {
    setState(() {
      _layerCounter++;
      _layers.add(Layer(
        id: 'layer_$_layerCounter',
        name: 'Layer $_layerCounter',
        effects: [],
      ));
    });
  }

  void _removeLayer(int index) {
    setState(() {
      _layers.removeAt(index);
    });
  }

  void _addEffectToLayer(int layerIndex, Effect effect) {
    setState(() {
      _layers[layerIndex].effects.add(effect);
    });
  }

  void _removeEffectFromLayer(int layerIndex, int effectIndex) {
    setState(() {
      _layers[layerIndex].effects.removeAt(effectIndex);
    });
  }

  void _applyPreset(String presetName) {
    setState(() {
      switch (presetName) {
        case 'Magic Bullet':
          _brightness = 0.1;
          _saturation = 1.4;
          _contrast = 1.2;
          _sharpness = 0.3;
          _gamma = 1.0;
          _hue = 5.0;
          _temperature = 6500;
          _glowIntensity = 0.6;
          _lookMix = 0.8;
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
          _lookMix = 1.0;
          break;
        case 'Film Grain':
          _brightness = -0.05;
          _saturation = 0.9;
          _contrast = 1.1;
          _sharpness = 0.5;
          _gamma = 1.1;
          _hue = 0.0;
          _temperature = 6500;
          _glowIntensity = 0.1;
          _lookMix = 0.0;
          break;
        default:
          break;
      }
    });
  }

  void _showExportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            String selectedRes = '1080p';
            String selectedFps = '60fps';
            String selectedBit = '35 Mbps';
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vulkan Render & Export Settings',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                  const SizedBox(height: 16),
                  const Text('Resolution', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['720p', '1080p', '2K (Pro)'].map((res) {
                      return ChoiceChip(
                        label: Text(res),
                        selected: selectedRes == res,
                        onSelected: (sel) => setStateModal(() => selectedRes = res),
                        selectedColor: Colors.deepPurpleAccent,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Frame Rate', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['30fps', '60fps', '90fps (Ultra)'].map((fps) {
                      return ChoiceChip(
                        label: Text(fps),
                        selected: selectedFps == fps,
                        onSelected: (sel) => setStateModal(() => selectedFps = fps),
                        selectedColor: Colors.deepPurpleAccent,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Bitrate', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['15 Mbps', '35 Mbps', '50 Mbps (Lossless)'].map((bit) {
                      return ChoiceChip(
                        label: Text(bit),
                        selected: selectedBit == bit,
                        onSelected: (sel) => setStateModal(() => selectedBit = bit),
                        selectedColor: Colors.deepPurpleAccent,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Exporting $selectedRes @ $selectedFps | $selectedBit'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      child: const Text('Render Master Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        title: const Text('32-Bit Render Pipeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.cyanAccent),
            onPressed: _pickVideo,
            tooltip: 'Import Video',
          ),
          IconButton(
            icon: const Icon(Icons.ios_share, color: Colors.cyanAccent),
            tooltip: 'Export',
            onPressed: _showExportDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _getAspectRatioValue(_selectedRatio),
                  child: _controller != null && _controller!.value.isInitialized
                      ? ShaderMask(
                          shaderCallback: (rect) {
                            final shader = ui.FragmentShader(
                              'shaders/aereality_core.frag',
                            );
                            shader.setFloat(0, _brightness);
                            shader.setFloat(1, _saturation);
                            shader.setFloat(2, _contrast);
                            shader.setFloat(3, _sharpness);
                            shader.setFloat(4, _gamma);
                            shader.setFloat(5, _hue);
                            shader.setFloat(6, _temperature);
                            shader.setFloat(7, _glowIntensity);
                            shader.setFloat(8, _lookMix);
                            return shader;
                          },
                          blendMode: BlendMode.srcATop,
                          child: VideoPlayer(_controller!),
                        )
                      : Container(
                          color: const Color(0xFF252525),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.video_library, size: 50, color: Colors.white24),
                                const SizedBox(height: 8),
                                const Text('Import a video to start',
                                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: _controller != null && _controller!.value.isInitialized
                      ? () {
                          setState(() {
                            if (_controller!.value.isPlaying) {
                              _controller!.pause();
                              _isPlaying = false;
                            } else {
                              _controller!.play();
                              _isPlaying = true;
                            }
                          });
                        }
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
                    activeColor: Colors.deepPurpleAccent,
                    inactiveColor: Colors.white10,
                    onChanged: (val) {
                      if (_controller != null && _controller!.value.isInitialized) {
                        _controller!.seekTo(Duration(seconds: val.toInt()));
                      }
                    },
                  ),
                ),
                Text(
                  _controller != null && _controller!.value.isInitialized
                      ? '${(_controller!.value.position.inSeconds ~/ 60)}:${(_controller!.value.position.inSeconds % 60).toString().padLeft(2, '0')}'
                      : '--:--',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildVerticalSlider('Bright', -1.0, 1.0, _brightness, (v) => setState(() => _brightness = v)),
                _buildVerticalSlider('Sat', 0.0, 3.0, _saturation, (v) => setState(() => _saturation = v)),
                _buildVerticalSlider('Contrast', 0.0, 2.0, _contrast, (v) => setState(() => _contrast = v)),
                _buildVerticalSlider('Sharp', 0.0, 5.0, _sharpness, (v) => setState(() => _sharpness = v)),
                _buildVerticalSlider('Gamma', 0.1, 2.5, _gamma, (v) => setState(() => _gamma = v)),
                _buildVerticalSlider('Hue', -180, 180, _hue, (v) => setState(() => _hue = v)),
                _buildVerticalSlider('Temp', 2000, 12000, _temperature, (v) => setState(() => _temperature = v)),
                _buildVerticalSlider('Glow', 0.0, 1.0, _glowIntensity, (v) => setState(() => _glowIntensity = v)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF151515),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Text('LAYERS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.cyanAccent),
                          onPressed: _addNewLayer,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _layers.length,
                      itemBuilder: (context, index) {
                        final layer = _layers[index];
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          child: ExpansionTile(
                            leading: Icon(
                              layer.enabled ? Icons.visibility : Icons.visibility_off,
                              color: layer.enabled ? Colors.deepPurpleAccent : Colors.grey,
                              size: 16,
                            ),
                            title: Text(
                              layer.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: layer.enabled ? Colors.white : Colors.grey,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: layer.enabled,
                                  activeColor: Colors.cyanAccent,
                                  onChanged: (val) {
                                    setState(() {
                                      _layers[index] = layer.copyWith(enabled: val);
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                  onPressed: () => _removeLayer(index),
                                ),
                              ],
                            ),
                            children: [
                              ...layer.effects.asMap().entries.map((entry) {
                                final eIdx = entry.key;
                                final effect = entry.value;
                                return ListTile(
                                  dense: true,
                                  title: Text(effect.name, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 60,
                                        child: Slider(
                                          value: effect.value,
                                          min: 0.0,
                                          max: 2.0,
                                          activeColor: Colors.cyanAccent,
                                          onChanged: (val) {
                                            setState(() {
                                              _layers[index].effects[eIdx].value = val;
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                                        onPressed: () => _removeEffectFromLayer(index, eIdx),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[800],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  ),
                                  onPressed: () {
                                    _showAddEffectDialog(index);
                                  },
                                  icon: const Icon(Icons.add, size: 14),
                                  label: const Text('Add Effect', style: TextStyle(fontSize: 10)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBottomNavButton(Icons.aspect_ratio, 'Ratios', _showRatioSelector),
                _buildBottomNavButton(Icons.auto_awesome, 'Presets', _showPresetsSheet),
                _buildBottomNavButton(Icons.tune, 'Adjustments', () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Use the sliders above to adjust color')),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalSlider(String label, double min, double max, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.grey[800],
                onChanged: onChanged,
              ),
            ),
          ),
          Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 8, color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _buildBottomNavButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  double _getAspectRatioValue(String ratio) {
    switch (ratio) {
      case "4:5": return 4 / 5;
      case "16:9": return 16 / 9;
      case "1:1": return 1 / 1;
      default: return 4 / 5;
    }
  }

  void _showRatioSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: ["4:5", "16:9", "1:1"].map((ratio) {
              return ListTile(
                title: Text(ratio, style: const TextStyle(color: Colors.white)),
                trailing: _selectedRatio == ratio ? const Icon(Icons.check, color: Colors.cyanAccent) : null,
                onTap: () {
                  setState(() {
                    _selectedRatio = ratio;
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showPresetsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('FX Presets', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              ...['Magic Bullet', 'Teal & Orange', 'Film Grain'].map((preset) {
                return ListTile(
                  title: Text(preset, style: const TextStyle(color: Colors.white70)),
                  onTap: () {
                    _applyPreset(preset);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Applied preset: $preset')),
                    );
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  void _showAddEffectDialog(int layerIndex) {
    final availableEffects = ['Brightness', 'Saturation', 'Contrast', 'Sharpness', 'Gamma', 'Hue', 'Temperature'];
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Add Effect', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableEffects.map((name) {
              return ListTile(
                title: Text(name, style: const TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  _addEffectToLayer(layerIndex, Effect(name: name, value: 0.5));
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
