// Rectangular crop of the flattened (and rotated) page. Pops with a CropRect.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../imaging/page_edits.dart';

/// The page with its filter and rotation but no crop, for the crop editor.
final uncroppedPreviewProvider = FutureProvider.autoDispose.family<Uint8List, ScanPage>((ref, page) async {
  final flat = await ref.watch(documentRepositoryProvider).pageImage(page.id, PageImage.flat);
  if (flat == null) throw StateError('missing page image');
  return ref.watch(scanEngineProvider).processEncoded(flat, page.edits.copyWith(crop: CropRect.full), maxSide: 1600);
});

class CropPage extends ConsumerStatefulWidget {
  const CropPage({super.key, required this.page});
  final ScanPage page;

  @override
  ConsumerState<CropPage> createState() => _CropPageState();
}

class _CropPageState extends ConsumerState<CropPage> {
  late CropRect _crop = widget.page.edits.crop;

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(uncroppedPreviewProvider(widget.page));
    // Aspect of the rotated, uncropped page.
    final turned = widget.page.edits.quarterTurns.isOdd;
    final w = (widget.page.renderWidth / widget.page.edits.crop.width).round();
    final h = (widget.page.renderHeight / widget.page.edits.crop.height).round();
    final size = w > 0 && h > 0 ? Size(w.toDouble(), h.toDouble()) : (turned ? const Size(4, 3) : const Size(3, 4));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Crop')),
      body: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (preview) {
              AsyncData(:final value) => CropEditor(
                  image: MemoryImage(value),
                  imageSize: size,
                  crop: _crop,
                  onChanged: (c) => setState(() => _crop = c),
                ),
              AsyncError(:final error) => Center(child: Text('$error', style: const TextStyle(color: Colors.white))),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => setState(() => _crop = CropRect.full),
                child: const Text('Reset'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('apply-crop'),
                onPressed: () => Navigator.of(context).pop(_crop),
                icon: const Icon(Icons.check),
                label: const Text('Apply'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Axis-aligned crop box over an image: drag corners, edges, or the inside to move it.
class CropEditor extends StatefulWidget {
  const CropEditor({super.key, required this.image, required this.imageSize, required this.crop, required this.onChanged});
  final ImageProvider image;
  final Size imageSize;
  final CropRect crop;
  final ValueChanged<CropRect> onChanged;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

enum _Grip { tl, tr, br, bl, top, right, bottom, left, move }

class _CropEditorState extends State<CropEditor> {
  static const hit = 32.0;
  static const minSize = 0.05;
  Rect _imageRect = Rect.zero;
  _Grip? _grip;
  Offset _start = Offset.zero;
  CropRect _startCrop = CropRect.full;

  Rect get _cropRect => Rect.fromLTWH(
        _imageRect.left + widget.crop.left * _imageRect.width,
        _imageRect.top + widget.crop.top * _imageRect.height,
        widget.crop.width * _imageRect.width,
        widget.crop.height * _imageRect.height,
      );

  _Grip? _gripAt(Offset p) {
    final r = _cropRect;
    final points = {
      _Grip.tl: r.topLeft,
      _Grip.tr: r.topRight,
      _Grip.br: r.bottomRight,
      _Grip.bl: r.bottomLeft,
      _Grip.top: r.topCenter,
      _Grip.right: r.centerRight,
      _Grip.bottom: r.bottomCenter,
      _Grip.left: r.centerLeft,
    };
    _Grip? best;
    var bestD = hit;
    points.forEach((g, o) {
      final d = (o - p).distance;
      if (d < bestD) {
        best = g;
        bestD = d;
      }
    });
    return best ?? (r.contains(p) ? _Grip.move : null);
  }

  void _update(Offset p) {
    final g = _grip;
    if (g == null) return;
    final dx = (p.dx - _start.dx) / _imageRect.width, dy = (p.dy - _start.dy) / _imageRect.height;
    final c = _startCrop;
    var l = c.left, t = c.top, r = c.left + c.width, b = c.top + c.height;
    if (g == _Grip.move) {
      final mx = dx.clamp(-l, 1 - r), my = dy.clamp(-t, 1 - b);
      l += mx;
      r += mx;
      t += my;
      b += my;
    } else {
      if (g == _Grip.tl || g == _Grip.bl || g == _Grip.left) l = (l + dx).clamp(0.0, r - minSize);
      if (g == _Grip.tr || g == _Grip.br || g == _Grip.right) r = (r + dx).clamp(l + minSize, 1.0);
      if (g == _Grip.tl || g == _Grip.tr || g == _Grip.top) t = (t + dy).clamp(0.0, b - minSize);
      if (g == _Grip.bl || g == _Grip.br || g == _Grip.bottom) b = (b + dy).clamp(t + minSize, 1.0);
    }
    widget.onChanged(CropRect(l, t, math.max(minSize, r - l), math.max(minSize, b - t)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final box = constraints.biggest;
      final fitted = applyBoxFit(BoxFit.contain, widget.imageSize, box).destination;
      _imageRect = Alignment.center.inscribe(fitted, Offset.zero & box);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) {
          _grip = _gripAt(d.localPosition);
          _start = d.localPosition;
          _startCrop = widget.crop;
        },
        onPanUpdate: (d) => _update(d.localPosition),
        onPanEnd: (_) => _grip = null,
        child: Stack(children: [
          Positioned.fromRect(rect: _imageRect, child: Image(image: widget.image, fit: BoxFit.fill)),
          Positioned.fill(child: CustomPaint(painter: _CropPainter(_cropRect, Theme.of(context).colorScheme.primary))),
        ]),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect, this.color);
  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, line);
    // Rule-of-thirds guides.
    final thin = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(rect.left + rect.width * i / 3, rect.top), Offset(rect.left + rect.width * i / 3, rect.bottom), thin);
      canvas.drawLine(Offset(rect.left, rect.top + rect.height * i / 3), Offset(rect.right, rect.top + rect.height * i / 3), thin);
    }
    final grip = Paint()..color = color;
    for (final o in [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft]) {
      canvas.drawCircle(o, 9, Paint()..color = Colors.white);
      canvas.drawCircle(o, 7, grip);
    }
    for (final o in [rect.topCenter, rect.centerRight, rect.bottomCenter, rect.centerLeft]) {
      canvas.drawCircle(o, 6, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect || old.color != color;
}
