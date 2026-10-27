import 'package:flutter/material.dart';

import '../../../imaging/geometry.dart';

/// Draws the live page outline (normalised corners) over the camera preview.
///
/// The page is found about 10 times a second; between two detections the
/// outline glides to the new corners so it moves smoothly instead of jumping.
class LiveQuadOverlay extends StatefulWidget {
  const LiveQuadOverlay({super.key, required this.corners, required this.progress, required this.color});

  final List<Pt>? corners;

  /// 0..1 steadiness; the outline thickens and the fill deepens as it fills up.
  final double progress;
  final Color color;

  @override
  State<LiveQuadOverlay> createState() => _LiveQuadOverlayState();
}

class _LiveQuadOverlayState extends State<LiveQuadOverlay> with SingleTickerProviderStateMixin {
  late final _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
  List<Pt>? _from;

  @override
  void didUpdateWidget(LiveQuadOverlay old) {
    super.didUpdateWidget(old);
    if (old.corners != widget.corners) {
      // Start from where the outline is drawn now; appear/disappear at once.
      _from = old.corners == null || widget.corners == null
          ? null
          : _at(old.corners!, Curves.easeOut.transform(_glide.value));
      _glide.forward(from: 0);
    }
  }

  List<Pt> _at(List<Pt> target, double t) {
    final from = _from;
    if (from == null || t >= 1) return target;
    return [
      for (var i = 0; i < 4; i++)
        Pt(from[i].x + (target[i].x - from[i].x) * t, from[i].y + (target[i].y - from[i].y) * t),
    ];
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _glide,
        builder: (context, _) {
          final c = widget.corners;
          final shown = c == null ? null : _at(c, Curves.easeOut.transform(_glide.value));
          return CustomPaint(size: Size.infinite, painter: _LiveQuadPainter(shown, widget.progress, widget.color));
        },
      ),
    ),
  );
}

class _LiveQuadPainter extends CustomPainter {
  _LiveQuadPainter(this.corners, this.progress, this.color);
  final List<Pt>? corners;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = corners;
    if (c == null) return;
    final pts = [for (final p in c) Offset(p.x * size.width, p.y * size.height)];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.15 + 0.2 * progress));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3 + 2 * progress,
    );
    for (final p in pts) {
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LiveQuadPainter old) => old.corners != corners || old.progress != progress || old.color != color;
}
