// Tesseract.js via web/ocr/ocr.js (window.DocScannerOcr).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ocr_result.dart';
import 'text_recognizer.dart';

TextRecognizer createTextRecognizer() => WebTextRecognizer();

class WebTextRecognizer implements TextRecognizer {
  JSObject? get _api => web.window.getProperty<JSObject?>('DocScannerOcr'.toJS);

  @override
  bool get isAvailable => _api != null;

  @override
  Future<OcrResult> recognize(Uint8List image, {String language = 'eng'}) async {
    final api = _api ?? (throw StateError('OCR script not loaded'));
    final promise = api.callMethod<JSPromise<JSObject>>('recognize'.toJS, image.toJS, language.toJS);
    final r = await promise.toDart;
    final lines = <OcrLine>[
      for (final l in r.getProperty<JSArray<JSObject>>('lines'.toJS).toDart)
        () {
          final box = l.getProperty<JSArray<JSNumber>>('box'.toJS).toDart.map((n) => n.toDartDouble).toList();
          return OcrLine(l.getProperty<JSString>('text'.toJS).toDart, box[0], box[1], box[2], box[3],
              confidence: l.getProperty<JSNumber>('confidence'.toJS).toDartDouble);
        }(),
    ];
    return OcrResult(r.getProperty<JSString>('text'.toJS).toDart, lines);
  }

  @override
  void dispose() {}
}
