// Draw a signature once; it is saved on this device and reused on any page.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../imaging/geometry.dart';

const _key = 'app/signature.json';

/// A saved signature: strokes normalised to its box, and the box's width/height ratio.
typedef SavedSignature = ({List<List<Pt>> strokes, double aspect});

final savedSignatureProvider = FutureProvider<SavedSignature?>((ref) async {
  final b = await ref.watch(keyValueStoreProvider).get(_key);
  if (b == null) return null;
  final j = jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
  return (
    strokes: [
      for (final s in j['strokes'] as List)
        [
          for (var i = 0; i + 1 < (s as List).length; i += 2)
            Pt((s[i] as num).toDouble(), (s[i + 1] as num).toDouble()),
        ],
    ],
    aspect: (j['aspect'] as num).toDouble(),
  );
});

Future<void> saveSignature(WidgetRef ref, SavedSignature sig) async {
  await ref
      .read(keyValueStoreProvider)
      .put(
        _key,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'aspect': sig.aspect,
              'strokes': [
                for (final s in sig.strokes)
                  [
                    for (final p in s) ...[p.x, p.y],
                  ],
              ],
            }),
          ),
        ),
      );
  ref.invalidate(savedSignatureProvider);
}

/// Opens the signature pad; returns the new signature (already saved) or null.
Future<SavedSignature?> drawSignature(BuildContext context, WidgetRef ref) async {
  final sig = await showDialog<SavedSignature>(context: context, builder: (_) => const _SignaturePad());
  if (sig != null) await saveSignature(ref, sig);
  return sig;
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad();

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  static const aspect = 3.0;
  final _strokes = <List<Pt>>[];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l.drawSignature),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.signatureHint),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: aspect,
              child: LayoutBuilder(
                builder: (context, c) {
                  Pt norm(Offset o) =>
                      Pt((o.dx / c.maxWidth).clamp(0, 1).toDouble(), (o.dy / c.maxHeight).clamp(0, 1).toDouble());
                  return Semantics(
                    label: l.drawSignature,
                    child: GestureDetector(
                      key: const ValueKey('signature-pad'),
                      onPanStart: (d) => setState(() => _strokes.add([norm(d.localPosition)])),
                      onPanUpdate: (d) => setState(() => _strokes.last.add(norm(d.localPosition))),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: scheme.outline, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: CustomPaint(painter: _PadPainter(_strokes), size: Size.infinite),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
          icon: const Icon(Icons.layers_clear_outlined),
          label: Text(l.clear),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          label: Text(l.cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('save-signature'),
          onPressed: _strokes.isEmpty
              ? null
              : () => Navigator.of(context).pop((strokes: _trimmed(), aspect: _trimmedAspect())),
          icon: const Icon(Icons.check),
          label: Text(l.save),
        ),
      ],
    );
  }

  // Fit the strokes' bounding box (with a small margin) so the signature fills its box.
  ({double l, double t, double r, double b}) get _bounds {
    final pts = [for (final s in _strokes) ...s];
    double minX = 1, minY = 1, maxX = 0, maxY = 0;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    const m = 0.02;
    return (l: (minX - m).clamp(0, 1), t: (minY - m).clamp(0, 1), r: (maxX + m).clamp(0, 1), b: (maxY + m).clamp(0, 1));
  }

  List<List<Pt>> _trimmed() {
    final b = _bounds;
    final w = (b.r - b.l).clamp(1e-3, 1.0), h = (b.b - b.t).clamp(1e-3, 1.0);
    return [
      for (final s in _strokes) [for (final p in s) Pt((p.x - b.l) / w, (p.y - b.t) / h)],
    ];
  }

  double _trimmedAspect() {
    final b = _bounds;
    return ((b.r - b.l) * aspect / (b.b - b.t).clamp(1e-3, 1.0)).clamp(0.5, 8.0);
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);
  final List<List<Pt>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A4FD6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(s.first.x * size.width, s.first.y * size.height);
      for (final p in s.skip(1)) {
        path.lineTo(p.x * size.width, p.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
