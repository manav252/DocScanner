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
  /// Steady when [window] detections (or at least [minFrames] spanning
  /// [minDuration], whichever comes first) lie within [tolerance] (fraction of
  /// the frame diagonal) of their mean. A hand-held phone's outline wobbles a
  /// little and the detector now and then returns a wrong outline for one
  /// frame: up to [allowedOutliers] such frames per count are ignored (more
  /// means the page is moving), and up to
  /// [allowedMisses] frames without a page do not restart the count. Slow
  /// drift drops the oldest frames instead of restarting.
  StabilityTracker({
    this.window = 8,
    this.tolerance = 0.025,
    this.allowedMisses = 2,
    this.allowedOutliers = 2,
    this.minFrames = 4,
    this.minDuration = const Duration(milliseconds: 900),
  });

  final int window;
  final double tolerance;
  final int allowedMisses;
  final int allowedOutliers;
  final int minFrames;
  final Duration minDuration;
  final _buf = Queue<(List<Pt>, Duration?)>();
  int _misses = 0;
  int _outliers = 0;

  void reset() {
    _buf.clear();
    _misses = 0;
    _outliers = 0;
  }

  /// [at]: the frame's time, so a slow phone (few frames a second) is steady
  /// after [minDuration] rather than after [window] frames.
  bool update(List<Pt>? corners, {Duration? at}) {
    if (corners == null) {
      if (++_misses > allowedMisses) reset();
      return false;
    }
    _misses = 0;
    if (_buf.isNotEmpty && _distance(corners, _mean()) > _limit) {
      if (++_outliers > allowedOutliers) {
        _buf.clear(); // the page (or the phone) really moved
        _outliers = 0;
      } else {
        return false;
      }
    }
    _buf.addLast((corners, at));
    while (_buf.length > window) {
      _buf.removeFirst();
    }
    // Slow drift: drop old frames that no longer agree with the mean.
    while (_buf.length > 1 && _distance(_buf.first.$1, _mean()) > _limit) {
      _buf.removeFirst();
    }
    return isSteady;
  }

  double get _limit => tolerance * math.sqrt2;

  List<Pt> _mean() {
    return [
      for (var i = 0; i < 4; i++)
        Pt(
          _buf.fold(0.0, (s, c) => s + c.$1[i].x) / _buf.length,
          _buf.fold(0.0, (s, c) => s + c.$1[i].y) / _buf.length,
        ),
    ];
  }

  static double _distance(List<Pt> a, List<Pt> b) {
    var worst = 0.0;
    for (var i = 0; i < 4; i++) {
      worst = math.max(worst, a[i].distanceTo(b[i]));
    }
    return worst;
  }

  Duration get _span {
    final first = _buf.isEmpty ? null : _buf.first.$2;
    final last = _buf.isEmpty ? null : _buf.last.$2;
    return first == null || last == null ? Duration.zero : last - first;
  }

  bool get isSteady => _buf.length >= window || (_buf.length >= minFrames && _span >= minDuration);

  /// 0..1, for drawing a "hold still" ring in the UI.
  double get progress {
    if (_buf.isEmpty) return 0;
    if (isSteady) return 1;
    final byTime = _span.inMicroseconds / minDuration.inMicroseconds;
    return math.min(1.0, math.max(_buf.length / window, math.min(byTime, (_buf.length) / minFrames)));
  }
}
