import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/document_controller.dart';
import 'package:docscanner/features/editor/ocr_runner.dart';
import 'package:docscanner/features/library/library_controller.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/imaging/page_edits.dart';
import 'package:docscanner/services/export/pdf_builder.dart';
import 'package:docscanner/services/ocr/ocr_result.dart';
import 'package:docscanner/services/ocr/text_recognizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../imaging/fixtures.dart';
import '../support/fakes.dart';

/// A page that reads well (readingScore above poorReadingScore).
const invoice = OcrResult(
  'INVOICE 42\nTotal 99.50\nPayment due within thirty days\nThank you for your business, Sharma Traders Private Limited, account 12345678',
  [
    OcrLine('INVOICE 42', 0.1, 0.1, 0.5, 0.05),
    OcrLine('Total 99.50', 0.1, 0.8, 0.3, 0.04),
    OcrLine('Payment due within thirty days', 0.1, 0.9, 0.6, 0.04),
    OcrLine('Thank you for your business, Sharma Traders Private Limited, account 12345678', 0.1, 0.95, 0.8, 0.03),
  ],
);

class FakeRecognizer implements TextRecognizer {
  int calls = 0;
  @override
  bool get isAvailable => true;
  final languages = <String>[];

  /// Results to return, in order (then [invoice]).
  final queue = <OcrResult>[];

