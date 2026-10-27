// Frame-to-frame corner smoothing and steadiness tracking for the live preview
// (port of scanner_core/smoothing.py). Works in normalised [0, 1] coordinates
// so it is independent of the analysis resolution.
import 'dart:collection';
import 'dart:math' as math;

import 'geometry.dart';

class CornerSmoother {
  CornerSmoother({this.alpha = 0.4, this.jumpThreshold = 0.08, this.holdFrames = 4});

  /// EMA weight of the newest frame (higher = more responsive, more jitter).
  final double alpha;

  /// If any corner moves more than this (fraction of the frame diagonal) the
  /// page was moved, so snap to the new position instead of easing.
  final double jumpThreshold;

  /// Keep showing the last outline for this many missed frames.
  final int holdFrames;

  List<Pt>? _state;
  int _missed = 0;

  void reset() {
    _state = null;
    _missed = 0;
  }

  /// [corners] normalised TL, TR, BR, BL, or null when nothing was detected.
  List<Pt>? update(List<Pt>? corners) {
    if (corners == null) {
      _missed++;
      if (_missed > holdFrames) _state = null;
      return _state;
    }
    _missed = 0;
    final s = _state;
    var maxMove = 0.0;
    if (s != null) {
      for (var i = 0; i < 4; i++) {
        maxMove = math.max(maxMove, corners[i].distanceTo(s[i]));
      }
    }
    if (s == null || maxMove > jumpThreshold * math.sqrt2) {
      _state = List.unmodifiable(corners);
    } else {
      _state = List.unmodifiable([for (var i = 0; i < 4; i++) corners[i] * alpha + s[i] * (1 - alpha)]);
    }
    return _state;
  }
}

class StabilityTracker {
  /// Steady when the last [window] detections all lie within [tolerance]
  /// (fraction of the frame diagonal) of their mean. At 10 fps, 8 frames ~ 0.8 s.
  /// Up to [allowedMisses] frames in a row without a page (the detector missing
  /// one frame of a hand-held page) do not restart the count.
  StabilityTracker({this.window = 8, this.tolerance = 0.012, this.allowedMisses = 2});

  final int window;
  final double tolerance;
  final int allowedMisses;
  final _buf = Queue<List<Pt>>();
  int _misses = 0;

  void reset() {
    _buf.clear();
    _misses = 0;
  }

  bool update(List<Pt>? corners) {
    if (corners == null) {
      if (++_misses > allowedMisses) _buf.clear();
      return false;
    }
    _misses = 0;
    _buf.addLast(corners);
    while (_buf.length > window) {
      _buf.removeFirst();
    }
    return isSteady;
  }

  double _spread() {
    var worst = 0.0;
    for (var i = 0; i < 4; i++) {
      var mx = 0.0, my = 0.0;
      for (final c in _buf) {
        mx += c[i].x;
        my += c[i].y;
      }
      final mean = Pt(mx / _buf.length, my / _buf.length);
      for (final c in _buf) {
        worst = math.max(worst, c[i].distanceTo(mean));
      }
    }
    return worst;
  }

  bool get _withinTolerance => _buf.isNotEmpty && _spread() <= tolerance * math.sqrt2;

  bool get isSteady => _buf.length == window && _withinTolerance;

  /// 0..1, for drawing a "hold still" ring in the UI.
  double get progress => _withinTolerance ? _buf.length / window : 0.0;
}
