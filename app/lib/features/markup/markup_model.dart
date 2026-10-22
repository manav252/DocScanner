// Undo/redo history and hit testing for the markup editor (no UI).
import 'dart:math' as math;
import 'dart:ui' show Size;

import '../../imaging/geometry.dart';
import '../../imaging/markup.dart';
import 'markup_painter.dart';

class MarkupHistory {
  MarkupHistory(List<MarkupItem> initial) : _items = List.unmodifiable(initial);

  List<MarkupItem> _items;
  final _undo = <List<MarkupItem>>[];
  final _redo = <List<MarkupItem>>[];

  List<MarkupItem> get items => _items;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Any change since opening (undoing everything counts as unchanged).
  bool get dirty => _undo.isNotEmpty;

  /// Make [next] the current state as one undoable step.
  void commit(List<MarkupItem> next) {
    _undo.add(_items);
    _items = List.unmodifiable(next);
    _redo.clear();
  }

  /// Show [next] without recording a step (live dragging); finish with [commitFrom].
  void preview(List<MarkupItem> next) => _items = List.unmodifiable(next);

  /// Record a step from [before] (captured when the gesture started) to now.
  void commitFrom(List<MarkupItem> before) {
    if (identical(before, _items)) return;
    _undo.add(before);
    _redo.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_items);
    _items = _undo.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_items);
    _items = _redo.removeLast();
  }

  List<MarkupItem> replace(String id, MarkupItem Function(MarkupItem) f) => [
    for (final i in _items) i.id == id ? f(i) : i,
  ];
  List<MarkupItem> without(String id) => [
    for (final i in _items)
      if (i.id != id) i,
  ];
}

double _distToSegment(Pt p, Pt a, Pt b) {
  final ab = b - a;
  final t = ((p - a).dot(ab) / (ab.dot(ab) + 1e-12)).clamp(0.0, 1.0);
  return p.distanceTo(a + ab * t);
}

/// Topmost item under [p] (normalised page coordinates). [tolerance] is in
/// normalised units; [page] is the displayed page size in pixels.
MarkupItem? hitTestMarkup(List<MarkupItem> items, Pt p, Size page, {double tolerance = 0.02}) {
  for (final item in items.reversed) {
    switch (item) {
      case StrokeMarkup s:
        final tol = math.max(tolerance, s.width * unitOf(page) / page.width);
        if (s.points.length == 1 && s.points.first.distanceTo(p) <= tol) return s;
        for (var i = 1; i < s.points.length; i++) {
          if (_distToSegment(p, s.points[i - 1], s.points[i]) <= tol) return s;
        }
      case ShapeMarkup sh when sh.kind == MarkupKind.line || sh.kind == MarkupKind.arrow:
        if (_distToSegment(p, sh.a, sh.b) <= tolerance) return sh;
      default:
        final b = markupBounds(item, page);
        if (p.x >= b.l - tolerance && p.x <= b.r + tolerance && p.y >= b.t - tolerance && p.y <= b.b + tolerance) {
          return item;
        }
    }
  }
  return null;
}

/// Stroke items the eraser at [p] touches.
Iterable<String> eraseAt(List<MarkupItem> items, Pt p, Size page, {double radius = 0.025}) sync* {
  for (final item in items) {
    if (item is StrokeMarkup && hitTestMarkup([item], p, page, tolerance: radius) != null) yield item.id;
  }
}
