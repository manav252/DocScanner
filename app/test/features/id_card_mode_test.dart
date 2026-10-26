// ID card mode end to end (without OCR engines or a server): recognition after
// OCR, card pages re-rendered for B&W/quality, and no upload before the user
// agrees.
import 'dart:convert';
import 'dart:typed_data';

import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/id_card.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/data/sync/sync_service.dart';
import 'package:docscanner/features/editor/document_controller.dart';
import 'package:docscanner/features/editor/ocr_runner.dart';
import 'package:docscanner/features/library/library_controller.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/api/api_client.dart';
import 'package:docscanner/services/ocr/ocr_result.dart';
import 'package:docscanner/services/ocr/text_recognizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

class CardRecognizer implements TextRecognizer {
  @override
  bool get isAvailable => true;
  @override
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'}) async =>
      const OcrResult('Government of India\nAsha Verma\nDOB: 18/06/1981\nFemale\n3026 9266 9721', [
        OcrLine('Government of India', 0.3, 0.05, 0.4, 0.06),
        OcrLine('Asha Verma', 0.3, 0.25, 0.3, 0.06),
        OcrLine('DOB: 18/06/1981', 0.3, 0.36, 0.3, 0.05),
        OcrLine('Female', 0.3, 0.45, 0.15, 0.05),
        OcrLine('3026 9266 9721', 0.24, 0.75, 0.5, 0.08),
      ]);
  @override
  void dispose() {}
}

/// A card (856 x 540) photographed in a 1000 x 1400 photo.
const cardCorners = [Pt(72, 430), Pt(928, 430), Pt(928, 970), Pt(72, 970)];

void main() {
  test('after OCR a card-shaped page is labelled, named and re-rendered as an ID card', () async {
    final engine = FakeEngine(frameDetector: (_) => noPage);
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryStore()),
        scanEngineProvider.overrideWithValue(engine),
        textRecognizerProvider.overrideWithValue(CardRecognizer()),
        pageRendererProvider.overrideWith(
          (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (856, 540)),
        ),
      ],
    );
    addTearDown(c.dispose);
    final doc = await c.read(libraryActionsProvider).createDocument();
    c.listen(documentProvider(doc.id), (_, _) {});
    await c.read(documentProvider(doc.id).notifier).addImage(Uint8List.fromList([1]), 1000, 1400, cardCorners);
    expect((await c.read(documentRepositoryProvider).get(doc.id))!.isIdCard, isTrue, reason: 'card shape alone');

    engine.processed.clear();
    await c.read(ocrRunnerProvider).run(doc.id);
    final d = (await c.read(documentRepositoryProvider).get(doc.id))!;
    expect(d.idCard, IdCardType.aadhaar);
    expect(d.title, startsWith('Aadhaar Card – '));
    expect(d.idFields, {'number': '3026 9266 9721', 'dob': '18/06/1981', 'name': 'Asha Verma'});
    expect(d.pages.single.edits.idCard, isTrue);
    expect(engine.processed.any((e) => e.idCard), isTrue, reason: 're-rendered as an ID card');

    // "Not an ID card": back to an ordinary document and name.
    await c.read(documentProvider(doc.id).notifier).setIdCard(IdCardType.none);
    final n = (await c.read(documentRepositoryProvider).get(doc.id))!;
    expect((n.isIdCard, n.pages.single.edits.idCard, n.title), (false, false, ScanDocument.defaultTitle(n.createdAt)));
  });

  test('sync uploads ordinary documents but an ID card only after the user agrees', () async {
    final store = MemoryStore();
    final repo = DocumentRepository(store);
    final uploaded = <String>{};
    final client = MockClient((req) async {
      if (req.method == 'GET') return http.Response(jsonEncode({'documents': [], 'cursor': 0}), 200);
      final parts = req.url.pathSegments;
      if (req.method == 'PUT' && parts.length == 2) {
        uploaded.add(parts[1]);
        return http.Response(jsonEncode({'id': parts[1], 'version': 1}), 200);
      }
      return http.Response('{}', 200); // page files
    });
    Future<ScanDocument> make(String id, List<Pt> corners) async {
      final page = ScanPage(id: 'p-$id', sourceWidth: 1000, sourceHeight: 1400, corners: corners);
      for (final k in [PageImage.source, PageImage.render, PageImage.thumb]) {
        await repo.putPageImage(page.id, k, Uint8List.fromList([1, 2, 3]));
      }
      final now = DateTime(2026, 10, 27);
      final d = ScanDocument(
        id: id,
        title: id,
        createdAt: now,
        updatedAt: now,
        pages: [page],
        revision: 1,
        backup: true,
      );
      await repo.save(d);
      return d;
    }

    await make('letter', fullBounds(1000, 1400));
    final card = await make('card', cardCorners);
    final sync = SyncService(
      api: ApiClient(
        baseUrl: 'http://api.test',
        httpClient: client,
        session: const Session(accessToken: 'a', refreshToken: 'r', userId: 'u', email: 'e@x.test'),
      ),
      repo: repo,
      store: store,
    );
    await sync.sync();
    expect(uploaded, {'letter'});
    await repo.save(card.edit(idBackupApproved: true));
    await sync.sync();
    expect(uploaded, {'letter', 'card'});
  });
}