  @override
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'}) async {
    calls++;
    languages.add(language);
    return queue.isNotEmpty ? queue.removeAt(0) : invoice;
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
    c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        scanEngineProvider.overrideWithValue(engine),
        textRecognizerProvider.overrideWithValue(recognizer),
        pageRendererProvider.overrideWith(
          (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (1000, 1400)),
        ),
      ],
    );
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
    expect(ps.every((p) => !p.needsOcr && p.ocrText == invoice.text), isTrue);
    final boxes = OcrResult.fromJson(
      jsonDecode(utf8.decode((await c.read(documentRepositoryProvider).pageOcr(ps.first.id))!)) as Map<String, dynamic>,
    );
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

  test('a sideways page (hardly a word read) is read turned and turned upright', () async {
    const garble = OcrResult('3 of\noff', [OcrLine('3 of', 0.1, 0.1, 0.2, 0.05), OcrLine('off', 0.1, 0.2, 0.2, 0.05)]);
    // Upright reading, its contrast retry, then a quarter turn (clear text), then three quarters.
    recognizer.queue.addAll([garble, garble, invoice, garble]);
    final first = (await pages()).first;
    await c.read(ocrRunnerProvider).run(id, pageIds: {first.id});
    final turned = (await pages()).first;
    expect(turned.edits.quarterTurns, 1);
    expect(turned.ocrText, invoice.text);
    expect(turned.needsOcr, isFalse, reason: 'the text belongs to the turned page');
    expect(recognizer.calls, 4);
  });

  test('a page that reads well is not tried turned', () async {
    await c.read(ocrRunnerProvider).run(id);
    expect(recognizer.calls, 2);
    expect((await pages()).every((p) => p.edits.quarterTurns == 0), isTrue);
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
      PdfPageInput(
        jpeg: jpg,
        width: 1200,
        height: 1600,
        lines: const [
          OcrLine('QUARTERLY REPORT', 0.1, 0.05, 0.6, 0.03),
          OcrLine('total – “quoted” 中', 0.1, 0.1, 0.6, 0.02),
        ],
      ),
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
    final r = cleanOcr(
      const OcrResult('', [
        OcrLine('|', 0, 0, 0.01, 0.1),
        OcrLine('QUARTERLY REPORT |', 0, 0, 1, 1),
        OcrLine('| invoice receipt', 0, 0, 1, 1),
        OcrLine('[ —— ]', 0, 0, 1, 1),
        OcrLine('Total: 42', 0, 0, 1, 1),
      ]),
    );
    expect(r.text, 'QUARTERLY REPORT\ninvoice receipt\nTotal: 42');
  });

  test('cleanOcr drops low-confidence lines and non-words; Hindi passes', () {
    final r = cleanOcr(
      const OcrResult('', [
        OcrLine('Invoice 42', 0, 0, 1, 1, confidence: 0.9),
        OcrLine('Rrnm qx', 0, 0, 1, 1, confidence: 0.2),
        OcrLine('~ | ;', 0, 0, 1, 1, confidence: 0.95),
        OcrLine('भारत एक विशाल देश है।', 0, 0, 1, 1, confidence: 0.94),
      ]),
    );
    expect(r.lines.map((l) => l.text), ['Invoice 42', 'भारत एक विशाल देश है।']);
    expect(meaningfulText('i'), isFalse);
    expect(meaningfulText('—— ——'), isFalse);
    expect(meaningfulText('दिनांक'), isTrue);
  });

  test('little text: read again from the contrast variant, keeping what either pass found', () async {
    final engine = c.read(scanEngineProvider) as FakeEngine;
    recognizer.queue.addAll([
      const OcrResult('DOB 01/02/1990', [OcrLine('DOB 01/02/1990', 0.3, 0.4, 0.3, 0.05)]),
      const OcrResult('Asha Verma\nDOB 01/02/1990', [
        OcrLine('Asha Verma', 0.3, 0.25, 0.3, 0.06),
        OcrLine('DOB 01/02/1990', 0.3, 0.4, 0.3, 0.05), // same place: not added twice
      ]),
      // Few words, so it is also read turned (each way, then upside down): nothing better.
      const OcrResult('', []),
      const OcrResult('', []),
      const OcrResult('', []),
    ]);
    expect(await c.read(ocrRunnerProvider).run(id, pageIds: {(await pages()).first.id}), 1);
    expect(engine.ocrPrepared, [
      false,
      true,
      false,
      false,
      false,
    ], reason: 'first pass, then grayscale + CLAHE, then turned');
    expect((await pages()).first.edits.quarterTurns, 0);
    expect((await pages()).first.ocrText, 'Asha Verma\nDOB 01/02/1990');
  });

  test('enough text: one pass only', () async {
    final engine = c.read(scanEngineProvider) as FakeEngine;
    await c.read(ocrRunnerProvider).run(id);
    expect(engine.ocrPrepared, [false, false]);
    expect(recognizer.calls, 2);
  });

  test('a page shown as Original is read from its shadow-corrected (Magic Color) version', () async {
    final engine = c.read(scanEngineProvider) as FakeEngine;
    final p = (await pages()).first;
    await c.read(documentProvider(id).notifier).setFilter(p.id, PageFilter.original);
    engine.processed.clear();
    await c.read(ocrRunnerProvider).run(id, pageIds: {p.id});
    expect(engine.processed.map((e) => e.filter), [PageFilter.magicColor]);
  });

  test('text recognition waits while the camera is open, and continues when it closes', () async {
    c.read(cameraActiveProvider.notifier).active = true;
    final run = c.read(ocrRunnerProvider).run(id);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(recognizer.calls, 0, reason: 'camera, detection and OCR never use memory at once');
    c.read(cameraActiveProvider.notifier).active = false;
    expect(await run, 2);
    expect(recognizer.calls, 2);
  });

  test('OCR uses the chosen language and re-reads pages after a language change', () async {
    expect(await c.read(ocrRunnerProvider).run(id), 2);
    expect(recognizer.languages, ['eng', 'eng']);
    final s = c.read(appSettingsProvider);
    await c.read(appSettingsProvider.notifier).update(s.copyWith(ocrLanguage: OcrLanguage.hindi));
    expect(await c.read(ocrRunnerProvider).run(id), 2, reason: 'text was read as English');
    expect(recognizer.languages.skip(2), ['hin', 'hin']);
    expect((await pages()).every((p) => p.ocrLanguage == 'hin'), isTrue);
  });

  test('searchable PDF keeps Hindi text when the Devanagari font is supplied', () async {
    final jpg = File('${fixturesDir.path}/tilted_paper.jpg').readAsBytesSync();
    final font = pw.Font.ttf(
      ByteData.sublistView(File('assets/fonts/NotoSansDevanagari-Regular.ttf').readAsBytesSync()),
    );
    final pdf = await buildPdf(
      [
        PdfPageInput(jpeg: jpg, width: 1200, height: 1600, lines: const [OcrLine('भारत देश', 0.1, 0.1, 0.5, 0.05)]),
      ],
      compress: false,
      devanagariFont: font,
    );
    final s = latin1.decode(pdf);
    expect(s, contains('NotoSansDevanagari'), reason: 'font embedded');
    expect(s, contains('/ToUnicode'), reason: 'text maps back to Unicode for search/copy');
    expect(pdfSafe('भारत देश', devanagari: true), 'भारत देश');
    expect(pdfSafe('भारत देश'), ' ', reason: 'without the font Hindi is left out');
    final out = File('build/test_hindi.pdf')..createSync(recursive: true);
    out.writeAsBytesSync(pdf); // inspected by tool/check_pdf_text.py
  });
}
