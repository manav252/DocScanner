// ScanEngine for the browser: talks to web/opencv/scanner_worker.js,
// which runs opencv.js (WASM) off the UI thread.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../core/crash_note.dart';

import '../scan_engine.dart';
import '../geometry.dart';
import '../page_edits.dart';

ScanEngine createScanEngine() => WebScanEngine();

/// The OpenCV worker, behind web/opencv/engine_bridge.js when the page loaded
/// it (on iPhone/iPad it decodes and encodes images on the page; same
/// interface as a Worker).
web.Worker _start(String url) {
  final bridge = web.window.getProperty<JSObject?>('DocScannerEngine'.toJS);
  if (bridge == null) return web.Worker(url.toJS);
  final w = bridge.callMethod<JSObject>('create'.toJS, url.toJS);
  noteEvent('image codec: ${w.getProperty<JSString>('codec'.toJS).toDart}');
  return w as web.Worker;
}

/// Changes every build (scripts/build_web.sh passes the git commit) so browsers
/// never run a cached worker from an older build.
const assetVersion = String.fromEnvironment('ASSET_VERSION', defaultValue: 'dev');

class WebScanEngine implements ScanEngine {
  WebScanEngine({String? workerUrl}) : _worker = _start(workerUrl ?? 'opencv/scanner_worker.js?v=$assetVersion') {
    _worker.onmessage = _onMessage.toJS;
    _worker.onerror = ((web.Event e) {
      if (!_ready.isCompleted) _ready.completeError(StateError('failed to start the OpenCV worker'));
    }).toJS;
  }

  final web.Worker _worker;
  final _ready = Completer<void>();
  final _pending = <int, Completer<JSObject>>{};
  final _notes = <int, int>{}; // call id -> crash note token
  var _nextId = 0;

  @override
  Future<void> get ready => _ready.future;

  void _onMessage(web.MessageEvent e) {
    final data = e.data! as JSObject;
    if (data.getProperty<JSString?>('type'.toJS)?.toDart == 'ready') {
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    final id = (data.getProperty<JSNumber>('id'.toJS)).toDartInt;
    final c = _pending.remove(id);
    final note = _notes.remove(id);
    if (note != null) noteDone(note);
    if (c == null) return;
    if (data.getProperty<JSBoolean>('ok'.toJS).toDart) {
      c.complete(data.getProperty<JSObject>('result'.toJS));
    } else {
      c.completeError(StateError(data.getProperty<JSString>('error'.toJS).toDart));
    }
  }

  Future<JSObject> _call(String type, Map<String, JSAny?> fields, [List<JSObject> transfer = const []]) {
    final id = _nextId++;
    final msg = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('type'.toJS, type.toJS);
    fields.forEach((k, v) => msg.setProperty(k.toJS, v));
    final c = _pending[id] = Completer<JSObject>();
    if (type != 'detectFrame') {
      // Image work that could exhaust an iPhone's memory: recorded (crash notes).
      final bytes = fields['bytes'];
      final kb = bytes != null && bytes.isA<JSArrayBuffer>()
          ? (bytes as JSArrayBuffer).toDart.lengthInBytes ~/ 1024
          : null;
      _notes[id] = noteStep('image work: $type${kb == null ? '' : ' ($kb KB)'}');
    }
    _worker.postMessage(msg, transfer.toJS);
    return c.future;
  }

  static Detection _toDetection(JSObject r) {
    final corners = (r.getProperty<JSArray<JSArray<JSNumber>>>('corners'.toJS)).toDart;
    return Detection(
      [for (final p in corners) Pt(p.toDart[0].toDartDouble, p.toDart[1].toDartDouble)],
      found: r.getProperty<JSBoolean>('found'.toJS).toDart,
      score: r.getProperty<JSNumber>('score'.toJS).toDartDouble,
    );
  }

  @override
  Future<Detection> detectFrame(FrameData f) async {
    if (f.format != PixelFormat.rgba || f.rowStride != f.width * 4) {
      throw ArgumentError('web frames must be dense RGBA (canvas ImageData)');
    }
    // Copy so the caller's buffer stays usable; the copy is transferred, not cloned.
    final copy = Uint8List.fromList(f.bytes).buffer.toJS;
    final image = JSObject()
      ..setProperty('data'.toJS, copy)
      ..setProperty('width'.toJS, f.width.toJS)
      ..setProperty('height'.toJS, f.height.toJS);
    return _toDetection(await _call('detect', {'image': image}, [copy]));
  }

  @override
  Future<EncodedDetection> detectEncoded(Uint8List bytes) async {
    final buf = Uint8List.fromList(bytes).buffer.toJS;
    final r = await _call('detectEncoded', {'bytes': buf}, [buf]);
    return (
      detection: _toDetection(r),
      width: r.getProperty<JSNumber>('width'.toJS).toDartInt,
      height: r.getProperty<JSNumber>('height'.toJS).toDartInt,
    );
  }

  @override
  Future<NormalizedImage> normalizeEncoded(Uint8List bytes, {int maxSide = 4000, int quality = 92}) async {
    final buf = Uint8List.fromList(bytes).buffer.toJS;
    final r = await _call(
      'normalizeEncoded',
      {'bytes': buf, 'maxSide': maxSide.toJS, 'quality': (quality / 100).toJS},
      [buf],
    );
    return (
      bytes: r.getProperty<JSArrayBuffer>('data'.toJS).toDart.asUint8List(),
      width: r.getProperty<JSNumber>('width'.toJS).toDartInt,
      height: r.getProperty<JSNumber>('height'.toJS).toDartInt,
    );
  }

  @override
  Future<Uint8List> warpEncoded(Uint8List bytes, List<Pt> corners, {int maxSide = 3000, int quality = 92}) async {
    final buf = Uint8List.fromList(bytes).buffer.toJS;
    final r = await _call(
      'warpEncoded',
      {
        'bytes': buf,
        'corners': [
          for (final p in corners) [p.x.toJS, p.y.toJS].toJS,
        ].toJS,
        'maxSide': maxSide.toJS,
        'quality': (quality / 100).toJS,
      },
      [buf],
    );
    return (r as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<Uint8List> processEncoded(Uint8List bytes, PageEdits edits, {int? maxSide, int quality = 90}) async {
    final buf = Uint8List.fromList(bytes).buffer.toJS;
    final r = await _call(
      'processEncoded',
      {'bytes': buf, 'edits': edits.toJson().jsify(), 'maxSide': maxSide?.toJS, 'quality': (quality / 100).toJS},
      [buf],
    );
    return (r as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  Future<Uint8List> prepareOcrEncoded(Uint8List bytes, {bool contrast = false, int quality = 92}) async {
    final buf = Uint8List.fromList(bytes).buffer.toJS;
    final r = await _call(
      'prepareOcr',
      {'bytes': buf, 'contrast': contrast.toJS, 'quality': (quality / 100).toJS},
      [buf],
    );
    return (r as JSArrayBuffer).toDart.asUint8List();
  }

  @override
  void dispose() {
    _worker.terminate();
    for (final c in _pending.values) {
      c.completeError(StateError('detector disposed'));
    }
    _pending.clear();
  }
}
