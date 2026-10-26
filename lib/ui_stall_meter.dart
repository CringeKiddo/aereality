// =============================================================================
// AEReality / Shaderly - UiStallMeter (benchmark helper, debug use)
//
// A 16 ms periodic timer on the UI isolate. If the isolate is blocked (blocking FFI call, heavy decode, huge rebuild)
// the timer fires late; the gap between ticks is the stall. It measures exactly what the user feels as "the button took
// 10 seconds": the longest time the UI isolate could not react.
//
// Usage:  UiStallMeter.start();   ... do the test ...   debugPrint(UiStallMeter.reportAndReset());
// =============================================================================

import 'dart:async';

class UiStallMeter {
  static Timer? _timer;
  static int _last = 0;
  static int _worstMs = 0;
  static int _ticks = 0;
  static int _over50 = 0;
  static int _over250 = 0;
  static int _over1000 = 0;
  static int _over5000 = 0;

  static void start() {
    if (_timer != null) return;
    _last = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_last != 0) {
        final gap = now - _last;
        _ticks++;
        if (gap > _worstMs) _worstMs = gap;
        if (gap > 50) _over50++;
        if (gap > 250) _over250++;
        if (gap > 1000) _over1000++;
        if (gap > 5000) _over5000++; // 5 s is where Android's "not responding" dialog becomes possible
      }
      _last = now;
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static String reportAndReset() {
    final s = 'UI stall: worst ${_worstMs} ms | gaps >50ms: $_over50, >250ms: $_over250, >1s: $_over1000, '
        '>5s: $_over5000 (of $_ticks ticks)';
    _worstMs = 0;
    _ticks = 0;
    _over50 = 0;
    _over250 = 0;
    _over1000 = 0;
    _over5000 = 0;
    _last = 0;
    return s;
  }
}
