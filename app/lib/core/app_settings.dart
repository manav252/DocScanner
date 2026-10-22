// Persisted user settings (server URL, server-side processing) and the session.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import '../services/api/api_client.dart';
import 'providers.dart';

class AppSettings {
  const AppSettings({required this.serverUrl, this.processOnServer = false, this.autoOcr = true});

  final String serverUrl;

  /// Run photo detection/warping/filters on the server instead of the device.
  final bool processOnServer;

  /// Recognise text in new pages automatically (searchable PDFs, search, copy).
  final bool autoOcr;

  /// Default backend: same host as the web app on port 8000, else localhost
  /// (Android emulators reach the host machine at 10.0.2.2).
  static String defaultServerUrl() {
    if (kIsWeb) return '${Uri.base.scheme}://${Uri.base.host}:8000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  AppSettings copyWith({String? serverUrl, bool? processOnServer, bool? autoOcr}) => AppSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        processOnServer: processOnServer ?? this.processOnServer,
        autoOcr: autoOcr ?? this.autoOcr,
      );

  Map<String, Object> toJson() => {'serverUrl': serverUrl, 'processOnServer': processOnServer, 'autoOcr': autoOcr};
  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        serverUrl: j['serverUrl'] as String? ?? defaultServerUrl(),
        processOnServer: j['processOnServer'] as bool? ?? false,
        autoOcr: j['autoOcr'] as bool? ?? true,
      );
}

const _settingsKey = 'app/settings.json';
const _sessionKey = 'app/session.json';

Future<Map<String, dynamic>?> _readJson(KeyValueStore s, String key) async {
  final b = await s.get(key);
  return b == null ? null : jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
}

Future<void> _writeJson(KeyValueStore s, String key, Object? value) async => value == null
    ? s.delete(key)
    : s.put(key, Uint8List.fromList(utf8.encode(jsonEncode(value))));

/// Loaded in main() before the app starts.
Future<(AppSettings, Session?)> loadSettingsAndSession(KeyValueStore store) async {
  final settings = await _readJson(store, _settingsKey);
  final session = await _readJson(store, _sessionKey);
  return (
    settings == null ? AppSettings(serverUrl: AppSettings.defaultServerUrl()) : AppSettings.fromJson(settings),
    session == null ? null : Session.fromJson(session),
  );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  AppSettingsNotifier([this._initial]);
  final AppSettings? _initial;

  @override
  AppSettings build() => _initial ?? AppSettings(serverUrl: AppSettings.defaultServerUrl());

  Future<void> update(AppSettings s) async {
    state = s;
    await _writeJson(ref.read(keyValueStoreProvider), _settingsKey, s.toJson());
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);

/// The signed-in user, or null. Tokens are stored in the app's local storage.
class SessionNotifier extends Notifier<Session?> {
  SessionNotifier([this._initial]);
  final Session? _initial;

  @override
  Session? build() => _initial;

  Future<void> set(Session? s) async {
    state = s;
    await _writeJson(ref.read(keyValueStoreProvider), _sessionKey, s?.toJson());
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

/// API client for the configured server, carrying the current session.
final apiClientProvider = Provider<ApiClient>((ref) {
  final url = ref.watch(appSettingsProvider.select((s) => s.serverUrl));
  final client = ApiClient(
    baseUrl: url,
    session: ref.read(sessionProvider),
    onSessionChanged: (s) => ref.read(sessionProvider.notifier).set(s),
  );
  ref.listen(sessionProvider, (_, s) => client.session = s);
  ref.onDispose(client.close);
  return client;
});
