// =============================================================================
// AEReality / Shaderly - Motion S screen (batch 9)
//
// Full screen opened from the main-menu "Motion S" button (it is NOT a tab). Source = a saved project (its grade is applied first) or a
// plain video file (raw). Three modes: SMEAR, MAIN, DUPLICATE, each with its own settings, plus shared settings and the optional
// Glitch Edge effect. Preview is paused by default, deliberately low fps / low quality (batch 2 rule: playing / scrubbing = lower
// quality, paused = sharpen). START PROCESS renders every frame on Vulkan in a worker isolate, with the ExportClockPanel as progress,
// a Cancel button, and then asks (immediately, no hold) whether to export through the live export path (ExportSuite).
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'accent_state.dart';
import 'app_settings.dart';
import 'constants.dart';
import 'editor_views.dart' show SmoothSliderRow;
import 'export_clock.dart';
import 'export_suite.dart';
import 'models.dart';
import 'motion_engine.dart';
import 'motion_slots.dart';
import 'ui_kit.dart';
import 'vulkan_bridge.dart';

enum _Phase { pick, ready, processing, done }

class MotionSScreen extends StatefulWidget {
  const MotionSScreen({super.key});

  @override
  State<MotionSScreen> createState() => _MotionSScreenState();
}

class _MotionSScreenState extends State<MotionSScreen> {
  _Phase _phase = _Phase.pick;
  MotionSource? _src;
  MotionEngine? _engine;
  List<StoredProject> _projects = [];
  bool _loadingSource = false;
  bool _nativeOk = true;
  String? _error;

  List<double> _s = MotionS.defaults();
  double _fps = 30.0;
  int _procRes = 0; // 0 native, 1080, 720
  double _previewQ = 0.6; // shared "Preview quality": extra scale on the preview size

  // preview
  ui.Image? _img;
  double _t = 0.0;
  bool _playing = false;
  bool _scrubbing = false;
  bool _showOriginal = false;
  bool _busy = false;
  bool _dirty = false;
  Timer? _playTimer;
  Timer? _sharpenTimer;
  DateTime _playClock = DateTime.now();
  String? _previewNote;

  // processing
  double _progress = 0.0;
  String _status = '';
  bool _cancel = false;
  MotionProcessResult? _result;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _nativeOk = await MotionEngine.ensureVulkan();
    try {
      _projects = await ProjectManager.loadProjects();
      _projects = _projects.where((p) => !p.data.isImage).toList();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _sharpenTimer?.cancel();
    _cancel = true;
    _engine?.dispose();
    _img?.dispose();
    vulkanSetBandBudgetMs(40);
    super.dispose();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // SOURCE
  // ---------------------------------------------------------------------------------------------------------------
  Future<void> _openProject(StoredProject p) async {
    setState(() {
      _loadingSource = true;
      _error = null;
    });
    final s = await MotionSource.open(mediaPath: p.mediaPath, name: p.name, project: p.data);
    _useSource(s, 'Could not open the video of "${p.name}".');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty || result.files.single.path == null) return;
    final path = result.files.single.path!;
    setState(() {
      _loadingSource = true;
      _error = null;
    });
    final s = await MotionSource.open(mediaPath: path, name: path.split('/').last, project: null);
    _useSource(s, 'That file is not a readable video.');
  }

