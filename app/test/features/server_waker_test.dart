// A sleeping free-tier backend: sign-in says "Waking up the server…", keeps
// retrying /health and then signs in, instead of showing an error.
import 'dart:async';

import 'package:docscanner/core/app_settings.dart';
import 'package:docscanner/core/providers.dart';
import 'package:docscanner/data/storage/key_value_store.dart';
import 'package:docscanner/data/sync/server_waker.dart';
import 'package:docscanner/features/account/account_page.dart';
import 'package:docscanner/services/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_app.dart';

const server = 'https://docscanner-api.onrender.com';

void main() {
  setUp(() {
    ServerWaker.maxWait = const Duration(seconds: 5);
    ServerWaker.retryEvery = const Duration(milliseconds: 50);
  });

  test('wake: retries /health until the server answers; waking in between', () async {
    var calls = 0;
    final c = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(() => AppSettingsNotifier(const AppSettings(serverUrl: server))),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            baseUrl: server,
            httpClient: MockClient(
              (_) async => ++calls < 3 ? http.Response('', 502) : http.Response('{"status":"ok"}', 200),
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final states = <ServerState>[];
    c.listen(serverWakerProvider, (_, s) => states.add(s), fireImmediately: true);
    expect(await c.read(serverWakerProvider.notifier).wake(), isTrue);
    expect(states, [ServerState.unknown, ServerState.waking, ServerState.up]);
    expect(calls, 3);
    expect(await c.read(serverWakerProvider.notifier).wake(), isTrue);
    expect(calls, 3, reason: 'awake: no more pings');
  });

  test('wake gives up after maxWait: unreachable', () async {
    ServerWaker.maxWait = const Duration(milliseconds: 120);
    final c = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(() => AppSettingsNotifier(const AppSettings(serverUrl: server))),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(baseUrl: server, httpClient: MockClient((_) async => throw http.ClientException('down'))),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(await c.read(serverWakerProvider.notifier).wake(), isFalse);
    expect(c.read(serverWakerProvider), ServerState.unreachable);
  });

  testWidgets('sign-in while the server wakes: message + spinner, then signed in', (tester) async {
    final awake = Completer<void>();
    final client = MockClient((req) async {
      if (req.url.path == '/health') {
        return awake.isCompleted ? http.Response('{"status":"ok"}', 200) : http.Response('', 503);
      }
      return http.Response('{"access_token":"a","refresh_token":"r","user":{"id":"u","email":"sam@example.com"}}', 200);
    });
    await tester.pumpWidget(
      testApp(
        const AccountPage(),
        overrides: [
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
          appSettingsProvider.overrideWith(() => AppSettingsNotifier(const AppSettings(serverUrl: server))),
          apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: server, httpClient: client)),
        ],
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('email')), 'sam@example.com');
    await tester.enterText(find.byKey(const ValueKey('password')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
    expect(find.text('Waking up the server, this can take up to a minute…'), findsOneWidget);
    expect(find.textContaining('Can’t reach the server'), findsNothing);

    awake.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // next retry (fake clock)
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Waking up the server, this can take up to a minute…'), findsNothing);
    expect(find.text('sam@example.com'), findsOneWidget, reason: 'signed in');
  });
}
