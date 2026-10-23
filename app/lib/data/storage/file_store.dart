// KeyValueStore backed by files: key "page/abc/source.jpg" -> <root>/page/abc/source.jpg.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'key_value_store.dart';

Future<KeyValueStore> openPlatformStore() async =>
    FileStore(Directory('${(await getApplicationDocumentsDirectory()).path}/docscanner'));

class FileStore implements KeyValueStore {
  FileStore(this.root);
  final Directory root;

  File _file(String key) {
    if (key.contains('..') || key.startsWith('/')) throw ArgumentError('bad key $key');
    return File('${root.path}/$key');
  }

  @override
  Future<Uint8List?> get(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> put(String key, Uint8List value) async {
    final f = _file(key);
    await f.parent.create(recursive: true);
    // Write-then-rename so a crash never leaves a half-written file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(value, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    for (final k in await keys(prefix)) {
      await delete(k);
    }
    // Remove now-empty directories for "dir/" prefixes.
    if (prefix.endsWith('/')) {
      final d = Directory('${root.path}/$prefix');
      if (await d.exists()) await d.delete(recursive: true);
    }
  }

  @override
  Future<int?> usageBytes() async {
    if (!await root.exists()) return 0;
    var n = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) n += await e.length();
    }
    return n;
  }

  @override
  Future<List<String>> keys(String prefix) async {
    if (!await root.exists()) return [];
    final out = <String>[];
    await for (final e in root.list(recursive: true)) {
      if (e is! File || e.path.endsWith('.tmp')) continue;
      final key = e.path.substring(root.path.length + 1).replaceAll(r'\', '/');
      if (key.startsWith(prefix)) out.add(key);
    }
    return out;
  }
}
