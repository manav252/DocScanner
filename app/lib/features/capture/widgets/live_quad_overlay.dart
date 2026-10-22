import 'package:flutter/material.dart';

import '../../../imaging/geometry.dart';

/// Draws the live page outline (normalised corners) over the camera preview.
class LiveQuadOverlay extends StatelessWidget {
  const LiveQuadOverlay({super.key, required this.corners, required this.progress, required this.color});

  final List<Pt>? corners;

  /// 0..1 steadiness; the outline thickens and the fill deepens as it fills up.
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _LiveQuadPainter(corners, progress, color),
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
