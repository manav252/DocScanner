// Draws markup items onto a canvas of the page's size. One painter for the
// editor, the page viewer and the flattened export, so they always match.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../imaging/geometry.dart';
import '../../imaging/markup.dart';

/// Font family bundled with the app (works offline on the web too).
const markupFontFamily = 'NotoSans';

double unitOf(Size s) => math.min(s.width, s.height);

TextPainter layoutText(TextMarkup t, Size page) {
  final unit = unitOf(page);
  return TextPainter(
    text: TextSpan(
      text: t.text.isEmpty ? ' ' : t.text,
      style: TextStyle(
        fontFamily: markupFontFamily,
        fontFamilyFallback: const ['NotoSansDevanagari'],
        fontSize: math.max(1, t.size * unit),
        fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
        color: Color(t.color),
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: math.max(4, t.width * unit));
}

/// Bounds of any item; text is measured so the box hugs the words.
({double l, double t, double r, double b}) markupBounds(MarkupItem item, Size page) {
  final aspect = page.width / page.height;
  if (item is! TextMarkup) return item.bounds(aspect: aspect);
  final tp = layoutText(item, page), unit = unitOf(page);
  final pad = item.background == TextBackground.white ? item.size * 0.4 : 0.0;
  return item.bounds(aspect: aspect, textHeight: tp.height / unit + pad, textWidth: tp.width / unit + pad);
}

void paintMarkup(Canvas canvas, Size page, List<MarkupItem> items) {
  final unit = unitOf(page);
  Offset px(Pt p) => Offset(p.x * page.width, p.y * page.height);
  for (final item in items) {
    switch (item) {
      case TextMarkup t:
        final tp = layoutText(t, page);
        canvas.save();
        canvas.translate(t.x * page.width, t.y * page.height);
        canvas.rotate(t.rotation);
        // Centred on (x, y); lines wrap at the box width.
        final box = Rect.fromCenter(center: Offset.zero, width: tp.width, height: tp.height);
        if (t.background == TextBackground.white) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(box.inflate(t.size * unit * 0.2), Radius.circular(t.size * unit * 0.15)),
            Paint()..color = Colors.white,
          );
        }
        tp.paint(canvas, box.topLeft);
        canvas.restore();
      case StrokeMarkup s when s.points.isNotEmpty:
        final paint = Paint()
          ..color = s.highlighter ? Color(s.color).withValues(alpha: 0.38) : Color(s.color)
          ..style = PaintingStyle.stroke
          ..strokeCap = s.highlighter ? StrokeCap.square : StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = math.max(1, s.width * unit)
          ..blendMode = s.highlighter ? BlendMode.multiply : BlendMode.srcOver;
        if (s.points.length == 1) {
          canvas.drawPoints(ui.PointMode.points, [px(s.points.first)], paint);
        } else {
          final path = Path()..moveTo(px(s.points.first).dx, px(s.points.first).dy);
          for (final p in s.points.skip(1)) {
            path.lineTo(px(p).dx, px(p).dy);
          }
          canvas.drawPath(path, paint);
        }
      case ShapeMarkup sh:
        final a = px(sh.a), b = px(sh.b);
        final stroke = Paint()
          ..color = Color(sh.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, sh.width * unit)
          ..strokeCap = StrokeCap.round;
        switch (sh.kind) {
          case MarkupKind.whiteout:
            canvas.drawRect(Rect.fromPoints(a, b), Paint()..color = Colors.white);
          case MarkupKind.rect:
            canvas.drawRect(Rect.fromPoints(a, b), stroke);
          case MarkupKind.line:
            canvas.drawLine(a, b, stroke);
          case MarkupKind.arrow:
            canvas.drawLine(a, b, stroke);
            final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
            final head = math.max(10.0, stroke.strokeWidth * 4);
            for (final da in [math.pi * 0.85, -math.pi * 0.85]) {
              canvas.drawLine(b, b + Offset(math.cos(angle + da), math.sin(angle + da)) * head, stroke);
            }
          default:
            break;
        }
      case SignatureMarkup sig:
        canvas.save();
        canvas.translate(sig.x * page.width, sig.y * page.height);
        canvas.rotate(sig.rotation);
        final w = sig.width * unit, h = sig.height * unit;
        final paint = Paint()
          ..color = Color(sig.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, h * 0.035)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final s in sig.strokes) {
          if (s.isEmpty) continue;
          final path = Path()..moveTo(-w / 2 + s.first.x * w, -h / 2 + s.first.y * h);
          for (final p in s.skip(1)) {
            path.lineTo(-w / 2 + p.x * w, -h / 2 + p.y * h);
          }
          canvas.drawPath(path, paint);
        }
        canvas.restore();
      default:
        break;
    }
  }
}

class MarkupPainter extends CustomPainter {
  MarkupPainter(this.items);
  final List<MarkupItem> items;

  @override
  void paint(Canvas canvas, Size size) => paintMarkup(canvas, size, items);

  @override
  bool shouldRepaint(MarkupPainter old) => old.items != items;
}

/// Burn [items] into an encoded page image. Returns PNG bytes of the same size.
Future<Uint8List> flattenMarkup(Uint8List encoded, List<MarkupItem> items) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final image = (await codec.getNextFrame()).image;
  final size = Size(image.width.toDouble(), image.height.toDouble());
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Offset.zero & size);
  canvas.drawImage(image, Offset.zero, Paint());
  paintMarkup(canvas, size, items);
  final out = await rec.endRecording().toImage(image.width, image.height);
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  out.dispose();
  codec.dispose();
  return png!.buffer.asUint8List();
}
