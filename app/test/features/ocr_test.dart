import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/document_controller.dart';
import 'package:docscanner/features/editor/ocr_runner.dart';
import 'package:docscanner/features/library/library_controller.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/export/pdf_builder.dart';
import 'package:docscanner/services/ocr/ocr_result.dart';
import 'package:docscanner/services/ocr/text_recognizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';

class FakeRecognizer implements TextRecognizer {
  int calls = 0;
  @override
  bool get isAvailable => true;
  @override
  Future<OcrResult> recognize(Uint8List image) async {
    calls++;
    return const OcrResult('INVOICE 42\nTotal 99.50', [
      OcrLine('INVOICE 42', 0.1, 0.1, 0.5, 0.05),
      OcrLine('Total 99.50', 0.1, 0.8, 0.3, 0.04),
    ]);
  }

  @override
  void dispose() {}
}

void main() {
  late ProviderContainer c;
  late FakeRecognizer recognizer;
  late MemoryStore store;
  late String id;

  setUp(() async {
    recognizer = FakeRecognizer();
    store = MemoryStore();
    final engine = FakeEngine(frameDetector: (_) => noPage);
    c = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      scanEngineProvider.overrideWithValue(engine),
      textRecognizerProvider.overrideWithValue(recognizer),
      pageRendererProvider.overrideWith(
        (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (1000, 1400)),
      ),
    ]);
    addTearDown(c.dispose);
    id = (await c.read(libraryActionsProvider).createDocument(title: 'Bills')).id;
    c.listen(documentProvider(id), (_, _) {});
    final ctrl = c.read(documentProvider(id).notifier);
    for (var i = 0; i < 2; i++) {
      await ctrl.addImage(Uint8List.fromList([i]), 1000, 1400, fullBounds(1000, 1400));
    }
  });

  Future<List<dynamic>> pages() async => (await c.read(documentRepositoryProvider).get(id))!.pages;

  test('OCR runs for stale pages only and stores text + line boxes', () async {
    expect((await pages()).every((p) => p.needsOcr), isTrue);
    expect(await c.read(ocrRunnerProvider).run(id), 2);
    final ps = await pages();
    expect(ps.every((p) => !p.needsOcr && p.ocrText == 'INVOICE 42\nTotal 99.50'), isTrue);
    final boxes = OcrResult.fromJson(
        jsonDecode(utf8.decode((await c.read(documentRepositoryProvider).pageOcr(ps.first.id))!)) as Map<String, dynamic>);
    expect(boxes.lines.first.text, 'INVOICE 42');
    expect(await c.read(ocrRunnerProvider).run(id), 0, reason: 'nothing stale');
    expect(recognizer.calls, 2);
  });

  test('editing a page makes its text stale; only that page is re-read', () async {
    await c.read(ocrRunnerProvider).run(id);
    final first = (await pages()).first;
    await c.read(documentProvider(id).notifier).rotate(first.id);
    expect((await pages()).first.needsOcr, isTrue);
    expect(await c.read(ocrRunnerProvider).run(id), 1);
  });

  test('OCR for an outdated revision is ignored', () async {
    final p = (await pages()).first;
    await c.read(documentProvider(id).notifier).setOcr(p.id, p.revision - 1, const OcrResult('old', []));
    expect((await pages()).first.ocrText, isNull);
  });

  test('library search finds words inside pages', () async {
    await c.read(ocrRunnerProvider).run(id);
    final sub = c.listen(libraryProvider, (_, _) {});
    addTearDown(sub.close);
    c.read(libraryQueryProvider.notifier).set('invoice 42');
    expect((await c.read(libraryProvider.future)).map((d) => d.title), ['Bills']);
  });

  test('searchable PDF: invisible text placed over the image', () async {
    final jpg = File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync();
    final pdf = await buildPdf([
      PdfPageInput(jpeg: jpg, width: 1200, height: 1600, lines: const [
        OcrLine('QUARTERLY REPORT', 0.1, 0.05, 0.6, 0.03),
        OcrLine('total – “quoted” 中', 0.1, 0.1, 0.6, 0.02),
      ]),
    ], compress: false);
    final s = latin1.decode(pdf);
    expect(s, contains('3 Tr'), reason: 'text rendering mode 3 = invisible');
    // Words are separate text runs; viewers join them by position.
    expect(s, contains('(QUARTERLY)'));
    expect(s, contains('(REPORT)'));
    expect(s, contains('("quoted")'), reason: 'typography mapped to ASCII');
    expect(s, isNot(contains('\u4e2d')), reason: 'CJK dropped (no Unicode font)');
  });

  test('pdfSafe', () {
    expect(pdfSafe('Café ‘ok’ … \u{1F600}'), "Café 'ok' ... ");
  });

  test('cleanOcr strips border junk and empty lines', () {
    final r = cleanOcr(const OcrResult('', [
      OcrLine('|', 0, 0, 0.01, 0.1),
      OcrLine('QUARTERLY REPORT |', 0, 0, 1, 1),
      OcrLine('| invoice receipt', 0, 0, 1, 1),
      OcrLine('[ —— ]', 0, 0, 1, 1),
      OcrLine('Total: 42', 0, 0, 1, 1),
    ]));
    expect(r.text, 'QUARTERLY REPORT\ninvoice receipt\nTotal: 42');
  });
}
