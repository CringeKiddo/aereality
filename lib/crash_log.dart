// =============================================================================
// AEReality / Shaderly - Crash Log
// Explains WHY the app died, the next time it is opened.
//
// A native crash (x265, FFmpeg, Vulkan, out-of-memory kill) takes the whole process down, so nothing in Dart can
// catch it. Instead this file leaves evidence behind and reads it back on the next launch:
//
//   1. BREADCRUMBS  - CrashLog.begin() / note() / end() wrap risky work (exports). Every note is flushed to disk
//                     immediately, with elapsed time and the app's memory use (rss).
//   2. MARKER FILE  - exists only while a risky operation is running. Found on launch = the app died inside it.
//   3. ANDROID'S OWN RECORD - getHistoricalProcessExitReasons (Android 11+) says how the process died
//                     (native crash / out of memory / ANR ...) and, for native crashes, includes strings from the
//                     tombstone (signal, library and function names).
//
// On launch, if anything above says the app died unexpectedly, a dialog shows the report with a Copy button.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'constants.dart' show kCardDark, kCyanAccent;

class CrashLog {
  static const MethodChannel _channel = MethodChannel('com.aereality/media');

  /// Give this to MaterialApp(navigatorKey: ...) so the report dialog can be shown from anywhere.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Directory? _dir;
  static final Stopwatch _clock = Stopwatch();
  static bool _active = false;

  /// Report built during init() when the previous session ended badly. Null = nothing to show.
  static String? pendingReport;

  static File get _trail => File('${_dir!.path}/trail.txt');
  static File get _marker => File('${_dir!.path}/running.marker');
  static File get _seen => File('${_dir!.path}/last_seen_exit.txt');
  static File get _lastReportFile => File('${_dir!.path}/last_report.txt');