  void _useSource(MotionSource? s, String errorText) {
    if (!mounted) return;
    if (s == null) {
      setState(() {
        _loadingSource = false;
        _error = errorText;
      });
      return;
    }
    _engine?.dispose();
    setState(() {
      _src = s;
      _engine = MotionEngine(s);
      _loadingSource = false;
      _phase = _Phase.ready;
      _t = 0.0;
      _result = null;
    });
    _requestPreview();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // PREVIEW (low fps / low quality while playing and scrubbing, sharp when paused)
  // ---------------------------------------------------------------------------------------------------------------
  bool get _interactive => _playing || _scrubbing;

  void _requestPreview() {
    if (_engine == null) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    _runPreview();
  }

  Future<void> _runPreview() async {
    final engine = _engine;
    if (engine == null) return;
    _busy = true;
    _dirty = false;
    try {
      final size = engine.previewSize(interactive: _interactive);
      final w = ((size[0] * _previewQ.clamp(0.25, 1.0)) ~/ 2) * 2;
      final h = ((size[1] * _previewQ.clamp(0.25, 1.0)) ~/ 2) * 2;
      final pw = w < 16 ? 16 : w;
      final ph = h < 16 ? 16 : h;
      vulkanSetBandBudgetMs(_interactive ? 12 : 40);
      final rgba = await engine.renderPreview(
        tSec: _t,
        settings: _s,
        fps: _fps,
        w: pw,
        h: ph,
        original: _showOriginal,
      );
      if (!mounted) return;
      if (rgba == null) {
        setState(() => _previewNote = 'Could not decode a preview frame.');
      } else {
        final img = await _toImage(rgba, pw, ph);
        if (!mounted) {
          img.dispose();
          return;
        }
        final old = _img;
        setState(() {
          _img = img;
          _previewNote = null;
        });
        old?.dispose();
      }
    } catch (e) {
      if (mounted) setState(() => _previewNote = 'Preview failed: $e');
    } finally {
      _busy = false;
      if (mounted && _dirty) _requestPreview();
    }
  }

  Future<ui.Image> _toImage(Uint8List rgba, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  // sharpen after things settle (batch 2 behaviour)
  void _scheduleSharpen() {
    _sharpenTimer?.cancel();
    _sharpenTimer = Timer(const Duration(milliseconds: 280), () {
      if (!_interactive) _requestPreview();
    });
  }

  void _settingChanged() {
    setState(() {});
    _requestPreview();
    _scheduleSharpen();
  }

  void _togglePlay() {
    final src = _src;
    if (src == null) return;
    if (_playing) {
      _playTimer?.cancel();
      setState(() => _playing = false);
      _requestPreview(); // paused: sharpen
      return;
    }
    if (_t >= src.durationSec - 0.05) _t = 0.0;
    _playClock = DateTime.now();
    setState(() => _playing = true);
    // intentionally low preview rate: one new frame about every 150 ms at most (it also waits for the previous one)
    _playTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted || _src == null) return;
      final now = DateTime.now();
      final dt = now.difference(_playClock).inMilliseconds / 1000.0;
      _playClock = now;
      var next = _t + dt;
      if (next >= _src!.durationSec) {
        next = _src!.durationSec - 0.001;
        _playTimer?.cancel();
        setState(() {
          _playing = false;
          _t = next;
        });
        _requestPreview();
        return;
      }
      setState(() => _t = next);
      _requestPreview();
    });
  }

  // ---------------------------------------------------------------------------------------------------------------
  // START PROCESS
  // ---------------------------------------------------------------------------------------------------------------
  Future<void> _startProcess() async {
    final engine = _engine;
    final src = _src;
    if (engine == null || src == null || _phase == _Phase.processing) return;
    if (!_nativeOk) {
      setState(() => _error = 'Motion S needs the Vulkan engine, which is not available on this device / build.');
      return;
    }
    _playTimer?.cancel();
    _sharpenTimer?.cancel();
    final size = engine.processSize(_procRes);
    setState(() {
      _playing = false;
      _phase = _Phase.processing;
      _cancel = false;
      _progress = 0.0;
      _status = 'Starting...';
      _error = null;
    });
    final res = await engine.processAll(
      settings: List<double>.of(_s),
      fps: _fps,
      w: size[0],
      h: size[1],
      onProgress: (p, st) {
        if (mounted) {
          setState(() {
            _progress = p;
            _status = st;
          });
        }
      },
      cancelled: () => _cancel,
    );
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _phase = _Phase.ready;
        _error = _cancel ? null : (engine.lastError ?? 'Processing stopped.');
      });
      if (_cancel) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancelled. Nothing was kept.')));
      }
      _requestPreview();
      return;
    }
    setState(() {
      _result = res;
      _phase = _Phase.done;
      _progress = 1.0;
    });
    _askExport(); // immediately (no ExportClockPanel.holdFinished here)
  }

  void _cancelProcess() {
    setState(() {
      _cancel = true;
      _status = 'Cancelling...';
    });
  }

  Future<void> _askExport() async {
    final r = _result;
    if (r == null || !mounted) return;
    final accent = gCustomAccentColor.value;
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceDark,
        shape: shelfShape(cut: 12, edge: accent.withOpacity(0.5)),
        title: const Text('Motion S finished', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text(
          'The whole video is processed and saved on this phone.\nStart an export now? (Your normal export settings.)',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('EXPORT', style: TextStyle(color: accent, fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (yes == true) _openExport();
  }

  void _openExport() {
    final r = _result;
    final src = _src;
    if (r == null || src == null) return;
    if (!File(r.path).existsSync()) {
      setState(() => _error = 'The processed video is gone. Run Start Process again.');
      return;
    }
    final feed = MotionExportFeed(path: r.path, width: r.width, height: r.height);
    ExportSuite.showExportSheet(
      context: context,
      project: ProjectData(mediaPath: r.path), // only the processed frames matter: renderFrameToRgba supplies them
      renderFrameToRgba: feed.render,
      prepareFrames: feed.prepare,
      configureRender: feed.configure,
      videoDurationMs: r.durationMs,
      videoFps: r.fps,
      videoWidth: r.width,
      videoHeight: r.height,
      audioSourcePath: src.mediaPath, // sound comes from the original video, exactly like a normal export
    );
  }

  void _deleteResult() {
    final r = _result;
    if (r == null) return;
    try {
      File(r.path).deleteSync();
    } catch (_) {}
    setState(() {
      _result = null;
      _phase = _Phase.ready;
    });
  }

  // ---------------------------------------------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gAccentListenable,
      builder: (context, _) {
        final accent = gCustomAccentColor.value;
        return Scaffold(
          backgroundColor: kBackgroundDark,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () {
                if (_phase == _Phase.processing) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancel the processing first.')));
                  return;
                }
                Navigator.maybePop(context);
              },
            ),
            title: Row(
              children: [
                DiamondDot(size: 8, color: accent),
                const SizedBox(width: 10),
                const Text('MOTION S', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)),
              ],
            ),
          ),
          body: _phase == _Phase.pick ? _buildPick(accent) : _buildEditor(accent), // no touch particles over the preview
        );
      },
    );
  }

  // ---- source picker ---------------------------------------------------------------------------------------------
  Widget _buildPick(Color accent) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        ShelfPanel(
          title: 'SOURCE',
          icon: Icons.movie_filter_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pick a saved project to blur / smear it WITH its grade, or a plain video file to use it as it is.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _plateButton('VIDEO FILE (no grade)', Icons.video_file_rounded, accent, _loadingSource ? null : _pickFile),
              if (_loadingSource) const Padding(padding: EdgeInsets.only(top: 14), child: Center(child: CircularProgressIndicator())),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
              if (!_nativeOk)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Vulkan engine not ready: Motion S cannot render on this build.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ShelfPanel(
          title: 'PROJECTS (graded)',
          icon: Icons.bookmarks_rounded,
          child: _projects.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('No saved video projects.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                )
              : Column(
                  children: [
                    for (final p in _projects)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: shelfShape(cut: 8),
                            onTap: _loadingSource ? null : () => _openProject(p),
                            child: Ink(
                              decoration: ShapeDecoration(color: kCardDark, shape: shelfShape(cut: 8, edge: Colors.white.withOpacity(0.07))),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              child: Row(
                                children: [
                                  Icon(Icons.movie_creation_rounded, color: accent, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                        Text(p.mediaPath.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded, color: accent, size: 13),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _plateButton(String text, IconData icon, Color accent, VoidCallback? onTap, {bool filled = false}) {
    final cols = accentColors();
    return Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: Container(
        decoration: ShapeDecoration(
          gradient: filled ? LinearGradient(colors: cols) : null,
          shape: shelfShape(cut: 10, edge: filled ? Colors.white.withOpacity(0.35) : accent.withOpacity(0.5)),
          shadows: filled ? [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12)] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: shelfShape(cut: 10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: filled ? Colors.black : accent, size: 19),
                  const SizedBox(width: 8),
                  Text(text, style: TextStyle(color: filled ? Colors.black : accent, fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 0.8)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- editor ----------------------------------------------------------------------------------------------------
  Widget _buildEditor(Color accent) {
    final src = _src!;
    final processing = _phase == _Phase.processing;
    final aspect = () {
      final c = src.crop;
      return c[2] / c[3];
    }();
    return Column(
      children: [
        // preview (pinned)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: LayoutBuilder(
            builder: (context, c) {
              final maxH = MediaQuery.of(context).size.height * 0.36;
              double w = c.maxWidth;
              double h = w / aspect;
              if (h > maxH) {
                h = maxH;
                w = h * aspect;
              }
              return Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: GlowFrame(
                    child: processing
                        ? ExportClockPanel(progress: _progress, status: _status, height: h)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: Colors.black),
                              if (_img != null) RawImage(image: _img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                              if (_img == null) const Center(child: CircularProgressIndicator()),
                              Positioned(
                                left: 6,
                                top: 6,
                                child: _tag(_interactive ? 'PREVIEW  low fps / low quality' : 'PREVIEW  paused'),
                              ),
                              if (_previewNote != null)
                                Positioned(left: 8, right: 8, bottom: 6, child: Text(_previewNote!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11))),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        if (!processing) _timelineRow(src, accent),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            children: processing ? _processingBody(accent) : _settingsBody(accent, src),
          ),
        ),
      ],
    );
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(3)),
        child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
      );

  Widget _timelineRow(MotionSource src, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: accent, size: 28),
            onPressed: _togglePlay,
          ),
          Expanded(
            child: SliderTheme(
              data: shelfSliderTheme(context),
              child: Slider(
                value: _t.clamp(0.0, src.durationSec).toDouble(),
                min: 0.0,
                max: src.durationSec,
                onChangeStart: (_) {
                  _scrubbing = true;
                },
                onChanged: (v) {
                  setState(() => _t = v);
                  _requestPreview();
                },
                onChangeEnd: (_) {
                  _scrubbing = false;
                  _requestPreview(); // sharpen after the scrub
                },
              ),
            ),
          ),
          Text('${_t.toStringAsFixed(1)} / ${src.durationSec.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  // ---- settings --------------------------------------------------------------------------------------------------
  Widget _sl(String title, int slot, double min, double max) {
    return SmoothSliderRow(
      title: title,
      val: _s[slot].clamp(min, max).toDouble(),
      min: min,
      max: max,
      onChanged: (v) {
        _s[slot] = v;
        _settingChanged();
      },
    );
  }

  Widget _chips(String title, List<String> labels, int selected, ValueChanged<int> onPick) {
    final accent = gCustomAccentColor.value;
    final cols = accentColors();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < labels.length; i++)
                GestureDetector(
                  onTap: () => onPick(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: ShapeDecoration(
                      gradient: i == selected ? LinearGradient(colors: cols) : null,
                      shape: shelfShape(cut: 6, edge: i == selected ? Colors.white.withOpacity(0.35) : accent.withOpacity(0.28)),
                    ),
                    child: Text(labels[i], style: TextStyle(color: i == selected ? Colors.black : accent, fontWeight: FontWeight.w800, fontSize: 11.5)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String title, int slot, {String? hint}) {
    final accent = gCustomAccentColor.value;
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      activeColor: accent,
      title: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
      subtitle: hint == null ? null : Text(hint, style: const TextStyle(color: Colors.white30, fontSize: 10.5)),
      value: _s[slot] > 0.5,
      onChanged: (v) {
        _s[slot] = v ? 1.0 : 0.0;
        _settingChanged();
      },
    );
  }

  List<Widget> _settingsBody(Color accent, MotionSource src) {
    final m = MotionS.modeOf(_s);
    final blendNames = <String>['Default', ...LayerBlendMode.values.map((b) => b.name)];
    return [
      // mode
      ShelfPanel(
        title: 'MODE',
        icon: Icons.blur_linear_rounded,
        child: _chips(
          'Each mode has its own settings below',
          const ['SMEAR', 'MAIN', 'DUPLICATE'],
          m - 1,
          (i) {
            _s[MotionS.mode] = (i + 1).toDouble();
            _settingChanged();
          },
        ),
      ),
      const SizedBox(height: 10),

      // mode specific
      if (m == MotionS.modeSmear)
        ShelfPanel(
          title: 'SMEAR',
          icon: Icons.auto_graph_rounded,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Text('Trails follow the real motion of the picture: shakes, zooms and spins all smear the way they move.', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
            _sl('Smear length (max, of frame)', MotionS.smLength, 0.0, 0.4),
            _sl('Smear speed (response)', MotionS.smSpeed, 0.1, 4.0),
            _sl('Smear falloff', MotionS.smFalloff, 0.0, 1.0),
            _sl('Smear line sharpness', MotionS.sharp, 0.0, 1.0),
            _sl('Trailing samples', MotionS.smSamples, 8.0, 96.0),
            _sl('Highlight bias', MotionS.highlightBias, 0.0, 1.0),
            _sl('Head strength (keeps the picture)', MotionS.smHead, 0.0, 1.0),
            _sl('Trail reach (grid cells)', MotionS.dilate, 0.0, 6.0),
            _sl('Angle override', MotionS.smAngle, 0.0, 360.0),
            _sl('Angle override amount', MotionS.smAngleLock, 0.0, 1.0),
            _sl('Blur amount (keep low)', MotionS.smBlur, 0.0, 1.0),
          ]),
        ),
      if (m == MotionS.modeMain)
        ShelfPanel(
          title: 'MAIN  (classic motion blur)',
          icon: Icons.motion_photos_on_rounded,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Text('After Effects style: sub-frame samples across the shutter interval, along each pixel\'s own motion.', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
            _sl('Shutter angle', MotionS.shutterAngle, 0.0, 720.0),
            _sl('Shutter phase', MotionS.shutterPhase, -360.0, 360.0),
            _sl('Sample count (sub-frames)', MotionS.mainSamples, 8.0, 96.0),
            _sl('Shutter softness', MotionS.shutterSoft, 0.0, 1.0),
            _sl('Edge bleed', MotionS.mainBleed, 0.0, 1.0),
            _sl('Blur amount (keep low)', MotionS.mainBlur, 0.0, 1.0),
          ]),
        ),
      if (m == MotionS.modeDuplicate)
        ShelfPanel(
          title: 'DUPLICATE  (echo)',
          icon: Icons.layers_rounded,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Text('Real earlier / later frames of the video, composited with falloff. Not copies of one still.', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
            _sl('Duplicate count', MotionS.dupCount, 1.0, 12.0),
            _sl('Duplicate spacing (frames)', MotionS.dupSpacing, 1.0, 4.0),
            _sl('Opacity falloff', MotionS.dupFalloff, 0.0, 1.0),
            _sl('First duplicate opacity', MotionS.dupStartOpacity, 0.0, 1.0),
            _chips('Direction of offset', const ['Past', 'Future', 'Both'], _s[MotionS.dupDirection].round().clamp(0, 2).toInt(), (i) {
              _s[MotionS.dupDirection] = i.toDouble();
              _settingChanged();
            }),
            _chips('How duplicates combine', const ['Screen', 'Add', 'Lighten', 'Blend', 'Over'], _s[MotionS.dupOp].round().clamp(0, 4).toInt(), (i) {
              _s[MotionS.dupOp] = i.toDouble();
              _settingChanged();
            }),
            _sl('Ghost smear (along the motion)', MotionS.dupSmear, 0.0, 1.0),
            _sl('Ghost drift (along the motion path)', MotionS.dupDrift, -1.0, 1.0),
            _sl('Tint amount (older = more)', MotionS.dupTintAmt, 0.0, 1.0),
          ]),
        ),
      const SizedBox(height: 10),

      // shared
      ShelfPanel(
        title: 'SHARED',
        icon: Icons.tune_rounded,
        child: Column(children: [
          _sl('Opacity', MotionS.opacity, 0.0, 1.0),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Row(
              children: [
                const Expanded(child: Text('Custom blend (inside the effect)', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600))),
                DropdownButton<int>(
                  value: _s[MotionS.blend].round().clamp(0, blendNames.length - 1).toInt(),
                  dropdownColor: kCardDark,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                  items: [for (int i = 0; i < blendNames.length; i++) DropdownMenuItem<int>(value: i, child: Text(blendNames[i]))],
                  onChanged: (v) {
                    if (v == null) return;
                    _s[MotionS.blend] = v.toDouble();
                    _settingChanged();
                  },
                ),
              ],
            ),
          ),
          _sl('Blend with original', MotionS.origMix, 0.0, 1.0),
          _sl('Protect detail (line art)', MotionS.protect, 0.0, 1.0),
          if (m != MotionS.modeDuplicate) ...[
            _sl('Intensity', MotionS.intensity, 0.0, 3.0),
            _sl('Motion threshold (ignore small moves)', MotionS.threshold, 0.0, 0.02),
            _sl('Threshold softness', MotionS.thresholdKnee, 1.0, 8.0),
            _sl('Max length (never runs away)', MotionS.maxLen, 0.0, 0.4),
          ],
          SmoothSliderRow(
            title: 'Preview quality',
            val: _previewQ,
            min: 0.25,
            max: 1.0,
            onChanged: (v) {
              _previewQ = v;
              _settingChanged();
            },
          ),
          Row(
            children: [
              const SizedBox(width: 6),
              Expanded(
                child: Text('Preview is intentionally low fps / quality. Processing uses the full size.', style: TextStyle(color: Colors.white30, fontSize: 10.5)),
              ),
              TextButton.icon(
                onPressed: () {
                  _showOriginal = !_showOriginal;
                  _settingChanged();
                },
                icon: Icon(_showOriginal ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 16, color: accent),
                label: Text(_showOriginal ? 'Original' : 'Effect', style: TextStyle(color: accent, fontSize: 11.5)),
              ),
            ],
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // glitch edge
      ShelfPanel(
        title: 'GLITCH EDGE  (optional effect)',
        icon: Icons.broken_image_rounded,
        child: Column(children: [
          _switchRow('Glitch Edge', MotionS.gOn, hint: 'Tears / holds bands of the picture where things move (null-box edge look).'),
          if (_s[MotionS.gOn] > 0.5) ...[
            _sl('Amount', MotionS.gAmount, 0.0, 1.0),
            _sl('Band size', MotionS.gBandSize, 0.005, 0.15),
            _sl('Chance per band', MotionS.gChance, 0.0, 1.0),
            _sl('Speed', MotionS.gSpeed, 0.0, 4.0),
            _sl('Frame hold', MotionS.gHold, 0.0, 1.0),
            _sl('Only at motion edges', MotionS.gEdgeGate, 0.0, 1.0),
            _sl('Seed', MotionS.gSeed, 0.0, 50.0),
          ],
        ]),
      ),
      const SizedBox(height: 10),

      // process
      ShelfPanel(
        title: 'PROCESS',
        icon: Icons.play_circle_outline_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _chips('Frame rate', const ['24', '25', '30', '50', '60'], _fpsIndex(), (i) {
              _fps = const [24.0, 25.0, 30.0, 50.0, 60.0][i];
              setState(() {});
              _requestPreview();
            }),
            _chips('Processing size', const ['Native', '1080p', '720p'], _procRes == 0 ? 0 : (_procRes == 1080 ? 1 : 2), (i) {
              _procRes = const [0, 1080, 720][i];
              setState(() {});
            }),
            Builder(builder: (_) {
              final sz = _engine!.processSize(_procRes);
              final frames = (src.durationSec * _fps).round();
              return Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                child: Text(
                  '${sz[0]} x ${sz[1]}  -  $frames frames  -  ${src.graded ? 'with the project grade' : 'raw video, no grade'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              );
            }),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: accent, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Processed video is saved. Export it any time.', style: TextStyle(color: Colors.white70, fontSize: 12))),
                    TextButton(onPressed: _openExport, child: Text('EXPORT', style: TextStyle(color: accent, fontWeight: FontWeight.w900))),
                    IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20), tooltip: 'Delete processed video', onPressed: _deleteResult),
                  ],
                ),
              ),
            _chips('Codec', const ['HEVC', 'H.264'], MotionS.sanitizeCodec(MotionS.intermediateCodec) == 'hevc' ? 0 : 1, (i) {
              if (_phase == _Phase.processing) return; // locked while a process runs
              MotionS.intermediateCodec = i == 0 ? 'hevc' : 'h264';
              SettingsStore.save();
              setState(() {});
            }),
            _chips('Bitrate (Mbps)', [for (final b in MotionS.bitrateOptions) '$b'], MotionS.bitrateOptions.indexOf(MotionS.sanitizeBitrate(MotionS.bitrateMbps)), (i) {
              if (_phase == _Phase.processing) return; // locked while a process runs
              MotionS.bitrateMbps = MotionS.bitrateOptions[i];
              SettingsStore.save();
              setState(() {});
            }),
            _plateButton('START PROCESS', Icons.auto_awesome_rounded, accent, _nativeOk ? _startProcess : null, filled: true),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Renders the WHOLE video on the GPU in the background and stores it with the phone\'s hardware encoder (HEVC by default) at the bitrate above; higher bitrate = cleaner smears and blurs, bigger file. It is only exported if you say yes afterwards.',
                style: TextStyle(color: Colors.white30, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  int _fpsIndex() {
    const f = [24.0, 25.0, 30.0, 50.0, 60.0];
    final i = f.indexOf(_fps);
    return i < 0 ? 2 : i;
  }

  List<Widget> _processingBody(Color accent) {
    return [
      ShelfPanel(
        title: 'PROCESSING',
        icon: Icons.hourglass_top_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('You can leave the phone alone: the UI stays responsive and nothing is exported until you say so.', style: TextStyle(color: Colors.white30, fontSize: 10.5)),
            const SizedBox(height: 12),
            _plateButton(_cancel ? 'CANCELLING...' : 'CANCEL', Icons.close_rounded, Colors.redAccent, _cancel ? null : _cancelProcess),
          ],
        ),
      ),
    ];
  }
}
