// Shows a photo with 4 draggable corner handles (+ 4 edge handles that move a
// whole side) and a magnifier loupe over the handle being dragged.
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../imaging/geometry.dart';

/// Whether [corners] (TL, TR, BR, BL in handle order) form a usable page outline.
bool isValidQuad(List<Pt> corners, Size imageSize) =>
    isConvex(corners) && polygonArea(corners) >= 0.01 * imageSize.width * imageSize.height;

class CornerEditor extends StatefulWidget {
  const CornerEditor({
    super.key,
    required this.image,
    required this.imageSize,
    required this.corners,
    required this.onChanged,
  });

  final ImageProvider image;
  final Size imageSize;

  /// TL, TR, BR, BL in image pixels.
  final List<Pt> corners;
  final ValueChanged<List<Pt>> onChanged;

  @override
  State<CornerEditor> createState() => CornerEditorState();
}

@visibleForTesting
class CornerEditorState extends State<CornerEditor> {
  static const hitRadius = 36.0;
  static const loupeSize = 116.0;
  static const loupeGap = 84.0;

  /// 0-3 = corner, 4-7 = midpoint of side (i-4, i-3).
  int? activeHandle;
  Rect _imageRect = Rect.zero;

  /// Handle position minus finger position at touch-down, so the handle keeps
  /// its offset from the finger (and follows it exactly, slop included).
  Offset _grab = Offset.zero;

  double get _scale => _imageRect.width / widget.imageSize.width;

  Offset _toScreen(Pt p) => _imageRect.topLeft + Offset(p.x, p.y) * _scale;

  List<Offset> _handles() {
    final c = [for (final p in widget.corners) _toScreen(p)];
    return [...c, for (var i = 0; i < 4; i++) (c[i] + c[(i + 1) % 4]) / 2];
  }

  /// Screen position the loupe magnifies (the corner, or the side's midpoint).
  Offset? get _focus => activeHandle == null ? null : _handles()[activeHandle!];

  void _onPanStart(DragStartDetails d) {
    final hs = _handles();
    int? best;
    var bestDist = hitRadius;
    for (var i = 0; i < hs.length; i++) {
      // Corners win ties over midpoints.
      final dist = (hs[i] - d.localPosition).distance - (i < 4 ? 6 : 0);
      if (dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    if (best != null) {
      HapticFeedback.selectionClick();
      _grab = hs[best] - d.localPosition;
      setState(() => activeHandle = best);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final h = activeHandle;
    if (h == null) return;
    final delta = (d.localPosition + _grab - _handles()[h]) / _scale;
    final w = widget.imageSize.width - 1, ht = widget.imageSize.height - 1;
    Pt move(Pt p) => Pt((p.x + delta.dx).clamp(0, w).toDouble(), (p.y + delta.dy).clamp(0, ht).toDouble());
    final next = [...widget.corners];
    if (h < 4) {
      next[h] = move(next[h]);
    } else {
      final i = h - 4;
      next[i] = move(next[i]);
      next[(i + 1) % 4] = move(next[(i + 1) % 4]);
    }
    widget.onChanged(next);
  }

  void _onPanEnd([Object? _]) => setState(() => activeHandle = null);

  @override
  Widget build(BuildContext context) {
    final valid = isValidQuad(widget.corners, widget.imageSize);
    final color = valid ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error;
    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
      final fitted = applyBoxFit(BoxFit.contain, widget.imageSize, box).destination;
      _imageRect = Alignment.center.inscribe(fitted, Offset.zero & box);
      final focus = _focus;
      Offset? loupeCenter;
      if (focus != null) {
        // Above the finger; flip below when too close to the top edge.
        final above = focus.dy - loupeGap - loupeSize / 2 >= 0;
        loupeCenter = Offset(
          focus.dx.clamp(loupeSize / 2, box.width - loupeSize / 2),
          above ? focus.dy - loupeGap : focus.dy + loupeGap,
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Pick the handle under the finger-down point, not where the drag slop ended.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanEnd,
        child: Stack(children: [
          Positioned.fromRect(rect: _imageRect, child: Image(image: widget.image, fit: BoxFit.fill, gaplessPlayback: true)),
          Positioned.fill(
            child: CustomPaint(
              painter: _EditorPainter(_handles(), color: color, active: activeHandle),
            ),
          ),
          if (loupeCenter != null)
            Positioned(
              key: const ValueKey('loupe'),
              left: loupeCenter.dx - loupeSize / 2,
              top: loupeCenter.dy - loupeSize / 2,
              child: RawMagnifier(
                size: const Size.square(loupeSize),
                magnificationScale: 2.5,
                focalPointOffset: focus! - loupeCenter,
                decoration: const MagnifierDecoration(
                  shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                  shadows: [BoxShadow(color: Colors.black54, blurRadius: 8)],
                ),
                child: CustomPaint(painter: _CrosshairPainter(color)),
              ),
            ),
        ]),
      );
    });
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter(this.handles, {required this.color, this.active});
  final List<Offset> handles;
  final Color color;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    final corners = handles.sublist(0, 4);
    final quad = Path()..addPolygon(corners, true);
    // Dim everything outside the page.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPolygon(corners, true),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawPath(quad, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    for (var i = 0; i < handles.length; i++) {
      final isCorner = i < 4, isActive = i == active;
      final r = isCorner ? (isActive ? 14.0 : 11.0) : (isActive ? 9.0 : 7.0);
      canvas.drawCircle(handles[i], r + 2, Paint()..color = Colors.white);
      canvas.drawCircle(handles[i], r, Paint()..color = isActive ? Colors.white : color.withValues(alpha: isCorner ? 0.9 : 0.6));
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) => true;
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const arm = 10.0;
    canvas.drawLine(c - const Offset(arm, 0), c + const Offset(arm, 0), p);
    canvas.drawLine(c - const Offset(0, arm), c + const Offset(0, arm), p);
    canvas.drawCircle(c, math.max(2, arm / 3), p..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.color != color;
}