  // ---------------------------------------------------------------------------
  // STARTUP
  // ---------------------------------------------------------------------------
  /// Call once in main(), after WidgetsFlutterBinding.ensureInitialized().
  static Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      _dir = Directory('${base.path}/crash_log');
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
      await _buildPendingReport();
    } catch (e) {
      debugPrint('CrashLog.init failed: $e');
    }
  }

  /// Logs Flutter / async Dart errors into the trail (they do not crash the app, but they explain a lot).
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      error(d.exception, d.stack);
      if (previous != null) {
        previous(d);
      } else {
        FlutterError.presentError(d);
      }
    };
    ui.PlatformDispatcher.instance.onError = (Object e, StackTrace s) {
      error(e, s);
      return false;
    };
  }

  /// Call right after runApp(); shows the dialog once the first frame is up.
  static void scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await showPendingReport();
    });
  }

  // ---------------------------------------------------------------------------
  // BREADCRUMB API
  // ---------------------------------------------------------------------------
  static void begin(String operation, [Map<String, Object?> info = const {}]) {
    if (_dir == null) return;
    try {
      _clock
        ..reset()
        ..start();
      _active = true;
      final b = StringBuffer()
        ..writeln('OPERATION: $operation')
        ..writeln('started: ${DateTime.now().toIso8601String()}')
        ..writeln('platform: ${Platform.operatingSystemVersion}');
      info.forEach((k, v) => b.writeln('$k: $v'));
      b.writeln('--- steps ---');
      _trail.writeAsStringSync(b.toString(), flush: true);
      _marker.writeAsStringSync(operation, flush: true);
      note('begin');
    } catch (e) {
      debugPrint('CrashLog.begin failed: $e');
    }
  }

  static void note(String message) {
    if (_dir == null || !_active) return;
    try {
      String mem = '';
      try {
        mem = ' rss=${ProcessInfo.currentRss ~/ (1024 * 1024)}MB';
      } catch (_) {}
      _trail.writeAsStringSync(
        '[${_clock.elapsedMilliseconds}ms$mem] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static void error(Object e, StackTrace? st) {
    if (_dir == null) return;
    try {
      final s = (st ?? StackTrace.empty).toString().split('\n').take(6).join('\n');
      _trail.writeAsStringSync(
        '[ERROR] $e\n$s\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// Call when the operation finished (or failed with a normal Dart exception). Removes the marker.
  static void end([String result = 'finished normally']) {
    if (_dir == null) return;
    try {
      note('end: $result');
      _active = false;
      if (_marker.existsSync()) _marker.deleteSync();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // REPORT
  // ---------------------------------------------------------------------------
  static const Set<int> _alwaysShow = {4, 5, 7, 12}; // CRASH, CRASH_NATIVE, INIT_FAILURE, DEPENDENCY_DIED
  static const Set<int> _showIfBusy = {2, 3, 6, 9}; // SIGNALED, LOW_MEMORY, ANR, EXCESSIVE_RESOURCE_USAGE

  static Future<void> _buildPendingReport() async {
    final bool interrupted = _marker.existsSync();
    String interruptedOp = '';
    String trailText = '';
    if (interrupted) {
      try {
        interruptedOp = _marker.readAsStringSync();
      } catch (_) {}
      try {
        trailText = _trail.existsSync() ? _trail.readAsStringSync() : '';
      } catch (_) {}
      try {
        _marker.deleteSync();
      } catch (_) {}
    }

    int lastSeen = 0;
    try {
      if (_seen.existsSync()) lastSeen = int.tryParse(_seen.readAsStringSync().trim()) ?? 0;
    } catch (_) {}

    List<Map<String, Object?>> exits = [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getExitReasons');
      for (final r in raw ?? const <dynamic>[]) {
        if (r is Map) exits.add(r.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (_) {}

    final fresh = exits.where((e) => ((e['timestamp'] as num?) ?? 0).toInt() > lastSeen).toList();
    int newest = lastSeen;
    for (final e in fresh) {
      final t = ((e['timestamp'] as num?) ?? 0).toInt();
      if (t > newest) newest = t;
    }
    try {
      _seen.writeAsStringSync('$newest', flush: true);
    } catch (_) {}

    bool worthShowing = interrupted;
    for (final e in fresh) {
      final reason = ((e['reason'] as num?) ?? -1).toInt();
      final importance = ((e['importance'] as num?) ?? 1000).toInt();
      if (_alwaysShow.contains(reason)) worthShowing = true;
      if (_showIfBusy.contains(reason) && (interrupted || importance <= 200)) worthShowing = true;
    }
    if (!worthShowing) return;

    final b = StringBuffer()
      ..writeln('SHADERLY CRASH REPORT')
      ..writeln('shown: ${DateTime.now().toIso8601String()}')
      ..writeln();

    if (interrupted) {
      b.writeln('The app stopped in the middle of: $interruptedOp');
    } else {
      b.writeln('Android reports the app was closed unexpectedly (no export was running).');
    }
    b.writeln();

    if (fresh.isNotEmpty) {
      b.writeln('--- How Android says the process ended ---');
      for (final e in fresh) {
        final ts = DateTime.fromMillisecondsSinceEpoch(((e['timestamp'] as num?) ?? 0).toInt());
        b.writeln('${e['reasonName']} (${e['reason']})  at $ts');
        b.writeln('  status/signal: ${e['status']}   importance: ${e['importance']}');
        b.writeln('  memory at death: pss=${_mb(e['pssKb'])}MB  rss=${_mb(e['rssKb'])}MB');
        final desc = (e['description'] ?? '').toString();
        if (desc.isNotEmpty) b.writeln('  description: $desc');
        final trace = (e['trace'] ?? '').toString();
        if (trace.isNotEmpty) {
          b.writeln('  native crash strings (signal / libraries / functions):');
          for (final line in trace.split('\n').take(70)) {
            b.writeln('    $line');
          }
        }
      }
      b.writeln();
      b.writeln('Hints: status 11 = SIGSEGV (bad memory access), 6 = SIGABRT (assert / abort),');
      b.writeln('       9 = SIGKILL (killed - usually out of memory). LOW_MEMORY or a high rss near the end');
      b.writeln('       of the steps below means the phone ran out of RAM.');
      b.writeln();
    }

    if (trailText.isNotEmpty) {
      final lines = trailText.split('\n');
      b.writeln('--- Last steps before it stopped ---');
      final header = lines.take(14).toList();
      final tail = lines.length > 60 ? lines.sublist(lines.length - 45) : lines.skip(14).toList();
      for (final l in header) {
        b.writeln(l);
      }
      if (lines.length > 60) b.writeln('   ... (${lines.length - 59} lines skipped) ...');
      for (final l in tail) {
        b.writeln(l);
      }
    }

    pendingReport = b.toString();
    try {
      _lastReportFile.writeAsStringSync(pendingReport!, flush: true);
    } catch (_) {}
  }

  static String _mb(Object? kb) => (((kb as num?) ?? 0) / 1024).round().toString();

  // ---------------------------------------------------------------------------
  // DIALOG
  // ---------------------------------------------------------------------------
  static Future<void> showPendingReport() async {
    final report = pendingReport;
    if (report == null) return;
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) {
      // Navigator not ready yet: try again shortly.
      Future<void>.delayed(const Duration(milliseconds: 500), showPendingReport);
      return;
    }
    pendingReport = null;

    await showDialog<void>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: kCardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bug_report_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Shaderly closed unexpectedly',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(dCtx).size.height * 0.55,
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                height: 1.35,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (dCtx.mounted) {
                ScaffoldMessenger.of(dCtx).showSnackBar(
                  const SnackBar(content: Text('Report copied'), duration: Duration(seconds: 1)),
                );
              }
            },
            child: const Text('Copy', style: TextStyle(color: kCyanAccent, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
