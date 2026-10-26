// Things going wrong, and plain navigation: server unreachable or refusing,
// files that are not photos, backup offline, moving between screens.
import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/document_repository.dart';
import 'package:docscanner/data/models.dart';
import 'package:docscanner/data/page_renderer.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/data/sync/server_waker.dart';
import 'package:docscanner/features/account/account_page.dart';
import 'package:docscanner/features/editor/document_editor_page.dart';
import 'package:docscanner/features/home/home_page.dart';
import 'package:docscanner/features/library/documents_page.dart';
import 'package:docscanner/imaging/geometry.dart';
import 'package:docscanner/services/api/api_client.dart';
import 'package:docscanner/services/import/import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../imaging/fixtures.dart';
import '../support/fakes.dart';
import '../support/test_app.dart';

final png = File('${fixturesDir.path}/filters/input.png').readAsBytesSync();
const server = 'http://192.168.1.20:8000';

class BrokenFileImporter extends ImportService {
  @override
  Future<List<ImportedFile>> pickImages() async => [ImportedFile('holiday.txt', Uint8List.fromList('hello'.codeUnits))];
}

List<Override> base(MemoryStore store, FakeEngine engine, {http.Client? http, Session? session}) => [
  keyValueStoreProvider.overrideWithValue(store),
  scanEngineProvider.overrideWithValue(engine),
  appSettingsProvider.overrideWith(() => AppSettingsNotifier(const AppSettings(serverUrl: server))),
  pageRendererProvider.overrideWith(
    (ref) => PageRenderer(engine, ref.watch(documentRepositoryProvider), measure: (_) async => (583, 800)),
  ),
  if (session != null) sessionProvider.overrideWith(() => SessionNotifier(session)),
  if (http != null)
    apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: server, httpClient: http, session: session)),
];

Future<void> settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}

Future<MemoryStore> seedOne() async {
  final store = MemoryStore();
  final repo = DocumentRepository(store);
  final p = ScanPage(
    id: 'p',
    sourceWidth: 583,
    sourceHeight: 800,
    corners: fullBounds(583, 800),
    renderWidth: 583,
    renderHeight: 800,
    revision: 1,
  );
  for (final k in PageImage.values) {
    await repo.putPageImage('p', k, png);
  }
  await repo.save(
    ScanDocument(id: 'd', title: 'Electricity bill', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: [p]),
  );
  return store;
}

void main() {
  // No real waiting for a "sleeping" server in these tests.
  setUp(() {
    ServerWaker.maxWait = Duration.zero;
    ServerWaker.retryEvery = Duration.zero;
  });

  FakeEngine engine() => FakeEngine(frameDetector: (_) => noPage);

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('email')), 'sam@example.com');
    await tester.enterText(find.byKey(const ValueKey('password')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await settle(tester);
  }

  testWidgets('sign-in with the server down: says it cannot reach the server; the app keeps working', (tester) async {
    final client = MockClient((_) async => throw http.ClientException('Connection refused'));
    await tester.pumpWidget(testApp(const AccountPage(), overrides: base(MemoryStore(), engine(), http: client)));
    await settle(tester);
    await signIn(tester);
    expect(find.textContaining("Can’t reach the server at $server"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('test-connection')));
    await settle(tester);
    expect(find.text('Can’t reach the server. Check the address and that the backend is running.'), findsOneWidget);
  });

  testWidgets('sign-in refused (401) and server error (500): clear messages', (tester) async {
    var status = 401;
    final client = MockClient(
      (req) async => req.url.path == '/health'
          ? http.Response('{"status":"ok"}', 200)
          : http.Response('{"detail":"Internal error"}', status),
    );
    await tester.pumpWidget(testApp(const AccountPage(), overrides: base(MemoryStore(), engine(), http: client)));
    await settle(tester);
    await signIn(tester);
    expect(find.text('Wrong email or password.'), findsOneWidget);
    status = 500;
    await signIn(tester);
    expect(find.text('Wrong email or password.'), findsNothing);
    expect(find.textContaining('Internal error'), findsOneWidget);
  });

  testWidgets('importing a file that is not a photo: names it, creates no empty document', (tester) async {
    final store = MemoryStore();
    final e = engine()..unreadable = (_) => true;
    await tester.pumpWidget(
      testApp(
        const HomePage(),
        overrides: [...base(store, e), importServiceProvider.overrideWithValue(BrokenFileImporter())],
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Import Photos'));
    await settle(tester, 10);
    await tester.pumpAndSettle();
    expect(
      find.text('These files could not be opened and were skipped: holiday.txt (damaged or unsupported file)'),
      findsOneWidget,
    );
    expect(find.byType(DocumentEditorPage), findsNothing);
    expect(await tester.runAsync(() => DocumentRepository(store).list()), isEmpty);
  });

  testWidgets('signed in but the backup server is offline: says scans are safe on this device', (tester) async {
    final store = (await tester.runAsync(seedOne))!;
    const session = Session(accessToken: 'a', refreshToken: 'r', userId: 'u', email: 'sam@example.com');
    final client = MockClient((_) async => throw http.ClientException('Network is unreachable'));
    await tester.pumpWidget(
      testApp(
        const HomePage(),
        overrides: base(store, engine(), http: client, session: session),
      ),
    );
    await settle(tester, 12);
    expect(find.textContaining('Backup server not reachable'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget, reason: 'local documents still listed');
  });

  testWidgets('navigation: Home → Documents → a document → back to Home', (tester) async {
    final store = (await tester.runAsync(seedOne))!;
    await tester.pumpWidget(testApp(const HomePage(), overrides: base(store, engine())));
    await settle(tester);
    await tester.tap(find.text('View Documents'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(DocumentsPage), findsOneWidget);
    await tester.tap(find.text('Electricity bill'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEditorPage), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DocumentsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Scan Document'), findsOneWidget);
  });
}
