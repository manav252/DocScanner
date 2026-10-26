import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Terminates the Tesseract.js workers (web/ocr/ocr.js); the next
/// recognition starts them again (~1 s).
Future<void> releaseOcrEngine() async {
  final api = web.window.getProperty<JSObject?>('DocScannerOcr'.toJS);
  if (api == null || !api.has('release')) return;
  await api.callMethod<JSPromise<JSAny?>>('release'.toJS).toDart;
}
