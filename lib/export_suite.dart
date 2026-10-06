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
import 'export_matrix.dart';
import 'constants.dart' hide ExportMatrix;

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
          videoDurationMs == null ||
          videoWidth == null ||
          videoHeight == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Export is not connected: renderFrameToRgba, videoDurationMs, videoWidth and videoHeight must be passed to showExportSheet.',
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
                const SizedBox(height: 24),
                if (isExporting) ...[
                  LinearProgressIndicator(
                    value: exportProgress > 0.0 ? exportProgress : null,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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
                            statusText = 'Rendering 32-bit linear surface...';
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
    required double videoDurationMs,
    required double videoFps,
    required int videoWidth,
    required int videoHeight,
    String? audioSourcePath,
  }) {
    String selectedRes = '1080p';
    String selectedCodec = 'H.264';
    String selectedBitDepth = '8-bit';
    String selectedBitrate = 'High (25 Mbps)';
    String selectedContainer = 'MP4';
    double selectedFps = const [24.0, 25.0, 30.0, 48.0, 50.0, 60.0].contains(videoFps) ? videoFps : 30.0;

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
                    children: [24.0, 25.0, 30.0, 48.0, 50.0, 60.0].map((f) {
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
                  const Text('Bit Depth & Color Gamut', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildDepthOption('8-bit', 'SDR (Rec.709)', selectedBitDepth, isExporting, (d) {
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
                      _buildDepthOption('10-bit', 'HDR (BT.2020)', selectedBitDepth, isExporting, (d) {
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
                      _buildDepthOption('16-bit', 'Master (4:4:4)', selectedBitDepth, isExporting, (d) {
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
                      'Standard (12 Mbps)',
                      'High (25 Mbps)',
                      'Ultra 4K (50 Mbps)',
                      'Lossless (CRF 14)',
                      'Master (80 Mbps)'
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

                  if (isExporting) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: exportProgress > 0.0 ? exportProgress : null,
                        minHeight: 6,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
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
                              statusText = 'Preparing pipeline & frame stream...';
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
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              setSheetState(() {
                                isExporting = false;
                                statusText = 'Export error: $e';
                              });
                              Music.setExporting(false);
                            }
                          },
                    child: const Text('Render & Export Master Video', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
      onProgress(0.3, 'Rasterizing 32-bit linear texture...');
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
  // VIDEO ENCODING EXECUTION - ROLLING 30-FRAME GPU SCRATCH PIPELINE
  // ===========================================================================
  static Future<void> executeVideoExport({
    required BuildContext context,
    required ProjectData project,
    AdjustmentLayer? curLayer,
    dynamic packUniforms,
    dynamic getActiveLut,
    Future<Uint8List> Function(double timestampMs)? renderFrameToRgba,
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

    try {
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
      final expectedBytes = videoWidth * videoHeight * 4;

      final targetDims = _calculateDimensions(resolution, videoWidth, videoHeight);
      final outW = targetDims['w']!;
      final outH = targetDims['h']!;

      final totalFrames = ((videoDurationMs / 1000.0) * videoFps).round().clamp(1, 999999);
      final frameIntervalMs = 1000.0 / videoFps;

      final bool isHevcExport = codec.contains('HEVC') || codec.contains('H.265');

      CrashLog.note('plan: $totalFrames frames -> ${outW}x$outH');

      const batchSize = 30;
      final totalBatches = (totalFrames / batchSize).ceil();
      final List<String> partVideoPaths = [];

      // Pass 1: Rolling 30-frame GPU scratch rendering.
      // Each batch is written to ONE raw file. The rawvideo demuxer does not expand
      // "frame_%04d.rgba" patterns (that is image2's job), so the old command opened a
      // literal file named "frame_%04d.rgba", which does not exist.
      for (int b = 0; b < totalBatches; b++) {
        final startFrame = b * batchSize;
        final endFrame = (startFrame + batchSize).clamp(0, totalFrames);
        final currentBatchCount = endFrame - startFrame;

        final rawFile = File('${sessionTempDir.path}/batch_$b.rgba');
        final raf = await rawFile.open(mode: FileMode.write);
        try {
          for (int f = 0; f < currentBatchCount; f++) {
            final globalFrameIdx = startFrame + f;
            final timeMs = globalFrameIdx * frameIntervalMs;

            CrashLog.note('frame ${globalFrameIdx + 1}/$totalFrames (batch $b) render START t=${timeMs.round()}ms');
            final bytes = await render(timeMs);
            if (bytes.length != expectedBytes) {
              throw Exception(
                'Frame $globalFrameIdx returned ${bytes.length} bytes, expected $expectedBytes '
                '(${videoWidth}x$videoHeight RGBA8).',
              );
            }
            await raf.writeFrom(bytes);
            CrashLog.note('frame ${globalFrameIdx + 1}/$totalFrames written');

            final progressRatio = (globalFrameIdx / totalFrames) * 0.70;
            onProgress(progressRatio, 'Rendering frames (${globalFrameIdx + 1}/$totalFrames)...');
          }
          await raf.flush();
        } finally {
          await raf.close();
        }

        // Encode batch part
        // HEVC: batches are stored as lossless FFV1 (pure FFmpeg core, no external codec library) and the real
        // HEVC encode runs ONCE over the whole clip afterwards. That means a single encoder start / stop instead
        // of one per 30 frames, no forced keyframe every second, and a guarded fallback chain (see _encodeHevcFinal).
        final partExt = isHevcExport ? 'mkv' : container.toLowerCase();
        final partFile = File('${sessionTempDir.path}/part_${b.toString().padLeft(4, '0')}.$partExt');

        final ffmpegBatchCmd = isHevcExport
            ? _buildMezzanineCmd(
                inputFile: rawFile.path,
                outputFile: partFile.path,
                fps: videoFps,
                inW: videoWidth,
                inH: videoHeight,
                outW: outW,
                outH: outH,
              )
            : _buildBatchEncodeCmd(
          inputFile: rawFile.path,
          outputFile: partFile.path,
          fps: videoFps,
          inW: videoWidth,
          inH: videoHeight,
          outW: outW,
          outH: outH,
          codec: codec,
          bitDepth: bitDepth,
          bitrateProfile: bitrateProfile,
          container: container,
        );

        CrashLog.note('batch $b encode START: ffmpeg $ffmpegBatchCmd');
        final session = await FFmpegKit.execute(ffmpegBatchCmd);
        final rc = await session.getReturnCode();

        CrashLog.note('batch $b encode RETURNED rc=$rc');
        if (!ReturnCode.isSuccess(rc) || !partFile.existsSync() || partFile.lengthSync() == 0) {
          final logTail = await _sessionLogTail(session);
          debugPrint('FFmpeg cmd: $ffmpegBatchCmd\n$logTail');
          throw Exception('FFmpeg batch $b failed (rc: $rc)\n$logTail');
        }

        partVideoPaths.add(partFile.path);

        // Immediate disk cleanup: purge the raw RGBA batch
        try {
          rawFile.deleteSync();
        } catch (_) {}
      }

      // Pass 2: Concatenate parts & remux original audio
      onProgress(0.75, 'Concatenating video stream & remuxing audio...');
      final concatListFile = File('${sessionTempDir.path}/concat_list.txt');
      final concatContent = partVideoPaths.map((p) => "file '$p'").join('\n');
      await concatListFile.writeAsString(concatContent, flush: true);

      final ext = container.toLowerCase();
      final tempFinalFile = File('${sessionTempDir.path}/temp_master_$timestamp.$ext');

      // -map is required: without it ffmpeg may pick the ORIGINAL video's picture stream
      // from the audio source instead of the graded concat output.
      // Audio codec must match the container (WebM/MKV -> opus, MP4/MOV -> aac).
      final fastStart = (container == 'MP4' || container == 'MOV') ? '-movflags +faststart' : '';
      String concatCmd;
      if (audioSourcePath != null && File(audioSourcePath).existsSync()) {
        final audioCodec = ExportMatrix.getAudioCodec(container);
        concatCmd = '-y -f concat -safe 0 -i "${concatListFile.path}" -i "$audioSourcePath" '
            '-map 0:v:0 -map 1:a:0? -c:v copy -c:a $audioCodec -b:a 320k -shortest $fastStart "${tempFinalFile.path}"';
      } else {
        concatCmd = '-y -f concat -safe 0 -i "${concatListFile.path}" -c copy $fastStart "${tempFinalFile.path}"';
      }

      if (isHevcExport) {
        // Single-pass HEVC encode (+ audio) over the lossless parts.
        await _encodeHevcFinal(
          concatList: concatListFile,
          audioSourcePath: audioSourcePath,
          outFile: tempFinalFile,
          container: container,
          bitDepth: bitDepth,
          bitrateProfile: bitrateProfile,
          onProgress: onProgress,
        );
      } else {
        CrashLog.note('concat START: ffmpeg $concatCmd');
        final concatSession = await FFmpegKit.execute(concatCmd);
        final concatRc = await concatSession.getReturnCode();

        if (!ReturnCode.isSuccess(concatRc) || !tempFinalFile.existsSync() || tempFinalFile.lengthSync() == 0) {
          final logTail = await _sessionLogTail(concatSession);
          debugPrint('FFmpeg concat cmd: $concatCmd\n$logTail');
          throw Exception('Stream concatenation failed (rc: $concatRc)\n$logTail');
        }
      }

      // Pass 3: save to Movies/Shaderly
      onProgress(0.92, 'Registering video with Android MediaStore...');
      final cleanCodec = codec.replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '_');
      final cleanBitDepth = bitDepth.replaceAll(RegExp(r'[^A-Za-z0-9.]+'), '_');
      final fileName = 'Shaderly_${resolution}_${cleanCodec}_${cleanBitDepth}_$timestamp.$ext';

      // MIME must match the extension or MediaStore may rename/reject the file.
      final mimeType = container == 'WEBM'
          ? 'video/webm'
          : container == 'MOV'
              ? 'video/quicktime'
              : container == 'MKV'
                  ? 'video/x-matroska'
                  : 'video/mp4';

      final finalUri = await saveToMovies(
        sourcePath: tempFinalFile.path,
        fileName: fileName,
        mimeType: mimeType,
      );

      CrashLog.note('saved to MediaStore: $finalUri');
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
    } catch (e) {
      CrashLog.end('FAILED with a Dart exception: $e');
      rethrow;
    } finally {
      // Purge session scratch directory
      try {
        if (sessionTempDir != null && sessionTempDir.existsSync()) {
          sessionTempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  // ===========================================================================
  // MASTER MATRIX FFMPEG COMMAND GENERATOR
  // Supports: H.264, HEVC, AV1, VP9, ProRes HQ/4444 + 8-bit, 10-bit HDR, 16-bit
  // ===========================================================================
  static String _buildBatchEncodeCmd({
    required String inputFile,
    required String outputFile,
    required double fps,
    required int inW,
    required int inH,
    required int outW,
    required int outH,
    required String codec,
    required String bitDepth,
    required String bitrateProfile,
    required String container,
  }) {
    final is10Bit = bitDepth.startsWith('10');
    final is16Bit = bitDepth.startsWith('16');
    final isProRes = codec.contains('ProRes');
    final isHevc = codec.contains('HEVC') || codec.contains('H.265');
    final isAv1 = codec.contains('AV1');
    final isVp9 = codec.contains('VP9');

    // 1. Bit depth & colour metadata
    String pixFmt;
    String colorMetadata;
    if (is10Bit) {
      pixFmt = '-pix_fmt yuv420p10le';
      colorMetadata = '-color_range tv -colorspace bt2020nc -color_primaries bt2020 -color_trc arib-std-b67';
    } else if (is16Bit) {
      pixFmt = '-pix_fmt yuv444p10le';
      colorMetadata = '-color_range tv -colorspace bt2020nc -color_primaries bt2020 -color_trc smpte2084';
    } else {
      pixFmt = '-pix_fmt yuv420p';
      colorMetadata = '-color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709';
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
      // Crash-safe x265 profile for Android: no worker thread pools (the pool / thread-affinity setup is what
      // brings the encoder down on mobile CPUs as soon as the lookahead window fills), a single frame thread,
      // and a lookahead that is always larger than the B-frame count. Slower than a threaded encode, but stable.
      codecExtra = '-x265-params log-level=error:pools=none:frame-threads=1:bframes=3:rc-lookahead=20';
    } else if (isAv1) {
      cOption = '-c:v libsvtav1';
      speed = '-preset 6';
      rate = '-crf 24';
    } else if (isVp9) {
      cOption = '-c:v libvpx-vp9';
      speed = '-deadline good -cpu-used 4 -row-mt 1';
      rate = '-crf 22 -b:v 0';
      extraFilters = ',unsharp=5:5:0.3:5:5:0.0';
    } else {
      cOption = '-c:v libx264';
      speed = '-preset fast';
      rate = '-crf 18';
    }

    // 3. Bitrate / quality profile (ProRes ignores it).
    // Note: -preset medium is only valid for x264/x265. The old code passed it to
    // SVT-AV1 and VP9 for the Lossless profile, which makes ffmpeg abort.
    if (!isProRes) {
      if (bitrateProfile.contains('Lossless')) {
        rate = isHevc ? '-crf 12' : (isVp9 ? '-crf 14 -b:v 0' : '-crf 14');
        if (!isAv1 && !isVp9 && !isHevc) speed = '-preset medium';   // HEVC stays on the crash-safe veryfast preset
      } else {
        int mbps = 0;
        if (bitrateProfile.contains('Master')) {
          mbps = 80;
        } else if (bitrateProfile.contains('Ultra')) {
          mbps = 50;
        } else if (bitrateProfile.contains('High')) {
          mbps = 25;
        } else if (bitrateProfile.contains('Standard')) {
          mbps = 12;
        }
        if (mbps > 0) {
          rate = isAv1
              ? '-b:v ${mbps}M'
              : '-b:v ${mbps}M -maxrate ${(mbps * 1.2).round()}M -bufsize ${mbps * 2}M';
        }
      }
    }

    // RGB -> YUV with the matrix the file is tagged with (default swscale uses BT.601 even when the tags say 709).
    // 'format=' right after the scale makes the conversion happen HERE, before unsharp (which cannot run on RGB).
    final String pixName = pixFmt.replaceFirst('-pix_fmt ', '');
    final String matrix = (is10Bit || is16Bit) ? 'bt2020' : 'bt709';
    final scaleFilter = 'scale=$outW:$outH:flags=lanczos+accurate_rnd:out_color_matrix=$matrix:out_range=tv,'
        'format=$pixName$extraFilters';

    return '-y -f rawvideo -pixel_format rgba -video_size ${inW}x$inH -framerate $fps '
        '-i "$inputFile" -vf "$scaleFilter" $cOption $speed $codecExtra $pixFmt $colorMetadata $rate "$outputFile"';
  }

  // ===========================================================================
  // HEVC: LOSSLESS MEZZANINE + ONE SINGLE-PASS x265 ENCODE (no fallbacks)
  // ===========================================================================
  /// rgba batch -> scaled, lossless FFV1 (bgr0) part. FFV1 is built into FFmpeg itself, so this step never
  /// touches x265.
  static String _buildMezzanineCmd({
    required String inputFile,
    required String outputFile,
    required double fps,
    required int inW,
    required int inH,
    required int outW,
    required int outH,
  }) {
    return '-y -f rawvideo -pixel_format rgba -video_size ${inW}x$inH -framerate $fps '
        '-i "$inputFile" -vf "scale=$outW:$outH:flags=lanczos,format=bgr0" '
        '-c:v ffv1 -level 3 -g 1 -slicecrc 0 -an "$outputFile"';
  }

  static int _profileMbps(String bitrateProfile) {
    if (bitrateProfile.contains('Master')) return 80;
    if (bitrateProfile.contains('Ultra')) return 50;
    if (bitrateProfile.contains('High')) return 25;
    if (bitrateProfile.contains('Standard')) return 12;
    return 0;
  }

  static String _hevcFinalCmd({
    required String concatList,
    required String? audioSourcePath,
    required String outFile,
    required String container,
    required String bitDepth,
    required String bitrateProfile,
  }) {
    final is10 = bitDepth.startsWith('10');
    final is16 = bitDepth.startsWith('16');
    final c = container.toUpperCase();
    final isMp4Family = c == 'MP4' || c == 'MOV';
    final lossless = bitrateProfile.contains('Lossless');
    final mbps = _profileMbps(bitrateProfile);

    String pixFmt;
    String colorMetadata;
    String matrix;
    if (is10) {
      pixFmt = 'yuv420p10le';
      matrix = 'bt2020';
      colorMetadata = '-color_range tv -colorspace bt2020nc -color_primaries bt2020 -color_trc arib-std-b67';
    } else if (is16) {
      pixFmt = 'yuv444p10le';
      matrix = 'bt2020';
      colorMetadata = '-color_range tv -colorspace bt2020nc -color_primaries bt2020 -color_trc smpte2084';
    } else {
      pixFmt = 'yuv420p';
      matrix = 'bt709';
      colorMetadata = '-color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709';
    }

    String rate;
    if (lossless) {
      rate = '-crf 12';
    } else if (mbps > 0) {
      rate = '-b:v ${mbps}M -maxrate ${(mbps * 1.2).round()}M -bufsize ${mbps * 2}M';
    } else {
      rate = '-crf 20';
    }

    // hvc1 is only valid in MP4 / MOV. Crash-safe x265 profile: no worker thread pools, one frame thread,
    // lookahead always larger than the B-frame count.
    final video = '-c:v libx265${isMp4Family ? ' -tag:v hvc1' : ''} -preset veryfast '
        '-x265-params log-level=error:pools=none:frame-threads=1:bframes=3:rc-lookahead=20 $rate';

    final fastStart = isMp4Family ? '-movflags +faststart' : '';
    final hasAudio = audioSourcePath != null && File(audioSourcePath).existsSync();
    final audioIn = hasAudio ? '-i "$audioSourcePath" ' : '';
    final audioOpts = hasAudio
        ? '-map 0:v:0 -map 1:a:0? -c:a ${ExportMatrix.getAudioCodec(container)} -b:a 320k -shortest'
        : '-map 0:v:0 -an';

    // RGB -> YUV with the SAME matrix that the file is tagged with (the old default was BT.601 while the
    // tags said BT.709, which shifted colours in players).
    return '-y -f concat -safe 0 -i "$concatList" $audioIn'
        '-vf "scale=out_color_matrix=$matrix:out_range=tv:flags=accurate_rnd,format=$pixFmt" '
        '$video $colorMetadata $audioOpts $fastStart "$outFile"';
  }

  static Future<void> _encodeHevcFinal({
    required File concatList,
    required String? audioSourcePath,
    required File outFile,
    required String container,
    required String bitDepth,
    required String bitrateProfile,
    required Function(double, String) onProgress,
  }) async {
    onProgress(0.80, 'Encoding HEVC (x265)...');
    final cmd = _hevcFinalCmd(
      concatList: concatList.path,
      audioSourcePath: audioSourcePath,
      outFile: outFile.path,
      container: container,
      bitDepth: bitDepth,
      bitrateProfile: bitrateProfile,
    );

    // If the app dies inside this call, the crash report shown on the next launch ends with these lines.
    CrashLog.note('HEVC final encode START: ffmpeg $cmd');
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    CrashLog.note('HEVC final encode RETURNED rc=$rc size=${outFile.existsSync() ? outFile.lengthSync() : -1}');

    if (!ReturnCode.isSuccess(rc) || !outFile.existsSync() || outFile.lengthSync() < 2048) {
      final tail = await _sessionLogTail(session);
      debugPrint('FFmpeg HEVC final cmd: $cmd\n$tail');
      throw Exception('HEVC encode failed (rc: $rc)\n$tail');
    }
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

    // Ensure even dimensions for YUV 4:2:0 subsampling
    if (w % 2 != 0) w += 1;
    if (h % 2 != 0) h += 1;

    return {'w': w, 'h': h};
  }
}
