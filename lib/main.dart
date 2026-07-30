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
