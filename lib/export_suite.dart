// =============================================================================
// AEReality / Shaderly - Master Export Suite
// True 32-Bit Linear Pipeline • All Codecs • All Bit Depths • MediaStore Scoped
// 100% Complete File - Zero Feature Omissions
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

import 'models.dart';
import 'crash_log.dart';
import 'cpu_safe.dart';
import 'vulkan_bridge.dart';
import 'export_matrix.dart';
import 'export_clock.dart';
import 'native_encoder.dart';

/// H.264 / HEVC (8-bit and 10-bit) are encoded by the phone's hardware encoder through Kotlin MediaCodec (NativeEncoder / MediaCodecEncoder.kt): no FFmpeg encode.
/// true = the graded frames go GPU -> the encoder's Surface without touching the CPU. false = NV12 frames are sent to the encoder instead (slower, same picture);
/// flip it if a phone's surface export ever looks softer than the NV12 one.
/// VP9 / AV1 / ProRes / 4:4:4 stay on the software FFmpeg path (RGBA frames for VP9 / AV1).
const bool kExportPreferSurface = true;

class ExportSuite {
  static const MethodChannel _mediaChannel = MethodChannel('com.aereality/media');

  // ===========================================================================
  // COPILOT MEDIASTORE SAVE INTEGRATION (Android 10 - 15 Compliant)
  // ===========================================================================
  static Future<String> saveToMovies({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    Object? nativeError;
    try {
      final uri = await _mediaChannel.invokeMethod<String>('saveToMovies', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });

      if (uri != null && uri.isNotEmpty) {
        debugPrint('Successfully saved via MediaStore: $uri');
        return uri;
      }
      nativeError = 'native save returned no URI';
    } catch (e) {
      nativeError = e;
      debugPrint('Native MediaStore save failed: $e');
    }

    // Direct filesystem fallback (only works if "All files access" was granted)
    try {
      final moviesDir = Directory('/storage/emulated/0/Movies/Shaderly');
      if (!moviesDir.existsSync()) {
        moviesDir.createSync(recursive: true);   // also creates root Movies if it is missing
      }
      final targetFile = File('${moviesDir.path}/$fileName');
      await File(sourcePath).copy(targetFile.path);

      try {
        await _mediaChannel.invokeMethod('scanFile', {'path': targetFile.path});
      } catch (_) {}

      return targetFile.path;
    } catch (e) {
      // IMPORTANT: do NOT return sourcePath here. The temp file is deleted in the
      // caller's finally block, so pretending it was saved loses the export silently.
      throw Exception('Could not save to Movies/Shaderly.\nMediaStore: $nativeError\nDirect copy: $e');
    }
  }

