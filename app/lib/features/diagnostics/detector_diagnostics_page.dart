// Runs the platform ScanEngine (isolate on mobile, Web Worker on web)
// on bundled sample photos and draws the detected outline with timings.
// Proves the whole Dart -> OpenCV path works on the target device/browser.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../imaging/scan_engine.dart';
import '../../imaging/geometry.dart';

const samples = ['tilted_paper', 'low_contrast', 'cluttered_background', 'strong_perspective'];


typedef SampleResult = ({String name, Uint8List bytes, EncodedDetection result, double ms});

final diagnosticsProvider = FutureProvider<List<SampleResult>>((ref) async {
  final detector = ref.watch(scanEngineProvider);
  await detector.ready;
  final out = <SampleResult>[];
  for (final name in samples) {
    final bytes = (await rootBundle.load('assets/samples/$name.jpg')).buffer.asUint8List();
    final sw = Stopwatch()..start();
    final r = await detector.detectEncoded(bytes);
    out.add((name: name, bytes: bytes, result: r, ms: sw.elapsedMicroseconds / 1000));
  }
  return out;
});

class DetectorDiagnosticsPage extends ConsumerWidget {
  const DetectorDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(diagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detector diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Run again',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(diagnosticsProvider),
          ),
        ],
      ),
      body: results.when(
        loading: () => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading OpenCV…'),
            ])),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Detector failed: $e'))),
        data: (items) => GridView.extent(
          maxCrossAxisExtent: 320,
          childAspectRatio: 0.68,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [for (final s in items) _SampleTile(s)],
        ),
      ),
    );
  }
}

class _SampleTile extends StatelessWidget {
  const _SampleTile(this.s);
  final SampleResult s;

  @override
  Widget build(BuildContext context) {
    final d = s.result.detection;
    return Card(
      key: ValueKey('sample-${s.name}'),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: s.result.width / s.result.height,
            child: CustomPaint(
              foregroundPainter: QuadPainter(d.normalized(s.result.width, s.result.height), found: d.found),
              child: Image.memory(s.bytes, fit: BoxFit.fill),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${s.name}\n${d.found ? 'found' : 'not found'} · ${s.ms.toStringAsFixed(0)} ms (incl. decode)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}

/// Draws a detected quad given in normalised [0, 1] coordinates.
class QuadPainter extends CustomPainter {
  QuadPainter(this.corners, {required this.found});
  final List<Pt> corners;
  final bool found;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final p in corners) Offset(p.x * size.width, p.y * size.height)];
    final color = found ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill);
    canvas.drawPath(Path()..addPolygon(pts, true), Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke);
    for (final p in pts) {
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(QuadPainter old) => old.corners != corners || old.found != found;
}
