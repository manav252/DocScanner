// Text view: "No text found", "Copy text" -> "Copied", failures with Try again.
import 'dart:io';

import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/features/editor/text_sheet.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/ocr/ocr_result.dart';
import 'package:docscanner/services/ocr/text_recognizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

class ScriptedRecognizer implements TextRecognizer {
  ScriptedRecognizer(this.result, {this.fail = false});
  OcrResult result;
  bool fail;
  @override
  bool get isAvailable => true;
  @override
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'}) async {
    if (fail) throw StateError('worker crashed');
    return result;
  }

  @override
  void dispose() {}
}

Future<MemoryStore> seed() async {
  final store = MemoryStore();
  final repo = DocumentRepository(store);
  final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();
  const p = ScanPage(
    id: 'p',
    sourceWidth: 1,
    sourceHeight: 1,
    corners: [Pt(0, 0), Pt(0, 0), Pt(0, 0), Pt(0, 0)],
    revision: 1,
    renderWidth: 1,
    renderHeight: 1,
  );
  for (final k in PageImage.values) {
    await repo.putPageImage('p', k, png);
  }
  await repo.save(
    ScanDocument(id: 'd', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [p]),
  );
  return store;
}

Future<void> open(WidgetTester tester, MemoryStore store, TextRecognizer r) async {
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => const Scaffold(
          body: TextSheet(documentId: 'd', pageId: 'p'),
        ),
      ),
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        scanEngineProvider.overrideWithValue(FakeEngine(frameDetector: (_) => noPage)),
        textRecognizerProvider.overrideWithValue(r),
      ],
    ),
  );
  // Keep the document controller alive like the editor does.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
}

void main() {
  testWidgets('photo without text: says so, Copy is disabled', (tester) async {
    final store = (await tester.runAsync(seed))!;
    await open(tester, store, ScriptedRecognizer(const OcrResult('l1 ~ |', [OcrLine('~ |', 0, 0, 1, 1)])));
    expect(find.text('No text found on this page'), findsOneWidget);
    final copy = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text('Copy text'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('recognised text can be copied; button confirms "Copied"', (tester) async {
    final store = (await tester.runAsync(seed))!;
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String;
      return null;
    });
    await open(tester, store, ScriptedRecognizer(const OcrResult('Invoice 42', [OcrLine('Invoice 42', 0, 0, 1, 1)])));
    expect(find.text('Invoice 42'), findsOneWidget);
    expect(find.byKey(const ValueKey('handwriting-note')), findsOneWidget);
    await tester.tap(find.text('Copy text'));
    await tester.pump();
    expect(clip, 'Invoice 42');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a failure explains what to do and offers Try again', (tester) async {
    final store = (await tester.runAsync(seed))!;
    final r = ScriptedRecognizer(const OcrResult('', []), fail: true);
    await open(tester, store, r);
    expect(find.textContaining('Text recognition failed: worker crashed'), findsOneWidget);
    r
      ..fail = false
      ..result = const OcrResult('Hello world', [OcrLine('Hello world', 0, 0, 1, 1)]);
    await tester.tap(find.text('Try again'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
    expect(find.text('Hello world'), findsOneWidget);
  });
}
