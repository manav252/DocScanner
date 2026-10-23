import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Round shutter button with a ring that fills while the page is held steady.
class ShutterButton extends StatelessWidget {
  const ShutterButton({
    super.key,
    required this.onPressed,
    required this.progress,
    this.busy = false,
    this.label = 'Capture',
  });

  final VoidCallback? onPressed;
  final double progress;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // InkWell: reachable with Tab and Enter/Space, with a visible focus ring.
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('shutter'),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        focusColor: scheme.primary.withValues(alpha: 0.5),
        child: SizedBox.square(
          dimension: 78,
          child: CustomPaint(
            painter: _RingPainter(progress, scheme.primary),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: busy ? 48 : 60,
                height: busy ? 48 : 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: onPressed == null ? Colors.white38 : Colors.white,
                ),
                child: busy
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 3))
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(
      rect.center,
      size.width / 2 - 2,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect.deflate(2),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}