  // ===========================================================================
  // IMAGE SAVE -> Pictures/Shaderly (MediaStore refuses images inside Movies, EPERM)
  // ===========================================================================
  static Future<String> saveImage({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      final res = await _mediaChannel.invokeMethod<dynamic>('saveImage', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      if (res is Map && res['location'] != null) return res['location'].toString();
      throw Exception('native image save returned no location');
    } catch (e) {
      throw Exception('Could not save image: $e');
    }
  }

  // ===========================================================================
  // MASTER DISPATCHER
  // ===========================================================================
  static void showExportSheet({
    required BuildContext context,
    required ProjectData project,
    AdjustmentLayer? curLayer,
    dynamic packUniforms,
    dynamic getActiveLut,
    dynamic lutTextureId,
    dynamic lutSize,
    dynamic vulkanBridge,
    dynamic bridge,
    dynamic onExportComplete,
    Future<Uint8List> Function(double timestampMs)? renderFrameToRgba,
    Future<void> Function(double startMs, int frameCount, double fps)? prepareFrames,
    Future<void> Function(int w, int h, bool nv12)? configureRender, // batch 18B: render size + frame format of the video export (0, 0 = back to the source size)
    double? videoDurationMs,
    double? videoFps,
    int? videoWidth,
    int? videoHeight,
    String? audioSourcePath,
  }) {
    if (project.isImage) {
      showImageExportSheet(
        context: context,
        project: project,
        curLayer: curLayer,
        packUniforms: packUniforms,
        getActiveLut: getActiveLut,
        lutTextureId: lutTextureId,
        lutSize: lutSize,
        renderFrameToRgba: renderFrameToRgba,
        srcWidth: videoWidth,
        srcHeight: videoHeight,
      );
    } else {
      // No silent defaults: a missing duration/size used to fall back to 5000 ms @ 1080p
      // (= 150 frames) and a missing renderer produced all-black frames.
      if (renderFrameToRgba == null ||
          configureRender == null ||
          videoDurationMs == null ||
          videoWidth == null ||
          videoHeight == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Export is not connected: renderFrameToRgba, configureRender, videoDurationMs, videoWidth and videoHeight must be passed to showExportSheet.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      showVideoExportSheet(
        context: context,
        project: project,
        curLayer: curLayer,
        packUniforms: packUniforms,
        getActiveLut: getActiveLut,
        lutTextureId: lutTextureId,
        lutSize: lutSize,
        renderFrameToRgba: renderFrameToRgba,
        prepareFrames: prepareFrames,
        configureRender: configureRender,
        videoDurationMs: videoDurationMs,
        videoFps: videoFps ?? 30.0,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
        audioSourcePath: audioSourcePath,
      );
    }
  }

  // ===========================================================================
  // IMAGE EXPORT SHEET
  // ===========================================================================
  static void showImageExportSheet({
    required BuildContext context,
    required ProjectData project,
    AdjustmentLayer? curLayer,
    dynamic packUniforms,
    dynamic getActiveLut,
    dynamic lutTextureId,
    dynamic lutSize,
    Future<Uint8List> Function(double timestampMs)? renderFrameToRgba,
    int? srcWidth,
    int? srcHeight,
  }) {
    String selectedFormat = 'PNG';
    String selectedRes = '1080p';
    bool isExporting = false;
    double exportProgress = 0.0;
    String statusText = 'Ready';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Export Master Image',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: isExporting ? null : () {
                        Music.setExporting(false);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                if (!isExporting) ...[
                const SizedBox(height: 16),
                const Text('Format', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: ['PNG', 'JPG', 'WEBP'].map((fmt) {
                    final selected = selectedFormat == fmt;
                    return Expanded(
                      child: GestureDetector(
                        onTap: isExporting ? null : () => setSheetState(() => selectedFormat = fmt),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF00E5FF).withOpacity(0.18) : const Color(0xFF1E1E2C),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? const Color(0xFF00E5FF) : Colors.white12,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            fmt,
                            style: TextStyle(
                              color: selected ? const Color(0xFF00E5FF) : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Resolution', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Native', '720p', '1080p', '2K', '4K'].map((res) {
                    final selected = selectedRes == res;
                    return ChoiceChip(
                      label: Text(res),
                      selected: selected,
                      selectedColor: const Color(0xFF00E5FF),
                      backgroundColor: const Color(0xFF1E1E2C),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: isExporting ? null : (s) {
                        if (s) setSheetState(() => selectedRes = res);
                      },
                    );
                  }).toList(),
                ),
                ],
                const SizedBox(height: 24),
                if (isExporting) ...[
                  ExportClockPanel(progress: exportProgress, status: statusText),
                  const SizedBox(height: 16),
                ] else if (statusText.startsWith('Failed')) ...[
                  SelectableText(
                    statusText,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isExporting
                      ? null
                      : () async {
                          setSheetState(() {
                            isExporting = true;
                            statusText = 'Rendering image...';
                            exportProgress = 0.2;
                          });

                          try {
                            await _executeImageExport(
                              context: context,
                              project: project,
                              format: selectedFormat,
                              resolution: selectedRes,
                              renderFrameToRgba: renderFrameToRgba,
                              srcW: srcWidth,
                              srcH: srcHeight,
                              onProgress: (p, msg) {
                                setSheetState(() {
                                  exportProgress = p;
                                  statusText = msg;
                                });
                              },
                            );
                            if (context.mounted) {
                              setSheetState(() {
                                exportProgress = 1.0;
                                statusText = 'Export complete!';
                              });
                              await ExportClockPanel.holdFinished();
                            }
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setSheetState(() {
                              isExporting = false;
                              statusText = 'Failed: $e';
                            });
                            Music.setExporting(false);
                          }
                        },
                  child: const Text('Export Image', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // VIDEO EXPORT SHEET
  // ===========================================================================
  static void showVideoExportSheet({
    required BuildContext context,
    required ProjectData project,
    AdjustmentLayer? curLayer,
    dynamic packUniforms,
    dynamic getActiveLut,
    dynamic lutTextureId,
    dynamic lutSize,
    Future<Uint8List> Function(double timestampMs)? renderFrameToRgba,
    Future<void> Function(double startMs, int frameCount, double fps)? prepareFrames,
    required Future<void> Function(int w, int h, bool nv12) configureRender,
    required double videoDurationMs,
    required double videoFps,
    required int videoWidth,
    required int videoHeight,
    String? audioSourcePath,
  }) {
    String selectedRes = '1080p';
    String selectedCodec = 'H.264';
    String selectedBitDepth = '8-bit';
    String selectedBitrate = '25 Mbps';
    String selectedContainer = 'MP4';
    double selectedFps = ExportChoices.fps.map((e) => e.toDouble()).contains(videoFps) ? videoFps : 30.0;

    bool isExporting = false;
    double exportProgress = 0.0;
    String statusText = 'Ready to encode';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Export Master Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: isExporting ? null : () {
                        Music.setExporting(false);
                        Navigator.pop(context);
                      },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (!isExporting) ...[
                  // 1. Resolution
                  const Text('Resolution', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['720p', '1080p', '2K', '4K'].map((res) {
                      final selected = selectedRes == res;
                      return ChoiceChip(
                        label: Text(res),
                        selected: selected,
                        selectedColor: const Color(0xFF00E5FF),
                        backgroundColor: const Color(0xFF1E1E2C),
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: isExporting ? null : (s) {
                          if (s) setSheetState(() => selectedRes = res);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 1b. Frame rate
                  const Text('Frame Rate', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ExportChoices.fps.map((e) => e.toDouble()).map((f) {
                      final selected = selectedFps == f;
                      return ChoiceChip(
                        label: Text('${f.toInt()} fps'),
                        selected: selected,
                        selectedColor: const Color(0xFF00E5FF),
                        backgroundColor: const Color(0xFF1E1E2C),
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: isExporting ? null : (s) {
                          if (s) setSheetState(() => selectedFps = f);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 2. Codec
                  const Text('Codec', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['H.264', 'HEVC / H.265', 'AV1', 'VP9', 'Apple ProRes'].map((cdc) {
                      final selected = selectedCodec == cdc;
                      return ChoiceChip(
                        label: Text(cdc),
                        selected: selected,
                        selectedColor: const Color(0xFF00E5FF),
                        backgroundColor: const Color(0xFF1E1E2C),
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: isExporting ? null : (s) {
                          if (s) {
                            setSheetState(() {
                              final r = _reconcile(
                                container: selectedContainer,
                                codec: cdc,
                                depth: selectedBitDepth,
                                changed: 'codec',
                              );
                              selectedContainer = r[0];
                              selectedCodec = r[1];
                              selectedBitDepth = r[2];
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 3. Container Format
                  const Text('Container Format', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: ['MP4', 'MKV', 'MOV', 'WEBM'].map((ctn) {
                      final selected = selectedContainer == ctn;
                      return Expanded(
                        child: GestureDetector(
                          onTap: isExporting
                              ? null
                              : () => setSheetState(() {
                                    final r = _reconcile(
                                      container: ctn,
                                      codec: selectedCodec,
                                      depth: selectedBitDepth,
                                      changed: 'container',
                                    );
                                    selectedContainer = r[0];
                                    selectedCodec = r[1];
                                    selectedBitDepth = r[2];
                                  }),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF00E5FF).withOpacity(0.18) : const Color(0xFF1E1E2C),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected ? const Color(0xFF00E5FF) : Colors.white12,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              ctn,
                              style: TextStyle(
                                color: selected ? const Color(0xFF00E5FF) : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 4. Bit Depth & Color Gamut
                  const Text('Bit Depth', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildDepthOption('8-bit', 'Rec.709', selectedBitDepth, isExporting, (d) {
                        setSheetState(() {
                          final r = _reconcile(
                            container: selectedContainer,
                            codec: selectedCodec,
                            depth: d,
                            changed: 'depth',
                          );
                          selectedContainer = r[0];
                          selectedCodec = r[1];
                          selectedBitDepth = r[2];
                        });
                      }),
                      _buildDepthOption('10-bit', 'Rec.709', selectedBitDepth, isExporting, (d) {
                        setSheetState(() {
                          final r = _reconcile(
                            container: selectedContainer,
                            codec: selectedCodec,
                            depth: d,
                            changed: 'depth',
                          );
                          selectedContainer = r[0];
                          selectedCodec = r[1];
                          selectedBitDepth = r[2];
                        });
                      }),
                      _buildDepthOption('16-bit', '4:4:4', selectedBitDepth, isExporting, (d) {
                        setSheetState(() {
                          final r = _reconcile(
                            container: selectedContainer,
                            codec: selectedCodec,
                            depth: d,
                            changed: 'depth',
                          );
                          selectedContainer = r[0];
                          selectedCodec = r[1];
                          selectedBitDepth = r[2];
                        });
                      }),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 5. Target Bitrate
                  const Text('Target Bitrate / Quality', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in ExportChoices.bitratesMbps) '$m Mbps',
                      'Lossless (CRF 14)',
                    ].map((br) {
                      final selected = selectedBitrate == br;
                      return ChoiceChip(
                        label: Text(br),
                        selected: selected,
                        selectedColor: const Color(0xFF00E5FF),
                        backgroundColor: const Color(0xFF1E1E2C),
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: isExporting ? null : (s) {
                          if (s) setSheetState(() => selectedBitrate = br);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  ],

                  if (isExporting) ...[
                    ExportClockPanel(progress: exportProgress, status: statusText),
                    const SizedBox(height: 16),
                  ] else if (statusText.startsWith('Export error')) ...[
                    SelectableText(
                      statusText,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                  ],

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isExporting
                        ? null
                        : () async {
                            setSheetState(() {
                              isExporting = true;
                              statusText = 'Preparing export...';
                              exportProgress = 0.02;
                            });

                            try {
                              await executeVideoExport(
                                context: context,
                                project: project,
                                curLayer: curLayer,
                                packUniforms: packUniforms,
                                getActiveLut: getActiveLut,
                                renderFrameToRgba: renderFrameToRgba,
                                prepareFrames: prepareFrames,
                                configureRender: configureRender,
                                videoDurationMs: videoDurationMs,
                                videoFps: selectedFps,
                                videoWidth: videoWidth,
                                videoHeight: videoHeight,
                                audioSourcePath: audioSourcePath,
                                resolution: selectedRes,
                                codec: selectedCodec,
                                bitDepth: selectedBitDepth,
                                bitrateProfile: selectedBitrate,
                                container: selectedContainer,
                                onProgress: (p, msg) {
                                  setSheetState(() {
                                    exportProgress = p;
                                    statusText = msg;
                                  });
                                },
                              );
                              if (context.mounted) {
                                setSheetState(() {
                                  exportProgress = 1.0;
                                  statusText = 'Export complete!';
                                });
                                await ExportClockPanel.holdFinished();
                              }
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              setSheetState(() {
                                isExporting = false;
                                statusText = 'Export error: $e';
                              });
                              Music.setExporting(false);
                            }
                          },
                    child: const Text('Export Video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildDepthOption(
    String key,
    String label,
    String current,
    bool isExporting,
    Function(String) onSelect,
  ) {
    final selected = current.startsWith(key);
    return Expanded(
      child: GestureDetector(
        onTap: isExporting ? null : () => onSelect(key),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E5FF).withOpacity(0.18) : const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF00E5FF) : Colors.white12,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            children: [
              Text(
                key,
                style: TextStyle(
                  color: selected ? const Color(0xFF00E5FF) : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF00E5FF).withOpacity(0.8) : Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // EXPORT MATRIX BRIDGE (UI chip names -> ExportMatrix rules)
  // ===========================================================================
  static String _matrixKey(String container) =>
      container.toUpperCase() == 'WEBM' ? 'WebM' : container.toUpperCase();

  static String _codecToken(String codec) {
    if (codec.contains('ProRes')) return 'ProRes';
    if (codec.contains('HEVC') || codec.contains('H.265')) return 'HEVC';
    if (codec.contains('AV1')) return 'AV1';
    if (codec.contains('VP9')) return 'VP9';
    return 'H.264';
  }

  /// True if ExportMatrix.containerCodecs allows this codec in this container.
  static bool _comboValid(String container, String codec) {
    final list = ExportMatrix.containerCodecs[_matrixKey(container)] ?? const <String>[];
    final token = _codecToken(codec);
    return list.any((e) => e.contains(token));
  }

  static String _defaultCodecFor(String container) {
    for (final c in const ['H.264', 'HEVC / H.265', 'VP9', 'AV1', 'Apple ProRes']) {
      if (_comboValid(container, c)) return c;
    }
    return 'H.264';
  }

  static String _bestContainer(String codec, String depth) {
    final order = _codecToken(codec) == 'VP9'
        ? const ['WEBM', 'MKV', 'MP4', 'MOV']
        : const ['MP4', 'MOV', 'MKV', 'WEBM'];
    for (final c in order) {
      if (_comboValid(c, codec) && ExportMatrix.isBitDepthValid(_matrixKey(c), codec, depth)) {
        return c;
      }
    }
    for (final c in order) {
      if (_comboValid(c, codec)) return c;
    }
    return 'MKV';
  }

  /// Keeps container / codec / bit depth legal after the user changes one of them.
  /// The thing the user just changed wins; the others adapt.
  static List<String> _reconcile({
    required String container,
    required String codec,
    required String depth,
    required String changed, // 'codec' | 'container' | 'depth'
  }) {
    String c = container, k = codec, d = depth;
    bool depthOk() => ExportMatrix.isBitDepthValid(_matrixKey(c), k, d);

    if (changed == 'depth') {
      if (!depthOk()) {
        if (d == '16-bit') {
          c = 'MKV';
        } else if (d == '10-bit' && k.contains('H.264')) {
          k = 'HEVC / H.265'; // Hi10P H.264 breaks mobile hardware decoders
        } else if (d == '8-bit' && k.contains('ProRes')) {
          k = 'H.264'; // ProRes is 10-bit minimum
        }
      }
    } else if (changed == 'codec') {
      if (!_comboValid(c, k)) c = _bestContainer(k, d);
    } else {
      if (!_comboValid(c, k)) k = _defaultCodecFor(c);
    }

    if (!_comboValid(c, k)) {
      if (changed == 'container') {
        k = _defaultCodecFor(c);
      } else {
        c = _bestContainer(k, d);
      }
    }
    if (!depthOk()) {
      for (final cand in const ['10-bit', '8-bit', '16-bit']) {
        if (ExportMatrix.isBitDepthValid(_matrixKey(c), k, cand)) {
          d = cand;
          break;
        }
      }
    }
    return [c, k, d];
  }

  static Future<String> _sessionLogTail(dynamic session) async {
    try {
      final out = await session.getOutput();
      final s = (out ?? '').toString();
      return s.length > 500 ? s.substring(s.length - 500) : s;
    } catch (_) {
      return '(FFmpeg log unavailable)';
    }
  }

  // ===========================================================================
  // IMAGE ENCODING EXECUTION
  // ===========================================================================
  static Future<void> _executeImageExport({
    required BuildContext context,
    required ProjectData project,
    required String format,
    required String resolution,
    Future<Uint8List> Function(double timestampMs)? renderFrameToRgba,
    int? srcW,
    int? srcH,
    required Function(double, String) onProgress,
  }) async {
    if (renderFrameToRgba == null || srcW == null || srcH == null) {
      throw Exception('Image export is not connected (renderer or source size missing).');
    }
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = format.toLowerCase();
    final tempRawFile = File('${tempDir.path}/raw_frame_$timestamp.rgba');
    final tempEncodedFile = File('${tempDir.path}/Shaderly_Art_${resolution}_$timestamp.$ext');

    try {
      CrashLog.begin('Image export', {'format': format, 'resolution': resolution, 'source': '${srcW}x$srcH'});
      onProgress(0.3, 'Rendering image...');
      if (renderFrameToRgba == null) {
        throw Exception('No frame renderer connected (renderFrameToRgba is null).');
      }
      final rgbaBytes = await renderFrameToRgba(0.0);
      if (rgbaBytes.length != srcW * srcH * 4) {
        throw Exception('Rendered image is ${rgbaBytes.length} bytes, expected ${srcW * srcH * 4}.');
      }

      await tempRawFile.writeAsBytes(rgbaBytes, flush: true);

      onProgress(0.6, 'Encoding $format surface...');
      final targetDims = _calculateDimensions(resolution, srcW, srcH);
      final w = targetDims['w']!;
      final h = targetDims['h']!;

      final ffmpegCmd = '-y -f rawvideo -pix_fmt rgba -s ${srcW}x$srcH -i "${tempRawFile.path}" '
          '-vf "scale=$w:$h:flags=lanczos" "${tempEncodedFile.path}"';

      final session = await FFmpegKit.execute(ffmpegCmd);
      final rc = await session.getReturnCode();

      if (!ReturnCode.isSuccess(rc)) {
        throw Exception('FFmpeg image encode failed with code: $rc');
      }

      onProgress(0.9, 'Saving image...');
      final mime = format == 'PNG' ? 'image/png' : (format == 'JPG' ? 'image/jpeg' : 'image/webp');
      final location = await saveImage(
        sourcePath: tempEncodedFile.path,
        fileName: 'Shaderly_Art_${resolution}_$timestamp.$ext',
        mimeType: mime,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $location'),
            backgroundColor: const Color(0xFF00E5FF),
          ),
        );
      }
      CrashLog.end('image export finished');
    } catch (e) {
      CrashLog.end('FAILED with a Dart exception: $e');
      rethrow;
    } finally {
      if (tempRawFile.existsSync()) tempRawFile.deleteSync();
      if (tempEncodedFile.existsSync()) tempEncodedFile.deleteSync();
    }
  }

  // ===========================================================================
  // VIDEO ENCODING EXECUTION - ROLLING 30-FRAME GPU PIPELINE (batch 18B)
  //
  //   source batch (ONE ffmpeg decode, already cropped + scaled to the EXPORT size)
  //     -> per frame: grade at the export size on the GPU, GPU converts RGB -> NV12 (pass 29), only NV12 comes back (1.5 bytes / pixel)
  //     -> NV12 batch file -> ONE ffmpeg call encodes it straight into the FINAL codec (no lossless mezzanine, no second encode)
  //     -> parts are joined with a stream copy (+ audio).
  //   H.264 / HEVC 8-bit / 10-bit: Kotlin MediaCodec hardware encoder (NativeEncoder). Frames go GPU -> encoder Surface (or NV12 buffers), ONE continuous MP4,
  //     no parts, no concat, no FFmpeg encode. FFmpeg is only used to decode the source and, if needed, to copy the audio / container (-c copy).
  //   VP9 / AV1: software FFmpeg, multithreaded, RGBA frames (no NV12 pass). ProRes and 4:4:4: software FFmpeg as before.
  // ===========================================================================
  static Future<void> executeVideoExport({
    required BuildContext context,
    required ProjectData project,
    AdjustmentLayer? curLayer,
    dynamic packUniforms,
    dynamic getActiveLut,
    Future<Uint8List> Function(double timestampMs)? renderFrameToRgba,
    Future<void> Function(double startMs, int frameCount, double fps)? prepareFrames,
    required Future<void> Function(int w, int h, bool nv12) configureRender,
    required double videoDurationMs,
    required double videoFps,
    required int videoWidth,
    required int videoHeight,
    String? audioSourcePath,
    required String resolution,
    required String codec,
    required String bitDepth,
    required String bitrateProfile,
    required String container,
    required Function(double, String) onProgress,
  }) async {
    Directory? sessionTempDir;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    ExportNotes.clear();

    try {
      StageTimer.reset();
      vulkanSetBandBudgetMs(150); // export: bigger GPU submits (less overhead); the phone UI is not being used
      CrashLog.begin('Video export', {
        'codec': codec,
        'container': container,
        'bitDepth': bitDepth,
        'bitrateProfile': bitrateProfile,
        'resolution': resolution,
        'source': '${videoWidth}x$videoHeight @ ${videoFps}fps, ${videoDurationMs.round()} ms',
      });
      final appTempDir = await getTemporaryDirectory();
      sessionTempDir = Directory('${appTempDir.path}/export_sess_$timestamp');
      if (!sessionTempDir.existsSync()) {
        sessionTempDir.createSync(recursive: true);
      }

      final render = renderFrameToRgba;
      if (render == null) {
        throw Exception('No frame renderer connected (renderFrameToRgba is null).');
      }
      if (!_comboValid(container, codec)) {
        throw Exception('$codec cannot be stored in $container.');
      }
      if (!ExportMatrix.isBitDepthValid(_matrixKey(container), codec, bitDepth)) {
        throw Exception('$bitDepth is not valid for $codec in $container.');
      }

      // ---- 1. Export size: the GPU renders AT this size (it used to render at the source size and let FFmpeg scale down) ----
      final targetDims = _calculateDimensions(resolution, videoWidth, videoHeight);
      final int outW = (targetDims['w']! + 3) & ~3; // the NV12 pass handles 4 pixels per row per invocation
      final int outH = (targetDims['h']! + 1) & ~1;

      final bool isProRes = codec.contains('ProRes');
      final bool isHevc = codec.contains('HEVC') || codec.contains('H.265');
      final bool isAv1 = codec.contains('AV1');
      final bool isVp9 = codec.contains('VP9');
      final bool isH264 = !isProRes && !isHevc && !isAv1 && !isVp9;
      // H.264 / HEVC at 8 or 10 bit = hardware (Kotlin MediaCodec). Everything else = software FFmpeg.
      final bool hwPath = (isH264 || isHevc) && (bitDepth.startsWith('8') || bitDepth.startsWith('10'));
      // VP9 / AV1 are back on RGBA frames (FFmpeg converts), exactly as before the NV12 pass existed; the NV12 pass stays for the other software encoders.
      final bool nv12 = !hwPath && vulkanNv12Available() && !isVp9 && !isAv1;
      if (!hwPath) await configureRender(outW, outH, nv12);
      final int expectedBytes = nv12 ? outW * outH * 3 ~/ 2 : outW * outH * 4;

      final totalFrames = ((videoDurationMs / 1000.0) * videoFps).round().clamp(1, 999999);
      final frameIntervalMs = 1000.0 / videoFps;

      // ===================== HARDWARE PATH: H.264 / HEVC through Kotlin MediaCodec =====================
      if (hwPath) {
        final String ext = container.toLowerCase();
        final int mbps = _hardwareMbps(bitrateProfile, outW, outH, videoFps);
        final String codecName = isHevc ? 'HEVC' : 'H.264';
        final bool wantAudio = audioSourcePath != null && File(audioSourcePath).existsSync();
        final String hwFile = '${sessionTempDir.path}/hw_$timestamp.mp4';
        onProgress(0.01, 'Starting the hardware $codecName encoder...');

        NativeEncoderSession hwSession;
        try {
          hwSession = await NativeEncoder.start(NativeEncoderConfig(
            codec: isHevc ? 'hevc' : 'h264',
            width: outW,
            height: outH,
            fps: videoFps,
            bitrateMbps: mbps,
            tenBit: bitDepth.startsWith('10'),
            outputPath: hwFile,
            preferSurface: kExportPreferSurface,
            audioPath: wantAudio ? audioSourcePath : null,
            audioStartMs: 0,
            audioDurationMs: videoDurationMs.round(),
          ));
        } on NativeEncoderException catch (e) {
          throw Exception('This phone\'s hardware $codecName encoder could not start at ${outW}x$outH, ${videoFps.round()} fps: ${e.message} '
              'Try a lower resolution or frame rate, or export with VP9 / AV1.');
        }
        final String depthUsed = hwSession.tenBit ? '10-bit' : '8-bit';
        final String encoderLine = 'Using hardware $codecName (${hwSession.encoder}${hwSession.hardware ? '' : ', software MediaCodec'}), '
            '${hwSession.surface ? 'zero-copy GPU surface' : 'NV12 buffers'}, $mbps Mbps, $depthUsed';
        onProgress(0.02, encoderLine);
        CrashLog.note(encoderLine);
        for (final n in hwSession.notes) {
          ExportNotes.add('encoder note: $n');
        }
        if (bitDepth.startsWith('10') && !hwSession.tenBit) {
          final note = 'This phone cannot encode 10-bit $codecName in hardware. Exporting 8-bit instead.';
          onProgress(0.02, note);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note), duration: const Duration(seconds: 5)));
        }

        await configureRender(outW, outH, !hwSession.surface); // surface: the render returns only a "frame done" token; buffer mode: NV12 frames
        final int nv12Bytes = outW * outH * 3 ~/ 2;
        const hwBatch = 30;
        final int hwBatches = (totalFrames / hwBatch).ceil();
        for (int b = 0; b < hwBatches; b++) {
          final startFrame = b * hwBatch;
          final endFrame = (startFrame + hwBatch).clamp(0, totalFrames);
          final cnt = endFrame - startFrame;
          final prep = prepareFrames;
          if (prep != null) {
            CrashLog.note('batch $b/$hwBatches source decode START (frames ${startFrame + 1}..$endFrame)');
            await StageTimer.time('batch: decode source', () => prep(startFrame * frameIntervalMs, cnt, videoFps));
          }
          int usTotal = 0;
          int usMax = 0;
          for (int f = 0; f < cnt; f++) {
            final idx = startFrame + f;
            final watch = Stopwatch()..start();
            final bytes = await render(idx * frameIntervalMs);
            final us = watch.elapsedMicroseconds;
            usTotal += us;
            if (us > usMax) usMax = us;
            if (!hwSession.surface) {
              if (bytes.length != nv12Bytes) throw Exception('Frame $idx returned ${bytes.length} bytes, expected $nv12Bytes (${outW}x$outH NV12).');
              if (!await StageTimer.time('frame: queue to encoder', () => NativeEncoder.queueNv12(bytes, idx))) {
                throw Exception('The hardware encoder did not accept frame ${idx + 1}.');
              }
            }
            onProgress((idx / totalFrames) * 0.88, 'Rendering frames (${idx + 1}/$totalFrames)...');
          }
          ExportNotes.add('batch $b: frames ${startFrame + 1}..$endFrame, avg ${(usTotal / cnt / 1000).toStringAsFixed(0)} ms/frame, max ${(usMax / 1000).toStringAsFixed(0)} ms');
          ExportNotes.flush();
        }

        onProgress(0.90, 'Finishing the video...');
        final NativeEncoderResult hwRes = await NativeEncoder.finish();
        if (!hwRes.ok) throw Exception('The hardware encoder could not finish the video${hwRes.error == null ? '' : ': ${hwRes.error}'}');
        CrashLog.note('hardware encode done: ${hwRes.frames}/$totalFrames frames, ${hwRes.bytes} bytes, audio ${hwRes.audio}, 10-bit=${hwRes.tenBit}');
        if (hwRes.frames < totalFrames * 0.9) {
          throw Exception('The hardware encoder dropped too many frames (${hwRes.frames} of $totalFrames).');
        }

        // FFmpeg is only used here for stream COPY: audio that is not AAC (Opus / Vorbis / MP3 sources) and the MKV container. No video is re-encoded.
        final bool isMp4Family = container == 'MP4' || container == 'MOV';
        final bool needAudioMux = wantAudio && !hwRes.audio.startsWith('copied');
        final bool needRemux = container == 'MKV';
        File tempFinalFile = File(hwRes.path);
        if (needAudioMux || needRemux) {
          onProgress(0.94, needAudioMux ? 'Adding the audio...' : 'Packing the video...');
          final out = File('${sessionTempDir.path}/final_$timestamp.$ext');
          final hvcTag = (isHevc && isMp4Family) ? '-tag:v hvc1 ' : '';
          final fastStart = isMp4Family ? '-movflags +faststart ' : '';
          final cmd = needAudioMux
              ? '-y -i "${hwRes.path}" -i "$audioSourcePath" -map 0:v:0 -map 1:a:0? -c:v copy $hvcTag-c:a ${ExportMatrix.getAudioCodec(container)} -b:a 320k -shortest $fastStart"${out.path}"'
              : '-y -i "${hwRes.path}" -c copy $hvcTag$fastStart"${out.path}"';
          CrashLog.note('copy-mux START: ffmpeg $cmd');
          final sess = await StageTimer.time('final: copy mux', () => FFmpegKit.execute(cmd));
          final rc = await sess.getReturnCode();
          if (!ReturnCode.isSuccess(rc) || !out.existsSync() || out.lengthSync() == 0) {
            final tail = await _sessionLogTail(sess);
            throw Exception('Could not pack the video (rc: $rc)\n$tail');
          }
          tempFinalFile = out;
        }

        await _saveFinishedVideo(
          context: context,
          tempFinalFile: tempFinalFile,
          ext: ext,
          resolution: resolution,
          codec: codec,
          depth: depthUsed,
          container: container,
          timestamp: timestamp,
          encoderLine: encoderLine,
          onProgress: onProgress,
        );
        return;
      }

      // ---- 2. Software encoder (VP9 / AV1 / ProRes / 4:4:4): CPU-safety probe ----
      String depth = bitDepth;
      await CpuSafe.ensureLoaded();
      {
        // CPU-safety probe: a ~1 s test encode with the real encoder settings BEFORE the long render, so an encoder that
        // executes an instruction this phone lacks (SIGILL) fails in a second, and the next launch steps it down.
        final String? guardedEncoder = CpuSafe.encoderForCodec(codec);
        final bool probeTenBit = bitDepth.startsWith('10') || bitDepth.startsWith('16');
        onProgress(0.01, 'Checking encoder compatibility...');
        await CpuSafe.verifyConversion(tenBit: probeTenBit); // FFmpeg's own colour conversion (every codec incl. ProRes)
        if (guardedEncoder != null) {
          final depthOk = await CpuSafe.verifyEncoder(guardedEncoder, tenBit: probeTenBit, chroma444: bitDepth.startsWith('16'));
          if (!depthOk && ExportMatrix.isBitDepthValid(_matrixKey(container), codec, '8-bit')) {
            depth = '8-bit';
            final note = 'This phone cannot encode $bitDepth with $codec. Exporting 8-bit instead.';
            onProgress(0.02, note);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note), duration: const Duration(seconds: 5)));
            }
          }
        }
      }

      final int threads = _encoderThreads();
      final String encoderLine = 'Using ${_softwareLabel(codec)}${isVp9 || isAv1 ? ', $threads threads' : ''}';
      onProgress(0.02, encoderLine);
      CrashLog.note(encoderLine);
      debugPrint('EXPORT: $encoderLine');
      CrashLog.note('plan: $totalFrames frames -> ${outW}x$outH, frames to the encoder as ${nv12 ? 'NV12 (GPU converted)' : 'RGBA8 (FFmpeg converts)'}');

      const batchSize = 30;
      final totalBatches = (totalFrames / batchSize).ceil();
      final List<String> partVideoPaths = [];
      Future<void>? pendingEncode; // encode of the previous batch, running while the next batch is decoded + rendered
      final String partExt = container.toLowerCase();
      final String rawExt = nv12 ? 'nv12' : 'rgba';

      // Pass 1: rolling 30-frame GPU pipeline. Each batch is written to ONE raw file (the rawvideo demuxer does not expand frame_%04d patterns).
      for (int b = 0; b < totalBatches; b++) {
        final startFrame = b * batchSize;
        final endFrame = (startFrame + batchSize).clamp(0, totalFrames);
        final currentBatchCount = endFrame - startFrame;

        // Decode this whole batch of source frames in ONE ffmpeg call (instead of one ffmpeg process per frame).
        final prep = prepareFrames;
        if (prep != null) {
          CrashLog.note('batch $b/$totalBatches source decode START (frames ${startFrame + 1}..$endFrame)'); // one flushed note per batch, not per frame
          await StageTimer.time('batch: decode source', () => prep(startFrame * frameIntervalMs, currentBatchCount, videoFps));
        }

        final rawFile = File('${sessionTempDir.path}/batch_$b.$rawExt');
        final raf = await rawFile.open(mode: FileMode.write);
        int renderUsTotal = 0;
        int renderUsMax = 0;
        try {
          for (int f = 0; f < currentBatchCount; f++) {
            final globalFrameIdx = startFrame + f;
            final timeMs = globalFrameIdx * frameIntervalMs;

            final frameWatch = Stopwatch()..start();
            final bytes = await render(timeMs);
            final us = frameWatch.elapsedMicroseconds;
            renderUsTotal += us;
            if (us > renderUsMax) renderUsMax = us;
            if (bytes.length != expectedBytes) {
              throw Exception(
                'Frame $globalFrameIdx returned ${bytes.length} bytes, expected $expectedBytes '
                '(${outW}x$outH ${nv12 ? 'NV12' : 'RGBA8'}).',
              );
            }
            await StageTimer.time('frame: write raw to disk', () => raf.writeFrom(bytes));

            final progressRatio = (globalFrameIdx / totalFrames) * 0.70;
            onProgress(progressRatio, 'Rendering frames (${globalFrameIdx + 1}/$totalFrames)...');
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
        // ONE log line per batch (the per-frame disk-flushing notes are gone)
        ExportNotes.add('batch $b: frames ${startFrame + 1}..$endFrame rendered, avg ${(renderUsTotal / currentBatchCount / 1000).toStringAsFixed(0)} ms/frame, '
            'max ${(renderUsMax / 1000).toStringAsFixed(0)} ms');
        ExportNotes.flush();

        // Encode batch part straight into the FINAL codec (no FFV1 mezzanine, no second encode).
        final partFile = File('${sessionTempDir.path}/part_${b.toString().padLeft(4, '0')}.$partExt');
        final ffmpegBatchCmd = _buildBatchEncodeCmd(
          inputFile: rawFile.path,
          outputFile: partFile.path,
          fps: videoFps,
          outW: outW,
          outH: outH,
          nv12: nv12,
          codec: codec,
          bitDepth: depth,
          bitrateProfile: bitrateProfile,
          container: container,
          threads: threads,
        );

        // At most ONE encode in flight: wait for the previous batch's encode, then start this one WITHOUT waiting, so the
        // GPU (next batch) and the encoder work at the same time instead of taking turns.
        if (pendingEncode != null) {
          await pendingEncode;
          pendingEncode = null;
        }
        partVideoPaths.add(partFile.path);
        final String encCmd = ffmpegBatchCmd;
        final int bIdx = b;
        final File rawRef = rawFile;
        final File partRef = partFile;
        pendingEncode = () async {
          if (bIdx == 0) CrashLog.note('first batch encode START: ffmpeg $encCmd');
          final session = await StageTimer.time('batch: encode', () => FFmpegKit.execute(encCmd));
          final rc = await session.getReturnCode();
          ExportNotes.add('batch $bIdx encode rc=$rc');
          if (!ReturnCode.isSuccess(rc) || !partRef.existsSync() || partRef.lengthSync() == 0) {
            final logTail = await _sessionLogTail(session);
            debugPrint('FFmpeg cmd: $encCmd\n$logTail');
            CrashLog.note('batch $bIdx encode FAILED rc=$rc: ffmpeg $encCmd');
            throw Exception('FFmpeg batch $bIdx failed (rc: $rc)\n$logTail');
          }
          try {
            rawRef.deleteSync(); // immediate disk cleanup of the raw batch
          } catch (_) {}
        }();
        pendingEncode.ignore(); // an error is still thrown by the await above / below; this only silences "unhandled"
      }

      if (pendingEncode != null) {
        await pendingEncode; // last batch must be finished before the parts are joined
        pendingEncode = null;
      }
      ExportNotes.flush();

      // Pass 2: concatenate parts (stream copy) & remux original audio
      onProgress(0.75, 'Joining parts...');
      final concatListFile = File('${sessionTempDir.path}/concat_list.txt');
      final concatContent = partVideoPaths.map((p) => "file '$p'").join('\n');
      await concatListFile.writeAsString(concatContent, flush: true);

      final ext = container.toLowerCase();
      final tempFinalFile = File('${sessionTempDir.path}/temp_master_$timestamp.$ext');

      // -map is required: without it ffmpeg may pick the ORIGINAL video's picture stream from the audio source instead of the graded concat output.
      // Audio codec must match the container (WebM/MKV -> opus, MP4/MOV -> aac).
      final bool isMp4Family = container == 'MP4' || container == 'MOV';
      final fastStart = isMp4Family ? '-movflags +faststart' : '';
      const String hvcTag = '';   // software parts carry their own tags (hvc1 is set per part in _buildBatchEncodeCmd)
      const String colorTags = '';
      String concatCmd;
      if (audioSourcePath != null && File(audioSourcePath).existsSync()) {
        final audioCodec = ExportMatrix.getAudioCodec(container);
        concatCmd = '-y -f concat -safe 0 -i "${concatListFile.path}" -i "$audioSourcePath" '
            '-map 0:v:0 -map 1:a:0? -c:v copy $hvcTag$colorTags-c:a $audioCodec -b:a 320k -shortest $fastStart "${tempFinalFile.path}"';
      } else {
        concatCmd = '-y -f concat -safe 0 -i "${concatListFile.path}" -c copy $hvcTag$colorTags$fastStart "${tempFinalFile.path}"';
      }

      CrashLog.note('concat START: ffmpeg $concatCmd');
      final concatSession = await StageTimer.time('final: concat + audio', () => FFmpegKit.execute(concatCmd));
      final concatRc = await concatSession.getReturnCode();

      if (!ReturnCode.isSuccess(concatRc) || !tempFinalFile.existsSync() || tempFinalFile.lengthSync() == 0) {
        final logTail = await _sessionLogTail(concatSession);
        debugPrint('FFmpeg concat cmd: $concatCmd\n$logTail');
        throw Exception('Stream concatenation failed (rc: $concatRc)\n$logTail');
      }

      // Pass 3: save to Movies/Shaderly
      onProgress(0.92, 'Saving video...');
      final cleanCodec = codec.replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '_');
      final cleanBitDepth = depth.replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '_');
      final fileName = 'Shaderly_${resolution}_${cleanCodec}_${cleanBitDepth}_$timestamp.$ext';

      // MIME must match the extension or MediaStore may rename/reject the file.
      final mimeType = container == 'WEBM'
          ? 'video/webm'
          : container == 'MOV'
              ? 'video/quicktime'
              : container == 'MKV'
                  ? 'video/x-matroska'
                  : 'video/mp4';

      final finalUri = await StageTimer.time('save to Movies', () => saveToMovies(
        sourcePath: tempFinalFile.path,
        fileName: fileName,
        mimeType: mimeType,
      ));

      CrashLog.note('saved to MediaStore: $finalUri');
      final timingReport = '$encoderLine\n${StageTimer.summary()}';
      CrashLog.note(timingReport);
      CrashLog.end('video export finished');
      onProgress(1.0, 'Export complete!');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Movies/Shaderly: $fileName'),
            backgroundColor: const Color(0xFF00E5FF),
          ),
        );
      }
      if (kShowExportTiming && context.mounted) {
        await StageTimer.showReport(context, timingReport);
      }
    } catch (e) {
      ExportNotes.flush();
      CrashLog.end('FAILED with a Dart exception: $e');
      rethrow;
    } finally {
      vulkanSetBandBudgetMs(40);
      // an export that stopped half way must not leave a MediaCodec / Surface open (after a normal finish nothing is active)
      if (NativeEncoder.active != null) {
        try {
          await NativeEncoder.cancel();
        } catch (_) {}
      }
      // Release the decoded source batch (it can be hundreds of MB on disk)
      try {
        await prepareFrames?.call(0, 0, videoFps);
      } catch (_) {}
      // Back to the source-size, RGBA preview / image-export behaviour
      try {
        await configureRender(0, 0, false);
      } catch (_) {}
      // Purge session scratch directory
      try {
        if (sessionTempDir != null && sessionTempDir.existsSync()) {
          sessionTempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }


  // Shared last step of the hardware path: save to Movies/Shaderly and report.
  static Future<void> _saveFinishedVideo({
    required BuildContext context,
    required File tempFinalFile,
    required String ext,
    required String resolution,
    required String codec,
    required String depth,
    required String container,
    required int timestamp,
    required String encoderLine,
    required Function(double, String) onProgress,
  }) async {
    onProgress(0.97, 'Saving video...');
    final cleanCodec = codec.replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '_');
    final cleanBitDepth = depth.replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '_');
    final fileName = 'Shaderly_${resolution}_${cleanCodec}_${cleanBitDepth}_$timestamp.$ext';
    final mimeType = container == 'WEBM'
        ? 'video/webm'
        : container == 'MOV'
            ? 'video/quicktime'
            : container == 'MKV'
                ? 'video/x-matroska'
                : 'video/mp4';
    final finalUri = await StageTimer.time('save to Movies', () => saveToMovies(
          sourcePath: tempFinalFile.path,
          fileName: fileName,
          mimeType: mimeType,
        ));
    CrashLog.note('saved to MediaStore: $finalUri');
    final timingReport = '$encoderLine\n${StageTimer.summary()}';
    CrashLog.note(timingReport);
    CrashLog.end('video export finished');
    onProgress(1.0, 'Export complete!');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to Movies/Shaderly: $fileName'), backgroundColor: const Color(0xFF00E5FF)),
      );
    }
    if (kShowExportTiming && context.mounted) {
      await StageTimer.showReport(context, timingReport);
    }
  }

  // ===========================================================================
  // ENCODER HELPERS
  // ===========================================================================
  static int _profileMbps(String bitrateProfile) {
    final m = RegExp(r'(\d+)\s*Mbps').firstMatch(bitrateProfile); // '10 Mbps' ... '80 Mbps'; 'Lossless (CRF 14)' has none -> 0
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  /// The hardware encoder is bitrate controlled (no CRF). The profile's Mbps, or for "Lossless" a high bitrate for the size (0.3 bit / pixel / frame, 12..100 Mbps).
  static int _hardwareMbps(String bitrateProfile, int w, int h, double fps) {
    final int p = _profileMbps(bitrateProfile);
    if (p > 0) return p;
    return ((w * h * fps * 0.30) / 1000000.0).round().clamp(12, 100).toInt();
  }

  /// Threads for the software VP9 / AV1 encoders: all cores, at most 8.
  static int _encoderThreads() {
    final int n = Platform.numberOfProcessors;
    if (n < 2) return 2;
    return n > 8 ? 8 : n;
  }

  static String _softwareLabel(String codec) {
    if (codec.contains('ProRes')) return 'ProRes (prores_ks, software)';
    if (codec.contains('HEVC') || codec.contains('H.265')) return 'Software HEVC (libx265)';
    if (codec.contains('AV1')) return 'Software AV1 (libsvtav1)';
    if (codec.contains('VP9')) return 'Software VP9 (libvpx-vp9)';
    return 'Software H.264 (libx264)';
  }

  // ===========================================================================
  // MASTER MATRIX FFMPEG COMMAND GENERATOR (one batch of raw frames -> a part in the FINAL codec)
  // Input is NV12 from the GPU (nv12 = true, no colour conversion in FFmpeg) or RGBA8 (nv12 = false, only for a native library without batch 18B).
  // ===========================================================================
  static String _buildBatchEncodeCmd({
    required String inputFile,
    required String outputFile,
    required double fps,
    required int outW,
    required int outH,
    required bool nv12,
    required String codec,
    required String bitDepth,
    required String bitrateProfile,
    required String container,
    required int threads,
  }) {
    const sdrTags = '-color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709';
    final String input = '-y ${CpuSafe.ffArgs()}-f rawvideo -pixel_format ${nv12 ? 'nv12' : 'rgba'} -video_size ${outW}x$outH -framerate $fps -i "$inputFile"';

    final is10Bit = bitDepth.startsWith('10');
    final is16Bit = bitDepth.startsWith('16');
    final isProRes = codec.contains('ProRes');
    final isHevc = codec.contains('HEVC') || codec.contains('H.265');
    final isAv1 = codec.contains('AV1');
    final isVp9 = codec.contains('VP9');

    // 1. Bit depth
    String pixFmt;
    if (is10Bit) {
      pixFmt = '-pix_fmt yuv420p10le';
    } else if (is16Bit) {
      // SVT-AV1 has no 4:4:4: AV1 stays 4:2:0 10-bit.
      pixFmt = isAv1 ? '-pix_fmt yuv420p10le' : '-pix_fmt yuv444p10le';
    } else {
      pixFmt = '-pix_fmt yuv420p';
    }

    // 2. Codec, speed preset and default quality
    String cOption;
    String speed = '';
    String rate = '';
    String extraFilters = '';
    String codecExtra = '';
    if (isProRes) {
      if (is16Bit) {
        cOption = '-c:v prores_ks -profile:v 4';
        pixFmt = '-pix_fmt yuv444p10le';
      } else {
        cOption = '-c:v prores_ks -profile:v 3';
        pixFmt = '-pix_fmt yuv422p10le';
      }
    } else if (isHevc) {
      // hvc1 is only valid in MP4 / MOV; Matroska rejects the tag and aborts the muxer.
      final hvcTag = (container.toUpperCase() == 'MP4' || container.toUpperCase() == 'MOV') ? ' -tag:v hvc1' : '';
      cOption = '-c:v libx265$hvcTag';
      speed = '-preset veryfast';
      rate = '-crf 20';
      // pools=none + frame-threads=1 are REQUIRED: without them libx265 dies with SIGILL on the Unisoc S6603L1 CPU (do not remove).
      codecExtra = '-x265-params log-level=error:pools=none:frame-threads=1:bframes=3:rc-lookahead=20${CpuSafe.x265AsmSuffix()}';
    } else if (isAv1) {
      cOption = '-c:v libsvtav1';
      speed = '-preset 10 -svtav1-params lp=$threads'; // lp = SVT-AV1's level of parallelism (logical processors it may use)
      rate = '-crf 24';
    } else if (isVp9) {
      cOption = '-c:v libvpx-vp9';
      // realtime deadline + cpu-used 6 + row multithreading on 4 tile columns, all cores
      speed = '-deadline realtime -cpu-used 6 -row-mt 1 -tile-columns 2 -threads $threads';
      rate = '-crf 22 -b:v 0';
      extraFilters = ',unsharp=5:5:0.3:5:5:0.0';
    } else {
      cOption = '-c:v libx264';
      speed = '-preset fast';
      codecExtra = CpuSafe.x264Args();
      rate = '-crf 18';
    }

    // 3. Bitrate / quality profile (ProRes ignores it).
    // Note: -preset medium is only valid for x264/x265. Passing it to SVT-AV1 or VP9 makes ffmpeg abort.
    if (!isProRes) {
      if (bitrateProfile.contains('Lossless')) {
        rate = isHevc ? '-crf 12' : (isVp9 ? '-crf 14 -b:v 0' : '-crf 14');
        if (!isAv1 && !isVp9 && !isHevc) speed = '-preset medium';
      } else {
        final int mbps = _profileMbps(bitrateProfile);
        if (mbps > 0) {
          rate = isAv1
              ? '-b:v ${mbps}M'
              : '-b:v ${mbps}M -maxrate ${(mbps * 1.2).round()}M -bufsize ${mbps * 2}M';
        }
      }
    }

    // 4. Filter chain. NV12 input: only the pixel-format change (nv12 -> the encoder's format, a plane interleave, no scaling).
    //    RGBA input (fallback): RGB -> YUV with the matrix the file is tagged with, at the size that is already the export size.
    final String pixName = pixFmt.replaceFirst('-pix_fmt ', '');
    final String vf = nv12
        ? 'format=$pixName$extraFilters'
        : 'scale=out_color_matrix=bt709:out_range=tv:flags=bicubic,format=$pixName$extraFilters';

    return '$input -vf "$vf" $cOption $speed $codecExtra $pixFmt $sdrTags $rate "$outputFile"';
  }

  // ===========================================================================
  // DIMENSION CALCULATOR (Aspect Ratio Preserving)
  // ===========================================================================
  static Map<String, int> _calculateDimensions(String resName, int srcW, int srcH) {
    int targetLongEdge;
    switch (resName) {
      case '720p':
        targetLongEdge = 1280;
        break;
      case '1080p':
        targetLongEdge = 1920;
        break;
      case '2K':
        targetLongEdge = 2560;
        break;
      case '4K':
        targetLongEdge = 3840;
        break;
      case 'Native':
      default:
        targetLongEdge = srcW > srcH ? srcW : srcH;
        break;
    }

    final aspect = srcW / srcH;
    int w, h;
    if (aspect >= 1.0) {
      w = targetLongEdge;
      h = (targetLongEdge / aspect).round();
    } else {
      h = targetLongEdge;
      w = (targetLongEdge * aspect).round();
    }

    // Ensure even dimensions for YUV 4:2:0 subsampling (executeVideoExport rounds the width up to a multiple of 4 for the GPU NV12 pass)
    if (w % 2 != 0) w += 1;
    if (h % 2 != 0) h += 1;

    return {'w': w, 'h': h};
  }
}

// =============================================================================
// Batch 18B: batched export notes. CrashLog.note() writes (and flushes) to disk on EVERY call; the export used to call it several times per frame.
// Lines collected here are written by ONE CrashLog.note() per flush (the export flushes once per batch, and when something fails).
// =============================================================================
class ExportNotes {
  ExportNotes._();
  static final List<String> _lines = <String>[];

  static void add(String line) {
    _lines.add(line);
    if (_lines.length >= 40) flush(); // never let it grow without a flush
  }

  static void flush() {
    if (_lines.isEmpty) return;
    CrashLog.note(_lines.join('\n'));
    _lines.clear();
  }

  static void clear() => _lines.clear();
}
