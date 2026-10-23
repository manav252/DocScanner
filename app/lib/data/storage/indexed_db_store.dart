// KeyValueStore backed by IndexedDB (browser). Values are stored as Uint8Arrays.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'key_value_store.dart';

Future<KeyValueStore> openPlatformStore() => IndexedDbStore.open();

class IndexedDbStore implements KeyValueStore {
  IndexedDbStore._(this._db);
  final web.IDBDatabase _db;
  static const _store = 'kv';

  static Future<IndexedDbStore> open({String name = 'docscanner'}) async {
    final req = web.window.indexedDB.open(name, 1);
    req.onupgradeneeded = ((web.Event _) {
      final db = req.result! as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
    }).toJS;
    final db = await _await<web.IDBDatabase>(req);
    // Ask the browser not to evict our data under storage pressure (best effort).
    unawaited(web.window.navigator.storage.persist().toDart.catchError((Object _) => false.toJS));
    return IndexedDbStore._(db);
  }

  static Future<T> _await<T extends JSAny?>(web.IDBRequest req) {
    final c = Completer<T>();
    req.onsuccess = ((web.Event _) => c.complete(req.result as T)).toJS;
    req.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB: ${req.error?.message}'))).toJS;
    return c.future;
  }

  web.IDBObjectStore _os(String mode) => _db.transaction(_store.toJS, mode).objectStore(_store);

  static web.IDBKeyRange _range(String prefix) => web.IDBKeyRange.bound(prefix.toJS, '$prefix￿'.toJS);

  @override
  Future<Uint8List?> get(String key) async {
    final v = await _await<JSAny?>(_os('readonly').get(key.toJS));
    return v == null ? null : (v as JSUint8Array).toDart;
  }

  @override
  Future<void> put(String key, Uint8List value) => _await<JSAny?>(_os('readwrite').put(value.toJS, key.toJS));

  @override
  Future<void> delete(String key) => _await<JSAny?>(_os('readwrite').delete(key.toJS));

  @override
  Future<void> deletePrefix(String prefix) => _await<JSAny?>(_os('readwrite').delete(_range(prefix)));

  /// The browser's figure for this site (documents plus the offline copy of the app).
  @override
  Future<int?> usageBytes() async {
    try {
      final e = await web.window.navigator.storage.estimate().toDart;
      return e.usage;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final r = await _await<JSArray<JSString>>(_os('readonly').getAllKeys(_range(prefix)));
    return [for (final k in r.toDart) k.toDart];
  }
}
