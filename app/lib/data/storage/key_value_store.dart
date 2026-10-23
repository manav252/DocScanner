// Minimal byte store used for both document metadata (JSON) and page images.
//   Android / iOS : files under the app's documents directory
//   Web           : IndexedDB (persists across reloads, works offline)
import 'dart:typed_data';

import 'unsupported_store.dart'
    if (dart.library.js_interop) 'indexed_db_store.dart'
    if (dart.library.io) 'file_store.dart';

abstract interface class KeyValueStore {
  /// The persistent store for this platform.
  static Future<KeyValueStore> open() => openPlatformStore();

  Future<Uint8List?> get(String key);
  Future<void> put(String key, Uint8List value);
  Future<void> delete(String key);

  /// Delete every key starting with [prefix].
  Future<void> deletePrefix(String prefix);

  /// Keys starting with [prefix].
  Future<List<String>> keys(String prefix);

  /// Bytes this app stores on the device, or null if the platform cannot tell.
  Future<int?> usageBytes();
}

/// In-memory store (tests).
class MemoryStore implements KeyValueStore {
  final data = <String, Uint8List>{};

  @override
  Future<Uint8List?> get(String key) async => data[key];

  @override
  Future<void> put(String key, Uint8List value) async => data[key] = Uint8List.fromList(value);

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deletePrefix(String prefix) async => data.removeWhere((k, _) => k.startsWith(prefix));

  @override
  Future<List<String>> keys(String prefix) async => [
    for (final k in data.keys)
      if (k.startsWith(prefix)) k,
  ];

  @override
  Future<int?> usageBytes() async => data.values.fold<int>(0, (n, v) => n + v.length);
}
